# Contract Reference — RobinVault & ERC4626Paris

## ERC4626Paris (`src/vaults/ERC4626Paris.sol`)

### Purpose

Paris-compatible ERC-4626 implementation mirroring OpenZeppelin's virtual-asset/share formulas without Cancun-only imports.

### Inheritance

`ERC20`, `IERC4626`

### Immutables / Storage

| Name | Type | Description |
|---|---|---|
| `_asset` | IERC20 immutable | Underlying token |
| `_underlyingDecimals` | uint8 immutable | From metadata or 18 |

### Key Functions

#### `totalAssets()` — virtual view

Default: `_asset.balanceOf(this)`. **Overridden** by RobinVault.

#### `_convertToShares(assets, rounding)`

```
assets.mulDiv(totalSupply + 10^offset, totalAssets + 1, rounding)
```

#### `_convertToAssets(shares, rounding)`

Inverse with `totalAssets + 1` and `totalSupply + offset`.

#### `_deposit(caller, receiver, assets, shares)`

1. `safeTransferFrom` asset from caller
2. `_mint(receiver, shares)`
3. Emit `Deposit`

#### `_withdraw(caller, receiver, owner, assets, shares)`

1. Allowance if caller ≠ owner
2. `_burn(owner, shares)`
3. `safeTransfer` asset to receiver
4. Emit `Withdraw`

#### `_decimalsOffset()` — virtual

RobinVault returns **6**.

---

## RobinVault (`src/vaults/RobinVault.sol`)

### Purpose

ERC-4626 vault with single-strategy debt, locked profit, fees, eligibility, in-kind extension, timelocked migration.

### Inheritance

`ERC4626Paris`, `AccessManaged`, `ReentrancyGuard`, `Events`, `IRobinVaultReport`

### Constants

| Name | Value |
|---|---|
| `DEFAULT_PROFIT_MAX_UNLOCK_TIME` | 7 days |
| `DECIMALS_OFFSET` (private) | 6 |

### State Variables

| Variable | Type | Purpose |
|---|---|---|
| `lifecycleState` | LifecycleState | Active/Paused/Shutdown |
| `strategy` | IRobinStrategy | Sole strategy |
| `strategyDebt` | uint256 | Book deployed assets |
| `depositCap` | uint256 | Max AUM |
| `idleBufferBps` | uint16 | Min idle % |
| `defaultMaxLossBps` | uint16 | Default withdraw loss cap (50) |
| `lockedProfit` | uint256 | Unvested gain |
| `lastProfitUpdate` | uint256 | Unlock timer anchor |
| `profitMaxUnlockTime` | uint256 | Unlock duration |
| `eligibilityThreshold` | uint256 | Min totalAssets for eligibility |
| `minPostWithdrawAssets` | uint256 | Post-withdraw floor |
| `accountant` | IRobinAccountant | Fee module |
| `strategyMigrationDelay` | uint256 | Migration timelock |
| `pendingMigration` | PendingStrategyMigration | Pending strategy |

### Constructor

Sets asset/name/symbol/authority; Active; cap=max; defaultMaxLoss=50; profit unlock=7 days.

---

### External/Public Functions

#### `totalAssets()` → uint256

**Formula:** `gross − lockedRemaining` (see Ch. 9). **Critical** for share price.

#### `maxDeposit(receiver)` → uint256

Zero if not Active or at cap; else `depositCap − totalAssets()`.

#### `deposit` / `mint` — override, `nonReentrant`

Call super; `_updateEligibilityTracking()`.

#### `withdraw` / `redeem` — override, `nonReentrant`

Delegate to `_withdrawWithMaxLoss` / `_redeemWithMaxLoss` with `defaultMaxLossBps`.

#### `withdraw(..., maxLossBps)` / `redeem(..., maxLossBps)` — external

User-specified loss bound.

#### `previewInKindRedeem(shares)` → InKindRedemptionResult

Calls strategy preview; adds vault INDEX pro-rata; subtracts locked profit discount.

#### `redeemInKind(shares, receiver, owner[, maxLossBps])`

Full flow in [08-execution-flows.md](../08-execution-flows.md).

**Errors:** `ZeroShares`, `ZeroAddress`, `InKindRedemptionMismatch`, max redeem exceeded

#### `setStrategy(newStrategy)` — restricted

Once only (no prior strategy); validates vault/asset match.

#### `setStrategyMigrationDelay` / `proposeStrategyMigration` / `executeStrategyMigration` / `cancelStrategyMigration`

Timelocked replacement when debt zero.

#### `setAccountant` / `setDepositCap` / `setIdleBufferBps` / `setDefaultMaxLossBps` / `setProfitMaxUnlockTime` / `setEligibilityThreshold` / `setMinPostWithdrawAssets`

Governance parameter setters.

#### `pause` / `unpause` / `shutdown` — restricted

Lifecycle control; shutdown irreversible.

#### `deployIdle()` / `deploy(assets)` — restricted, nonReentrant

Capital deployment to strategy.

#### `report(HarvestReport)` — external, `msg.sender == strategy`, nonReentrant

Updates debt, locked profit, fees; emits `StrategyReported`.

#### `isEligible()` → (bool, qualifyingBalance, threshold)

`qualifyingBalance = totalAssets()`; eligible if threshold==0 or balance ≥ threshold.

---

### Private Helpers

| Function | Role |
|---|---|
| `_redeemInKindWithMaxLoss` | In-kind CEI implementation |
| `_withdrawWithMaxLoss` / `_redeemWithMaxLoss` | Max loss withdraw path |
| `_withdrawWithLossBound` | Liquidity + super._withdraw |
| `_deployToStrategy` | Transfer + deployFunds + debt |
| `_ensureLiquidity` | Idle or strategy.freeFunds |
| `_deployableIdle` | Buffer-aware deploy amount |
| `_inKindStrategy` | Cast strategy to IInKindRedemptionStrategy |
| `_validInKindResult` | Preview vs actual + maxLoss on INDEX |
| `_lockedProfitRemaining` | Linear vesting math |
| `_syncLockedProfit` | Age locked profit |
| `_enforcePostWithdrawEligibility` | minPostWithdrawAssets check |
| `_assessReportFees` | Cap-and-forfeit fee transfer |
| `_validateStrategy` | vault/asset compatibility |

---

### Events (vault-specific)

`StrategyUpdated`, `StrategyMigrationProposed`, `InKindRedeem`, `FeesCapped`, `ProtocolFeesCollected`, `StrategyDebtUpdated`, etc.

---

### Security Considerations

- **nonReentrant** on all user paths
- **Virtual shares** anti-inflation
- **Locked profit** anti-harvest sandwich
- **maxLossBps** on strategy withdrawals
- **In-kind preview verification** prevents oracle latency arbitrage (bounded)
- **Timestamp** used for profit unlock — acceptable over 7-day window per Slither notes

### Gas

In-kind O(n) retained tokens. Report/sync locked profit on every harvest.

---

**Next:** [strategies.md](./strategies.md)
