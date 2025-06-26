// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract NonReentrant {
    error Locked();

    /// bytes32(uint256(keccak256("u4s.reentrancy.slot")) - 1)
    bytes32 public constant REENTRANCY_SLOT = 0x5fcf4be461d3147bb69e7426d02feccb70e05316ffd8ddef41008407a8e69540;

    modifier _nonReentrant() {
        assembly {
            let locked := tload(REENTRANCY_SLOT)
            if eq(locked, 1) {
                mstore(0x00, 0x0f2e5b6c)
                revert(0x00, 0x04)
            }
            tstore(REENTRANCY_SLOT, 1)
        }
        _;
        assembly {
            tstore(REENTRANCY_SLOT, 0)
        }
    }
}
