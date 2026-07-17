// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessManager as OpenZeppelinAccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/// @title Robin Harvest Access Manager
/// @notice Central authority for delayed, role-based protocol administration.
/// @dev Selector assignments and production role holders are deliberately configured after deployment.
contract AccessManager is OpenZeppelinAccessManager {
    uint64 public constant GOVERNANCE_ROLE = 1;
    uint64 public constant STRATEGY_MANAGER_ROLE = 2;
    uint64 public constant KEEPER_ROLE = 3;
    uint64 public constant ORACLE_MANAGER_ROLE = 4;
    uint64 public constant REWARD_MANAGER_ROLE = 5;
    uint64 public constant SECURITY_COUNCIL_ROLE = 6;

    /// @notice Deploys the authority with one immediate OpenZeppelin root administrator.
    /// @param initialGovernance The initial governance or deployment authority.
    constructor(address initialGovernance) OpenZeppelinAccessManager(initialGovernance) {
        _configureOperationalRole(STRATEGY_MANAGER_ROLE);
        _configureOperationalRole(KEEPER_ROLE);
        _configureOperationalRole(ORACLE_MANAGER_ROLE);
        _configureOperationalRole(REWARD_MANAGER_ROLE);

        _setRoleAdmin(GOVERNANCE_ROLE, ADMIN_ROLE);
        _setRoleGuardian(GOVERNANCE_ROLE, SECURITY_COUNCIL_ROLE);
        _setRoleAdmin(SECURITY_COUNCIL_ROLE, GOVERNANCE_ROLE);
        _setRoleGuardian(SECURITY_COUNCIL_ROLE, SECURITY_COUNCIL_ROLE);
    }

    function _configureOperationalRole(uint64 roleId) private {
        _setRoleAdmin(roleId, GOVERNANCE_ROLE);
        _setRoleGuardian(roleId, SECURITY_COUNCIL_ROLE);
    }
}
