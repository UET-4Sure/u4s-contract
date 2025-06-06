// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IKYCContract {
    /**
        @dev check if the user is permit kyc
        @param amount the amount of the token
        @param token the token address
        @return true if the user is permit kyc, false otherwise
    */
    function isPermitKYC(uint256 amount, address token) external view returns (bool);

    /**
        @dev set restricted users
        @param users the users to set
        @param restricted the restricted status
    */
    function setRestrictedUsers(address[] calldata users, bool[] calldata restricted) external;

    /**
        @dev set restricted tokens
        @param tokens the tokens to set
        @param restricted the restricted status
    */
    function setRestrictedTokens(address[] calldata tokens, bool[] calldata restricted) external;
}