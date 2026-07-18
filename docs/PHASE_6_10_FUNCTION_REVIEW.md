# Phase 6-10 Function Review

This document reviews the public and external surface added for Phases 6-10:

- `RobinVault`
- `OracleRegistry`
- `RewardRegistry`
- `ExecutionRouter`
- `StrategyBase`

Scope notes:

- Public state variables are included because Solidity generates public getter functions for them.
- Inherited OpenZeppelin-style ERC-20, ERC-4626, and `AccessManaged` functions are summarized where they are part of the ABI. The detailed per-function review focuses on functions declared or overridden by the Phase 6-10 contracts.
- The architecture document is treated as the source of truth. Where the repository's completed Phase 3 interfaces differ from the architecture sketch, the implementation intentionally preserves the existing interfaces.

## RobinVault

`RobinVault` implements Phase 6: an ERC-4626 vault with total asset/share accounting, one strategy, explicit strategy debt, idle buffer, deposit caps, inflation protection, profit unlocking, max-loss withdrawals, pause/shutdown states, eligibility hooks, and a reserved in-kind redemption extension point.

### Public Getters

#### `DEFAULT_PROFIT_MAX_UNLOCK_TIME()`

- Exists to expose the default locked-profit duration.
- Implements the profit smoothing / locked-profit requirement.
- Relies on the invariant that profit is only added through authenticated strategy reports.
- Assumes seven days is a reasonable default until governance updates it.
- Matches the architecture conceptually; the exact duration is an implementation parameter.

#### `lifecycleState()`

- Exists to expose whether the vault is `Active`, `Paused`, or `Shutdown`.
- Implements reversible pause and irreversible shutdown visibility.
- Relies on `_setLifecycleState` preventing exit from `Shutdown`.
- Assumes off-chain operators and integrators read this before attempting deposits or deployments.
- Matches the architecture.

#### `strategy()`

- Exists to expose the sole V1 strategy.
- Implements "one strategy per vault, V1".
- Relies on `setStrategy` verifying vault and asset compatibility.
- Assumes strategy migration with live debt is out of scope for this phase.
- Matches the architecture.

#### `strategyDebt()`

- Exists to expose asset-denominated capital assigned to the strategy.
- Implements single-strategy debt accounting.
- Relies on debt changing only through deployment, withdrawals/free-funds, and strategy reports.
- Assumes strategies report honest realized gain/loss/debt payment through the vault boundary.
- Matches the architecture.

#### `depositCap()`

- Exists to expose the current deposit ceiling.
- Implements deposit caps, especially useful while eligibility is uncertain.
- Relies on `maxDeposit` enforcing the cap against `totalAssets`.
- Assumes governance sets product-appropriate caps.
- Matches the architecture.

#### `idleBufferBps()`

- Exists to expose the configured idle liquidity buffer.
- Implements the idle liquidity buffer requirement.
- Relies on `deployIdle` preserving the configured buffer and governance setting sane BPS values.
- Assumes the buffer is expressed against vault `totalAssets`.
- Matches the architecture.

#### `defaultMaxLossBps()`

- Exists to expose the default loss bound for standard ERC-4626 withdrawals/redeems.
- Implements max-loss support while preserving standard ERC-4626 method signatures.
- Relies on `_ensureLiquidity` measuring realized loss from strategy `freeFunds`.
- Assumes users who need tighter bounds call the overloaded max-loss methods.
- Intentionally differs from the architecture sketch by keeping standard ERC-4626 methods and adding overloads, because Phase 3 interfaces were already fixed.

#### `lockedProfit()`

- Exists to expose profit still excluded from `totalAssets`.
- Implements profit smoothing and harvest front-running mitigation.
- Relies on `_syncLockedProfit` aging profit before new reports or unlock-duration changes.
- Assumes gains are reported by the strategy only after value is controlled by the system.
- Matches the architecture.

