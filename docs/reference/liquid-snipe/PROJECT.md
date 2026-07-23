# liquid-snipe — PROJECT

## Objective

Build a Solana **liquidity sniping bot in Rust** that listens to first-liquidity
events on the major Solana DEXes / launchpads, filters them through one
operator-configured strategy, executes WSOL-denominated buys against the
originating DEX, and manages each position event-driven through a list of
sell triggers — within a written risk profile.

This is a **clean-room implementation** in a new Rust crate sibling to the
existing `liquid-snipe/` POC directory. The POC's research findings —
the entry/exit signal taxonomy, the price-from-tx insight, the strategy
profiles — inform the design but are **not the code we're shipping**. No
file from `liquid-snipe/` is read by the new bot at runtime.

Directory: **`liquid-snipe-rs/`** (sibling to `liquid-snipe/`). Workspace
binary is `liquid-snipe`; crates are `liquid-snipe`, `liquid-snipe-core`,
`liquid-snipe-stream`, `liquid-snipe-strategy`, `liquid-snipe-simulator`,
`liquid-snipe-exec`.

## Scope

**In:** pump.fun, PumpSwap, Raydium AMM v4 / CPMM, Meteora DAMM v2 — the
DEXes `sol-trade-sdk` can execute against. Capture-only on Raydium CLMM,
Meteora DLMM, Orca Whirlpool (signal evaluation runs but no buy/sell tx).
**WSOL-only** quote: WSOL is the universal pair on fresh pools and dropping
USDC/USDT removes a class of edge cases (different ATAs, different SOL→USDC
paths). A SOL↔WSOL wrap helper is in scope so the operator can top up the
WSOL ATA from native SOL without a separate tool.

**Out:** Jupiter / aggregator routing. Cross-DEX arbitrage. Multi-wallet.
Web UI (CLI + structured logs only). Generating wallets in-app — the
operator provides one.

## Strategy model

One configurable **Strategy** = one **BuyTrigger** + an ordered list of
**SellTriggers**, all tied to a **RiskProfile**. The operator can swap or
tune any of them via config; the bot loads exactly one strategy at a time.

### BuyTrigger (AND-combined filters on a captured chain event)

The hot loop sees a CREATE / INIT / MIGRATE / DEPOSIT event and runs each
configured filter. All must pass.

| filter | meaning |
|---|---|
| `event_kinds` | which liquidity events count (default `["INIT", "MIGRATE"]`) |
| `min_sol_liquidity` | event `solValue` ≥ N |
| `dex_allowlist` / `dex_blocklist` | restrict to a subset of capture-DEXes |
| `quote_mints` | quote token whitelist (default `["WSOL"]`) |
| `require_renounced_authorities` | mint+freeze authority both null |
| `require_lp_burned` | ≥95 % of LP token at burn / locker |
| `max_top10_holder_concentration` | top-10 holders own ≤ X fraction of supply |
| `min_holder_count` | total token holders ≥ N |
| `max_market_cap_sol` | computed from supply × spot price ≤ N |
| `deployer_max_prior_launches` | prior tokens by signer ≤ N (proxy for serial rugger) |
| `deployer_blocklist_path` | hard-deny list, JSON file, hot-reloadable |
| `enrichment_timeout_ms` | how long to wait for async mint enrichment before reject |

Filters that need RPC (renounced authorities, LP burn, holder concentration,
deployer history) are computed by the **enrichment task** and read from cache
on the hot path. A strategy that requires an enrichment field rejects the
candidate if the cache is cold past `enrichment_timeout_ms`; the same mint
gets a warm cache for the next event.

### SellTriggers (OR-combined, evaluated in priority order on every chain event for the position's mint)

The bot ships seven trigger kinds; the operator composes any subset.

| kind | params | meaning |
|---|---|---|
| `hard_stop` | `stop_pct` (negative) | exit fully when return ≤ stop_pct |
| `ladder` | `rungs: [{profit, sell}]` | sell `sell` fraction at each profit rung |
| `trailing_stop` | `trail_pct` | exit fully when drop from peak ≥ trail_pct (only after entry is in profit) |
| `liquidity_drain` | `drain_pct` | exit when pool quote reserve < `drain_pct` × baseline |
| `decay` | `samples_n` | exit on N consecutive non-positive returns |
| `insider_sell` | `insider_pct` | exit when any address in the position's *insider set* sells ≥ `insider_pct` of supply in one tx (see SPEC §4.4 for set construction) |
| `time_stop` | `hold_sec` | exit after holding for hold_sec |

Priority (when multiple fire on the same event): `hard_stop` → `ladder` →
`trailing_stop` → `liquidity_drain` → `insider_sell` → `decay` → `time_stop`.
Time and decay also run on a wall-clock heartbeat (default 100 ms) for the
case where nobody else is trading the mint.

### RiskProfile (bankroll-relative, not absolute)

