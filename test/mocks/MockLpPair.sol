// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockLpPair is ERC20 {
    address public immutable token0;
    address public immutable token1;

    uint112 private _reserve0;
    uint112 private _reserve1;

    constructor(address token0_, address token1_) ERC20("Mock LP Pair", "mLp") {
        token0 = token0_;
        token1 = token1_;
        _reserve0 = 100_000 ether;
        _reserve1 = 100_000 ether;
    }

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = uint32(block.timestamp);
    }

    function setReserves(uint112 reserve0, uint112 reserve1) external {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external returns (uint256 amount0, uint256 amount1) {
        uint256 total = totalSupply();
        amount0 = total == 0 ? 0 : uint256(_reserve0) * amount / total;
        amount1 = total == 0 ? 0 : uint256(_reserve1) * amount / total;

        _burn(address(this), amount);

        _reserve0 = uint112(uint256(_reserve0) - amount0);
        _reserve1 = uint112(uint256(_reserve1) - amount1);

        IERC20(token0).transfer(to, amount0);
        IERC20(token1).transfer(to, amount1);
    }
}
