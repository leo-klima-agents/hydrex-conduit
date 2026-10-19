// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {MockBribe} from "./mocks/MockBribe.sol";
import {ConduitTestBase} from "./utils/ConduitTestBase.sol";
import {Reference} from "./utils/Reference.sol";

contract ScoreTest is ConduitTestBase {
    struct Case {
        address[] pools;
        uint256[] weights;
        uint256[] values;
        uint256[] others;
    }

    function _case(uint256 seed, uint256 n, uint256 maxUsdc, uint256 maxOthers, uint256 maxWeight)
        internal
        returns (Case memory c)
    {
        c.pools = new address[](n);
        c.weights = new uint256[](n);
        c.values = new uint256[](n);
        c.others = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            uint256 amount = uint256(keccak256(abi.encode(seed, "b", i))) % (maxUsdc + 1);
            c.others[i] = uint256(keccak256(abi.encode(seed, "v", i))) % (maxOthers + 1);
            c.weights[i] = 1 + uint256(keccak256(abi.encode(seed, "w", i))) % maxWeight;
            c.pools[i] = _pool(0, c.others[i]);
            _reward(c.pools[i], address(usdc), amount);
            c.values[i] = amount * 1e12;
        }
    }

    function _expected(Case memory c, uint256 power) internal pure returns (uint256 s) {
        uint256 total;
        for (uint256 i; i < c.weights.length; ++i) {
            total += c.weights[i];
        }
        for (uint256 i; i < c.weights.length; ++i) {
            s += Reference.share(c.values[i], c.others[i], Reference.votesFor(c.weights[i], power, total));
        }
    }

    function testFuzz_score_matchesReference(uint256 seed, uint256 n, uint256 power) public {
        n = bound(n, 1, conduit.MAX_POOLS());
        power = bound(power, 1e18, 1e30);
        ve.setPastVotes(address(conduit), EPOCH, power);
        Case memory c = _case(seed, n, 1e36, 1e30, 1e9);
        assertEq(conduit.score(c.pools, c.weights), _expected(c, power));
        for (uint256 i; i < n; ++i) {
            assertEq(conduit.poolValue(c.pools[i]), c.values[i]);
        }
    }

    function testFuzz_votes_roundAsTheVoter(uint256 seed, uint256 n, uint256 power) public {
        n = bound(n, 1, conduit.MAX_POOLS());
        power = bound(power, 1e18, 1e30);
        ve.setPastVotes(address(conduit), EPOCH, power);
        Case memory c = _case(seed, n, 1e30, 1e30, 1e12);
        uint256 expected = _expected(c, power);
        vm.assume(expected >= 1e18);

        uint256 proposed = conduit.score(c.pools, c.weights);
        conduit.vote(c.pools, c.weights);

        uint256 total;
        for (uint256 i; i < n; ++i) {
            total += c.weights[i];
        }
        for (uint256 i; i < n; ++i) {
            assertEq(voter.votes(address(conduit), c.pools[i]), Reference.votesFor(c.weights[i], power, total));
            assertEq(voter.weights(c.pools[i]), c.others[i] + voter.votes(address(conduit), c.pools[i]));
        }
        assertEq(conduit.currentScore(), proposed);
        assertEq(proposed, expected);
    }

    function test_score_noOverflowAtBounds() public {
        uint256 n = conduit.MAX_POOLS();
        ve.setPastVotes(address(conduit), EPOCH, 1e30);
        Case memory c;
        c.pools = new address[](n);
        c.weights = new uint256[](n);
        c.values = new uint256[](n);
        c.others = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            c.others[i] = i % 2 == 0 ? 1e30 : 0;
            c.pools[i] = _pool(0, c.others[i]);
            _reward(c.pools[i], address(usdc), 1e36);
            c.values[i] = 1e48;
            c.weights[i] = 1e30;
        }
        assertEq(conduit.poolValue(c.pools[0]), 1e48);
        assertEq(conduit.score(c.pools, c.weights), _expected(c, 1e30));

        (address[] memory one, uint256[] memory w) = _one(c.pools[0]);
        assertEq(conduit.score(one, w), Reference.share(1e48, 1e30, 1e30));
        assertEq(conduit.score(one, w), 0.5e48);
    }

    function test_score_noOverflowAtBounds_wethAndBtc() public {
        address pool = _pool(0, 1e30);
        _reward(pool, address(weth), uint256(1e30 * 1e18) / 2400);
        _reward(pool, address(cbbtc), 1e30 * 1e8 / 80_000);
        (address[] memory pools, uint256[] memory weights) = _one(pool);
        ve.setPastVotes(address(conduit), EPOCH, 1e30);
        uint256 value = conduit.poolValue(pool);
        assertApproxEqRel(value, 2e48, 1e-12 ether);
        assertEq(conduit.score(pools, weights), Reference.share(value, 1e30, 1e30));
    }

    function test_poolValue_sumsBothBribesAndEveryPricedToken() public {
        address pool = _pool(0, 0);
        address gauge = voter.gauges(pool);
        MockBribe ext = MockBribe(voter.external_bribes(gauge));
        MockBribe intl = MockBribe(voter.internal_bribes(gauge));
        ext.setRewards(address(weth), EPOCH, 1e18);
        intl.setRewards(address(weth), EPOCH, 0.5e18);
        ext.setRewards(address(cbbtc), EPOCH, 1e8);
        intl.setRewards(address(usdc), EPOCH, 10e6);
        ext.setRewards(address(eurc), EPOCH, 100e6);
        assertEq(conduit.poolValue(pool), 3600e18 + 80_000e18 + 10e18 + 112e18);
    }

    function test_poolValue_ignoresOtherEpochs() public {
        address pool = _pool(0, 0);
        MockBribe ext = MockBribe(voter.external_bribes(voter.gauges(pool)));
        ext.setRewards(address(usdc), EPOCH - WEEK, 1000e6);
        ext.setRewards(address(usdc), EPOCH + WEEK, 1000e6);
        assertEq(conduit.poolValue(pool), 0);
    }

    function test_poolValue_unpricedTokensCountZero() public {
        address pool = _pool(0, 0);
        _reward(pool, address(junk), 1_000_000e18);
        assertEq(conduit.poolValue(pool), 0);
        _reward(pool, address(usdc), 5e6);
        assertEq(conduit.poolValue(pool), 5e18);
    }

    function test_poolValue_deadGaugeWithoutVotesCountsZero() public {
        address pool = _pool(1000, 0);
        assertEq(conduit.poolValue(pool), 1000e18);
        voter.killGauge(voter.gauges(pool));
        assertEq(conduit.poolValue(pool), 0);
        assertEq(conduit.poolValue(address(0xdead)), 0);
    }

    function test_currentScore_zeroBeforeVoting() public view {
        assertEq(conduit.currentScore(), 0);
    }

    function test_currentScore_killedGaugeKeepsItsBribes() public {
        address a = _pool(100, POWER);
        address b = _pool(50, 0);
        (address[] memory pools, uint256[] memory weights) = _two(a, b, 1, 1);
        conduit.vote(pools, weights);
        uint256 score = Reference.share(100e18, POWER, POWER / 2) + 50e18;
        assertEq(conduit.currentScore(), score);
        voter.killGauge(voter.gauges(a));
        assertEq(voter.weights(a), 0);
        assertEq(conduit.currentScore(), score);
        assertEq(conduit.poolValue(a), 100e18);
    }

    function test_ownVotes_subtractedOnlyWhenVoted() public {
        address pool = _pool(100, 3 * POWER);
        (address[] memory pools, uint256[] memory weights) = _one(pool);
        assertEq(conduit.score(pools, weights), 25e18);
        conduit.vote(pools, weights);
        assertEq(voter.weights(pool), 4 * POWER);
        assertEq(conduit.currentScore(), 25e18);
        assertEq(conduit.score(pools, weights), 25e18);

        _nextEpoch(1 hours);
        assertEq(voter.votes(address(conduit), pool), POWER, "the Voter keeps last epoch's votes until reset");
        _reward(pool, address(usdc), 100e6);
        voter.setOthers(pool, POWER);
        assertEq(conduit.currentScore(), 0);
        assertEq(conduit.score(pools, weights), 50e18);
    }

    function test_score_proposalSharingPoolsWithTheVoteInForce() public {
        address a = _pool(100, POWER);
        address b = _pool(300, POWER);
        (address[] memory pools, uint256[] memory weights) = _two(a, b, 1, 1);
        conduit.vote(pools, weights);
        _next();
        (pools, weights) = _two(b, a, 3, 1);
        uint256 expected = Reference.share(300e18, POWER, POWER * 3 / 4) + Reference.share(100e18, POWER, POWER / 4);
        assertEq(conduit.score(pools, weights), expected);
        (uint256 oldScore, uint256 newScore) = conduit.vote(pools, weights);
        assertEq(oldScore, Reference.share(100e18, POWER, POWER / 2) + Reference.share(300e18, POWER, POWER / 2));
        assertEq(newScore, expected);
    }

    function testFuzz_reference_mulDiv(uint256 a, uint256 b, uint256 d) public view {
        d = bound(d, 1, type(uint256).max);
        try this.mulDiv(a, b, d) returns (uint256 q) {
            unchecked {
                assertEq(q * d + mulmod(a, b, d), a * b);
            }
            if (a == 0 || b <= type(uint256).max / a) assertEq(q, a * b / d);
        } catch {}
    }

    function test_reference_mulDiv_knownValues() public pure {
        assertEq(Reference.mulDiv(2 ** 200, 2 ** 200, 2 ** 150), 2 ** 250);
        assertEq(Reference.mulDiv(type(uint256).max, type(uint256).max, type(uint256).max), type(uint256).max);
        assertEq(Reference.mulDiv(1e48, 1e30, 3e30), uint256(1e48) / 3);
    }

    function mulDiv(uint256 a, uint256 b, uint256 d) external pure returns (uint256) {
        return Reference.mulDiv(a, b, d);
    }

    function test_score_revertsWithoutPower() public {
        ve.setPastVotes(address(conduit), EPOCH, 0);
        (address[] memory pools, uint256[] memory weights) = _one(_pool(100, 0));
        vm.expectRevert(ImmutableVeTokenConduit.NoVotingPower.selector);
        conduit.score(pools, weights);
    }
}
