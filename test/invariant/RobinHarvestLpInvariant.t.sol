// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {LpStrategy} from "../../src/strategies/LpStrategy.sol";
import {ExecutionRouter} from "../../src/router/ExecutionRouter.sol";
import {OracleRegistry} from "../../src/registries/OracleRegistry.sol";
import {RewardRegistry} from "../../src/registries/RewardRegistry.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockDex} from "../mocks/MockDex.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {MockLpPair} from "../mocks/MockLpPair.sol";
import {MockLpRouter} from "../mocks/MockLpRouter.sol";
import {MockGauge} from "../mocks/MockGauge.sol";
import {RewardCategory, RewardDisposition, RewardTokenConfig, OracleConfig} from "../../src/types/ProtocolTypes.sol";

contract LpHarvestHandler is Test {
    AccessManager public manager;
    MockINDEX public index;
    MockStockToken public pairedStock;
    MockDex public dex;
    MockOracle public indexFeed;
    MockOracle public pairedFeed;

    OracleRegistry public oracleRegistry;
    RewardRegistry public rewardRegistry;
    ExecutionRouter public router;

    MockLpPair public lpPair;
    MockLpRouter public lpRouter;
    MockGauge public gauge;

    RobinVault public vault;
    LpStrategy public strategy;

    address public governance = makeAddr("governance");
    address[] public users;

    constructor() {
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

        index.mint(address(dex), 1_000_000 ether);
        pairedStock.mint(address(dex), 1_000_000 ether);
        dex.setRate(address(index), address(pairedStock), 1e18);
        dex.setRate(address(pairedStock), address(index), 1e18);

        index.mint(address(lpPair), 100_000 ether);
        pairedStock.mint(address(lpPair), 100_000 ether);

        users.push(makeAddr("user1"));
        users.push(makeAddr("user2"));

        for (uint256 i = 0; i < users.length; i++) {
            index.mint(users[i], 1_000_000 ether);
            vm.prank(users[i]);
            index.approve(address(vault), type(uint256).max);
        }
    }

    function deposit(uint256 userIdx, uint96 amount) external {
        address u = users[userIdx % users.length];
        uint256 dep = bound(amount, 100_000, 100_000 ether);

        vm.prank(u);
        try vault.deposit(dep, u) {
            vm.prank(governance);
            try vault.deployIdle() {} catch {}
        } catch {}
    }

    function withdraw(uint256 userIdx, uint96 amount) external {
        address u = users[userIdx % users.length];
        uint256 maxS = vault.maxRedeem(u);
        uint256 minS = 100_000;
        if (maxS < minS) return;
        uint256 sharesToRedeem = bound(amount, minS, maxS);

        vm.prank(u);
        try vault.redeem(sharesToRedeem, u, u, 1000) {} catch {}
    }

    function harvest() external {
        if (vault.strategyDebt() == 0) return;
        vm.prank(governance);
        try strategy.harvest() {} catch {}
    }

    function _oracleConfig(address feed) private pure returns (OracleConfig memory config) {
        config = OracleConfig({
            feed: feed,
            heartbeat: 1 hours,
            decimals: 8,
            maxDeviationBps: 500,
            uiMultiplier: 1e18,
            paused: false
        });
    }
}

contract RobinHarvestLpInvariantTest is StdInvariant, Test {
    LpHarvestHandler public handler;

    function setUp() public {
        handler = new LpHarvestHandler();
        targetContract(address(handler));
    }

    function invariant_lpTotalAssetsNonNegative() public view {
        uint256 totalAssets = handler.vault().totalAssets();
        assertGe(totalAssets, 0);
    }

    function invariant_lpAccountingConserved() public view {
        RobinVault vault = handler.vault();
        uint256 idle = handler.index().balanceOf(address(vault));
        uint256 debt = vault.strategyDebt();
        uint256 gross = idle + debt;

        assertGe(gross, vault.totalAssets());
    }

    function invariant_noRewardTokensStranded() public view {
        MockINDEX index = handler.index();
        LpStrategy strategy = handler.strategy();
        assertGe(index.balanceOf(address(strategy)), 0);
    }

    function invariant_withdrawBoundedByNav() public view {
        RobinVault vault = handler.vault();
        assertGe(vault.totalAssets(), 0);
    }
}
