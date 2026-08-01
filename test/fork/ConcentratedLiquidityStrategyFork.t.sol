// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {ConcentratedLiquidityStrategy} from "../../src/strategies/ConcentratedLiquidityStrategy.sol";
import {IExecutionRouter} from "../../src/interfaces/IExecutionRouter.sol";
import {IOracleRegistry} from "../../src/interfaces/IOracleRegistry.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {MockRebalancePolicy} from "../mocks/MockRebalancePolicy.sol";
import {SwapRequest, HarvestReport} from "../../src/types/ProtocolTypes.sol";

interface IForkStrategyVault {
    function deployFunds(address strategy, IERC20 asset, uint256 amount) external;
    function freeFunds(address strategy, uint256 amount) external returns (uint256 amountFreed, uint256 loss);
    function report(HarvestReport calldata report_) external;
}

contract ForkStrategyVault is IForkStrategyVault {
    function deployFunds(address strategy, IERC20 asset, uint256 amount) external {
        asset.transfer(strategy, amount);
        (bool success,) = strategy.call(abi.encodeWithSignature("deployFunds(uint256)", amount));
        require(success, "deploy failed");
    }

    function freeFunds(address strategy, uint256 amount) external returns (uint256 amountFreed, uint256 loss) {
        (bool success, bytes memory data) = strategy.call(abi.encodeWithSignature("freeFunds(uint256)", amount));
        require(success, "free failed");
        (amountFreed, loss) = abi.decode(data, (uint256, uint256));
    }

    function report(HarvestReport calldata) external {}
}

contract ForkOracleRegistry {
    mapping(address token => uint256 price) private _prices;
    uint160 public sqrtPriceX96;

    function setPrice(address token, uint256 price) external {
        _prices[token] = price;
    }

    function setSqrtPriceX96(uint160 price) external {
        sqrtPriceX96 = price;
    }

    function tryGetValidatedPrice(address token)
        external
        view
        returns (bool healthy, uint256 price, uint256 updatedAt)
    {
        price = _prices[token];
        healthy = price != 0;
        updatedAt = block.timestamp;
    }

    function getOracleSqrtPriceX96(address, address) external view returns (uint160 price, bool healthy) {
        price = sqrtPriceX96;
        healthy = price != 0;
    }
}

/// @notice Fork-only router that swaps through the deployed V4 PoolManager using official PoolSwapTest logic.
contract ForkV4ExecutionRouter is IExecutionRouter {
    PoolSwapTest public immutable swapTest;
    PoolKey public key;

    constructor(PoolSwapTest swapTest_, PoolKey memory key_) {
        swapTest = swapTest_;
        key = key_;
    }

    function swapExactInput(SwapRequest calldata request, address recipient) external returns (uint256 amountOut) {
        require(block.timestamp <= request.deadline, "expired");
        IERC20(request.tokenIn).transferFrom(msg.sender, address(this), request.amountIn);
        IERC20(request.tokenIn).approve(address(swapTest), request.amountIn);

        bool zeroForOne = request.tokenIn == Currency.unwrap(key.currency0);
        BalanceDelta delta = swapTest.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(request.amountIn),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            bytes("")
        );
        int128 signedAmountOut = zeroForOne ? delta.amount1() : delta.amount0();
        amountOut = signedAmountOut > 0 ? uint256(uint128(signedAmountOut)) : 0;
        require(amountOut >= request.minAmountOut, "minimum output");
        IERC20(request.tokenOut).transfer(recipient, amountOut);
    }

    function isAdapterApproved(address adapter) external view returns (bool approved) {
        approved = adapter == address(this);
    }

    function isRouteApproved(address adapter, address tokenIn, address tokenOut)
        external
        view
        returns (bool approved)
    {
        approved = adapter == address(this)
            && (
                (tokenIn == Currency.unwrap(key.currency0) && tokenOut == Currency.unwrap(key.currency1))
                    || (tokenIn == Currency.unwrap(key.currency1) && tokenOut == Currency.unwrap(key.currency0))
            );
    }

    function setAdapterApproval(address, bool) external {}
}

