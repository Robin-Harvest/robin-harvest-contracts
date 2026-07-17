// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStockToken} from "../../src/interfaces/external/IStockToken.sol";

/// @notice Deterministic tokenized-stock stand-in for tests.
/// @dev TEST-ONLY and UNCONFIRMED against live stock-token contracts. Unsafe for production.
contract MockStockToken is ERC20, IStockToken {
    error TransfersPaused();

    uint8 private immutable _mockDecimals;
    bool public override transfersEnabled = true;
    uint256 public override corporateActionMultiplier = 1e18;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _mockDecimals = decimals_;
    }

    function decimals() public view override(ERC20, IStockToken) returns (uint8) {
        return _mockDecimals;
    }

    function name() public view override(ERC20, IStockToken) returns (string memory) {
        return super.name();
    }

    function symbol() public view override(ERC20, IStockToken) returns (string memory) {
        return super.symbol();
    }

    function setTransfersEnabled(bool enabled) external {
        transfersEnabled = enabled;
    }

    function setCorporateActionMultiplier(uint256 multiplier) external {
        corporateActionMultiplier = multiplier;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (!transfersEnabled && from != address(0) && to != address(0)) revert TransfersPaused();
        super._update(from, to, value);
    }
}
