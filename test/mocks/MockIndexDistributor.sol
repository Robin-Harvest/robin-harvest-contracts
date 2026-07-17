// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IIndexFinance} from "../../src/interfaces/external/IIndexFinance.sol";

/// @notice Deterministic Index Finance reward-distributor stand-in for tests.
/// @dev TEST-ONLY and UNCONFIRMED against the live Index Finance ABI. Unsafe for production.
contract MockIndexDistributor is IIndexFinance {
    using SafeERC20 for IERC20;

    error AccountIneligible(address account);

    mapping(address account => bool eligible) private _eligible;
    mapping(address account => address[] rewardTokens) private _rewardTokens;
    mapping(address account => mapping(address token => uint256 amount)) public accrued;
    mapping(address account => mapping(address token => bool listed)) private _listed;

    function setEligible(address account, bool eligible_) external {
        _eligible[account] = eligible_;
    }

    function accrue(address account, address token, uint256 amount) external {
        if (!_listed[account][token]) {
            _listed[account][token] = true;
            _rewardTokens[account].push(token);
        }
        accrued[account][token] += amount;
    }

    function isEligible(address account) external view override returns (bool) {
        return _eligible[account];
    }

    function claimRewards(address account, address receiver)
        external
        override
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        if (!_eligible[account]) revert AccountIneligible(account);

        rewardTokens = _rewardTokens[account];
        claimedAmounts = new uint256[](rewardTokens.length);
        for (uint256 i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            uint256 amount = accrued[account][token];
            accrued[account][token] = 0;
            claimedAmounts[i] = amount;
            if (amount != 0) IERC20(token).safeTransfer(receiver, amount);
        }
    }
}
