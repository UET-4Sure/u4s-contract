// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIdentitySBT} from "./interfaces/IIdentitySBT.sol";

/**
 * Only KYC'ed people can trade on the V4 hook'ed pool.
 */
contract KYCContract {
    IIdentitySBT public identitySBT;

    constructor(address _identitySBT) {
        identitySBT = IIdentitySBT(_identitySBT);
    }

    modifier onlyPermitKYC() {
        require(identitySBT.hasToken(tx.origin), "KYCContract: not permit kyc");
        _;
    }
}