#### `lastProfitUpdate()`

- Exists to expose the timestamp used for locked-profit aging.
- Implements deterministic profit unlock accounting.
- Relies on monotonic block timestamps.
- Assumes no chain-level timestamp manipulation large enough to break unlock policy.
- Matches the architecture.

#### `profitMaxUnlockTime()`

- Exists to expose the current linear unlock duration.
- Implements configurable profit smoothing.
- Relies on governance-controlled updates and `_syncLockedProfit` before duration changes.
- Assumes governance can tune the duration per product risk.
- Matches the architecture.

#### `eligibilityThreshold()`

- Exists to expose the configurable INDEX eligibility threshold.
- Implements the instruction not to hardcode `10_000e18`.
- Relies on governance configuring the value after Index Finance semantics are known.
- Assumes this phase only provides hooks, not final Index Finance integration.
- Matches the architecture.

#### `minPostWithdrawAssets()`

- Exists to expose the optional post-withdraw minimum.
- Implements the eligibility invariant hook that withdrawals should not silently break qualification where configured.
- Relies on `_enforcePostWithdrawEligibility` running after withdrawals.
- Assumes governance sets this only when the product should enforce a minimum asset balance.
- Matches the architecture as a Phase 6 hook.

### Direct Functions

#### `totalAssets()`

- Exists to provide the ERC-4626 asset value used for share pricing.
- Implements total assets, strategy debt accounting, and locked-profit exclusion.
- Relies on `strategyDebt` being updated deterministically and on locked profit never exceeding gross assets.
- Assumes strategy NAV enters vault accounting through reports rather than arbitrary external reads.
- Matches the architecture's "single most security-critical number" requirement.

#### `maxDeposit(address)`

- Exists to expose the maximum deposit allowed under lifecycle and cap policy.
- Implements deposit caps and pause/shutdown deposit blocking.
- Relies on `totalAssets()` and `depositCap` being accurate.
- Assumes receiver-specific eligibility is not needed in Phase 6.
- Matches the architecture.

#### `maxMint(address)`

- Exists to provide ERC-4626-compatible mint limits in shares.
- Implements deposit cap enforcement for `mint`.
- Relies on `maxDeposit` and preview conversion consistency.
- Assumes standard ERC-4626 share previews are acceptable.
- Matches the architecture.

#### `deposit(uint256 assets, address receiver)`

- Exists as the standard ERC-4626 deposit entry point.
- Implements deposit asset acceptance, share minting, and per-user share accounting.
- Relies on `maxDeposit`, ERC-4626 preview math, non-reentrancy, and safe ERC-20 transfer behavior.
- Assumes deposits are denominated only in the vault asset.
- Matches the architecture, with ERC-4626 math provided by a Paris-compatible local base rather than importing OZ's current Cancun-only implementation.

#### `mint(uint256 shares, address receiver)`

- Exists as the standard ERC-4626 share-targeted deposit entry point.
- Implements ERC-4626 total shares and user share accounting.
- Relies on `maxMint`, `previewMint`, non-reentrancy, and safe asset transfer-in.
- Assumes users accept the asset amount calculated by ERC-4626 rounding rules.
- Matches the architecture.

#### `withdraw(uint256 assets, address receiver, address owner)`

- Exists as the standard ERC-4626 asset-targeted withdrawal entry point.
- Implements standard withdrawals while applying the governance default max-loss bound.
- Relies on allowance checks, `_ensureLiquidity`, and `defaultMaxLossBps`.
- Assumes users who require a custom loss bound call the overload.
- Intentionally differs from the architecture sketch that showed max loss in the primary signature; the standard signature is preserved for ERC-4626 compatibility.

#### `withdraw(uint256 assets, address receiver, address owner, uint16 maxLossBps)`

