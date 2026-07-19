// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {ExecutionRouter} from "../../src/router/ExecutionRouter.sol";
import {OracleRegistry} from "../../src/registries/OracleRegistry.sol";
import {RewardRegistry} from "../../src/registries/RewardRegistry.sol";
import {CoreStrategy} from "../../src/strategies/CoreStrategy.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {OracleConfig, RewardCategory, RewardDisposition, RewardTokenConfig} from "../../src/types/ProtocolTypes.sol";
import {IRobinStrategy} from "../../src/interfaces/IRobinStrategy.sol";
import {MockDex} from "../mocks/MockDex.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockIndexFinanceCore} from "../mocks/MockIndexFinanceCore.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";

contract CoreStrategyTest is Test {
    AccessManager internal manager;
    MockINDEX internal index;
    MockStockToken internal stock;
    MockStockToken internal ignoredStock;
    MockDex internal dex;
    MockOracle internal indexFeed;
    MockOracle internal stockFeed;
    MockOracle internal ignoredFeed;
    OracleRegistry internal oracleRegistry;
    RewardRegistry internal rewardRegistry;
    ExecutionRouter internal router;
    MockIndexFinanceCore internal indexFinance;
    RobinVault internal vault;
    CoreStrategy internal strategy;

    address internal governance = makeAddr("governance");
    address internal user = makeAddr("user");
    address internal receiver = makeAddr("receiver");

    function setUp() public {
        manager = new AccessManager(governance);
        index = new MockINDEX(18);
        stock = new MockStockToken("Mock Apple", "mAAPL", 18);
        ignoredStock = new MockStockToken("Mock Microsoft", "mMSFT", 18);
        dex = new MockDex();
        indexFeed = new MockOracle(8, 1e8);
        stockFeed = new MockOracle(8, 1e8);
        ignoredFeed = new MockOracle(8, 1e8);

        oracleRegistry = new OracleRegistry(address(manager));
        rewardRegistry = new RewardRegistry(address(manager));
        router = new ExecutionRouter(address(manager), oracleRegistry);
        indexFinance = new MockIndexFinanceCore(IERC20(address(index)));
        vault = new RobinVault(index, "Robin INDEX Vault", "rhINDEX", address(manager));
        strategy = new CoreStrategy(
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
        oracleRegistry.setOracleConfig(address(stock), _oracleConfig(address(stockFeed), false));
        oracleRegistry.setOracleConfig(address(ignoredStock), _oracleConfig(address(ignoredFeed), false));
        router.setAdapterApproval(address(dex), true);
        router.setRoute(address(dex), address(stock), address(index), true, 500);
        rewardRegistry.setAdapterApproval(address(stock), address(dex), true);
        rewardRegistry.setRewardTokenConfig(address(stock), _rewardConfig(RewardDisposition.Sell, address(stockFeed)));
        rewardRegistry.setRewardTokenConfig(
            address(ignoredStock), _rewardConfig(RewardDisposition.Ignore, address(ignoredFeed))
        );
        strategy.addRewardToken(address(stock));
        strategy.addRewardToken(address(ignoredStock));
        vm.stopPrank();

        indexFinance.setEligible(address(strategy), true);
        dex.setRate(address(stock), address(index), 1e18);
        index.mint(address(dex), 1_000_000 ether);

        index.mint(user, 10_000 ether);
        vm.prank(user);
        index.approve(address(vault), type(uint256).max);
    }

    function testDeployFundsDepositsIndexIntoIndexFinance() public {
        _depositAndDeploy(1_000 ether);

        assertEq(indexFinance.totalDeposited(address(strategy)), 1_000 ether);
        assertEq(strategy.deployedAssets(), 1_000 ether);
        assertEq(vault.strategyDebt(), 1_000 ether);
        assertEq(index.balanceOf(address(strategy)), 0);
    }

    function testFreeFundsReturnsIndexToVaultForWithdrawals() public {
        _depositAndDeploy(1_000 ether);

        vm.prank(user);
        vault.withdraw(250 ether, receiver, user, 0);

        assertEq(index.balanceOf(receiver), 250 ether);
        assertEq(indexFinance.totalDeposited(address(strategy)), 750 ether);
        assertEq(vault.strategyDebt(), 750 ether);
    }

    function testFreeFundsReportsWithdrawalLoss() public {
        _depositAndDeploy(1_000 ether);
        indexFinance.setNextWithdrawLoss(25 ether);

        vm.prank(user);
        vault.withdraw(250 ether, receiver, user, 1_000);

        assertEq(index.balanceOf(receiver), 250 ether);
        assertEq(vault.strategyDebt(), 725 ether);
        assertEq(indexFinance.totalDeposited(address(strategy)), 725 ether);
    }

    function testHarvestSellsRewardsCompoundsAndReportsGain() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(stock, 100 ether);

        vm.prank(governance);
        strategy.harvest();

        assertEq(index.balanceOf(address(vault)), 100 ether);
        assertEq(vault.strategyDebt(), 1_000 ether);
        assertEq(vault.lockedProfit(), 100 ether);
        assertEq(stock.balanceOf(address(strategy)), 0);
    }

    function testHarvestMinOutputAccountsForTokenDecimals() public {
        MockStockToken sixDecimalReward = new MockStockToken("Mock Six", "mSIX", 6);
        MockOracle sixDecimalFeed = new MockOracle(8, 2e8);

        vm.startPrank(governance);
        oracleRegistry.setOracleConfig(address(sixDecimalReward), _oracleConfig(address(sixDecimalFeed), false));
        router.setRoute(address(dex), address(sixDecimalReward), address(index), true, 500);
        rewardRegistry.setAdapterApproval(address(sixDecimalReward), address(dex), true);
        RewardTokenConfig memory sixDecimalConfig = _rewardConfig(RewardDisposition.Sell, address(sixDecimalFeed));
        sixDecimalConfig.minHarvestAmount = 1e6;
        rewardRegistry.setRewardTokenConfig(address(sixDecimalReward), sixDecimalConfig);
        strategy.addRewardToken(address(sixDecimalReward));
        vm.stopPrank();

        dex.setRate(address(sixDecimalReward), address(index), 2e30);
        _depositAndDeploy(1_000 ether);
        sixDecimalReward.mint(address(indexFinance), 100e6);
        indexFinance.accrue(address(strategy), address(sixDecimalReward), 100e6);

        vm.prank(governance);
        strategy.harvest();

        assertEq(index.balanceOf(address(vault)), 200 ether);
        assertEq(sixDecimalReward.balanceOf(address(strategy)), 0);
    }

    function testHarvestIgnoresConfiguredIgnoredRewards() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(ignoredStock, 50 ether);

        vm.prank(governance);
        strategy.harvest();

        assertEq(ignoredStock.balanceOf(address(strategy)), 50 ether);
        assertEq(vault.lockedProfit(), 0);
        assertEq(vault.strategyDebt(), 1_000 ether);
    }

    function testRetainRewardRevertsWithCustomError() public {
        vm.startPrank(governance);
        rewardRegistry.setRewardTokenConfig(
            address(ignoredStock), _rewardConfig(RewardDisposition.Retain, address(ignoredFeed))
        );
        vm.stopPrank();

        _depositAndDeploy(1_000 ether);
        _accrueReward(ignoredStock, 50 ether);

        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(CoreStrategy.RetainedRewardsUnsupported.selector, address(ignoredStock)));
        strategy.harvest();
    }

    function testHarvestReportsExternalPositionLoss() public {
        _depositAndDeploy(1_000 ether);
        indexFinance.slash(address(strategy), 100 ether);

        vm.prank(governance);
        strategy.harvest();

        assertEq(vault.strategyDebt(), 900 ether);
        assertEq(vault.lockedProfit(), 0);
    }

    function testDebtRepaymentPaysSoldRewardsToVault() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(stock, 25 ether);

        vm.prank(governance);
        strategy.harvest();

        assertEq(index.balanceOf(address(vault)), 25 ether);
        assertEq(indexFinance.totalDeposited(address(strategy)), 1_000 ether);
    }

    function testPauseBlocksHarvest() public {
        vm.prank(governance);
        strategy.pause();

        vm.prank(governance);
        vm.expectRevert();
        strategy.harvest();
    }

    function testShutdownBlocksNewDeployments() public {
        vm.prank(governance);
        strategy.shutdown();

        vm.prank(user);
        vault.deposit(100 ether, user);

        vm.prank(governance);
        vm.expectRevert();
        vault.deploy(100 ether);
    }

    function testUnauthorizedAccessReverts() public {
        vm.prank(user);
        vm.expectRevert();
        strategy.harvest();

        vm.prank(user);
        vm.expectRevert();
        strategy.setCoreParameters(100, 1 hours);

        vm.prank(user);
        vm.expectRevert();
        strategy.deployFunds(1 ether);
    }

    function testReentrantHarvestAttemptFailsAndOuterHarvestContinues() public {
        _depositAndDeploy(1_000 ether);

        vm.startPrank(governance);
        manager.grantRole(manager.GOVERNANCE_ROLE(), governance, 0);
        manager.grantRole(manager.KEEPER_ROLE(), governance, 0);
        manager.grantRole(manager.KEEPER_ROLE(), address(indexFinance), 0);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IRobinStrategy.harvest.selector;
        manager.setTargetFunctionRole(address(strategy), selectors, manager.KEEPER_ROLE());
        vm.stopPrank();

        indexFinance.setReentry(address(strategy), abi.encodeWithSelector(IRobinStrategy.harvest.selector));

        vm.prank(governance);
        strategy.harvest();

        assertTrue(indexFinance.reentryAttempted());
        assertFalse(indexFinance.reentrySucceeded());
    }

    function testRouterFailureIsolatesRewardToken() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(stock, 100 ether);

        vm.prank(governance);
        router.setRoute(address(dex), address(stock), address(index), false, 500);

        vm.prank(governance);
        strategy.harvest();

        assertTrue(strategy.isRewardTokenIsolated(address(stock)));
        assertEq(stock.balanceOf(address(strategy)), 100 ether);
    }

    function testOracleFailureIsolatesRewardToken() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(stock, 100 ether);

        vm.prank(governance);
        oracleRegistry.setOraclePaused(address(stock), true);

        vm.prank(governance);
        strategy.harvest();

        assertTrue(strategy.isRewardTokenIsolated(address(stock)));
    }

    function testZeroRewardEdgeCaseDoesNotReportGain() public {
        _depositAndDeploy(1_000 ether);
        indexFinance.accrue(address(strategy), address(stock), 0);

        vm.prank(governance);
        strategy.harvest();

        assertEq(vault.lockedProfit(), 0);
        assertEq(vault.strategyDebt(), 1_000 ether);
        assertFalse(strategy.isRewardTokenIsolated(address(stock)));
    }

    function testMalformedRewardClaimReverts() public {
        _depositAndDeploy(1_000 ether);
        _accrueReward(stock, 1 ether);
        indexFinance.setReturnMalformedClaim(true);

        vm.prank(governance);
        vm.expectRevert(CoreStrategy.InvalidRewardClaim.selector);
        strategy.harvest();
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

    function _oracleConfig(address feed, bool paused) private pure returns (OracleConfig memory config) {
        config = OracleConfig({
            feed: feed, heartbeat: 1 hours, decimals: 8, maxDeviationBps: 500, uiMultiplier: 1e18, paused: paused
        });
    }

    function _rewardConfig(RewardDisposition disposition, address oracle)
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
            maxExposureBps: 0
        });
    }
}
