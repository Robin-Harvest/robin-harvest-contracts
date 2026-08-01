# Chapter 11 — Testing

## 11.1 Test Framework

**Foundry** (`forge test`) with Solidity tests co-located in `test/`.

Configuration (`foundry.toml`):

| Profile | Fuzz runs | Invariant runs | Depth |
|---|---|---|---|
| default | 256 | 256 | 64 |
| ci | 1000 | 500 | 128 |

Seed: `0x726f62696e2d68617276657374` ("robin-harvest")

`invariant.fail_on_revert = true` — handler reverts fail the run.

---

## 11.2 Unit Tests

### RobinVault.t.sol

| Test | Proves |
|---|---|
| `testDepositMintsSharesAndRespectsCap` | ERC-4626 mint + depositCap |
| `testFuzzDepositShareAccounting` | Share math random amounts |
| `testPauseStopsDepositsButAllowsWithdrawals` | Lifecycle |
| `testDeployIdleCreatesStrategyDebtAndHonorsBuffer` | idleBufferBps |
| `testWithdrawFreesStrategyFundsWithinMaxLoss` | freeFunds integration |
| `testWithdrawRevertsWhenLossExceedsMaxLoss` | LossExceedsMaximum |
| `testReportedProfitUnlocksLinearly` | Locked profit vesting |
| `testDonationDoesNotBreakFirstDepositorShareProtection` | Virtual offset |
| `testReportSucceedsWhenFeesExceedLockedProfit` | Cap-and-forfeit |
| `testStrategyMigrationRequiresTimelock` | Migration delay |

### CoreStrategy.t.sol

Deploy/free funds, harvest sell, min output decimals, ignore/disposition, retain revert, loss reporting, isolation on router/oracle failure, reentrancy, malformed claim.

### GrowthStrategy.t.sol

Extensive suite: retention, exposure limits, in-kind (partial/full/sequential), liquidation order, sandwich, fee-on-transfer rejection, NAV conservation, category retain bands, oracle pause on withdraw.

### LpStrategy.t.sol

Pool liquidity deployment, proportional LP token burning on freeFunds, governance controls (gauge, max slippage, pause compounding), auto-compounding of arbitrary reward tokens, and unhealthy oracle handling.

### Registry/Router/Accountant/Access/Adapter

Each file tests governance validation, revert paths, and happy paths documented in function review.

### DeploymentFlow.t.sol

Deploy script does not auto-configure; Configure script idempotency; Validate fails before init.

---

## 11.3 Integration Tests

`GrowthStrategy.t.sol` includes full lifecycle tests:

- `testFullGrowthLifecycleIntegrationThroughFullWithdrawal`
- `testMixedRedemptionLifecycleIntegration`

These combine deposit → deploy → harvest → retain → withdraw/redeem/in-kind.

---

## 11.4 Invariant Tests

### RobinHarvestInvariant.t.sol
**Handler:** `RobinHarvestHandler` — random deposit, withdraw, redeemInKind, accrueAndHarvest.

| Invariant | Property |
|---|---|
| `invariant_noProfitableSandwich` | User extracted value ≤ starting balance |
| `invariant_navMonotonicity` | NAV per share ≥ ~1 (minus tolerance) |
| `invariant_noFeesOnPrincipal` | Fees bounded / not draining principal unboundedly |
| `invariant_growthExposureCaps` | Stock exposure ≤ config + tolerance |
| `invariant_coreRetainsNothing` | Core strategy stock balance always 0 |

### RobinHarvestLpInvariant.t.sol
**Handler:** `LpHarvestHandler` — random deposit, withdraw, harvest for LP vaults.

| Invariant | Property |
|---|---|
| `invariant_lpAccountingConserved` | Deployed LP assets + vault idle = NAV |
| `invariant_lpTotalAssetsNonNegative` | Total assets strictly ≥ 0 |
| `invariant_noRewardTokensStranded` | Reward tokens fully processed / 0 stranded |
| `invariant_withdrawBoundedByNav` | Withdrawals strictly bounded by available NAV |

`invariant_lossBoundsRespected` — documented placeholder (enforced by reverts in handler).

---

## 11.5 Fuzz Tests

Examples:

- `RobinVault.t.sol`: `testFuzzDepositShareAccounting`
- `RobinAccountant.t.sol`: fee split, HWM drift
- `OracleRegistry.t.sol`: positive price normalization
- `RewardRegistry.t.sol`: exposure BPS rejection
- `StrategyBase.t.sol`: `testFuzzFreeFundsRepaysUpToRequestedAmount`

---

## 11.6 Mocks

| Mock | Simulates |
|---|---|
| `MockINDEX` | Mintable INDEX |
| `MockIndexFinanceCore` | Deposit/withdraw/accrue/claim |
| `MockDex` | Configurable swap output |
| `MockOracle` | Chainlink-shaped feed |
| `MockStockToken` | transfersEnabled, mint |
| `MockFeeOnTransferToken` | Deficit on transfer |
| `TestStrategy` | Concrete StrategyBase for unit tests |

Mocks **do not** replace mainnet fork tests (listed as launch blocker).

The CL strategy additionally requires regression coverage for current-timestamp TWAP expiry and exact-per-operation
Permit2 approvals. See [`docs/SECURITY_HARDENING.md`](../SECURITY_HARDENING.md) for the selected security policies.

---

## 11.7 Running Tests

```bash
forge test                    # default profile
FOUNDRY_PROFILE=ci forge test # CI parity
forge test --match-contract GrowthStrategy -vvv
forge test --match-path test/invariant/*
```

---

## 11.8 What Is NOT Tested (Gaps)

| Gap | Risk | Mitigation path |
|---|---|---|
| Real Index Finance contracts | Integration mismatch | Mainnet fork tests + official ABI |
| Real Robinhood Chain oracles/DEX | Production behavior | Fork + staging deploy |
| Extreme retained token count gas | O(n) in-kind DoS | Operational limits on portfolio size |
| AccessManager delay scheduling | Misconfiguration | Validate script + ops checklist |
| Multi-vault cross-contamination | N/A V1 | Single strategy per vault by design |
| LP strategy | Not implemented | Future phase |
| Upgrade/migration with live debt | Blocked in V1 | Timelock migration at zero debt only |
| 100% formal verification | — | External audit |

---

## 11.9 CI Integration

`.github/workflows/test.yml`: `forge build --sizes` + `forge test -vvv` on push/PR with `FOUNDRY_PROFILE=ci`.

EIP-170 size regression caught at build time.

---

**Next:** [12-security.md](./12-security.md)
