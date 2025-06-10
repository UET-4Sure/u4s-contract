// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Config} from "./base/Config.sol";
import {Constants} from "./base/Constants.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {MainHook} from "../src/MainHook.sol";

/// @notice Mines the address and deploys the MainHook.sol Hook contract
contract MainHookScript is Script, Config, Constants {
    function setUp() public {}

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER, KYC_CONTRACT, TAX_CONTRACT);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(MainHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.broadcast();
        MainHook mainHook = new MainHook{salt: salt}(IPoolManager(POOLMANAGER), KYC_CONTRACT, TAX_CONTRACT);
        require(address(mainHook) == hookAddress, "MainHookScript: hook address mismatch");
    }
}
