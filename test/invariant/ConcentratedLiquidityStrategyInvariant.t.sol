// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {ConcentratedLiquidityStrategy} from "../../src/strategies/ConcentratedLiquidityStrategy.sol";
import {IExecutionRouter} from "../../src/interfaces/IExecutionRouter.sol";
import {IOracleRegistry} from "../../src/interfaces/IOracleRegistry.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {MockV4PoolManager} from "../mocks/MockV4PoolManager.sol";
import {MockV4PositionManager} from "../mocks/MockV4PositionManager.sol";
import {MockRebalancePolicy} from "../mocks/MockRebalancePolicy.sol";
import {
    MockClExecutionRouter,
    MockClOracleRegistry,
    MockStrategyVaultCaller
} from "../unit/ConcentratedLiquidityStrategy.t.sol";

contract ConcentratedLiquidityStrategyInvariant is StdInvariant, Test {
    AccessManager internal authority;
    MockINDEX internal index;
    MockStockToken internal paired;
    MockV4PoolManager internal poolManager;
    MockV4PositionManager internal positionManager;
    MockRebalancePolicy internal policy;
    MockClOracleRegistry internal oracle;
    MockClExecutionRouter internal executionRouter;
    MockStrategyVaultCaller internal vault;
    ConcentratedLiquidityStrategy internal strategy;
    PoolKey internal key;
    address internal governance = makeAddr("governance");

    function setUp() public {
        authority = new AccessManager(governance);
        index = new MockINDEX(18);
        paired = new MockStockToken("Paired", "PAIR", 18);
        poolManager = new MockV4PoolManager();
        positionManager = new MockV4PositionManager();
        policy = new MockRebalancePolicy(-600, 600, 120, 2400);
        oracle = new MockClOracleRegistry();
        executionRouter = new MockClExecutionRouter();
        vault = new MockStrategyVaultCaller();

        (address token0, address token1) =
            address(index) < address(paired) ? (address(index), address(paired)) : (address(paired), address(index));
        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3_000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        poolManager.setSlot0(key.toId(), 1 << 96, 0, 0, 3_000);
        oracle.setPrice(address(index), 1e18);
        oracle.setPrice(address(paired), 1e18);
        oracle.setSqrtPriceX96(1 << 96);

        strategy = new ConcentratedLiquidityStrategy(
            address(vault),
            index,
            address(authority),
            IPoolManager(address(poolManager)),
            IPositionManager(address(positionManager)),
            key,
            IExecutionRouter(address(executionRouter)),
            IOracleRegistry(address(oracle)),
            policy
        );

        index.mint(address(vault), 100 ether);
        paired.mint(address(strategy), 100 ether);
        index.mint(address(executionRouter), 100 ether);
        paired.mint(address(executionRouter), 100 ether);
        vm.prank(governance);
        strategy.setSwapRoute(address(executionRouter));
        vault.deployFunds(address(strategy), index, 100 ether);

        targetContract(address(positionManager));
        bytes4[] memory excludedSelectors = new bytes4[](1);
        excludedSelectors[0] = MockV4PositionManager.modifyLiquidities.selector;
        excludeSelector(FuzzSelector({addr: address(positionManager), selectors: excludedSelectors}));
    }

    function invariant_activePositionCountIsV1Bounded() public view {
        assertLe(strategy.activePositionCount(), strategy.MAX_ACTIVE_POSITIONS());
    }

    function invariant_strategyModeIsAValidEnumValue() public view {
        assertLe(uint8(strategy.mode()), 3);
    }
}
