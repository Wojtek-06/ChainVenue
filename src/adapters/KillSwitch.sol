// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title KillSwitch
/// @notice Simple authority-gated halt for adapters / executors (local & testnet ops).
contract KillSwitch {
    address public owner;
    bool public active;
    string public lastReason;

    event Tripped(address indexed by, string reason);
    event Reset(address indexed by);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error AlreadyActive();
    error NotActive();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address owner_) {
        owner = owner_ == address(0) ? msg.sender : owner_;
    }

    function trip(string calldata reason) external onlyOwner {
        if (active) revert AlreadyActive();
        active = true;
        lastReason = reason;
        emit Tripped(msg.sender, reason);
    }

    function reset() external onlyOwner {
        if (!active) revert NotActive();
        active = false;
        lastReason = "";
        emit Reset(msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
