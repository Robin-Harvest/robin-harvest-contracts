// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Provisional metadata and compliance boundary for tokenized stocks.
/// @dev UNCONFIRMED — verify against live contract.
interface IStockToken {
    /// @notice Returns the token display name.
    /// @dev UNCONFIRMED — verify ERC-20 metadata compatibility against live contract.
    function name() external view returns (string memory tokenName);

    /// @notice Returns the token ticker symbol.
    /// @dev UNCONFIRMED — verify ERC-20 metadata compatibility against live contract.
    function symbol() external view returns (string memory tokenSymbol);

    /// @notice Returns the token's raw-unit decimal precision.
    /// @dev UNCONFIRMED — verify ERC-20 metadata compatibility against live contract.
    function decimals() external view returns (uint8 tokenDecimals);

    /// @notice Reports whether transfers are currently enabled.
    /// @dev UNCONFIRMED — verify selector and whether restrictions are global or account-specific against live contract.
    function transfersEnabled() external view returns (bool enabled);

    /// @notice Returns a cumulative multiplier representing corporate-action adjustments.
    /// @dev UNCONFIRMED — verify selector, precision, update rules, and applicability against live contract.
    function corporateActionMultiplier() external view returns (uint256 multiplier);
}
