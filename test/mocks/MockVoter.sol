// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {MockBribe} from "./MockBribe.sol";
import {MockVotingEscrow} from "./MockVotingEscrow.sol";

contract MockVoter {
    uint256 internal constant WEEK = 604800;

    MockVotingEscrow public immutable ve;
    address public immutable bribeOwner;
    uint256 internal epoch;

    mapping(address => address) public gauges;
    mapping(address => address) public poolForGauge;
    mapping(address => bool) public isAlive;
    mapping(address => address) public external_bribes;
    mapping(address => address) public internal_bribes;
    mapping(uint256 => mapping(address => uint256)) public weightsPerEpoch;
    mapping(address => mapping(address => uint256)) public votes;
    mapping(address => address[]) internal poolVotes;
    mapping(address => uint256) public lastVoted;

    error EpochFlipInProgress();
    error VoteDelayNotMet();
    error EpochStale();
    error LengthMismatch();
    error VotedAlready();
    error InsufficientVotingPower();
    error NotApprovedOrOwner();

    constructor(MockVotingEscrow ve_, address bribeOwner_) {
        ve = ve_;
        bribeOwner = bribeOwner_;
    }

    function _epochTimestamp() external view returns (uint256) {
        return epoch;
    }

    function setEpoch(uint256 epoch_) external {
        epoch = epoch_;
    }

    function addPool(address pool) external returns (address gauge) {
        gauge = address(uint160(uint256(keccak256(abi.encode("gauge", pool)))));
        gauges[pool] = gauge;
        poolForGauge[gauge] = pool;
        isAlive[gauge] = true;
        external_bribes[gauge] = address(new MockBribe(address(this), bribeOwner));
        internal_bribes[gauge] = address(new MockBribe(address(this), bribeOwner));
    }

    function killGauge(address gauge) external {
        isAlive[gauge] = false;
        weightsPerEpoch[epoch][poolForGauge[gauge]] = 0;
    }

    function setOthers(address pool, uint256 weight) external {
        weightsPerEpoch[epoch][pool] += weight;
        MockBribe(internal_bribes[gauges[pool]]).deposit(weight, address(0));
        MockBribe(external_bribes[gauges[pool]]).deposit(weight, address(0));
    }

    function weights(address pool) external view returns (uint256) {
        return weightsPerEpoch[epoch][pool];
    }

    function poolVote(address voter, uint256 index) external view returns (address) {
        return poolVotes[voter][index];
    }

    function poolVoteLength(address voter) external view returns (uint256) {
        return poolVotes[voter].length;
    }

    function vote(address[] calldata pools, uint256[] calldata proportions) external {
        if (block.timestamp == epoch) revert EpochFlipInProgress();
        if (block.timestamp <= lastVoted[msg.sender]) revert VoteDelayNotMet();
        if (block.timestamp > epoch + WEEK) revert EpochStale();
        if (pools.length != proportions.length) revert LengthMismatch();
        _reset(msg.sender);
        uint256 power = ve.getPastVotes(msg.sender, epoch);
        uint256 total;
        for (uint256 i; i < pools.length; ++i) {
            if (isAlive[gauges[pools[i]]]) total += proportions[i];
        }
        uint256 used;
        for (uint256 i; i < pools.length; ++i) {
            address pool = pools[i];
            address gauge = gauges[pool];
            if (!isAlive[gauge]) continue;
            uint256 weight = proportions[i] * power / total;
            if (votes[msg.sender][pool] != 0) revert VotedAlready();
            if (weight == 0) revert InsufficientVotingPower();
            poolVotes[msg.sender].push(pool);
            weightsPerEpoch[epoch][pool] += weight;
            votes[msg.sender][pool] += weight;
            used += weight;
            MockBribe(internal_bribes[gauge]).deposit(weight, msg.sender);
            MockBribe(external_bribes[gauge]).deposit(weight, msg.sender);
        }
        if (power < used) revert InsufficientVotingPower();
        lastVoted[msg.sender] = block.timestamp;
    }

    function _reset(address voter) internal {
        bool votedInEpoch = lastVoted[voter] >= epoch;
        address[] storage pools = poolVotes[voter];
        for (uint256 i; i < pools.length; ++i) {
            address pool = pools[i];
            uint256 weight = votes[voter][pool];
            if (weight == 0) continue;
            if (votedInEpoch && isAlive[gauges[pool]]) weightsPerEpoch[epoch][pool] -= weight;
            votes[voter][pool] = 0;
            MockBribe(internal_bribes[gauges[pool]]).withdraw(weight, voter);
            MockBribe(external_bribes[gauges[pool]]).withdraw(weight, voter);
        }
        delete poolVotes[voter];
    }

    function claimBribesToRecipientByTokenId(
        address[] calldata bribes,
        address[][] calldata tokens,
        uint256 tokenId,
        address recipient
    ) external {
        _claim(bribes, tokens, tokenId, recipient);
    }

    function claimFeesToRecipientByTokenId(
        address[] calldata fees,
        address[][] calldata tokens,
        uint256 tokenId,
        address recipient
    ) external {
        _claim(fees, tokens, tokenId, recipient);
    }

    function _claim(address[] calldata bribes, address[][] calldata tokens, uint256 tokenId, address recipient)
        internal
    {
        if (!ve.isApprovedClaimRedirectOrOwner(msg.sender, tokenId)) revert NotApprovedOrOwner();
        for (uint256 i; i < bribes.length; ++i) {
            MockBribe(bribes[i]).getRewardToRecipient(tokenId, tokens[i], recipient);
        }
    }
}
