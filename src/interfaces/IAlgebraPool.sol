// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IAlgebraPool {
    function plugin() external view returns (address pluginAddress);
}
