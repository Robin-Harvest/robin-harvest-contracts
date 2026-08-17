# Open Questions & Architectural Decisions

This document tracks the external prerequisites required before production launch on Robinhood Chain Mainnet, as well as the confirmed architectural decisions resolved prior to external audit.

---

## 🔴 External Prerequisites for Mainnet Launch

These items depend on external protocol deployments, official network announcements, and governance infrastructure. They must be resolved with authoritative addresses and parameters before broadcasting mainnet transactions:

### 1. Network & Infrastructure
- **Official Robinhood Chain RPC & Explorer**: Production RPC endpoints, Blockscout/Etherscan explorer URL, and verification API keys.
- **EVM Hard Fork & Opcodes**: Verify that Robinhood Chain Mainnet EVM natively supports Cancun opcodes (`TSTORE` / `TLOAD` - EIP-1153) required by Uniswap v4.
- **Gas & Block Constraints**: Confirm block gas limits and transaction finality guarantees.

### 2. External Protocol Contracts
- **Canonical INDEX Token**: Confirmed mainnet ERC-20 address for the `INDEX` asset.
- **Official Index Finance Core**: Official live Index Finance Core contract address, verified ABI, reward token set, and issuance/redemption interfaces. (Set `INDEX_FINANCE_INTEGRATION_VERIFIED=true` upon verification).
- **Uniswap v4 Deployments**: Canonical `PoolManager`, `PositionManager`, and paired token (e.g. `WETH`, `USDC`) addresses on Robinhood Chain.
- **Production Oracle Feeds**: Authoritative Chainlink / Robinhood Chain native oracle feed addresses, heartbeat intervals, and deviation parameters for `INDEX`, paired tokens, and underlying stock assets.

### 3. Governance & Operations
- **Multisig Signers & Threshold**: Gnosis Safe / Safe{Wallet} addresses configured for `GOVERNANCE_ADDRESS` and `SECURITY_COUNCIL_ADDRESS`.
- **Operational Account Provisioning**: Designated addresses for `STRATEGY_MANAGER_ADDRESS`, `KEEPER_ADDRESS`, `ORACLE_MANAGER_ADDRESS`, and `REWARD_MANAGER_ADDRESS`.

---

## 🟢 Resolved Protocol Architecture Decisions (v1.2 Pre-Audit)

The following architectural questions and security decisions have been fully designed, implemented, and verified in the smart contract codebase:

### 1. Fee Shortfall Policy (Cap-and-Forfeit)
- **Decision**: Management and performance fees assessed during vault reports are rigidly capped at the available `lockedProfit`. Any fee amount exceeding this cap is permanently forfeited. This eliminates "fee debt spirals" and strictly preserves depositor principal during market downturns.

### 2. In-Kind Redemption Slippage & Value Conservation
- **Decision**: The exiting user bears the cost of slippage during non-INDEX asset disposition. The payout is bounded by a user-supplied `maxLossBps` parameter. In-kind allocations use pro-rata floor-rounding ($\lfloor rac{	ext{balance} 	imes 	ext{shares}}{	ext{totalSupply}} floor$), and full redemptions sweep the entire remaining balance to eliminate stranded division dust.

### 3. DEX Adapter Architecture & Multi-Hop Routing
- **Decision**: `UniswapV2DexAdapter` supports multi-hop paths via `setCustomPath`, managed by `AccessManaged` governance. The exact-input flow pulls required tokens via `safeTransferFrom`, sets `forceApprove`, and resets approval to `0` immediately post-swap to eliminate residual allowances.

### 4. Single-Position Concentrated Liquidity Bound (`MAX_ACTIVE_POSITIONS = 1`)
- **Decision**: The concentrated liquidity strategy is bounded to a single active Uniswap v4 position NFT. This eliminates iteration loops, prevents gas exhaustion during `harvest`, `tend`, and `emergencyClosePositions`, and guarantees compliance with the EIP-170 runtime code size limit (24.576 KB).

### 5. Hookless Pool Internal TWAP Observation Ring
- **Decision**: Because hookless Uniswap v4 pools provide no native TWAP, `ConcentratedLiquidityStrategy` maintains an internal ring buffer of up to 64 price observations evaluated against the current block timestamp, rejecting stale or uninitialized windows.

### 6. Oracle Deviation & Liveness Policy
- **Decision**: `ExecutionRouter` enforces maximum relative deviation against healthy oracle feeds before swaps. If an oracle feed for a retained token is stale or paused during Growth Vault liquidation, the asset is safely treated as 0-value during NAV calculation rather than reverting vault operations (prioritizing protocol liveness).

### 7. Two-Tier Timelock Delays
- **Decision**: Role execution delays (`OPERATIONAL_ROLE_EXECUTION_DELAY`, e.g. 24h) and configuration function delays (`CONFIG_FUNCTION_DELAY`, e.g. 48h) protect against governance key compromise, while emergency pause and position exit functions remain immediate (`delay = 0`).
