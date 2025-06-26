// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Config} from "./base/Config.sol";
import {Constants} from "./base/Constants.sol";

contract QueryPoolData is Script, Config, Constants {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    function run() public {
        // Match exact pool configuration from AddLiquidity script
        uint24 lpFee = 3000; // 0.30%
        int24 tickSpacing = 60;
        
        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        (uint160 sqrtPriceX96,,,) = POOLMANAGER.getSlot0(pool.toId());
        uint128 liquidity = POOLMANAGER.getLiquidity(pool.toId());

        // Calculate price
        uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) >> 192;

        // Get token balances   
        uint256 balance0 = token0.balanceOf(address(POOLMANAGER));
        uint256 balance1 = token1.balanceOf(address(POOLMANAGER));

        // Log results
        console.log("Pool Data:");
        console.log("Current SqrtPriceX96:", sqrtPriceX96);
        console.log("Price (in terms of token1/token0):", price);
        console.log("Liquidity:", liquidity);
        console.log("Token0 Balance:", balance0);
        console.log("Token1 Balance:", balance1);
    }
} 