// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/// @notice Shared configuration between scripts
contract Config {

    // TOKEN ADDRESS
    IERC20 constant USDC = IERC20(address(0x7cE3f087D7C5c215cFe817dB8aCb5d72a99F24D4));
    IERC20 constant WETH = IERC20(address(0xc45dDDe92509308b0E22d2a87B3E04e5fdf6f397));
    IERC20 constant WBTC = IERC20(address(0x3d2E50ED0bd344dAA1FE4779099F65f05f93960c));
    IERC20 constant LINK = IERC20(address(0x8ff8Ac069AdB98c0385F15e0390D71e40612C615));
    IERC20 constant EUR = IERC20(address(0x68197D8f47D7ABD3E2307Bf0f7707213Fc416c52));

    // CURRENCY
    Currency constant usdc = Currency.wrap(address(USDC));
    Currency constant weth = Currency.wrap(address(WETH));
    Currency constant wbtc = Currency.wrap(address(WBTC));
    Currency constant link = Currency.wrap(address(LINK));
    Currency constant eur = Currency.wrap(address(EUR));

    // PRICE FEED ADDRESS
    address public constant USDC_PRICE_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address public constant WETH_PRICE_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address public constant WBTC_PRICE_FEED = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    address public constant LINK_PRICE_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
    address public constant EUR_PRICE_FEED = 0x1a81afB8146aeFfCFc5E50e8479e826E7D55b910;

    // KYC Hook contract address
    IHooks constant hookContract = IHooks(address(0x84e78baD6d5AdC5dF0b6438a36bCE8Dd97b8CA80));
}
