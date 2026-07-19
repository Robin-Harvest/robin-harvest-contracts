// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Fee assessment boundary between RobinVault and RobinAccountant.
interface IRobinAccountant {
    /// @notice Recipient of accrued protocol fees.
    function feeRecipient() external view returns (address recipient);

    /// @notice Computes report-time fees against gross vault assets.
    function assessReportFees(uint256 totalAssetsGross, uint256 reportedGain)
        external
        returns (uint256 performanceFee, uint256 managementFee);
}
