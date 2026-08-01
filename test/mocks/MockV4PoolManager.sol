// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @notice Minimal hookless PoolManager stand-in for strategy unit tests.
/// @dev The production strategy only reads slot0 through StateLibrary in these tests. The mock therefore
///      exposes the official extsload overloads and stores the same packed slot used by v4-core.
contract MockV4PoolManager {
    bytes32 private constant POOLS_SLOT = bytes32(uint256(6));

    mapping(bytes32 slot => bytes32 value) private _slots;

    function setSlot(bytes32 slot, bytes32 value) external {
        _slots[slot] = value;
    }

    function setSlot0(PoolId poolId, uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) external {
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
        uint256 packed = uint256(sqrtPriceX96);
        packed |= uint256(uint24(tick)) << 160;
        packed |= uint256(protocolFee) << 184;
        packed |= uint256(lpFee) << 208;
        _slots[stateSlot] = bytes32(packed);
    }

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        value = _slots[slot];
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values) {
        values = new bytes32[](nSlots);
        for (uint256 i; i < nSlots; ++i) {
            values[i] = _slots[bytes32(uint256(startSlot) + i)];
        }
    }

    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory values) {
        values = new bytes32[](slots.length);
        for (uint256 i; i < slots.length; ++i) {
            values[i] = _slots[slots[i]];
        }
    }
}
