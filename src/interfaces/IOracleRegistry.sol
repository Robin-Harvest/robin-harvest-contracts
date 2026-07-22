// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OracleConfig} from "../types/ProtocolTypes.sol";

/// @notice Canonical boundary for oracle configuration and validated normalized prices.
interface IOracleRegistry {
    /// @notice Returns the oracle policy configured for an asset.
    /// @param asset Asset whose price is requested.
    function getOracleConfig(address asset) external view returns (OracleConfig memory config);

    /// @notice Returns a validated normalized price and its observation timestamp.
    /// @dev Implementations must reject missing, stale, paused, non-positive, or otherwise invalid observations.
    /// @param asset Asset whose price is requested.
    /// @return price Price normalized to the registry's documented common precision.
    /// @return updatedAt Timestamp of the accepted underlying observation.
    function getValidatedPrice(address asset) external view returns (uint256 price, uint256 updatedAt);

    /// @notice Returns a validated normalized price without reverting on stale or invalid feeds.
    /// @param asset Asset whose price is requested.
    /// @return healthy True if the oracle feed is active, non-stale, and valid.
    /// @return price Price normalized to 1e18 precision (0 if unhealthy).
    /// @return updatedAt Timestamp of observation (0 if unhealthy).
    function tryGetValidatedPrice(address asset)
        external
        view
        returns (bool healthy, uint256 price, uint256 updatedAt);

    /// @notice Returns whether an asset's oracle feed is healthy, active, and fresh.
    /// @param asset Asset to check.
    function isHealthy(address asset) external view returns (bool healthy);

    /// @notice Creates or replaces an asset's oracle policy.
    /// @param asset Asset whose policy is updated.
    /// @param config Validated oracle policy to persist.
    function setOracleConfig(address asset, OracleConfig calldata config) external;

    /// @notice Pauses or unpauses price reads for an asset.
    /// @param asset Asset whose price-read state changes.
    /// @param paused New pause state.
    function setOraclePaused(address asset, bool paused) external;
}
