// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {HarvestReport, LifecycleState} from "../types/ProtocolTypes.sol";

/// @notice Boundary between a Robin vault and one accounting strategy.
interface IRobinStrategy {
    /// @notice Returns the vault permitted to allocate capital to this strategy.
    function vault() external view returns (address vaultAddress);

    /// @notice Returns the ERC-20 asset used for strategy accounting.
    function asset() external view returns (address assetAddress);

    /// @notice Returns the strategy lifecycle state.
    function lifecycleState() external view returns (LifecycleState state);

    /// @notice Returns the total asset-denominated value controlled by the strategy.
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /// @notice Deploys idle strategy assets according to its constrained mandate.
    /// @param amount Maximum amount of the accounting asset to deploy.
    function deployFunds(uint256 amount) external;

    /// @notice Frees accounting assets for the vault.
    /// @param amount Amount requested by the vault.
    /// @return amountFreed Amount made available to the vault.
    /// @return loss Realized accounting loss incurred while freeing funds.
    function freeFunds(uint256 amount) external returns (uint256 amountFreed, uint256 loss);

    /// @notice Performs reward processing and returns the resulting accounting report.
    function harvest() external returns (HarvestReport memory report);

    /// @notice Performs permissioned maintenance that does not realize a harvest report.
    function tend() external;

    /// @notice Permanently stops new capital deployment.
    function shutdown() external;

    /// @notice Attempts to return all available capital to the vault during an emergency.
    /// @return amountFreed Accounting assets returned to the vault.
    /// @return loss Realized accounting loss incurred by the withdrawal.
    function emergencyWithdraw() external returns (uint256 amountFreed, uint256 loss);
}
