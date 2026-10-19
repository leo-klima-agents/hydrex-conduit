// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {MockBribe} from "./mocks/MockBribe.sol";
import {MockFeed} from "./mocks/MockFeed.sol";
import {MockRouter, ReentrantRouter} from "./mocks/MockRouter.sol";
import {MockFalseToken, MockNoReturnToken, MockTokenBase, MockUsdtToken} from "./mocks/MockToken.sol";
import {MockVoter} from "./mocks/MockVoter.sol";
import {ConduitTestBase, FeeHarness} from "./utils/ConduitTestBase.sol";

contract ClaimTest is ConduitTestBase {
    event Claimed(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed caller,
        address[] claimTokens,
        uint256[] claimedAmounts,
        uint256 usdcReceived,
        uint256 fee
    );

    ImmutableVeTokenConduit.Swap[] internal none;

    function _wethSwap(uint256 usdcOut) internal view returns (ImmutableVeTokenConduit.Swap[] memory) {
        return _swaps(_swap(address(weth), 1e18, usdcOut, address(conduit)));
    }

    function test_claim_strangerClaimsForOwner() public {
        _earn(address(weth), 1e18);
        _earn(address(usdc), 100e6);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 100e6;
        vm.expectEmit(address(conduit));
        emit Claimed(TOKEN_ID, holder, stranger, _tokens(address(weth), address(usdc)), amounts, 2500e6, 25e6);
        (uint256 out, uint256 fee) = _claim(stranger, _tokens(address(weth), address(usdc)), _wethSwap(2400e6), 0);
        assertEq(out, 2475e6);
        assertEq(fee, 25e6);
        assertEq(usdc.balanceOf(holder), 2475e6);
        assertEq(usdc.balanceOf(treasury), 25e6);
        assertEq(usdc.balanceOf(stranger), 0);
        assertEq(weth.balanceOf(stranger), 0);
        assertEq(usdc.balanceOf(address(conduit)), 0);
        assertEq(weth.balanceOf(address(conduit)), 0);
        assertEq(weth.allowance(address(conduit), address(router)), 0);
    }

    function testFuzz_claim_alwaysPaysTheOwner(address caller) public {
        vm.assume(caller != address(conduit) && caller != address(router));
        _earn(address(weth), 1e18);
        (uint256 out,) = _claim(caller, _tokens(address(weth)), _wethSwap(2400e6), 0);
        assertEq(out, 2376e6);
        assertEq(usdc.balanceOf(holder), out);
        if (caller != holder && caller != treasury) assertEq(usdc.balanceOf(caller), 0);
    }

    function test_claim_usdcRewardsWithoutSwaps() public {
        _earn(address(usdc), 100e6);
        (uint256 out, uint256 fee) = _claim(stranger, _tokens(address(usdc)), none, 0);
        assertEq(out, 99e6);
        assertEq(fee, 1e6);
        assertEq(usdc.balanceOf(holder), 99e6);
        assertEq(usdc.balanceOf(treasury), 1e6);
    }

    function test_claim_feeContractsAndBribes() public {
        address p = _pool(0, 0);
        MockBribe fees = MockBribe(voter.internal_bribes(voter.gauges(p)));
        fees.setEarned(TOKEN_ID, address(usdc), 30e6);
        _earn(address(usdc), 70e6);
        address[] memory feeAddresses = new address[](1);
        feeAddresses[0] = address(fees);
        vm.prank(stranger);
        (uint256 out, uint256 fee) = conduit.claim(TOKEN_ID, feeAddresses, _bribes(), _tokens(address(usdc)), none, 0);
        assertEq(out + fee, 100e6);
        assertEq(fee, 1e6);
    }

    function test_claim_nothingToClaim() public {
        (uint256 out, uint256 fee) =
            conduit.claim(TOKEN_ID, new address[](0), new address[](0), new address[](0), none, 0);
        assertEq(out, 0);
        assertEq(fee, 0);
    }

    function test_claim_notOptedInRevertsInVoter() public {
        ve.mint(8, makeAddr("other holder"));
        vm.expectRevert(MockVoter.NotApprovedOrOwner.selector);
        conduit.claim(8, new address[](0), _bribes(), new address[](0), none, 0);

        vm.prank(holder);
        ve.setConduitApproval(address(conduit), TOKEN_ID, false);
        _earn(address(usdc), 1e6);
        vm.expectRevert(MockVoter.NotApprovedOrOwner.selector);
        _claim(stranger, _tokens(address(usdc)), none, 0);
    }

    function test_claim_ownerOfRevertsForMissingToken() public {
        vm.expectRevert(bytes("ERC721NonexistentToken"));
        conduit.claim(404, new address[](0), new address[](0), new address[](0), none, 0);
    }

    function test_thirdParty_unpricedTokenReverts() public {
        _earn(address(junk), 1e18);
        ImmutableVeTokenConduit.Swap[] memory s = _swaps(_swap(address(junk), 1e18, 1e6, address(conduit)));
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnpricedToken.selector, address(junk)));
        _claim(stranger, _tokens(address(junk)), s, 0);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnpricedToken.selector, address(junk)));
        _claim(stranger, _tokens(address(usdc), address(junk)), s, 0);
    }

    function test_thirdParty_belowFloorReverts() public {
        _earn(address(weth), 1e18);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BelowOracleFloor.selector, 2376e6 - 1, 2376e6));
        _claim(stranger, _tokens(address(weth)), _wethSwap(2376e6 - 1), 0);
    }

    function test_thirdParty_usdcSentElsewhereReverts() public {
        _earn(address(weth), 1e18);
        address[2] memory sinks = [stranger, holder];
        for (uint256 i; i < sinks.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BelowOracleFloor.selector, 0, 2376e6));
            _claim(stranger, _tokens(address(weth)), _swaps(_swap(address(weth), 1e18, 2400e6, sinks[i])), 0);
        }
    }

    function test_thirdParty_exactlyAtFloorPasses() public {
        _earn(address(weth), 1e18);
        (uint256 out, uint256 fee) = _claim(stranger, _tokens(address(weth)), _wethSwap(2376e6), 0);
        assertEq(out + fee, 2376e6);
        assertEq(fee, 23.76e6);
    }

    function test_thirdParty_usdcRewardsDoNotCoverADivertedSwap() public {
        _earn(address(usdc), 10_000e6);
        _earn(address(weth), 0.04e18);
        uint256 floor = 10_000e6 + 96e6 * 99 / 100;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10_000e6;
        amounts[1] = 0.04e18;
        assertEq(conduit.claimFloor(_tokens(address(usdc), address(weth)), amounts), floor);

        ImmutableVeTokenConduit.Swap[] memory s = _swaps(_swap(address(weth), 0.04e18, 96e6, stranger));
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BelowOracleFloor.selector, 10_000e6, floor));
        _claim(stranger, _tokens(address(usdc), address(weth)), s, 0);

        s = _swaps(_swap(address(weth), 0.04e18, 96e6 * 99 / 100, address(conduit)));
        (uint256 out, uint256 fee) = _claim(stranger, _tokens(address(usdc), address(weth)), s, 0);
        assertEq(out + fee, floor);
    }

    function testFuzz_claimFloor_matchesClaim(uint256 wethAmount, uint256 btcAmount, uint256 usdcAmount) public {
        wethAmount = bound(wethAmount, 1e12, 1e24);
        btcAmount = bound(btcAmount, 1e3, 1e12);
        usdcAmount = bound(usdcAmount, 0, 1e15);
        _earn(address(weth), wethAmount);
        _earn(address(cbbtc), btcAmount);
        _earn(address(usdc), usdcAmount);
        address[] memory tokens = new address[](3);
        tokens[0] = address(weth);
        tokens[1] = address(cbbtc);
        tokens[2] = address(usdc);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = wethAmount;
        amounts[1] = btcAmount;
        amounts[2] = usdcAmount;
        uint256 floor = conduit.claimFloor(tokens, amounts);
        uint256 swapped = wethAmount * 2400e18 / 1e18 + btcAmount * 80_000e18 / 1e8;
        assertApproxEqAbs(floor, usdcAmount + swapped * 99 / 100 / 1e12, 1);

        ImmutableVeTokenConduit.Swap[] memory s = new ImmutableVeTokenConduit.Swap[](2);
        uint256 needed = floor - usdcAmount;
        s[0] = _swap(address(weth), wethAmount, needed / 2, address(conduit));
        s[1] = _swap(address(cbbtc), btcAmount, needed - needed / 2 - 1, address(conduit));
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BelowOracleFloor.selector, floor - 1, floor));
        _claim(stranger, tokens, s, 0);

        s[1] = _swap(address(cbbtc), btcAmount, needed - needed / 2, address(conduit));
        (uint256 out, uint256 fee) = _claim(stranger, tokens, s, 0);
        assertEq(out + fee, floor);
    }

    function test_claimFloor_revertsOnLengthMismatch() public {
        vm.expectRevert(ImmutableVeTokenConduit.LengthMismatch.selector);
        conduit.claimFloor(_tokens(address(weth)), new uint256[](2));
    }

    function test_claimFloor_revertsOnUnpricedToken() public {
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnpricedToken.selector, address(junk)));
        conduit.claimFloor(_tokens(address(junk)), new uint256[](1));
    }

    function test_owner_claimsUnpricedTokens() public {
        _earn(address(junk), 1e18);
        (uint256 out, uint256 fee) =
            _claim(holder, _tokens(address(junk)), _swaps(_swap(address(junk), 1e18, 50e6, address(conduit))), 0);
        assertEq(out, 49.5e6);
        assertEq(fee, 0.5e6);
        assertEq(usdc.balanceOf(holder), 49.5e6);
    }

    function test_owner_acceptsAnyRouteAboveMinUsdcOut() public {
        _earn(address(weth), 1e18);
        uint256 snapshot = vm.snapshotState();
        (uint256 out,) = _claim(holder, _tokens(address(weth)), _wethSwap(100e6), 99e6);
        assertEq(out, 99e6);
        vm.revertToState(snapshot);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.InsufficientOutput.selector, 99e6, 99e6 + 1));
        _claim(holder, _tokens(address(weth)), _wethSwap(100e6), 99e6 + 1);
    }

    function test_thirdParty_minUsdcOutApplies() public {
        _earn(address(weth), 1e18);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.InsufficientOutput.selector, 2376e6, 2400e6));
        _claim(stranger, _tokens(address(weth)), _wethSwap(2400e6), 2400e6);
    }

    function test_fee_harness() public {
        FeeHarness h = _deployHarness();
        assertEq(h.fee(0, 100), 0);
        assertEq(h.fee(1e6, 0), 0);
        assertEq(h.fee(1e6, 100), 1e4);
        assertEq(h.fee(1e6, 500), 5e4);
        assertEq(h.fee(1e6, 2000), 2e5);
        assertEq(h.fee(1e6, 10_000), 1e6);
        assertEq(h.fee(99, 100), 0);
        assertEq(h.fee(199, 100), 1);
        assertEq(h.fee(1999, 500), 99);
        assertEq(h.fee(49, 2000), 9);
        assertEq(h.fee(12_345, 10_000), 12_345);
    }

    function testFuzz_fee_everyClaimPaysTreasury(uint256 amount, bool thirdParty) public {
        amount = bound(amount, 0, 1e18);
        _earn(address(usdc), amount);
        (uint256 out, uint256 fee) = _claim(thirdParty ? stranger : holder, _tokens(address(usdc)), none, 0);
        assertEq(fee, amount * conduit.FEE_BPS() / 10_000);
        assertEq(out, amount - fee);
        assertEq(usdc.balanceOf(treasury), fee);
        assertEq(usdc.balanceOf(holder), out);
    }

    function test_swap_eachApprovedRouterCanBeUsed() public {
        MockRouter second = new MockRouter();
        address[] memory routers = new address[](2);
        routers[0] = address(router);
        routers[1] = address(second);
        conduit = new ImmutableVeTokenConduit(
            address(voter), address(ve), address(usdc), address(sequencer), routers, _priced()
        );
        assertEq(conduit.approvedRouters(1), address(second));
        assertTrue(conduit.isApprovedRouter(address(second)));
        vm.prank(holder);
        ve.setConduitApproval(address(conduit), TOKEN_ID, true);
        _earn(address(weth), 1e18);
        _earn(address(cbbtc), 1e8);
        ImmutableVeTokenConduit.Swap[] memory s = new ImmutableVeTokenConduit.Swap[](2);
        s[0] = _swap(address(weth), 1e18, 2400e6, address(conduit));
        s[1] = ImmutableVeTokenConduit.Swap(
            address(cbbtc),
            address(second),
            abi.encodeCall(MockRouter.swap, (address(cbbtc), 1e8, address(usdc), 80_000e6, address(conduit)))
        );
        (uint256 out, uint256 fee) = _claim(stranger, _tokens(address(weth), address(cbbtc)), s, 0);
        assertEq(out + fee, 82_400e6);
        assertEq(router.calls(), 1);
        assertEq(second.calls(), 1);
    }

    function test_swap_unswappedRewardReverts() public {
        _earn(address(weth), 1e18);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.RewardNotSwapped.selector, address(weth)));
        _claim(holder, _tokens(address(weth)), none, 0);
    }

    function test_swap_partialPullReverts() public {
        _earn(address(weth), 1e18);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.RewardNotSwapped.selector, address(weth)));
        _claim(holder, _tokens(address(weth)), _swaps(_swap(address(weth), 1e18 - 1, 2400e6, address(conduit))), 0);
    }

    function test_swap_pullingMoreThanApprovedReverts() public {
        _earn(address(weth), 1e18);
        weth.mint(address(conduit), 1e18);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        _claim(holder, _tokens(address(weth)), _swaps(_swap(address(weth), 1e18 + 1, 2400e6, address(conduit))), 0);
    }

    function test_swap_unapprovedRouterReverts() public {
        _earn(address(weth), 1e18);
        MockRouter other = new MockRouter();
        ImmutableVeTokenConduit.Swap memory s = _swap(address(weth), 1e18, 2400e6, address(conduit));
        s.router = address(other);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnapprovedRouter.selector, address(other)));
        _claim(holder, _tokens(address(weth)), _swaps(s), 0);
        s.router = address(voter);
        s.data = abi.encodeCall(MockVoter.vote, (new address[](0), new uint256[](0)));
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnapprovedRouter.selector, address(voter)));
        _claim(holder, _tokens(address(weth)), _swaps(s), 0);
    }

    function test_swap_usdcSwapReverts() public {
        _earn(address(usdc), 1e6);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BadSwap.selector, address(usdc)));
        _claim(holder, _tokens(address(usdc)), _swaps(_swap(address(usdc), 1e6, 1e6, address(conduit))), 0);
    }

    function test_swap_unclaimedTokenReverts() public {
        _earn(address(weth), 1e18);
        weth.mint(address(conduit), 1e18);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BadSwap.selector, address(weth)));
        _claim(holder, _tokens(address(usdc)), _wethSwap(2400e6), 0);
    }

    function test_swap_duplicateSwapReverts() public {
        _earn(address(weth), 1e18);
        ImmutableVeTokenConduit.Swap[] memory s = new ImmutableVeTokenConduit.Swap[](2);
        s[0] = _swap(address(weth), 0.5e18, 1200e6, address(conduit));
        s[1] = s[0];
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BadSwap.selector, address(weth)));
        _claim(holder, _tokens(address(weth)), s, 0);
    }

    function test_swap_zeroAmountSkipsTheRouter() public {
        _earn(address(usdc), 10e6);
        vm.expectCall(address(weth), abi.encodeWithSignature("approve(address,uint256)"), 0);
        (uint256 out,) = _claim(stranger, _tokens(address(weth), address(usdc)), _wethSwap(2400e6), 0);
        assertEq(out, 9.9e6);
        assertEq(router.calls(), 0);
    }

    function test_swap_approvesExactlyTheClaimedAmountThenZero() public {
        _earn(address(weth), 1e18);
        weth.mint(address(conduit), 5e18);
        vm.expectCall(address(weth), abi.encodeWithSignature("approve(address,uint256)", address(router), 0), 2);
        vm.expectCall(address(weth), abi.encodeWithSignature("approve(address,uint256)", address(router), 1e18), 1);
        _claim(stranger, _tokens(address(weth)), _wethSwap(2400e6), 0);
        assertEq(weth.allowance(address(conduit), address(router)), 0);
        assertEq(weth.balanceOf(address(conduit)), 5e18);
    }

    function test_swap_usdcIsNeverApproved() public {
        _earn(address(weth), 1e18);
        _earn(address(usdc), 1e6);
        vm.expectCall(address(usdc), abi.encodeWithSignature("approve(address,uint256)"), 0);
        _claim(stranger, _tokens(address(weth), address(usdc)), _wethSwap(2400e6), 0);
    }

    function test_swap_routerRevertBubbles() public {
        _earn(address(weth), 1e18);
        ImmutableVeTokenConduit.Swap memory s = ImmutableVeTokenConduit.Swap(
            address(weth), address(router), abi.encodeCall(MockRouter.fail, (hex"c0ffee"))
        );
        vm.expectRevert(bytes(hex"c0ffee"));
        _claim(holder, _tokens(address(weth)), _swaps(s), 0);
        s.data = abi.encodeCall(MockRouter.fail, (""));
        vm.expectRevert(bytes(""));
        _claim(holder, _tokens(address(weth)), _swaps(s), 0);
    }

    function test_swap_reentryIsBlocked() public {
        ReentrantRouter reentrant = new ReentrantRouter();
        address[] memory routers = new address[](1);
        routers[0] = address(reentrant);
        conduit = new ImmutableVeTokenConduit(
            address(voter), address(ve), address(usdc), address(sequencer), routers, _priced()
        );
        ve.setPastVotes(address(conduit), EPOCH, POWER);
        vm.prank(holder);
        ve.setConduitApproval(address(conduit), TOKEN_ID, true);
        _earn(address(weth), 1e18);
        (address[] memory pools, uint256[] memory weights) = _one(_pool(100, 0));

        bytes[2] memory inner = [
            abi.encodeCall(
                ImmutableVeTokenConduit.claim, (TOKEN_ID, new address[](0), new address[](0), new address[](0), none, 0)
            ),
            abi.encodeCall(ImmutableVeTokenConduit.vote, (pools, weights))
        ];
        for (uint256 i; i < inner.length; ++i) {
            ImmutableVeTokenConduit.Swap memory s = ImmutableVeTokenConduit.Swap(
                address(weth),
                address(reentrant),
                abi.encodeCall(ReentrantRouter.swap, (address(weth), 1e18, address(conduit), inner[i]))
            );
            vm.expectRevert(ImmutableVeTokenConduit.Reentrancy.selector);
            _claim(holder, _tokens(address(weth)), _swaps(s), 0);
        }
    }

    function test_claim_duplicateClaimTokensRevert() public {
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.Duplicate.selector, address(usdc)));
        _claim(holder, _tokens(address(usdc), address(usdc)), none, 0);
    }

    function test_claim_straysStayPut() public {
        weth.mint(address(conduit), 3e18);
        usdc.mint(address(conduit), 7e6);
        junk.mint(address(conduit), 11e18);
        _earn(address(weth), 1e18);
        _earn(address(usdc), 100e6);
        (uint256 out, uint256 fee) = _claim(stranger, _tokens(address(weth), address(usdc)), _wethSwap(2400e6), 0);
        assertEq(out + fee, 2500e6);
        assertEq(weth.balanceOf(address(conduit)), 3e18);
        assertEq(usdc.balanceOf(address(conduit)), 7e6);
        assertEq(junk.balanceOf(address(conduit)), 11e18);
    }

    function test_token_usdtStyleAndNonReturningTokensWork() public {
        MockUsdtToken usdt = new MockUsdtToken(6);
        MockNoReturnToken quiet = new MockNoReturnToken(18);
        _earn(address(usdt), 10e6);
        _earn(address(quiet), 1e18);
        ImmutableVeTokenConduit.Swap[] memory s = new ImmutableVeTokenConduit.Swap[](2);
        s[0] = _swap(address(usdt), 10e6, 10e6, address(conduit));
        s[1] = _swap(address(quiet), 1e18, 5e6, address(conduit));
        usdt.mint(address(conduit), 1);
        vm.prank(address(conduit));
        usdt.approve(address(router), 1);
        (uint256 out, uint256 fee) = _claim(holder, _tokens(address(usdt), address(quiet)), s, 0);
        assertEq(out + fee, 15e6);
        assertEq(usdt.allowance(address(conduit), address(router)), 0);
        assertEq(quiet.allowance(address(conduit), address(router)), 0);
    }

    function test_token_nonReturningUsdcWorks() public {
        MockNoReturnToken quietUsdc = new MockNoReturnToken(6);
        ImmutableVeTokenConduit.PricedToken[] memory p = _priced();
        p[2].token = address(quietUsdc);
        conduit = new ImmutableVeTokenConduit(
            address(voter), address(ve), address(quietUsdc), address(sequencer), _routers(), p
        );
        vm.prank(holder);
        ve.setConduitApproval(address(conduit), TOKEN_ID, true);
        _earn(address(quietUsdc), 100e6);
        (uint256 out, uint256 fee) = _claim(stranger, _tokens(address(quietUsdc)), none, 0);
        assertEq(out, 99e6);
        assertEq(quietUsdc.balanceOf(holder), 99e6);
        assertEq(quietUsdc.balanceOf(treasury), fee);
    }

    function test_token_falseReturnReverts() public {
        MockFalseToken liar = new MockFalseToken(18);
        _earn(address(liar), 1e18);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.TokenCallFailed.selector, address(liar)));
        _claim(holder, _tokens(address(liar)), _swaps(_swap(address(liar), 1e18, 1e6, address(conduit))), 0);
    }

    function test_token_usdcBlockingTreasuryOrOwnerReverts() public {
        _earn(address(usdc), 100e6);
        usdc.setBlocked(treasury, true);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.TokenCallFailed.selector, address(usdc)));
        _claim(stranger, _tokens(address(usdc)), none, 0);
        usdc.setBlocked(treasury, false);
        usdc.setBlocked(holder, true);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.TokenCallFailed.selector, address(usdc)));
        _claim(stranger, _tokens(address(usdc)), none, 0);
    }
}

