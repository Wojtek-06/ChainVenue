# ChainVenue

[![CI](https://github.com/Wojtek-06/ChainVenue/actions/workflows/ci.yml/badge.svg)](https://github.com/Wojtek-06/ChainVenue/actions/workflows/ci.yml)

Cross-venue **CLOB–AMM** laboratory: Foundry-tested EVM mechanics + constant-product AMM, with a stub adapter toward [QuantForge](https://github.com/Wojtek-06/QuantForge)’s off-chain limit-order-book MM stack (**Project 1 done** — this repo uses synth/JSON book mids).

> Placement pitch: *I understand CLOB vs AMM economics and can ship Foundry-tested contracts with operational risk controls—on Anvil/fork only, not extractive live MEV.*

**Local path:** `C:\Projekty\Quant\ChainVenue`  
**Safety:** local Anvil / fork / testnet-only. No mainnet deploys with real funds. See [`docs/ANVIL.md`](docs/ANVIL.md).

---

## Architecture

```
┌─────────────────────┐     fair price / inventory      ┌──────────────────────┐
│ CLOB adapter        │◄────────────────────────────────┤ Quote & hedge engine │
│ (QuantForge venue)  │   IClobVenue snapshots (later)  │ (Python + C++ hooks) │
└─────────────────────┘                                 └──────────┬───────────┘
                                                                   │
┌─────────────────────┐     pool state / events                    │
│ AMM + exec contracts│◄───────────────────────────────────────────┤
│ (Solidity / Foundry)│     ICrossVenueAdapter stub                │
│ Anvil / fork        │──── txs / receipts / gas ──────────────────┘
└─────────────────────┘
          ↑
   EVM mechanics lab (storage / memory / calls / reentrancy)
```

| Layer | Role |
|-------|------|
| `src/lab/` | EVM stack/memory/storage/calldata + call-types + reentrancy demos |
| `src/amm/ConstantProductAMM.sol` | CPAMM: LP mint/burn, swap, fees |
| `src/tokens/MockERC20.sol` | Test tokens |
| `src/adapters/` | CLOB stub + kill switch + **guarded hedge executor** |
| `python/reference/` | CPAMM math + IL; vectors for Forge differential tests |
| `python/bridge/` | Quote engine (basis / sizing) + Cast snapshot helpers |
| `test/` | Unit, fuzz, invariant, lab, adapter, differential, adversarial |
| `script/DeployLab.s.sol` / `DeployAMM.s.sol` | Anvil deploys |

Languages: **Solidity 0.8.28 + Foundry** (Forge / Cast / Anvil); **Python** for the AMM reference model and future QuantForge bridges.

---

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`) on `PATH`
- Python 3.10+ (for reference tests / vector generation)
- Git submodules (`lib/forge-std`)

```bash
git submodule update --init --recursive
```

---

## Build & test

```bash
forge build
forge test -vv

# Gas report on hot paths
forge test --gas-report

# Python reference + quote engine
python -m pip install -r python/requirements.txt
cd python && python cpamm/generate_vectors.py && python -m pytest -q && cd ..
```

CI: [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs Foundry (`fmt` / `build` / `test`) and Python pytest on Ubuntu.

---

## Demo (misprice → hedge → P&L)

```bash
# Offline economics (no chain; CI-safe)
cd python && python demo/e2e_hedge.py sim --mid 0.95 --no-native

# Anvil end-to-end
anvil   # terminal A
forge script script/DemoHedge.s.sol:DemoHedgeScript --rpc-url http://127.0.0.1:8545 --broadcast -vv
```

Details: [`docs/ANVIL.md`](docs/ANVIL.md) · EVM notes: [`docs/EVM_LAB.md`](docs/EVM_LAB.md) · QuantForge bridge: [`docs/QUANTFORGE_INTEGRATION.md`](docs/QUANTFORGE_INTEGRATION.md).

---

## MVP status vs placement plan

| Deliverable (Project 2) | Status |
|-------------------------|--------|
| EVM / Foundry laboratory | Done |
| CPAMM + Python differential | Done |
| Cross-venue MM + hedge | Guarded executor + quote engine + E2E demo (gas-net logs) |
| AMM sandbox | IL sim, two-pool arb search + `AtomicArbExecutor`, `SpotOracle` lab |
| Security & ops pack | Kill switch, sandwich/FoT/oracle manip tests, invariants, threat model |
| Evidence pack | CI + docs + metrics dashboard; short screen video still user-owned |

QuantForge is a **done sibling** — ChainVenue uses synth/JSON mids with the same book shape.

Docs: [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) · [`docs/LATENCY_FEE_REGIMES.md`](docs/LATENCY_FEE_REGIMES.md) · dashboard [`web/dashboard/`](web/dashboard/).

```bash
cd python && python demo/e2e_hedge.py ledger --out ../web/dashboard/metrics_ledger.json --no-native
```

---

## Explicit non-goals

- Absorbing Fitness-App
- Public mainnet with real funds
- Live adversarial MEV against real users
- Starting AgentGrid from this repo

---

## Sibling projects

- **QuantForge** — C++ LOB MM / backtester ([repo](https://github.com/Wojtek-06/QuantForge)); mids via synth/JSON
- **AgentGrid** — not started; later dogfood target
