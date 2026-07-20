# Changelog

All notable changes to the Robin Harvest protocol will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] (v1.2 Pre-Audit)

### Added
- **Multi-hop Routing:** Added `setCustomPath` to `UniswapV2DexAdapter` allowing `AccessManaged` governance to configure safe multi-hop swap paths to mitigate low liquidity on direct pairs.
- **Retained Token Skipper:** `GrowthStrategy._freeFunds` now gracefully skips tokens without valid oracle feeds or adapter configs instead of reverting, preventing INDEX-only withdrawals from being DoS'd by a single failing asset.
- **In-Kind Slippage Boundary:** Added `maxLossBps` slippage protection to `Vault.redeemInKind` and `GrowthStrategy.redeemInKind`.

### Changed
- **Cap-and-Forfeit Fees:** Re-architected `RobinVault._assessReportFees` to rigidly cap management and performance fees to the current `lockedProfit`. Any fee exceeding this cap is permanently forfeited, preventing fee debt accumulation during market downturns.
- **In-Kind Execution Flow:** Rerouted `GrowthStrategy.redeemInKind` INDEX fulfillment to transfer directly to `msg.sender` (Vault) instead of the end-user. The Vault then discounts the remaining `lockedProfit` according to the withdrawal slippage loss and consolidates the transfer to the user, strictly preserving accounting integrity.
- **DEX Adapter Flow:** Updated `UniswapV2DexAdapter` to explicitly pull required tokens via `safeTransferFrom`, apply `forceApprove`, and completely reset approval to `0` post-swap to safeguard against unspent allowances.

### Fixed
- **Isolation Flag Drift:** Fixed `StrategyBase.removeRewardToken` to guarantee the `isRewardTokenIsolated` flag is cleared to `false` when a token is removed, ensuring it doesn't remain erroneously isolated upon re-addition.
- **Sandwich Vector in Redemptions:** Tightened `redeemInKind` value assertions and loss tolerances to protect against oracle latency arbitrage and flash loan sandwiching.
