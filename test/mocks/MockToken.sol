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

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(!blocked[to], "blocked");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
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
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice Returns nothing from `transfer`, like USDT on Ethereum.
contract MockNoReturnToken is MockTokenBase {
    constructor(uint8 decimals_) MockTokenBase(decimals_) {}

    function transfer(address to, uint256 amount) external {
        _transfer(msg.sender, to, amount);
    }
}

/// @notice Returns `false` without moving anything when `liar` sends, and transfers normally otherwise.
contract MockFalseToken is MockTokenBase {
    address public liar;

    constructor(uint8 decimals_) MockTokenBase(decimals_) {}

    function setLiar(address liar_) external {
        liar = liar_;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (msg.sender == liar) return false;
        _transfer(msg.sender, to, amount);
        return true;
    }
}

/// @notice Keeps 1% of every transfer.
contract MockTaxToken is MockToken {
    constructor(uint8 decimals_) MockToken(decimals_) {}

    function _transfer(address from, address to, uint256 amount) internal override {
        super._transfer(from, to, amount);
        balanceOf[to] -= amount / 100;
    }
}

/// @notice When `from` sends, calls `target` with `data` first and bubbles its revert.
contract MockReentrantToken is MockToken {
    address public from;
    address public target;
    bytes public data;

    constructor(uint8 decimals_) MockToken(decimals_) {}

    function arm(address from_, address target_, bytes calldata data_) external {
        from = from_;
        target = target_;
        data = data_;
    }

    function _transfer(address sender, address to, uint256 amount) internal override {
        if (sender == from) {
            (bool ok, bytes memory ret) = target.call(data);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
        }
        super._transfer(sender, to, amount);
    }
}