- Exists to let users provide an explicit max-loss bound.
- Implements maxLossBps support and selective withdrawal's "revert rather than socialize excessive slippage" principle.
- Relies on strategy `freeFunds` returning truthful `amountFreed` and `loss`.
- Assumes this phase does not implement retained-asset liquidation ordering.
- Matches the Phase 6 requirement; later Growth liquidation logic remains out of scope.

#### `redeem(uint256 shares, address receiver, address owner)`

- Exists as the standard ERC-4626 share-targeted redemption entry point.
- Implements ERC-4626 withdrawals with the governance default max-loss bound.
- Relies on `previewRedeem`, share allowance/burn behavior, and `_ensureLiquidity`.
- Assumes default loss tolerance is acceptable for standard integrations.
- Matches ERC-4626; intentionally adds default max-loss behavior around the standard method.

#### `redeem(uint256 shares, address receiver, address owner, uint16 maxLossBps)`

- Exists to let users redeem shares with an explicit loss bound.
- Implements maxLossBps support for redeem flows.
- Relies on preview math and realized strategy-loss accounting.
- Assumes no in-kind redemption in this phase.
- Matches the Phase 6 requirement.

#### `previewInKindRedeem(uint256)`

- Exists as a reserved extension point for later explicit in-kind redemption.
- Implements the Phase 6 requirement to reserve hooks but not implement in-kind redemption.
- Relies on returning empty arrays rather than pretending proportional stock redemption exists.
- Assumes Phase 12 will define real previews and limits.
- Matches the architecture intentionally as a stub.

#### `redeemInKind(uint256 shares, address receiver, address owner)`

- Exists as the future explicit non-ERC-4626 in-kind redemption entry point.
- Implements the reserved extension hook and makes non-implementation explicit by reverting.
- Relies on callers not treating this as live functionality.
- Assumes later Growth phases will replace or extend this behavior.
- Matches the architecture requirement not to implement in-kind redemption in Phase 6.

#### `setStrategy(address newStrategy)`

- Exists to install the one V1 strategy.
- Implements single-strategy architecture and strategy/vault asset compatibility.
- Relies on AccessManager restrictions and strategy `vault()` / `asset()` correctness.
- Assumes live migration with nonzero debt is not handled in this phase.
- Matches the architecture.

#### `setDepositCap(uint256 newCap)`

- Exists to let governance set deposit limits.
- Implements deposit cap governance configuration.
- Relies on AccessManager authorization.
- Assumes governance selects safe caps for launch/eligibility state.
- Matches the architecture.

#### `setIdleBufferBps(uint16 newBufferBps)`

- Exists to configure idle liquidity.
- Implements idle buffer sizing for withdrawal liquidity.
- Relies on BPS validation against `10_000`.
- Assumes governance balances liquidity availability against capital deployment.
- Matches the architecture.

#### `setDefaultMaxLossBps(uint16 newMaxLossBps)`

- Exists to configure default withdrawal loss tolerance.
- Implements max-loss support for standard ERC-4626 functions.
- Relies on BPS validation.
- Assumes explicit overloads are used when users need stricter control.
- Matches the requirement conceptually; intentionally preserves standard ERC-4626 method signatures.

#### `setProfitMaxUnlockTime(uint256 newDuration)`

- Exists to configure profit smoothing duration.
- Implements profit unlocking policy.
- Relies on `_syncLockedProfit` before changing the duration.
- Assumes governance can set zero to unlock immediately if policy requires.
- Matches the architecture.

#### `setEligibilityThreshold(uint256 newThreshold)`

- Exists to configure eligibility threshold.
- Implements configurable INDEX eligibility threshold.
- Relies on governance and external verification of Index Finance rules.
- Assumes Phase 6 does not hardcode the exact threshold.
- Matches the architecture.

#### `setMinPostWithdrawAssets(uint256 newMinimum)`

- Exists to configure the post-withdraw eligibility hook.
- Implements minimum post-withdraw qualifying balance behavior.
- Relies on `totalAssets()` as the qualifying balance proxy.
- Assumes exact Index Finance holder semantics are still external to later phases.
- Matches the architecture as a hook, not a final integration.

