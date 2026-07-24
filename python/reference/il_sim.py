"""Impermanent loss / LP vs HODL sandbox for ChainVenue AMM research."""

from __future__ import annotations

from dataclasses import dataclass

from .cpamm import impermanent_loss_ratio, mint_liquidity, spot_price_x_per_y


@dataclass(frozen=True)
class LpPosition:
    amount0: int
    amount1: int
    liquidity: int
    total_supply: int


@dataclass(frozen=True)
class LpReport:
    price_ratio: float
    il_ratio: float
    value_lp: float
    value_hodl: float
    fees_earned_quote: float
    lp_vs_hodl_with_fees: float


def bootstrap_position(amount0: int, amount1: int) -> LpPosition:
    liq = mint_liquidity(amount0, amount1, 0, 0, 0)
    # total supply = liq + MINIMUM_LIQUIDITY locked
    return LpPosition(amount0, amount1, liq, liq + 1000)


def simulate_il(
    amount0: int,
    amount1: int,
    *,
    price_ratio: float,
    fees_earned_quote: float = 0.0,
) -> LpReport:
    """
    Compare 50/50 LP value vs HODL after relative price move `price_ratio` (= P1/P0).

    Values denominated in token1 ("quote") with initial spot = amount1/amount0.
    """
    if amount0 <= 0 or amount1 <= 0:
        raise ValueError("amounts must be > 0")
    if price_ratio <= 0:
        raise ValueError("price_ratio must be > 0")

    spot0 = spot_price_x_per_y(amount0, amount1)  # token1 per token0
    # HODL value in token1 after move: amount0 * spot0 * price_ratio + amount1
    # (token0 revalued by price_ratio relative to initial spot)
    value_hodl = amount0 * spot0 * price_ratio + amount1

    il = impermanent_loss_ratio(price_ratio)
    value_lp = value_hodl * (1.0 - il)
    with_fees = value_lp + fees_earned_quote

    return LpReport(
        price_ratio=price_ratio,
        il_ratio=il,
        value_lp=value_lp,
        value_hodl=value_hodl,
        fees_earned_quote=fees_earned_quote,
        lp_vs_hodl_with_fees=with_fees - value_hodl,
    )
