// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

abstract contract MockTokenBase {
    uint8 public immutable decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public blocked;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function setBlocked(address account, bool isBlocked) external {
        blocked[account] = isBlocked;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(!blocked[to], "blocked");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function _spend(address from, uint256 amount) internal {
        allowance[from][msg.sender] -= amount;
    }
}

/// @notice Returns `true` from `transfer`, `transferFrom` and `approve`.
contract MockToken is MockTokenBase {
    constructor(uint8 decimals_) MockTokenBase(decimals_) {}

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spend(from, amount);
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice Returns nothing from `transfer`, `transferFrom` and `approve`.
contract MockNoReturnToken is MockTokenBase {
    constructor(uint8 decimals_) MockTokenBase(decimals_) {}

    function transfer(address to, uint256 amount) external {
        _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external {
        _spend(from, amount);
        _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external virtual {
        allowance[msg.sender][spender] = amount;
    }
}

/// @notice Like USDT on Ethereum: returns nothing, and only approves from or to zero.
contract MockUsdtToken is MockNoReturnToken {
    constructor(uint8 decimals_) MockNoReturnToken(decimals_) {}

    function approve(address spender, uint256 amount) external override {
        require(amount == 0 || allowance[msg.sender][spender] == 0, "approve from non-zero");
        allowance[msg.sender][spender] = amount;
    }
}

/// @notice Transfers like `MockToken`, but `approve` returns `false` instead of reverting.
contract MockFalseToken is MockTokenBase {
    constructor(uint8 decimals_) MockTokenBase(decimals_) {}

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return false;
    }
}
