# ChainVenue

Cross-venue **CLOB–AMM** laboratory: Foundry-tested EVM mechanics + constant-product AMM, with a stub adapter toward [QuantForge](https://github.com/Wojtek-06/QuantForge)’s off-chain limit-order-book MM stack.

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
| `src/adapters/` | `IClobVenue` + hedge adapter stub (QuantForge link later) |
| `python/reference/` | Reference math + IL helper; vectors for Forge differential tests |
| `test/` | Unit, fuzz, invariant, lab, adapter, differential |
| `script/DeployLab.s.sol` | One-shot Anvil deploy |

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

# Python reference + differential vectors
python -m pip install -r python/requirements.txt
python python/cpamm/generate_vectors.py
python -m pytest python/tests -q
```

CI: [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs Foundry (`fmt` / `build` / `test`) and Python pytest on Ubuntu.

---

## Anvil demo

```bash
anvil   # terminal A
forge script script/DeployLab.s.sol:DeployLabScript --rpc-url http://127.0.0.1:8545 --broadcast
```

Details: [`docs/ANVIL.md`](docs/ANVIL.md) · EVM notes: [`docs/EVM_LAB.md`](docs/EVM_LAB.md) · QuantForge link plan: [`docs/QUANTFORGE_INTEGRATION.md`](docs/QUANTFORGE_INTEGRATION.md).

---

## MVP status vs placement plan

| Deliverable (Project 2) | This scaffold |
|-------------------------|---------------|
| EVM / Foundry laboratory | Done (contracts + tests + notes) |
| CPAMM + Python differential | Done (Solidity + `python/reference` + vector diff test) |
| Cross-venue MM + hedge capstone | Stub interfaces + kill switch / freshness / inventory guards |
| Security & ops pack | Partial (reentrancy demo, invariants, safety policy) |
| Evidence pack | In progress (CI + docs; demo video later) |

---

## Explicit non-goals

- Absorbing Fitness-App
- Modifying QuantForge (sibling only; optional README link)
- Public mainnet with real funds
- Live adversarial MEV against real users
- Starting AgentGrid from this repo

---

## Sibling projects

- **QuantForge** — C++ LOB MM / backtester (CLOB venue this adapter will consume)
- **AgentGrid** — not started; later dogfood target
