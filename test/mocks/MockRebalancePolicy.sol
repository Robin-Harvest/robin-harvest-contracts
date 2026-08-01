// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRebalancePolicy} from "../../src/interfaces/IRebalancePolicy.sol";

/// @notice Deterministic policy double for concentrated-liquidity strategy tests.
contract MockRebalancePolicy is IRebalancePolicy {
    bool public rebalanceResult;
    int24 private _lower;
    int24 private _upper;
    int24 private _minWidth;
    int24 private _maxWidth;

    constructor(int24 lower_, int24 upper_, int24 minWidth_, int24 maxWidth_) {
        _lower = lower_;
        _upper = upper_;
        _minWidth = minWidth_;
        _maxWidth = maxWidth_;
    }

    function setRebalance(bool shouldRebalance_) external {
        rebalanceResult = shouldRebalance_;
    }

    function setRange(int24 lower_, int24 upper_) external {
        _lower = lower_;
        _upper = upper_;
    }

    function shouldRebalance(uint256, int24, int24, int24, uint128) external view returns (bool rebalance) {
        rebalance = rebalanceResult;
    }

    function targetRange(int24, int24) external view returns (int24 lower, int24 upper) {
        lower = _lower;
        upper = _upper;
    }

    function minTickWidth() external view returns (int24 width) {
        width = _minWidth;
    }

    function maxTickWidth() external view returns (int24 width) {
        width = _maxWidth;
    }
}
