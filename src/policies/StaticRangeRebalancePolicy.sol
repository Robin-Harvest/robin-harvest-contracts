// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {InvalidRange, ZeroAddress} from "../libraries/Errors.sol";
import {IRebalancePolicy} from "../interfaces/IRebalancePolicy.sol";

/// @title Static Range Rebalance Policy
/// @notice Recenters a fixed-width band around the current pool tick and rebalances when price exits the band.
/// @dev Tick validation is performed exclusively by the strategy via `_validateTicks()`.
contract StaticRangeRebalancePolicy is IRebalancePolicy, AccessManaged {
    int24 public immutable halfWidth;
    int24 private immutable _minTickWidth;
    int24 private immutable _maxTickWidth;

    /// @param authority_ AccessManager authority for governance updates.
    /// @param halfWidth_ Half of the target band width in ticks; total width equals `2 * halfWidth`.
    /// @param minTickWidth_ Minimum width enforced by the strategy during validation.
    /// @param maxTickWidth_ Maximum width enforced by the strategy during validation.
    constructor(address authority_, int24 halfWidth_, int24 minTickWidth_, int24 maxTickWidth_)
        AccessManaged(authority_)
    {
        if (authority_ == address(0)) revert ZeroAddress();
        if (halfWidth_ <= 0 || minTickWidth_ <= 0 || maxTickWidth_ < minTickWidth_) {
            revert InvalidRange(
                uint256(int256(minTickWidth_)), uint256(int256(halfWidth_ * 2)), uint256(int256(maxTickWidth_))
            );
        }
        halfWidth = halfWidth_;
        _minTickWidth = minTickWidth_;
        _maxTickWidth = maxTickWidth_;
    }

    /// @inheritdoc IRebalancePolicy
    function shouldRebalance(uint256, int24 currentTick, int24 lower, int24 upper, uint128 liquidity)
        external
        pure
        override
        returns (bool rebalance)
    {
        if (liquidity == 0) return false;
        rebalance = currentTick < lower || currentTick >= upper;
    }

    /// @inheritdoc IRebalancePolicy
    function targetRange(int24 currentTick, int24 tickSpacing)
        external
        view
        override
        returns (int24 lower, int24 upper)
    {
        int24 aligned = _alignTick(currentTick, tickSpacing);
        lower = _alignTick(aligned - halfWidth, tickSpacing);
        upper = _alignTick(aligned + halfWidth, tickSpacing);
        if (lower <= TickMath.MIN_TICK) lower = TickMath.minUsableTick(tickSpacing);
        if (upper >= TickMath.MAX_TICK) upper = TickMath.maxUsableTick(tickSpacing);
        if (lower >= upper) {
            lower = _alignTick(currentTick - halfWidth, tickSpacing);
            upper = _alignTick(currentTick + halfWidth, tickSpacing);
        }
    }

    /// @inheritdoc IRebalancePolicy
    function minTickWidth() external view override returns (int24 width) {
        width = _minTickWidth;
    }

    /// @inheritdoc IRebalancePolicy
    function maxTickWidth() external view override returns (int24 width) {
        width = _maxTickWidth;
    }

    function _alignTick(int24 tick, int24 tickSpacing) private pure returns (int24 aligned) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed -= 1;
        aligned = compressed * tickSpacing;
    }
}
