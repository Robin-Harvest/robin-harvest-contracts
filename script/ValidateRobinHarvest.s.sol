// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {IAccessManaged} from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import {AccessManager} from "../src/access/AccessManager.sol";
import {RobinAccountant} from "../src/accounting/RobinAccountant.sol";
import {ExecutionRouter} from "../src/router/ExecutionRouter.sol";
import {OracleRegistry} from "../src/registries/OracleRegistry.sol";
import {RewardRegistry} from "../src/registries/RewardRegistry.sol";
import {GrowthStrategy} from "../src/strategies/GrowthStrategy.sol";
import {StrategyBase} from "../src/strategies/StrategyBase.sol";
import {RobinVault} from "../src/vaults/RobinVault.sol";
import {ConfigureRobinHarvest} from "./ConfigureRobinHarvest.s.sol";
import {FeeConfig, OracleConfig, RewardTokenConfig} from "../src/types/ProtocolTypes.sol";

/// @notice Fails closed when a Robin Harvest deployment is not fully wired to the supplied production manifest.
contract ValidateRobinHarvest is Script, ConfigureRobinHarvest {
    error MissingCode(address target);
    error AuthorityMismatch(address target, address expected, address actual);
    error RoleMissing(uint64 role, address account);
    error SelectorUnauthorized(address caller, address target, bytes4 selector);
    error WiringMismatch(bytes32 key, address expected, address actual);
    error UintMismatch(bytes32 key, uint256 expected, uint256 actual);
    error FeeConfigMismatch(FeeConfig expected, FeeConfig actual);
    error OracleConfigMismatch(address asset);
    error RewardConfigMismatch(address token);
    error AdapterNotApproved(address adapter);
    error RouteConfigMismatch(address adapter, address tokenIn, address tokenOut);

    function run() external view override {
        _validate(_loadConfig());
    }

    function _validate(InitConfig memory config) internal view {
        _validateBaseConfig(config);

        AccessManager manager = AccessManager(config.addresses.manager);
        _requireCode(config.addresses.manager);
        _requireAuthorities(config);
        _requireRoles(config, manager);
        _requireSelectorRoles(config, manager);
        _requireVaultWiring(config);
        _requireExternalPolicy(config);
    }

    function _requireAuthorities(InitConfig memory config) private view {
        _requireAuthority(config.addresses.oracleRegistry, config.addresses.manager);
        _requireAuthority(config.addresses.rewardRegistry, config.addresses.manager);
        _requireAuthority(config.addresses.router, config.addresses.manager);
        _requireAuthority(config.addresses.coreAccountant, config.addresses.manager);
        _requireAuthority(config.addresses.growthAccountant, config.addresses.manager);
        _requireAuthority(config.addresses.coreVault, config.addresses.manager);
        _requireAuthority(config.addresses.coreStrategy, config.addresses.manager);
        _requireAuthority(config.addresses.growthVault, config.addresses.manager);
        _requireAuthority(config.addresses.growthStrategy, config.addresses.manager);
    }

    function _requireRoles(InitConfig memory config, AccessManager manager) private view {
        _requireRole(manager, manager.ADMIN_ROLE(), config.roles.governance);
        _requireRole(manager, manager.GOVERNANCE_ROLE(), config.roles.governance);
        _requireRole(manager, manager.STRATEGY_MANAGER_ROLE(), config.roles.governance);
        _requireRole(manager, manager.KEEPER_ROLE(), config.roles.governance);
        _requireRole(manager, manager.ORACLE_MANAGER_ROLE(), config.roles.governance);
        _requireRole(manager, manager.REWARD_MANAGER_ROLE(), config.roles.governance);
        _requireRole(manager, manager.SECURITY_COUNCIL_ROLE(), config.roles.governance);
        _requireRole(manager, manager.STRATEGY_MANAGER_ROLE(), config.roles.strategyManager);
        _requireRole(manager, manager.KEEPER_ROLE(), config.roles.keeper);
        _requireRole(manager, manager.ORACLE_MANAGER_ROLE(), config.roles.oracleManager);
        _requireRole(manager, manager.REWARD_MANAGER_ROLE(), config.roles.rewardManager);
        _requireRole(manager, manager.SECURITY_COUNCIL_ROLE(), config.roles.securityCouncil);
    }

    function _requireSelectorRoles(InitConfig memory config, AccessManager manager) private view {
        _canCall(manager, config.roles.strategyManager, config.addresses.coreVault, RobinVault.setStrategy.selector);
        _canCall(manager, config.roles.strategyManager, config.addresses.growthVault, RobinVault.setStrategy.selector);
        _canCall(manager, config.roles.keeper, config.addresses.coreVault, RobinVault.deploy.selector);
        _canCall(manager, config.roles.keeper, config.addresses.growthVault, RobinVault.deploy.selector);
        _canCall(manager, config.roles.securityCouncil, config.addresses.coreVault, RobinVault.pause.selector);
        _canCall(manager, config.roles.securityCouncil, config.addresses.growthVault, RobinVault.pause.selector);

        _canCall(manager, config.roles.keeper, config.addresses.coreStrategy, StrategyBase.harvest.selector);
        _canCall(manager, config.roles.keeper, config.addresses.growthStrategy, StrategyBase.harvest.selector);
        _canCall(manager, config.roles.rewardManager, config.addresses.coreStrategy, StrategyBase.addRewardToken.selector);
        _canCall(
            manager, config.roles.rewardManager, config.addresses.growthStrategy, StrategyBase.addRewardToken.selector
        );
        _canCall(manager, config.roles.securityCouncil, config.addresses.coreStrategy, StrategyBase.pause.selector);
        _canCall(manager, config.roles.securityCouncil, config.addresses.growthStrategy, StrategyBase.pause.selector);
        _canCall(
            manager, config.roles.strategyManager, config.addresses.growthStrategy, GrowthStrategy.setNavHaircutBps.selector
        );

        _canCall(
            manager, config.roles.oracleManager, config.addresses.oracleRegistry, OracleRegistry.setOracleConfig.selector
        );
        _canCall(
            manager, config.roles.rewardManager, config.addresses.rewardRegistry, RewardRegistry.setRewardTokenConfig.selector
        );
        _canCall(manager, config.roles.strategyManager, config.addresses.router, ExecutionRouter.setRoute.selector);
    }

    function _requireVaultWiring(InitConfig memory config) private view {
        _requireVault(
            config.addresses.coreVault,
            config.addresses.coreStrategy,
            config.addresses.coreAccountant,
            config.feeRecipient,
            config.eligibilityThreshold,
            config.strategyMigrationDelay,
            config.feeConfig
        );
        _requireVault(
            config.addresses.growthVault,
            config.addresses.growthStrategy,
            config.addresses.growthAccountant,
            config.feeRecipient,
            config.eligibilityThreshold,
            config.strategyMigrationDelay,
            config.feeConfig
        );
    }

    function _requireVault(
        address vault_,
        address strategy_,
        address accountant_,
        address feeRecipient_,
        uint256 eligibilityThreshold_,
        uint256 strategyMigrationDelay_,
        FeeConfig memory feeConfig_
    ) private view {
        RobinVault vault = RobinVault(vault_);
        RobinAccountant accountant = RobinAccountant(accountant_);
        if (address(vault.strategy()) != strategy_) {
            revert WiringMismatch("VAULT_STRATEGY", strategy_, address(vault.strategy()));
        }
        if (address(vault.accountant()) != accountant_) {
            revert WiringMismatch("VAULT_ACCOUNTANT", accountant_, address(vault.accountant()));
        }
        if (vault.eligibilityThreshold() != eligibilityThreshold_) {
            revert UintMismatch("ELIGIBILITY_THRESHOLD", eligibilityThreshold_, vault.eligibilityThreshold());
        }
        if (vault.strategyMigrationDelay() != strategyMigrationDelay_) {
            revert UintMismatch("STRATEGY_MIGRATION_DELAY", strategyMigrationDelay_, vault.strategyMigrationDelay());
        }
        if (accountant.vault() != vault_) revert WiringMismatch("ACCOUNTANT_VAULT", vault_, accountant.vault());
        if (accountant.feeRecipient() != feeRecipient_) {
            revert WiringMismatch("FEE_RECIPIENT", feeRecipient_, accountant.feeRecipient());
        }
        (uint16 performanceBps, uint16 managementBps) = accountant.feeConfig();
        FeeConfig memory actualFeeConfig =
            FeeConfig({performanceBps: performanceBps, managementBps: managementBps});
        if (
            actualFeeConfig.performanceBps != feeConfig_.performanceBps
                || actualFeeConfig.managementBps != feeConfig_.managementBps
        ) revert FeeConfigMismatch(feeConfig_, actualFeeConfig);
    }

    function _requireExternalPolicy(InitConfig memory config) private view {
        ExecutionRouter router = ExecutionRouter(config.addresses.router);
        OracleRegistry oracleRegistry = OracleRegistry(config.addresses.oracleRegistry);
        RewardRegistry rewardRegistry = RewardRegistry(config.addresses.rewardRegistry);

        for (uint256 i; i < config.approvedDexAdapters.length; ++i) {
            if (!router.isAdapterApproved(config.approvedDexAdapters[i])) {
                revert AdapterNotApproved(config.approvedDexAdapters[i]);
            }
        }
        for (uint256 i; i < config.routes.length; ++i) {
            RouteEntry memory route = config.routes[i];
            ExecutionRouter.RouteConfig memory actual =
                router.getRouteConfig(route.adapter, route.tokenIn, route.tokenOut);
            if (actual.enabled != route.enabled || actual.maxOracleDeviationBps != route.maxOracleDeviationBps) {
                revert RouteConfigMismatch(route.adapter, route.tokenIn, route.tokenOut);
            }
        }
        for (uint256 i; i < config.oracles.length; ++i) {
            OracleConfig memory actual = oracleRegistry.getOracleConfig(config.oracles[i].asset);
            OracleConfig memory expected = config.oracles[i].config;
            if (
                actual.feed != expected.feed || actual.heartbeat != expected.heartbeat
                    || actual.decimals != expected.decimals || actual.maxDeviationBps != expected.maxDeviationBps
                    || actual.uiMultiplier != expected.uiMultiplier || actual.paused != expected.paused
            ) revert OracleConfigMismatch(config.oracles[i].asset);
        }
        for (uint256 i; i < config.rewards.length; ++i) {
            RewardTokenConfig memory actual = rewardRegistry.getRewardTokenConfig(config.rewards[i].token);
            RewardTokenConfig memory expected = config.rewards[i].config;
            if (
                actual.enabled != expected.enabled || actual.category != expected.category
                    || actual.disposition != expected.disposition || actual.oracle != expected.oracle
                    || actual.minHarvestAmount != expected.minHarvestAmount || actual.retainable != expected.retainable
                    || actual.adapter != expected.adapter || actual.maxExposureBps != expected.maxExposureBps
            ) revert RewardConfigMismatch(config.rewards[i].token);
        }
    }

    function _requireCode(address target) private view {
        if (target.code.length == 0) revert MissingCode(target);
    }

    function _requireAuthority(address target, address expectedAuthority) private view {
        _requireCode(target);
        address actual = IAccessManaged(target).authority();
        if (actual != expectedAuthority) revert AuthorityMismatch(target, expectedAuthority, actual);
    }

    function _requireRole(AccessManager manager, uint64 role, address account) private view {
        (bool hasRole,) = manager.hasRole(role, account);
        if (!hasRole) revert RoleMissing(role, account);
    }

    function _canCall(AccessManager manager, address caller, address target, bytes4 selector) private view {
        (bool immediate,) = manager.canCall(caller, target, selector);
        if (!immediate) revert SelectorUnauthorized(caller, target, selector);
    }
}
