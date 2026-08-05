// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockINDEX} from "../test/mocks/MockINDEX.sol";
import {MockStockToken} from "../test/mocks/MockStockToken.sol";
import {MockIndexFinanceCore} from "../test/mocks/MockIndexFinanceCore.sol";
import {MockDex} from "../test/mocks/MockDex.sol";
import {MockV4PoolManager} from "../test/mocks/MockV4PoolManager.sol";
import {MockV4PositionManager} from "../test/mocks/MockV4PositionManager.sol";
import {MockPermit2} from "../test/mocks/MockPermit2.sol";

contract DeployMocks is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockINDEX indexToken = new MockINDEX(18);
        MockStockToken pairedToken = new MockStockToken("Mock Stock Token", "mSTK", 18);

        MockIndexFinanceCore indexFinance = new MockIndexFinanceCore(indexToken);
        MockDex dexAdapter = new MockDex();

        MockV4PoolManager poolManager = new MockV4PoolManager();
        MockPermit2 permit2 = new MockPermit2();
        MockV4PositionManager positionManager = new MockV4PositionManager();
        positionManager.setPermit2(address(permit2));

        vm.stopBroadcast();

        console.log("============================");
        console.log("MOCK DEPENDENCIES DEPLOYED");
        console.log("============================");
        console.log("Please copy these exact lines into your .env file:");
        console.log("");
        console.log("INDEX_TOKEN_ADDRESS=%s", address(indexToken));
        console.log("INDEX_FINANCE_ADDRESS=%s", address(indexFinance));
        console.log("V4_PAIRED_TOKEN_ADDRESS=%s", address(pairedToken));
        console.log("SWAP_ADAPTER_ADDRESS=%s", address(dexAdapter));
        console.log("V4_POOL_MANAGER_ADDRESS=%s", address(poolManager));
        console.log("V4_POSITION_MANAGER_ADDRESS=%s", address(positionManager));
        console.log("============================");
    }
}
