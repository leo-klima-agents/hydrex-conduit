// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IVoterV5_ClaimHelper} from "./IVoterV5_ClaimHelper.sol";

interface IVoterV5_ClaimLogic is IVoterV5_ClaimHelper, IERC165 {
    // Functions inherited from IVoterV5_ClaimHelper
    function claimRewards(address[] memory _gauges) external;
    function claimRewardsFor(address[] memory _gauges, address _claimFor) external;
    function claimRewardTokens(address[] memory _gauges, address[][] memory _tokens) external;
    function claimRewardTokensFor(address[] memory _gauges, address[][] memory _tokens, address _claimFor) external;
    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId) external;
    function claimFees(address[] memory _fees, address[][] memory _tokens, uint256 _tokenId) external;
    function claimBribes(address[] memory _bribes, address[][] memory _tokens) external;
    function claimFees(address[] memory _fees, address[][] memory _tokens) external;

    // Functions specific to IVoterV5_ClaimLogic
    function claimRewardTokensToRecipient(
        address[] memory _gauges,
        address[][] memory _tokens,
        address _claimFor,
        address _recipient
    ) external;

    function claimBribesToRecipientByTokenId(
        address[] memory _bribes,
        address[][] memory _tokens,
        uint256 _tokenId,
        address _recipient
    ) external;

    function claimBribesToRecipientByAddress(
        address[] memory _bribes,
        address[][] memory _tokens,
        address _claimFor,
        address _recipient
    ) external;

    function claimFeesToRecipientByTokenId(
        address[] memory _fees,
        address[][] memory _tokens,
        uint256 _tokenId,
        address _recipient
    ) external;

    function claimFeesToRecipientByAddress(
        address[] memory _fees,
        address[][] memory _tokens,
        address _claimFor,
        address _recipient
    ) external;
} 