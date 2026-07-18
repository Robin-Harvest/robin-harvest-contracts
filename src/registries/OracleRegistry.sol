// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../libraries/Constants.sol";
import {Events} from "../libraries/Events.sol";
import {Disabled, InvalidBasisPoints, InvalidOracleAnswer, StaleOracle, ZeroAddress, ZeroAmount} from "../libraries/Errors.sol";
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

    function getValidatedPrice(address asset) external view returns (uint256 price, uint256 updatedAt) {
        OracleConfig memory config = _configs[asset];
        if (config.feed == address(0)) revert ZeroAddress();
        if (config.paused) revert Disabled(config.feed);

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
