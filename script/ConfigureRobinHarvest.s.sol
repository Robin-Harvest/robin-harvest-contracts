// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {AccessManager} from "../src/access/AccessManager.sol";
import {RobinAccountant} from "../src/accounting/RobinAccountant.sol";
import {ExecutionRouter} from "../src/router/ExecutionRouter.sol";
import {OracleRegistry} from "../src/registries/OracleRegistry.sol";
import {RewardRegistry} from "../src/registries/RewardRegistry.sol";
import {CoreStrategy} from "../src/strategies/CoreStrategy.sol";
import {GrowthStrategy} from "../src/strategies/GrowthStrategy.sol";
import {ConcentratedLiquidityStrategy} from "../src/strategies/ConcentratedLiquidityStrategy.sol";
import {StrategyBase} from "../src/strategies/StrategyBase.sol";
import {RobinVault} from "../src/vaults/RobinVault.sol";
import {Constants} from "../src/libraries/Constants.sol";
import {
    FeeConfig,
    OracleConfig,
    RewardCategory,
    RewardDisposition,
    RewardTokenConfig
} from "../src/types/ProtocolTypes.sol";

/// @notice Governance-executed, idempotent production initialization for a deployed Robin Harvest release.
/// @dev Run through the governance multisig. The deployment EOA is not expected to hold protocol authority.
contract ConfigureRobinHarvest is Script {
    struct Addresses {
        address manager;
        address oracleRegistry;
        address rewardRegistry;
        address router;
        address coreVault;
        address coreStrategy;
        address coreAccountant;
        address growthVault;
        address growthStrategy;
        address growthAccountant;
        address clVault;
        address clStrategy;
        address clAccountant;
    }

    struct RoleHolders {
        address governance;
        address strategyManager;
        address keeper;
        address oracleManager;
        address rewardManager;
        address securityCouncil;
    }

    struct OracleEntry {
        address asset;
        OracleConfig config;
    }

    struct RewardEntry {
        address token;
        RewardTokenConfig config;
    }

    struct RouteEntry {
        address adapter;
        address tokenIn;
        address tokenOut;
        bool enabled;
        uint16 maxOracleDeviationBps;
    }

    struct InitConfig {
        Addresses addresses;
        RoleHolders roles;
        address feeRecipient;
        uint256 eligibilityThreshold;
        uint256 strategyMigrationDelay;
        FeeConfig feeConfig;
        address[] approvedDexAdapters;
        OracleEntry[] oracles;
        RewardEntry[] rewards;
        RouteEntry[] routes;
        address swapAdapter;
    }

    error LengthMismatch(bytes32 listName);
    error InvalidAddress(bytes32 key);
    error ExistingConfiguration(bytes32 key, address expected, address actual);
    error InvalidBps(uint256 value);

    function run() external virtual {
        InitConfig memory config = _loadConfig();
        vm.startBroadcast();
        _configure(config);
        vm.stopBroadcast();
    }

    function _configure(InitConfig memory config) internal {
        _validateBaseConfig(config);
        AccessManager manager = AccessManager(config.addresses.manager);

        _ensureRole(manager, manager.GOVERNANCE_ROLE(), config.roles.governance);
        _ensureRole(manager, manager.SECURITY_COUNCIL_ROLE(), config.roles.governance);
        _ensureRole(manager, manager.STRATEGY_MANAGER_ROLE(), config.roles.governance);
        _ensureRole(manager, manager.KEEPER_ROLE(), config.roles.governance);
        _ensureRole(manager, manager.ORACLE_MANAGER_ROLE(), config.roles.governance);
        _ensureRole(manager, manager.REWARD_MANAGER_ROLE(), config.roles.governance);
        _ensureRole(manager, manager.SECURITY_COUNCIL_ROLE(), config.roles.securityCouncil);
        _ensureRole(manager, manager.STRATEGY_MANAGER_ROLE(), config.roles.strategyManager);
        _ensureRole(manager, manager.KEEPER_ROLE(), config.roles.keeper);
        _ensureRole(manager, manager.ORACLE_MANAGER_ROLE(), config.roles.oracleManager);
        _ensureRole(manager, manager.REWARD_MANAGER_ROLE(), config.roles.rewardManager);

        _configureSelectorRoles(config, manager);
        _configureVault(
            config.addresses.coreVault,
            config.addresses.coreStrategy,
            config.addresses.coreAccountant,
            config.feeRecipient,
            config.eligibilityThreshold,
            config.strategyMigrationDelay,
            config.feeConfig
        );
        _configureVault(
            config.addresses.growthVault,
            config.addresses.growthStrategy,
            config.addresses.growthAccountant,
            config.feeRecipient,
            config.eligibilityThreshold,
            config.strategyMigrationDelay,
            config.feeConfig
        );
        _configureVault(
            config.addresses.clVault,
            config.addresses.clStrategy,
            config.addresses.clAccountant,
            config.feeRecipient,
            config.eligibilityThreshold,
            config.strategyMigrationDelay,
            config.feeConfig
        );

        _configureExternalPolicies(config);
    }

    function _configureSelectorRoles(InitConfig memory config, AccessManager manager) internal {
        _setVaultSelectorRoles(manager, config.addresses.coreVault);
        _setVaultSelectorRoles(manager, config.addresses.growthVault);
        _setVaultSelectorRoles(manager, config.addresses.clVault);
        _setStrategySelectorRoles(manager, config.addresses.coreStrategy);
        _setStrategySelectorRoles(manager, config.addresses.growthStrategy);
        _setStrategySelectorRoles(manager, config.addresses.clStrategy);
        _setGrowthSelectorRoles(manager, config.addresses.growthStrategy);
        _setConcentratedSelectorRoles(manager, config.addresses.clStrategy);
        _setRegistryAndRouterSelectorRoles(manager, config);
    }

    function _configureVault(
        address vault_,
        address strategy_,
        address accountant_,
        address feeRecipient_,
        uint256 eligibilityThreshold_,
        uint256 strategyMigrationDelay_,
        FeeConfig memory feeConfig_
    ) internal {
        RobinVault vault = RobinVault(vault_);
        RobinAccountant accountant = RobinAccountant(accountant_);

        address configuredStrategy = address(vault.strategy());
        if (configuredStrategy == address(0)) {
            vault.setStrategy(strategy_);
        } else if (configuredStrategy != strategy_) {
            revert ExistingConfiguration("VAULT_STRATEGY", strategy_, configuredStrategy);
        }

        vault.setAccountant(accountant_);
        vault.setEligibilityThreshold(eligibilityThreshold_);
        vault.setStrategyMigrationDelay(strategyMigrationDelay_);

        address configuredVault = accountant.vault();
        if (configuredVault == address(0)) {
            accountant.setVault(vault_);
        } else if (configuredVault != vault_) {
            revert ExistingConfiguration("ACCOUNTANT_VAULT", vault_, configuredVault);
        }
        accountant.setFeeRecipient(feeRecipient_);
        accountant.setFeeConfig(feeConfig_);
    }

    function _configureExternalPolicies(InitConfig memory config) internal {
        ExecutionRouter router = ExecutionRouter(config.addresses.router);
        OracleRegistry oracleRegistry = OracleRegistry(config.addresses.oracleRegistry);
        RewardRegistry rewardRegistry = RewardRegistry(config.addresses.rewardRegistry);

        if (config.swapAdapter != address(0)) {
            ConcentratedLiquidityStrategy(config.addresses.clStrategy).setSwapRoute(config.swapAdapter);
        }

        for (uint256 i; i < config.approvedDexAdapters.length; ++i) {
            router.setAdapterApproval(config.approvedDexAdapters[i], true);
        }
        for (uint256 i; i < config.routes.length; ++i) {
            RouteEntry memory route = config.routes[i];
            router.setRoute(route.adapter, route.tokenIn, route.tokenOut, route.enabled, route.maxOracleDeviationBps);
        }
        for (uint256 i; i < config.oracles.length; ++i) {
            oracleRegistry.setOracleConfig(config.oracles[i].asset, config.oracles[i].config);
        }
        for (uint256 i; i < config.rewards.length; ++i) {
            if (config.rewards[i].config.adapter != address(0)) {
                rewardRegistry.setAdapterApproval(config.rewards[i].token, config.rewards[i].config.adapter, true);
            }
            rewardRegistry.setRewardTokenConfig(config.rewards[i].token, config.rewards[i].config);
        }
    }

    function _ensureRole(AccessManager manager, uint64 role, address account) internal {
        (bool hasRole,) = manager.hasRole(role, account);
        if (!hasRole) manager.grantRole(role, account, 0);
    }

    function _setVaultSelectorRoles(AccessManager manager, address vault) internal {
        bytes4[] memory strategySelectors = new bytes4[](11);
        strategySelectors[0] = RobinVault.setStrategy.selector;
        strategySelectors[1] = RobinVault.setStrategyMigrationDelay.selector;
        strategySelectors[2] = RobinVault.proposeStrategyMigration.selector;
        strategySelectors[3] = RobinVault.executeStrategyMigration.selector;
        strategySelectors[4] = RobinVault.cancelStrategyMigration.selector;
        strategySelectors[5] = RobinVault.setAccountant.selector;
        strategySelectors[6] = RobinVault.setDepositCap.selector;
        strategySelectors[7] = RobinVault.setIdleBufferBps.selector;
        strategySelectors[8] = RobinVault.setDefaultMaxLossBps.selector;
        strategySelectors[9] = RobinVault.setProfitMaxUnlockTime.selector;
        strategySelectors[10] = RobinVault.setEligibilityThreshold.selector;
        manager.setTargetFunctionRole(vault, strategySelectors, manager.STRATEGY_MANAGER_ROLE());

        bytes4[] memory keeperSelectors = new bytes4[](2);
        keeperSelectors[0] = RobinVault.deploy.selector;
        keeperSelectors[1] = RobinVault.deployIdle.selector;
        manager.setTargetFunctionRole(vault, keeperSelectors, manager.KEEPER_ROLE());

        bytes4[] memory securitySelectors = new bytes4[](4);
        securitySelectors[0] = RobinVault.pause.selector;
        securitySelectors[1] = RobinVault.unpause.selector;
        securitySelectors[2] = RobinVault.shutdown.selector;
        securitySelectors[3] = RobinVault.setMinPostWithdrawAssets.selector;
        manager.setTargetFunctionRole(vault, securitySelectors, manager.SECURITY_COUNCIL_ROLE());
    }

    function _setStrategySelectorRoles(AccessManager manager, address strategy) internal {
        bytes4[] memory strategySelectors = new bytes4[](1);
        strategySelectors[0] = CoreStrategy.setCoreParameters.selector;
        manager.setTargetFunctionRole(strategy, strategySelectors, manager.STRATEGY_MANAGER_ROLE());

        bytes4[] memory keeperSelectors = new bytes4[](2);
        keeperSelectors[0] = StrategyBase.harvest.selector;
        keeperSelectors[1] = StrategyBase.tend.selector;
        manager.setTargetFunctionRole(strategy, keeperSelectors, manager.KEEPER_ROLE());

        bytes4[] memory rewardSelectors = new bytes4[](3);
        rewardSelectors[0] = StrategyBase.addRewardToken.selector;
        rewardSelectors[1] = StrategyBase.removeRewardToken.selector;
        rewardSelectors[2] = StrategyBase.setRewardTokenIsolated.selector;
        manager.setTargetFunctionRole(strategy, rewardSelectors, manager.REWARD_MANAGER_ROLE());

        bytes4[] memory securitySelectors = new bytes4[](4);
        securitySelectors[0] = StrategyBase.pause.selector;
        securitySelectors[1] = StrategyBase.unpause.selector;
        securitySelectors[2] = StrategyBase.shutdown.selector;
        securitySelectors[3] = StrategyBase.emergencyWithdraw.selector;
        manager.setTargetFunctionRole(strategy, securitySelectors, manager.SECURITY_COUNCIL_ROLE());
    }

    function _setGrowthSelectorRoles(AccessManager manager, address growthStrategy) internal {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = GrowthStrategy.setCategoryPolicy.selector;
        selectors[1] = GrowthStrategy.setLiquidationOrder.selector;
        selectors[2] = GrowthStrategy.setNavHaircutBps.selector;
        selectors[3] = GrowthStrategy.markRebalance.selector;
        manager.setTargetFunctionRole(growthStrategy, selectors, manager.STRATEGY_MANAGER_ROLE());
    }

    function _setConcentratedSelectorRoles(AccessManager manager, address clStrategy) internal {
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = ConcentratedLiquidityStrategy.setPolicy.selector;
        selectors[1] = ConcentratedLiquidityStrategy.setRiskParameters.selector;
        selectors[2] = ConcentratedLiquidityStrategy.setAutoCompound.selector;
        selectors[3] = ConcentratedLiquidityStrategy.setSwapRoute.selector;
        selectors[4] = ConcentratedLiquidityStrategy.enterWithdrawOnly.selector;
        selectors[5] = ConcentratedLiquidityStrategy.enterHarvestOnly.selector;
        manager.setTargetFunctionRole(clStrategy, selectors, manager.STRATEGY_MANAGER_ROLE());

        bytes4[] memory keeperSelectors = new bytes4[](1);
        keeperSelectors[0] = ConcentratedLiquidityStrategy.rebalance.selector;
        manager.setTargetFunctionRole(clStrategy, keeperSelectors, manager.KEEPER_ROLE());

        bytes4[] memory securitySelectors = new bytes4[](2);
        securitySelectors[0] = ConcentratedLiquidityStrategy.emergencyClosePositions.selector;
        securitySelectors[1] = ConcentratedLiquidityStrategy.emergencyReturnAssetsToVault.selector;
        manager.setTargetFunctionRole(clStrategy, securitySelectors, manager.SECURITY_COUNCIL_ROLE());
    }

    function _setRegistryAndRouterSelectorRoles(AccessManager manager, InitConfig memory config) internal {
        bytes4[] memory oracleSelectors = new bytes4[](3);
        oracleSelectors[0] = OracleRegistry.setOracleConfig.selector;
        oracleSelectors[1] = OracleRegistry.setOraclePaused.selector;
        oracleSelectors[2] = OracleRegistry.setUiMultiplier.selector;
        manager.setTargetFunctionRole(config.addresses.oracleRegistry, oracleSelectors, manager.ORACLE_MANAGER_ROLE());

        bytes4[] memory rewardSelectors = new bytes4[](3);
        rewardSelectors[0] = RewardRegistry.setRewardTokenConfig.selector;
        rewardSelectors[1] = RewardRegistry.disableRewardToken.selector;
        rewardSelectors[2] = RewardRegistry.setAdapterApproval.selector;
        manager.setTargetFunctionRole(config.addresses.rewardRegistry, rewardSelectors, manager.REWARD_MANAGER_ROLE());

        bytes4[] memory routerSelectors = new bytes4[](2);
        routerSelectors[0] = ExecutionRouter.setAdapterApproval.selector;
        routerSelectors[1] = ExecutionRouter.setRoute.selector;
        manager.setTargetFunctionRole(config.addresses.router, routerSelectors, manager.STRATEGY_MANAGER_ROLE());
    }

    function _validateBaseConfig(InitConfig memory config) internal pure {
        _requireAddress("MANAGER", config.addresses.manager);
        _requireAddress("GOVERNANCE", config.roles.governance);
        _requireAddress("STRATEGY_MANAGER", config.roles.strategyManager);
        _requireAddress("KEEPER", config.roles.keeper);
        _requireAddress("ORACLE_MANAGER", config.roles.oracleManager);
        _requireAddress("REWARD_MANAGER", config.roles.rewardManager);
        _requireAddress("SECURITY_COUNCIL", config.roles.securityCouncil);
        _requireAddress("FEE_RECIPIENT", config.feeRecipient);
        if (config.feeConfig.performanceBps > Constants.MAX_BPS) revert InvalidBps(config.feeConfig.performanceBps);
        if (config.feeConfig.managementBps > Constants.MAX_BPS) revert InvalidBps(config.feeConfig.managementBps);
    }

    function _requireAddress(bytes32 key, address value) internal pure {
        if (value == address(0)) revert InvalidAddress(key);
    }

    function _loadConfig() internal view returns (InitConfig memory config) {
        config.addresses = Addresses({
            manager: vm.envAddress("ACCESS_MANAGER_ADDRESS"),
            oracleRegistry: vm.envAddress("ORACLE_REGISTRY_ADDRESS"),
            rewardRegistry: vm.envAddress("REWARD_REGISTRY_ADDRESS"),
            router: vm.envAddress("EXECUTION_ROUTER_ADDRESS"),
            coreVault: vm.envAddress("CORE_VAULT_ADDRESS"),
            coreStrategy: vm.envAddress("CORE_STRATEGY_ADDRESS"),
            coreAccountant: vm.envAddress("CORE_ACCOUNTANT_ADDRESS"),
            growthVault: vm.envAddress("GROWTH_VAULT_ADDRESS"),
            growthStrategy: vm.envAddress("GROWTH_STRATEGY_ADDRESS"),
            growthAccountant: vm.envAddress("GROWTH_ACCOUNTANT_ADDRESS"),
            clVault: vm.envAddress("CL_VAULT_ADDRESS"),
            clStrategy: vm.envAddress("CL_STRATEGY_ADDRESS"),
            clAccountant: vm.envAddress("CL_ACCOUNTANT_ADDRESS")
        });
        config.roles = RoleHolders({
            governance: vm.envAddress("GOVERNANCE_ADDRESS"),
            strategyManager: vm.envAddress("STRATEGY_MANAGER_ADDRESS"),
            keeper: vm.envAddress("KEEPER_ADDRESS"),
            oracleManager: vm.envAddress("ORACLE_MANAGER_ADDRESS"),
            rewardManager: vm.envAddress("REWARD_MANAGER_ADDRESS"),
            securityCouncil: vm.envAddress("SECURITY_COUNCIL_ADDRESS")
        });
        config.feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");
        config.eligibilityThreshold = vm.envUint("ELIGIBILITY_THRESHOLD");
        config.strategyMigrationDelay = vm.envUint("STRATEGY_MIGRATION_DELAY");
        config.feeConfig = FeeConfig({
            performanceBps: uint16(vm.envOr("PERFORMANCE_FEE_BPS", uint256(0))),
            managementBps: uint16(vm.envOr("MANAGEMENT_FEE_BPS", uint256(0)))
        });
        config.approvedDexAdapters = vm.envOr("APPROVED_DEX_ADAPTERS", ",", new address[](0));
        config.oracles = _loadOracleEntries();
        config.rewards = _loadRewardEntries();
        config.routes = _loadRouteEntries();
        config.swapAdapter = vm.envOr("SWAP_ADAPTER_ADDRESS", address(0));
    }

    function _loadOracleEntries() private view returns (OracleEntry[] memory entries) {
        address[] memory assets = vm.envOr("ORACLE_ASSETS", ",", new address[](0));
        address[] memory feeds = vm.envOr("ORACLE_FEEDS", ",", new address[](0));
        uint256[] memory heartbeats = vm.envOr("ORACLE_HEARTBEATS", ",", new uint256[](0));
        uint256[] memory decimals_ = vm.envOr("ORACLE_DECIMALS", ",", new uint256[](0));
        uint256[] memory maxDeviationBps = vm.envOr("ORACLE_MAX_DEVIATION_BPS", ",", new uint256[](0));
        uint256[] memory uiMultipliers = vm.envOr("ORACLE_UI_MULTIPLIERS", ",", new uint256[](0));
        bool[] memory paused = vm.envOr("ORACLE_PAUSED", ",", new bool[](0));

        uint256 length = assets.length;
        if (
            feeds.length != length || heartbeats.length != length || decimals_.length != length
                || maxDeviationBps.length != length || uiMultipliers.length != length || paused.length != length
        ) revert LengthMismatch("ORACLE");

        entries = new OracleEntry[](length);
        for (uint256 i; i < length; ++i) {
            entries[i] = OracleEntry({
                asset: assets[i],
                config: OracleConfig({
                    feed: feeds[i],
                    heartbeat: uint48(heartbeats[i]),
                    decimals: uint8(decimals_[i]),
                    maxDeviationBps: uint16(maxDeviationBps[i]),
                    uiMultiplier: uiMultipliers[i],
                    paused: paused[i]
                })
            });
        }
    }

    function _loadRewardEntries() private view returns (RewardEntry[] memory entries) {
        address[] memory tokens = vm.envOr("REWARD_TOKENS", ",", new address[](0));
        bool[] memory enabled = vm.envOr("REWARD_ENABLED", ",", new bool[](0));
        uint256[] memory categories = vm.envOr("REWARD_CATEGORIES", ",", new uint256[](0));
        uint256[] memory dispositions = vm.envOr("REWARD_DISPOSITIONS", ",", new uint256[](0));
        address[] memory oracles = vm.envOr("REWARD_ORACLES", ",", new address[](0));
        uint256[] memory minHarvestAmounts = vm.envOr("REWARD_MIN_HARVEST_AMOUNTS", ",", new uint256[](0));
        bool[] memory retainable = vm.envOr("REWARD_RETAINABLE", ",", new bool[](0));
        address[] memory adapters = vm.envOr("REWARD_ADAPTERS", ",", new address[](0));
        uint256[] memory maxExposureBps = vm.envOr("REWARD_MAX_EXPOSURE_BPS", ",", new uint256[](0));

        uint256 length = tokens.length;
        if (
            enabled.length != length || categories.length != length || dispositions.length != length
                || oracles.length != length || minHarvestAmounts.length != length || retainable.length != length
                || adapters.length != length || maxExposureBps.length != length
        ) revert LengthMismatch("REWARD");

        entries = new RewardEntry[](length);
        for (uint256 i; i < length; ++i) {
            entries[i] = RewardEntry({
                token: tokens[i],
                config: RewardTokenConfig({
                    enabled: enabled[i],
                    category: RewardCategory(categories[i]),
                    disposition: RewardDisposition(dispositions[i]),
                    oracle: oracles[i],
                    minHarvestAmount: minHarvestAmounts[i],
                    retainable: retainable[i],
                    adapter: adapters[i],
                    maxExposureBps: uint16(maxExposureBps[i])
                })
            });
        }
    }

    function _loadRouteEntries() private view returns (RouteEntry[] memory entries) {
        address[] memory adapters = vm.envOr("ROUTE_ADAPTERS", ",", new address[](0));
        address[] memory tokenIns = vm.envOr("ROUTE_TOKEN_INS", ",", new address[](0));
        address[] memory tokenOuts = vm.envOr("ROUTE_TOKEN_OUTS", ",", new address[](0));
        bool[] memory enabled = vm.envOr("ROUTE_ENABLED", ",", new bool[](0));
        uint256[] memory maxDeviationBps = vm.envOr("ROUTE_MAX_ORACLE_DEVIATION_BPS", ",", new uint256[](0));

        uint256 length = adapters.length;
        if (
            tokenIns.length != length || tokenOuts.length != length || enabled.length != length
                || maxDeviationBps.length != length
        ) revert LengthMismatch("ROUTE");

        entries = new RouteEntry[](length);
        for (uint256 i; i < length; ++i) {
            entries[i] = RouteEntry({
                adapter: adapters[i],
                tokenIn: tokenIns[i],
                tokenOut: tokenOuts[i],
                enabled: enabled[i],
                maxOracleDeviationBps: uint16(maxDeviationBps[i])
            });
        }
    }
}
