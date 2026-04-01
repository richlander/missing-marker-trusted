# Missing Marker Proposal Summary

Memory safety v2 is one of the most high-stakes features that we've taken on. It directly relates to the most foundational value propositions of the language and runtime and to other industry languages. It's where we have to adopt our most strict and critical design sensibilities.

Safety boundaries — where safe code guards unsafe operations — are the most critical audit targets in any memory-safe codebase. No safe-by-default language marks them. D's `@trusted` is the sole prior art, but D is unsafe-by-default, so its safety boundaries only cover the `@safe` subset — not the whole program. This proposal adds a `safe` keyword to C# so that safety boundaries are explicitly marked, grep-discoverable, lossless under `git blame`, and — because C# is safe-by-default — exhaustive roots of the audit graph.

| Design | Score |
|--------|-------|
| C# (optimal) — `unsafe` + `safe`, default-on | **87.5%** |
| Rust | **77.5%** |
| C# + `unsafe` + `safe` (opt-in) | **72.5%** |
| C# + `unsafe` keyword (no `safe`) | **50.0%** |
| Swift | **50.0%** |
| D | **40.0%** |
| C# (current) | **35.0%** |
| C# + `RequiresUnsafe` | **35.0%** |

- [The `safe` keyword proposal](proposal.md) — critique of CallerUnsafe, the safety boundary pattern, the `safe` keyword, and grep-ability
- [The safety boundary concept](safety-boundary.md) — three-layer model, propagation vs encapsulation, detailed design
- [Safe code guarding unsafe operations](safe-guards-unsafe-examples.md) — real-world examples from .NET, Rust, and Swift standard libraries
- [Language comparison](language-comparison.md) — grep-based discoverability across D, Rust, Swift, and C#, in ranking order
- [Scoring methodology](scoring-methodology.md) — the grep test framework and detailed scoring
- [Appendices](appendices.md) — lossless attestations, xz backdoor lesson, binary distribution, agent workflows, keyword lineage
