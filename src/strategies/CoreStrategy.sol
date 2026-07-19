// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../libraries/Constants.sol";
import {InvalidAccounting, InvalidBasisPoints, InvalidRange, ZeroAddress, ZeroAmount} from "../libraries/Errors.sol";
import {IExecutionRouter} from "../interfaces/IExecutionRouter.sol";
import {IOracleRegistry} from "../interfaces/IOracleRegistry.sol";
import {IRewardRegistry} from "../interfaces/IRewardRegistry.sol";
import {IIndexFinanceCore} from "../interfaces/external/IIndexFinanceCore.sol";
import {RewardDisposition, RewardTokenConfig, SwapRequest} from "../types/ProtocolTypes.sol";
import {StrategyBase} from "./StrategyBase.sol";

/// @title Robin Harvest Core Strategy
/// @notice Concrete rhINDEX-Core strategy that deploys INDEX, claims rewards, sells approved rewards to INDEX, and reports
/// deterministic asset-denominated accounting to RobinVault.
/// @dev Core intentionally does not retain rewards. Unswapped reward balances are excluded from NAV until converted to
/// INDEX. Index Finance deposit/withdraw selectors remain provisional until the official Phase 11 ABI is verified.
contract CoreStrategy is StrategyBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IIndexFinanceCore public immutable indexFinance;
    IRewardRegistry public immutable rewardRegistry;
    IOracleRegistry public immutable oracleRegistry;
    IExecutionRouter public immutable executionRouter;

    /// @notice Maximum oracle-derived slippage accepted when Core sells rewards.
    uint16 public maxSlippageBps;

    /// @notice Seconds added to the current timestamp when constructing router swap deadlines.
    uint48 public swapDeadlineDelay;

    event CoreParametersUpdated(uint16 maxSlippageBps, uint48 swapDeadlineDelay);
    event CoreCapitalDeployed(uint256 assets);
    event CoreCapitalFreed(uint256 requestedAssets, uint256 withdrawnAssets, uint256 loss);
    event CoreRewardsClaimed(address indexed token, uint256 amount);
    event CoreRewardSkipped(address indexed token, uint256 amount, RewardDisposition disposition);
    event CoreRewardDeferred(address indexed token, uint256 amount, uint256 minHarvestAmount);
    event CoreRewardSold(address indexed token, uint256 amountIn, uint256 amountOut);

    error IndexFinanceIneligible(address account);
    error InvalidRewardClaim();
    error RetainedRewardsUnsupported(address token);
    error ZeroMinimumOutput(address token, uint256 amountIn);
    error DeadlineOverflow(uint256 deadline);

    constructor(
        address vault_,
        IERC20 asset_,
        address authority_,
        IIndexFinanceCore indexFinance_,
        IRewardRegistry rewardRegistry_,
        IOracleRegistry oracleRegistry_,
        IExecutionRouter executionRouter_,
        uint16 maxSlippageBps_,
        uint48 swapDeadlineDelay_
    ) StrategyBase(vault_, asset_, authority_) {
        if (
            address(indexFinance_) == address(0) || address(rewardRegistry_) == address(0)
                || address(oracleRegistry_) == address(0) || address(executionRouter_) == address(0)
        ) revert ZeroAddress();
        if (maxSlippageBps_ > Constants.MAX_BPS) revert InvalidBasisPoints(maxSlippageBps_);
        if (swapDeadlineDelay_ == 0) revert ZeroAmount();

        indexFinance = indexFinance_;
        rewardRegistry = rewardRegistry_;
        oracleRegistry = oracleRegistry_;
        executionRouter = executionRouter_;
        maxSlippageBps = maxSlippageBps_;
        swapDeadlineDelay = swapDeadlineDelay_;
    }

    /// @notice Updates deterministic swap parameters used by parameterless keeper harvests.
    function setCoreParameters(uint16 newMaxSlippageBps, uint48 newSwapDeadlineDelay) external restricted {
        if (newMaxSlippageBps > Constants.MAX_BPS) revert InvalidBasisPoints(newMaxSlippageBps);
        if (newSwapDeadlineDelay == 0) revert ZeroAmount();
        maxSlippageBps = newMaxSlippageBps;
        swapDeadlineDelay = newSwapDeadlineDelay;
        emit CoreParametersUpdated(newMaxSlippageBps, newSwapDeadlineDelay);
    }

    /// @notice Returns the current INDEX-denominated position reported by the provisional Index Finance boundary.
    function deployedAssets() public view returns (uint256 assets_) {
        assets_ = indexFinance.totalDeposited(address(this));
    }

    function _deployFunds(uint256 amount) internal override {
        IERC20 assetToken = IERC20(asset());
        uint256 balanceBefore = assetToken.balanceOf(address(this));
        uint256 positionBefore = deployedAssets();
        assetToken.forceApprove(address(indexFinance), amount);
        indexFinance.deposit(amount);
        assetToken.forceApprove(address(indexFinance), 0);
        uint256 balanceAfter = assetToken.balanceOf(address(this));
        if (balanceBefore < balanceAfter || balanceBefore - balanceAfter != amount) revert InvalidAccounting();
        if (deployedAssets() < positionBefore + amount) revert InvalidAccounting();
        emit CoreCapitalDeployed(amount);
    }

    function _freeFunds(uint256 amount) internal override returns (uint256 loss) {
        uint256 positionBefore = deployedAssets();
        uint256 requested = amount > positionBefore ? positionBefore : amount;
        // Justification: requested == 0 is a parameter-derived early return, not a balance invariant.
        // slither-disable-next-line incorrect-equality
        if (requested == 0) return amount;

        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        uint256 reportedWithdrawn = indexFinance.withdraw(requested);
        uint256 balanceAfter = IERC20(asset()).balanceOf(address(this));
        uint256 withdrawn = balanceAfter - balanceBefore;
        if (reportedWithdrawn > withdrawn) revert InvalidAccounting();
        uint256 positionAfter = deployedAssets();
        if (positionAfter > positionBefore) revert InvalidAccounting();
        uint256 principalConsumed = positionBefore - positionAfter;
        if (principalConsumed < withdrawn) revert InvalidAccounting();

        loss = principalConsumed - withdrawn;
        emit CoreCapitalFreed(amount, withdrawn, loss);
    }

    function _claimRewards() internal override {
        if (!indexFinance.isEligible(address(this))) revert IndexFinanceIneligible(address(this));

        (address[] memory rewardTokens_, uint256[] memory claimedAmounts) =
            indexFinance.claimRewards(address(this), address(this));
        if (rewardTokens_.length != claimedAmounts.length) revert InvalidRewardClaim();

        for (uint256 i; i < rewardTokens_.length; ++i) {
            address token = rewardTokens_[i];
            uint256 amount = claimedAmounts[i];
            if (token == address(0)) revert ZeroAddress();
            emit CoreRewardsClaimed(token, amount);
            if (amount == 0) continue;

            // Justification: The registry read is a pure view call inside a bounded reward-token loop.
            // slither-disable-next-line calls-loop
            RewardTokenConfig memory config = rewardRegistry.getRewardTokenConfig(token);
            if (!config.enabled) {
                emit CoreRewardSkipped(token, amount, RewardDisposition.Ignore);
            } else if (config.disposition == RewardDisposition.Retain) {
                revert RetainedRewardsUnsupported(token);
            }
        }
    }

    function _processRewardToken(address token) internal override returns (uint256 assetGain) {
        uint256 amount = IERC20(token).balanceOf(address(this));
        // Justification: amount == 0 is an early return for dust balances, not a balance invariant.
        // slither-disable-next-line incorrect-equality
        if (amount == 0) return 0;

        RewardTokenConfig memory config = rewardRegistry.getRewardTokenConfig(token);
        if (!config.enabled) {
            emit CoreRewardSkipped(token, amount, RewardDisposition.Ignore);
            return 0;
        }

        if (amount < config.minHarvestAmount) {
            emit CoreRewardDeferred(token, amount, config.minHarvestAmount);
            return 0;
        }

        if (config.disposition == RewardDisposition.Ignore) {
            emit CoreRewardSkipped(token, amount, config.disposition);
            return 0;
        }
        if (config.disposition == RewardDisposition.Retain) revert RetainedRewardsUnsupported(token);
        if (config.disposition != RewardDisposition.Sell) revert InvalidRange(0, uint256(config.disposition), 2);

        // Justification: Reentrancy is prevented because harvest() is protected by nonReentrant.
        // The event emitted after the external call is benign logging.
        // slither-disable-next-line reentrancy-benign,reentrancy-events
        assetGain = _sellReward(token, amount, config.adapter);
        emit CoreRewardSold(token, amount, assetGain);
    }

    function _tend() internal view override {
        if (!indexFinance.isEligible(address(this))) revert IndexFinanceIneligible(address(this));
    }

    /// @dev Shutdown stops future deployment through StrategyBase lifecycle. Capital return is handled by emergencyWithdraw.
    function _shutdownStrategy() internal override {}

    function _emergencyWithdraw() internal override returns (uint256 loss) {
        uint256 amount = deployedAssets();
        if (amount == 0) return 0;
        loss = _withdrawFromIndexFinance(amount, amount);
    }

    function _deployedAssets() internal view override returns (uint256) {
        return deployedAssets();
    }

    /// @dev Core excludes unsold rewards from NAV until they are converted to INDEX.
    function _rewardAssets() internal pure override returns (uint256) {
        return 0;
    }

    function _sellReward(address token, uint256 amount, address adapter) private returns (uint256 amountOut) {
        if (adapter == address(0)) revert ZeroAddress();
        uint256 minAmountOut = _minimumOutput(token, amount);
        // Justification: minAmountOut == 0 guards against worthless oracle-derived output, not a balance invariant.
        // slither-disable-next-line incorrect-equality
        if (minAmountOut == 0) revert ZeroMinimumOutput(token, amount);
        uint48 deadline = _swapDeadline();

        IERC20(token).forceApprove(address(executionRouter), amount);
        amountOut = executionRouter.swapExactInput(
            SwapRequest({
                adapter: adapter,
                tokenIn: token,
                tokenOut: asset(),
                amountIn: amount,
                minAmountOut: minAmountOut,
                deadline: deadline
            }),
            address(this)
        );
        IERC20(token).forceApprove(address(executionRouter), 0);
    }

    /// @dev Computes the router minimum output from validated oracle prices:
    ///      amountIn * priceIn / priceOut, converted from token decimals to INDEX decimals, less configured slippage.
    ///      This is deliberately conservative: if either oracle is stale/paused/invalid, the registry reverts and no
    ///      swap is attempted. The router independently rechecks oracle deviation against the realized execution.
    function _minimumOutput(address token, uint256 amount) private view returns (uint256 minAmountOut) {
        // Justification: updatedAt is validated inside the OracleRegistry; the strategy does not re-check it.
        // slither-disable-next-line unused-return
        (uint256 priceIn,) = oracleRegistry.getValidatedPrice(token);
        // slither-disable-next-line unused-return
        (uint256 priceOut,) = oracleRegistry.getValidatedPrice(asset());
        uint8 decimalsIn = IERC20Metadata(token).decimals();
        uint8 decimalsOut = IERC20Metadata(asset()).decimals();

        uint256 expectedOut = amount.mulDiv(priceIn, priceOut).mulDiv(10 ** decimalsOut, 10 ** decimalsIn);
        minAmountOut = expectedOut.mulDiv(Constants.BPS - maxSlippageBps, Constants.BPS);
    }

    // Justification: block.timestamp is used to construct a swap deadline, not for authorization or pricing.
    // slither-disable-next-line timestamp
    function _swapDeadline() private view returns (uint48 deadline) {
        uint256 rawDeadline = block.timestamp + uint256(swapDeadlineDelay);
        if (rawDeadline > type(uint48).max) revert DeadlineOverflow(rawDeadline);
        deadline = uint48(rawDeadline);
    }

    function _withdrawFromIndexFinance(uint256 amount, uint256 lossBasis) private returns (uint256 loss) {
        uint256 positionBefore = deployedAssets();
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        uint256 reportedWithdrawn = indexFinance.withdraw(amount);
        uint256 balanceAfter = IERC20(asset()).balanceOf(address(this));
        uint256 withdrawn = balanceAfter - balanceBefore;
        if (reportedWithdrawn > withdrawn) revert InvalidAccounting();
        uint256 positionAfter = deployedAssets();
        if (positionAfter > positionBefore) revert InvalidAccounting();
        uint256 principalConsumed = positionBefore - positionAfter;
        if (principalConsumed < withdrawn) revert InvalidAccounting();

        loss = principalConsumed - withdrawn;
        emit CoreCapitalFreed(lossBasis, withdrawn, loss);
    }
}
