// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {RobinAccountant} from "../../src/accounting/RobinAccountant.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {FeeConfig} from "../../src/types/ProtocolTypes.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {TestStrategy} from "../helpers/TestStrategy.sol";

contract RobinAccountantTest is Test {
    AccessManager internal manager;
    MockINDEX internal index;
    RobinVault internal vault;
    RobinAccountant internal accountant;
    TestStrategy internal strategy;

    address internal governance = makeAddr("governance");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal user = makeAddr("user");

    function setUp() public {
        manager = new AccessManager(governance);
        index = new MockINDEX(18);
        vault = new RobinVault(index, "Robin INDEX Vault", "rhINDEX", address(manager));
        strategy = new TestStrategy(address(vault), index, address(manager));
        accountant = new RobinAccountant(index, address(manager));

        vm.startPrank(governance);
        vault.setStrategy(address(strategy));
        vault.setAccountant(address(accountant));
        accountant.setVault(address(vault));
        accountant.setFeeRecipient(feeRecipient);
        accountant.setFeeConfig(FeeConfig({performanceBps: 2_000, managementBps: 200}));
        vm.stopPrank();

        index.mint(user, 10_000 ether);
        vm.prank(user);
        index.approve(address(vault), type(uint256).max);
        vm.prank(user);
        vault.deposit(1_000 ether, user);
        vm.prank(governance);
        vault.deploy(900 ether);
    }

    function testPerformanceFeeUsesHighWaterMark() public {
        vm.prank(governance);
        strategy.reportGainToDebt(100 ether);

        assertEq(index.balanceOf(feeRecipient), 20 ether);
        assertEq(accountant.highWaterMark(), 1_100 ether);
    }

    function testNoPerformanceFeeWhileRecoveringLoss() public {
        vm.startPrank(governance);
        strategy.reportGainToDebt(100 ether);
        strategy.reportLoss(50 ether);
        strategy.reportGainToDebt(50 ether);
        vm.stopPrank();

        assertEq(index.balanceOf(feeRecipient), 20 ether);
    }

    function testFuzzFeeSplitMath(uint96 grossAssets, uint96 reportedGain) public {
        uint256 gross = bound(uint256(grossAssets), 1, 100_000_000 ether);
        uint256 gain = bound(uint256(reportedGain), 0, gross);

        // Management fee: 200 bps / year. We fast forward exactly 1 year to make math exact.
        vm.warp(block.timestamp + 365 days);

        vm.prank(address(vault));
        (uint256 perfFee, uint256 mgmtFee) = accountant.assessReportFees(gross, gain);

        // Performance fee should be 20% of gain
        assertEq(perfFee, (gain * 2000) / 10000, "Performance fee math incorrect");

        // Management fee should be 2% of gross assets after exactly 1 year
        assertEq(mgmtFee, (gross * 200) / 10000, "Management fee math incorrect");
    }

    function testFuzzHighWaterMarkDrift(uint16[5] calldata gains, uint16[5] calldata losses) public {
        // High water mark should only rise on net positive gain, and never fall.
        uint256 startHwm = accountant.highWaterMark();
        uint256 currentHwm = startHwm;

        for (uint256 i = 0; i < 5; i++) {
            uint256 gain = uint256(gains[i]) * 1 ether;
            uint256 loss = uint256(losses[i]) * 1 ether;

            vm.startPrank(governance);
            if (gain > 0) strategy.reportGainToDebt(gain);
            if (loss > 0) strategy.reportLoss(loss);
            vm.stopPrank();

            uint256 newHwm = accountant.highWaterMark();
            assertGe(newHwm, currentHwm, "High water mark decreased!");
            currentHwm = newHwm;
        }
    }

    function testZeroFeeMintPath() public {
        // Test that 0 fee config results in 0 fees and 0 transfers
        vm.prank(governance);
        accountant.setFeeConfig(FeeConfig({performanceBps: 0, managementBps: 0}));

        vm.warp(block.timestamp + 365 days);

        vm.prank(address(vault));
        (uint256 perfFee, uint256 mgmtFee) = accountant.assessReportFees(1000 ether, 100 ether);

        assertEq(perfFee, 0);
        assertEq(mgmtFee, 0);
    }
}
