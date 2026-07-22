// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../libraries/Constants.sol";
import {
    InvalidBasisPoints,
    InvalidLifecycleState,
    LossExceedsMaximum,
    ZeroAddress,
    ZeroAmount
} from "../libraries/Errors.sol";
import {HarvestReport, SwapRequest} from "../types/ProtocolTypes.sol";
import {ILpStrategy} from "../interfaces/ILpStrategy.sol";
import {IDexAdapter} from "../interfaces/IDexAdapter.sol";
import {IExecutionRouter} from "../interfaces/IExecutionRouter.sol";
import {IOracleRegistry} from "../interfaces/IOracleRegistry.sol";
import {IRewardRegistry} from "../interfaces/IRewardRegistry.sol";
import {StrategyBase} from "./StrategyBase.sol";

interface IUniswapV2PairMock {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint256);
}

interface IUniswapV2RouterMock {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

interface IGaugeMock {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function balanceOf(address account) external view returns (uint256);
}

/// @title Robin Harvest LP Yield Strategy
/// @notice Auto-compounding liquidity provider strategy for INDEX pools.
/// @dev Calculates optimal swap splits, provides pool liquidity, stakes into gauges, and auto-compounds yields.
contract LpStrategy is StrategyBase, ILpStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;

    address public immutable override lpToken;
    address public immutable override pairedToken;
    address public immutable override dexRouter;
    address public immutable override dexAdapter;

    IExecutionRouter public immutable executionRouter;
    IOracleRegistry public immutable oracleRegistry;
    IRewardRegistry public immutable rewardRegistry;

    address public override gauge;
    uint16 public override maxSlippageBps = 300; // 3% default max slippage
    bool public override compoundingPaused;

    event LpGaugeUpdated(address indexed newGauge);
    event LpMaxSlippageUpdated(uint16 previousBps, uint16 newBps);
    event CompoundingStateUpdated(bool paused);
    event LpCapitalDeployed(uint256 indexAmount, uint256 lpTokensMinted);
    event LpCapitalFreed(uint256 lpTokensBurned, uint256 indexFreed, uint256 loss);

    constructor(
        address vault_,
        IERC20 asset_,
        address authority_,
        address lpToken_,
        address pairedToken_,
        address dexRouter_,
        address dexAdapter_,
        IExecutionRouter executionRouter_,
        IOracleRegistry oracleRegistry_,
        IRewardRegistry rewardRegistry_
    ) StrategyBase(vault_, asset_, authority_) {
        if (
            lpToken_ == address(0) || pairedToken_ == address(0) || dexRouter_ == address(0)
                || dexAdapter_ == address(0) || address(executionRouter_) == address(0)
                || address(oracleRegistry_) == address(0) || address(rewardRegistry_) == address(0)
        ) {
            revert ZeroAddress();
        }

        lpToken = lpToken_;
        pairedToken = pairedToken_;
        dexRouter = dexRouter_;
        dexAdapter = dexAdapter_;
        executionRouter = executionRouter_;
        oracleRegistry = oracleRegistry_;
        rewardRegistry = rewardRegistry_;
    }

    /// @inheritdoc ILpStrategy
    // slither-disable-next-line missing-zero-check
    function setGauge(address newGauge) external restricted {
        gauge = newGauge;
        emit LpGaugeUpdated(newGauge);
    }

    /// @inheritdoc ILpStrategy
    function setMaxSlippage(uint16 newSlippageBps) external restricted {
        if (newSlippageBps > Constants.MAX_BPS) revert InvalidBasisPoints(newSlippageBps);
        emit LpMaxSlippageUpdated(maxSlippageBps, newSlippageBps);
        maxSlippageBps = newSlippageBps;
    }

    /// @inheritdoc ILpStrategy
    function pauseCompounding() external restricted {
        compoundingPaused = true;
        emit CompoundingStateUpdated(true);
    }

    /// @inheritdoc ILpStrategy
    function resumeCompounding() external restricted {
        compoundingPaused = false;
        emit CompoundingStateUpdated(false);
    }

    /// @notice Returns total INDEX-denominated mark-to-market value of deployed LP holdings.
    function deployedAssets() public view returns (uint256 totalValue) {
        return _deployedAssets();
    }

