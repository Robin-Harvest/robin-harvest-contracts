// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {InvalidTickRange, TickNotSpaced, TickOutOfBounds, TickWidthOutOfBounds} from "./Errors.sol";

/// @title Tick Validation Library
/// @notice Centralizes concentrated-liquidity tick range validation inside the strategy layer.
library TickValidationLib {
    /// @notice Validates a candidate tick range against Uniswap and policy constraints.
    /// @param lower Candidate lower tick (inclusive).
    /// @param upper Candidate upper tick (exclusive).
    /// @param tickSpacing Pool tick spacing from the immutable PoolKey.
    /// @param minWidth Minimum permitted width from the active rebalance policy.
    /// @param maxWidth Maximum permitted width from the active rebalance policy.
    function validateTicks(int24 lower, int24 upper, int24 tickSpacing, int24 minWidth, int24 maxWidth) internal pure {
        if (lower >= upper) revert InvalidTickRange(lower, upper);

        _checkTickBounds(lower);
        _checkTickBounds(upper);
        _checkTickSpacing(lower, tickSpacing);
        _checkTickSpacing(upper, tickSpacing);

        int24 width = upper - lower;
        if (width < minWidth || width > maxWidth) {
            revert TickWidthOutOfBounds(width, minWidth, maxWidth);
        }
    }

    function _checkTickBounds(int24 tick) private pure {
        if (tick < TickMath.MIN_TICK || tick > TickMath.MAX_TICK) revert TickOutOfBounds(tick);
    }

    function _checkTickSpacing(int24 tick, int24 tickSpacing) private pure {
        if (tickSpacing == 0) revert TickNotSpaced(tick, tickSpacing);
        if (tick % tickSpacing != 0) revert TickNotSpaced(tick, tickSpacing);
    }
}
