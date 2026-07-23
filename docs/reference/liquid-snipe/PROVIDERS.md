# liquid-snipe — Provider Research

Companion to `PROJECT.md` (Open decisions §) and `SPEC.md` (§5.6, §6, §11).
Resolves the two cost/latency-driving picks: **gRPC stream** and **SWQOS**.

Pricing as of **May 2026**. Tip floors and subscription tiers move
month-to-month — re-verify before locking in.

---

## Operator profile (drives every pick below)

- **Located in NY.** All region picks bias to NYC PoPs.
- **Not running full-time.** Goal is to prove strategy works on paper, then
  trickle into live. Don't pre-pay for predictable-cost infra (Helius
  Business, dedicated nodes) until expectancy is measured.
- **Currently on Helius free tier**; planning to add Triton PAYG ($125 entry)
  for real Yellowstone gRPC.
- **Avoid the WS-fallback rung** — the SPEC's `logsNotifications` + per-candidate
  `getTransaction` path adds 50–200 ms per evaluation, which kills the
  whole point of building a sniper.

## TL;DR — Recommended day-one stack

| layer                   | pick                | monthly fixed                                   | per-tx variable                                        | why                                                                                                 |
| ----------------------- | ------------------- | ----------------------------------------------- | ------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| gRPC                    | **Triton One PAYG** | **$125 prepay** → ~$60–300/mo metered after     | $0 per call, $0.08/GB egress                           | Cheapest real-Yellowstone path. Authors of yellowstone-grpc. **NYC GeoDNS** = colocated to your IP. |
| RPC (enrichment, blockhash, simulator) | **Helius free** (until rate-limited) → Helius Dev $49 if needed | **$0**          | $0                                                     | You already have it; only upgrade when free-tier RPS bites. Triton PAYG also covers RPC if you'd rather consolidate. |
| SWQOS slot 1            | **Jito (NYC)**      | $0                                              | live tip floor (~0.0000025 SOL p50, ~0.000337 SOL p99) | No account friction, only provider with bundles, lowest practical tip floor.                        |
| SWQOS slot 2            | **0slot.trade (NY)**| $0 (promo)                                      | 0.0001 SOL (Advanced) / 0.001 SOL (lower tiers)        | Parallel leg for fan-out, NY PoP, no approval gate.                                                 |
| SWQOS slot 3 (optional) | **BlockRazor (NY)** | $0                                              | 0.0001 SOL                                             | Best explicit anti-sandwich (`sandwichMitigation` + `safeWindow`) for fresh-pool buys.              |

**Total day-one fixed: $125 Triton prepay** (consumed as you stream, not lost).
**Recurring: ~$60–300/mo metered Triton, $0 RPC** (until Helius free runs
out), variable SWQOS tips. At 50 trades/day with Jito p75 tip ≈ $0.06/day
at SOL=$200.

### Cost ladder — when to step up, not where to start

| stack                                                 | monthly fixed                 | upgrade trigger                                                                  |
| ----------------------------------------------------- | ----------------------------- | -------------------------------------------------------------------------------- |
| **Triton PAYG + Helius free + Jito (NYC)** ← *start here* | **~$60–300 metered**      | —                                                                                |
| + Helius Dev for RPC headroom                         | **+$49**                      | Helius free 429s on enrichment / blockhash refresh under sustained load          |
| + 0slot / BlockRazor as parallel SWQOS legs           | **+$0**                       | First evidence of buy-failure correlation with single-provider latency           |
| Swap Triton PAYG → Helius Business (flat $499)        | **$499**                      | Triton metered consistently above ~$400/mo AND you want predictable billing      |
| Self-host Yellowstone in NYC (Latitude/Vultr)         | **~$800**                     | Monthly infra costs already > $500 AND strategy is profitably live full-time     |

The point: don't pay for predictable-cost infra until the strategy proves
itself. Triton PAYG aligns the bill with usage — slow weeks cost less,
hot weeks cost more, no commitment to a flat tier.

