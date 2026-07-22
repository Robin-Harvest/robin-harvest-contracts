// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRobinStrategy} from "./IRobinStrategy.sol";

/// @title Robin Harvest LP Strategy Interface
/// @notice Interface exposing LP pool addresses, gauge configuration, and governance parameters.
interface ILpStrategy is IRobinStrategy {
    /// @notice Returns the LP pair token address.
    function lpToken() external view returns (address pairToken);

    /// @notice Returns the token paired with INDEX in the LP pool.
    function pairedToken() external view returns (address token);

    /// @notice Returns the approved DEX router used for adding/removing liquidity.
    function dexRouter() external view returns (address router);

    /// @notice Returns the approved DEX adapter for swaps.
    function dexAdapter() external view returns (address adapter);

    /// @notice Returns the LP gauge / staking contract address (optional, zero if unstaked).
    function gauge() external view returns (address gaugeAddress);

    /// @notice Returns maximum allowed slippage in basis points for liquidity operations.
    function maxSlippageBps() external view returns (uint16 bps);

    /// @notice Returns whether compounding yields during harvest is currently paused.
    function compoundingPaused() external view returns (bool paused);

    /// @notice Configures the LP staking gauge.
    function setGauge(address newGauge) external;

    /// @notice Updates maximum allowed slippage for liquidity provisioning and removal.
    function setMaxSlippage(uint16 newSlippageBps) external;

    /// @notice Pauses yield auto-compounding during harvest routines.
    function pauseCompounding() external;

    /// @notice Resumes yield auto-compounding during harvest routines.
    function resumeCompounding() external;
}
