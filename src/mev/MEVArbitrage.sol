// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IMEVArbitrage} from "./IMevArbitrage.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {CurrencySettler} from "src/helper/CurrencySettler.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {LiquidityAmounts} from "src/helper/LiquidityAmounts.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import {NonReentrant} from "src/helper/NonReentrant.sol";
import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MEVArbitrage is BaseHook, ERC20, NonReentrant, IMEVArbitrage, IUnlockCallback {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using TickMath for int24;
    using Pool for Pool.State;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using CurrencySettler for Currency;

    using SafeERC20 for ERC20;

    uint24 internal constant _PIPS = 1000000;

    int24 public immutable lowerTick;
    int24 public immutable upperTick;
    uint160 public immutable sqrtPriceX96Lower;
    uint160 public immutable sqrtPriceX96Upper;
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

    struct ArbSwapParams {
        uint160 sqrtPriceX96;
        uint160 newSqrtPriceX96;
        uint160 sqrtPriceX96Lower;
        uint160 sqrtPriceX96Upper;
        uint128 liquidity;
        uint24 betaFactor;
    }

    modifier _checkPoolKey(PoolKey calldata _poolKey) {
        if (PoolId.unwrap(_poolKey.toId()) != PoolId.unwrap(poolKey.toId())) {
            revert WrongPoolKey();
        }
        _;
    }

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
        sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(lowerTick);
        sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(upperTick);

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

    function _beforeInitialize(address, PoolKey calldata _poolKey, uint160 sqrtPriceX96)
        internal
        override
        returns (bytes4)
    {
        _initialize(_poolKey, sqrtPriceX96);
        return this.beforeInitialize.selector;
    }

    function _beforeSwap(address sender, PoolKey calldata _poolKey, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        view
        override
        _checkPoolKey(_poolKey)
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        /// if swap is coming from the hook then its a 1 wei swap to kick the price and not a "normal" swap
        if (sender != address(this)) {
            /// disallow normal swaps at top of block
            if (lastBlockOpened != block.number) revert PoolNotOpen();
        }
        if (PoolId.unwrap(_poolKey.toId()) != PoolId.unwrap(poolKey.toId())) {
            revert WrongPoolKey();
        }
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata _poolKey,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override _checkPoolKey(_poolKey) returns (bytes4, int128) {
        /// if swap is coming from the hook then its a 1 wei swap to kick the price and not a "normal" swap
        if (sender != address(this)) {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(PoolIdLibrary.toId(poolKey));
            if (sqrtPriceX96 >= sqrtPriceX96Upper || sqrtPriceX96 <= sqrtPriceX96Lower) revert PriceOutOfBounds();

            (uint128 curLiquidity,,) =
                poolManager.getPositionInfo(poolKey.toId(), address(this), lowerTick, upperTick, bytes32(0));
            (uint256 current0, uint256 current1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96, sqrtPriceX96Lower, sqrtPriceX96Upper, curLiquidity
            );

            (uint256 need0, uint256 need1) = LiquidityAmounts.getAmountsForLiquidity(
                committedSqrtPriceX96, sqrtPriceX96Lower, sqrtPriceX96Upper, curLiquidity
            );

            if (need0 > current0) {
                uint256 min0 = need0 - current0;
                if (min0 > hedgeCommitted0) revert InsufficientHedgeCommitted();
                hedgeRequired0 = min0;
                hedgeRequired1 = 0;
            } else if (need1 > current1) {
                uint256 min1 = need1 - current1;
                if (min1 > hedgeCommitted1) revert InsufficientHedgeCommitted();
                hedgeRequired1 = min1;
                hedgeRequired0 = 0;
            } else {
                hedgeRequired0 = 0;
                hedgeRequired1 = 0;
            }
        }

        return (this.afterSwap.selector, 0);
    }

    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata _poolKey,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal view override _checkPoolKey(_poolKey) returns (bytes4) {
        /// force LPs to provide liquidity through hook
        if (sender != address(this)) revert OnlyModifyViaHook();
        return this.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata _poolKey,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal view override _checkPoolKey(_poolKey) returns (bytes4) {
        /// force LPs to remove liquidity through hook
        if (sender != address(this)) revert OnlyModifyViaHook();
        return this.beforeRemoveLiquidity.selector;
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

    function mint(uint256 _mintAmount, address _receiver)
        external
        payable
        _nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (_mintAmount == 0) revert MintZero();

        /// encode calldata to pass through lock()
        bytes memory data = abi.encode(
            PoolManagerCalldata({
                amount: _mintAmount,
                msgSender: msg.sender,
                receiver: _receiver,
                actionType: ActionType.MINT
            })
        );
        /// state variables to be able to bubble up amount0 and amount1 as return args
        _a0 = _a1 = 0;

        /// begin pool actions (passing data through lock() into _lockAcquiredMint())
        poolManager.unlock(data);

        /// handle eth refunds
        if (poolKey.currency0.isAddressZero()) {
            uint256 leftover = address(this).balance - hedgeCommitted0;
            if (leftover > 0) _nativeTransfer(msg.sender, leftover);
        }
        if (poolKey.currency1.isAddressZero()) {
            uint256 leftover = address(this).balance - hedgeCommitted1;
            if (leftover > 0) _nativeTransfer(msg.sender, leftover);
        }

        /// set return arguments (stored during lock callback)
        amount0 = _a0;
        amount1 = _a1;

        /// remit ERC20 liquidity shares to target receiver
        _mint(_receiver, _mintAmount);
    }

    function burn(uint256 burnAmount_, address receiver_)
        external
        _nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (burnAmount_ == 0) revert BurnZero();
        if (totalSupply() < burnAmount_) revert BurnExceedsSupply();

        /// encode calldata to pass through lock()
        bytes memory data = abi.encode(
            PoolManagerCalldata({
                amount: burnAmount_,
                msgSender: msg.sender,
                receiver: receiver_,
                actionType: ActionType.BURN
            })
        );

        /// state variables to be able to bubble up amount0 and amount1 as return args
        _a0 = _a1 = 0;

        /// begin pool actions (passing data through lock() into _lockAcquiredBurn())
        poolManager.unlock(data);

        /// set return arguments (stored during lock callback)
        amount0 = _a0;
        amount1 = _a1;

        /// burn ERC20 LP shares of the caller
        _burn(msg.sender, burnAmount_);
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

    function withdrawHedgeCommitment(uint256 amount0, uint256 amount1) external _nonReentrant {
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

    function _lockAcquiredArb(PoolManagerCalldata memory pmCalldata) internal {
        // find block delta to compute beta
        uint256 blockDelta = _checkLastOpen();

        // push price back to previous committed price + vault re-deposit
        (uint160 sqrtPriceX96Real, uint160 sqrtPriceX96Virtual, uint128 liquidityReal, uint128 liquidityVirtual) =
            _resetLiquidity(false);

        uint160 newSqrtPriceX96 = SafeCast.toUint160(pmCalldata.amount);

        /// compute swap amounts, swap direction, and amount of liquidity to mint
        {
            (uint256 swap0, uint256 swap1) = _getArbSwap(
                ArbSwapParams({
                    sqrtPriceX96: sqrtPriceX96Virtual,
                    newSqrtPriceX96: newSqrtPriceX96,
                    sqrtPriceX96Lower: sqrtPriceX96Lower,
                    sqrtPriceX96Upper: sqrtPriceX96Upper,
                    liquidity: liquidityVirtual,
                    betaFactor: _getBeta(blockDelta)
                })
            );

            /// burn all liquidity
            if (liquidityReal > 0) {
                poolManager.modifyLiquidity(
                    poolKey,
                    IPoolManager.ModifyLiquidityParams({
                        liquidityDelta: -SafeCast.toInt256(uint256(liquidityReal)),
                        tickLower: lowerTick,
                        tickUpper: upperTick,
                        salt: bytes32(0)
                    }),
                    ""
                );
                _clear6909Balances();
            }

            /// swap 1 wei in zero liquidity to kick the price to newSqrtPriceX96
            bool zeroForOne = newSqrtPriceX96 < sqrtPriceX96Virtual;
            if (newSqrtPriceX96 != sqrtPriceX96Real) {
                poolManager.swap(
                    poolKey,
                    IPoolManager.SwapParams({
                        zeroForOne: newSqrtPriceX96 < sqrtPriceX96Real,
                        amountSpecified: 1,
                        sqrtPriceLimitX96: newSqrtPriceX96
                    }),
                    ""
                );
            }

            /// handle swap transfers (send to / transferFrom arber)
            if (zeroForOne) {
                poolKey.currency0.settle(poolManager, pmCalldata.msgSender, swap0, false);
                poolKey.currency1.take(poolManager, pmCalldata.receiver, swap1, false);
            } else {
                poolKey.currency1.settle(poolManager, pmCalldata.msgSender, swap1, false);
                poolKey.currency0.take(poolManager, pmCalldata.receiver, swap0, false);
            }
        }

        (uint256 totalHoldings0, uint256 totalHoldings1) = _checkCurrencyBalances();

        uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            newSqrtPriceX96, sqrtPriceX96Lower, sqrtPriceX96Upper, totalHoldings0, totalHoldings1
        );

        /// mint new liquidity around newSqrtPriceX96
        poolManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                liquidityDelta: SafeCast.toInt256(uint256(newLiquidity)),
                tickLower: lowerTick,
                tickUpper: upperTick,
                salt: bytes32(0)
            }),
            ""
        );

        /// if any positive balances remain in PoolManager after all operations, mint erc1155 shares
        _mintLeftover();
    }

    function _lockAcquiredMint(PoolManagerCalldata memory pmCalldata) internal {
        uint256 totalSupply = totalSupply();

        if (totalSupply == 0) {
            poolManager.modifyLiquidity(
                poolKey,
                IPoolManager.ModifyLiquidityParams({
                    liquidityDelta: SafeCast.toInt256(pmCalldata.amount),
                    tickLower: lowerTick,
                    tickUpper: upperTick,
                    salt: bytes32(0)
                }),
                ""
            );

            // casting to uint256 is ok for minting
            _a0 = SafeCast.toUint256(poolManager.currencyDelta(address(this), poolKey.currency0));
            _a1 = SafeCast.toUint256(poolManager.currencyDelta(address(this), poolKey.currency1));
            if (_a0 > 0) {
                poolKey.currency0.settle(poolManager, pmCalldata.msgSender, _a0, false);
            }
            if (_a1 > 0) {
                poolKey.currency1.settle(poolManager, pmCalldata.msgSender, _a1, false);
            }
        } else {
            uint128 liquidity;
            /// if this is first touch in this block, then we need to _resetLiquidity() first
            if (lastBlockOpened != block.number) {
                (,, liquidity,) = _resetLiquidity(true);
            } else {
                (liquidity,,) = poolManager.getPositionInfo(
                    PoolIdLibrary.toId(poolKey), address(this), lowerTick, upperTick, bytes32(0)
                );
            }

            if (liquidity > 0) {
                poolManager.modifyLiquidity(
                    poolKey,
                    IPoolManager.ModifyLiquidityParams({
                        liquidityDelta: -SafeCast.toInt256(uint256(liquidity)),
                        tickLower: lowerTick,
                        tickUpper: upperTick,
                        salt: bytes32(0)
                    }),
                    ""
                );
            }

            _checkCurrencyBalances();

            (, uint256 leftOver0,, uint256 leftOver1) = _get6909Balances();

            // mint back the position.
            uint256 newLiquidity = liquidity + FullMath.mulDiv(pmCalldata.amount, liquidity, totalSupply);

            if (newLiquidity > 0) {
                poolManager.modifyLiquidity(
                    poolKey,
                    IPoolManager.ModifyLiquidityParams({
                        liquidityDelta: SafeCast.toInt256(newLiquidity),
                        tickLower: lowerTick,
                        tickUpper: upperTick,
                        salt: bytes32(0)
                    }),
                    ""
                );
            }

            uint256 amount0 = SafeCast.toUint256(poolManager.currencyDelta(address(this), poolKey.currency0));
            uint256 amount1 = SafeCast.toUint256(poolManager.currencyDelta(address(this), poolKey.currency1));

            amount0 += FullMath.mulDivRoundingUp(leftOver0, pmCalldata.amount, totalSupply);
            amount1 += FullMath.mulDivRoundingUp(leftOver1, pmCalldata.amount, totalSupply);

            if (amount0 > 0) {
                poolKey.currency0.settle(poolManager, pmCalldata.msgSender, amount0, false);
            }

            if (amount1 > 0) {
                poolKey.currency1.settle(poolManager, pmCalldata.msgSender, amount1, false);
            }

            _a0 = amount0;
            _a1 = amount1;
        }
        _mintLeftover();

        if (hedgeRequired0 > 0) {
            hedgeRequired0 += FullMath.mulDiv(hedgeRequired0, pmCalldata.amount, totalSupply);
        }
        if (hedgeRequired1 > 0) {
            hedgeRequired1 += FullMath.mulDiv(hedgeRequired1, pmCalldata.amount, totalSupply);
        }

        if (hedgeRequired0 > hedgeCommitted0 || hedgeRequired1 > hedgeCommitted1) revert InsufficientHedgeCommitted();
    }

    function _lockAcquiredBurn(PoolManagerCalldata memory pmCalldata) internal {
        /// burn everything, positions and erc1155
        uint256 totalSupply = totalSupply();

        uint128 liquidity;
        /// if this is first touch in this block, then we need to _resetLiquidity() first
        if (lastBlockOpened != block.number) {
            (,, liquidity,) = _resetLiquidity(true);
        } else {
            (liquidity,,) = poolManager.getPositionInfo(
                PoolIdLibrary.toId(poolKey), address(this), lowerTick, upperTick, bytes32(0)
            );
        }

        if (liquidity > 0) {
            poolManager.modifyLiquidity(
                poolKey,
                IPoolManager.ModifyLiquidityParams({
                    liquidityDelta: -SafeCast.toInt256(uint256(liquidity)),
                    tickLower: lowerTick,
                    tickUpper: upperTick,
                    salt: bytes32(0)
                }),
                ""
            );
        }

        _clear6909Balances();

        (uint256 currency0Balance, uint256 currency1Balance) = _checkCurrencyBalances();
        uint256 amount0 = FullMath.mulDiv(pmCalldata.amount, currency0Balance, totalSupply);
        uint256 amount1 = FullMath.mulDiv(pmCalldata.amount, currency1Balance, totalSupply);

        uint256 newLiquidity = liquidity - FullMath.mulDiv(pmCalldata.amount, liquidity, totalSupply);

        if (newLiquidity > 0) {
            poolManager.modifyLiquidity(
                poolKey,
                IPoolManager.ModifyLiquidityParams({
                    liquidityDelta: SafeCast.toInt256(newLiquidity),
                    tickLower: lowerTick,
                    tickUpper: upperTick,
                    salt: bytes32(0)
                }),
                ""
            );
        }

        (currency0Balance, currency1Balance) = _checkCurrencyBalances();

        amount0 = amount0 > currency0Balance ? currency0Balance : amount0;
        amount1 = amount1 > currency1Balance ? currency1Balance : amount1;

        // take amounts and send them to receiver
        if (amount0 > 0) {
            poolManager.take(poolKey.currency0, pmCalldata.receiver, amount0);
        }
        if (amount1 > 0) {
            poolManager.take(poolKey.currency1, pmCalldata.receiver, amount1);
        }

        _a0 = amount0;
        _a1 = amount1;
        _mintLeftover();
        if (hedgeRequired0 > 0) {
            hedgeRequired0 -= FullMath.mulDiv(hedgeRequired0, pmCalldata.amount, totalSupply);
        }
        if (hedgeRequired1 > 0) {
            hedgeRequired1 -= FullMath.mulDiv(hedgeRequired1, pmCalldata.amount, totalSupply);
        }
    }

    function _checkLastOpen() internal view returns (uint256) {
        /// compute block delta since last time pool was utilized.
        uint256 blockDelta = block.number - lastBlockOpened;

        /// revert if block delta is 0 (pool is already open, top of block arb already happened)
        if (blockDelta == 0) revert PoolAlreadyOpened();

        return blockDelta;
    }

    function _getArbSwap(ArbSwapParams memory params) internal pure returns (uint256 swap0, uint256 swap1) {
        /// cannot do arb in zero liquidity
        if (params.liquidity == 0) revert LiquidityZero();

        /// cannot move price to edge of LP positin
        if (params.newSqrtPriceX96 >= params.sqrtPriceX96Upper || params.newSqrtPriceX96 <= params.sqrtPriceX96Lower) {
            revert PriceOutOfBounds();
        }

        /// get amount0/1 of current liquidity
        (uint256 current0, uint256 current1) = LiquidityAmounts.getAmountsForLiquidity(
            params.sqrtPriceX96, params.sqrtPriceX96Lower, params.sqrtPriceX96Upper, params.liquidity
        );

        /// get amount0/1 of current liquidity if price was newSqrtPriceX96
        (uint256 new0, uint256 new1) = LiquidityAmounts.getAmountsForLiquidity(
            params.newSqrtPriceX96, params.sqrtPriceX96Lower, params.sqrtPriceX96Upper, params.liquidity
        );

        // question: Is this error necessary?
        if (new0 == current0 || new1 == current1) revert ArbTooSmall();
        bool zeroForOne = new0 > current0;

        /// differential of curLiquidity amount0/1 at those two prices gives X and Y of classic UniV2 swap
        /// to get (1-Beta)*X and (1-Beta)*Y for our swap apply `factor`
        swap0 = FullMath.mulDiv(zeroForOne ? new0 - current0 : current0 - new0, params.betaFactor, _PIPS);
        swap1 = FullMath.mulDiv(zeroForOne ? current1 - new1 : new1 - current1, params.betaFactor, _PIPS);
    }

    function _resetLiquidity(bool isMintOrBurn)
        internal
        returns (uint160 sqrtPriceX96, uint160 newSqrtPriceX96, uint128 liquidity, uint128 newLiquidity)
    {
        (sqrtPriceX96,,,) = poolManager.getSlot0(PoolIdLibrary.toId(poolKey));

        (uint128 curLiquidity,,) = poolManager.getPositionInfo(
            PoolIdLibrary.toId(poolKey),
            address(this),
            lowerTick,
            upperTick,
            bytes32(0) // empty salt
        );
        if (lastBlockReset <= lastBlockOpened) {
            // Withdraw all liquidity
            if (curLiquidity > 0) {
                poolManager.modifyLiquidity(
                    poolKey,
                    IPoolManager.ModifyLiquidityParams({
                        liquidityDelta: -SafeCast.toInt256(uint256(curLiquidity)),
                        tickLower: lowerTick,
                        tickUpper: upperTick,
                        salt: bytes32(0) // empty salt
                    }),
                    "" // empty hook data
                );
            }

            _clear6909Balances();

            (newSqrtPriceX96, newLiquidity) = _getResetPriceAndLiquidity(committedSqrtPriceX96, isMintOrBurn);

            if (isMintOrBurn) {
                /// swap 1 wei in zero liquidity to kick the price to committedSqrtPriceX96
                if (sqrtPriceX96 != newSqrtPriceX96) {
                    poolManager.swap(
                        poolKey,
                        IPoolManager.SwapParams({
                            zeroForOne: newSqrtPriceX96 < sqrtPriceX96,
                            amountSpecified: 1,
                            sqrtPriceLimitX96: newSqrtPriceX96
                        }),
                        "" // empty hook data
                    );
                }

                if (newLiquidity > 0) {
                    poolManager.modifyLiquidity(
                        poolKey,
                        IPoolManager.ModifyLiquidityParams({
                            liquidityDelta: SafeCast.toInt256(uint256(newLiquidity)),
                            tickLower: lowerTick,
                            tickUpper: upperTick,
                            salt: bytes32(0) // empty salt
                        }),
                        "" // empty hook data
                    );
                }

                liquidity = newLiquidity;

                if (hedgeCommitted0 > 0) {
                    poolKey.currency0.settle(poolManager, address(this), hedgeCommitted0, false);
                }
                if (hedgeCommitted1 > 0) {
                    poolKey.currency1.settle(poolManager, address(this), hedgeCommitted1, false);
                }

                _mintLeftover();
            } else {
                if (hedgeCommitted0 > 0) {
                    poolKey.currency0.settle(poolManager, address(this), hedgeCommitted0, false);
                }
                if (hedgeCommitted1 > 0) {
                    poolKey.currency1.settle(poolManager, address(this), hedgeCommitted1, false);
                }
            }

            // reset hedger variables
            hedgeRequired0 = 0;
            hedgeRequired1 = 0;
            hedgeCommitted0 = 0;
            hedgeCommitted1 = 0;

            // store reset
            lastBlockReset = block.number;
        } else {
            liquidity = curLiquidity;
            newLiquidity = curLiquidity;
            newSqrtPriceX96 = sqrtPriceX96;
        }
    }

    function _getResetPriceAndLiquidity(uint160 lastCommittedSqrtPriceX96, bool isMintOrBurn)
        internal
        view
        returns (uint160, uint128)
    {
        (uint256 totalHoldings0, uint256 totalHoldings1) = _checkCurrencyBalances();

        uint160 finalSqrtPriceX96;
        {
            (uint256 maxLiquidity0, uint256 maxLiquidity1) = LiquidityAmounts.getAmountsForLiquidity(
                lastCommittedSqrtPriceX96,
                sqrtPriceX96Lower,
                sqrtPriceX96Upper,
                LiquidityAmounts.getLiquidityForAmounts(
                    lastCommittedSqrtPriceX96, sqrtPriceX96Lower, sqrtPriceX96Upper, totalHoldings0, totalHoldings1
                )
            );

            /// NOTE one of these should be roughly zero but we don't know which one so we just increase both
            // (adding 0 or dust to the other side should cause no issue or major imprecision)
            uint256 extra0 = FullMath.mulDiv(totalHoldings0 - maxLiquidity0, vaultRedepositRate, _PIPS);
            uint256 extra1 = FullMath.mulDiv(totalHoldings1 - maxLiquidity1, vaultRedepositRate, _PIPS);

            /// NOTE this algorithm only works if liquidity position is full range
            uint256 priceX96 = FullMath.mulDiv(maxLiquidity1 + extra1, 1 << 96, maxLiquidity0 + extra0);
            finalSqrtPriceX96 = SafeCast.toUint160(_sqrt(priceX96) * (1 << 48));
        }

        if (finalSqrtPriceX96 >= sqrtPriceX96Upper || finalSqrtPriceX96 <= sqrtPriceX96Lower) revert PriceOutOfBounds();

        if (isMintOrBurn) {
            totalHoldings0 -= 1;
            totalHoldings1 -= 1;
        }
        uint128 finalLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            finalSqrtPriceX96, sqrtPriceX96Lower, sqrtPriceX96Upper, totalHoldings0, totalHoldings1
        );

        return (finalSqrtPriceX96, finalLiquidity);
    }

    function _checkCurrencyBalances() internal view returns (uint256, uint256) {
        int256 currency0BalanceRaw = poolManager.currencyDelta(address(this), poolKey.currency0);
        if (currency0BalanceRaw > 0) revert InvalidCurrencyDelta();
        uint256 currency0Balance = SafeCast.toUint256(-currency0BalanceRaw);

        int256 currency1BalanceRaw = poolManager.currencyDelta(address(this), poolKey.currency1);
        if (currency1BalanceRaw > 0) revert InvalidCurrencyDelta();
        uint256 currency1Balance = SafeCast.toUint256(-currency1BalanceRaw);

        return (currency0Balance, currency1Balance);
    }

    function _mintLeftover() internal {
        (uint256 currencyBalance0, uint256 currencyBalance1) = _checkCurrencyBalances();

        if (currencyBalance0 > 0) {
            poolManager.mint(address(this), poolKey.currency0.toId(), currencyBalance0);
        }
        if (currencyBalance1 > 0) {
            poolManager.mint(address(this), poolKey.currency1.toId(), currencyBalance1);
        }
    }

    function _clear6909Balances() internal {
        (uint256 currency0Id, uint256 leftOver0, uint256 currency1Id, uint256 leftOver1) = _get6909Balances();

        if (leftOver0 > 0) {
            poolManager.burn(address(this), currency0Id, leftOver0);
        }

        if (leftOver1 > 0) {
            poolManager.burn(address(this), currency1Id, leftOver1);
        }
    }

    function _get6909Balances()
        internal
        view
        returns (uint256 currency0Id, uint256 leftOver0, uint256 currency1Id, uint256 leftOver1)
    {
        currency0Id = poolKey.currency0.toId();
        leftOver0 = poolManager.balanceOf(address(this), currency0Id);

        currency1Id = poolKey.currency1.toId();
        leftOver1 = poolManager.balanceOf(address(this), currency1Id);
    }

    function _getBeta(uint256 blockDelta) internal view returns (uint24) {
        /// if blockDelta = 1 then decay is 0; if blockDelta = 2 then decay is decayRate; if blockDelta = 3 then decay is 2*decayRate etc.
        uint256 decayAmt = (blockDelta - 1) * decayRate;
        /// decayAmt downcast is safe here because we know baseBeta < 10000
        uint24 subtractAmt = decayAmt >= baseBeta ? 0 : baseBeta - uint24(decayAmt);

        return _PIPS - subtractAmt;
    }

    function _transferToHook(address _from, address _token, uint256 _amount) internal {
        if (_token == address(0)) {
            if (msg.value != _amount) revert InvalidMsgValue();
        } else {
            ERC20(_token).safeTransferFrom(_from, address(this), _amount);
        }
    }

    function _transferToExternal(address _to, address _token, uint256 _amount) internal {
        if (_token == address(0)) {
            _nativeTransfer(_to, _amount);
        } else {
            ERC20(_token).safeTransfer(_to, _amount);
        }
    }

    function _nativeTransfer(address _to, uint256 _amount) internal {
        bool success;
        assembly {
            success := call(gas(), _to, _amount, 0, 0, 0, 0)
        }

        if (!success) revert NativeTransferFailed();
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
