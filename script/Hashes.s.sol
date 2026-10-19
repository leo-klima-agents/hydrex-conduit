// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";
import {Deploy} from "./Deploy.s.sol";

contract Hashes is Deploy {
    function record() external returns (address predicted) {
        require(block.chainid == 8453, "run with --fork-url pointing at Base");
        predicted = predict();
        string memory artifact = vm.readFile("out/ImmutableVeTokenConduit.sol/ImmutableVeTokenConduit.json");
        ImmutableVeTokenConduit local =
            new ImmutableVeTokenConduit{salt: keccak256("Hashes")}(VOTER, VE_TOKEN, SEQUENCER_FEED, pricedTokens());

        ImmutableVeTokenConduit.PricedToken[] memory p = pricedTokens();
        address[] memory tokens = new address[](p.length);
        address[] memory feeds = new address[](p.length);
        uint256[] memory maxAges = new uint256[](p.length);
        for (uint256 i; i < p.length; ++i) {
            tokens[i] = p[i].token;
            feeds[i] = p[i].feed;
            maxAges[i] = p[i].maxAge;
        }

        string memory dep = "deployment";
        string memory depJson = vm.serializeAddress(dep, "voter", VOTER);
        depJson = vm.serializeAddress(dep, "veToken", VE_TOKEN);
        depJson = vm.serializeAddress(dep, "sequencerFeed", SEQUENCER_FEED);
        depJson = vm.serializeAddress(dep, "pricedTokens", tokens);
        depJson = vm.serializeAddress(dep, "feeds", feeds);
        depJson = vm.serializeUint(dep, "maxAges", maxAges);
        depJson = vm.serializeBytes(dep, "constructorArgs", constructorArgs());
        depJson = vm.serializeAddress(dep, "address", predicted);
        depJson = vm.serializeBytes32(dep, "runtimeKeccak", keccak256(address(local).code));

        string memory root = "hashes";
        string memory json =
            vm.serializeString(root, "contract", "src/ImmutableVeTokenConduit.sol:ImmutableVeTokenConduit");
        json = vm.serializeString(root, "solc", vm.parseJsonString(artifact, ".metadata.compiler.version"));
        json = vm.serializeAddress(root, "create2Deployer", CREATE2_FACTORY);
        json = vm.serializeString(root, "saltPreimage", SALT_PREIMAGE);
        json = vm.serializeBytes32(root, "salt", SALT);
        json = vm.serializeBytes32(root, "creationCodeKeccak", keccak256(type(ImmutableVeTokenConduit).creationCode));
        json = vm.serializeString(root, "deployment", depJson);
        vm.writeJson(json, "verification/bytecode-hashes.json");
    }
}
