// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIdentitySBT} from "./interfaces/IIdentitySBT.sol";
import {Config} from "../script/base/Config.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Oracle} from "./Oracle.sol";
import {console} from "forge-std/console.sol";

/**
 * @title KYCContract
 * @dev Manages KYC verification and volume restrictions for token transactions
 */
contract KYCContract is Config, Ownable {
    // State variables
    IIdentitySBT public immutable identitySBT;
    mapping(address => bool) private _restrictedUsers;
    mapping(address => bool) private _restrictedTokens;
    
    // Configurable volume limits
    uint256 public minVolume;
    uint256 public maxVolume;
    
    // Events
    event RestrictedUsersUpdated(address[] users, bool[] restricted);
    event RestrictedTokensUpdated(address[] tokens, bool[] restricted);
    event PriceFeedSet(address token, address priceFeed);
    event VolumeLimitsUpdated(uint256 minVolume, uint256 maxVolume);

    // Errors
    error PriceFeedNotSet();
    error InvalidInputLength();
    error Unauthorized();
    error InvalidVolumeLimits();

    constructor(
        address _identitySBT
    ) Ownable(msg.sender) {
        if (_identitySBT == address(0)) revert("Invalid identity SBT address");
        
        identitySBT = IIdentitySBT(_identitySBT);
        minVolume = 500 * 10**18;
        maxVolume = 10000 * 10**18;
    }

    /**
     * @dev Checks if a transaction is permitted based on KYC and volume restrictions
     * @param amount The amount of the token
     * @param token The token address
     * @return bool Whether the transaction is permitted
     */
    function isPermitKYC(uint256 amount, address token) public view returns (bool) {
        address priceFeed = priceFeeds[token];
        if (priceFeed == address(0)) revert PriceFeedNotSet();
        uint256 price = uint256(Oracle(priceFeed).getChainlinkDataFeedLatestAnswer());
        uint256 volume = amount * price;

        // Check restrictions
        if (_restrictedUsers[tx.origin] || _restrictedTokens[token]) {
            return false;
        }

        // Allow transactions below minimum volume
        if (volume <= minVolume) {
            return true;
        }

        // Reject transactions above maximum volume
        if (volume > maxVolume) {
            return false;
        }

        // For transactions between min and max volume, require KYC
        return identitySBT.hasToken(tx.origin);
    }

    /**
     * @dev Updates the volume limits
     * @param _minVolume New minimum volume
     * @param _maxVolume New maximum volume
     */
    function setVolumeLimits(uint256 _minVolume, uint256 _maxVolume) external onlyOwner {
        if (_minVolume >= _maxVolume) revert InvalidVolumeLimits();
        
        minVolume = _minVolume;
        maxVolume = _maxVolume;
        
        emit VolumeLimitsUpdated(_minVolume, _maxVolume);
    }

    /**
     * @dev Updates the restricted status of multiple users
     * @param users Array of user addresses
     * @param restricted Array of restricted statuses
     */
    function setRestrictedUsers(address[] calldata users, bool[] calldata restricted) external onlyOwner {
        if (users.length != restricted.length) revert InvalidInputLength();
        
        for (uint256 i = 0; i < users.length; i++) {
            _restrictedUsers[users[i]] = restricted[i];
        }
        
        emit RestrictedUsersUpdated(users, restricted);
    }

    /**
     * @dev Updates the restricted status of multiple tokens
     * @param tokens Array of token addresses
     * @param restricted Array of restricted statuses
     */
    function setRestrictedTokens(address[] calldata tokens, bool[] calldata restricted) external onlyOwner {
        if (tokens.length != restricted.length) revert InvalidInputLength();
        
        for (uint256 i = 0; i < tokens.length; i++) {
            _restrictedTokens[tokens[i]] = restricted[i];
        }
        
        emit RestrictedTokensUpdated(tokens, restricted);
    }

    /**
     * @dev Sets the price feed for a token (for testing purposes)
     * @param token The token address
     * @param priceFeed The price feed address
     */
    function setPriceFeed(address token, address priceFeed) external onlyOwner {
        if (token == address(0) || priceFeed == address(0)) revert("Invalid address");
        priceFeeds[token] = priceFeed;
        emit PriceFeedSet(token, priceFeed);
    }

    /**
     * @dev Checks if a user is restricted
     * @param user The user address
     * @return bool Whether the user is restricted
     */
    function isUserRestricted(address user) external view returns (bool) {
        return _restrictedUsers[user];
    }

    /**
     * @dev Checks if a token is restricted
     * @param token The token address
     * @return bool Whether the token is restricted
     */
    function isTokenRestricted(address token) external view returns (bool) {
        return _restrictedTokens[token];
    }
}