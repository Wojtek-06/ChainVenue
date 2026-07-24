"""QuantForge-shaped CLOB snapshot feed.

Does not import or modify QuantForge by default. Accepts:
  - synthetic drifting mids (default / CI)
  - JSON metrics dicts with QuantForge-like keys
  - optional live `quantforge` native module if importable on PYTHONPATH
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator

from .quote_engine import BPS, WAD, BookSnapshot

SOURCE_SYNTH = b"synth"
SOURCE_QF_JSON = b"quantforge-json"
SOURCE_QF_NATIVE = b"quantforge"


@dataclass(frozen=True)
class FeedConfig:
    base_mid_wad: int = WAD
    inventory_base: int = 0
    spread_bps: int = 100
    # Synthetic mispricing vs a 1.0 AMM spot (negative ⇒ mid below spot).
    misprice_bps: int = -500
    step_interval_sec: float = 0.0


def _book(
    *,
    mid: int,
    inventory_base: int,
    ts: int,
    spread_bps: int,
    source_id: bytes,
    best_bid: int | None = None,
    best_ask: int | None = None,
    microprice: int | None = None,
) -> BookSnapshot:
    half = (mid * spread_bps) // (2 * BPS)
    return BookSnapshot(
        best_bid=mid - half if best_bid is None else best_bid,
        best_ask=mid + half if best_ask is None else best_ask,
        mid=mid,
        microprice=mid if microprice is None else microprice,
        inventory_base=inventory_base,
        ts=ts,
        source_id=source_id,
    )


def snapshot_from_metrics(metrics: dict[str, Any], *, ts: int | None = None) -> BookSnapshot:
    """Map a QuantForge-like metrics dict into BookSnapshot.

    Mid keys: mid, mid_px, microprice, fair_price, mark, price
    Inventory: inventory_base, inventory, position, base_inventory
    """
    mid_raw = _first_number(
        metrics, ("mid", "mid_px", "microprice", "fair_price", "mark", "price")
    )
    if mid_raw is None:
        raise ValueError("metrics missing mid/price field")

    mid_wad = _to_wad(mid_raw)
    inv = int(
        _first_number(
            metrics,
            ("inventory_base", "inventory", "position", "base_inventory"),
            default=0,
        )
        or 0
    )
    now = int(ts if ts is not None else metrics.get("ts", time.time()))
    spread_bps = int(metrics.get("spread_bps", 100))

    bid_raw = _first_number(metrics, ("best_bid", "bid"))
    ask_raw = _first_number(metrics, ("best_ask", "ask"))
    micro_raw = metrics.get("microprice")

    return _book(
        mid=mid_wad,
        inventory_base=inv,
        ts=now,
        spread_bps=spread_bps,
        source_id=SOURCE_QF_JSON,
        best_bid=_to_wad(bid_raw) if bid_raw is not None else None,
        best_ask=_to_wad(ask_raw) if ask_raw is not None else None,
        microprice=_to_wad(micro_raw) if micro_raw is not None else None,
    )


def snapshot_from_json_file(path: str | Path, *, ts: int | None = None) -> BookSnapshot:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    metrics = _dig_qf_payload(data) if "experiment" in data else data
    return snapshot_from_metrics(metrics, ts=ts)


def try_snapshot_from_native(
    *,
    horizon: int = 200,
    seed: int = 42,
    strategy: str = "avellaneda_stoikov",
) -> BookSnapshot | None:
    """Best-effort pull from QuantForge pybind if available on PYTHONPATH."""
    try:
        import quantforge  # type: ignore
    except Exception:
        return None
    if not getattr(quantforge, "available", lambda: False)():
        return None

    result = quantforge.run_simulation(seed=seed, horizon=horizon, strategy=strategy)
    metrics: dict[str, Any]
    if isinstance(result, dict):
        metrics = result
    else:
        metrics = {"mid": 1.0, "inventory": 0}

    if not any(k in metrics for k in ("mid", "mid_px", "fair_price", "mark", "price", "microprice")):
        inv = int(metrics.get("inventory", metrics.get("final_inventory", 0)) or 0)
        return _book(
            mid=WAD,
            inventory_base=inv,
            ts=int(time.time()),
            spread_bps=100,
            source_id=SOURCE_QF_NATIVE,
        )

    snap = snapshot_from_metrics(metrics)
    return _book(
        mid=snap.mid,
        inventory_base=snap.inventory_base,
        ts=snap.ts,
        spread_bps=100,
        source_id=SOURCE_QF_NATIVE,
        best_bid=snap.best_bid,
        best_ask=snap.best_ask,
        microprice=snap.microprice,
    )


def iter_synthetic_snapshots(cfg: FeedConfig | None = None) -> Iterator[BookSnapshot]:
    """Yield synthetic QuantForge-shaped snapshots (mispriced vs 1.0 AMM spot)."""
    cfg = cfg or FeedConfig()
    mid = (cfg.base_mid_wad * (BPS + cfg.misprice_bps)) // BPS
    step = 0
    while True:
        wobble = (step % 11 - 5) * cfg.base_mid_wad // 10_000
        yield _book(
            mid=mid + wobble,
            inventory_base=cfg.inventory_base + step,
            ts=int(time.time()),
            spread_bps=cfg.spread_bps,
            source_id=SOURCE_SYNTH,
        )
        step += 1
        if cfg.step_interval_sec > 0:
            time.sleep(cfg.step_interval_sec)


def _dig_qf_payload(data: dict[str, Any]) -> dict[str, Any]:
    exp = data.get("experiment") or {}
    if not isinstance(exp, dict):
        return data
    for key in ("metrics", "result", "summary"):
        if isinstance(exp.get(key), dict):
            return exp[key]
    strats = exp.get("strategies") or exp.get("results")
    if isinstance(strats, dict) and strats:
        first = next(iter(strats.values()))
        if isinstance(first, dict):
            return first
    if isinstance(strats, list) and strats and isinstance(strats[0], dict):
        return strats[0]
    return data


def _first_number(
    d: dict[str, Any],
    keys: tuple[str, ...],
    default: float | int | None = None,
) -> float | int | None:
    for k in keys:
        if k in d and d[k] is not None:
            return d[k]
    return default


def _to_wad(x: float | int) -> int:
    if isinstance(x, int):
        if abs(x) >= 10**12:
            return int(x)
        return int(x) * WAD
    return int(float(x) * WAD)
