// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClobVenue} from "./IClobVenue.sol";
import {ICrossVenueAdapter} from "./ICrossVenueAdapter.sol";
import {KillSwitch} from "./KillSwitch.sol";
import {ConstantProductAMM} from "../amm/ConstantProductAMM.sol";

interface IERC20Adapter {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title CrossVenueAdapter
/// @notice Links QuantForge-style CLOB snapshots to on-chain AMM hedges with guards.
/// @dev Local / Anvil / fork only. No extractive live MEV.
contract CrossVenueAdapter is ICrossVenueAdapter {
    uint256 public constant WAD = 1e18;
    uint256 public constant BPS = 10_000;

    IClobVenue public immutable override clob;
    KillSwitch public immutable killSwitch;
    address public operator;

    /// @notice Minimum |AMM spot − CLOB mid| / mid in bps required to hedge.
    uint64 public minBasisBps = 10;
    uint64 public maxSnapshotAge = 30;

    mapping(bytes32 => bool) public seenKeys;

    error NotOperator();
    error KillActive();
    error GasCap();
    error Slippage();
    error ProfitGuard();
    error TransferFailed();
    error ApproveFailed();

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

    function setOperator(address who) external onlyOperator {
        operator = who;
    }

    function setMaxSnapshotAge(uint64 age) external onlyOperator {
        maxSnapshotAge = age;
    }

    function setMinBasisBps(uint64 bps) external onlyOperator {
        minBasisBps = bps;
    }

    /// @inheritdoc ICrossVenueAdapter
    function previewHedge(HedgeIntent calldata intent)
        public
        view
        override
        returns (uint256 amountOut, uint256 fairOut, int256 basisBps)
    {
        ConstantProductAMM pool = ConstantProductAMM(intent.pool);
        (uint112 r0, uint112 r1,) = pool.getReserves();
        bool token0In = intent.tokenIn == pool.token0();
        require(token0In || intent.tokenIn == pool.token1(), "TOKEN");

        if (token0In) {
            amountOut = pool.getAmountOut(intent.amountIn, r0, r1);
        } else {
            amountOut = pool.getAmountOut(intent.amountIn, r1, r0);
        }

        IClobVenue.BookSnapshot memory snap = clob.latestSnapshot();
        fairOut = _fairOut(intent.tokenIn, pool.token0(), intent.amountIn, snap.mid);
        basisBps = _basisBps(r0, r1, snap.mid);
    }

    /// @inheritdoc ICrossVenueAdapter
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
        if (intent.to == address(0)) return (false, "no_recipient");
        if (seenKeys[intent.idempotencyKey]) return (false, "duplicate_key");
        if (intent.maxGasWei > 0 && tx.gasprice > intent.maxGasWei) {
            return (false, "gas_cap");
        }

        IClobVenue.BookSnapshot memory snap = clob.latestSnapshot();
        if (snap.mid == 0) return (false, "zero_mid");
        if (snap.inventoryBase > intent.maxInventoryBase) return (false, "inventory_cap");

        ConstantProductAMM pool = ConstantProductAMM(intent.pool);
        (uint112 r0, uint112 r1,) = pool.getReserves();
        if (r0 == 0 || r1 == 0) return (false, "empty_pool");

        bool token0In = intent.tokenIn == pool.token0();
        if (!token0In && intent.tokenIn != pool.token1()) return (false, "bad_token");

        int256 basisBps = _basisBps(r0, r1, snap.mid);
        uint256 absBasis = basisBps >= 0 ? uint256(basisBps) : uint256(-basisBps);
        if (absBasis < minBasisBps) return (false, "basis_too_small");

        // Sell the rich AMM leg: positive basis ⇒ sell token0; negative ⇒ sell token1.
        if (basisBps > 0 && !token0In) return (false, "wrong_side");
        if (basisBps < 0 && token0In) return (false, "wrong_side");

        (uint256 amountOut, uint256 fairOut,) = previewHedge(intent);
        if (amountOut < intent.minAmountOut) return (false, "slippage");
        if (amountOut < fairOut + intent.minProfitOut) return (false, "profit_guard");

        return (true, "ok");
    }

    /// @inheritdoc ICrossVenueAdapter
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

        emit HedgeProposed(intent.idempotencyKey, intent.pool, intent.amountIn, intent.minAmountOut);

        (, uint256 fairOut,) = previewHedge(intent);
        uint256 amountOut = _pullAndSwap(intent);

        if (amountOut < fairOut + intent.minProfitOut) revert ProfitGuard();

        seenKeys[intent.idempotencyKey] = true;
        emit HedgeExecuted(
            intent.idempotencyKey,
            intent.pool,
            intent.tokenIn,
            intent.amountIn,
            amountOut,
            fairOut,
            intent.to
        );
        return true;
    }

    function _pullAndSwap(HedgeIntent calldata intent) private returns (uint256 out) {
        if (intent.maxGasWei > 0 && tx.gasprice > intent.maxGasWei) revert GasCap();

        IERC20Adapter tokenIn = IERC20Adapter(intent.tokenIn);
        if (!_transferFrom(tokenIn, msg.sender, address(this), intent.amountIn)) {
            revert TransferFailed();
        }
        _forceApprove(tokenIn, intent.pool, intent.amountIn);

        out = ConstantProductAMM(intent.pool)
            .swapExactIn(intent.tokenIn, intent.amountIn, intent.minAmountOut, intent.to);
        if (out < intent.minAmountOut) revert Slippage();
    }

    function _fairOut(address tokenIn, address token0, uint256 amountIn, uint256 mid)
        private
        pure
        returns (uint256)
    {
        if (mid == 0) return 0;
        if (tokenIn == token0) {
            return (amountIn * mid) / WAD;
        }
        return (amountIn * WAD) / mid;
    }

    /// @dev (ammSpot − mid) / mid in bps, signed. ammSpot = reserve1/reserve0 (WAD).
    function _basisBps(uint112 r0, uint112 r1, uint256 mid) private pure returns (int256) {
        if (r0 == 0 || mid == 0) return 0;
        uint256 ammSpot = (uint256(r1) * WAD) / uint256(r0);
        if (ammSpot >= mid) {
            return int256(((ammSpot - mid) * BPS) / mid);
        }
        return -int256(((mid - ammSpot) * BPS) / mid);
    }

    function _transferFrom(IERC20Adapter token, address from, address to, uint256 amount)
        private
        returns (bool)
    {
        (bool ok, bytes memory data) = address(token)
            .call(abi.encodeWithSelector(token.transferFrom.selector, from, to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _forceApprove(IERC20Adapter token, address spender, uint256 amount) private {
        (bool ok1,) =
            address(token).call(abi.encodeWithSelector(token.approve.selector, spender, 0));
        (bool ok2, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.approve.selector, spender, amount));
        if (!(ok1 && ok2 && (data.length == 0 || abi.decode(data, (bool))))) {
            revert ApproveFailed();
        }
    }
}
