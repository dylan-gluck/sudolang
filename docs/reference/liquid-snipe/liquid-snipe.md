## PROJECT.md

```sudolang
# liquid-snipe — PROJECT

Solana liquidity sniping bot in **Rust**. Listens to first-liquidity events on
major DEXes/launchpads, filters via one operator-configured strategy, executes
WSOL-denominated buys against originating DEX, manages each position
event-driven via sell triggers within a written risk profile.

Clean-room implementation in `liquid-snipe-rs/` (sibling to POC `liquid-snipe/`).
POC research informs design but no POC file is read at runtime.

Workspace bin: `liquid-snipe`. Crates: `liquid-snipe`, `-core`, `-stream`,
`-strategy`, `-simulator`, `-exec`.

Scope {
  in = [pump.fun, PumpSwap, Raydium AMM-v4, Raydium CPMM, Meteora DAMM-v2]
       // DEXes sol-trade-sdk executes against
  captureOnly = [Raydium CLMM, Meteora DLMM, Orca Whirlpool]
                // signal eval runs, no buy/sell tx
  quote = WSOL-only  // universal pair, removes USDC/USDT edge cases
  include = SOL↔WSOL wrap helper
  out = [Jupiter/aggregator routing, cross-DEX arb, multi-wallet, web UI,
         in-app wallet generation]
}

interface Strategy {
  buyTrigger: BuyTrigger
  sellTriggers: SellTrigger[]   // ordered priority
  riskProfile: RiskProfile
  constraints {
    exactly one strategy loaded at boot; swappable via config
  }
}

interface BuyTrigger {
  // AND-combined filters on a captured chain event (CREATE|INIT|MIGRATE|DEPOSIT)
  event_kinds                    = ["INIT","MIGRATE"]  // default
  min_sol_liquidity              // event.solValue ≥ N
  dex_allowlist | dex_blocklist  // restrict capture-DEX subset
  quote_mints                    = ["WSOL"]            // default
  require_renounced_authorities  // mint+freeze both null
  require_lp_burned              // ≥95% LP at burn/locker
  max_top10_holder_concentration // top-10 holders ≤ X of supply
  min_holder_count
  max_market_cap_sol             // supply × spot ≤ N
  deployer_max_prior_launches    // prior tokens by signer ≤ N
  deployer_blocklist_path        // JSON, hot-reloadable
  enrichment_timeout_ms          // async enrich wait before reject

  constraints {
    RPC-dependent filters (authorities, LP burn, top10, deployer history)
      computed by enrichment task, hot path reads cache only.
    Cold cache past enrichment_timeout_ms ⇒ reject candidate,
      warm cache for next event on same mint.
  }
}

interface SellTrigger {
  // OR-combined, evaluated in priority order on every chain event for mint
  hard_stop(stop_pct<0)              // exit fully when return ≤ stop_pct
  ladder(rungs:[{profit,sell}])      // sell `sell` fraction at each profit rung
  trailing_stop(trail_pct)           // exit when drop-from-peak ≥ trail_pct;
                                     //   only after entry in profit
  liquidity_drain(drain_pct)         // pool quote reserve < drain_pct × baseline
  decay(samples_n)                   // N consecutive non-positive returns
  insider_sell(insider_pct)          // insider sells ≥ insider_pct of supply
                                     //   in one tx; see SPEC §4.4
  time_stop(hold_sec)                // exit after holding hold_sec

  priority = hard_stop > ladder > trailing_stop > liquidity_drain
           > insider_sell > decay > time_stop
  heartbeat = 100ms                  // time/decay also run on wall-clock for
                                     //   mints nobody else is trading
}

interface RiskProfile {
  // bankroll-relative, not absolute
  bankroll_sol           // auto-detected from wallet; refreshed each fill
  max_total_risk_pct=50  // halt new entries while open exposure > X%
  max_per_trade_risk_pct=5
  max_daily_loss_pct=10  // halt new entries when today's realised ≤ −X%
  max_open_positions=4
  min_wallet_sol_floor=0.05  // absolute SOL floor
  default_slippage_bps   // slippage controller adapts
}

Requirements {
  Functional {
    R1 LiveStream: one Yellowstone gRPC sub delivers every entry candidate +
       every price/exit update on every open position. Helius WS
       logsNotifications = fallback. Both hot-swappable (R6).
    R2 SingleStrategy: boot loads one Strategy from config; retune w/o code.
    R3 BuyExec: BuyTrigger fires + RiskProfile approves ⇒ build TradeBuyParams
       via sol-trade-sdk, sign, submit through SWQOS in spawned task
       (hot loop never blocks). Failure ⇒ position `failed` immediately,
       no auto-retry (sniping is time-sensitive).
    R4 AdaptiveSlippage: after N=5 consecutive buy failures, bump slippage by
       slippage_bump_bps (default +1000bps) up to max_slippage_bps. Reset on
       success or window expiry.
    R5 PositionMgmt: event-driven per open position via same gRPC sub. No
       polling. 100ms heartbeat covers time/decay safety nets only.
    R6 HotReload: SIGHUP ⇒ swap gRPC endpoint, SWQOS, slippage params w/o
       restart. Strategy/Risk reload applies only to NEW positions;
       in-flight keep original triggers.
    R7 RiskEnforce: pre-entry check exposure, size, daily loss, count,
       floor; violation rejects w/ reason logged to signal_decisions.
    R8 Wallet: loaded from config path or env var. Bot never creates wallet.
       Missing/invalid ⇒ fatal in `live`, warn in `paper`.
    R9 Modes: live (default) | paper | observe (CLI > config).
    R10 Persistence: DuckDB at data/liquid-snipe.duckdb (chain events,
        signal decisions, mint enrichment, positions append-only, fills,
        blocklist). Hot loop never writes directly — persistence task
        batches (default 1s or 1024 rows).
    R11 ModularSWQOS: [[swqos]] array → any combination sol-trade-sdk supports
        (default RPC, Jito, Temporal/Nozomi, ZeroSlot, FlashBlock, BlockRazor,
        Astralane, NextBlock, SpeedLanding). api_key+region OR custom URL
        (handles Temporal self-hosted). Concurrent parallel-submit, fastest wins.
    R12 Stats: `liquid-snipe stats [--window 24h]` → open positions, realised
        PnL/day, hit rate, mean/med/max/drawdown, exit-reason histogram,
        slippage state, kill-switch state. Text + `--json`.
  }

  NonFunctional {
    N1 Latency {
      hot_frame: gRPC update → decide → spawn submit  // p99 < 500µs
      buy_submit: spawn → confirmed                   // p50<250ms, p99<1s
      sell_submit: p99<1s
      assumes dedicated gRPC + colocated SWQOS
    }
    N2 Reliability: all upstreams auto-reconnect, expo backoff cap 5s.
       Pipeline never aborts on single upstream fail. SWQOS provider
       failures isolated.
    N3 Observability: tracing JSON per chain event, signal decision, submit,
       fill, slippage bump, kill-switch trip. Per-frame timing histogram.
    N4 Footprint: single binary, DuckDB under data/, no services beyond
       RPC/gRPC/SWQOS.
  }
}

Acceptance {
  AC1 BootDryObserve: `--observe` → connects <5s, ≥3 distinct DEX events
      in 60s, one signal_decisions row per (event,strategy) incl rejections.
  AC2 FrameBudget: replay 10k recorded updates, all bg stubbed ⇒
      p99 < 500µs, p99.9 < 1ms. CI gate.
  AC3 PaperE2E: `--paper` 60min live gRPC ⇒ BuyTrigger fires ≥1x, complete
      sim trade in positions+fills, stats reports.
  AC4 LiveBuyReal: `--live` funded test wallet, max_per_trade_risk_pct=1 ⇒
      one buy lands within N1 budget, exits via real sell, realised PnL row
      with actual prices, `replay <sig>` prints full trail.
  AC5 RiskKillSwitch: max_daily_loss_pct=10, bankroll=1.0, inject −0.15 SOL
      loss ⇒ next candidate rejected w/ `risk:daily-loss-exceeded`,
      persisted, visible in stats.
  AC6 HotReload: edit gRPC endpoint + SellTrigger threshold, SIGHUP ⇒ gRPC
      reconnects <5s, new positions use new trigger, in-flight keep originals.
  AC7 AdaptiveSlippage: force 5 simulated fails ⇒ slippage bumped exactly
      slippage_bump_bps, success resets counter, never exceeds max_slippage_bps.
}

Risks {
  - Latency dominated by Yellowstone tier + SWQOS provider (operator's plan)
  - Strategy expectancy unproven; paper-mode runs measure it
  - Processed→Confirmed rollback: ~400ms ahead of Confirmed, small fraction
    reverted; reverted entry tx ⇒ force-close at market (SPEC recovery path)
  - CLMM/DLMM/Whirlpool capture-only; if strongest signals appear there,
    plan v2 Jupiter routing
  - Reserve poisoning during partial sell: deployer can drain mid-sell;
    mitigation = never cancel in-flight, preempt w/ higher fee next tx (§4.3)
}

OpenDecisions {
  gRPC endpoint provider (Helius dedicated / Triton / Jito Shredstream /
    self-hosted Yellowstone) → affects monthly cost + N1 ceiling.
    SPEC carries literal placeholder until resolved.
  SWQOS day-one set: default-RPC ships OOTB but won't hit N1.
    Adding Jito/Temporal/ZeroSlot/etc needs API keys + per-provider tip
    budget. Operator picks; bot supports any subset.
}

References {
  liquid-snipe/docs/research.md — canonical signal taxonomy
  liquid-snipe/docs/proof.md — +10.1% real-mainnet trade
  reference/sol-trade-sdk/ — Rust execution SDK
  reference/Solana-Sniper-Bot/src/processor/sniper_bot.rs — production
    sniper architecture: single hot loop, parsed-tx reserves, event-driven exits
  reference/carbon/decoders/ — anchor IDL decoders
}
```

