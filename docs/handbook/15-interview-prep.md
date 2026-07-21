# Chapter 15 — Interview Preparation

150 questions about **this repository**, with detailed answers citing contracts and tests. Organized by difficulty.

---

## Section A — Beginner (Questions 1–50)

### Blockchain & Repo Basics

**1. What is Robin Harvest?**  
An ERC-4626 yield optimizer on Robinhood Chain targeting Index Finance. Users deposit INDEX; vaults deploy via Core or Growth strategies; rewards are claimed and processed per governance policy. See `README.md`.

**2. What version is the codebase?**  
`v0.1.0-alpha`, feature complete, pre-audit (`README.md`).

**3. What is the vault asset?**  
INDEX ERC-20 (`DeployRobinHarvest.s.sol` uses `INDEX_TOKEN_ADDRESS`).

**4. Name the two vault products.**  
Core (`rhINDEX-C` + `CoreStrategy`) and Growth (`rhINDEX-G` + `GrowthStrategy`).

**5. What toolchain compiles the contracts?**  
Foundry, Solidity 0.8.25, EVM Paris (`foundry.toml`).

**6. Where is the main vault contract?**  
`src/vaults/RobinVault.sol`.

**7. What OpenZeppelin version is used?**  
v5.6.1 (`README.md`, `foundry.toml` dependencies).

**8. Is the protocol approved for production?**  
No — external audit and external addresses pending (`README.md` launch checklist).

**9. What license applies?**  
MIT (`LICENSE`).

**10. What command runs tests?**  
`forge test` (`README.md`).

---

### ERC-4626 & User Flow

**11. What standard do vault shares follow?**  
ERC-4626 over ERC-20 (`RobinVault` extends `ERC4626Paris`).

**12. What function deposits INDEX?**  
`deposit(uint256 assets, address receiver)` on `RobinVault`.

**13. What function withdraws a fixed INDEX amount?**  
`withdraw(uint256 assets, address receiver, address owner)`.

**14. What function burns shares for INDEX?**  
`redeem(uint256 shares, address receiver, address owner)`.

**15. What is special about Growth redemptions?**  
Optional `redeemInKind` returns INDEX + retained stocks (`RobinVault`, `GrowthStrategy`).

**16. Does standard redeem liquidate stocks?**  
Standard ERC-4626 paths return INDEX only; Growth may liquidate retained assets via `_freeFunds` (`GrowthStrategy`).

**17. What token do users receive on Core withdraw?**  
INDEX only.

**18. What is `totalAssets()` used for?**  
Share pricing and deposit caps (`RobinVault.totalAssets`).

**19. Why might `previewDeposit` differ from exact deposit?**  
Rounding — floor shares on deposit (`ERC4626Paris._convertToShares`).

**20. What is `maxDeposit` when paused?**  
0 (`RobinVault.maxDeposit` checks `lifecycleState == Active`).

---

### Strategies & Index Finance

**21. How many strategies per vault in V1?**  
One (`RobinVault.strategy`).

**22. What does CoreStrategy do with rewards?**  
Sells enabled rewards to INDEX; reverts on Retain disposition (`CoreStrategy._processRewardToken`).

**23. What extra capability does GrowthStrategy add?**  
Retain rewards, portfolio NAV, in-kind redemption, liquidation order (`GrowthStrategy.sol`).

**24. Who calls `harvest()`?**  
Keeper or governance-authorized caller (`StrategyBase.harvest`, `restricted`).

**25. What external protocol deploys INDEX?**  
Index Finance via `IIndexFinanceCore.deposit` (`CoreStrategy._deployFunds`).

**26. Is Index Finance integration final?**  
Provisional — `OPEN_QUESTIONS.md`, `IIndexFinanceCore` interface.

**27. What happens on harvest if one reward token fails?**  
Token isolated; harvest continues (`StrategyBase.harvest` try/catch).

**28. What is `deployIdle()`?**  
Deploys excess vault INDEX above idle buffer (`RobinVault._deployableIdle`).

**29. What is strategyDebt?**  
Vault book value of assets assigned to strategy (`RobinVault.strategyDebt`).

**30. Who can call `report()`?**  
Only configured strategy (`RobinVault.report`, `StrategyMismatch` otherwise).

---

### Registries & Router

