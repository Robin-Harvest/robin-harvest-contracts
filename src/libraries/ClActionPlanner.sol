// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {ActionConstants} from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @title Concentrated Liquidity Action Planner
/// @notice Builds PositionManager `modifyLiquidities` payloads using official v4 periphery action codes.
library ClActionPlanner {
    struct Plan {
        bytes actions;
        bytes[] params;
    }

    /// @notice Initializes an empty action plan.
    function init() internal pure returns (Plan memory plan) {
        plan.actions = bytes("");
        plan.params = new bytes[](0);
    }

    /// @notice Appends an action and parameter pair to the plan.
    function add(Plan memory plan, uint256 action, bytes memory param) internal pure returns (Plan memory) {
        bytes memory actions = new bytes(plan.params.length + 1);
        bytes[] memory params = new bytes[](plan.params.length + 1);

        for (uint256 i; i < plan.params.length; ++i) {
            actions[i] = plan.actions[i];
            params[i] = plan.params[i];
        }

        actions[params.length - 1] = bytes1(uint8(action));
        params[params.length - 1] = param;
        plan.actions = actions;
        plan.params = params;
        return plan;
    }

    /// @notice Encodes a plan into the strict ABI layout expected by the v4 PositionManager.
    function encode(Plan memory plan) internal pure returns (bytes memory unlockData) {
        unlockData = abi.encode(plan.actions, plan.params);
    }

    /// @notice Builds a mint-position plan that settles both currencies from the caller.
    function planMintPosition(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address owner,
        bytes memory hookData
    ) public pure returns (bytes memory unlockData) {
        Plan memory plan = init();
        plan = add(
            plan,
            Actions.MINT_POSITION,
            abi.encode(key, tickLower, tickUpper, liquidity, amount0Max, amount1Max, owner, hookData)
        );
        plan = add(plan, Actions.SETTLE_PAIR, abi.encode(key.currency0, key.currency1));
        unlockData = encode(plan);
    }

    /// @notice Builds a full liquidity removal and NFT burn plan.
    function planClosePosition(
        PoolKey memory key,
        uint256 tokenId,
        uint128 liquidity,
        uint128 amount0Min,
        uint128 amount1Min,
        address recipient,
        bytes memory hookData
    ) public pure returns (bytes memory unlockData) {
        Plan memory plan = init();
        plan = add(plan, Actions.DECREASE_LIQUIDITY, abi.encode(tokenId, liquidity, amount0Min, amount1Min, hookData));
        plan = add(plan, Actions.TAKE_PAIR, abi.encode(key.currency0, key.currency1, recipient));
        plan = add(plan, Actions.BURN_POSITION, abi.encode(tokenId, amount0Min, amount1Min, hookData));
        unlockData = encode(plan);
    }

    /// @notice Encodes an increase-liquidity action with settlement for both pool currencies.
    function planIncreaseLiquidity(
        PoolKey memory key,
        uint256 tokenId,
        uint128 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        bytes memory hookData
    ) public pure returns (bytes memory unlockData) {
        Plan memory plan = init();
        plan = add(
            plan, Actions.INCREASE_LIQUIDITY, abi.encode(tokenId, uint256(liquidity), amount0Max, amount1Max, hookData)
        );
        plan = add(plan, Actions.SETTLE_PAIR, abi.encode(key.currency0, key.currency1));
        unlockData = encode(plan);
    }

    function planCollectFees(PoolKey memory key, uint256 tokenId, address recipient, bytes memory hookData)
        public
        pure
        returns (bytes memory unlockData)
    {
        Plan memory plan = init();
        plan = add(plan, Actions.DECREASE_LIQUIDITY, abi.encode(tokenId, uint256(0), uint128(0), uint128(0), hookData));
        plan = add(plan, Actions.TAKE_PAIR, abi.encode(key.currency0, key.currency1, recipient));
        unlockData = encode(plan);
    }

    /// @notice Builds a single-pool exact-input swap plan with settlement and take to recipient.
    function planSwapExactInput(Currency inputCurrency, Currency outputCurrency, address recipient)
        internal
        pure
        returns (Plan memory plan)
    {
        plan = init();
        plan = add(plan, Actions.SETTLE, abi.encode(inputCurrency, ActionConstants.OPEN_DELTA, true));
        plan = add(plan, Actions.TAKE, abi.encode(outputCurrency, recipient, ActionConstants.OPEN_DELTA));
    }
}
