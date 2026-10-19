// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Vm} from "forge-std/Vm.sol";

import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {MockFeed} from "./mocks/MockFeed.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {ConduitTestBase} from "./utils/ConduitTestBase.sol";

contract SurfaceTest is ConduitTestBase {
    string internal constant ARTIFACT = "out/ImmutableVeTokenConduit.sol/ImmutableVeTokenConduit.json";

    function test_gateInventory_onlyVoteAndClaimWrite() public view {
        string memory json = vm.readFile(ARTIFACT);
        string[] memory writers = new string[](8);
        uint256 n;
        uint256 functions;
        for (uint256 i;; ++i) {
            string memory key = string.concat(".abi[", vm.toString(i), "]");
            if (!vm.keyExistsJson(json, key)) break;
            string memory kind = vm.parseJsonString(json, string.concat(key, ".type"));
            assertTrue(!vm.contains(kind, "receive") && !vm.contains(kind, "fallback"), kind);
            if (keccak256(bytes(kind)) != keccak256("function")) continue;
            ++functions;
            string memory mutability = vm.parseJsonString(json, string.concat(key, ".stateMutability"));
            if (keccak256(bytes(mutability)) == keccak256("view") || keccak256(bytes(mutability)) == keccak256("pure"))
            {
                continue;
            }
            assertEq(mutability, "nonpayable");
            writers[n++] = vm.parseJsonString(json, string.concat(key, ".name"));
        }
        assertEq(n, 2);
        assertEq(writers[0], "claim");
        assertEq(writers[1], "vote");
        assertGt(functions, 2);
    }

    function test_constants() public view {
        assertEq(conduit.TREASURY(), 0x450c72de8c0079B49AcedF294a13011bd09D125B);
        assertEq(conduit.FEE_BPS(), 100);
        assertEq(conduit.MAX_POOLS(), 20);
        assertEq(conduit.MIN_GAIN(), 1e18);
        assertEq(conduit.SEQUENCER_GRACE(), 3600);
    }

    function test_constructor_storesConfiguration() public view {
        assertEq(conduit.voter(), address(voter));
        assertEq(conduit.veToken(), address(ve));
        assertEq(conduit.sequencerFeed(), address(sequencer));
        (address token,,,,) = conduit.pricedTokens(3);
        assertEq(token, address(eurc));
    }

    function test_constructor_registersConduitConfig() public view {
        uint8[] memory actions = ve.getConduitActions(address(conduit));
        assertEq(actions.length, 2);
        assertEq(actions[0], 3, "CLAIM_REDIRECT_APPROVAL");
        assertEq(actions[1], 5, "VOTING_DELEGATE");
        assertEq(ve.configDescription(address(conduit)), "");
        assertTrue(ve.configActive(address(conduit)));
    }

    function test_noReceiveOrFallback() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(conduit).call{value: 1}("");
        assertFalse(ok);
        (ok,) = address(conduit).call(hex"deadbeef");
        assertFalse(ok);
        (ok,) = address(conduit).call{value: 1}(abi.encodeCall(ImmutableVeTokenConduit.currentScore, ()));
        assertFalse(ok);
    }

    function test_storage_onlyClaimWritesTheLastClaimBlock() public {
        address pool = _pool(100, POWER);
        _earn(address(weth), 1e18);
        _earn(address(usdc), 10e6);
        (address[] memory pools, uint256[] memory weights) = _one(pool);

        vm.startStateDiffRecording();
        conduit.score(pools, weights);
        conduit.currentScore();
        conduit.poolValue(pool);
        conduit.pricedTokens(0);
        conduit.lastClaimBlock(TOKEN_ID);
        vm.prank(stranger);
        conduit.vote(pools, weights);
        _assertWrites(vm.stopAndReturnStateDiff(), 0);

        vm.startStateDiffRecording();
        _claim(stranger, _tokens(address(weth), address(usdc)));
        _assertWrites(vm.stopAndReturnStateDiff(), 1);
    }

    function _assertWrites(Vm.AccountAccess[] memory accesses, uint256 expected) internal view {
        uint256 recorded;
        uint256 writes;
        for (uint256 i; i < accesses.length; ++i) {
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory s = accesses[i].storageAccesses[j];
                if (s.account != address(conduit)) continue;
                ++recorded;
                if (!s.isWrite) continue;
                assertEq(s.slot, keccak256(abi.encode(TOKEN_ID, uint256(1))));
                assertEq(uint256(s.newValue), block.number);
                ++writes;
            }
        }
        assertGt(recorded, 0);
        assertEq(writes, expected);
    }

    function test_constructor_revertsOnZeroAddresses() public {
        address[3] memory core = [address(voter), address(ve), address(sequencer)];
        for (uint256 i; i < 3; ++i) {
            address[3] memory a = core;
            a[i] = address(0);
            vm.expectRevert(ImmutableVeTokenConduit.ZeroAddress.selector);
            new ImmutableVeTokenConduit(a[0], a[1], a[2], _priced());
        }
    }

    function test_constructor_revertsOnBadPricedTokens() public {
        vm.expectRevert(ImmutableVeTokenConduit.BadPricedTokenCount.selector);
        _deployWith(new ImmutableVeTokenConduit.PricedToken[](0));

        ImmutableVeTokenConduit.PricedToken[] memory five = new ImmutableVeTokenConduit.PricedToken[](5);
        for (uint256 i; i < 5; ++i) {
            five[i] = ImmutableVeTokenConduit.PricedToken(address(new MockToken(18)), address(usdcFeed), 108_000);
        }
        vm.expectRevert(ImmutableVeTokenConduit.BadPricedTokenCount.selector);
        _deployWith(five);

        ImmutableVeTokenConduit.PricedToken[] memory p = _priced();
        p[3].token = address(weth);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.Duplicate.selector, address(weth)));
        _deployWith(p);

        p = _priced();
        p[3].token = address(0);
        vm.expectRevert(bytes(""));
        _deployWith(p);
    }

    function test_constructor_acceptsOnePricedToken() public {
        ImmutableVeTokenConduit.PricedToken[] memory one = new ImmutableVeTokenConduit.PricedToken[](1);
        one[0] = _priced()[2];
        (address token,,,,) = _deployWith(one).pricedTokens(0);
        assertEq(token, address(usdc));
    }

    function test_constructor_revertsOnUnusableFeeds() public {
        ethFeed.set(ETH_USD, block.timestamp - 1501);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BadFeed.selector, address(ethFeed)));
        _deploy();
        ethFeed.set(0, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BadFeed.selector, address(ethFeed)));
        _deploy();
        ethFeed.set(ETH_USD, block.timestamp);
        MockFeed f = new MockFeed(8, 1e8);
        f.setReverts(true);
        address[3] memory bad = [address(f), makeAddr("no feed"), address(0)];
        for (uint256 i; i < bad.length; ++i) {
            ImmutableVeTokenConduit.PricedToken[] memory p = _priced();
            p[3].feed = bad[i];
            vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BadFeed.selector, bad[i]));
            _deployWith(p);
        }
    }

    function test_constructor_revertsWhileSequencerDown() public {
        sequencer.set(1, 0);
        vm.expectRevert(ImmutableVeTokenConduit.SequencerDown.selector);
        _deploy();
        sequencer.set(0, 0);
        sequencer.setStartedAt(block.timestamp - 60);
        vm.expectRevert(ImmutableVeTokenConduit.SequencerDown.selector);
        _deploy();
    }

    function test_constructor_revertsIfAlreadyRegistered() public {
        bytes memory args = abi.encode(address(voter), address(ve), address(sequencer), _priced());
        bytes32 initHash = keccak256(bytes.concat(type(ImmutableVeTokenConduit).creationCode, args));
        ve.squat(vm.computeCreate2Address(bytes32(0), initHash, address(this)));
        vm.expectRevert(bytes("Conduit already configured"));
        new ImmutableVeTokenConduit{salt: bytes32(0)}(address(voter), address(ve), address(sequencer), _priced());
    }
}
