// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Checkpoints} from "./libraries/Checkpoints.sol";
import {IVotes} from "./interfaces/IVotes.sol";
import {IVotingEscrowV2_Data} from "./IVotingEscrowV2_Data.sol";

/**
 * @title Voting Escrow V2 Interface for Upgrades
 */
interface IVotingEscrowV2_Logic is IVotingEscrowV2_Data, IVotes {
    function balanceOfNFT(uint256 _tokenId) external view returns (uint256);

    function balanceOfNFTAt(uint256 _tokenId, uint256 _timestamp) external view returns (uint256);

    function delegates(uint256 tokenId, uint48 timestamp) external view returns (address);

    function lockDetails(uint256 tokenId) external view returns (LockDetails calldata);

    function getPastEscrowPoint(
        uint256 _tokenId,
        uint256 _timePoint
    ) external view returns (Checkpoints.Point memory, uint48);

    function getFirstEscrowPoint(uint256 _tokenId) external view returns (Checkpoints.Point memory, uint48);

    function checkpoint() external;

    function increaseAmount(uint256 _tokenId, uint256 _value) external;

    function createLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        LockType _lockType
    ) external returns (uint256);

    function createDelegatedLockFor(
        uint256 _value,
        uint256 _lockDuration,
        address _to,
        address _delegatee,
        LockType _lockType
    ) external returns (uint256);

    function split(uint256[] memory _weights, uint256 _tokenId) external;

    function merge(uint256 _from, uint256 _to) external;

    function burn(uint256 _tokenId) external;

    function setClaimRedirectApproval(address to, uint256 tokenId) external;

    function setClaimRedirectApprovalForAll(address operator, bool approved) external;

    function getClaimRedirectApproved(uint256 tokenId) external view returns (address);

    function isClaimRedirectApprovedForAll(address owner, address operator) external view returns (bool);

    function isApprovedClaimRedirectOrOwner(address operator, uint256 tokenId) external view returns (bool);
    
    function isClaimRedirectApprovedForAllOrOwner(address owner, address operator) external view returns (bool);

    function setConduitApproval(address conduitAddress, uint256 tokenId, bool approve) external;

    function setConduitApprovalConfig(IVotingEscrowV2_Data.ApprovalActionType[] calldata actions, string calldata description) external;

    function getConduitApprovalConfig(address conduitAddress) external view returns (IVotingEscrowV2_Data.ApprovalActionType[] memory actions, bool active, string memory description);

    function delegateBatch(uint256[] calldata tokenIds, address delegatee) external;
}