## SPEC.md

```sudolang
# liquid-snipe — SPEC

Companion to PROJECT.md. PROJECT = what/why; SPEC = how.
Clean-room Rust crate in `liquid-snipe-rs/`. Bin: `liquid-snipe`.
No POC code reused/imported at runtime.

# 1. Architecture

## 1.1 HotLoop {
  shape proven by reference/Solana-Sniper-Bot/.../sniper_bot.rs:464–489
  One tokio task; blocks only on stream.next().await

  loop {
    raw = stream.next().await
    evt = decode(raw)                              // ~µs in-process
    persist_async(evt)                             // crossbeam send

    if pos = open_positions.get(&evt.mint) {
      pos.apply(&evt)                              // price from evt
      if action = strategy.evaluate_exits(pos,&evt) {
        tokio::spawn(execute_sell(pos,action))     // off hot path
      }
    }
    if evt.is_entry_candidate() {
      dec = strategy.evaluate_buy(&evt,&enrich,&risk)
      if plan = dec.fired() { tokio::spawn(execute_buy(plan)) }
    }
  }

  Sources (hot-swappable) = [Yellowstone gRPC, Helius WS fallback, JSONL replay]
    one sub: 8 program IDs

  Workers = tokio::spawn(execute_buy|execute_sell)
    build → blockhash inject → SWQOS submit

  Background (never block hot loop) = {
    blockhash refresher        // poll Nms
    enrichment prefetcher      // mint+holders+deployer; LRU+TTL
    housekeeping               // cleanup, expire enrich
    persistence writer         // drain WAL → DuckDB
    heartbeat                  // X3/X7 fallback every Nms
    slippage controller        // consecutive-failure counter; bump global bps;
                               // reset on success
    config reloader            // SIGHUP → re-read TOML → swap gRPC/SWQOS/
                               // strategy for new positions
  }
}

## 1.2 OffHotPath {
  getAccountInfo (mint auths)       → enrichment task     // RPC RTT
  getTokenLargestAccounts (LP, top10) → enrichment task   // RPC RTT
  getSignaturesForAddress (deployer)  → enrichment task   // RPC RTT
  getLatestBlockhash                  → blockhash refresher
  getBalance                          → own task, [wallet].balance_refresh_ms
                                        (default 1s), AtomicU64. Also eager
                                        refresh on every fill confirmation.
  tx build+sign+submit                → execute_buy|execute_sell workers
  DuckDB writes                       → persistence task draining
                                        crossbeam::channel
  wall-clock sells (time, decay fb)   → heartbeat task
}

## CachingContract {
  Hot loop reads ONLY in-memory:
    open_positions: DashMap
    enrich_cache: DashMap
    blockhash: ArcSwap<Hash>
    wallet_balance: AtomicU64
    daily_pnl: AtomicI64
    slippage_bps: AtomicU16
  Enrichment cache miss for required field ⇒ reject `enrichment-pending`,
    kick off enrichment for next time.
}

## 1.3 Subscription {
  One Yellowstone gRPC sub, commitment=Processed:
    SubscribeRequestFilterTransactions {
      vote: Some(false), failed: Some(false),
      account_required: [], account_exclude: [], signature: None,
      account_include: [/* DEX program ids from active config */]
    }
  Single filter delivers entry candidates AND price updates on every mint
    trading on those programs. Membership in open_positions decides
    whether buy/sell tx triggers exit eval.

  HotSwap: SIGHUP reload re-reads config; if endpoint or [dexes].enabled
    changed → drop stream, reopen w/ new params, in-flight drains.

  Fallback: Helius logsNotifications per program. Logs lack reserves ⇒
    one getTransaction per candidate. Degraded mode, not default.
}

## 1.4 AsyncModel {
  one Tokio multi-thread runtime
  one hot task (stream + inline decode/decide)
  one executor pool: tokio::spawn(execute_*), bounded Semaphore (default 8)
  background tasks independent
  NO per-position task
  shutdown: single CancellationToken → drop stream → drain workers →
    flush persistence → exit. 30s budget, force after.
}

## 1.5 ConfirmationAudit {
  Hot loop acts on Processed. Separate confirmation_audit task re-checks
    every fill at Confirmed after [confirmation_audit].delay_ms (default 7s).

  Per fill: getTransaction(sig, commitment=Confirmed) with retries:
    | attempt | wait | meaning |
    | 1 | initial | first try |
    | 2 | 1s | retry on transient RPC error or null |
    | 3 | 2s | retry |
    | 4 | 4s | last try |

  Transient = RPC transport error (timeout|429|5xx)
            | (null AND current_slot - fill.submit_slot < 32)
              // past 32 slots, null is authoritative missing

  OnRpcExhaustion (all 4 fail transport) {
    fills.confirmed_at_ns := NULL
    fills.error := "audit-rpc-failure"
    log warn(sig, last_error)
    DO NOT mutate position state — outcome unknown, tx may have landed.
    Operator inspects via `liquid-snipe replay <sig>`.
  }

  OnAuthoritative match {
    case Confirmed Ok: set fills.confirmed_at_ns
    case Confirmed Err | missing-past-grace: {
      if buy:          position.state := failed_reverted (no tokens transferred)
      if partial sell: roll back realised_frac, realised_sol; re-eval exits
                       on next event
      if final sell:   reopen position with previous version's state
    }
    case reverted-price-update (rare): on next Confirmed event for mint,
      recompute peak and apply/no-op
  }
}

# 2. FrameBudget

frame = one inbound chain update

| step                            | p99       | runs              |
|---------------------------------|-----------|-------------------|
| stream.next().await wakeup      | ~50µs     | tokio + gRPC      |
| decode tx → ChainEvent          | <100µs    | borsh/log parse   |
| open_positions lookup           | <1µs      | DashMap           |
| pos.apply + evaluate_exits      | <50µs     | pure compute      |
| strategy.evaluate_buy           | <50µs     | pure compute      |
| tokio::spawn(execute_*)         | <10µs     | task spawn        |
| **frame total**                 | **<500µs**|                   |
| (off-frame) execute_buy submit  | p50<250ms, p99<1s | hits N1   |

# 3. DataModel (DuckDB, append-only) {

  chain_events {
    slot, received_at_ns, block_time,
    dex_key, program_id, event_kind  // INIT|CREATE|MIGRATE|DEPOSIT|BUY|SELL
    tx_signature PK, signer,
    base_mint, quote_mint, pool,
    sol_value, base_reserve, quote_reserve, price_quote_per_base,
    confirmed BOOLEAN DEFAULT FALSE  // set by confirmation_audit
    index(base_mint)
  }

  signal_decisions {
    tx_signature PK, decided_at_ns, ok BOOLEAN,
    filters_passed JSON, filters_failed JSON, risk_reason
  }

  mint_enrichment {
    mint PK, fetched_at, decimals, supply,
    mint_authority, freeze_authority,
    top10_concentration, holder_count, lp_burned_or_locked,
    deployer, deployer_prior_launches, notes JSON
  }

  positions {
    (position_id, version) PK,
    mode (live|paper),
    state (opening|open|closing|closed|failed|failed_reverted),
    mint, dex_key, pool, pool_signature,
    entry_slot, entry_at, entry_price, entry_sol_size,
    baseline_quote_reserve, token_amount_open,
    peak_price, realised_frac, realised_sol,
    pnl_sol, pnl_pct, exit_reason, closed_at, updated_at
    index(state), index(mint)
  }

  fills {
    fill_id PK, position_id, side (buy|sell),
    reason (entry|hard_stop|ladder|trailing_stop|liquidity_drain
           |insider_sell|decay|time_stop|shutdown),
    requested_at_ns, submitted_at_ns, confirmed_at_ns,
    tx_signature, fraction_of_pos, tokens, quote_filled, fee_sol,
    slippage_bps, swqos_provider, error
  }

  blocklist { address PK, reason, added_at }

  view open_positions = positions where state in (opening,open,closing)
                        and version is max for position_id
  view daily_pnl = SUM(pnl_sol) where state=closed AND closed_at >= today()
}

# 4. ExitDetection

## 4.1 TwoClocks {
  EventClock (primary): every BUY/SELL on owned mint runs hot loop.
    pos.apply(&evt) updates price/peak/reserves; SellTriggers evaluated
    priority-order; first to fire wins.
  HeartbeatClock (safety net, default 100ms): iterates open_positions;
    fires only time_stop + decay when N samples haven't arrived event-driven.
}

## 4.2 ConcurrentFill {
  On sell dispatch: state := closing, pending_sell:AtomicBool := true.
  Subsequent equal-or-lower-priority triggers IGNORED until pending resolves.
  Higher-priority preempts: new sell dispatched w/ higher compute-unit price
    (multiplier in config). Solana can't truly cancel — racing-with-fee
    is the only mechanism.
  On Confirmed prior tx: advance realised_frac/realised_sol, clear pending,
    re-eval exits.
  On Confirmed failure: clear pending, re-eval.
}

## 4.3 SlotCollisions {
  pos.apply records (slot, signature) of latest applied event.
  Drop later event if evt.slot < last_applied.slot (out of order).
  Same slot diff signature: apply if (slot,signature) hash sorts after last
    (deterministic tiebreak).
}

## 4.4 InsiderSetConstruction {
  Insider set captured ONCE at entry, frozen for position lifetime ⇒
    hot path checks `signer ∈ set` in O(1) without RPC.

  Set = {
    pool_event.signer  // submitted INIT/CREATE/MIGRATE/DEPOSIT
    mint_enrichment.deployer (if != #1)
    top-N initial holders from entry-burst enrichment:
      N = [strategy.buy_trigger].insider_capture_top_n (default 5)
      min_holding = .insider_capture_min_pct (default 0.01 = 1%)
      source = getTokenLargestAccounts snapshot at entry slot
      exclude: holders < min_pct, pool itself, bot's ATA, WSOL mint
  }

  Stored: in-mem `insider_set: HashSet<Pubkey>` (~≤7)
  Persisted: JSON array in positions.notes at v1 for replay/audit.

  trigger:
    if evt.event_kind == SELL
       && pos.insider_set.contains(evt.signer)
       && (evt.tokens_sold / enrich.supply) >= trigger.insider_pct {
      fire(SellReason::InsiderSell)
    }

  If largest-accounts query times out at entry-burst ⇒ fallback set =
    {signer, deployer}; log timeout. Snapshot runs in parallel —
    does NOT block entry (BuyTrigger has its own enrichment deps).
}

# 5. CrateInventory {
  liquid-snipe-rs/
    Cargo.toml  // workspace
    config.toml.example
    crates/
      liquid-snipe              // bin: hot loop owner, CLI, app wiring
      liquid-snipe-core         // types, config, DuckDB, risk, slippage
      liquid-snipe-stream       // gRPC + WS subs; decoders
      liquid-snipe-strategy     // BuyTrigger + SellTriggers + heartbeat eval
      liquid-snipe-simulator    // paper-mode fill model
      liquid-snipe-exec         // sol-trade-sdk wrapper buy/sell
}

## 5.1 bin liquid-snipe modules {
  main.rs                 runtime bootstrap, crypto provider install, CLI parse
  cli.rs                  clap subcommands: run (default), replay <sig>,
                          stats, migrate
  app.rs                  wires AppState + shared atomics; spawns bg tasks;
                          owns hot loop
  hot_loop.rs             async fn run(stream,state,strategy) -> !
  bg/blockhash.rs         refresher
  bg/wallet_balance.rs    polls getBalance + WSOL ATA on
                          [wallet].balance_refresh_ms; updates AtomicU64;
                          recomputes bankroll
  bg/enrichment.rs        speculative mint fetcher
  bg/heartbeat.rs         wall-clock tick: time_stop, decay fallback
  bg/housekeeping.rs      prune closed positions, expire enrichment
  bg/persistence.rs       drains crossbeam::channel<DbWrite> →
                          DuckDB batched inserts
  bg/confirmation_audit.rs  re-check fills at Confirmed, handle reverts
  bg/slippage_controller.rs tracks consecutive-failure window,
                            bumps slippage_bps atomic
  bg/config_reloader.rs   SIGHUP → reload TOML → swap source/SWQOS/strategy
  metrics.rs              structured logs, frame timing histogram
  stats.rs                stats subcommand output (text + JSON)
}

## 5.2 liquid-snipe-core {
  types.rs    ChainEvent, EventKind, Position, Fill, EnrichedMint, DexKey
  dexes.rs    DEX registry: program IDs, event kinds, decoder selector
  config.rs   TOML loader, {{helius}} expansion, validation, Config::reload
  wallet.rs   wallet loader (file path | WALLET_BASE58_ENV); fatal on
              missing in live
  db.rs       DuckDB connection, migrations, prepared statements
  risk.rs     RiskEngine::pre_entry_ok(plan, snapshot) -> Result<(),
              RejectReason> — bankroll-relative thresholds
  slippage.rs Controller: failure window, current bps, bump policy
  state.rs    AppState; DashMap<Pubkey,Position>, DashMap<Pubkey,EnrichedMint>
  consts.rs   WSOL, burn addresses
}

## 5.3 liquid-snipe-stream {
  source.rs        enum Source { Yellowstone, HeliusWs, Replay } →
                   Stream<Item=RawTx>; Source::reload(new_config) swaps endpoint
  yellowstone.rs   YellowstoneSource over yellowstone-grpc-client;
                   auto-reconnect w/ backoff
  helius_ws.rs     fallback
  replay.rs        reads recorded JSONL of past events for offline tests
  decoders.rs      per-DEX decode(raw_tx) -> Option<ChainEvent>.
                   Anchor decoders via carbon-*-decoder.
                   Legacy log-substring fallback for Raydium AMM v4
                   (initialize2, ray_log) and pump.fun snake_case discriminators.
  parser.rs        extract (base_mint, quote_mint, base_reserve,
                   quote_reserve, price) from decoded tx
}

## 5.4 liquid-snipe-strategy {
  buy_trigger.rs   BuyTrigger { filters: Vec<Filter> } with
                   evaluate(event, enrich, risk) -> BuyDecision
  filters.rs       enum Filter { EventKind, MinSolLiquidity, DexAllowlist,
                                  QuoteMints, RenouncedAuthorities, LpBurned,
                                  MaxTop10Concentration, MinHolderCount,
                                  MaxMarketCapSol, DeployerMaxPriorLaunches,
                                  DeployerBlocklist }   // each pure fn
  sell_triggers.rs enum SellTrigger { HardStop, Ladder, TrailingStop,
                                       LiquidityDrain, Decay, InsiderSell,
                                       TimeStop } w/ priority + evaluator
  evaluator.rs     Strategy::evaluate_buy / evaluate_exits; stable priority
  decay_ring.rs    in-memory ring of last N price samples per position
                   used by Decay
}

## 5.5 liquid-snipe-simulator {
  fill.rs   linear-impact slippage model + flat gas (configurable defaults)
  paper.rs  when mode=paper, exec routes here; same Fill shape as live
}

## 5.6 liquid-snipe-exec {
  client.rs       ExecClient holds Arc<TradingInfrastructure>
                  (sol-trade-sdk Method 2 shared infra) + Arc<Keypair>
  swqos.rs        builds Vec<SwqosConfig> from [[swqos]] — supports
                  default RPC, Jito, Temporal/Nozomi (hosted or self-hosted
                  via custom URL), ZeroSlot, FlashBlock, BlockRazor,
                  Astralane, NextBlock, SpeedLanding
  dex_params.rs   per-DEX TradeBuyParams/TradeSellParams builders.
                  PumpFun/PumpSwap event-derived;
                  Raydium AMM v4 / CPMM and Meteora DAMM v2 use
                  from_pool_address_by_rpc (prefetched by enrichment)
  buy.rs          async fn buy(plan, blockhash, slippage_bps, gas)->Result<Fill>
  sell.rs         async fn sell(pos, fraction, reason, blockhash,
                                slippage_bps, gas) -> Result<Fill>
  wsol_wrap.rs    wrap N SOL → WSOL ATA. Subcommand: `liquid-snipe wrap-sol
                  <amount>`. Runs once at boot if [wallet].auto_wrap_sol > 0.
}

## 5.7 DexMapping {
  pumpfun           → PumpFun       | PumpFunParams::from_dev_trade        // event-derived
  pumpswap          → PumpSwap      | PumpSwapParams::from_trade           // event-derived
  raydium-amm       → RaydiumAmmV4  | RaydiumAmmV4Params::from_pool_address_by_rpc // prefetch
  raydium-cpmm      → RaydiumCpmm   | RaydiumCpmmParams::from_pool_address_by_rpc  // prefetch
  meteora-damm-v2   → MeteoraDammV2 | MeteoraDammV2Params::from_pool_address_by_rpc// prefetch
  raydium-clmm | meteora-dlmm | orca-whirlpool → (no SDK support)
    capture & evaluate only; execution skipped with `signal:fired,exec:unsupported`
}

# 6. ConfigSchema (TOML) {

  [mode] default = "live"             // CLI flag wins

  [wallet]
    keypair_path        = "data/wallet.json"  // OR WALLET_BASE58_ENV
    keypair_env         = "WALLET_BASE58"
    auto_wrap_sol       = 0.0          // 0 = no wrap
    balance_refresh_ms  = 1000          // independent of [blockhash].refresh_ms

  [risk] {
    // Bankroll =
    //   wallet.lamports/1e9
    // + WSOL_ATA.balance
    // + Σ open_positions.realised_sol   (closed-rung proceeds from partial
    //                                    sells not yet spent on new entry)
    // Unrealised mark-to-market is NOT bankroll — tracked as "open exposure"
    //   against max_total_risk_pct.
    // Recomputed on boot + on every fill.
    max_total_risk_pct     = 50
    max_per_trade_risk_pct = 5
    max_daily_loss_pct     = 10
    max_open_positions     = 4
    min_wallet_sol_floor   = 0.05      // absolute SOL floor
  }

  [slippage]
    default_bps      = 300              // 3% starting
    max_bps          = 2500             // cap 25%
    bump_bps         = 1000             // +10% per bump
    fail_window_n    = 5                // consecutive failures
    fail_window_secs = 60               // failures only count within
    reset_on_success = true

  // Hot-swappable on SIGHUP:
  [grpc]
    enabled        = true
    endpoint       = "https://your-yellowstone.example.com:443"
    auth_token_env = "GRPC_AUTH_TOKEN"
  [grpc.fallback_ws]
    enabled  = true
    http_url = "{{helius}}"
    ws_url   = "{{helius}}"

  [rpc]
    http_url         = "{{helius}}"     // enrichment + blockhash + sol-trade-sdk
    commitment_hot   = "processed"
    commitment_audit = "confirmed"

  // [[swqos]] each maps 1:1 to sol-trade-sdk SwqosConfig variant.
  // Provide region (hosted) OR url (custom/self-hosted) per entry.
  [mev] mev_protection = false          // Astralane QUIC :9000 / BlockRazor

  [[swqos]] provider="default"; url="{{rpc.http_url}}"
  // [[swqos]] provider="jito"; uuid="..."; region="Frankfurt"
  // [[swqos]] provider="temporal"; api_token_env="TEMPORAL_API_TOKEN";
  //           region="Frankfurt"      // OR url for self-hosted
  // [[swqos]] provider="zeroslot"; api_token_env="ZEROSLOT_API_TOKEN";
  //           region="Frankfurt"
  // ... flashblock, blockrazor, astralane (transport="quic"), nextblock,
  //     speedlanding

  [gas]
    compute_unit_limit       = 500_000
    compute_unit_price_micro = 150_000
    priority_fee_sol_buy     = 0.001
    priority_fee_sol_sell    = 0.001
    preempt_fee_multiplier   = 2.0      // applied on higher-priority preempt

  [dexes]
    enabled = ["raydium-amm","raydium-cpmm","raydium-clmm",
               "orca-whirlpool","meteora-dlmm","meteora-damm-v2",
               "pumpfun","pumpswap"]

  [hot_loop]
    frame_warn_us = 1000                 // log if frame exceeds
    spawn_buffer  = 8                    // bounded executor concurrency

  [blockhash]   refresh_ms = 400
  [enrichment] {
    mint_ttl_sec        = 300
    deployer_ttl_sec    = 3600
    deployer_lookback   = 50
    required_timeout_ms = 800           // hold candidate waiting
  }
  [heartbeat]    tick_ms = 250          // time/decay fallback cadence
  [housekeeping] tick_sec = 30
  [persistence] {
    batch_max_rows = 256
    batch_max_ms   = 1000
    duckdb_path    = "data/liquid-snipe.duckdb"
  }
  [confirmation_audit] delay_ms = 7000  // wait after submit before re-check

  [strategy] id = "default"
  [strategy.buy_trigger] {
    event_kinds                    = ["INIT","MIGRATE"]
    min_sol_liquidity              = 10.0
    dex_allowlist                  = []    // empty = use [dexes].enabled
    quote_mints                    = ["WSOL"]
    require_renounced_authorities  = true
    require_lp_burned              = false
    max_top10_holder_concentration = 0.50
    min_holder_count               = 0
    max_market_cap_sol             = 0     // 0 = no cap
    deployer_max_prior_launches    = 0     // 0 = first-time; null = no limit
    deployer_blocklist_path        = "data/blocklist.json"
    enrichment_timeout_ms          = 800
    // Insider-set capture (§4.4); frozen at entry
    insider_capture_top_n          = 5
    insider_capture_min_pct        = 0.01
  }

  // Sell triggers — array order is priority on tie.
  [[strategy.sell_triggers]] kind="hard_stop"     stop_pct=-0.15
  [[strategy.sell_triggers]] kind="ladder"        rungs=[
                                                    {profit=0.10, sell=0.5 },
                                                    {profit=0.25, sell=0.25},
                                                    {profit=0.50, sell=0.25}]
  [[strategy.sell_triggers]] kind="trailing_stop" trail_pct=0.08
  [[strategy.sell_triggers]] kind="liquidity_drain" drain_pct=0.5
  [[strategy.sell_triggers]] kind="insider_sell"  insider_pct=0.10
  [[strategy.sell_triggers]] kind="decay"         samples_n=4
  [[strategy.sell_triggers]] kind="time_stop"     hold_sec=300

  [logging] level="info"; format="json"
}

## 6.1 Validation {
  - ≥1 filter on BuyTrigger; ≥1 SellTrigger
  - max_per_trade_risk_pct ≤ max_total_risk_pct
  - min_wallet_sol_floor > 0 in live mode
  - wallet keypair resolvable in live mode
  - {{helius}} → https://mainnet.helius-rpc.com/?api-key=$HELIUS_API_KEY
  - empty SWQOS list = fatal in live mode
}

# 7. AdaptiveSlippageController {

  struct Controller {
    base_bps:    u16
    current_bps: AtomicU16      // read by execute_buy
    max_bps:     u16
    bump_bps:    u16
    failures:    Mutex<VecDeque<Instant>>
    fail_window: Duration
    fail_threshold: usize
    reset_on_success: bool
  }

  Behaviour {
    on every buy: read current_bps → use as slippage_basis_points
    on failure (timeout|slippage-exceeded|SWQOS reject):
      record_failure(now); drop entries older than fail_window;
      if remaining ≥ fail_threshold:
        current_bps = min(current_bps + bump_bps, max_bps)
        clear failure deque
    on success:
      if reset_on_success: clear deque
      if current_bps > base_bps: decay one step toward base
    all transitions logged structurally + persisted to signal_decisions
      via risk_reason field for audit
  }
}

# 8. HotReload — SIGHUP {

  bg/config_reloader.rs handler:
    1. re-parse config.toml, validate
    2. diff: which sub-trees changed
    3. dispatch per changed tree:
       [grpc] | [grpc.fallback_ws] | [dexes] → Source::reload(new) (drop stream,
                                                reopen, in-flight drains)
       [[swqos]] | [mev]                    → rebuild Vec<SwqosConfig>;
                                              exec swaps (TradingInfrastructure
                                              rebuilt; in-flight tx use old
                                              until they finish)
       [slippage]                           → Controller::update(new)
       [gas] | [hot_loop] | [heartbeat] | [persistence] → atomic swap of
                                              relevant config struct
       [strategy] | [risk]                  → swap Arc<Strategy> &
                                              Arc<RiskProfile> in AppState.
                                              In-flight positions retain
                                              snapshot of their original
                                              SellTriggers (cloned at entry).
                                              New entries see new strategy.
                                              Logged.
    4. emit structured log per changed sub-tree

  Failures during reload (validation | reconnect) ⇒ leave old config, log error.

  InFlightSemantics — clone-at-entry is total. Every in-flight Position
    carries Arc<StrategySnapshot> taken when opened; hot loop evaluates
    against snapshot, not AppState.strategy.

  | reload change                          | in-flight | new |
  |-----------------------------------------|-----------|-----|
  | existing SellTrigger param changed     | no        | yes |
  | existing SellTrigger removed           | no        | yes |
  | new SellTrigger kind added             | no        | yes |
  | [risk] thresholds                      | yes for next entry-attempt's risk
                                             check; in-flight sizing locked | yes |
  | [strategy.buy_trigger]                 | n/a       | yes |
  | [slippage]                             | yes (global) | yes |
  | [gas] | [hot_loop] | [heartbeat]       | yes (runtime-global) | yes |
  | [grpc] | [[swqos]]                     | yes (substrate, not per-position) | yes |

  Retroactive trigger upgrade workflow = close & reopen:
    (a) `liquid-snipe close <position_id> --reason manual` (planned subcmd)
    (b) wait for existing triggers to fire naturally
  No mid-flight upgrade — would invalidate priority order + pending_sell SM.

  Reload log example:
    config-reload: strategy swapped (id=v3 → v4). Diff:
      added:    insider_sell { insider_pct=0.05 }
      modified: trailing_stop { trail_pct: 0.08 → 0.06 }
      removed:  none
    in-flight positions retained original strategy: 3
      - position a3w… (entry +12s)   strategy=v3
      ...
    new positions opened from now will use strategy v4
}

# 9. WorkspaceDeps {
  internal crates (path):
    liquid-snipe, -core, -stream, -strategy, -simulator, -exec

  Solana/trading:
    sol-trade-sdk = path "../../reference/sol-trade-sdk", v4.0.8
    solana-sdk    = "3.0"
    solana-client = "3.1"
    solana-program= "3.0"

  Carbon decoders ONLY (no Pipeline):
    carbon-core              = "0.12"
    carbon-raydium-amm-v4-decoder, -cpmm-decoder, -clmm-decoder,
    carbon-orca-whirlpool-decoder,
    carbon-meteora-dlmm-decoder, -damm-v2-decoder,
    carbon-pumpfun-decoder, carbon-pump-swap-decoder    = "0.12"

  Streaming:
    yellowstone-grpc-client = "5"
    yellowstone-grpc-proto  = "5"

  duckdb = "1" features=[bundled]

  Async:
    tokio="1" features=[full]
    tokio-util="0.7" features=[rt]
    futures="0.3"

  HotLoopPrimitives:
    dashmap="6", arc-swap="1", crossbeam-channel="0.5", parking_lot="0.12"

  ConfigReload:
    notify="6"               // optional file watcher
    signal-hook-tokio="0.3"

  CLI/serde:
    clap="4" features=[derive]; serde="1" features=[derive]; toml="0.8"
    tracing="0.1"; tracing-subscriber="0.3" features=[env-filter,json]
    dotenvy="0.15"

  Misc: clru="0.6", anyhow="1", thiserror="1",
        uuid="1" features=[v4,serde], chrono="0.4"

  // We DO NOT depend on carbon-yellowstone-grpc-datasource or
  // carbon-core::Pipeline (multi-stage shape rejected). Carbon decoders only.
}

# 10. Tests

## 10.1 Unit/property (liquid-snipe-strategy) {
  - Filter pure-fn tests w/ synthetic ChainEvent + EnrichedMint fixtures
    (in-test, no external files).
  - SellTrigger priority: Position + ChainEvent satisfying multiple ⇒
    highest-priority fires.
  - Concurrent-fill semantics: pending_sell=true + higher-priority trigger ⇒
    preempt sell dispatched w/ multiplied fee.
  - Decay ring: rolling-window correctness.
}

## 10.2 FrameBudgetRegression (liquid-snipe)
  Replay 10 000 synthetic gRPC updates through hot_loop::run, all bg stubbed.
  Assert p99 < 500µs, p99.9 < 1ms.  **CI gate (AC2)**.

## 10.3 PaperRoundTrip (liquid-snipe)
  Source::Replay of recorded chain events, full app in paper mode ⇒
  known fixture produces known positions+fills rows.

## 10.4 HotReload (liquid-snipe)
  Boot config A → SIGHUP → config B w/ different SellTrigger threshold +
  different SWQOS list. Assert gRPC reconnect, slippage controller picked
  up new params, in-flight position kept old triggers.

## 10.5 LiveTestWallet (manual, AC4)
  Operator-run only. Documented in docs/manual-tests.md.

# 11. OperationalNotes {
  WalletProvisioning: operator generates data/wallet.json
    (`solana-keygen new -o data/wallet.json`) OR sets WALLET_BASE58_ENV,
    funds it. Bot won't generate one. Boot fails fast on missing/invalid
    in live mode w/ clear message.
  WrapSOL: first time trading WSOL pairs needs WSOL ATA.
    `liquid-snipe wrap-sol <amount>` once, OR set [wallet].auto_wrap_sol.
  FirstRunMigration: `liquid-snipe migrate` creates DuckDB schema.
    Idempotent. See §11.1.
  Secrets: HELIUS_API_KEY, GRPC_AUTH_TOKEN, all SWQOS API tokens via env
    (dotenvy reads .env.local). Never logged.
  Shutdown: SIGINT → CancellationToken → drop stream → drain workers →
    final SELL every open position (reason=shutdown) → persistence drains →
    exit. 30s budget, force-exit on timeout.
  HotSwap: SIGHUP triggers reload (§8).
  Replay: `liquid-snipe replay <tx_signature>` reconstructs trail from
    chain_events, signal_decisions, positions, fills. Output §13.
}

## 11.1 SchemaEvolution — DuckDB versioned via _meta {

  _meta { key PK, value }
  // rows: schema_version (int monotonic), created_at (ISO-8601),
  //       binary_version (semver of liquid-snipe that last opened)

  MigrationFiles {
    location: crates/liquid-snipe-core/migrations/V<n>__<name>.sql
              (e.g. V1__initial.sql, V2__add_insider_set.sql)
    embedded via include_str!
    filenames immutable once released; new deltas always get higher V<n>
  }

  `liquid-snipe migrate` {
    1. open DuckDB file (create if missing)
    2. read _meta.schema_version (missing → 0)
    3. read binary's EXPECTED_SCHEMA_VERSION constant
    4. branch:
       DB == binary: no-op, exit 0 (idempotent, safe repeat)
       DB <  binary: apply each V<n>__*.sql for n in (db+1..=binary)
                     inside single tx per file; bump _meta.schema_version
                     after each successful file
       DB >  binary: FATAL — print
                     "error: DB at schema_version=N, this binary expects M
                      (M<N). Refusing to open. Use a newer binary."
                     exit 2. Do not open the DB.
  }

  ForwardOnly {
    Migrations append-only — can CREATE TABLE | ALTER TABLE ADD COLUMN |
      CREATE INDEX | CREATE VIEW | INSERT seed data.
    May NOT drop columns, drop tables, or rewrite existing rows lossily
      unless operator passes --force-destructive.
    Intent: data/liquid-snipe.duckdb is permanent history; schema evolves
      additively.
  }

  RunBootCheck {
    Every non-migrate subcommand opens DB r/w and verifies
      _meta.schema_version == EXPECTED_SCHEMA_VERSION.
    lower  → fail fast: "DB schema outdated. Run `liquid-snipe migrate`."
    higher → fatal as above.
    Bot NEVER auto-migrates on boot — schema changes are operator-acknowledged.
  }
}

# 12. StatsCommand
  `liquid-snipe stats [--window 24h] [--json]` → plain text default:

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
    Slippage:      300 bps base  →  current 300 bps  (no failures in 60s)
    Risk:          OK   (open 8% / 50% cap, daily +4.3% / -10% loss cap)
    Last reload:   2026-05-14 11:32:01 UTC  (changed: [strategy.sell_triggers],
                                              [grpc])

  --json emits same data structured for piping.

# 13. ReplayCommand
  `liquid-snipe replay <tx_signature> [--json]` reconstructs the full
    decision+execution trail for any tx the bot saw.
  tx_signature may be:
    (a) entry-trigger pool event
    (b) buy/sell fill
    (c) non-traded candidate rejected by filters/risk
  Joins chain_events, signal_decisions, positions (all versions), fills,
    mint_enrichment.

  Plain-text accept example:
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
                       require_renounced_authorities,
                       max_top10_holder_concentration,
                       deployer_max_prior_launches
      filters_failed:  []
      risk:            OK   open 8% / 50% cap   daily +4.3% / -10% loss cap
      size:            0.0420 SOL  (5.0% of bankroll 0.84 SOL)
    Buy fill:    submitted 2026-05-14 11:32:01.245   txSig 4xy…def
                 swqos    jito (frankfurt)             slippage 300 bps
                 confirmed 2026-05-14 11:32:01.598    +353ms
                 tokens 4.179e9   quote_filled 0.0420 SOL   fee 0.00128 SOL
    Position:    a3w…  v1→v6   state closed   age 41s
      v1  open     entry_price 1.005e-8   peak 1.005e-8
      v2  open     +1.2s   evt BUY   px 1.057e-8 +5.2%   peak 1.057e-8
      v3  open     +3.4s   evt BUY   px 1.087e-8 +8.1%   peak 1.087e-8
      v4  closing  +12.7s sell trigger=ladder rung 1   sold 0.50  reason ladder
      v5  closing  +15.3s sell trigger=trailing_stop   sold 0.50  reason trailing_stop
      v6  closed   +41.0s realised +0.0048 SOL  +11.4%
    Sells:       2 fills, total 4.179e9 tokens, total quote 0.0468 SOL
      ladder           0.50 frac   tx 7uV…111   slippage 300 bps   confirmed +12.9s
      trailing_stop    0.50 frac   tx 9wQ…222   slippage 300 bps   confirmed +15.5s
    Audit:       all fills confirmed at Confirmed commitment   no reverts

  Plain-text reject example:
    === liquid-snipe replay 8jZ…aaa ===
    Captured:    2026-05-14 11:33:14.001 UTC   slot 234568012
    DEX:         raydium-amm   pool …
    Event:       INIT          sol_value 3.2
    Enrichment:  cache cold (waited 800 ms, gave up)
    Decision:    REJECT
      filters_passed:  event_kinds, dex_allowlist, quote_mints
      filters_failed:  min_sol_liquidity (3.2 < 10.0),
                       require_renounced_authorities (cache cold:
                                                       enrichment-pending)
      risk:            (not evaluated)

  --json emits same structure w/ stable keys for piping.

# 14. BuildTestRun {
  cargo build --release
  cargo test --workspace
  cargo run -p liquid-snipe -- --config config.toml             // [mode].default
  cargo run -p liquid-snipe -- --config config.toml --paper     // CLI overrides
  cargo run -p liquid-snipe -- --config config.toml --observe
  cargo run -p liquid-snipe -- replay <txSignature>
  cargo run -p liquid-snipe -- stats --window 24h
  cargo run -p liquid-snipe -- wrap-sol 0.5                     // SOL→WSOL one-shot
  cargo run -p liquid-snipe -- migrate
}
```

