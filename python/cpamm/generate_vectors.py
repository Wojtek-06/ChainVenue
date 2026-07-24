#!/usr/bin/env python3
"""Regenerate python/vectors/swap_vectors.json from the reference model."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from reference.cpamm import get_amount_out  # noqa: E402

CASES = [
    {"amount_in": 10**18, "reserve_in": 100 * 10**18, "reserve_out": 100 * 10**18, "fee_bps": 30},
    {"amount_in": 5 * 10**17, "reserve_in": 100 * 10**18, "reserve_out": 200 * 10**18, "fee_bps": 30},
    {"amount_in": 10**16, "reserve_in": 50 * 10**18, "reserve_out": 75 * 10**18, "fee_bps": 30},
    {"amount_in": 2 * 10**18, "reserve_in": 1000 * 10**18, "reserve_out": 1000 * 10**18, "fee_bps": 5},
    {"amount_in": 10**18, "reserve_in": 1000 * 10**18, "reserve_out": 500 * 10**18, "fee_bps": 30},
]


def main() -> None:
    out_cases = []
    for c in CASES:
        amount_out = get_amount_out(c["amount_in"], c["reserve_in"], c["reserve_out"], c["fee_bps"])
        out_cases.append({**c, "amount_out": amount_out})
    payload = {"count": len(out_cases), "cases": out_cases}
    dest = ROOT / "vectors" / "swap_vectors.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {dest} ({len(out_cases)} cases)")


if __name__ == "__main__":
    main()
