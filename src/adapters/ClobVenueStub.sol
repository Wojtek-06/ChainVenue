// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClobVenue} from "./IClobVenue.sol";

/// @notice Push-based snapshot feed for Anvil / fork labs (synth or QuantForge-shaped JSON).
contract ClobVenueStub is IClobVenue {
    BookSnapshot private _snap;
    address public updater;

    event SnapshotUpdated(uint256 mid, int256 inventoryBase, uint64 ts);

    error NotUpdater();

    constructor(address updater_) {
        updater = updater_ == address(0) ? msg.sender : updater_;
    }

    function setUpdater(address updater_) external {
        if (msg.sender != updater) revert NotUpdater();
        updater = updater_;
    }

    function pushSnapshot(BookSnapshot calldata snap) external {
        if (msg.sender != updater) revert NotUpdater();
        _snap = snap;
        emit SnapshotUpdated(snap.mid, snap.inventoryBase, snap.ts);
    }

    function latestSnapshot() external view returns (BookSnapshot memory) {
        return _snap;
    }

    function isFresh(uint64 maxAgeSeconds) external view returns (bool) {
        if (_snap.ts == 0) return false;
        return block.timestamp <= uint256(_snap.ts) + uint256(maxAgeSeconds);
    }
}
