# QuantForge ↔ ChainVenue integration (planned)

Sibling project: [QuantForge](https://github.com/Wojtek-06/QuantForge) at `C:\Projekty\Quant\QuantForge`.

ChainVenue does **not** vendor or modify QuantForge in the MVP. Integration is adapter-shaped so the CLOB remains the off-chain venue of record.

## What QuantForge provides (reference)

| QuantForge piece | Use in ChainVenue |
|------------------|-------------------|
| C++ LOB matching + queue position | Fair mid / microprice / inventory inputs |
| Avellaneda–Stoikov-style quoting | Cross-venue quote skew vs AMM implied price |
| Kill switch / risk gates | Shared semantics with `KillSwitch` + `CrossVenueAdapter` |
| Python research API (`quantforge`, FastAPI) | Push `IClobVenue.BookSnapshot` onto Anvil stub |

## MVP surfaces already in this repo

- `IClobVenue` — normalized book snapshot (`bestBid`/`bestAsk`/`mid`/`microprice`/`inventoryBase`/`ts`)
- `ICrossVenueAdapter` / `CrossVenueAdapter` — hedge intent + idempotency + freshness guards
- `KillSwitch` — guardian-gated halt
- `ClobVenueStub` — Anvil-side snapshot holder awaiting an off-chain pusher

## Integration phases

1. **Now (MVP):** Foundry lab + CPAMM + Python differential model + adapter stubs.
2. **Next:** Python service reads QuantForge sim/metrics and `pushSnapshot` via Cast/web3 to Anvil.
3. **Capstone:** Quote engine compares CLOB mid/microprice to AMM `reserve1/reserve0`, proposes hedges through the adapter with slippage/gas/profit guards; end-to-end P&L + gas accounting.

## Non-goals

- Rewriting the LOB inside Solidity
- Absorbing Fitness-App
- Live mainnet MEV
