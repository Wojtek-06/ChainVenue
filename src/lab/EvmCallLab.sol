// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Target for staticcall / call / delegatecall experiments.
contract EvmCallTarget {
    uint256 public stored;
    address public lastCaller;

    function set(uint256 v) external {
        stored = v;
        lastCaller = msg.sender;
    }

    function get() external view returns (uint256) {
        return stored;
    }

    function boom() external pure {
        revert("BOOM");
    }
}

/// @notice Minimal proxy-style storage that delegatecall writes into *this* contract.
contract EvmDelegateProxy {
    // Must match EvmCallTarget slot 0 layout for the demo.
    uint256 public stored;
    address public lastCaller;
    address public implementation;

    constructor(address impl) {
        implementation = impl;
    }

    function delegatedSet(uint256 v) external {
        (bool ok, bytes memory data) =
            implementation.delegatecall(abi.encodeWithSelector(EvmCallTarget.set.selector, v));
        require(ok, string(data));
    }
}

/// @title EvmCallLab
/// @notice Documents call / staticcall / delegatecall / revert bubbling.
contract EvmCallLab {
    function doCall(address target, uint256 v) external returns (bool ok) {
        (ok,) = target.call(abi.encodeWithSelector(EvmCallTarget.set.selector, v));
    }

    function doStaticGet(address target) external view returns (uint256 value) {
        (bool ok, bytes memory data) =
            target.staticcall(abi.encodeWithSelector(EvmCallTarget.get.selector));
        require(ok, "STATICCALL_FAIL");
        value = abi.decode(data, (uint256));
    }

    function doRevert(address target) external returns (bool ok, bytes memory data) {
        (ok, data) = target.call(abi.encodeWithSelector(EvmCallTarget.boom.selector));
    }
}
