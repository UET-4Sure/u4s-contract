// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/// @notice Shared configuration between scripts
contract Config {
    /// @dev populated with default anvil addresses
    // IERC20 constant token0 = IERC20(address(0x0165878A594ca255338adfa4d48449f69242Eb8F));
    // IERC20 constant token1 = IERC20(address(0xa513E6E4b8f2a923D98304ec87F64353C4D5C853));

    // WBTC & WETH Sepolia network
    IERC20 constant token0 = IERC20(address(0x099b46d437014D6f234169654A73f4FB56faD10A));
    IERC20 constant token1 = IERC20(address(0x27D3Fd7B857cdc5CCA5C1898C12f09Ea9F8C8D37));
    // KYC Hook contract address
    IHooks constant hookContract = IHooks(address(0x84e78baD6d5AdC5dF0b6438a36bCE8Dd97b8CA80));

    Currency constant currency0 = Currency.wrap(address(token0));
    Currency constant currency1 = Currency.wrap(address(token1));
}
