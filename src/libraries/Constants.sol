// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Chain-independent constants shared throughout Robin Harvest.
library Constants {
    /// @notice Denominator used for all basis-point calculations.
    uint256 internal constant BPS = 10_000;

    /// @notice Maximum representable basis-point value.
    uint16 internal constant MAX_BPS = 10_000;

    /// @notice Number of seconds used for annualized accounting.
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
}
