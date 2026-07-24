# Anvil / local fork notes

## Safety policy

ChainVenue runs **only** on:

1. Local Anvil (`anvil`)
2. Optional **mainnet forks** for read-only / simulated execution after invariants are green
3. Optional public **testnets** later, only with throwaway keys and documented threat model

**Never** deploy these lab contracts to public mainnet with real funds.  
**Never** run extractive sandwich/MEV bots against live users. Defensive ordering analysis only.

## Quick start

```bash
# Terminal A — local chain
anvil

# Terminal B — deploy lab + AMM + adapter stub
forge script script/DeployLab.s.sol:DeployLabScript --rpc-url http://127.0.0.1:8545 --broadcast
```

Default Anvil account #0 private key is baked into the script via `vm.envOr` for local convenience. Override with `PRIVATE_KEY` if needed.

## Useful Cast commands

```bash
cast block-number --rpc-url http://127.0.0.1:8545
cast call <amm> "getReserves()(uint112,uint112,uint32)" --rpc-url http://127.0.0.1:8545
cast sig "swapExactIn(address,uint256,uint256,address)"
```

## Fork (optional, later)

```bash
anvil --fork-url $ETH_RPC_URL
```

Use forks for:

- Pool-state parsing experiments
- Adversarial ordering / sandwich *simulation*
- Gas/inclusion sensitivity studies

Do not bridge real capital or target third-party wallets.

## Kill switch / reconciliation (capstone direction)

`CrossVenueAdapter` + `KillSwitch` already expose:

- CLOB freshness checks
- Idempotency keys
- Operator-gated propose path
- Guardian kill switch

Next: wire `proposeHedge` → AMM `swapExactIn` under min-profit / max-slippage / gas caps, and reconcile fills vs QuantForge CLOB inventory.
