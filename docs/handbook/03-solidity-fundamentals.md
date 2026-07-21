# Chapter 3 — Solidity Fundamentals

Solidity is the primary language of Robin Harvest. This chapter teaches Solidity **before** diving into protocol contracts. Every mechanism below appears in `src/`.

---

## 3.1 The Solidity Compiler

### What it is

**Solidity** compiles human-readable contract source to **EVM bytecode** and an **ABI**. Robin Harvest pins **`solc 0.8.25`** in `foundry.toml`.

### Why it exists

High-level safety features: types, modifiers, inheritance, custom errors. The compiler also performs optimization (`optimizer = true`, `optimizer_runs = 200`, `via_ir = true`).

### Internal pipeline (simplified)

```
.sol source → Parser → AST → Type checker → IR (optional via_ir) → Bytecode + metadata
```

### Robin Harvest usage

- `pragma solidity 0.8.25;` on every file
- **`bytecode_hash = "none"`**, **`cbor_metadata = false`** — reproducible builds, smaller artifacts
- **Checked arithmetic** by default since 0.8.0 (overflow reverts)

### Alternatives

| Language | Tradeoff |
|---|---|
| Vyper | Simpler, less feature-rich |
| Huff/Yul | Lower level, smaller gas, harder audit |

### Security

Compiler bugs are rare but possible — pin versions and verify bytecode in CI.

---

## 3.2 ABI Encoding

### What it is

Function selectors are first 4 bytes of `keccak256("functionName(type1,type2)")`. Arguments are **ABI-encoded** in 32-byte words.

### Robin Harvest example

`report(HarvestReport calldata report_)` — struct encoding follows ABI rules for tuples.

Custom errors: `error LossExceedsMaximum(uint256 lossBps, uint256 maxLossBps)` — cheaper than revert strings, precise decoding.

---

## 3.3 Data Locations: Storage, Memory, Calldata

### What they are

| Location | Lifetime | Mutability | Gas |
|---|---|---|---|
| **storage** | Permanent on chain | Read/write | Expensive write |
| **memory** | Current call | Temporary | Medium |
| **calldata** | External call args | Read-only | Cheapest for external fn args |

### Why they exist

EVM must distinguish persistent vs transient data.

### Robin Harvest patterns

```solidity
function report(HarvestReport calldata report_) external nonReentrant
function swapExactInput(SwapRequest calldata request, address recipient)
```

Structs passed as **`calldata`** in external functions avoid memory copies.

Internal functions like `_assessReportFees` use memory for local arithmetic.

### Security

Uninitialized **memory** structs can be zero — always set fields explicitly. Storage pointers alias state — careful with struct assignments to storage.

---

## 3.4 Constants and Immutable

### Constant

Compile-time literal inlined in bytecode:

```solidity
uint256 public constant DEFAULT_PROFIT_MAX_UNLOCK_TIME = 7 days;
uint256 internal constant BPS = 10_000; // Constants.sol
```

### Immutable

Set once in constructor, stored in bytecode (not SLOAD):

```solidity
address public immutable vault;           // StrategyBase
IOracleRegistry public immutable oracleRegistry; // ExecutionRouter
IERC20 private immutable _asset;          // ERC4626Paris
```

### Why Robin Harvest uses them

