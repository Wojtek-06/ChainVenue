# AMM research sandbox (ChainVenue-only)

QuantForge (Project 1) is **done** as a sibling. ChainVenue continues with its own AMM / oracle / arb lab; CLOB mids come from **synthetic or JSON** book snapshots (same shape as a finished QuantForge feed — no QF code changes required).

## Components

| Piece | Location |
|-------|----------|
| CPAMM | `src/amm/ConstantProductAMM.sol` |
| Python differential | `python/reference/cpamm.py` |
| IL / LP vs HODL | `python/reference/il_sim.py` |
| Two-pool arb search | `python/reference/two_pool_arb.py` |
| Atomic arb executor | `src/exec/AtomicArbExecutor.sol` |
| Spot oracle (trust assumptions) | `src/oracle/SpotOracle.sol` |
| Cross-venue hedge | `src/adapters/CrossVenueAdapter.sol` |

## Oracle assumptions

`SpotOracle` is **owner-settable**. That is intentional for the lab:

- Demonstrates stale-price risk (`maxAge` / `isFresh`)
- Demonstrates manipulation: owner can push an arbitrary `priceWad`
- Hedge path must not rely on oracle honesty alone — ChainVenue uses CLOB mid + AMM spot + **profit / slippage / basis** guards

## Two-pool arb (local only)

```bash
cd python
python -c "from reference import PoolState, search_two_pool_arb; \
print(search_two_pool_arb(PoolState(10**23,10**23), PoolState(8*10**22,12*10**22), max_in=10**21))"
```

On-chain (Anvil): deploy two pools with divergent reserves → `AtomicArbExecutor.executeTwoPool`.

**Non-goal:** extractive live MEV against real users.

## IL quick check

```bash
cd python
python -c "from reference import simulate_il; print(simulate_il(10**20,10**20, price_ratio=2.0))"
```
