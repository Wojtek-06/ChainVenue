// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";

/// @notice Measures inclusion delay / reorg-style rollback impact on a pending hedge intent.
/// @dev Anvil cheatcodes only — stands in for RPC delay / reorg risk called out in the sprint plan.
contract InclusionReorgTest is Test {
    ConstantProductAMM internal pool;
    address internal t0;
    address internal trader = address(0xBEEF);

    function setUp() public {
        MockERC20 a = new MockERC20("A", "A", 18);
        MockERC20 b = new MockERC20("B", "B", 18);
        pool = new ConstantProductAMM(address(a), address(b), 30);
        t0 = pool.token0();
        a.mint(address(this), 1_000_000 ether);
        b.mint(address(this), 1_000_000 ether);
        a.approve(address(pool), type(uint256).max);
        b.approve(address(pool), type(uint256).max);
        pool.addLiquidity(50_000 ether, 50_000 ether, address(this));

        MockERC20(t0).mint(trader, 1000 ether);
        vm.prank(trader);
        MockERC20(t0).approve(address(pool), type(uint256).max);
    }

    function test_delayedInclusionGetsWorseFill() public {
        uint256 amountIn = 100 ether;
        (uint112 r0, uint112 r1,) = pool.getReserves();
        uint256 quoteAtSignal = pool.getAmountOut(amountIn, r0, r1);

        // Competing flow lands first (simulates loser inclusion / mempool delay).
        address competitor = address(0xC0FFEE);
        MockERC20(t0).mint(competitor, 5000 ether);
        vm.startPrank(competitor);
        MockERC20(t0).approve(address(pool), type(uint256).max);
        pool.swapExactIn(t0, 2000 ether, 0, competitor);
        vm.stopPrank();

        (uint112 r0b, uint112 r1b,) = pool.getReserves();
        uint256 quoteAfterDelay = pool.getAmountOut(amountIn, r0b, r1b);
        assertLt(quoteAfterDelay, quoteAtSignal);

        // Trader protected by slippage floor sized at signal time.
        uint256 minOut = (quoteAtSignal * 9900) / 10_000;
        vm.prank(trader);
        vm.expectRevert(ConstantProductAMM.InsufficientOutputAmount.selector);
        pool.swapExactIn(t0, amountIn, minOut, trader);
    }

    function test_reorgRollsBackSwapState() public {
        uint256 snapshotId = vm.snapshotState();

        vm.prank(trader);
        pool.swapExactIn(t0, 50 ether, 0, trader);
        (uint112 r0After,,) = pool.getReserves();

        vm.revertToState(snapshotId);
        (uint112 r0Reorg,,) = pool.getReserves();
        assertLt(uint256(r0Reorg), uint256(r0After));
        assertEq(uint256(r0Reorg), 50_000 ether);
    }
}
