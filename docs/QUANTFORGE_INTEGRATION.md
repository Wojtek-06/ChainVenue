# CLOB book feed ↔ ChainVenue

**QuantForge (Project 1) is done.** ChainVenue treats it as a finished sibling that *can* emit book metrics; this repo does **not** modify QuantForge and does not block on further QF work.

Day-to-day ChainVenue development uses **synthetic / JSON** snapshots with the same field shape (`mid`, `inventory`, …).

## What QuantForge provides (reference)

| QuantForge piece | Use in ChainVenue |
|------------------|-------------------|
| C++ LOB matching + queue position | Fair mid / microprice / inventory inputs |
| Avellaneda–Stoikov-style quoting | Cross-venue quote skew vs AMM implied price |
| Kill switch / risk gates | Shared semantics with `KillSwitch` + `CrossVenueAdapter` |
| Python research API (`quantforge`, FastAPI) | Feed `BookSnapshot` into `ClobVenueStub` |

## On-chain surfaces

- `IClobVenue` / `ClobVenueStub` — normalized book snapshot
- `KillSwitch` — guardian-gated halt
- `CrossVenueAdapter` — basis check, inventory/gas/slippage/profit guards, **executes** `swapExactIn`
- Hedge only when `|AMM spot − CLOB mid| ≥ minBasisBps` and direction matches the rich AMM leg

### Mid convention

`BookSnapshot.mid` = **token1 per token0**, 1e18-scaled (WAD).  
AMM spot = `reserve1 * 1e18 / reserve0`.

| Basis | Meaning | Hedge side |
|-------|---------|------------|
| `ammSpot > mid` (positive) | AMM overvalues token0 | Sell token0 on AMM |
| `ammSpot < mid` (negative) | AMM undervalues token0 | Sell token1 on AMM |

## Off-chain bridge (`python/bridge/`)

```bash
cd python
python -c "from bridge import BookSnapshot, decide_hedge; \
snap=BookSnapshot.from_mid(mid=int(0.95e18), ts=1700000000); \
print(decide_hedge(reserve0=10**20, reserve1=10**20, fee_bps=30, snap=snap, amount_in=10**18, now_ts=1700000000))"
```

Push a snapshot to Anvil (command builder only — review before running):

```python
from bridge import BookSnapshot, cast_push_snapshot_cmd
snap = BookSnapshot.from_mid(mid=10**18, ts=1700000000, inventory_base=0)
print(cast_push_snapshot_cmd("0xYourClobStub", snap, private_key="0x..."))
```

Optional mapping from QuantForge sim metrics → `BookSnapshot` fields (`mid`, `microprice`, `inventory_base`, `ts`) uses the same JSON shape; a live daemon is out of scope for this lab.

## E2E demo (misprice → hedge → P&L)

```bash
# Offline (CI-safe) — synthetic / JSON QuantForge-shaped mid
cd python
python demo/e2e_hedge.py sim --mid 0.95 --no-native
python demo/e2e_hedge.py sim --json fixtures/qf_metrics_sample.json --no-native

# Local Anvil
anvil   # terminal A
# terminal B:
forge script script/DemoHedge.s.sol:DemoHedgeScript --rpc-url http://127.0.0.1:8545 --broadcast -vv
# or:
python demo/e2e_hedge.py anvil

# Synthetic snapshot feed (optional cast push once you have a clob stub address)
python demo/e2e_hedge.py feed --steps 3
python demo/e2e_hedge.py feed --steps 1 --clob-stub 0xYourClobStub
```

`python/bridge/quantforge_feed.py` maps QuantForge-like JSON (`mid` / `inventory` / …) and will use native `quantforge` if that package is importable — never required.

## ChainVenue lab status

This repo is a **portfolio-complete lab demo**. Shipped:

1. Foundry lab + CPAMM + Python differential + CLOB stub feed
2. Guarded hedge execution + Python quote engine + adversarial sims
3. Snapshot feed + E2E sim / Anvil `DemoHedge` (gross + gas-net logs)
4. Two-pool arb executor + oracle lab + IL sandbox
5. Inclusion / reorg sims + evidence pack (swap walkthrough, adversarial table, CI, dashboard)

## Non-goals

- Rewriting the LOB inside Solidity
- Live QuantForge snapshot daemon (synth/JSON mids are enough)
- Live mainnet MEV / sandwiches against real users
