// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Adversarial ERC-20 that skims a fee on every transfer (local tests only).
contract FeeOnTransferERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public immutable feeBps;
    uint256 public constant FEE_DENOM = 10_000;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public feeSink;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 feeBps_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        feeBps = feeBps_;
        feeSink = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ALLOWANCE");
            unchecked {
                allowance[from][msg.sender] = allowed - amount;
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "ZERO_TO");
        uint256 bal = balanceOf[from];
        require(bal >= amount, "BALANCE");
        uint256 fee = (amount * feeBps) / FEE_DENOM;
        uint256 sendAmt = amount - fee;
        unchecked {
            balanceOf[from] = bal - amount;
            balanceOf[to] += sendAmt;
            balanceOf[feeSink] += fee;
        }
        emit Transfer(from, to, sendAmt);
        if (fee > 0) emit Transfer(from, feeSink, fee);
    }
}