#### `pause()`

- Exists to stop deposits and deployments without permanently disabling withdrawals.
- Implements reversible pause.
- Relies on AccessManager authorization.
- Assumes withdrawal attempts should remain available whenever technically possible.
- Matches the architecture.

#### `unpause()`

- Exists to return a paused vault to active operation.
- Implements reversible pause.
- Relies on shutdown being irreversible.
- Assumes unpause authorization is configured more strongly through AccessManager selectors.
- Matches the architecture.

#### `shutdown()`

- Exists to permanently stop active operation.
- Implements emergency shutdown.
- Relies on lifecycle checks preventing return from shutdown.
- Assumes withdrawals may still run when liquidity exists or can be freed.
- Matches the architecture.

#### `deployIdle()`

- Exists to deploy excess idle assets while preserving the configured buffer.
- Implements idle buffer and single-strategy debt allocation.
- Relies on active lifecycle, configured strategy, and safe transfer to strategy before `deployFunds`.
- Assumes strategy `deployFunds` accounts for received assets and does not reenter.
- Matches the architecture.

#### `deploy(uint256 assets)`

- Exists to let authorized operators deploy an explicit amount.
- Implements controlled strategy debt allocation.
- Relies on AccessManager, active lifecycle, and configured strategy compatibility.
- Assumes operators choose an amount consistent with buffer policy when not using `deployIdle`.
- Matches the architecture.

#### `report(HarvestReport calldata report_)`

- Exists for the strategy to report realized gain, loss, and debt payment.
- Implements strategy reporting, debt repayment, loss accounting, and profit locking.
- Relies on `msg.sender` being the configured strategy and on `debtReduction <= strategyDebt`.
- Assumes Phase 10 strategies honestly calculate reports; malicious strategies are mitigated by governance selection and audits.
- Matches the architecture, adapted to the completed `HarvestReport` struct from Phase 3.

#### `isEligible()`

- Exists to expose vault eligibility status.
- Implements eligibility status view.
- Relies on `totalAssets()` as the current qualifying balance proxy.
- Assumes exact on-chain Index Finance eligibility semantics will be wired in later phases.
- Matches the Phase 6 hook requirement.

### Inherited RobinVault ABI Surface

The following functions are inherited from `ERC4626Paris`, `ERC20`, and `AccessManaged`:

- ERC-20: `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`, `transfer`, `allowance`, `approve`, `transferFrom`.
- ERC-4626: `asset`, `convertToShares`, `convertToAssets`, `maxWithdraw`, `maxRedeem`, `previewDeposit`, `previewMint`, `previewWithdraw`, `previewRedeem`.
- Access control: `authority`, `setAuthority`, `isConsumingScheduledOp`.

These exist for standards compatibility and AccessManager integration. They rely on OpenZeppelin ERC-20 semantics, the local Paris-compatible ERC-4626 virtual share formula, and AccessManager authorization. They match the architecture's ERC-4626 and AccessManager requirements, with one intentional implementation difference: `ERC4626Paris` mirrors the relevant OpenZeppelin ERC-4626 behavior because the installed OpenZeppelin ERC-4626 imports Cancun-only memory helpers while the repository targets `paris`.

## OracleRegistry

`OracleRegistry` implements Phase 7: feed registration, heartbeat, stale checks, positive price validation, decimal normalization, paused feeds, `uiMultiplier`, governance configuration, events, and custom errors.

### Public Getters

#### `NORMALIZED_PRICE_DECIMALS()`

- Exists to document the common precision used by validated prices.
- Implements decimal normalization discoverability.
- Relies on all returned prices being normalized to 1e18.
- Assumes downstream components treat oracle prices as 1e18 fixed point.
- Matches the architecture.

### Direct Functions

