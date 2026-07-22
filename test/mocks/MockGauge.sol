// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockINDEX} from "./MockINDEX.sol";

contract MockGauge {
    IERC20 public immutable stakingToken;
    MockINDEX public immutable rewardToken;

    mapping(address => uint256) public balanceOf;

    constructor(IERC20 stakingToken_, MockINDEX rewardToken_) {
        stakingToken = stakingToken_;
        rewardToken = rewardToken_;
    }

    function deposit(uint256 amount) external {
        stakingToken.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "INSUFFICIENT_BALANCE");
        balanceOf[msg.sender] -= amount;
        stakingToken.transfer(msg.sender, amount);
    }

    function getReward() external {
        // Mint 10 INDEX rewards to caller on claim
        rewardToken.mint(msg.sender, 10 ether);
    }
}
