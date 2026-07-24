"""Offline E2E sim + QuantForge-shaped feed tests (no Anvil required)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from bridge.quantforge_feed import (  # noqa: E402
    FeedConfig,
    iter_synthetic_snapshots,
    snapshot_from_json_file,
    snapshot_from_metrics,
)
from bridge.quote_engine import WAD  # noqa: E402
from demo.e2e_hedge import run_sim  # noqa: E402


def test_sim_detects_mispricing_and_profits():
    result = run_sim(mid=0.95, try_native=False)
    assert result.should_hedge
    assert result.basis_bps > 0
    assert result.profit_vs_fair > 0
    assert result.amount_out > result.fair_out
    assert result.net_profit_vs_fair == result.profit_vs_fair - result.gas_cost_wei
    assert result.gas_cost_wei > 0


def test_sim_skips_when_aligned():
    result = run_sim(mid=1.0, try_native=False)
    assert not result.should_hedge
    assert result.reason == "basis_too_small"


def test_snapshot_from_qf_like_json(tmp_path: Path):
    payload = {
        "experiment": {
            "metrics": {"mid": 0.97, "inventory": 12, "best_bid": 0.96, "best_ask": 0.98}
        }
    }
    path = tmp_path / "qf.json"
    path.write_text(json.dumps(payload), encoding="utf-8")
    snap = snapshot_from_json_file(path, ts=123)
    assert snap.mid == int(0.97 * WAD)
    assert snap.inventory_base == 12
    assert snap.ts == 123


def test_snapshot_from_float_and_wad_int():
    a = snapshot_from_metrics({"mid": 1.0, "inventory": 0, "ts": 1})
    b = snapshot_from_metrics({"mid": WAD, "inventory": 0, "ts": 1})
    assert a.mid == WAD
    assert b.mid == WAD


def test_synthetic_feed_mispriced():
    snap = next(iter_synthetic_snapshots(FeedConfig(misprice_bps=-500)))
    assert snap.mid < WAD


def test_ledger_writes_runs(tmp_path: Path):
    from demo.e2e_hedge import run_ledger

    out = tmp_path / "metrics_ledger.json"
    ledger = run_ledger(mids=[0.95, 1.0], out_path=out, try_native=False)
    assert out.is_file()
    assert len(ledger["runs"]) == 2
    assert ledger["runs"][0]["should_hedge"] is True
    assert ledger["runs"][1]["should_hedge"] is False
