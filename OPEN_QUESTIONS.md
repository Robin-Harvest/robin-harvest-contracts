# Open Questions

Phase 1 assumes no external ABI, address, route, feed, role holder, parameter, or capability. Answers must cite authoritative sources and be reviewed before implementation.

## Network

- What are the official Robinhood Chain chain ID, RPC endpoints, explorer URL, and explorer API?
- **EVM Hard Fork & Opcodes**: Uniswap v4 concentrated liquidity strategies require transient storage opcodes (`tload`/`tstore`), requiring an EVM target of **Cancun** or later. Does the target Robinhood Chain production release natively support Cancun opcodes?
- What are expected block time, finality, reorganization, gas, and contract-size constraints?
- **Testnet & Mocks**: Until live testnet faucets, canonical wrapped tokens, and Index Finance Core addresses are officially published, deployment validation relies on local simulation and mock suites via `script/DeployMocks.s.sol`.

## Index Finance

- What Index Finance contracts, interfaces, deployed addresses, and versions are approved?
- What index lifecycle, issuance, redemption, rebalance, and custody mechanics must be supported?
- Which assets and weights define each initial index, and who may update them?
- What failure, pause, and recovery behavior does the integration expose?
- Does the live integration implement `claimRewards(address,address)` and `isEligible(address)`; what are their authorization, token-set, accounting, and return-value semantics?

## Tokenized Stocks

- Which tokenized-stock issuers, standards, contracts, decimals, transfer restrictions, and corporate-action mechanics are authoritative?
- Are assets permissioned, pausable, upgradeable, rebasing, fee-on-transfer, or subject to market-hour restrictions?
- Which jurisdictions, allowlists, sanctions controls, and redemption constraints apply?
- Do live stock tokens expose standard string metadata plus `transfersEnabled()` and `corporateActionMultiplier()`; what precision and account-specific restrictions apply?

## DEX Integration

- Which DEX deployments, router/quoter interfaces, factory addresses, fee tiers, and supported pools are official?
- Which routes and slippage/deadline protections are permitted?
- How are insufficient liquidity, stale quotes, partial fills, and nonstandard tokens handled?
- Can every approved venue be represented safely by the structured exact-input adapter boundary without arbitrary target or calldata execution?

## Oracles

- Which oracle providers, feed addresses, quote currencies, decimals, heartbeat limits, and deviation thresholds are approved?
- How are tokenized-stock prices handled outside market hours and during corporate actions?
- What fallback, circuit-breaker, and sequencer-health mechanisms are required?
- Are approved feeds Chainlink-compatible with `decimals()` and `latestRoundData()`; how must round completeness and `answeredInRound` be validated?

## Governance

- Which multisig, timelock, guardian, pauser, upgrader, and operational role holders are authorized?
- What delays, quorum, proposal, emergency, role-transfer, and role-renunciation policies apply?
- Are contracts immutable or upgradeable; if upgradeable, which proxy pattern is approved?

## Deployment

- Which networks and deployment order are approved?
- What deterministic deployment method, salt policy, confirmations, and verification process are required?
- Which deployment addresses and artifacts may be committed, and how are environment-specific values managed?

## Fees

- What protocol, management, performance, issuance, redemption, and swap fees apply?
- What caps, floors, recipients, accrual formulas, update delays, rounding rules, and fee exemptions are required?

## Testing

- Which official RPC archive endpoints and fixed fork block numbers should be used?
- Which external-contract fixtures, historical incidents, invariant properties, and adversarial token behaviors must be covered?
- What fuzz/invariant run counts, gas limits, coverage thresholds, and CI acceptance criteria are required?

---

## Resolved Questions (v1.2 Pre-Audit)

- **Fee Shortfall Policy (Finding 1 Related)**: *What happens if accrued management fees exceed `lockedProfit`?*
  **Decision (Cap-and-Forfeit)**: Fees are strictly capped at the available `lockedProfit`. Any fee amount exceeding this cap is permanently forfeited. This prevents a "fee debt spiral" and protects user principal during extended periods of stagnation.

- **In-Kind Redemption Slippage (Finding 3)**: *Who bears the cost of slippage during the forced liquidation of non-INDEX assets?*
  **Decision**: The exiting user bears the slippage cost. The actual payout can be less than the previewed payout, bounded by a user-supplied `maxLossBps` parameter. This prevents DoS attacks and protects remaining shareholders.

- **DEX Adapter Architecture (Finding 2)**: *Should the DEX adapter support multi-hop routing, and how should it be secured?*
  **Decision**: Yes, the `UniswapV2DexAdapter` now supports multi-hop paths via a `setCustomPath` function. It is secured via `AccessManaged` to ensure only governance can configure routes. The exact-input flow was also hardened to pull tokens, force approve, and reset approval to 0.
