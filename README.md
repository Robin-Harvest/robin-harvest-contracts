# Robin Harvest Contracts

![Solidity](https://img.shields.io/badge/Solidity-0.8.25-blue)
![Foundry](https://img.shields.io/badge/Foundry-v1.9.7-orange)
![License](https://img.shields.io/badge/License-MIT-green)
![Version](https://img.shields.io/badge/Version-v0.1.0--alpha-purple)

Foundry workspace for Robin Harvest, an ERC-4626 yield optimizer targeting Robinhood Chain and Index Finance (INDEX).

## Version & Audit Status

**Current Version:** `v0.1.0-alpha`  
**Status:** Feature Complete / Pre-Audit

> ⚠️ **Audit Status:** No external audit has been completed. The protocol should be considered experimental until the launch checklist is fully satisfied.

## Production Readiness

Current repository status:
✅ Feature complete
✅ Integration tests
✅ Invariant tests
✅ Slither
⚠️ External integrations pending
⚠️ External audit pending
❌ Not approved for production deployment

## Quick Start

```bash
git clone https://github.com/Robin-Harvest/robin-harvest-contracts.git
cd robin-harvest-contracts

# Install dependencies
forge install

# Compile contracts
forge build

# Run test suite
forge test

# Run static analysis
slither .
```

## Status

| Phase | Scope | Status |
|---|---|---|
| 1–5 | Bootstrap, types, interfaces, mocks, AccessManager | Complete |
| 6 | RobinVault (ERC-4626, debt, profit lock, in-kind hook) | Complete |
| 7–9 | OracleRegistry, RewardRegistry, ExecutionRouter | Complete |
| 10–11 | StrategyBase, CoreStrategy (provisional Index Finance ABI) | Complete |
| 12–13 | GrowthStrategy (retention, liquidation order, conservative NAV, category policy) | Complete |
| 14 | Optional In-Kind Redemption UX, integration, and system tests | Complete |
| 15 | Deployment scripts and operational docs | Complete |
| 16 | rhINDEX-LP Strategy (DEX liquidity provision, Gauge staking, optimal deposit swap math, LP valuation, stateful LP invariant suite) | Complete |

## Features

- ERC-4626 compliant vault architecture
- **Three Vault Strategy Products**: Core (Lending Yield), Growth (Stock Token Retention), and LP (DEX Liquidity Provision & Auto-compounding)
- Automated optimal ratio swap calculation for single-sided INDEX deposits into DEX LP pools
- Automated gauge staking and arbitrary reward token harvest & auto-compounding
- Oracle-backed reward valuation & liveness-first accounting policy
- Constrained execution router with max deviation protection
- Configurable reward registry
- Conservative NAV accounting
- Category exposure enforcement
- Optional in-kind redemption for Growth vaults
- Performance + management fee accounting
- Timelocked strategy migration
- Linear profit unlocking / lockup smoothing
- AccessManager-based governance

## Supported Standards

- **ERC-20**: Standard token integration for all assets and rewards.
- **ERC-4626**: Tokenized vault standard for deposits and redemptions.
- **EIP-170**: Compliant runtime bytecode size for all deployed contracts.

## Protocol Flow

```mermaid
flowchart TD
    Depositor --> RobinVault
    RobinVault --> Strategy
    
    Strategy --> IndexFinance
    
    Strategy --> ExecutionRouter
    ExecutionRouter --> DEX
    
    Strategy --> OracleRegistry
    Strategy --> RewardRegistry
    
    Strategy --> Portfolio
    
    %% Optional in-kind redemption flow
    RobinVault -. redeemInKind .-> Portfolio
```

### Redemption UX
- **Standard ERC4626 `redeem()`**: INDEX only (liquidates retained assets as necessary).
- **Optional `redeemInKind()`**: Proportional INDEX + retained stock rewards.

## Backward Compatibility & Gas Impact

The implementation is structured as an optional extension and does not modify or disrupt existing core accounting:
- Standard ERC4626 deposits and withdrawals remain unaffected.
- The CoreStrategy, Harvest pipeline, and Reward processing flow identically.
- Gas overhead is strictly isolated to the users who opt-in to `redeemInKind()`, meaning standard users pay no additional penalty.

## Security Assumptions

Robin Harvest assumes:
- trusted governance
- approved reward tokens
- approved oracle feeds
- approved DEX adapters
- standard ERC20 retained assets
- non-malicious external protocols

**Oracle Valuation & Liveness Policy**:
- Protocol liveness is prioritized over temporary NAV precision during price feed disruptions.
- If an oracle feed for a retained token is stale, paused, or invalid, the token's value is safely treated as `0` during NAV calculation rather than reverting vault operations.
- Operators receive `UnpriceableAssetSkipped` event alerts during liquidation routines and must treat unpriced feeds as operational alerts requiring oracle remediation.

**Explicitly Unsupported:**
- fee-on-transfer tokens
- rebasing tokens
- ERC777
- callback-enabled wrappers
- transfer-tax tokens

## External Audit Scope

The intended external audit includes:
- Vault accounting
- Strategy accounting
- Oracle integration
- Reward processing
- Execution router
- In-kind redemption
- Fee accounting
- Strategy migration

## Launch Checklist

Before production:
- [ ] Official Index Finance ABI
- [ ] Production oracle feeds
- [ ] Production DEX routes
- [ ] Governance multisig
- [ ] Timelock configuration
- [ ] Mainnet fork tests
- [ ] External audit
- [ ] Audit remediation

## Current Limitations & External Integrations

Current implementation assumes:
- Official Index Finance integration is still provisional.
- Production oracle addresses are not finalized.
- Production DEX routes remain external configuration.
- LP strategy not yet implemented (blocked on LP type confirmation).

## Toolchain & Tests

- Foundry (Solidity `0.8.25`, EVM target `paris`)
- OpenZeppelin Contracts `v5.6.1`
- forge-std `v1.9.7`

Current repository test suite includes:
- Unit tests
- Integration tests
- Stateful invariant tests
- Fuzz tests

## Commands

```sh
forge fmt --check
forge build --sizes
forge test
```
CI runs formatting, build with size report, tests, and Slither. 

> **Note on EIP-170**: `GrowthStrategy` and all other core contracts remain below the EIP-170 runtime size limit (24.576 kb) after implementation. Deployment sizes are continuously verified in CI using `forge build --sizes`.

## Deployment

Deployment consists of:
1. Deploy contracts
2. Governance initialization
3. Registry configuration
4. Strategy wiring
5. Deployment verification
6. Testnet validation
7. Production enablement

See [docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md) for launch procedures.

## License

MIT
