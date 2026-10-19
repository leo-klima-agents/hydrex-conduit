// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {MockBribe} from "./mocks/MockBribe.sol";
import {MockVoter} from "./mocks/MockVoter.sol";
import {ConduitTestBase} from "./utils/ConduitTestBase.sol";

contract VoteTest is ConduitTestBase {
    function _many(uint256 n, uint256 usd) internal returns (address[] memory pools, uint256[] memory weights) {
        pools = new address[](n);
        weights = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            pools[i] = _pool(usd, 0);
            weights[i] = 1;
        }
    }

    function test_vote_firstVoteAcceptedAtOneDollar() public {
        (address[] memory pools, uint256[] memory weights) = _one(_pool(1, 0));
        vm.prank(stranger);
        (uint256 oldScore, uint256 newScore) = conduit.vote(pools, weights);
        assertEq(newScore, 1e18);
        assertEq(oldScore, 0);
        assertEq(voter.lastVoted(address(conduit)), block.timestamp);
        assertEq(voter.votes(address(conduit), pools[0]), POWER);
    }

    function test_vote_firstVoteBelowOneDollarReverts() public {
        address pool = _pool(0, 0);
        _reward(pool, address(usdc), 1e6 - 1);
        (address[] memory pools, uint256[] memory weights) = _one(pool);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.NotBetter.selector, 0, 1e18 - 1e12));
        conduit.vote(pools, weights);
    }

    function test_vote_belowCurrentPlusOneDollarReverts() public {
        address a = _pool(100, 0);
        address b = _pool(0, 0);
        _reward(b, address(usdc), 101e6 - 1);
        (address[] memory pools, uint256[] memory weights) = _one(a);
        conduit.vote(pools, weights);
        _next();
        (pools, weights) = _one(b);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.NotBetter.selector, 100e18, 101e18 - 1e12));
        conduit.vote(pools, weights);
        (pools, weights) = _one(a);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.NotBetter.selector, 100e18, 100e18));
        conduit.vote(pools, weights);
    }

    function test_vote_betterProposalAccepted() public {
        address a = _pool(100, 0);
        address b = _pool(101, 0);
        (address[] memory pools, uint256[] memory weights) = _one(a);
        conduit.vote(pools, weights);
        _next();
        (pools, weights) = _one(b);
        vm.prank(stranger);
        (uint256 oldScore, uint256 newScore) = conduit.vote(pools, weights);
        assertEq(oldScore, 100e18);
        assertEq(newScore, 101e18);
        assertEq(voter.poolVoteLength(address(conduit)), 1);
        assertEq(voter.poolVote(address(conduit), 0), b);
        assertEq(voter.votes(address(conduit), a), 0);
        assertEq(voter.weights(a), 0);
        assertEq(voter.weights(b), POWER);
    }

    function test_vote_splitBeatsSingle() public {
        address a = _pool(100, POWER);
        address b = _pool(100, POWER);
        (address[] memory pools, uint256[] memory weights) = _one(a);
        conduit.vote(pools, weights);
        assertEq(conduit.currentScore(), 50e18);
        _next();
        (pools, weights) = _two(a, b, 1, 1);
        (, uint256 newScore) = conduit.vote(pools, weights);
        assertEq(newScore, 2 * (100e18 * (POWER / 2) / (POWER + POWER / 2)));
    }

    function test_vote_emitsVoteAccepted() public {
        (address[] memory pools, uint256[] memory weights) = _one(_pool(5, 0));
        vm.expectEmit(address(conduit));
        emit ImmutableVeTokenConduit.VoteAccepted(EPOCH, stranger, pools, weights, 0, 5e18);
        vm.prank(stranger);
        conduit.vote(pools, weights);
    }

    function test_vote_revertsOnDuplicatePoolsBeforeScoringTheVoteInForce() public {
        address a = _pool(100, 0);
        (address[] memory pools, uint256[] memory weights) = _one(a);
        conduit.vote(pools, weights);
        _next();
        (pools, weights) = _two(a, a, 1, 1);
        vm.expectCall(address(voter), abi.encodeWithSelector(MockVoter.poolVoteLength.selector), 0);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.Duplicate.selector, a));
        conduit.vote(pools, weights);
    }

    function test_vote_revertsOnTooManyPools() public {
        (address[] memory pools, uint256[] memory weights) = _many(conduit.MAX_POOLS() + 1, 10);
        vm.expectRevert(ImmutableVeTokenConduit.BadPoolCount.selector);
        conduit.vote(pools, weights);
    }

    function test_vote_acceptsMaxPools() public {
        uint256 n = conduit.MAX_POOLS();
        (address[] memory pools, uint256[] memory weights) = _many(n, 10);
        (, uint256 newScore) = conduit.vote(pools, weights);
        assertEq(newScore, n * 10e18);
        assertEq(voter.poolVoteLength(address(conduit)), n);
    }

    function test_vote_revertsOnNoPools() public {
        vm.expectRevert(ImmutableVeTokenConduit.BadPoolCount.selector);
        conduit.vote(new address[](0), new uint256[](0));
    }

    function test_vote_revertsOnZeroWeight() public {
        (address[] memory pools, uint256[] memory weights) = _two(_pool(100, 0), _pool(100, 0), 1, 0);
        vm.expectRevert(ImmutableVeTokenConduit.ZeroWeight.selector);
        conduit.vote(pools, weights);
    }

    function test_vote_revertsWhenAPoolWouldGetNoVotes() public {
        ve.setPastVotes(address(conduit), EPOCH, 10);
        address b = _pool(100, 0);
        (address[] memory pools, uint256[] memory weights) = _two(_pool(100, 0), b, 100, 1);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.ZeroVotes.selector, b));
        conduit.vote(pools, weights);
    }

    function test_vote_revertsOnDeadGauge() public {
        address a = _pool(100, 0);
        address b = _pool(100, 0);
        voter.killGauge(voter.gauges(b));
        (address[] memory pools, uint256[] memory weights) = _two(a, b, 1, 1);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.DeadGauge.selector, b));
        conduit.vote(pools, weights);
        address noGauge = address(0xbeef);
        (pools, weights) = _two(a, noGauge, 1, 1);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.DeadGauge.selector, noGauge));
        conduit.vote(pools, weights);
    }

    function test_vote_killedGaugeInForceStillCounts() public {
        address a = _pool(100, 0);
        (address[] memory pools, uint256[] memory weights) = _one(a);
        conduit.vote(pools, weights);
        voter.killGauge(voter.gauges(a));
        _next();
        (pools, weights) = _one(_pool(100, 0));
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.NotBetter.selector, 100e18, 100e18));
        conduit.vote(pools, weights);
        (pools, weights) = _one(_pool(101, 0));
        (uint256 oldScore,) = conduit.vote(pools, weights);
        assertEq(oldScore, 100e18);
    }

    function test_vote_revertsOnLengthMismatch() public {
        (address[] memory pools,) = _two(_pool(100, 0), _pool(100, 0), 1, 1);
        vm.expectRevert(ImmutableVeTokenConduit.LengthMismatch.selector);
        conduit.vote(pools, new uint256[](1));
    }

    function test_vote_revertsOnStaleEpoch() public {
        (address[] memory pools, uint256[] memory weights) = _one(_pool(100, 0));
        vm.warp(EPOCH + WEEK);
        _refreshFeeds();
        vm.expectRevert(ImmutableVeTokenConduit.EpochStale.selector);
        conduit.vote(pools, weights);
        vm.expectRevert(ImmutableVeTokenConduit.EpochStale.selector);
        conduit.currentScore();
        vm.warp(EPOCH - 1);
        vm.expectRevert(ImmutableVeTokenConduit.EpochStale.selector);
        conduit.vote(pools, weights);
    }

    function test_vote_revertsWithoutPower() public {
        ve.setPastVotes(address(conduit), EPOCH, 0);
        (address[] memory pools, uint256[] memory weights) = _one(_pool(100, 0));
        vm.expectRevert(ImmutableVeTokenConduit.NoVotingPower.selector);
        conduit.vote(pools, weights);
    }

    function test_vote_secondVoteInSameBlockRevertsInVoter() public {
        address a = _pool(100, 0);
        address b = _pool(200, 0);
        (address[] memory pools, uint256[] memory weights) = _one(a);
        conduit.vote(pools, weights);
        (pools, weights) = _one(b);
        vm.expectRevert(MockVoter.VoteDelayNotMet.selector);
        conduit.vote(pools, weights);
    }

    function test_vote_votesDoNotCarryOver() public {
        address a = _pool(100, 0);
        (address[] memory pools, uint256[] memory weights) = _one(a);
        conduit.vote(pools, weights);
        _nextEpoch(1 hours);
        _reward(a, address(usdc), 1e6);
        assertEq(conduit.currentScore(), 0);
        (uint256 oldScore, uint256 newScore) = conduit.vote(pools, weights);
        assertEq(oldScore, 0);
        assertEq(newScore, 1e18);
        assertEq(voter.weights(a), POWER);
    }

    function test_vote_anyAcceptedVoteCanBeReplaced() public {
        uint256 n = conduit.MAX_POOLS();
        (address[] memory pools, uint256[] memory weights) = _many(n, 10);
        conduit.vote(pools, weights);
        _next();
        (pools, weights) = _many(n, 11);
        (uint256 oldScore, uint256 newScore) = conduit.vote(pools, weights);
        assertEq(oldScore, n * 10e18);
        assertEq(newScore, n * 11e18);
    }

    function test_knownLimitation_bribeOwnerCanDepositAndRecover() public {
        address honest = _pool(100, 0);
        address captured = _pool(0, 0);
        (address[] memory pools, uint256[] memory weights) = _one(honest);
        conduit.vote(pools, weights);
        _next();

        MockBribe bribe = MockBribe(voter.external_bribes(voter.gauges(captured)));
        usdc.mint(bribeOwner, 1_000e6);
        vm.startPrank(bribeOwner);
        usdc.approve(address(bribe), 1_000e6);
        bribe.notifyRewardAmount(address(usdc), 1_000e6);
        (pools, weights) = _one(captured);
        conduit.vote(pools, weights);
        bribe.recoverERC20AndUpdateData(address(usdc), 1_000e6);
        vm.stopPrank();

        assertEq(voter.poolVote(address(conduit), 0), captured);
        assertEq(usdc.balanceOf(bribeOwner), 1_000e6);
        assertEq(conduit.poolValue(captured), 0);
    }
}
