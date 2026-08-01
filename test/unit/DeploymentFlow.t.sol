// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {DeployRobinHarvest} from "../../script/DeployRobinHarvest.s.sol";
import {ConfigureRobinHarvest} from "../../script/ConfigureRobinHarvest.s.sol";
import {ValidateRobinHarvest} from "../../script/ValidateRobinHarvest.s.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {ExecutionRouter} from "../../src/router/ExecutionRouter.sol";
import {OracleRegistry} from "../../src/registries/OracleRegistry.sol";
import {RewardRegistry} from "../../src/registries/RewardRegistry.sol";
import {ConcentratedLiquidityStrategy} from "../../src/strategies/ConcentratedLiquidityStrategy.sol";
import {StrategyBase} from "../../src/strategies/StrategyBase.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {
    FeeConfig,
    OracleConfig,
    RewardCategory,
    RewardDisposition,
    RewardTokenConfig
} from "../../src/types/ProtocolTypes.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockIndexFinanceCore} from "../mocks/MockIndexFinanceCore.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {MockV4PoolManager} from "../mocks/MockV4PoolManager.sol";
import {MockV4PositionManager} from "../mocks/MockV4PositionManager.sol";

contract DeployHarness is DeployRobinHarvest {
    function deployPublic(DeploymentConfig memory config) external returns (DeploymentAddresses memory deployed) {
        deployed = _deploy(config);
    }
}

contract ConfigureHarness is ConfigureRobinHarvest {
    function configurePublic(InitConfig memory config) external {
        _configure(config);
    }
}

contract ValidateHarness is ValidateRobinHarvest {
    function validatePublic(InitConfig memory config) external view {
        _validate(config);
    }
}

