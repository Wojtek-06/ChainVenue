# Safety & threat model (MVP)

## Allowed environments

| Environment | Allowed |
|-------------|---------|
| Local Anvil | Yes |
| Mainnet / L2 fork (Anvil) | Yes — analysis & tests |
| Public testnet | Only after invariants + threat docs reviewed |
| Public mainnet with real funds | **No** for this MVP |

## Explicit non-goals

- Extractive live MEV / sandwich bots against real users
- Deploying unaudited AMM / adapters with material TVL
- Blindly trusting manipulated oracles (assumptions must be documented)

## Defensive controls (present or stubbed)

| Control | Status |
|---------|--------|
| Kill switch on adapter | Implemented (`KillSwitch`) |
| CLOB snapshot freshness | Implemented (`ClobVenueStub.isFresh`) |
| Idempotency keys | Implemented on successful `proposeHedge` |
| Min-profit / max-slippage / gas guards | Implemented on `CrossVenueAdapter` |
| Basis / wrong-side guards | Implemented (`minBasisBps` + direction) |
| Sandwich ordering sim (local) | Implemented (`test/adversarial/SandwichSim.t.sol`) |
| Weird ERC-20 (fee-on-transfer) | Implemented (`test/adversarial/WeirdERC20.t.sol`) |
| Reorg / inclusion simulation | Planned |
| QuantForge live snapshot daemon | Planned |

## Authority

- Lab keys are Anvil defaults or local env `PRIVATE_KEY`.
- Never commit funded mainnet keys. `.env` is gitignored.
