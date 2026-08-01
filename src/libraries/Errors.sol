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

/// @notice Thrown when a cooldown has not elapsed.
/// @param availableAt Earliest permitted execution timestamp.
error CooldownActive(uint256 availableAt);

/// @notice Thrown when a tick range fails strategy validation.
/// @param lower Provided lower tick.
/// @param upper Provided upper tick.
error InvalidTickRange(int24 lower, int24 upper);

/// @notice Thrown when a tick is outside Uniswap TickMath bounds.
/// @param tick Invalid tick value.
error TickOutOfBounds(int24 tick);

/// @notice Thrown when a tick is not aligned to pool tick spacing.
/// @param tick Misaligned tick.
/// @param tickSpacing Required tick spacing multiple.
error TickNotSpaced(int24 tick, int24 tickSpacing);

/// @notice Thrown when a tick range width violates policy bounds.
/// @param width Observed tick width.
/// @param minWidth Minimum permitted width.
/// @param maxWidth Maximum permitted width.
error TickWidthOutOfBounds(int24 width, int24 minWidth, int24 maxWidth);

/// @notice Thrown when an operation is invalid for the current strategy mode.
/// @param currentMode Encoded current strategy mode.
error InvalidStrategyMode(uint8 currentMode);

/// @notice Thrown when oracle, spot, and TWAP prices diverge beyond policy.
/// @param deviationBps Observed deviation in basis points.
/// @param maxDeviationBps Maximum permitted deviation in basis points.
error HardOracleFailure(uint256 deviationBps, uint256 maxDeviationBps);

/// @notice Thrown when a withdrawal fails TWAP safety checks.
/// @param deviationBps Observed deviation in basis points.
/// @param maxDeviationBps Maximum permitted deviation in basis points.
error WithdrawSafetyFailure(uint256 deviationBps, uint256 maxDeviationBps);

/// @notice Thrown when active positions remain while an operation requires none.
/// @param remaining Count of remaining active positions.
error ActivePositionsRemain(uint256 remaining);

/// @notice Thrown when governance attempts to mutate configuration while paused.
error GovernanceBlockedWhilePaused();

/// @notice Thrown when a managed position record is missing or inactive.
/// @param tokenId Position NFT identifier.
error UnknownPosition(uint256 tokenId);

/// @notice Thrown when a position token ID is already present in the strategy set.
/// @param tokenId Position NFT identifier.
error PositionAlreadyTracked(uint256 tokenId);

/// @notice Thrown when an amount cannot be represented by a V4 uint128 amount field.
error V4AmountOverflow();

/// @notice Thrown when adding a position would exceed the strategy's bounded position set.
/// @param maximum Maximum number of active positions supported by the strategy.
error ActivePositionLimitExceeded(uint256 maximum);
