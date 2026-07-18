// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {TestStrategy} from "../helpers/TestStrategy.sol";

contract RobinVaultTest is Test {
    AccessManager internal manager;
    MockINDEX internal index;
    RobinVault internal vault;
    TestStrategy internal strategy;

    address internal governance = makeAddr("governance");
    address internal user = makeAddr("user");
    address internal receiver = makeAddr("receiver");

    function setUp() public {
        manager = new AccessManager(governance);
        index = new MockINDEX(18);
        vault = new RobinVault(index, "Robin INDEX Vault", "rhINDEX", address(manager));
        strategy = new TestStrategy(address(vault), index, address(manager));

        vm.prank(governance);
        vault.setStrategy(address(strategy));

        index.mint(user, 10_000 ether);
        vm.prank(user);
        index.approve(address(vault), type(uint256).max);
    }

    function testDepositMintsSharesAndRespectsCap() public {
        vm.prank(governance);
        vault.setDepositCap(100 ether);

        vm.prank(user);
        vault.deposit(100 ether, user);

        assertEq(vault.totalAssets(), 100 ether);
        assertGt(vault.balanceOf(user), 100 ether);

        vm.prank(user);
        vm.expectRevert();
        vault.deposit(1, user);
    }

    function testFuzzDepositShareAccounting(uint96 amount) public {
        uint256 assets = bound(uint256(amount), 1, index.balanceOf(user));

        vm.prank(user);
        uint256 shares = vault.deposit(assets, user);

        assertEq(vault.balanceOf(user), shares);
        assertEq(vault.totalAssets(), assets);
        assertApproxEqAbs(vault.convertToAssets(shares), assets, 1);
    }

    function testPauseStopsDepositsButAllowsWithdrawals() public {
        vm.prank(user);
        vault.deposit(100 ether, user);

        vm.prank(governance);
        vault.pause();

        vm.prank(user);
        vm.expectRevert();
        vault.deposit(1 ether, user);

        vm.prank(user);
        vault.withdraw(10 ether, receiver, user);
        assertEq(index.balanceOf(receiver), 10 ether);
    }

    function testDeployIdleCreatesStrategyDebtAndHonorsBuffer() public {
        vm.prank(user);
        vault.deposit(1_000 ether, user);

        vm.startPrank(governance);
        vault.setIdleBufferBps(1_000);
        uint256 deployed = vault.deployIdle();
        vm.stopPrank();

        assertEq(deployed, 900 ether);
        assertEq(vault.strategyDebt(), 900 ether);
        assertEq(index.balanceOf(address(vault)), 100 ether);
        assertEq(strategy.deployedAssets(), 900 ether);
    }

    function testWithdrawFreesStrategyFundsWithinMaxLoss() public {
        vm.prank(user);
        vault.deposit(1_000 ether, user);
        vm.prank(governance);
        vault.deploy(900 ether);

        strategy.setNextLoss(1 ether);
        vm.prank(user);
        vault.withdraw(500 ether, receiver, user, 30);

        assertEq(index.balanceOf(receiver), 500 ether);
        assertEq(vault.strategyDebt(), 499 ether);
    }

    function testWithdrawRevertsWhenLossExceedsMaxLoss() public {
        vm.prank(user);
        vault.deposit(1_000 ether, user);
        vm.prank(governance);
        vault.deploy(900 ether);

        strategy.setNextLoss(50 ether);
        vm.prank(user);
        vm.expectRevert();
        vault.withdraw(500 ether, receiver, user, 100);
    }

    function testReportedProfitUnlocksLinearly() public {
        vm.prank(user);
        vault.deposit(1_000 ether, user);
        vm.prank(governance);
        vault.deploy(1_000 ether);

        strategy.addDeployedProfit(100 ether);
        vm.prank(governance);
        strategy.harvest();

        assertEq(vault.strategyDebt(), 1_100 ether);
        assertEq(vault.lockedProfit(), 100 ether);
        assertEq(vault.totalAssets(), 1_000 ether);

        vm.warp(block.timestamp + vault.profitMaxUnlockTime());
        assertEq(vault.totalAssets(), 1_100 ether);
    }

    function testDonationDoesNotBreakFirstDepositorShareProtection() public {
        index.mint(address(vault), 100 ether);

        vm.prank(user);
        uint256 shares = vault.deposit(1 ether, user);

        assertGt(shares, 0);
    }

    function testMinPostWithdrawEligibilityHookReverts() public {
        vm.prank(user);
        vault.deposit(1_000 ether, user);
        vm.prank(governance);
        vault.setMinPostWithdrawAssets(900 ether);

        vm.prank(user);
        vm.expectRevert();
        vault.withdraw(200 ether, receiver, user);
    }
}
