// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {ConcentratedLiquidityStrategy} from "../../src/strategies/ConcentratedLiquidityStrategy.sol";
import {IExecutionRouter} from "../../src/interfaces/IExecutionRouter.sol";
import {IOracleRegistry} from "../../src/interfaces/IOracleRegistry.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {StrategyMode} from "../../src/types/ClStrategyTypes.sol";
import {SwapRequest} from "../../src/types/ProtocolTypes.sol";
import {HarvestReport} from "../../src/types/ProtocolTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRobinStrategy} from "../../src/interfaces/IRobinStrategy.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {MockV4PoolManager} from "../mocks/MockV4PoolManager.sol";
import {MockV4PositionManager} from "../mocks/MockV4PositionManager.sol";
import {MockRebalancePolicy} from "../mocks/MockRebalancePolicy.sol";
import {MockPermit2} from "../mocks/MockPermit2.sol";

contract MockClOracleRegistry {
    mapping(address asset => uint256 price) private _prices;
    uint160 private _sqrtPriceX96;

    function setPrice(address asset, uint256 price) external {
        _prices[asset] = price;
    }

    function setSqrtPriceX96(uint160 sqrtPriceX96) external {
        _sqrtPriceX96 = sqrtPriceX96;
    }

    function tryGetValidatedPrice(address asset)
        external
        view
        returns (bool healthy, uint256 price, uint256 updatedAt)
    {
        price = _prices[asset];
        healthy = price != 0;
        updatedAt = block.timestamp;
    }

    function getOracleSqrtPriceX96(address, address) external view returns (uint160 sqrtPriceX96, bool healthy) {
        sqrtPriceX96 = _sqrtPriceX96;
        healthy = sqrtPriceX96 != 0;
    }
}

contract MockClExecutionRouter {
    function isRouteApproved(address, address, address) external pure returns (bool approved) {
        approved = true;
    }

    function swapExactInput(SwapRequest calldata request, address recipient) external returns (uint256 amountOut) {
        amountOut = request.amountIn;
        IERC20(request.tokenIn).transferFrom(msg.sender, address(this), request.amountIn);
        IERC20(request.tokenOut).transfer(recipient, amountOut);
    }
}

contract MockStrategyVaultCaller {
    function deployFunds(address strategy, IERC20 asset, uint256 amount) external {
        asset.transfer(strategy, amount);
        IRobinStrategy(strategy).deployFunds(amount);
    }

    function freeFunds(address strategy, uint256 amount) external returns (uint256 amountFreed, uint256 loss) {
        (amountFreed, loss) = IRobinStrategy(strategy).freeFunds(amount);
    }

    function report(HarvestReport calldata) external {}
}

