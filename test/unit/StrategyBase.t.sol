// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {LifecycleState} from "../../src/types/ProtocolTypes.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {TestStrategy} from "../helpers/TestStrategy.sol";

contract StrategyBaseTest is Test {
    AccessManager internal manager;
    MockINDEX internal index;
    MockStockToken internal rewardA;
    MockStockToken internal rewardB;
    RobinVault internal vault;
    TestStrategy internal strategy;

    address internal governance = makeAddr("governance");
    address internal user = makeAddr("user");

    function setUp() public {
        manager = new AccessManager(governance);
        index = new MockINDEX(18);
        rewardA = new MockStockToken("Reward A", "rA", 18);
        rewardB = new MockStockToken("Reward B", "rB", 18);
        vault = new RobinVault(index, "Robin INDEX Vault", "rhINDEX", address(manager));
        strategy = new TestStrategy(address(vault), index, address(manager));

        vm.prank(governance);
        vault.setStrategy(address(strategy));

        index.mint(user, 1_000 ether);
        vm.prank(user);
        index.approve(address(vault), type(uint256).max);
    }

    function testOnlyVaultCanDeployFunds() public {
        index.mint(address(strategy), 100 ether);

        vm.prank(user);
        vm.expectRevert();
        strategy.deployFunds(100 ether);
    }

    function testLifecyclePauseBlocksTendAndHarvest() public {
        vm.prank(governance);
        strategy.pause();

        assertEq(uint8(strategy.lifecycleState()), uint8(LifecycleState.Paused));

        vm.prank(governance);
        vm.expectRevert();
        strategy.tend();

        vm.prank(governance);
        vm.expectRevert();
        strategy.harvest();
    }

    function testRewardFailuresAreIsolatedPerToken() public {
        vm.startPrank(governance);
        strategy.addRewardToken(address(rewardA));
        strategy.addRewardToken(address(rewardB));
        vm.stopPrank();

        strategy.setRewardShouldFail(address(rewardA), true);

        vm.prank(governance);
        strategy.harvest();

        assertTrue(strategy.isRewardTokenIsolated(address(rewardA)));
        assertFalse(strategy.isRewardTokenIsolated(address(rewardB)));
    }

    function testEmergencyWithdrawReturnsDeployedFundsAndShutsDown() public {
        vm.prank(user);
        vault.deposit(1_000 ether, user);
        vm.prank(governance);
        vault.deploy(500 ether);

        vm.prank(governance);
        (uint256 freed, uint256 loss) = strategy.emergencyWithdraw();

        assertEq(freed, 500 ether);
        assertEq(loss, 0);
        assertEq(index.balanceOf(address(vault)), 1_000 ether);
        assertEq(uint8(strategy.lifecycleState()), uint8(LifecycleState.Shutdown));
    }

    function testFuzzFreeFundsRepaysUpToRequestedAmount(uint96 requested) public {
        uint256 amount = bound(uint256(requested), 1, 500 ether);

        vm.prank(user);
        vault.deposit(1_000 ether, user);
        vm.prank(governance);
        vault.deploy(500 ether);

        vm.prank(user);
        vault.withdraw(amount, user, user, 100);

        assertEq(index.balanceOf(user), amount);
    }

    function testRewardTokenTrackingAndRemoval() public {
        vm.startPrank(governance);
        strategy.addRewardToken(address(rewardA));
        strategy.addRewardToken(address(rewardB));

        assertTrue(strategy.isRewardTokenTracked(address(rewardA)));
        assertTrue(strategy.isRewardTokenTracked(address(rewardB)));

        address[] memory tokensBefore = strategy.rewardTokens();
        assertEq(tokensBefore.length, 2);
        assertEq(tokensBefore[0], address(rewardA));
        assertEq(tokensBefore[1], address(rewardB));

        strategy.removeRewardToken(address(rewardA));
        assertFalse(strategy.isRewardTokenTracked(address(rewardA)));
        assertTrue(strategy.isRewardTokenTracked(address(rewardB)));

        address[] memory tokensAfter = strategy.rewardTokens();
        assertEq(tokensAfter.length, 1);
        assertEq(tokensAfter[0], address(rewardB));
        vm.stopPrank();
    }

    function testRewardTokenRemovalClearsIsolation() public {
        vm.startPrank(governance);
        strategy.addRewardToken(address(rewardA));
        strategy.setRewardTokenIsolated(address(rewardA), true);
        
        assertTrue(strategy.isRewardTokenIsolated(address(rewardA)));
        
        strategy.removeRewardToken(address(rewardA));
        assertFalse(strategy.isRewardTokenIsolated(address(rewardA)));
        
        strategy.addRewardToken(address(rewardA));
        assertFalse(strategy.isRewardTokenIsolated(address(rewardA)));
        
        vm.stopPrank();
    }
}
