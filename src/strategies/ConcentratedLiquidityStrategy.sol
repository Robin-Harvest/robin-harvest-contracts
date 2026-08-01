// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Constants} from "../libraries/Constants.sol";
import {ClActionPlanner} from "../libraries/ClActionPlanner.sol";
import {PoolPriceLib} from "../libraries/PoolPriceLib.sol";
import {TickValidationLib} from "../libraries/TickValidationLib.sol";
import {
    ActivePositionsRemain,
    ActivePositionLimitExceeded,
    GovernanceBlockedWhilePaused,
    HardOracleFailure,
    InsufficientOutput,
    InvalidBasisPoints,
    InvalidStrategyMode,
    LossExceedsMaximum,
    NotApproved,
    UnknownPosition,
    V4AmountOverflow,
    WithdrawSafetyFailure,
    ZeroAddress,
    ZeroAmount
} from "../libraries/Errors.sol";
import {IConcentratedLiquidityStrategy} from "../interfaces/IConcentratedLiquidityStrategy.sol";
import {IExecutionRouter} from "../interfaces/IExecutionRouter.sol";
import {IOracleRegistry} from "../interfaces/IOracleRegistry.sol";
import {IRebalancePolicy} from "../interfaces/IRebalancePolicy.sol";
import {StrategyBase} from "./StrategyBase.sol";
import {ManagedPosition, PriceObservation, StrategyMode} from "../types/ClStrategyTypes.sol";
import {SwapRequest} from "../types/ProtocolTypes.sol";

/// @dev Official PositionManager implementations expose the Permit2 dependency through this public getter.
interface IPositionManagerPermit2 {
    function permit2() external view returns (address);
}

