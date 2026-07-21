# Study Roadmap — From Zero to Protocol Expert

This roadmap turns the handbook into a structured course. Times assume focused reading (not skimming). Adjust ±50% based on your background.

---

## Milestone 0 — Orientation (2–3 hours)

**Read:** [README.md](./README.md) → [01-introduction.md](./01-introduction.md) → [05-project-overview.md](./05-project-overview.md)

**Outcome:** You can explain what Robin Harvest does, Core vs Growth, and why it is not production-ready.

**Exercise:** Draw on paper: Depositor → Vault → Strategy → Index Finance. Label INDEX flow.

---

## Milestone 1 — Blockchain & EVM Literacy (12–18 hours)

**Prerequisites:** None

**Read:** [02-blockchain-fundamentals.md](./02-blockchain-fundamentals.md)

**Outcome:** You understand blocks, transactions, gas, EOAs vs contracts, ABI, deployment, RPC, validators.

**Exercise:** Use `cast` (after [13-deployment.md](./13-deployment.md) toolchain section) to read `totalSupply()` of any ERC-20 on a public chain.

**Checkpoint questions:**
- What is the difference between an EOA and a contract account?
- Why does every state change cost gas?
- What is calldata vs storage?

---

## Milestone 2 — Solidity Fluency (15–22 hours)

**Prerequisites:** Milestone 1

**Read:** [03-solidity-fundamentals.md](./03-solidity-fundamentals.md)

**Outcome:** You can read Robin Harvest contracts and predict storage layout, inheritance, and call types.

**Exercise:** Clone the repo, run `forge build`, open `RobinVault.sol` and identify every `external` function.

**Checkpoint questions:**
- When is `memory` vs `calldata` used?
- What does `delegatecall` preserve vs `call`?
- How does ERC-4626 convert assets to shares?

---

## Milestone 3 — DeFi & Vault Concepts (10–14 hours)

**Prerequisites:** Milestones 1–2

**Read:** [04-defi-fundamentals.md](./04-defi-fundamentals.md)

**Outcome:** You understand ERC-4626, NAV, yield strategies, oracles, AMMs, fees, MEV — in Robin Harvest context.

**Exercise:** Manually compute share mint for a 1000 INDEX deposit when `totalAssets=5000`, `totalSupply=4500`, decimals offset 6.

**Checkpoint questions:**
- Why exclude locked profit from `totalAssets()`?
- What is a high-water mark performance fee?
- How can oracle latency enable sandwich attacks on redemption?

---

## Milestone 4 — Architecture & Repository (8–12 hours)

**Prerequisites:** Milestones 1–3

**Read:** [06-architecture.md](./06-architecture.md) → [07-repository-walkthrough.md](./07-repository-walkthrough.md)

**Outcome:** You know every folder, dependency, and trust boundary.

**Exercise:** Run `forge test -vv` and map one failing/passing test to the contract it exercises.

**Checkpoint questions:**
- Why is `ERC4626Paris` local instead of OpenZeppelin's ERC4626?
- Which roles can call `harvest()`?
- What is shared vs per-vault in deployment?

---

## Milestone 5 — Execution & Mathematics (14–20 hours)

**Prerequisites:** Milestone 4

**Read:** [08-execution-flows.md](./08-execution-flows.md) → [09-mathematics.md](./09-mathematics.md)

**Outcome:** You can trace any user transaction through contracts with exact state changes.

**Exercise:** Write a sequence diagram for `GrowthStrategy.harvest()` with one retained and one sold reward.

**Checkpoint questions:**
- What is the CEI order for `redeemInKind`?
- How is cap-and-forfeit fee policy applied in `report()`?
- What rounding direction prevents overpayment on in-kind exit?

---

## Milestone 6 — Contract Mastery (25–40 hours)

**Prerequisites:** Milestone 5

**Read:** All files in [08-contracts/](./08-contracts/)

**Outcome:** You can explain every function, error, event, and edge case in the codebase.

**Exercise:** Pick `GrowthStrategy._freeFunds` and list every revert path with triggering condition.

**Checkpoint:** Complete 20 random questions from [15-interview-prep.md](./15-interview-prep.md) (advanced section).

---

## Milestone 7 — Security, Testing & Operations (12–18 hours)

**Prerequisites:** Milestone 6

**Read:** [11-testing.md](./11-testing.md) → [12-security.md](./12-security.md) → [13-deployment.md](./13-deployment.md) → [14-cicd.md](./14-cicd.md) → [15-production-readiness.md](./15-production-readiness.md)

**Outcome:** You can run CI locally, explain invariant properties, and execute deployment checklist.

**Exercise:** Run `slither .` and explain one finding vs one suppressed finding in `RobinVault`.

---

## Milestone 8 — Stakeholder Communication (6–10 hours)

**Prerequisites:** Milestones 4–7

**Read:** [14-founder-guide.md](./14-founder-guide.md) → [15-interview-prep.md](./15-interview-prep.md) → [16-glossary.md](./16-glossary.md)

**Outcome:** You can present to founders, pass a senior Solidity interview on this repo, and answer auditor scoping questions.

**Exercise:** Deliver a 10-minute architecture talk using only [06-architecture.md](./06-architecture.md) diagrams.

---

## Total Estimated Time

| Path | Hours |
|---|---|
| Minimum (experienced Solidity + DeFi) | ~60 |
| Standard (some programming, new to crypto) | ~100–120 |
| Complete (zero background, all exercises) | ~130–160 |

---

## Recommended Parallel Activities

1. **Run the test suite weekly** — `forge test`; note which tests cover features you are studying.
2. **Read `CHANGELOG.md` and `OPEN_QUESTIONS.md`** alongside Milestone 4 — they capture recent design decisions.
3. **Compare `DESIGN.md` in-kind section** with `GrowthStrategy.redeemInKind` when studying Milestone 5.

---

## When You Are "Done"

You are ready for founder-level technical design discussions when you can, **without notes**:

1. Draw the full protocol architecture from memory.
2. Walk through deposit → deploy → harvest → withdraw with accounting formulas.
3. Explain in-kind redemption invariants and fee cap-and-forfeit policy.
4. List production launch blockers and unsupported token assumptions.
5. Answer 40+ interview questions at intermediate level fluently.

Proceed to [02-blockchain-fundamentals.md](./02-blockchain-fundamentals.md) to begin.