## PROVIDERS.md

```sudolang
# liquid-snipe — Provider Research

Companion to PROJECT.md (OpenDecisions §) and SPEC.md (§5.6, §6, §11).
Resolves the two cost/latency-driving picks: gRPC stream and SWQOS.

Pricing as of **May 2026**. Tip floors and tiers move month-to-month —
re-verify before locking in.

OperatorProfile {
  location = NY                       // region picks bias to NYC PoPs
  usage    = not full-time            // goal: prove paper, trickle to live
  currentTier = Helius free; planning Triton PAYG ($125 entry) for real Yellowstone
  constraints {
    Don't pre-pay for predictable-cost infra (Helius Business, dedicated
      nodes) until expectancy is measured.
    Avoid the WS-fallback rung — SPEC's logsNotifications +
      per-candidate getTransaction adds 50–200ms/eval, kills the sniper.
  }
}

TLDR_DayOneStack {
  | layer              | pick                   | fixed/mo                     | per-tx variable                                    | why |
  |--------------------|------------------------|------------------------------|----------------------------------------------------|-----|
  | gRPC               | Triton One PAYG        | $125 prepay → ~$60–300/mo    | $0/call, $0.08/GB egress                           | Cheapest real-Yellowstone path; authors of yellowstone-grpc; NYC GeoDNS colocates operator |
  | RPC                | Helius free → Dev $49  | $0 (until rate-limited)      | $0                                                 | Already have it; upgrade only when free-tier RPS bites. Triton PAYG also covers RPC if consolidating. |
  | SWQOS slot 1       | Jito (NYC)             | $0                           | live tip floor (~0.0000025 SOL p50, ~0.000337 p99) | No account friction, only provider w/ bundles, lowest practical tip floor |
  | SWQOS slot 2       | 0slot.trade (NY)       | $0 (promo)                   | 0.0001 SOL (Advanced) / 0.001 (lower tiers)        | Parallel leg for fan-out, NY PoP, no approval gate |
  | SWQOS slot 3 (opt) | BlockRazor (NY)        | $0                           | 0.0001 SOL                                         | Best explicit anti-sandwich (sandwichMitigation + safeWindow) for fresh-pool buys |

  Totals {
    fixed_day_one    = $125 Triton prepay (consumed as you stream, not lost)
    recurring        = ~$60–300/mo metered Triton + $0 RPC (until Helius
                       free out) + variable SWQOS tips
    example_rate     = 50 trades/day × Jito p75 tip ≈ $0.06/day at SOL=$200
  }
}

CostLadder {
  Don't pay for predictable-cost infra until strategy proves itself.
  Triton PAYG aligns bill w/ usage — slow weeks cheap, hot weeks hot,
    no commitment to flat tier.

  | stack                                       | fixed/mo  | upgrade trigger |
  |---------------------------------------------|-----------|-----------------|
  | Triton PAYG + Helius free + Jito (NYC) ← start | ~$60–300 metered | —      |
  | + Helius Dev for RPC headroom               | +$49      | Helius free 429s on enrichment/blockhash under load |
  | + 0slot / BlockRazor parallel SWQOS legs    | +$0       | First evidence of buy-failure correlation w/ single-provider latency |
  | Swap Triton PAYG → Helius Business flat $499 | $499     | Triton metered consistently > ~$400/mo AND want predictable billing |
  | Self-host Yellowstone NYC (Latitude/Vultr)  | ~$800     | Monthly infra > $500/mo AND strategy profitably live full-time |
}

# 1. gRPCProviders
//   one stream, 8 DEX program IDs, processed commitment

  | provider                | min entry             | included                                                      | regions                                | latency                                              | auth          | gotcha |
  |-------------------------|-----------------------|---------------------------------------------------------------|----------------------------------------|------------------------------------------------------|---------------|--------|
  | Helius LaserStream      | $499/mo (Business)    | 100M credits, 200 RPC req/s, multi-region failover, replay   | US/EU/Asia (managed)                   | No published p99; managed gRPC ~few ms behind slot   | API key URL   | Bandwidth add-on +$400/mo at high stream volume; chatty filters (Pump.fun) hit fast |
  | Triton Dragon's Mouth   | $125 prepay (PAYG)    | gRPC+WS streaming, replay (Old Faithful), Fumarole HA        | AMS + NYC (GeoDNS) — matches operator  | Self-published: slot p90 ~5ms, account update p90 ~215ms | x-token   | $0.08/GB egress, $0/call streaming — ~$60–300/mo our filter. Region-pin requires Dedicated (~$2,900/mo) but GeoDNS routes NY→NYC. account_include_max default 10 (we need 8 — fits) |
  | Jito Shredstream        | $0 + your infra (~1 vCPU, ~few hundred Mbps) | Raw shred UDP, up to 2 regions     | AMS,DUB,FRA,LON,NYC,SLC,SGP,TYO        | Lowest-latency feed; arrives BEFORE block assembly   | Pubkey allowlist (Jito Discord) | Shreds not parsed tx — needs deshred→entry→tx→account-write resolution. Account state diffs not directly observable. Complement to Yellowstone, NOT substitute. |
  | Self-hosted Yellowstone | ~$800/mo (Latitude f4.metal.large, FRA) | Full RPC + geyser-grpc-plugin, 20TB egress pool | Anywhere bare-metal exists | Best — sub-ms plugin-to-consumer if colocated | You configure (x-token) | You now operate a Solana RPC node: monthly Agave releases, snapshots, peering, ~10–20 hr/mo sysadmin. Initial sync 6–24 hr. |

  Pick = Triton PAYG {
    $125 prepay unlocks self-serve Yellowstone gRPC metered $0.08/GB
      streaming, no per-call charge.
    For our 8-program filter ≈ $60–300/mo — materially cheaper than
      Helius Business flat $499.
    GeoDNS routes operator's NY traffic to NYC PoP ⇒ shared-tier latency
      fine, no need for dedicated region-pinning.
    Step up to Helius Business only when Triton metered consistently
      exceeds flat fee AND want billing predictability.
    Self-host = "strategy profitably full-time" decision, not day-one.
    Shredstream alone insufficient — delivers raw shreds, not parsed
      account writes the hot loop needs.
  }

# 2. SWQOSProviders
//   [[swqos]] array holds any combination; SDK parallel-submit, fastest wins.
//   cost = monthly subscription + per-tx tip floor × trade rate

  | provider     | monthly                   | min tip                                                    | regions                                            | transports                                                   | bundles                              | MEV-protect                                                       | self-host     | onboarding              | verdict |
  |--------------|---------------------------|------------------------------------------------------------|----------------------------------------------------|--------------------------------------------------------------|--------------------------------------|-------------------------------------------------------------------|---------------|-------------------------|---------|
  | Jito         | $0                        | 1k lamports floor; live p50 ~0.0000025 SOL, p99 ~0.000337  | AMS,DUB,FRA,LON,NYC,SLC,DAL,SGP,TYO                | HTTP, gRPC                                                   | YES (5-tx atomic, revert protect)    | default on single-tx                                              | no            | instant, no key         | **enable** |
  | 0slot.trade  | $0 (promo)                | 0.001 SOL (Trial/Entry/Inter) / 0.0001 SOL (Advanced)      | NY,LA,FRA,AMS,TYO                                  | HTTP staked_conn                                              | no                                   | claims best-in-class anti-sandwich                                | no            | Discord (kurt0slot) — friction | **enable** as 2nd leg |
  | BlockRazor   | $0                        | 0.0001 SOL (T0) / 0.001 SOL (T4–T1)                        | NY,FRA,AMS,LON,TYO                                 | HTTP, gRPC                                                   | no                                   | explicit sandwichMitigation + safeWindow                          | no            | API key                 | **enable** as 3rd leg for fresh-pool buys |
  | Astralane    | unpublished (sales)       | 0.00001 SOL (lowest)                                       | FRA×2,SF,TYO,NY,AMS×2,Limburg,SGP,Lithuania        | HTTP /iris, Binary /irisb, QUIC :7000 / :9000 (mev-protect)  | no                                   | port 9000 + mev-protect=true flag                                 | no            | sales contact           | **evaluate** — opaque price but best tech (persistent QUIC, lowest tip) |
  | Temporal/Nozomi | $0 (gated approval)    | 0.001 SOL (~1000× Jito floor)                              | PIT,EWR,IAD,LA,FRA,AMS,LON,TYO,SGP                 | HTTP                                                         | no                                   | optional Front-Running Protection (Helius/Coinbase only — slower) | enterprise-only | approval form         | **skip day one** — same floor as 0slot, no compensating advantage; only consider for US-east coverage 0slot lacks |
  | NextBlock    | $249/mo (Entry, 5 TPS)    | 0.001 SOL                                                  | NY,FRA,AMS,DUB,SLC,TYO,SGP,LON                     | HTTP                                                         | no                                   | not documented                                                    | no            | API key                 | **skip** — only one w/ mandatory sub, steep for solo |
  | FlashBlock   | unpublished (sales)       | 0.0001 SOL                                                 | NY,SLC,AMS,FRA,LON,SGP,TYO                         | HTTP                                                         | no                                   | claimed but no toggle documented                                  | no            | sales contact           | **skip** — no transparent pricing, no QUIC, weak MEV story |
  | SpeedLanding | private                   | 0.001 SOL                                                  | NYC,FRA,AMS,TYO,SGP                                | QUIC :17778 only                                             | no                                   | not documented                                                    | no            | wallet-pubkey-bound, contact via fnzero | **skip** — effectively private, no self-serve |

  PerTxCostIntuition (SOL = $200) {
    | floor                                              | $/tx   | $/100tx |
    |----------------------------------------------------|--------|---------|
    | 0.00001 SOL (Astralane)                            | $0.002 | $0.20   |
    | 0.0001 SOL (0slot Adv, BlockRazor T0, FlashBlock)  | $0.02  | $2.00   |
    | 0.0003 SOL (Jito p99 competitive)                  | $0.06  | $6.00   |
    | 0.001 SOL (Nozomi, NextBlock, 0slot lower)         | $0.20  | $20.00  |
  }

  SubscriptionVsTipMath: NextBlock loses for a solo wallet —
    $249/mo + $20/100tx vs Jito $0/mo + $6/100tx.
    NextBlock only wins above ~1500 tx/mo AND if 5 TPS rate limit matters —
      neither holds for our profile.

# 3. OpenQuestionsBeforeLockIn {

  1. JitoTipFloorStrategy:
     SPEC §6 has static [gas]. Need live-tip-floor poll
       (https://bundles.jito.wtf/api/v1/bundles/tip_floor) feeding buy
       executor — else underbid (no land) or overpay.
     Action: add small task neighborhood of bg/blockhash.rs that refreshes
       Jito tip percentile every N seconds; expose as
       AtomicU64 jito_tip_lamports. Default p75, configurable.

  2. AstralaneOnboarding:
     If pricing reasonable (~$2-3/mo indexing tier suggests sender plans
       similar) it's strongest tech: lowest tip floor, persistent QUIC
       eliminates handshake per submit, dedicated MEV-protect port.
     Action: request quote before committing to BlockRazor as 3rd leg.

  3. ZeroslotPromoEndDate:
     "Free!" flagged "NEW" — could revert. Validate on re-check.

  4. NozomiForUsEastCoverage:
     If US-east leader slots matter (verify via slot-vs-region analysis
       once live), Nozomi's PIT/EWR/IAD PoPs are only ones in providers
       we'd use. Cost = same 0.001 SOL floor as 0slot Trial.

  5. SelfHostedYellowstoneBreakeven:
     Not relevant until strategy profitably full-time.
     Trigger to revisit: monthly infra already > $500/mo AND live PnL
       justifies ~10–20 hr/mo ops burden.
     Spec the box in NYC (Latitude m3.large.x86 or comparable) — same
       region as operator and most NY-side leader stake.

  6. TritonBandwidthCeiling:
     PAYG bills overage at same base rate ($0.08/GB) — no cliff. But a
       runaway filter (e.g. accidentally subscribing to chatty system
       program) could rack a surprise bill.
     Set budget alert in Triton console; cap filter to 8 confirmed DEX
       program IDs; validate egress for first week.
}

# 4. Citations

  gRPC {
    Helius pricing               https://www.helius.dev/pricing
    Helius LaserStream docs      https://www.helius.dev/docs/grpc
    Triton Dragon's Mouth        https://docs.triton.one/project-yellowstone/dragons-mouth-grpc-subscriptions
    Triton blog (latency, bw)    https://blog.triton.one/complete-guide-to-solana-streaming-and-yellowstone-grpc/
    Jito Shredstream docs        https://docs.jito.wtf/lowlatencytxnfeed/
    Shredstream proxy            https://github.com/jito-labs/shredstream-proxy
    Latitude bare-metal pricing  https://www.latitude.sh/blog/the-best-servers-for-solana-rpc-and-validator-nodes
    yellowstone-grpc plugin      https://github.com/rpcpool/yellowstone-grpc
  }

  SWQOS {
    Jito low-latency tx send     https://docs.jito.wtf/lowlatencytxnsend/
    Jito mainnet addresses       https://jito-labs.gitbook.io/mev/searcher-resources/block-engine/mainnet-addresses
    Jito rate limits             https://jito-labs.gitbook.io/mev/searcher-resources/json-rpc-api-reference/rate-limits
    Jito live tip floor          https://bundles.jito.wtf/api/v1/bundles/tip_floor
    Nozomi endpoints             https://use.temporal.xyz/nozomi/endpoints
    Nozomi tipping & FAQ         https://use.temporal.xyz/nozomi/tipping-and-faq
    0slot.trade                  https://0slot.trade/ , https://0slot.trade/docs.php
    BlockRazor docs              https://blockrazor.gitbook.io/blockrazor
    BlockRazor latency benchmark https://www.blockrazor.io/blog/20250826e2etest/
    Astralane docs               https://astralane.gitbook.io/docs
    Astralane QUIC submission    https://astralane.gitbook.io/docs/low-latency/submit-transactions/quic-transaction-submission
    NextBlock pricing            https://docs.nextblock.io/pricing-and-rate-limits
    FlashBlock                   https://flashblock.trade/ , https://doc.flashblock.trade/
    sol-trade-sdk SWQOS source   reference/sol-trade-sdk/src/constants/swqos.rs
  }
```
