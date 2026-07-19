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
}
