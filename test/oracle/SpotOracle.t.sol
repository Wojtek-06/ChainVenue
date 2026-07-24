// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SpotOracle} from "../../src/oracle/SpotOracle.sol";
import {MockERC20} from "../../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../../src/amm/ConstantProductAMM.sol";
import {ClobVenueStub} from "../../src/adapters/ClobVenueStub.sol";
import {KillSwitch} from "../../src/adapters/KillSwitch.sol";
import {CrossVenueAdapter} from "../../src/adapters/CrossVenueAdapter.sol";
import {IClobVenue} from "../../src/adapters/IClobVenue.sol";
import {ICrossVenueAdapter} from "../../src/adapters/ICrossVenueAdapter.sol";

/// @notice Documents that a manipulated / stale oracle (or CLOB mid) can induce bad hedges
///         unless freshness + basis + profit guards remain on.
contract SpotOracleTest is Test {
    SpotOracle internal oracle;

    function setUp() public {
        vm.warp(1_700_000_000);
        oracle = new SpotOracle(1e18);
    }

    function test_freshByDefault() public view {
        (uint256 px, uint64 ts, bool fresh) = oracle.latest();
        assertEq(px, 1e18);
        assertTrue(fresh);
        assertEq(ts, uint64(block.timestamp));
    }

    function test_becomesStale() public {
        oracle.setMaxAge(10);
        vm.warp(block.timestamp + 11);
        assertFalse(oracle.isFresh());
    }

    function test_ownerCanManipulatePrice() public {
        // Explicit assumption: owner == trusted updater OR attacker in adversarial lab.
        oracle.setPrice(0.5e18);
        (uint256 px,, bool fresh) = oracle.latest();
        assertEq(px, 0.5e18);
        assertTrue(fresh);
    }

    function test_manipulatedMidStillNeedsProfitGuard() public {
        // Wire: attacker sets CLOB mid far from AMM, but profit_guard + wrong_side logic
        // only hedges when AMM actually pays better than fair — manipulation alone is not enough
        // if minProfitOut is set aggressively relative to true economics.
        MockERC20 a = new MockERC20("A", "A", 18);
        MockERC20 b = new MockERC20("B", "B", 18);
        ConstantProductAMM pool = new ConstantProductAMM(address(a), address(b), 30);
        a.mint(address(this), 1_000_000 ether);
        b.mint(address(this), 1_000_000 ether);
        a.approve(address(pool), type(uint256).max);
        b.approve(address(pool), type(uint256).max);
        pool.addLiquidity(100 ether, 100 ether, address(this));

        KillSwitch ks = new KillSwitch(address(this));
        ClobVenueStub clob = new ClobVenueStub(address(this));
        CrossVenueAdapter adapter = new CrossVenueAdapter(clob, ks, address(this));

        // Manipulated mid very low → huge positive basis, hedge looks good.
        oracle.setPrice(0.5e18);
        clob.pushSnapshot(
            IClobVenue.BookSnapshot({
                bestBid: 0.49e18,
                bestAsk: 0.51e18,
                mid: 0.5e18,
                microprice: 0.5e18,
                inventoryBase: 0,
                ts: uint64(block.timestamp),
                sourceId: keccak256("manipulated")
            })
        );

        ICrossVenueAdapter.HedgeIntent memory intent = ICrossVenueAdapter.HedgeIntent({
            pool: address(pool),
            tokenIn: pool.token0(),
            amountIn: 1 ether,
            minAmountOut: 1,
            maxGasWei: 0,
            minProfitOut: 0,
            maxInventoryBase: type(int256).max,
            to: address(this),
            idempotencyKey: keccak256("m1")
        });
        (bool ok,) = adapter.shouldHedge(intent);
        assertTrue(ok); // economics vs manipulated mid say hedge

        // With an absurd profit floor, guard blocks even under manipulation.
        intent.minProfitOut = 10 ether;
        intent.idempotencyKey = keccak256("m2");
        (bool ok2, string memory reason) = adapter.shouldHedge(intent);
        assertFalse(ok2);
        assertEq(reason, "profit_guard");
    }
}
