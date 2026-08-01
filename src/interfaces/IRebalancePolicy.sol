// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Concentrated Liquidity Rebalance Policy
/// @notice External policy contract that decides when and where to reposition liquidity.
/// @dev Tick validation is intentionally excluded; the strategy owns all range validation via `_validateTicks()`.
interface IRebalancePolicy {
    /// @notice Returns whether an active position should be repositioned given current pool state.
    /// @param tokenId Position NFT identifier under evaluation.
    /// @param currentTick Current pool tick from slot0.
    /// @param lower Current position lower tick.
    /// @param upper Current position upper tick.
    /// @param liquidity Current position liquidity.
    /// @return rebalance True when the keeper should invoke `rebalance()`.
    function shouldRebalance(uint256 tokenId, int24 currentTick, int24 lower, int24 upper, uint128 liquidity)
        external
        view
        returns (bool rebalance);

    /// @notice Returns the target tick range for a new or repositioned liquidity band.
    /// @dev The strategy validates spacing, bounds, and width before acting on this output.
    /// @param currentTick Current pool tick from slot0.
    /// @param tickSpacing Pool tick spacing from the immutable PoolKey.
    /// @return lower Target lower tick (inclusive).
    /// @return upper Target upper tick (exclusive in Uniswap convention).
    function targetRange(int24 currentTick, int24 tickSpacing) external view returns (int24 lower, int24 upper);

    /// @notice Minimum permitted tick width (upper - lower) in tick units.
    function minTickWidth() external view returns (int24 width);

    /// @notice Maximum permitted tick width (upper - lower) in tick units.
    function maxTickWidth() external view returns (int24 width);
}
