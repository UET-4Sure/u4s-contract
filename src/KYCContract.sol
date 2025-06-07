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
    uint256 public minVolumeSwap;
    uint256 public maxVolumeSwap;
    uint256 public minVolumeModifyLiquidity;
    uint256 public maxVolumeModifyLiquidity;
    
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
        minVolumeSwap = 500 * 10**18;
        maxVolumeSwap = 10000 * 10**18;
        minVolumeModifyLiquidity = 500 * 10**18;
        maxVolumeModifyLiquidity = 1000000 * 10**18;
    }

    /**
     * @dev Checks if a transaction is permitted based on KYC and volume restrictions
     * @param amount The amount of the token
     * @param token The token address
     * @return bool Whether the transaction is permitted
     */
    function isPermitKYCSwap(uint256 amount, address token) public view returns (bool) {
        // Check restrictions
        if (_restrictedUsers[tx.origin] || _restrictedTokens[token]) {
            return false;
        }

        address priceFeed = priceFeeds[token];
        if (priceFeed == address(0)) revert PriceFeedNotSet();
        uint256 price = uint256(Oracle(priceFeed).getChainlinkDataFeedLatestAnswer());
        uint256 volume = amount * price;        

        // Allow transactions below minimum volume
        if (volume <= minVolumeSwap) {
            return true;
        }

        // Reject transactions above maximum volume
        if (volume > maxVolumeSwap) {
            return false;
        }

        // For transactions between min and max volume, require KYC
        return identitySBT.hasToken(tx.origin);
    }

    /**
     * @dev Checks if a modify liquidity transaction is permitted based on KYC and volume restrictions
     * @param amount0 The amount of token0
     * @param token0 The token0 address
     * @param amount1 The amount of token1
     * @param token1 The token1 address
     * @return bool Whether the transaction is permitted
     */
    function isPermitKYCModifyLiquidity(
        uint256 amount0, 
        address token0, 
        uint256 amount1, 
        address token1
    ) public view returns (bool) {
        // Check restrictions
        if (_restrictedUsers[tx.origin] || _restrictedTokens[token0] || _restrictedTokens[token1]) {
            return false;
        }

        address priceFeed0 = priceFeeds[token0];
        address priceFeed1 = priceFeeds[token1];
        if (priceFeed0 == address(0) || priceFeed1 == address(0)) revert PriceFeedNotSet();
        uint256 price0 = uint256(Oracle(priceFeed0).getChainlinkDataFeedLatestAnswer());
        uint256 price1 = uint256(Oracle(priceFeed1).getChainlinkDataFeedLatestAnswer());
        uint256 totalVolume = amount0 * price0 + amount1 * price1;

        if(totalVolume <= minVolumeModifyLiquidity) {
            return true;
        }

        if(totalVolume > maxVolumeModifyLiquidity) {
            return false;
        }

        return identitySBT.hasToken(tx.origin);
    }

    /**
     * @dev Updates the volume limits
     * @param _minVolume New minimum volume
     * @param _maxVolume New maximum volume
     */
    function setVolumeLimitsSwap(uint256 _minVolume, uint256 _maxVolume) external onlyOwner {
        if (_minVolume >= _maxVolume) revert InvalidVolumeLimits();
        
        minVolumeSwap = _minVolume;
        maxVolumeSwap = _maxVolume;
        
        emit VolumeLimitsUpdated(_minVolume, _maxVolume);
    }

    /**
     * @dev Updates the volume limits for modify liquidity
     * @param _minVolume New minimum volume
     * @param _maxVolume New maximum volume
     */
    function setVolumeLimitsModifyLiquidity(uint256 _minVolume, uint256 _maxVolume) external onlyOwner {
        if (_minVolume >= _maxVolume) revert InvalidVolumeLimits();
        
        minVolumeModifyLiquidity = _minVolume;
        maxVolumeModifyLiquidity = _maxVolume;
        
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