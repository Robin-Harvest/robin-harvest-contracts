# Robin Harvest Contracts

Foundry workspace for Robin Harvest, an intended on-chain protocol targeting Robinhood Chain. This repository has completed **Phase 5: protocol access management**. It contains chain-agnostic primitives, interface boundaries, test-only external-system stand-ins, and an OpenZeppelin-based role authority, but no deployment scripts or production registries, vaults, routers, or strategies.

> **Warning:** This repository is unaudited, incomplete, and not production-ready.

## Toolchain

- Foundry
- Solidity `0.8.25`
- EVM target `paris` (conservative temporary target pending Robinhood Chain confirmation)
- OpenZeppelin Contracts `v5.6.1`
- forge-std `v1.9.7`

## Setup

Copy `.env.example` to `.env` and provide only values confirmed by official sources. Never commit secrets.

When network access is available, install the exact dependency revisions:

```sh
forge install OpenZeppelin/openzeppelin-contracts@v5.6.1 --no-commit
forge install foundry-rs/forge-std@v1.9.7 --no-commit
```

In an offline environment, leave `lib/` empty and run those commands later. The remappings are already configured.

## Commands

```sh
forge fmt --check
forge build
forge test
forge build --sizes
```

The current phase contains Solidity primitives, interfaces, and test-only mocks but intentionally has no executable production protocol contracts. These commands validate compilation, formatting, and the installed dependencies.

## Security posture

No external ABI, address, oracle feed, DEX route, token behavior, role holder, or network capability is assumed. Resolve and document each item in [OPEN_QUESTIONS.md](./OPEN_QUESTIONS.md) before it is used. Future code must follow least privilege, explicit validation, deterministic testing, and independent audit practices.

## Repository layout

- `src/types/` — shared enums and data-only structs
- `src/libraries/` — shared errors, constants, and canonical event declarations
- `src/interfaces/` — internal protocol boundaries
- `src/interfaces/external/` — provisional external ABIs requiring live-contract verification
- `src/access/` — OpenZeppelin-based protocol access authority
- `test/mocks/` — deterministic test-only INDEX, stock-token, oracle, DEX, and reward-distributor stand-ins
- `test/unit/` — focused unit tests for implemented production components
- `test/` — future unit, fuzz, invariant, fork, and integration tests
- `script/` — future deployment and administration scripts
- `docs/` — future architecture and operational documentation
- `lib/` — pinned Foundry dependencies

Empty directories contain `.gitkeep` files so the intended layout is tracked.

## Roadmap

1. **Phase 1 — Repository bootstrap:** implemented.
2. **Phase 2 — Types, errors, events, and constants:** implemented.
3. **Phase 3 — Internal and external interfaces:** implemented.
4. **Phase 4 — Mocks:** implemented.
5. **Phase 5 — AccessManager:** implemented.
6. **Phases 6–13 — Registries, execution, vault, and strategies:** intentionally unimplemented.
6. **Phase 14 — Invariant and adversarial testing:** intentionally unimplemented.
7. **Phase 15 — Deployment tooling and documentation:** intentionally unimplemented.

Implementation must stop after Phase 5 until Phase 6 is explicitly approved. Deployment must transfer root administration to approved governance, assign operational holders, configure target selectors with least privilege, and choose delays from reviewed governance requirements. Test mocks do not establish live ABI compatibility; verification remains blocked on [OPEN_QUESTIONS.md](./OPEN_QUESTIONS.md).
