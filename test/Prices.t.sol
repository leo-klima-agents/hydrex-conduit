// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {MockFeed} from "./mocks/MockFeed.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {ConduitTestBase} from "./utils/ConduitTestBase.sol";

contract PricesTest is ConduitTestBase {
    address internal pool;

    function setUp() public override {
        super.setUp();
        pool = _pool(0, 0);
        _reward(pool, address(weth), 1e18);
        _reward(pool, address(usdc), 10e6);
    }

    function test_scaling_matchesDecimals() public view {
        _assertOracle(0, address(weth), address(ethFeed), 1500, 1, 1e8);
        _assertOracle(1, address(cbbtc), address(btcFeed), 1500, 100, 1);
        _assertOracle(2, address(usdc), address(usdcFeed), 108_000, 1e4, 1);
        _assertOracle(3, address(eurc), address(eurcFeed), 108_000, 1e4, 1);
    }

    function _assertOracle(uint256 i, address token, address feed, uint256 maxAge, uint256 mul, uint256 div)
        internal
        view
    {
        (address t, address f, uint256 a, uint256 m, uint256 d) = conduit.pricedTokens(i);
        assertEq(t, token);
        assertEq(f, feed);
        assertEq(a, maxAge);
        assertEq(m, mul);
        assertEq(d, div);
    }

    function test_scaling_oneUnitOfEachToken() public {
        address p = _pool(0, 0);
        _reward(p, address(cbbtc), 1e8);
        assertEq(conduit.poolValue(p), 80_000e18);
        p = _pool(0, 0);
        _reward(p, address(eurc), 1e6);
        assertEq(conduit.poolValue(p), 1.12e18);
        assertEq(conduit.poolValue(pool), 2400e18 + 10e18);
    }

    function testFuzz_scaling_anyDecimals(uint8 tokenDecimals, uint8 feedDecimals, uint256 amount) public {
        tokenDecimals = uint8(bound(tokenDecimals, 0, 36));
        feedDecimals = uint8(bound(feedDecimals, 0, 36));
        amount = bound(amount, 0, 1e30);
        MockToken t = new MockToken(tokenDecimals);
        MockFeed f = new MockFeed(feedDecimals, int256(3 * 10 ** feedDecimals));
        ImmutableVeTokenConduit.PricedToken[] memory p = new ImmutableVeTokenConduit.PricedToken[](2);
        p[0] = ImmutableVeTokenConduit.PricedToken(address(usdc), address(usdcFeed), 108_000);
        p[1] = ImmutableVeTokenConduit.PricedToken(address(t), address(f), 100);
        ImmutableVeTokenConduit c =
            new ImmutableVeTokenConduit(address(voter), address(ve), address(usdc), address(sequencer), _routers(), p);
        ve.setPastVotes(address(c), EPOCH, POWER);
        address q = _pool(0, 0);
        _reward(q, address(t), amount);
        uint256 d = uint256(tokenDecimals) + feedDecimals;
        uint256 expected = d <= 18
            ? amount * 3 * 10 ** feedDecimals * 10 ** (18 - d)
            : amount * 3 * 10 ** feedDecimals / 10 ** (d - 18);
        assertEq(c.poolValue(q), expected);
        assertApproxEqAbs(c.poolValue(q), amount * 3e18 / 10 ** tokenDecimals, 1);
    }

    function test_vote_staleFeedCountsZero() public {
        ethFeed.set(ETH_USD, block.timestamp - 1500);
        assertEq(conduit.poolValue(pool), 2410e18);
        ethFeed.set(ETH_USD, block.timestamp - 1501);
        assertEq(conduit.poolValue(pool), 10e18);
        usdcFeed.set(USDC_USD, block.timestamp - 108_000);
        assertEq(conduit.poolValue(pool), 10e18);
        usdcFeed.set(USDC_USD, block.timestamp - 108_001);
        assertEq(conduit.poolValue(pool), 0);
    }

    function test_vote_invalidFeedCountsZero() public {
        ethFeed.set(0, block.timestamp);
        assertEq(conduit.poolValue(pool), 10e18);
        ethFeed.set(-1, block.timestamp);
        assertEq(conduit.poolValue(pool), 10e18);
        ethFeed.set(ETH_USD, block.timestamp + 1);
        assertEq(conduit.poolValue(pool), 10e18);
        ethFeed.set(ETH_USD, block.timestamp);
        ethFeed.setReverts(true);
        assertEq(conduit.poolValue(pool), 10e18);
        vm.etch(address(ethFeed), hex"00");
        assertEq(conduit.poolValue(pool), 10e18);
    }

    function test_vote_badFeedDoesNotBlockVoting() public {
        ethFeed.setReverts(true);
        (address[] memory pools, uint256[] memory weights) = _one(pool);
        (uint256 newScore,) = conduit.vote(pools, weights);
        assertEq(newScore, 10e18);
    }

    function test_claim_staleFeedReverts() public {
        _earn(address(weth), 1e18);
        ethFeed.set(ETH_USD, block.timestamp - 1501);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnpricedToken.selector, address(weth)));
        _claim(stranger, _tokens(address(weth)), _swaps(_swap(address(weth), 1e18, 2400e6, address(conduit))), 0);
    }

    function test_claim_invalidFeedReverts() public {
        _earn(address(weth), 1e18);
        ImmutableVeTokenConduit.Swap[] memory s = _swaps(_swap(address(weth), 1e18, 2400e6, address(conduit)));
        int256[2] memory bad = [int256(0), -1];
        for (uint256 i; i < bad.length; ++i) {
            ethFeed.set(bad[i], block.timestamp);
            vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnpricedToken.selector, address(weth)));
            _claim(stranger, _tokens(address(weth)), s, 0);
        }
        ethFeed.set(ETH_USD, block.timestamp);
        ethFeed.setReverts(true);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnpricedToken.selector, address(weth)));
        _claim(stranger, _tokens(address(weth)), s, 0);
    }

    function test_claim_staleUsdcFeedReverts() public {
        _earn(address(weth), 1e18);
        usdcFeed.set(USDC_USD, block.timestamp - 108_001);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnpricedToken.selector, address(usdc)));
        _claim(stranger, _tokens(address(weth)), _swaps(_swap(address(weth), 1e18, 2400e6, address(conduit))), 0);
    }

    function test_claim_unrelatedBadFeedDoesNotRevert() public {
        _earn(address(weth), 1e18);
        btcFeed.setReverts(true);
        eurcFeed.set(-1, block.timestamp);
        (uint256 out,) =
            _claim(stranger, _tokens(address(weth)), _swaps(_swap(address(weth), 1e18, 2400e6, address(conduit))), 0);
        assertEq(out, 2376e6);
    }

    function test_sequencerDown_revertsVotesAndThirdPartyClaims() public {
        _earn(address(weth), 1e18);
        sequencer.set(1, 0);
        _assertSequencerBlocks();
    }

    function test_sequencerGrace_revertsVotesAndThirdPartyClaims() public {
        _earn(address(weth), 1e18);
        sequencer.setStartedAt(block.timestamp - 3600);
        _assertSequencerBlocks();
        sequencer.setStartedAt(block.timestamp - 3601);
        (address[] memory pools, uint256[] memory weights) = _one(pool);
        conduit.vote(pools, weights);
        _claim(stranger, _tokens(address(weth)), _swaps(_swap(address(weth), 1e18, 2400e6, address(conduit))), 0);
    }

    function test_sequencerFeedReverting_revertsVotesAndThirdPartyClaims() public {
        _earn(address(weth), 1e18);
        sequencer.setReverts(true);
        (address[] memory pools, uint256[] memory weights) = _one(pool);
        vm.expectRevert(bytes("feed reverts"));
        conduit.vote(pools, weights);
        vm.expectRevert(bytes("feed reverts"));
        _claim(stranger, _tokens(address(weth)), _swaps(_swap(address(weth), 1e18, 2400e6, address(conduit))), 0);
        _claim(holder, _tokens(address(weth)), _swaps(_swap(address(weth), 1e18, 2400e6, address(conduit))), 0);
    }

    function _assertSequencerBlocks() internal {
        (address[] memory pools, uint256[] memory weights) = _one(pool);
        ImmutableVeTokenConduit.Swap[] memory s = _swaps(_swap(address(weth), 1e18, 2400e6, address(conduit)));
        vm.expectRevert(ImmutableVeTokenConduit.SequencerDown.selector);
        conduit.vote(pools, weights);
        vm.expectRevert(ImmutableVeTokenConduit.SequencerDown.selector);
        conduit.score(pools, weights);
        vm.expectRevert(ImmutableVeTokenConduit.SequencerDown.selector);
        conduit.currentScore();
        vm.expectRevert(ImmutableVeTokenConduit.SequencerDown.selector);
        conduit.poolValue(pool);
        vm.expectRevert(ImmutableVeTokenConduit.SequencerDown.selector);
        _claim(stranger, _tokens(address(weth)), s, 0);
        vm.expectRevert(ImmutableVeTokenConduit.SequencerDown.selector);
        conduit.claimFloor(_tokens(address(weth)), new uint256[](1));

        uint256 snapshot = vm.snapshotState();
        (uint256 out, uint256 fee) = _claim(holder, _tokens(address(weth)), s, 0);
        assertEq(out + fee, 2400e6);
        vm.revertToState(snapshot);
    }

    function test_ownerClaim_readsNoFeeds() public {
        _earn(address(weth), 1e18);
        _earn(address(junk), 5e18);
        ImmutableVeTokenConduit.Swap[] memory s = new ImmutableVeTokenConduit.Swap[](2);
        s[0] = _swap(address(weth), 1e18, 2400e6, address(conduit));
        s[1] = _swap(address(junk), 5e18, 1e6, address(conduit));
        MockFeed[5] memory feeds = [ethFeed, btcFeed, usdcFeed, eurcFeed, sequencer];
        for (uint256 i; i < feeds.length; ++i) {
            feeds[i].setReverts(true);
            vm.expectCall(address(feeds[i]), abi.encodeWithSignature("latestRoundData()"), 0);
        }
        (uint256 out, uint256 fee) = _claim(holder, _tokens(address(weth), address(junk)), s, 0);
        assertEq(out + fee, 2401e6);
    }
}
