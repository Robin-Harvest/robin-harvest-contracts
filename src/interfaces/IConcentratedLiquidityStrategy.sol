// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {StrategyMode} from "../types/ClStrategyTypes.sol";
import {IRobinStrategy} from "./IRobinStrategy.sol";
import {IRebalancePolicy} from "./IRebalancePolicy.sol";

/// @title Robin Harvest Concentrated Liquidity Strategy Interface
/// @notice Exposes immutable pool wiring, governance parameters, lifecycle controls, and simulation helpers.
interface IConcentratedLiquidityStrategy is IRobinStrategy {
    /// @notice TWAP observation window in seconds used for manipulation-resistant price checks.
    /// @dev V1 maintains an internal observation ring updated on every state-changing pool interaction.
    ///      Default: 30 minutes (1800 seconds).
    function twapWindow() external view returns (uint32 windowSeconds);

    /// @notice Returns the active rebalance policy.
    function policy() external view returns (IRebalancePolicy policy_);

    /// @notice Returns the current strategy operational mode.
    function mode() external view returns (StrategyMode currentMode);

    /// @notice Maximum swap slippage in basis points for rebalancing operations.
    function maxSlippageBps() external view returns (uint16 bps);

    /// @notice Maximum realized loss in basis points during withdrawals.
    function maxLossBps() external view returns (uint16 bps);

    /// @notice Maximum relative sqrt-price deviation between spot, TWAP, and oracle values during deposits and rebalances.
    function oracleSqrtPriceDeviationBps() external view returns (uint16 bps);

    /// @notice Maximum relative sqrt-price deviation permitted between spot and TWAP during withdrawals.
    function maxWithdrawSqrtPriceDeviationBps() external view returns (uint16 bps);

    /// @notice Whether harvested fees are automatically redeployed into liquidity.
    function autoCompound() external view returns (bool enabled);

    /// @notice Returns the number of actively tracked position NFTs.
    function activePositionCount() external view returns (uint256 count);

    /// @notice Reposition liquidity according to policy when conditions are met.
    function rebalance() external;

    /// @notice Enter withdraw-only mode; deposits and rebalances are blocked.
    function enterWithdrawOnly() external;

    /// @notice Enter harvest-only mode; only fee collection and compounding remain enabled.
    function enterHarvestOnly() external;

    /// @notice Close every managed position after pausing; requires `mode == Paused`.
    function emergencyClosePositions() external;

    /// @notice Return idle assets to the immutable parent vault; requires paused mode and no open positions.
    function emergencyReturnAssetsToVault() external;
}
