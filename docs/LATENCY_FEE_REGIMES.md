# Latency & fee regimes

How ChainVenue thinks about timing and fees when deciding a hedge.

## Fee stack

| Layer | Default (lab) | Effect |
|-------|---------------|--------|
| AMM swap fee | 30 bps | Reduces `amountOut` via fee-on-input |
| Gas | `gas_used × gas_price` | Subtracted for **net** P&L |
| CLOB fees | QuantForge sibling | Not on-chain; mid comes from synth/JSON |

Gross edge = `amountOut − fairOut` at CLOB mid.  
Net edge = gross − gas (and any explicit priority fee in Anvil demos).

## Latency regimes (decision → inclusion)

| Regime | Model | Hedge behaviour |
|--------|-------|-----------------|
| **Instant** | Offline `e2e_hedge.py sim` | Decision and fill same step; upper bound on edge |
| **Anvil local** | `DemoHedge.s.sol` | One-block inclusion; gas logged; no competing searchers |
| **Stale mid** | Old QuantForge JSON / low `ts` freshness | Quote engine / oracle freshness rejects or widens |
| **Toxic flow** | Mid jumps against inventory | Inventory skew shrinks size; kill switch if limits breach |

## Basis thresholds

`decide_hedge` requires basis above a minimum (bps) and correct side vs pool mid. Inventory skew scales `amount_in` down when base inventory is large. Profit guard rejects hedges that would lose vs fair after slippage bounds.

## Demo knobs

```bash
# Cheap gas → more net-positive hedges
python demo/e2e_hedge.py sim --mid 0.95 --no-native

# Ledger across mids (for dashboard)
python demo/e2e_hedge.py ledger --out web/dashboard/metrics_ledger.json --no-native
```

Anvil: bump `gasPrice` in the script env / cast flags to see net edge flip negative while gross stays positive—good interview talking point.
