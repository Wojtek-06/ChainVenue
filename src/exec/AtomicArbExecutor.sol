// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ConstantProductAMM} from "../amm/ConstantProductAMM.sol";
import {KillSwitch} from "../adapters/KillSwitch.sol";

interface IERC20Exec {
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title AtomicArbExecutor
/// @notice Two-pool CPAMM round-trip arb with min-profit / gas / kill-switch guards.
/// @dev Local Anvil / fork only. Not live MEV against real users.
///
/// Flow (tokenBorrow start):
///   1) Sell tokenBorrow on `poolSell` → intermediate token
///   2) Sell intermediate on `poolBuyBack` → tokenBorrow to operator
/// Profit if final tokenBorrow ≥ amountIn + minProfit.
contract AtomicArbExecutor {
    KillSwitch public immutable killSwitch;
    address public operator;

    event ArbExecuted(
        address indexed poolSell,
        address indexed poolBuyBack,
        address tokenBorrow,
        uint256 amountIn,
        uint256 amountOut,
        uint256 profit
    );
    event ArbSkipped(string reason);

    error NotOperator();
    error KillActive();
    error GasCap();
    error NoProfit();
    error TransferFailed();
    error ApproveFailed();
    error BadPools();

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    constructor(KillSwitch killSwitch_, address operator_) {
        killSwitch = killSwitch_;
        operator = operator_ == address(0) ? msg.sender : operator_;
    }

    function setOperator(address who) external onlyOperator {
        operator = who;
    }

    function executeTwoPool(
        address poolSell,
        address poolBuyBack,
        address tokenBorrow,
        uint256 amountIn,
        uint256 minProfit,
        uint256 maxGasWei
    ) external onlyOperator returns (uint256 profit) {
        if (killSwitch.active()) {
            emit ArbSkipped("kill_switch");
            revert KillActive();
        }
        if (maxGasWei > 0 && tx.gasprice > maxGasWei) {
            emit ArbSkipped("gas_cap");
            revert GasCap();
        }
        if (poolSell == poolBuyBack || amountIn == 0) revert BadPools();

        ConstantProductAMM sell = ConstantProductAMM(poolSell);
        ConstantProductAMM buy = ConstantProductAMM(poolBuyBack);
        if (sell.token0() != buy.token0() || sell.token1() != buy.token1()) revert BadPools();
        if (tokenBorrow != sell.token0() && tokenBorrow != sell.token1()) revert BadPools();

        address tokenMid = tokenBorrow == sell.token0() ? sell.token1() : sell.token0();

        IERC20Exec borrowTok = IERC20Exec(tokenBorrow);
        IERC20Exec midTok = IERC20Exec(tokenMid);

        if (!_transferFrom(borrowTok, msg.sender, address(this), amountIn)) {
            revert TransferFailed();
        }
        _forceApprove(borrowTok, poolSell, amountIn);

        uint256 midOut = sell.swapExactIn(tokenBorrow, amountIn, 1, address(this));
        _forceApprove(midTok, poolBuyBack, midOut);

        uint256 endBal = buy.swapExactIn(tokenMid, midOut, amountIn + minProfit, msg.sender);
        if (endBal < amountIn + minProfit) revert NoProfit();

        profit = endBal - amountIn;
        emit ArbExecuted(poolSell, poolBuyBack, tokenBorrow, amountIn, endBal, profit);
    }

    function _transferFrom(IERC20Exec token, address from, address to, uint256 amount)
        private
        returns (bool)
    {
        (bool ok, bytes memory data) = address(token)
            .call(abi.encodeWithSelector(token.transferFrom.selector, from, to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _forceApprove(IERC20Exec token, address spender, uint256 amount) private {
        (bool ok1,) =
            address(token).call(abi.encodeWithSelector(token.approve.selector, spender, 0));
        (bool ok2, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.approve.selector, spender, amount));
        if (!(ok1 && ok2 && (data.length == 0 || abi.decode(data, (bool))))) {
            revert ApproveFailed();
        }
    }
}
