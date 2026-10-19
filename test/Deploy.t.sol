// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../script/Deploy.s.sol";
import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {MockFeed} from "./mocks/MockFeed.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MockVotingEscrow} from "./mocks/MockVotingEscrow.sol";

contract DeployTest is Test {
    Deploy internal d;

    function setUp() public {
        vm.chainId(8453);
        vm.warp(1_792_400_000);
        d = new Deploy();
        vm.etch(d.VOTER(), hex"00");
        vm.etch(d.VE_TOKEN(), address(new MockVotingEscrow()).code);
        vm.etch(d.WETH(), address(new MockToken(18)).code);
        vm.etch(d.CBBTC(), address(new MockToken(8)).code);
        vm.etch(d.USDC(), address(new MockToken(6)).code);
        vm.etch(d.EURC(), address(new MockToken(6)).code);
        _feed(d.ETH_USD(), 8, 2400e8);
        _feed(d.CBBTC_USD(), 8, 80_000e8);
        _feed(d.USDC_USD(), 8, 1e8);
        _feed(d.EURC_USD(), 8, 1.12e8);
        _feed(d.SEQUENCER_FEED(), 0, 0);
        MockFeed(d.SEQUENCER_FEED()).setStartedAt(block.timestamp - 30 days);
    }

    function _feed(address feed, uint8 decimals, int256 answer) internal {
        vm.etch(feed, address(new MockFeed(decimals, answer)).code);
        MockFeed(feed).set(answer, block.timestamp);
    }

    function test_canonicalValues() public view {
        assertEq(d.VOTER(), 0xc69E3eF39E3fFBcE2A1c570f8d3ADF76909ef17b);
        assertEq(d.VE_TOKEN(), 0x25B2ED7149fb8A05f6eF9407d9c8F878f59cd1e1);
        assertEq(d.USDC(), 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
        assertEq(d.SEQUENCER_FEED(), 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433);
        assertEq(d.SALT(), keccak256("metadex.cafe/ImmutableVeTokenConduit/v1"));

        ImmutableVeTokenConduit.PricedToken[] memory p = d.pricedTokens();
        assertEq(p.length, 4);
        _assertPriced(
            p[0], 0x4200000000000000000000000000000000000006, 0x50015f8b17fb2C290Dde41fDc246ed0dcEE93a8b, 1500
        );
        _assertPriced(
            p[1], 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf, 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D, 1500
        );
        _assertPriced(
            p[2], 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, 108_000
        );
        _assertPriced(
            p[3], 0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42, 0xDAe398520e2B67cd3f27aeF9Cf14D93D927f8250, 108_000
        );
    }

    function _assertPriced(ImmutableVeTokenConduit.PricedToken memory p, address token, address feed, uint256 maxAge)
        internal
        pure
    {
        assertEq(p.token, token);
        assertEq(p.feed, feed);
        assertEq(p.maxAge, maxAge);
    }

    function test_maxAges_areHeartbeatsPlusAQuarter() public view {
        assertEq(d.FAST_MAX_AGE(), 1200 * 5 / 4);
        assertEq(d.SLOW_MAX_AGE(), 86_400 * 5 / 4);
    }

    function test_recordMatchesScript() public {
        string memory json = vm.readFile("verification/bytecode-hashes.json");
        assertEq(vm.parseJsonString(json, ".contract"), "src/ImmutableVeTokenConduit.sol:ImmutableVeTokenConduit");
        assertEq(vm.parseJsonAddress(json, ".create2Deployer"), CREATE2_FACTORY);
        assertEq(vm.parseJsonString(json, ".saltPreimage"), d.SALT_PREIMAGE());
        assertEq(vm.parseJsonBytes32(json, ".salt"), d.SALT());
        assertEq(
            vm.parseJsonBytes32(json, ".creationCodeKeccak"), keccak256(type(ImmutableVeTokenConduit).creationCode)
        );

        ImmutableVeTokenConduit local =
            new ImmutableVeTokenConduit(d.VOTER(), d.VE_TOKEN(), d.SEQUENCER_FEED(), d.pricedTokens());
        assertEq(vm.parseJsonAddress(json, ".deployment.voter"), d.VOTER());
        assertEq(vm.parseJsonAddress(json, ".deployment.veToken"), d.VE_TOKEN());
        assertEq(vm.parseJsonAddress(json, ".deployment.sequencerFeed"), d.SEQUENCER_FEED());
        ImmutableVeTokenConduit.PricedToken[] memory p = d.pricedTokens();
        address[] memory tokens = vm.parseJsonAddressArray(json, ".deployment.pricedTokens");
        address[] memory feeds = vm.parseJsonAddressArray(json, ".deployment.feeds");
        uint256[] memory maxAges = vm.parseJsonUintArray(json, ".deployment.maxAges");
        assertEq(tokens.length, p.length);
        for (uint256 i; i < p.length; ++i) {
            assertEq(tokens[i], p[i].token);
            assertEq(feeds[i], p[i].feed);
            assertEq(maxAges[i], p[i].maxAge);
        }
        assertEq(vm.parseJsonBytes(json, ".deployment.constructorArgs"), d.constructorArgs());
        assertEq(vm.parseJsonAddress(json, ".deployment.address"), d.predict());
        assertEq(vm.parseJsonBytes32(json, ".deployment.runtimeKeccak"), keccak256(address(local).code));
    }

    function test_run_deploysAtPredictedAddress() public {
        address predicted = d.predict();
        assertEq(predicted.code.length, 0);

        assertEq(d.run(), predicted);

        ImmutableVeTokenConduit c = ImmutableVeTokenConduit(predicted);
        assertEq(c.voter(), d.VOTER());
        assertEq(c.veToken(), d.VE_TOKEN());
        assertEq(c.sequencerFeed(), d.SEQUENCER_FEED());
        assertTrue(MockVotingEscrow(d.VE_TOKEN()).configActive(predicted));
    }

    function test_run_isIdempotent() public {
        address first = d.run();
        bytes32 codehash = first.codehash;

        assertEq(d.run(), first);
        assertEq(first.codehash, codehash);
    }

    function test_run_failsWithoutDeployer() public {
        vm.etch(CREATE2_FACTORY, "");
        vm.expectRevert(bytes("CREATE2 deployer not present"));
        d.run();
    }

    function test_run_failsOffBase() public {
        vm.chainId(1);
        vm.expectRevert(bytes("not Base"));
        d.run();
    }
}
