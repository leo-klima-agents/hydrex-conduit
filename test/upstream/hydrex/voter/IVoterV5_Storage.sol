// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IVoterV5_GaugeLogic} from "./IVoterV5_GaugeLogic.sol";

/// @title IVoterV5_Storage
/// @notice Interface for accessing public and external variables of the VoterV5_Storage contract
interface IVoterV5_Storage {
    /// @notice Returns the address of the ve token
    function _ve() external view returns (address);

    /// @notice Returns the address of the base token
    function base() external view returns (address);

    /// @notice Returns the address of the option token
    function oToken() external view returns (address);

    /// @notice Returns the address of the bribe factory
    function bribefactory() external view returns (address);

    /// @notice Returns the address of the minter
    function minter() external view returns (address);

    /// @notice Returns the address of the permission registry
    function permissionRegistry() external view returns (address);

    /// @notice Returns the address of a pool at a given index
    /// @param index The index of the pool in the pools array
    function pools(uint256 index) external view returns (address);

    /// @notice Returns the global gauge index
    function index() external view returns (uint256);

    /// @notice Returns the delay between votes in seconds
    function VOTE_DELAY() external view returns (uint256);

    /// @notice Returns the maximum vote delay allowed
    function MAX_VOTE_DELAY() external view returns (uint256);

    /// @notice Returns the claimable amount for a given account
    /// @param account The address of the account
    function claimable(address account) external view returns (uint256);

    /// @notice Returns the gauge address for a given pool
    /// @param pool The address of the pool
    function gauges(address pool) external view returns (address);

    /// @notice Returns the last distribution timestamp for a given gauge
    /// @param gauge The address of the gauge
    function gaugesDistributionTimestamp(address gauge) external view returns (uint256);

    /// @notice Returns the pool address for a given gauge
    /// @param gauge The address of the gauge
    function poolForGauge(address gauge) external view returns (address);

    /// @notice Returns the internal bribe address for a given gauge
    /// @param gauge The address of the gauge
    function internal_bribes(address gauge) external view returns (address);

    /// @notice Returns the external bribe address for a given gauge
    /// @param gauge The address of the gauge
    function external_bribes(address gauge) external view returns (address);

    /// @notice Returns the votes for a given NFT and pool
    /// @param nft The address of the NFT
    /// @param pool The address of the pool
    function votes(address nft, address pool) external view returns (uint256);

    /// @notice Returns the pool address at a given index for a given NFT
    /// @param nft The address of the NFT
    /// @param index The index of the pool in the poolVote array
    function poolVote(address nft, uint256 index) external view returns (address);

    /// @notice Returns the timestamp of the last vote for a given NFT
    /// @param nft The address of the NFT
    function lastVoted(address nft) external view returns (uint256);

    /// @notice Returns whether a given address is a gauge
    /// @param gauge The address of the gauge
    function isGauge(address gauge) external view returns (bool);

    /// @notice Returns whether a given token is whitelisted
    /// @param token The address of the token
    function isWhitelisted(address token) external view returns (bool);

    /// @notice Returns whether a given pool is whitelisted
    /// @param token The address of the pool token
    function isWhitelistedPool(address token) external view returns (bool);

    /// @notice Returns whether a given gauge is alive
    /// @param gauge The address of the gauge
    function isAlive(address gauge) external view returns (bool);

    /// @notice Returns the factory status of a given address
    /// @param factory The address of the factory
    function isFactory(address factory) external view returns (uint8);

    /// @notice Returns whether a given address is a gauge factory
    /// @param gaugeFactory The address of the gauge factory
    /// @dev in 5.4.1, this returns a uint8 instead of a bool
    ///      This allows the same gauge factory to be used across multiple gauge types.
    ///      Storage-safe: bool and uint8 both occupy 1 byte, existing true/false values
    ///      become 1/0 counters seamlessly during upgrades.
    function isGaugeFactory(address gaugeFactory) external view returns (uint8);

    /// @notice Returns whether a given address is a gauge depositor
    /// @param gaugeFactory The address of the gauge factory
    function isGaugeDepositor(address gaugeFactory) external view returns (bool);

    /// @notice Returns the address of the gauge logic contract
    function gaugeLogic() external view returns (IVoterV5_GaugeLogic);

    /// @notice Returns the epoch timestamp when a given gauge was killed
    /// @param gauge The address of the gauge
    function gaugeKilledEpoch(address gauge) external view returns (uint256);
}