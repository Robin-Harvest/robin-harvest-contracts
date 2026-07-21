# Chapter 13 — Deployment

## 13.1 Foundry Toolchain

| Tool | Purpose |
|---|---|
| **forge** | Compile, test, deploy scripts |
| **cast** | CLI for RPC calls, calldata, wallet |
| **anvil** | Local EVM node for dev |

Install: [getfoundry.sh](https://book.getfoundry.sh/getting-started/installation)

Robin Harvest pins Foundry **v1.9.7** (README); CI uses **v1.3.1** toolchain action — verify compatibility locally.

---

## 13.2 Build

```bash
forge install
forge build
forge build --sizes   # EIP-170 check
```

Compiler settings (`foundry.toml`):

- solc 0.8.25, evm paris, optimizer 200 runs, via_ir

---

## 13.3 Environment Variables

From `.env.example` and deployment scripts:

### Chain

| Variable | Purpose |
|---|---|
| `ROBINHOOD_RPC_URL` | RPC endpoint |
| `ROBINHOOD_EXPLORER_API_URL` | Verification |
| `ROBINHOOD_EXPLORER_API_KEY` | Verification |
| `DEPLOYER_PRIVATE_KEY` | Broadcast signer (secret manager) |

### Deploy (`DeployRobinHarvest.s.sol`)

| Variable | Purpose |
|---|---|
| `GOVERNANCE_ADDRESS` | Initial AccessManager admin |
| `INDEX_TOKEN_ADDRESS` | INDEX ERC-20 |
| `INDEX_FINANCE_ADDRESS` | Index Finance core |
| `MAX_SLIPPAGE_BPS` | Strategy slippage |
| `SWAP_DEADLINE_DELAY` | Swap deadline offset (seconds) |
| `ELIGIBILITY_THRESHOLD` | Vault eligibility |
| `STRATEGY_MIGRATION_DELAY` | Migration timelock |

### Configure (`ConfigureRobinHarvest.s.sol`)

Deployed addresses: `ACCESS_MANAGER_ADDRESS`, `ORACLE_REGISTRY_ADDRESS`, etc.

Role holders: `STRATEGY_MANAGER_ADDRESS`, `KEEPER_ADDRESS`, `ORACLE_MANAGER_ADDRESS`, `REWARD_MANAGER_ADDRESS`, `SECURITY_COUNCIL_ADDRESS`

Fee: `FEE_RECIPIENT_ADDRESS`, `PERFORMANCE_FEE_BPS`, `MANAGEMENT_FEE_BPS`

Arrays (comma-separated): oracle assets/feeds/heartbeats, reward tokens/config, route adapters, `APPROVED_DEX_ADAPTERS`

---

## 13.4 Deploy Command

```bash
source .env
forge script script/DeployRobinHarvest.s.sol:DeployRobinHarvest \
  --rpc-url "$ROBINHOOD_RPC_URL" \
  --broadcast \
  --verify
```

**Output:** Console logs all contract addresses.

**Note:** Deploy script does **not** wire strategy, roles, or registries — governance runs Configure separately.

---

## 13.5 Post-Deploy Configuration

```bash
forge script script/ConfigureRobinHarvest.s.sol:ConfigureRobinHarvest \
  --rpc-url "$ROBINHOOD_RPC_URL" \
  --broadcast
```

Must be executed by **governance multisig** (not deployer EOA unless same).

Configure script:

1. Grants roles
2. Maps selectors to roles
3. Sets strategy + accountant per vault
4. Sets fee recipient and rates
5. Approves DEX adapters and routes
6. Registers oracles and reward tokens

**Idempotent:** Re-running skips existing correct config; reverts on mismatch.

---

## 13.6 Validation

```bash
forge script script/ValidateRobinHarvest.s.sol:ValidateRobinHarvest \
  --rpc-url "$ROBINHOOD_RPC_URL"
```

Read-only `view` run — fails closed if wiring, roles, or policy mismatch env manifest.

---

## 13.7 Operational Checklist

From `docs/DEPLOYMENT.md`:

1. Transfer AccessManager `ADMIN_ROLE` to governance multisig
2. Grant operational roles
3. Configure oracles, rewards, routes **before deposits**
4. Set conservative deposit caps
5. Wire accountant to each vault
6. Archive addresses under `deployments/`
7. **Complete external audit** before user funds

---

## 13.8 Incident Response

1. **Pause** — Security Council: vault + strategy pause
2. **Investigate** — block numbers, tx hashes, oracle/route state
3. **Communicate** — eligibility, withdrawal status
4. **Recover** — unpause with stronger auth; `emergencyWithdraw` only for wind-down

---

## 13.9 Verification

`foundry.toml` etherscan section for Robinhood explorer. Set `VERIFY_CONTRACTS=true` and verifier env vars per `.env.example`.

---

## 13.10 cast Examples

```bash
# Read totalAssets
cast call $VAULT "totalAssets()(uint256)" --rpc-url $ROBINHOOD_RPC_URL

# Check lifecycle
cast call $VAULT "lifecycleState()(uint8)" --rpc-url $ROBINHOOD_RPC_URL

# Eligibility
cast call $VAULT "isEligible()(bool,uint256,uint256)" --rpc-url $ROBINHOOD_RPC_URL
```

---

**Next:** [14-cicd.md](./14-cicd.md)
