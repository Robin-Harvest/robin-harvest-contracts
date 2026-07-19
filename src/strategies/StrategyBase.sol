// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Events} from "../libraries/Events.sol";
import {InvalidLifecycleState, ZeroAddress, ZeroAmount} from "../libraries/Errors.sol";
import {IRobinStrategy} from "../interfaces/IRobinStrategy.sol";
import {IRobinVaultReport} from "../interfaces/IRobinVaultReport.sol";
import {HarvestReport, LifecycleState} from "../types/ProtocolTypes.sol";

/// @title Robin Harvest Strategy Base
/// @notice Abstract framework for isolated, keeper-triggered strategies attached to a single RobinVault.
/// @dev Later strategies implement protocol-specific reward claiming, deployment, and NAV hooks. This base never accepts
/// arbitrary calldata and never performs Index Finance, portfolio, or retention policy logic directly.
// Justification: StrategyBase is an abstract base contract, and the inheriting strategies will implement these functions.
// slither-disable-next-line unimplemented-functions
abstract contract StrategyBase is IRobinStrategy, AccessManaged, ReentrancyGuard, Events {
    using SafeERC20 for IERC20;

    address public immutable override vault;
    IERC20 private immutable _asset;

    LifecycleState public override lifecycleState;
    uint256 public lastReportedAssets;

    address[] private _rewardTokens;
    mapping(address token => bool tracked) public isRewardTokenTracked;
    mapping(address token => bool isolated) public isRewardTokenIsolated;
    mapping(address token => uint16 exposureBps) public tokenExposureBps;

    event RewardTokenTracked(address indexed token, bool tracked);
    event RewardTokenIsolationUpdated(address indexed token, bool isolated);
    event FundsDeployed(uint256 amount);
    event FundsFreed(uint256 requested, uint256 amountFreed, uint256 loss);
    event EmergencyWithdrawal(uint256 amountFreed, uint256 loss);
    event StrategyTended(address indexed keeper);

    error OnlyVault(address caller);
    error OnlySelf(address caller);

    constructor(address vault_, IERC20 asset_, address authority_) AccessManaged(authority_) {
        if (vault_ == address(0) || address(asset_) == address(0) || authority_ == address(0)) revert ZeroAddress();
        vault = vault_;
        _asset = asset_;
        lifecycleState = LifecycleState.Active;
    }

    function asset() public view override returns (address assetAddress) {
        assetAddress = address(_asset);
    }

    /// @notice Returns idle assets plus strategy-specific deployed NAV and reward NAV hooks.
    function totalAssets() public view virtual override returns (uint256 totalManagedAssets) {
        totalManagedAssets = _asset.balanceOf(address(this)) + _deployedAssets() + _rewardAssets();
    }

    function rewardTokens() external view returns (address[] memory tokens) {
        tokens = _rewardTokens;
    }

    function deployFunds(uint256 amount) external override nonReentrant onlyVault {
        if (lifecycleState != LifecycleState.Active) revert InvalidLifecycleState(uint8(lifecycleState));
        if (amount == 0) revert ZeroAmount();
        _deployFunds(amount);
        lastReportedAssets = totalAssets();
        emit FundsDeployed(amount);
    }

    function freeFunds(uint256 amount)
        external
        override
        nonReentrant
        onlyVault
        returns (uint256 amountFreed, uint256 loss)
    {
        if (amount == 0) revert ZeroAmount();
        uint256 idleBefore = _asset.balanceOf(address(this));
        if (idleBefore < amount) {
            loss = _freeFunds(amount - idleBefore);
        }

        uint256 idleAfter = _asset.balanceOf(address(this));
        amountFreed = idleAfter < amount ? idleAfter : amount;
        if (amountFreed != 0) _asset.safeTransfer(vault, amountFreed);

        lastReportedAssets = totalAssets();
        emit FundsFreed(amount, amountFreed, loss);
    }

    function harvest() external override restricted nonReentrant returns (HarvestReport memory report_) {
        if (lifecycleState != LifecycleState.Active) revert InvalidLifecycleState(uint8(lifecycleState));

        _claimRewards();
        address[] memory tokens = _rewardTokens;
        for (uint256 i; i < tokens.length; ++i) {
            address token = tokens[i];
            if (isRewardTokenIsolated[token]) continue;
            // Justification: Calls processRewardToken externally via `this.` intentionally to execute
            // it inside a try-catch block. This isolates individual reward token failures during harvest.
            // Justification: The return value of processRewardToken is intentionally ignored here, as the overall
            // gain is calculated via totalAssets() delta at the end of the harvest.
            // slither-disable-next-line calls-loop,unused-return
            try this.processRewardToken(token) returns (uint256) {}
            catch (bytes memory reasonData) {
                isRewardTokenIsolated[token] = true;
                emit RewardTokenIsolationUpdated(token, true);
                emit RewardProcessingFailed(token, reasonData);
            }
        }

        uint256 assetsNow = totalAssets();
        uint256 previous = lastReportedAssets;
        if (assetsNow >= previous) {
            report_.gain = assetsNow - previous;
        } else {
            report_.loss = previous - assetsNow;
        }

        uint256 debtPayment = _asset.balanceOf(address(this));
        if (debtPayment != 0) {
            _asset.safeTransfer(vault, debtPayment);
            report_.debtPayment = debtPayment;
        }

        IRobinVaultReport(vault).report(report_);
        lastReportedAssets = totalAssets();
    }

    /// @notice Self-call boundary used so one reward-token failure cannot revert the whole harvest.
    function processRewardToken(address token) external returns (uint256 assetGain) {
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);
        assetGain = _processRewardToken(token);
    }

    function tend() external override restricted nonReentrant {
        if (lifecycleState != LifecycleState.Active) revert InvalidLifecycleState(uint8(lifecycleState));
        _tend();
        lastReportedAssets = totalAssets();
        emit StrategyTended(msg.sender);
    }

    function pause() external restricted {
        _setLifecycleState(LifecycleState.Paused);
    }

    function unpause() external restricted {
        if (lifecycleState == LifecycleState.Shutdown) revert InvalidLifecycleState(uint8(lifecycleState));
        _setLifecycleState(LifecycleState.Active);
    }

    function shutdown() external override restricted {
        _shutdownStrategy();
        _setLifecycleState(LifecycleState.Shutdown);
    }

    function emergencyWithdraw()
        external
        override
        restricted
        nonReentrant
        returns (uint256 amountFreed, uint256 loss)
    {
        loss = _emergencyWithdraw();
        amountFreed = _asset.balanceOf(address(this));
        if (amountFreed != 0) _asset.safeTransfer(vault, amountFreed);
        if (amountFreed != 0 || loss != 0) {
            IRobinVaultReport(vault).report(HarvestReport({gain: 0, loss: loss, debtPayment: amountFreed}));
        }
        lastReportedAssets = totalAssets();
        _setLifecycleState(LifecycleState.Shutdown);
        emit EmergencyWithdrawal(amountFreed, loss);
    }

    function addRewardToken(address token) external restricted {
        if (token == address(0)) revert ZeroAddress();
        if (isRewardTokenTracked[token]) return;
        isRewardTokenTracked[token] = true;
        _rewardTokens.push(token);
        emit RewardTokenTracked(token, true);
    }

    function removeRewardToken(address token) external restricted {
        if (!isRewardTokenTracked[token]) return;
        isRewardTokenTracked[token] = false;
        uint256 length = _rewardTokens.length;
        uint256 foundIndex = type(uint256).max;
        for (uint256 i; i < length; ++i) {
            if (_rewardTokens[i] == token) {
                foundIndex = i;
                break;
            }
        }
        if (foundIndex != type(uint256).max) {
            _rewardTokens[foundIndex] = _rewardTokens[length - 1];
            _rewardTokens.pop();
        }
        emit RewardTokenTracked(token, false);
    }

    function setRewardTokenIsolated(address token, bool isolated) external restricted {
        if (token == address(0)) revert ZeroAddress();
        isRewardTokenIsolated[token] = isolated;
        emit RewardTokenIsolationUpdated(token, isolated);
    }

    // Justification: _setTokenExposure is an internal helper hook intended for concrete strategies that inherit StrategyBase.
    // slither-disable-next-line dead-code
    function _setTokenExposure(address token, uint16 exposureBps) internal {
        tokenExposureBps[token] = exposureBps;
    }

    modifier onlyVault() {
        _checkOnlyVault();
        _;
    }

    function _checkOnlyVault() internal view {
        if (msg.sender != vault) revert OnlyVault(msg.sender);
    }

    function _setLifecycleState(LifecycleState newState) private {
        LifecycleState previousState = lifecycleState;
        if (previousState == LifecycleState.Shutdown && newState != LifecycleState.Shutdown) {
            revert InvalidLifecycleState(uint8(previousState));
        }
        lifecycleState = newState;
        emit LifecycleStateChanged(previousState, newState);
    }

    function _deployFunds(uint256 amount) internal virtual;

    /// @notice Frees deployed assets back into this contract and returns realized loss, if any.
    function _freeFunds(uint256 amount) internal virtual returns (uint256 loss);

    // Justification: _claimRewards is a virtual hook overridden by concrete strategies (e.g. CoreStrategy).
    // slither-disable-next-line dead-code
    function _claimRewards() internal virtual {}

    function _processRewardToken(address token) internal virtual returns (uint256 assetGain);

    // Justification: _tend is a virtual hook overridden by concrete strategies (e.g. CoreStrategy).
    // slither-disable-next-line dead-code
    function _tend() internal virtual {}

    // Justification: _shutdownStrategy is a virtual hook overridden by concrete strategies (e.g. CoreStrategy).
    // slither-disable-next-line dead-code
    function _shutdownStrategy() internal virtual {}

    function _emergencyWithdraw() internal virtual returns (uint256 loss);

    function _deployedAssets() internal view virtual returns (uint256);

    // Justification: _rewardAssets is a virtual hook overridden by concrete strategies (e.g. CoreStrategy).
    // slither-disable-next-line dead-code
    function _rewardAssets() internal view virtual returns (uint256) {
        return 0;
    }
}
