// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IClobVenue
/// @notice Normalized view of an off-chain CLOB (QuantForge-shaped) for cross-venue quoting.
/// @dev Lab design: push-based snapshots (see ClobVenueStub). No live LOB in-solidity.
interface IClobVenue {
    struct BookSnapshot {
        uint256 bestBid;
        uint256 bestAsk;
        uint256 mid;
        uint256 microprice;
        int256 inventoryBase; // signed inventory in base units
        uint64 ts; // unix seconds of snapshot
        bytes32 sourceId; // e.g. keccak("quantforge")
    }

    /// @notice Latest trusted CLOB snapshot used by the quote/hedge engine.
    function latestSnapshot() external view returns (BookSnapshot memory);

    /// @notice Whether the venue feed is considered fresh for quoting.
    function isFresh(uint64 maxAgeSeconds) external view returns (bool);
}
