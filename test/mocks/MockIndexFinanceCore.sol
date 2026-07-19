// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IIndexFinanceCore} from "../../src/interfaces/external/IIndexFinanceCore.sol";

/// @notice Deterministic Phase 11 Index Finance core stand-in.
/// @dev TEST-ONLY and UNCONFIRMED against live Index Finance. Unsafe for production.
contract MockIndexFinanceCore is IIndexFinanceCore {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    mapping(address account => bool eligible) private _eligible;
    mapping(address account => uint256 assets) private _deposited;
    mapping(address account => address[] rewardTokens) private _rewardTokens;
    mapping(address account => mapping(address token => uint256 amount)) public accrued;
    mapping(address account => mapping(address token => bool listed)) private _listed;

    uint256 public nextWithdrawLoss;
    bool public returnMalformedClaim;
    address public reentryTarget;
    bytes public reentryData;
    bool public reentryAttempted;
    bool public reentrySucceeded;

    error AccountIneligible(address account);

    constructor(IERC20 asset_) {
        asset = asset_;
    }

    function setEligible(address account, bool eligible_) external {
        _eligible[account] = eligible_;
    }

    function setNextWithdrawLoss(uint256 loss) external {
        nextWithdrawLoss = loss;
    }

    function setReturnMalformedClaim(bool malformed) external {
        returnMalformedClaim = malformed;
    }

    function setReentry(address target, bytes calldata data) external {
        reentryTarget = target;
        reentryData = data;
    }

    function accrue(address account, address token, uint256 amount) external {
        if (!_listed[account][token]) {
            _listed[account][token] = true;
            _rewardTokens[account].push(token);
        }
        accrued[account][token] += amount;
    }

    function slash(address account, uint256 amount) external {
        uint256 current = _deposited[account];
        _deposited[account] = amount > current ? 0 : current - amount;
    }

    function deposit(uint256 assets) external {
        _deposited[msg.sender] += assets;
        asset.safeTransferFrom(msg.sender, address(this), assets);
    }

    function withdraw(uint256 assets) external returns (uint256 withdrawnAssets) {
        uint256 current = _deposited[msg.sender];
        uint256 requestedLoss = nextWithdrawLoss;
        nextWithdrawLoss = 0;

        uint256 principalNeeded = assets + requestedLoss;
        uint256 principalConsumed = principalNeeded > current ? current : principalNeeded;
        uint256 loss = requestedLoss > principalConsumed ? principalConsumed : requestedLoss;
        withdrawnAssets = principalConsumed - loss;
        if (withdrawnAssets > assets) withdrawnAssets = assets;

        _deposited[msg.sender] = current - principalConsumed;
        if (withdrawnAssets != 0) asset.safeTransfer(msg.sender, withdrawnAssets);
    }

    function totalDeposited(address account) external view returns (uint256 assets_) {
        assets_ = _deposited[account];
    }

    function isEligible(address account) external view returns (bool) {
        return _eligible[account];
    }

    function claimRewards(address account, address receiver)
        external
        returns (address[] memory rewardTokens, uint256[] memory claimedAmounts)
    {
        if (!_eligible[account]) revert AccountIneligible(account);

        if (reentryTarget != address(0)) {
            reentryAttempted = true;
            (reentrySucceeded,) = reentryTarget.call(reentryData);
        }

        rewardTokens = _rewardTokens[account];
        uint256 amountLength =
            returnMalformedClaim && rewardTokens.length != 0 ? rewardTokens.length - 1 : rewardTokens.length;
        claimedAmounts = new uint256[](amountLength);

        for (uint256 i; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            uint256 amount = accrued[account][token];
            accrued[account][token] = 0;
            if (i < claimedAmounts.length) claimedAmounts[i] = amount;
            if (amount != 0) IERC20(token).safeTransfer(receiver, amount);
        }
    }
}