**31. What does OracleRegistry do?**  
Validates and normalizes price feeds (`OracleRegistry.getValidatedPrice`).

**32. What does RewardRegistry do?**  
Stores per-token sell/retain/ignore policy (`RewardTokenConfig`).

**33. Why use ExecutionRouter instead of calling DEX directly?**  
Constrained adapters/routes, no arbitrary calldata (`ExecutionRouter.sol`).

**34. What DEX adapter ships in-repo?**  
`UniswapV2DexAdapter`.

**35. Can governance add multi-hop swap paths?**  
Yes — `UniswapV2DexAdapter.setCustomPath` (CHANGELOG v1.2).

---

### Governance & Access

**36. What contract holds roles?**  
`AccessManager` (`src/access/AccessManager.sol`).

**37. Name three roles.**  
Governance, Keeper, Security Council (role IDs 1, 3, 6).

**38. Who can pause the vault?**  
Security Council on pause selector (`ConfigureRobinHarvest._setVaultSelectorRoles`).

**39. Who can call `harvest`?**  
Keeper role (`ConfigureRobinHarvest`).

**40. What modifier protects admin functions?**  
`restricted` from OpenZeppelin `AccessManaged`.

---

### Fees & Accounting

**41. Where are fees configured?**  
`RobinAccountant.setFeeConfig`.

**42. What two fee types exist?**  
Performance (high-water mark) and management (time-based).

**43. What is locked profit?**  
Reported gains excluded from `totalAssets()` until linear unlock (`RobinVault.lockedProfit`).

**44. Default profit unlock duration?**  
7 days (`DEFAULT_PROFIT_MAX_UNLOCK_TIME`).

**45. What happens if fees exceed locked profit?**  
Cap-and-forfeit — fee capped at locked profit (`RobinVault._assessReportFees`, CHANGELOG).

---

### Testing & Security Basics

**46. Name a test file for the vault.**  
`test/unit/RobinVault.t.sol`.

**47. Are invariant tests included?**  
Yes — `test/invariant/RobinHarvestInvariant.t.sol`.

**48. What static analyzer runs in CI?**  
Slither (`.github/workflows/slither.yml`).

**49. Are fee-on-transfer tokens supported?**  
No — explicit rejection in Growth in-kind (`FeeOnTransferDetected`).

**50. What is the default max loss on withdraw?**  
50 bps (`RobinVault` constructor sets `defaultMaxLossBps = 50`).

---

## Section B — Intermediate (Questions 51–100)

### Share Math & ERC4626Paris

**51. Why does Robin Harvest use `ERC4626Paris` instead of OZ ERC4626?**  
OZ ERC4626 imports Cancun `mcopy`; repo targets EVM Paris (`ERC4626Paris.sol` comment).

**52. Write the convertToShares formula.**  
`assets * (totalSupply + 10^offset) / (totalAssets + 1)` floor (`ERC4626Paris._convertToShares`).

**53. What is decimals offset in RobinVault?**  
6 (`DECIMALS_OFFSET`).

**54. Why virtual shares/assets (+1, +10^offset)?**  
Mitigate first-depositor / donation inflation attacks (OZ ERC-4626 pattern).

**55. How does `totalAssets()` differ from gross assets?**  
Subtracts remaining locked profit (`RobinVault.totalAssets`).

**56. When is locked profit synced?**  
Before report, fee assessment, unlock duration change (`_syncLockedProfit`).

**57. Formula for remaining locked profit mid-vesting?**  
`lockedProfit * (1 - elapsed/duration)` (`_lockedProfitRemaining`).

**58. What happens if `profitMaxUnlockTime` is set to 0?**  
Remaining locked profit returns 0 immediately when duration is 0.

**59. How does deposit cap interact with `maxDeposit`?**  
`depositCap - totalAssets()` when Active (`RobinVault.maxDeposit`).

**60. What test protects first depositor inflation?**  
`testDonationDoesNotBreakFirstDepositorShareProtection` in `RobinVault.t.sol`.

---

### Withdrawals & Liquidity

**61. Walk through `_ensureLiquidity`.**  
If vault idle INDEX ≥ needed, return. Else `strategy.freeFunds(shortfall)`, verify loss BPS ≤ maxLoss, reduce strategyDebt (`RobinVault._ensureLiquidity`).

