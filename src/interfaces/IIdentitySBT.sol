// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IIdentitySBT {
    /**
     * @dev Check whether a given address has a valid identity SBT
     *     @param _addr Address to check for tokens
     *     @return valid Whether the address has a valid token
     */
    function hasToken(address _addr) external view returns (bool valid);
}