contract ClaimHandler is Test {
    uint256 internal constant TOKEN_ID = 7;

    ImmutableVeTokenConduit internal immutable target;
    MockRouter internal immutable router;
    MockBribe internal immutable bribe;
    address internal immutable owner;
    address internal immutable weth;
    address internal immutable cbbtc;
    address internal immutable usdc;
    MockFeed internal immutable ethFeed;
    MockFeed internal immutable btcFeed;
    MockFeed internal immutable usdcFeed;
    address[] internal callers;
    bool public belowFloor;
    uint256 public thirdPartyClaims;

    constructor(ImmutableVeTokenConduit target_, MockRouter router_, MockBribe bribe_, address owner_) {
        target = target_;
        router = router_;
        bribe = bribe_;
        owner = owner_;
        address feed;
        (weth, feed,,,) = target.pricedTokens(0);
        ethFeed = MockFeed(feed);
        (cbbtc, feed,,,) = target.pricedTokens(1);
        btcFeed = MockFeed(feed);
        (usdc, feed,,,) = target.pricedTokens(2);
        usdcFeed = MockFeed(feed);
        callers.push(owner_);
        callers.push(address(0xC0FFEE));
        callers.push(address(0xBEEF));
    }

    function claim(
        uint256 callerSeed,
        uint256 wethAmount,
        uint256 btcAmount,
        uint256 usdcAmount,
        uint256 pullMode,
        uint256 payBps,
        uint256 payTo
    ) external {
        address caller = callers[callerSeed % callers.length];
        address[] memory tokens = new address[](3);
        tokens[0] = weth;
        tokens[1] = cbbtc;
        tokens[2] = usdc;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = bound(wethAmount, 0, 1e22);
        amounts[1] = bound(btcAmount, 0, 1e10);
        amounts[2] = bound(usdcAmount, 0, 1e12);
        for (uint256 i; i < 3; ++i) {
            bribe.setEarned(TOKEN_ID, tokens[i], amounts[i]);
        }
        uint256 floor = target.claimFloor(tokens, amounts);

        uint256 pull = amounts[0];
        if (pullMode % 4 == 2 && pull != 0) --pull;
        if (pullMode % 4 == 3) ++pull;
        uint256 pay = (floor > amounts[2] ? floor - amounts[2] : 0) * bound(payBps, 0, 20_000) / 10_000;
        address[4] memory sinks = [address(target), address(target), caller, owner];
        address sink = sinks[payTo % 4];
        ImmutableVeTokenConduit.Swap[] memory s = new ImmutableVeTokenConduit.Swap[](2);
        s[0] = ImmutableVeTokenConduit.Swap(
            weth, address(router), abi.encodeCall(MockRouter.swap, (weth, pull, usdc, pay / 2, sink))
        );
        s[1] = ImmutableVeTokenConduit.Swap(
            cbbtc,
            address(router),
            abi.encodeCall(MockRouter.swap, (cbbtc, amounts[1], usdc, pay - pay / 2, address(target)))
        );

        address[] memory bribes = new address[](1);
        bribes[0] = address(bribe);
        uint256 ownerBefore = MockTokenBase(usdc).balanceOf(owner);
        vm.prank(caller);
        try target.claim(TOKEN_ID, new address[](0), bribes, tokens, s, 0) returns (uint256 out, uint256 fee) {
            uint256 direct = sink == owner && amounts[0] != 0 ? pay / 2 : 0;
            uint256 paid = MockTokenBase(usdc).balanceOf(owner) - ownerBefore;
            if (paid != out + direct) belowFloor = true;
            if (caller != owner) {
                ++thirdPartyClaims;
                if (out + fee + 1 < _expectedFloor(amounts)) belowFloor = true;
            }
        } catch {}
        for (uint256 i; i < 3; ++i) {
            bribe.setEarned(TOKEN_ID, tokens[i], 0);
        }
    }

    /// @dev The claimed USDC plus 99% of the WETH and cbBTC, at the mock feeds' prices.
    function _expectedFloor(uint256[] memory amounts) internal view returns (uint256) {
        uint256 swappedUsd = amounts[0] * uint256(ethFeed.answer()) / 1e8 + amounts[1] * uint256(btcFeed.answer()) * 100;
        return amounts[2] + swappedUsd * 99 / 100 / (uint256(usdcFeed.answer()) * 1e4);
    }
}

contract ClaimInvariantTest is ConduitTestBase {
    ClaimHandler internal handler;

    function setUp() public override {
        super.setUp();
        _earn(address(usdc), 0);
        weth.mint(address(conduit), 3e18);
        cbbtc.mint(address(conduit), 5e8);
        usdc.mint(address(conduit), 7e6);
        handler = new ClaimHandler(conduit, router, rewardBribe, holder);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ClaimHandler.claim.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function invariant_conduitKeepsOnlyStrays() public view {
        assertEq(weth.balanceOf(address(conduit)), 3e18);
        assertEq(cbbtc.balanceOf(address(conduit)), 5e8);
        assertEq(usdc.balanceOf(address(conduit)), 7e6);
        assertEq(weth.allowance(address(conduit), address(router)), 0);
        assertEq(cbbtc.allowance(address(conduit), address(router)), 0);
    }

    function invariant_ownerNeverBelowFloorOnThirdPartyClaims() public view {
        assertFalse(handler.belowFloor());
    }

    function afterInvariant() external view {
        assertGt(handler.thirdPartyClaims(), 0, "no third-party claim succeeded");
    }
}
