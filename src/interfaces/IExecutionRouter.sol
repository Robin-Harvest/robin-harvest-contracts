// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SwapRequest} from "../types/ProtocolTypes.sol";

/// @notice Constrained execution boundary that accepts structured exact-input swaps only.
interface IExecutionRouter {
    /// @notice Executes an exact-input swap through the approved adapter in the request.
    /// @dev Implementations must not expose arbitrary target or arbitrary calldata execution.
    /// @param request Fully specified swap constraints.
    /// @param recipient Address receiving the output token.
    /// @return amountOut Output token amount received by the recipient.
    function swapExactInput(SwapRequest calldata request, address recipient) external returns (uint256 amountOut);

    /// @notice Returns whether an adapter is approved for router execution.
    /// @param adapter Adapter address to inspect.
    function isAdapterApproved(address adapter) external view returns (bool approved);

    /// @notice Returns whether a route is approved for execution router.
    /// @param adapter Approved execution adapter.
    /// @param tokenIn Token sold.
    /// @param tokenOut Token bought.
    function isRouteApproved(address adapter, address tokenIn, address tokenOut) external view returns (bool approved);

    /// @notice Updates whether an adapter may receive constrained swap requests.
    /// @param adapter Adapter address to update.
    /// @param approved New approval state.
    function setAdapterApproval(address adapter, bool approved) external;
}
