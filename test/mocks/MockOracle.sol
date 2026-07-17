// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPriceFeed} from "../../src/interfaces/external/IPriceFeed.sol";

/// @notice Configurable Chainlink-shaped price-feed stand-in for tests.
/// @dev TEST-ONLY and UNCONFIRMED against live feeds. Unsafe for production.
contract MockOracle is IPriceFeed {
    error FeedPaused();

    uint8 public immutable override decimals;
    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;
    bool public paused;

    constructor(uint8 decimals_, int256 initialAnswer) {
        decimals = decimals_;
        setRoundData(1, initialAnswer, block.timestamp, block.timestamp, 1);
    }

    function setRoundData(
        uint80 roundId_,
        int256 answer_,
        uint256 startedAt_,
        uint256 updatedAt_,
        uint80 answeredInRound_
    ) public {
        roundId = roundId_;
        answer = answer_;
        startedAt = startedAt_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    function setPaused(bool paused_) external {
        paused = paused_;
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        if (paused) revert FeedPaused();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