---

## 1. gRPC providers (one stream, 8 DEX program IDs, processed commitment)

| provider                    | min entry                                        | included                                                      | regions                                | latency story                                                    | auth                                      | gotcha                                                                                                                                                                         |
| --------------------------- | ------------------------------------------------ | ------------------------------------------------------------- | -------------------------------------- | ---------------------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Helius LaserStream**      | **$499/mo** (Business)                           | 100M credits, 200 RPC req/s, multi-region failover, replay    | US/EU/Asia (managed)                   | No published p99; managed gRPC ~few ms behind slot               | API key in URL                            | Bandwidth add-on **+$400/mo** at high stream volume; chatty filters (Pump.fun) hit it fast                                                                                     |
| **Triton Dragon's Mouth**   | **$125 prepay** (PAYG, metered after)            | gRPC + WS streaming, replay (Old Faithful), Fumarole HA       | AMS + NYC (GeoDNS) — **NYC matches operator**  | Self-published: slot p90 **~5 ms**, account update p90 ~215 ms   | x-token header                            | **$0.08/GB egress, $0/call for streaming** — ~$60–300/mo for our 8-program filter. Region-pinning requires Dedicated (~$2,900/mo) but GeoDNS already routes NY traffic to NYC. `account_include_max` default 10 (we need 8 — fits) |
| **Jito Shredstream**        | **$0** + your infra (~1 vCPU, ~few hundred Mbps) | Raw shred UDP, up to 2 regions                                | AMS, DUB, FRA, LON, NYC, SLC, SGP, TYO | Lowest-latency feed on Solana; arrives **before** block assembly | Pubkey whitelist (apply via Jito Discord) | **Shreds, not parsed tx** — needs deshred → entry → tx → account-write resolution. Account state diffs not directly observable. **Complement to Yellowstone, not substitute.** |
| **Self-hosted Yellowstone** | **~$800/mo** (Latitude f4.metal.large, FRA)      | Full RPC + geyser-grpc-plugin, 20 TB egress pool              | Anywhere bare-metal exists             | Best possible — sub-ms plugin-to-consumer if colocated           | You configure (typically x-token)         | You now operate a Solana RPC node: monthly Agave releases, snapshots, peering, ~10–20 hr/mo sysadmin. Initial sync 6–24 hr.                                                    |

**Pick: Triton PAYG.** $125 prepay unlocks self-serve Yellowstone gRPC
metered at $0.08/GB streaming with no per-call charge — for our 8-program
filter that's ~$60–300/mo, materially cheaper than Helius Business at $499
flat. **GeoDNS routes the operator's NY traffic to the NYC PoP**, so
shared-tier latency is fine for NY-based operation; no need to chase
dedicated region-pinning. Step up to Helius Business only when Triton
metered consistently exceeds the flat fee AND you want billing
predictability. Self-hosting is a "strategy is profitably full-time"
decision, not a day-one one. Shredstream alone is **insufficient** — it
delivers raw shreds, not the parsed account writes we need for the hot
loop.

---

## 2. SWQOS providers

The bot's `[[swqos]]` array can hold any combination; concurrent multi-provider
sends use the SDK's parallel-submit path (fastest wins). The cost equation
is **monthly subscription + per-tx tip floor × trade rate**.

