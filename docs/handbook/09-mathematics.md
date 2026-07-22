# Chapter 9 — Mathematics

All accounting formulas used in Robin Harvest with worked examples.

---

## 9.1 Basis Points (BPS)

From `Constants.sol`:

```
BPS = 10_000
1 bps = 0.01%
```

Used for: slippage, fees, exposure caps, max loss, haircuts.

---

## 9.2 ERC-4626 Share Conversion (Virtual Offset)

From `ERC4626Paris._convertToShares` / `_convertToAssets`:

```
offset = 10^DECIMALS_OFFSET   // RobinVault: DECIMALS_OFFSET = 6 → 1_000_000

shares = assets × (totalSupply + offset) / (totalAssets + 1)   [Floor]
assets = shares × (totalAssets + 1) / (totalSupply + offset)   [Floor default]
```

**Withdraw/redeem previews** use Ceil on shares-for-assets to favor vault.

### Worked example — first deposit

- `totalSupply = 0`, `totalAssets = 0`, offset = 1e6, deposit 1000e18 INDEX

```
shares = 1000e18 × (0 + 1e6) / (0 + 1) ≈ 1000e18 × 1e6
```

Virtual offset mitigates **first depositor inflation attack** (donation + front-run).

---

## 9.3 Vault totalAssets

From `RobinVault.totalAssets()`:

```
grossAssets = balanceOf(INDEX on vault) + strategyDebt
remainingLocked = _lockedProfitRemaining()
totalAssets = max(grossAssets − remainingLocked, 0)
```

### Locked profit remaining

```
if lockedProfit == 0 OR duration == 0 OR now >= lastProfitUpdate + duration:
    remaining = 0
else:
    elapsed = now − lastProfitUpdate
    unlocked = lockedProfit × elapsed / duration
    remaining = lockedProfit − unlocked
```

Default `duration = profitMaxUnlockTime = 7 days`.

### Example

- grossAssets = 1,000,000 INDEX
- lockedProfit = 100,000, elapsed = 3.5 days, duration = 7 days
- unlocked half → remainingLocked = 50,000
- totalAssets = 950,000 INDEX

---

## 9.4 Strategy Debt Updates

**On deploy** (`_deployToStrategy`):
```
strategyDebt += assets
```

**On report** (`report`):
```
debtReduction = loss + debtPayment
strategyDebt = previousDebt + gain − debtReduction
lockedProfit += gain
```

**On withdraw liquidity** (`_ensureLiquidity`):
```
strategyDebt -= (amountFreed + loss)
```

**On in-kind** (pro-rata):
```
debtReduction = shares == supplyBefore ? debtBefore : debtBefore × shares / supplyBefore
```

---

## 9.5 Harvest Gain/Loss

In `StrategyBase.harvest`:

```
assetsNow = totalAssets()  // strategy NAV
if assetsNow >= lastReportedAssets:
    gain = assetsNow − lastReportedAssets
else:
    loss = lastReportedAssets − assetsNow
debtPayment = idle INDEX balance (transferred to vault before report)
```

---

## 9.6 Performance Fee (High-Water Mark)

From `RobinAccountant._assessPerformanceFee`:

```
if reportedGain == 0 OR performanceBps == 0: fee = 0

Initialize HWM if first time:
    if highWaterMark == 0 AND totalAssetsGross > reportedGain:
        highWaterMark = totalAssetsGross − reportedGain

if totalAssetsGross <= highWaterMark: fee = 0

feeableGain = totalAssetsGross − highWaterMark
feeableGain = min(feeableGain, reportedGain)
performanceFee = feeableGain × performanceBps / BPS

highWaterMark = totalAssetsGross  // after assessment
```

### Example

- HWM = 1,000,000, gross after harvest = 1,050,000, reportedGain = 50,000, perf fee = 20%

```
feeableGain = 50,000
performanceFee = 50,000 × 2000 / 10000 = 10,000 INDEX
```

After loss: gross drops below HWM → **no performance fee** until recovery.

---

## 9.7 Management Fee

From `RobinAccountant._accrueManagementFee`:

```
elapsed = block.timestamp − lastFeeAccrual
managementFee = totalAssetsGross × managementBps / BPS × elapsed / SECONDS_PER_YEAR
lastFeeAccrual = block.timestamp
```

`SECONDS_PER_YEAR = 365 days` (Constants.sol).

### Example

- AUM = 10,000,000 INDEX, managementBps = 200 (2%), elapsed = 30 days

```
annual = 10M × 0.02 = 200,000
monthly ≈ 200,000 × (30/365) ≈ 16,438 INDEX
```

---

## 9.8 Cap-and-Forfeit Fee Policy

From `RobinVault._assessReportFees`:

```
totalFee = performanceFee + managementFee
if totalFee > lockedProfit:
    emit FeesCapped(totalFee, lockedProfit)
    totalFee = lockedProfit
lockedProfit -= totalFee
```

