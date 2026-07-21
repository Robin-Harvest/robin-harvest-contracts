# Contract Reference — Index

Contract-by-contract documentation for every Solidity file in `src/`.

---

## Files

| Document | Contracts |
|---|---|
| [vault.md](./vault.md) | `RobinVault`, `ERC4626Paris` |
| [strategies.md](./strategies.md) | `StrategyBase`, `CoreStrategy`, `GrowthStrategy` |
| [registries.md](./registries.md) | `OracleRegistry`, `RewardRegistry` |
| [router-and-adapters.md](./router-and-adapters.md) | `ExecutionRouter`, `UniswapV2DexAdapter` |
| [accounting-and-access.md](./accounting-and-access.md) | `RobinAccountant`, `AccessManager` |
| [interfaces-types-libraries.md](./interfaces-types-libraries.md) | All interfaces, `ProtocolTypes`, libraries |

---

## Reading Guide

For each function the sub-documents cover:

- Purpose and architecture role
- Parameters, returns, access control
- State changes and events
- Call graph and callers
- Security and gas notes
- Edge and failure cases

Cross-reference [08-execution-flows.md](../08-execution-flows.md) and [09-mathematics.md](../09-mathematics.md).

---

## Contract Dependency Matrix

| Contract | Calls | Called by |
|---|---|---|
| RobinVault | strategy.*, accountant.*, INDEX | Users, strategy.report |
| StrategyBase | vault.report, tokens | Vault, keeper |
| CoreStrategy | indexFinance, router, registries | Vault |
| GrowthStrategy | + in-kind | Vault |
| ExecutionRouter | adapters, oracle | Strategies |
| RobinAccountant | (view math only) | Vault.report path |
| OracleRegistry | price feeds | Router, strategies |
| RewardRegistry | — | Strategies, governance |

---

Start with [vault.md](./vault.md).