#### `getOracleConfig(address asset)`

- Exists to expose an asset's oracle policy.
- Implements feed registration visibility and governance-auditable configuration.
- Relies on `_configs` being updated only through restricted functions.
- Assumes unset assets return an empty config and validated reads handle missing feeds by reverting.
- Matches the architecture.

#### `getValidatedPrice(address asset)`

- Exists to return a checked normalized price.
- Implements positive-price validation, current-round validation, heartbeat/stale checks, paused-feed rejection, decimal normalization, and `uiMultiplier`.
- Relies on the feed implementing the provisional Chainlink-shaped `IPriceFeed`.
- Assumes `answeredInRound >= roundId` means the observation is complete and that configured decimals match feed decimals.
- Matches the architecture.

#### `setOracleConfig(address asset, OracleConfig calldata config)`

- Exists to create or replace oracle policy.
- Implements governance configuration for feeds, heartbeat, deviation parameter storage, pause state, decimals, and multiplier.
- Relies on AccessManager restrictions and validation of nonzero addresses, heartbeat, multiplier, decimals, and BPS.
- Assumes provider/feed choices are configurable until final integration.
- Matches the architecture.

#### `setOraclePaused(address asset, bool paused)`

- Exists to pause or unpause reads without deleting configuration.
- Implements paused feed behavior and emergency controls.
- Relies on the asset already having a configured feed.
- Assumes governance/security roles are configured at AccessManager level.
- Matches the architecture.

#### `setUiMultiplier(address asset, uint256 newMultiplier)`

- Exists to update corporate-action/display multiplier independently.
- Implements `uiMultiplier` support.
- Relies on nonzero multiplier and existing config.
- Assumes multiplier precision is 1e18.
- Matches the architecture.

## RewardRegistry

`RewardRegistry` implements Phase 8: allowlist, categories, disposition, ignore/sell/retain policy data, retainability, minimum harvest, exposure caps, approved adapters, and governance updates.

### Direct Functions

#### `getRewardTokenConfig(address token)`

- Exists to expose complete reward-token policy.
- Implements allowlist/config visibility.
- Relies on `_configs` being changed only through restricted functions.
- Assumes strategies consume the full config rather than inferring behavior from balances.
- Matches the architecture.

#### `isRewardTokenEnabled(address token)`

- Exists as a cheap allowlist check.
- Implements supported/disabled status.
- Relies on config updates preserving the `enabled` flag.
- Assumes disabled tokens may retain historical config for auditability.
- Matches the architecture.

#### `isAdapterApproved(address token, address adapter)`

- Exists to expose per-token adapter approval.
- Implements approved adapters per reward token.
- Relies on governance-controlled adapter approvals.
- Assumes router-level adapter approval is checked separately by `ExecutionRouter`.
- Matches the architecture.

#### `setRewardTokenConfig(address token, RewardTokenConfig calldata config)`

- Exists to create or replace reward-token policy.
- Implements allowlist, categories, disposition, min harvest, retainability, exposure caps, oracle assignment, and default adapter.
- Relies on BPS validation, retain disposition requiring oracle/retainability, and sell disposition requiring an already approved adapter.
- Assumes setting `config.adapter` also approving that adapter is acceptable once the adapter was approved beforehand.
- Matches the architecture.

#### `disableRewardToken(address token)`

- Exists to disable a token while preserving historical configuration.
- Implements disabled status and emergency controls.
- Relies on token nonzero validation.
- Assumes disabling should not erase category, oracle, or caps needed for audit/recovery.
- Matches the architecture.

#### `setAdapterApproval(address token, address adapter, bool approved)`

- Exists to manage per-token approved execution adapters.
- Implements approved adapters.
- Relies on AccessManager restrictions and nonzero token/adapter.
- Assumes adapter approval here is policy-level and does not by itself allow router execution without router approval.
- Matches the architecture.

## ExecutionRouter

