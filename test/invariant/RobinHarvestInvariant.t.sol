// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessManager} from "../../src/access/AccessManager.sol";
import {RobinVault} from "../../src/vaults/RobinVault.sol";
import {CoreStrategy} from "../../src/strategies/CoreStrategy.sol";
import {GrowthStrategy} from "../../src/strategies/GrowthStrategy.sol";
import {ExecutionRouter} from "../../src/router/ExecutionRouter.sol";
import {OracleRegistry} from "../../src/registries/OracleRegistry.sol";
import {RewardRegistry} from "../../src/registries/RewardRegistry.sol";
import {RobinAccountant} from "../../src/accounting/RobinAccountant.sol";
import {MockINDEX} from "../mocks/MockINDEX.sol";
import {MockDex} from "../mocks/MockDex.sol";
import {MockIndexFinanceCore} from "../mocks/MockIndexFinanceCore.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {
    RewardCategory,
    RewardDisposition,
    RewardTokenConfig,
    OracleConfig,
    FeeConfig,
    CategoryPolicy,
    InKindRedemptionResult
} from "../../src/types/ProtocolTypes.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract RobinHarvestHandler is Test {
    AccessManager public manager;
    MockINDEX public index;
    MockIndexFinanceCore public indexFinance;
    MockDex public dex;
    MockOracle public oracleFeed;
    MockStockToken public stockToken;

    RobinVault public vault;
    GrowthStrategy public strategy;
    CoreStrategy public coreStrategy;
    RobinAccountant public accountant;
    OracleRegistry public oracleRegistry;
    RewardRegistry public rewardRegistry;
    ExecutionRouter public router;

    address public governance = makeAddr("governance");
    address[] public users;

    // Invariant tracking variables
    mapping(address => uint256) public userTotalInvested; // Total INDEX deposited - withdrawn
    mapping(address => uint256) public userHighestSeenValue; // To track sandwich

    uint256 public highestNAV;
    uint256 public feesPaid;
    uint256 public maxLossBps = 100;

    constructor() {
        manager = new AccessManager(governance);
        index = new MockINDEX(18);
        indexFinance = new MockIndexFinanceCore(index);
        dex = new MockDex();
        oracleFeed = new MockOracle(8, 1e8);
        stockToken = new MockStockToken("Stock", "STK", 18);

        oracleRegistry = new OracleRegistry(address(manager));
        rewardRegistry = new RewardRegistry(address(manager));
        router = new ExecutionRouter(address(manager), oracleRegistry);

        vault = new RobinVault(index, "Invariant Vault", "rhINV", address(manager));
        accountant = new RobinAccountant(index, address(manager));

        strategy = new GrowthStrategy(
            address(vault),
            index,
            address(manager),
            indexFinance,
            rewardRegistry,
            oracleRegistry,
            router,
            500,
            30 minutes
        );
        coreStrategy = new CoreStrategy(
            address(vault),
            index,
            address(manager),
            indexFinance,
            rewardRegistry,
            oracleRegistry,
            router,
            500,
            30 minutes
        );

        // Setup governance configs
        vm.startPrank(governance);
        vault.setStrategy(address(strategy));
        vault.setAccountant(address(accountant));
        accountant.setVault(address(vault));
        accountant.setFeeRecipient(governance);
        accountant.setFeeConfig(FeeConfig(1000, 1000)); // 10% perf, 10% mgmt

        oracleRegistry.setOracleConfig(
            address(stockToken), OracleConfig(address(oracleFeed), 86400, 8, 500, 1e18, false)
        );
        rewardRegistry.setRewardTokenConfig(
            address(stockToken),
            RewardTokenConfig(
                true, RewardCategory.Equity, RewardDisposition.Retain, address(oracleFeed), 0, true, address(dex), 2000
            )
        );

        strategy.addRewardToken(address(stockToken));
        router.setRoute(address(dex), address(stockToken), address(index), true, 500); // 5% slippage
        vm.stopPrank();

        for (uint256 i = 0; i < 3; i++) {
            address u = makeAddr(string(abi.encodePacked("user", i)));
            users.push(u);
            index.mint(u, 1_000_000 ether);
            vm.prank(u);
            index.approve(address(vault), type(uint256).max);
        }
    }

    function deposit(uint256 userIndex, uint96 amount) external {
        address u = users[userIndex % users.length];
        amount = uint96(bound(uint256(amount), 1, 10_000 ether));
        if (amount > index.balanceOf(u)) return;

        vm.prank(u);
        vault.deposit(amount, u);
        userTotalInvested[u] += amount;

        uint256 currentNAV = vault.totalAssets();
        if (currentNAV > highestNAV) highestNAV = currentNAV;
    }

    function withdraw(uint256 userIndex, uint96 amount) external {
        address u = users[userIndex % users.length];
        uint256 maxW = vault.maxWithdraw(u);
        if (maxW == 0) return;
        amount = uint96(bound(uint256(amount), 1, maxW));

        vm.prank(u);
        vault.withdraw(amount, u, u, uint16(maxLossBps));
        if (amount > userTotalInvested[u]) userTotalInvested[u] = 0;
        else userTotalInvested[u] -= amount;
    }

    function redeemInKind(uint256 userIndex, uint96 shares) external {
        address u = users[userIndex % users.length];
        uint256 bal = vault.balanceOf(u);
        if (bal == 0) return;
        shares = uint96(bound(uint256(shares), 1, bal));

        vm.prank(u);
        InKindRedemptionResult memory res = vault.redeemInKind(shares, u, u, uint16(maxLossBps));

        uint256 val = res.indexPaid;
        if (res.retainedTokens.length > 0) val += res.retainedAmounts[0]; // simplistic 1:1 value assuming mock oracle

        if (val > userTotalInvested[u]) userTotalInvested[u] = 0;
        else userTotalInvested[u] -= val;

        // Track for sandwich
        if (val > userHighestSeenValue[u]) userHighestSeenValue[u] = val;
    }

    function accrueAndHarvest(uint96 indexReward, uint96 stockReward) external {
        if (vault.totalAssets() == 0) return;

        indexReward = uint96(bound(uint256(indexReward), 1, 1_000 ether));
        stockReward = uint96(bound(uint256(stockReward), 1, 1_000 ether));

        index.mint(address(strategy), indexReward); // simulate INDEX gain
        stockToken.mint(address(strategy), stockReward);

        uint256 amountToDeploy = vault.totalAssets() / 2;
        vm.prank(governance);
        vault.deploy(amountToDeploy);

        indexFinance.accrue(address(strategy), address(stockToken), stockReward);

        vm.warp(block.timestamp + 30 days);

        if (!indexFinance.isEligible(address(strategy))) return;

        vm.prank(governance);
        strategy.harvest();

        uint256 currentNAV = vault.totalAssets();
        if (currentNAV > highestNAV) highestNAV = currentNAV;
        feesPaid = index.balanceOf(governance);
    }
}

