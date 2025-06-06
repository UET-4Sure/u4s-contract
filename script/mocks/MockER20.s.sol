// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockToken} from "../../src/mock/MockToken.sol";

contract MockTokenScript is Script {
    uint256 public constant INITIAL_SUPPLY = 1000000000 * 10**18;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        MockToken USDC = new MockToken("Circle USD", "USDC", INITIAL_SUPPLY);
        console.log("USDC", address(USDC));
        MockToken WETH = new MockToken("Wrapped Ethereum", "WETH", INITIAL_SUPPLY);
        console.log("WETH", address(WETH));
        MockToken WBTC = new MockToken("Wrapped Bitcoin", "WBTC", INITIAL_SUPPLY);
        console.log("WBTC", address(WBTC));
        MockToken LINK = new MockToken("Chainlink", "LINK", INITIAL_SUPPLY);
        console.log("LINK", address(LINK));
        MockToken EUR = new MockToken("Euro", "EUR", INITIAL_SUPPLY);
        console.log("EUR", address(EUR));
        vm.stopBroadcast();
    }
}
