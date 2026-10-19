// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {ImmutableVeTokenConduit} from "../../src/ImmutableVeTokenConduit.sol";
import {MockBribe} from "../mocks/MockBribe.sol";
import {MockFeed} from "../mocks/MockFeed.sol";
import {MockRouter} from "../mocks/MockRouter.sol";
import {MockToken} from "../mocks/MockToken.sol";
import {MockVoter} from "../mocks/MockVoter.sol";
import {MockVotingEscrow} from "../mocks/MockVotingEscrow.sol";

contract FeeHarness is ImmutableVeTokenConduit {
    constructor(
        address voter_,
        address veToken_,
        address usdc_,
        address sequencerFeed_,
        address[] memory routers_,
        PricedToken[] memory pricedTokens_
    ) ImmutableVeTokenConduit(voter_, veToken_, usdc_, sequencerFeed_, routers_, pricedTokens_) {}

    function fee(uint256 amount, uint256 bps) external pure returns (uint256) {
        return _fee(amount, bps);
    }
}

abstract contract ConduitTestBase is Test {
    uint256 internal constant WEEK = 604800;
    uint256 internal constant EPOCH = 2963 * WEEK;
    uint256 internal constant POWER = 1_000_000e18;
    uint256 internal constant TOKEN_ID = 7;

    int256 internal constant ETH_USD = 2400e8;
    int256 internal constant BTC_USD = 80_000e8;
    int256 internal constant USDC_USD = 1e8;
    int256 internal constant EURC_USD = 1.12e8;

    address internal holder = makeAddr("holder");
    address internal stranger = makeAddr("stranger");
    address internal bribeOwner = makeAddr("bribe owner");
    address internal treasury;

    MockVotingEscrow internal ve;
    MockVoter internal voter;
    MockToken internal weth;
    MockToken internal cbbtc;
    MockToken internal usdc;
    MockToken internal eurc;
    MockToken internal junk;
    MockFeed internal ethFeed;
    MockFeed internal btcFeed;
    MockFeed internal usdcFeed;
    MockFeed internal eurcFeed;
    MockFeed internal sequencer;
    MockRouter internal router;
    ImmutableVeTokenConduit internal conduit;

    uint256 internal poolCount;
    MockBribe internal rewardBribe;

    function setUp() public virtual {
        vm.warp(EPOCH + 1 days);
        sequencer = new MockFeed(0, 0);
        sequencer.setStartedAt(EPOCH - 30 days);
        weth = new MockToken(18);
        cbbtc = new MockToken(8);
        usdc = new MockToken(6);
        eurc = new MockToken(6);
        junk = new MockToken(18);
        ethFeed = new MockFeed(8, ETH_USD);
        btcFeed = new MockFeed(8, BTC_USD);
        usdcFeed = new MockFeed(8, USDC_USD);
        eurcFeed = new MockFeed(8, EURC_USD);
        ve = new MockVotingEscrow();
        voter = new MockVoter(ve, bribeOwner);
        voter.setEpoch(EPOCH);
        router = new MockRouter();
        conduit = _deploy();
        treasury = conduit.TREASURY();
        ve.setPastVotes(address(conduit), EPOCH, POWER);
        ve.mint(TOKEN_ID, holder);
        vm.prank(holder);
        ve.setConduitApproval(address(conduit), TOKEN_ID, true);
    }

    function _routers() internal view returns (address[] memory r) {
        r = new address[](1);
        r[0] = address(router);
    }

    function _priced() internal view returns (ImmutableVeTokenConduit.PricedToken[] memory p) {
        p = new ImmutableVeTokenConduit.PricedToken[](4);
        p[0] = ImmutableVeTokenConduit.PricedToken(address(weth), address(ethFeed), 1500);
        p[1] = ImmutableVeTokenConduit.PricedToken(address(cbbtc), address(btcFeed), 1500);
        p[2] = ImmutableVeTokenConduit.PricedToken(address(usdc), address(usdcFeed), 108_000);
        p[3] = ImmutableVeTokenConduit.PricedToken(address(eurc), address(eurcFeed), 108_000);
    }

    function _deploy() internal returns (ImmutableVeTokenConduit) {
        return new ImmutableVeTokenConduit(
            address(voter), address(ve), address(usdc), address(sequencer), _routers(), _priced()
        );
    }

    function _deployHarness() internal returns (FeeHarness) {
        return new FeeHarness(address(voter), address(ve), address(usdc), address(sequencer), _routers(), _priced());
    }

    /// @dev A new pool with a live gauge, `others` votes from other voters, and `usd` dollars of USDC rewards this
    /// epoch on its external bribe.
    function _pool(uint256 usd, uint256 others) internal returns (address pool) {
        pool = address(uint160(0x1000 + ++poolCount));
        voter.addPool(pool);
        if (usd != 0) _reward(pool, address(usdc), usd * 1e6);
        if (others != 0) voter.setOthers(pool, others);
    }

    function _reward(address pool, address token, uint256 amount) internal {
        MockBribe b = MockBribe(voter.external_bribes(voter.gauges(pool)));
        b.setRewards(token, voter._epochTimestamp(), b.rewardsPerEpoch(token, voter._epochTimestamp()) + amount);
    }

    function _one(address pool) internal pure returns (address[] memory pools, uint256[] memory weights) {
        pools = new address[](1);
        pools[0] = pool;
        weights = new uint256[](1);
        weights[0] = 1;
    }

    function _two(address a, address b, uint256 wa, uint256 wb)
        internal
        pure
        returns (address[] memory pools, uint256[] memory weights)
    {
        pools = new address[](2);
        pools[0] = a;
        pools[1] = b;
        weights = new uint256[](2);
        weights[0] = wa;
        weights[1] = wb;
    }

    function _next() internal {
        vm.warp(block.timestamp + 2);
        vm.roll(block.number + 1);
    }

    function _refreshFeeds() internal {
        ethFeed.set(ETH_USD, block.timestamp);
        btcFeed.set(BTC_USD, block.timestamp);
        usdcFeed.set(USDC_USD, block.timestamp);
        eurcFeed.set(EURC_USD, block.timestamp);
    }

    /// @dev Moves to the start of the next epoch plus `delay`, as the minter would.
    function _nextEpoch(uint256 delay) internal returns (uint256 epoch) {
        epoch = voter._epochTimestamp() + WEEK;
        vm.warp(epoch + delay);
        vm.roll(block.number + 1);
        voter.setEpoch(epoch);
        _refreshFeeds();
        ve.setPastVotes(address(conduit), epoch, POWER);
    }

    /// @dev Makes `amount` of `token` claimable for `TOKEN_ID` from `rewardBribe`.
    function _earn(address token, uint256 amount) internal {
        if (address(rewardBribe) == address(0)) {
            rewardBribe = MockBribe(voter.external_bribes(voter.gauges(_pool(0, 0))));
        }
        rewardBribe.setEarned(TOKEN_ID, token, amount);
    }

    function _bribes() internal view returns (address[] memory b) {
        b = new address[](1);
        b[0] = address(rewardBribe);
    }

    function _tokens(address a) internal pure returns (address[] memory t) {
        t = new address[](1);
        t[0] = a;
    }

    function _tokens(address a, address b) internal pure returns (address[] memory t) {
        t = new address[](2);
        t[0] = a;
        t[1] = b;
    }

    function _swap(address token, uint256 amountIn, uint256 usdcOut, address to)
        internal
        view
        returns (ImmutableVeTokenConduit.Swap memory)
    {
        return ImmutableVeTokenConduit.Swap(
            token, address(router), abi.encodeCall(MockRouter.swap, (token, amountIn, address(usdc), usdcOut, to))
        );
    }

    function _swaps(ImmutableVeTokenConduit.Swap memory a)
        internal
        pure
        returns (ImmutableVeTokenConduit.Swap[] memory s)
    {
        s = new ImmutableVeTokenConduit.Swap[](1);
        s[0] = a;
    }

    function _claim(address caller, address[] memory tokens, ImmutableVeTokenConduit.Swap[] memory swaps, uint256 min)
        internal
        returns (uint256 usdcOut, uint256 fee)
    {
        vm.prank(caller);
        return conduit.claim(TOKEN_ID, new address[](0), _bribes(), tokens, swaps, min);
    }
}
