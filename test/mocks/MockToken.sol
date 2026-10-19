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

contract MockNoReturnToken is MockTokenBase {
    constructor(uint8 decimals_) MockTokenBase(decimals_) {}

    function transfer(address to, uint256 amount) external {
        _transfer(msg.sender, to, amount);
    }
}

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

contract MockTaxToken is MockToken {
    constructor(uint8 decimals_) MockToken(decimals_) {}

    function _transfer(address from, address to, uint256 amount) internal override {
        super._transfer(from, to, amount);
        balanceOf[to] -= amount / 100;
    }
}

contract MockReentrantToken is MockToken {
    address public conduit;
    bytes public data;

    constructor(uint8 decimals_) MockToken(decimals_) {}

    function arm(address conduit_, bytes calldata data_) external {
        conduit = conduit_;
        data = data_;
    }

    function _transfer(address sender, address to, uint256 amount) internal override {
        if (sender == conduit) {
            (bool ok, bytes memory ret) = conduit.call(data);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
        }
        super._transfer(sender, to, amount);
    }
}
