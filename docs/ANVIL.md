# Anvil / local fork notes

## Safety policy

ChainVenue runs **only** on:

1. Local Anvil (`anvil`)
2. Optional **mainnet forks** for read-only / simulated execution after invariants are green
3. Optional public **testnets** with throwaway keys and a documented threat model

**Never** deploy these lab contracts to public mainnet with real funds.  
**Never** run extractive sandwich/MEV bots against live users. Defensive ordering analysis only.

## Quick start

```bash
# Terminal A — local chain
anvil

# Terminal B — full mispricing → hedge → P&L demo (preferred)
forge script script/DemoHedge.s.sol:DemoHedgeScript --rpc-url http://127.0.0.1:8545 --broadcast -vv

# Or deploy lab + AMM + adapter only
forge script script/DeployLab.s.sol:DeployLabScript --rpc-url http://127.0.0.1:8545 --broadcast
```

Offline Python P&L (no chain): `cd python && python demo/e2e_hedge.py sim --mid 0.95 --no-native`

Scripts default to the **well-known Anvil account #0** private key (public Foundry test key) via `vm.envOr` for local convenience. Override with `PRIVATE_KEY` in `.env` (see `.env.example`). Never use a funded mainnet key here.

## Useful Cast commands

```bash
cast block-number --rpc-url http://127.0.0.1:8545
cast call <amm> "getReserves()(uint112,uint112,uint32)" --rpc-url http://127.0.0.1:8545
cast sig "swapExactIn(address,uint256,uint256,address)"
```

## Fork (optional)

```bash
anvil --fork-url $ETH_RPC_URL
```

Use forks for:

- Pool-state parsing experiments
- Adversarial ordering / sandwich *simulation*
- Gas/inclusion sensitivity studies

Do not bridge real capital or target third-party wallets.

## Kill switch / reconciliation

`CrossVenueAdapter` + `KillSwitch` already expose:

- CLOB freshness + inventory + gas caps
- Basis / wrong-side guards (`minBasisBps`)
- Slippage (`minAmountOut`) + profit (`minProfitOut`) guards
- Idempotency keys (set after successful execute)
- Operator-gated `proposeHedge` → AMM `swapExactIn`

Off-chain: size hedges with `python/bridge/quote_engine.py`, push mids with `cast_push_snapshot_cmd`.

**Out of scope for this lab:** a continuous QuantForge snapshot daemon and live fill/P&L reconciliation against a production LOB.
