// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {KYCContract} from "../src/KYCContract.sol";
import {MockToken} from "../src/mock/MockToken.sol";
import {MockIdentitySBT} from "../src/mock/MockIdentitySBT.sol";
import {MockV3Aggregator} from "chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

contract KYCContractTest is Test {
    KYCContract kycContract;
    MockToken usdc;
    MockToken weth;
    MockIdentitySBT identitySBT;
    MockV3Aggregator priceFeed;
    address user1 = address(0x1);
    address user2 = address(0x2);
    address owner = address(this);
    int256 price = 100000000; // 1 USD with 8 decimals

    function setUp() public {
        // Deploy mock contracts
        identitySBT = new MockIdentitySBT();
        usdc = new MockToken("USDC", "USDC", 1000000 * 10**18);
        weth = new MockToken("WETH", "WETH", 1000000 * 10**18);
        priceFeed = new MockV3Aggregator(8, price); // 8 decimals, initial price 1 USD
        
        // Deploy KYC contract
        kycContract = new KYCContract(address(identitySBT));
        
        // Set up price feeds
        kycContract.setPriceFeed(address(usdc), address(priceFeed));
        kycContract.setPriceFeed(address(weth), address(priceFeed));
    }

    function test_IsPermitKYC_UnderLimit() public {
        // Test with amount under $500
        assertTrue(kycContract.isPermitKYCSwap(100 * 10**18, address(usdc)));
    }

    function test_IsPermitKYC_OverLimit() public {
        // Test with amount over $10000
        assertFalse(kycContract.isPermitKYCSwap(20000 * 10**18, address(usdc)));
    }

    function test_IsPermitKYC_WithKYC() public {
        // Mint KYC token to user1
        identitySBT.setKYC(tx.origin, true);
        
        // Test with amount over $500 but user has KYC
        vm.prank(tx.origin);
        assertTrue(kycContract.isPermitKYCSwap(1000 * 10**18, address(usdc)));
    }

    function test_IsPermitKYC_WithoutKYC() public {
        // Test with amount over $500 but user has not KYC
        vm.prank(tx.origin);
        assertFalse(kycContract.isPermitKYCSwap(1000 * 10**18, address(usdc)));
    }

    function test_IsPermitKYCModifyLiquidity_UnderLimit() public {
        // Test with amounts under $500
        assertTrue(kycContract.isPermitKYCModifyLiquidity(
            100 * 10**18,  // amount0
            address(usdc),
            100 * 10**18,  // amount1
            address(weth)
        ));
    }

    function test_IsPermitKYCModifyLiquidity_OverLimit() public {
        // Test with amounts over $10000
        assertFalse(kycContract.isPermitKYCModifyLiquidity(
            10000 * 10**18,  // amount0
            address(usdc),
            10000 * 10**18,  // amount1
            address(weth)
        ));
    }

    function test_IsPermitKYCModifyLiquidity_WithKYC() public {
        // Mint KYC token to user1
        identitySBT.setKYC(tx.origin, true);
        
        // Test with amounts over $500 but user has KYC
        vm.prank(tx.origin);
        assertTrue(kycContract.isPermitKYCModifyLiquidity(
            1000 * 10**18,  // amount0
            address(usdc),
            1000 * 10**18,  // amount1
            address(weth)
        ));
    }

    function test_IsPermitKYCModifyLiquidity_WithoutKYC() public {
        // Test with amount over $500 but user has not KYC
        vm.prank(tx.origin);
        assertFalse(kycContract.isPermitKYCModifyLiquidity(
            1000 * 10**18,  // amount0
            address(usdc),
            1000 * 10**18,  // amount1
            address(weth)
        ));
    }

    function test_IsPermitKYCModifyLiquidity_MixedAmounts() public {
        // Test with mixed amounts (one under limit, one over)
        assertFalse(kycContract.isPermitKYCModifyLiquidity(
            100 * 10**18,    // amount0 under limit
            address(usdc),
            1000 * 10**18,   // amount1 over limit
            address(weth)
        ));
    }

    function test_QueryPrice_ZeroAddress() public {
        vm.expectRevert(KYCContract.PriceFeedNotSet.selector);
        kycContract.isPermitKYCSwap(100 * 10**18, address(0));
    }

    function test_QueryPrice_UpdatePrice() public {
        // Update price to $2
        priceFeed.updateAnswer(200000000);
        
        // Test with amount that would be under limit at $1 but over at $2
        assertFalse(kycContract.isPermitKYCSwap(1000 * 10**18, address(usdc)));
    }
} 