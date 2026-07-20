// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {UniswapV2DexAdapter} from "../../src/adapters/UniswapV2DexAdapter.sol";
import {IUniswapV2Router} from "../../src/interfaces/external/IUniswapV2Router.sol";
import {ZeroAddress, ZeroAmount} from "../../src/libraries/Errors.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";

// Mock Router for testing the adapter
contract MockRouter is IUniswapV2Router {
    mapping(address => mapping(address => uint256)) public rates;
    uint256 public feeOnTransferBps; // 0 for no fee

    function setRate(address tokenIn, address tokenOut, uint256 rate) external {
        rates[tokenIn][tokenOut] = rate;
    }

    function setFeeOnTransfer(uint256 bps) external {
        feeOnTransferBps = bps;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "EXPIRED");
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];
        
        // pull tokenIn
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        uint256 rate = rates[tokenIn][tokenOut];
        require(rate > 0, "NO_RATE");
        
        uint256 amountOut = amountIn * rate / 1e18;
        
        // apply fee-on-transfer if set
        if (feeOnTransferBps > 0) {
            amountOut = amountOut - (amountOut * feeOnTransferBps / 10000);
        }
        
        require(amountOut >= amountOutMin, "INSUFFICIENT_OUTPUT");
        
        // push tokenOut
        MockStockToken(tokenOut).mint(to, amountOut);
        
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = amountOut;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts) {
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];
        uint256 rate = rates[tokenIn][tokenOut];
        require(rate > 0, "NO_RATE");
        
        uint256 amountOut = amountIn * rate / 1e18;
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = amountOut;
    }
}

contract UniswapV2DexAdapterTest is Test {
    AccessManager internal manager;
    MockRouter internal router;
    UniswapV2DexAdapter internal adapter;
    
    MockStockToken internal tokenA;
    MockStockToken internal tokenB;
    MockStockToken internal tokenC;
    
    address internal governance = makeAddr("governance");
    address internal user = makeAddr("user");

    function setUp() public {
        manager = new AccessManager(governance);
        router = new MockRouter();
        adapter = new UniswapV2DexAdapter(router, address(manager));
        
        tokenA = new MockStockToken("Token A", "tA", 18);
        tokenB = new MockStockToken("Token B", "tB", 18);
        tokenC = new MockStockToken("Token C", "tC", 18);
        
        router.setRate(address(tokenA), address(tokenB), 2e18); // 1 A = 2 B
        router.setRate(address(tokenA), address(tokenC), 4e18); // 1 A = 4 C
        
        tokenA.mint(user, 1_000 ether);
        vm.prank(user);
        tokenA.approve(address(adapter), type(uint256).max);
    }

    function testDirectPairSwap() public {
        vm.prank(user);
        uint256 amountOut = adapter.swapExactInput(address(tokenA), address(tokenB), 100 ether, 190 ether, user, uint48(block.timestamp));
        
        assertEq(amountOut, 200 ether);
        assertEq(tokenA.balanceOf(user), 900 ether);
        assertEq(tokenB.balanceOf(user), 200 ether);
        
        // Check approval reset
        assertEq(tokenA.allowance(address(adapter), address(router)), 0);
    }
    
    function testMultiHopCustomPath() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        
        vm.prank(governance);
        adapter.setCustomPath(address(tokenA), address(tokenC), path);
        
        vm.prank(user);
        uint256 amountOut = adapter.swapExactInput(address(tokenA), address(tokenC), 100 ether, 390 ether, user, uint48(block.timestamp));
        
        assertEq(amountOut, 400 ether);
        assertEq(tokenA.allowance(address(adapter), address(router)), 0);
    }
    
    function testPathValidationReverts() public {
        address[] memory shortPath = new address[](1);
        shortPath[0] = address(tokenA);
        
        vm.startPrank(governance);
        vm.expectRevert(UniswapV2DexAdapter.InvalidPath.selector);
        adapter.setCustomPath(address(tokenA), address(tokenB), shortPath);
        
        address[] memory badEndpoints = new address[](2);
        badEndpoints[0] = address(tokenB); // mismatch
        badEndpoints[1] = address(tokenB);
        
        vm.expectRevert(UniswapV2DexAdapter.InvalidPath.selector);
        adapter.setCustomPath(address(tokenA), address(tokenB), badEndpoints);
        
        address[] memory zeroAddr = new address[](2);
        zeroAddr[0] = address(tokenA);
        zeroAddr[1] = address(0);
        
        vm.expectRevert(UniswapV2DexAdapter.InvalidPath.selector);
        adapter.setCustomPath(address(tokenA), address(tokenB), zeroAddr);
        vm.stopPrank();
    }
    
    function testFeeOnTransferToken() public {
        router.setFeeOnTransfer(1000); // 10% fee
        
        vm.prank(user);
        // Expecting 200, minus 10% = 180.
        // We set minAmountOut to 180 exactly.
        uint256 amountOut = adapter.swapExactInput(address(tokenA), address(tokenB), 100 ether, 180 ether, user, uint48(block.timestamp));
        
        assertEq(amountOut, 180 ether);
        assertEq(tokenB.balanceOf(user), 180 ether);
    }
}
