# Static Analysis and Verification Record

This is the hardening-gate record for the Uniswap V4 concentrated-liquidity migration.

## Commands and results

| Check | Command | Result |
|---|---|---|
| Build | `forge build --skip test` | Pass |
| Full tests | `forge test -vv` | 142 passed, 0 failed, 1 fork test skipped without RPC |
| Fork tests | `ROBINHOOD_FORK_RPC=... forge test --match-contract ConcentratedLiquidityStrategyForkTest -vv` | 4 passed |
| Slither | `slither . --fail-pedantic` | Non-zero; 47 intentional loop/equality findings remain for review |
| Solhint | `npx solhint@6.2.3 'src/**/*.sol'` | Exit 0, but emits existing style/NatSpec/remapping warnings |
| Gas | `forge test --gas-report test/unit/ConcentratedLiquidityStrategy.t.sol` | Pass; 13 CL tests and gas table generated |
| Coverage | `forge coverage --report summary ...` | Blocked by `stack too deep`; `--ir-minimum` also fails in Yul |

The Solhint run used Node 18.19.1 while Solhint 6.2.3 requests Node 20+, so its
warnings should be rerun in the pinned CI runtime before audit sign-off.

## Slither dispositions

The meaningful findings were addressed as follows:

- V4 and Permit2 amount fields are now checked before narrowing to `uint128` or
  `uint160`; oversized balances revert with `V4AmountOverflow`.
- Position set mutations now check the `EnumerableSet` return values.
- Swap return values are checked defensively against `minOut`.
- Future oracle timestamps are treated as unhealthy at the strategy boundary.
- Active positions are capped at `MAX_ACTIVE_POSITIONS = 16`, bounding accounting,
  harvest, withdrawal, rebalance, and emergency loops.
- Permit2 discovery now uses the official PositionManager `permit2()` getter rather
  than a low-level compatibility call.

The remaining findings are not silently suppressed:

- `reentrancy-*`: external calls are to immutable PositionManager, Permit2,
  ExecutionRouter, OracleRegistry, or policy dependencies. Public strategy entry
  points are guarded by `nonReentrant`; `deployFunds` and `freeFunds` are also
  guarded in `StrategyBase`. The remaining reports require auditor confirmation,
  especially state updates following PositionManager calls.
- `calls-inside-a-loop` and `costly-loop`: position sets are intentionally bounded
  operationally; rebalance and emergency close must process every tracked
  position. Gas limits must be validated against the configured maximum position
  count before production deployment.
- `incorrect-equality` and strict-zero checks: zero is used deliberately as a
  sentinel for unavailable TWAP/oracle values, empty liquidity, and optional swap
  routes.
- `divide-before-multiply`: StaticRangeRebalancePolicy aligns signed ticks using
  Solidity's signed division semantics before spacing normalization; this is
  intentional tick policy behavior.
- `unused-return`: timestamp metadata, set-operation booleans, and swap return
  values are intentionally ignored where balance deltas or route validation are
  the authoritative result.
- `missing-zero-check`: the route setter uses `address(0)` as an explicit disable
  sentinel and later causes `RouteNotConfigured` for non-dust swaps.

These dispositions are review notes, not a claim that the findings are resolved.
The `--fail-pedantic` gate should remain enabled in CI and must be rerun after any
audit remediation.

## Coverage limitation

Foundry coverage disables the repository's optimizer and `viaIR` settings for
source mapping. Without `viaIR`, `ConcentratedLiquidityStrategy` fails with
`stack too deep`; with `--ir-minimum`, the compiler fails with a Yul stack error.
This needs a toolchain-supported instrumentation strategy before production sign-off.
