// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ValidateRobinHarvest} from "../../script/ValidateRobinHarvest.s.sol";

contract ValidateTestnetForkHarness is ValidateRobinHarvest {
    function validateTestnetFork(bool overrideVerified) external view {
        InitConfig memory config = _loadConfig();
        if (overrideVerified) {
            config.indexFinanceIntegrationVerified = true;
        }
        _validate(config);
    }
}

contract TestnetForkValidateTest is Test {
    ValidateTestnetForkHarness internal validator;

    function setUp() public {
        validator = new ValidateTestnetForkHarness();
    }

    function testForkValidationFailsWhenProvisionalWithoutVerificationFlag() public {
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert(ValidateRobinHarvest.ProvisionalIndexFinanceIntegration.selector);
        validator.validateTestnetFork(false);
    }

    function testForkValidationPassesWhenVerifiedFlagTrue() public {
        vm.warp(block.timestamp + 6 days);
        validator.validateTestnetFork(true);
    }
}
