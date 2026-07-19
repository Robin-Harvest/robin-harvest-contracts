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
  --broadcast \
  --verify
```

Required environment variables for the script:

| Variable | Purpose |
|---|---|
| `GOVERNANCE_ADDRESS` | Initial governance multisig |
| `INDEX_TOKEN_ADDRESS` | INDEX ERC-20 |
| `INDEX_FINANCE_ADDRESS` | Provisional Index Finance core boundary |
| `DEX_ADAPTER_ADDRESS` | Approved DEX adapter |
| `MAX_SLIPPAGE_BPS` | Core/Growth swap slippage bound |
| `SWAP_DEADLINE_DELAY` | Swap deadline offset in seconds |
| `ELIGIBILITY_THRESHOLD` | Configurable eligibility threshold (do not hardcode `10_000e18` until verified) |
| `STRATEGY_MIGRATION_DELAY` | Timelock for strategy replacement |

## Post-deploy checklist

1. Transfer AccessManager `ADMIN_ROLE` to governance multisig.
2. Grant operational roles (Strategy Manager, Keeper, Oracle Manager, Reward Manager, Security Council).
3. Configure oracle feeds, reward token policies, and router routes before deposits.
4. Set deposit caps conservatively until eligibility is verified on-chain.
5. Wire `RobinAccountant` to each vault and configure fee recipients/rates.
6. Publish contract addresses and archive deployment artifacts under `deployments/`.
7. Complete external audit before accepting user funds.

## Incident response

1. **Pause:** Security Council pauses vault/strategy via AccessManager.
2. **Investigate:** Preserve block numbers, transaction hashes, and oracle/route state.
3. **Communicate:** Publish eligibility impact, withdrawal availability, and next steps.
4. **Recover:** Unpause only with stronger authorization; use `emergencyWithdraw` only when wind-down is required.
