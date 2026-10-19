// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVoterV5_GaugeLogic} from "./VoterV5_GaugeLogic.sol";
import {IVoterV5_ClaimHelper} from "./IVoterV5_ClaimHelper.sol";
import {IBribe} from "./IBribe.sol";
import {IGauge} from "../interfaces/IGauge.sol";
import {IOptionTokenV4} from "../OptionToken/IOptionTokenV4.sol";
import {IMinter} from "../interfaces/IMinter.sol";
import {IPermissionsRegistry} from "../interfaces/IPermissionsRegistry.sol";
import {IVotingEscrowV2} from "./VotingEscrow/IVotingEscrowV2.sol";

/// @title IVoterV5_Logic
/// @notice Interface to manage the functionality of the VoterV5 contract
/// @custom:version 2.0.0
/// - Replace addFactory, removeFactory, replaceFactory with setFactory to support GaugeType enum
interface IVoterV5_Logic is IVoterV5_ClaimHelper {
    // Initialization
    function initialize(
        address __ve,
        address _pairFactory,
        address _gaugeFactory,
        address _bribes,
        address _gaugeLogic,
        address _claimLogic,
        string memory _protocolName
    ) external;

    function _init(address[] memory _tokens, address _permissionsRegistry, address _minter, address _oToken) external;

    // Role Management
    function setVoteDelay(uint256 _delay) external;

    function setMinter(address _minter) external;

    function setOptionsToken(address _oToken) external;

    function refreshApprovals(uint256 start, uint256 finish, address _oldOtoken) external;

    function setGaugeDepositor(address _depositor, bool _enabled) external;

    function setBribeFactory(address _bribeFactory) external;

    function setPermissionsRegistry(address _permissionRegistry) external;

    function setNewBribes(address _gauge, address _internal, address _external) external;

    function setInternalBribeFor(address _gauge, address _internal) external;

    function setExternalBribeFor(address _gauge, address _external) external;

    function setFactory(uint256 _gaugeType, address _pairFactory, address _gaugeFactory) external;

    // Governance
    function updateWhitelistToken(address[] memory _tokens, bool _whitelist) external;

    function updateWhitelistPool(address[] memory _pools, bool _whitelist) external;

    function killGauge(address _gauge) external;

    function reviveGauge(address _gauge) external;

    // User Interaction
    function reset() external;

    function poke() external;

    function vote(address[] calldata _poolVote, uint256[] calldata _weights) external;

    // Gauge Management
    function createGauges(
        address[] memory _pool,
        uint256[] memory _gaugeTypes
    ) external returns (address[] memory, address[] memory, address[] memory);

    function createGauge(
        address _pool,
        uint256 _gaugeType
    ) external returns (address _gauge, address _internal_bribe, address _external_bribe);

    // View Functions
    function length() external view returns (uint256);

    function poolVoteLength(address voter) external view returns (uint256);

    function factories() external view returns (address[] memory);

    function factoryLength() external view returns (uint256);

    function gaugeFactories() external view returns (address[] memory);

    function gaugeFactoriesLength() external view returns (uint256);

    function weights(address _pool) external view returns (uint256);

    function weightsAt(address _pool, uint256 _time) external view returns (uint256);

    function totalWeight() external view returns (uint256);

    function totalWeightAt(uint256 _time) external view returns (uint256);

    function _epochTimestamp() external view returns (uint256);

    function ve() external view returns (address);

    // Distribution
    function notifyRewardAmount(uint256 amount) external;

    function distributeFees(address[] memory _gauges) external;

    function distributeAll() external;

    function distribute(uint256 start, uint256 finish) external;

    function distribute(address[] memory _gauges) external;
}