`ExecutionRouter` implements Phase 9: adapter registry, route registry, exact-input execution, slippage/min-output protection, deadline protection, oracle deviation checks, scoped approvals, balance-delta accounting, and reentrancy protection. It intentionally exposes no arbitrary calldata or arbitrary router target.

### Public Getters

#### `oracleRegistry()`

- Exists to expose the oracle registry used for deviation checks.
- Implements the oracle-versus-execution deviation dependency.
- Relies on the immutable registry being set correctly at construction.
- Assumes oracle registry replacement requires deploying a new router or later migration path.
- Matches the architecture.

### Direct Functions

#### `swapExactInput(SwapRequest calldata request, address recipient)`

- Exists to execute a constrained exact-input swap through an approved adapter and route.
- Implements exact-input execution, min-output, deadline, approved adapter/route checks, oracle deviation checks, scoped approvals, balance-delta accounting, and non-reentrancy.
- Relies on `IDexAdapter` not accepting arbitrary calldata, on token decimals being readable, and on `OracleRegistry` prices being valid when deviation checks are enabled.
- Assumes `maxOracleDeviationBps == 0` intentionally disables oracle deviation checks for a route.
- Matches the architecture.

#### `isAdapterApproved(address adapter)`

- Exists to expose adapter registry status.
- Implements adapter registry visibility.
- Relies on `_approvedAdapters` updates through restricted functions.
- Assumes strategies and off-chain operators use this for preflight checks.
- Matches the architecture.

#### `isRouteApproved(address adapter, address tokenIn, address tokenOut)`

- Exists to expose route enablement.
- Implements route registry visibility.
- Relies on deterministic `getRouteId`.
- Assumes route policy is keyed by adapter/token pair rather than arbitrary calldata.
- Matches the architecture; "route identifiers" are implemented as deterministic route IDs.

#### `getRouteConfig(address adapter, address tokenIn, address tokenOut)`

- Exists to expose route policy, including oracle deviation bound.
- Implements route registry and deviation-configuration visibility.
- Relies on deterministic `getRouteId`.
- Assumes route config is sufficient for Phase 9 without multi-hop route details.
- Matches the architecture at the adapter/pair level; multi-hop venue details remain inside approved adapters.

#### `setAdapterApproval(address adapter, bool approved)`

- Exists to manage which adapters may receive swaps.
- Implements adapter registry governance.
- Relies on AccessManager restrictions and nonzero adapter validation.
- Assumes approved adapters are audited constrained adapters, not arbitrary DEX routers.
- Matches the architecture.

#### `setRoute(address adapter, address tokenIn, address tokenOut, bool enabled, uint16 maxOracleDeviationBps)`

- Exists to manage approved token-pair routes for an adapter.
- Implements route registry, pair allowlisting, and route-level deviation policy.
- Relies on BPS validation and nonzero addresses.
- Assumes route keys are exact adapter/tokenIn/tokenOut triples.
- Matches the architecture.

#### `getRouteId(address adapter, address tokenIn, address tokenOut)`

- Exists to provide deterministic route identifiers.
- Implements route identifiers without raw calldata.
- Relies on collision resistance of `keccak256(abi.encode(...))`.
- Assumes route IDs need not include chain ID because contracts are chain-local.
- Matches the architecture.

## StrategyBase

`StrategyBase` implements Phase 10: abstract strategy framework with vault-only capital operations, harvest/tend, shutdown, emergency withdrawal, lifecycle, per-token reward isolation, debt repayment, NAV reporting, keeper integration, and exposure plumbing. It deliberately avoids Index Finance, Growth, LP, portfolio, retention engine, and stock policy logic.

### Public Getters

#### `vault()`

- Exists to expose the only vault allowed to allocate or withdraw capital.
- Implements the one-vault/one-strategy boundary.
- Relies on constructor immutability.
- Assumes a strategy is not reused across vaults.
- Matches the architecture.

