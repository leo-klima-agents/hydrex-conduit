// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IAlgebraFactory {
    function poolByPair(address tokenA, address tokenB) external view returns (address pool);
}
