// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Config} from "./base/Config.sol";
import {TaxContract} from "../src/TaxContract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract QueryTaxContractScript is Script, Config {
    TaxContract taxContract;

    function setUp() public {
        // Initialize tax contract instance using the deployed address from Config
        taxContract = TaxContract(payable(TAX_CONTRACT));
    }

    function run() public view {
        // Query ETH balance
        uint256 ethBalance = taxContract.getETHCollected();
        console.log("ETH Balance:", ethBalance);

        // Query ERC20 token balances
        // USDC
        uint256 usdcBalance = taxContract.getERC20Collected(USDC);
        console.log("USDC Balance:", usdcBalance);

        // WETH
        uint256 wethBalance = taxContract.getERC20Collected(WETH);
        console.log("WETH Balance:", wethBalance);

        // WBTC
        uint256 wbtcBalance = taxContract.getERC20Collected(WBTC);
        console.log("WBTC Balance:", wbtcBalance);

        // LINK
        uint256 linkBalance = taxContract.getERC20Collected(LINK);
        console.log("LINK Balance:", linkBalance);

        // EUR
        uint256 eurBalance = taxContract.getERC20Collected(EUR);
        console.log("EUR Balance:", eurBalance);
    }
}