# ChainVenue evidence pack

Placement demos for Project 2 (CLOB–AMM / Foundry). QuantForge is a **done sibling**; use synth/JSON mids.

## Generate artefacts

```bash
# Full Forge suite (fuzz + invariant + adversarial)
forge test -vv

# Offline hedge economics (gross + gas-net)
cd python
python demo/e2e_hedge.py sim --mid 0.95 --no-native

# Anvil end-to-end
anvil   # terminal A
forge script script/DemoHedge.s.sol:DemoHedgeScript --rpc-url http://127.0.0.1:8545 --broadcast -vv
```

## Swap trace walkthrough (interview)

1. **Calldata** — `swapExactIn(tokenIn, amountIn, minOut, to)` selector + ABI args (`cast sig` / Forge `-vvvv`).
2. **Memory** — fee-on-input math in `getAmountOut` (no SSTORE yet).
3. **External token calls** — `transferFrom` then optimistic `transfer` out.
4. **Storage** — `_update` writes `reserve0` / `reserve1` / `blockTimestampLast` (packed `uint112` slots).
5. **Events** — `Swap` + `Sync` for indexing / reconciliation.
6. **Guards** — `InvalidK` if balances violate constant-product after fee adjustment.

Lab companions: `docs/EVM_LAB.md`, `forge test --match-contract EvmStorageLabTest -vvvv`.

## Adversarial report (local / Anvil only)

| Case | Test | Result |
|------|------|--------|
| Sandwich ordering | `SandwichSimTest` | `minAmountOut` protects victim; unguarded fill worse |
| Fee-on-transfer ERC-20 | `WeirdERC20Test` | swap reverts (`InvalidK` / transfer accounting) |
| Reentrancy vault | `ReentrancyLabTest` / `EvmLabTest` | vulnerable drains; safe CEI+lock holds |
| Oracle / mid manipulation | `SpotOracleTest` | owner can set price; `profit_guard` still blocks absurd floors |
| Kill switch | adapter + arb executor tests | hedges/arbs halt when tripped |

**Non-goal:** extractive live MEV against real users.

## Demo script (~5 min)

1. Architecture — README / `docs/AMM_SANDBOX.md`.
2. EVM lab — packed slot + calldata vs memory gas.
3. CPAMM invariant — `k` non-decreasing under fee-on-input swaps.
4. Misprice → hedge — `DemoHedge` / `e2e_hedge.py sim` (basis bps, gross vs fair, gas-net).
5. Two-pool arb — `AtomicArbExecutor` + Python `search_two_pool_arb`.
6. Adversarial table above + CI badge.

## CI

[![CI](https://github.com/Wojtek-06/ChainVenue/actions/workflows/ci.yml/badge.svg)](https://github.com/Wojtek-06/ChainVenue/actions/workflows/ci.yml)
