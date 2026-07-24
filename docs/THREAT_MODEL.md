# Threat model (lab / Anvil scope)

Scope: local Anvil, fork, or testnet. **Not** extractive live MEV against real users.

## Assets

| Asset | Why it matters |
|-------|----------------|
| AMM reserves / LP shares | Mispriced swaps drain value vs fair mid |
| Adapter hedge inventory | Wrong-side or oversized hedges amplify loss |
| Oracle / CLOB mid | Stale or manipulated mid → false basis |
| Kill switch | Last line of defense when economics break |

## Adversaries (simulated)

1. **Sandwich bot** — front-runs victim swap; `minAmountOut` + profit guards.
2. **Fee-on-transfer token** — breaks naive balance accounting; CPAMM reverts on `InvalidK`.
3. **Reentrancy** — classic vault drain vs CEI + lock (lab contracts).
4. **Oracle owner / mid feeder** — can set absurd prices; adapter still blocks on basis / profit / gas.
5. **Replay / double-submit** — idempotency key on adapter hedges.

## Controls mapped to tests

| Control | Location |
|---------|----------|
| Constant-product invariant | `ConstantProductAMM.invariant.t.sol` |
| Differential vs Python | `Differential.t.sol` + `python/reference/cpamm.py` |
| Sandwich / FoT / reentrancy | `test/adversarial/` |
| Kill switch | `KillSwitch.sol` + adapter / arb tests |
| Basis / inventory / gas / slippage | `CrossVenueAdapter.t.sol` |
| Inclusion / reorg notes | `InclusionReorg.t.sol` |

## Residual risk (accepted in lab)

- Synth/JSON mids are not a live CLOB feed.
- Gas estimates are scenario knobs, not mempool truth.
- Forked mainnet state can diverge; demos stay Anvil-first.

## Fuzz / invariant report (how to regenerate)

```bash
forge test --match-contract ConstantProductAMMInvariant -vv
forge test --match-path test/amm/ConstantProductAMM.t.sol --fuzz-runs 256
```

Expect: invariant holds under fee-on-input swaps; unit/fuzz paths stay green in CI.
