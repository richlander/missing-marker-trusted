# Scoring Methodology

## Why Grep?

Code review — the primary context where safety-critical code is evaluated — operates at the same level as grep. When reviewing a pull request in GitHub or any diff view, there is no sophisticated language-specific tooling. The reviewer's tools are their eyes and Ctrl/CMD-F. An agent is more likely to use grep. Source code should stand on its own for safety review.

We can use grep as a proxy for sound language design, matching how [`jq` has been used as the arbiter of sound schema design](https://github.com/dotnet/designs/blob/main/accepted/2025/cve-schema/cve_schema.md#design-philosophy). If a safety-relevant question can't be answered by grep, the language design has failed at explicit self-description.

Search ergonomics are a fitness property of the safety model. Language-specific tools are part of that and so is grep. The addition of explicit keywords will make agent enablement easier and increase confidence by eliminating footguns and offering implicit skills for agents that are asked to review code.

## Grep Difficulty Scale

Each discovery task is scored on a 0–2 scale based on the grep difficulty required:

| Method | Score | Rationale |
|--------|-------|-----------|
| Clean grep | 2 | Easy grep, always accurate |
| Grep with pattern knowledge | 1.5 | Harder grep (regex, `-A 1`, multiline), always accurate |
| Script (awk/parser) | 0.5 | Approximation with known false positives, not authoritative |
| Not possible / invisible | 0 | Requires AST/LSP or information doesn't exist in the source |

## Metric Descriptions

Scores are organized into two categories: **positive metrics** (discovery capability and auditing design) and **demerits** (observable problems in the grep workflow). Positive metrics measure how well the design supports auditing. Demerits measure friction an auditor or agent encounters when interpreting grep results.

### Discovery: Find safety boundaries (weight: 3)

Safety boundary functions are where human judgment meets compiler enforcement. A developer has reviewed the interior unsafe code and attests that the function is safe to call. These are the highest-value audit targets — if a safety boundary attestation is wrong, the safe code that depends on it is silently unsound.

### Discovery: Find unsafe declarations (weight: 3)

Unsafe declarations — functions that are unsafe to call — are the second audit priority. They contain the operations that safety boundaries depend on. An auditor reviewing a safety boundary needs to understand what unsafe functions it calls and what contracts those functions require.

### Discovery: Safe as default (weight: 3)

Safe-as-default makes safety boundaries exhaustive roots of the audit graph. Scored as a binary property: 3 points if safe is the default, 0 if not. This is related to but distinct from enforcement: safe-as-default determines whether grep targets are *exhaustive* (all paths covered), while enforcement determines whether they are *correct* (annotations are authoritative). D satisfies enforcement but not exhaustiveness. Swift satisfies exhaustiveness but not enforcement.

### Auditing design: Outer unsafe is viral contract (+1)

When `unsafe` on a function signature propagates to callers — requiring them to also be in an unsafe context — the unsafety spreads upward through the call chain until a `safe` method absorbs it. This creates a traceable chain from unsafe operations through to their safety boundary. Without this property, `unsafe` merely enables a scope and the call graph carries no safety information.

### Auditing design: Inner unsafe is constrained (+1)

When interior `unsafe` blocks are implementation-only — hidden from callers, absorbed by the enclosing safety boundary — the audit surface is minimized. The compiler verifies everything outside the `unsafe` blocks; the semantic auditor (human or agent) focuses only on what's inside them.

### Auditing design: Enforcement on by default (+3)

When the safety model runs without opt-in, grep results reflect ground truth from the start — there is no adoption gap where annotations are incomplete. Rust's borrow checker, lifetime system, and unsafe propagation are active in every Rust project by default. C#'s current `unsafe` gate is similarly default-on. New C# proposals (including `safe`) require opting in to the new model, so they lose this credit until the model matures. Swift's strict memory safety requires `-strict-memory-safety`. D's `@safe` is opt-in per function.

The weight of 3 reflects that default-on enforcement is a significant advantage — it is what allows Rust's safety model to be trusted across the ecosystem without per-project verification. This also partially accounts for Rust's borrow checker, which is a comprehensive verification system that this discoverability-focused scoring does not otherwise measure.

### Demerit: Grep ambiguity (-1 each)

A grep ambiguity demerit applies when a single grep pattern returns results with mixed safety roles. Each distinct source of ambiguity is an independent -1 demerit.

**`unsafe` mixes methods, blocks, and types (-1).** Observable: run `rg "unsafe"` on a C# codebase. The results include `unsafe void M()` (method signatures), `unsafe { }` (blocks), `unsafe class` (type declarations), and `unsafe` fields. The auditor cannot determine the safety role of a hit without reading context. Applies to: all C# variants.

**`unsafe class` makes members implicitly unsafe (-1).** Observable: methods inside an `unsafe class` have no per-method `unsafe` marker — invisible to grep. Applies to: C# (current), C# + `RequiresUnsafe`. Does not apply to designs where `unsafe class` is an error requiring per-method marking.

**`RequiresUnsafe` mixes true and false (-1).** Observable: `rg "RequiresUnsafe"` returns both `[RequiresUnsafe]` (caller-unsafe) and `[RequiresUnsafe(false)]` (safety boundary) in the same result set. No other language encodes two distinct safety roles in a single identifier distinguished by a boolean parameter. Applies to: C# + `RequiresUnsafe`.

### Demerit: Audit-based model (varies)

An enforcement-based model (errors) guarantees that grep results are complete. An audit-based model (warnings) means annotations are aspirational. Observable: build [apple/swift-collections](https://github.com/apple/swift-collections) with `-strict-memory-safety` — 12,526 warnings, but grep finds only 158 explicit `unsafe` expressions (11%).

The demerit is scaled by distribution model. Source-distributed languages: -1 (consumers can run the compiler). Binary-distributed languages (C#/.NET): -3 (warnings invisible to consumers). C#'s binary distribution is a consequence of language design — .NET's stable metadata format made binary distribution possible; NuGet followed. Errors are the only safety signal that crosses the binary boundary.

### Demerit: Duplicate marking (-1)

Observable: under `[RequiresUnsafe]`, pointer-bearing methods carry both `unsafe` (scope enabler) and `[RequiresUnsafe]` (caller-unsafe semantics). In dotnet/runtime, 97% of methods with pointers would require this dual annotation.

## Scoring Detail

**Discovery** (max 15):

| Task | Weight | D | Rust | Swift | C# (current) | C# + `unsafe` keyword | C# + `RequiresUnsafe` | C# + `unsafe` + `safe` | C# (optimal) |
|------|--------|---|------|-------|---------------|------------------------|------------------------|--------------------------|---------------|
| Find safety boundaries | 3 | 2 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 2 | 2 |
| Find unsafe declarations | 3 | 0 | 2 | 1.5 | 1.5 | 1.5 | 1.5 | 1.5 | 1.5 |
| Safe as default | 3 | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Discovery subtotal** | | **6** | **10.5** | **9** | **9** | **9** | **9** | **13.5** | **13.5** |

**Auditing design** (max 5):

| Sub-point | D | Rust | Swift | C# (current) | C# + `unsafe` keyword | C# + `RequiresUnsafe` | C# + `unsafe` + `safe` | C# (optimal) |
|-----------|---|------|-------|---------------|------------------------|------------------------|--------------------------|---------------|
| Outer unsafe is caller contract | 1 | 1 | 1 | 0 | 1 | 1 | 1 | 1 |
| Inner unsafe is implementation-only | 1 | 1 | 1 | 0 | 1 | 1 | 1 | 1 |
| Enforcement on by default | — | 3 | — | 3 | — | — | — | 3 |
| **Auditing subtotal** | **2** | **5** | **2** | **3** | **2** | **2** | **2** | **5** |

**Demerits:**

| Condition | D | Rust | Swift | C# (current) | C# + `unsafe` keyword | C# + `RequiresUnsafe` | C# + `unsafe` + `safe` | C# (optimal) |
|-----------|---|------|-------|---------------|------------------------|------------------------|--------------------------|---------------|
| `unsafe` mixes methods, blocks, and types | — | — | — | -1 | -1 | -1 | -1 | -1 |
| `unsafe class` makes members implicitly unsafe | — | — | — | -1 | — | -1 | — | — |
| `RequiresUnsafe` mixes true and false | — | — | — | — | — | -1 | — | — |
| Audit-based, source-delivered | — | — | -1 | — | — | — | — | — |
| Audit-based, binary-delivered | — | — | — | -3 | — | — | — | — |
| Duplicate marking | — | — | — | — | — | -1 | — | — |
| **Total demerits** | **0** | **0** | **-1** | **-5** | **-1** | **-4** | **-1** | **-1** |

## Combined Results

Base possible: 15 (discovery) + 5 (auditing) = **20**

| Language | Discovery | Auditing | Demerits | Total | % |
|----------|-----------|----------|----------|-------|---|
| C# (optimal) | 13.5 | 5 | -1 | 17.5 | 87.5% |
| Rust | 10.5 | 5 | 0 | 15.5 | 77.5% |
| C# + `unsafe` + `safe` | 13.5 | 2 | -1 | 14.5 | 72.5% |
| C# + `unsafe` keyword | 9 | 2 | -1 | 10 | 50.0% |
| Swift | 9 | 2 | -1 | 10 | 50.0% |
| D | 6 | 2 | 0 | 8 | 40.0% |
| C# (current) | 9 | 3 | -5 | 7 | 35.0% |
| C# + `RequiresUnsafe` | 9 | 2 | -4 | 7 | 35.0% |

## Note on Weighting

The three discovery dimensions are equally weighted at 3 points each. Safe-as-default separates D from the safe-first languages: D scores perfectly on safety boundary discovery but its unsafe-first default means those boundaries only cover the safe subset. Rust has the opposite profile — safe-as-default but no safety boundary marker. Enforcement on by default (+3) recognizes that Rust's borrow checker and C#'s current `unsafe` gate run without opt-in, while new C# proposals, Swift, and D require explicit adoption. C# (optimal) represents the mature state where the `safe`/`unsafe` model is no longer opt-in.

## Roadmap

| Step | Change | Score |
|------|--------|-------|
| C# (current) | — | **35.0%** |
| + `unsafe` keyword (caller contract) | Caller contract, implementation-only scoping | **50.0%** |
| + `safe` keyword | Safety boundaries become grep-discoverable | **72.5%** |
| + default-on | Model maturity, no longer opt-in | **87.5%** |

See [language-comparison.md](language-comparison.md) for the per-language analysis that applies this methodology.
