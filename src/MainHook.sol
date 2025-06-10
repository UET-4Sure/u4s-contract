// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IKYCContract} from "./interfaces/IKYCContract.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "lib/uniswap-hooks/lib/v4-periphery/lib/v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "lib/uniswap-hooks/lib/v4-core/src/libraries/StateLibrary.sol";
import {ITaxContract} from "./interfaces/ITaxContract.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MainHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // Custom errors
    error NotPermitKYCSwap();
    error NotPermitKYCAddLiquidity();
    error NotPermitKYCRemoveLiquidity();

    // State variables
    IKYCContract public immutable kycContract;
    ITaxContract public immutable taxContract;

    mapping(address => uint256) public taxFees; // token => tax fee

    constructor(
        IPoolManager _poolManager,
        address _kycContract,
        address _taxContract
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        kycContract = IKYCContract(_kycContract);
        taxContract = ITaxContract(_taxContract);
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
            afterSwap: true,
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
    ) internal override returns (bytes4, BeforeSwapDelta delta, uint24) {
        uint256 amount = params.amountSpecified > 0 ? uint256(params.amountSpecified) : uint256(-params.amountSpecified);
        address token = _getSwapExactToken(key, params);

        if (!kycContract.isPermitKYCSwap(amount, token)) {
            revert NotPermitKYCSwap();
        }

        delta = _applyTax(key, params, amount);
        
        // Return 0 for lpFeeOverride as we're not changing the LP fee
        return (BaseHook.beforeSwap.selector, delta, 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        _transferTaxFee(key, params);
        
        return (BaseHook.afterSwap.selector, 0);
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

    function _transferTaxFee(PoolKey calldata key, IPoolManager.SwapParams calldata params) internal {
        address token = _getSwapTokenIn(key, params);
        uint256 fee = taxFees[token];
        if (fee > 0) {
            IERC20(token).transfer(address(taxContract), fee);
            taxFees[token] = 0;
        }
    }

    // Internal helper functions
    function _applyTax(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        uint256 amount
    ) internal returns (BeforeSwapDelta delta) {
        // Calculate a tax fee
        uint256 fee = taxContract.calculateTax(amount);
        int128 feeInt = int128(int256(fee));
        int128 amountInt = int128(int256(amount));

        // Adjust the specified amount based on swap direction
        int128 adjustedSpecifiedAmount;
        if (params.amountSpecified < 0) {
            // For exact input, reduce the amount by the fee
            adjustedSpecifiedAmount = amountInt - feeInt;
        } else {
            // For exact output, increase the amount by the fee
            adjustedSpecifiedAmount = amountInt + feeInt;
        }
        
        // Create the BeforeSwapDelta using toBeforeSwapDelta function
        delta = params.zeroForOne 
            ? toBeforeSwapDelta(-adjustedSpecifiedAmount, 0)
            : toBeforeSwapDelta(0, -adjustedSpecifiedAmount);

        address tokenIn = _getSwapTokenIn(key, params);
        taxFees[tokenIn] = fee;

        return delta;
    }

    function _getSwapExactToken(PoolKey calldata key, IPoolManager.SwapParams calldata params) internal pure returns (address) {
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

    function _getSwapTokenIn(PoolKey calldata key, IPoolManager.SwapParams calldata params) internal pure returns (address) {
        return params.zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);
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
