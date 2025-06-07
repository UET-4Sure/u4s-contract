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
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "lib/uniswap-hooks/lib/v4-periphery/lib/v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "lib/uniswap-hooks/lib/v4-core/src/libraries/StateLibrary.sol";

contract MainHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // Custom errors
    error NotPermitKYCSwap();
    error NotPermitKYCAddLiquidity();
    error NotPermitKYCRemoveLiquidity();

    // State variables
    IKYCContract public immutable kycContract;

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
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 amount = params.amountSpecified > 0 ? uint256(params.amountSpecified) : uint256(-params.amountSpecified);
        address token = _getSwapToken(key, params);

        if (!kycContract.isPermitKYCSwap(amount, token)) {
            revert NotPermitKYCSwap();
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) internal override returns (bytes4) {
        (uint256 amount0, uint256 amount1) = _calculateLiquidityAmounts(key, params);

        if (!kycContract.isPermitKYCModifyLiquidity(
            amount0,
            Currency.unwrap(key.currency0),
            amount1,
            Currency.unwrap(key.currency1)
        )) {
            revert NotPermitKYCAddLiquidity();
        }

        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) internal override returns (bytes4) {
        (uint256 amount0, uint256 amount1) = _calculateLiquidityAmounts(key, params);

        if (!kycContract.isPermitKYCModifyLiquidity(
            amount0,
            Currency.unwrap(key.currency0),
            amount1,
            Currency.unwrap(key.currency1)
        )) {
            revert NotPermitKYCRemoveLiquidity();
        }

        return BaseHook.beforeRemoveLiquidity.selector;
    }

    // Internal helper functions
    function _getSwapToken(PoolKey calldata key, IPoolManager.SwapParams calldata params) internal pure returns (address) {
        if (params.zeroForOne) {
            return params.amountSpecified > 0 
                ? Currency.unwrap(key.currency1)
                : Currency.unwrap(key.currency0);
        } else {
            return params.amountSpecified > 0
                ? Currency.unwrap(key.currency0)
                : Currency.unwrap(key.currency1);
        }
    }

    function _calculateLiquidityAmounts(
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params
    ) internal view returns (uint256 amount0, uint256 amount1) {
        // Get current sqrt price
        bytes32 stateSlot = keccak256(abi.encode(key.toId(), uint256(0)));
        bytes32 data = poolManager.extsload(stateSlot);
        uint160 sqrtPriceX96 = uint160(uint256(data));

        // Get sqrt prices for the range
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(params.tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(params.tickUpper);

        // Calculate amounts for the given liquidity
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            uint128(uint256(params.liquidityDelta))
        );
    }
}
