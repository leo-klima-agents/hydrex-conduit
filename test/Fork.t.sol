// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {stdJson} from "forge-std/StdJson.sol";
import {Test, Vm} from "forge-std/Test.sol";

import {Deploy} from "../script/Deploy.s.sol";
import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {IBribe} from "../src/interfaces/IBribe.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVoter} from "../src/interfaces/IVoter.sol";
import {IVotingEscrow} from "../src/interfaces/IVotingEscrow.sol";

interface IVoterExtra {
    function VOTE_DELAY() external view returns (uint256);
    function minter() external view returns (address);
    function weightsAt(address pool, uint256 time) external view returns (uint256);
    function permissionRegistry() external view returns (address);
    function claimLogic() external view returns (address);
    function killGauge(address gauge) external;
}

interface IPermissionsRegistry {
    function emergencyCouncil() external view returns (address);
}

interface IVotingEscrowExtra {
    function approvalLogic() external view returns (address);
    function setConduitApproval(address conduit, uint256 tokenId, bool approve) external;
    function getConduitApprovalConfig(address conduit)
        external
        view
        returns (uint8[] memory actions, bool active, string memory description);
}

interface IBribeExtra {
    function notifyRewardAmount(address token, uint256 amount) external;
    function recoverERC20AndUpdateData(address token, uint256 amount) external;
    function emergencyRecoverERC20(address token, uint256 amount) external;
    function owner() external view returns (address);
    function bribeFactory() external view returns (address);
}

interface IBribeFactory {
    function recoverERC20AndUpdateData(address[] memory bribes, address[] memory tokens, uint256[] memory amounts)
        external;
    function recoverERC20From(address[] memory bribes, address[] memory tokens, uint256[] memory amounts) external;
}

interface IOwned {
    function owner() external view returns (address);
}

interface IBeacon {
    function implementation() external view returns (address);
}

interface IMinter {
    function update_period() external returns (uint256);
}

