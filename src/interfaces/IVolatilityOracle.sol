// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IVolatilityOracle {
    function getTimepoints(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint88[] memory volatilityCumulatives);
}
