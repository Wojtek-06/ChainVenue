// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";

contract AmmHandler is Test {
    ConstantProductAMM public immutable amm;
    MockERC20 public immutable token0;
    MockERC20 public immutable token1;
    address public immutable actor;

    constructor(ConstantProductAMM amm_, address actor_) {
        amm = amm_;
        token0 = MockERC20(amm_.token0());
        token1 = MockERC20(amm_.token1());
        actor = actor_;
    }

    function swap0to1(uint256 amountIn) external {
        amountIn = bound(amountIn, 1, 5 ether);
        (uint112 r0, uint112 r1,) = amm.getReserves();
        if (r0 == 0 || r1 == 0) return;
        uint256 bal = token0.balanceOf(actor);
        if (bal < amountIn) amountIn = bal;
        if (amountIn == 0) return;

        vm.prank(actor);
        try amm.swapExactIn(address(token0), amountIn, 0, actor) {} catch {}
    }

    function swap1to0(uint256 amountIn) external {
        amountIn = bound(amountIn, 1, 5 ether);
        (uint112 r0, uint112 r1,) = amm.getReserves();
        if (r0 == 0 || r1 == 0) return;
        uint256 bal = token1.balanceOf(actor);
        if (bal < amountIn) amountIn = bal;
        if (amountIn == 0) return;

        vm.prank(actor);
        try amm.swapExactIn(address(token1), amountIn, 0, actor) {} catch {}
    }
}

contract ConstantProductAMMInvariantTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    ConstantProductAMM internal amm;
    AmmHandler internal handler;
    address internal lp;
    address internal trader;
    uint256 internal initialK;

    function setUp() public {
        lp = makeAddr("lp");
        trader = makeAddr("trader");
        tokenA = new MockERC20("A", "A", 18);
        tokenB = new MockERC20("B", "B", 18);
        amm = new ConstantProductAMM(address(tokenA), address(tokenB), 30);

        tokenA.mint(lp, 1_000_000 ether);
        tokenB.mint(lp, 1_000_000 ether);
        tokenA.mint(trader, 100_000 ether);
        tokenB.mint(trader, 100_000 ether);

        vm.startPrank(lp);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1000 ether, 1000 ether, lp);
        vm.stopPrank();

        vm.startPrank(trader);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        (uint112 r0, uint112 r1,) = amm.getReserves();
        initialK = uint256(r0) * uint256(r1);

        handler = new AmmHandler(amm, trader);
        targetContract(address(handler));
    }

    function invariant_kNonDecreasing() public view {
        (uint112 r0, uint112 r1,) = amm.getReserves();
        uint256 k = uint256(r0) * uint256(r1);
        assertGe(k, initialK);
    }

    function invariant_reservesMatchBalances() public view {
        (uint112 r0, uint112 r1,) = amm.getReserves();
        assertEq(uint256(r0), MockERC20(amm.token0()).balanceOf(address(amm)));
        assertEq(uint256(r1), MockERC20(amm.token1()).balanceOf(address(amm)));
    }

    function invariant_totalSupplyCoversLockedLiquidity() public view {
        assertGe(amm.totalSupply(), amm.MINIMUM_LIQUIDITY());
    }
}
