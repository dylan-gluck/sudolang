# liquid-snipe — SPEC

Companion to `PROJECT.md`. PROJECT defines *what* and *why*; this defines
*how*.

This is a **clean-room implementation** in a new Rust crate sibling to
`liquid-snipe/`. Directory: `liquid-snipe-rs/`. Workspace binary:
`liquid-snipe`. The POC's research informs the design; no POC code is
reused or imported at runtime.

## 1. Architecture

### 1.1 The hot loop

There is **one runtime loop**. Every other concern is either a background
task that feeds it cached values, or a worker task it spawns to absorb
tx-submit latency. This is the shape proven by
`reference/Solana-Sniper-Bot/src/processor/sniper_bot.rs:464–489`.

```
┌─────────────────────────────────────────────────────────────────────────┐
│  HOT LOOP  (one tokio task, blocks only on stream.next().await)        │
│                                                                         │
│  loop {                                                                 │
│    let raw = stream.next().await;                                       │
│    let evt = decode(raw);                         // ~µs, in-process    │
│    persist_async(evt);                            // crossbeam send     │
│                                                                         │
│    if let Some(pos) = open_positions.get(&evt.mint) {                   │
│      pos.apply(&evt);                             // price from evt     │
│      if let Some(action) = strategy.evaluate_exits(pos, &evt) {         │
│        tokio::spawn(execute_sell(pos, action));   // off hot path       │
│      }                                                                  │
│    }                                                                    │
│                                                                         │
│    if evt.is_entry_candidate() {                                        │
│      let dec = strategy.evaluate_buy(&evt, &enrich, &risk);             │
│      if let Some(plan) = dec.fired() {                                  │
│        tokio::spawn(execute_buy(plan));           // off hot path       │
│      }                                                                  │
│    }                                                                    │
│  }                                                                      │
└─────────────────────────────────────────────────────────────────────────┘
                       ▲                                       │
                       │                                       ▼
        ┌──────────────┴──────────┐               ┌────────────────────────┐
        │ Source (hot-swappable)  │               │ tokio::spawn workers   │
        │  - Yellowstone gRPC     │               │  - execute_buy()       │
        │  - Helius WS fallback   │               │  - execute_sell()      │
        │  - JSONL replay         │               │ build → blockhash inject│
        │ One sub: 8 program IDs  │               │  → SWQOS submit         │
        └─────────────────────────┘               └────────────────────────┘
                       ▲
                       │ background tasks (don't block the hot loop)
                       │
   ┌─────────────┬─────┴──────────┬──────────────┬─────────────┬──────────┐
   │ blockhash   │ enrichment     │ housekeeping │ persistence │ heartbeat│
   │ refresher   │ prefetcher     │ (cleanup,    │ writer      │ (X3,X7   │
   │ (poll Nms)  │ (mint+holders, │  expire      │ (drain WAL  │  fallback│
   │             │  deployer hist)│  enrich)     │  → DuckDB)  │  every   │
   │             │  LRU + TTL     │              │             │  Nms)    │
   └─────────────┴────────────────┴──────────────┴─────────────┴──────────┘
                                            │
                                            ▼
                              ┌───────────────────────────┐
                              │ slippage controller       │
                              │ (consecutive-failure       │
                              │  counter; bumps global    │
                              │  bps; resets on success)  │
                              └───────────────────────────┘
                                            │
                                            ▼
                              ┌───────────────────────────┐
                              │ config reloader            │
                              │ (SIGHUP → re-read TOML →   │
                              │ swap gRPC source / SWQOS / │
                              │ strategy for new positions)│
                              └───────────────────────────┘
```

### 1.2 What's NOT on the hot path

| concern | where | why |
|---|---|---|
| `getAccountInfo` for mint authorities | enrichment task | RPC RTT |
| `getTokenLargestAccounts` for LP burn / top-10 | enrichment task | RPC RTT |
| `getSignaturesForAddress` for deployer history | enrichment task | RPC RTT |
| `getLatestBlockhash` | blockhash refresher (interval configurable) | RPC RTT |
| `getBalance` for wallet | own task on `[wallet].balance_refresh_ms` cadence (default 1 s); cached as `AtomicU64`. Also refreshed eagerly on every fill confirmation. | RPC RTT |
| Tx build + sign + submit | `execute_buy` / `execute_sell` workers | RPC + SWQOS RTT |
| DuckDB writes | persistence task draining a `crossbeam::channel` | append latency |
| Wall-clock sell triggers (time, decay fallback) | heartbeat task | event-driven covers the rest |

**Caching contract.** The hot loop reads only from in-memory state:
`open_positions: DashMap`, `enrich_cache: DashMap`, `blockhash:
ArcSwap<Hash>`, `wallet_balance: AtomicU64`, `daily_pnl: AtomicI64`,
`slippage_bps: AtomicU16`. Cache miss on enrichment for a strategy that
requires the field → reject candidate with reason `enrichment-pending`,
kick off enrichment for next time.

### 1.3 Subscriptions

One Yellowstone gRPC subscription, `commitment = Processed`:

```rust
SubscribeRequestFilterTransactions {
    vote: Some(false),
    failed: Some(false),
    account_required: vec![],
    account_include: vec![/* DEX program ids from active config */],
    account_exclude: vec![],
    signature: None,
}
```

This single filter delivers entry candidates AND price updates on every
mint trading on those programs. Membership in `open_positions` is the
inline check that decides whether a buy/sell tx triggers an exit eval.

**Hot-swap.** SIGHUP-triggered reload re-reads the config; if the gRPC
endpoint or `[dexes].enabled` changed, the source task drops the current
stream and reopens with the new params. In-flight events drain naturally.

**Fallback.** Helius `logsNotifications` per program when gRPC is
unavailable. Logs alone don't carry reserves, so on the WS path we pay one
`getTransaction` per candidate. Acceptable as degraded mode, not the
default.

### 1.4 Async model

- One Tokio multi-thread runtime.
- One **hot task** owns the stream and inline decode/decide.
- One **executor pool**: `tokio::spawn(execute_*)`, bounded by a `Semaphore`
  (default 8; configurable).
