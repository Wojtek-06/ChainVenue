// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EvmCallLab, EvmCallTarget, EvmDelegateProxy} from "../../src/lab/EvmCallLab.sol";

contract EvmCallLabTest is Test {
    EvmCallLab internal lab;
    EvmCallTarget internal target;
    EvmDelegateProxy internal proxy;

    function setUp() public {
        lab = new EvmCallLab();
        target = new EvmCallTarget();
        proxy = new EvmDelegateProxy(address(target));
    }

    function test_callWritesTargetStorage() public {
        assertTrue(lab.doCall(address(target), 99));
        assertEq(target.stored(), 99);
        assertEq(target.lastCaller(), address(lab));
    }

    function test_staticcallReads() public {
        target.set(7);
        assertEq(lab.doStaticGet(address(target)), 7);
    }

    function test_revertBubblesAsFalse() public {
        (bool ok, bytes memory data) = lab.doRevert(address(target));
        assertFalse(ok);
        assertGt(data.length, 0);
    }

    function test_delegatecallWritesProxyStorage() public {
        proxy.delegatedSet(55);
        assertEq(proxy.stored(), 55);
        assertEq(proxy.lastCaller(), address(this));
        // Implementation storage untouched.
        assertEq(target.stored(), 0);
    }
}
