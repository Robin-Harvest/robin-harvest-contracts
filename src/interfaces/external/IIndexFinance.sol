// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Provisional minimal boundary for a future Index Finance integration.
/// @dev UNCONFIRMED — verify against live contract.
interface IIndexFinance {
    /// @notice Claims rewards attributed to an account and sends them to a receiver.
    /// @dev UNCONFIRMED — verify selector, authorization, token set, accounting, and return semantics against live contract.
    /// @param account Account whose accrued rewards are claimed.
    /// @param receiver Address receiving claimed rewards.
    /// @return rewardTokens Token addresses reported as claimed.
    /// @return claimedAmounts Raw amounts corresponding to rewardTokens.
    function claimRewards(address account, address receiver)
        external
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts);

    /// @notice Reports whether an account is eligible for rewards.
    /// @dev UNCONFIRMED — verify selector and eligibility semantics against live contract.
    /// @param account Account to inspect.
    function isEligible(address account) external view returns (bool eligible);
}
