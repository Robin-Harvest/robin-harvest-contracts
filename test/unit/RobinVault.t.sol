// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {StrategyBase} from "../../src/strategies/StrategyBase.sol";
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

    function testDeployUpdatesStrategyDebtCorrectly() public {
        vm.prank(user);
        vault.deposit(1_000 ether, user);

        vm.startPrank(governance);
        vault.deploy(500 ether);
        vm.stopPrank();

        assertEq(vault.strategyDebt(), 500 ether);
        assertEq(index.balanceOf(address(vault)), 500 ether);
        assertEq(strategy.deployedAssets(), 500 ether);
    }

    function testVaultStrategyReentrancyPrevention() public {
        ReenteringStrategy reentrantStrategy = new ReenteringStrategy(address(vault), index, address(manager));
        
        vm.prank(governance);
        vault.setStrategy(address(reentrantStrategy));

        vm.prank(user);
        vault.deposit(100 ether, user);

        // 1. Test reentrancy during deploy
        reentrantStrategy.setReenterDeploy(true);
        vm.prank(governance);
        vm.expectRevert(); // Should revert due to reentrancy lock on vault.deploy
        vault.deploy(50 ether);

        // 2. Test reentrancy during withdraw (which triggers freeFunds)
        reentrantStrategy.setReenterDeploy(false);
        vm.prank(governance);
        vault.deploy(50 ether); // Success deploy first

        reentrantStrategy.setReenterFree(true);
        vm.prank(user);
        vm.expectRevert(); // Should revert due to reentrancy lock on vault.withdraw
        vault.withdraw(80 ether, receiver, user);
    }
}

contract ReenteringStrategy is StrategyBase {
    bool public reenterDeploy;
    bool public reenterFree;
    uint256 public deployedAssets;

    constructor(address vault_, IERC20 asset_, address authority_) StrategyBase(vault_, asset_, authority_) {}

    function setReenterDeploy(bool val) external {
        reenterDeploy = val;
    }

    function setReenterFree(bool val) external {
        reenterFree = val;
    }

    function _deployFunds(uint256 amount) internal override {
        if (reenterDeploy) {
            RobinVault(vault).deploy(amount);
        }
        MockINDEX(asset()).burn(address(this), amount);
        deployedAssets += amount;
    }

    function _freeFunds(uint256 amount) internal override returns (uint256 loss) {
        if (reenterFree) {
            RobinVault(vault).withdraw(amount, address(this), address(this));
        }
        deployedAssets -= amount;
        MockINDEX(asset()).mint(address(this), amount);
        return 0;
    }

    function _processRewardToken(address) internal pure override returns (uint256) {
        return 0;
    }

    function _emergencyWithdraw() internal pure override returns (uint256) {
        return 0;
    }

    function _deployedAssets() internal view override returns (uint256) {
        return deployedAssets;
    }
}
