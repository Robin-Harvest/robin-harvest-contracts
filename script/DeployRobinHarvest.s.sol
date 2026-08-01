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
import {ConcentratedLiquidityStrategy} from "../src/strategies/ConcentratedLiquidityStrategy.sol";
import {StaticRangeRebalancePolicy} from "../src/policies/StaticRangeRebalancePolicy.sol";
import {RobinVault} from "../src/vaults/RobinVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIndexFinanceCore} from "../src/interfaces/external/IIndexFinanceCore.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @notice Deploys the Core, Growth, and Uniswap v4 concentrated-liquidity products.
/// @dev The CL product is hookless and single-pool. Governance configures the swap route after deployment.
contract DeployRobinHarvest is Script {
    struct DeploymentConfig {
        address governance;
        address indexToken;
        address indexFinance;
        uint16 maxSlippageBps;
        uint48 swapDeadlineDelay;
        address poolManager;
        address positionManager;
        address pairedToken;
        uint24 poolFee;
        int24 tickSpacing;
        address hooks;
        int24 policyHalfWidth;
        int24 policyMinTickWidth;
        int24 policyMaxTickWidth;
    }

    struct DeploymentAddresses {
        AccessManager manager;
        OracleRegistry oracleRegistry;
        RewardRegistry rewardRegistry;
        ExecutionRouter router;
        RobinAccountant coreAccountant;
        RobinAccountant growthAccountant;
        RobinAccountant clAccountant;
        RobinVault coreVault;
        CoreStrategy coreStrategy;
        RobinVault growthVault;
        GrowthStrategy growthStrategy;
        RobinVault clVault;
        ConcentratedLiquidityStrategy clStrategy;
        StaticRangeRebalancePolicy clPolicy;
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
        RobinAccountant clAccountant = new RobinAccountant(IERC20(config.indexToken), address(manager));

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

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(config.indexToken < config.pairedToken ? config.indexToken : config.pairedToken),
            currency1: Currency.wrap(config.indexToken < config.pairedToken ? config.pairedToken : config.indexToken),
            fee: config.poolFee,
            tickSpacing: config.tickSpacing,
            hooks: IHooks(config.hooks)
        });
        StaticRangeRebalancePolicy policy = new StaticRangeRebalancePolicy(
            address(manager), config.policyHalfWidth, config.policyMinTickWidth, config.policyMaxTickWidth
        );
        RobinVault clVault =
            new RobinVault(IERC20(config.indexToken), "Robin INDEX Concentrated Vault", "rhINDEX-CL", address(manager));
        ConcentratedLiquidityStrategy clStrategy = new ConcentratedLiquidityStrategy(
            address(clVault),
            IERC20(config.indexToken),
            address(manager),
            IPoolManager(config.poolManager),
            IPositionManager(config.positionManager),
            key,
            router,
            oracleRegistry,
            policy
        );

        deployed = DeploymentAddresses({
            manager: manager,
            oracleRegistry: oracleRegistry,
            rewardRegistry: rewardRegistry,
            router: router,
            coreAccountant: coreAccountant,
            growthAccountant: growthAccountant,
            clAccountant: clAccountant,
            coreVault: coreVault,
            coreStrategy: coreStrategy,
            growthVault: growthVault,
            growthStrategy: growthStrategy,
            clVault: clVault,
            clStrategy: clStrategy,
            clPolicy: policy
        });
    }

    function _loadConfig() internal view returns (DeploymentConfig memory config) {
        config.governance = vm.envAddress("GOVERNANCE_ADDRESS");
        config.indexToken = vm.envAddress("INDEX_TOKEN_ADDRESS");
        config.indexFinance = vm.envAddress("INDEX_FINANCE_ADDRESS");
        config.maxSlippageBps = uint16(vm.envUint("MAX_SLIPPAGE_BPS"));
        config.swapDeadlineDelay = uint48(vm.envUint("SWAP_DEADLINE_DELAY"));
        config.poolManager = vm.envAddress("V4_POOL_MANAGER_ADDRESS");
        config.positionManager = vm.envAddress("V4_POSITION_MANAGER_ADDRESS");
        config.pairedToken = vm.envAddress("V4_PAIRED_TOKEN_ADDRESS");
        config.poolFee = uint24(vm.envUint("V4_POOL_FEE"));
        config.tickSpacing = int24(vm.envInt("V4_TICK_SPACING"));
        config.hooks = vm.envOr("V4_HOOKS_ADDRESS", address(0));
        config.policyHalfWidth = int24(vm.envInt("CL_POLICY_HALF_WIDTH"));
        config.policyMinTickWidth = int24(vm.envInt("CL_POLICY_MIN_TICK_WIDTH"));
        config.policyMaxTickWidth = int24(vm.envInt("CL_POLICY_MAX_TICK_WIDTH"));
    }

    function _logDeployment(DeploymentAddresses memory deployed) private pure {
        console2.log("ACCESS_MANAGER_ADDRESS=", address(deployed.manager));
        console2.log("ORACLE_REGISTRY_ADDRESS=", address(deployed.oracleRegistry));
        console2.log("REWARD_REGISTRY_ADDRESS=", address(deployed.rewardRegistry));
        console2.log("EXECUTION_ROUTER_ADDRESS=", address(deployed.router));
        console2.log("CORE_ACCOUNTANT_ADDRESS=", address(deployed.coreAccountant));
        console2.log("GROWTH_ACCOUNTANT_ADDRESS=", address(deployed.growthAccountant));
        console2.log("CL_ACCOUNTANT_ADDRESS=", address(deployed.clAccountant));
        console2.log("CORE_VAULT_ADDRESS=", address(deployed.coreVault));
        console2.log("CORE_STRATEGY_ADDRESS=", address(deployed.coreStrategy));
        console2.log("GROWTH_VAULT_ADDRESS=", address(deployed.growthVault));
        console2.log("GROWTH_STRATEGY_ADDRESS=", address(deployed.growthStrategy));
        console2.log("CL_VAULT_ADDRESS=", address(deployed.clVault));
        console2.log("CL_STRATEGY_ADDRESS=", address(deployed.clStrategy));
        console2.log("CL_POLICY_ADDRESS=", address(deployed.clPolicy));
    }
}
