"""Two-pool constant-product arb search (local sandbox, not live MEV)."""

from __future__ import annotations

from dataclasses import dataclass

from .cpamm import get_amount_out


@dataclass(frozen=True)
class PoolState:
    reserve0: int
    reserve1: int
    fee_bps: int = 30


@dataclass(frozen=True)
class ArbOpportunity:
    direction: str  # "0->1->0" or "1->0->1"
    amount_in: int
    amount_out: int
    profit: int
    buy_pool: str
    sell_pool: str


def _round_trip_0(pool_buy: PoolState, pool_sell: PoolState, amount_in: int) -> int:
    """Spend token0 on buy pool → token1, sell token1 on sell pool → token0."""
    mid = get_amount_out(amount_in, pool_buy.reserve0, pool_buy.reserve1, pool_buy.fee_bps)
    return get_amount_out(mid, pool_sell.reserve1, pool_sell.reserve0, pool_sell.fee_bps)


def _round_trip_1(pool_buy: PoolState, pool_sell: PoolState, amount_in: int) -> int:
    """Spend token1 on buy pool → token0, sell token0 on sell pool → token1."""
    mid = get_amount_out(amount_in, pool_buy.reserve1, pool_buy.reserve0, pool_buy.fee_bps)
    return get_amount_out(mid, pool_sell.reserve0, pool_sell.reserve1, pool_sell.fee_bps)


def search_two_pool_arb(
    pool_a: PoolState,
    pool_b: PoolState,
    *,
    max_in: int,
    steps: int = 32,
    min_profit: int = 1,
    name_a: str = "A",
    name_b: str = "B",
) -> ArbOpportunity | None:
    """Grid-search a small size ladder for the best atomic two-pool arb."""
    if max_in <= 0 or steps <= 0:
        return None

    best: ArbOpportunity | None = None

    def consider(opp: ArbOpportunity) -> None:
        nonlocal best
        if opp.profit < min_profit:
            return
        if best is None or opp.profit > best.profit:
            best = opp

    for i in range(1, steps + 1):
        amount_in = (max_in * i) // steps
        if amount_in == 0:
            continue

        # A cheap for token1 (buy token1 on A with token0), sell token1 on B
        out = _round_trip_0(pool_a, pool_b, amount_in)
        consider(
            ArbOpportunity("0->1->0", amount_in, out, out - amount_in, name_a, name_b)
        )
        out = _round_trip_0(pool_b, pool_a, amount_in)
        consider(
            ArbOpportunity("0->1->0", amount_in, out, out - amount_in, name_b, name_a)
        )

        out = _round_trip_1(pool_a, pool_b, amount_in)
        consider(
            ArbOpportunity("1->0->1", amount_in, out, out - amount_in, name_a, name_b)
        )
        out = _round_trip_1(pool_b, pool_a, amount_in)
        consider(
            ArbOpportunity("1->0->1", amount_in, out, out - amount_in, name_b, name_a)
        )

    return best