    function _deployedAssets() internal view override returns (uint256 totalValue) {
        uint256 lpBalance = _stakedLpBalance();
        // Justification: lpBalance == 0 early return
        // slither-disable-next-line incorrect-equality
        if (lpBalance == 0) return 0;

        uint256 totalSupplyLp = IUniswapV2PairMock(lpToken).totalSupply();
        // Justification: totalSupplyLp == 0 zero check
        // slither-disable-next-line incorrect-equality
        if (totalSupplyLp == 0) return 0;

        // slither-disable-next-line unused-return
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairMock(lpToken).getReserves();
        address token0 = IUniswapV2PairMock(lpToken).token0();

        uint256 reserveIndex = token0 == asset() ? uint256(reserve0) : uint256(reserve1);
        uint256 reservePaired = token0 == asset() ? uint256(reserve1) : uint256(reserve0);

        uint256 pairedValueInIndex = 0;
        // slither-disable-next-line unused-return
        (bool healthy, uint256 pricePaired,) = oracleRegistry.tryGetValidatedPrice(pairedToken);
        if (healthy && pricePaired != 0) {
            uint8 decimalsPaired = IERC20Metadata(pairedToken).decimals();
            uint8 decimalsIndex = IERC20Metadata(asset()).decimals();
            pairedValueInIndex =
                reservePaired.mulDiv(pricePaired, 1e18).mulDiv(10 ** decimalsIndex, 10 ** decimalsPaired);
        }

        uint256 totalPoolIndexValue = reserveIndex + pairedValueInIndex;
        totalValue = lpBalance.mulDiv(totalPoolIndexValue, totalSupplyLp);
    }

    // Justification: Reentrancy is protected by onlyVault modifier on StrategyBase callers.
    // slither-disable-next-line reentrancy-benign,reentrancy-events,reentrancy-balance
    function _deployFunds(uint256 amount) internal override {
        // Justification: amount == 0 early return
        // slither-disable-next-line incorrect-equality
        if (amount == 0) return;

        // slither-disable-next-line unused-return
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairMock(lpToken).getReserves();
        address token0 = IUniswapV2PairMock(lpToken).token0();
        uint256 reserveIndex = token0 == asset() ? uint256(reserve0) : uint256(reserve1);

        uint256 indexToSwap = _optimalSwapAmount(amount, reserveIndex);
        if (indexToSwap >= amount) indexToSwap = amount / 2;

        IERC20(asset()).forceApprove(address(executionRouter), indexToSwap);
        uint256 pairedReceived = executionRouter.swapExactInput(
            SwapRequest({
                adapter: dexAdapter,
                tokenIn: asset(),
                tokenOut: pairedToken,
                amountIn: indexToSwap,
                minAmountOut: 1,
                deadline: uint48(block.timestamp + 1 hours)
            }),
            address(this)
        );
        IERC20(asset()).forceApprove(address(executionRouter), 0);

        uint256 indexRemaining = amount - indexToSwap;

        IERC20(asset()).forceApprove(dexRouter, indexRemaining);
        IERC20(pairedToken).forceApprove(dexRouter, pairedReceived);

        uint256 minIndex = indexRemaining.mulDiv(Constants.BPS - maxSlippageBps, Constants.BPS);
        uint256 minPaired = pairedReceived.mulDiv(Constants.BPS - maxSlippageBps, Constants.BPS);

        // slither-disable-next-line unused-return
        (,, uint256 liquidityMinted) = IUniswapV2RouterMock(dexRouter).addLiquidity(
            asset(),
            pairedToken,
            indexRemaining,
            pairedReceived,
            minIndex,
            minPaired,
            address(this),
            block.timestamp + 1 hours
        );

        IERC20(asset()).forceApprove(dexRouter, 0);
        IERC20(pairedToken).forceApprove(dexRouter, 0);

        if (gauge != address(0) && liquidityMinted != 0) {
            IERC20(lpToken).forceApprove(gauge, liquidityMinted);
            IGaugeMock(gauge).deposit(liquidityMinted);
            IERC20(lpToken).forceApprove(gauge, 0);
        }

        emit LpCapitalDeployed(amount, liquidityMinted);
    }