- Background tasks (blockhash, enrichment, housekeeping, persistence,
  heartbeat, slippage controller, config reloader) run independently.
- **No per-position task.**
- Shutdown: single `CancellationToken` → drop the stream, drain workers,
  flush persistence, exit. 30 s budget; force after.

### 1.5 Processed → Confirmed reconciliation

Hot loop acts on `Processed` events. A separate `confirmation_audit` task
re-checks every fill at `Confirmed` after `[confirmation_audit].delay_ms`
(default 7 s) post-submit.

**Per fill, the audit task issues `getTransaction(sig, commitment=Confirmed)`
with retry policy:**

| attempt | wait before | meaning |
|---|---|---|
| 1 | (initial) | first try |
| 2 | 1 s | retry after transient RPC error or `null` response |
| 3 | 2 s | retry |
| 4 | 4 s | last try |

A "transient" outcome that triggers retry:
- RPC transport error (timeout, 429, 5xx).
- `null` response *and* the tx age is still inside the
  finality grace window (current slot − fill.submit_slot < 32). After 32
  slots, `null` is treated as authoritative "missing".

**On RPC exhaustion (all 4 attempts fail with transport errors):**
- `fills.confirmed_at_ns := NULL`
- `fills.error := "audit-rpc-failure"`
- log `warn` with the tx signature and last error
- **do not mutate position state.** Outcome is unknown; the on-chain tx may
  have landed. Operator inspects via `liquid-snipe replay <sig>`.

**On authoritative outcome:**

- **Fill confirmed (tx returned, status=Ok)**: mark `fills.confirmed_at_ns`.
- **Fill landed but reverted (status=Err)**: as below.
- **Fill missing after grace window (null past slot+32)**: as below.
  - if it was a buy: position's `state := failed_reverted`, no sell needed
    (no tokens were actually transferred).
  - if it was a partial sell: roll back `realised_frac` and `realised_sol`;
    re-evaluate exit triggers on next event.
  - if it was a final sell: position is reopened with the previous version's
    state.
- **Position acted on a reverted price update** (rare): on the next
  `Confirmed` event for the mint, recompute peak and apply / no-op.

## 2. Frame budget

A "frame" = one inbound chain update.

| step | budget (p99) | what runs |
|---|---|---|
| stream.next().await wakeup | ~50 µs | tokio + gRPC client |
| decode tx → ChainEvent | <100 µs | borsh / log parse |
| open_positions lookup | <1 µs | DashMap |
| `pos.apply(&evt) + evaluate_exits` | <50 µs | pure compute |
| `strategy.evaluate_buy` | <50 µs | pure compute |
| `tokio::spawn(execute_*)` | <10 µs | task spawn |
| **frame total** | **<500 µs** | |
| (off-frame) execute_buy → submitted | p50 <250 ms, p99 <1 s | hits N1 |

## 3. Data model (DuckDB)

DuckDB chosen per `CLAUDE.md`. Append-only.

```sql
CREATE TABLE chain_events (
    slot                 BIGINT      NOT NULL,
    received_at_ns       BIGINT      NOT NULL,
    block_time           BIGINT,
    dex_key              VARCHAR     NOT NULL,
    program_id           VARCHAR     NOT NULL,
    event_kind           VARCHAR     NOT NULL,    -- INIT|CREATE|MIGRATE|DEPOSIT|BUY|SELL
    tx_signature         VARCHAR     NOT NULL PRIMARY KEY,
    signer               VARCHAR,
    base_mint            VARCHAR,
    quote_mint           VARCHAR,
    pool                 VARCHAR,
    sol_value            DOUBLE,
    base_reserve         DOUBLE,
    quote_reserve        DOUBLE,
    price_quote_per_base DOUBLE,
    confirmed            BOOLEAN     DEFAULT FALSE   -- set by confirmation_audit task
);
CREATE INDEX chain_events_mint_idx ON chain_events(base_mint);

CREATE TABLE signal_decisions (
    tx_signature        VARCHAR   NOT NULL,
    decided_at_ns       BIGINT    NOT NULL,
    ok                  BOOLEAN   NOT NULL,
    filters_passed      JSON      NOT NULL,    -- which filters fired
    filters_failed      JSON      NOT NULL,    -- which rejected, with reason
    risk_reason         VARCHAR,                -- non-null if risk engine rejected
    PRIMARY KEY (tx_signature)
);

CREATE TABLE mint_enrichment (
    mint                       VARCHAR PRIMARY KEY,
    fetched_at                 TIMESTAMP NOT NULL,
    decimals                   INTEGER,
    supply                     DOUBLE,
    mint_authority             VARCHAR,
    freeze_authority           VARCHAR,
    top10_concentration        DOUBLE,
    holder_count               INTEGER,
    lp_burned_or_locked        BOOLEAN,
    deployer                   VARCHAR,
    deployer_prior_launches    INTEGER,
    notes                      JSON
);

CREATE TABLE positions (
    position_id        UUID       NOT NULL,
    version            INTEGER    NOT NULL,
    mode               VARCHAR    NOT NULL,             -- live | paper
    state              VARCHAR    NOT NULL,             -- opening | open | closing | closed | failed | failed_reverted
    mint               VARCHAR    NOT NULL,
    dex_key            VARCHAR    NOT NULL,
    pool               VARCHAR    NOT NULL,
    pool_signature     VARCHAR    NOT NULL,             -- entry-trigger tx
    entry_slot         BIGINT     NOT NULL,
    entry_at           TIMESTAMP  NOT NULL,
    entry_price        DOUBLE     NOT NULL,
    entry_sol_size     DOUBLE     NOT NULL,
    baseline_quote_reserve DOUBLE NOT NULL,
    token_amount_open  DOUBLE     NOT NULL,
    peak_price         DOUBLE     NOT NULL,
    realised_frac      DOUBLE     NOT NULL,
    realised_sol       DOUBLE     NOT NULL,
    pnl_sol            DOUBLE,
    pnl_pct            DOUBLE,
    exit_reason        VARCHAR,
    closed_at          TIMESTAMP,
    updated_at         TIMESTAMP  NOT NULL,
    PRIMARY KEY (position_id, version)
);
CREATE INDEX positions_state_idx    ON positions(state);
CREATE INDEX positions_mint_idx     ON positions(mint);

CREATE TABLE fills (
    fill_id           UUID       PRIMARY KEY,
    position_id       UUID       NOT NULL,
    side              VARCHAR    NOT NULL,              -- buy | sell
    reason            VARCHAR    NOT NULL,              -- entry|hard_stop|ladder|trailing_stop|liquidity_drain|insider_sell|decay|time_stop|shutdown
    requested_at_ns   BIGINT     NOT NULL,
    submitted_at_ns   BIGINT,
    confirmed_at_ns   BIGINT,
    tx_signature      VARCHAR,
    fraction_of_pos   DOUBLE     NOT NULL,
    tokens            DOUBLE     NOT NULL,
    quote_filled      DOUBLE     NOT NULL,
    fee_sol           DOUBLE     NOT NULL,
    slippage_bps      INTEGER,
    swqos_provider    VARCHAR,
    error             VARCHAR
);

CREATE TABLE blocklist (
    address    VARCHAR PRIMARY KEY,
    reason     VARCHAR,
    added_at   TIMESTAMP NOT NULL
);

-- Views
CREATE VIEW open_positions AS
SELECT * FROM positions p
WHERE version = (SELECT MAX(version) FROM positions WHERE position_id = p.position_id)
  AND state IN ('opening','open','closing');

CREATE VIEW daily_pnl AS
SELECT SUM(pnl_sol) FILTER (WHERE state='closed' AND closed_at >= today()) AS realised_today
FROM positions;
```

