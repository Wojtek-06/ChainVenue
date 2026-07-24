"""Tests for two-pool arb search and IL sandbox."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from reference.il_sim import bootstrap_position, simulate_il  # noqa: E402
from reference.two_pool_arb import PoolState, search_two_pool_arb  # noqa: E402


def test_two_pool_finds_profit_when_skewed():
    fair = PoolState(100_000 * 10**18, 100_000 * 10**18, 30)
    skewed = PoolState(80_000 * 10**18, 120_000 * 10**18, 30)
    opp = search_two_pool_arb(fair, skewed, max_in=1_000 * 10**18, steps=40, min_profit=1)
    assert opp is not None
    assert opp.profit > 0
    assert opp.amount_out > opp.amount_in


def test_two_pool_none_when_aligned():
    a = PoolState(100_000 * 10**18, 100_000 * 10**18, 30)
    b = PoolState(100_000 * 10**18, 100_000 * 10**18, 30)
    opp = search_two_pool_arb(a, b, max_in=1_000 * 10**18, steps=20, min_profit=1)
    assert opp is None


def test_il_doubling_classic():
    report = simulate_il(100 * 10**18, 100 * 10**18, price_ratio=2.0)
    assert 0.05 < report.il_ratio < 0.06
    assert report.value_lp < report.value_hodl
    assert report.lp_vs_hodl_with_fees < 0


def test_fees_can_offset_il():
    base = simulate_il(100 * 10**18, 100 * 10**18, price_ratio=2.0)
    # Use a large fee addend — float64 cannot represent +1.0 on ~1e20 values.
    fees = (base.value_hodl - base.value_lp) * 1.05
    report = simulate_il(
        100 * 10**18,
        100 * 10**18,
        price_ratio=2.0,
        fees_earned_quote=fees,
    )
    assert report.lp_vs_hodl_with_fees > 0


def test_bootstrap_position():
    pos = bootstrap_position(100 * 10**18, 100 * 10**18)
    assert pos.liquidity > 0
    assert pos.total_supply == pos.liquidity + 1000
