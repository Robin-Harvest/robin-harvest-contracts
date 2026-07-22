// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockLpPair} from "./MockLpPair.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MockLpRouter {
    using Math for uint256;

    MockLpPair public immutable pair;

    constructor(MockLpPair pair_) {
        pair = pair_;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(block.timestamp <= deadline, "EXPIRED");
        require(amountADesired >= amountAMin && amountBDesired >= amountBMin, "INSUFFICIENT_OUTPUT");

        IERC20(tokenA).transferFrom(msg.sender, address(pair), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(pair), amountBDesired);

        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = (amountA + amountB) / 2;

        pair.mint(to, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(block.timestamp <= deadline, "EXPIRED");

        pair.transferFrom(msg.sender, address(pair), liquidity);
        (uint256 amount0, uint256 amount1) = pair.burn(to, liquidity);

        amountA = tokenA == pair.token0() ? amount0 : amount1;
        amountB = tokenA == pair.token0() ? amount1 : amount0;

        require(amountA >= amountAMin && amountB >= amountBMin, "INSUFFICIENT_OUTPUT");
    }
}
