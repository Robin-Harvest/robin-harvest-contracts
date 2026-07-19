// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../libraries/Constants.sol";
import {
    CooldownActive,
    ExposureLimitExceeded,
    InvalidBasisPoints,
    InvalidRange,
    ZeroAddress
} from "../libraries/Errors.sol";
import {IExecutionRouter} from "../interfaces/IExecutionRouter.sol";
import {IOracleRegistry} from "../interfaces/IOracleRegistry.sol";
import {IRewardRegistry} from "../interfaces/IRewardRegistry.sol";
import {IIndexFinanceCore} from "../interfaces/external/IIndexFinanceCore.sol";
import {IStockToken} from "../interfaces/external/IStockToken.sol";
import {CategoryPolicy, RewardCategory, RewardDisposition, RewardTokenConfig} from "../types/ProtocolTypes.sol";
import {CoreStrategy} from "./CoreStrategy.sol";



/// @title Robin Harvest Growth Strategy
/// @notice rhINDEX-Growth strategy that sells SELL rewards, ignores IGNORE rewards, and retains approved stock rewards.
/// @dev Growth extends Core's Index Finance deployment, withdrawal, reward selling, min-output, and reporting behavior.
/// Retained rewards are included in NAV using validated oracle prices. The architecture also requires conservative
/// executable quotes and haircuts; no quote or haircut algorithm is defined yet, so this phase enforces that every newly
/// retained asset has a valid oracle and an approved liquidation route, then leaves executable-quote haircuts as a TODO.
contract GrowthStrategy is CoreStrategy {
    using Math for uint256;

    mapping(address token => uint256 amount) public retainedBalance;
    mapping(address token => bool tracked) public isRetainedToken;
    mapping(RewardCategory category => CategoryPolicy policy) public categoryPolicies;
    mapping(RewardCategory category => uint256 timestamp) public lastRebalanceAt;

    address[] private _retainedTokens;

    event GrowthRewardRetained(address indexed token, RewardCategory indexed category, uint256 amount, uint256 value);
    event GrowthCategoryPolicyUpdated(RewardCategory indexed category, CategoryPolicy policy);
    event GrowthRebalanceMarked(RewardCategory indexed category, uint256 timestamp);
    event GrowthRetentionSkipped(address indexed token, uint256 amount, string reason);

    error RetainedAssetInvalid(address token);
    error RetainedAssetRouteUnavailable(address token, address adapter);
    error RetainedAssetTransfersPaused(address token);

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
    )
        CoreStrategy(
            vault_,
            asset_,
            authority_,
            indexFinance_,
            rewardRegistry_,
            oracleRegistry_,
            executionRouter_,
            maxSlippageBps_,
            swapDeadlineDelay_
        )
    {}

    /// @notice Returns the retained reward tokens included in portfolio NAV.
    function retainedTokens() external view returns (address[] memory tokens) {
        tokens = _retainedTokens;
    }

    /// @notice Returns the number of retained token entries.
    function retainedTokenCount() external view returns (uint256 count) {
        count = _retainedTokens.length;
    }

    /// @notice Configures target/min/max/category exposure policy for a reward category.
    /// @dev Phase 13 defines target bands but not a rebalance algorithm. This function stores those bands and enforces
    /// `maxPortfolioBps` as a hard cap when new rewards are retained.
    function setCategoryPolicy(RewardCategory category, CategoryPolicy calldata policy) external restricted {
        if (
            policy.minRetainBps > policy.targetRetainBps || policy.targetRetainBps > policy.maxRetainBps
                || policy.maxPortfolioBps > Constants.MAX_BPS
        ) {
            revert InvalidRange(policy.minRetainBps, policy.targetRetainBps, policy.maxRetainBps);
        }
        if (policy.maxRetainBps > Constants.MAX_BPS) revert InvalidBasisPoints(policy.maxRetainBps);
        categoryPolicies[category] = policy;
        emit GrowthCategoryPolicyUpdated(category, policy);
    }

    /// @notice Records a rebalance checkpoint for a category after the configured cooldown.
    /// @dev TODO(PHASE-13-REBALANCE): Implement deterministic rebalance execution once the architecture defines the
    /// allocation algorithm, executable quote source, and haircut parameters. This hook only records cadence.
    function markRebalance(RewardCategory category) external restricted {
        CategoryPolicy memory policy = categoryPolicies[category];
        uint256 previous = lastRebalanceAt[category];
        // Justification: block.timestamp is used for a target policy rebalance cooldown check.
        // slither-disable-next-line timestamp
        if (policy.rebalanceCooldown != 0 && previous != 0 && block.timestamp < previous + policy.rebalanceCooldown) {
            revert CooldownActive(previous + policy.rebalanceCooldown);
        }
        lastRebalanceAt[category] = block.timestamp;
        emit GrowthRebalanceMarked(category, block.timestamp);
    }

    /// @notice Returns current retained value for one token, denominated in INDEX.
    function retainedValue(address token) public view returns (uint256 value) {
        value = _valueToken(token, retainedBalance[token]);
    }

    /// @notice Returns current retained exposure for one token in basis points of strategy NAV.
    function retainedExposureBps(address token) external view returns (uint256 exposureBps) {
        exposureBps = _exposureBps(retainedValue(token), totalAssets());
    }

    /// @notice Returns current category value and exposure in basis points of strategy NAV.
    function categoryExposure(RewardCategory category) public view returns (uint256 value, uint256 exposureBps) {
        value = _categoryValue(category);
        exposureBps = _exposureBps(value, totalAssets());
    }

    function _claimRewards() internal override {
        if (!indexFinance.isEligible(address(this))) revert IndexFinanceIneligible(address(this));

        (address[] memory rewardTokens_, uint256[] memory claimedAmounts) =
            indexFinance.claimRewards(address(this), address(this));
        if (rewardTokens_.length != claimedAmounts.length) revert InvalidRewardClaim();

        // Justification: Bounded reward tokens list iteration.
        // slither-disable-next-line calls-loop
        for (uint256 i; i < rewardTokens_.length; ++i) {
            address token = rewardTokens_[i];
            uint256 amount = claimedAmounts[i];
            if (token == address(0)) revert ZeroAddress();
            emit CoreRewardsClaimed(token, amount);
            if (amount == 0) continue;

            RewardTokenConfig memory config = rewardRegistry.getRewardTokenConfig(token);
            if (!config.enabled) {
                emit CoreRewardSkipped(token, amount, RewardDisposition.Ignore);
            }
        }
    }

    function _processRewardToken(address token) internal override returns (uint256 assetGain) {
        uint256 amount = IERC20(token).balanceOf(address(this));
        // Justification: amount == 0 is an early return check.
        // slither-disable-next-line incorrect-equality
        if (amount == 0) return 0;

        RewardTokenConfig memory config = rewardRegistry.getRewardTokenConfig(token);
        if (!config.enabled) {
            emit CoreRewardSkipped(token, amount, RewardDisposition.Ignore);
            return 0;
        }

        uint256 retained = retainedBalance[token];
        uint256 processAmount = amount > retained ? amount - retained : 0;
        // Justification: processAmount == 0 checks if there is any new reward to process.
        // slither-disable-next-line incorrect-equality
        if (processAmount == 0 && config.disposition == RewardDisposition.Retain) return 0;
        // Justification: processAmount == 0 checks if there is any new reward to process.
        // slither-disable-next-line incorrect-equality
        if (processAmount == 0) return super._processRewardToken(token);

        if (processAmount < config.minHarvestAmount) {
            emit CoreRewardDeferred(token, processAmount, config.minHarvestAmount);
            return 0;
        }

        if (config.disposition == RewardDisposition.Ignore) {
            emit CoreRewardSkipped(token, processAmount, config.disposition);
            return 0;
        }

        if (config.disposition == RewardDisposition.Sell) {
            // Justification: Reentrancy is prevented because harvest() is protected by nonReentrant.
            // slither-disable-next-line reentrancy-benign,reentrancy-events
            assetGain = _sellReward(token, amount, config.adapter);
            emit CoreRewardSold(token, amount, assetGain);
            return assetGain;
        }

        if (config.disposition != RewardDisposition.Retain) revert InvalidRange(0, uint256(config.disposition), 2);

        _retainReward(token, config);
    }

    /// @dev Frees deployed INDEX first, then liquidates retained assets only if INDEX remains insufficient.
    /// TODO(PHASE-12-LIQUIDATION-ORDER): Replace insertion-order liquidation with the governance-approved liquidation
    /// order once the architecture defines its storage and update rules.
    // Justification: Reentrancy is prevented because withdraw/redeem are protected by nonReentrant in the vault,
    // and freeFunds is only callable by the vault and protected by nonReentrant in StrategyBase.
    // slither-disable-next-line reentrancy-no-eth,reentrancy-benign,reentrancy-events
    function _freeFunds(uint256 amount) internal override returns (uint256 loss) {
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        loss = super._freeFunds(amount);

        uint256 available = IERC20(asset()).balanceOf(address(this));
        if (available >= amount) return loss;

        uint256 remaining = amount - available;
        address[] memory tokens = _retainedTokens;
        // Justification: Bounded loop of retained tokens is safe.
        // slither-disable-next-line calls-loop
        for (uint256 i; i < tokens.length && remaining != 0; ++i) {
            address token = tokens[i];
            uint256 retained = retainedBalance[token];
            // Justification: retained == 0 check is an early return check.
            // slither-disable-next-line incorrect-equality
            if (retained == 0) continue;

            RewardTokenConfig memory config = rewardRegistry.getRewardTokenConfig(token);
            uint256 amountToSell = _tokenAmountForAssetValue(token, remaining);
            if (amountToSell > retained) amountToSell = retained;

            uint256 valueBefore = _valueToken(token, amountToSell);
            retainedBalance[token] = retained - amountToSell;
            uint256 amountOut = _sellReward(token, amountToSell, config.adapter);
            // Justification: valueBefore > amountOut comparison is safe.
            // slither-disable-next-line timestamp
            if (valueBefore > amountOut) loss += valueBefore - amountOut;

            uint256 newAvailable = IERC20(asset()).balanceOf(address(this));
            // Justification: remaining newAvailable comparison is safe.
            // slither-disable-next-line timestamp
            remaining = newAvailable >= amount ? 0 : amount - newAvailable;
        }

        uint256 balanceAfter = IERC20(asset()).balanceOf(address(this));
        if (balanceAfter < balanceBefore) revert RetainedAssetInvalid(address(0));
    }

    function _rewardAssets() internal view override returns (uint256 value) {
        value = _portfolioValue();
    }

    function _retainReward(address token, RewardTokenConfig memory config) private {
        if (!config.retainable || config.oracle == address(0)) revert RetainedAssetInvalid(token);
        if (config.adapter == address(0)) revert ZeroAddress();
        if (!executionRouter.isRouteApproved(config.adapter, token, asset())) {
            revert RetainedAssetRouteUnavailable(token, config.adapter);
        }
        _validateStockToken(token);

        uint256 amount = IERC20(token).balanceOf(address(this));
        uint256 value = _valueToken(token, amount);
        // Justification: value == 0 checks if the token has non-zero oracle value before retention.
        // slither-disable-next-line incorrect-equality
        if (value == 0) revert RetainedAssetInvalid(token);

        if (!isRetainedToken[token]) {
            isRetainedToken[token] = true;
            _retainedTokens.push(token);
        }
        retainedBalance[token] = amount;

        _enforceExposure(token, config, value);
        emit GrowthRewardRetained(token, config.category, amount, value);
    }

    function _validateStockToken(address token) private view {
        if (!IStockToken(token).transfersEnabled()) revert RetainedAssetTransfersPaused(token);
        // Justification: corporateActionMultiplier is called to verify target stock token conforms to interface.
        // slither-disable-next-line unused-return
        IStockToken(token).corporateActionMultiplier();
    }

    function _enforceExposure(address token, RewardTokenConfig memory config, uint256 tokenValue) private {
        uint256 nav = totalAssets();
        uint256 tokenExposure = _exposureBps(tokenValue, nav);
        if (config.maxExposureBps != 0 && tokenExposure > config.maxExposureBps) {
            revert ExposureLimitExceeded(bytes32(uint256(uint160(token))), tokenExposure, config.maxExposureBps);
        }
        if (tokenExposure > type(uint16).max) {
            revert ExposureLimitExceeded(bytes32(uint256(uint160(token))), tokenExposure, type(uint16).max);
        }
        // casting to uint16 is safe because tokenExposure is bounded above by type(uint16).max immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        _setTokenExposure(token, uint16(tokenExposure));

        (, uint256 categoryExposureBps_) = categoryExposure(config.category);
        CategoryPolicy memory policy = categoryPolicies[config.category];
        if (policy.maxPortfolioBps != 0 && categoryExposureBps_ > policy.maxPortfolioBps) {
            revert ExposureLimitExceeded(
                bytes32(uint256(uint8(config.category))), categoryExposureBps_, policy.maxPortfolioBps
            );
        }
    }

    function _portfolioValue() private view returns (uint256 value) {
        address[] memory tokens = _retainedTokens;
        // Justification: Bounded loop of retained tokens is safe.
        // slither-disable-next-line calls-loop
        for (uint256 i; i < tokens.length; ++i) {
            value += _valueToken(tokens[i], retainedBalance[tokens[i]]);
        }
    }

    function _categoryValue(RewardCategory category) private view returns (uint256 value) {
        address[] memory tokens = _retainedTokens;
        // Justification: Bounded loop of retained tokens is safe.
        // slither-disable-next-line calls-loop
        for (uint256 i; i < tokens.length; ++i) {
            RewardTokenConfig memory config = rewardRegistry.getRewardTokenConfig(tokens[i]);
            if (config.enabled && config.category == category) {
                value += _valueToken(tokens[i], retainedBalance[tokens[i]]);
            }
        }
    }

    function _valueToken(address token, uint256 amount) private view returns (uint256 value) {
        // Justification: amount == 0 check is an early return check.
        // slither-disable-next-line incorrect-equality
        if (amount == 0) return 0;
        // Justification: updatedAt is validated inside the OracleRegistry; the strategy does not re-check it.
        // slither-disable-next-line unused-return
        (uint256 priceIn,) = oracleRegistry.getValidatedPrice(token);
        // Justification: updatedAt is validated inside the OracleRegistry; the strategy does not re-check it.
        // slither-disable-next-line unused-return
        (uint256 priceOut,) = oracleRegistry.getValidatedPrice(asset());
        uint8 decimalsIn = IERC20Metadata(token).decimals();
        uint8 decimalsOut = IERC20Metadata(asset()).decimals();
        value = amount.mulDiv(priceIn, priceOut).mulDiv(10 ** decimalsOut, 10 ** decimalsIn);
    }

    function _tokenAmountForAssetValue(address token, uint256 assetValue) private view returns (uint256 amount) {
        // Justification: assetValue == 0 check is an early return check.
        // slither-disable-next-line incorrect-equality
        if (assetValue == 0) return 0;
        // Justification: updatedAt is validated inside the OracleRegistry; the strategy does not re-check it.
        // slither-disable-next-line unused-return
        (uint256 priceIn,) = oracleRegistry.getValidatedPrice(token);
        // Justification: updatedAt is validated inside the OracleRegistry; the strategy does not re-check it.
        // slither-disable-next-line unused-return
        (uint256 priceOut,) = oracleRegistry.getValidatedPrice(asset());
        uint8 decimalsIn = IERC20Metadata(token).decimals();
        uint8 decimalsOut = IERC20Metadata(asset()).decimals();
        amount = assetValue.mulDiv(priceOut, priceIn, Math.Rounding.Ceil).mulDiv(
            10 ** decimalsIn, 10 ** decimalsOut, Math.Rounding.Ceil
        );
    }

    function _exposureBps(uint256 value, uint256 nav) private pure returns (uint256 exposureBps) {
        // Justification: value == 0 check is an early return check.
        // slither-disable-next-line incorrect-equality
        if (value == 0) return 0;
        // Justification: nav == 0 check prevents division by zero.
        // slither-disable-next-line incorrect-equality
        if (nav == 0) return type(uint256).max;
        exposureBps = value.mulDiv(Constants.BPS, nav, Math.Rounding.Ceil);
    }
}
