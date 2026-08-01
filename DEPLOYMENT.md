# Robin Harvest Deployment Guide

This document outlines the end-to-end procedure for deploying, configuring, and validating the Robin Harvest protocol on Robinhood Chain (mainnet) or Sepolia (testnet).

## Prerequisites

1. **Foundry Toolchain**: Ensure you have [Foundry](https://getfoundry.sh/) installed (`forge`, `cast`).
2. **RPC Node**: A reliable RPC provider for the target network.
3. **Deployer Wallet**: An EOA with sufficient gas token (ETH/RHO) to broadcast the transactions. Note: The deployer EOA is *not* expected to retain any governance authority post-deployment.
4. **Governance Multisig**: The target address (e.g., Gnosis Safe) that will hold all protocol admin rights.

## Required Environment Variables

Copy `.env.example` to `.env` and fill in the required fields. Do not commit `.env` to version control.

### Network & Tooling
```bash
ROBINHOOD_RPC_URL=
ROBINHOOD_EXPLORER_URL=
ROBINHOOD_EXPLORER_API_URL=
ROBINHOOD_EXPLORER_API_KEY=
DEPLOYER_PRIVATE_KEY=
VERIFY_CONTRACTS=true
```

### Protocol Dependencies (Target Network Specific)
```bash
GOVERNANCE_ADDRESS=            # Address of the multisig
INDEX_TOKEN_ADDRESS=           # Address of INDEX token
INDEX_FINANCE_ADDRESS=         # Address of Index Finance Core
SWAP_ADAPTER_ADDRESS=          # Governance-approved exact-input adapter
V4_POOL_MANAGER_ADDRESS=       # Official Uniswap v4 PoolManager
V4_POSITION_MANAGER_ADDRESS=   # Official Uniswap v4 PositionManager
V4_PAIRED_TOKEN_ADDRESS=       # Higher-sorted currency paired with INDEX
V4_POOL_FEE=3000
V4_TICK_SPACING=60
V4_HOOKS_ADDRESS=0x0000000000000000000000000000000000000000
CL_POLICY_HALF_WIDTH=600
CL_POLICY_MIN_TICK_WIDTH=120
CL_POLICY_MAX_TICK_WIDTH=2400
```

### Protocol Configuration
```bash
MAX_SLIPPAGE_BPS=500               # 5% max slippage
SWAP_DEADLINE_DELAY=1800           # 30 minutes
ELIGIBILITY_THRESHOLD=10000000000  # Example 10k INDEX (scaled)
STRATEGY_MIGRATION_DELAY=86400     # 24 hours
```

## 0. Testnet Mock Infrastructure (Optional)

If you are deploying to a testnet (e.g. Sepolia or Robinhood Testnet) and do not have access to real live ERC20 token dependencies, you can deploy a full suite of mock contracts to simulate the live environment.

```bash
forge script script/DeployMocks.s.sol \
    --rpc-url $ROBINHOOD_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --broadcast
```

*This deploys `MockINDEX`, `MockStockToken`, `MockIndexFinanceCore`, and `MockDex`. The printed paired-token and swap-adapter addresses can be copied into the **Protocol Dependencies** section.*

## 1. Deployment Order

The deployment script provisions Core, Growth, and the Uniswap v4 concentrated-liquidity vaults, strategies, registries, policy, and router.

```bash
forge script script/DeployRobinHarvest.s.sol \
    --rpc-url $ROBINHOOD_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --broadcast \
    --verify
```

*Save the output addresses from the console log. You will need them for configuration.*

## 2. Configuration Order

The configuration script is idempotent and can be re-run safely. It binds the strategies to the vaults, configures fee recipients, and sets up granular access control roles.

*Before running this, ensure your `.env` contains the output addresses from Step 1 (`CORE_VAULT_ADDRESS`, `ACCESS_MANAGER_ADDRESS`, etc).*

```bash
forge script script/ConfigureRobinHarvest.s.sol \
    --rpc-url $ROBINHOOD_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --broadcast
```

## 3. Validation

The validation script acts as a strict manifest checker. It verifies that all storage slots, pointers, and roles exactly match the intended `.env` configuration. 

```bash
forge script script/ValidateRobinHarvest.s.sol \
    --rpc-url $ROBINHOOD_RPC_URL
```
**If this script reverts with an error (e.g., `WiringMismatch`, `RoleMissing`), DO NOT proceed to production.** Investigate the mismatched state.

## 4. Verification

If `--verify` fails during the deployment step due to network congestion or API limits, you can manually verify contracts using `forge verify-contract`:

```bash
forge verify-contract <CONTRACT_ADDRESS> src/<PATH_TO_CONTRACT>.sol:<CONTRACT_NAME> \
    --rpc-url $ROBINHOOD_RPC_URL \
    --verifier-url $ROBINHOOD_EXPLORER_API_URL \
    --etherscan-api-key $ROBINHOOD_EXPLORER_API_KEY
```

## 5. Expected Addresses

Upon successful deployment, you should have the following unique contract instances:

| Component | Instances | Description |
|---|---|---|
| **AccessManager** | 1 | Global role-based access controller |
| **Registries** | 2 | `OracleRegistry`, `RewardRegistry` |
| **ExecutionRouter** | 1 | Handles external DEX swaps |
| **Vaults** | 3 | `rhINDEX-C`, `rhINDEX-G`, `rhINDEX-CL` |
| **Strategies** | 3 | `CoreStrategy`, `GrowthStrategy`, `ConcentratedLiquidityStrategy` |
| **Accountants** | 3 | Fee routing modules for each vault |

## 6. Upgrade Procedure

Robin Harvest uses **immutable** (non-upgradeable) smart contracts.

To upgrade the protocol logic:
1. Deploy a new `Strategy` contract.
2. Call `proposeStrategyMigration(newStrategy)` on the Vault.
3. Wait the mandatory `STRATEGY_MIGRATION_DELAY` (e.g. 24 hours).
4. Call `executeStrategyMigration()`.

During migration, all vault funds are pulled from the old strategy and pushed to the new strategy automatically.

## 7. Emergency Rollback / Pausing

If a critical vulnerability or external dependency failure occurs:

1. **Pause Strategies**: The `SECURITY_COUNCIL_ROLE` should call `pause()` on `CoreStrategy`, `GrowthStrategy`, and `ConcentratedLiquidityStrategy`.
2. **Close CL positions**: Call `emergencyClosePositions()` while the CL strategy is paused.
3. **Return CL assets**: Call `emergencyReturnAssetsToVault()` after confirming there are no active positions.
4. **Pause Vaults**: Call `pause()` on the Vaults to temporarily halt withdrawals if the accounting system is compromised.

## 8. Common Failures

- **`WiringMismatch` during Validation**: You forgot to update the `.env` file with the newly deployed addresses before running the configuration script.
- **Oracle Verification Fails**: The mock oracles were used instead of real feeds. Ensure `ORACLE_FEEDS` in `.env` is populated correctly.
- **`RoleMissing` error**: The EOA running the script does not have `STRATEGY_MANAGER_ROLE` permissions to configure the protocol. Make sure configuration is run from an authorized account or routed through the multisig.