| provider            | monthly fee                | min tip                                                               | regions                                            | transports                                                          | bundles                               | MEV-protect                                                       | self-host       | onboarding                              | verdict                                                                                                           |
| ------------------- | -------------------------- | --------------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------- | ----------------------------------------------------------------- | --------------- | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **Jito**            | $0                         | **1k lamports floor**, but live p50 ~0.0000025 SOL, p99 ~0.000337 SOL | AMS, DUB, FRA, LON, NYC, SLC, DAL, SGP, TYO        | HTTP, gRPC                                                          | **Yes (5-tx atomic, revert protect)** | default on single-tx                                              | no              | instant, no key required                | **enable**                                                                                                        |
| **0slot.trade**     | $0 (promo)                 | 0.001 SOL (Trial/Entry/Inter) / **0.0001 SOL (Advanced)**             | NY, LA, FRA, AMS, TYO                              | HTTP `staked_conn`                                                  | no                                    | claimed best-in-class anti-sandwich                               | no              | Discord (`kurt0slot`) — friction        | **enable** as 2nd leg                                                                                             |
| **BlockRazor**      | $0                         | 0.0001 SOL (T0) / 0.001 SOL (T4–T1)                                   | NY, FRA, AMS, LON, TYO                             | HTTP, gRPC                                                          | no                                    | **explicit `sandwichMitigation` + `safeWindow`**                  | no              | API key                                 | **enable** as 3rd leg for fresh-pool buys                                                                         |
| **Astralane**       | unpublished (sales)        | **0.00001 SOL** (lowest)                                              | FRA×2, SF, TYO, NY, AMS×2, Limburg, SGP, Lithuania | HTTP `/iris`, Binary `/irisb`, **QUIC :7000 / :9000 (mev-protect)** | no                                    | port 9000 + `mev-protect=true` flag                               | no              | sales contact required                  | **evaluate** — opaque price but tech is best-in-class (persistent QUIC, lowest tip)                               |
| **Temporal/Nozomi** | $0 (gated approval)        | **0.001 SOL** (~1000× Jito floor)                                     | PIT, EWR, IAD, LA, FRA, AMS, LON, TYO, SGP         | HTTP                                                                | no                                    | optional Front-Running Protection (Helius/Coinbase only — slower) | enterprise-only | approval form                           | **skip day one** — same floor as 0slot, no compensating advantage; only consider for US-east coverage 0slot lacks |
| **NextBlock**       | **$249/mo** (Entry, 5 TPS) | 0.001 SOL                                                             | NY, FRA, AMS, DUB, SLC, TYO, SGP, LON              | HTTP                                                                | no                                    | not documented                                                    | no              | API key                                 | **skip** — only one with mandatory subscription, steep for solo wallet                                            |
| **FlashBlock**      | unpublished (sales)        | 0.0001 SOL                                                            | NY, SLC, AMS, FRA, LON, SGP, TYO                   | HTTP                                                                | no                                    | claimed but no toggle documented                                  | no              | sales contact                           | **skip** — no transparent pricing, no QUIC, weak MEV story, obscure                                               |
| **SpeedLanding**    | private                    | 0.001 SOL                                                             | NYC, FRA, AMS, TYO, SGP                            | QUIC :17778 only                                                    | no                                    | not documented                                                    | no              | wallet-pubkey-bound, contact via fnzero | **skip** — effectively private, no self-serve onboarding                                                          |

### Per-tx cost intuition (SOL = $200)

| floor                                             | $/tx   | $/100 tx |
| ------------------------------------------------- | ------ | -------- |
| 0.00001 SOL (Astralane)                           | $0.002 | $0.20    |
| 0.0001 SOL (0slot Adv, BlockRazor T0, FlashBlock) | $0.02  | $2.00    |
| 0.0003 SOL (Jito p99, competitive)                | $0.06  | $6.00    |
| 0.001 SOL (Nozomi, NextBlock, 0slot lower tiers)  | $0.20  | $20.00   |

The **subscription-vs-tip math** is what kills NextBlock for a solo wallet:
$249/mo + $20 per 100 tx vs. Jito's $0/mo + $6 per 100 tx. NextBlock only
wins if you're routinely above ~1500 tx/mo _and_ their 5 TPS rate limit
matters — neither holds for our profile.

---

## 3. Open questions before locking in

1. **Jito tip-floor strategy.** SPEC §6 has `[gas]` static fields. We need a
   live-tip-floor poll (`https://bundles.jito.wtf/api/v1/bundles/tip_floor`)
   feeding the buy executor — otherwise we either underbid (no land) or
   overpay. **Action:** add a small task to `bg/blockhash.rs` neighborhood
   that refreshes the Jito tip percentile every N seconds and exposes it as
   `AtomicU64 jito_tip_lamports`. Probably p75 by default, configurable.

