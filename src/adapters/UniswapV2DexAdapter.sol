// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IDexAdapter} from "../interfaces/IDexAdapter.sol";
import {IUniswapV2Router} from "../interfaces/external/IUniswapV2Router.sol";
import {ZeroAddress, ZeroAmount, Unauthorized} from "../libraries/Errors.sol";

/// @title Uniswap V2 Style DEX Adapter
/// @notice Exact-input adapter for a constant-product router.
/// @dev Governance must configure the router against an official Robinhood Chain deployment.
contract UniswapV2DexAdapter is IDexAdapter, AccessManaged {
    using SafeERC20 for IERC20;

    error DeadlineExpired();
    error PathUnavailable();
    error InsufficientOutput(uint256 amountOut, uint256 minimum);
    error InvalidPath();

    event CustomPathSet(address indexed tokenIn, address indexed tokenOut, address[] path);

    /// @notice Approved router used for swaps and quotes.
    IUniswapV2Router public immutable router;

    /// @notice Execution router authorized to execute swaps via this adapter (optional, if zero any caller is permitted).
    address public immutable executionRouter;

    mapping(address tokenIn => mapping(address tokenOut => address[])) private _customPaths;

    // Justification: executionRouter_ is intentionally optional. Passing address(0) permits any caller for test environments.
    // slither-disable-next-line missing-zero-check,zero-address
    constructor(IUniswapV2Router router_, address executionRouter_, address authority_) AccessManaged(authority_) {
        if (address(router_) == address(0) || authority_ == address(0)) revert ZeroAddress();
        router = router_;
        executionRouter = executionRouter_;
    }

    /// @notice Configures a custom multi-hop path.
    function setCustomPath(address tokenIn, address tokenOut, address[] calldata path) external restricted {
        if (tokenIn == address(0) || tokenOut == address(0)) revert ZeroAddress();
        if (path.length < 2) revert InvalidPath();
        if (path[0] != tokenIn || path[path.length - 1] != tokenOut) revert InvalidPath();
        for (uint256 i; i < path.length; ++i) {
            if (path[i] == address(0)) revert ZeroAddress();
        }
        _customPaths[tokenIn][tokenOut] = path;
        emit CustomPathSet(tokenIn, tokenOut, path);
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
        if (executionRouter != address(0) && msg.sender != executionRouter) revert Unauthorized(msg.sender, bytes32(0));
        if (amountIn == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (block.timestamp > deadline) revert DeadlineExpired();

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(router), amountIn);

        address[] memory path = _path(tokenIn, tokenOut);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(recipient);
        // Justification: The return value of the router swap is captured to satisfy Slither,
        // but the actual amount received is verified using balance differences to account for fee-on-transfer.
        // slither-disable-next-line unused-return,reentrancy-balance,reentrancy-events
        router.swapExactTokensForTokens(amountIn, minAmountOut, path, recipient, deadline);

        IERC20(tokenIn).forceApprove(address(router), 0);

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

    function _path(address tokenIn, address tokenOut) private view returns (address[] memory path) {
        if (tokenIn == address(0) || tokenOut == address(0)) revert ZeroAddress();

        address[] memory customPath = _customPaths[tokenIn][tokenOut];
        if (customPath.length > 0) {
            return customPath;
        }

        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }
}
