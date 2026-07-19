// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {ExecutionRouter} from "../../src/router/ExecutionRouter.sol";
import {OracleRegistry} from "../../src/registries/OracleRegistry.sol";
import {RewardRegistry} from "../../src/registries/RewardRegistry.sol";
import {CoreStrategy} from "../../src/strategies/CoreStrategy.sol";
import {GrowthStrategy} from "../../src/strategies/GrowthStrategy.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {
    OracleConfig,
    RewardCategory,
    RewardDisposition,
    RewardTokenConfig,
    CategoryPolicy
} from "../../src/types/ProtocolTypes.sol";
import {MockDex} from "../mocks/MockDex.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockIndexFinanceCore} from "../mocks/MockIndexFinanceCore.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";

contract GrowthStrategyTest is Test {
    AccessManager internal manager;
    MockINDEX internal index;
    MockStockToken internal retainStock;
    MockStockToken internal sellStock;
    MockStockToken internal ignoredStock;
    MockDex internal dex;
    MockOracle internal indexFeed;
    MockOracle internal retainFeed;
    MockOracle internal sellFeed;
    MockOracle internal ignoredFeed;
    OracleRegistry internal oracleRegistry;
    RewardRegistry internal rewardRegistry;
    ExecutionRouter internal router;
    MockIndexFinanceCore internal indexFinance;
    RobinVault internal vault;
    GrowthStrategy internal strategy;

    address internal governance = makeAddr("governance");
    address internal user = makeAddr("user");

    function setUp() public {
        manager = new AccessManager(governance);
        index = new MockINDEX(18);
        retainStock = new MockStockToken("Mock Apple", "mAAPL", 18);
        sellStock = new MockStockToken("Mock Nvidia", "mNVDA", 18);
        ignoredStock = new MockStockToken("Mock Microsoft", "mMSFT", 18);
        dex = new MockDex();
        indexFeed = new MockOracle(8, 1e8);
        retainFeed = new MockOracle(8, 1e8);
        sellFeed = new MockOracle(8, 1e8);
        ignoredFeed = new MockOracle(8, 1e8);

        oracleRegistry = new OracleRegistry(address(manager));
        rewardRegistry = new RewardRegistry(address(manager));
        router = new ExecutionRouter(address(manager), oracleRegistry);
        indexFinance = new MockIndexFinanceCore(IERC20(address(index)));
        vault = new RobinVault(index, "Robin Growth Vault", "rhINDEX-G", address(manager));
        strategy = new GrowthStrategy(
            address(vault),
            index,
            address(manager),
            indexFinance,
            rewardRegistry,
            oracleRegistry,
            router,
            500,
            30 minutes
        );

        vm.startPrank(governance);
        vault.setStrategy(address(strategy));
        oracleRegistry.setOracleConfig(address(index), _oracleConfig(address(indexFeed), false));
        oracleRegistry.setOracleConfig(address(retainStock), _oracleConfig(address(retainFeed), false));
        oracleRegistry.setOracleConfig(address(sellStock), _oracleConfig(address(sellFeed), false));
        oracleRegistry.setOracleConfig(address(ignoredStock), _oracleConfig(address(ignoredFeed), false));

        router.setAdapterApproval(address(dex), true);
        router.setRoute(address(dex), address(retainStock), address(index), true, 500);
        router.setRoute(address(dex), address(sellStock), address(index), true, 500);
        rewardRegistry.setAdapterApproval(address(sellStock), address(dex), true);

        rewardRegistry.setRewardTokenConfig(
            address(retainStock), _rewardConfig(RewardDisposition.Retain, address(retainFeed), 0)
        );
        rewardRegistry.setRewardTokenConfig(
            address(sellStock), _rewardConfig(RewardDisposition.Sell, address(sellFeed), 0)
        );
        rewardRegistry.setRewardTokenConfig(
            address(ignoredStock), _rewardConfig(RewardDisposition.Ignore, address(ignoredFeed), 0)
        );
        strategy.addRewardToken(address(retainStock));
        strategy.addRewardToken(address(sellStock));
        strategy.addRewardToken(address(ignoredStock));
        strategy.setCategoryPolicy(RewardCategory.Equity, _policy(5_000));
        vm.stopPrank();

        indexFinance.setEligible(address(strategy), true);
        dex.setRate(address(sellStock), address(index), 1e18);
        dex.setRate(address(retainStock), address(index), 1e18);
        index.mint(address(dex), 1_000_000 ether);

        index.mint(user, 10_000 ether);
        vm.prank(user);
        index.approve(address(vault), type(uint256).max);
    }

    function testRetainedRewardProcessingAddsPortfolioNav() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);

        vm.prank(governance);
        strategy.harvest();

        assertEq(strategy.retainedBalance(address(retainStock)), 100 ether);
        assertEq(strategy.retainedValue(address(retainStock)), 100 ether);
        assertEq(strategy.totalAssets(), 1_100 ether);
        assertEq(vault.strategyDebt(), 1_100 ether);
        assertEq(vault.lockedProfit(), 100 ether);
    }

    function testMixedSellRetainAndIgnoreHarvest() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        _accrueReward(sellStock, 50 ether);
        _accrueReward(ignoredStock, 25 ether);

        vm.prank(governance);
        strategy.harvest();

        assertEq(strategy.retainedBalance(address(retainStock)), 100 ether);
        assertEq(index.balanceOf(address(vault)), 50 ether);
        assertEq(ignoredStock.balanceOf(address(strategy)), 25 ether);
        assertEq(strategy.totalAssets(), 1_100 ether);
        assertEq(vault.strategyDebt(), 1_100 ether);
        assertEq(vault.lockedProfit(), 150 ether);
    }

    function testFullGrowthLifecycleIntegrationThroughFullWithdrawal() public {
        _depositAndDeploy(1_000 ether);
        assertEq(indexFinance.totalDeposited(address(strategy)), 1_000 ether);

        _accrueReward(retainStock, 100 ether);
        _accrueReward(sellStock, 50 ether);
        _accrueReward(ignoredStock, 25 ether);

        vm.prank(governance);
        strategy.harvest();

        assertEq(strategy.retainedBalance(address(retainStock)), 100 ether);
        assertEq(ignoredStock.balanceOf(address(strategy)), 25 ether);
        assertEq(index.balanceOf(address(vault)), 50 ether);
        assertEq(vault.strategyDebt(), 1_100 ether);
        assertEq(vault.lockedProfit(), 150 ether);

        vm.warp(block.timestamp + vault.profitMaxUnlockTime());
        _refreshOracles();
        vm.prank(user);
        vault.withdraw(200 ether, user, user, 0);

        assertEq(index.balanceOf(user), 9_200 ether);
        assertEq(indexFinance.totalDeposited(address(strategy)), 850 ether);
        assertEq(strategy.retainedBalance(address(retainStock)), 100 ether);
        assertEq(vault.strategyDebt(), 950 ether);

        _accrueReward(sellStock, 50 ether);
        vm.prank(governance);
        strategy.harvest();

        assertEq(index.balanceOf(address(vault)), 50 ether);
        assertEq(vault.strategyDebt(), 950 ether);
        assertEq(vault.lockedProfit(), 50 ether);

        vm.warp(block.timestamp + vault.profitMaxUnlockTime());
        _refreshOracles();
        uint256 shares = vault.balanceOf(user);

        vm.prank(user);
        uint256 assets = vault.redeem(shares, user, user, 0);

        assertApproxEqAbs(assets, 1_000 ether, 1);
        assertEq(vault.balanceOf(user), 0);
        assertApproxEqAbs(index.balanceOf(user), 10_200 ether, 1);
        assertEq(indexFinance.totalDeposited(address(strategy)), 0);
        assertLe(strategy.retainedBalance(address(retainStock)), 1);
        assertLe(vault.strategyDebt(), 1);
    }

    function testCategoryExposureLimitIsolatesToken() public {
        vm.prank(governance);
        strategy.setCategoryPolicy(RewardCategory.Equity, _policy(500));

        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);

        vm.prank(governance);
        strategy.harvest();

        assertTrue(strategy.isRewardTokenIsolated(address(retainStock)));
        assertEq(strategy.retainedBalance(address(retainStock)), 0);
        assertEq(retainStock.balanceOf(address(strategy)), 100 ether);
    }

    function testTokenExposureLimitIsolatesToken() public {
        vm.prank(governance);
        rewardRegistry.setRewardTokenConfig(
            address(retainStock), _rewardConfig(RewardDisposition.Retain, address(retainFeed), 500)
        );

        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);

        vm.prank(governance);
        strategy.harvest();

        assertTrue(strategy.isRewardTokenIsolated(address(retainStock)));
        assertEq(strategy.retainedBalance(address(retainStock)), 0);
    }

    function testPortfolioAccountingAndCategoryExposure() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);

        vm.prank(governance);
        strategy.harvest();

        (uint256 value, uint256 exposureBps) = strategy.categoryExposure(RewardCategory.Equity);
        assertEq(value, 100 ether);
        assertEq(exposureBps, 910);
        assertEq(strategy.tokenExposureBps(address(retainStock)), 910);
    }

    function testOracleFailureIsolatesRetainedReward() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        oracleRegistry.setOraclePaused(address(retainStock), true);

        vm.prank(governance);
        strategy.harvest();

        assertTrue(strategy.isRewardTokenIsolated(address(retainStock)));
        assertEq(strategy.retainedBalance(address(retainStock)), 0);
    }

    function testUnsupportedStockTokenIsIsolated() public {
        MockINDEX unsupportedReward = new MockINDEX(18);
        MockOracle unsupportedFeed = new MockOracle(8, 1e8);

        vm.startPrank(governance);
        oracleRegistry.setOracleConfig(address(unsupportedReward), _oracleConfig(address(unsupportedFeed), false));
        router.setRoute(address(dex), address(unsupportedReward), address(index), true, 500);
        rewardRegistry.setRewardTokenConfig(
            address(unsupportedReward), _rewardConfig(RewardDisposition.Retain, address(unsupportedFeed), 0)
        );
        strategy.addRewardToken(address(unsupportedReward));
        vm.stopPrank();

        _depositAndDeploy(1_000 ether);
        unsupportedReward.mint(address(indexFinance), 100 ether);
        indexFinance.accrue(address(strategy), address(unsupportedReward), 100 ether);

        vm.prank(governance);
        strategy.harvest();

        assertTrue(strategy.isRewardTokenIsolated(address(unsupportedReward)));
        assertEq(strategy.retainedBalance(address(unsupportedReward)), 0);
    }

    function testMissingLiquidationRouteIsolatesRetainedReward() public {
        vm.prank(governance);
        router.setRoute(address(dex), address(retainStock), address(index), false, 500);

        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);

        vm.prank(governance);
        strategy.harvest();

        assertTrue(strategy.isRewardTokenIsolated(address(retainStock)));
    }

    function testMalformedRewardClaimReverts() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 1 ether);
        indexFinance.setReturnMalformedClaim(true);

        vm.prank(governance);
        vm.expectRevert(CoreStrategy.InvalidRewardClaim.selector);
        strategy.harvest();
    }

    function testUnauthorizedPolicyUpdatesRevert() public {
        vm.prank(user);
        vm.expectRevert();
        strategy.setCategoryPolicy(RewardCategory.Equity, _policy(1_000));

        vm.prank(user);
        vm.expectRevert();
        strategy.markRebalance(RewardCategory.Equity);
    }

    function testRebalanceHookHonorsCooldown() public {
        vm.prank(governance);
        strategy.markRebalance(RewardCategory.Equity);

        vm.prank(governance);
        vm.expectRevert();
        strategy.markRebalance(RewardCategory.Equity);

        vm.warp(block.timestamp + 1 days);
        vm.prank(governance);
        strategy.markRebalance(RewardCategory.Equity);
    }

    function testCoreStrategyRegressionStillRejectsRetainRewards() public {
        RobinVault coreVault = new RobinVault(index, "Robin Core Vault", "rhINDEX", address(manager));
        MockIndexFinanceCore coreIndexFinance = new MockIndexFinanceCore(IERC20(address(index)));
        CoreStrategy core = new CoreStrategy(
            address(coreVault),
            index,
            address(manager),
            coreIndexFinance,
            rewardRegistry,
            oracleRegistry,
            router,
            500,
            30 minutes
        );
        vm.prank(governance);
        coreVault.setStrategy(address(core));
        vm.prank(governance);
        core.addRewardToken(address(retainStock));
        coreIndexFinance.setEligible(address(core), true);

        index.mint(user, 1_000 ether);
        vm.prank(user);
        index.approve(address(coreVault), type(uint256).max);
        vm.prank(user);
        coreVault.deposit(1_000 ether, user);
        vm.prank(governance);
        coreVault.deploy(1_000 ether);

        retainStock.mint(address(coreIndexFinance), 100 ether);
        coreIndexFinance.accrue(address(core), address(retainStock), 100 ether);

        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(CoreStrategy.RetainedRewardsUnsupported.selector, address(retainStock)));
        core.harvest();
    }

    function _depositAndDeploy(uint256 amount) private {
        vm.prank(user);
        vault.deposit(amount, user);
        vm.prank(governance);
        vault.deploy(amount);
    }

    function _accrueReward(MockStockToken token, uint256 amount) private {
        token.mint(address(indexFinance), amount);
        indexFinance.accrue(address(strategy), address(token), amount);
    }

    function _refreshOracles() private {
        indexFeed.setRoundData(indexFeed.roundId() + 1, 1e8, block.timestamp, block.timestamp, indexFeed.roundId() + 1);
        retainFeed.setRoundData(
            retainFeed.roundId() + 1, 1e8, block.timestamp, block.timestamp, retainFeed.roundId() + 1
        );
        sellFeed.setRoundData(sellFeed.roundId() + 1, 1e8, block.timestamp, block.timestamp, sellFeed.roundId() + 1);
        ignoredFeed.setRoundData(
            ignoredFeed.roundId() + 1, 1e8, block.timestamp, block.timestamp, ignoredFeed.roundId() + 1
        );
    }

    function _oracleConfig(address feed, bool paused) private pure returns (OracleConfig memory config) {
        config = OracleConfig({
            feed: feed, heartbeat: 1 hours, decimals: 8, maxDeviationBps: 500, uiMultiplier: 1e18, paused: paused
        });
    }

    function _rewardConfig(RewardDisposition disposition, address oracle, uint16 maxExposureBps)
        private
        view
        returns (RewardTokenConfig memory config)
    {
        config = RewardTokenConfig({
            enabled: true,
            category: RewardCategory.Equity,
            disposition: disposition,
            oracle: oracle,
            minHarvestAmount: 1 ether,
            retainable: disposition == RewardDisposition.Retain,
            adapter: address(dex),
            maxExposureBps: maxExposureBps
        });
    }

    function _policy(uint16 maxPortfolioBps) private pure returns (CategoryPolicy memory policy) {
        policy = CategoryPolicy({
            targetRetainBps: maxPortfolioBps,
            minRetainBps: 0,
            maxRetainBps: maxPortfolioBps,
            maxPortfolioBps: maxPortfolioBps,
            rebalanceCooldown: 1 days
        });
    }
}
