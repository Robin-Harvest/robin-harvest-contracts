// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Operational mode governing concentrated-liquidity strategy behavior.
enum StrategyMode {
    /// @notice Normal operation: deposits, rebalances, harvests, and withdrawals permitted.
    Active,
    /// @notice Fee collection and compounding only; no new deployment or rebalancing.
    HarvestOnly,
    /// @notice Liquidity removal only; no deposits or rebalances.
    WithdrawOnly,
    /// @notice All capital-moving operations halted except emergency unwind paths.
    Paused
}

/// @notice On-chain accounting for a Uniswap v4 position NFT managed by the strategy.
struct ManagedPosition {
    /// @notice ERC-721 token identifier issued by the v4 PositionManager.
    uint256 tokenId;
    /// @notice Whether the position is actively counted toward deployed NAV.
    bool active;
    /// @notice Last known liquidity amount for the position.
    uint128 liquidity;
    /// @notice Lower tick bound of the position range.
    int24 lower;
    /// @notice Upper tick bound of the position range.
    int24 upper;
    /// @notice Block timestamp when the position was opened.
    uint48 openedAt;
    /// @notice Block timestamp of the last fee compound for this position.
    uint48 lastCompound;
}

/// @notice Snapshot used for internal TWAP computation (V1 hookless pools).
struct PriceObservation {
    uint160 sqrtPriceX96;
    uint48 timestamp;
}

/// @notice Result of a rebalance simulation or execution.
struct RebalanceResult {
    uint256 oldTokenId;
    uint256 newTokenId;
    int24 oldLower;
    int24 oldUpper;
    int24 newLower;
    int24 newUpper;
    uint128 liquidity;
    uint256 amount0;
    uint256 amount1;
}

/// @notice Preview output for capital deployment into a new or existing range.
struct DeployPreview {
    int24 lower;
    int24 upper;
    uint128 liquidity;
    uint256 amount0;
    uint256 amount1;
    uint256 assetRequired;
}

/// @notice Preview output for withdrawing capital from managed positions.
struct WithdrawPreview {
    uint256 assetOut;
    uint256 loss;
    uint256 amount0;
    uint256 amount1;
}
