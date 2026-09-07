// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {EvmStorageLab} from "../src/lab/EvmStorageLab.sol";
import {EvmMemoryLab} from "../src/lab/EvmMemoryLab.sol";
import {EvmCallTarget, EvmCallLab, EvmDelegateProxy} from "../src/lab/EvmCallLab.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ConstantProductAMM} from "../src/amm/ConstantProductAMM.sol";
import {ClobVenueStub} from "../src/adapters/ClobVenueStub.sol";
import {KillSwitch} from "../src/adapters/KillSwitch.sol";
import {CrossVenueAdapter} from "../src/adapters/CrossVenueAdapter.sol";

/// @notice Local Anvil deploy for EVM lab + AMM sandbox + guarded adapter.
/// @dev Never point at public mainnet with real funds.
contract DeployLabScript is Script {
    function run() external {
        uint256 pk = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        EvmStorageLab storageLab = new EvmStorageLab();
        EvmMemoryLab memoryLab = new EvmMemoryLab();
        EvmCallTarget callTarget = new EvmCallTarget();
        EvmCallLab callLab = new EvmCallLab();
        EvmDelegateProxy proxy = new EvmDelegateProxy(address(callTarget));

        MockERC20 tokenA = new MockERC20("TokenA", "TKA", 18);
        MockERC20 tokenB = new MockERC20("TokenB", "TKB", 18);
        ConstantProductAMM amm = new ConstantProductAMM(address(tokenA), address(tokenB), 30);

        tokenA.mint(deployer, 1_000_000 ether);
        tokenB.mint(deployer, 1_000_000 ether);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(100_000 ether, 100_000 ether, deployer);

        KillSwitch ks = new KillSwitch(deployer);
        ClobVenueStub clob = new ClobVenueStub(deployer);
        CrossVenueAdapter adapter = new CrossVenueAdapter(clob, ks, deployer);
        tokenA.approve(address(adapter), type(uint256).max);
        tokenB.approve(address(adapter), type(uint256).max);

        vm.stopBroadcast();

        console2.log("EvmStorageLab", address(storageLab));
        console2.log("EvmMemoryLab", address(memoryLab));
        console2.log("EvmCallTarget", address(callTarget));
        console2.log("EvmCallLab", address(callLab));
        console2.log("EvmDelegateProxy", address(proxy));
        console2.log("TokenA", address(tokenA));
        console2.log("TokenB", address(tokenB));
        console2.log("ConstantProductAMM", address(amm));
        console2.log("KillSwitch", address(ks));
        console2.log("ClobVenueStub", address(clob));
        console2.log("CrossVenueAdapter", address(adapter));
    }
}
