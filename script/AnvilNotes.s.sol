// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

/// @notice Placeholder script documenting common Anvil workflows (see docs/ANVIL.md).
contract AnvilNotes is Script {
    function run() external pure {
        console2.log("See docs/ANVIL.md for local Anvil / fork workflows.");
        console2.log("Default Anvil account0 key is used by DeployAMM when PRIVATE_KEY unset.");
    }
}
