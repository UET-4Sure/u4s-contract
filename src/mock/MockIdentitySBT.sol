// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIdentitySBT} from "../interfaces/IIdentitySBT.sol";

contract MockIdentitySBT is IIdentitySBT {
    mapping(address => bool) private _hasToken;

    function mint(address to) external {
        _hasToken[to] = true;
    }

    function hasToken(address account) external view override returns (bool) {
        return _hasToken[account];
    }
} 