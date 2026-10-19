// SPDX-FileCopyrightText: 2026 Léo de Souza
// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {MockBribe} from "./mocks/MockBribe.sol";
import {
    MockFalseToken,
    MockNoReturnToken,
    MockReentrantToken,
    MockTaxToken,
    MockToken,
    MockTokenBase
} from "./mocks/MockToken.sol";
import {MockVoter} from "./mocks/MockVoter.sol";
import {ConduitTestBase, FeeHarness} from "./utils/ConduitTestBase.sol";

contract ClaimTest is ConduitTestBase {
    event Claimed(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed caller,
        address[] tokens,
        uint256[] amounts,
        uint256[] fees
    );

    function _three(address a, address b, address c) internal pure returns (address[] memory t) {
        t = new address[](3);
        t[0] = a;
        t[1] = b;
        t[2] = c;
    }

    function _uints(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory u) {
        u = new uint256[](3);
        u[0] = a;
        u[1] = b;
        u[2] = c;
    }

    function test_claim_strangerClaimsForOwner() public {
        _earn(address(weth), 1e18);
        _earn(address(usdc), 100e6);
        _earn(address(junk), 5e18);
        address[] memory tokens = _three(address(weth), address(usdc), address(junk));
        vm.expectEmit(address(conduit));
        emit Claimed(TOKEN_ID, holder, stranger, tokens, _uints(1e18, 100e6, 5e18), _uints(0.01e18, 1e6, 0.05e18));
        uint256[] memory amounts = _claim(stranger, tokens);
        assertEq(amounts, _uints(1e18, 100e6, 5e18));

        assertEq(weth.balanceOf(holder), 0.99e18);
        assertEq(usdc.balanceOf(holder), 99e6);
        assertEq(junk.balanceOf(holder), 4.95e18);
        assertEq(weth.balanceOf(treasury), 0.01e18);
        assertEq(usdc.balanceOf(treasury), 1e6);
        assertEq(junk.balanceOf(treasury), 0.05e18);
        for (uint256 i; i < tokens.length; ++i) {
            assertEq(MockTokenBase(tokens[i]).balanceOf(stranger), 0);
            assertEq(MockTokenBase(tokens[i]).balanceOf(address(conduit)), 0);
        }
    }

    function testFuzz_claim_alwaysPaysTheOwner(address caller) public {
        _earn(address(weth), 1e18);
        vm.assume(caller != address(conduit) && caller != treasury && caller != address(rewardBribe));
        _claim(caller, _tokens(address(weth)));
        assertEq(weth.balanceOf(holder), 0.99e18);
        assertEq(weth.balanceOf(treasury), 0.01e18);
        if (caller != holder) assertEq(weth.balanceOf(caller), 0);
    }

    function test_claim_ownerPaysTheFeeToo() public {
        _earn(address(usdc), 100e6);
        _claim(holder, _tokens(address(usdc)));
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
        uint256[] memory amounts = conduit.claim(TOKEN_ID, feeAddresses, _bribes(), _tokens(address(usdc)));
        assertEq(amounts[0], 100e6);
        assertEq(usdc.balanceOf(holder), 99e6);
    }

    function test_claim_withoutRewardContractsReverts() public {
        ve.mint(8, makeAddr("other holder"));
        vm.expectRevert(ImmutableVeTokenConduit.NoRewardContracts.selector);
        conduit.claim(8, new address[](0), new address[](0), _tokens(address(usdc)));
        vm.expectRevert(ImmutableVeTokenConduit.NoRewardContracts.selector);
        conduit.claim(TOKEN_ID, new address[](0), new address[](0), new address[](0));
    }

    function test_claim_nothingToClaim() public {
        _earn(address(usdc), 0);
        vm.recordLogs();
        uint256[] memory amounts = _claim(stranger, new address[](0));
        assertEq(amounts.length, 0);
        assertEq(vm.getRecordedLogs().length, 1);
        vm.expectCall(address(weth), abi.encodeWithSelector(MockToken.transfer.selector), 0);
        amounts = _claim(stranger, _tokens(address(weth)));
        assertEq(amounts[0], 0);
    }

    function test_claim_notOptedInRevertsInVoter() public {
        ve.mint(8, makeAddr("other holder"));
        _earn(address(usdc), 1e6);
        vm.expectRevert(MockVoter.NotApprovedOrOwner.selector);
        conduit.claim(8, new address[](0), _bribes(), _tokens(address(usdc)));

        vm.prank(holder);
        ve.setConduitApproval(address(conduit), TOKEN_ID, false);
        vm.expectRevert(MockVoter.NotApprovedOrOwner.selector);
        _claim(stranger, _tokens(address(usdc)));
    }

    function test_claim_ownerOfRevertsForMissingToken() public {
        _earn(address(usdc), 0);
        vm.expectRevert(bytes("ERC721NonexistentToken"));
        conduit.claim(404, new address[](0), _bribes(), new address[](0));
    }

    function test_claim_duplicateTokensRevert() public {
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.Duplicate.selector, address(usdc)));
        _claim(holder, _three(address(weth), address(usdc), address(usdc)));
    }

    function test_claim_straysStayPut() public {
        weth.mint(address(conduit), 3e18);
        usdc.mint(address(conduit), 7e6);
        junk.mint(address(conduit), 11e18);
        _earn(address(weth), 1e18);
        _earn(address(usdc), 100e6);
        uint256[] memory amounts = _claim(stranger, _three(address(weth), address(usdc), address(junk)));
        assertEq(amounts, _uints(1e18, 100e6, 0));
        assertEq(weth.balanceOf(address(conduit)), 3e18);
        assertEq(usdc.balanceOf(address(conduit)), 7e6);
        assertEq(junk.balanceOf(address(conduit)), 11e18);
        assertEq(junk.balanceOf(holder), 0);
    }

    function test_claim_smallAmountsPayNoFee() public {
        _earn(address(usdc), 99);
        _claim(stranger, _tokens(address(usdc)));
        assertEq(usdc.balanceOf(holder), 99);
        assertEq(usdc.balanceOf(treasury), 0);
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

    function testFuzz_fee_everyClaimPaysTreasury(uint256 a, uint256 b, bool thirdParty) public {
        a = bound(a, 0, 1e30);
        b = bound(b, 0, 1e30);
        _earn(address(weth), a);
        _earn(address(junk), b);
        _claim(thirdParty ? stranger : holder, _tokens(address(weth), address(junk)));
        assertEq(weth.balanceOf(treasury), a * conduit.FEE_BPS() / 10_000);
        assertEq(junk.balanceOf(treasury), b * conduit.FEE_BPS() / 10_000);
        assertEq(weth.balanceOf(holder), a - a * conduit.FEE_BPS() / 10_000);
        assertEq(junk.balanceOf(holder), b - b * conduit.FEE_BPS() / 10_000);
    }

    function test_token_nonReturningTokenWorks() public {
        MockNoReturnToken quiet = new MockNoReturnToken(6);
        _earn(address(quiet), 10e6);
        _claim(stranger, _tokens(address(quiet)));
        assertEq(quiet.balanceOf(holder), 9.9e6);
        assertEq(quiet.balanceOf(treasury), 0.1e6);
    }

    function test_token_falseReturnReverts() public {
        MockFalseToken liar = new MockFalseToken(18);
        liar.setLiar(address(conduit));
        _earn(address(liar), 1e18);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.TokenCallFailed.selector, address(liar)));
        _claim(stranger, _tokens(address(liar)));
    }

    function test_token_blockedTreasuryOrOwnerReverts() public {
        _earn(address(usdc), 100e6);
        usdc.setBlocked(treasury, true);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.TokenCallFailed.selector, address(usdc)));
        _claim(stranger, _tokens(address(usdc)));
        usdc.setBlocked(treasury, false);
        usdc.setBlocked(holder, true);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.TokenCallFailed.selector, address(usdc)));
        _claim(stranger, _tokens(address(usdc)));
    }

    function test_token_taxTokenIsTaxedOnTheWayInAndOut() public {
        MockTaxToken taxed = new MockTaxToken(18);
        _earn(address(taxed), 100e18);
        uint256[] memory amounts = _claim(stranger, _tokens(address(taxed)));
        assertEq(amounts[0], 99e18);
        assertEq(taxed.balanceOf(treasury), 0.99e18 - 0.0099e18);
        assertEq(taxed.balanceOf(holder), 98.01e18 - 0.9801e18);
        assertEq(taxed.balanceOf(address(conduit)), 0);
    }

    function _reentries() internal returns (bytes[2] memory inner) {
        (address[] memory pools, uint256[] memory weights) = _one(_pool(100, 0));
        inner = [
            abi.encodeCall(
                ImmutableVeTokenConduit.claim, (TOKEN_ID, new address[](0), new address[](0), new address[](0))
            ),
            abi.encodeCall(ImmutableVeTokenConduit.vote, (pools, weights))
        ];
    }

    /// @dev A token's transfer is a low-level call, so the lock's revert surfaces as `TokenCallFailed`.
    function test_token_reentryIsBlocked() public {
        MockReentrantToken evil = new MockReentrantToken(18);
        _earn(address(evil), 1e18);
        bytes[2] memory inner = _reentries();
        for (uint256 i; i < inner.length; ++i) {
            evil.arm(address(conduit), address(conduit), inner[i]);
            vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.TokenCallFailed.selector, address(evil)));
            _claim(stranger, _tokens(address(evil)));
        }
        evil.arm(address(conduit), address(conduit), abi.encodeCall(ImmutableVeTokenConduit.currentScore, ()));
        _claim(stranger, _tokens(address(evil)));
        assertEq(evil.balanceOf(holder), 0.99e18);
    }

    function test_bribe_reentryIsBlocked() public {
        ReentrantBribe evil = new ReentrantBribe();
        address[] memory bribes = new address[](1);
        bribes[0] = address(evil);
        bytes[2] memory inner = _reentries();
        for (uint256 i; i < inner.length; ++i) {
            evil.arm(address(conduit), inner[i]);
            vm.expectRevert(ImmutableVeTokenConduit.Reentrancy.selector);
            vm.prank(stranger);
            conduit.claim(TOKEN_ID, new address[](0), bribes, _tokens(address(usdc)));
        }
    }

    function test_token_withoutCodeReverts() public {
        _earn(address(usdc), 0);
        address nothing = makeAddr("not a token");
        vm.expectRevert();
        _claim(stranger, _tokens(nothing));
    }
}

