# Deployment and Operations

> **Warning:** Production deployment requires verified external addresses, governance handoff, and an external audit.

## Prerequisites

1. Copy `.env.example` to `.env` and fill values from authoritative Robinhood Chain / Index Finance sources.
2. Install dependencies:

```sh
forge install OpenZeppelin/openzeppelin-contracts@v5.6.1 --no-commit
forge install foundry-rs/forge-std@v1.9.7 --no-commit
```

3. Confirm all items in [OPEN_QUESTIONS.md](../OPEN_QUESTIONS.md) relevant to your launch scope.

## Deploy

```sh
source .env
forge script script/DeployRobinHarvest.s.sol:DeployRobinHarvest \
  --rpc-url "$ROBINHOOD_RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast \
  --verify
```

The CL strategy links `ClActionPlanner` to keep the strategy runtime below the
EIP-170 size limit. `forge script` dry-runs resolve this linked library
automatically; archive the generated broadcast artifacts with the deployment
records.

Required environment variables for the script:

| Variable | Purpose |
|---|---|
| `ROBINHOOD_RPC_URL` | Target Robinhood Chain RPC URL |
| `DEPLOYER_PRIVATE_KEY` | Deployment signer private key |
| `GOVERNANCE_ADDRESS` | Initial governance multisig |
| `INDEX_TOKEN_ADDRESS` | INDEX ERC-20 |
| `INDEX_FINANCE_ADDRESS` | Provisional Index Finance core boundary |
| `V4_POOL_MANAGER_ADDRESS` | Official Uniswap V4 PoolManager |
| `V4_POSITION_MANAGER_ADDRESS` | Official Uniswap V4 PositionManager |
| `V4_PAIRED_TOKEN_ADDRESS` | Non-INDEX pool currency |
| `V4_POOL_FEE` | Pool fee tier |
| `V4_TICK_SPACING` | Pool tick spacing |
| `V4_HOOKS_ADDRESS` | Hook address; must be zero for V1 |
| `CL_POLICY_HALF_WIDTH` | Static policy half-width in ticks |
| `CL_POLICY_MIN_TICK_WIDTH` | Minimum allowed CL range width |
| `CL_POLICY_MAX_TICK_WIDTH` | Maximum allowed CL range width |
| `MAX_SLIPPAGE_BPS` | Core/Growth swap slippage bound |
| `SWAP_DEADLINE_DELAY` | Swap deadline offset in seconds |

After deployment, copy the logged addresses into `.env`, including
`CL_POLICY_ADDRESS`, then run governance configuration:

```sh
forge script script/ConfigureRobinHarvest.s.sol:ConfigureRobinHarvest \
  --rpc-url "$ROBINHOOD_RPC_URL" \
  --private-key "$GOVERNANCE_PRIVATE_KEY" \
  --broadcast
```

Configuration additionally requires:

| Variable | Purpose |
|---|---|
| `DEX_ADAPTER_ADDRESS` | Approved DEX adapter |
| `ELIGIBILITY_THRESHOLD` | Configurable eligibility threshold (do not hardcode `10_000e18` until verified) |
| `STRATEGY_MIGRATION_DELAY` | Timelock for strategy replacement |
| Role holder env vars | Strategy Manager, Keeper, Oracle Manager, Reward Manager, Security Council |

Validate the configured deployment:

```sh
forge script script/ValidateRobinHarvest.s.sol:ValidateRobinHarvest \
  --rpc-url "$ROBINHOOD_RPC_URL"
```

## Post-deploy checklist

1. Transfer AccessManager `ADMIN_ROLE` to governance multisig.
2. Grant operational roles (Strategy Manager, Keeper, Oracle Manager, Reward Manager, Security Council).
3. Configure oracle feeds, reward token policies, and router routes before deposits.
4. Set deposit caps conservatively until eligibility is verified on-chain.
5. Wire `RobinAccountant` to each vault and configure fee recipients/rates.
6. Publish contract addresses and archive deployment artifacts under `deployments/`.
7. Complete external audit before accepting user funds.

The CL strategy V1 is intentionally one active V4 position per strategy instance.
On-chain preview/diagnostic getters were removed from the deployable strategy ABI
to keep runtime size under EIP-170; use deployment artifacts, emitted events, and
off-chain simulations for operator dashboards.

## Incident response

1. **Pause:** Security Council pauses vault/strategy via AccessManager.
2. **Investigate:** Preserve block numbers, transaction hashes, and oracle/route state.
3. **Communicate:** Publish eligibility impact, withdrawal availability, and next steps.
4. **Recover:** Unpause only with stronger authorization; use `emergencyWithdraw` only when wind-down is required.
