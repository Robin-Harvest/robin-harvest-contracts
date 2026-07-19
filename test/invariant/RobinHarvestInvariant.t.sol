// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {TestStrategy} from "../helpers/TestStrategy.sol";

contract RobinHarvestHandler is Test {
    AccessManager public manager;
    MockINDEX public index;
    RobinVault public vault;
    TestStrategy public strategy;
    address public governance = address(0xA11CE);
    address public user = address(0xB0B);

    constructor() {
        manager = new AccessManager(governance);
        index = new MockINDEX(18);
        vault = new RobinVault(index, "Invariant Vault", "rhINV", address(manager));
        strategy = new TestStrategy(address(vault), index, address(manager));
        vm.prank(governance);
        vault.setStrategy(address(strategy));
        index.mint(user, 1_000_000 ether);
        vm.prank(user);
        index.approve(address(vault), type(uint256).max);
    }

    function deposit(uint96 assets) external {
        assets = uint96(bound(uint256(assets), 1, 10_000 ether));
        if (assets > index.balanceOf(user)) return;
        vm.prank(user);
        vault.deposit(assets, user);
    }

    function withdraw(uint96 assets) external {
        uint256 maxWithdrawable = vault.maxWithdraw(user);
        if (maxWithdrawable == 0) return;
        assets = uint96(bound(uint256(assets), 1, maxWithdrawable));
        vm.prank(user);
        vault.withdraw(assets, user, user);
    }

    function reportGain(uint96 gain) external {
        gain = uint96(bound(uint256(gain), 1, 1_000 ether));
        vm.prank(governance);
        strategy.reportGainToDebt(gain);
    }
}

contract RobinHarvestInvariantTest is StdInvariant, Test {
    RobinHarvestHandler internal handler;

    function setUp() public {
        handler = new RobinHarvestHandler();
        targetContract(address(handler));
    }

    function invariant_totalSupplyMatchesUserShares() public view {
        assertEq(handler.vault().totalSupply(), handler.vault().balanceOf(handler.user()));
    }

    function invariant_strategyDebtMatchesDeployedAssets() public view {
        assertGe(handler.vault().strategyDebt(), handler.strategy().deployedAssets());
    }
}
