// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockToken} from "../../src/mock/MockToken.sol";

contract MockTokenScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        MockToken USDC = new MockToken("Circle USD", "USDC");
        console.log("USDC", address(USDC));
        MockToken WETH = new MockToken("Wrapped Ethereum", "WETH");
        console.log("WETH", address(WETH));
        MockToken WBTC = new MockToken("Wrapped Bitcoin", "WBTC");
        console.log("WBTC", address(WBTC));
        MockToken LINK = new MockToken("Chainlink", "LINK");
        console.log("LINK", address(LINK));
        MockToken EUR = new MockToken("Euro", "EUR");
        console.log("EUR", address(EUR));
        vm.stopBroadcast();
    }
}
