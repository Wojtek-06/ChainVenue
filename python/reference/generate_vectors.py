"""Generate JSON vectors consumed by Foundry Differential.t.sol."""

from __future__ import annotations

import json
from pathlib import Path

from .cpamm import get_amount_out

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "vectors" / "swap_vectors.json"

CASES = [
    {"amount_in": 10**18, "reserve_in": 100 * 10**18, "reserve_out": 100 * 10**18, "fee_bps": 30},
    {"amount_in": 5 * 10**17, "reserve_in": 100 * 10**18, "reserve_out": 200 * 10**18, "fee_bps": 30},
    {"amount_in": 10**16, "reserve_in": 50 * 10**18, "reserve_out": 75 * 10**18, "fee_bps": 30},
    {"amount_in": 2 * 10**18, "reserve_in": 1_000 * 10**18, "reserve_out": 1_000 * 10**18, "fee_bps": 5},
    {"amount_in": 10**18, "reserve_in": 10**21, "reserve_out": 5 * 10**20, "fee_bps": 30},
]


def main() -> None:
    cases = []
    for c in CASES:
        out = get_amount_out(c["amount_in"], c["reserve_in"], c["reserve_out"], c["fee_bps"])
        cases.append({**c, "amount_out": out})
    payload = {"count": len(cases), "cases": cases}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUT} ({len(cases)} cases)")


if __name__ == "__main__":
    main()
