// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {MainHook} from "../src/MainHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IIdentitySBT} from "../src/interfaces/IIdentitySBT.sol";
import {MockV3Aggregator} from "chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {KYCContract} from "../src/KYCContract.sol";
import {MockIdentitySBT} from "../src/mock/MockIdentitySBT.sol";
import {TaxContract} from "../src/TaxContract.sol";
import {console} from "forge-std/console.sol";

contract MainHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    MainHook hook;
    PoolId poolId;
    MockIdentitySBT identitySBT;
    KYCContract kycContract;
    TaxContract taxContract;
    MockV3Aggregator priceFeed;
    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    uint256 constant TAX_PERCENTAGE = 1e15; // 0.1% tax rate
    uint256 constant TAX_DENOMINATOR = 1e18;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy mock IdentitySBT
        identitySBT = new MockIdentitySBT();
        identitySBT.setKYC(tx.origin, true);

        // Deploy kyc contract
        kycContract = new KYCContract(address(identitySBT));

        // Deploy tax contract with 0.1% tax rate
        taxContract = new TaxContract(TAX_PERCENTAGE);

        // Set up price feeds for the actual tokens used in the pool
        priceFeed = new MockV3Aggregator(8, 1 * 10 ** 8); // 8 decimals, initial price 1 USD
        kycContract.setPriceFeed(Currency.unwrap(currency0), address(priceFeed));
        kycContract.setPriceFeed(Currency.unwrap(currency1), address(priceFeed));

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager, address(kycContract), address(taxContract));
        deployCodeTo("MainHook.sol:MainHook", constructorArgs, flags);
        hook = MainHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 1000;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );

        // Fund to pool manager
        currency0.transfer(address(manager), 1000e18);
        currency1.transfer(address(manager), 1000e18);
    }

    function testSwapWithKYC_LowVolume() public {
        // Test swap with KYC'ed user
        bool zeroForOne = true;
        int256 amountSpecified = -500e18;
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        assertEq(int256(swapDelta.amount0()), amountSpecified);
    }

    function testSwapWithKYC_HighVolume() public {
        priceFeed.updateAnswer(5001 * 10 ** 8);

        // Test swap with KYC'ed user
        bool zeroForOne = true;
        int256 amountSpecified = -2e18;
        vm.expectRevert();
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
    }

    function testSwapWithKYC() public {
        priceFeed.updateAnswer(500 * 10 ** 8);

        // Test swap with KYC'ed user
        bool zeroForOne = true;
        int256 amountSpecified = -2e18;
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        assertEq(int256(swapDelta.amount0()), amountSpecified);
    }

    function testSwapWithoutKYC() public {
        // Revoke KYC
        identitySBT.setKYC(tx.origin, false);

        bool zeroForOne = true;
        int256 amountSpecified = -1000e18;
        vm.expectRevert();
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
    }

    function testSwapWithTaxFee() public {

        // Test swap with 0.1% tax fee
        bool zeroForOne = true;
        int256 amountSpecified = -1000e18; // 1000 tokens
        
        // Calculate expected tax fee: 1000 * 0.001 = 1 token
        uint256 expectedTaxFee = 1e18;
        
        // Record initial balances
        uint256 initialTaxContractBalance0 = currency0.balanceOf(address(taxContract));
        uint256 initialTaxContractBalance1 = currency1.balanceOf(address(taxContract));
        
        // Perform the swap
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        
        // Check that tax was collected
        uint256 finalTaxContractBalance0 = currency0.balanceOf(address(taxContract));
        uint256 finalTaxContractBalance1 = currency1.balanceOf(address(taxContract));
        
        // Since we're swapping currency0 for currency1 (zeroForOne = true), 
        // the tax should be collected in currency0
        assertEq(finalTaxContractBalance0 - initialTaxContractBalance0, expectedTaxFee, "Tax fee not collected correctly");
        assertEq(finalTaxContractBalance1, initialTaxContractBalance1, "Unexpected tax collected in currency1");
    }
}
