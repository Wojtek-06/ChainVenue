"""Tests for the off-chain CLOB↔AMM quote engine."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from bridge.quote_engine import BookSnapshot, basis_bps, decide_hedge, size_hedge  # noqa: E402
from bridge.snapshot import cast_push_snapshot_cmd, encode_push_snapshot_args  # noqa: E402


def test_basis_positive_when_amm_rich():
    # spot = 1.0, mid = 0.95 → positive basis
    bps = basis_bps(100 * 10**18, 100 * 10**18, int(0.95 * 10**18))
    assert bps > 10


def test_decide_hedge_sells_token0_when_amm_rich():
    snap = BookSnapshot.from_mid(mid=int(0.95 * 10**18), inventory_base=0, ts=1_700_000_000)
    d = decide_hedge(
        reserve0=100 * 10**18,
        reserve1=100 * 10**18,
        fee_bps=30,
        snap=snap,
        amount_in=10**18,
        now_ts=1_700_000_000,
    )
    assert d.should_hedge
    assert d.token_in_is_token0 is True
    assert d.profit > 0
    assert d.amount_out > d.fair_out


def test_decide_hedge_sells_token1_when_amm_cheap_token0():
    # spot = 1.0, mid = 1.05 → negative basis ⇒ sell token1
    snap = BookSnapshot.from_mid(mid=int(1.05 * 10**18), ts=100)
    d = decide_hedge(
        reserve0=100 * 10**18,
        reserve1=100 * 10**18,
        fee_bps=30,
        snap=snap,
        amount_in=10**18,
        now_ts=100,
    )
    assert d.should_hedge
    assert d.token_in_is_token0 is False


def test_stale_and_inventory_guards():
    snap = BookSnapshot.from_mid(mid=10**18, inventory_base=10**21, ts=1)
    d = decide_hedge(
        reserve0=100 * 10**18,
        reserve1=100 * 10**18,
        fee_bps=30,
        snap=snap,
        amount_in=10**18,
        max_inventory_base=10**18,
        now_ts=1,
    )
    assert not d.should_hedge
    assert d.reason == "inventory_cap"

    snap2 = BookSnapshot.from_mid(mid=int(0.9 * 10**18), ts=1)
    d2 = decide_hedge(
        reserve0=100 * 10**18,
        reserve1=100 * 10**18,
        fee_bps=30,
        snap=snap2,
        amount_in=10**18,
        now_ts=1000,
        max_snapshot_age=30,
    )
    assert not d2.should_hedge
    assert d2.reason == "stale_clob"


def test_cast_cmd_contains_stub_and_sig():
    snap = BookSnapshot.from_mid(mid=10**18, ts=42, inventory_base=-5)
    args = encode_push_snapshot_args(snap)
    assert args[2] == 10**18
    assert args[5] == 42
    cmd = cast_push_snapshot_cmd("0xabc", snap, private_key="0x1")
    assert "pushSnapshot" in cmd
    assert "0xabc" in cmd


def test_inventory_skew_increases_sell_size_when_long():
    base = 10**18
    long_size = size_hedge(
        base_amount_in=base,
        inventory_base=80,
        basis_bps_signed=200,  # sell token0
        max_inventory_base=100,
        inventory_skew_bps=50,
    )
    short_size = size_hedge(
        base_amount_in=base,
        inventory_base=-80,
        basis_bps_signed=200,
        max_inventory_base=100,
        inventory_skew_bps=50,
    )
    assert long_size > base
    assert short_size < long_size
