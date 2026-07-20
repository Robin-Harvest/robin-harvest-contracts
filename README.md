# Robin Harvest Contracts

Foundry workspace for Robin Harvest, an ERC-4626 yield optimizer targeting Robinhood Chain and Index Finance (INDEX).

> **Warning:** This repository is unaudited. Do not deploy to production until external audit completion and all launch gates in the Final Architecture are satisfied.

## Status

| Phase | Scope | Status |
|---|---|---|
| 1–5 | Bootstrap, types, interfaces, mocks, AccessManager | Complete |
| 6 | RobinVault (ERC-4626, debt, profit lock, in-kind hook) | Complete |
| 7–9 | OracleRegistry, RewardRegistry, ExecutionRouter | Complete |
| 10–11 | StrategyBase, CoreStrategy (provisional Index Finance ABI) | Complete |
| 12–13 | GrowthStrategy (retention, liquidation order, conservative NAV, category policy) | Complete |
| 14 | Optional In-Kind Redemption UX, integration, and system tests | Complete |
| 15 | Deployment scripts and operational docs | Complete (pending live addresses) |

**Not in scope for this repository yet:** INDEX-ETH LP strategy (blocked on LP type confirmation), live Index Finance ABI finalization, production oracle/DEX addresses.

## Toolchain

- Foundry
- Solidity `0.8.25`
- EVM target `paris`
- OpenZeppelin Contracts `v5.6.1`
- forge-std `v1.9.7`

## Commands

```sh
forge fmt --check
forge build --sizes
forge test
```

CI runs formatting, build with size report, tests, and Slither.

## Architecture

- **RobinVault:** asset-agnostic ERC-4626 accounting, debt, profit smoothing, eligibility hooks, optional in-kind redemption coordination, timelocked strategy migration, fee integration.
- **CoreStrategy / GrowthStrategy:** isolated harvest strategies; Growth owns portfolio retention, exposure, liquidation, and in-kind payouts.
- **Registries + Router:** governance-configured oracles, reward policies, and constrained swaps (no arbitrary calldata).
- **RobinAccountant:** performance fees with high-water mark and annualized management fees.

See [DESIGN.md](./DESIGN.md) for in-kind redemption details and [docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md) for launch procedures.

## Open integration blockers

Resolve and document each item in [OPEN_QUESTIONS.md](./OPEN_QUESTIONS.md) before mainnet launch, especially:

- Official Index Finance distributor ABI and eligibility semantics
- Robinhood Chain DEX router and liquidity
- Oracle feeds for INDEX and each tokenized stock
- Governance multisig, timelock durations, and fee schedule

## Repository layout

- `src/access/` — AccessManager
- `src/accounting/` — RobinAccountant
- `src/adapters/` — DEX adapters
- `src/registries/` — Oracle and reward registries
- `src/router/` — ExecutionRouter
- `src/strategies/` — StrategyBase, CoreStrategy, GrowthStrategy
- `src/vaults/` — RobinVault
- `test/` — unit, integration, and invariant tests
- `script/` — deployment scripts
