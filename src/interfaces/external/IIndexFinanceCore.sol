// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IIndexFinance} from "./IIndexFinance.sol";

/*
 * TEMPORARY - PHASE 11 ONLY
 *
 * This interface reflects assumptions made during Phase 11 because the Final Architecture explicitly marks the
 * official Index Finance contracts and reward ABI as unresolved external blockers.
 *
 * Do not treat this interface as canonical Index Finance documentation.
 * Replace or adapt it once the official Index Finance ABI is finalized and verified.
 */
/// @notice Provisional minimal boundary for the rhINDEX-Core Index Finance position.
/// @dev UNCONFIRMED. Models only the minimum behavior CoreStrategy needs to compile and test against mocks:
/// account-scoped INDEX deposit, INDEX withdrawal, reward claiming, eligibility checks, and position NAV.
/// TODO(PHASE-11-INTEGRATION): Replace or adapt this boundary after the official Index Finance ABI is verified.
interface IIndexFinanceCore is IIndexFinance {
    /// @notice Deposits INDEX from msg.sender into the caller's Index Finance position.
    /// @dev UNCONFIRMED selector and semantics. Assumes the implementation pulls exactly `assets` INDEX from msg.sender.
    function deposit(uint256 assets) external;

    /// @notice Withdraws up to `assets` INDEX from msg.sender's Index Finance position back to msg.sender.
    /// @dev UNCONFIRMED selector and semantics. The return value is measured against actual balance deltas by callers.
    function withdraw(uint256 assets) external returns (uint256 withdrawnAssets);

    /// @notice Returns the INDEX-denominated position currently attributed to an account.
    /// @dev UNCONFIRMED selector and semantics. Required so CoreStrategy can report deterministic NAV and losses.
    function totalDeposited(address account) external view returns (uint256 assets);
}
