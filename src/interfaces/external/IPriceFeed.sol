// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Provisional Chainlink-shaped read boundary for an external price feed.
/// @dev UNCONFIRMED — verify against live contract.
interface IPriceFeed {
    /// @notice Returns the feed answer decimal precision.
    /// @dev UNCONFIRMED — verify selector and feed implementation against live contract.
    function decimals() external view returns (uint8 feedDecimals);

    /// @notice Returns the latest round data exposed by the feed.
    /// @dev UNCONFIRMED — verify ABI, round semantics, heartbeat, and answeredInRound behavior against live contract.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
