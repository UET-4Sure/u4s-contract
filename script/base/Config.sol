// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/// @notice Shared configuration between scripts
contract Config {

    // TOKEN ADDRESS
    IERC20 constant USDC = IERC20(address(0x0ff5065E79c051c3D4C790BC9e8ebc9b4E56bbcc));
    IERC20 constant WETH = IERC20(address(0x342d6127609A5Ad63C93E10cb73b7d9dE9bC43Aa));
    IERC20 constant WBTC = IERC20(address(0x12Df3798C30532c068306372d24c9f2f451676e9));
    IERC20 constant LINK = IERC20(address(0x88B42E9E9E769F86ab499D8cb111fcb6f691F70E));
    IERC20 constant EUR = IERC20(address(0x336d87aEdF99d5Fb4F07132C8DbE4bea4c766eAc));

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

    // IDENTITY SBT ADDRESS
    address constant IDENTITY_SBT = address(0xb117d1c006fC208FEAFFE5E08529BE5de8235B73);

    // KYC Hook contract address
    IHooks constant hookContract = IHooks(address(0x43C5d270ea5C0D4c509747578486F977CFC50a80));

    // TOKEN & CURRENCY for pool
    IERC20 constant token0 = USDC;
    IERC20 constant token1 = WETH;
    Currency constant currency0 = usdc;
    Currency constant currency1 = weth;
}