#### `lifecycleState()`

- Exists to expose Active/Paused/Shutdown status.
- Implements strategy lifecycle visibility.
- Relies on shutdown irreversibility.
- Assumes keepers and vault managers check state before operations.
- Matches the architecture.

#### `lastReportedAssets()`

- Exists to track the previous NAV baseline for gain/loss reporting.
- Implements NAV reporting and harvest accounting.
- Relies on updates after deployment, free-funds, harvest, tend, and emergency paths.
- Assumes concrete strategies provide accurate `_deployedAssets` and `_rewardAssets`.
- Matches the architecture.

#### `isRewardTokenTracked(address token)`

- Exists to expose the tracked reward-token set membership.
- Implements per-token reward processing.
- Relies on restricted add/remove functions.
- Assumes concrete strategies only process tokens intentionally tracked.
- Matches the architecture.

#### `isRewardTokenIsolated(address token)`

- Exists to expose whether a reward token is quarantined after failure.
- Implements per-token reward isolation.
- Relies on harvest catching failures from `processRewardToken`.
- Assumes governance can later clear isolation after remediation.
- Matches the architecture.

#### `tokenExposureBps(address token)`

- Exists to expose exposure plumbing for later strategies.
- Implements exposure-control plumbing.
- Relies on concrete strategies setting exposure through `_setTokenExposure`.
- Assumes Phase 10 does not enforce final Growth caps directly.
- Matches the architecture as plumbing only.

### Direct Functions

#### `asset()`

- Exists to expose the strategy accounting asset.
- Implements the `IRobinStrategy` boundary.
- Relies on constructor immutability.
- Assumes accounting is denominated in the vault asset.
- Matches the architecture.

#### `totalAssets()`

- Exists to expose strategy NAV.
- Implements NAV reporting by combining idle assets, deployed assets, and reward NAV hooks.
- Relies on concrete strategy hooks being conservative and deterministic.
- Assumes Phase 10 does not value Growth retained stocks itself.
- Matches the architecture as an abstract base.

#### `rewardTokens()`

- Exists to expose the tracked reward-token list.
- Implements per-token reward processing visibility.
- Relies on restricted list mutation.
- Assumes the list remains small enough for harvest iteration in derived strategies.
- Matches the architecture.

#### `deployFunds(uint256 amount)`

- Exists for the vault to deploy capital into the strategy.
- Implements vault-only capital ops and deployFunds support.
- Relies on `onlyVault`, active lifecycle, nonzero amount, non-reentrancy, and concrete `_deployFunds`.
- Assumes the vault transfers assets before calling this function.
- Matches the completed Phase 3 interface; the architecture concept matches.

#### `freeFunds(uint256 amount)`

- Exists for the vault to request assets back for withdrawals.
- Implements freeFunds support and debt repayment plumbing.
- Relies on `onlyVault`, nonzero amount, non-reentrancy, and concrete `_freeFunds` returning realized loss.
- Assumes max-loss enforcement is performed by the vault because the completed Phase 3 interface lacks `maxLossBps`.
- Intentionally differs from the architecture sketch that included `maxLossBps` in the strategy signature; preserves the completed repo interface.

#### `harvest()`

- Exists for keepers/governance-authorized callers to process rewards and report accounting.
- Implements keeper integration, per-token isolation, NAV reporting, debt repayment, and harvest lifecycle.
- Relies on AccessManager restrictions, active lifecycle, non-reentrancy, concrete hooks, and the vault accepting reports only from this strategy.
- Assumes no arbitrary execution data in Phase 10 because completed interfaces expose parameterless `harvest`.
- Intentionally differs from the architecture sketch that showed `harvest(bytes executionData)`; preserves Phase 3 interface and avoids arbitrary calldata.

#### `processRewardToken(address token)`

