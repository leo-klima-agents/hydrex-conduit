// SPDX-FileCopyrightText: 2026 Léo de Souza
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
        string memory md = vm.readFile("test/upstream/UPSTREAM.md");
        assertEq(conduit.TREASURY(), 0x450c72de8c0079B49AcedF294a13011bd09D125B);
        assertTrue(vm.contains(md, string.concat("| `TREASURY` | `", vm.toString(conduit.TREASURY()), "` |")));
        assertEq(conduit.FEE_BPS(), 100);
        assertTrue(vm.contains(md, "| `FEE_BPS` | `100` |"));
        assertEq(conduit.MAX_POOLS(), 20);
        assertEq(conduit.MIN_GAIN(), 1e18);
        assertEq(conduit.MAX_SLIPPAGE_BPS(), 100);
        assertEq(conduit.SEQUENCER_GRACE(), 3600);
        assertEq(conduit.WEEK(), 604800);
    }

    function test_constructor_storesConfiguration() public view {
        assertEq(conduit.voter(), address(voter));
        assertEq(conduit.veToken(), address(ve));
        assertEq(conduit.usdc(), address(usdc));
        assertEq(conduit.sequencerFeed(), address(sequencer));
        assertEq(conduit.approvedRouters(0), address(router));
        assertTrue(conduit.isApprovedRouter(address(router)));
        assertFalse(conduit.isApprovedRouter(address(voter)));
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

    function test_storage_neverWrittenAfterDeployment() public {
        address pool = _pool(100, POWER);
        _earn(address(weth), 1e18);
        _earn(address(usdc), 10e6);
        (address[] memory pools, uint256[] memory weights) = _one(pool);

        vm.startStateDiffRecording();
        conduit.score(pools, weights);
        conduit.currentScore();
        conduit.poolValue(pool);
        conduit.claimFloor(_tokens(address(weth)), new uint256[](1));
        conduit.pricedTokens(0);
        conduit.approvedRouters(0);
        conduit.isApprovedRouter(address(router));
        vm.prank(stranger);
        conduit.vote(pools, weights);
        _claim(
            stranger,
            _tokens(address(weth), address(usdc)),
            _swaps(_swap(address(weth), 1e18, 2400e6, address(conduit))),
            0
        );
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        uint256 reads;
        for (uint256 i; i < accesses.length; ++i) {
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory s = accesses[i].storageAccesses[j];
                if (s.account != address(conduit)) continue;
                assertFalse(s.isWrite && s.newValue != s.previousValue, "conduit storage changed");
                assertFalse(s.isWrite, "conduit storage written");
                ++reads;
            }
        }
        assertGt(reads, 0);
    }

    function test_constructor_revertsOnZeroAddresses() public {
        address[4] memory core = [address(voter), address(ve), address(usdc), address(sequencer)];
        for (uint256 i; i < 4; ++i) {
            address[4] memory a = core;
            a[i] = address(0);
            vm.expectRevert(ImmutableVeTokenConduit.ZeroAddress.selector);
            new ImmutableVeTokenConduit(a[0], a[1], a[2], a[3], _routers(), _priced());
        }
        address[] memory r = _routers();
        r[0] = address(0);
        vm.expectRevert(ImmutableVeTokenConduit.ZeroAddress.selector);
        _deployWith(r, _priced());
        ImmutableVeTokenConduit.PricedToken[] memory p = _priced();
        p[1].token = address(0);
        vm.expectRevert(ImmutableVeTokenConduit.ZeroAddress.selector);
        _deployWith(_routers(), p);
        p = _priced();
        p[1].feed = address(0);
        vm.expectRevert(ImmutableVeTokenConduit.ZeroAddress.selector);
        _deployWith(_routers(), p);
    }

    function test_constructor_revertsOnBadRouters() public {
        vm.expectRevert(ImmutableVeTokenConduit.BadConfig.selector);
        _deployWith(new address[](0), _priced());

        address[] memory r = new address[](1);
        r[0] = makeAddr("no code");
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.NotAContract.selector, r[0]));
        _deployWith(r, _priced());

        r = new address[](2);
        r[0] = address(router);
        r[1] = address(router);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BadRouter.selector, address(router)));
        _deployWith(r, _priced());

        address[12] memory forbidden = [
            address(voter),
            address(ve),
            address(usdc),
            address(sequencer),
            address(weth),
            address(cbbtc),
            address(eurc),
            address(ethFeed),
            address(btcFeed),
            address(usdcFeed),
            address(eurcFeed),
            address(usdc)
        ];
        r = new address[](1);
        for (uint256 i; i < forbidden.length; ++i) {
            r[0] = forbidden[i];
            vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.BadRouter.selector, forbidden[i]));
            _deployWith(r, _priced());
        }
    }

    function test_constructor_revertsOnBadPricedTokens() public {
        vm.expectRevert(ImmutableVeTokenConduit.BadConfig.selector);
        _deployWith(_routers(), new ImmutableVeTokenConduit.PricedToken[](0));

        ImmutableVeTokenConduit.PricedToken[] memory nine = new ImmutableVeTokenConduit.PricedToken[](9);
        for (uint256 i; i < 9; ++i) {
            nine[i] = ImmutableVeTokenConduit.PricedToken(address(new MockToken(18)), address(usdcFeed), 108_000);
        }
        nine[0].token = address(usdc);
        vm.expectRevert(ImmutableVeTokenConduit.BadConfig.selector);
        _deployWith(_routers(), nine);

        ImmutableVeTokenConduit.PricedToken[] memory p = _priced();
        p[3].token = address(weth);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.Duplicate.selector, address(weth)));
        _deployWith(_routers(), p);

        p = _priced();
        p[3].feed = makeAddr("no feed");
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.NotAContract.selector, p[3].feed));
        _deployWith(_routers(), p);

        p = _priced();
        p[2] = p[3];
        p[3] = ImmutableVeTokenConduit.PricedToken(address(junk), address(eurcFeed), 108_000);
        vm.expectRevert(ImmutableVeTokenConduit.BadConfig.selector);
        _deployWith(_routers(), p);
    }

    function test_constructor_revertsOnUnusableFeeds() public {
        ethFeed.set(ETH_USD, block.timestamp - 1501);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnpricedToken.selector, address(weth)));
        _deploy();
        ethFeed.set(0, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnpricedToken.selector, address(weth)));
        _deploy();
        ethFeed.set(ETH_USD, block.timestamp);
        MockFeed f = new MockFeed(8, 1e8);
        f.setReverts(true);
        ImmutableVeTokenConduit.PricedToken[] memory p = _priced();
        p[3].feed = address(f);
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.UnpricedToken.selector, address(eurc)));
        _deployWith(_routers(), p);
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
        bytes memory args =
            abi.encode(address(voter), address(ve), address(usdc), address(sequencer), _routers(), _priced());
        bytes32 initHash = keccak256(bytes.concat(type(ImmutableVeTokenConduit).creationCode, args));
        ve.squat(vm.computeCreate2Address(bytes32(0), initHash, address(this)));
        vm.expectRevert(bytes("Conduit already configured"));
        new ImmutableVeTokenConduit{salt: bytes32(0)}(
            address(voter), address(ve), address(usdc), address(sequencer), _routers(), _priced()
        );
    }

    function _deployWith(address[] memory routers, ImmutableVeTokenConduit.PricedToken[] memory p)
        internal
        returns (ImmutableVeTokenConduit)
    {
        return new ImmutableVeTokenConduit(address(voter), address(ve), address(usdc), address(sequencer), routers, p);
    }
}
