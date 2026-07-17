// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RewardTokenConfig} from "../types/ProtocolTypes.sol";

/// @notice Canonical read and administration boundary for approved reward tokens.
interface IRewardRegistry {
    /// @notice Returns the complete configuration for a reward token.
    /// @param token Reward-token address.
    function getRewardTokenConfig(address token) external view returns (RewardTokenConfig memory config);

    /// @notice Returns whether a reward token is enabled for processing.
    /// @param token Reward-token address.
    function isRewardTokenEnabled(address token) external view returns (bool enabled);

    /// @notice Creates or replaces a reward-token configuration.
    /// @param token Reward-token address.
    /// @param config Validated configuration to persist.
    function setRewardTokenConfig(address token, RewardTokenConfig calldata config) external;

    /// @notice Disables a reward token without deleting its configuration history.
    /// @param token Reward-token address.
    function disableRewardToken(address token) external;
}
