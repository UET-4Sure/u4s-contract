// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMEVArbitrage {
    /// @notice Emitted when MEV Hook is already initialized
    error AlreadyInitialized();

    /// @notice Emitted if tick spacing is correct on MEV Hook initialization
    error InvalidTickSpacing();

    /// @notice Emitted when pool has no liquidity to perform swap
    error TotalSupplyZero();

    /// @notice Emitted when operation require `openPool` executed by builder first
    error PoolNotOpen();

    /// @notice Emitted if msg.value is not passed as expected amount
    error InvalidMsgValue();

    /// @notice Emitted when user does only committer allowed operation
    error OnlyCommitter();

    /// @notice Emitted when committer wants to withdraw amount larger than available amount
    error WithdrawExceedsAvailable();

    /// @notice Emitted when failing to transfer native
    error NativeTransferFailed();
}
