// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDexAdapter} from "../../src/interfaces/IDexAdapter.sol";

/// @notice Deterministic exact-input DEX stand-in for tests.
/// @dev TEST-ONLY. Route rates use 1e18 fixed-point precision. Unsafe for production.
contract MockDex is IDexAdapter {
    using SafeERC20 for IERC20;

    error DeadlineExpired();
    error RouteUnavailable();
    error InsufficientOutput(uint256 amountOut, uint256 minimum);

    uint256 private constant RATE_SCALE = 1e18;
    mapping(address tokenIn => mapping(address tokenOut => uint256 rate)) public rate;

    function setRate(address tokenIn, address tokenOut, uint256 rate_) external {
        rate[tokenIn][tokenOut] = rate_;
    }

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint48 deadline
    ) external override returns (uint256 amountOut) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        uint256 routeRate = rate[tokenIn][tokenOut];
        if (routeRate == 0) revert RouteUnavailable();

        amountOut = amountIn * routeRate / RATE_SCALE;
        if (amountOut < minAmountOut) revert InsufficientOutput(amountOut, minAmountOut);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(recipient, amountOut);
    }

    function quoteExactInput(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        override
        returns (uint256 amountOut)
    {
        uint256 routeRate = rate[tokenIn][tokenOut];
        if (routeRate == 0) return 0;
        amountOut = amountIn * routeRate / RATE_SCALE;
    }
}
