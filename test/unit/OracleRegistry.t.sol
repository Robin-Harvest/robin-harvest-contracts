// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {OracleRegistry} from "../../src/registries/OracleRegistry.sol";
import {OracleConfig} from "../../src/types/ProtocolTypes.sol";
import {MockOracle} from "../mocks/MockOracle.sol";

contract OracleRegistryTest is Test {
    AccessManager internal manager;
    OracleRegistry internal registry;
    MockOracle internal feed;

    address internal governance = makeAddr("governance");
    address internal asset = makeAddr("asset");

    function setUp() public {
        manager = new AccessManager(governance);
        registry = new OracleRegistry(address(manager));
        feed = new MockOracle(8, 123_00000000);
    }

    function testGovernanceRegistersAndNormalizesPrice() public {
        vm.prank(governance);
        registry.setOracleConfig(asset, _config(address(feed), false));

        (uint256 price, uint256 updatedAt) = registry.getValidatedPrice(asset);

        assertEq(price, 123 ether);
        assertEq(updatedAt, block.timestamp);
    }

    function testUiMultiplierAdjustsNormalizedPrice() public {
        vm.prank(governance);
        registry.setOracleConfig(asset, _config(address(feed), false));
        vm.prank(governance);
        registry.setUiMultiplier(asset, 2e18);

        (uint256 price,) = registry.getValidatedPrice(asset);
        assertEq(price, 246 ether);
    }

    function testStalePriceReverts() public {
        vm.prank(governance);
        registry.setOracleConfig(asset, _config(address(feed), false));

        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert();
        registry.getValidatedPrice(asset);
    }

    function testNegativeOrIncompleteRoundReverts() public {
        vm.prank(governance);
        registry.setOracleConfig(asset, _config(address(feed), false));

        feed.setRoundData(2, -1, block.timestamp, block.timestamp, 1);
        vm.expectRevert();
        registry.getValidatedPrice(asset);
    }

    function testPausedFeedReverts() public {
        vm.prank(governance);
        registry.setOracleConfig(asset, _config(address(feed), true));

        vm.expectRevert();
        registry.getValidatedPrice(asset);
    }

    function testFuzzPositivePricesNormalize(uint96 rawPrice) public {
        uint256 bounded = bound(uint256(rawPrice), 1, type(uint80).max);
        feed.setRoundData(1, int256(bounded), block.timestamp, block.timestamp, 1);

        vm.prank(governance);
        registry.setOracleConfig(asset, _config(address(feed), false));

        (uint256 price,) = registry.getValidatedPrice(asset);
        assertEq(price, bounded * 1e10);
    }

    function _config(address feed_, bool paused) private pure returns (OracleConfig memory config) {
        config = OracleConfig({
            feed: feed_, heartbeat: 1 hours, decimals: 8, maxDeviationBps: 500, uiMultiplier: 1e18, paused: paused
        });
    }
}
