// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {LifecycleState, RewardCategory} from "../types/ProtocolTypes.sol";

/// @notice Canonical event surface inherited by later protocol implementations.
/// @dev This abstract contract has no executable functions or state.
abstract contract Events {
    /// @notice Emitted when a component changes lifecycle state.
    /// @param previousState State before the transition.
    /// @param newState State after the transition.
    event LifecycleStateChanged(LifecycleState indexed previousState, LifecycleState indexed newState);

    /// @notice Emitted when the configurable INDEX eligibility threshold changes.
    /// @param previousThreshold Threshold before the update.
    /// @param newThreshold Threshold after the update.
    event EligibilityThresholdUpdated(uint256 previousThreshold, uint256 newThreshold);

    /// @notice Emitted when eligibility changes.
    /// @param account Vault or strategy address evaluated for eligibility.
    /// @param eligible Whether the address meets current policy.
    /// @param indexBalance INDEX balance used for the evaluation.
    /// @param threshold Configured threshold used for the evaluation.
    event EligibilityStatusChanged(address indexed account, bool eligible, uint256 indexBalance, uint256 threshold);

    /// @notice Emitted after strategy accounting is reported.
    /// @param strategy Reporting strategy.
    /// @param gain Realized gain denominated in vault assets.
    /// @param loss Realized loss denominated in vault assets.
    /// @param debtPayment Capital returned to the vault.
    event StrategyReported(address indexed strategy, uint256 gain, uint256 loss, uint256 debtPayment);

    /// @notice Emitted when a reward-token configuration changes.
    /// @param token Reward token updated.
    /// @param enabled Whether processing is enabled.
    /// @param category Portfolio category assigned to the token.
    /// @param retainable Whether strategies may retain the token.
    /// @param maxExposureBps Maximum token exposure in basis points.
    event RewardTokenConfigured(
        address indexed token, bool enabled, RewardCategory indexed category, bool retainable, uint16 maxExposureBps
    );

    /// @notice Emitted when a reward token is isolated after an independent processing failure.
    /// @param token Reward token whose processing failed.
    /// @param reasonData Encoded revert data retained for diagnosis.
    event RewardProcessingFailed(address indexed token, bytes reasonData);

    /// @notice Emitted when an oracle configuration changes.
    /// @param asset Asset priced by the oracle.
    /// @param feed Configured feed address.
    /// @param heartbeat Maximum permitted observation age.
    /// @param paused Whether reads are disabled.
    event OracleConfigured(address indexed asset, address indexed feed, uint48 heartbeat, bool paused);

    /// @notice Emitted when an execution adapter's approval changes.
    /// @param adapter Adapter whose status changed.
    /// @param approved Whether the adapter is approved.
    event AdapterApprovalUpdated(address indexed adapter, bool approved);

    /// @notice Emitted after an approved swap completes.
    /// @param adapter Adapter used for execution.
    /// @param tokenIn Token sold.
    /// @param tokenOut Token bought.
    /// @param amountIn Exact input amount.
    /// @param amountOut Actual output amount.
    event SwapExecuted(
        address indexed adapter, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    /// @notice Emitted when an unhealthy or stale oracle asset is skipped during state-changing operations.
    /// @param token Token whose price feed was unhealthy.
    /// @param oracle Feed address or oracle identifier.
    event UnpriceableAssetSkipped(address indexed token, address indexed oracle);

    /// @notice Emitted when a zero-balance retained token is pruned from the strategy portfolio.
    /// @param token Retained token pruned.
    event RetainedTokenPruned(address indexed token);
}
