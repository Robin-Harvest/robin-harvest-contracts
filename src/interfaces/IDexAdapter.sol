// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Minimal exact-input boundary implemented by an approved DEX-specific adapter.
interface IDexAdapter {
    /// @notice Swaps an exact input amount under explicit token, slippage, deadline, and recipient constraints.
    /// @dev Implementations must encode venue-specific calls internally and must not accept arbitrary calldata.
    /// @param tokenIn Token sold.
    /// @param tokenOut Token bought.
    /// @param amountIn Exact amount of tokenIn supplied.
    /// @param minAmountOut Minimum acceptable tokenOut amount.
    /// @param recipient Address receiving tokenOut.
    /// @param deadline Latest valid execution timestamp.
    /// @return amountOut Output token amount received by the recipient.
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint48 deadline
    ) external returns (uint256 amountOut);
}
