// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";
import {IClobVenue} from "../../src/adapters/IClobVenue.sol";
import {ICrossVenueAdapter} from "../../src/adapters/ICrossVenueAdapter.sol";
import {ClobVenueStub} from "../../src/adapters/ClobVenueStub.sol";
import {KillSwitch} from "../../src/adapters/KillSwitch.sol";
import {CrossVenueAdapter} from "../../src/adapters/CrossVenueAdapter.sol";

contract CrossVenueAdapterTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    ClobVenueStub internal clob;
    KillSwitch internal ks;
    CrossVenueAdapter internal adapter;
    ConstantProductAMM internal pool;

    address internal operator = address(this);

    function setUp() public {
        tokenA = new MockERC20("A", "A", 18);
        tokenB = new MockERC20("B", "B", 18);
        // Equal pool ⇒ AMM spot = 1e18 (token1 per token0).
        pool = new ConstantProductAMM(address(tokenA), address(tokenB), 30);
        tokenA.mint(operator, 1_000_000 ether);
        tokenB.mint(operator, 1_000_000 ether);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        pool.addLiquidity(100 ether, 100 ether, operator);

        ks = new KillSwitch(operator);
        clob = new ClobVenueStub(operator);
        adapter = new CrossVenueAdapter(clob, ks, operator);

        // Adapter pulls tokenIn from operator.
        tokenA.approve(address(adapter), type(uint256).max);
        tokenB.approve(address(adapter), type(uint256).max);

        vm.warp(1_700_000_000);
        vm.txGasPrice(1 gwei);
    }

    function _snap(uint256 mid, int256 inventory)
        internal
        view
        returns (IClobVenue.BookSnapshot memory)
    {
        return IClobVenue.BookSnapshot({
            bestBid: mid * 99 / 100,
            bestAsk: mid * 101 / 100,
            mid: mid,
            microprice: mid,
            inventoryBase: inventory,
            ts: uint64(block.timestamp),
            sourceId: keccak256("quantforge")
        });
    }

    /// @dev CLOB mid below AMM spot ⇒ sell token0 on AMM (positive basis).
    function _mispricedSellToken0() internal {
        clob.pushSnapshot(_snap(0.95e18, 0));
    }

    function _intent(bytes32 key, address tokenIn, uint256 minOut, uint256 minProfit)
        internal
        view
        returns (ICrossVenueAdapter.HedgeIntent memory)
    {
        return ICrossVenueAdapter.HedgeIntent({
            pool: address(pool),
            tokenIn: tokenIn,
            amountIn: 1 ether,
            minAmountOut: minOut,
            maxGasWei: 0,
            minProfitOut: minProfit,
            maxInventoryBase: 100e18,
            to: operator,
            idempotencyKey: key
        });
    }

    function test_rejectsWhenStale() public {
        (bool ok, string memory reason) =
            adapter.shouldHedge(_intent(keccak256("k1"), pool.token0(), 1, 0));
        assertFalse(ok);
        assertEq(reason, "stale_clob");
    }

    function test_rejectsBasisTooSmall() public {
        clob.pushSnapshot(_snap(1e18, 0)); // mid == AMM spot
        (bool ok, string memory reason) =
            adapter.shouldHedge(_intent(keccak256("k1b"), pool.token0(), 1, 0));
        assertFalse(ok);
        assertEq(reason, "basis_too_small");
    }

    function test_rejectsWrongSide() public {
        _mispricedSellToken0();
        (bool ok, string memory reason) =
            adapter.shouldHedge(_intent(keccak256("k1c"), pool.token1(), 1, 0));
        assertFalse(ok);
        assertEq(reason, "wrong_side");
    }

    function test_rejectsInventoryCap() public {
        clob.pushSnapshot(_snap(0.95e18, 200e18));
        (bool ok, string memory reason) =
            adapter.shouldHedge(_intent(keccak256("k1d"), pool.token0(), 1, 0));
        assertFalse(ok);
        assertEq(reason, "inventory_cap");
    }

    function test_rejectsGasCap() public {
        _mispricedSellToken0();
        ICrossVenueAdapter.HedgeIntent memory intent =
            _intent(keccak256("k1e"), pool.token0(), 1, 0);
        intent.maxGasWei = 0.5 gwei; // below tx gas price
        (bool ok, string memory reason) = adapter.shouldHedge(intent);
        assertFalse(ok);
        assertEq(reason, "gas_cap");
    }

    function test_executesHedgeAndIdempotent() public {
        _mispricedSellToken0();
        address t0 = pool.token0();
        address t1 = pool.token1();

        (uint256 previewOut, uint256 fairOut, int256 basis) =
            adapter.previewHedge(_intent(keccak256("k2"), t0, 1, 0));
        assertGt(basis, 0);
        assertGt(previewOut, fairOut);

        uint256 bal1Before = MockERC20(t1).balanceOf(operator);
        ICrossVenueAdapter.HedgeIntent memory intent = _intent(keccak256("k2"), t0, previewOut, 0);
        assertTrue(adapter.proposeHedge(intent));
        assertEq(MockERC20(t1).balanceOf(operator) - bal1Before, previewOut);

        // Duplicate key skipped.
        assertFalse(adapter.proposeHedge(intent));
        assertTrue(adapter.seenKeys(keccak256("k2")));
    }

    function test_profitGuardBlocksUneconomic() public {
        _mispricedSellToken0();
        // Demand impossible profit.
        ICrossVenueAdapter.HedgeIntent memory intent =
            _intent(keccak256("k3p"), pool.token0(), 1, 1 ether);
        (bool ok, string memory reason) = adapter.shouldHedge(intent);
        assertFalse(ok);
        assertEq(reason, "profit_guard");
    }

    function test_killSwitchBlocks() public {
        _mispricedSellToken0();
        ks.trip("manual");
        (bool ok, string memory reason) =
            adapter.shouldHedge(_intent(keccak256("k3"), pool.token0(), 1, 0));
        assertFalse(ok);
        assertEq(reason, "kill_switch");
        assertTrue(adapter.killSwitchActive());
    }
}
