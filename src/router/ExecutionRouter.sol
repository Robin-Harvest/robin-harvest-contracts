// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants} from "../libraries/Constants.sol";
import {Events} from "../libraries/Events.sol";
import {DeadlineExpired, InsufficientOutput, InvalidBasisPoints, NotApproved, OracleDeviationExceeded, ZeroAddress, ZeroAmount} from "../libraries/Errors.sol";
import {IDexAdapter} from "../interfaces/IDexAdapter.sol";
import {IExecutionRouter} from "../interfaces/IExecutionRouter.sol";
import {IOracleRegistry} from "../interfaces/IOracleRegistry.sol";
import {SwapRequest} from "../types/ProtocolTypes.sol";

/// @title Robin Harvest Execution Router
/// @notice Constrained router for governance-approved exact-input swaps.
/// @dev No arbitrary target or calldata is exposed. Adapters encode venue-specific behavior internally.
contract ExecutionRouter is IExecutionRouter, AccessManaged, ReentrancyGuard, Events {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct RouteConfig {
        bool enabled;
        uint16 maxOracleDeviationBps;
    }

    IOracleRegistry public immutable oracleRegistry;

    mapping(address adapter => bool approved) private _approvedAdapters;
    mapping(bytes32 routeId => RouteConfig config) private _routes;

    event RouteConfigured(
        bytes32 indexed routeId,
        address indexed adapter,
        address indexed tokenIn,
        address tokenOut,
        bool enabled,
        uint16 maxOracleDeviationBps
    );

    error RouteNotApproved(bytes32 routeId);

    constructor(address authority_, IOracleRegistry oracleRegistry_) AccessManaged(authority_) {
        if (authority_ == address(0) || address(oracleRegistry_) == address(0)) revert ZeroAddress();
        oracleRegistry = oracleRegistry_;
    }

    function swapExactInput(SwapRequest calldata request, address recipient)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (request.amountIn == 0) revert ZeroAmount();
        if (block.timestamp > request.deadline) revert DeadlineExpired(request.deadline, block.timestamp);
        if (!_approvedAdapters[request.adapter]) revert NotApproved(request.adapter);

        bytes32 routeId = getRouteId(request.adapter, request.tokenIn, request.tokenOut);
        RouteConfig memory route = _routes[routeId];
        if (!route.enabled) revert RouteNotApproved(routeId);

        IERC20 tokenIn = IERC20(request.tokenIn);
        IERC20 tokenOut = IERC20(request.tokenOut);
        uint256 balanceBefore = tokenOut.balanceOf(recipient);

        tokenIn.safeTransferFrom(msg.sender, address(this), request.amountIn);
        tokenIn.forceApprove(request.adapter, request.amountIn);
        amountOut = IDexAdapter(request.adapter).swapExactInput(
            request.tokenIn, request.tokenOut, request.amountIn, request.minAmountOut, recipient, request.deadline
        );
        tokenIn.forceApprove(request.adapter, 0);

        uint256 balanceAfter = tokenOut.balanceOf(recipient);
        uint256 observedOut = balanceAfter - balanceBefore;
        if (observedOut < request.minAmountOut) revert InsufficientOutput(observedOut, request.minAmountOut);
        if (amountOut != observedOut) amountOut = observedOut;

        _enforceOracleDeviation(request, amountOut, route.maxOracleDeviationBps);
        emit SwapExecuted(request.adapter, request.tokenIn, request.tokenOut, request.amountIn, amountOut);
    }

    function isAdapterApproved(address adapter) external view returns (bool approved) {
        approved = _approvedAdapters[adapter];
    }

    function isRouteApproved(address adapter, address tokenIn, address tokenOut) external view returns (bool approved) {
        approved = _routes[getRouteId(adapter, tokenIn, tokenOut)].enabled;
    }

    function getRouteConfig(address adapter, address tokenIn, address tokenOut)
        external
        view
        returns (RouteConfig memory config)
    {
        config = _routes[getRouteId(adapter, tokenIn, tokenOut)];
    }

    function setAdapterApproval(address adapter, bool approved) external restricted {
        if (adapter == address(0)) revert ZeroAddress();
        _approvedAdapters[adapter] = approved;
        emit AdapterApprovalUpdated(adapter, approved);
    }

    function setRoute(
        address adapter,
        address tokenIn,
        address tokenOut,
        bool enabled,
        uint16 maxOracleDeviationBps
    ) external restricted {
        if (adapter == address(0) || tokenIn == address(0) || tokenOut == address(0)) revert ZeroAddress();
        if (maxOracleDeviationBps > Constants.MAX_BPS) revert InvalidBasisPoints(maxOracleDeviationBps);
        bytes32 routeId = getRouteId(adapter, tokenIn, tokenOut);
        _routes[routeId] = RouteConfig({enabled: enabled, maxOracleDeviationBps: maxOracleDeviationBps});
        emit RouteConfigured(routeId, adapter, tokenIn, tokenOut, enabled, maxOracleDeviationBps);
    }

    function getRouteId(address adapter, address tokenIn, address tokenOut) public pure returns (bytes32 routeId) {
        routeId = keccak256(abi.encode(adapter, tokenIn, tokenOut));
    }

    function _enforceOracleDeviation(SwapRequest calldata request, uint256 amountOut, uint16 maxDeviationBps)
        private
        view
    {
        if (maxDeviationBps == 0) return;

        (uint256 priceIn,) = oracleRegistry.getValidatedPrice(request.tokenIn);
        (uint256 priceOut,) = oracleRegistry.getValidatedPrice(request.tokenOut);
        uint8 decimalsIn = IERC20Metadata(request.tokenIn).decimals();
        uint8 decimalsOut = IERC20Metadata(request.tokenOut).decimals();

        uint256 expectedOut =
            request.amountIn.mulDiv(priceIn, priceOut).mulDiv(10 ** decimalsOut, 10 ** decimalsIn);
        if (expectedOut == 0) return;

        uint256 deviation = amountOut > expectedOut ? amountOut - expectedOut : expectedOut - amountOut;
        uint256 deviationBps = deviation.mulDiv(Constants.BPS, expectedOut, Math.Rounding.Ceil);
        if (deviationBps > maxDeviationBps) revert OracleDeviationExceeded(deviationBps, maxDeviationBps);
    }
}