    // Justification: Reentrancy is protected by onlyVault modifier on StrategyBase callers.
    // slither-disable-next-line reentrancy-benign,reentrancy-events,reentrancy-balance
    function _freeFunds(uint256 amount) internal override returns (uint256 loss) {
        uint256 currentDeployed = deployedAssets();
        // Justification: amount == 0 check or currentDeployed == 0
        // slither-disable-next-line incorrect-equality
        if (amount == 0 || currentDeployed == 0) return 0;

        uint256 totalLp = _stakedLpBalance();
        // Justification: totalLp == 0 check
        // slither-disable-next-line incorrect-equality
        if (totalLp == 0) return amount;

        uint256 lpToBurn = totalLp.mulDiv(amount, currentDeployed, Math.Rounding.Ceil);
        if (lpToBurn < totalLp) {
            lpToBurn += 1;
        }
        if (lpToBurn > totalLp) lpToBurn = totalLp;

        if (gauge != address(0)) {
            IGaugeMock(gauge).withdraw(lpToBurn);
        }

        uint256 indexBefore = IERC20(asset()).balanceOf(address(this));
        uint256 pairedBefore = IERC20(pairedToken).balanceOf(address(this));

        IERC20(lpToken).forceApprove(dexRouter, lpToBurn);
        // slither-disable-next-line unused-return
        IUniswapV2RouterMock(dexRouter).removeLiquidity(
            asset(), pairedToken, lpToBurn, 0, 0, address(this), block.timestamp + 1 hours
        );
        IERC20(lpToken).forceApprove(dexRouter, 0);

        uint256 indexReceived = IERC20(asset()).balanceOf(address(this)) - indexBefore;
        uint256 pairedReceived = IERC20(pairedToken).balanceOf(address(this)) - pairedBefore;

        uint256 swappedIndex = 0;
        if (pairedReceived != 0) {
            IERC20(pairedToken).forceApprove(address(executionRouter), pairedReceived);
            swappedIndex = executionRouter.swapExactInput(
                SwapRequest({
                    adapter: dexAdapter,
                    tokenIn: pairedToken,
                    tokenOut: asset(),
                    amountIn: pairedReceived,
                    minAmountOut: 1,
                    deadline: uint48(block.timestamp + 1 hours)
                }),
                address(this)
            );
            IERC20(pairedToken).forceApprove(address(executionRouter), 0);
        }

        uint256 totalFreed = indexReceived + swappedIndex;
        if (totalFreed < amount) {
            loss = amount - totalFreed;
        }

        emit LpCapitalFreed(lpToBurn, totalFreed, loss);
    }

    function _claimRewards() internal override {
        if (gauge != address(0)) {
            IGaugeMock(gauge).getReward();
        }
    }

    // Justification: Reentrancy is protected by onlyVault modifier on StrategyBase callers.
    // slither-disable-next-line reentrancy-benign,reentrancy-events,reentrancy-balance
    function _processRewardToken(address token) internal override returns (uint256 assetGain) {
        uint256 amount = IERC20(token).balanceOf(address(this));
        // Justification: amount == 0 early return
        // slither-disable-next-line incorrect-equality
        if (amount == 0 || compoundingPaused) return 0;

        if (token == asset()) {
            _deployFunds(amount);
            return amount;
        }

        IERC20(token).forceApprove(address(executionRouter), amount);
        assetGain = executionRouter.swapExactInput(
            SwapRequest({
                adapter: dexAdapter,
                tokenIn: token,
                tokenOut: asset(),
                amountIn: amount,
                minAmountOut: 1,
                deadline: uint48(block.timestamp + 1 hours)
            }),
            address(this)
        );
        IERC20(token).forceApprove(address(executionRouter), 0);

        if (assetGain != 0) {
            _deployFunds(assetGain);
        }
    }

    function _emergencyWithdraw() internal override returns (uint256 loss) {
        uint256 deployed = _deployedAssets();
        if (deployed != 0) {
            loss = _freeFunds(deployed);
        }
    }

    function _stakedLpBalance() private view returns (uint256 balance) {
        balance = IERC20(lpToken).balanceOf(address(this));
        if (gauge != address(0)) {
            balance += IGaugeMock(gauge).balanceOf(address(this));
        }
    }

    /// @notice Calculates optimal INDEX amount to swap for constant-product pool alignment.
    function _optimalSwapAmount(uint256 amount, uint256 reserveIndex) private pure returns (uint256 swapAmount) {
        // Justification: reserveIndex == 0 check
        // slither-disable-next-line incorrect-equality
        if (reserveIndex == 0) return amount / 2;
        uint256 radicand = reserveIndex.mulDiv(3988000 * amount + 3988009 * reserveIndex, 1);
        uint256 root = Math.sqrt(radicand);
        if (root > 1997 * reserveIndex) {
            swapAmount = (root - 1997 * reserveIndex) / 1994;
        } else {
            swapAmount = amount / 2;
        }
    }
}