**62. Why is max loss enforced in vault not strategy?**  
Phase 3 interface `freeFunds(uint256)` only (`IRobinStrategy`, `PHASE_6_10_FUNCTION_REVIEW.md`).

**63. How is loss BPS computed on freeFunds?**  
`loss * BPS / (amountFreed + loss)` ceil.

**64. What Growth-specific step happens in `_freeFunds`?**  
Liquidate retained tokens in governance order if INDEX insufficient (`GrowthStrategy._freeFunds`).

**65. What happens if a retained token has paused oracle during withdraw?**  
Skipped with event — INDEX-only withdraw not DoS'd (CHANGELOG retained token skipper).

**66. What is idle buffer?**  
`idleBufferBps` of totalAssets kept undeployed for withdraw liquidity.

**67. What is minPostWithdrawAssets?**  
Optional revert if post-withdraw totalAssets below minimum (`_enforcePostWithdrawEligibility`).

**68. How does eligibility threshold work?**  
`totalAssets() >= eligibilityThreshold` (`isEligible`); not raw INDEX balance (DESIGN.md).

**69. When is EligibilityStatusChanged emitted?**  
When eligible flag toggles on deposit/withdraw/report/threshold change.

**70. Explain strategy migration timelock.**  
Propose when debt=0, wait `strategyMigrationDelay`, execute (`proposeStrategyMigration`, `executeStrategyMigration`).

---

### Harvest & Rewards

**71. Order of operations in `StrategyBase.harvest`.**  
Claim → per-token process (try/catch) → compute gain/loss → transfer idle INDEX as debtPayment → vault.report.

**72. Why `this.processRewardToken` external self-call?**  
Isolate per-token failures in try/catch (`StrategyBase.processRewardToken`, `OnlySelf`).

**73. How does Core compute min swap output?**  
Oracle prices both legs, decimal adjust, subtract `maxSlippageBps` (`CoreStrategy._minimumOutput`).

**74. What dispositions exist?**  
Ignore, Sell, Retain (`RewardDisposition` enum).

**75. When is reward deferred not processed?**  
Balance < `minHarvestAmount` (`CoreRewardDeferred` event).

**76. How does Growth split retain vs sell?**  
`_computeRetainBps` from category policy vs current exposure; retain portion via `_retainRewardAmount`.

**77. What must hold to retain a token?**  
retainable, oracle, approved route, valid stock token, exposure caps (`GrowthStrategy._retainRewardAmount`).

**78. How is retained NAV valued?**  
min(oracle value, DEX quote) minus `navHaircutBps` (`GrowthStrategy._valueToken`).

**79. What is IStockToken used for?**  
`transfersEnabled()` and interface check before retention.

**80. What happens if Index not eligible?**  
`IndexFinanceIneligible` on claim/tend (`CoreStrategy._claimRewards`).

---

### Oracle & Swaps

**81. Normalized oracle price decimals?**  
1e18 (`OracleRegistry.NORMALIZED_PRICE_DECIMALS`).

**82. What stale check is applied?**  
`block.timestamp > observedAt + heartbeat` → `StaleOracle`.

**83. What is uiMultiplier for?**  
Corporate action / display adjustment post-normalization.

**84. ExecutionRouter deviation check optional?**  
Yes — `maxOracleDeviationBps == 0` skips (`ExecutionRouter._enforceOracleDeviation`).

**85. How does router verify swap output?**  
Recipient balance delta ≥ minAmountOut.

**86. SwapRequest deadline type?**  
uint48 in struct; strategy checks overflow (`CoreStrategy._swapDeadline`).

**87. Sell disposition config requirement?**  
Adapter must be pre-approved in RewardRegistry (`RewardRegistry._validateConfig`).

**88. Difference between router adapter approval and reward adapter approval?**  
Router global; reward per-token policy — both required for swaps.

**89. How does adapter handle missing quote?**  
`quoteExactInput` returns 0; Growth uses oracle-only if quote 0.

**90. What test verifies oracle deviation revert?**  
`testOracleDeviationReverts` in `ExecutionRouter.t.sol`.

---

### In-Kind Redemption

**91. Which strategy implements in-kind?**  
`GrowthStrategy` via `IInKindRedemptionStrategy`.