2. **Astralane onboarding.** If pricing turns out to be reasonable (~$2-3/mo
   indexing tier suggests sender plans are similar), it's the strongest
   tech pick: lowest tip floor, persistent QUIC eliminates handshake on
   every submit, dedicated MEV-protect port. **Action:** request a quote
   before committing to BlockRazor as the third leg.

3. **0slot promo end date.** "Free!" is flagged "NEW" — could revert any
   time. Validate when re-checking pricing.

4. **Nozomi for US-east coverage.** If we discover that US-east leader slots
   matter (verify by slot-vs-region analysis once live), Nozomi's PIT/EWR/IAD
   PoPs are the only ones in the providers we'd use. Cost is the same
   0.001 SOL floor as 0slot Trial.

5. **Self-hosted Yellowstone break-even.** Not relevant until the strategy
   is profitably full-time. Trigger to revisit: monthly infra costs already
   above $500/mo AND live PnL justifies the ~10–20 hr/mo ops burden. Spec
   the box in NYC (Latitude `m3.large.x86` or comparable) — same region as
   the operator and most NY-side leader stake.

6. **Triton bandwidth ceiling.** PAYG bills overage at the same base rate
   ($0.08/GB), so there's no cliff — but a runaway filter (e.g.,
   accidentally subscribing to a chatty system program) could rack up a
   surprise bill. Set a budget alert in Triton console; cap the filter to
   the 8 confirmed DEX program IDs and validate egress for the first week.

---

## 4. Citations

### gRPC

- Helius pricing: https://www.helius.dev/pricing — Business $499 unlocks mainnet LaserStream
- Helius LaserStream docs: https://www.helius.dev/docs/grpc
- Triton Dragon's Mouth: https://docs.triton.one/project-yellowstone/dragons-mouth-grpc-subscriptions
- Triton blog (latency, bandwidth model): https://blog.triton.one/complete-guide-to-solana-streaming-and-yellowstone-grpc/
- Jito Shredstream docs: https://docs.jito.wtf/lowlatencytxnfeed/
- Shredstream proxy: https://github.com/jito-labs/shredstream-proxy
- Latitude bare-metal pricing: https://www.latitude.sh/blog/the-best-servers-for-solana-rpc-and-validator-nodes
- yellowstone-grpc plugin: https://github.com/rpcpool/yellowstone-grpc

### SWQOS

- Jito low-latency tx send: https://docs.jito.wtf/lowlatencytxnsend/
- Jito mainnet addresses: https://jito-labs.gitbook.io/mev/searcher-resources/block-engine/mainnet-addresses
- Jito rate limits: https://jito-labs.gitbook.io/mev/searcher-resources/json-rpc-api-reference/rate-limits
- Jito live tip floor: https://bundles.jito.wtf/api/v1/bundles/tip_floor
- Nozomi endpoints: https://use.temporal.xyz/nozomi/endpoints
- Nozomi tipping & FAQ: https://use.temporal.xyz/nozomi/tipping-and-faq
- 0slot.trade: https://0slot.trade/ , https://0slot.trade/docs.php
- BlockRazor docs: https://blockrazor.gitbook.io/blockrazor
- BlockRazor latency benchmark: https://www.blockrazor.io/blog/20250826e2etest/
- Astralane docs: https://astralane.gitbook.io/docs
- Astralane QUIC submission: https://astralane.gitbook.io/docs/low-latency/submit-transactions/quic-transaction-submission
- NextBlock pricing: https://docs.nextblock.io/pricing-and-rate-limits
- FlashBlock: https://flashblock.trade/ , https://doc.flashblock.trade/
- sol-trade-sdk SWQOS source of truth: `reference/sol-trade-sdk/src/constants/swqos.rs`
