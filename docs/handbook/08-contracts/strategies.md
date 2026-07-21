# Contract Reference — Strategies

## StrategyBase (`src/strategies/StrategyBase.sol`)

### Purpose

Abstract framework: vault-only capital, harvest/tend, reward isolation, lifecycle, emergency exit.

### Immutables

| Name | Description |
|---|---|
| `vault` | Parent RobinVault address |
| `_asset` | INDEX token |

### State

| Variable | Purpose |
|---|---|
| `lifecycleState` | Active/Paused/Shutdown |
| `lastReportedAssets` | NAV baseline for harvest |
| `_rewardTokens` | Tracked reward list |
| `isRewardTokenTracked` | Membership map |
| `isRewardTokenIsolated` | Quarantine flag |
| `tokenExposureBps` | Exposure plumbing |

### External Functions

#### `totalAssets()` → uint256

`idle + _deployedAssets() + _rewardAssets()`

#### `deployFunds(amount)` — onlyVault

Calls `_deployFunds`; updates `lastReportedAssets`.

#### `freeFunds(amount)` — onlyVault → (amountFreed, loss)

Uses idle first; else `_freeFunds`; transfers up to `amount` to vault.

#### `harvest()` — restricted, nonReentrant → HarvestReport

1. `_claimRewards()`
2. Loop tokens: try `this.processRewardToken(token)`; catch → isolate
3. Compute gain/loss
4. Transfer idle INDEX to vault as debtPayment
5. `IRobinVaultReport(vault).report(report_)`

#### `processRewardToken(token)` — external, onlySelf

Self-call boundary for try/catch isolation.

#### `tend()` — restricted, nonReentrant

Calls `_tend()`; updates lastReportedAssets.

#### `pause` / `unpause` / `shutdown` — restricted

Lifecycle.

#### `emergencyWithdraw()` — restricted, nonReentrant

`_emergencyWithdraw`; transfer all INDEX; report; shutdown.

#### `addRewardToken` / `removeRewardToken` / `setRewardTokenIsolated` — restricted

Reward list governance. **removeRewardToken** clears isolation flag (v1.2 fix).

### Virtual Hooks (implement in derived)

| Hook | Core | Growth |
|---|---|---|
| `_deployFunds` | Index deposit | Same |
| `_freeFunds` | Index withdraw | + liquidate retained |
| `_claimRewards` | claim + no retain | claim all enabled |
| `_processRewardToken` | sell/ignore | sell/retain/ignore |
| `_deployedAssets` | totalDeposited | Same |
| `_rewardAssets` | 0 | portfolio value |
| `_emergencyWithdraw` | full withdraw | Same |
| `_tend` | eligibility check | Same |
| `_shutdownStrategy` | no-op | no-op |

---

## CoreStrategy (`src/strategies/CoreStrategy.sol`)

### Purpose

rhINDEX-Core: deploy INDEX to Index Finance; claim; sell rewards; never retain.

### Immutables

`indexFinance`, `rewardRegistry`, `oracleRegistry`, `executionRouter`

### Config State

| Variable | Default | Setter |
|---|---|---|
| `maxSlippageBps` | constructor | `setCoreParameters` |
| `swapDeadlineDelay` | constructor | `setCoreParameters` |

### Key Internals

#### `_deployFunds`

Approve Index Finance → `deposit(amount)` → verify balance and position deltas.

#### `_freeFunds` → loss

`indexFinance.withdraw(requested)`; loss = principalConsumed − withdrawn.

#### `_claimRewards`

Requires `isEligible`; **reverts RetainedRewardsUnsupported** if config disposition is Retain.

#### `_processRewardToken`

1. Skip if disabled/ignore/deferred/minHarvest
2. Revert on Retain
3. `_sellReward` via router

#### `_sellReward`

Compute `minAmountOut` from oracles; approve router; `swapExactInput`; reset approval.

#### `_minimumOutput`

Oracle cross-rate minus `maxSlippageBps`.

---

## GrowthStrategy (`src/strategies/GrowthStrategy.sol`)

### Purpose

rhINDEX-Growth: retain stocks, category policy, conservative NAV, in-kind redemption, liquidation order.

### Additional State

| Variable | Purpose |
|---|---|
| `retainedBalance` | Per-token retained amount |
| `isRetainedToken` | In portfolio set |
| `categoryPolicies` | Target/min/max retain + maxPortfolioBps |
| `lastRebalanceAt` | Cooldown tracking |
| `_liquidationOrder` | Withdraw liquidation priority |
| `navHaircutBps` | Extra NAV discount |
| `_retainedTokens` | Iterable list |

### IInKindRedemptionStrategy

#### `previewInKindRedemption(shares)`

Uses vault `totalSupply()` and floor pro-rata.

#### `redeemInKind(shares, debtReduction, receiver, maxLossBps)` — onlyVault

Updates retained balances; `_refreshExposure`; may `_freeFunds` with maxLoss; transfers tokens via `_transferExact` (fee-on-transfer check).

### Policy Functions — restricted

- `setCategoryPolicy`
- `setLiquidationOrder`
- `setNavHaircutBps`
- `markRebalance` — cooldown enforced

### Key Internals

#### `_processRewardToken` (override)

Split retain/sell based on `_computeRetainBps`; `_retainRewardAmount` enforces exposure.

#### `_freeFunds` (override)

After Index withdraw, sell retained in liquidation order; **skip** bad oracle/adapter (v1.2).

#### `_valueToken` / `_oracleValue` / `_quoteValue`

Conservative NAV (Ch. 9).

#### `_enforceExposure`

Token and category caps → `ExposureLimitExceeded`.

#### `_validateStockToken`

Requires `transfersEnabled()`; probes `corporateActionMultiplier()`.

---

## Call Graph Summary

```
harvest → claimRewards → processRewardToken → sellReward → router.swap
                      → retainRewardAmount (Growth)
        → vault.report → accountant.assessReportFees

withdraw path: vault._ensureLiquidity → strategy.freeFunds → indexFinance.withdraw
                                              → Growth: liquidate retained
```

---

**Next:** [registries.md](./registries.md)