contract DeploymentFlowTest is Test {
    DeployHarness internal deployHarness;
    ConfigureHarness internal configureHarness;
    ValidateHarness internal validateHarness;

    MockINDEX internal index;
    MockStockToken internal rewardToken;
    MockOracle internal indexFeed;
    MockOracle internal rewardFeed;
    MockIndexFinanceCore internal indexFinance;

    address internal deployer = makeAddr("deployer");
    address internal strategyManager = makeAddr("strategyManager");
    address internal keeper = makeAddr("keeper");
    address internal oracleManager = makeAddr("oracleManager");
    address internal rewardManager = makeAddr("rewardManager");
    address internal securityCouncil = makeAddr("securityCouncil");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal dexAdapter = makeAddr("dexAdapter");

    function setUp() public {
        deployHarness = new DeployHarness();
        configureHarness = new ConfigureHarness();
        validateHarness = new ValidateHarness();

        index = new MockINDEX(18);
        rewardToken = new MockStockToken("Reward", "RWD", 18);
        indexFinance = new MockIndexFinanceCore(index);
        indexFeed = new MockOracle(8, 1e8);
        rewardFeed = new MockOracle(8, 2e8);
    }

    function testDeployDoesNotConfigureRestrictedStateOrRequireDeployerAsGovernance() public {
        vm.prank(deployer);
        DeployRobinHarvest.DeploymentAddresses memory deployed = _deploy(address(configureHarness));

        (bool governanceIsAdmin,) = deployed.manager.hasRole(deployed.manager.ADMIN_ROLE(), address(configureHarness));
        (bool deployerIsAdmin,) = deployed.manager.hasRole(deployed.manager.ADMIN_ROLE(), deployer);
        assertTrue(governanceIsAdmin);
        assertFalse(deployerIsAdmin);
        assertEq(address(deployed.coreVault.strategy()), address(0));
        assertEq(address(deployed.growthVault.strategy()), address(0));
        assertEq(deployed.coreAccountant.vault(), address(0));
        assertEq(deployed.growthAccountant.vault(), address(0));

        vm.prank(deployer);
        vm.expectRevert();
        deployed.coreVault.setStrategy(address(deployed.coreStrategy));
    }

    function testGovernanceInitializationConfiguresRolesWiringAndExternalPolicy() public {
        DeployRobinHarvest.DeploymentAddresses memory deployed = _deploy(address(configureHarness));
        ConfigureRobinHarvest.InitConfig memory config = _initConfig(deployed);

        configureHarness.configurePublic(config);

        _assertConfigured(deployed, config);
        validateHarness.validatePublic(config);
    }

    function testGovernanceInitializationIsIdempotent() public {
        DeployRobinHarvest.DeploymentAddresses memory deployed = _deploy(address(configureHarness));
        ConfigureRobinHarvest.InitConfig memory config = _initConfig(deployed);

        configureHarness.configurePublic(config);
        configureHarness.configurePublic(config);

        validateHarness.validatePublic(config);
    }

    function testConfigurationFailsWhenInitializerDoesNotOwnGovernanceAuthority() public {
        DeployRobinHarvest.DeploymentAddresses memory deployed = _deploy(makeAddr("governance"));
        ConfigureRobinHarvest.InitConfig memory config = _initConfig(deployed);

        vm.expectRevert();
        configureHarness.configurePublic(config);
    }

    function testValidationFailsBeforeGovernanceInitialization() public {
        DeployRobinHarvest.DeploymentAddresses memory deployed = _deploy(address(configureHarness));
        ConfigureRobinHarvest.InitConfig memory config = _initConfig(deployed);

        vm.expectRevert();
        validateHarness.validatePublic(config);
    }

    function testValidationFailsForIncorrectOwnership() public {
        DeployRobinHarvest.DeploymentAddresses memory deployed = _deploy(address(configureHarness));
        ConfigureRobinHarvest.InitConfig memory config = _initConfig(deployed);
        configureHarness.configurePublic(config);

        config.roles.keeper = makeAddr("wrongKeeper");

        vm.expectRevert();
        validateHarness.validatePublic(config);
    }

    function _deploy(address governance) private returns (DeployRobinHarvest.DeploymentAddresses memory deployed) {
        deployed = deployHarness.deployPublic(
            DeployRobinHarvest.DeploymentConfig({
                governance: governance,
                indexToken: address(index),
                indexFinance: address(indexFinance),
                maxSlippageBps: 500,
                swapDeadlineDelay: 1800,
                poolManager: address(new MockV4PoolManager()),
                positionManager: address(new MockV4PositionManager()),
                pairedToken: address(rewardToken),
                poolFee: 3_000,
                tickSpacing: 60,
                hooks: address(0),
                policyHalfWidth: 600,
                policyMinTickWidth: 120,
                policyMaxTickWidth: 2_400
            })
        );
    }

    function _initConfig(DeployRobinHarvest.DeploymentAddresses memory deployed)
        private
        view
        returns (ConfigureRobinHarvest.InitConfig memory config)
    {
        address[] memory approvedDexAdapters = new address[](1);
        approvedDexAdapters[0] = dexAdapter;

        ConfigureRobinHarvest.RouteEntry[] memory routes = new ConfigureRobinHarvest.RouteEntry[](1);
        routes[0] = ConfigureRobinHarvest.RouteEntry({
            adapter: dexAdapter,
            tokenIn: address(rewardToken),
            tokenOut: address(index),
            enabled: true,
            maxOracleDeviationBps: 500
        });

        ConfigureRobinHarvest.OracleEntry[] memory oracles = new ConfigureRobinHarvest.OracleEntry[](2);
        oracles[0] = ConfigureRobinHarvest.OracleEntry({
            asset: address(index),
            config: OracleConfig({
                feed: address(indexFeed),
                heartbeat: 1 days,
                decimals: 8,
                maxDeviationBps: 500,
                uiMultiplier: 1e18,
                paused: false
            })
        });
        oracles[1] = ConfigureRobinHarvest.OracleEntry({
            asset: address(rewardToken),
            config: OracleConfig({
                feed: address(rewardFeed),
                heartbeat: 1 days,
                decimals: 8,
                maxDeviationBps: 500,
                uiMultiplier: 1e18,
                paused: false
            })
        });

        ConfigureRobinHarvest.RewardEntry[] memory rewards = new ConfigureRobinHarvest.RewardEntry[](1);
        rewards[0] = ConfigureRobinHarvest.RewardEntry({
            token: address(rewardToken),
            config: RewardTokenConfig({
                enabled: true,
                category: RewardCategory.Equity,
                disposition: RewardDisposition.Sell,
                oracle: address(rewardFeed),
                minHarvestAmount: 1,
                retainable: false,
                adapter: dexAdapter,
                maxExposureBps: 0
            })
        });

        config = ConfigureRobinHarvest.InitConfig({
            addresses: ConfigureRobinHarvest.Addresses({
                manager: address(deployed.manager),
                oracleRegistry: address(deployed.oracleRegistry),
                rewardRegistry: address(deployed.rewardRegistry),
                router: address(deployed.router),
                coreVault: address(deployed.coreVault),
                coreStrategy: address(deployed.coreStrategy),
                coreAccountant: address(deployed.coreAccountant),
                growthVault: address(deployed.growthVault),
                growthStrategy: address(deployed.growthStrategy),
                growthAccountant: address(deployed.growthAccountant),
                clVault: address(deployed.clVault),
                clStrategy: address(deployed.clStrategy),
                clAccountant: address(deployed.clAccountant)
            }),
            roles: ConfigureRobinHarvest.RoleHolders({
                governance: address(configureHarness),
                strategyManager: strategyManager,
                keeper: keeper,
                oracleManager: oracleManager,
                rewardManager: rewardManager,
                securityCouncil: securityCouncil
            }),
            feeRecipient: feeRecipient,
            eligibilityThreshold: 10_000 ether,
            strategyMigrationDelay: 1 days,
            feeConfig: FeeConfig({performanceBps: 2_000, managementBps: 200}),
            approvedDexAdapters: approvedDexAdapters,
            oracles: oracles,
            rewards: rewards,
            routes: routes,
            swapAdapter: dexAdapter
        });
    }

    function _assertConfigured(
        DeployRobinHarvest.DeploymentAddresses memory deployed,
        ConfigureRobinHarvest.InitConfig memory config
    ) private view {
        AccessManager manager = deployed.manager;
        (bool keeperHasRole,) = manager.hasRole(manager.KEEPER_ROLE(), keeper);
        assertTrue(keeperHasRole);

        (bool keeperCanDeploy,) = manager.canCall(keeper, address(deployed.coreVault), RobinVault.deploy.selector);
        (bool keeperCanHarvest,) =
            manager.canCall(keeper, address(deployed.coreStrategy), StrategyBase.harvest.selector);
        (bool councilCanPause,) =
            manager.canCall(securityCouncil, address(deployed.growthVault), RobinVault.pause.selector);
        (bool managerCanEnterWithdrawOnly,) = manager.canCall(
            strategyManager, address(deployed.clStrategy), ConcentratedLiquidityStrategy.enterWithdrawOnly.selector
        );
        (bool managerCanEnterHarvestOnly,) = manager.canCall(
            strategyManager, address(deployed.clStrategy), ConcentratedLiquidityStrategy.enterHarvestOnly.selector
        );
        (bool councilCanEmergencyClose,) = manager.canCall(
            securityCouncil,
            address(deployed.clStrategy),
            ConcentratedLiquidityStrategy.emergencyClosePositions.selector
        );
        (bool councilCanEmergencyReturn,) = manager.canCall(
            securityCouncil,
            address(deployed.clStrategy),
            ConcentratedLiquidityStrategy.emergencyReturnAssetsToVault.selector
        );
        assertTrue(keeperCanDeploy);
        assertTrue(keeperCanHarvest);
        assertTrue(councilCanPause);
        assertTrue(managerCanEnterWithdrawOnly);
        assertTrue(managerCanEnterHarvestOnly);
        assertTrue(councilCanEmergencyClose);
        assertTrue(councilCanEmergencyReturn);

        assertEq(address(deployed.coreVault.strategy()), address(deployed.coreStrategy));
        assertEq(address(deployed.growthVault.strategy()), address(deployed.growthStrategy));
        assertEq(address(deployed.coreVault.accountant()), address(deployed.coreAccountant));
        assertEq(address(deployed.growthVault.accountant()), address(deployed.growthAccountant));
        assertEq(deployed.coreAccountant.vault(), address(deployed.coreVault));
        assertEq(deployed.growthAccountant.vault(), address(deployed.growthVault));
        assertEq(deployed.coreAccountant.feeRecipient(), feeRecipient);
        assertEq(deployed.growthAccountant.feeRecipient(), feeRecipient);
        assertEq(deployed.coreVault.eligibilityThreshold(), config.eligibilityThreshold);
        assertEq(deployed.growthVault.strategyMigrationDelay(), config.strategyMigrationDelay);

        assertTrue(deployed.router.isAdapterApproved(dexAdapter));
        assertTrue(deployed.router.isRouteApproved(dexAdapter, address(rewardToken), address(index)));
        assertEq(deployed.oracleRegistry.getOracleConfig(address(index)).feed, address(indexFeed));
        assertTrue(deployed.rewardRegistry.isAdapterApproved(address(rewardToken), dexAdapter));
        assertTrue(deployed.rewardRegistry.isRewardTokenEnabled(address(rewardToken)));
    }
}
