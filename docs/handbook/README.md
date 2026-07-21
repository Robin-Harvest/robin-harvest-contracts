# Robin Harvest Protocol — Definitive Technical Handbook

**Version:** v0.1.0-alpha (repository state)  
**Audience:** Founders, senior Solidity engineers, auditors, investors, contributors, recruiters  
**Status:** Pre-audit / feature-complete implementation

---

## About This Handbook

This handbook is the authoritative technical reference for the **Robin Harvest** smart contract system. It was generated from a line-by-line reading of every Solidity contract, interface, library, deployment script, test, invariant, fuzz test, GitHub workflow, configuration file, and markdown document in the [`robin-harvest-contracts`](https://github.com/Robin-Harvest/robin-harvest-contracts) repository.

**When documentation disagrees with implementation, the implementation is authoritative.** Discrepancies are called out explicitly.

---

## How to Read This Book

| If you are… | Start here |
|---|---|
| Completely new to blockchain | [01-introduction.md](./01-introduction.md) → [02-blockchain-fundamentals.md](./02-blockchain-fundamentals.md) |
| Know Ethereum but not this repo | [05-project-overview.md](./05-project-overview.md) → [06-architecture.md](./06-architecture.md) |
| A Solidity engineer joining the team | [07-repository-walkthrough.md](./07-repository-walkthrough.md) → [08-contracts/](./08-contracts/) |
| An auditor | [12-security.md](./12-security.md) → [08-contracts/](./08-contracts/) → [11-testing.md](./11-testing.md) |
| A founder or investor | [14-founder-guide.md](./14-founder-guide.md) → [06-architecture.md](./06-architecture.md) |
| Preparing for an interview | [study-roadmap.md](./study-roadmap.md) → [15-interview-prep.md](./15-interview-prep.md) |

For a structured learning path with time estimates, see **[study-roadmap.md](./study-roadmap.md)**.

For the complete chapter list in reading order, see **[SUMMARY.md](./SUMMARY.md)**.

---

## Repository Quick Facts

| Property | Value |
|---|---|
| Language | Solidity 0.8.25 |
| Framework | Foundry (forge-std v1.9.7) |
| EVM target | Paris |
| Token standard | ERC-4626 vault shares over INDEX |
| Strategies | CoreStrategy (sell-all rewards), GrowthStrategy (retain + in-kind redemption) |
| Governance | OpenZeppelin AccessManager v5.6.1 |
| External deps | Index Finance (provisional ABI), Chainlink-shaped oracles, Uniswap V2-style DEX |
| Production status | **Not approved for production deployment** — external audit pending |

---

## Complete File Index

| File | Topic |
|---|---|
| [01-introduction.md](./01-introduction.md) | Orientation |
| [02-blockchain-fundamentals.md](./02-blockchain-fundamentals.md) | Blockchain / EVM |
| [03-solidity-fundamentals.md](./03-solidity-fundamentals.md) | Solidity |
| [04-defi-fundamentals.md](./04-defi-fundamentals.md) | DeFi concepts |
| [05-project-overview.md](./05-project-overview.md) | Robin Harvest products |
| [06-architecture.md](./06-architecture.md) | System architecture |
| [07-repository-walkthrough.md](./07-repository-walkthrough.md) | Repo layout |
| [08-execution-flows.md](./08-execution-flows.md) | Transaction flows |
| [09-mathematics.md](./09-mathematics.md) | Formulas & examples |
| [08-contracts/](./08-contracts/) | Per-contract reference |
| [11-testing.md](./11-testing.md) | Test suite |
| [12-security.md](./12-security.md) | Security model |
| [13-deployment.md](./13-deployment.md) | Deploy & ops |
| [14-cicd.md](./14-cicd.md) | CI/CD |
| [15-production-readiness.md](./15-production-readiness.md) | Launch readiness |
| [14-founder-guide.md](./14-founder-guide.md) | Founder narrative |
| [15-interview-prep.md](./15-interview-prep.md) | 150 Q&A |
| [16-glossary.md](./16-glossary.md) | Term definitions |
| [study-roadmap.md](./study-roadmap.md) | Learning path |

## Diagram Assets

Mermaid source diagrams are stored under [`assets/`](./assets/). Markdown chapters embed diagrams inline; the assets folder preserves standalone copies for PDF conversion tooling.

---

## License

The Robin Harvest contracts are MIT-licensed. This handbook describes that codebase and does not constitute financial, legal, or investment advice.
