# Chapter 16 — Glossary

Alphabetical reference for blockchain, Solidity, DeFi, and **Robin Harvest–specific** terms used in this handbook.

---

## A

**ABI (Application Binary Interface)**  
JSON description of contract functions/events/errors. Lets wallets and scripts encode calls. Robin Harvest ABIs are produced by `forge build` in `out/`.

**AccessManaged**  
OpenZeppelin mixin requiring `authority()` to authorize `restricted` functions. All Robin Harvest core contracts use the shared `AccessManager`.

**AccessManager**  
Central role registry (`src/access/AccessManager.sol`). Defines GOVERNANCE, KEEPER, STRATEGY_MANAGER, etc.

**Accountant**  
See **RobinAccountant**.

**AMM (Automated Market Maker)**  
DEX model pricing trades via formulas (e.g. x·y=k). `UniswapV2DexAdapter` integrates constant-product routers.

**answeredInRound**  
Chainlink round field; must be ≥ roundId for complete round (`OracleRegistry.getValidatedPrice`).

---

## B

**Basis points (bps)**  
1/100 of a percent; denominator 10_000 in `Constants.BPS`.

**Bytecode**  
EVM executable code deployed at contract address. Size limited by EIP-170 (~24KB runtime).

**Block**  
Batch of transactions with timestamp, parent hash, state root. Profit unlock uses `block.timestamp`.

---

## C

**Calldata**  
Read-only transaction input bytes where function arguments live for external calls.

**Cap-and-forfeit (fees)**  
If accrued fees exceed `lockedProfit`, excess is discarded rather than charged to principal (`RobinVault._assessReportFees`).

**CEI (Checks-Effects-Interactions)**  
Safe pattern: validate, mutate state, then external calls. In-kind redemption follows CEI across vault/strategy (`DESIGN.md`).

**Chain ID**  
Network identifier in transactions. Robinhood Chain ID TBD (`OPEN_QUESTIONS.md`).

**Constant product**  
AMM invariant x·y=k; Uniswap V2 style.

**CoreStrategy**  
Sell-all-rewards strategy; deploys INDEX to Index Finance (`src/strategies/CoreStrategy.sol`).

**CREATE / CREATE2**  
Opcodes deploying contracts; CREATE2 enables deterministic addresses via salt.

---

## D

**Debt payment**  
INDEX returned from strategy to vault during report (`HarvestReport.debtPayment`).

**Decimals offset**  
Virtual share bump 10^6 in RobinVault ERC-4626 conversions.

**Delegatecall**  
Execute callee code in caller context; used by proxies (not primary pattern here).

**Deposit cap**  
Max `totalAssets()` vault accepts (`RobinVault.depositCap`).

**DEX adapter**  
Contract implementing `IDexAdapter`; encodes venue swaps (`UniswapV2DexAdapter`).

---

## E

**Eligibility (Index Finance)**  
External protocol check `indexFinance.isEligible(strategy)` before claim/tend.

**Eligibility threshold (vault)**  
Minimum `totalAssets()` for vault qualification hook (`RobinVault.eligibilityThreshold`).

**ERC-20**  
Fungible token standard; INDEX and reward tokens.

**ERC-4626**  
Tokenized vault standard: deposit asset, receive shares, `totalAssets` NAV.

**ERC4626Paris**  
Local Paris-compatible ERC-4626 base (`src/vaults/ERC4626Paris.sol`).

**EVM (Ethereum Virtual Machine)**  
Stack machine executing smart contracts. Target: **Paris** hard fork.

**ExecutionRouter**  
Governed swap router (`src/router/ExecutionRouter.sol`).

**Exposure (bps)**  
Token or category value as fraction of strategy NAV × 10_000.

---

## F

**Fee-on-transfer token**  
Token deducting fee on transfer; **unsupported** (`FeeOnTransferDetected`).

**Foundry**  
Solidity toolchain: forge, cast, anvil. Used for build/test/deploy.

**freeFunds**  
Strategy returns INDEX to vault for withdrawals (`IRobinStrategy.freeFunds`).

**Fuzz test**  
Property test with random inputs; e.g. `testFuzzDepositShareAccounting`.

---

## G

**Gas**  
Computation payment on chain; swap/harvest/in-kind costs scale with operations.

**GrowthStrategy**  
Retain/sell rewards, portfolio NAV, in-kind redemption (`src/strategies/GrowthStrategy.sol`).

---

## H

**Harvest**  
Keeper operation: claim rewards, process tokens, report to vault (`StrategyBase.harvest`).

**HarvestReport**  
Struct `{gain, loss, debtPayment}` (`ProtocolTypes.sol`).

**Heartbeat (oracle)**  
Max age of price observation before stale revert.

**High-water mark (HWM)**  
Peak gross assets for performance fee (`RobinAccountant.highWaterMark`).

---

## I

**Idle buffer**  
Percentage of totalAssets kept as vault INDEX (`idleBufferBps`).

**Immutable**  
Constructor-set value stored in bytecode; e.g. `ExecutionRouter.oracleRegistry`.

**In-kind redemption**  
Non-ERC4626 exit: proportional INDEX + retained stocks (`redeemInKind`).

**INDEX**  
Vault asset token; Index Finance ecosystem token.

**Index Finance**  
External yield source; provisional `IIndexFinanceCore` integration.

**Invariant test**  
Stateful fuzz with global properties (`RobinHarvestInvariant.t.sol`).

