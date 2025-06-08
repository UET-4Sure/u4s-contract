// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Config} from "./base/Config.sol";
import {KYCContract} from "../src/KYCContract.sol";

/// @notice Deploys the KYCContract.sol contract
contract KycContractScript is Script, Config {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        KYCContract kycContract = new KYCContract(IDENTITY_SBT);
        console.log("KycContract address: ", address(kycContract));
    }
}