interface IApprove {
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IFeed {
    function description() external view returns (string memory);
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

contract ForkTest is Test {
    using stdJson for string;

    uint256 internal constant WEEK = 604800;
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    uint256 internal constant WEIGHTS_PER_EPOCH_SLOT = 22;

    address internal constant VOTER = 0xc69E3eF39E3fFBcE2A1c570f8d3ADF76909ef17b;
    address internal constant VOTER_IMPL = 0x9CB9fc7D128F89CBD43Bbfd89dBAb05D1FA17233;
    address internal constant VE = 0x25B2ED7149fb8A05f6eF9407d9c8F878f59cd1e1;
    address internal constant VE_IMPL = 0x0FC68cE53Be957a1AA779f553AD49f6068fFf231;
    address internal constant BRIBE_BEACON = 0x5aEb9f88B66Cd94f0cE50d139F9Fc257B65411C2;
    address internal constant BRIBE_IMPL = 0x6225a2B81F83a71c0595449A224Fc2385DfAA28D;
    address internal constant CLAIM_LOGIC = 0x68Ed6a9fd3fe6DB26dEf56641c3B251278d8C21D;
    address internal constant APPROVAL_LOGIC = 0x4B0BC0889EB524Dbae36d409fF733851E9B4f63D;
    address internal constant BRIBE_OWNER = 0x1aE3753d9b60743A89159CcFF8E251C60B560311;
    address internal constant MINTER = 0xA7D64625F45548a19B2A19e28E7546bb2839003E;
    address internal constant TREASURY = 0x450c72de8c0079B49AcedF294a13011bd09D125B;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant HYDX = 0x00000e7efa313F4E11Bfff432471eD9423AC6B30;
    address internal constant SEQUENCER_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    bytes32 internal constant VOTER_PROXY_CODEHASH = 0xbdf20cb78c052fa6ad3cfe77fde23f9eea05a6f1f4087c07ecde2f274a2b36e1;
    bytes32 internal constant VOTER_IMPL_CODEHASH = 0x42618eac51788e20459a854690666979bd13bbe185e3323bd6d7dd59ee8a31b0;
    bytes32 internal constant VE_PROXY_CODEHASH = 0x96c3cd33e65424eb56bec90a4fb2ab41c16085b1afc0dcb37dcd412b666fb2d6;
    bytes32 internal constant VE_IMPL_CODEHASH = 0xe6b54672ba85711eac5516d6ce09fe96cabe9cc3764a178e5d2f33a6241c2b42;
    bytes32 internal constant BEACON_CODEHASH = 0xaaa27093ce9a3136b77cbcbfbee1c26a564b1d2742bc57f916f1cafe5e41f956;
    bytes32 internal constant BRIBE_IMPL_CODEHASH = 0x419b9ff2bbe35af4ba4fb135c4f4a2cc215e0c212196d0b0d5dbf7bb6f301055;
    bytes32 internal constant CLAIM_LOGIC_CODEHASH = 0xff06fc1990ab09a31cf65c657fd15babd45a76ecf9a93f0b64d33e163e6cecf8;
    bytes32 internal constant APPROVAL_LOGIC_CODEHASH =
        0xd1fab3adcd045439b72359a675665cb9f9267b32aebb140df865fc723681a930;
    bytes32 internal constant TREASURY_CODEHASH = 0x4e381985ca68b3e5d27b4425fa581c19cf33146d3f887a3cfca96f55528ea46f;

    uint256 internal constant TOKEN_ID = 14_247;
    address internal constant HOLDER = 0xa79cd47655156b299762DFE92A67980805ce5a31;

    address internal stranger = makeAddr("stranger");
    address internal briber = makeAddr("briber");
    string internal fx;
    ImmutableVeTokenConduit internal conduit;
    Deploy internal d;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_RPC_URL", string(""));
        vm.skip(bytes(rpc).length == 0);
        fx = vm.readFile("test/fixtures/fork.json");
        vm.createSelectFork(rpc, fx.readUint(".block"));
        assertEq(block.chainid, 8453);
        d = new Deploy();
    }

    function _deploy() internal {
        conduit = ImmutableVeTokenConduit(d.run());
    }

    function _optIn() internal {
        vm.prank(HOLDER);
        IVotingEscrowExtra(VE).setConduitApproval(address(conduit), TOKEN_ID, true);
    }

    function _nextEpoch() internal returns (uint256 epoch) {
        epoch = fx.readUint(".epoch") + WEEK;
        vm.warp(epoch + 1 hours);
        vm.roll(block.number + 1800);
        IMinter(MINTER).update_period();
        assertEq(IVoter(VOTER)._epochTimestamp(), epoch);
        _restampFeeds();
    }

    function _restampFeeds() internal {
        ImmutableVeTokenConduit.PricedToken[] memory p = d.pricedTokens();
        uint256[] memory answers = fx.readUintArray(".answers");
        for (uint256 i; i < p.length; ++i) {
            vm.mockCall(
                p[i].feed,
                abi.encodeCall(IFeed.latestRoundData, ()),
                abi.encode(uint80(1), int256(answers[i]), block.timestamp, block.timestamp, uint80(1))
            );
        }
    }

    function _next() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 2);
        _restampFeeds();
    }

    function _notify(address bribe, address token, uint256 amount) internal {
        deal(token, briber, amount);
        vm.startPrank(briber);
        IApprove(token).approve(bribe, amount);
        IBribeExtra(bribe).notifyRewardAmount(token, amount);
        vm.stopPrank();
    }

    function _weightSlot(address pool, uint256 epoch) internal pure returns (bytes32) {
        return keccak256(abi.encode(pool, keccak256(abi.encode(epoch, WEIGHTS_PER_EPOCH_SLOT))));
    }

    function _replayMarket(uint256 epoch) internal {
        address[] memory bribes = fx.readAddressArray(".market.bribes");
        address[] memory tokens = fx.readAddressArray(".market.tokens");
        uint256[] memory amounts = fx.readUintArray(".market.amounts");
        for (uint256 i; i < bribes.length; ++i) {
            _notify(bribes[i], tokens[i], amounts[i]);
        }
        address[] memory pools = fx.readAddressArray(".market.pools");
        uint256[] memory others = fx.readUintArray(".market.others");
        for (uint256 i; i < pools.length; ++i) {
            vm.store(VOTER, _weightSlot(pools[i], epoch), bytes32(others[i]));
            assertEq(IVoterExtra(VOTER).weightsAt(pools[i], epoch), others[i]);
        }
    }

    function _externalBribe(address pool) internal view returns (address) {
        return IVoter(VOTER).external_bribes(IVoter(VOTER).gauges(pool));
    }

    function _repeat(address[] memory tokens, uint256 n) internal pure returns (address[][] memory r) {
        r = new address[][](n);
        for (uint256 i; i < n; ++i) {
            r[i] = tokens;
        }
    }

    function test_pin_hydrex() public view {
        assertEq(address(uint160(uint256(vm.load(VOTER, IMPL_SLOT)))), VOTER_IMPL);
        assertEq(address(uint160(uint256(vm.load(VE, IMPL_SLOT)))), VE_IMPL);
        assertEq(IBeacon(BRIBE_BEACON).implementation(), BRIBE_IMPL);
        assertEq(VOTER.codehash, VOTER_PROXY_CODEHASH);
        assertEq(VOTER_IMPL.codehash, VOTER_IMPL_CODEHASH);
        assertEq(VE.codehash, VE_PROXY_CODEHASH);
        assertEq(VE_IMPL.codehash, VE_IMPL_CODEHASH);
        assertEq(BRIBE_BEACON.codehash, BEACON_CODEHASH);
        assertEq(BRIBE_IMPL.codehash, BRIBE_IMPL_CODEHASH);
        assertEq(IVoterExtra(VOTER).claimLogic(), CLAIM_LOGIC);
        assertEq(CLAIM_LOGIC.codehash, CLAIM_LOGIC_CODEHASH);
        assertEq(IVotingEscrowExtra(VE).approvalLogic(), APPROVAL_LOGIC);
        assertEq(APPROVAL_LOGIC.codehash, APPROVAL_LOGIC_CODEHASH);

        assertEq(IVoterExtra(VOTER).VOTE_DELAY(), 0);
        assertEq(IVoterExtra(VOTER).minter(), MINTER);
        assertEq(IVoter(VOTER)._epochTimestamp(), fx.readUint(".epoch"));
        assertEq(IVotingEscrow(VE).ownerOf(TOKEN_ID), HOLDER);

        address bribe = fx.readAddressArray(".market.bribes")[0];
        assertEq(IBribeExtra(bribe).owner(), BRIBE_OWNER);
        assertEq(IOwned(IBribeExtra(bribe).bribeFactory()).owner(), BRIBE_OWNER);
        assertEq(
            address(uint160(uint256(vm.load(bribe, bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1))))),
            BRIBE_BEACON
        );

        address pool = fx.readAddressArray(".market.pools")[0];
        uint256 epoch = fx.readUint(".epoch");
        assertEq(uint256(vm.load(VOTER, _weightSlot(pool, epoch))), IVoterExtra(VOTER).weightsAt(pool, epoch));
        assertGt(IVoterExtra(VOTER).weightsAt(pool, epoch), 0);
    }

    function test_pin_feedsAndTreasury() public view {
        string[4] memory descriptions = ["ETH / USD", "cbBTC / USD", "USDC / USD", "EURC / USD"];
        ImmutableVeTokenConduit.PricedToken[] memory p = d.pricedTokens();
        uint256[] memory answers = fx.readUintArray(".answers");
        for (uint256 i; i < p.length; ++i) {
            assertEq(IFeed(p[i].feed).description(), descriptions[i]);
            assertEq(IFeed(p[i].feed).decimals(), 8);
            (, int256 answer,, uint256 updatedAt,) = IFeed(p[i].feed).latestRoundData();
            assertEq(uint256(answer), answers[i]);
            assertLe(block.timestamp - updatedAt, p[i].maxAge);
        }
        assertEq(IFeed(SEQUENCER_FEED).description(), "L2 Sequencer Uptime Status Feed");
        (, int256 status, uint256 startedAt,,) = IFeed(SEQUENCER_FEED).latestRoundData();
        assertEq(status, 0);
        assertGt(block.timestamp - startedAt, 3600);
        assertEq(TREASURY.codehash, TREASURY_CODEHASH);
    }

    function test_pin_deployScript() public {
        address predicted = d.predict();
        assertEq(predicted.code.length, 0);
        assertEq(d.run(), predicted);
        ImmutableVeTokenConduit c = ImmutableVeTokenConduit(predicted);
        assertEq(c.voter(), VOTER);
        assertEq(c.veToken(), VE);
        assertEq(c.TREASURY(), TREASURY);
        (uint8[] memory actions, bool active, string memory description) =
            IVotingEscrowExtra(VE).getConduitApprovalConfig(predicted);
        assertTrue(active);
        assertEq(actions.length, 2);
        assertEq(actions[0], 3);
        assertEq(actions[1], 5);
        assertEq(description, "");
        assertEq(
            keccak256(predicted.code),
            vm.parseJsonBytes32(vm.readFile("verification/bytecode-hashes.json"), ".deployment.runtimeKeccak")
        );
    }

    function test_vote_waterFilling() public {
        _deploy();
        _optIn();
        uint256 epoch = _nextEpoch();
        _replayMarket(epoch);

        uint256 power = fx.readUint(".power");
        assertEq(IVotingEscrow(VE).getPastVotes(address(conduit), epoch), power);
        address[] memory pools = fx.readAddressArray(".market.pools");
        uint256[] memory weights = fx.readUintArray(".market.weights");
        uint256[] memory values = fx.readUintArray(".market.values");
        uint256[] memory others = fx.readUintArray(".market.others");
        for (uint256 i; i < pools.length; ++i) {
            assertEq(conduit.poolValue(pools[i]), values[i]);
            assertEq(IVoter(VOTER).weights(pools[i]), others[i]);
        }
        uint256 expected = fx.readUint(".market.score");
        assertEq(conduit.currentScore(), 0);
        assertEq(conduit.score(pools, weights), expected);

        vm.prank(stranger);
        (uint256 oldScore, uint256 newScore) = conduit.vote(pools, weights);
        assertEq(oldScore, 0);
        assertEq(newScore, expected);
        assertApproxEqAbs(newScore, fx.readUint(".market.optimum"), 1e9);
        assertEq(conduit.currentScore(), newScore);
        uint256 total;
        for (uint256 i; i < weights.length; ++i) {
            total += weights[i];
        }
        for (uint256 i; i < pools.length; ++i) {
            assertEq(IVoter(VOTER).votes(address(conduit), pools[i]), weights[i] * power / total);
            assertEq(IVoter(VOTER).weights(pools[i]), others[i] + weights[i] * power / total);
        }

        address[] memory one = new address[](1);
        one[0] = pools[0];
        uint256[] memory w1 = new uint256[](1);
        w1[0] = 1;
        vm.expectRevert(
            abi.encodeWithSelector(ImmutableVeTokenConduit.NotBetter.selector, newScore, conduit.score(one, w1))
        );
        conduit.vote(one, w1);

        address extra = _freshPool(pools);
        _notify(_externalBribe(extra), USDC, 1000e6);
        address[] memory better = new address[](pools.length + 1);
        uint256[] memory wb = new uint256[](pools.length + 1);
        for (uint256 i; i < pools.length; ++i) {
            better[i] = pools[i];
            wb[i] = weights[i];
        }
        better[pools.length] = extra;
        wb[pools.length] = 1e18;
        uint256 betterScore = conduit.score(better, wb);
        assertGt(betterScore, newScore + 999e18);
        vm.expectRevert(abi.encodeWithSignature("VoteDelayNotMet()"));
        conduit.vote(better, wb);

        _next();
        vm.prank(stranger);
        (oldScore, newScore) = conduit.vote(better, wb);
        assertEq(newScore, betterScore);
        assertEq(oldScore, expected);
        assertEq(IVoter(VOTER).poolVoteLength(address(conduit)), pools.length + 1);
    }

    function _freshPool(address[] memory taken) internal view returns (address) {
        address[] memory candidates = fx.readAddressArray(".gasPools");
        for (uint256 i; i < candidates.length; ++i) {
            bool used;
            for (uint256 j; j < taken.length; ++j) {
                used = used || taken[j] == candidates[i];
            }
            if (!used && IVoter(VOTER).weights(candidates[i]) == 0) return candidates[i];
        }
        revert("no fresh pool");
    }

    function test_vote_worstCaseGas() public {
        _deploy();
        _optIn();
        _nextEpoch();
        address[] memory candidates = fx.readAddressArray(".gasPools");
        uint256 n = conduit.MAX_POOLS();
        address[] memory current = new address[](n);
        address[] memory proposal = new address[](n);
        uint256[] memory weights = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            current[i] = candidates[i];
            proposal[i] = candidates[n + i];
            weights[i] = 1;
            _notify(_externalBribe(current[i]), USDC, 10e6);
            _notify(_externalBribe(proposal[i]), USDC, 20e6);
        }
        vm.prank(stranger);
        conduit.vote(current, weights);
        assertEq(IVoter(VOTER).poolVoteLength(address(conduit)), n);

        _next();
        vm.prank(stranger);
        conduit.vote(proposal, weights);
        Vm.Gas memory g = vm.lastFrameGas();
        uint256 used = g.gasLimit - g.gasRemaining;
        uint256 calldataGas = 16 * abi.encodeCall(ImmutableVeTokenConduit.vote, (proposal, weights)).length;
        emit log_named_uint("worst-case vote, execution gas", used);
        emit log_named_uint("worst-case vote, with intrinsic gas", used + 21_000 + calldataGas);
        assertLt(used + 21_000 + calldataGas, 14_000_000);
        assertEq(IVoter(VOTER).poolVote(address(conduit), 0), proposal[0]);
        assertEq(IVoter(VOTER).votes(address(conduit), current[0]), 0);
    }

    function test_vote_killedGaugeInForceStillCounts() public {
        _deploy();
        _optIn();
        uint256 epoch = _nextEpoch();
        address[] memory candidates = fx.readAddressArray(".gasPools");
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = candidates[0];
        weights[0] = 1;
        _notify(_externalBribe(candidates[0]), USDC, 100e6);
        _notify(_externalBribe(candidates[1]), USDC, 100e6);
        vm.prank(stranger);
        (, uint256 score) = conduit.vote(pools, weights);

        address gauge = IVoter(VOTER).gauges(candidates[0]);
        vm.prank(IPermissionsRegistry(IVoterExtra(VOTER).permissionRegistry()).emergencyCouncil());
        IVoterExtra(VOTER).killGauge(gauge);
        assertFalse(IVoter(VOTER).isAlive(gauge));
        assertEq(IVoter(VOTER).weights(candidates[0]), 0);
        assertEq(
            IBribe(_externalBribe(candidates[0])).totalSupplyAt(epoch),
            IVoter(VOTER).votes(address(conduit), candidates[0])
        );

        _next();
        assertEq(conduit.currentScore(), score);
        pools[0] = candidates[1];
        vm.expectRevert(abi.encodeWithSelector(ImmutableVeTokenConduit.NotBetter.selector, score, score));
        conduit.vote(pools, weights);
    }

    function _claimArgs()
        internal
        view
        returns (address[] memory fees, address[] memory bribes, address[] memory tokens, uint256[] memory amounts)
    {
        fees = fx.readAddressArray(".claim.fees");
        bribes = fx.readAddressArray(".claim.bribes");
        tokens = fx.readAddressArray(".claim.tokens");
        amounts = fx.readUintArray(".claim.amounts");
        assertEq(tokens[0], USDC);
        assertEq(tokens[1], WETH);
        assertEq(tokens[2], HYDX);
    }

    function _balances(address[] memory tokens, address account) internal view returns (uint256[] memory b) {
        b = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            b[i] = IERC20(tokens[i]).balanceOf(account);
        }
    }

    function _assertSplit(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory holderBefore,
        uint256[] memory treasuryBefore
    ) internal view {
        uint256[] memory holderAfter = _balances(tokens, HOLDER);
        uint256[] memory treasuryAfter = _balances(tokens, TREASURY);
        for (uint256 i; i < tokens.length; ++i) {
            assertGt(amounts[i], 100);
            assertEq(treasuryAfter[i] - treasuryBefore[i], amounts[i] / 100);
            assertEq(holderAfter[i] - holderBefore[i], amounts[i] - amounts[i] / 100);
            assertEq(IERC20(tokens[i]).balanceOf(address(conduit)), 0);
        }
    }

    function test_claim_strangerPaysOwnerAndTreasury() public {
        _deploy();
        _optIn();
        (address[] memory fees, address[] memory bribes, address[] memory tokens, uint256[] memory amounts) =
            _claimArgs();
        uint256[] memory holderBefore = _balances(tokens, HOLDER);
        uint256[] memory treasuryBefore = _balances(tokens, TREASURY);

        uint256[] memory cuts = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            cuts[i] = amounts[i] / 100;
        }
        vm.expectEmit(address(conduit));
        emit ImmutableVeTokenConduit.Claimed(TOKEN_ID, HOLDER, stranger, tokens, amounts, cuts, 0);
        vm.prank(stranger);
        assertEq(conduit.claim(TOKEN_ID, fees, bribes, tokens), amounts);
        assertEq(conduit.lastClaimBlock(TOKEN_ID), block.number);

        _assertSplit(tokens, amounts, holderBefore, treasuryBefore);
        uint256[] memory strangerAfter = _balances(tokens, stranger);
        for (uint256 i; i < tokens.length; ++i) {
            assertEq(strangerAfter[i], 0);
        }
    }

    function test_claim_ownerPaysTheSameFee() public {
        _deploy();
        _optIn();
        (address[] memory fees, address[] memory bribes, address[] memory tokens, uint256[] memory amounts) =
            _claimArgs();
        uint256[] memory holderBefore = _balances(tokens, HOLDER);
        uint256[] memory treasuryBefore = _balances(tokens, TREASURY);
        vm.prank(HOLDER);
        conduit.claim(TOKEN_ID, fees, bribes, tokens);
        _assertSplit(tokens, amounts, holderBefore, treasuryBefore);
    }

    function test_claim_requiresOptIn() public {
        _deploy();
        (address[] memory fees, address[] memory bribes, address[] memory tokens,) = _claimArgs();
        vm.expectRevert(abi.encodeWithSignature("NotApprovedOrOwner()"));
        vm.prank(stranger);
        conduit.claim(TOKEN_ID, fees, bribes, tokens);
    }

    function test_claim_ownerCanBypassTheConduit() public {
        _deploy();
        _optIn();
        (address[] memory fees, address[] memory bribes, address[] memory tokens, uint256[] memory amounts) =
            _claimArgs();
        uint256[] memory holderBefore = _balances(tokens, HOLDER);
        uint256[] memory treasuryBefore = _balances(tokens, TREASURY);
        vm.startPrank(HOLDER);
        IVoter(VOTER).claimFeesToRecipientByTokenId(fees, _repeat(tokens, fees.length), TOKEN_ID, HOLDER);
        IVoter(VOTER).claimBribesToRecipientByTokenId(bribes, _repeat(tokens, bribes.length), TOKEN_ID, HOLDER);
        vm.stopPrank();
        uint256[] memory holderAfter = _balances(tokens, HOLDER);
        uint256[] memory treasuryAfter = _balances(tokens, TREASURY);
        for (uint256 i; i < tokens.length; ++i) {
            assertEq(holderAfter[i] - holderBefore[i], amounts[i]);
            assertEq(treasuryAfter[i], treasuryBefore[i]);
        }
    }

    function test_bribes_onlyTheirOwnerCanRecoverThem() public {
        address[] memory bribes = fx.readAddressArray(".market.bribes");
        address[] memory tokens = fx.readAddressArray(".market.tokens");
        uint256[] memory amounts = fx.readUintArray(".market.amounts");
        uint256 k;
        while (tokens[k] != USDC) ++k;
        address bribe = bribes[k];
        uint256 amount = amounts[k];
        (, uint256 recorded,) = IBribe(bribe).rewardData(USDC, fx.readUint(".epoch"));
        assertEq(recorded, amount);

        address[] memory b = new address[](1);
        b[0] = bribe;
        address[] memory t = new address[](1);
        t[0] = USDC;
        uint256[] memory a = new uint256[](1);
        a[0] = amount;
        IBribeFactory factory = IBribeFactory(IBribeExtra(bribe).bribeFactory());
        address[3] memory others = [stranger, HOLDER, TREASURY];
        for (uint256 i; i < others.length; ++i) {
            vm.startPrank(others[i]);
            vm.expectRevert(bytes("permission is denied!"));
            IBribeExtra(bribe).recoverERC20AndUpdateData(USDC, amount);
            vm.expectRevert(bytes("permission is denied!"));
            IBribeExtra(bribe).emergencyRecoverERC20(USDC, amount);
            vm.expectRevert(bytes("Ownable: caller is not the owner"));
            factory.recoverERC20AndUpdateData(b, t, a);
            vm.expectRevert(bytes("Ownable: caller is not the owner"));
            factory.recoverERC20From(b, t, a);
            vm.stopPrank();
        }

        uint256 before = IERC20(USDC).balanceOf(BRIBE_OWNER);
        vm.prank(BRIBE_OWNER);
        factory.recoverERC20AndUpdateData(b, t, a);
        (, recorded,) = IBribe(bribe).rewardData(USDC, fx.readUint(".epoch"));
        assertEq(recorded, 0);
        assertEq(IERC20(USDC).balanceOf(BRIBE_OWNER) - before, amount);
    }
}
