// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EvmStorageLab} from "../../src/lab/EvmStorageLab.sol";

contract EvmStorageLabTest is Test {
    EvmStorageLab internal lab;

    function setUp() public {
        lab = new EvmStorageLab();
    }

    function test_packedSlotLayout() public {
        address who = address(0xBEEF);
        lab.writePacked(who, true, 7);

        bytes32 slot0 = vm.load(address(lab), bytes32(uint256(0)));
        // low 20 bytes = owner
        address ownerFromSlot = address(uint160(uint256(slot0)));
        assertEq(ownerFromSlot, who);

        // flagged at byte 20, tier at byte 21
        uint8 flagged = uint8(uint256(slot0) >> 160);
        uint8 tier = uint8(uint256(slot0) >> 168);
        assertEq(flagged, 1);
        assertEq(tier, 7);
    }

    function test_counterSlot() public {
        lab.bumpCounter(42);
        bytes32 slot1 = vm.load(address(lab), bytes32(uint256(1)));
        assertEq(uint256(slot1), 42);
    }

    function test_mappingSlotFormula() public {
        address who = address(0xCAFE);
        lab.setValue(who, 1234);
        bytes32 slot = lab.valueSlot(who);
        assertEq(uint256(vm.load(address(lab), slot)), 1234);
        assertEq(slot, keccak256(abi.encode(who, uint256(2))));
    }
}