- Exists as an external self-call boundary so each reward token can fail independently.
- Implements per-token reward isolation.
- Relies on `msg.sender == address(this)` so users cannot invoke token processing directly.
- Assumes concrete `_processRewardToken` is deterministic and constrained by registries/router in later strategies.
- Matches the architecture's per-token isolation requirement.

#### `tend()`

- Exists for keeper maintenance that does not realize a harvest report.
- Implements tend support and keeper integration.
- Relies on AccessManager restrictions, active lifecycle, and concrete `_tend`.
- Assumes no arbitrary execution data because the completed Phase 3 interface is parameterless.
- Intentionally differs from the architecture sketch that showed `tend(bytes executionData)`.

#### `pause()`

- Exists to stop active keeper/capital operations without full shutdown.
- Implements lifecycle `Paused`.
- Relies on AccessManager restrictions.
- Assumes unpause authority is handled by AccessManager role/selector configuration.
- Matches the architecture.

#### `unpause()`

- Exists to resume operation from pause.
- Implements lifecycle return to `Active`.
- Relies on shutdown irreversibility.
- Assumes governance has evaluated strategy safety before unpausing.
- Matches the architecture.

#### `shutdown()`

- Exists to permanently stop new strategy operation.
- Implements shutdown lifecycle.
- Relies on concrete `_shutdownStrategy` for protocol-specific unwinding/panic behavior.
- Assumes emergency capital return may require `emergencyWithdraw`.
- Matches the architecture.

#### `emergencyWithdraw()`

- Exists to return available capital to the vault in emergencies and shut down.
- Implements emergencyWithdraw, debt repayment, and shutdown.
- Relies on AccessManager restrictions, non-reentrancy, concrete `_emergencyWithdraw`, and vault `report`.
- Assumes concrete strategies can conservatively determine realized loss.
- Matches the architecture.

#### `addRewardToken(address token)`

- Exists to add a token to per-token processing.
- Implements per-token reward isolation setup.
- Relies on AccessManager restrictions and nonzero token validation.
- Assumes higher-level reward policy validation occurs in `RewardRegistry` or derived strategy configuration.
- Matches Phase 10 plumbing.

#### `removeRewardToken(address token)`

- Exists to remove a token from processing.
- Implements reward-token list governance.
- Relies on restricted access and swap-and-pop list mutation.
- Assumes removing a token does not by itself transfer or liquidate balances.
- Matches Phase 10 plumbing.

#### `setRewardTokenIsolated(address token, bool isolated)`

- Exists to manually quarantine or restore a token.
- Implements per-token reward isolation recovery.
- Relies on AccessManager restrictions.
- Assumes governance/keepers diagnose a failed token before clearing isolation.
- Matches the architecture.

## Summary of Intentional Differences

1. `RobinVault` uses `ERC4626Paris` instead of importing the installed OpenZeppelin `ERC4626` directly. The reason is toolchain compatibility: this repository targets EVM `paris`, while the installed OpenZeppelin implementation currently imports memory helpers that compile to Cancun-only `mcopy`. The local base keeps the ERC-4626 surface and OpenZeppelin virtual asset/share formula.
2. `StrategyBase.freeFunds` does not accept `maxLossBps`. The completed Phase 3 `IRobinStrategy` interface exposes `freeFunds(uint256)`, so max-loss enforcement is performed by `RobinVault`.
3. `StrategyBase.harvest` and `StrategyBase.tend` are parameterless. The completed Phase 3 interface is parameterless, and this also reinforces the architecture rule that keepers trigger policy rather than passing arbitrary execution data.
4. `RobinVault` keeps standard ERC-4626 `withdraw` and `redeem` signatures and adds overloads with `maxLossBps`. This preserves ERC-4626 integration while supporting explicit user loss bounds.
5. `previewInKindRedeem` and `redeemInKind` are stubs by design. Phase 6 only reserves the extension point; real in-kind redemption belongs to later Growth/selective-withdrawal phases.

