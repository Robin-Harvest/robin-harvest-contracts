# Handbook Diagram Assets

Mermaid diagram sources for PDF/HTML export tools. Chapters embed equivalent diagrams inline; these files are the canonical standalone copies.

| File | Description | Primary chapter |
|---|---|---|
| [architecture-overview.mmd](./architecture-overview.mmd) | Full protocol component graph | [06-architecture.md](../06-architecture.md) |
| [deposit-flow.mmd](./deposit-flow.mmd) | ERC-4626 deposit sequence | [08-execution-flows.md](../08-execution-flows.md) |
| [harvest-flow.mmd](./harvest-flow.mmd) | Keeper harvest pipeline | [08-execution-flows.md](../08-execution-flows.md) |
| [inkind-redemption-flow.mmd](./inkind-redemption-flow.mmd) | Growth in-kind CEI sequence | [08-execution-flows.md](../08-execution-flows.md), DESIGN.md |

## Rendering

Using [Mermaid CLI](https://github.com/mermaid-js/mermaid-cli):

```bash
mmdc -i architecture-overview.mmd -o architecture-overview.png
```

Or paste `.mmd` body into any Mermaid-compatible Markdown renderer.
