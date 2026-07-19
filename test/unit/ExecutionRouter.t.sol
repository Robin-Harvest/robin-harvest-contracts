// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {ExecutionRouter} from "../../src/router/ExecutionRouter.sol";
import {OracleRegistry} from "../../src/registries/OracleRegistry.sol";
import {OracleConfig, SwapRequest} from "../../src/types/ProtocolTypes.sol";
import {MockDex} from "../mocks/MockDex.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";

contract ExecutionRouterTest is Test {
    AccessManager internal manager;
    OracleRegistry internal oracleRegistry;
    ExecutionRouter internal router;
    MockDex internal dex;
    MockINDEX internal index;
    MockStockToken internal stock;
    MockOracle internal indexFeed;
    MockOracle internal stockFeed;

    address internal governance = makeAddr("governance");
    address internal trader = makeAddr("trader");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        manager = new AccessManager(governance);
        oracleRegistry = new OracleRegistry(address(manager));
        router = new ExecutionRouter(address(manager), oracleRegistry);
        dex = new MockDex();
        index = new MockINDEX(18);
        stock = new MockStockToken("Mock Apple", "mAAPL", 18);
        indexFeed = new MockOracle(8, 1e8);
        stockFeed = new MockOracle(8, 1e8);

        vm.startPrank(governance);
        oracleRegistry.setOracleConfig(address(index), _config(address(indexFeed)));
        oracleRegistry.setOracleConfig(address(stock), _config(address(stockFeed)));
        router.setAdapterApproval(address(dex), true);
        router.setRoute(address(dex), address(stock), address(index), true, 500);
        vm.stopPrank();

        stock.mint(trader, 1_000 ether);
        index.mint(address(dex), 1_000 ether);
        dex.setRate(address(stock), address(index), 1e18);

        vm.prank(trader);
        stock.approve(address(router), type(uint256).max);
    }

    function testSwapExactInputUsesApprovedRouteAndBalanceDelta() public {
        vm.prank(trader);
        uint256 amountOut = router.swapExactInput(_request(100 ether, 99 ether, uint48(block.timestamp + 1)), recipient);

        assertEq(amountOut, 100 ether);
        assertEq(index.balanceOf(recipient), 100 ether);
        assertEq(stock.allowance(address(router), address(dex)), 0);
    }

    function testExpiredDeadlineReverts() public {
        vm.prank(trader);
        vm.expectRevert();
        router.swapExactInput(_request(100 ether, 99 ether, uint48(block.timestamp - 1)), recipient);
    }

    function testUnapprovedRouteReverts() public {
        vm.prank(governance);
        router.setRoute(address(dex), address(stock), address(index), false, 500);

        vm.prank(trader);
        vm.expectRevert();
        router.swapExactInput(_request(100 ether, 99 ether, uint48(block.timestamp + 1)), recipient);
    }

    function testMinOutputReverts() public {
        dex.setRate(address(stock), address(index), 0.5e18);

        vm.prank(trader);
        vm.expectRevert();
        router.swapExactInput(_request(100 ether, 99 ether, uint48(block.timestamp + 1)), recipient);
    }

    function testOracleDeviationReverts() public {
        dex.setRate(address(stock), address(index), 0.5e18);

        vm.prank(trader);
        vm.expectRevert();
        router.swapExactInput(_request(100 ether, 1 ether, uint48(block.timestamp + 1)), recipient);
    }

    function _request(uint256 amountIn, uint256 minAmountOut, uint48 deadline)
        private
        view
        returns (SwapRequest memory request)
    {
        request = SwapRequest({
            adapter: address(dex),
            tokenIn: address(stock),
            tokenOut: address(index),
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            deadline: deadline
        });
    }

    function _config(address feed) private pure returns (OracleConfig memory config) {
        config = OracleConfig({
            feed: feed, heartbeat: 1 hours, decimals: 8, maxDeviationBps: 500, uiMultiplier: 1e18, paused: false
        });
    }
}
