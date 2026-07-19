// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {StrategyBase} from "../../src/strategies/StrategyBase.sol";
import {IRobinVaultReport} from "../../src/interfaces/IRobinVaultReport.sol";
import {HarvestReport} from "../../src/types/ProtocolTypes.sol";

contract TestStrategy is StrategyBase {
    using SafeERC20 for IERC20;

    uint256 public deployedAssets;
    uint256 public nextLoss;
    mapping(address token => bool shouldFail) public rewardShouldFail;

    constructor(address vault_, MockINDEX asset_, address authority_) StrategyBase(vault_, asset_, authority_) {}

    function setNextLoss(uint256 loss) external {
        nextLoss = loss;
    }

    function addDeployedProfit(uint256 amount) external {
        deployedAssets += amount;
    }

    function setRewardShouldFail(address token, bool shouldFail) external {
        rewardShouldFail[token] = shouldFail;
    }

    function reportGain(uint256 gain) external {
        MockINDEX(asset()).mint(address(this), gain);
        IERC20(asset()).safeTransfer(vault, gain);
        IRobinVaultReport(vault).report(HarvestReport({gain: gain, loss: 0, debtPayment: gain}));
        lastReportedAssets = totalAssets();
    }

    function reportGainToDebt(uint256 gain) external {
        deployedAssets += gain;
        IRobinVaultReport(vault).report(HarvestReport({gain: gain, loss: 0, debtPayment: 0}));
        lastReportedAssets = totalAssets();
    }

    function reportLoss(uint256 loss) external {
        if (loss > deployedAssets) loss = deployedAssets;
        deployedAssets -= loss;
        IRobinVaultReport(vault).report(HarvestReport({gain: 0, loss: loss, debtPayment: 0}));
        lastReportedAssets = totalAssets();
    }

    function _deployFunds(uint256 amount) internal override {
        MockINDEX(asset()).burn(address(this), amount);
        deployedAssets += amount;
    }

    function _freeFunds(uint256 amount) internal override returns (uint256 loss) {
        loss = nextLoss;
        nextLoss = 0;
        uint256 requestedWithLoss = amount + loss;
        if (requestedWithLoss > deployedAssets) {
            requestedWithLoss = deployedAssets;
            loss = requestedWithLoss > amount ? requestedWithLoss - amount : 0;
        }
        uint256 freed = requestedWithLoss - loss;
        deployedAssets -= requestedWithLoss;
        if (freed != 0) MockINDEX(asset()).mint(address(this), freed);
    }

    function _processRewardToken(address token) internal view override returns (uint256) {
        if (rewardShouldFail[token]) revert("reward failed");
        return IERC20(token).balanceOf(address(this));
    }

    function _emergencyWithdraw() internal override returns (uint256) {
        uint256 deployed = deployedAssets;
        deployedAssets = 0;
        if (deployed != 0) MockINDEX(asset()).mint(address(this), deployed);
        return 0;
    }

    function _deployedAssets() internal view override returns (uint256) {
        return deployedAssets;
    }
}
