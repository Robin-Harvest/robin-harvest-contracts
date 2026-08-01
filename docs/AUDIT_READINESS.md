# External Audit Readiness

## Scope package

The proposed audit scope is:

- `src/strategies/ConcentratedLiquidityStrategy.sol`
- `src/strategies/StrategyBase.sol`
- `src/libraries/PoolPriceLib.sol`, `ClActionPlanner.sol`, and `TickValidationLib.sol`
- `src/router/ExecutionRouter.sol`
- `src/registries/OracleRegistry.sol`
- the CL interfaces, policy, deployment scripts, and their integration boundaries

Architecture and operating assumptions are documented in `DESIGN.md`,
`DEPLOYMENT.md`, the handbook, and [SECURITY_HARDENING.md](./SECURITY_HARDENING.md).
The security properties are enumerated in [INVARIANTS.md](./INVARIANTS.md).

## Freeze checklist

- [x] Core CL implementation and migration-specific tests present
- [x] TWAP freshness policy selected and documented
- [x] Exact-per-operation Permit2 policy selected, tested, and documented
- [x] Oracle deviation units named and documented as sqrt-price BPS
- [x] Fork test harness and run command recorded
- [x] Static-analysis findings recorded with dispositions
- [ ] Coverage instrumentation produces a valid report
- [ ] Static-analysis findings accepted or remediated by security review
- [ ] Deployment addresses, oracle feeds, routes, governance, and timelocks finalized
- [ ] External auditor engaged and audit window opened

No external audit has been started from this workspace. Until the unchecked gates
are closed, the repository must remain blocked from production deployment and new
feature work should not be mixed into the audit candidate.

## Build and test artifacts

The latest local verification commands and outcomes are recorded in
`STATIC_ANALYSIS.md`. Foundry build outputs are generated under `out/`; deployment
broadcasts must be generated only from an approved environment with finalized
addresses and governance configuration. No live deployment was performed by this
review.

## Known audit questions

- Confirm reentrancy safety of all PositionManager, Permit2, router, policy, and
  oracle calls, including callbacks from official V4 components.
- Confirm the maximum operational position count and worst-case gas for rebalance,
  harvest, withdrawal, and emergency close.
- Confirm sqrt-price deviation thresholds are appropriate after squaring into token
  price terms.
- Confirm oracle decimal normalization and cross-rate direction for every asset and
  pool currency combination.
- Confirm the exact Permit2 allowance cleanup behavior on every revert path and with
  non-standard ERC20s.
- Repeat fork tests with production vault, oracle registry, execution router, and
  approved swap adapter addresses rather than test doubles.
