// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EvmMemoryLab} from "../../src/lab/EvmMemoryLab.sol";

contract EvmMemoryLabTest is Test {
    EvmMemoryLab internal lab;

    function setUp() public {
        lab = new EvmMemoryLab();
    }

    function test_sumCalldataAndMemoryAgree() public {
        uint256[] memory xs = new uint256[](4);
        xs[0] = 1;
        xs[1] = 2;
        xs[2] = 3;
        xs[3] = 4;
        assertEq(lab.sumCalldata(xs), 10);
        assertEq(lab.sumMemory(xs), 10);
    }

    function test_allocateScratch() public {
        uint256 after1 = lab.allocateScratch(1);
        uint256 after8 = lab.allocateScratch(8);
        // Absolute free-mem values depend on Solidity codegen; relative growth must hold.
        assertGt(after8, after1);
        assertEq(after8 - after1, 7 * 0x20);
    }

    function test_echoHead() public {
        bytes memory payload = abi.encodePacked(bytes32(uint256(0xABC)), bytes32(uint256(1)));
        (bytes32 head,) = lab.echoHead(payload);
        assertEq(head, bytes32(uint256(0xABC)));
    }
}
