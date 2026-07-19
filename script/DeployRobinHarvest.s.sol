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
import {RobinVault} from "../src/vaults/RobinVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIndexFinanceCore} from "../src/interfaces/external/IIndexFinanceCore.sol";

/// @notice Deterministic deployment script for Robin Harvest Core and Growth products.
/// @dev Addresses in `.env` must be confirmed against official Robinhood Chain sources before production use.
contract DeployRobinHarvest is Script {
    struct DeploymentConfig {
        address governance;
        address indexToken;
        address indexFinance;
        uint16 maxSlippageBps;
        uint48 swapDeadlineDelay;
        uint256 eligibilityThreshold;
        uint256 strategyMigrationDelay;
    }

    function run() external {
        DeploymentConfig memory config = _loadConfig();
        vm.startBroadcast();

        AccessManager manager = new AccessManager(config.governance);
        OracleRegistry oracleRegistry = new OracleRegistry(address(manager));
        RewardRegistry rewardRegistry = new RewardRegistry(address(manager));
        ExecutionRouter router = new ExecutionRouter(address(manager), oracleRegistry);
        RobinAccountant accountant = new RobinAccountant(IERC20(config.indexToken), address(manager));

        RobinVault coreVault =
            new RobinVault(IERC20(config.indexToken), "Robin INDEX Core Vault", "rhINDEX-C", address(manager));
        CoreStrategy coreStrategy = new CoreStrategy(
            address(coreVault),
            IERC20(config.indexToken),
            address(manager),
            IIndexFinanceCore(config.indexFinance),
            rewardRegistry,
            oracleRegistry,
            router,
            config.maxSlippageBps,
            config.swapDeadlineDelay
        );

        RobinVault growthVault =
            new RobinVault(IERC20(config.indexToken), "Robin INDEX Growth Vault", "rhINDEX-G", address(manager));
        GrowthStrategy growthStrategy = new GrowthStrategy(
            address(growthVault),
            IERC20(config.indexToken),
            address(manager),
            IIndexFinanceCore(config.indexFinance),
            rewardRegistry,
            oracleRegistry,
            router,
            config.maxSlippageBps,
            config.swapDeadlineDelay
        );

        coreVault.setStrategy(address(coreStrategy));
        growthVault.setStrategy(address(growthStrategy));
        coreVault.setEligibilityThreshold(config.eligibilityThreshold);
        growthVault.setEligibilityThreshold(config.eligibilityThreshold);
        coreVault.setStrategyMigrationDelay(config.strategyMigrationDelay);
        growthVault.setStrategyMigrationDelay(config.strategyMigrationDelay);
        accountant.setVault(address(coreVault));
        accountant.setFeeRecipient(config.governance);

        vm.stopBroadcast();
    }

    function _loadConfig() internal view returns (DeploymentConfig memory config) {
        config.governance = vm.envAddress("GOVERNANCE_ADDRESS");
        config.indexToken = vm.envAddress("INDEX_TOKEN_ADDRESS");
        config.indexFinance = vm.envAddress("INDEX_FINANCE_ADDRESS");
        config.maxSlippageBps = uint16(vm.envUint("MAX_SLIPPAGE_BPS"));
        config.swapDeadlineDelay = uint48(vm.envUint("SWAP_DEADLINE_DELAY"));
        config.eligibilityThreshold = vm.envUint("ELIGIBILITY_THRESHOLD");
        config.strategyMigrationDelay = vm.envUint("STRATEGY_MIGRATION_DELAY");
    }
}
