// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {TaxContract} from "../src/TaxContract.sol";
import {MockToken} from "../src/mock/MockToken.sol";

contract TaxContractTest is Test {
    TaxContract taxContract;
    MockToken token;
    
    address owner = address(this);
    address user1 = address(0x1);
    address user2 = address(0x2);
    address user3 = address(0x3);
    
    uint256 constant INITIAL_TAX_RATE = 0.05e18; // 5%
    uint256 constant MAX_TAX_RATE = 1e18; // 100%
    uint256 constant INITIAL_TOKEN_SUPPLY = 1000000 * 10**18;

    event TaxWithdrawn(address indexed token, uint256 amount);
    event ETHWithdrawn(uint256 amount);
    event WhitelistUpdated(address indexed account, bool isWhitelisted);
    event TaxRateUpdated(uint256 oldRate, uint256 newRate);

    function setUp() public {
        // Deploy contracts
        taxContract = new TaxContract(INITIAL_TAX_RATE);
        token = new MockToken("Test Token", "TEST", INITIAL_TOKEN_SUPPLY);
        
        // Fund the tax contract with some ETH and tokens
        vm.deal(address(taxContract), 10 ether);
        token.transfer(address(taxContract), 100000 * 10**18);
        
        // Give some ETH to test users
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);
    }


    // ============ Whitelist Management Tests ============

    function test_UpdateWhitelist_Success() public {
        assertFalse(taxContract.isWhitelisted(user1));
        
        vm.expectEmit(true, true, true, true);
        emit WhitelistUpdated(user1, true);
        
        taxContract.updateWhitelist(user1, true);
        assertTrue(taxContract.isWhitelisted(user1));
        
        vm.expectEmit(true, true, true, true);
        emit WhitelistUpdated(user1, false);
        
        taxContract.updateWhitelist(user1, false);
        assertFalse(taxContract.isWhitelisted(user1));
    }

    function test_BatchUpdateWhitelist_Success() public {
        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = user2;
        accounts[2] = user3;
        
        // Expect all events
        vm.expectEmit(true, true, true, true);
        emit WhitelistUpdated(user1, true);
        vm.expectEmit(true, true, true, true);
        emit WhitelistUpdated(user2, true);
        vm.expectEmit(true, true, true, true);
        emit WhitelistUpdated(user3, true);
        
        taxContract.batchUpdateWhitelist(accounts, true);
        
        assertTrue(taxContract.isWhitelisted(user1));
        assertTrue(taxContract.isWhitelisted(user2));
        assertTrue(taxContract.isWhitelisted(user3));
        
        // Test batch remove
        taxContract.batchUpdateWhitelist(accounts, false);
        
        assertFalse(taxContract.isWhitelisted(user1));
        assertFalse(taxContract.isWhitelisted(user2));
        assertFalse(taxContract.isWhitelisted(user3));
    }

    // ============ Withdrawal Tests ============

    function test_WithdrawERC20_Success() public {
        // Whitelist owner first
        taxContract.updateWhitelist(owner, true);
        
        uint256 withdrawAmount = 1000 * 10**18;
        uint256 initialBalance = token.balanceOf(owner);
        uint256 contractBalance = token.balanceOf(address(taxContract));
        
        vm.expectEmit(true, true, true, true);
        emit TaxWithdrawn(address(token), withdrawAmount);
        
        taxContract.withdrawERC20(address(token), withdrawAmount);
        
        assertEq(token.balanceOf(owner), initialBalance + withdrawAmount);
        assertEq(token.balanceOf(address(taxContract)), contractBalance - withdrawAmount);
    }

    function test_WithdrawERC20_ZeroAddress() public {
        taxContract.updateWhitelist(owner, true);
        
        vm.expectRevert(TaxContract.ZeroAddress.selector);
        taxContract.withdrawERC20(address(0), 1000);
    }


    function test_WithdrawERC20_InsufficientBalance() public {
        taxContract.updateWhitelist(owner, true);
        
        uint256 contractBalance = token.balanceOf(address(taxContract));
        
        vm.expectRevert(TaxContract.InsufficientBalance.selector);
        taxContract.withdrawERC20(address(token), contractBalance + 1);
    }

    function test_WithdrawERC20_NotWhitelisted() public {
        vm.expectRevert(TaxContract.NotWhitelisted.selector);
        taxContract.withdrawERC20(address(token), 1000);
    }

    function test_WithdrawERC20_OnlyOwner() public {
        taxContract.updateWhitelist(user1, true);
        
        vm.prank(user1);
        vm.expectRevert();
        taxContract.withdrawERC20(address(token), 1000);
    }

    function test_WithdrawETH_Success() public {
        taxContract.updateWhitelist(owner, true);
        
        uint256 withdrawAmount = 1 ether;
        uint256 initialBalance = owner.balance;
        uint256 contractBalance = address(taxContract).balance;
        
        vm.expectEmit(true, true, true, true);
        emit ETHWithdrawn(withdrawAmount);
        
        taxContract.withdrawETH(withdrawAmount);
        
        assertEq(owner.balance, initialBalance + withdrawAmount);
        assertEq(address(taxContract).balance, contractBalance - withdrawAmount);
    }

    function test_WithdrawETH_InsufficientBalance() public {
        taxContract.updateWhitelist(owner, true);
        
        uint256 contractBalance = address(taxContract).balance;
        
        vm.expectRevert(TaxContract.InsufficientBalance.selector);
        taxContract.withdrawETH(contractBalance + 1);
    }

    function test_WithdrawETH_NotWhitelisted() public {
        vm.expectRevert(TaxContract.NotWhitelisted.selector);
        taxContract.withdrawETH(1 ether);
    }

    function test_WithdrawETH_OnlyOwner() public {
        taxContract.updateWhitelist(user1, true);
        
        vm.prank(user1);
        vm.expectRevert();
        taxContract.withdrawETH(1 ether);
    }

    // ============ View Function Tests ============

    function test_GetETHCollected() public {
        assertEq(taxContract.getETHCollected(), address(taxContract).balance);
        
        // Send more ETH and test again
        vm.deal(address(taxContract), 20 ether);
        assertEq(taxContract.getETHCollected(), 20 ether);
    }

    function test_CalculateTax() public {
        uint256 amount = 1000 * 10**18;
        uint256 expectedTax = (amount * INITIAL_TAX_RATE) / 1e18;
        
        assertEq(taxContract.calculateTax(amount), expectedTax);
        
        // Test with different tax rate
        taxContract.setTaxRate(0.1e18); // 10%
        expectedTax = (amount * 0.1e18) / 1e18;
        assertEq(taxContract.calculateTax(amount), expectedTax);
    }

    function test_GetAmountAfterTax() public {
        uint256 amount = 1000 * 10**18;
        uint256 tax = (amount * INITIAL_TAX_RATE) / 1e18;
        uint256 expectedAmountAfterTax = amount - tax;
        
        assertEq(taxContract.getAmountAfterTax(amount), expectedAmountAfterTax);
    }

    
    function test_ReceiveETH() public {
        uint256 initialBalance = address(taxContract).balance;
        uint256 sendAmount = 1 ether;
        
        (bool success,) = address(taxContract).call{value: sendAmount}("");
        assertTrue(success);
        
        assertEq(address(taxContract).balance, initialBalance + sendAmount);
        assertEq(taxContract.getETHCollected(), initialBalance + sendAmount);
    }

    // ============ Receive Function ============

    /**
     * @dev Allows the test contract to receive ETH
     */
    receive() external payable {}
} 