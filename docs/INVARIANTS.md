# Concentrated Liquidity Strategy Invariants

These invariants define the properties required during audit and fork review.

## Ownership and destinations

- User ownership is represented only by vault shares.
- The strategy's only permitted asset destination is its immutable vault.
- Emergency return cannot send assets to an arbitrary caller or receiver.
- PositionManager approvals name only the immutable PositionManager and are exact
  per operation; successful operations clear both ERC20 and Permit2 allowances.

## Position state

- V1 permits at most one active V4 position NFT per strategy instance.
- An active position has validated, ordered, spacing-aligned ticks.
- Closing a position clears the active slot and updates accounting exactly once.
- Rebalance closes the active position, performs any needed paired-token swap, and
  mints the replacement position atomically.
- The active position count is bounded by `MAX_ACTIVE_POSITIONS = 1`; emergency
  and accounting operations therefore have a fixed operational upper bound.

## Modes and lifecycle

- `Active` permits deployment, tend, harvest, and rebalance subject to policy.
- `HarvestOnly` permits harvest but blocks new liquidity deployment and tend.
- `WithdrawOnly` blocks new deployment and allows withdrawal paths.
- `Paused` blocks governance changes and requires emergency close before emergency
  return.
- Strategy mode is independent of `StrategyBase` lifecycle state.

## Pricing and safety

- Oracle deviation thresholds are relative `sqrtPriceX96` deviations in BPS.
- Swap minimum outputs are oracle-derived and enforced by `ExecutionRouter`.
- Withdrawals with active positions require a complete, current-timestamp TWAP
  window; stale or short observation history cannot bypass that safety check.
- Hookless pools do not provide native TWAP; the internal observation ring is the
  sole TWAP source for this V1 strategy.
- Paired-token balances are converted back to the asset on withdrawal when a
  configured approved route and healthy oracle permit it; economically zero dust is
  not forced through a one-unit minimum-output swap.

## Existing executable coverage

- `test/unit/ConcentratedLiquidityStrategy.t.sol` covers mode transitions, exact
  Permit2 approvals, TWAP expiry, paired-token withdrawal, tick validation, and
  the one-active-position V1 bound.
- `test/invariant/ConcentratedLiquidityStrategyInvariant.t.sol` covers the active
  position bound and valid mode values.
- `test/fork/ConcentratedLiquidityStrategyFork.t.sol` covers real PoolManager and
  PositionManager deposit, fee/harvest, rebalance, withdrawals, emergency flow,
  unauthorized access, oracle failure, and TWAP expiry.
- Existing vault and protocol invariant suites cover NAV, loss, fee, and share
  accounting properties.