/// @notice A fee or bribe address a caller passes in, which calls `target` with `data` when the Voter pays out.
contract ReentrantBribe {
    address internal target;
    bytes internal data;

    function arm(address target_, bytes calldata data_) external {
        target = target_;
        data = data_;
    }

    function getRewardToRecipient(uint256, address[] calldata, address) external {
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}

contract ClaimHandler is Test {
    uint256 internal constant TOKEN_ID = 7;

    ImmutableVeTokenConduit internal immutable target;
    MockBribe internal immutable bribe;
    address internal immutable owner;
    address internal immutable treasury;
    address[] internal tokens;
    address[] internal callers;
    bool public wrongPayout;
    uint256 public claims;

    constructor(ImmutableVeTokenConduit target_, MockBribe bribe_, address owner_, address[] memory tokens_) {
        target = target_;
        bribe = bribe_;
        owner = owner_;
        treasury = target_.TREASURY();
        tokens = tokens_;
        callers.push(owner_);
        callers.push(address(0xC0FFEE));
        callers.push(address(0xBEEF));
    }

    function claim(uint256 callerSeed, uint256 seed, uint256 mask) external {
        address caller = callers[callerSeed % callers.length];
        uint256 k;
        for (uint256 i; i < tokens.length; ++i) {
            if ((mask >> i) & 1 == 1) ++k;
        }
        address[] memory picked = new address[](k);
        uint256[] memory amounts = new uint256[](k);
        uint256[] memory ownerBefore = new uint256[](k);
        uint256[] memory treasuryBefore = new uint256[](k);
        k = 0;
        for (uint256 i; i < tokens.length; ++i) {
            if ((mask >> i) & 1 == 0) continue;
            picked[k] = tokens[i];
            amounts[k] = uint256(keccak256(abi.encode(seed, i))) % 1e30;
            bribe.setEarned(TOKEN_ID, picked[k], amounts[k]);
            ownerBefore[k] = MockTokenBase(picked[k]).balanceOf(owner);
            treasuryBefore[k] = MockTokenBase(picked[k]).balanceOf(treasury);
            ++k;
        }
        address[] memory bribes = new address[](1);
        bribes[0] = address(bribe);

        vm.prank(caller);
        uint256[] memory claimed = target.claim(TOKEN_ID, new address[](0), bribes, picked);
        ++claims;
        for (uint256 i; i < k; ++i) {
            uint256 fee = amounts[i] / 100;
            if (claimed[i] != amounts[i]) wrongPayout = true;
            if (MockTokenBase(picked[i]).balanceOf(treasury) - treasuryBefore[i] != fee) wrongPayout = true;
            if (MockTokenBase(picked[i]).balanceOf(owner) - ownerBefore[i] != amounts[i] - fee) wrongPayout = true;
        }
    }
}

contract ClaimInvariantTest is ConduitTestBase {
    ClaimHandler internal handler;
    address[] internal tokens;

    function setUp() public override {
        super.setUp();
        _earn(address(usdc), 0);
        tokens.push(address(weth));
        tokens.push(address(usdc));
        tokens.push(address(junk));
        tokens.push(address(new MockNoReturnToken(6)));
        for (uint256 i; i < tokens.length; ++i) {
            MockTokenBase(tokens[i]).mint(address(conduit), 1000 + i);
        }
        handler = new ClaimHandler(conduit, rewardBribe, holder, tokens);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ClaimHandler.claim.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    function invariant_conduitKeepsOnlyStrays() public view {
        for (uint256 i; i < tokens.length; ++i) {
            assertEq(MockTokenBase(tokens[i]).balanceOf(address(conduit)), 1000 + i);
        }
    }

    function invariant_ownerAndTreasuryGetExactShares() public view {
        assertFalse(handler.wrongPayout());
    }

    function afterInvariant() external view {
        assertGt(handler.claims(), 0, "no claim succeeded");
    }
}
