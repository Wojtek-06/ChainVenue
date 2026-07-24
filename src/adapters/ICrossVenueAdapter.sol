// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClobVenue} from "./IClobVenue.sol";

/// @title ICrossVenueAdapter
/// @notice CLOB↔AMM hedge / quote linkage with defensive execution guards.
interface ICrossVenueAdapter {
    /// @dev `mid` on the CLOB snapshot is token1 per token0, 1e18-scaled.
    struct HedgeIntent {
        address pool;
        address tokenIn;
        uint256 amountIn;
        uint256 minAmountOut; // AMM slippage floor
        uint256 maxGasWei; // 0 = disabled
        uint256 minProfitOut; // require amountOut >= fairOut + minProfitOut
        int256 maxInventoryBase; // reject if CLOB inventory already above this
        address to; // recipient of tokenOut
        bytes32 idempotencyKey;
    }

    event HedgeProposed(bytes32 indexed key, address pool, uint256 amountIn, uint256 minOut);
    event HedgeExecuted(
        bytes32 indexed key,
        address indexed pool,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fairOut,
        address to
    );
    event HedgeSkipped(bytes32 indexed key, string reason);

    function clob() external view returns (IClobVenue);
    function killSwitchActive() external view returns (bool);

    /// @notice Evaluate whether a hedge should fire given CLOB + AMM state.
    function shouldHedge(HedgeIntent calldata intent)
        external
        view
        returns (bool ok, string memory reason);

    /// @notice Preview AMM out vs CLOB-fair out for an intent (no state change).
    function previewHedge(HedgeIntent calldata intent)
        external
        view
        returns (uint256 amountOut, uint256 fairOut, int256 basisBps);

    /// @notice Propose and (if guards pass) execute a hedge against the AMM.
    function proposeHedge(HedgeIntent calldata intent) external returns (bool accepted);
}
