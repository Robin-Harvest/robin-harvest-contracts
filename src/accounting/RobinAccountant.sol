// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../libraries/Constants.sol";
import {InvalidBasisPoints, ZeroAddress} from "../libraries/Errors.sol";
import {FeeConfig} from "../types/ProtocolTypes.sol";

/// @title Robin Harvest Protocol Accountant
/// @notice Computes performance fees against a high-water mark and annualized management fees.
/// @dev Fees are charged only on gains above the prior high-water mark. Losses must be recovered before performance
/// fees resume. The vault remains responsible for transferring fee proceeds to the configured recipient.
contract RobinAccountant is AccessManaged {
    using Math for uint256;

    /// @notice Vault asset used for fee denomination.
    IERC20 public immutable asset;

    /// @notice Vault authorized to request fee calculations after strategy reports.
    address public vault;

    /// @notice Recipient of accrued protocol fees.
    address public feeRecipient;

    /// @notice Current fee configuration.
    FeeConfig public feeConfig;

    /// @notice Highest gross vault assets observed before performance-fee assessment.
    uint256 public highWaterMark;

    /// @notice Timestamp of the last management-fee accrual boundary.
    uint256 public lastFeeAccrual;

    event FeeConfigUpdated(FeeConfig config);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
    event VaultUpdated(address indexed previousVault, address indexed newVault);
    event PerformanceFeeAssessed(uint256 feeAmount, uint256 newHighWaterMark);
    event ManagementFeeAssessed(uint256 feeAmount);

    error OnlyVault(address caller);

    constructor(IERC20 asset_, address authority_) AccessManaged(authority_) {
        if (address(asset_) == address(0) || authority_ == address(0)) revert ZeroAddress();
        asset = asset_;
        lastFeeAccrual = block.timestamp;
    }

    /// @notice Authorizes the vault that may request fee assessments.
    function setVault(address vault_) external restricted {
        if (vault_ == address(0)) revert ZeroAddress();
        emit VaultUpdated(vault, vault_);
        vault = vault_;
    }

    /// @notice Sets the fee recipient address.
    function setFeeRecipient(address recipient) external restricted {
        if (recipient == address(0)) revert ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, recipient);
        feeRecipient = recipient;
    }

    /// @notice Updates performance and management fee rates.
    function setFeeConfig(FeeConfig calldata config) external restricted {
        if (config.performanceBps > Constants.MAX_BPS || config.managementBps > Constants.MAX_BPS) {
            revert InvalidBasisPoints(config.performanceBps);
        }
        feeConfig = config;
        emit FeeConfigUpdated(config);
    }

    /// @notice Computes report-time fees against the supplied gross vault assets.
    /// @param totalAssetsGross Vault assets including locked profit, before fee deduction.
    /// @param reportedGain Realized gain reported by the strategy for the harvest window.
    /// @return performanceFee Performance fee owed on gains above the high-water mark.
    /// @return managementFee Management fee accrued since the previous assessment.
    function assessReportFees(uint256 totalAssetsGross, uint256 reportedGain)
        external
        returns (uint256 performanceFee, uint256 managementFee)
    {
        if (msg.sender != vault) revert OnlyVault(msg.sender);

        managementFee = _accrueManagementFee(totalAssetsGross);
        performanceFee = _assessPerformanceFee(totalAssetsGross, reportedGain);

        if (performanceFee != 0) emit PerformanceFeeAssessed(performanceFee, highWaterMark);
        if (managementFee != 0) emit ManagementFeeAssessed(managementFee);
    }

    function _assessPerformanceFee(uint256 totalAssetsGross, uint256 reportedGain)
        private
        returns (uint256 performanceFee)
    {
        if (reportedGain == 0 || feeConfig.performanceBps == 0) return 0;

        if (highWaterMark == 0 && totalAssetsGross > reportedGain) {
            highWaterMark = totalAssetsGross - reportedGain;
        }
        if (totalAssetsGross <= highWaterMark) return 0;

        uint256 feeableGain = totalAssetsGross - highWaterMark;
        if (feeableGain > reportedGain) feeableGain = reportedGain;
        performanceFee = feeableGain.mulDiv(feeConfig.performanceBps, Constants.BPS);
        highWaterMark = totalAssetsGross;
    }

    function _accrueManagementFee(uint256 totalAssetsGross) private returns (uint256 managementFee) {
        if (feeConfig.managementBps == 0 || totalAssetsGross == 0) {
            lastFeeAccrual = block.timestamp;
            return 0;
        }

        uint256 elapsed = block.timestamp - lastFeeAccrual;
        lastFeeAccrual = block.timestamp;
        managementFee =
            totalAssetsGross.mulDiv(feeConfig.managementBps, Constants.BPS).mulDiv(elapsed, Constants.SECONDS_PER_YEAR);
    }
}