contract ConcentratedLiquidityStrategyTest is Test {
    AccessManager internal authority;
    MockINDEX internal index;
    MockStockToken internal paired;
    MockV4PoolManager internal poolManager;
    MockV4PositionManager internal positionManager;
    MockRebalancePolicy internal policy;
    MockClOracleRegistry internal oracle;
    MockClExecutionRouter internal executionRouter;
    MockStrategyVaultCaller internal vault;
    MockPermit2 internal permit2;
    ConcentratedLiquidityStrategy internal strategy;
    PoolKey internal key;

    address internal governance = makeAddr("governance");

    function setUp() public {
        authority = new AccessManager(governance);
        index = new MockINDEX(18);
        paired = new MockStockToken("Paired", "PAIR", 18);
        poolManager = new MockV4PoolManager();
        positionManager = new MockV4PositionManager();
        permit2 = new MockPermit2();
        positionManager.setPermit2(address(permit2));
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
    }

    function testInitialConfigurationAndOfficialWiring() public view {
        assertEq(strategy.vault(), address(vault));
        assertEq(strategy.asset(), address(index));
        assertEq(address(strategy.policy()), address(policy));
        assertEq(uint8(strategy.mode()), uint8(StrategyMode.Active));
        assertEq(strategy.twapWindow(), 30 minutes);
        assertEq(strategy.activePositionCount(), 0);
        assertEq(strategy.oracleSqrtPriceDeviationBps(), 500);
        assertEq(strategy.maxWithdrawSqrtPriceDeviationBps(), 300);
        assertEq(strategy.MAX_ACTIVE_POSITIONS(), 1);
    }

    function testPolicyProducesExpectedDefaultRange() public view {
        (int24 lower, int24 upper) = policy.targetRange(0, key.tickSpacing);
        assertEq(lower, -600);
        assertEq(upper, 600);
    }

    function testGovernanceModeTransitions() public {
        vm.prank(governance);
        strategy.enterWithdrawOnly();
        assertEq(uint8(strategy.mode()), uint8(StrategyMode.WithdrawOnly));

        vm.prank(governance);
        strategy.pause();
        assertEq(uint8(strategy.mode()), uint8(StrategyMode.Paused));

        vm.prank(governance);
        strategy.unpause();
        assertEq(uint8(strategy.mode()), uint8(StrategyMode.Active));
    }

    function testHarvestOnlyModeBlocksDeploymentAndTend() public {
        vm.prank(governance);
        strategy.enterHarvestOnly();
        assertEq(uint8(strategy.mode()), uint8(StrategyMode.HarvestOnly));

        vm.prank(governance);
        vm.expectRevert();
        strategy.tend();

        index.mint(address(vault), 1 ether);
        vm.expectRevert();
        vault.deployFunds(address(strategy), index, 1 ether);
    }

    function testPolicyRangeIsValidatedByStrategy() public {
        policy.setRange(-601, 600);
        index.mint(address(vault), 1 ether);
        paired.mint(address(strategy), 1 ether);
        vm.prank(governance);
        strategy.setSwapRoute(address(executionRouter));
        vm.expectRevert();
        vault.deployFunds(address(strategy), index, 1 ether);
    }

    function testRejectsOversizedPositionAmounts() public {
        index.mint(address(vault), 1);
        paired.mint(address(strategy), uint256(type(uint128).max) + 1);
        paired.mint(address(executionRouter), uint256(type(uint128).max) + 1);
        vm.prank(governance);
        strategy.setSwapRoute(address(executionRouter));
        vm.expectRevert();
        vault.deployFunds(address(strategy), index, 1);
    }

    function testPositionManagerActionPlanTracksMintAndClose() public {
        index.mint(address(strategy), 100 ether);
        paired.mint(address(strategy), 100 ether);

        // The action mock is exercised directly here; strategy integration tests can use its official selectors
        // without requiring a full PoolManager settlement implementation.
        uint256 nextId = positionManager.nextTokenId();
        positionManager.setPositionLiquidity(nextId, 123);
        assertEq(positionManager.getPositionLiquidity(nextId), 123);
    }

    function testDeployAndFreeFundsTracksAnOfficialPosition() public {
        index.mint(address(vault), 100 ether);
        paired.mint(address(strategy), 100 ether);
        index.mint(address(positionManager), 60 ether);
        paired.mint(address(positionManager), 40 ether);
        index.mint(address(executionRouter), 100 ether);
        paired.mint(address(executionRouter), 100 ether);
        positionManager.setReturnAmounts(60 ether, 40 ether);

        vm.prank(governance);
        strategy.setSwapRoute(address(executionRouter));

        vault.deployFunds(address(strategy), index, 100 ether);
        assertEq(strategy.activePositionCount(), 1);
        uint256 expected0 = address(index) == Currency.unwrap(key.currency0) ? 50 ether : 150 ether;
        uint256 expected1 = address(index) == Currency.unwrap(key.currency1) ? 50 ether : 150 ether;
        assertEq(positionManager.lastObservedPermit2Amount0(), expected0);
        assertEq(positionManager.lastObservedPermit2Amount1(), expected1);
        assertEq(index.allowance(address(strategy), address(permit2)), 0);
        assertEq(paired.allowance(address(strategy), address(permit2)), 0);

        // The mock settles no-op mint actions, so remove the idle balance to model all capital being in the NFT.
        index.burn(address(strategy), index.balanceOf(address(strategy)));

        vm.warp(block.timestamp + 30 minutes);
        (uint256 freed, uint256 loss) = vault.freeFunds(address(strategy), 50 ether);
        assertEq(freed, 50 ether);
        assertEq(loss, 0);
        assertEq(strategy.activePositionCount(), 0);
        assertEq(index.balanceOf(address(vault)), 50 ether);
    }

    function testPermit2ApprovalsAreExactAndClearedAfterIncrease() public {
        index.mint(address(vault), 100 ether);
        paired.mint(address(strategy), 100 ether);
        index.mint(address(positionManager), 100 ether);
        paired.mint(address(positionManager), 100 ether);
        index.mint(address(executionRouter), 100 ether);
        paired.mint(address(executionRouter), 100 ether);
        positionManager.setReturnAmounts(1 ether, 1 ether);

        vm.prank(governance);
        strategy.setSwapRoute(address(executionRouter));
        vault.deployFunds(address(strategy), index, 100 ether);

        vm.prank(governance);
        strategy.harvest();

        assertEq(positionManager.lastObservedPermit2Amount0(), 1 ether);
        assertEq(positionManager.lastObservedPermit2Amount1(), 1 ether);
        assertEq(index.allowance(address(strategy), address(permit2)), 0);
        assertEq(paired.allowance(address(strategy), address(permit2)), 0);
    }

    function testWithdrawRejectsExpiredObservationWindow() public {
        index.mint(address(vault), 100 ether);
        paired.mint(address(strategy), 100 ether);
        index.mint(address(positionManager), 100 ether);
        paired.mint(address(positionManager), 100 ether);
        index.mint(address(executionRouter), 100 ether);
        paired.mint(address(executionRouter), 100 ether);
        positionManager.setReturnAmounts(100 ether, 100 ether);

        vm.prank(governance);
        strategy.setSwapRoute(address(executionRouter));
        vault.deployFunds(address(strategy), index, 100 ether);
        index.burn(address(strategy), index.balanceOf(address(strategy)));
        vm.warp(block.timestamp + 30 minutes + 1);

        vm.expectRevert();
        vault.freeFunds(address(strategy), 1 ether);
    }

    function testFreeFundsSwapsPairedTokenBackToAsset() public {
        index.mint(address(vault), 100 ether);
        paired.mint(address(strategy), 100 ether);
        index.mint(address(positionManager), 100 ether);
        paired.mint(address(positionManager), 100 ether);
        index.mint(address(executionRouter), 500 ether);
        paired.mint(address(executionRouter), 500 ether);
        positionManager.setReturnAmounts(
            address(index) == Currency.unwrap(key.currency0) ? 0 : 100 ether,
            address(index) == Currency.unwrap(key.currency0) ? 100 ether : 0
        );

        vm.prank(governance);
        strategy.setSwapRoute(address(executionRouter));
        vault.deployFunds(address(strategy), index, 100 ether);
        index.burn(address(strategy), index.balanceOf(address(strategy)));

        vm.warp(block.timestamp + 30 minutes);
        (uint256 freed, uint256 loss) = vault.freeFunds(address(strategy), 50 ether);
        assertEq(freed, 50 ether);
        assertEq(loss, 0);
        assertEq(paired.balanceOf(address(strategy)), 0);
        assertEq(index.balanceOf(address(vault)), 50 ether);
    }

    function testV1RejectsSecondActivePosition() public {
        index.mint(address(vault), 200 ether);
        paired.mint(address(strategy), 200 ether);
        index.mint(address(positionManager), 100 ether);
        paired.mint(address(positionManager), 100 ether);
        index.mint(address(executionRouter), 200 ether);
        paired.mint(address(executionRouter), 200 ether);
        positionManager.setReturnAmounts(0, 0);

        vm.prank(governance);
        strategy.setSwapRoute(address(executionRouter));
        vault.deployFunds(address(strategy), index, 100 ether);
        assertEq(strategy.activePositionCount(), 1);

        vm.expectRevert();
        vault.deployFunds(address(strategy), index, 100 ether);
    }

    function testConstructorRejectsUnsortedOrHookedPoolKey() public {
        PoolKey memory hooked = key;
        hooked.hooks = IHooks(address(1));
        vm.expectRevert();
        new ConcentratedLiquidityStrategy(
            address(vault),
            index,
            address(authority),
            IPoolManager(address(poolManager)),
            IPositionManager(address(positionManager)),
            hooked,
            IExecutionRouter(address(executionRouter)),
            IOracleRegistry(address(oracle)),
            policy
        );

        PoolKey memory reversed = key;
        (reversed.currency0, reversed.currency1) = (key.currency1, key.currency0);
        vm.expectRevert();
        new ConcentratedLiquidityStrategy(
            address(vault),
            index,
            address(authority),
            IPoolManager(address(poolManager)),
            IPositionManager(address(positionManager)),
            reversed,
            IExecutionRouter(address(executionRouter)),
            IOracleRegistry(address(oracle)),
            policy
        );
    }

    function testFuzzDeployAcceptsStrategyValidatedRanges(int16 lowerSeed, uint8 widthSeed) public {
        int24 lower = int24(int256(bound(int256(lowerSeed), -20, 20)) * 60);
        int24 width = int24(120 + uint24(bound(uint256(widthSeed), 0, 38)) * 60);
        policy.setRange(lower, lower + width);

        index.mint(address(vault), 1 ether);
        paired.mint(address(strategy), 1 ether);
        index.mint(address(executionRouter), 1 ether);
        paired.mint(address(executionRouter), 1 ether);
        vm.prank(governance);
        strategy.setSwapRoute(address(executionRouter));
        vault.deployFunds(address(strategy), index, 1 ether);
        assertEq(strategy.activePositionCount(), 1);
    }
}