**Isolation (reward token)**  
Failed token skipped in harvest (`isRewardTokenIsolated`).

---

## K

**Keeper**  
Automated or ops EOA with KEEPER_ROLE for harvest/deploy.

---

## L

**LifecycleState**  
`Active`, `Paused`, `Shutdown` — shared enum for vault/strategy.

**Liquidation order**  
Governance-ordered retained token sales on INDEX withdraw (`GrowthStrategy.setLiquidationOrder`).

**Locked profit**  
Reported gain withheld from `totalAssets()` until linear unlock.

**Loss (realized)**  
Shortfall when freeing INDEX from Index Finance or liquidating stocks.

**LP (Liquidity Provider)**  
DEX pool participant; LP strategy **not implemented** in V1.

---

## M

**Management fee**  
Time-accrual fee on gross assets (`RobinAccountant._accrueManagementFee`).

**maxLossBps**  
User/governance cap on acceptable withdrawal loss in basis points.

**Memory**  
Temporary Solidity data area; cleared between calls.

**MEV (Maximal Extractable Value)**  
Profit from transaction ordering; mitigated partially via locked profit, slippage bounds.

**minHarvestAmount**  
Minimum reward balance to process (`RewardTokenConfig`).

---

## N

**NAV (Net Asset Value)**  
Total economic value of vault/strategy; vault uses `totalAssets()`, strategy `totalAssets()`.

**navHaircutBps**  
Extra discount on retained asset NAV after min(oracle, quote).

**Non-reentrant**  
OpenZeppelin guard preventing recursive entry during external calls.

---

## O

**Oracle**  
Price feed; Chainlink-shaped `IPriceFeed.latestRoundData`.

**Oracle deviation**  
Post-swap check: execution vs oracle implied output (`ExecutionRouter`).

**OracleRegistry**  
Governed feed config and validation (`src/registries/OracleRegistry.sol`).

---

## P

**Paris (EVM)**  
Hard fork target without Cancun opcodes; drives ERC4626Paris decision.

**Pause**  
Reversible stop of deposits/deploy/harvest; withdrawals may continue.

**Performance fee**  
Fee on gains above high-water mark.

**Preview function**  
ERC-4626 view simulating deposit/withdraw without state change.

**Profit smoothing**  
Same as locked profit / linear unlock.

---

## R

**Rebasing token**  
Supply changes per holder; **unsupported**.

**Reentrancy**  
Re-entering contract mid-call; guarded by `nonReentrant`.

**Retain (disposition)**  
Hold reward token in Growth portfolio.

**Retained balance**  
Growth mapping token → amount held (`retainedBalance`).

**RewardRegistry**  
Governed reward token policies (`src/registries/RewardRegistry.sol`).

**RewardDisposition**  
Ignore | Sell | Retain.

**RobinVault**  
Main ERC-4626 vault contract.

**Rounding (floor/ceil)**  
Floor on in-kind payouts; ceil on locked profit discount — prevents overpay leavers.

**RPC**  
HTTP endpoint to node (`ROBINHOOD_RPC_URL`).

---

## S

**SafeERC20**  
OpenZeppelin safe transfer/approve helpers.

**Sandwich attack**  
Manipulate price before/after victim trade; slippage + deviation limits mitigate.

**Share**  
Vault ERC-20 token representing pro-rata claim on `totalAssets()`.

**Shutdown**  
Irreversible lifecycle halt (`InvalidLifecycleState` if leaving shutdown).

**Slippage**  
Difference between expected and executed swap price; bounded by `maxSlippageBps` and `minAmountOut`.

**Slither**  
Static analyzer run in CI.

**Staticcall**  
Read-only external call; used in `_tryGetAssetDecimals`.

**Storage**  
Persistent contract state; layout matters for upgrades (not upgradeable here).

**Strategy debt**  
Vault-internal accounting of assets deployed to strategy.

**StrategyBase**  
Abstract strategy framework.

**SwapRequest**  
Router input struct with adapter, tokens, amounts, deadline.

---

## T

**Tend**  
Maintenance call without full harvest report (`StrategyBase.tend`).

**Timelock (migration)**  
Delay between propose and execute strategy migration.

**Tokenized stock**  
Equity wrapped as ERC-20; `IStockToken` interface.

**totalAssets()**  
ERC-4626 NAV; vault excludes unlocked portion of locked profit.

**Trust assumptions**  
Governance, oracles, Index Finance, DEX honesty (`README.md`).

---

## U

**uiMultiplier**  
Oracle config scalar at 1e18 precision for corporate actions.

**Underlying asset**  
Vault deposit token — INDEX.

---

## V

**Validator**  
Chain participant proposing blocks; Robinhood Chain specifics TBD.

**Vault**  
RobinVault instance holding INDEX and issuing shares.

**Virtual shares/assets**  
+10^offset and +1 in conversion formulas.

---

## W

**Withdraw**  
ERC-4626 pull INDEX by asset amount; may trigger `freeFunds`.

---

## Symbols & Files

| Symbol | Meaning |
|---|---|
| rhINDEX-C | Core vault share token |
| rhINDEX-G | Growth vault share token |
| `src/` | Production Solidity |
| `script/` | Deploy/configure/validate |
| `test/` | Foundry tests |
| `OPEN_QUESTIONS.md` | Unresolved external parameters |

---

**See also:** [SUMMARY.md](./SUMMARY.md) for chapter navigation.
