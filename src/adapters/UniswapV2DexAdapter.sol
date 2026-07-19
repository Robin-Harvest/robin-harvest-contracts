// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDexAdapter} from "../interfaces/IDexAdapter.sol";
import {IUniswapV2Router} from "../interfaces/external/IUniswapV2Router.sol";
import {ZeroAddress, ZeroAmount} from "../libraries/Errors.sol";

/// @title Uniswap V2 Style DEX Adapter
/// @notice Exact-input adapter for a two-hop constant-product router.
/// @dev Governance must configure the router against an official Robinhood Chain deployment. The adapter never accepts
/// arbitrary calldata from keepers; only the fixed swap selector is used.
contract UniswapV2DexAdapter is IDexAdapter {
    using SafeERC20 for IERC20;

    error DeadlineExpired();
    error PathUnavailable();
    error InsufficientOutput(uint256 amountOut, uint256 minimum);

    /// @notice Approved router used for swaps and quotes.
    IUniswapV2Router public immutable router;

    constructor(IUniswapV2Router router_) {
        if (address(router_) == address(0)) revert ZeroAddress();
        router = router_;
    }

    /// @inheritdoc IDexAdapter
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint48 deadline
    ) external override returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (block.timestamp > deadline) revert DeadlineExpired();

        address[] memory path = _path(tokenIn, tokenOut);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(recipient);
        router.swapExactTokensForTokens(amountIn, minAmountOut, path, recipient, deadline);
        amountOut = IERC20(tokenOut).balanceOf(recipient) - balanceBefore;
        if (amountOut < minAmountOut) revert InsufficientOutput(amountOut, minAmountOut);
    }

    /// @inheritdoc IDexAdapter
    function quoteExactInput(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        override
        returns (uint256 amountOut)
    {
        if (amountIn == 0) return 0;
        address[] memory path = _path(tokenIn, tokenOut);
        try router.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
        } catch {
            amountOut = 0;
        }
    }

    function _path(address tokenIn, address tokenOut) private pure returns (address[] memory path) {
        if (tokenIn == address(0) || tokenOut == address(0)) revert ZeroAddress();
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }
}
