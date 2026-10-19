// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {MockTokenBase} from "./MockToken.sol";

interface IEpoch {
    function _epochTimestamp() external view returns (uint256);
}

interface ITransfer {
    function transfer(address to, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external;
}

contract MockBribe {
    address public immutable voter;
    address public immutable owner;
    mapping(address => mapping(uint256 => uint256)) public rewardsPerEpoch;
    mapping(uint256 => mapping(address => uint256)) public earned;
    mapping(uint256 => uint256) public totalSupplyAt;
    mapping(address => mapping(uint256 => uint256)) public balanceOfOwnerAt;

    constructor(address voter_, address owner_) {
        voter = voter_;
        owner = owner_;
    }

    function rewardData(address token, uint256 epoch) external view returns (uint256, uint256, uint256) {
        return (epoch, rewardsPerEpoch[token][epoch], 0);
    }

    function setRewards(address token, uint256 epoch, uint256 amount) external {
        rewardsPerEpoch[token][epoch] = amount;
    }

    function notifyRewardAmount(address token, uint256 amount) external {
        ITransfer(token).transferFrom(msg.sender, address(this), amount);
        rewardsPerEpoch[token][IEpoch(voter)._epochTimestamp()] += amount;
    }

    function recoverERC20AndUpdateData(address token, uint256 amount) external {
        require(msg.sender == owner, "permission is denied!");
        rewardsPerEpoch[token][IEpoch(voter)._epochTimestamp()] -= amount;
        ITransfer(token).transfer(owner, amount);
    }

    function setEarned(uint256 tokenId, address token, uint256 amount) external {
        earned[tokenId][token] = amount;
        MockTokenBase(token).mint(address(this), amount);
    }

    function getRewardToRecipient(uint256 tokenId, address[] calldata tokens, address recipient) external {
        require(msg.sender == voter, "Not authorized");
        for (uint256 i; i < tokens.length; ++i) {
            uint256 amount = earned[tokenId][tokens[i]];
            if (amount == 0) continue;
            earned[tokenId][tokens[i]] = 0;
            ITransfer(tokens[i]).transfer(recipient, amount);
        }
    }

    function deposit(uint256 amount, address user) external {
        require(msg.sender == voter);
        uint256 epoch = IEpoch(voter)._epochTimestamp();
        totalSupplyAt[epoch] += amount;
        balanceOfOwnerAt[user][epoch] += amount;
    }

    function withdraw(uint256 amount, address user) external {
        require(msg.sender == voter);
        uint256 epoch = IEpoch(voter)._epochTimestamp();
        if (amount <= balanceOfOwnerAt[user][epoch]) {
            totalSupplyAt[epoch] -= amount;
            balanceOfOwnerAt[user][epoch] -= amount;
        }
    }
}
