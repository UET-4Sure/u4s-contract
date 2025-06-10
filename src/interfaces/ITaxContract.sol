// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITaxContract {
    /**
     * @dev Calculate the tax amount for a given amount
     * @param amount The amount to calculate tax for
     * @return The tax amount
     */
    function calculateTax(uint256 amount) external view returns (uint256);

    /**
     * @dev Get the amount after tax for a given amount
     * @param amount The amount to get the amount after tax for
     * @return The amount after tax
     */
    function getAmountAfterTax(uint256 amount) external view returns (uint256);
}