## 4. Exit detection

### 4.1 Two clocks

1. **Event clock (primary).** Every BUY/SELL on a mint we own runs through
   the hot loop. `pos.apply(&evt)` updates price/peak/reserves; then each
   SellTrigger is evaluated in priority order; first to fire wins.
2. **Wall-clock heartbeat (safety net).** Configurable interval (default
   100 ms). Iterates `open_positions`; fires only `time_stop` and `decay`
   when N samples haven't arrived event-driven.

### 4.2 Concurrent-fill semantics

- When a sell tx is dispatched, the position is marked `state := closing` in
  memory and a `pending_sell: AtomicBool` is set. Subsequent triggers of
  *equal-or-lower* priority are ignored until the pending tx resolves.
- A *higher-priority* trigger preempts: a new sell tx is dispatched **with a
  higher compute-unit price** (multiplier in config) so it lands first.
  Solana doesn't truly cancel txs, so racing-with-fee is the only mechanism.
- On `Confirmed` for the prior tx: advance `realised_frac` / `realised_sol`,
  clear `pending_sell`, re-evaluate exits.
- On `Confirmed` failure: clear `pending_sell`, re-evaluate.

### 4.3 Slot-level price collisions

`pos.apply(&evt)` records `(slot, signature)` of the latest applied event.
A later-arriving event with `evt.slot < last_applied.slot` is dropped (out
of order). Same slot with different signature: applied if `slot, signature`
hash sorts after the last (deterministic tiebreak).

### 4.4 Insider set construction

The `insider_sell` SellTrigger needs a per-position set of addresses that
count as "insiders". The set is captured **once at entry** (frozen for the
lifetime of the position) so the hot path checks `signer ∈ set` in O(1)
without RPC.

**Insider set =**

1. `pool_event.signer` — the address that submitted the
   INIT/CREATE/MIGRATE/DEPOSIT tx that triggered the entry.
2. The deployer (`mint_enrichment.deployer`) if different from #1.
3. Top-N initial holders captured during the entry-burst enrichment:
   - **N** = `[strategy.buy_trigger].insider_capture_top_n` (default 5)
   - **min holding** = `[strategy.buy_trigger].insider_capture_min_pct`
     fraction of supply (default 0.01 = 1 %)
   - source = `getTokenLargestAccounts` snapshot taken at entry slot;
     accounts holding < min_pct of supply are excluded
   - addresses owned by the pool itself, the bot's own ATA, and the WSOL
     mint are filtered out

The set lives on the in-memory `Position` as `insider_set: HashSet<Pubkey>`
(typically ≤ 7 entries). It is **also persisted** as a JSON array in the
`positions.notes` column at v1 of each position so that `replay` and audits
can reconstruct it.

**Trigger evaluation** (hot path, on every BUY/SELL event for the mint):

```rust
if matches!(evt.event_kind, SELL)
   && pos.insider_set.contains(&evt.signer)
   && (evt.tokens_sold / enrich.supply) >= trigger.insider_pct {
    fire(SellReason::InsiderSell);
}
```

If the entry-burst enrichment for the largest-accounts query times out, the
position falls back to set = {signer, deployer} only and the timeout is
logged. The bot does not block the entry on the largest-accounts query —
the BuyTrigger has its own enrichment dependencies (see
`[strategy.buy_trigger].enrichment_timeout_ms`); this snapshot runs in
parallel.

## 5. Crate / module inventory

```
liquid-snipe-rs/                  # sibling to liquid-snipe/
  Cargo.toml                      # workspace
  config.toml.example
  crates/
    liquid-snipe/                 # bin: hot loop owner, CLI, app wiring
    liquid-snipe-core/            # types, config, DuckDB, risk engine, slippage controller
    liquid-snipe-stream/          # gRPC + WS subscriptions; decoders
    liquid-snipe-strategy/        # BuyTrigger + SellTriggers + heartbeat evaluators
    liquid-snipe-simulator/       # paper-mode fill model
    liquid-snipe-exec/            # sol-trade-sdk wrapper for buy/sell
```

### 5.1 `liquid-snipe` (bin)

