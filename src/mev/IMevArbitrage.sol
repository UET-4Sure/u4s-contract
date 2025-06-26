// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMEVArbitrage {
    /// @notice Revert when MEV Hook is already initialized
    error AlreadyInitialized();

    /// @notice Revert if tick spacing is correct on MEV Hook initialization
    error InvalidTickSpacing();

    /// @notice Revert when pool has no liquidity to perform swap
    error TotalSupplyZero();

    /// @notice Revert when operation require `openPool` executed by builder first
    error PoolNotOpen();

    /// @notice Revert if msg.value is not passed as expected amount
    error InvalidMsgValue();

    /// @notice Revert when user does only committer allowed operation
    error OnlyCommitter();

    /// @notice Revert when committer wants to withdraw amount larger than available amount
    error WithdrawExceedsAvailable();

    /// @notice Revert when failing to transfer native
    error NativeTransferFailed();

    /// @notice Revert if pool is already opened (in arbitrage call)
    error PoolAlreadyOpened();

    /// @notice Revert if invalid currency delta
    error InvalidCurrencyDelta();

    /// @notice Revert if price is go out of bound
    error PriceOutOfBounds();

    /// @notice Revert if there is not any liquidity to perform swap / arbitrage
    error LiquidityZero();

    /// @notice Revert if arbitrage size is too small
    error ArbTooSmall();

    /// @notice Revert if user mints 0 liquidity
    error MintZero();

    /// @notice Revert if user burn 0 liquidty
    error BurnZero();

    /// @notice Revert if amounts to burn exceed supply
    error BurnExceedsSupply();

    /// @notice Revert if hedge committed is not enough
    error InsufficientHedgeCommitted();

    /// @notice Revert if user modify liquidity through pool manager
    error OnlyModifyViaHook();

    /// @notice Revert if wrong poolkey
    error WrongPoolKey();
}
