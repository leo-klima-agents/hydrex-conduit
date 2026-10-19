// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ImmutableVeTokenConduit} from "../src/ImmutableVeTokenConduit.sol";

contract Deploy is Script {
    address public constant VOTER = 0xc69E3eF39E3fFBcE2A1c570f8d3ADF76909ef17b;
    address public constant VE_TOKEN = 0x25B2ED7149fb8A05f6eF9407d9c8F878f59cd1e1;
    address public constant SEQUENCER_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant ETH_USD = 0x50015f8b17fb2C290Dde41fDc246ed0dcEE93a8b;
    address public constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address public constant CBBTC_USD = 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant USDC_USD = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address public constant EURC = 0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42;
    address public constant EURC_USD = 0xDAe398520e2B67cd3f27aeF9Cf14D93D927f8250;
    uint256 public constant FAST_MAX_AGE = 1500;
    uint256 public constant SLOW_MAX_AGE = 108_000;

    string public constant SALT_PREIMAGE = "metadex.cafe/ImmutableVeTokenConduit/v1";
    bytes32 public constant SALT = keccak256(bytes(SALT_PREIMAGE));

    function pricedTokens() public pure returns (ImmutableVeTokenConduit.PricedToken[] memory p) {
        p = new ImmutableVeTokenConduit.PricedToken[](4);
        p[0] = ImmutableVeTokenConduit.PricedToken(WETH, ETH_USD, FAST_MAX_AGE);
        p[1] = ImmutableVeTokenConduit.PricedToken(CBBTC, CBBTC_USD, FAST_MAX_AGE);
        p[2] = ImmutableVeTokenConduit.PricedToken(USDC, USDC_USD, SLOW_MAX_AGE);
        p[3] = ImmutableVeTokenConduit.PricedToken(EURC, EURC_USD, SLOW_MAX_AGE);
    }

    function constructorArgs() public pure returns (bytes memory) {
        return abi.encode(VOTER, VE_TOKEN, SEQUENCER_FEED, pricedTokens());
    }

    function initCode() public pure returns (bytes memory) {
        return bytes.concat(type(ImmutableVeTokenConduit).creationCode, constructorArgs());
    }

    function predict() public pure returns (address) {
        return vm.computeCreate2Address(SALT, keccak256(initCode()), CREATE2_FACTORY);
    }

    function run() external returns (address deployed) {
        require(block.chainid == 8453, "not Base");
        require(CREATE2_FACTORY.code.length != 0, "CREATE2 deployer not present");
        deployed = predict();
        console.log("ImmutableVeTokenConduit", deployed);
        require(
            deployed == vm.parseJsonAddress(vm.readFile("verification/bytecode-hashes.json"), ".deployment.address"),
            "build differs from verification/bytecode-hashes.json"
        );
        if (deployed.code.length != 0) {
            console.log("already deployed");
            return deployed;
        }
        vm.startBroadcast();
        (bool ok,) = CREATE2_FACTORY.call(bytes.concat(SALT, initCode()));
        vm.stopBroadcast();
        require(ok && deployed.code.length != 0, "CREATE2 deploy failed");
        console.log("deployed");
    }
}
