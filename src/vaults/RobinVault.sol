// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../libraries/Constants.sol";
import {Events} from "../libraries/Events.sol";
import {InvalidAccounting, InvalidBasisPoints, InvalidLifecycleState, LossExceedsMaximum, ZeroAddress} from "../libraries/Errors.sol";
import {IRobinStrategy} from "../interfaces/IRobinStrategy.sol";
import {HarvestReport, LifecycleState} from "../types/ProtocolTypes.sol";
import {ERC4626Paris} from "./ERC4626Paris.sol";

/// @title Robin Harvest ERC-4626 Vault
/// @notice Standards-based vault accounting with one strategy, explicit debt, idle liquidity, and smooth profit unlocks.
/// @dev Security notes:
/// - Share conversion delegates to OpenZeppelin ERC-4626 and uses a positive decimals offset for virtual shares.
/// - `totalAssets()` excludes still-locked profit, reducing harvest sandwich incentives.
/// - Strategy withdrawals are bounded by caller-selected or governance-default max loss.
/// - In-kind redemption is intentionally only a reserved hook until the later Growth phases.
contract RobinVault is ERC4626Paris, AccessManaged, ReentrancyGuard, Events {
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
    event InKindRedemptionRequested(address indexed owner, address indexed receiver, uint256 shares);

    error CapExceeded(uint256 assetsAfterDeposit, uint256 cap);
    error InKindRedemptionNotImplemented();
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
    function totalAssets() public view override returns (uint256) {
        uint256 grossAssets = IERC20(asset()).balanceOf(address(this)) + strategyDebt;
        uint256 remainingLockedProfit = _lockedProfitRemaining();
        return grossAssets > remainingLockedProfit ? grossAssets - remainingLockedProfit : 0;
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (lifecycleState != LifecycleState.Active) return 0;
        uint256 managedAssets = totalAssets();
        if (managedAssets >= depositCap) return 0;
        return depositCap - managedAssets;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        return previewDeposit(maxDeposit(receiver));
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
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

    /// @notice Reserved non-standard redemption surface for a later Growth implementation.
    function previewInKindRedeem(uint256) external pure returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](0);
        amounts = new uint256[](0);
    }

    /// @notice Reserved non-standard redemption surface for a later Growth implementation.
    function redeemInKind(uint256 shares, address receiver, address owner)
        external
        returns (address[] memory, uint256[] memory)
    {
        emit InKindRedemptionRequested(owner, receiver, shares);
        revert InKindRedemptionNotImplemented();
    }

    /// @notice Installs the sole strategy for this V1 vault.
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

    function isEligible() public view returns (bool eligible, uint256 qualifyingBalance, uint256 threshold) {
        qualifyingBalance = totalAssets();
        threshold = eligibilityThreshold;
        eligible = threshold == 0 || qualifyingBalance >= threshold;
    }

    function _withdrawWithMaxLoss(uint256 assets, address receiver, address owner, uint16 maxLossBps)
        private
        returns (uint256 shares)
    {
        if (assets > maxWithdraw(owner)) revert ERC4626ExceededMaxWithdraw(owner, assets, maxWithdraw(owner));
        shares = previewWithdraw(assets);
        _withdrawWithLossBound(_msgSender(), receiver, owner, assets, shares, maxLossBps);
    }

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

    function _deployToStrategy(uint256 assets) private {
        if (lifecycleState != LifecycleState.Active) revert InvalidLifecycleState(uint8(lifecycleState));
        IRobinStrategy currentStrategy = strategy;
        if (address(currentStrategy) == address(0)) revert ZeroAddress();
        if (assets == 0) return;

        uint256 previousDebt = strategyDebt;
        IERC20(asset()).safeTransfer(address(currentStrategy), assets);
        currentStrategy.deployFunds(assets);
        strategyDebt = previousDebt + assets;
        emit StrategyDebtUpdated(address(currentStrategy), previousDebt, strategyDebt);
    }

    function _ensureLiquidity(uint256 assets, uint16 maxLossBps) private {
        IERC20 assetToken = IERC20(asset());
        uint256 idle = assetToken.balanceOf(address(this));
        if (idle >= assets) return;

        IRobinStrategy currentStrategy = strategy;
        if (address(currentStrategy) == address(0)) revert InvalidAccounting();

        uint256 shortfall = assets - idle;
        uint256 balanceBefore = idle;
        (uint256 amountFreed, uint256 loss) = currentStrategy.freeFunds(shortfall);

        uint256 lossDenominator = amountFreed + loss;
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

    function _deployableIdle() private view returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 targetIdle = totalAssets().mulDiv(idleBufferBps, Constants.BPS);
        return idle > targetIdle ? idle - targetIdle : 0;
    }

    function _lockedProfitRemaining() private view returns (uint256) {
        if (lockedProfit == 0) return 0;
        uint256 duration = profitMaxUnlockTime;
        if (duration == 0 || block.timestamp >= lastProfitUpdate + duration) return 0;
        uint256 elapsed = block.timestamp - lastProfitUpdate;
        return lockedProfit - lockedProfit.mulDiv(elapsed, duration);
    }

    function _syncLockedProfit() private {
        lockedProfit = _lockedProfitRemaining();
        lastProfitUpdate = block.timestamp;
    }

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
