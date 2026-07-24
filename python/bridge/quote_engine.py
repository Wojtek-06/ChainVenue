"""Fair-price / inventory quote engine for CLOB↔AMM hedges.

Compares QuantForge-style book mids to CPAMM spot and sizes a defensive hedge.
Does not submit live MEV — outputs an intent for the Foundry adapter on Anvil.
"""

from __future__ import annotations

from dataclasses import dataclass

from reference.cpamm import get_amount_out

WAD = 10**18
BPS = 10_000


@dataclass(frozen=True)
class BookSnapshot:
    best_bid: int
    best_ask: int
    mid: int  # token1 per token0, 1e18-scaled
    microprice: int
    inventory_base: int  # signed
    ts: int
    source_id: bytes = b"quantforge"

    @classmethod
    def from_mid(
        cls,
        mid: int,
        inventory_base: int = 0,
        ts: int = 0,
        spread_bps: int = 100,
    ) -> BookSnapshot:
        half = (mid * spread_bps) // (2 * BPS)
        return cls(
            best_bid=mid - half,
            best_ask=mid + half,
            mid=mid,
            microprice=mid,
            inventory_base=inventory_base,
            ts=ts,
        )


@dataclass(frozen=True)
class HedgeDecision:
    should_hedge: bool
    reason: str
    token_in_is_token0: bool | None
    amount_in: int
    amount_out: int
    fair_out: int
    min_amount_out: int
    basis_bps: int
    profit: int


def amm_spot_wad(reserve0: int, reserve1: int) -> int:
    if reserve0 <= 0:
        raise ValueError("reserve0 must be > 0")
    return (reserve1 * WAD) // reserve0


def basis_bps(reserve0: int, reserve1: int, mid: int) -> int:
    """Signed (amm_spot - mid) / mid in bps."""
    if mid <= 0:
        raise ValueError("mid must be > 0")
    spot = amm_spot_wad(reserve0, reserve1)
    if spot >= mid:
        return ((spot - mid) * BPS) // mid
    return -(((mid - spot) * BPS) // mid)


def fair_out(amount_in: int, mid: int, token_in_is_token0: bool) -> int:
    if mid <= 0:
        raise ValueError("mid must be > 0")
    if token_in_is_token0:
        return (amount_in * mid) // WAD
    return (amount_in * WAD) // mid


def size_hedge(
    *,
    base_amount_in: int,
    inventory_base: int,
    basis_bps_signed: int,
    max_inventory_base: int,
    inventory_skew_bps: int = 25,
) -> int:
    """Scale hedge size by |basis| and inventory pressure (AS-style intuition).

    - Larger |basis| → larger size (up to 2x)
    - Inventory on the same side as the sell leg → larger size (reduce risk)
    - Inventory against the sell leg → smaller size (down to 0.5x)
    """
    if base_amount_in <= 0:
        return 0
    abs_basis = abs(basis_bps_signed)
    basis_mult = min(2.0, 1.0 + abs_basis / 500.0)

    # Positive basis ⇒ sell token0; long inventory_base reinforces that hedge.
    selling_token0 = basis_bps_signed > 0
    inv_frac = 0.0
    if max_inventory_base > 0:
        inv_frac = max(-1.0, min(1.0, inventory_base / float(max_inventory_base)))
    inv_sign = 1.0 if selling_token0 else -1.0
    inv_mult = 1.0 + inv_sign * inv_frac * (inventory_skew_bps / 100.0)
    inv_mult = max(0.5, min(1.5, inv_mult))

    sized = int(base_amount_in * basis_mult * inv_mult)
    return max(1, sized) if base_amount_in > 0 else 0


def decide_hedge(
    *,
    reserve0: int,
    reserve1: int,
    fee_bps: int,
    snap: BookSnapshot,
    amount_in: int,
    min_basis_bps: int = 10,
    slippage_bps: int = 50,
    min_profit_out: int = 0,
    max_inventory_base: int = 10**30,
    max_snapshot_age: int = 30,
    now_ts: int | None = None,
    apply_inventory_skew: bool = False,
) -> HedgeDecision:
    """Decide whether to sell token0 or token1 into the AMM given CLOB mid."""
    if now_ts is not None:
        if snap.ts == 0 or now_ts > snap.ts + max_snapshot_age:
            return HedgeDecision(False, "stale_clob", None, 0, 0, 0, 0, 0, 0)

    if snap.inventory_base > max_inventory_base:
        return HedgeDecision(False, "inventory_cap", None, 0, 0, 0, 0, 0, 0)

    if reserve0 <= 0 or reserve1 <= 0:
        return HedgeDecision(False, "empty_pool", None, 0, 0, 0, 0, 0, 0)

    bps = basis_bps(reserve0, reserve1, snap.mid)
    abs_bps = abs(bps)
    if abs_bps < min_basis_bps:
        return HedgeDecision(False, "basis_too_small", None, 0, 0, 0, 0, bps, 0)

    sized_in = amount_in
    if apply_inventory_skew:
        sized_in = size_hedge(
            base_amount_in=amount_in,
            inventory_base=snap.inventory_base,
            basis_bps_signed=bps,
            max_inventory_base=max_inventory_base if max_inventory_base < 10**30 else max(abs(snap.inventory_base), 1) * 2 or 1,
        )

    token0_in = bps > 0
    if token0_in:
        out = get_amount_out(sized_in, reserve0, reserve1, fee_bps)
    else:
        out = get_amount_out(sized_in, reserve1, reserve0, fee_bps)

    fair = fair_out(sized_in, snap.mid, token0_in)
    profit = out - fair
    min_out = (out * (BPS - slippage_bps)) // BPS

    if out < fair + min_profit_out:
        return HedgeDecision(
            False, "profit_guard", token0_in, sized_in, out, fair, min_out, bps, profit
        )

    return HedgeDecision(
        True, "ok", token0_in, sized_in, out, fair, min_out, bps, profit
    )
