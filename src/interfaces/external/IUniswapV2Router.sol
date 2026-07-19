// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Provisional Uniswap V2 router boundary for the first production DEX adapter.
/// @dev UNCONFIRMED against Robinhood Chain deployments. Verify router ABI before production use.
interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}
