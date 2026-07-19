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
    CategoryPolicy,
    InKindRedemptionResult
} from "../../src/types/ProtocolTypes.sol";
import {MockDex} from "../mocks/MockDex.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockIndexFinanceCore} from "../mocks/MockIndexFinanceCore.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {MockFeeOnTransferToken} from "../mocks/MockFeeOnTransferToken.sol";
import {ZeroAddress} from "../../src/libraries/Errors.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract GrowthStrategyTest is Test {
    using Math for uint256;

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
    address internal userTwo = makeAddr("userTwo");
    address internal receiver = makeAddr("receiver");
    address internal operator = makeAddr("operator");

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
        index.mint(userTwo, 10_000 ether);
        vm.prank(user);
        index.approve(address(vault), type(uint256).max);
        vm.prank(userTwo);
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

    function testPartialInKindRedeemMatchesPreviewAndReducesDebtProportionally() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 shares = vault.balanceOf(user) / 2;
        uint256 supplyBefore = vault.totalSupply();
        uint256 debtBefore = vault.strategyDebt();
        (uint256 indexPreview, uint256 retainedPreview) = _previewSingleRetained(shares);
        uint256 receiverIndexBefore = index.balanceOf(receiver);
        uint256 receiverStockBefore = retainStock.balanceOf(receiver);

        vm.prank(user);
        vault.redeemInKind(shares, receiver, user);

        assertEq(index.balanceOf(receiver) - receiverIndexBefore, indexPreview);
        assertEq(retainStock.balanceOf(receiver) - receiverStockBefore, retainedPreview);
        assertEq(strategy.retainedBalance(address(retainStock)), 100 ether - retainedPreview);
        assertEq(vault.strategyDebt(), debtBefore - debtBefore * shares / supplyBefore);
        assertEq(strategy.tokenExposureBps(address(retainStock)), 910);
    }

    function testFullInKindRedeemTransfersRemainingDust() public {
        _depositAndDeploy(3 ether);
        _accrueReward(retainStock, 1 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 firstShares = vault.balanceOf(user) - 1;
        vm.prank(user);
        vault.redeemInKind(firstShares, user, user);

        uint256 finalShares = vault.balanceOf(user);
        uint256 remainingStock = strategy.retainedBalance(address(retainStock));
        vm.prank(user);
        vault.redeemInKind(finalShares, user, user);

        assertEq(vault.balanceOf(user), 0);
        assertEq(strategy.retainedBalance(address(retainStock)), 0);
        assertEq(retainStock.balanceOf(address(strategy)), 0);
        assertEq(vault.strategyDebt(), 0);
        assertEq(retainStock.balanceOf(user), 1 ether);
        assertGt(remainingStock, 0);
    }

    function testInKindRedeemSupportsAllowanceAndDistinctReceiver() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 shares = vault.balanceOf(user) / 10;
        vm.prank(user);
        vault.approve(operator, shares);
        uint256 receiverStockBefore = retainStock.balanceOf(receiver);

        vm.prank(operator);
        vault.redeemInKind(shares, receiver, user);

        assertEq(retainStock.balanceOf(receiver) - receiverStockBefore, 10 ether);
        assertEq(vault.balanceOf(user), vault.totalSupply());
    }

    function testSequentialUsersReceiveProportionalInKindPayouts() public {
        vm.prank(user);
        vault.deposit(1_000 ether, user);
        vm.prank(userTwo);
        vault.deposit(1_000 ether, userTwo);
        vm.prank(governance);
        vault.deploy(2_000 ether);
        _accrueReward(retainStock, 200 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 userShares = vault.balanceOf(user);
        uint256 userTwoShares = vault.balanceOf(userTwo);
        vm.prank(user);
        vault.redeemInKind(userShares, user, user);
        vm.prank(userTwo);
        vault.redeemInKind(userTwoShares, userTwo, userTwo);

        assertEq(retainStock.balanceOf(user), 100 ether);
        assertEq(retainStock.balanceOf(userTwo), 100 ether);
        assertEq(strategy.retainedBalance(address(retainStock)), 0);
        assertEq(vault.strategyDebt(), 0);
    }

    function testInKindRedemptionRemainsAvailableWhenStrategyPaused() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();
        vm.prank(governance);
        strategy.pause();

        uint256 shares = vault.balanceOf(user) / 10;
        vm.prank(user);
        vault.redeemInKind(shares, user, user);

        assertEq(retainStock.balanceOf(user), 10 ether);
    }

    function testMixedRedemptionLifecycleIntegration() public {
        vm.prank(user);
        vault.deposit(1_000 ether, user);
        vm.prank(userTwo);
        vault.deposit(1_000 ether, userTwo);
        vm.prank(governance);
        vault.deploy(2_000 ether);

        _accrueReward(retainStock, 200 ether);
        _accrueReward(sellStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();
        assertEq(strategy.retainedBalance(address(retainStock)), 200 ether);
        assertEq(vault.strategyDebt(), 2_200 ether);

        vm.warp(block.timestamp + vault.profitMaxUnlockTime());
        _refreshOracles();
        vm.prank(user);
        vault.withdraw(200 ether, user, user, 0);
        assertEq(retainStock.balanceOf(user), 0);
        assertEq(strategy.retainedBalance(address(retainStock)), 200 ether);

        uint256 userTwoShares = vault.balanceOf(userTwo) / 2;
        (, uint256 expectedUserTwoStock) = _previewSingleRetained(userTwoShares);
        vm.prank(userTwo);
        vault.redeemInKind(userTwoShares, userTwo, userTwo);
        assertEq(retainStock.balanceOf(userTwo), expectedUserTwoStock);
        assertEq(strategy.retainedBalance(address(retainStock)), 200 ether - expectedUserTwoStock);

        _accrueReward(retainStock, 50 ether);
        vm.prank(governance);
        strategy.harvest();
        assertEq(strategy.retainedBalance(address(retainStock)), 250 ether - expectedUserTwoStock);

        uint256 remainingUserShares = vault.balanceOf(user);
        vm.prank(user);
        vault.redeemInKind(remainingUserShares, user, user);
        uint256 remainingUserTwoShares = vault.balanceOf(userTwo);
        vm.prank(userTwo);
        vault.redeemInKind(remainingUserTwoShares, userTwo, userTwo);

        assertEq(vault.totalSupply(), 0);
        assertEq(vault.strategyDebt(), 0);
        assertEq(strategy.retainedBalance(address(retainStock)), 0);
        assertEq(retainStock.balanceOf(address(strategy)), 0);
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

    function _previewSingleRetained(uint256 shares)
        private
        view
        returns (uint256 indexPreview, uint256 retainedPreview)
    {
        InKindRedemptionResult memory preview = strategy.previewInKindRedemption(shares);
        require(preview.retainedTokens.length == 1 && preview.retainedTokens[0] == address(retainStock));
        retainedPreview = preview.retainedAmounts[0];
        indexPreview = preview.indexPaid + index.balanceOf(address(vault)) * shares / vault.totalSupply();
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
            feed: feed,
            heartbeat: 1 hours,
            decimals: 8,
            maxDeviationBps: 500,
            uiMultiplier: 1e18,
            paused: paused
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

    function testInKindRedeemSingleShare() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 shares = 1;
        uint256 supplyBefore = vault.totalSupply();
        uint256 debtBefore = vault.strategyDebt();
        (uint256 indexPreview, uint256 retainedPreview) = _previewSingleRetained(shares);

        uint256 receiverIndexBefore = index.balanceOf(receiver);
        uint256 receiverStockBefore = retainStock.balanceOf(receiver);

        vm.prank(user);
        vault.redeemInKind(shares, receiver, user);

        assertEq(index.balanceOf(receiver) - receiverIndexBefore, indexPreview);
        assertEq(retainStock.balanceOf(receiver) - receiverStockBefore, retainedPreview);
        assertEq(strategy.retainedBalance(address(retainStock)), 100 ether - retainedPreview);
        assertEq(vault.strategyDebt(), debtBefore - debtBefore * shares / supplyBefore);
    }

    function testInKindRedeem99Percent() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 shares = (vault.balanceOf(user) * 99) / 100;
        uint256 supplyBefore = vault.totalSupply();
        uint256 debtBefore = vault.strategyDebt();
        (uint256 indexPreview, uint256 retainedPreview) = _previewSingleRetained(shares);

        uint256 receiverIndexBefore = index.balanceOf(receiver);
        uint256 receiverStockBefore = retainStock.balanceOf(receiver);

        vm.prank(user);
        vault.redeemInKind(shares, receiver, user);

        assertEq(index.balanceOf(receiver) - receiverIndexBefore, indexPreview);
        assertEq(retainStock.balanceOf(receiver) - receiverStockBefore, retainedPreview);
        // Assert that dust/remaining assets still exist in the strategy
        assertEq(strategy.retainedBalance(address(retainStock)), 100 ether - retainedPreview);
        assertEq(vault.strategyDebt(), debtBefore - debtBefore * shares / supplyBefore);
        assertGt(strategy.retainedBalance(address(retainStock)), 0);
    }

    function testSequentialPartialRedemptionsSameUser() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 userShares = vault.balanceOf(user);
        uint256 chunk = userShares / 3;

        // 1st partial redeem
        vm.prank(user);
        vault.redeemInKind(chunk, user, user);

        // 2nd partial redeem
        vm.prank(user);
        vault.redeemInKind(chunk, user, user);

        // 3rd redeem (remaining)
        uint256 remainingShares = vault.balanceOf(user);
        vm.prank(user);
        vault.redeemInKind(remainingShares, user, user);

        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(strategy.retainedBalance(address(retainStock)), 0);
        assertEq(retainStock.balanceOf(address(strategy)), 0);
        assertEq(vault.strategyDebt(), 0);
        assertEq(retainStock.balanceOf(user), 100 ether);
    }

    function testLastUserReceivesDust() public {
        vm.prank(user);
        vault.deposit(3 ether, user);
        vm.prank(userTwo);
        vault.deposit(3 ether, userTwo);
        vm.prank(governance);
        vault.deploy(6 ether);

        // accrue 1 wei which creates division dust
        _accrueReward(retainStock, 1 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 userShares = vault.balanceOf(user);
        uint256 userTwoShares = vault.balanceOf(userTwo);

        // User 1 redeems
        vm.prank(user);
        vault.redeemInKind(userShares, user, user);

        // User 2 redeems all remaining
        vm.prank(userTwo);
        vault.redeemInKind(userTwoShares, userTwo, userTwo);

        assertEq(vault.totalSupply(), 0);
        assertEq(strategy.retainedBalance(address(retainStock)), 0);
        assertEq(retainStock.balanceOf(address(strategy)), 0);
        assertEq(vault.strategyDebt(), 0);
        // Total transferred stocks should sum to exactly what was accrued (1 ether)
        assertEq(retainStock.balanceOf(user) + retainStock.balanceOf(userTwo), 1 ether);
    }

    function testInKindRedeemZeroRetainedAssets() public {
        _depositAndDeploy(1_000 ether);
        // No rewards accrued/retained
        uint256 shares = vault.balanceOf(user) / 2;

        vm.prank(user);
        InKindRedemptionResult memory result = vault.redeemInKind(shares, user, user);

        assertEq(result.retainedTokens.length, 0); // no tokens retained
        assertEq(result.indexPaid, 500 ether);
    }

    function testInKindRedeemManyRetainedAssets() public {
        MockStockToken extraStock = new MockStockToken("Extra Stock", "mEXT", 18);
        MockOracle extraFeed = new MockOracle(8, 1e8);

        vm.startPrank(governance);
        oracleRegistry.setOracleConfig(address(extraStock), _oracleConfig(address(extraFeed), false));
        router.setRoute(address(dex), address(extraStock), address(index), true, 500);
        rewardRegistry.setRewardTokenConfig(
            address(extraStock), _rewardConfig(RewardDisposition.Retain, address(extraFeed), 0)
        );
        strategy.addRewardToken(address(extraStock));
        vm.stopPrank();

        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        _accrueReward(extraStock, 50 ether);

        vm.prank(governance);
        strategy.harvest();

        assertEq(strategy.retainedBalance(address(retainStock)), 100 ether);
        assertEq(strategy.retainedBalance(address(extraStock)), 50 ether);

        uint256 shares = vault.balanceOf(user) / 2;

        uint256 userStockBefore = retainStock.balanceOf(user);
        uint256 userExtraBefore = extraStock.balanceOf(user);

        vm.prank(user);
        vault.redeemInKind(shares, user, user);

        assertEq(retainStock.balanceOf(user) - userStockBefore, 50 ether);
        assertEq(extraStock.balanceOf(user) - userExtraBefore, 25 ether);
    }

    function testInKindRedeemTinyBalances() public {
        // Change retainStock minHarvestAmount to 1 wei
        vm.prank(governance);
        rewardRegistry.setRewardTokenConfig(
            address(retainStock),
            RewardTokenConfig({
                enabled: true,
                category: RewardCategory.Equity,
                disposition: RewardDisposition.Retain,
                oracle: address(retainFeed),
                minHarvestAmount: 1, // 1 wei
                retainable: true,
                adapter: address(dex),
                maxExposureBps: 0
            })
        );

        _depositAndDeploy(1_000 ether);
        // Accrue extremely tiny balance (e.g. 10 wei)
        _accrueReward(retainStock, 10 wei);
        vm.prank(governance);
        strategy.harvest();

        uint256 shares = vault.balanceOf(user) / 3; // 1/3 shares
        vm.prank(user);
        vault.redeemInKind(shares, user, user);

        // 10 * 1/3 = 3 wei (floor rounded)
        assertEq(retainStock.balanceOf(user), 3 wei);
        assertEq(strategy.retainedBalance(address(retainStock)), 7 wei);
    }

    function testInKindRedeemLargeBalances() public {
        uint256 largeAmount = 10_000_000_000 ether;
        index.mint(user, largeAmount * 2);
        vm.prank(user);
        index.approve(address(vault), type(uint256).max);

        _depositAndDeploy(largeAmount * 2);

        // Accrue huge balance
        _accrueReward(retainStock, largeAmount);
        vm.prank(governance);
        strategy.harvest();

        uint256 shares = vault.balanceOf(user) / 2;
        vm.prank(user);
        vault.redeemInKind(shares, user, user);

        assertEq(retainStock.balanceOf(user), largeAmount / 2);
    }

    function testFeeOnTransferTokenRejection() public {
        MockFeeOnTransferToken feeToken = new MockFeeOnTransferToken("Fee Token", "mFEE", 18, 100); // 1% fee
        MockOracle feeFeed = new MockOracle(8, 1e8);

        vm.startPrank(governance);
        oracleRegistry.setOracleConfig(address(feeToken), _oracleConfig(address(feeFeed), false));
        router.setRoute(address(dex), address(feeToken), address(index), true, 500);
        rewardRegistry.setRewardTokenConfig(
            address(feeToken), _rewardConfig(RewardDisposition.Retain, address(feeFeed), 0)
        );
        strategy.addRewardToken(address(feeToken));
        vm.stopPrank();

        _depositAndDeploy(1_000 ether);

        // Accrue fee token
        feeToken.mint(address(indexFinance), 100 ether);
        indexFinance.accrue(address(strategy), address(feeToken), 100 ether);

        vm.prank(governance);
        strategy.harvest();

        // 100 ether was claimed, but because of 1% transfer fee, the strategy only gets 99 ether
        assertEq(strategy.retainedBalance(address(feeToken)), 99 ether);

        uint256 shares = vault.balanceOf(user) / 2;

        vm.prank(user);
        // Should revert because the strategy transfers 49.5 ether, but receiver only gets 49.005 ether
        vm.expectRevert(
            abi.encodeWithSelector(
                GrowthStrategy.FeeOnTransferDetected.selector, address(feeToken), 49.5 ether, 49.005 ether
            )
        );
        vault.redeemInKind(shares, user, user);
    }

    function testInKindRedeemZeroSharesReverts() public {
        _depositAndDeploy(1_000 ether);
        vm.prank(user);
        vm.expectRevert(RobinVault.ZeroShares.selector);
        vault.redeemInKind(0, user, user);
    }

    function testInKindRedeemZeroReceiverReverts() public {
        _depositAndDeploy(1_000 ether);
        vm.prank(user);
        vm.expectRevert(ZeroAddress.selector);
        vault.redeemInKind(10 ether, address(0), user);
    }

    function testInKindRedeemInsufficientAllowanceReverts() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 shares = vault.balanceOf(user);

        vm.prank(userTwo); // userTwo trying to redeem user's shares without allowance
        vm.expectRevert();
        vault.redeemInKind(shares, userTwo, user);
    }

    function testPreviewMatchesEventMatchesReceiverDelta() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 shares = vault.balanceOf(user) / 2;

        InKindRedemptionResult memory preview = vault.previewInKindRedeem(shares);

        uint256 receiverIndexBefore = index.balanceOf(receiver);
        uint256 receiverStockBefore = retainStock.balanceOf(receiver);

        vm.expectEmit(true, true, false, true, address(vault));
        emit RobinVault.InKindRedeem(
            user, receiver, shares, preview.indexPaid, preview.retainedTokens, preview.retainedAmounts
        );

        vm.prank(user);
        vault.redeemInKind(shares, receiver, user);

        assertEq(index.balanceOf(receiver) - receiverIndexBefore, preview.indexPaid);
        assertEq(retainStock.balanceOf(receiver) - receiverStockBefore, preview.retainedAmounts[0]);
    }

    function testDebtReductionProportionalToSharesBurned() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        uint256 shares = vault.balanceOf(user) / 4;
        uint256 supplyBefore = vault.totalSupply();
        uint256 debtBefore = vault.strategyDebt();

        vm.prank(user);
        InKindRedemptionResult memory result = vault.redeemInKind(shares, receiver, user);

        uint256 expectedDebtReduction = debtBefore * shares / supplyBefore;
        assertEq(result.debtReduction, expectedDebtReduction);
        assertEq(vault.strategyDebt(), debtBefore - expectedDebtReduction);
    }

    function testNavConservationInvariant() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        // Pre-redemption assets
        uint256 preVaultIndex = index.balanceOf(address(vault));
        uint256 preStrategyIndex = index.balanceOf(address(strategy)) + strategy.deployedAssets();
        uint256 preRetainedValue = strategy.retainedValue(address(retainStock));
        uint256 preTotalNav = preVaultIndex + preStrategyIndex + preRetainedValue;

        uint256 shares = vault.balanceOf(user) / 3;

        uint256 receiverIndexBefore = index.balanceOf(receiver);
        uint256 receiverStockBefore = retainStock.balanceOf(receiver);

        vm.prank(user);
        vault.redeemInKind(shares, receiver, user);

        uint256 receiverIndexGained = index.balanceOf(receiver) - receiverIndexBefore;
        // Payout stock value in INDEX
        uint256 receiverStockGained = retainStock.balanceOf(receiver) - receiverStockBefore;
        (uint256 stockPriceIn,) = oracleRegistry.getValidatedPrice(address(retainStock));
        (uint256 stockPriceOut,) = oracleRegistry.getValidatedPrice(address(index));
        uint256 redeemedStockValue = receiverStockGained.mulDiv(stockPriceIn, stockPriceOut);

        uint256 totalRedeemedValue = receiverIndexGained + redeemedStockValue;

        // Post-redemption assets
        uint256 postVaultIndex = index.balanceOf(address(vault));
        uint256 postStrategyIndex = index.balanceOf(address(strategy)) + strategy.deployedAssets();
        uint256 postRetainedValue = strategy.retainedValue(address(retainStock));
        uint256 postTotalNav = postVaultIndex + postStrategyIndex + postRetainedValue;

        // Check conservation: preTotalNav == postTotalNav + totalRedeemedValue within floor-rounding dust
        assertApproxEqAbs(preTotalNav, postTotalNav + totalRedeemedValue, 10);
    }


    function testCategoryRetentionSplitBelowTargetRetainsMax() public {
        vm.startPrank(governance);
        strategy.setCategoryPolicy(
            RewardCategory.Equity,
            CategoryPolicy({
                targetRetainBps: 5_000,
                minRetainBps: 2_000,
                maxRetainBps: 8_000,
                maxPortfolioBps: 10_000,
                rebalanceCooldown: 1 days
            })
        );
        vm.stopPrank();

        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        // Category exposure is 0 before first retention => below target => maxRetainBps (8000) applies.
        // 80% of 100 ether = 80 ether retained, 20 ether sold.
        uint256 retained = strategy.retainedBalance(address(retainStock));
        assertEq(retained, 80 ether);
    }

    function testLiquidationOrderIsHonored() public {
        MockStockToken secondStock = new MockStockToken("Mock Tesla", "mTSLA", 18);
        MockOracle secondFeed = new MockOracle(8, 1e8);

        vm.startPrank(governance);
        oracleRegistry.setOracleConfig(address(secondStock), _oracleConfig(address(secondFeed), false));
        router.setRoute(address(dex), address(secondStock), address(index), true, 500);
        rewardRegistry.setAdapterApproval(address(secondStock), address(dex), true);
        rewardRegistry.setRewardTokenConfig(
            address(secondStock), _rewardConfig(RewardDisposition.Retain, address(secondFeed), 0)
        );
        strategy.addRewardToken(address(secondStock));
        address[] memory order = new address[](2);
        order[0] = address(secondStock);
        order[1] = address(retainStock);
        strategy.setLiquidationOrder(order);
        vm.stopPrank();

        dex.setRate(address(secondStock), address(index), 1e18);
        secondStock.mint(address(dex), 1_000_000 ether);

        _depositAndDeploy(1_000 ether);
        _accrueReward(retainStock, 100 ether);
        _accrueReward(secondStock, 100 ether);
        vm.prank(governance);
        strategy.harvest();

        // Slash the Index Finance position so deployed INDEX cannot fully cover the withdrawal,
        // forcing the strategy to liquidate retained assets in governance-approved order.
        indexFinance.slash(address(strategy), 900 ether);

        vm.warp(block.timestamp + vault.profitMaxUnlockTime());
        _refreshOracles();
        secondFeed.setRoundData(
            secondFeed.roundId() + 1, 1e8, block.timestamp, block.timestamp, secondFeed.roundId() + 1
        );

        vm.prank(user);
        vault.withdraw(150 ether, user, user, 500);

        assertLt(secondStock.balanceOf(address(strategy)), 100 ether);
        assertEq(retainStock.balanceOf(address(strategy)), 100 ether);
    }

    function _policy(uint16 maxPortfolioBps) private pure returns (CategoryPolicy memory policy) {
        policy = CategoryPolicy({
            targetRetainBps: 10_000,
            minRetainBps: 10_000,
            maxRetainBps: 10_000,
            maxPortfolioBps: maxPortfolioBps,
            rebalanceCooldown: 1 days
        });
    }
}
