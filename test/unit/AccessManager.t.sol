// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";

contract AccessManagerTest is Test {
    AccessManager internal manager;
    address internal governance = makeAddr("governance");
    address internal outsider = makeAddr("outsider");
    address internal securityCouncil = makeAddr("securityCouncil");
    address internal target = makeAddr("target");

    uint64 internal GOVERNANCE_ROLE;
    uint64 internal STRATEGY_MANAGER_ROLE;
    uint64 internal KEEPER_ROLE;
    uint64 internal ORACLE_MANAGER_ROLE;
    uint64 internal REWARD_MANAGER_ROLE;
    uint64 internal SECURITY_COUNCIL_ROLE;

    function setUp() public {
        manager = new AccessManager(governance);
        GOVERNANCE_ROLE = manager.GOVERNANCE_ROLE();
        STRATEGY_MANAGER_ROLE = manager.STRATEGY_MANAGER_ROLE();
        KEEPER_ROLE = manager.KEEPER_ROLE();
        ORACLE_MANAGER_ROLE = manager.ORACLE_MANAGER_ROLE();
        REWARD_MANAGER_ROLE = manager.REWARD_MANAGER_ROLE();
        SECURITY_COUNCIL_ROLE = manager.SECURITY_COUNCIL_ROLE();
    }

    function testZeroInitialGovernanceReverts() public {
        vm.expectRevert();
        new AccessManager(address(0));
    }

    function testInitialGovernanceHasAdminRole() public view {
        (bool governanceIsAdmin,) = manager.hasRole(manager.ADMIN_ROLE(), governance);
        (bool outsiderIsAdmin,) = manager.hasRole(manager.ADMIN_ROLE(), outsider);
        assertTrue(governanceIsAdmin);
        assertFalse(outsiderIsAdmin);
    }

    function testRoleIdsAreDistinct() public view {
        uint64[6] memory roles = [
            GOVERNANCE_ROLE,
            STRATEGY_MANAGER_ROLE,
            KEEPER_ROLE,
            ORACLE_MANAGER_ROLE,
            REWARD_MANAGER_ROLE,
            SECURITY_COUNCIL_ROLE
        ];
        for (uint256 i; i < roles.length; ++i) {
            for (uint256 j = i + 1; j < roles.length; ++j) {
                assertNotEq(roles[i], roles[j]);
            }
        }
    }

    function testRoleAdministrationAndGuardianship() public view {
        assertEq(manager.getRoleAdmin(GOVERNANCE_ROLE), manager.ADMIN_ROLE());
        assertEq(manager.getRoleAdmin(SECURITY_COUNCIL_ROLE), GOVERNANCE_ROLE);

        uint64[4] memory operationalRoles =
            [STRATEGY_MANAGER_ROLE, KEEPER_ROLE, ORACLE_MANAGER_ROLE, REWARD_MANAGER_ROLE];
        for (uint256 i; i < operationalRoles.length; ++i) {
            assertEq(manager.getRoleAdmin(operationalRoles[i]), GOVERNANCE_ROLE);
            assertEq(manager.getRoleGuardian(operationalRoles[i]), SECURITY_COUNCIL_ROLE);
            (bool councilHoldsOperationalRole,) = manager.hasRole(operationalRoles[i], securityCouncil);
            assertFalse(councilHoldsOperationalRole);
        }
    }

    function testUnauthorizedCallerCannotGrantRole() public {
        vm.prank(outsider);
        vm.expectRevert();
        manager.grantRole(KEEPER_ROLE, outsider, 0);
    }

    function testGovernanceCanGrantOperationalRoleAfterGovernanceRoleGranted() public {
        vm.prank(governance);
        manager.grantRole(GOVERNANCE_ROLE, governance, 0);

        vm.prank(governance);
        manager.grantRole(KEEPER_ROLE, outsider, 0);
        (bool isKeeper,) = manager.hasRole(KEEPER_ROLE, outsider);
        assertTrue(isKeeper);
    }

    function testUnconfiguredSelectorIsAdminOnlyAndClosedTargetDeniesCall() public {
        bytes4 selector = bytes4(keccak256("rebalance()"));
        (bool adminCanCall,) = manager.canCall(governance, target, selector);
        (bool outsiderCanCall,) = manager.canCall(outsider, target, selector);
        assertTrue(adminCanCall);
        assertFalse(outsiderCanCall);

        vm.prank(governance);
        manager.setTargetClosed(target, true);
        (bool adminCanCallClosed,) = manager.canCall(governance, target, selector);
        assertFalse(adminCanCallClosed);
    }
}
