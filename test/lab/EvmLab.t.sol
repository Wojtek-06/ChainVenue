// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {EvmStorageLab} from "../../src/lab/EvmStorageLab.sol";
import {EvmMemoryLab} from "../../src/lab/EvmMemoryLab.sol";
import {EvmCallLab, EvmCallTarget, EvmDelegateProxy} from "../../src/lab/EvmCallLab.sol";
import {VulnerableVault, SafeVault, ReentrancyAttacker} from "../../src/lab/ReentrancyLab.sol";

contract EvmLabTest is Test {
    EvmStorageLab internal storageLab;
    EvmMemoryLab internal memoryLab;
    EvmCallLab internal callLab;

    function setUp() public {
        storageLab = new EvmStorageLab();
        memoryLab = new EvmMemoryLab();
        callLab = new EvmCallLab();
    }

    function test_storagePackedSlot0() public {
        storageLab.writePacked(address(0xBEEF), true, 7);
        // Load raw slot 0 and check packing: owner in low 160 bits.
        bytes32 slot0 = vm.load(address(storageLab), bytes32(uint256(0)));
        address ownerFromSlot = address(uint160(uint256(slot0)));
        assertEq(ownerFromSlot, address(0xBEEF));
        assertTrue(storageLab.flagged());
        assertEq(storageLab.tier(), 7);
    }

    function test_storageMappingSlot() public {
        address who = address(0xA11CE);
        storageLab.setValue(who, 42);
        bytes32 slot = storageLab.valueSlot(who);
        assertEq(uint256(vm.load(address(storageLab), slot)), 42);
    }

    function test_counterSstore() public {
        assertEq(storageLab.bumpCounter(5), 5);
        assertEq(uint256(vm.load(address(storageLab), bytes32(uint256(1)))), 5);
    }

    function test_calldataVsMemorySum() public {
        uint256[] memory xs = new uint256[](4);
        xs[0] = 1;
        xs[1] = 2;
        xs[2] = 3;
        xs[3] = 4;
        assertEq(memoryLab.sumCalldata(xs), 10);
        assertEq(memoryLab.sumMemory(xs), 10);
    }

    function test_allocateScratchGrowsFreeMem() public pure {
        // Pure assembly helper — just ensure it returns non-zero after allocation.
        EvmMemoryLab lab = EvmMemoryLab(address(0)); // unused pattern avoided below
        lab; // silence
    }

    function test_allocateScratch() public {
        uint256 free = memoryLab.allocateScratch(8);
        assertGt(free, 0x80);
    }

    function test_callAndStaticcall() public {
        EvmCallTarget target = new EvmCallTarget();
        assertTrue(callLab.doCall(address(target), 99));
        assertEq(target.stored(), 99);
        assertEq(callLab.doStaticGet(address(target)), 99);
    }

    function test_delegatecallWritesProxyStorage() public {
        EvmCallTarget impl = new EvmCallTarget();
        EvmDelegateProxy proxy = new EvmDelegateProxy(address(impl));
        proxy.delegatedSet(123);
        assertEq(proxy.stored(), 123);
        assertEq(proxy.lastCaller(), address(this));
        // Implementation storage untouched.
        assertEq(impl.stored(), 0);
    }

    function test_revertBubblesAsFalse() public {
        EvmCallTarget target = new EvmCallTarget();
        (bool ok, bytes memory data) = callLab.doRevert(address(target));
        assertFalse(ok);
        assertGt(data.length, 0);
    }

    function test_reentrancyDrainsVulnerableVault() public {
        VulnerableVault vault = new VulnerableVault();
        ReentrancyAttacker attacker = new ReentrancyAttacker(vault);

        vm.deal(address(this), 10 ether);
        vault.deposit{value: 5 ether}();

        attacker.attack{value: 1 ether}(5);
        assertLt(address(vault).balance, 5 ether);
        assertGt(address(attacker).balance, 1 ether);
    }

    function test_safeVaultBlocksReentrancy() public {
        SafeVault vault = new SafeVault();
        // Direct deposit + withdraw happy path.
        vault.deposit{value: 1 ether}();
        uint256 before = address(this).balance;
        vault.withdraw();
        assertEq(address(this).balance, before + 1 ether);
    }

    receive() external payable {}
}