| field | meaning |
|---|---|
| `bankroll_sol` | baseline; auto-detected from wallet balance on boot, refreshed on every fill |
| `max_total_risk_pct` | halt new entries while open exposure > X % of bankroll (default 50) |
| `max_per_trade_risk_pct` | size each new trade as X % of bankroll (default 5) |
| `max_daily_loss_pct` | halt new entries when today's realised PnL ≤ −X % (default 10) |
| `max_open_positions` | hard cap on concurrent positions (default 4) |
| `min_wallet_sol_floor` | refuse new entries if wallet < this absolute SOL (default 0.05) |
| `default_slippage_bps` | starting slippage; adapted by the slippage controller |

## Requirements

### Functional

- **R1 — Live event stream.** One Yellowstone gRPC subscription delivers
  every entry candidate and every price/exit update on every open position.
  Endpoint and auth are config-driven. Helius WS `logsNotifications` is the
  fallback when gRPC is unavailable. Both are hot-swappable (see R6).
- **R2 — Single configurable strategy.** Boot loads one Strategy
  (BuyTrigger + SellTriggers + RiskProfile) from config. No code change
  required to retune.
- **R3 — Buy execution.** When the BuyTrigger fires and the RiskProfile
  approves, build the appropriate `TradeBuyParams` for the originating DEX
  via `sol-trade-sdk`, sign with the configured wallet, submit through SWQOS.
  Tx submission runs in a spawned task so the hot loop never blocks. **A buy
  failure marks the position `failed` immediately** — no auto-retry on the
  same opportunity (sniping is time-sensitive, a missed entry is gone).
- **R4 — Adaptive slippage.** The slippage controller tracks consecutive buy
  failures across the rolling window. After **N consecutive failures**
  (default 5), increase the global slippage by `slippage_bump_bps` (default
  +1000 bps = +10 %) up to a `max_slippage_bps` cap. After a success or
  decay window expires, reset.
- **R5 — Position management (event-driven).** Each open position is updated
  on every chain event for its mint, delivered by the same gRPC subscription.
  No position polling. Wall-clock heartbeat (default 100 ms) covers
  time/decay safety nets only.
- **R6 — Config-driven and hot-reloadable.** All endpoints, wallet path,
  strategy, risk profile, SWQOS providers, gas, and tuning live in one TOML.
  `SIGHUP` triggers a config reload that swaps gRPC endpoint, SWQOS providers,
  and adaptive-slippage parameters without restart. Strategy / RiskProfile
  changes also reload but apply only to *new* positions; in-flight positions
  keep their original triggers.
- **R7 — RiskProfile enforcement.** Before every new entry, the risk engine
  evaluates total open exposure, per-trade size, daily loss, open-position
  count, and wallet floor. Any violation rejects the candidate with a
  reason logged to `signal_decisions`.
- **R8 — Wallet from config, never generated.** Wallet keypair is loaded
  from a config-specified path or environment variable. **The bot never
  creates a wallet.** A missing/invalid wallet is a fatal boot error in
  `live` mode (warning in `paper`).
- **R9 — Modes.** Three modes selectable via CLI flag (priority) or config
  (fallback):
  - `live` — real on-chain buys/sells via SWQOS. **Default if neither CLI nor
    config specifies.**
  - `paper` — full pipeline + simulator-based fills, written to DuckDB with
    `tx_signature = paper_<uuid>`.
  - `observe` — capture + signal evaluation only, no buys.
- **R10 — Persistence.** DuckDB at `data/liquid-snipe.duckdb` holds chain events,
  signal decisions, mint enrichment cache, positions (append-only), fills,
  blocklist. The hot loop never writes directly — a persistence task batches
  writes (default every 1 s or 1024 rows).
- **R11 — Modular SWQOS.** The `[[swqos]]` config array configures any
  combination of providers `sol-trade-sdk` supports: default RPC, Jito,
  Temporal/Nozomi, ZeroSlot, FlashBlock, BlockRazor, Astralane, NextBlock,
  SpeedLanding. Each entry takes API key + region OR custom URL (which is
  how Temporal self-hosted is handled — point at your own relay). Concurrent
  multi-provider sends use the SDK's parallel-submit path; fastest wins.
- **R12 — Stats.** `liquid-snipe stats [--window 24h]` summarises: open
  positions, realised PnL by day, hit rate, mean / median / max / drawdown,
  exit-reason histogram, slippage controller state, kill-switch state. Plain
  text + a `--json` flag for piping.

### Non-functional

- **N1 — Latency budget.**
  - Hot-loop frame (gRPC update → decide → spawn submit): **p99 < 500 µs**.
  - Buy submit (spawn → tx confirmed by SWQOS): p50 < 250 ms, p99 < 1 s on a
    dedicated gRPC + colocated SWQOS provider.
  - Sell submit: p99 < 1 s.
- **N2 — Reliability.** All upstreams (gRPC, WS, RPC) auto-reconnect with
  exponential backoff capped at 5 s. The pipeline never aborts on a single
  upstream failure. SWQOS provider failures are isolated; one dead provider
  doesn't take down the rest.