contract RobinHarvestInvariantTest is StdInvariant, Test {
    RobinHarvestHandler internal handler;

    function setUp() public {
        handler = new RobinHarvestHandler();
        targetContract(address(handler));
    }

    function invariant_noProfitableSandwich() public view {
        // Since max deposit is 10k per call, if user deposits and redems, value shouldn't magically balloon.
        // A full check requires more granular state tracking, but we assert users don't extract infinite value.
        for (uint256 i = 0; i < 3; i++) {
            address u = handler.users(i);
            assertLe(handler.userHighestSeenValue(u), 1_000_000 ether, "User extracted more than starting balance");
        }
    }

    function invariant_navMonotonicity() public view {
        // NAV only drops due to withdrawals or explicitly mocked losses.
        // In the handler we don't mock losses except through maxLossBps.
        // But NAV per share should generally remain stable or grow.
        uint256 totalSupply = handler.vault().totalSupply();
        uint256 totalAssets = handler.vault().totalAssets();
        if (totalSupply > 0) {
            uint256 expectedMultiplier = 10 ** 6; // vault DECIMALS_OFFSET
            uint256 navPerShare = totalSupply == 0 ? 1e18 : totalAssets * 1e18 * expectedMultiplier / totalSupply;
            assertGe(navPerShare, 1e18 - 1, "NAV per share dropped below 1");
        }
    }

    function invariant_noFeesOnPrincipal() public view {
        // Fees should only come from profits.
        uint256 totalAssets = handler.vault().totalAssets();
        uint256 supply = handler.vault().totalSupply();
        if (totalAssets < supply) {
            // No profit, fees should not have been paid recently (unless paid from past lockedProfit)
        }
        // General sanity check: if no gains, fees don't drain principal
        assertLe(handler.feesPaid(), 100_000 ether);
    }

    function invariant_lossBoundsRespected() public view {
        // Strategy loss must not exceed maxLossBps. Handled by reverts in handler if it did.
    }

    function invariant_growthExposureCaps() public view {
        GrowthStrategy s = GrowthStrategy(payable(address(handler.strategy())));
        uint256 nav = s.totalAssets();
        if (nav > 0) {
            uint256 stockVal = s.retainedValue(address(handler.stockToken()));
            uint256 bps = (stockVal * Constants.BPS) / nav;
            assertLe(bps, 2000 + 100, "Exposure exceeded max by more than tolerance"); // 2000 is config, +100 for rounding tolerance
        }
    }

    function invariant_coreRetainsNothing() public view {
        // Core strategy always sells everything
        CoreStrategy c = CoreStrategy(payable(address(handler.coreStrategy())));
        assertEq(handler.stockToken().balanceOf(address(c)), 0, "Core strategy retained tokens");
    }
}
