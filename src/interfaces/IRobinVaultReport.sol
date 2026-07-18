// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {HarvestReport} from "../types/ProtocolTypes.sol";

/// @notice Interface for the RobinVault's reporting function.
interface IRobinVaultReport {
    /// @notice Called by the strategy after harvest accounting is known.
    function report(HarvestReport calldata report_) external;
}