- **N3 — Observability.** Structured JSON logs (`tracing`) per chain event,
  per signal decision, per submitted tx, per fill, per slippage adjustment,
  per kill-switch trip. Per-frame timing histogram exported.
- **N4 — Footprint.** Single binary. DuckDB file under `data/`. No external
  services beyond RPC + gRPC + SWQOS (all third-party).

## Acceptance criteria

### AC1 — Boot and dry observe

`liquid-snipe --config config.toml --observe` against a configured
Yellowstone gRPC endpoint:

- connects within 5 s;
- writes chain events to DuckDB `chain_events` for ≥3 distinct DEXes inside
  60 s of capture during normal mainnet activity;
- emits one `signal_decisions` row per (event, strategy) including
  rejections with structured reasons.

### AC2 — Frame budget

A regression test replays 10 000 recorded gRPC updates through the hot loop
with all background tasks stubbed. **p99 frame time < 500 µs**, p99.9 < 1 ms.
CI gate.

### AC3 — Paper trade end-to-end

`liquid-snipe --config config.toml --paper` for 60 minutes against live
gRPC:

- BuyTrigger fires at least once with a configured threshold tuned for
  current market activity (operator-supplied);
- a complete simulated trade (entry + at least one sell) is recorded in
  `positions` and `fills`;
- `liquid-snipe stats` reports the result.

### AC4 — Live buy on a real liquidity event

`liquid-snipe --config config.toml --live` with a funded test wallet
(operator provisions) and `max_per_trade_risk_pct = 1`:

- one BuyTrigger fires and a real buy lands on-chain (confirmed) within the
  N1 latency budget;
- the position is then exited (any reason) with a real on-chain sell;
- the realised PnL row is written to `positions` with actual on-chain prices;
- `liquid-snipe replay <tx_signature>` prints the full decision and
  execution trail.

### AC5 — Risk and kill-switch verify

With `max_daily_loss_pct = 10` and `bankroll_sol = 1.0`, manually inserting
a synthetic −0.15 SOL realised loss row (15 % of bankroll) causes the next
entry candidate to be **rejected with reason
`risk:daily-loss-exceeded`**, persisted to `signal_decisions`, and visible
in `liquid-snipe stats`.

### AC6 — Hot-reload

Edit the TOML to change the gRPC endpoint and one SellTrigger threshold,
then send `SIGHUP`:

- gRPC reconnects to the new endpoint within 5 s without restart;
- new positions opened after the SIGHUP use the updated SellTrigger;
- in-flight positions continue with their original triggers (logged at info).

### AC7 — Adaptive slippage

Force 5 consecutive simulated buy failures (config: stub a SWQOS that always
errors). Assert:

- the global slippage was bumped by exactly `slippage_bump_bps`;
- a successful buy resets the failure counter;
- slippage never exceeds `max_slippage_bps`.

## Risks and unknowns

- **Latency depends on infrastructure choice.** Yellowstone gRPC tier and
  SWQOS provider latency dominate N1. The bot's frame budget is internal; the
  end-to-end number is bounded by the operator's plan.
- **Strategy expectancy is unproven.** The POC suggested positive expectancy
  on whale-filtered events but `n` is small. Live paper-mode runs are how
  expectancy gets measured.
- **Processed-commitment rollback risk.** Hot loop acts on `Processed` events
  (~400 ms ahead of `Confirmed`). A small fraction of events get reverted;
  a position acted on a reverted entry tx must be force-closed at market. SPEC
  documents the recovery path.
- **DEX coverage gap on CLMM/DLMM/Whirlpool.** Capture-only in v1; if the
  strongest signals start showing up there, plan a v2 Jupiter routing path.
- **Reserve poisoning during partial sell.** A deployer can drain a pool
  while our partial sell is mid-flight. Mitigation: never cancel an
  in-flight tx; preempt with a higher fee on the next tx (SPEC §4.3).

## Open decisions

- **gRPC endpoint provider.** Helius dedicated (Developer plan+), Triton,
  Jito Shredstream, or a self-hosted Yellowstone. Provider research is
  happening in a separate session. Decision affects monthly cost and the
  N1 latency ceiling. SPEC carries a literal placeholder endpoint until
  resolved.
- **SWQOS providers to enable on day one.** Default-RPC ships out of the
  box; under that config the live mode will not hit N1 (p99 < 1 s). Adding
  Jito / Temporal / ZeroSlot / etc. needs API keys and a per-provider tip
  budget. Operator picks; bot supports any subset.

## References

- `liquid-snipe/docs/research.md` — the v2 POC research; canonical source
  for the signal taxonomy this project implements.
- `liquid-snipe/docs/proof.md` — the +10.1 % real-mainnet trade that
  motivated v1.
- `reference/sol-trade-sdk/` — Rust execution SDK (buy/sell against the
  originating DEX).
- `reference/Solana-Sniper-Bot/src/processor/sniper_bot.rs` — production
  sniper architecture this project follows (single hot loop, parsed-tx
  reserves, event-driven exits).
- `reference/carbon/decoders/` — anchor IDL decoders used for instruction
  parsing.