**92. Pro-rata payout rounding direction?**  
Floor — prevents overpayment (DESIGN.md).

**93. Full redemption special case?**  
When shares == supply, transfer entire balances — no dust stranded.

**94. CEI order in redeemInKind?**  
Validate → preview → burn shares → reduce debt/lockedProfit → strategy transfers → vault verify → transfer vault INDEX (`DESIGN.md` sequence).

**95. Who bears in-kind INDEX slippage?**  
Exiting user, bounded by `maxLossBps` (OPEN_QUESTIONS resolved, CHANGELOG).

**96. What is locked profit discount on in-kind INDEX?**  
Ceil pro-rata share subtracted from gross INDEX payout (`previewInKindRedeem`).

**97. What invariant test checks exposure caps?**  
`invariant_growthExposureCaps` in `RobinHarvestInvariant.t.sol`.

**98. What reverts on fee-on-transfer retained token?**  
`FeeOnTransferDetected` in `_transferExact`.

**99. Can in-kind run when strategy paused?**  
Test `testInKindRedemptionRemainsAvailableWhenStrategyPaused` — vault path may still work; strategy must not be paused for harvest not redemption from vault.

**100. Triple payout consistency?**  
preview == event == receiver delta (DESIGN.md, Growth tests).

---

## Section C — Advanced (Questions 101–150)

### Accounting Edge Cases

**101. Prove fee cap-and-forfeit with code path.**  
`report` → `_assessReportFees` → if `totalFee > lockedProfit` cap → transfer min; excess forfeited (`RobinVault` lines 635–638).

**102. Can performance fee charge during loss recovery?**  
No if `totalAssetsGross <= highWaterMark` (`RobinAccountant._assessPerformanceFee`).

**103. How is HWM initialized?**  
First gain report: HWM = gross - reportedGain.

**104. Relationship between reportedGain and feeableGain?**  
feeableGain capped at reportedGain even if above HWM gap.

**105. Management fee when totalAssetsGross is 0?**  
Accrual clock still updates; fee 0.

**106. Does donating INDEX to vault inflate share price?**  
Donation increases gross assets; virtual share math mitigates first-depositor attack; donation benefits all shareholders.

**107. strategyDebt after report with gain?**  
`newDebt = prev + gain - (loss + debtPayment)` (`RobinVault.report`).

**108. When can debtReduction exceed strategyDebt?**  
Never — reverts `InvalidAccounting`.

**109. Emergency withdraw accounting path?**  
Strategy `_emergencyWithdraw`, transfer all INDEX, report loss/debtPayment, shutdown (`StrategyBase.emergencyWithdraw`).

**110. lastReportedAssets purpose?**  
Harvest gain/loss delta baseline (`StrategyBase.harvest`).

---

### Security & MEV

**111. How does locked profit mitigate harvest sandwich?**  
New gains not in totalAssets until vest; front-run deposit gets fewer shares on unlocked portion only.

**112. In-kind sandwich test?**  
`testInKindSandwichExploitFails` in `GrowthStrategy.t.sol`.

**113. Reentrancy guards on which vault functions?**  
deposit, mint, withdraw, redeem, redeemInKind, deploy, report (`nonReentrant`).

**114. Why CEI violated in `_ensureLiquidity`?**  
Debt reduction depends on external freeFunds return; mitigated by nonReentrant on callers (Slither comment).

**115. Can keeper pass arbitrary swap calldata?**  
No — parameterless harvest; routes fixed in registries.

**116. Oracle manipulation on Growth NAV?**  
Conservative min(oracle, quote) + haircut; stale feeds revert on retain/refresh.

**117. Flash loan attack surface on deposit/redeem same block?**  
Virtual shares + locked profit reduce pure inflation; not fully eliminated for all patterns — audit scope.

**118. Isolation flag bug fix?**  
`removeRewardToken` clears `isRewardTokenIsolated` (CHANGELOG).

**119. DEX approval hardening?**  
forceApprove then reset to 0 post swap (adapter + router).

**120. Slither timestamp findings on vault?**  
Accepted for multi-day profit unlock windows.

---

### Deployment & Operations

**121. Deployment script entrypoint?**  
`script/DeployRobinHarvest.s.sol:DeployRobinHarvest`.