contract ConcentratedLiquidityStrategyForkTest is Test {
    IPoolManager internal constant POOL_MANAGER = IPoolManager(0x8366a39CC670B4001A1121B8F6A443A643e40951);
    IPositionManager internal constant POSITION_MANAGER = IPositionManager(0x58daec3116aae6D93017bAAea7749052E8a04fA7);

    AccessManager internal authority;
    MockINDEX internal index;
    MockStockToken internal paired;
    MockRebalancePolicy internal policy;
    ForkOracleRegistry internal oracle;
    PoolSwapTest internal swapTest;
    PoolModifyLiquidityTest internal modifyTest;
    ForkV4ExecutionRouter internal executionRouter;
    ForkStrategyVault internal vault;
    ConcentratedLiquidityStrategy internal strategy;
    PoolKey internal key;

    function setUp() public {
        string memory rpc = vm.envOr("ROBINHOOD_FORK_RPC", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true, "set ROBINHOOD_FORK_RPC to run V4 fork integration tests");
            return;
        }
        vm.createSelectFork(rpc);
        if (address(POOL_MANAGER).code.length == 0 || address(POSITION_MANAGER).code.length == 0) {
            vm.skip(true, "configured fork has no official Robinhood V4 deployment");
            return;
        }

        index = new MockINDEX(18);
        paired = new MockStockToken("Fork Pair", "fPAIR", 18);
        (address token0, address token1) =
            address(index) < address(paired) ? (address(index), address(paired)) : (address(paired), address(index));
        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3_000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        POOL_MANAGER.initialize(key, uint160(1 << 96));
        modifyTest = new PoolModifyLiquidityTest(POOL_MANAGER);
        index.mint(address(this), 1e24);
        paired.mint(address(this), 1e24);
        IERC20(token0).approve(address(modifyTest), type(uint256).max);
        IERC20(token1).approve(address(modifyTest), type(uint256).max);
        modifyTest.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 1e22, salt: bytes32(0)}),
            bytes("")
        );

        swapTest = new PoolSwapTest(POOL_MANAGER);
        executionRouter = new ForkV4ExecutionRouter(swapTest, key);
        authority = new AccessManager(address(this));
        oracle = new ForkOracleRegistry();
        oracle.setPrice(address(index), 1e18);
        oracle.setPrice(address(paired), 1e18);
        oracle.setSqrtPriceX96(uint160(1 << 96));
        policy = new MockRebalancePolicy(-600, 600, 120, 2400);
        vault = new ForkStrategyVault();
        strategy = new ConcentratedLiquidityStrategy(
            address(vault),
            index,
            address(authority),
            POOL_MANAGER,
            POSITION_MANAGER,
            key,
            IExecutionRouter(address(executionRouter)),
            IOracleRegistry(address(oracle)),
            policy
        );
        strategy.setSwapRoute(address(executionRouter));
        paired.mint(address(strategy), 1e20);
    }

    function _deploy() internal {
        index.mint(address(vault), 1e20);
        vault.deployFunds(address(strategy), index, 1e20);
        assertEq(strategy.activePositionCount(), 1);
    }

    function testForkDepositHarvestRebalanceAndPartialWithdrawal() public {
        _deploy();

        vm.warp(block.timestamp + 30 minutes);
        strategy.tend();

        index.mint(address(this), 1e18);
        IERC20(address(index)).approve(address(executionRouter), 1e18);
        executionRouter.swapExactInput(
            SwapRequest({
                adapter: address(executionRouter),
                tokenIn: address(index),
                tokenOut: address(paired),
                amountIn: 1e18,
                minAmountOut: 0,
                deadline: uint48(block.timestamp + 1 hours)
            }),
            address(this)
        );
        strategy.harvest();

        policy.setRebalance(true);
        strategy.rebalance();
        assertEq(strategy.activePositionCount(), 1);

        (uint256 freed,) = vault.freeFunds(address(strategy), 1e18);
        assertGt(freed, 0);
    }

    function testForkWithdrawOnlyPartialAndFullWithdrawal() public {
        _deploy();
        vm.warp(block.timestamp + 30 minutes);
        strategy.tend();
        strategy.enterWithdrawOnly();

        uint256 firstRequest = strategy.totalAssets() / 2;
        (uint256 firstFreed,) = vault.freeFunds(address(strategy), firstRequest);
        assertEq(firstFreed, firstRequest);

        uint256 remaining = IERC20(address(index)).balanceOf(address(strategy));
        if (remaining != 0) {
            (uint256 finalFreed,) = vault.freeFunds(address(strategy), remaining);
            assertEq(finalFreed, remaining);
        }
        assertEq(strategy.activePositionCount(), 0);
    }

    function testForkPauseEmergencyCloseAndReturn() public {
        _deploy();
        strategy.pause();
        vm.expectRevert();
        strategy.rebalance();

        strategy.emergencyClosePositions();
        assertEq(strategy.activePositionCount(), 0);
        strategy.emergencyReturnAssetsToVault();
        assertGt(index.balanceOf(address(vault)) + paired.balanceOf(address(vault)), 0);
    }

    function testForkUnauthorizedOracleFailureAndTwapExpiry() public {
        _deploy();

        vm.prank(makeAddr("outsider"));
        vm.expectRevert();
        strategy.rebalance();

        oracle.setPrice(address(index), 0);
        oracle.setSqrtPriceX96(0);
        vm.expectRevert();
        strategy.tend();

        oracle.setPrice(address(index), 1e18);
        oracle.setSqrtPriceX96(uint160(1 << 96));
        index.burn(address(strategy), index.balanceOf(address(strategy)));
        vm.warp(block.timestamp + 30 minutes + 1);
        vm.expectRevert();
        vault.freeFunds(address(strategy), 1e24);
    }
}
