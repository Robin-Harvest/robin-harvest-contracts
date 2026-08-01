// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/// @notice Minimal Permit2 allowance surface for testing exact approvals and cleanup.
contract MockPermit2 {
    struct StoredAllowance {
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }

    mapping(address owner => mapping(address token => mapping(address spender => StoredAllowance))) private _allowances;

    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        StoredAllowance storage allowance_ = _allowances[msg.sender][token][spender];
        allowance_.amount = amount;
        allowance_.expiration = expiration;
        emit IAllowanceTransfer.Approval(msg.sender, token, spender, amount, expiration);
    }

    function allowance(address owner, address token, address spender)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce)
    {
        StoredAllowance memory allowance_ = _allowances[owner][token][spender];
        return (allowance_.amount, allowance_.expiration, allowance_.nonce);
    }
}
