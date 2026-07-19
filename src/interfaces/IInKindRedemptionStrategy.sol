// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {InKindRedemptionResult} from "../types/ProtocolTypes.sol";

/// @notice Optional portfolio-redemption capability implemented only by GrowthStrategy.
/// @dev RobinVault uses this narrow boundary so it never needs to track individual retained assets.
interface IInKindRedemptionStrategy {
    /// @notice Previews the strategy-held proportional position for a share redemption.
    /// @dev Uses the vault's current total supply as the denominator and rounds every asset down.
    function previewInKindRedemption(uint256 shares) external view returns (InKindRedemptionResult memory result);

    /// @notice Transfers the strategy-held proportional position to a receiver.
    /// @dev Callable only by the strategy's configured vault.
    function redeemInKind(uint256 shares, uint256 debtReduction, address receiver)
        external
        returns (InKindRedemptionResult memory result);
}
