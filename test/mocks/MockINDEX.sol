// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Deterministic mintable INDEX stand-in for tests.
/// @dev TEST-ONLY. Unsafe for production deployment.
contract MockINDEX is ERC20 {
    uint8 private immutable _mockDecimals;

    constructor(uint8 decimals_) ERC20("Mock INDEX", "mINDEX") {
        _mockDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _mockDecimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
