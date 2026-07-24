"""Helpers to push `IClobVenue.BookSnapshot` onto `ClobVenueStub` via Cast."""

from __future__ import annotations

from .quote_engine import BookSnapshot


def _i256(value: int) -> int:
    """Normalize signed int into uint256 bit-pattern for ABI (two's complement)."""
    if value >= 0:
        return value
    return (1 << 256) + value


def encode_push_snapshot_args(snap: BookSnapshot) -> tuple:
    """Positional args matching ClobVenueStub.pushSnapshot((...))."""
    source = snap.source_id
    if isinstance(source, str):
        source_bytes = source.encode()
    else:
        source_bytes = source
    # bytes32: right-pad / keccak-style fixed 32 bytes from raw label
    if len(source_bytes) > 32:
        source_bytes = source_bytes[:32]
    source_hex = "0x" + source_bytes.hex().ljust(64, "0")

    return (
        snap.best_bid,
        snap.best_ask,
        snap.mid,
        snap.microprice,
        _i256(snap.inventory_base),
        snap.ts,
        source_hex,
    )


def cast_push_snapshot_cmd(
    clob_stub: str,
    snap: BookSnapshot,
    *,
    rpc_url: str = "http://127.0.0.1:8545",
    private_key: str = "",
) -> str:
    """Build a `cast send` command string for local Anvil (does not execute)."""
    args = encode_push_snapshot_args(snap)
    # cast tuple syntax for struct
    tuple_args = (
        f"({args[0]},{args[1]},{args[2]},{args[3]},{args[4]},{args[5]},{args[6]})"
    )
    sig = "pushSnapshot((uint256,uint256,uint256,uint256,int256,uint64,bytes32))"
    parts = [
        "cast",
        "send",
        clob_stub,
        sig,
        tuple_args,
        "--rpc-url",
        rpc_url,
    ]
    if private_key:
        parts.extend(["--private-key", private_key])
    return " ".join(parts)
