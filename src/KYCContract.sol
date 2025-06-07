// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIdentitySBT} from "./interfaces/IIdentitySBT.sol";
import {Config} from "../script/base/Config.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Oracle} from "./Oracle.sol";
import {console} from "forge-std/console.sol";

contract KYCContract is Config, Ownable {
    IIdentitySBT public identitySBT;
    mapping(address => bool) restrictedUsers;
    mapping(address => bool) restrictedTokens;
    
    uint256 public MIN_VOLUME = 500 * 10 ** 18; // 500 USD
    uint256 public MAX_VOLUME = 10000 * 10 ** 18; // 10000 USD

    constructor(address _identitySBT) Ownable(msg.sender) {
        identitySBT = IIdentitySBT(_identitySBT);
    }

    /**
        @dev check if the user is permit kyc
        @param amount the amount of the token
        @param token the token address
    */
    function isPermitKYC(uint256 amount, address token) public view returns (bool) {
        if(priceFeeds[token] == address(0)) {
            revert("KYCContract: price feed not set");
        }

        Oracle oracle = Oracle(priceFeeds[token]);
        uint256 price = uint256(oracle.getChainlinkDataFeedLatestAnswer());
        uint256 volume = amount * price;

        // if the user is restricted, return false
        if(restrictedUsers[tx.origin] || restrictedTokens[token]) {
            return false;
        }

        // if the volume is less than 500 USD, return true
        if(volume <= MIN_VOLUME) {
            return true;
        }

        // if the volume is greater than 10000 USD, return false
        if(volume > MAX_VOLUME) {
            return false;
        }

        // if the user is kyc, return true
        if(identitySBT.hasToken(tx.origin)) {
            return true;
        }

        return false;
    }

    /**
        @dev set restricted users
        @param users the users to set
        @param restricted the restricted status
    */
    function setRestrictedUsers(address[] calldata users, bool[] calldata restricted) public onlyOwner {
        for(uint256 i = 0; i < users.length; i++) {
            restrictedUsers[users[i]] = restricted[i];
        }
    }

    /**
        @dev set restricted tokens
        @param tokens the tokens to set
        @param restricted the restricted status
    */
    function setRestrictedTokens(address[] calldata tokens, bool[] calldata restricted) public onlyOwner {
        for(uint256 i = 0; i < tokens.length; i++) {
            restrictedTokens[tokens[i]] = restricted[i];
        }
    }   

    /**
        @dev set min volume
        @param minVolume the min volume
    */
    function setMinVolume(uint256 minVolume) public onlyOwner {
        MIN_VOLUME = minVolume;
    }

    /**
        @dev set max volume
        @param maxVolume the max volume
    */
    function setMaxVolume(uint256 maxVolume) public onlyOwner {
        MAX_VOLUME = maxVolume;
    }


    //////////////////////////////
    // HELPER TESTING FUNCTIONS //
    //////////////////////////////

    /**
        @dev set price feed for a token (ONLY FOR TESTING)
        @param token the token address
        @param priceFeed the price feed address
    */
    function setPriceFeed(address token, address priceFeed) public onlyOwner {
        priceFeeds[token] = priceFeed;
    }
}