# EVM mechanics laboratory

Interview-ready notes for ChainVenue’s Foundry lab contracts under `src/lab/`.

## Accounts, transactions, and state

- **EOA vs contract:** EOAs sign txs; contracts have code + storage. Both have balances.
- **Transaction → message call:** A tx creates an initial call frame; contracts may `CALL` / `STATICCALL` / `DELEGATECALL` / `CREATE`.
- **Gas:** Prepaid; unused gas refunded (with caveats). Storage writes (`SSTORE`) dominate cost.
- **Revert:** Undoes state changes in the failing call frame (unless a low-level call swallowed the failure).

## Storage (`EvmStorageLab`)

Solidity packs `address` + `bool` + `uint8` into **slot 0**. `uint256 counter` is **slot 1**. Mapping `values` base is **slot 2**; element `values[who]` lives at `keccak256(abi.encode(who, 2))`.

Trace with Forge:

```bash
forge test --match-contract EvmStorageLabTest -vvvv
```

Or on Anvil after deploy:

```bash
cast storage <lab> 0
cast storage <lab> 1
```

## Memory vs calldata (`EvmMemoryLab`)

| Location | Lifetime | Cost intuition |
|----------|----------|----------------|
| **calldata** | Call input, read-only | Cheap to read in place |
| **memory** | Ephemeral per call | Expand + copy costs gas |
| **storage** | Persistent | Expensive read/write |

`sumCalldata` reads the argument array without an extra ABI memory copy at the call boundary the same way `sumMemory` does—compare gas with `forge test --gas-report`.

Free-memory pointer lives at `0x40`. `allocateScratch` advances it by `words * 0x20`.

## Calls (`EvmCallLab`)

| Opcode family | Writes callee storage? | `msg.sender` in callee |
|---------------|------------------------|-------------------------|
| `CALL` | Yes (callee) | Caller contract |
| `STATICCALL` | No (reverts on write) | Caller contract |
| `DELEGATECALL` | Yes (**caller** storage) | Original `msg.sender` |

`EvmDelegateProxy` shows why proxy slot layouts must match implementations.

## Reentrancy (`ReentrancyLab`)

- `VulnerableVault`: external call **before** zeroing balance → classic drain (local Anvil only).
- `SafeVault`: CEI + `nonReentrant` lock.

**Policy:** adversarial tests are for education and defensive design. No extractive live MEV against real users.

## Suggested interview walkthrough

1. Show packed slot 0 via `vm.load` / `cast storage`.
2. Walk a swap: calldata selector → `swapExactIn` → reserve `SSTORE` → `Swap`/`Sync` events.
3. Explain why invariant tests assert **k non-decreasing** under fee-on-input swaps.
