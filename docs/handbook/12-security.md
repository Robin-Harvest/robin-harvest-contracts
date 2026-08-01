# Chapter 12 — Security

## 12.1 Threat Model Overview

Robin Harvest V1 faces standard DeFi threats:

| Threat | Surface | Severity |
|---|---|---|
| Reentrancy | vault withdraw, harvest, swaps | High |
| Oracle manipulation | NAV, minOut, deviation | High |
| Share inflation | first depositor / donation | Medium |
| Flash loans | harvest/swap/redemption timing | Medium |
| Sandwich / MEV | swaps, large withdrawals | Medium |
| Access control bypass | governance functions | Critical |
| Accounting drift | debt vs actual balances | High |
| DoS | many retained tokens, failing oracle | Medium |
| Malicious tokens | fee-on-transfer, hooks | Medium |
| External protocol | Index Finance bugs | High (external) |

---

## 12.2 Reentrancy

### Mitigation

- `ReentrancyGuard` on `RobinVault` user functions, `ExecutionRouter.swapExactInput`, `StrategyBase.harvest`/`emergencyWithdraw`
- CEI on in-kind redemption (burn before transfers)
- `processRewardToken` only callable via `address(this)`

### Residual

`_ensureLiquidity` calls `freeFunds` before updating debt — **documented** exception because return values required; protected by vault `nonReentrant`.

---

## 12.3 Oracle Manipulation

### Mitigations

- Heartbeat staleness (`StaleOracle`)
- Positive price validation
- Round completeness check
- Pause flag per asset
- Router deviation bound (optional per route)
- Strategy minOut from oracle − slippage
- Growth NAV: **min(oracle, DEX quote)** + haircut

### Residual

- Short-term oracle spike still affects minOut until heartbeat/deviation catches
- Market-hours / corporate actions on stock tokens — **OPEN_QUESTIONS**
- Paused oracle **blocks** in-kind exposure refresh (`testPausedOracleFreezesWithdrawal`)

---

## 12.4 Share Inflation

### Mitigation

ERC4626Paris virtual offset (`10^6` virtual shares/assets).

**Test:** `testDonationDoesNotBreakFirstDepositorShareProtection`

---

## 12.5 Flash Loans

No explicit flash-loan guard. Attack must complete within one tx:

- Harvest gain computed from **strategy totalAssets()** delta, not single-block donation to vault alone
- Locked profit delays share price boost from reported gains
- In-kind: preview must match actual within `maxLossBps`

**Residual:** Sophisticated multi-step attacks within one tx against AMM — partially mitigated by minOut + deviation.

---

## 12.6 Sandwich Attacks

### Mitigations

- Slippage on swaps (`maxSlippageBps`, `minAmountOut`)
- User `maxLossBps` on withdrawals and in-kind
- Test: `testInKindSandwichExploitFails`

### Residual

Keepers' harvest txs remain public — MEV on reward selling.

---

## 12.7 Fee-on-Transfer / Non-Standard Tokens

### Policy

Explicitly **unsupported** (README).

### Mitigation

`GrowthStrategy._transferExact` — balance delta must equal amount or `FeeOnTransferDetected`.

---

## 12.8 Access Control

### Mitigation

- OpenZeppelin `AccessManaged` + `restricted`
- Role hierarchy in `AccessManager`
- Selector-level roles in `ConfigureRobinHarvest`
- `ValidateRobinHarvest` read-only verification script

### Trust

Compromised governance = full protocol control. Production requires multisig + timelock (OPEN_QUESTIONS).

---

## 12.9 Accounting Integrity

### Invariants

- `strategyDebt` tracks vault-booked deployment
- Report: `debtReduction <= previousDebt`
- Withdraw: balance increase ≥ amountFreed
- In-kind: debt reduction ∝ shares burned

### Fee cap

Cap-and-forfeit prevents fee debt on principal (v1.2).

---

## 12.10 DoS Vectors

| Vector | Behavior |
|---|---|
| Many retained tokens | In-kind gas O(n) — operational limit |
| One bad retained token on withdraw | **Skipped** (v1.2) — INDEX-only withdraw not blocked |
| Isolated reward token | Harvest continues for other tokens |
| Paused lifecycle | Deposits/harvest blocked; withdraw if liquidity |

---

## 12.11 Execution Router Safety

- No arbitrary call targets
- Adapter allowlist
- Route allowlist per (adapter, tokenIn, tokenOut)
- Approvals reset to 0 after swap
- Balance-delta verification

---

## 12.12 External Audit Scope

From README:

- Vault accounting
- Strategy accounting
- Oracle integration
- Reward processing
- Execution router
- In-kind redemption
- Fee accounting
- Strategy migration

---

## 12.13 Slither

CI runs `slither . --fail-pedantic`. Contracts include targeted suppressions with justifications (timestamp, reentrancy CEI exceptions, cyclomatic complexity on in-kind).

The CL strategy security decisions are recorded in [`docs/SECURITY_HARDENING.md`](../SECURITY_HARDENING.md), including
current-timestamp TWAP freshness, exact-per-operation Permit2 approvals, and sqrt-price deviation units.

---

## 12.14 Unmitigated / Accepted Risks

| Risk | Acceptance rationale |
|---|---|
| Index Finance provisional ABI | Must verify before mainnet |
| Immutable contracts | Migration path at zero debt only |
| Governance trust | Industry-standard for configurable DeFi |
| block.timestamp manipulation | Negligible vs day-scale unlock |
| No formal verification | Audit planned |

---

**Next:** [13-deployment.md](./13-deployment.md)
