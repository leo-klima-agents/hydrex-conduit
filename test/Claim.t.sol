// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test, Vm} from "forge-std/Test.sol";

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
import {ConduitTestBase} from "./utils/ConduitTestBase.sol";

contract ClaimTest is ConduitTestBase {
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
        address[] memory tokens = _tokens(address(weth), address(usdc), address(junk));
        vm.expectEmit(address(conduit));
        emit ImmutableVeTokenConduit.Claimed(
            TOKEN_ID, holder, stranger, tokens, _uints(1e18, 100e6, 5e18), _uints(0.01e18, 1e6, 0.05e18), 0
        );
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

    function test_claim_feeContractsAndBribes() public {
        MockBribe fees = new MockBribe(address(voter), bribeOwner);
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
        vm.recordLogs();
        uint256[] memory amounts = _claim(stranger, new address[](0));
        assertEq(amounts.length, 0);
        assertEq(vm.getRecordedLogs().length, 1);
        vm.expectCall(address(weth), abi.encodeWithSelector(MockToken.transfer.selector), 0);
        amounts = _claim(stranger, _tokens(address(weth)));
        assertEq(amounts[0], 0);
        assertEq(conduit.lastClaimBlock(TOKEN_ID), 0);
    }

    function _previousClaimBlock(uint256 tokenId, address[] memory tokens) internal returns (uint256 previous) {
        vm.recordLogs();
        vm.prank(stranger);
        conduit.claim(tokenId, new address[](0), _bribes(), tokens);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (,,, previous) = abi.decode(logs[logs.length - 1].data, (address[], uint256[], uint256[], uint256));
    }

    function test_claim_eventLinksToThePreviousClaimBlock() public {
        vm.roll(100);
        _earn(address(usdc), 100e6);
        assertEq(_previousClaimBlock(TOKEN_ID, _tokens(address(usdc))), 0);
        assertEq(conduit.lastClaimBlock(TOKEN_ID), 100);
        vm.roll(105);
        _earn(address(usdc), 100e6);
        assertEq(_previousClaimBlock(TOKEN_ID, _tokens(address(usdc))), 100);
        assertEq(conduit.lastClaimBlock(TOKEN_ID), 105);
    }

    function test_claim_emptyClaimsKeepThePointer() public {
        vm.roll(100);
        _earn(address(usdc), 100e6);
        _claim(stranger, _tokens(address(usdc)));
        vm.roll(105);
        assertEq(_previousClaimBlock(TOKEN_ID, _tokens(address(usdc))), 100);
        assertEq(conduit.lastClaimBlock(TOKEN_ID), 100);
        _earn(address(usdc), 100e6);
        assertEq(_previousClaimBlock(TOKEN_ID, _tokens(address(usdc))), 100);
        assertEq(_previousClaimBlock(TOKEN_ID, _tokens(address(usdc))), 105);
        assertEq(conduit.lastClaimBlock(TOKEN_ID), 105);
    }

    function test_claim_sameBlockClaimsPointToThatBlock() public {
        _earn(address(usdc), 100e6);
        assertEq(_previousClaimBlock(TOKEN_ID, _tokens(address(usdc))), 0);
        _earn(address(weth), 1e18);
        assertEq(_previousClaimBlock(TOKEN_ID, _tokens(address(weth))), block.number);
        assertEq(conduit.lastClaimBlock(TOKEN_ID), block.number);
    }

    function test_claim_pointersArePerVeNft() public {
        address other = makeAddr("other holder");
        ve.mint(8, other);
        vm.prank(other);
        ve.setConduitApproval(address(conduit), 8, true);
        rewardBribe.setEarned(8, address(usdc), 100e6);
        assertEq(_previousClaimBlock(8, _tokens(address(usdc))), 0);
        assertEq(conduit.lastClaimBlock(8), block.number);
        assertEq(conduit.lastClaimBlock(TOKEN_ID), 0);
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
        vm.expectRevert(bytes("ERC721NonexistentToken"));
        conduit.claim(404, new address[](0), _bribes(), new address[](0));
    }

    function test_claim_repeatedTokenPaysOnce() public {
        usdc.mint(address(conduit), 7e6);
        _earn(address(usdc), 100e6);
        uint256[] memory amounts = _claim(stranger, _tokens(address(usdc), address(weth), address(usdc)));
        assertEq(amounts, _uints(100e6, 0, 0));
        assertEq(usdc.balanceOf(holder), 99e6);
        assertEq(usdc.balanceOf(treasury), 1e6);
        assertEq(usdc.balanceOf(address(conduit)), 7e6);
    }

    function test_claim_straysStayPut() public {
        weth.mint(address(conduit), 3e18);
        usdc.mint(address(conduit), 7e6);
        junk.mint(address(conduit), 11e18);
        _earn(address(weth), 1e18);
        _earn(address(usdc), 100e6);
        uint256[] memory amounts = _claim(stranger, _tokens(address(weth), address(usdc), address(junk)));
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
            abi.encodeCall(ImmutableVeTokenConduit.claim, (TOKEN_ID, new address[](0), _bribes(), new address[](0))),
            abi.encodeCall(ImmutableVeTokenConduit.vote, (pools, weights))
        ];
    }

    function test_token_reentryIsBlocked() public {
        MockReentrantToken evil = new MockReentrantToken(18);
        _earn(address(evil), 1e18);
        bytes[2] memory inner = _reentries();
        for (uint256 i; i < inner.length; ++i) {
            evil.arm(address(conduit), inner[i]);
            vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.TokenCallFailed.selector, address(evil)));
            _claim(stranger, _tokens(address(evil)));
        }
        evil.arm(address(conduit), abi.encodeCall(ImmutableVeTokenConduit.currentScore, ()));
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

    function test_token_withoutCodeRevertsBeforeClaiming() public {
        vm.expectCall(address(voter), abi.encodeWithSelector(MockVoter.claimBribesToRecipientByTokenId.selector), 0);
        vm.expectRevert(bytes(""));
        _claim(stranger, _tokens(makeAddr("not a token")));
    }
}

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

    function claim(uint256 callerSeed, uint256 seed) external {
        uint256 n = tokens.length;
        uint256[] memory amounts = new uint256[](n);
        uint256[] memory ownerBefore = new uint256[](n);
        uint256[] memory treasuryBefore = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            amounts[i] = uint256(keccak256(abi.encode(seed, i))) % 1e30;
            bribe.setEarned(TOKEN_ID, tokens[i], amounts[i]);
            ownerBefore[i] = MockTokenBase(tokens[i]).balanceOf(owner);
            treasuryBefore[i] = MockTokenBase(tokens[i]).balanceOf(treasury);
        }
        address[] memory bribes = new address[](1);
        bribes[0] = address(bribe);

        vm.prank(callers[callerSeed % callers.length]);
        assertEq(target.claim(TOKEN_ID, new address[](0), bribes, tokens), amounts);
        ++claims;
        for (uint256 i; i < n; ++i) {
            uint256 fee = amounts[i] / 100;
            assertEq(MockTokenBase(tokens[i]).balanceOf(treasury) - treasuryBefore[i], fee);
            assertEq(MockTokenBase(tokens[i]).balanceOf(owner) - ownerBefore[i], amounts[i] - fee);
        }
    }
}

contract ClaimInvariantTest is ConduitTestBase {
    ClaimHandler internal handler;
    address[] internal tokens;

    function setUp() public override {
        super.setUp();
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

    function afterInvariant() external view {
        assertGt(handler.claims(), 0, "no claim succeeded");
    }
}
