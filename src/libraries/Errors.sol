// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Thrown when a required address is the zero address.
error ZeroAddress();

/// @notice Thrown when a required amount is zero.
error ZeroAmount();

/// @notice Thrown when a basis-point value exceeds the protocol denominator.
/// @param value Invalid basis-point value.
error InvalidBasisPoints(uint256 value);

/// @notice Thrown when a supplied range is internally inconsistent.
/// @param minimum Lower bound.
/// @param target Target value.
/// @param maximum Upper bound.
error InvalidRange(uint256 minimum, uint256 target, uint256 maximum);

/// @notice Thrown when an account is not authorized for an operation.
/// @param account Unauthorized account.
/// @param role Required role identifier.
error Unauthorized(address account, bytes32 role);

/// @notice Thrown when an operation is invalid for the current lifecycle state.
/// @param currentState Encoded current lifecycle state.
error InvalidLifecycleState(uint8 currentState);

/// @notice Thrown when a deadline has passed.
/// @param deadline Configured deadline.
/// @param currentTimestamp Current block timestamp.
error DeadlineExpired(uint256 deadline, uint256 currentTimestamp);

/// @notice Thrown when an execution output is below the caller-approved minimum.
/// @param amountOut Actual output.
/// @param minAmountOut Minimum approved output.
error InsufficientOutput(uint256 amountOut, uint256 minAmountOut);

/// @notice Thrown when realized loss exceeds the caller-approved bound.
/// @param lossBps Realized loss in basis points.
/// @param maxLossBps Maximum approved loss in basis points.
error LossExceedsMaximum(uint256 lossBps, uint256 maxLossBps);

/// @notice Thrown when an asset or route is not approved.
/// @param target Unapproved token, adapter, route, or other target.
error NotApproved(address target);

/// @notice Thrown when a required registry entry is disabled.
/// @param target Disabled feed, token, adapter, or route.
error Disabled(address target);

/// @notice Thrown when an oracle answer is invalid.
/// @param oracle Oracle that returned the invalid answer.
error InvalidOracleAnswer(address oracle);

/// @notice Thrown when an oracle observation is older than its heartbeat.
/// @param oracle Oracle whose answer is stale.
/// @param updatedAt Timestamp of the latest observation.
/// @param heartbeat Maximum permitted age.
error StaleOracle(address oracle, uint256 updatedAt, uint256 heartbeat);

/// @notice Thrown when an observed price deviation exceeds policy.
/// @param deviationBps Observed deviation in basis points.
/// @param maxDeviationBps Maximum permitted deviation in basis points.
error OracleDeviationExceeded(uint256 deviationBps, uint256 maxDeviationBps);

/// @notice Thrown when an exposure cap would be exceeded.
/// @param subject Token or encoded category identifier subject to the cap.
/// @param exposureBps Resulting exposure in basis points.
/// @param maxExposureBps Maximum permitted exposure in basis points.
error ExposureLimitExceeded(bytes32 subject, uint256 exposureBps, uint256 maxExposureBps);

/// @notice Thrown when reported accounting values are inconsistent.
error InvalidAccounting();

/// @notice Thrown when the configured INDEX eligibility threshold is not met.
/// @param balance Current eligible INDEX balance.
/// @param threshold Required INDEX balance.
error EligibilityThresholdNotMet(uint256 balance, uint256 threshold);

/// @notice Thrown when a cooldown has not elapsed.
/// @param availableAt Earliest permitted execution timestamp.
error CooldownActive(uint256 availableAt);