| module | responsibility |
|---|---|
| `main.rs` | runtime bootstrap, install crypto provider, parse CLI |
| `cli.rs` | clap subcommands: `run` (default), `replay <sig>`, `stats`, `migrate` |
| `app.rs` | wires `AppState` and shared atomics; spawns background tasks; **owns the hot loop** |
| `hot_loop.rs` | `async fn run(stream, state, strategy) -> !` |
| `bg/blockhash.rs` | refresher task |
| `bg/wallet_balance.rs` | polls `getBalance` (+ WSOL ATA) on `[wallet].balance_refresh_ms`; updates `AtomicU64`; recomputes bankroll |
| `bg/enrichment.rs` | speculative mint fetcher |
| `bg/heartbeat.rs` | wall-clock tick: time_stop, decay fallback |
| `bg/housekeeping.rs` | prune closed positions, expire enrichment |
| `bg/persistence.rs` | drains `crossbeam::channel<DbWrite>` → DuckDB batched inserts |
| `bg/confirmation_audit.rs` | re-check fills at `Confirmed`, handle reverts |
| `bg/slippage_controller.rs` | tracks consecutive-failure window, bumps `slippage_bps` atomic |
| `bg/config_reloader.rs` | SIGHUP handler → reload TOML, swap source/SWQOS/strategy |
| `metrics.rs` | structured logs, frame timing histogram |
| `stats.rs` | `stats` subcommand output (text + JSON) |

### 5.2 `liquid-snipe-core`

| module | responsibility |
|---|---|
| `types.rs` | `ChainEvent`, `EventKind`, `Position`, `Fill`, `EnrichedMint`, `DexKey` |
| `dexes.rs` | DEX registry: program IDs, event kinds, decoder selector |
| `config.rs` | TOML loader, `{{helius}}` expansion, validation, `Config::reload(path)` |
| `wallet.rs` | wallet loader (file path or `WALLET_BASE58_ENV`); fatal on missing in `live` |
| `db.rs` | DuckDB connection, migrations, prepared statements |
| `risk.rs` | `RiskEngine::pre_entry_ok(plan, snapshot) -> Result<(), RejectReason>` evaluating bankroll-relative thresholds |
| `slippage.rs` | controller state struct: failure window, current bps, bump policy |
| `state.rs` | `AppState` and the `DashMap<Pubkey, Position>`, `DashMap<Pubkey, EnrichedMint>` definitions |
| `consts.rs` | WSOL, burn addresses |

### 5.3 `liquid-snipe-stream`

| module | responsibility |
|---|---|
| `source.rs` | `enum Source { Yellowstone, HeliusWs, Replay }` — all yield `Stream<Item = RawTx>`; `Source::reload(new_config)` swaps endpoint |
| `yellowstone.rs` | `YellowstoneSource` over `yellowstone-grpc-client`. Auto-reconnect with backoff. |
| `helius_ws.rs` | fallback path |
| `replay.rs` | reads recorded JSONL of past events for offline test runs |
| `decoders.rs` | per-DEX `decode(raw_tx) -> Option<ChainEvent>`. Anchor decoders via `carbon-*-decoder`. Legacy log-substring fallback for Raydium AMM v4 (`initialize2`, `ray_log`) and pump.fun snake_case discriminators. |
| `parser.rs` | extract `(base_mint, quote_mint, base_reserve, quote_reserve, price)` from decoded tx |

### 5.4 `liquid-snipe-strategy`

| module | responsibility |
|---|---|
| `buy_trigger.rs` | `BuyTrigger { filters: Vec<Filter> }` with `evaluate(event, enrich, risk) -> BuyDecision` |
| `filters.rs` | `enum Filter { EventKind, MinSolLiquidity, DexAllowlist, QuoteMints, RenouncedAuthorities, LpBurned, MaxTop10Concentration, MinHolderCount, MaxMarketCapSol, DeployerMaxPriorLaunches, DeployerBlocklist }` — each is a pure fn |
| `sell_triggers.rs` | `enum SellTrigger { HardStop, Ladder, TrailingStop, LiquidityDrain, Decay, InsiderSell, TimeStop }` with priority & evaluator |
| `evaluator.rs` | `Strategy::evaluate_buy` and `Strategy::evaluate_exits`; stable priority order |
| `decay_ring.rs` | small in-memory ring of last N price samples per position, used by `Decay` |

### 5.5 `liquid-snipe-simulator`

| module | responsibility |
|---|---|
| `fill.rs` | linear-impact slippage model + flat gas (configurable defaults) |
| `paper.rs` | when mode=paper, `liquid-snipe-exec` routes here; same `Fill` shape as live |

### 5.6 `liquid-snipe-exec`

| module | responsibility |
|---|---|
| `client.rs` | `ExecClient` holds `Arc<TradingInfrastructure>` (shared per `sol-trade-sdk` "Method 2: Shared infrastructure") and `Arc<Keypair>` |
| `swqos.rs` | builds `Vec<SwqosConfig>` from `[[swqos]]` config array — supports default RPC, Jito, Temporal/Nozomi (hosted or self-hosted via custom URL), ZeroSlot, FlashBlock, BlockRazor, Astralane, NextBlock, SpeedLanding |

| `dex_params.rs` | per-DEX `TradeBuyParams` / `TradeSellParams` builders. PumpFun / PumpSwap event-derived; Raydium AMM v4 / CPMM and Meteora DAMM v2 use `from_pool_address_by_rpc` (prefetched by enrichment) |
| `buy.rs` | `async fn buy(plan, blockhash, slippage_bps, gas) -> Result<Fill>` |
| `sell.rs` | `async fn sell(pos, fraction, reason, blockhash, slippage_bps, gas) -> Result<Fill>` |
| `wsol_wrap.rs` | helper: wrap N SOL → WSOL ATA. Exposed as `liquid-snipe wrap-sol <amount>` subcommand. Runs once at boot if `[wallet].auto_wrap_sol > 0`. |

### 5.7 DEX → `sol-trade-sdk::DexType` mapping

| DexKey | DexType | params builder |
|---|---|---|
| `pumpfun` | `PumpFun` | `PumpFunParams::from_dev_trade` (event-derived) |
| `pumpswap` | `PumpSwap` | `PumpSwapParams::from_trade` (event-derived) |
| `raydium-amm` | `RaydiumAmmV4` | `RaydiumAmmV4Params::from_pool_address_by_rpc` (prefetch) |
| `raydium-cpmm` | `RaydiumCpmm` | `RaydiumCpmmParams::from_pool_address_by_rpc` (prefetch) |
| `meteora-damm-v2` | `MeteoraDammV2` | `MeteoraDammV2Params::from_pool_address_by_rpc` (prefetch) |
| `raydium-clmm`, `meteora-dlmm`, `orca-whirlpool` | (no SDK support) | capture & evaluate only; execution skipped with `signal:fired,exec:unsupported` |

