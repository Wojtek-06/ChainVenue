// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";
import {KillSwitch} from "../../src/adapters/KillSwitch.sol";
import {AtomicArbExecutor} from "../../src/exec/AtomicArbExecutor.sol";

contract AtomicArbExecutorTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    ConstantProductAMM internal poolFair;
    ConstantProductAMM internal poolSkewed;
    KillSwitch internal ks;
    AtomicArbExecutor internal exec;
    address internal t0;

    function setUp() public {
        tokenA = new MockERC20("A", "A", 18);
        tokenB = new MockERC20("B", "B", 18);

        poolFair = new ConstantProductAMM(address(tokenA), address(tokenB), 30);
        poolSkewed = new ConstantProductAMM(address(tokenA), address(tokenB), 30);

        tokenA.mint(address(this), 10_000_000 ether);
        tokenB.mint(address(this), 10_000_000 ether);
        tokenA.approve(address(poolFair), type(uint256).max);
        tokenB.approve(address(poolFair), type(uint256).max);
        tokenA.approve(address(poolSkewed), type(uint256).max);
        tokenB.approve(address(poolSkewed), type(uint256).max);

        poolFair.addLiquidity(100_000 ether, 100_000 ether, address(this));
        poolSkewed.addLiquidity(80_000 ether, 120_000 ether, address(this));

        ks = new KillSwitch(address(this));
        exec = new AtomicArbExecutor(ks, address(this));
        tokenA.approve(address(exec), type(uint256).max);
        tokenB.approve(address(exec), type(uint256).max);
        t0 = poolFair.token0();

        vm.txGasPrice(1 gwei);
    }

    function test_twoPoolArbProfitable() public {
        uint256 balBefore = MockERC20(t0).balanceOf(address(this));
        uint256 profit =
            exec.executeTwoPool(address(poolSkewed), address(poolFair), t0, 100 ether, 1, 0);
        uint256 balAfter = MockERC20(t0).balanceOf(address(this));
        assertGt(profit, 0);
        assertEq(balAfter - balBefore, profit);
    }

    function test_killSwitchBlocksArb() public {
        ks.trip("halt");
        vm.expectRevert(AtomicArbExecutor.KillActive.selector);
        exec.executeTwoPool(address(poolSkewed), address(poolFair), t0, 10 ether, 1, 0);
    }

    function test_gasCapBlocksArb() public {
        vm.expectRevert(AtomicArbExecutor.GasCap.selector);
        exec.executeTwoPool(address(poolSkewed), address(poolFair), t0, 10 ether, 1, 0.5 gwei);
    }

    function test_minProfitTooHighReverts() public {
        vm.expectRevert();
        exec.executeTwoPool(address(poolSkewed), address(poolFair), t0, 100 ether, 50_000 ether, 0);
    }
}
