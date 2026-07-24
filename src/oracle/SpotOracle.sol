// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SpotOracle
/// @notice Lab oracle with explicit trust / manipulation assumptions.
/// @dev NOT a decentralized price feed. Owner (or attacker in tests) can set any price.
///      Consumers MUST treat `stale` and `manipulated` as first-class risk.
contract SpotOracle {
    address public owner;
    /// @notice token1 per token0, 1e18-scaled (same convention as CLOB mid).
    uint256 public priceWad;
    uint64 public updatedAt;
    uint64 public maxAge = 30;

    event PriceSet(uint256 priceWad, uint64 updatedAt, address indexed by);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MaxAgeSet(uint64 maxAge);

    error NotOwner();
    error ZeroPrice();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(uint256 initialPriceWad) {
        if (initialPriceWad == 0) revert ZeroPrice();
        owner = msg.sender;
        priceWad = initialPriceWad;
        updatedAt = uint64(block.timestamp);
        emit PriceSet(initialPriceWad, updatedAt, msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setMaxAge(uint64 age) external onlyOwner {
        maxAge = age;
        emit MaxAgeSet(age);
    }

    /// @notice Trusted setter — in production this would be a manipulate-able surface.
    function setPrice(uint256 newPriceWad) external onlyOwner {
        if (newPriceWad == 0) revert ZeroPrice();
        priceWad = newPriceWad;
        updatedAt = uint64(block.timestamp);
        emit PriceSet(newPriceWad, updatedAt, msg.sender);
    }

    function latest() external view returns (uint256 price, uint64 ts, bool fresh) {
        price = priceWad;
        ts = updatedAt;
        fresh = updatedAt != 0 && block.timestamp <= uint256(updatedAt) + uint256(maxAge);
    }

    function isFresh() external view returns (bool) {
        return updatedAt != 0 && block.timestamp <= uint256(updatedAt) + uint256(maxAge);
    }
}
