// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IMEVArbitrage} from "./IMevArbitrage.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MEVArbitrage is BaseHook, ERC20, IMEVArbitrage, IUnlockCallback {
    using TickMath for int24;

    using SafeERC20 for ERC20;

    uint24 internal constant _PIPS = 1000000;

    int24 public immutable lowerTick;
    int24 public immutable upperTick;
    int24 public immutable tickSpacing;
    uint24 public immutable baseBeta; // % expressed as uint < 1e6
    uint24 public immutable decayRate; // % expressed as uint < 1e6
    uint24 public immutable vaultRedepositRate; // % expressed as uint < 1e6

    /// @dev these could be TRANSIENT STORAGE eventually
    uint256 internal _a0;
    uint256 internal _a1;
    /// ----------

    uint256 public lastBlockOpened;
    uint256 public lastBlockReset;
    uint256 public hedgeRequired0;
    uint256 public hedgeRequired1;
    uint256 public hedgeCommitted0;
    uint256 public hedgeCommitted1;
    uint160 public committedSqrtPriceX96;
    PoolKey public poolKey;
    address public committer;
    bool public initialized;

    mapping(address => bool) private blockedBuilders;

    enum ActionType {
        MINT,
        BURN,
        ARB_SWAP
    }

    struct PoolManagerCalldata {
        uint256 amount;
        /// mintAmount | burnAmount | newSqrtPriceX96 (inferred from actionType)
        address msgSender;
        address receiver;
        ActionType actionType;
    }
    /// 0 = mint | 1 = burn | 2 = arbSwap

    constructor(
        IPoolManager _poolManager,
        int24 _tickSpacing,
        uint24 _baseBeta,
        uint24 _decayRate,
        uint24 _vaultRedepositRate
    ) BaseHook(_poolManager) ERC20("U4S LP Token", "U4S-LP") {
        tickSpacing = _tickSpacing;
        lowerTick = _tickSpacing.minUsableTick();
        upperTick = _tickSpacing.maxUsableTick();

        require(_baseBeta < _PIPS && _decayRate <= _baseBeta && _vaultRedepositRate < _PIPS);

        baseBeta = _baseBeta;
        decayRate = _decayRate;
        vaultRedepositRate = _vaultRedepositRate;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _initialize(PoolKey memory _poolKey, uint160 _newSqrtPriceX96) internal {
        if (initialized) revert AlreadyInitialized();
        if (_poolKey.tickSpacing != tickSpacing) revert InvalidTickSpacing();

        /// initialize state variable
        poolKey = _poolKey;
        lastBlockOpened = block.number - 1;
        lastBlockReset = block.number;
        committedSqrtPriceX96 = _newSqrtPriceX96;
        initialized = true;
    }

    function openPool(uint160 _newSqrtPriceX96) external {
        // Pool has no liquidity
        if (totalSupply() == 0) {
            revert TotalSupplyZero();
        }

        bytes memory data = abi.encode(
            PoolManagerCalldata({
                amount: _newSqrtPriceX96,
                msgSender: msg.sender,
                receiver: msg.sender,
                actionType: ActionType.ARB_SWAP
            })
        );

        poolManager.unlock(data);

        committer = msg.sender;
        committedSqrtPriceX96 = _newSqrtPriceX96;
        lastBlockOpened = block.number;
    }

    function depositHedgeCommitment(uint256 amount0, uint256 amount1) external payable {
        if (lastBlockOpened != block.number) {
            revert PoolNotOpen();
        }

        if (amount0 > 0) {
            _transferToHook(msg.sender, Currency.unwrap(poolKey.currency0), amount0);
            hedgeCommitted0 += amount0;
        }

        if (amount1 > 0) {
            _transferToHook(msg.sender, Currency.unwrap(poolKey.currency1), amount1);
            hedgeCommitted1 += amount1;
        }
    }

    function withdrawHedgeCommitment(uint256 amount0, uint256 amount1) external {
        if (committer != msg.sender) {
            revert OnlyCommitter();
        }

        if (amount0 > 0) {
            uint256 withdrawAvailable0 = hedgeRequired0 > 0 ? hedgeCommitted0 - hedgeRequired0 : hedgeCommitted0;
            if (amount0 > withdrawAvailable0) revert WithdrawExceedsAvailable();
            hedgeCommitted0 -= amount0;
            _transferToExternal(msg.sender, Currency.unwrap(poolKey.currency0), amount0);
        }

        if (amount1 > 0) {
            uint256 withdrawAvailable1 = hedgeRequired1 > 0 ? hedgeCommitted1 - hedgeRequired1 : hedgeCommitted1;

            if (amount1 > withdrawAvailable1) revert WithdrawExceedsAvailable();
            hedgeCommitted1 -= amount1;
            _transferToExternal(msg.sender, Currency.unwrap(poolKey.currency1), amount1);
        }
    }

    function unlockCallback(bytes memory _data) external override onlyPoolManager returns (bytes memory) {
        PoolManagerCalldata memory pmCalldata = abi.decode(_data, (PoolManagerCalldata));

        if (pmCalldata.actionType == ActionType.ARB_SWAP) _lockAcquiredArb(pmCalldata);
        if (pmCalldata.actionType == ActionType.MINT) _lockAcquiredMint(pmCalldata);
        if (pmCalldata.actionType == ActionType.BURN) _lockAcquiredBurn(pmCalldata);
    }

    function _lockAcquiredArb(PoolManagerCalldata memory pmCalldata) internal {}

    function _lockAcquiredMint(PoolManagerCalldata memory pmCalldata) internal {}

    function _lockAcquiredBurn(PoolManagerCalldata memory pmCalldata) internal {}

    function _transferToHook(address _from, address _token, uint256 _amount) internal {
        if (_token == address(0)) {
            if (msg.value != _amount) revert InvalidMsgValue();
        } else {
            ERC20(_token).safeTransferFrom(_from, address(this), _amount);
        }
    }

    function _transferToExternal(address _to, address _token, uint256 _amount) internal {
        if (_token == address(0)) {
            bool success;
            assembly {
                success := call(gas(), _to, _amount, 0, 0, 0, 0)
            }

            if (!success) revert NativeTransferFailed();
        } else {
            ERC20(_token).safeTransfer(_to, _amount);
        }
    }
}
