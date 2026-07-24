// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title EvmStorageLab
/// @notice Demonstrates storage slots, packing, and SLOAD/SSTORE layout for interview traces.
/// @dev Slot layout (see docs/EVM_LAB.md):
///      slot 0: owner (20) | flagged (1) | tier (1)  — packed into one word
///      slot 1: counter (uint256)
///      slot 2: mapping base for values[address]
contract EvmStorageLab {
    // slot 0 (packed)
    address public owner; // 20 bytes
    bool public flagged; // 1 byte
    uint8 public tier; // 1 byte

    // slot 1
    uint256 public counter;

    // slot 2 — mapping base
    mapping(address => uint256) public values;

    event PackedWritten(address owner, bool flagged, uint8 tier);
    event CounterBumped(uint256 newValue);
    event ValueSet(address indexed who, uint256 value);

    constructor() {
        owner = msg.sender;
        tier = 1;
    }

    function writePacked(address newOwner, bool newFlagged, uint8 newTier) external {
        owner = newOwner;
        flagged = newFlagged;
        tier = newTier;
        emit PackedWritten(newOwner, newFlagged, newTier);
    }

    function bumpCounter(uint256 delta) external returns (uint256) {
        counter += delta;
        emit CounterBumped(counter);
        return counter;
    }

    function setValue(address who, uint256 value) external {
        values[who] = value;
        emit ValueSet(who, value);
    }

    /// @notice Expose the mapping storage slot for `values[who]` (keccak256(abi.encode(who, 2))).
    function valueSlot(address who) external pure returns (bytes32) {
        return keccak256(abi.encode(who, uint256(2)));
    }
}