- **Gas savings** on hot paths
- **Trust reduction** — critical addresses cannot change after deploy (router's oracle registry)

### Tradeoff

Immutables cannot be updated — new router requires new deployment.

---

## 3.5 Mappings and Nested Mappings

### What they are

`mapping(key => value)` — hash table in storage; not iterable by default.

### Robin Harvest examples

```solidity
mapping(address token => bool tracked) public isRewardTokenTracked;     // StrategyBase
mapping(address token => uint256 amount) public retainedBalance;        // GrowthStrategy
mapping(address adapter => bool approved) private _approvedAdapters;    // ExecutionRouter
mapping(address token => mapping(address adapter => bool approved))     // RewardRegistry
```

### Security

Uninitialized keys return **zero/false** — ensure logic handles missing keys. Do not assume `mapping` length exists.

---

## 3.6 Structs and Enums

### Enums (`ProtocolTypes.sol`)

```solidity
enum LifecycleState { Active, Paused, Shutdown }
enum RewardDisposition { Ignore, Sell, Retain }
enum RewardCategory { Unclassified, Equity, Fund, Other }
```

Enums compress categorical state to small integers; ABI encodes as uint8.

### Structs

`HarvestReport`, `InKindRedemptionResult`, `RewardTokenConfig`, `OracleConfig`, `SwapRequest`, `FeeConfig`, `CategoryPolicy`, `PendingStrategyMigration`.

Structs group related fields for single ABI parameters and clear interfaces.

---

## 3.7 Libraries

### What they are

Deployed or inlined code reused across contracts. Robin Harvest uses **OpenZeppelin** libraries:

- `SafeERC20` — safe transfer/approve
- `Math` — `mulDiv` with rounding modes

Local **`Constants`**, **`Errors`**, **`Events`** are protocol-specific shared modules.

`Constants.sol` is a `library` with internal constants — inlined at compile time.

---

## 3.8 Inheritance

### What it is

Contracts extend base contracts; linearized by C3 order.

### Robin Harvest inheritance trees

**RobinVault:**
```
RobinVault
  ├── ERC4626Paris
  │     ├── ERC20
  │     └── IERC4626
  ├── AccessManaged
  ├── ReentrancyGuard
  ├── Events (abstract)
  └── IRobinVaultReport
```

**GrowthStrategy:**
```
GrowthStrategy
  ├── CoreStrategy
  │     └── StrategyBase
  │           ├── IRobinStrategy
  │           ├── AccessManaged
  │           ├── ReentrancyGuard
  │           └── Events
  └── IInKindRedemptionStrategy
```

### `override` and `virtual`

`RobinVault.totalAssets()` **overrides** `ERC4626Paris.totalAssets()`.

### Security

Deep inheritance increases audit surface — understand which parent defines `onlyVault`, `restricted`, `_withdraw`.

---

## 3.9 Modifiers

### What they are

Functions wrapped with preconditions:

```solidity
modifier onlyVault() {
    if (msg.sender != vault) revert OnlyVault(msg.sender);
    _;
}
```

OpenZeppelin:
- **`restricted`** — AccessManaged authorization
- **`nonReentrant`** — ReentrancyGuard

### Robin Harvest

Nearly all user entrypoints: `nonReentrant`. Strategy capital ops: `onlyVault`. Governance setters: `restricted`.

---

## 3.10 Interfaces and Abstract Contracts

### Interfaces

Define external API without implementation:

- `IRobinStrategy`, `IOracleRegistry`, `IDexAdapter`, `IExecutionRouter`, `IInKindRedemptionStrategy`

External protocols:
- `IIndexFinanceCore`, `IPriceFeed`, `IUniswapV2Router`, `IStockToken`

### Abstract contracts

`StrategyBase` — implements common logic, leaves hooks `virtual`/`internal`:
- `_deployFunds`, `_freeFunds`, `_processRewardToken`, `_emergencyWithdraw`

`Events` — abstract, events only.

`ERC4626Paris` — abstract ERC-4626 base.

---

## 3.11 Events

### What they are

Append-only logs for indexers; cheaper than storage.

### Robin Harvest

Canonical events in `Events.sol`: `LifecycleStateChanged`, `StrategyReported`, `SwapExecuted`, etc.

Vault-specific: `InKindRedeem`, `StrategyDebtUpdated`, `FeesCapped`.

### Security

Events are **not** authoritative for accounting — always use on-chain state for value; events for UX/analytics.

---

## 3.12 Custom Errors

Defined in `Errors.sol`:

```solidity
error LossExceedsMaximum(uint256 lossBps, uint256 maxLossBps);
error StaleOracle(address oracle, uint256 updatedAt, uint256 heartbeat);
error ExposureLimitExceeded(bytes32 subject, uint256 exposureBps, uint256 maxExposureBps);
```

**Why:** Lower gas than strings; structured for tooling.

---

## 3.13 Low-Level Calls

### call

Generic value + data transfer. Can change callee storage if malicious.

### staticcall

Read-only; used in `ERC4626Paris._tryGetAssetDecimals` to probe `decimals()` safely.

### delegatecall

Runs callee code in **caller's storage context**. Used by proxy upgrade patterns — **not used** in Robin Harvest core (no proxies).

### Robin Harvest discipline

External calls to INDEX, Index Finance, DEX adapters happen **after** state updates where possible (CEI). Documented exceptions: `_ensureLiquidity` must call `freeFunds` before debt reduction because return values are needed.

---

## 3.14 CREATE and CREATE2

**CREATE:** Address = hash(deployer, nonce).

**CREATE2:** Deterministic address from deployer + salt + init code.

Robin Harvest deploy script uses standard **`new Contract()`** (CREATE) — addresses depend on deployer nonce order.

---

## 3.15 ERC Standards in Robin Harvest

### ERC-20

Fungible tokens: INDEX, vault shares (`ERC20` in `ERC4626Paris`), reward tokens.

Methods: `transfer`, `approve`, `balanceOf`. Robin Harvest uses **SafeERC20** for non-standard return values.

**Unsupported:** fee-on-transfer, rebasing — breaks balance-delta accounting in `GrowthStrategy._transferExact`.

### ERC-4626 (Tokenized Vault Standard)

Standard interface for vaults:

| Function | Robin Harvest behavior |
|---|---|
| `asset()` | INDEX |
| `deposit` / `mint` | Mint shares; update eligibility tracking |
| `withdraw` / `redeem` | Default `maxLossBps`; may call `strategy.freeFunds` |
| `totalAssets()` | Idle + strategyDebt − locked profit remaining |
| `convertToShares` / `convertToAssets` | Virtual offset (+10^6 virtual shares) |

**Extension:** `redeemInKind` is **explicitly non-ERC-4626** — optional Growth feature.

### EIP-170

Max contract size 24576 bytes — verified in CI.

---

## 3.16 OpenZeppelin Patterns Used

| Module | Usage |
|---|---|
| `AccessManaged` | Vault, strategies, registries, router, accountant |
| `ReentrancyGuard` | Vault user ops, router swaps, strategy harvest |
| `SafeERC20` | All token transfers |
| `Math.mulDiv` | Share math, fees, exposure BPS |

---

## 3.17 Check-Effects-Interactions (CEI)

Recommended order:
1. **Checks** — validate inputs
2. **Effects** — update state
3. **Interactions** — external calls

`redeemInKind` (DESIGN.md sequence):
1. Validate shares/receiver
2. Preview snapshot
3. Burn shares, reduce debt/locked profit
4. Strategy updates retained balances
5. Transfer tokens

---

## 3.18 Chapter Summary

Robin Harvest Solidity code is **Solidity 0.8.25**, **Paris EVM**, **OpenZeppelin 5.6.1**, emphasizing:

- Custom errors and events
- Immutables for wiring
- AccessManaged + ReentrancyGuard
- calldata structs for external APIs
- Local ERC4626Paris for compatibility

**Next:** [04-defi-fundamentals.md](./04-defi-fundamentals.md)