## 6. Config schema

TOML. Every tuning value is configurable. Defaults are conservative; the
operator overrides for production.

```toml
[mode]
default = "live"   # live | paper | observe; CLI flag wins

[wallet]
keypair_path       = "data/wallet.json" # OR set WALLET_BASE58_ENV
keypair_env        = "WALLET_BASE58"
auto_wrap_sol      = 0.0                # SOL→WSOL on boot, 0 = no wrap
balance_refresh_ms = 1000               # background poll cadence; independent
                                        # of [blockhash].refresh_ms

[risk]
# All percentages are of bankroll. Bankroll is computed as:
#
#   bankroll_sol = wallet.lamports / 1e9
#                + WSOL_ATA.balance
#                + Σ open_positions.realised_sol         (closed-rung proceeds
#                                                         from partial sells
#                                                         that haven't yet been
#                                                         spent on a new entry)
#
# Unrealised mark-to-market on open positions is *not* counted as bankroll —
# it is tracked separately as "open exposure" against max_total_risk_pct.
# Bankroll is recomputed on boot and on every fill.
max_total_risk_pct      = 50           # halt new entries while open exposure > 50%
max_per_trade_risk_pct  = 5            # size each new trade as 5% of bankroll
max_daily_loss_pct      = 10           # halt new entries on -10% day
max_open_positions      = 4
min_wallet_sol_floor    = 0.05         # absolute SOL floor

[slippage]
default_bps        = 300               # 3% starting slippage
max_bps            = 2500              # cap (25%)
bump_bps           = 1000              # +10% per bump
fail_window_n      = 5                 # consecutive failures before bump
fail_window_secs   = 60                # failures only count within window
reset_on_success   = true

# --- Streaming source (hot-swappable on SIGHUP) ---
[grpc]
enabled        = true
endpoint       = "https://your-yellowstone.example.com:443"
auth_token_env = "GRPC_AUTH_TOKEN"

[grpc.fallback_ws]                      # used when gRPC unavailable
enabled  = true
http_url = "{{helius}}"
ws_url   = "{{helius}}"

[rpc]
http_url        = "{{helius}}"          # for enrichment + blockhash + sol-trade-sdk
commitment_hot  = "processed"
commitment_audit = "confirmed"

# --- SWQOS (hot-swappable on SIGHUP) ---
# Each entry maps 1:1 to a sol-trade-sdk SwqosConfig variant.
# Provide either `region` (hosted) or `url` (custom / self-hosted) for each.
[mev]
mev_protection = false                  # global flag (Astralane QUIC :9000 / BlockRazor)

[[swqos]]
provider = "default"                    # plain RPC submission
url      = "{{rpc.http_url}}"

# [[swqos]]
# provider = "jito"
# uuid     = "..."                      # empty string for community
# region   = "Frankfurt"

# [[swqos]]
# provider = "temporal"                 # = Nozomi
# api_token_env = "TEMPORAL_API_TOKEN"
# region   = "Frankfurt"                # OR set url for self-hosted

# [[swqos]]
# provider = "temporal"
# api_token_env = "TEMPORAL_API_TOKEN"
# url      = "http://my-relay:8080"     # self-hosted Nozomi node

# [[swqos]]
# provider = "zeroslot"
# api_token_env = "ZEROSLOT_API_TOKEN"
# region   = "Frankfurt"

# [[swqos]] provider = "flashblock"; api_token_env = "FLASHBLOCK_TOKEN"; region = "Frankfurt"
# [[swqos]] provider = "blockrazor"; api_token_env = "BLOCKRAZOR_TOKEN"; region = "Frankfurt"
# [[swqos]] provider = "astralane";  api_token_env = "ASTRALANE_KEY"; region = "Frankfurt"; transport = "quic"
# [[swqos]] provider = "nextblock";  api_token_env = "NEXTBLOCK_TOKEN"; region = "NewYork"
# [[swqos]] provider = "speedlanding"; api_token_env = "SPEEDLANDING_TOKEN"; region = "Frankfurt"

[gas]
compute_unit_limit       = 500_000
compute_unit_price_micro = 150_000
priority_fee_sol_buy     = 0.001
priority_fee_sol_sell    = 0.001
preempt_fee_multiplier   = 2.0          # multiplier applied when a higher-priority sell preempts a pending one

[dexes]
enabled = ["raydium-amm","raydium-cpmm","raydium-clmm",
           "orca-whirlpool","meteora-dlmm","meteora-damm-v2",
           "pumpfun","pumpswap"]

# --- Tuning (all configurable) ---
[hot_loop]
frame_warn_us = 1000                    # log if a frame exceeds this
spawn_buffer  = 8                       # bounded executor concurrency

[blockhash]
refresh_ms = 400

[enrichment]
mint_ttl_sec        = 300
deployer_ttl_sec    = 3600
deployer_lookback   = 50
required_timeout_ms = 800               # how long to hold a candidate waiting

[heartbeat]
tick_ms = 250                           # wall-clock cadence for time/decay fallback

[housekeeping]
tick_sec = 30

[persistence]
batch_max_rows = 256
batch_max_ms   = 1000
duckdb_path    = "data/liquid-snipe.duckdb"

[confirmation_audit]
delay_ms = 7000                         # wait this long after submit before re-checking at Confirmed

# --- Strategy ---
[strategy]
id = "default"

[strategy.buy_trigger]
event_kinds                  = ["INIT", "MIGRATE"]
min_sol_liquidity            = 10.0
dex_allowlist                = []                       # empty = use [dexes].enabled
quote_mints                  = ["WSOL"]
require_renounced_authorities = true
require_lp_burned            = false
max_top10_holder_concentration = 0.50
min_holder_count             = 0
max_market_cap_sol           = 0                        # 0 = no cap
deployer_max_prior_launches  = 0                        # 0 = first-time deployer; null = no limit
deployer_blocklist_path      = "data/blocklist.json"
enrichment_timeout_ms        = 800

# Insider-set capture (used by the insider_sell SellTrigger; see SPEC §4.4).
# Snapshot taken at entry, frozen for the position's lifetime.
insider_capture_top_n        = 5                        # top-N largest holders to include
insider_capture_min_pct      = 0.01                     # exclude holders below this fraction of supply

# Sell triggers — order is priority order on tie.
[[strategy.sell_triggers]]
kind = "hard_stop"
stop_pct = -0.15

[[strategy.sell_triggers]]
kind = "ladder"
rungs = [
  { profit = 0.10, sell = 0.5  },
  { profit = 0.25, sell = 0.25 },
  { profit = 0.50, sell = 0.25 },
]

[[strategy.sell_triggers]]
kind = "trailing_stop"
trail_pct = 0.08

[[strategy.sell_triggers]]
kind = "liquidity_drain"
drain_pct = 0.5

[[strategy.sell_triggers]]
kind = "insider_sell"
insider_pct = 0.10

[[strategy.sell_triggers]]
kind = "decay"
samples_n = 4

[[strategy.sell_triggers]]
kind = "time_stop"
hold_sec = 300

[logging]
level  = "info"
format = "json"
```

