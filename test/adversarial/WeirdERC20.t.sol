// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/tokens/MockERC20.sol";
import {FeeOnTransferERC20} from "../../src/tokens/FeeOnTransferERC20.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";

/// @notice Fee-on-transfer tokens break naive reserve accounting — CPAMM must revert.
contract WeirdERC20Test is Test {
    function test_feeOnTransferBreaksSwapKCheck() public {
        FeeOnTransferERC20 fot = new FeeOnTransferERC20("FoT", "FOT", 18, 100); // 1%
        MockERC20 normal = new MockERC20("N", "N", 18);
        ConstantProductAMM pool = new ConstantProductAMM(address(fot), address(normal), 30);

        fot.mint(address(this), 1000 ether);
        normal.mint(address(this), 1000 ether);
        fot.approve(address(pool), type(uint256).max);
        normal.approve(address(pool), type(uint256).max);

        // Bootstrap with FoT: pool receives less than "amount" due to fee skim.
        // addLiquidity uses transferFrom amounts then syncs to balances — may succeed
        // with skewed reserves. Subsequent exact-in swap that assumes full amountIn
        // credits should fail the k invariant when FoT is the input.
        pool.addLiquidity(100 ether, 100 ether, address(this));

        address tokenIn = address(fot);
        // If fot is token0 or token1, try swapExactIn — expect revert (InvalidK or InsufficientInput).
        vm.expectRevert();
        pool.swapExactIn(tokenIn, 1 ether, 0, address(this));
    }
}
