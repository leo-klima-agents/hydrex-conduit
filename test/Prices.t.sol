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
        ImmutableVeTokenConduit.PricedToken[] memory p = new ImmutableVeTokenConduit.PricedToken[](1);
        p[0] = ImmutableVeTokenConduit.PricedToken(address(t), address(f), 100);
        ImmutableVeTokenConduit c = _deployWith(p);
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

    function test_poolValue_staleFeedCountsZero() public {
        ethFeed.set(ETH_USD, block.timestamp - 1500);
        assertEq(conduit.poolValue(pool), 2410e18);
        ethFeed.set(ETH_USD, block.timestamp - 1501);
        assertEq(conduit.poolValue(pool), 10e18);
        usdcFeed.set(USDC_USD, block.timestamp - 108_000);
        assertEq(conduit.poolValue(pool), 10e18);
        usdcFeed.set(USDC_USD, block.timestamp - 108_001);
        assertEq(conduit.poolValue(pool), 0);
    }

    function test_poolValue_invalidFeedCountsZero() public {
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
        (, uint256 newScore) = conduit.vote(pools, weights);
        assertEq(newScore, 10e18);
    }

    function test_sequencerDown_revertsVotes() public {
        sequencer.set(1, 0);
        _assertSequencerBlocks(abi.encodeWithSelector(ImmutableVeTokenConduit.SequencerDown.selector));
    }

    function test_sequencerGrace_revertsVotes() public {
        sequencer.setStartedAt(block.timestamp - 3600);
        _assertSequencerBlocks(abi.encodeWithSelector(ImmutableVeTokenConduit.SequencerDown.selector));
        sequencer.setStartedAt(block.timestamp - 3601);
        (address[] memory pools, uint256[] memory weights) = _one(pool);
        conduit.vote(pools, weights);
    }

    function test_sequencerFeedReverting_revertsVotes() public {
        sequencer.setReverts(true);
        _assertSequencerBlocks(bytes("feed reverts"));
    }

    function _assertSequencerBlocks(bytes memory err) internal {
        (address[] memory pools, uint256[] memory weights) = _one(pool);
        vm.expectRevert(err);
        conduit.vote(pools, weights);
        vm.expectRevert(err);
        conduit.score(pools, weights);
        vm.expectRevert(err);
        conduit.currentScore();
        vm.expectRevert(err);
        conduit.poolValue(pool);
    }

    function test_claim_readsNoFeeds() public {
        _earn(address(weth), 1e18);
        _earn(address(junk), 5e18);
        MockFeed[5] memory feeds = [ethFeed, btcFeed, usdcFeed, eurcFeed, sequencer];
        for (uint256 i; i < feeds.length; ++i) {
            feeds[i].setReverts(true);
            vm.expectCall(address(feeds[i]), abi.encodeWithSignature("latestRoundData()"), 0);
        }
        _claim(stranger, _tokens(address(weth), address(junk)));
        assertEq(weth.balanceOf(holder), 0.99e18);
        assertEq(junk.balanceOf(holder), 4.95e18);
    }
}