### 6.1 Validation

- Boot: at least one filter on the BuyTrigger; at least one SellTrigger;
  `max_per_trade_risk_pct ≤ max_total_risk_pct`; `min_wallet_sol_floor > 0`
  in `live` mode; wallet keypair resolvable in `live` mode.
- `{{helius}}` resolves to `https://mainnet.helius-rpc.com/?api-key=$HELIUS_API_KEY`.
- Empty SWQOS list is a fatal error in `live` mode.

## 7. Adaptive slippage controller

State (in `liquid-snipe-core::slippage::Controller`):

```rust
struct Controller {
    base_bps:    u16,                // from config
    current_bps: AtomicU16,          // read by execute_buy
    max_bps:     u16,
    bump_bps:    u16,
    failures:    Mutex<VecDeque<Instant>>,
    fail_window: Duration,
    fail_threshold: usize,
    reset_on_success: bool,
}
```

Behaviour:

- On every buy attempt the executor reads `current_bps` and uses it as the
  `slippage_basis_points` field in `TradeBuyParams`.
- On buy failure (timeout, slippage exceeded, SWQOS reject), call
  `record_failure(now)`. Drop entries older than `fail_window`. If the
  remaining count ≥ `fail_threshold`, `current_bps = min(current_bps +
  bump_bps, max_bps)` and clear the failure deque.
- On buy success and `reset_on_success`, clear the deque; if `current_bps >
  base_bps`, decay one step toward base.
- All transitions logged structurally and persisted to `signal_decisions`
  via the `risk_reason` field for audit.

## 8. Hot-reload mechanism

`bg/config_reloader.rs` registers a `SIGHUP` handler. On signal:

1. Re-parse `config.toml`. Validate.
2. Compute a diff: which sub-trees changed.
3. For each changed sub-tree, dispatch:
   - `[grpc]`, `[grpc.fallback_ws]`, `[dexes]` → `Source::reload(new)` (drops
     stream, reopens with new params, in-flight events drain).
   - `[[swqos]]`, `[mev]` → rebuild `Vec<SwqosConfig>`, ask `liquid-snipe-exec` to
     swap (`TradingInfrastructure` rebuilt; in-flight buys/sells use the old
     until they finish).
   - `[slippage]` → `Controller::update(new)`.
   - `[gas]`, `[hot_loop]`, `[heartbeat]`, `[persistence]` → atomic swap of
     the relevant config struct.
   - `[strategy]` and `[risk]` → swap `Arc<Strategy>` and `Arc<RiskProfile>`
     in `AppState`. **In-flight positions retain a snapshot of their
     original SellTriggers** (cloned at entry). New entries see the new
     strategy. Logged.
4. Emit a structured log line per changed sub-tree.

Failures during reload (validation error, gRPC reconnect failure) leave the
old config in place and log error.

**In-flight positions and strategy reload — explicit semantics.**

The clone-at-entry rule is total: every in-flight `Position` carries an
`Arc<StrategySnapshot>` it took when it was opened, and the hot loop
evaluates exits against that snapshot, not against the current
`AppState.strategy`.

| reload change | applies to in-flight positions? | applies to new positions? |
|---|---|---|
| existing SellTrigger param changed (e.g. `trail_pct`) | **no** | yes |
| existing SellTrigger removed | **no** | yes |
| new SellTrigger kind added | **no** | yes |
| `[risk]` thresholds changed | **yes for the next entry-attempt's risk check; in-flight position sizing is already locked** | yes |
| `[strategy.buy_trigger]` changed | n/a (in-flight is past entry) | yes |
| `[slippage]` changed | yes (slippage is global, not per-position) | yes |
| `[gas]`, `[hot_loop]`, `[heartbeat]` | yes (these are runtime-global) | yes |
| `[grpc]`, `[[swqos]]` | yes (substrate, not per-position) | yes |

**Operator workflow for retroactively applying new triggers to existing
positions:** close & reopen. Either (a) invoke a manual close via
`liquid-snipe close <position_id> --reason manual` (planned subcommand) or
(b) wait for the existing triggers to fire naturally. There is no
mid-flight trigger upgrade — it would invalidate the priority ordering and
the `pending_sell` state machine.

On every reload that mutates `[strategy]` or `[risk]`, the reloader emits:

```
config-reload: strategy swapped (id=v3 → v4). Diff:
  added:    insider_sell { insider_pct=0.05 }
  modified: trailing_stop { trail_pct: 0.08 → 0.06 }
  removed:  none
in-flight positions retained original strategy: 3
  - position a3w… (entry +12s)   strategy=v3
  - position 7tj… (entry +4s)    strategy=v3
  - position f9q… (entry +1s)    strategy=v3
new positions opened from now will use strategy v4
```

## 9. Workspace dependencies

