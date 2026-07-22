// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {ExecutionRouter} from "../../src/router/ExecutionRouter.sol";
import {OracleRegistry} from "../../src/registries/OracleRegistry.sol";
import {RewardRegistry} from "../../src/registries/RewardRegistry.sol";
import {LpStrategy} from "../../src/strategies/LpStrategy.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {
    OracleConfig,
    RewardCategory,
    RewardDisposition,
    RewardTokenConfig,
    SwapRequest
} from "../../src/types/ProtocolTypes.sol";
import {MockDex} from "../mocks/MockDex.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {MockLpPair} from "../mocks/MockLpPair.sol";
import {MockLpRouter} from "../mocks/MockLpRouter.sol";
import {MockGauge} from "../mocks/MockGauge.sol";

contract LpStrategyTest is Test {
    AccessManager internal manager;
    MockINDEX internal index;
    MockStockToken internal pairedStock;
    MockDex internal dex;
    MockOracle internal indexFeed;
    MockOracle internal pairedFeed;

    OracleRegistry internal oracleRegistry;
    RewardRegistry internal rewardRegistry;
    ExecutionRouter internal router;

    MockLpPair internal lpPair;
    MockLpRouter internal lpRouter;
    MockGauge internal gauge;

    RobinVault internal vault;
    LpStrategy internal strategy;

    address internal governance = makeAddr("governance");
    address internal user = makeAddr("user");

    function setUp() public {
        manager = new AccessManager(governance);
        index = new MockINDEX(18);
        pairedStock = new MockStockToken("Mock Tesla", "mTSLA", 18);
        dex = new MockDex();
        indexFeed = new MockOracle(8, 1e8);
        pairedFeed = new MockOracle(8, 1e8);

        oracleRegistry = new OracleRegistry(address(manager));
        rewardRegistry = new RewardRegistry(address(manager));
        router = new ExecutionRouter(address(manager), oracleRegistry);

        lpPair = new MockLpPair(address(index), address(pairedStock));
        lpRouter = new MockLpRouter(lpPair);
        gauge = new MockGauge(lpPair, index);

        vault = new RobinVault(index, "Robin INDEX LP Vault", "rhINDEX-LP", address(manager));

        strategy = new LpStrategy(
            address(vault),
            index,
            address(manager),
            address(lpPair),
            address(pairedStock),
            address(lpRouter),
            address(dex),
            router,
            oracleRegistry,
            rewardRegistry
        );

        vm.startPrank(governance);
        vault.setStrategy(address(strategy));
        oracleRegistry.setOracleConfig(address(index), _oracleConfig(address(indexFeed)));
        oracleRegistry.setOracleConfig(address(pairedStock), _oracleConfig(address(pairedFeed)));

        router.setAdapterApproval(address(dex), true);
        router.setRoute(address(dex), address(index), address(pairedStock), true, 500);
        router.setRoute(address(dex), address(pairedStock), address(index), true, 500);
        rewardRegistry.setAdapterApproval(address(index), address(dex), true);

        rewardRegistry.setRewardTokenConfig(
            address(index),
            RewardTokenConfig({
                enabled: true,
                category: RewardCategory.Other,
                disposition: RewardDisposition.Sell,
                oracle: address(indexFeed),
                minHarvestAmount: 0,
                retainable: false,
                adapter: address(dex),
                maxExposureBps: 0
            })
        );

        strategy.addRewardToken(address(index));
        strategy.setGauge(address(gauge));
        vm.stopPrank();

        // Seed liquidity pool and dex rates
        index.mint(address(dex), 1_000_000 ether);
        pairedStock.mint(address(dex), 1_000_000 ether);
        dex.setRate(address(index), address(pairedStock), 1e18);
        dex.setRate(address(pairedStock), address(index), 1e18);

        index.mint(address(lpPair), 100_000 ether);
        pairedStock.mint(address(lpPair), 100_000 ether);

        index.mint(user, 1_000_000 ether);
        vm.prank(user);
        index.approve(address(vault), type(uint256).max);
    }

    function testDeployFundsPoolsLiquidity() public {
        _depositAndDeploy(10_000 ether);

        assertGt(gauge.balanceOf(address(strategy)), 0);
        assertGt(strategy.deployedAssets(), 0);
    }

    function testFreeFundsProportionalBurn() public {
        _depositAndDeploy(10_000 ether);

        uint256 balanceBefore = index.balanceOf(user);
        vm.prank(user);
        vault.withdraw(1_000 ether, user, user);

        assertGe(index.balanceOf(user), balanceBefore + 1_000 ether);
    }

    function testHarvestAutoCompoundsArbitraryRewards() public {
        _depositAndDeploy(10_000 ether);

        uint256 deployedBefore = strategy.deployedAssets();

        vm.prank(governance);
        strategy.harvest();

        uint256 deployedAfter = strategy.deployedAssets();
        assertGe(deployedAfter, deployedBefore);
    }

    function testUnhealthyOracleHandling() public {
        _depositAndDeploy(10_000 ether);

        // Pause paired token feed
        vm.prank(governance);
        oracleRegistry.setOracleConfig(address(pairedStock), _oracleConfig(address(pairedFeed), true));

        // totalAssets / deployedAssets does not revert and uses conservative valuation
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0);

        // Operations continue
        vm.prank(user);
        vault.withdraw(100 ether, user, user);
    }

    function testGovernanceControls() public {
        vm.startPrank(governance);
        strategy.setMaxSlippage(500);
        assertEq(strategy.maxSlippageBps(), 500);

        strategy.pauseCompounding();
        assertTrue(strategy.compoundingPaused());

        strategy.resumeCompounding();
        assertFalse(strategy.compoundingPaused());
        vm.stopPrank();
    }

    function _depositAndDeploy(uint256 amount) private {
        vm.prank(user);
        vault.deposit(amount, user);

        vm.prank(governance);
        vault.deployIdle();
    }

    function _oracleConfig(address feed) private pure returns (OracleConfig memory config) {
        config = _oracleConfig(feed, false);
    }

    function _oracleConfig(address feed, bool paused) private pure returns (OracleConfig memory config) {
        config = OracleConfig({
            feed: feed,
            heartbeat: 1 hours,
            decimals: 8,
            maxDeviationBps: 500,
            uiMultiplier: 1e18,
            paused: paused
        });
    }
}
