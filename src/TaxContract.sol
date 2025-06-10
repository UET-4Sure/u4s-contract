// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TaxContract is Ownable {
    
    uint256 public taxRate;
    mapping(address => bool) private _whitelistedAddresses;

    
    event TaxWithdrawn(address indexed token, uint256 amount);
    event ETHWithdrawn(uint256 amount);
    event WhitelistUpdated(address indexed account, bool isWhitelisted);
    event TaxRateUpdated(uint256 oldRate, uint256 newRate);

    
    error NotWhitelisted();
    error ZeroAmount();
    error InsufficientBalance();
    error InvalidTaxRate();
    error ZeroAddress();


    constructor(uint256 _taxRate) Ownable(msg.sender) {
        if (_taxRate > 1e18) revert InvalidTaxRate();
        taxRate = _taxRate;
    }

    modifier onlyWhitelisted() {
        if (!_checkWhitelisted(msg.sender)) revert NotWhitelisted();
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    // ============ External Functions ============

    /**
     * @dev Withdraws ERC20 tokens from the contract
     * @param token The token address to withdraw
     * @param amount The amount to withdraw
     */
    function withdrawERC20(address token, uint256 amount) 
        external 
        onlyOwner 
        onlyWhitelisted 
        validAmount(amount) 
    {
        if (token == address(0)) revert ZeroAddress();
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();
        
        IERC20(token).transfer(msg.sender, amount);
        emit TaxWithdrawn(token, amount);
    }

    /**
     * @dev Withdraws ETH from the contract
     * @param amount The amount of ETH to withdraw
     */
    function withdrawETH(uint256 amount) 
        external 
        onlyOwner 
        onlyWhitelisted 
        validAmount(amount) 
    {
        if (address(this).balance < amount) revert InsufficientBalance();
        
        payable(msg.sender).transfer(amount);
        emit ETHWithdrawn(amount);
    }

    /**
     * @dev Sets a new tax rate
     * @param _taxRate The new tax rate (must be <= 1e18)
     */
    function setTaxRate(uint256 _taxRate) external onlyOwner {
        if (_taxRate > 1e18) revert InvalidTaxRate();
        
        uint256 oldRate = taxRate;
        taxRate = _taxRate;
        
        emit TaxRateUpdated(oldRate, _taxRate);
    }

    /**
     * @dev Updates the whitelist status for a single address
     * @param account The address to update
     * @param whitelisted The new whitelist status
     */
    function updateWhitelist(address account, bool whitelisted) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        
        _whitelistedAddresses[account] = whitelisted;
        emit WhitelistUpdated(account, whitelisted);
    }

    /**
     * @dev Updates the whitelist status for multiple addresses
     * @param accounts The addresses to update
     * @param whitelisted The new whitelist status for all addresses
     */
    function batchUpdateWhitelist(address[] calldata accounts, bool whitelisted) external onlyOwner {
        uint256 length = accounts.length;
        for (uint256 i = 0; i < length;) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            
            _whitelistedAddresses[accounts[i]] = whitelisted;
            emit WhitelistUpdated(accounts[i], whitelisted);
            
            unchecked { ++i; }
        }
    }

    // ============ View Functions ============

    function getETHCollected() external view returns (uint256) {
        return address(this).balance;
    }

    function getERC20Collected(address token) external view returns (uint256) {
        if (token == address(0)) revert ZeroAddress();
        return IERC20(token).balanceOf(address(this));
    }

    function isWhitelisted(address account) external view returns (bool) {
        return _whitelistedAddresses[account];
    }

    /**
     * @dev Calculates the tax amount for a given amount
     * @param amount The amount to calculate tax for
     * @return The tax amount
     */
    function calculateTax(uint256 amount) external view returns (uint256) {
        return _calculateTax(amount);
    }

    function getAmountAfterTax(uint256 amount) external view returns (uint256) {
        return _applyTax(amount);
    }

    // ============ Internal Functions ============

    function _checkWhitelisted(address account) internal view returns (bool) {
        return _whitelistedAddresses[account];
    }

    /**
     * @dev Internal function to calculate tax amount
     * @param amount The amount to calculate tax for
     * @return The tax amount
     */
    function _calculateTax(uint256 amount) internal view returns (uint256) {
        return (amount * taxRate) / 1e18;
    }

    /**
     * @dev Internal function to apply tax to an amount
     * @param amount The amount to apply tax to
     * @return The amount after tax deduction
     */
    function _applyTax(uint256 amount) internal view returns (uint256) {
        return amount - _calculateTax(amount);
    }

    // ============ Receive Function ============

    /**
     * @dev Allows the contract to receive ETH
     */
    receive() external payable {}
}