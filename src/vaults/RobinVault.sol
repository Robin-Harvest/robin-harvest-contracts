// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../libraries/Constants.sol";
import {Events} from "../libraries/Events.sol";
import {
    InvalidAccounting,
    InvalidBasisPoints,
    InvalidLifecycleState,
    LossExceedsMaximum,
    ZeroAddress
} from "../libraries/Errors.sol";
import {IRobinStrategy} from "../interfaces/IRobinStrategy.sol";
import {IInKindRedemptionStrategy} from "../interfaces/IInKindRedemptionStrategy.sol";
import {IRobinVaultReport} from "../interfaces/IRobinVaultReport.sol";
import {HarvestReport, InKindRedemptionResult, LifecycleState} from "../types/ProtocolTypes.sol";
import {ERC4626Paris} from "./ERC4626Paris.sol";

/// @title Robin Harvest ERC-4626 Vault
/// @notice Standards-based vault accounting with one strategy, explicit debt, idle liquidity, and smooth profit unlocks.
/// @dev Security notes:
/// - Share conversion delegates to OpenZeppelin ERC-4626 and uses a positive decimals offset for virtual shares.
/// - `totalAssets()` excludes still-locked profit, reducing harvest sandwich incentives.
/// - Strategy withdrawals are bounded by caller-selected or governance-default max loss.
/// - In-kind redemption is intentionally only a reserved hook until the later Growth phases.
contract RobinVault is ERC4626Paris, AccessManaged, ReentrancyGuard, Events, IRobinVaultReport {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public constant DEFAULT_PROFIT_MAX_UNLOCK_TIME = 7 days;
    uint8 private constant DECIMALS_OFFSET = 6;

    /// @notice Current lifecycle gate for deposits, deployments, and emergency behavior.
    LifecycleState public lifecycleState;

    /// @notice Sole strategy allowed to receive assets in V1.
    IRobinStrategy public strategy;

    /// @notice Asset-denominated value assigned to the active strategy.
    uint256 public strategyDebt;

    /// @notice Maximum total managed assets accepted by the vault.
    uint256 public depositCap;

    /// @notice Desired idle liquidity as a percentage of total assets.
    uint16 public idleBufferBps;

    /// @notice Governance default max loss used by standard ERC-4626 withdrawals.
    uint16 public defaultMaxLossBps;

    /// @notice Profit still excluded from `totalAssets()` for smoothing.
    uint256 public lockedProfit;

    /// @notice Last timestamp used to age the locked-profit balance.
    uint256 public lastProfitUpdate;

    /// @notice Linear unlock duration for reported profits.
    uint256 public profitMaxUnlockTime;

    /// @notice Configurable INDEX eligibility threshold, expressed in vault assets.
    uint256 public eligibilityThreshold;

    /// @notice Optional minimum total assets required after user withdrawals.
    uint256 public minPostWithdrawAssets;

    event StrategyUpdated(address indexed previousStrategy, address indexed newStrategy);
    event StrategyDebtUpdated(address indexed strategy, uint256 previousDebt, uint256 newDebt);
    event DepositCapUpdated(uint256 previousCap, uint256 newCap);
    event IdleBufferUpdated(uint16 previousBufferBps, uint16 newBufferBps);
    event DefaultMaxLossUpdated(uint16 previousMaxLossBps, uint16 newMaxLossBps);
    event ProfitUnlockUpdated(uint256 previousDuration, uint256 newDuration);
    event InKindRedeem(
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 indexPaid,
        address[] retainedTokens,
        uint256[] retainedAmounts
    );

    error CapExceeded(uint256 assetsAfterDeposit, uint256 cap);
    error InKindRedemptionNotSupported(address strategy_);
    error InKindRedemptionMismatch();
    error ZeroShares();
    error StrategyAlreadySet();
    error StrategyMismatch();
    error WithdrawWouldBreakEligibility(uint256 assetsAfterWithdraw, uint256 minimum);

    constructor(IERC20 asset_, string memory name_, string memory symbol_, address authority_)
        ERC4626Paris(asset_, name_, symbol_)
        AccessManaged(authority_)
    {
        if (address(asset_) == address(0) || authority_ == address(0)) revert ZeroAddress();
        lifecycleState = LifecycleState.Active;
        depositCap = type(uint256).max;
        defaultMaxLossBps = 50;
        profitMaxUnlockTime = DEFAULT_PROFIT_MAX_UNLOCK_TIME;
        lastProfitUpdate = block.timestamp;
    }

    /// @notice Returns total managed assets, excluding still-locked profit.
    // Justification: block.timestamp is used via _lockedProfitRemaining() to calculate linear profit unlocking.
    // Minor timestamp variations are negligible over multi-day profit unlocking windows.
    // slither-disable-next-line timestamp
    function totalAssets() public view override returns (uint256) {
        uint256 grossAssets = IERC20(asset()).balanceOf(address(this)) + strategyDebt;
        uint256 remainingLockedProfit = _lockedProfitRemaining();
        return grossAssets > remainingLockedProfit ? grossAssets - remainingLockedProfit : 0;
    }

    // Justification: Calls totalAssets() which uses block.timestamp to dynamically compute remaining locked profit.
    // slither-disable-next-line timestamp
    function maxDeposit(address) public view override returns (uint256) {
        if (lifecycleState != LifecycleState.Active) return 0;
        uint256 managedAssets = totalAssets();
        if (managedAssets >= depositCap) return 0;
        return depositCap - managedAssets;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        return previewDeposit(maxDeposit(receiver));
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        shares = super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        assets = super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        shares = _withdrawWithMaxLoss(assets, receiver, owner, defaultMaxLossBps);
    }

    /// @notice Withdraws assets using a caller-selected max loss bound.
    function withdraw(uint256 assets, address receiver, address owner, uint16 maxLossBps)
        external
        nonReentrant
        returns (uint256 shares)
    {
        shares = _withdrawWithMaxLoss(assets, receiver, owner, maxLossBps);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        assets = _redeemWithMaxLoss(shares, receiver, owner, defaultMaxLossBps);
    }

    /// @notice Redeems shares using a caller-selected max loss bound.
    function redeem(uint256 shares, address receiver, address owner, uint16 maxLossBps)
        external
        nonReentrant
        returns (uint256 assets)
    {
        assets = _redeemWithMaxLoss(shares, receiver, owner, maxLossBps);
    }

    /// @notice Previews the optional proportional INDEX and retained-stock payout for Growth vault shares.
    /// @dev Every amount uses floor rounding against the current share supply, so previews never overstate a payout.
    // Justification: uses shares == supply comparison to handle full redemption, and checks if supply is non-zero.
    // Both variables can be tainted by block.timestamp (via strategyDebt or lockedProfit).
    // slither-disable-next-line incorrect-equality,timestamp
    function previewInKindRedeem(uint256 shares) external view returns (InKindRedemptionResult memory result) {
        IInKindRedemptionStrategy inKindStrategy = _inKindStrategy();
        result = inKindStrategy.previewInKindRedemption(shares);
        uint256 supply = totalSupply();
        if (shares == supply) {
            result.indexPaid += IERC20(asset()).balanceOf(address(this));
        } else if (supply != 0) {
            result.indexPaid += IERC20(asset()).balanceOf(address(this)).mulDiv(shares, supply);
        }
    }

    /// @notice Redeems shares for proportional INDEX and GrowthStrategy retained assets without liquidating stocks.
    /// @dev This explicit non-ERC-4626 extension burns shares before external transfers. The vault remains asset-agnostic:
    ///      only the strategy selects, accounts for, and transfers retained stock tokens.
    // Justification: uses shares == supplyBefore comparison to handle full redemption.
    // MaxRedeem comparison depends on totalAssets (tainted by block.timestamp).
    // slither-disable-next-line incorrect-equality,timestamp
    function redeemInKind(uint256 shares, address receiver, address owner)
        external
        nonReentrant
        returns (InKindRedemptionResult memory result)
    {
        if (shares == 0) revert ZeroShares();
        if (receiver == address(0)) revert ZeroAddress();
        if (shares > maxRedeem(owner)) revert ERC4626ExceededMaxRedeem(owner, shares, maxRedeem(owner));

        IInKindRedemptionStrategy inKindStrategy = _inKindStrategy();
        uint256 supplyBefore = totalSupply();
        uint256 vaultIndexBefore = IERC20(asset()).balanceOf(address(this));
        uint256 debtBefore = strategyDebt;
        uint256 lockedProfitBefore = lockedProfit;
        InKindRedemptionResult memory preview = inKindStrategy.previewInKindRedemption(shares);

        uint256 debtReduction = shares == supplyBefore ? debtBefore : debtBefore.mulDiv(shares, supplyBefore);
        if (preview.debtReduction != debtReduction) revert InKindRedemptionMismatch();
        uint256 vaultIndexPaid =
            shares == supplyBefore ? vaultIndexBefore : vaultIndexBefore.mulDiv(shares, supplyBefore);

        if (_msgSender() != owner) _spendAllowance(owner, _msgSender(), shares);
        _burn(owner, shares);
        strategyDebt = debtBefore - debtReduction;
        lockedProfit = shares == supplyBefore ? 0 : lockedProfitBefore - lockedProfitBefore.mulDiv(shares, supplyBefore);
        lastProfitUpdate = block.timestamp;
        emit StrategyDebtUpdated(address(strategy), debtBefore, strategyDebt);

        InKindRedemptionResult memory strategyResult = inKindStrategy.redeemInKind(shares, debtReduction, receiver);
        if (!_sameInKindResult(preview, strategyResult)) revert InKindRedemptionMismatch();

        if (vaultIndexPaid != 0) IERC20(asset()).safeTransfer(receiver, vaultIndexPaid);
        result = strategyResult;
        result.indexPaid += vaultIndexPaid;
        emit InKindRedeem(owner, receiver, shares, result.indexPaid, result.retainedTokens, result.retainedAmounts);
        _enforcePostWithdrawEligibility();
    }

    /// @notice Installs the sole strategy for this V1 vault.
    // Justification: Checks strategyDebt, which can be tainted by block.timestamp via profit reports.
    // However, this comparison does not rely on or check time.
    // slither-disable-next-line timestamp
    function setStrategy(address newStrategy) external restricted {
        if (newStrategy == address(0)) revert ZeroAddress();
        if (address(strategy) != address(0) && strategyDebt != 0) revert StrategyAlreadySet();
        if (IRobinStrategy(newStrategy).vault() != address(this) || IRobinStrategy(newStrategy).asset() != asset()) {
            revert StrategyMismatch();
        }
        address previousStrategy = address(strategy);
        strategy = IRobinStrategy(newStrategy);
        emit StrategyUpdated(previousStrategy, newStrategy);
    }

    function setDepositCap(uint256 newCap) external restricted {
        emit DepositCapUpdated(depositCap, newCap);
        depositCap = newCap;
    }

    function setIdleBufferBps(uint16 newBufferBps) external restricted {
        if (newBufferBps > Constants.MAX_BPS) revert InvalidBasisPoints(newBufferBps);
        emit IdleBufferUpdated(idleBufferBps, newBufferBps);
        idleBufferBps = newBufferBps;
    }

    function setDefaultMaxLossBps(uint16 newMaxLossBps) external restricted {
        if (newMaxLossBps > Constants.MAX_BPS) revert InvalidBasisPoints(newMaxLossBps);
        emit DefaultMaxLossUpdated(defaultMaxLossBps, newMaxLossBps);
        defaultMaxLossBps = newMaxLossBps;
    }

    function setProfitMaxUnlockTime(uint256 newDuration) external restricted {
        _syncLockedProfit();
        emit ProfitUnlockUpdated(profitMaxUnlockTime, newDuration);
        profitMaxUnlockTime = newDuration;
    }

    function setEligibilityThreshold(uint256 newThreshold) external restricted {
        emit EligibilityThresholdUpdated(eligibilityThreshold, newThreshold);
        eligibilityThreshold = newThreshold;
    }

    function setMinPostWithdrawAssets(uint256 newMinimum) external restricted {
        minPostWithdrawAssets = newMinimum;
    }

    function pause() external restricted {
        _setLifecycleState(LifecycleState.Paused);
    }

    function unpause() external restricted {
        if (lifecycleState == LifecycleState.Shutdown) revert InvalidLifecycleState(uint8(lifecycleState));
        _setLifecycleState(LifecycleState.Active);
    }

    function shutdown() external restricted {
        _setLifecycleState(LifecycleState.Shutdown);
    }

    /// @notice Deploys idle assets to the single strategy while preserving the configured buffer.
    // Justification: `deployed` is computed via `_deployableIdle()`, which relies on `totalAssets()`,
    // which in turn is tainted by block.timestamp. The check `deployed != 0` is not a time dependency.
    // slither-disable-next-line timestamp
    function deployIdle() external restricted nonReentrant returns (uint256 deployed) {
        deployed = _deployableIdle();
        if (deployed != 0) _deployToStrategy(deployed);
    }

    /// @notice Deploys an explicit asset amount to the single strategy.
    function deploy(uint256 assets) external restricted nonReentrant {
        _deployToStrategy(assets);
    }

    /// @notice Called by the strategy after harvest accounting is known.
    function report(HarvestReport calldata report_) external nonReentrant {
        if (msg.sender != address(strategy)) revert StrategyMismatch();
        _syncLockedProfit();

        uint256 previousDebt = strategyDebt;
        uint256 debtReduction = report_.loss + report_.debtPayment;
        if (debtReduction > previousDebt) revert InvalidAccounting();

        uint256 newDebt = previousDebt + report_.gain - debtReduction;
        strategyDebt = newDebt;
        lockedProfit += report_.gain;
        lastProfitUpdate = block.timestamp;

        emit StrategyReported(msg.sender, report_.gain, report_.loss, report_.debtPayment);
        emit StrategyDebtUpdated(msg.sender, previousDebt, newDebt);
    }

    // Justification: qualifyingBalance uses totalAssets() which is tainted by block.timestamp.
    // The comparison against threshold is not dependent on block.timestamp manipulation.
    // slither-disable-next-line timestamp
    function isEligible() public view returns (bool eligible, uint256 qualifyingBalance, uint256 threshold) {
        qualifyingBalance = totalAssets();
        threshold = eligibilityThreshold;
        eligible = threshold == 0 || qualifyingBalance >= threshold;
    }

    // Justification: uses maxWithdraw() which relies on totalAssets() (tainted by block.timestamp).
    // slither-disable-next-line timestamp
    function _withdrawWithMaxLoss(uint256 assets, address receiver, address owner, uint16 maxLossBps)
        private
        returns (uint256 shares)
    {
        if (assets > maxWithdraw(owner)) revert ERC4626ExceededMaxWithdraw(owner, assets, maxWithdraw(owner));
        shares = previewWithdraw(assets);
        _withdrawWithLossBound(_msgSender(), receiver, owner, assets, shares, maxLossBps);
    }

    // Justification: uses maxRedeem() which relies on totalAssets() (tainted by block.timestamp).
    // slither-disable-next-line timestamp
    function _redeemWithMaxLoss(uint256 shares, address receiver, address owner, uint16 maxLossBps)
        private
        returns (uint256 assets)
    {
        if (shares > maxRedeem(owner)) revert ERC4626ExceededMaxRedeem(owner, shares, maxRedeem(owner));
        assets = previewRedeem(shares);
        _withdrawWithLossBound(_msgSender(), receiver, owner, assets, shares, maxLossBps);
    }

    function _withdrawWithLossBound(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint16 maxLossBps
    ) private {
        if (maxLossBps > Constants.MAX_BPS) revert InvalidBasisPoints(maxLossBps);
        _ensureLiquidity(assets, maxLossBps);
        super._withdraw(caller, receiver, owner, assets, shares);
        _enforcePostWithdrawEligibility();
    }

    // Justification: Tainted by strategyDebt. But it does not rely on or check time.
    // slither-disable-next-line timestamp
    function _deployToStrategy(uint256 assets) private {
        if (lifecycleState != LifecycleState.Active) revert InvalidLifecycleState(uint8(lifecycleState));
        IRobinStrategy currentStrategy = strategy;
        if (address(currentStrategy) == address(0)) revert ZeroAddress();
        // Justification: assets == 0 is checking a parameter input, not a state variable, to return early.
        // slither-disable-next-line incorrect-equality
        if (assets == 0) return;

        uint256 previousDebt = strategyDebt;
        strategyDebt = previousDebt + assets;
        emit StrategyDebtUpdated(address(currentStrategy), previousDebt, strategyDebt);

        IERC20(asset()).safeTransfer(address(currentStrategy), assets);
        currentStrategy.deployFunds(assets);
    }

    // Justification: Tainted by strategyDebt. But it does not rely on or check time.
    // slither-disable-next-line timestamp
    function _ensureLiquidity(uint256 assets, uint16 maxLossBps) private {
        IERC20 assetToken = IERC20(asset());
        uint256 idle = assetToken.balanceOf(address(this));
        if (idle >= assets) return;

        IRobinStrategy currentStrategy = strategy;
        if (address(currentStrategy) == address(0)) revert InvalidAccounting();

        uint256 shortfall = assets - idle;
        uint256 balanceBefore = idle;
        // Justification: CEI cannot be applied here because the state update (strategyDebt reduction) depends
        // on the `amountFreed` and `loss` returned by the external `freeFunds` call.
        // Reentrancy is prevented because all user-facing functions calling this internal method (withdraw, redeem)
        // are protected by the `nonReentrant` modifier.
        // slither-disable-next-line reentrancy-no-eth,reentrancy-benign,reentrancy-balance
        (uint256 amountFreed, uint256 loss) = currentStrategy.freeFunds(shortfall);

        uint256 lossDenominator = amountFreed + loss;
        // Justification: lossDenominator == 0 check is necessary to prevent division by zero.
        // slither-disable-next-line incorrect-equality
        uint256 lossBps = lossDenominator == 0 ? 0 : loss.mulDiv(Constants.BPS, lossDenominator, Math.Rounding.Ceil);
        if (lossBps > maxLossBps) revert LossExceedsMaximum(lossBps, maxLossBps);

        uint256 balanceAfter = assetToken.balanceOf(address(this));
        if (balanceAfter < balanceBefore + amountFreed) revert InvalidAccounting();

        uint256 debtReduction = amountFreed + loss;
        if (debtReduction > strategyDebt) revert InvalidAccounting();
        uint256 previousDebt = strategyDebt;
        strategyDebt = previousDebt - debtReduction;
        emit StrategyDebtUpdated(address(currentStrategy), previousDebt, strategyDebt);

        if (balanceAfter < assets) revert InvalidAccounting();
    }

    // Justification: Calls totalAssets() which is tainted by block.timestamp.
    // slither-disable-next-line timestamp
    function _deployableIdle() private view returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 targetIdle = totalAssets().mulDiv(idleBufferBps, Constants.BPS);
        return idle > targetIdle ? idle - targetIdle : 0;
    }

    function _inKindStrategy() private view returns (IInKindRedemptionStrategy inKindStrategy) {
        address strategyAddress = address(strategy);
        if (strategyAddress == address(0)) revert InKindRedemptionNotSupported(strategyAddress);
        inKindStrategy = IInKindRedemptionStrategy(strategyAddress);
    }

    // Justification: Compares values that could be tainted by block.timestamp.
    // slither-disable-next-line timestamp
    function _sameInKindResult(InKindRedemptionResult memory expected, InKindRedemptionResult memory actual)
        private
        pure
        returns (bool)
    {
        if (
            expected.debtReduction != actual.debtReduction || expected.indexPaid != actual.indexPaid
                || expected.retainedTokens.length != actual.retainedTokens.length
                || expected.retainedAmounts.length != actual.retainedAmounts.length
        ) return false;

        for (uint256 i; i < expected.retainedTokens.length; ++i) {
            if (
                expected.retainedTokens[i] != actual.retainedTokens[i]
                    || expected.retainedAmounts[i] != actual.retainedAmounts[i]
            ) return false;
        }
        return true;
    }

    function _lockedProfitRemaining() private view returns (uint256) {
        // Justification: lockedProfit == 0 is checking status flag to return early.
        // slither-disable-next-line incorrect-equality
        if (lockedProfit == 0) return 0;
        uint256 duration = profitMaxUnlockTime;
        // Justification: Linear profit unlock is time-dependent by design.
        // slither-disable-next-line timestamp
        if (duration == 0 || block.timestamp >= lastProfitUpdate + duration) return 0;
        uint256 elapsed = block.timestamp - lastProfitUpdate;
        return lockedProfit - lockedProfit.mulDiv(elapsed, duration);
    }

    function _syncLockedProfit() private {
        lockedProfit = _lockedProfitRemaining();
        lastProfitUpdate = block.timestamp;
    }

    // Justification: assetsAfterWithdraw uses totalAssets() which is tainted by block.timestamp.
    // slither-disable-next-line timestamp
    function _enforcePostWithdrawEligibility() private view {
        uint256 minimum = minPostWithdrawAssets;
        if (minimum == 0) return;
        uint256 assetsAfterWithdraw = totalAssets();
        if (assetsAfterWithdraw < minimum) revert WithdrawWouldBreakEligibility(assetsAfterWithdraw, minimum);
    }

    function _setLifecycleState(LifecycleState newState) private {
        LifecycleState previousState = lifecycleState;
        if (previousState == LifecycleState.Shutdown && newState != LifecycleState.Shutdown) {
            revert InvalidLifecycleState(uint8(previousState));
        }
        lifecycleState = newState;
        emit LifecycleStateChanged(previousState, newState);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return DECIMALS_OFFSET;
    }
}
