"""Differential tests: Python reference vs known Solidity vectors / invariants."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from reference.cpamm import (  # noqa: E402
    get_amount_out,
    impermanent_loss_ratio,
    mint_liquidity,
    price_impact_bps,
    quote,
)


# Locked to ConstantProductAMM.t.sol::test_getAmountOutMatchesPythonVector
SOLIDITY_VECTOR_OUT = 987_158_034_397_061_298


def test_amount_out_matches_solidity_vector():
    out = get_amount_out(10**18, 100 * 10**18, 100 * 10**18, fee_bps=30)
    assert out == SOLIDITY_VECTOR_OUT


@pytest.mark.parametrize(
    "amount_in,reserve_in,reserve_out",
    [
        (10**9, 10**18, 10**18),  # tiny but non-zero after fee rounding
        (10**18, 10**18, 10**18),
        (5 * 10**17, 200 * 10**18, 50 * 10**18),
        (10**21, 10**24, 10**24),
    ],
)
def test_amount_out_bounds(amount_in, reserve_in, reserve_out):
    out = get_amount_out(amount_in, reserve_in, reserve_out, fee_bps=30)
    assert 0 < out < reserve_out


def test_quote_proportional():
    assert quote(2 * 10**18, 100 * 10**18, 400 * 10**18) == 8 * 10**18


def test_mint_bootstrap_locks_minimum():
    liq = mint_liquidity(100 * 10**18, 100 * 10**18, 0, 0, 0)
    assert liq == 100 * 10**18 - 1000


def test_fee_increases_impact():
    impact_low = price_impact_bps(10**18, 100 * 10**18, 100 * 10**18, fee_bps=5)
    impact_high = price_impact_bps(10**18, 100 * 10**18, 100 * 10**18, fee_bps=30)
    assert impact_high > impact_low


def test_il_zero_when_price_unchanged():
    assert math.isclose(impermanent_loss_ratio(1.0), 0.0, abs_tol=1e-12)


def test_il_positive_when_price_doubles():
    il = impermanent_loss_ratio(2.0)
    # Classic ~5.72% IL for 2x move
    assert 0.05 < il < 0.06
