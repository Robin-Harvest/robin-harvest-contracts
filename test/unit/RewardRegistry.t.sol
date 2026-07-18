// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {RewardRegistry} from "../../src/registries/RewardRegistry.sol";
import {RewardCategory, RewardDisposition, RewardTokenConfig} from "../../src/types/ProtocolTypes.sol";

contract RewardRegistryTest is Test {
    AccessManager internal manager;
    RewardRegistry internal registry;

    address internal governance = makeAddr("governance");
    address internal token = makeAddr("reward");
    address internal oracle = makeAddr("oracle");
    address internal adapter = makeAddr("adapter");

    function setUp() public {
        manager = new AccessManager(governance);
        registry = new RewardRegistry(address(manager));
    }

    function testConfigureRetainableReward() public {
        RewardTokenConfig memory config = _config(RewardDisposition.Retain);

        vm.prank(governance);
        registry.setRewardTokenConfig(token, config);

        RewardTokenConfig memory stored = registry.getRewardTokenConfig(token);
        assertTrue(stored.enabled);
        assertEq(uint8(stored.category), uint8(RewardCategory.Equity));
        assertEq(uint8(stored.disposition), uint8(RewardDisposition.Retain));
        assertTrue(registry.isRewardTokenEnabled(token));
    }

    function testSellDispositionRequiresApprovedAdapter() public {
        RewardTokenConfig memory config = _config(RewardDisposition.Sell);

        vm.prank(governance);
        vm.expectRevert();
        registry.setRewardTokenConfig(token, config);

        vm.prank(governance);
        registry.setAdapterApproval(token, adapter, true);
        vm.prank(governance);
        registry.setRewardTokenConfig(token, config);

        assertTrue(registry.isAdapterApproved(token, adapter));
    }

    function testRetainDispositionRequiresRetainableFlag() public {
        RewardTokenConfig memory config = _config(RewardDisposition.Retain);
        config.retainable = false;

        vm.prank(governance);
        vm.expectRevert();
        registry.setRewardTokenConfig(token, config);
    }

    function testDisableRewardPreservesConfigHistory() public {
        vm.prank(governance);
        registry.setRewardTokenConfig(token, _config(RewardDisposition.Retain));

        vm.prank(governance);
        registry.disableRewardToken(token);

        RewardTokenConfig memory stored = registry.getRewardTokenConfig(token);
        assertFalse(stored.enabled);
        assertEq(stored.oracle, oracle);
    }

    function testFuzzRejectsExposureAboveBps(uint16 exposureBps) public {
        vm.assume(exposureBps > 10_000);
        RewardTokenConfig memory config = _config(RewardDisposition.Ignore);
        config.maxExposureBps = exposureBps;

        vm.prank(governance);
        vm.expectRevert();
        registry.setRewardTokenConfig(token, config);
    }

    function _config(RewardDisposition disposition) private view returns (RewardTokenConfig memory config) {
        config = RewardTokenConfig({
            enabled: true,
            category: RewardCategory.Equity,
            disposition: disposition,
            oracle: oracle,
            minHarvestAmount: 1e18,
            retainable: true,
            adapter: adapter,
            maxExposureBps: 2_000
        });
    }
}
