#!/usr/bin/env python3
"""End-to-end ChainVenue hedge demo.

Modes:
  sim   — pure Python (CI / offline): misprice → decide → virtual swap → P&L
  anvil — run Foundry DemoHedge.s.sol against local Anvil (requires forge + anvil)
  feed  — emit / optionally push synthetic QuantForge-shaped snapshots

Examples:
  python demo/e2e_hedge.py sim
  python demo/e2e_hedge.py sim --mid 0.95
  python demo/e2e_hedge.py anvil
  python demo/e2e_hedge.py feed --steps 3
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
sys.path.insert(0, str(ROOT))

from bridge.quantforge_feed import (  # noqa: E402
    FeedConfig,
    iter_synthetic_snapshots,
    snapshot_from_json_file,
    snapshot_from_metrics,
    try_snapshot_from_native,
)
from bridge.quote_engine import WAD, BookSnapshot, decide_hedge  # noqa: E402
from bridge.snapshot import cast_push_snapshot_cmd  # noqa: E402
from reference.cpamm import get_amount_out  # noqa: E402


@dataclass
class SimResult:
    mode: str
    should_hedge: bool
    reason: str
    basis_bps: int
    amount_in: int
    amount_out: int
    fair_out: int
    profit_vs_fair: int
    gas_cost_wei: int
    net_profit_vs_fair: int
    reserve0_after: int
    reserve1_after: int
    source: str
    mid: int
    mid_float: float | None = None


def _resolve_snapshot(
    *,
    mid: float | None,
    metrics_json: str | None,
    try_native: bool,
) -> tuple[BookSnapshot, str]:
    if metrics_json:
        return snapshot_from_json_file(metrics_json), "json"
    if mid is not None:
        return snapshot_from_metrics({"mid": mid, "inventory": 0, "ts": 1_700_000_000}), "cli-mid"
    if try_native:
        native = try_snapshot_from_native()
        if native is not None:
            return native, "quantforge-native"
    return snapshot_from_metrics({"mid": 0.95, "inventory": 0, "ts": 1_700_000_000}), "synth"


def run_sim(
    *,
    reserve0: int = 100_000 * WAD,
    reserve1: int = 100_000 * WAD,
    fee_bps: int = 30,
    amount_in: int = 10 * WAD,
    mid: float | None = None,
    metrics_json: str | None = None,
    try_native: bool = True,
    gas_used: int = 180_000,
    gas_price_wei: int = 1_000_000_000,
) -> SimResult:
    snap, source = _resolve_snapshot(mid=mid, metrics_json=metrics_json, try_native=try_native)
    decision = decide_hedge(
        reserve0=reserve0,
        reserve1=reserve1,
        fee_bps=fee_bps,
        snap=snap,
        amount_in=amount_in,
        now_ts=snap.ts,
        max_inventory_base=10**30,
        apply_inventory_skew=True,
    )
    gas_cost = gas_used * gas_price_wei

    mid_float = snap.mid / WAD

    if not decision.should_hedge:
        return SimResult(
            mode="sim",
            should_hedge=False,
            reason=decision.reason,
            basis_bps=decision.basis_bps,
            amount_in=amount_in,
            amount_out=0,
            fair_out=decision.fair_out,
            profit_vs_fair=0,
            gas_cost_wei=gas_cost,
            net_profit_vs_fair=-gas_cost,
            reserve0_after=reserve0,
            reserve1_after=reserve1,
            source=source,
            mid=snap.mid,
            mid_float=mid_float,
        )

    traded_in = decision.amount_in
    if decision.token_in_is_token0:
        out = get_amount_out(traded_in, reserve0, reserve1, fee_bps)
        r0, r1 = reserve0 + traded_in, reserve1 - out
    else:
        out = get_amount_out(traded_in, reserve1, reserve0, fee_bps)
        r0, r1 = reserve0 - out, reserve1 + traded_in

    gross = out - decision.fair_out
    return SimResult(
        mode="sim",
        should_hedge=True,
        reason=decision.reason,
        basis_bps=decision.basis_bps,
        amount_in=traded_in,
        amount_out=out,
        fair_out=decision.fair_out,
        profit_vs_fair=gross,
        gas_cost_wei=gas_cost,
        net_profit_vs_fair=gross - gas_cost,
        reserve0_after=r0,
        reserve1_after=r1,
        source=source,
        mid=snap.mid,
        mid_float=mid_float,
    )


def run_ledger(
    *,
    mids: list[float],
    out_path: Path,
    try_native: bool = False,
    gas_used: int = 180_000,
    gas_price_wei: int = 1_000_000_000,
) -> dict:
    """Sweep mids and write a dashboard-friendly metrics ledger JSON."""
    from datetime import datetime, timezone

    runs = []
    for mid in mids:
        result = run_sim(
            mid=mid,
            try_native=try_native,
            gas_used=gas_used,
            gas_price_wei=gas_price_wei,
        )
        row = asdict(result)
        row["mid_float"] = mid
        runs.append(row)

    ledger = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "gas_used": gas_used,
        "gas_price_wei": gas_price_wei,
        "runs": runs,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(ledger, indent=2) + "\n", encoding="utf-8")
    return ledger


def run_anvil(*, rpc_url: str, private_key: str | None) -> int:
    env = os.environ.copy()
    if private_key:
        env["PRIVATE_KEY"] = private_key
    cmd = [
        "forge",
        "script",
        "script/DemoHedge.s.sol:DemoHedgeScript",
        "--rpc-url",
        rpc_url,
        "--broadcast",
        "-vv",
    ]
    print("Running:", " ".join(cmd), flush=True)
    return subprocess.run(cmd, cwd=str(REPO), env=env).returncode


def run_feed(steps: int, clob_stub: str | None, rpc_url: str, private_key: str) -> None:
    gen = iter_synthetic_snapshots(FeedConfig(misprice_bps=-500))
    for i in range(steps):
        snap = next(gen)
        print(f"[{i}] mid={snap.mid} inv={snap.inventory_base} ts={snap.ts}")
        if clob_stub:
            cmd = cast_push_snapshot_cmd(
                clob_stub, snap, rpc_url=rpc_url, private_key=private_key
            )
            print(" ", cmd)
            subprocess.run(cmd, shell=True, check=False)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="ChainVenue E2E hedge demo")
    sub = p.add_subparsers(dest="cmd", required=True)

    sim_p = sub.add_parser("sim", help="Offline Python P&L simulation")
    sim_p.add_argument("--mid", type=float, default=None, help="CLOB mid as float (e.g. 0.95)")
    sim_p.add_argument("--json", dest="metrics_json", default=None, help="QuantForge-like JSON")
    sim_p.add_argument("--amount-in-ether", type=float, default=10.0)
    sim_p.add_argument("--no-native", action="store_true", help="Skip QuantForge native probe")

    anvil_p = sub.add_parser("anvil", help="Broadcast DemoHedge.s.sol to Anvil")
    anvil_p.add_argument("--rpc-url", default=os.environ.get("ANVIL_RPC", "http://127.0.0.1:8545"))
    anvil_p.add_argument("--private-key", default=os.environ.get("PRIVATE_KEY"))

    feed_p = sub.add_parser("feed", help="Print / push synthetic snapshots")
    feed_p.add_argument("--steps", type=int, default=3)
    feed_p.add_argument("--clob-stub", default=None)
    feed_p.add_argument("--rpc-url", default=os.environ.get("ANVIL_RPC", "http://127.0.0.1:8545"))
    feed_p.add_argument(
        "--private-key",
        default=os.environ.get(
            "PRIVATE_KEY",
            "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        ),
    )

    led_p = sub.add_parser("ledger", help="Sweep mids → metrics_ledger.json for dashboard")
    led_p.add_argument(
        "--out",
        default=str(REPO / "web" / "dashboard" / "metrics_ledger.json"),
        help="Output JSON path",
    )
    led_p.add_argument(
        "--mids",
        default="0.90,0.93,0.95,0.97,1.0,1.03,1.05",
        help="Comma-separated mid floats",
    )
    led_p.add_argument("--no-native", action="store_true")
    led_p.add_argument("--gas-used", type=int, default=180_000)
    led_p.add_argument("--gas-price-wei", type=int, default=1_000_000_000)

    args = p.parse_args(argv)

    if args.cmd == "sim":
        result = run_sim(
            amount_in=int(args.amount_in_ether * WAD),
            mid=args.mid,
            metrics_json=args.metrics_json,
            try_native=not args.no_native,
        )
        print(json.dumps(asdict(result), indent=2))
        return 0 if result.should_hedge else 2

    if args.cmd == "anvil":
        return run_anvil(rpc_url=args.rpc_url, private_key=args.private_key)

    if args.cmd == "feed":
        run_feed(args.steps, args.clob_stub, args.rpc_url, args.private_key)
        return 0

    if args.cmd == "ledger":
        mids = [float(x.strip()) for x in args.mids.split(",") if x.strip()]
        ledger = run_ledger(
            mids=mids,
            out_path=Path(args.out),
            try_native=not args.no_native,
            gas_used=args.gas_used,
            gas_price_wei=args.gas_price_wei,
        )
        print(json.dumps({"wrote": args.out, "runs": len(ledger["runs"])}, indent=2))
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
