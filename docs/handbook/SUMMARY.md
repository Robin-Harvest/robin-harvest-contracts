# Robin Harvest Handbook — Table of Contents

Read chapters in order for a complete education from zero to protocol expert.

---

## Part I — Foundations

1. **[Introduction](./01-introduction.md)** — What Robin Harvest is, who this book is for, how to use it, production status
2. **[Blockchain Fundamentals](./02-blockchain-fundamentals.md)** — Blockchains, Ethereum, EVM, accounts, gas, transactions, nodes, consensus, ABI, bytecode, deployment
3. **[Solidity Fundamentals](./03-solidity-fundamentals.md)** — Compiler, storage, memory, inheritance, interfaces, libraries, ERC standards, low-level calls
4. **[DeFi Fundamentals](./04-defi-fundamentals.md)** — Vaults, ERC-4626, yield strategies, NAV, fees, oracles, DEXs, MEV, and why Robin Harvest needs each

## Part II — The Robin Harvest System

5. **[Project Overview](./05-project-overview.md)** — Problem statement, products (Core vs Growth), trust model, limitations, open questions
6. **[Architecture](./06-architecture.md)** — System diagram, component responsibilities, ownership, lifecycle, dependency graph
7. **[Repository Walkthrough](./07-repository-walkthrough.md)** — Every directory, file, and configuration explained

## Part III — Deep Implementation

8. **[Execution Flows](./08-execution-flows.md)** — Deposit, withdraw, redeem, in-kind redeem, harvest, fees, swaps, governance, emergency
9. **[Mathematics](./09-mathematics.md)** — Share accounting, NAV, locked profit, high-water mark, fees, exposure, slippage — with worked examples
10. **[Contract Reference](./08-contracts/README.md)** — Contract-by-contract walkthrough
    - [RobinVault & ERC4626Paris](./08-contracts/vault.md)
    - [StrategyBase, CoreStrategy, GrowthStrategy](./08-contracts/strategies.md)
    - [OracleRegistry & RewardRegistry](./08-contracts/registries.md)
    - [ExecutionRouter & UniswapV2DexAdapter](./08-contracts/router-and-adapters.md)
    - [RobinAccountant & AccessManager](./08-contracts/accounting-and-access.md)
    - [Interfaces, Types & Libraries](./08-contracts/interfaces-types-libraries.md)

## Part IV — Quality, Operations & Communication

11. **[Testing](./11-testing.md)** — Unit, integration, invariant, and fuzz tests; mocks; coverage gaps
12. **[Security](./12-security.md)** — Threat model, mitigations, unmitigated risks, audit scope
13. **[Deployment](./13-deployment.md)** — Foundry toolchain, scripts, environment variables, operational checklist
14. **[CI/CD](./14-cicd.md)** — GitHub Actions, formatting, Slither, gas sizes
15. **[Production Readiness](./15-production-readiness.md)** — Implemented vs documented vs planned

## Part V — Stakeholder Preparation

16. **[Founder Guide](./14-founder-guide.md)** — Business narrative, design decisions, FAQ for founders
17. **[Interview Preparation](./15-interview-prep.md)** — 150 questions (beginner / intermediate / advanced) with answers
18. **[Glossary](./16-glossary.md)** — Blockchain, Solidity, and protocol-specific terms

## Diagram Assets

Standalone Mermaid sources in [`assets/`](./assets/):

- [architecture-overview.mmd](./assets/architecture-overview.mmd)
- [deposit-flow.mmd](./assets/deposit-flow.mmd)
- [harvest-flow.mmd](./assets/harvest-flow.mmd)
- [inkind-redemption-flow.mmd](./assets/inkind-redemption-flow.mmd)

## Meta

- **[Study Roadmap](./study-roadmap.md)** — Reading order, prerequisites, time estimates, milestones
- **[README](./README.md)** — Navigation hub

---

## Cross-Reference Index (by topic)

| Topic | Primary chapters |
|---|---|
| ERC-4626 share math | Ch. 3, 9, [vault.md](./08-contracts/vault.md) |
| Locked profit / profit smoothing | Ch. 4, 9, [vault.md](./08-contracts/vault.md) |
| In-kind redemption | Ch. 5, 8, [strategies.md](./08-contracts/strategies.md), DESIGN.md |
| Harvest pipeline | Ch. 8, [strategies.md](./08-contracts/strategies.md) |
| Oracle validation | Ch. 4, 12, [registries.md](./08-contracts/registries.md) |
| Fee accounting (cap-and-forfeit) | Ch. 9, [accounting-and-access.md](./08-contracts/accounting-and-access.md) |
| Access control / roles | Ch. 6, 13, [accounting-and-access.md](./08-contracts/accounting-and-access.md) |
| Index Finance integration | Ch. 5, [strategies.md](./08-contracts/strategies.md), OPEN_QUESTIONS.md |
