// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";

contract ConstantProductAMMTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    ConstantProductAMM internal amm;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint256 internal constant FEE_BPS = 30;

    function setUp() public {
        tokenA = new MockERC20("A", "A", 18);
        tokenB = new MockERC20("B", "B", 18);
        // Constructor sorts token0 < token1 by address.
        amm = new ConstantProductAMM(address(tokenA), address(tokenB), FEE_BPS);

        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(alice, 1_000_000 ether);
        tokenA.mint(bob, 1_000_000 ether);
        tokenB.mint(bob, 1_000_000 ether);

        vm.startPrank(alice);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function _token0() internal view returns (MockERC20) {
        return MockERC20(amm.token0());
    }

    function _token1() internal view returns (MockERC20) {
        return MockERC20(amm.token1());
    }

    function test_addLiquidityMintsShares() public {
        vm.prank(alice);
        uint256 liq = amm.addLiquidity(100 ether, 100 ether, alice);
        assertGt(liq, 0);
        assertEq(amm.balanceOf(alice), liq);
        assertEq(amm.balanceOf(address(0)), amm.MINIMUM_LIQUIDITY());
        (uint112 r0, uint112 r1,) = amm.getReserves();
        assertEq(uint256(r0), 100 ether);
        assertEq(uint256(r1), 100 ether);
    }

    function test_swapExactInMovesPrice() public {
        vm.prank(alice);
        amm.addLiquidity(100 ether, 100 ether, alice);

        uint256 amountIn = 1 ether;
        uint256 expectedOut = amm.getAmountOut(amountIn, 100 ether, 100 ether);

        uint256 balBefore = _token1().balanceOf(bob);
        address t0 = amm.token0();
        vm.prank(bob);
        uint256 out = amm.swapExactIn(t0, amountIn, 0, bob);
        assertEq(out, expectedOut);
        assertEq(_token1().balanceOf(bob) - balBefore, out);

        (uint112 r0, uint112 r1,) = amm.getReserves();
        assertGt(uint256(r0), 100 ether);
        assertLt(uint256(r1), 100 ether);
    }

    function test_removeLiquidityReturnsProRata() public {
        vm.prank(alice);
        uint256 liq = amm.addLiquidity(50 ether, 50 ether, alice);

        uint256 a0 = _token0().balanceOf(alice);
        uint256 a1 = _token1().balanceOf(alice);
        vm.prank(alice);
        (uint256 out0, uint256 out1) = amm.removeLiquidity(liq, alice);
        assertGt(out0, 0);
        assertGt(out1, 0);
        assertEq(_token0().balanceOf(alice), a0 + out0);
        assertEq(_token1().balanceOf(alice), a1 + out1);
    }

    function test_swapRevertsOnSlippage() public {
        vm.prank(alice);
        amm.addLiquidity(100 ether, 100 ether, alice);

        address t0 = amm.token0();
        vm.prank(bob);
        vm.expectRevert(ConstantProductAMM.InsufficientOutputAmount.selector);
        amm.swapExactIn(t0, 1 ether, type(uint256).max, bob);
    }

    function testFuzz_getAmountOutPositive(uint128 amountIn) public {
        // Keep amount large enough that fee-on-input still yields > 0 out.
        amountIn = uint128(bound(amountIn, 1e9, 50 ether));
        vm.prank(alice);
        amm.addLiquidity(100 ether, 200 ether, alice);

        (uint112 r0, uint112 r1,) = amm.getReserves();
        uint256 out = amm.getAmountOut(amountIn, r0, r1);
        assertGt(out, 0);
        assertLt(out, r1);
    }

    function testFuzz_kNeverDecreasesOnSwap(uint128 amountIn) public {
        amountIn = uint128(bound(amountIn, 1e9, 20 ether));
        vm.prank(alice);
        amm.addLiquidity(100 ether, 100 ether, alice);

        (uint112 r0Before, uint112 r1Before,) = amm.getReserves();
        uint256 kBefore = uint256(r0Before) * uint256(r1Before);

        address t0 = amm.token0();
        vm.prank(bob);
        amm.swapExactIn(t0, amountIn, 0, bob);

        (uint112 r0After, uint112 r1After,) = amm.getReserves();
        uint256 kAfter = uint256(r0After) * uint256(r1After);
        // Fees grow k.
        assertGe(kAfter, kBefore);
    }
}
