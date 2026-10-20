// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IBribe {
    function rewardData(address token, uint256 epoch)
        external
        view
        returns (uint256 periodFinish, uint256 rewardsPerEpoch, uint256 lastUpdateTime);
    function totalSupplyAt(uint256 timestamp) external view returns (uint256);
    function rewardTokens(uint256 index) external view returns (address);
}
