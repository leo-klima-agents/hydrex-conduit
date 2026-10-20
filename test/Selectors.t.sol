// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {IAlgebraFactory} from "../src/interfaces/IAlgebraFactory.sol";
import {IAlgebraPool} from "../src/interfaces/IAlgebraPool.sol";
import {IBribe} from "../src/interfaces/IBribe.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVolatilityOracle} from "../src/interfaces/IVolatilityOracle.sol";
import {IVoter} from "../src/interfaces/IVoter.sol";
import {IVotingEscrow} from "../src/interfaces/IVotingEscrow.sol";

contract SelectorsTest is Test {
    struct Pin {
        bytes4 selector;
        bytes4 literal;
        string signature;
    }

    function _pins() internal pure returns (Pin[] memory p) {
        p = new Pin[](26);
        p[0] = Pin(IVoter.vote.selector, 0x6f816a20, "vote(address[],uint256[])");
        p[1] = Pin(IVoter._epochTimestamp.selector, 0xf8803bb6, "_epochTimestamp()");
        p[2] = Pin(IVoter.weights.selector, 0xa7cac846, "weights(address)");
        p[3] = Pin(IVoter.poolVoteLength.selector, 0x8daeaa5a, "poolVoteLength(address)");
        p[4] = Pin(IVoter.gauges.selector, 0xb9a09fd5, "gauges(address)");
        p[5] = Pin(IVoter.isAlive.selector, 0x1703e5f9, "isAlive(address)");
        p[6] = Pin(IVoter.external_bribes.selector, 0xae21c4cb, "external_bribes(address)");
        p[7] = Pin(IVoter.internal_bribes.selector, 0xeae40f26, "internal_bribes(address)");
        p[8] = Pin(IVoter.votes.selector, 0xcad1b906, "votes(address,address)");
        p[9] = Pin(IVoter.poolVote.selector, 0xc48f5af4, "poolVote(address,uint256)");
        p[10] = Pin(IVoter.lastVoted.selector, 0x9a61df89, "lastVoted(address)");
        p[11] = Pin(
            IVoter.claimBribesToRecipientByTokenId.selector,
            0xa5f00340,
            "claimBribesToRecipientByTokenId(address[],address[][],uint256,address)"
        );
        p[12] = Pin(
            IVoter.claimFeesToRecipientByTokenId.selector,
            0x11d41550,
            "claimFeesToRecipientByTokenId(address[],address[][],uint256,address)"
        );
        p[13] = Pin(IVotingEscrow.getPastVotes.selector, 0x3a46b1a8, "getPastVotes(address,uint256)");
        p[14] = Pin(
            IVotingEscrow.setConduitApprovalConfig.selector, 0x7c3a328f, "setConduitApprovalConfig(uint8[],string)"
        );
        p[15] = Pin(IVotingEscrow.ownerOf.selector, 0x6352211e, "ownerOf(uint256)");
        p[16] = Pin(IBribe.rewardData.selector, 0x38174862, "rewardData(address,uint256)");
        p[17] = Pin(IERC20.balanceOf.selector, 0x70a08231, "balanceOf(address)");
        p[18] = Pin(IERC20.transfer.selector, 0xa9059cbb, "transfer(address,uint256)");
        p[19] = Pin(IERC20.decimals.selector, 0x313ce567, "decimals()");
        p[20] = Pin(IAggregatorV3.latestRoundData.selector, 0xfeaf968c, "latestRoundData()");
        p[21] = Pin(IBribe.totalSupplyAt.selector, 0x981b24d0, "totalSupplyAt(uint256)");
        p[22] = Pin(IBribe.rewardTokens.selector, 0x7bb7bed1, "rewardTokens(uint256)");
        p[23] = Pin(IAlgebraFactory.poolByPair.selector, 0xd9a641e1, "poolByPair(address,address)");
        p[24] = Pin(IAlgebraPool.plugin.selector, 0xef01df4f, "plugin()");
        p[25] = Pin(IVolatilityOracle.getTimepoints.selector, 0x9d3a5241, "getTimepoints(uint32[])");
    }

    function test_selectors_matchLiteralsAndSignatures() public pure {
        Pin[] memory p = _pins();
        for (uint256 i; i < p.length; ++i) {
            assertEq(p[i].selector, p[i].literal, p[i].signature);
            assertEq(p[i].selector, bytes4(keccak256(bytes(p[i].signature))), p[i].signature);
        }
        assertEq(IAggregatorV3.decimals.selector, IERC20.decimals.selector);
    }

    function test_selectors_conduitVoteMatchesVoter() public pure {
        assertEq(ImmutableVeTokenConduit.vote.selector, IVoter.vote.selector);
    }

    function test_selectors_upstreamMdTable() public view {
        string memory md = vm.readFile("test/upstream/UPSTREAM.md");
        Pin[] memory p = _pins();
        for (uint256 i; i < p.length; ++i) {
            string memory row =
                string.concat("| `", p[i].signature, "` | `", vm.toString(abi.encodePacked(p[i].literal)), "` |");
            assertTrue(vm.contains(md, row), string.concat("UPSTREAM.md row missing or stale: ", row));
        }
    }
}
