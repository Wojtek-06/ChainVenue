// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClobVenue} from "./IClobVenue.sol";

/// @title ICrossVenueAdapter
/// @notice Skeleton for CLOB↔AMM hedge / quote linkage (capstone; not wired yet).
interface ICrossVenueAdapter {
    struct HedgeIntent {
        address pool;
        address tokenIn;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 maxGasWei;
        int256 maxInventoryBase;
        bytes32 idempotencyKey;
    }

    event KillSwitchTripped(address indexed by, string reason);
    event HedgeProposed(bytes32 indexed key, address pool, uint256 amountIn, uint256 minOut);
    event HedgeSkipped(bytes32 indexed key, string reason);

    function clob() external view returns (IClobVenue);
    function killSwitchActive() external view returns (bool);

    /// @notice Evaluate whether a hedge should fire given CLOB + AMM state (stub returns false).
    function shouldHedge(HedgeIntent calldata intent)
        external
        view
        returns (bool ok, string memory reason);

    /// @notice Propose a hedge; MVP only records intent / emits — no live execution.
    function proposeHedge(HedgeIntent calldata intent) external returns (bool accepted);
}
