// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../src/amm/ConstantProductAMM.sol";
import {ClobVenueStub} from "../src/adapters/ClobVenueStub.sol";
import {KillSwitch} from "../src/adapters/KillSwitch.sol";
import {CrossVenueAdapter} from "../src/adapters/CrossVenueAdapter.sol";
import {IClobVenue} from "../src/adapters/IClobVenue.sol";
import {ICrossVenueAdapter} from "../src/adapters/ICrossVenueAdapter.sol";

/// @notice Self-contained Anvil demo: mispriced CLOB mid → guarded hedge → P&L logs.
/// @dev forge script script/DemoHedge.s.sol:DemoHedgeScript --rpc-url http://127.0.0.1:8545 --broadcast -vv
contract DemoHedgeScript is Script {
    struct Deployed {
        ConstantProductAMM pool;
        ClobVenueStub clob;
        CrossVenueAdapter adapter;
        address token0;
        address token1;
    }

    function run() external {
        uint256 pk = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address operator = vm.addr(pk);

        vm.startBroadcast(pk);
        Deployed memory d = _deploy(operator);
        _pushMispricedMid(d.clob, 0.95e18);
        _executeAndLog(d, operator, 10 ether);
        vm.stopBroadcast();
    }

    function _deploy(address operator) internal returns (Deployed memory d) {
        MockERC20 tokenA = new MockERC20("TokenA", "TKA", 18);
        MockERC20 tokenB = new MockERC20("TokenB", "TKB", 18);
        d.pool = new ConstantProductAMM(address(tokenA), address(tokenB), 30);

        tokenA.mint(operator, 1_000_000 ether);
        tokenB.mint(operator, 1_000_000 ether);
        tokenA.approve(address(d.pool), type(uint256).max);
        tokenB.approve(address(d.pool), type(uint256).max);
        d.pool.addLiquidity(100_000 ether, 100_000 ether, operator);

        KillSwitch ks = new KillSwitch(operator);
        d.clob = new ClobVenueStub(operator);
        d.adapter = new CrossVenueAdapter(d.clob, ks, operator);
        tokenA.approve(address(d.adapter), type(uint256).max);
        tokenB.approve(address(d.adapter), type(uint256).max);

        d.token0 = d.pool.token0();
        d.token1 = d.pool.token1();
    }

    function _pushMispricedMid(ClobVenueStub clob, uint256 mid) internal {
        clob.pushSnapshot(
            IClobVenue.BookSnapshot({
                bestBid: mid * 99 / 100,
                bestAsk: mid * 101 / 100,
                mid: mid,
                microprice: mid,
                inventoryBase: 0,
                ts: uint64(block.timestamp),
                sourceId: keccak256("quantforge-demo")
            })
        );
        console2.log("clob mid (WAD)", mid);
    }

    function _executeAndLog(Deployed memory d, address operator, uint256 amountIn) internal {
        ICrossVenueAdapter.HedgeIntent memory intent = ICrossVenueAdapter.HedgeIntent({
            pool: address(d.pool),
            tokenIn: d.token0,
            amountIn: amountIn,
            minAmountOut: 1,
            maxGasWei: 0,
            minProfitOut: 0,
            maxInventoryBase: type(int256).max,
            to: operator,
            idempotencyKey: keccak256(abi.encodePacked("demo-hedge-1", block.timestamp))
        });

        (uint256 previewOut, uint256 fairOut, int256 basisBps) = d.adapter.previewHedge(intent);
        intent.minAmountOut = (previewOut * 9950) / 10_000;

        uint256 bal1Before = MockERC20(d.token1).balanceOf(operator);
        uint256 gasBefore = gasleft();
        require(d.adapter.proposeHedge(intent), "HEDGE_SKIPPED");
        uint256 gasUsed = gasBefore - gasleft();
        uint256 amountOut = MockERC20(d.token1).balanceOf(operator) - bal1Before;
        uint256 gasCostWei = gasUsed * tx.gasprice;
        int256 net = int256(amountOut) - int256(fairOut) - int256(gasCostWei);

        console2.log("=== ChainVenue DemoHedge ===");
        console2.log("pool", address(d.pool));
        console2.log("adapter", address(d.adapter));
        console2.log("basis bps (signed)", basisBps);
        console2.log("amountIn token0", amountIn);
        console2.log("previewOut", previewOut);
        console2.log("fairOut @ mid", fairOut);
        console2.log("amountOut token1", amountOut);
        console2.log("gross profit vs fair (wei)", amountOut - fairOut);
        console2.log("gasUsed (call frame est)", gasUsed);
        console2.log("gasCost wei", gasCostWei);
        console2.log("net vs fair after gas (lab units)", net);
    }
}
