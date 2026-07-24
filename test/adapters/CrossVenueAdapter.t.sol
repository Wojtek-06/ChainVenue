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
    ClobVenueStub internal clob;
    KillSwitch internal ks;
    CrossVenueAdapter internal adapter;
    ConstantProductAMM internal pool;

    function setUp() public {
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 18);
        pool = new ConstantProductAMM(address(tokenA), address(tokenB), 30);
        tokenA.mint(address(this), 1_000_000 ether);
        tokenB.mint(address(this), 1_000_000 ether);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        pool.addLiquidity(100 ether, 100 ether, address(this));

        ks = new KillSwitch(address(this));
        clob = new ClobVenueStub(address(this));
        adapter = new CrossVenueAdapter(clob, ks, address(this));
        vm.warp(1_700_000_000);
    }

    function _freshSnap(int256 inventory) internal view returns (IClobVenue.BookSnapshot memory) {
        return IClobVenue.BookSnapshot({
            bestBid: 99e18,
            bestAsk: 101e18,
            mid: 100e18,
            microprice: 100e18,
            inventoryBase: inventory,
            ts: uint64(block.timestamp),
            sourceId: keccak256("quantforge")
        });
    }

    function _intent(bytes32 key) internal view returns (ICrossVenueAdapter.HedgeIntent memory) {
        return ICrossVenueAdapter.HedgeIntent({
            pool: address(pool),
            tokenIn: pool.token0(),
            amountIn: 1 ether,
            minAmountOut: 1,
            maxGasWei: 0,
            maxInventoryBase: 100e18,
            idempotencyKey: key
        });
    }

    function test_rejectsWhenStale() public {
        (bool ok, string memory reason) = adapter.shouldHedge(_intent(keccak256("k1")));
        assertFalse(ok);
        assertEq(reason, "stale_clob");
    }

    function test_acceptsFreshAndIdempotent() public {
        clob.pushSnapshot(_freshSnap(10e18));
        ICrossVenueAdapter.HedgeIntent memory intent = _intent(keccak256("k2"));
        (bool ok,) = adapter.shouldHedge(intent);
        assertTrue(ok);
        assertTrue(adapter.proposeHedge(intent));
        assertFalse(adapter.proposeHedge(intent));
    }

    function test_killSwitchBlocks() public {
        clob.pushSnapshot(_freshSnap(0));
        ks.trip("manual");
        (bool ok, string memory reason) = adapter.shouldHedge(_intent(keccak256("k3")));
        assertFalse(ok);
        assertEq(reason, "kill_switch");
        assertTrue(adapter.killSwitchActive());
    }
}