/// @title Robin Harvest Uniswap v4 Concentrated Liquidity Strategy
/// @notice Single-pool, hookless v4 allocator for one RobinVault ERC-4626 product.
/// @dev User ownership remains exclusively in vault shares. This contract never sends assets anywhere except `vault`.
contract ConcentratedLiquidityStrategy is StrategyBase, IConcentratedLiquidityStrategy {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using Math for uint256;

    /// @notice Maximum active positions in V1. One active NFT keeps accounting and emergency operations minimal.
    uint256 public constant MAX_ACTIVE_POSITIONS = 1;

    /// @notice Default internal TWAP observation window in seconds.
    uint32 public constant DEFAULT_TWAP_WINDOW = 30 minutes;

    uint256 private constant OBSERVATION_LIMIT = 64;

    IPoolManager private immutable _poolManager;
    IPositionManager private immutable _positionManager;
    IExecutionRouter private immutable _executionRouter;
    IOracleRegistry private immutable _oracleRegistry;
    PoolKey private _poolKey;
    uint32 public immutable override twapWindow;

    IRebalancePolicy public override policy;
    StrategyMode public override mode;
    uint16 public override maxSlippageBps;
    uint16 public override maxLossBps;
    /// @notice Maximum relative sqrt-price deviation for oracle/spot/TWAP checks, in basis points.
    uint16 public override oracleSqrtPriceDeviationBps;
    /// @notice Maximum relative sqrt-price deviation between spot and TWAP during withdrawals, in basis points.
    uint16 public override maxWithdrawSqrtPriceDeviationBps;
    bool public override autoCompound;

    address public swapAdapter;

    mapping(uint256 => ManagedPosition) private _positions;
    uint256 private _activeTokenId;
    PriceObservation[] private _observations;

    event PositionOpened(
        uint256 indexed tokenId, int24 lower, int24 upper, uint128 liquidity, uint256 amount0, uint256 amount1
    );
    event PositionClosed(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event Rebalanced(
        uint256 indexed oldTokenId,
        uint256 indexed newTokenId,
        int24 oldLower,
        int24 oldUpper,
        int24 newLower,
        int24 newUpper,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event Harvested(uint256 amount0, uint256 amount1, bool compounded);
    event EmergencyRescueTriggered(uint256 amount0, uint256 amount1, address indexed vault);
    event StrategyModeUpdated(StrategyMode indexed previousMode, StrategyMode indexed newMode);
    event PolicyUpdated(address indexed previousPolicy, address indexed newPolicy);
    event RiskParametersUpdated(
        uint16 maxSlippageBps,
        uint16 maxLossBps,
        uint16 oracleSqrtPriceDeviationBps,
        uint16 maxWithdrawSqrtPriceDeviationBps
    );
    event AutoCompoundUpdated(bool enabled);
    event SwapRouteUpdated(address indexed adapter);

    error PoolKeyMismatch();
    error UnsupportedNativeCurrency();
    error NoLiquidity();
    error RouteNotConfigured();

    constructor(
        address vault_,
        IERC20 asset_,
        address authority_,
        IPoolManager poolManager_,
        IPositionManager positionManager_,
        PoolKey memory poolKey_,
        IExecutionRouter executionRouter_,
        IOracleRegistry oracleRegistry_,
        IRebalancePolicy policy_
    ) StrategyBase(vault_, asset_, authority_) {
        if (
            address(poolManager_) == address(0) || address(positionManager_) == address(0)
                || address(executionRouter_) == address(0) || address(oracleRegistry_) == address(0)
                || address(policy_) == address(0)
        ) revert ZeroAddress();
        if (poolKey_.currency0.isAddressZero() || poolKey_.currency1.isAddressZero()) {
            revert UnsupportedNativeCurrency();
        }
        if (Currency.unwrap(poolKey_.currency0) >= Currency.unwrap(poolKey_.currency1)) revert PoolKeyMismatch();
        if (address(poolKey_.hooks) != address(0)) revert PoolKeyMismatch();

        address assetAddress = address(asset_);
        if (assetAddress != Currency.unwrap(poolKey_.currency0) && assetAddress != Currency.unwrap(poolKey_.currency1))
        {
            revert PoolKeyMismatch();
        }
        if (poolKey_.tickSpacing <= 0) revert PoolKeyMismatch();

        _poolManager = poolManager_;
        _positionManager = positionManager_;
        _executionRouter = executionRouter_;
        _oracleRegistry = oracleRegistry_;
        _poolKey = poolKey_;
        policy = policy_;
        twapWindow = DEFAULT_TWAP_WINDOW;
        mode = StrategyMode.Active;
        maxSlippageBps = 300;
        maxLossBps = 100;
        oracleSqrtPriceDeviationBps = 500;
        maxWithdrawSqrtPriceDeviationBps = 300;
        autoCompound = true;
    }

    function activePositionCount() external view override returns (uint256 count) {
        count = _activeTokenId == 0 ? 0 : 1;
    }

    function setPolicy(IRebalancePolicy newPolicy) external restricted {
        _requireGovernanceAllowed();
        if (address(newPolicy) == address(0)) revert ZeroAddress();
        emit PolicyUpdated(address(policy), address(newPolicy));
        policy = newPolicy;
    }

    function setRiskParameters(
        uint16 newMaxSlippageBps,
        uint16 newMaxLossBps,
        uint16 newOracleSqrtPriceDeviationBps,
        uint16 newWithdrawSqrtPriceDeviationBps
    ) external restricted {
        _requireGovernanceAllowed();
        if (
            newMaxSlippageBps > Constants.MAX_BPS || newMaxLossBps > Constants.MAX_BPS
                || newOracleSqrtPriceDeviationBps > Constants.MAX_BPS
                || newWithdrawSqrtPriceDeviationBps > Constants.MAX_BPS
        ) revert InvalidBasisPoints(type(uint256).max);
        maxSlippageBps = newMaxSlippageBps;
        maxLossBps = newMaxLossBps;
        oracleSqrtPriceDeviationBps = newOracleSqrtPriceDeviationBps;
        maxWithdrawSqrtPriceDeviationBps = newWithdrawSqrtPriceDeviationBps;
        emit RiskParametersUpdated(
            newMaxSlippageBps, newMaxLossBps, newOracleSqrtPriceDeviationBps, newWithdrawSqrtPriceDeviationBps
        );
    }

    function setAutoCompound(bool enabled) external restricted {
        _requireGovernanceAllowed();
        autoCompound = enabled;
        emit AutoCompoundUpdated(enabled);
    }

    /// @notice Sets or disables the paired-token swap adapter.
    /// @dev Passing address(0) deliberately disables swaps; non-dust conversions then revert as unconfigured.
    function setSwapRoute(address adapter) external restricted {
        _requireGovernanceAllowed();
        // Zero is the documented disable sentinel, not an invalid configuration.
        // slither-disable-next-line missing-zero-check
        swapAdapter = adapter;
        emit SwapRouteUpdated(adapter);
    }

    function pause() public override restricted {
        super.pause();
        _setMode(StrategyMode.Paused);
    }

    function unpause() public override restricted {
        super.unpause();
        _setMode(StrategyMode.Active);
    }

    function enterWithdrawOnly() external override restricted nonReentrant {
        if (mode == StrategyMode.Paused) revert InvalidStrategyMode(uint8(mode));
        _setMode(StrategyMode.WithdrawOnly);
    }

    function enterHarvestOnly() external override restricted nonReentrant {
        if (mode == StrategyMode.Paused) revert InvalidStrategyMode(uint8(mode));
        _setMode(StrategyMode.HarvestOnly);
    }

    /// @inheritdoc IConcentratedLiquidityStrategy
    function rebalance() external override restricted nonReentrant {
        if (mode != StrategyMode.Active) revert InvalidStrategyMode(uint8(mode));
        _checkHardFailure();
        _recordObservation();

        uint256 oldId = _activeTokenId;
        if (oldId == 0) return;

        int24 currentTick = PoolPriceLib.currentTick(_poolManager, _poolKey);
        ManagedPosition memory oldPosition = _positions[oldId];
        if (!policy.shouldRebalance(oldId, currentTick, oldPosition.lower, oldPosition.upper, oldPosition.liquidity)) {
            return;
        }

        (int24 lower, int24 upper) = policy.targetRange(currentTick, _poolKey.tickSpacing);
        _validateTicks(lower, upper);

        (uint256 amount0Closed, uint256 amount1Closed) = _closePosition(oldId);
        _rebalanceSwap(lower, upper);

        uint256 newId = _mintPosition(lower, upper);
        ManagedPosition memory newPosition = _positions[newId];
        (uint256 amount0Minted, uint256 amount1Minted) =
            _amountsForLiquidity(_spot(), lower, upper, newPosition.liquidity);

        emit Rebalanced(
            oldId,
            newId,
            oldPosition.lower,
            oldPosition.upper,
            lower,
            upper,
            newPosition.liquidity,
            amount0Closed + amount0Minted,
            amount1Closed + amount1Minted
        );
    }

    function emergencyClosePositions() external override restricted nonReentrant {
        if (mode != StrategyMode.Paused) revert InvalidStrategyMode(uint8(mode));
        if (_activeTokenId != 0) _closePosition(_activeTokenId);
    }

    function emergencyReturnAssetsToVault() external override restricted nonReentrant {
        if (mode != StrategyMode.Paused) revert InvalidStrategyMode(uint8(mode));
        if (_activeTokenId != 0) revert ActivePositionsRemain(1);

        (uint256 amount0, uint256 amount1) = _balances();
        if (amount0 != 0) IERC20(Currency.unwrap(_poolKey.currency0)).safeTransfer(vault, amount0);
        if (amount1 != 0) IERC20(Currency.unwrap(_poolKey.currency1)).safeTransfer(vault, amount1);
        emit EmergencyRescueTriggered(amount0, amount1, vault);
    }

    function _deployFunds(uint256 amount) internal override {
        if (mode != StrategyMode.Active) revert InvalidStrategyMode(uint8(mode));
        if (amount == 0) revert ZeroAmount();
        _checkHardFailure();
        _recordObservation();

        (int24 lower, int24 upper) =
            policy.targetRange(PoolPriceLib.currentTick(_poolManager, _poolKey), _poolKey.tickSpacing);
        _validateTicks(lower, upper);
        _prepareBalancesForRange(amount, lower, upper);
        // PositionManager and router are immutable dependencies; the vault-only entry point is nonReentrant.
        // slither-disable-next-line reentrancy-benign
        _mintPosition(lower, upper);
    }

    function _freeFunds(uint256 amount) internal override returns (uint256 loss) {
        if (mode == StrategyMode.Paused || mode == StrategyMode.HarvestOnly) {
            revert InvalidStrategyMode(uint8(mode));
        }
        if (amount == 0) return 0;

        _checkWithdrawSafety();
        _recordObservation();

        uint256 assetBefore = IERC20(asset()).balanceOf(address(this));
        if (IERC20(asset()).balanceOf(address(this)) - assetBefore < amount && _activeTokenId != 0) {
            // The entry point is nonReentrant; the baseline is intentionally retained across each close.
            // slither-disable-next-line reentrancy-balance
            _closePosition(_activeTokenId);
        }

        uint256 assetAfter = IERC20(asset()).balanceOf(address(this));
        if (assetAfter - assetBefore < amount) {
            // The entry point is nonReentrant; the baseline is intentionally retained across this conversion.
            // slither-disable-next-line reentrancy-balance
            _swapIdlePairToAsset();
            assetAfter = IERC20(asset()).balanceOf(address(this));
        }
        uint256 freed = assetAfter > assetBefore ? assetAfter - assetBefore : 0;
        if (freed < amount) loss = amount - freed;

        if (loss != 0) {
            uint256 lossBps = loss.mulDiv(Constants.BPS, amount, Math.Rounding.Ceil);
            if (lossBps > maxLossBps) revert LossExceedsMaximum(lossBps, maxLossBps);
        }
    }

    function _claimRewards() internal override {
        if (mode == StrategyMode.Paused) revert InvalidStrategyMode(uint8(mode));

        _recordObservation();
        (uint256 before0, uint256 before1) = _balances();

        uint256 tokenId = _activeTokenId;
        if (tokenId != 0) {
            bytes memory data = ClActionPlanner.planCollectFees(_poolKey, tokenId, address(this), bytes(""));
            // PositionManager is immutable and the caller is protected by StrategyBase.nonReentrant.
            // slither-disable-next-line reentrancy-no-eth
            _positionManager.modifyLiquidities(data, block.timestamp + 1 hours);
        }

        (uint256 after0, uint256 after1) = _balances();
        uint256 amount0 = after0 - before0;
        uint256 amount1 = after1 - before1;

        if (autoCompound && mode == StrategyMode.Active && tokenId != 0 && (amount0 != 0 || amount1 != 0)) {
            ManagedPosition storage position = _positions[tokenId];
            // PositionManager is immutable and the caller is protected by StrategyBase.nonReentrant.
            // slither-disable-next-line reentrancy-no-eth
            _increasePosition(tokenId, amount0, amount1);
            position.lastCompound = uint48(block.timestamp);
        }

        emit Harvested(amount0, amount1, autoCompound && mode == StrategyMode.Active && tokenId != 0);
    }

    function _processRewardToken(address) internal pure override returns (uint256) {
        return 0;
    }

    function _tend() internal override {
        if (mode != StrategyMode.Active) revert InvalidStrategyMode(uint8(mode));
        _checkHardFailure();
        _recordObservation();
    }

    function _shutdownStrategy() internal override {
        if (mode != StrategyMode.Paused) _setMode(StrategyMode.WithdrawOnly);
    }

    function _emergencyWithdraw() internal override returns (uint256 loss) {
        _checkWithdrawSafety();
        if (_activeTokenId != 0) {
            // emergencyWithdraw() is restricted and nonReentrant; mode updates only after successful closes.
            // slither-disable-next-line reentrancy-benign
            _closePosition(_activeTokenId);
        }
        _setMode(StrategyMode.Paused);
        loss = 0;
    }

    function _deployedAssets() internal view override returns (uint256 totalValue) {
        (bool healthy0, uint256 price0) = _tryGetValidatedPrice(Currency.unwrap(_poolKey.currency0));
        (bool healthy1, uint256 price1) = _tryGetValidatedPrice(Currency.unwrap(_poolKey.currency1));
        uint160 spot = _spot();
        if (!healthy0 || !healthy1 || spot == 0) return 0;

        address token0 = Currency.unwrap(_poolKey.currency0);
        address token1 = Currency.unwrap(_poolKey.currency1);
        uint256 idle0 = token0 == asset() ? 0 : IERC20(token0).balanceOf(address(this));
        uint256 idle1 = token1 == asset() ? 0 : IERC20(token1).balanceOf(address(this));
        totalValue +=
            PoolPriceLib.valueInAsset(asset(), token0, token1, idle0, idle1, price0, price1, healthy0, healthy1);

        if (_activeTokenId != 0) {
            ManagedPosition memory position = _positions[_activeTokenId];
            uint128 liquidity = _positionManager.getPositionLiquidity(position.tokenId);
            (uint256 amount0, uint256 amount1) = _amountsForLiquidity(spot, position.lower, position.upper, liquidity);
            totalValue += PoolPriceLib.valueInAsset(
                asset(),
                Currency.unwrap(_poolKey.currency0),
                Currency.unwrap(_poolKey.currency1),
                amount0,
                amount1,
                price0,
                price1,
                healthy0,
                healthy1
            );
        }
    }

    function _mintPosition(int24 lower, int24 upper) internal returns (uint256 tokenId) {
        if (_activeTokenId != 0) {
            revert ActivePositionLimitExceeded(MAX_ACTIVE_POSITIONS);
        }
        uint160 spot = _spot();
        (uint256 amount0, uint256 amount1) = _balances();
        _validateV4Amounts(amount0, amount1);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            spot, TickMath.getSqrtPriceAtTick(lower), TickMath.getSqrtPriceAtTick(upper), amount0, amount1
        );
        if (liquidity == 0) revert NoLiquidity();

        _approvePermit2(amount0, amount1);
        tokenId = _positionManager.nextTokenId();
        bytes memory data = ClActionPlanner.planMintPosition(
            _poolKey, lower, upper, liquidity, uint128(amount0), uint128(amount1), address(this), bytes("")
        );
        // PositionManager is immutable and the caller is protected by StrategyBase.nonReentrant.
        // slither-disable-next-line reentrancy-benign
        _positionManager.modifyLiquidities(data, block.timestamp + 1 hours);
        _clearPermit2Approvals();

        _positions[tokenId] = ManagedPosition({
            tokenId: tokenId,
            active: true,
            liquidity: liquidity,
            lower: lower,
            upper: upper,
            openedAt: uint48(block.timestamp),
            lastCompound: uint48(block.timestamp)
        });
        _activeTokenId = tokenId;

        (uint256 used0, uint256 used1) = _amountsForLiquidity(spot, lower, upper, liquidity);
        emit PositionOpened(tokenId, lower, upper, liquidity, used0, used1);
    }

    function _increasePosition(uint256 tokenId, uint256 amount0, uint256 amount1) internal {
        if (amount0 == 0 && amount1 == 0) return;
        _validateV4Amounts(amount0, amount1);
        ManagedPosition storage position = _positions[tokenId];
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _spot(),
            TickMath.getSqrtPriceAtTick(position.lower),
            TickMath.getSqrtPriceAtTick(position.upper),
            amount0,
            amount1
        );
        if (liquidity == 0) return;

        _approvePermit2(amount0, amount1);
        // PositionManager is immutable and the caller is protected by StrategyBase.nonReentrant.
        // slither-disable-next-line reentrancy-no-eth,reentrancy-benign
        _positionManager.modifyLiquidities(
            ClActionPlanner.planIncreaseLiquidity(
                _poolKey, tokenId, liquidity, uint128(amount0), uint128(amount1), bytes("")
            ),
            block.timestamp + 1 hours
        );
        _clearPermit2Approvals();
        position.liquidity += liquidity;
    }

    function _closePosition(uint256 tokenId) internal returns (uint256 amount0, uint256 amount1) {
        ManagedPosition memory position = _positions[tokenId];
        if (!position.active) revert UnknownPosition(tokenId);

        (uint256 before0, uint256 before1) = _balances();
        uint128 liquidity = _positionManager.getPositionLiquidity(tokenId);

        bytes memory data =
            ClActionPlanner.planClosePosition(_poolKey, tokenId, liquidity, 0, 0, address(this), bytes(""));
        // PositionManager is immutable and every public caller is protected by nonReentrant.
        // slither-disable-next-line reentrancy-no-eth,reentrancy-benign
        _positionManager.modifyLiquidities(data, block.timestamp + 1 hours);

        (uint256 after0, uint256 after1) = _balances();
        amount0 = after0 - before0;
        amount1 = after1 - before1;

        delete _positions[tokenId];
        _activeTokenId = 0;
        emit PositionClosed(tokenId, amount0, amount1);
    }

    function _prepareBalancesForRange(uint256 amount, int24 lower, int24 upper) internal {
        address token0 = Currency.unwrap(_poolKey.currency0);
        address token1 = Currency.unwrap(_poolKey.currency1);
        address assetToken = asset();

        if (assetToken == token0) {
            _swapToTarget(token0, token1, amount, lower, upper);
        } else {
            _swapToTarget(token1, token0, amount, lower, upper);
        }
    }

    function _rebalanceSwap(int24 lower, int24 upper) internal {
        address assetToken = asset();
        uint256 assetBalance = IERC20(assetToken).balanceOf(address(this));
        if (assetBalance == 0) return;
        _prepareBalancesForRange(assetBalance, lower, upper);
    }

    function _swapToTarget(address tokenIn, address tokenOut, uint256 amountIn, int24 lower, int24 upper) internal {
        if (amountIn == 0) return;
        if (swapAdapter == address(0)) revert RouteNotConfigured();
        if (!_executionRouter.isRouteApproved(swapAdapter, tokenIn, tokenOut)) revert NotApproved(swapAdapter);

        uint160 spot = _spot();
        (uint256 current0, uint256 current1) = _balances();
        uint128 targetLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            spot,
            TickMath.getSqrtPriceAtTick(lower),
            TickMath.getSqrtPriceAtTick(upper),
            current0 + (tokenIn == Currency.unwrap(_poolKey.currency0) ? amountIn : 0),
            current1 + (tokenIn == Currency.unwrap(_poolKey.currency1) ? amountIn : 0)
        );
        (uint256 target0, uint256 target1) = _amountsForLiquidity(spot, lower, upper, targetLiquidity);

        uint256 haveIn = tokenIn == Currency.unwrap(_poolKey.currency0) ? current0 : current1;
        uint256 needIn = tokenIn == Currency.unwrap(_poolKey.currency0) ? target0 : target1;
        if (haveIn + amountIn <= needIn) return;

        uint256 swapAmount = haveIn + amountIn - needIn;
        if (swapAmount > amountIn) swapAmount = amountIn / 2;
        if (swapAmount == 0) return;

        (bool healthyIn,) = _tryGetValidatedPrice(tokenIn);
        (bool healthyOut,) = _tryGetValidatedPrice(tokenOut);
        if (!healthyIn || !healthyOut) return;

        uint256 minOut = _minimumOutput(swapAmount, tokenIn, tokenOut);
        // Leave economically zero-output dust idle rather than submitting a swap whose minimum cannot be met after
        // decimal rounding.
        if (minOut == 0) return;
        _executeRouterSwap(tokenIn, tokenOut, swapAmount, minOut);
    }

    function _minimumOutput(uint256 amountIn, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 minAmountOut)
    {
        (bool healthyIn, uint256 priceIn) = _tryGetValidatedPrice(tokenIn);
        (bool healthyOut, uint256 priceOut) = _tryGetValidatedPrice(tokenOut);
        if (!healthyIn || !healthyOut || priceOut == 0) return 0;

        uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
        uint8 decimalsOut = IERC20Metadata(tokenOut).decimals();
        minAmountOut = amountIn.mulDiv(priceIn, priceOut).mulDiv(10 ** decimalsOut, 10 ** decimalsIn);
        minAmountOut = minAmountOut.mulDiv(Constants.BPS - maxSlippageBps, Constants.BPS);
    }

    function _recordObservation() internal {
        uint160 sqrtPrice = _spot();
        if (sqrtPrice == 0) return;
        if (_observations.length == OBSERVATION_LIMIT) {
            for (uint256 i; i + 1 < OBSERVATION_LIMIT; ++i) {
                _observations[i] = _observations[i + 1];
            }
            _observations.pop();
        }
        _observations.push(PriceObservation({sqrtPriceX96: sqrtPrice, timestamp: uint48(block.timestamp)}));
    }

    /// @dev Compares pool spot against hookless TWAP ring and Chainlink cross-rate.
    function _checkHardFailure() internal view {
        uint160 spot = _spot();
        uint160 twap = PoolPriceLib.twapSqrtPriceX96(_observations, twapWindow, uint48(block.timestamp));
        (uint160 oraclePrice, bool healthy) = _oracleRegistry.getOracleSqrtPriceX96(
            Currency.unwrap(_poolKey.currency0), Currency.unwrap(_poolKey.currency1)
        );

        if (!healthy) revert HardOracleFailure(type(uint256).max, oracleSqrtPriceDeviationBps);

        if (twap != 0) {
            uint256 spotTwapDeviation = PoolPriceLib.sqrtPriceDeviationBps(spot, twap);
            if (spotTwapDeviation > oracleSqrtPriceDeviationBps) {
                revert HardOracleFailure(spotTwapDeviation, oracleSqrtPriceDeviationBps);
            }
            uint256 twapOracleDeviation = PoolPriceLib.sqrtPriceDeviationBps(twap, oraclePrice);
            if (twapOracleDeviation > oracleSqrtPriceDeviationBps) {
                revert HardOracleFailure(twapOracleDeviation, oracleSqrtPriceDeviationBps);
            }
        }

        uint256 spotOracleDeviation = PoolPriceLib.sqrtPriceDeviationBps(spot, oraclePrice);
        if (spotOracleDeviation > oracleSqrtPriceDeviationBps) {
            revert HardOracleFailure(spotOracleDeviation, oracleSqrtPriceDeviationBps);
        }
    }

    /// @dev Withdrawals enforce current-timestamp TWAP safety using `maxWithdrawSqrtPriceDeviationBps` over
    ///      `twapWindow`; an active position cannot withdraw without a full-window observation history.
    function _checkWithdrawSafety() internal view {
        uint160 spot = _spot();
        uint160 twap = PoolPriceLib.twapSqrtPriceX96(_observations, twapWindow, uint48(block.timestamp));
        if (_activeTokenId != 0 && twap == 0) {
            revert WithdrawSafetyFailure(type(uint256).max, maxWithdrawSqrtPriceDeviationBps);
        }
        if (twap == 0) return;
        uint256 deviation = PoolPriceLib.sqrtPriceDeviationBps(spot, twap);
        if (deviation > maxWithdrawSqrtPriceDeviationBps) {
            revert WithdrawSafetyFailure(deviation, maxWithdrawSqrtPriceDeviationBps);
        }
    }

    function _validateTicks(int24 lower, int24 upper) internal view {
        TickValidationLib.validateTicks(
            lower, upper, _poolKey.tickSpacing, policy.minTickWidth(), policy.maxTickWidth()
        );
    }

    /// @dev Uses exact-per-operation Permit2 approvals. Allowances are cleared after each successful settlement.
    function _approvePermit2(uint256 amount0, uint256 amount1) internal {
        address permit2 = _permit2();
        if (permit2 == address(0)) return;
        address token0 = Currency.unwrap(_poolKey.currency0);
        address token1 = Currency.unwrap(_poolKey.currency1);
        uint48 expiration = uint48(block.timestamp + 1 hours);
        IERC20(token0).forceApprove(permit2, amount0);
        IERC20(token1).forceApprove(permit2, amount1);
        IAllowanceTransfer(permit2).approve(token0, address(_positionManager), uint160(amount0), expiration);
        IAllowanceTransfer(permit2).approve(token1, address(_positionManager), uint160(amount1), expiration);
    }

    function _clearPermit2Approvals() internal {
        address permit2 = _permit2();
        if (permit2 == address(0)) return;
        address token0 = Currency.unwrap(_poolKey.currency0);
        address token1 = Currency.unwrap(_poolKey.currency1);
        IERC20(token0).forceApprove(permit2, 0);
        IERC20(token1).forceApprove(permit2, 0);
        IAllowanceTransfer(permit2).approve(token0, address(_positionManager), 0, 0);
        IAllowanceTransfer(permit2).approve(token1, address(_positionManager), 0, 0);
    }

    function _permit2() internal view returns (address permit2) {
        permit2 = IPositionManagerPermit2(address(_positionManager)).permit2();
    }

    function _swapIdlePairToAsset() internal {
        address token0 = Currency.unwrap(_poolKey.currency0);
        address token1 = Currency.unwrap(_poolKey.currency1);
        address assetToken = asset();
        address pairedToken = assetToken == token0 ? token1 : token0;
        uint256 amountIn = IERC20(pairedToken).balanceOf(address(this));
        if (amountIn == 0) return;
        if (swapAdapter == address(0)) revert RouteNotConfigured();
        if (!_executionRouter.isRouteApproved(swapAdapter, pairedToken, assetToken)) {
            revert NotApproved(swapAdapter);
        }

        (bool healthyIn,) = _tryGetValidatedPrice(pairedToken);
        (bool healthyOut,) = _tryGetValidatedPrice(assetToken);
        if (!healthyIn || !healthyOut) revert HardOracleFailure(type(uint256).max, oracleSqrtPriceDeviationBps);

        uint256 minOut = _minimumOutput(amountIn, pairedToken, assetToken);
        // Paired-token dust remains idle and is handled by a later withdrawal or emergency return.
        if (minOut == 0) return;
        // The caller is nonReentrant; amountIn is the intentional input snapshot for this swap.
        // slither-disable-next-line reentrancy-balance
        _executeRouterSwap(pairedToken, assetToken, amountIn, minOut);
    }

    function _executeRouterSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) private {
        IERC20(tokenIn).forceApprove(address(_executionRouter), amountIn);
        uint256 amountOut = _executionRouter.swapExactInput(
            SwapRequest({
                adapter: swapAdapter,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                minAmountOut: minOut,
                deadline: uint48(block.timestamp + 1 hours)
            }),
            address(this)
        );
        if (amountOut < minOut) revert InsufficientOutput(amountOut, minOut);
        IERC20(tokenIn).forceApprove(address(_executionRouter), 0);
    }

    function _balances() private view returns (uint256 balance0, uint256 balance1) {
        balance0 = IERC20(Currency.unwrap(_poolKey.currency0)).balanceOf(address(this));
        balance1 = IERC20(Currency.unwrap(_poolKey.currency1)).balanceOf(address(this));
    }

    /// @dev V4 PositionManager action parameters use uint128 amounts. Rejecting oversized balances avoids truncation.
    function _validateV4Amounts(uint256 amount0, uint256 amount1) private pure {
        if (amount0 > type(uint128).max || amount1 > type(uint128).max) revert V4AmountOverflow();
    }

    /// @dev Keeps the strategy's oracle boundary defensive if an implementation returns a future timestamp.
    function _tryGetValidatedPrice(address token) private view returns (bool healthy, uint256 price) {
        uint256 updatedAt;
        (healthy, price, updatedAt) = _oracleRegistry.tryGetValidatedPrice(token);
        if (updatedAt > block.timestamp) healthy = false;
    }

    function _spot() internal view returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = PoolPriceLib.spotSqrtPriceX96(_poolManager, _poolKey);
    }

    function _setMode(StrategyMode newMode) private {
        StrategyMode previous = mode;
        mode = newMode;
        emit StrategyModeUpdated(previous, newMode);
    }

    function _requireGovernanceAllowed() private view {
        if (mode == StrategyMode.Paused) revert GovernanceBlockedWhilePaused();
    }

    function _amountsForLiquidity(uint160 sqrtPriceX96, int24 lower, int24 upper, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (liquidity == 0) return (0, 0);
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(lower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(upper);
        if (sqrtPriceX96 <= sqrtLower) {
            amount0 = FullMath.mulDiv(
                uint256(liquidity) * (sqrtUpper - sqrtLower), FixedPoint96.Q96, uint256(sqrtUpper) * sqrtLower
            );
        } else if (sqrtPriceX96 < sqrtUpper) {
            amount0 = FullMath.mulDiv(
                uint256(liquidity) * (sqrtUpper - sqrtPriceX96), FixedPoint96.Q96, uint256(sqrtUpper) * sqrtPriceX96
            );
            amount1 = FullMath.mulDiv(liquidity, sqrtPriceX96 - sqrtLower, FixedPoint96.Q96);
        } else {
            amount1 = FullMath.mulDiv(liquidity, sqrtUpper - sqrtLower, FixedPoint96.Q96);
        }
    }
}
