// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {MEVArbitrage} from "src/mev/MEVArbitrage.sol";

import "forge-std/console2.sol";

contract MEVBaseTest is Test, Deployers {
    using StateLibrary for IPoolManager;

    MEVArbitrage hook;
    MEVArbitrage nativeHook;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address builder = makeAddr("builder");

    uint256 public constant blockNum = 1000;
    uint24 constant PIPS = 1000000;
    int24 public tickSpacing = 20;
    uint24 public baseBeta = PIPS / 2; // % expressed as uint < 1e6
    uint24 public decayRate = PIPS / 10; // % expressed as uint < 1e6
    uint24 public vaultRedepositRate = PIPS / 10; // % expressed as uint < 1e6
    // we also want to pass in a minimum constant amount (maybe even a % of total pool size, so the vault eventually empties)
    // if we only ever take 1% of the vault, the vault may never empty.
    uint24 public fee = 1000; // % expressed as uint < 1e6

    address token0;
    address token1;

    uint256 public constant TOKEN_INITIAL_AMOUNT = 1e18;

    function setUp() public {
        vm.roll(blockNum);

        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        bytes memory constructorArgs = abi.encode(manager, tickSpacing, baseBeta, decayRate, vaultRedepositRate);

        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_INITIALIZE_FLAG
                | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        deployCodeTo("MEVArbitrage.sol", constructorArgs, address(flags | (1 << 100)));
        deployCodeTo("MEVArbitrage.sol", constructorArgs, address(flags | (1 << 101)));

        hook = MEVArbitrage(address(flags | (1 << 100)));
        nativeHook = MEVArbitrage(address(flags | (1 << 101)));

        (key,) = initPool(currency0, currency1, hook, fee, tickSpacing, SQRT_PRICE_1_1);
        (nativeKey,) = initPool(CurrencyLibrary.ADDRESS_ZERO, currency1, nativeHook, fee, tickSpacing, SQRT_PRICE_1_1);

        // Mint initial liquidity
        MockERC20(Currency.unwrap(currency0)).approve(address(hook), Constants.MAX_UINT256);
        MockERC20(Currency.unwrap(currency1)).approve(address(hook), Constants.MAX_UINT256);
        MockERC20(Currency.unwrap(currency1)).approve(address(nativeHook), Constants.MAX_UINT256);

        hook.mint(1e20, address(this));
        nativeHook.mint{value: 1e20}(1e20, address(this));

        token0 = Currency.unwrap(currency0);
        token1 = Currency.unwrap(currency1);

        _deal(builder);
        _deal(alice);
        _deal(bob);
    }

    function test_simpleArbitrage_success() public {
        vm.roll(block.number + 3);
        uint160 committedSqrtPriceX96 = TickMath.getSqrtPriceAtTick(10);

        uint256 poolBalance0Before = IERC20(token0).balanceOf(address(manager));
        uint256 poolBalance1Before = IERC20(token1).balanceOf(address(manager));
        uint256 liquidityBefore = manager.getLiquidity(key.toId());
        uint256 builderBalance0Before = IERC20(token0).balanceOf(builder);
        uint256 builderBalance1Before = IERC20(token1).balanceOf(builder);

        vm.startPrank(builder);
        hook.openPool(committedSqrtPriceX96);
        vm.stopPrank();

        uint256 poolBalance0After = IERC20(token0).balanceOf(address(manager));
        uint256 poolBalance1After = IERC20(token1).balanceOf(address(manager));
        uint256 liquidityAfter = manager.getLiquidity(key.toId());
        uint256 builderBalance0After = IERC20(token0).balanceOf(builder);
        uint256 builderBalance1After = IERC20(token1).balanceOf(builder);

        (uint160 newSqrtPriceX96,,,) = manager.getSlot0(key.toId());
        assertEq(newSqrtPriceX96, committedSqrtPriceX96);
        assertGt(poolBalance1After, poolBalance1Before);
        assertLt(poolBalance0After, poolBalance0Before);
        assertLt(liquidityAfter, liquidityBefore);
        assertGt(builderBalance0After, builderBalance0Before);
        assertLt(builderBalance1After, builderBalance1Before);
        assertEq(builderBalance0After - builderBalance0Before, poolBalance0Before - poolBalance0After);
        assertEq(builderBalance1Before - builderBalance1After, poolBalance1After - poolBalance1Before);
    }

    function _deal(address who) internal {
        IERC20(token0).transfer(who, TOKEN_INITIAL_AMOUNT);
        IERC20(token1).transfer(who, TOKEN_INITIAL_AMOUNT);
        deal(who, TOKEN_INITIAL_AMOUNT);

        vm.startPrank(who);

        IERC20(token0).approve(address(hook), Constants.MAX_UINT256);
        IERC20(token0).approve(address(nativeHook), Constants.MAX_UINT256);
        IERC20(token1).approve(address(hook), Constants.MAX_UINT256);
        IERC20(token1).approve(address(nativeHook), Constants.MAX_UINT256);

        IERC20(token0).approve(address(manager), Constants.MAX_UINT256);
        IERC20(token1).approve(address(manager), Constants.MAX_UINT256);

        vm.stopPrank();
    }
}
