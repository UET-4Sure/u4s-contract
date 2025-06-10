// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/// @notice Shared configuration between scripts
contract Config {
    mapping(address => address) public priceFeeds;

    // TOKEN ADDRESS
    address constant USDC = address(0x0ff5065E79c051c3D4C790BC9e8ebc9b4E56bbcc);
    address constant WETH = address(0x342d6127609A5Ad63C93E10cb73b7d9dE9bC43Aa);
    address constant WBTC = address(0x12Df3798C30532c068306372d24c9f2f451676e9);
    address constant LINK = address(0x88B42E9E9E769F86ab499D8cb111fcb6f691F70E);
    address constant EUR = address(0x336d87aEdF99d5Fb4F07132C8DbE4bea4c766eAc);

    // CURRENCY
    Currency constant usdc = Currency.wrap(USDC);
    Currency constant weth = Currency.wrap(WETH);
    Currency constant wbtc = Currency.wrap(WBTC);
    Currency constant link = Currency.wrap(LINK);
    Currency constant eur = Currency.wrap(EUR);

    // PRICE FEED ADDRESS
    address public constant USDC_PRICE_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address public constant WETH_PRICE_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address public constant WBTC_PRICE_FEED = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    address public constant LINK_PRICE_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
    address public constant EUR_PRICE_FEED = 0x1a81afB8146aeFfCFc5E50e8479e826E7D55b910;

    // IDENTITY SBT ADDRESS
    address constant IDENTITY_SBT = address(0xb117d1c006fC208FEAFFE5E08529BE5de8235B73);

    // KYC Contract
    address constant KYC_CONTRACT = address(0xa496e8d38896EA779BAf5c4B6B5E5389513A67a3);

    // TAX CONTRACT
    address constant TAX_CONTRACT = address(0x0000000000000000000000000000000000000000);

    // MAIN HOOK ADDRESS
    address constant MAIN_HOOK = address(0xF1B65Ab2a975D3796bEb9d3Ea8786dEE235F0a80);

    // IHooks
    IHooks constant hookContract = IHooks(MAIN_HOOK);

    // TOKEN & CURRENCY for pool
    IERC20 constant token0 = IERC20(USDC);
    IERC20 constant token1 = IERC20(WETH);
    Currency constant currency0 = usdc;
    Currency constant currency1 = weth;

    constructor() {
        priceFeeds[USDC] = USDC_PRICE_FEED;
        priceFeeds[WETH] = WETH_PRICE_FEED;
        priceFeeds[WBTC] = WBTC_PRICE_FEED;
        priceFeeds[LINK] = LINK_PRICE_FEED;
        priceFeeds[EUR] = EUR_PRICE_FEED;
    }
}