**122. What ConfigureRobinHarvest does?**  
Roles, vault wiring, oracles, rewards, routes (`ConfigureRobinHarvest.s.sol`).

**123. ValidateRobinHarvest purpose?**  
Read-only fail-closed verification before enablement.

**124. Required env vars for deploy?**  
GOVERNANCE_ADDRESS, INDEX_TOKEN_ADDRESS, INDEX_FINANCE_ADDRESS, MAX_SLIPPAGE_BPS, etc. (`docs/DEPLOYMENT.md`).

**125. CI fuzz seed?**  
`0x726f62696e2d68617276657374` ("robin-harvest" ASCII, `foundry.toml`).

**126. CI invariant depth vs local?**  
CI: 500 runs, depth 128; local: 256/64.

**127. EIP-170 compliance?**  
README — all contracts under 24kb; CI `forge build --sizes`.

**128. Post-deploy first step?**  
Transfer ADMIN_ROLE to governance multisig (`DEPLOYMENT.md`).

**129. Idempotent configuration?**  
Configure script skips re-set if already correct; reverts on mismatch.

**130. fs_permissions in foundry.toml?**  
Read `./deployments` for scripts.

---

### Design & Architecture

**131. Why separate accountants per vault?**  
Independent HWM and fee accrual per product (`DeployRobinHarvest`).

**132. Why shared OracleRegistry?**  
Single feed config; both strategies read same prices.

**133. CategoryPolicy rebalance algorithm implemented?**  
No — only hooks and cooldown marker (`markRebalance` comment Phase 13).

**134. LP strategy status?**  
Not implemented — README blocked on LP type confirmation.

**135. IRobinVaultReport purpose?**  
Strategy calls `vault.report` without importing full vault (`IRobinVaultReport.sol`).

**136. Why Growth extends Core not StrategyBase?**  
Reuse Index deploy/withdraw/sell pipeline (`GrowthStrategy is CoreStrategy`).

**137. Retained token iteration gas concern?**  
O(n) in-kind; DESIGN.md warns 200+ assets may hit block limit.

**138. Doc vs code: Phase 6 redeemInKind stub?**  
PHASE_6_10 doc outdated; implementation live in Growth (Ch. 1 discrepancy table).

**139. Alternatives to floor rounding on in-kind?**  
Ceil would overpay leavers; floor leaves dust for remainders (DESIGN.md).

**140. Can Core vault call redeemInKind?**  
Vault exposes function but CoreStrategy doesn't implement IInKindRedemption — calls revert or mismatch unless Growth strategy set.

---

### Code Reading & Debugging

**141. Find all custom errors on RobinVault.**  
CapExceeded, InKindRedemptionNotSupported, InKindRedemptionMismatch, ZeroShares, StrategyAlreadySet, etc. (contract + inherited).

**142. Which events does Events.sol define?**  
LifecycleStateChanged, StrategyReported, SwapExecuted, OracleConfigured, etc.

**143. Constants.MAX_BPS value?**  
10_000 (`Constants.sol`).

**144. How to add new reward token to harvest loop?**  
Governance: RewardRegistry config + `strategy.addRewardToken` + router route.

**145. Mock used for Index Finance in tests?**  
`MockIndexFinanceCore` (`test/mocks/`).

**146. Handler in invariant test?**  
`RobinHarvestHandler` — deposit, withdraw, redeemInKind, accrueAndHarvest.

**147. What does invariant_noProfitableSandwich assert?**  
User extracted value ≤ starting minted balance.

**148. Growth test for liquidation order?**  
`testLiquidationOrderIsHonored` in `GrowthStrategy.t.sol`.

**149. DeploymentFlow test significance?**  
Deploy doesn't auto-configure; governance script required (`DeploymentFlow.t.sol`).

**150. If you could audit one function first, which and why?**  
`_redeemInKindWithMaxLoss` — coordinates burn, debt, locked profit, external strategy transfer, preview verification; highest cross-contract accounting risk.

---

## How to Use This Chapter

- **Phone screen:** Questions 1–30  
- **Solidity onsite:** 51–100 + live trace of `harvest()`  
- **Staff / architect:** 101–150 + whiteboard architecture from [06-architecture.md](./06-architecture.md)

Cross-reference [16-glossary.md](./16-glossary.md) for term definitions.
