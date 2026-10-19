// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IVotingEscrow {
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function setConduitApprovalConfig(uint8[] calldata actions, string calldata description) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}
