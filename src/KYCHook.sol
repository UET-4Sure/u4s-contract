// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import {IIdentitySBT} from "./interfaces/IIdentitySBT.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Only KYC'ed people can trade on the V4 hook'ed pool.
 */
contract KYCHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    IIdentitySBT public identitySBT;


    constructor(
        IPoolManager _poolManager,
        address _identitySBT
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        identitySBT = IIdentitySBT(_identitySBT);
    }

    modifier onlyPermitKYC() {
        require(identitySBT.hasToken(tx.origin), "KYCHook: not permit kyc");
        _;
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
        PoolKey calldata, 
        IPoolManager.SwapParams calldata, 
        bytes calldata
    ) internal onlyPermitKYC() override returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0); 
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal onlyPermitKYC() override returns (bytes4) {
        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal onlyPermitKYC() override returns (bytes4) {
        return BaseHook.beforeRemoveLiquidity.selector;
    }
}
