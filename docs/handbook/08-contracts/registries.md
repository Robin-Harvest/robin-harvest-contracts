# Contract Reference — Registries, Router, Adapter, Accounting, Access

## OracleRegistry (`src/registries/OracleRegistry.sol`)

### Purpose

Store and validate Chainlink-shaped price feeds.

### Constant

`NORMALIZED_PRICE_DECIMALS = 1e18`

### Functions

| Function | Access | Description |
|---|---|---|
| `getOracleConfig(asset)` | view | Return OracleConfig |
| `getValidatedPrice(asset)` | view | Validated normalized price + updatedAt |
| `setOracleConfig(asset, config)` | restricted | Register/update feed |
| `setOraclePaused(asset, paused)` | restricted | Emergency pause reads |
| `setUiMultiplier(asset, mult)` | restricted | Corporate action multiplier |

### Validation in getValidatedPrice

- Feed exists, not paused
- answer > 0, observedAt > 0
- answeredInRound >= roundId
- heartbeat staleness
- Normalize: raw × 10^(18-dec) × uiMultiplier/1e18

### Errors

`StaleOracle`, `InvalidOracleAnswer`, `IncompleteOracleRound`, `Disabled`, `InvalidDecimals`

---

## RewardRegistry (`src/registries/RewardRegistry.sol`)

### Purpose

Governance allowlist for reward token handling policy.

### Functions

| Function | Access | Description |
|---|---|---|
| `getRewardTokenConfig(token)` | view | Full RewardTokenConfig |
| `isRewardTokenEnabled(token)` | view | config.enabled |
| `isAdapterApproved(token, adapter)` | view | Per-token adapter |
| `setRewardTokenConfig(token, config)` | restricted | Create/update |
| `disableRewardToken(token)` | restricted | enabled=false, preserve config |
| `setAdapterApproval(token, adapter, approved)` | restricted | Adapter map |

### Validation (_validateConfig)

- Sell → adapter approved
- Retain → retainable + oracle set
- maxExposureBps ≤ MAX_BPS

---

## ExecutionRouter (`src/router/ExecutionRouter.sol`)

### Purpose

Constrained exact-input swaps; no arbitrary targets/calldata.

### Immutable

`oracleRegistry`

### swapExactInput(request, recipient)

1. Checks: recipient, amount, deadline, adapter approved, route enabled
2. Pull tokenIn, approve adapter, adapter.swap
3. Reset approval
4. Balance delta ≥ minOut
5. Oracle deviation if route.maxOracleDeviationBps > 0

### Governance

`setAdapterApproval`, `setRoute(adapter, tokenIn, tokenOut, enabled, maxOracleDeviationBps)`

### getRouteId

`keccak256(abi.encode(adapter, tokenIn, tokenOut))`

---

## UniswapV2DexAdapter (`src/adapters/UniswapV2DexAdapter.sol`)

### Purpose

Exact-input swaps via constant-product router.

### Immutable

`router` (IUniswapV2Router)

### setCustomPath(tokenIn, tokenOut, path) — restricted

Multi-hop when direct pair illiquid. Validates path[0]=tokenIn, path[end]=tokenOut.

### swapExactInput

Pull tokens, approve router, swapExactTokensForTokens, verify balance delta, reset approval.

### quoteExactInput

`getAmountsOut` with try/catch → 0 on failure (Growth uses for conservative NAV).

---

## RobinAccountant (`src/accounting/RobinAccountant.sol`)

### Purpose

Performance fee (HWM) + management fee (time-based).

### Immutable

`asset` (INDEX)

### State

`vault`, `feeRecipient`, `feeConfig`, `highWaterMark`, `lastFeeAccrual`

### assessReportFees(gross, reportedGain) — onlyVault

Returns (performanceFee, managementFee); updates HWM and lastFeeAccrual.

See [09-mathematics.md](../09-mathematics.md).

---

## AccessManager (`src/access/AccessManager.sol`)

### Purpose

Central role authority extending OpenZeppelin AccessManager.

### Role Constants

| ID | Name |
|---|---|
| 1 | GOVERNANCE_ROLE |
| 2 | STRATEGY_MANAGER_ROLE |
| 3 | KEEPER_ROLE |
| 4 | ORACLE_MANAGER_ROLE |
| 5 | REWARD_MANAGER_ROLE |
| 6 | SECURITY_COUNCIL_ROLE |

### Constructor

Sets role admins/guardians: operational roles under GOVERNANCE; SECURITY_COUNCIL as guardian.

Production selector→role mapping in `ConfigureRobinHarvest.s.sol`.

---

## Interfaces, Types, Libraries

See [interfaces-types-libraries.md](./interfaces-types-libraries.md).

---

**Next:** [interfaces-types-libraries.md](./interfaces-types-libraries.md)