```toml
[workspace.dependencies]
liquid-snipe           = { path = "crates/liquid-snipe" }
liquid-snipe-core      = { path = "crates/liquid-snipe-core" }
liquid-snipe-stream    = { path = "crates/liquid-snipe-stream" }
liquid-snipe-strategy  = { path = "crates/liquid-snipe-strategy" }
liquid-snipe-simulator = { path = "crates/liquid-snipe-simulator" }
liquid-snipe-exec      = { path = "crates/liquid-snipe-exec" }

# Solana / trading
sol-trade-sdk  = { path = "../../reference/sol-trade-sdk", version = "4.0.8" }
solana-sdk     = "3.0"
solana-client  = "3.1"
solana-program = "3.0"

# Carbon decoders only (no Pipeline)
carbon-core                       = "0.12"
carbon-raydium-amm-v4-decoder     = "0.12"
carbon-raydium-cpmm-decoder       = "0.12"
carbon-raydium-clmm-decoder       = "0.12"
carbon-orca-whirlpool-decoder     = "0.12"
carbon-meteora-dlmm-decoder       = "0.12"
carbon-meteora-damm-v2-decoder    = "0.12"
carbon-pumpfun-decoder            = "0.12"
carbon-pump-swap-decoder          = "0.12"

yellowstone-grpc-client = "5"
yellowstone-grpc-proto  = "5"

duckdb = { version = "1", features = ["bundled"] }

tokio       = { version = "1", features = ["full"] }
tokio-util  = { version = "0.7", features = ["rt"] }
futures     = "0.3"

# Hot-loop primitives
dashmap           = "6"
arc-swap          = "1"
crossbeam-channel = "0.5"
parking_lot       = "0.12"

# Config reload
notify     = "6"      # optional: file watcher in addition to SIGHUP
signal-hook-tokio = "0.3"

clap     = { version = "4", features = ["derive"] }
serde    = { version = "1", features = ["derive"] }
toml     = "0.8"
tracing  = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter","json"] }
dotenvy  = "0.15"

clru      = "0.6"
anyhow    = "1"
thiserror = "1"
uuid      = { version = "1", features = ["v4","serde"] }
chrono    = "0.4"
```

