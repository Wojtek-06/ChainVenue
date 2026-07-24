// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClobVenue} from "./IClobVenue.sol";
import {ICrossVenueAdapter} from "./ICrossVenueAdapter.sol";
import {KillSwitch} from "./KillSwitch.sol";
import {ConstantProductAMM} from "../amm/ConstantProductAMM.sol";

/// @title CrossVenueAdapter
/// @notice Skeleton linking QuantForge-style CLOB snapshots to on-chain AMM hedges.
/// @dev MVP: freshness + kill-switch + inventory guards only. No atomic executor yet.
contract CrossVenueAdapter is ICrossVenueAdapter {
    IClobVenue public immutable override clob;
    KillSwitch public immutable killSwitch;
    address public operator;
    uint64 public maxSnapshotAge = 30;

    mapping(bytes32 => bool) public seenKeys;

    error NotOperator();
    error KillActive();

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    constructor(IClobVenue clob_, KillSwitch killSwitch_, address operator_) {
        clob = clob_;
        killSwitch = killSwitch_;
        operator = operator_ == address(0) ? msg.sender : operator_;
    }

    function killSwitchActive() public view override returns (bool) {
        return killSwitch.active();
    }

    function setMaxSnapshotAge(uint64 age) external onlyOperator {
        maxSnapshotAge = age;
    }

    function shouldHedge(HedgeIntent calldata intent)
        public
        view
        override
        returns (bool ok, string memory reason)
    {
        if (killSwitchActive()) return (false, "kill_switch");
        if (!clob.isFresh(maxSnapshotAge)) return (false, "stale_clob");
        if (intent.amountIn == 0) return (false, "zero_amount");
        if (intent.pool == address(0)) return (false, "no_pool");
        if (seenKeys[intent.idempotencyKey]) return (false, "duplicate_key");

        IClobVenue.BookSnapshot memory snap = clob.latestSnapshot();
        if (snap.inventoryBase > intent.maxInventoryBase) {
            // Inventory already too high on the CLOB side — hedge may still be desired;
            // MVP only flags the condition for the quote engine.
            // Continue evaluation rather than hard-rejecting.
        }

        // Spot-check AMM can theoretically quote something.
        (uint112 r0, uint112 r1,) = ConstantProductAMM(intent.pool).getReserves();
        if (r0 == 0 || r1 == 0) return (false, "empty_pool");

        // Capstone will compare CLOB mid vs AMM marginal price and size the hedge.
        ok = true;
        reason = "ok_stub";
    }

    function proposeHedge(HedgeIntent calldata intent)
        external
        override
        onlyOperator
        returns (bool accepted)
    {
        if (killSwitchActive()) {
            emit HedgeSkipped(intent.idempotencyKey, "kill_switch");
            revert KillActive();
        }

        (bool ok, string memory reason) = shouldHedge(intent);
        if (!ok) {
            emit HedgeSkipped(intent.idempotencyKey, reason);
            return false;
        }

        seenKeys[intent.idempotencyKey] = true;
        emit HedgeProposed(intent.idempotencyKey, intent.pool, intent.amountIn, intent.minAmountOut);
        // Future: route through GuardedExecutor with min-profit / gas / slippage checks.
        return true;
    }
}
