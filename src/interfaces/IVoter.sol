// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

interface IVoter {
    function vote(address[] calldata poolVote, uint256[] calldata weights) external;
    function _epochTimestamp() external view returns (uint256);
    function weights(address pool) external view returns (uint256);
    function poolVoteLength(address voter) external view returns (uint256);
    function gauges(address pool) external view returns (address);
    function isAlive(address gauge) external view returns (bool);
    function external_bribes(address gauge) external view returns (address);
    function internal_bribes(address gauge) external view returns (address);
    function votes(address voter, address pool) external view returns (uint256);
    function poolVote(address voter, uint256 index) external view returns (address);
    function lastVoted(address voter) external view returns (uint256);
    function claimBribesToRecipientByTokenId(
        address[] calldata bribes,
        address[][] calldata tokens,
        uint256 tokenId,
        address recipient
    ) external;
    function claimFeesToRecipientByTokenId(
        address[] calldata fees,
        address[][] calldata tokens,
        uint256 tokenId,
        address recipient
    ) external;
}
