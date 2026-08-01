# Chapter 14 — CI/CD

## 14.1 Overview

Three GitHub Actions workflows on push and pull_request:

| Workflow | File | Purpose |
|---|---|---|
| Test | `.github/workflows/test.yml` | Build sizes + tests |
| Format | `.github/workflows/fmt.yml` | `forge fmt --check` |
| Slither | `.github/workflows/slither.yml` | Static analysis |

All use pinned action SHAs for supply-chain security.

---

## 14.2 Test Workflow

```yaml
env:
  FOUNDRY_PROFILE: ci
steps:
  - checkout (submodules recursive)
  - foundry-toolchain v1.3.1
  - forge build --sizes
  - forge test -vvv
```

**CI profile** increases fuzz (1000) and invariant (500, depth 128) runs vs local default.

**EIP-170:** `--sizes` fails if contract bytecode exceeds limit.

---

## 14.3 Format Workflow

Ensures consistent Solidity style via `forge fmt --check`. Run locally:

```bash
forge fmt
forge fmt --check
```

---

## 14.4 Slither Workflow

1. Python 3.12 + pip install from `.github/slither-requirements.txt`
2. `forge build --build-info`
3. `slither . --fail-pedantic`

Slither config: `slither.config.json` — project-specific filters.

In-contract suppressions use `slither-disable-next-line` with justifications.

---

## 14.5 Coverage

No dedicated coverage workflow in repo currently. Local:

```bash
forge coverage
```

**Current gap:** Foundry coverage instrumentation disables the production
`viaIR` configuration and currently fails on `ConcentratedLiquidityStrategy` with
`stack too deep`. No CI coverage threshold is enforced until an instrumented build
works (see [`../STATIC_ANALYSIS.md`](../STATIC_ANALYSIS.md)).

---

## 14.6 Gas Snapshots

Not automated in CI beyond `forge build --sizes`. Optional:

```bash
forge snapshot
```

The current targeted CL gas report is generated with:

```bash
forge test --gas-report test/unit/ConcentratedLiquidityStrategy.t.sol
```

---

## 14.7 Release Workflow

No automated release/tag workflow in repo. Version tracked in README badge and CHANGELOG manually.

Suggested production process (not implemented):

1. Tag semver after audit
2. Archive `deployments/` manifest
3. Publish verification links

---

## 14.8 Local CI Parity

```bash
FOUNDRY_PROFILE=ci forge build --sizes
FOUNDRY_PROFILE=ci forge test -vvv
forge fmt --check
slither . --fail-pedantic
```

---

**Next:** [15-production-readiness.md](./15-production-readiness.md)
