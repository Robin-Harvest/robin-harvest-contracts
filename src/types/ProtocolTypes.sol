// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Lifecycle state shared by vaults and strategies.
enum LifecycleState {
    Active,
    Paused,
    Shutdown
}

/// @notice Coarse reward categories used for portfolio policy and exposure accounting.
/// @dev Categories are intentionally generic until the supported tokenized-stock taxonomy is approved.
enum RewardCategory {
    Unclassified,
    Equity,
    Fund,
    Other
}

/// @notice Action to take when processing an enabled reward token.
enum RewardDisposition {
    Ignore,
    Sell,
    Retain
}

/// @notice A strategy's accounting report to its vault.
/// @param gain Value earned since the previous report, denominated in the vault asset.
/// @param loss Value lost since the previous report, denominated in the vault asset.
/// @param debtPayment Vault capital returned by the strategy during the report.
struct HarvestReport {
    uint256 gain;
    uint256 loss;
    uint256 debtPayment;
}

/// @notice Deterministic payout data for an optional in-kind redemption.
/// @param debtReduction Asset-denominated strategy debt removed by the redemption.
/// @param indexPaid INDEX transferred from the strategy position.
/// @param retainedTokens Retained stock tokens paid from the Growth portfolio in deterministic stored order.
/// @param retainedAmounts Raw token amounts paired with `retainedTokens`.
struct InKindRedemptionResult {
    uint256 debtReduction;
    uint256 indexPaid;
    address[] retainedTokens;
    uint256[] retainedAmounts;
}

/// @notice Configuration governing whether and how a reward token may be handled.
/// @param enabled Whether the reward token is approved for processing.
/// @param category Portfolio category assigned to the token.
/// @param disposition Processing action assigned to the token.
/// @param oracle Registered oracle identifier or feed address for the token.
/// @param minHarvestAmount Minimum raw token amount worth processing.
/// @param retainable Whether a strategy may hold the token after harvest.
/// @param adapter Approved execution adapter for this token.
/// @param maxExposureBps Maximum token exposure as a share of strategy NAV.
struct RewardTokenConfig {
    bool enabled;
    RewardCategory category;
    RewardDisposition disposition;
    address oracle;
    uint256 minHarvestAmount;
    bool retainable;
    address adapter;
    uint16 maxExposureBps;
}

/// @notice Oracle validation policy for one priced asset.
/// @param feed Registered price feed address.
/// @param heartbeat Maximum permitted age of a price observation, in seconds.
/// @param decimals Number of decimals in normalized feed answers.
/// @param maxDeviationBps Maximum permitted deviation from the configured reference check.
/// @param uiMultiplier Multiplier applied after decimal normalization, using 1e18 precision.
/// @param paused Whether reads from the feed are disabled.
struct OracleConfig {
    address feed;
    uint48 heartbeat;
    uint8 decimals;
    uint16 maxDeviationBps;
    uint256 uiMultiplier;
    bool paused;
}

/// @notice Target allocation policy for a reward category.
/// @param targetRetainBps Desired retained allocation.
/// @param minRetainBps Lower bound for retained allocation.
/// @param maxRetainBps Upper bound for retained allocation.
/// @param maxPortfolioBps Maximum category exposure as a share of strategy NAV.
/// @param rebalanceCooldown Minimum seconds between category rebalances.
struct CategoryPolicy {
    uint16 targetRetainBps;
    uint16 minRetainBps;
    uint16 maxRetainBps;
    uint16 maxPortfolioBps;
    uint48 rebalanceCooldown;
}

/// @notice Constraints fixed by policy before a swap is submitted.
/// @param adapter Approved execution adapter.
/// @param tokenIn Token sold.
/// @param tokenOut Token bought.
/// @param amountIn Exact input amount.
/// @param minAmountOut Minimum acceptable output amount.
/// @param deadline Latest valid execution timestamp.
struct SwapRequest {
    address adapter;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 minAmountOut;
    uint48 deadline;
}

/// @notice Configurable fee rates expressed in basis points.
/// @param performanceBps Fee charged only on realized profit.
/// @param managementBps Annualized management fee rate.
struct FeeConfig {
    uint16 performanceBps;
    uint16 managementBps;
}

/// @notice Conservative NAV haircut applied after min(oracle, executable quote) valuation.
/// @param navHaircutBps Additional haircut applied to retained-asset NAV.
struct NavHaircutConfig {
    uint16 navHaircutBps;
}

/// @notice Timelocked strategy replacement proposal.
/// @param newStrategy Candidate strategy awaiting activation.
/// @param executableAt Earliest timestamp when the migration may execute.
struct PendingStrategyMigration {
    address newStrategy;
    uint256 executableAt;
}
