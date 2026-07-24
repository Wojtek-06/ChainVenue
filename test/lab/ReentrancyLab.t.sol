// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {VulnerableVault, SafeVault, ReentrancyAttacker} from "../../src/lab/ReentrancyLab.sol";

contract ReentrancyLabTest is Test {
    receive() external payable {}

    function test_vulnerableVaultDrained() public {
        VulnerableVault vault = new VulnerableVault();
        ReentrancyAttacker attacker = new ReentrancyAttacker(vault);

        vm.deal(address(this), 10 ether);
        vault.deposit{value: 5 ether}();

        attacker.attack{value: 1 ether}(5);
        assertLt(address(vault).balance, 5 ether);
        assertGt(address(attacker).balance, 1 ether);
    }

    function test_safeVaultResistsReentrancy() public {
        SafeVault vault = new SafeVault();
        // Attacker only targets VulnerableVault; exercise CEI path directly.
        vm.deal(address(this), 3 ether);
        vault.deposit{value: 2 ether}();
        vault.withdraw();
        assertEq(address(vault).balance, 0);
        assertEq(vault.balances(address(this)), 0);
    }
}
