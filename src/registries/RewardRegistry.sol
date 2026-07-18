// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Constants} from "../libraries/Constants.sol";
import {Events} from "../libraries/Events.sol";
import {InvalidBasisPoints, NotApproved, ZeroAddress} from "../libraries/Errors.sol";
import {IRewardRegistry} from "../interfaces/IRewardRegistry.sol";
import {RewardDisposition, RewardTokenConfig} from "../types/ProtocolTypes.sol";

/// @title Robin Harvest Reward Registry
/// @notice Governance-controlled policy registry for tokenized-stock rewards and other reward assets.
/// @dev Strategies consult this registry; transferred tokens are not trusted unless explicitly enabled here.
contract RewardRegistry is IRewardRegistry, AccessManaged, Events {
    mapping(address token => RewardTokenConfig config) private _configs;
    mapping(address token => mapping(address adapter => bool approved)) private _approvedAdapters;

    event RewardTokenDisabled(address indexed token);
    event RewardAdapterApprovalUpdated(address indexed token, address indexed adapter, bool approved);

    error InvalidDisposition(RewardDisposition disposition);
    error RetentionNotAllowed(address token);

    constructor(address authority_) AccessManaged(authority_) {
        if (authority_ == address(0)) revert ZeroAddress();
    }

    function getRewardTokenConfig(address token) external view returns (RewardTokenConfig memory config) {
        config = _configs[token];
    }

    function isRewardTokenEnabled(address token) external view returns (bool enabled) {
        enabled = _configs[token].enabled;
    }

    function isAdapterApproved(address token, address adapter) external view returns (bool approved) {
        approved = _approvedAdapters[token][adapter];
    }

    function setRewardTokenConfig(address token, RewardTokenConfig calldata config) external restricted {
        _validateConfig(token, config);
        _configs[token] = config;

        if (config.adapter != address(0)) {
            _approvedAdapters[token][config.adapter] = true;
            emit RewardAdapterApprovalUpdated(token, config.adapter, true);
        }

        emit RewardTokenConfigured(token, config.enabled, config.category, config.retainable, config.maxExposureBps);
    }

    function disableRewardToken(address token) external restricted {
        if (token == address(0)) revert ZeroAddress();
        RewardTokenConfig storage config = _configs[token];
        config.enabled = false;
        emit RewardTokenDisabled(token);
        emit RewardTokenConfigured(token, false, config.category, config.retainable, config.maxExposureBps);
    }

    function setAdapterApproval(address token, address adapter, bool approved) external restricted {
        if (token == address(0) || adapter == address(0)) revert ZeroAddress();
        _approvedAdapters[token][adapter] = approved;
        emit RewardAdapterApprovalUpdated(token, adapter, approved);
    }

    function _validateConfig(address token, RewardTokenConfig calldata config) private view {
        if (token == address(0)) revert ZeroAddress();
        if (config.maxExposureBps > Constants.MAX_BPS) revert InvalidBasisPoints(config.maxExposureBps);

        if (!config.enabled) return;

        if (config.disposition == RewardDisposition.Sell) {
            if (config.adapter == address(0) || !_approvedAdapters[token][config.adapter]) {
                revert NotApproved(config.adapter);
            }
        } else if (config.disposition == RewardDisposition.Retain) {
            if (!config.retainable) revert RetentionNotAllowed(token);
            if (config.oracle == address(0)) revert ZeroAddress();
        } else if (config.disposition != RewardDisposition.Ignore) {
            revert InvalidDisposition(config.disposition);
        }
    }
}
