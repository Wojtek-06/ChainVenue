"""Constant-product AMM reference model (Uniswap V2-style).

Mirrors `src/amm/ConstantProductAMM.sol` for differential testing.
"""

from __future__ import annotations

FEE_DENOMINATOR = 10_000
MINIMUM_LIQUIDITY = 1_000


def get_amount_out(
    amount_in: int,
    reserve_in: int,
    reserve_out: int,
    fee_bps: int = 30,
) -> int:
    if amount_in <= 0:
        raise ValueError("insufficient input")
    if reserve_in <= 0 or reserve_out <= 0:
        raise ValueError("insufficient liquidity")
    amount_in_with_fee = amount_in * (FEE_DENOMINATOR - fee_bps)
    numerator = amount_in_with_fee * reserve_out
    denominator = reserve_in * FEE_DENOMINATOR + amount_in_with_fee
    return numerator // denominator


def quote(amount_a: int, reserve_a: int, reserve_b: int) -> int:
    if amount_a <= 0:
        raise ValueError("insufficient input")
    if reserve_a <= 0 or reserve_b <= 0:
        raise ValueError("insufficient liquidity")
    return (amount_a * reserve_b) // reserve_a


def sqrt(y: int) -> int:
    if y > 3:
        z = y
        x = y // 2 + 1
        while x < z:
            z = x
            x = (y // x + x) // 2
        return z
    if y != 0:
        return 1
    return 0


def mint_liquidity(
    amount0: int,
    amount1: int,
    reserve0: int,
    reserve1: int,
    total_supply: int,
) -> int:
    if total_supply == 0:
        liquidity = sqrt(amount0 * amount1)
        if liquidity <= MINIMUM_LIQUIDITY:
            raise ValueError("insufficient liquidity minted")
        return liquidity - MINIMUM_LIQUIDITY
    liq0 = (amount0 * total_supply) // reserve0
    liq1 = (amount1 * total_supply) // reserve1
    liquidity = liq0 if liq0 < liq1 else liq1
    if liquidity == 0:
        raise ValueError("insufficient liquidity minted")
    return liquidity


def burn_amounts(
    liquidity: int,
    balance0: int,
    balance1: int,
    total_supply: int,
) -> tuple[int, int]:
    amount0 = (liquidity * balance0) // total_supply
    amount1 = (liquidity * balance1) // total_supply
    if amount0 == 0 or amount1 == 0:
        raise ValueError("insufficient liquidity burned")
    return amount0, amount1


def spot_price_x_per_y(reserve0: int, reserve1: int) -> float:
    """Marginal price of token0 in token1 units (no fee)."""
    return reserve1 / reserve0


def price_impact_bps(
    amount_in: int,
    reserve_in: int,
    reserve_out: int,
    fee_bps: int = 30,
) -> float:
    """Approximate mid-to-execution impact in bps (positive = worse for taker)."""
    spot = reserve_out / reserve_in
    out = get_amount_out(amount_in, reserve_in, reserve_out, fee_bps)
    exec_price = out / amount_in
    return (1.0 - exec_price / spot) * 10_000.0


def impermanent_loss_ratio(price_ratio: float) -> float:
    """IL as fraction of HODL value for a 50/50 CPAMM when price moves by `price_ratio`.

    price_ratio = P1 / P0. Returns value lost vs HODL (0 = none, 0.05 ≈ 5%).
    """
    if price_ratio <= 0:
        raise ValueError("price_ratio must be positive")
    # value_lp / value_hodl = 2*sqrt(r) / (1+r)
    r = price_ratio
    return 1.0 - (2.0 * (r**0.5)) / (1.0 + r)
