// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../src/amm/ConstantProductAMM.sol";
import {ClobVenueStub} from "../src/adapters/ClobVenueStub.sol";
import {KillSwitch} from "../src/adapters/KillSwitch.sol";
import {CrossVenueAdapter} from "../src/adapters/CrossVenueAdapter.sol";

/// @notice Local Anvil deploy of AMM sandbox + cross-venue stubs.
contract DeployAMM is Script {
    function run() external {
        uint256 pk = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        MockERC20 tokenA = new MockERC20("Token A", "TKA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKB", 18);
        ConstantProductAMM pool = new ConstantProductAMM(address(tokenA), address(tokenB), 30);

        tokenA.mint(deployer, 1_000_000 ether);
        tokenB.mint(deployer, 1_000_000 ether);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        pool.addLiquidity(100_000 ether, 100_000 ether, deployer);

        KillSwitch ks = new KillSwitch(deployer);
        ClobVenueStub clob = new ClobVenueStub(deployer);
        CrossVenueAdapter adapter = new CrossVenueAdapter(clob, ks, deployer);

        vm.stopBroadcast();

        console2.log("tokenA", address(tokenA));
        console2.log("tokenB", address(tokenB));
        console2.log("pool", address(pool));
        console2.log("killSwitch", address(ks));
        console2.log("clobStub", address(clob));
        console2.log("adapter", address(adapter));
    }
}
