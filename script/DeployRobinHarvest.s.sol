// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {AccessManager} from "../src/access/AccessManager.sol";
import {RobinAccountant} from "../src/accounting/RobinAccountant.sol";
import {ExecutionRouter} from "../src/router/ExecutionRouter.sol";
import {OracleRegistry} from "../src/registries/OracleRegistry.sol";
import {RewardRegistry} from "../src/registries/RewardRegistry.sol";
import {CoreStrategy} from "../src/strategies/CoreStrategy.sol";
import {GrowthStrategy} from "../src/strategies/GrowthStrategy.sol";
import {LpStrategy} from "../src/strategies/LpStrategy.sol";
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
        address lpToken;
        address pairedToken;
        address dexAdapter;
        address dexRouter;
    }

    struct DeploymentAddresses {
        AccessManager manager;
        OracleRegistry oracleRegistry;
        RewardRegistry rewardRegistry;
        ExecutionRouter router;
        RobinAccountant coreAccountant;
        RobinAccountant growthAccountant;
        RobinAccountant lpAccountant;
        RobinVault coreVault;
        CoreStrategy coreStrategy;
        RobinVault growthVault;
        GrowthStrategy growthStrategy;
        RobinVault lpVault;
        LpStrategy lpStrategy;
    }

    function run() external returns (DeploymentAddresses memory deployed) {
        DeploymentConfig memory config = _loadConfig();
        vm.startBroadcast();
        deployed = _deploy(config);
        vm.stopBroadcast();

        _logDeployment(deployed);
    }

    function _deploy(DeploymentConfig memory config) internal returns (DeploymentAddresses memory deployed) {
        AccessManager manager = new AccessManager(config.governance);
        OracleRegistry oracleRegistry = new OracleRegistry(address(manager));
        RewardRegistry rewardRegistry = new RewardRegistry(address(manager));
        ExecutionRouter router = new ExecutionRouter(address(manager), oracleRegistry);
        RobinAccountant coreAccountant = new RobinAccountant(IERC20(config.indexToken), address(manager));
        RobinAccountant growthAccountant = new RobinAccountant(IERC20(config.indexToken), address(manager));
        RobinAccountant lpAccountant = new RobinAccountant(IERC20(config.indexToken), address(manager));

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

        RobinVault lpVault =
            new RobinVault(IERC20(config.indexToken), "Robin INDEX LP Vault", "rhINDEX-LP", address(manager));
        LpStrategy lpStrategy = new LpStrategy(
            address(lpVault),
            IERC20(config.indexToken),
            address(manager),
            config.lpToken,
            config.pairedToken,
            config.dexRouter,
            config.dexAdapter,
            router,
            oracleRegistry,
            rewardRegistry
        );

        deployed.manager = manager;
        deployed.oracleRegistry = oracleRegistry;
        deployed.rewardRegistry = rewardRegistry;
        deployed.router = router;
        deployed.coreAccountant = coreAccountant;
        deployed.growthAccountant = growthAccountant;
        deployed.lpAccountant = lpAccountant;
        deployed.coreVault = coreVault;
        deployed.coreStrategy = coreStrategy;
        deployed.growthVault = growthVault;
        deployed.growthStrategy = growthStrategy;
        deployed.lpVault = lpVault;
        deployed.lpStrategy = lpStrategy;
    }

    function _loadConfig() internal view returns (DeploymentConfig memory config) {
        config.governance = vm.envAddress("GOVERNANCE_ADDRESS");
        config.indexToken = vm.envAddress("INDEX_TOKEN_ADDRESS");
        config.indexFinance = vm.envAddress("INDEX_FINANCE_ADDRESS");
        config.maxSlippageBps = uint16(vm.envUint("MAX_SLIPPAGE_BPS"));
        config.swapDeadlineDelay = uint48(vm.envUint("SWAP_DEADLINE_DELAY"));
        config.eligibilityThreshold = vm.envUint("ELIGIBILITY_THRESHOLD");
        config.strategyMigrationDelay = vm.envUint("STRATEGY_MIGRATION_DELAY");
        config.lpToken = vm.envAddress("LP_TOKEN_ADDRESS");
        config.pairedToken = vm.envAddress("PAIRED_TOKEN_ADDRESS");
        config.dexAdapter = vm.envAddress("DEX_ADAPTER_ADDRESS");
        config.dexRouter = vm.envAddress("DEX_ROUTER_ADDRESS");
    }

    function _logDeployment(DeploymentAddresses memory deployed) private pure {
        console2.log("ACCESS_MANAGER_ADDRESS=", address(deployed.manager));
        console2.log("ORACLE_REGISTRY_ADDRESS=", address(deployed.oracleRegistry));
        console2.log("REWARD_REGISTRY_ADDRESS=", address(deployed.rewardRegistry));
        console2.log("EXECUTION_ROUTER_ADDRESS=", address(deployed.router));
        console2.log("CORE_ACCOUNTANT_ADDRESS=", address(deployed.coreAccountant));
        console2.log("GROWTH_ACCOUNTANT_ADDRESS=", address(deployed.growthAccountant));
        console2.log("LP_ACCOUNTANT_ADDRESS=", address(deployed.lpAccountant));
        console2.log("CORE_VAULT_ADDRESS=", address(deployed.coreVault));
        console2.log("CORE_STRATEGY_ADDRESS=", address(deployed.coreStrategy));
        console2.log("GROWTH_VAULT_ADDRESS=", address(deployed.growthVault));
        console2.log("GROWTH_STRATEGY_ADDRESS=", address(deployed.growthStrategy));
        console2.log("LP_VAULT_ADDRESS=", address(deployed.lpVault));
        console2.log("LP_STRATEGY_ADDRESS=", address(deployed.lpStrategy));
    }
}
