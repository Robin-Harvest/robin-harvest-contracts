// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/// @notice Minimal PositionManager stand-in that understands the action plans emitted by ClActionPlanner.
/// @dev It intentionally does not implement the full ERC-721 surface. Tests pass its address through the official
///      IPositionManager interface, while this mock records liquidity mutations needed by the strategy boundary.
contract MockV4PositionManager {
    address public permit2;
    uint256 private _nextTokenId = 1;
    mapping(uint256 tokenId => uint128 liquidity) private _liquidity;
    uint256 private _returnAmount0;
    uint256 private _returnAmount1;
    Currency private _currency0;
    Currency private _currency1;
    uint256 private _pendingAmount0;
    uint256 private _pendingAmount1;
    uint160 public lastObservedPermit2Amount0;
    uint160 public lastObservedPermit2Amount1;

    function setPermit2(address permit2_) external {
        permit2 = permit2_;
    }

    function setPositionLiquidity(uint256 tokenId, uint128 liquidity) external {
        _liquidity[tokenId] = liquidity;
    }

    function setReturnAmounts(uint256 amount0, uint256 amount1) external {
        _returnAmount0 = amount0;
        _returnAmount1 = amount1;
    }

    function nextTokenId() external view returns (uint256 tokenId) {
        tokenId = _nextTokenId;
    }

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity) {
        liquidity = _liquidity[tokenId];
    }

    function modifyLiquidities(bytes calldata unlockData, uint256) external payable {
        (bytes memory actions, bytes[] memory params) = abi.decode(unlockData, (bytes, bytes[]));
        for (uint256 i; i < actions.length; ++i) {
            uint8 action = uint8(actions[i]);
            if (action == uint8(Actions.MINT_POSITION)) {
                (PoolKey memory key,,, uint256 liquidity,,,,) =
                    abi.decode(params[i], (PoolKey, int24, int24, uint256, uint128, uint128, address, bytes));
                _currency0 = key.currency0;
                _currency1 = key.currency1;
                _recordPermit2Allowances(msg.sender);
                _liquidity[_nextTokenId] = uint128(liquidity);
                ++_nextTokenId;
            } else if (action == uint8(Actions.INCREASE_LIQUIDITY)) {
                (uint256 tokenId, uint256 liquidity,,,) =
                    abi.decode(params[i], (uint256, uint256, uint128, uint128, bytes));
                _recordPermit2Allowances(msg.sender);
                _liquidity[tokenId] += uint128(liquidity);
            } else if (action == uint8(Actions.DECREASE_LIQUIDITY)) {
                (uint256 tokenId, uint256 liquidity,,,) =
                    abi.decode(params[i], (uint256, uint256, uint128, uint128, bytes));
                _pendingAmount0 = _returnAmount0;
                _pendingAmount1 = _returnAmount1;
                if (liquidity >= _liquidity[tokenId]) delete _liquidity[tokenId];
                else _liquidity[tokenId] -= uint128(liquidity);
            } else if (action == uint8(Actions.TAKE_PAIR)) {
                (,, address recipient) = abi.decode(params[i], (Currency, Currency, address));
                if (_pendingAmount0 != 0) {
                    IERC20(Currency.unwrap(_currency0)).transfer(recipient, _pendingAmount0);
                }
                if (_pendingAmount1 != 0) {
                    IERC20(Currency.unwrap(_currency1)).transfer(recipient, _pendingAmount1);
                }
                _pendingAmount0 = 0;
                _pendingAmount1 = 0;
            } else if (action == uint8(Actions.BURN_POSITION)) {
                (uint256 tokenId,,,) = abi.decode(params[i], (uint256, uint128, uint128, bytes));
                delete _liquidity[tokenId];
            }
        }
    }

    function _recordPermit2Allowances(address owner) internal {
        if (permit2 == address(0)) return;
        (lastObservedPermit2Amount0,,) =
            IAllowanceTransfer(permit2).allowance(owner, Currency.unwrap(_currency0), address(this));
        (lastObservedPermit2Amount1,,) =
            IAllowanceTransfer(permit2).allowance(owner, Currency.unwrap(_currency1), address(this));
    }
}
