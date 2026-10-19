// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {MockTokenBase} from "./MockToken.sol";

interface ITransferFrom {
    function transferFrom(address from, address to, uint256 amount) external;
}

/// @notice Pulls `amountIn` from the caller and mints `amountOut` to `to`. A test chooses the amounts and `to`, so the
/// same router can be honest, pull more than approved, pay less than promised or pay someone else.
contract MockRouter {
    uint256 public calls;

    function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut, address to) external {
        ++calls;
        ITransferFrom(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        MockTokenBase(tokenOut).mint(to, amountOut);
    }

    function fail(bytes calldata reason) external pure {
        assembly ("memory-safe") {
            let p := mload(0x40)
            calldatacopy(p, reason.offset, reason.length)
            revert(p, reason.length)
        }
    }
}

/// @notice Pulls `amountIn`, then calls `target` with `data` and bubbles its revert.
contract ReentrantRouter {
    function swap(address tokenIn, uint256 amountIn, address target, bytes calldata data) external {
        ITransferFrom(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}
