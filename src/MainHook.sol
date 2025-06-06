// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IKYCContract} from "./interfaces/IKYCContract.sol";
import {Currency} from "v4-core/src/types/Currency.sol";


contract MainHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    IKYCContract kycContract;

    constructor(
        IPoolManager _poolManager,
        address _kycContract
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        kycContract = IKYCContract(_kycContract);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(
        address, 
        PoolKey calldata key, 
        IPoolManager.SwapParams calldata params, 
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24)
    {
        // exact out
        uint256 amount = uint256(params.amountSpecified);
        address token;

        if(params.zeroForOne) {
            if(params.amountSpecified > 0) {
                token = Currency.unwrap(key.currency1);
            } else {
                token = Currency.unwrap(key.currency0);
            }
        } else {
            if(params.amountSpecified > 0) {   
                token = Currency.unwrap(key.currency0);
            } else {
                token = Currency.unwrap(key.currency1);
            }
        }

        if(!kycContract.isPermitKYC(amount, token)) {
            revert("MainHook: not permit kyc");
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0); 
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        return BaseHook.beforeRemoveLiquidity.selector;
    }
}