We **do not** depend on `carbon-yellowstone-grpc-datasource` or
`carbon-core::Pipeline` (multi-stage shape we're rejecting). Carbon
decoders only.

## 10. Tests

### 10.1 Unit / property tests (`liquid-snipe-strategy`)

- Filter pure-function tests with synthetic `ChainEvent` + `EnrichedMint`
  fixtures (built in-test, no external files).
- SellTrigger priority test: construct a `Position` and a `ChainEvent` that
  satisfies multiple triggers; assert highest-priority one fires.
- Concurrent-fill semantics: simulate `pending_sell` true + new
  higher-priority trigger → asserts a preempt sell is dispatched with the
  multiplied fee.
- Decay ring: rolling-window correctness.

### 10.2 Frame budget regression (`liquid-snipe`)

Replay 10 000 synthetic gRPC updates through `hot_loop::run` with all
backgrounds stubbed. Assert p99 < 500 µs, p99.9 < 1 ms. **CI gate (AC2).**

### 10.3 Integration: paper round-trip (`liquid-snipe`)

Spin a `Source::Replay` of recorded chain events, run the full app in
`paper` mode, assert a known fixture produces a known set of `positions`
and `fills` rows.

### 10.4 Integration: hot-reload (`liquid-snipe`)

Boot with config A, send SIGHUP after switching to config B with a
different SellTrigger threshold and a different SWQOS list. Assert: gRPC
reconnect happened, slippage controller picked up new params, in-flight
position kept its old triggers.

### 10.5 Integration: live test wallet (manual)

Operator-run only (AC4). Documented in `docs/manual-tests.md`.

## 11. Operational notes

- **Wallet provisioning.** Operator generates `data/wallet.json` with
  `solana-keygen new -o data/wallet.json` (or sets `WALLET_BASE58_ENV`) and
  funds it. The bot will not generate one. Boot fails fast on a missing or
  invalid wallet in `live` mode with a clear message.
- **Wrapping SOL.** The first time you trade WSOL pairs you need a WSOL
  ATA. Run `liquid-snipe wrap-sol <amount>` once, or set
  `[wallet].auto_wrap_sol` to wrap on every boot.
- **First-run migration.** `liquid-snipe migrate` creates the DuckDB
  schema. Idempotent. Schema-evolution policy is in §11.1.
- **Secrets.** `HELIUS_API_KEY`, `GRPC_AUTH_TOKEN`, all SWQOS API tokens
  loaded via env (`dotenvy` reads `.env.local`). Never logged.
- **Shutdown.** SIGINT → `CancellationToken` → drop stream → drain workers
  → final SELL on every open position (`reason = shutdown`) → persistence
  drains → exit. 30 s budget; force-exit on timeout.
- **Hot-swap.** SIGHUP triggers config reload (§8).
- **Replay.** `liquid-snipe replay <tx_signature>` reconstructs the
  decision trail from `chain_events`, `signal_decisions`, `positions`,
  `fills`. Output spec in §13.

### 11.1 Migration / schema evolution

DuckDB schema is versioned via a `_meta` table:

```sql
CREATE TABLE _meta (
    key      VARCHAR PRIMARY KEY,
    value    VARCHAR
);
-- _meta rows include:
--   schema_version → integer monotonically increasing
--   created_at     → ISO-8601 timestamp of first migrate
--   binary_version → semver of the liquid-snipe build that last opened the DB
```

**Migration files** live in
`crates/liquid-snipe-core/migrations/V<n>__<name>.sql`
(for example `V1__initial.sql`, `V2__add_insider_set.sql`). They are
embedded into the binary via `include_str!`. Filenames are immutable once
released; new schema deltas always get a higher `V<n>`.

**`liquid-snipe migrate` behaviour:**

1. Open the DuckDB file (create if missing).
2. Read `_meta.schema_version` (treat missing → 0).
3. Read the binary's `EXPECTED_SCHEMA_VERSION` constant.
4. Branch:
   - **DB == binary**: no-op, exit 0 (idempotent — safe to run repeatedly).
   - **DB < binary**: apply each `V<n>__*.sql` for `n in (db+1..=binary)`
     inside a single transaction per file; bump `_meta.schema_version`
     after each successful file.
   - **DB > binary**: **fatal**. Print:
     `error: DB at schema_version=N, this binary expects M (M < N).
     Refusing to open. Use a newer binary.` Exit 2. Do not open the DB.

**Forward-only.** Migrations are **append-only** — they can `CREATE TABLE`,
`ALTER TABLE … ADD COLUMN`, `CREATE INDEX`, `CREATE VIEW`, and `INSERT`
seed data. They may **not** drop columns, drop tables, or rewrite existing
rows in a way that loses information unless the operator passes
`--force-destructive`. The intent is that `data/liquid-snipe.duckdb` is a
permanent record of the bot's history; schema evolves additively.

**`liquid-snipe run` boot check.** Every non-migrate subcommand opens the DB
read/write and verifies `_meta.schema_version == EXPECTED_SCHEMA_VERSION`.
If lower → boot fails fast with
`error: DB schema is outdated. Run \`liquid-snipe migrate\` and retry.`
If higher → fatal as above. The bot never auto-migrates on boot — schema
changes are operator-acknowledged.

## 12. Stats command

`liquid-snipe stats [--window 24h] [--json]` prints (in plain text by
default):

```
=== liquid-snipe stats — last 24h ===
Mode:          live
Bankroll:      4.20 SOL  (wallet 3.85 + open exposure 0.35)
Open exposure: 0.35 SOL across 2 positions
                position    mint        entry  cur     pnl%   age
                a3W4…pump   pumpswap    2.42e-5 2.66e-5 +9.9%  4m
                7tj…bonk    pumpfun     1.10e-6 1.05e-6 -4.5%  1m

Realised today: +0.180 SOL  (+4.3% of bankroll)
Trades:        18 closed   hit 11/18 (61%)   mean +1.2%   med +0.4%
                worst -8.1%  best +18.3%   max-drawdown -2.1%
Exits:         hard_stop:3  ladder:7  trail:5  drain:2  decay:1

Slippage:      300 bps base  →  current 300 bps  (no failures in 60s window)
Risk:          OK   (open 8% / 50% cap, daily +4.3% / -10% loss cap)
Last reload:   2026-05-14 11:32:01 UTC  (changed: [strategy.sell_triggers], [grpc])
```

`--json` emits the same data structured for piping.

## 13. Replay command

`liquid-snipe replay <tx_signature> [--json]` reconstructs the full
decision and execution trail for any tx the bot saw. The `tx_signature`
may be (a) the entry-trigger pool event, (b) a buy/sell fill, or (c) a
non-traded candidate that was rejected by filters or risk. The command
joins `chain_events`, `signal_decisions`, `positions` (all versions),
`fills`, and `mint_enrichment`.

Plain-text output:

```
=== liquid-snipe replay 5xY…aBc ===
Captured:    2026-05-14 11:32:01.123 UTC   slot 234567890   recv +14ms
DEX:         pumpswap         pool 5xy…abc        program 6EF7…
Event:       MIGRATE          sol_value 12.4
             base_reserve 1.234e9   quote_reserve 12.4   px 1.005e-8

Enrichment:  mint 4Tz…pump (decimals 9, supply 1.000e9)
             mint_authority null   freeze_authority null   lp_burned true
             top10 0.42   holders 187   deployer 9aB…   prior_launches 0
             fetched_at 2026-05-14 11:32:01.090   age 33ms

Decision:    ACCEPT
  filters_passed:  event_kinds, min_sol_liquidity, quote_mints,
                   require_renounced_authorities, max_top10_holder_concentration,
                   deployer_max_prior_launches
  filters_failed:  []
  risk:            OK   open 8% / 50% cap   daily +4.3% / -10% loss cap
  size:            0.0420 SOL  (5.0% of bankroll 0.84 SOL)

Buy fill:    submitted 2026-05-14 11:32:01.245   txSig 4xy…def
             swqos    jito (frankfurt)             slippage 300 bps
             confirmed 2026-05-14 11:32:01.598    +353ms
             tokens 4.179e9   quote_filled 0.0420 SOL   fee 0.00128 SOL

Position:    a3w…  v1→v6   state closed   age 41s
  v1  open   2026-05-14 11:32:01.598   entry_price 1.005e-8   peak 1.005e-8
  v2  open   +1.2s   evt BUY   px 1.057e-8 +5.2%   peak 1.057e-8
  v3  open   +3.4s   evt BUY   px 1.087e-8 +8.1%   peak 1.087e-8
  v4  closing +12.7s sell trigger=ladder rung 1   sold 0.50   reason ladder
  v5  closing +15.3s sell trigger=trailing_stop   sold 0.50   reason trailing_stop
  v6  closed  +41.0s realised +0.0048 SOL  +11.4%

Sells:       2 fills, total 4.179e9 tokens, total quote 0.0468 SOL
  ladder           0.50 frac   tx 7uV…111   slippage 300 bps   confirmed +12.9s
  trailing_stop    0.50 frac   tx 9wQ…222   slippage 300 bps   confirmed +15.5s

Audit:       all fills confirmed at Confirmed commitment   no reverts
```

If the signature was rejected:

```
=== liquid-snipe replay 8jZ…aaa ===
Captured:    2026-05-14 11:33:14.001 UTC   slot 234568012
DEX:         raydium-amm   pool …
Event:       INIT          sol_value 3.2

Enrichment:  cache cold (waited 800 ms, gave up)

Decision:    REJECT
  filters_passed:  event_kinds, dex_allowlist, quote_mints
  filters_failed:  min_sol_liquidity (3.2 < 10.0),
                   require_renounced_authorities (cache cold: enrichment-pending)
  risk:            (not evaluated)
```

`--json` emits the same structure with stable keys for piping.

## 14. Build / test / run

```bash
cargo build --release
cargo test --workspace
cargo run -p liquid-snipe -- --config config.toml                      # uses [mode].default; live if unset
cargo run -p liquid-snipe -- --config config.toml --paper              # CLI overrides config
cargo run -p liquid-snipe -- --config config.toml --observe
cargo run -p liquid-snipe -- replay <txSignature>
cargo run -p liquid-snipe -- stats --window 24h
cargo run -p liquid-snipe -- wrap-sol 0.5                              # one-shot SOL→WSOL
cargo run -p liquid-snipe -- migrate
```
