// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";

/// @notice Local sandwich-ordering simulation: slippage floor protects the victim.
/// @dev Analysis only — never run extractive MEV against live users.
contract SandwichSimTest is Test {
    MockERC20 internal token0;
    MockERC20 internal token1;
    ConstantProductAMM internal pool;
    address internal attacker;
    address internal victim;

    function setUp() public {
        attacker = makeAddr("attacker");
        victim = makeAddr("victim");
        MockERC20 a = new MockERC20("A", "A", 18);
        MockERC20 b = new MockERC20("B", "B", 18);
        pool = new ConstantProductAMM(address(a), address(b), 30);
        token0 = MockERC20(pool.token0());
        token1 = MockERC20(pool.token1());

        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        pool.addLiquidity(1000 ether, 1000 ether, address(this));

        token0.mint(attacker, 500 ether);
        token0.mint(victim, 10 ether);
        vm.prank(attacker);
        token0.approve(address(pool), type(uint256).max);
        vm.prank(victim);
        token0.approve(address(pool), type(uint256).max);
    }

    function test_minAmountOutProtectsVictimFromSandwich() public {
        uint256 victimIn = 10 ether;
        uint256 honestOut = pool.getAmountOut(victimIn, 1000 ether, 1000 ether);
        // Victim tolerates 50 bps slippage vs honest quote.
        uint256 minOut = (honestOut * 9950) / 10_000;

        // Attacker front-runs a large buy of token1 (sells token0).
        vm.prank(attacker);
        pool.swapExactIn(address(token0), 200 ether, 0, attacker);

        // Victim tx lands after front-run — should revert on slippage floor.
        vm.prank(victim);
        vm.expectRevert(ConstantProductAMM.InsufficientOutputAmount.selector);
        pool.swapExactIn(address(token0), victimIn, minOut, victim);
    }

    function test_unguardedVictimReceivesWorseFill() public {
        uint256 victimIn = 10 ether;
        uint256 honestOut = pool.getAmountOut(victimIn, 1000 ether, 1000 ether);

        vm.prank(attacker);
        pool.swapExactIn(address(token0), 200 ether, 0, attacker);

        uint256 before = token1.balanceOf(victim);
        vm.prank(victim);
        uint256 out = pool.swapExactIn(address(token0), victimIn, 0, victim);
        assertEq(token1.balanceOf(victim) - before, out);
        assertLt(out, honestOut);
    }
}
