"""CPAMM reference package used by docs / vector generation."""

from __future__ import annotations

import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from reference.cpamm import (  # noqa: E402
    FEE_DENOMINATOR,
    MINIMUM_LIQUIDITY,
    burn_amounts,
    get_amount_out,
    impermanent_loss_ratio,
    mint_liquidity,
    price_impact_bps,
    quote,
    spot_price_x_per_y,
    sqrt,
)

amount_out = get_amount_out

__all__ = [
    "FEE_DENOMINATOR",
    "MINIMUM_LIQUIDITY",
    "amount_out",
    "burn_amounts",
    "get_amount_out",
    "impermanent_loss_ratio",
    "mint_liquidity",
    "price_impact_bps",
    "quote",
    "spot_price_x_per_y",
    "sqrt",
]