Excess fee is **permanently forfeited** — never charged to principal later.

---

## 9.9 Withdrawal Loss Bound

From `_ensureLiquidity`:

```
lossBps = loss × BPS / (amountFreed + loss)   [Ceil rounding]
require lossBps <= maxLossBps
```

User default: `defaultMaxLossBps = 50` (0.5%) unless overload specified.

---

## 9.10 Swap Minimum Output

From `CoreStrategy._minimumOutput`:

```
expectedOut = amountIn × priceIn / priceOut × 10^decOut / 10^decIn
minAmountOut = expectedOut × (BPS − maxSlippageBps) / BPS
```

Prices from `oracleRegistry.getValidatedPrice`.

Router additionally checks deviation vs execution if configured.

---

## 9.11 Growth — Retained Token Value

From `GrowthStrategy._valueToken`:

```
value = _oracleValue(token, amount)
quoteValue = _quoteValue(token, amount)  // DEX quote, 0 if unavailable
if quoteValue != 0 AND quoteValue < value:
    value = quoteValue
if navHaircutBps != 0:
    value = value × (BPS − navHaircutBps) / BPS
```

**Conservative NAV:** never values above min(oracle, quote), then haircut.

---

## 9.12 Exposure (Basis Points of NAV)

From `_exposureBps`:

```
exposureBps = value × BPS / nav   [Ceil]
```

Enforced caps:
- Per token: `config.maxExposureBps`
- Per category: `categoryPolicies[cat].maxPortfolioBps`

---

## 9.13 Retain Split on Harvest

From `GrowthStrategy._processRewardToken`:

```
retainBps = _computeRetainBps(category)
retainAmount = processAmount × retainBps / BPS
sellAmount = processAmount − retainAmount
```

`_computeRetainBps` logic:
- If `maxRetainBps == 0` → retain 100%
- If category exposure < target → `maxRetainBps`
- If > target → `minRetainBps`
- Else → `targetRetainBps`

---

## 9.14 In-Kind Pro-Rata (Floor Rounding)

From DESIGN.md and `_inKindRedemptionResult`:

```
payout = floor(assetBalance × shares / totalSupplyBefore)
```

Full redemption (`shares == supply`): transfer **entire** remaining balance (no dust stranded).

Vault INDEX portion in preview adds pro-rata vault idle INDEX; subtracts **Ceil** share of locked profit discount.

---

## 9.15 Idle Buffer

From `_deployableIdle`:

```
targetIdle = totalAssets() × idleBufferBps / BPS
deployable = max(vaultIdle − targetIdle, 0)
```

---

## 9.16 Deposit Cap

```
maxDeposit = depositCap − totalAssets()   if Active and totalAssets < cap
else 0
```

---

**Next:** [08-contracts/README.md](./08-contracts/README.md)

---

## 9.17 Optimal Single-Sided LP Swap Amount

From `LpStrategy._optimalSwapAmount`:

Given a pool with reserves $(R_{\text{index}})$ and a single-sided deposit amount $A$ in INDEX, the exact amount $s$ to swap (so remaining INDEX + received paired token match the pool ratio exactly) is:

```
s = (sqrt(1997² × R² + 3996000 × R × A) − 1997 × R) / 1998
```

Where `1997 = 2 × 997 + 3` and the 997/1000 factor accounts for the standard 0.30% DEX swap fee.

### Worked example

- Pool: `R_index = 100_000 INDEX`, deposit = 10_000 INDEX

```
discriminant = 1997² × 100000² + 3996000 × 100000 × 10000
             = 3.988009e14 + 3.996e15
             = 4.39480e15
sqrt(discriminant) ≈ 66,293,288
s ≈ (66_293_288 − 199_700_000) / 1998 ... (simplified)
≈ 4878 INDEX   (slightly less than 50%)
```

The remaining `10000 − 4878 = 5122 INDEX` and the received paired tokens are deposited into the pool with zero leftovers.

---

## 9.18 Mark-to-Market LP Token Valuation

From `LpStrategy.deployedAssets`:

```
totalPoolValueIndex = reserveIndex + reservePaired × pricePaired / 1e18
deployedAssets = stakedLpBalance × totalPoolValueIndex / lpTotalSupply
```

Where:
- `reserveIndex`, `reservePaired` = current pool reserves (from `IUniswapV2Pair.getReserves()`)
- `pricePaired` = oracle price of paired token denominated in INDEX (from `OracleRegistry`)
- `stakedLpBalance` = LP tokens staked in Gauge
- `lpTotalSupply` = total supply of the LP token

### Worked example

- Pool reserves: 50,000 INDEX + 50,000 AAPL
- Oracle: AAPL = 2.0 INDEX (i.e., `2e18`)
- LP totalSupply = 100,000; strategy holds 10,000 LP

```
totalPoolValueIndex = 50000 + 50000 × 2.0 = 150,000 INDEX
deployedAssets = 10000 × 150000 / 100000 = 15,000 INDEX
```


