// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PriceObservation} from "../types/ClStrategyTypes.sol";
import {Constants} from "./Constants.sol";

using Math for uint256;

/// @title Pool Price Library
/// @notice Reads spot prices and computes hookless TWAP estimates from strategy-maintained observations.
library PoolPriceLib {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    /// @notice Returns the current pool sqrt price from PoolManager slot0.

    function spotSqrtPriceX96(IPoolManager manager, PoolKey memory key) internal view returns (uint160 sqrtPriceX96) {
        PoolId poolId = key.toId();
        (sqrtPriceX96,,,) = StateLibrary.getSlot0(manager, poolId);
    }

    /// @notice Returns the current pool tick from PoolManager slot0.
    function currentTick(IPoolManager manager, PoolKey memory key) internal view returns (int24 tick) {
        PoolId poolId = key.toId();
        (, tick,,) = StateLibrary.getSlot0(manager, poolId);
    }

    /// @notice Computes a time-weighted sqrt price from stored observations over `windowSeconds`.
    /// @dev V1 pools do not ship with enshrined oracles; the strategy records observations on interaction.
    ///      The newest observation is validated against `currentTimestamp`, not merely against itself. A TWAP is
    ///      unavailable until the observation ring contains a sample at or before the window's start, preventing a
    ///      stale or short observation history from being treated as a full-window TWAP.
    function twapSqrtPriceX96(PriceObservation[] storage observations, uint32 windowSeconds, uint48 currentTimestamp)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        uint256 length = observations.length;
        if (length == 0) return 0;

        uint256 newestIndex = length - 1;
        PriceObservation memory newest = observations[newestIndex];
        if (newest.timestamp == 0) return 0;

        if (newest.timestamp > currentTimestamp) return 0;
        if (currentTimestamp - newest.timestamp > windowSeconds) return 0;

        uint48 cutoff = currentTimestamp > windowSeconds ? currentTimestamp - windowSeconds : 0;
        uint256 weightedSum;
        uint256 totalWeight;
        bool hasWindowCoverage;

        for (uint256 i = length; i > 0;) {
            unchecked {
                --i;
            }
            PriceObservation memory obs = observations[i];
            if (obs.timestamp == 0 || obs.timestamp > currentTimestamp) return 0;

            uint48 nextTimestamp = i + 1 < length ? observations[i + 1].timestamp : currentTimestamp;
            if (nextTimestamp > currentTimestamp) nextTimestamp = currentTimestamp;

            uint48 segmentStart = obs.timestamp < cutoff ? cutoff : obs.timestamp;
            if (obs.timestamp <= cutoff) hasWindowCoverage = true;
            if (nextTimestamp > segmentStart) {
                uint256 weight = nextTimestamp - segmentStart;
                weightedSum += uint256(obs.sqrtPriceX96) * weight;
                totalWeight += weight;
            }
        }

        if (!hasWindowCoverage || totalWeight == 0) return 0;
        sqrtPriceX96 = uint160(weightedSum / totalWeight);
    }

    /// @notice Returns absolute relative deviation between two sqrt prices in basis points.
    /// @dev This deliberately measures sqrt-price deviation, not price-ratio deviation. A configured value of 300
    ///      means 3% movement in sqrtPriceX96; callers and governance parameters use the explicit `SqrtPrice` name.
    function sqrtPriceDeviationBps(uint160 sqrtA, uint160 sqrtB) internal pure returns (uint256 deviationBps) {
        if (sqrtA == 0 || sqrtB == 0) return type(uint256).max;
        uint256 a = uint256(sqrtA);
        uint256 b = uint256(sqrtB);
        uint256 delta = a > b ? a - b : b - a;
        deviationBps = delta.mulDiv(Constants.BPS, b, Math.Rounding.Ceil);
    }

    /// @notice Converts an oracle cross-rate into sqrtPriceX96.
    /// @param priceToken1PerToken0 Oracle price of token1 per token0 at 1e18 precision.
    function sqrtPriceX96FromOraclePrice(uint256 priceToken1PerToken0) internal pure returns (uint160 sqrtPriceX96) {
        if (priceToken1PerToken0 == 0) return 0;
        uint256 ratioX192 = priceToken1PerToken0 << 192;
        sqrtPriceX96 = uint160(Math.sqrt(ratioX192 / 1e18));
    }

    /// @notice Values token balances in terms of the vault asset using oracle cross-rates.
    function valueInAsset(
        address asset,
        address token0,
        address token1,
        uint256 balance0,
        uint256 balance1,
        uint256 price0,
        uint256 price1,
        bool healthy0,
        bool healthy1
    ) internal view returns (uint256 totalValue) {
        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        if (healthy0 && balance0 != 0) {
            uint8 decimals0 = IERC20Metadata(token0).decimals();
            totalValue += balance0.mulDiv(price0, 1e18).mulDiv(10 ** assetDecimals, 10 ** decimals0);
        }
        if (healthy1 && balance1 != 0) {
            uint8 decimals1 = IERC20Metadata(token1).decimals();
            totalValue += balance1.mulDiv(price1, 1e18).mulDiv(10 ** assetDecimals, 10 ** decimals1);
        }
    }
}
