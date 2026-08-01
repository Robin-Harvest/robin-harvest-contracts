# CL Strategy Security Hardening Record

This document records the security decisions and validation gates for the Uniswap V4 concentrated-liquidity strategy.

## TWAP freshness

The strategy maintains up to 64 observations because hookless V4 pools do not provide a native oracle. The TWAP helper now evaluates observations against the current block timestamp. It returns no TWAP when:

- the newest observation is in the future;
- the newest observation is older than the configured window; or
- the retained observations do not cover the complete configured window.

Withdrawals with active positions require a valid full-window TWAP. Deposits and rebalances continue to use the Chainlink-derived oracle/spot check when the internal TWAP is unavailable.

The default window is 30 minutes. This policy intentionally makes a withdrawal unavailable after observation expiry rather than silently treating stale observations as current.

## Permit2 approval policy

The selected policy is **exact-per-operation approval**:

1. The strategy approves Permit2 for the exact currency amounts supplied to a mint or increase operation.
2. Permit2 approves only the immutable PositionManager as spender.
3. The ERC20 and Permit2 allowances are cleared after successful settlement.
4. A failed operation reverts the entire transaction, including the temporary approvals.

This avoids persistent unlimited allowances. The trust model still includes the official Permit2 and PositionManager contracts, but neither receives an ongoing unlimited token allowance from the strategy.

## Oracle deviation units

`oracleSqrtPriceDeviationBps` and `maxWithdrawSqrtPriceDeviationBps` are explicitly **relative sqrt-price deviation** thresholds, not actual price-ratio thresholds.

For example, a value of `300` means 3% deviation in `sqrtPriceX96`. Because token price is proportional to the square of sqrt price, this is not equivalent to a 3% token-price deviation. Names, NatSpec, events, and tests use the sqrt-price definition consistently.

## Trust boundaries

- The strategy has one immutable vault destination.
- Emergency return transfers pool currencies only to that vault.
- The strategy uses official V4 PoolManager and PositionManager interfaces.
- The strategy bounds active positions to 16 to cap looped accounting and emergency
  work.
- Swaps pass through the approved ExecutionRouter and adapter route.
- Oracle prices must be healthy and fresh according to OracleRegistry configuration.
- Governance cannot mutate CL configuration while the strategy is paused.

## Validation status

Completed locally:

- Forge build
- 142 unit, fuzz, and invariant tests
- TWAP expiry regression coverage
- Exact Permit2 approval and cleanup coverage
- Four fork scenarios against deployed Robinhood Chain V4 contracts
- Targeted CL gas report

Analysis results and limitations are recorded in
[STATIC_ANALYSIS.md](./STATIC_ANALYSIS.md). Coverage currently cannot compile this
via-IR-heavy repository under Foundry's coverage instrumentation; that remains a
release gate rather than an accepted coverage result.

Remaining release gates:

- Resolve or explicitly accept the documented static-analysis findings
- Obtain a coverage report using a supported instrumented build
- External audit and remediation
