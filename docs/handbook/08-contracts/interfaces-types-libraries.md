# Contract Reference — Interfaces, Types & Libraries

## ProtocolTypes (`src/types/ProtocolTypes.sol`)

### Enums

| Enum | Values | Usage |
|---|---|---|
| `LifecycleState` | Active, Paused, Shutdown | Vault + strategy |
| `RewardCategory` | Unclassified, Equity, Fund, Other | Portfolio grouping |
| `RewardDisposition` | Ignore, Sell, Retain | Harvest action |

### Structs

| Struct | Fields | Usage |
|---|---|---|
| `HarvestReport` | gain, loss, debtPayment | Strategy → vault report |
| `InKindRedemptionResult` | debtReduction, indexPaid, retainedTokens[], retainedAmounts[] | In-kind flows |
| `RewardTokenConfig` | enabled, category, disposition, oracle, minHarvestAmount, retainable, adapter, maxExposureBps | RewardRegistry |
| `OracleConfig` | feed, heartbeat, decimals, maxDeviationBps, uiMultiplier, paused | OracleRegistry |
| `CategoryPolicy` | target/min/max RetainBps, maxPortfolioBps, rebalanceCooldown | GrowthStrategy |
| `SwapRequest` | adapter, tokenIn, tokenOut, amountIn, minAmountOut, deadline | ExecutionRouter |
| `FeeConfig` | performanceBps, managementBps | RobinAccountant |
| `PendingStrategyMigration` | newStrategy, executableAt | RobinVault |

---

## IRobinStrategy (`src/interfaces/IRobinStrategy.sol`)

Strategy surface: `asset`, `vault`, `totalAssets`, `deployFunds`, `freeFunds`, `harvest`, `tend`, lifecycle, `emergencyWithdraw`, reward token views.

---

## IInKindRedemptionStrategy

`previewInKindRedemption(shares)`, `redeemInKind(shares, debtReduction, receiver, maxLossBps)`

---

## IIndexFinanceCore (`src/interfaces/external/IIndexFinanceCore.sol`) — PROVISIONAL

Expected methods (verify against official ABI before production):

- `deposit(amount)`
- `withdraw(amount)` → reported withdrawn
- `totalDeposited(account)` → position size
- `claimRewards(account, recipient)` → tokens + amounts
- `isEligible(account)` → bool

**Status:** Open question; mocks in tests implement this shape.

---

## IPriceFeed

Chainlink-compatible: `latestRoundData()`, `decimals()`

---

## IStockToken

`transfersEnabled()`, `corporateActionMultiplier()` — Growth retention validation

---

## Constants.sol

```solidity
BPS = 10_000
MAX_BPS = 10_000
SECONDS_PER_YEAR = 365 days
```

---

## Errors.sol

Full catalog of custom errors — see grep in repo. Categories:

- Access: `Unauthorized`, `OnlyVault` (strategy-local)
- Lifecycle: `InvalidLifecycleState`
- Oracle: `StaleOracle`, `InvalidOracleAnswer`, `OracleDeviationExceeded`
- Trading: `InsufficientOutput`, `DeadlineExpired`, `LossExceedsMaximum`
- Policy: `ExposureLimitExceeded`, `NotApproved`, `Disabled`
- Accounting: `InvalidAccounting`

---

## Events.sol

Shared abstract events inherited by vault, strategy, registries, router.

---

## External Interface Files

| File | Purpose |
|---|---|
| `IOracleRegistry.sol` | getValidatedPrice, getOracleConfig |
| `IRewardRegistry.sol` | getRewardTokenConfig, isRewardTokenEnabled |
| `IExecutionRouter.sol` | swapExactInput, route queries |
| `IDexAdapter.sol` | swapExactInput, quoteExactInput |
| `IRobinAccountant.sol` | assessReportFees, feeRecipient |
| `IRobinVaultReport.sol` | report(HarvestReport) |
| `IUniswapV2Router.sol` | swapExactTokensForTokens, getAmountsOut |
| `IIndexFinance.sol` | Supplementary types if used |

All interfaces define **boundaries** for testing (mocks) and future upgrades to official ABIs.
