// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Constants} from "../libraries/Constants.sol";
import {Events} from "../libraries/Events.sol";
import {
    Disabled,
    InvalidBasisPoints,
    InvalidOracleAnswer,
    StaleOracle,
    ZeroAddress,
    ZeroAmount
} from "../libraries/Errors.sol";
import {IOracleRegistry} from "../interfaces/IOracleRegistry.sol";
import {IPriceFeed} from "../interfaces/external/IPriceFeed.sol";
import {OracleConfig} from "../types/ProtocolTypes.sol";

/// @title Robin Harvest Oracle Registry
/// @notice Stores and validates price feeds with heartbeat, round, decimal, pause, and multiplier policy.
/// @dev Normalized prices are returned at 1e18 precision after applying `uiMultiplier` at 1e18 precision.
contract OracleRegistry is IOracleRegistry, AccessManaged, Events {
    using Math for uint256;

    uint256 public constant NORMALIZED_PRICE_DECIMALS = 1e18;

    mapping(address asset => OracleConfig config) private _configs;

    event OracleMultiplierUpdated(address indexed asset, uint256 previousMultiplier, uint256 newMultiplier);

    error InvalidDecimals(uint8 decimals);
    error IncompleteOracleRound(address oracle, uint80 roundId, uint80 answeredInRound);

    constructor(address authority_) AccessManaged(authority_) {
        if (authority_ == address(0)) revert ZeroAddress();
    }

    function getOracleConfig(address asset) external view returns (OracleConfig memory config) {
        config = _configs[asset];
    }

    // Justification: The oracle freshness check validates observedAt against block.timestamp to detect stale feeds.
    // Miner manipulation on block.timestamp is negligible relative to the heartbeat window (usually hours).
    // slither-disable-next-line timestamp
    function getValidatedPrice(address asset) external view returns (uint256 price, uint256 updatedAt) {
        OracleConfig memory config = _configs[asset];
        if (config.feed == address(0)) revert ZeroAddress();
        if (config.paused) revert Disabled(config.feed);

        // Justification: the startedAt parameter returned by latestRoundData is intentionally unused.
        // slither-disable-next-line unused-return
        (uint80 roundId, int256 answer,, uint256 observedAt, uint80 answeredInRound) =
            IPriceFeed(config.feed).latestRoundData();
        if (answer <= 0 || observedAt == 0) revert InvalidOracleAnswer(config.feed);
        if (answeredInRound < roundId) revert IncompleteOracleRound(config.feed, roundId, answeredInRound);
        if (config.heartbeat != 0 && block.timestamp > observedAt + config.heartbeat) {
            revert StaleOracle(config.feed, observedAt, config.heartbeat);
        }

        updatedAt = observedAt;
        price = _normalize(uint256(answer), config.decimals).mulDiv(_multiplier(config.uiMultiplier), 1e18);
    }

    // Justification: The oracle freshness check validates observedAt against block.timestamp to detect stale feeds.
    // Miner manipulation on block.timestamp is negligible relative to the heartbeat window (usually hours).
    // slither-disable-next-line timestamp
    function tryGetValidatedPrice(address asset)
        external
        view
        returns (bool healthy, uint256 price, uint256 updatedAt)
    {
        OracleConfig memory config = _configs[asset];
        if (config.feed == address(0) || config.paused) return (false, 0, 0);

        // slither-disable-next-line unused-return
        try IPriceFeed(config.feed).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, uint256 observedAt, uint80 answeredInRound
        ) {
            if (answer <= 0 || observedAt == 0) return (false, 0, 0);
            if (answeredInRound < roundId) return (false, 0, 0);
            if (config.heartbeat != 0 && block.timestamp > observedAt + config.heartbeat) {
                return (false, 0, 0);
            }

            updatedAt = observedAt;
            price = _normalize(uint256(answer), config.decimals).mulDiv(_multiplier(config.uiMultiplier), 1e18);
            return (true, price, updatedAt);
        } catch {
            return (false, 0, 0);
        }
    }

    function isHealthy(address asset) external view returns (bool healthy) {
        // slither-disable-next-line unused-return
        (healthy,,) = this.tryGetValidatedPrice(asset);
    }

    /// @inheritdoc IOracleRegistry
    function getCrossRate(address token0, address token1) external view returns (uint256 price, bool healthy) {
        // slither-disable-next-line unused-return
        (bool healthy0, uint256 price0,) = this.tryGetValidatedPrice(token0);
        // slither-disable-next-line unused-return
        (bool healthy1, uint256 price1,) = this.tryGetValidatedPrice(token1);
        if (!healthy0 || !healthy1 || price1 == 0) return (0, false);

        uint8 decimals0 = IERC20Metadata(token0).decimals();
        uint8 decimals1 = IERC20Metadata(token1).decimals();
        price = price0.mulDiv(10 ** decimals1, price1).mulDiv(1e18, 10 ** decimals0);
        healthy = price != 0;
    }

    /// @inheritdoc IOracleRegistry
    function getOracleSqrtPriceX96(address token0, address token1)
        external
        view
        returns (uint160 sqrtPriceX96, bool healthy)
    {
        (uint256 crossRate, bool rateHealthy) = this.getCrossRate(token0, token1);
        if (!rateHealthy) return (0, false);
        uint256 ratioX192 = crossRate << 192;
        sqrtPriceX96 = uint160(Math.sqrt(ratioX192 / 1e18));
        healthy = sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 < TickMath.MAX_SQRT_PRICE;
    }

    function setOracleConfig(address asset, OracleConfig calldata config) external restricted {
        _validateAssetAndConfig(asset, config);
        _configs[asset] = config;
        emit OracleConfigured(asset, config.feed, config.heartbeat, config.paused);
    }

    function setOraclePaused(address asset, bool paused) external restricted {
        OracleConfig storage config = _configs[asset];
        if (config.feed == address(0)) revert ZeroAddress();
        config.paused = paused;
        emit OracleConfigured(asset, config.feed, config.heartbeat, paused);
    }

    function setUiMultiplier(address asset, uint256 newMultiplier) external restricted {
        if (newMultiplier == 0) revert ZeroAmount();
        OracleConfig storage config = _configs[asset];
        if (config.feed == address(0)) revert ZeroAddress();
        emit OracleMultiplierUpdated(asset, config.uiMultiplier, newMultiplier);
        config.uiMultiplier = newMultiplier;
        emit OracleConfigured(asset, config.feed, config.heartbeat, config.paused);
    }

    function _validateAssetAndConfig(address asset, OracleConfig calldata config) private view {
        if (asset == address(0) || config.feed == address(0)) revert ZeroAddress();
        if (config.heartbeat == 0 || config.uiMultiplier == 0) revert ZeroAmount();
        if (config.maxDeviationBps > Constants.MAX_BPS) revert InvalidBasisPoints(config.maxDeviationBps);
        if (config.decimals > 36) revert InvalidDecimals(config.decimals);

        uint8 feedDecimals = IPriceFeed(config.feed).decimals();
        if (feedDecimals != config.decimals) revert InvalidDecimals(feedDecimals);
    }

    function _normalize(uint256 rawPrice, uint8 decimals_) private pure returns (uint256) {
        if (decimals_ == 18) return rawPrice;
        if (decimals_ < 18) return rawPrice * (10 ** (18 - decimals_));
        return rawPrice / (10 ** (decimals_ - 18));
    }

    function _multiplier(uint256 uiMultiplier) private pure returns (uint256) {
        return uiMultiplier == 0 ? 1e18 : uiMultiplier;
    }
}
