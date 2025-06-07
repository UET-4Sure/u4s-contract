// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {KYCContract} from "../src/KYCContract.sol";
import {MockToken} from "../src/mock/MockToken.sol";
import {MockIdentitySBT} from "../src/mock/MockIdentitySBT.sol";
import {MockOracle} from "../src/mock/MockOracle.sol";

contract KYCContractTest is Test {
    KYCContract kycContract;
    MockToken usdc;
    MockToken weth;
    MockIdentitySBT identitySBT;
    MockOracle oracle;
    address user1 = address(0x1);
    address user2 = address(0x2);
    address owner = address(this);

    function setUp() public {
        // Deploy mock contracts
        identitySBT = new MockIdentitySBT();
        usdc = new MockToken("USDC", "USDC", 1000000 * 10**18);
        weth = new MockToken("WETH", "WETH", 1000000 * 10**18);
        oracle = new MockOracle();
        
        // Deploy KYC contract
        kycContract = new KYCContract(address(identitySBT));
        
        // Set up price feeds
        vm.store(
            address(kycContract),
            keccak256(abi.encode(address(usdc), uint256(0))),
            bytes32(uint256(uint160(address(oracle))))
        );
        vm.store(
            address(kycContract),
            keccak256(abi.encode(address(weth), uint256(0))),
            bytes32(uint256(uint160(address(oracle))))
        );
    }

    function test_IsPermitKYC_UnderLimit() public {
        // Set oracle price to $1
        oracle.setPrice(1); // 1 USD with 8 decimals
        
        // Test with amount under $500
        assertTrue(kycContract.isPermitKYC(100 * 10**18, address(usdc)));
    }

    function test_IsPermitKYC_OverLimit() public {
        // Set oracle price to $1
        oracle.setPrice(1);
        
        // Test with amount over $10000
        assertFalse(kycContract.isPermitKYC(20000 * 10**18, address(usdc)));
    }

    function test_IsPermitKYC_WithKYC() public {
        // Set oracle price to $1
        oracle.setPrice(1);
        
        // Mint KYC token to user1
        identitySBT.setKYC(tx.origin, true);
        
        // Test with amount over $500 but user has KYC
        vm.prank(tx.origin);
        assertTrue(kycContract.isPermitKYC(1000 * 10**18, address(usdc)));
    }

    function test_IsPermitKYC_WithoutKYC() public {
        // Set oracle price to $1
        oracle.setPrice(1);
        
        // Test with amount over $500 but user has not KYC
        vm.prank(tx.origin);
        assertFalse(kycContract.isPermitKYC(1000 * 10**18, address(usdc)));
    }
} 