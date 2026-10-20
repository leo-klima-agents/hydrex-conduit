// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract MockAlgebraFactory {
    mapping(address => mapping(address => address)) public poolByPair;

    function setPool(address tokenA, address tokenB, address pool) external {
        poolByPair[tokenA][tokenB] = pool;
        poolByPair[tokenB][tokenA] = pool;
    }
}

contract MockAlgebraPool {
    address public immutable token0;
    address public immutable token1;
    address public plugin;

    constructor(address tokenA, address tokenB, address plugin_) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        plugin = plugin_;
    }

    function setPlugin(address plugin_) external {
        plugin = plugin_;
    }
}

contract MockPlugin {
    enum Mode {
        Normal,
        Reverts,
        Short,
        Long,
        BadOffset,
        BadLength,
        OutOfRange,
        BurnsGas,
        ReturnBomb
    }

    Mode public mode;
    int256 public start;
    int256 public end;

    function setTick(int256 tick) external {
        setCumulatives(-7 * 2 ** 40, -7 * 2 ** 40 + tick * 1800);
    }

    function setCumulatives(int256 start_, int256 end_) public {
        start = start_;
        end = end_;
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function getTimepoints(uint32[] calldata) external view returns (int56[] memory, uint88[] memory) {
        Mode m = mode;
        if (m == Mode.Reverts) revert("plugin reverts");
        if (m == Mode.BurnsGas) {
            for (uint256 i; i < type(uint256).max; ++i) {}
        }
        bytes memory ret = abi.encode(_words(2), new uint256[](2));
        if (m == Mode.Short) ret = abi.encode(start, end);
        if (m == Mode.Long) ret = bytes.concat(ret, bytes32(0));
        if (m == Mode.BadOffset) {
            assembly ("memory-safe") {
                mstore(add(ret, 0x20), 0x60)
            }
        }
        if (m == Mode.BadLength) ret = abi.encode(_words(3), new uint256[](1));
        if (m == Mode.OutOfRange) {
            assembly ("memory-safe") {
                mstore(add(ret, 0xa0), shl(56, 1))
            }
        }
        if (m == Mode.ReturnBomb) ret = new bytes(100_000);
        assembly ("memory-safe") {
            return(add(ret, 0x20), mload(ret))
        }
    }

    function _words(uint256 n) internal view returns (int256[] memory w) {
        w = new int256[](n);
        w[0] = start;
        w[1] = end;
    }
}
