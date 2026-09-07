# Safety & threat model (lab demo)

## Allowed environments

| Environment | Allowed |
|-------------|---------|
| Local Anvil | Yes |
| Mainnet / L2 fork (Anvil) | Yes — analysis & tests |
| Public testnet | Only with throwaway keys after reviewing threat docs |
| Public mainnet with real funds | **No** |

## Explicit non-goals

- Extractive live MEV / sandwich bots against real users
- Deploying unaudited AMM / adapters with material TVL
- Blindly trusting manipulated oracles (assumptions are documented)
- A live QuantForge snapshot daemon inside this repo

## Defensive controls

| Control | Status |
|---------|--------|
| Kill switch on adapter / arb | Implemented (`KillSwitch`) |
| CLOB snapshot freshness | Implemented (`ClobVenueStub.isFresh`) |
| Idempotency keys | Implemented on successful `proposeHedge` |
| Min-profit / max-slippage / gas guards | Implemented on `CrossVenueAdapter` |
| Basis / wrong-side guards | Implemented (`minBasisBps` + direction) |
| Sandwich ordering sim (local) | Implemented (`test/adversarial/SandwichSim.t.sol`) |
| Weird ERC-20 (fee-on-transfer) | Implemented (`test/adversarial/WeirdERC20.t.sol`) |
| Reorg / inclusion simulation | Implemented (`test/ops/InclusionReorg.t.sol`) |
| Live QuantForge snapshot daemon | **Out of scope** — synth/JSON mids only |

## Authority

- Lab scripts default to the **well-known Anvil account #0** private key (public Foundry test key) via `vm.envOr` / CLI defaults. Override with `PRIVATE_KEY` in a local `.env` (see `.env.example`).
- Never commit funded mainnet keys, RPC tokens, or keystores. `.env`, keystores, and Anvil log dumps are gitignored.

See also [`THREAT_MODEL.md`](THREAT_MODEL.md).
