// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

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
    address constant IDENTITY_SBT = address(0xF555752b80FD128421730B540d2D63542C9221F6);

    // KYC Contract
    address constant KYC_CONTRACT = address(0xa3AE13adF3DA4d1AD819EF2cF8C3F5D0a0E6A2F0);

    // TAX PERCENTAGE
    uint256 constant TAX_PERCENTAGE = 1e15;

    // TAX CONTRACT
    address constant TAX_CONTRACT = address(0x4fA6a8e870f38308dFCB9320dfaE80ec6dD57B09);

    // MAIN HOOK ADDRESS
    address constant MAIN_HOOK = address(0x37fD86A65078c7C1e94c867165d2ff6328F54ac8);

    // IHooks
    IHooks constant hookContract = IHooks(MAIN_HOOK);

    // TOKEN & CURRENCY for pool
    IERC20 constant token0 = IERC20(EUR);
    IERC20 constant token1 = IERC20(LINK);
    Currency constant currency0 = eur;
    Currency constant currency1 = link;

    /*
        CURRENT POOLS:
        USDC - WETH
        USDC - WBTC
        USDC - LINK
        USDC - EUR
        WBTC - WETH
        WETH - LINK
        EUR - WETH
        WBTC - LINK
        WBTC - EUR
        EUR - LINK
    */

    constructor() {
        priceFeeds[USDC] = USDC_PRICE_FEED;
        priceFeeds[WETH] = WETH_PRICE_FEED;
        priceFeeds[WBTC] = WBTC_PRICE_FEED;
        priceFeeds[LINK] = LINK_PRICE_FEED;
        priceFeeds[EUR] = EUR_PRICE_FEED;
    }
}
