// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockOracle {
    int256 private _price;

    function setPrice(int256 price) external {
        _price = price;
    }

    function getChainlinkDataFeedLatestAnswer() external view returns (int256) {
        return _price;
    }
} 