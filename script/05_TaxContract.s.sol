// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Config} from "./base/Config.sol";
import {TaxContract} from "../src/TaxContract.sol";

/// @notice Deploys the TaxContract.sol contract
contract TaxContractScript is Script, Config {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        TaxContract taxContract = new TaxContract(TAX_PERCENTAGE);
        console.log("TaxContract address: ", address(taxContract));
    }
}
