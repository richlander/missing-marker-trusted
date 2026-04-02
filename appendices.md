# Appendices

> Optional background material supporting the main proposal. The primary argument lives in [README.md](README.md), [cve-analysis.md](cve-analysis.md), [notable-patterns.md](notable-patterns.md), [language-comparison.md](language-comparison.md), and [scoring-methodology.md](scoring-methodology.md).

## Lossless Attestations

"Lossless" means every safety attestation is recorded in code and source control. There is never a compiler-accepted state where information is lost. `git blame` finds who attested safety and when. `grep` inventories every attestation. Code review tools can flag changes to attested methods for re-review.

In "absence means safe" designs, there is no attestation to find. An auditor cannot distinguish "reviewed and confirmed safe" from "never reviewed." When a safety-critical bug is found, `git blame` answers the question in a lossless system. In an inference-based system, there's nothing to find.

### Defense in Depth: The xz Backdoor Lesson

The [xz/liblzma backdoor](https://en.wikipedia.org/wiki/XZ_Utils_backdoor) illustrates why enforcement matters. There are three tiers of defense against malicious changes:

1. **Compiler errors** — the change cannot land without explicitly modifying the safety annotation. The strongest defense.
2. **Tool warnings** (valgrind, analyzers, etc.) — the change can land, but produces signals after the fact. An attacker with commit access can volunteer to "fix" the warnings.
3. **Diff review** — the change is visible in version control but has no structural salience. Requires a reviewer to notice the significance. The weakest defense.

The xz attacker operated at tiers 2 and 3: the diffs were structurally unremarkable, and when valgrind flagged stack layout mismatches, the attacker [misdirected the fix](https://github.com/tukaani-project/xz/commit/82ecc538193b380a21622aea02b0ba078e7ade92) and [disabled oss-fuzz detection](https://github.com/google/oss-fuzz/pull/10667). Advisory warnings were subverted because they were advisory. Compiler errors cannot be quietly absorbed — they require an explicit change to the safety model itself.

A `safe` keyword design operates at tier 1. Removing `safe` from a method with interior `unsafe` blocks is a compiler error — the method becomes unmarked and unmarked methods cannot contain `unsafe` blocks. Removing the `unsafe` blocks from a `safe` method is a compiler warning (unnecessary attestation). The attacker would have to explicitly change the safety annotations, producing a structurally remarkable diff — not a diff that looks like routine cleanup.

Lossy designs — where a safety boundary has no marker — operate at tier 3 at best. The diff that removes an `unsafe` block from an unmarked method looks like routine cleanup. There is no compiler error. There is no annotation change in the signature. The safety attestation simply vanishes from the code without any toolchain signal.

D's `@trusted` and the proposed C# `safe` keyword both produce lossless attestations at tier 1. Rust's and Swift's safety boundaries do not.

## Binary Distribution Raises the Bar

C#/.NET is primarily binary-distributed — consumers receive compiled assemblies, not source code. Compiler warnings during the library author's build are invisible downstream. Errors are the only safety signal that reliably crosses the binary boundary.

Rust and Swift are primarily source-distributed; their consumers compile from source and see warnings themselves. This asymmetry raises the bar for C#: anything that is "just a warning" is effectively invisible to the majority of consumers. We need a safety model built on errors, not warnings.

Swift faces a related challenge with Apple's own frameworks. During the [SE-0458 discussion](https://forums.swift.org/t/se-0458-opt-in-strict-memory-safety-checking/77274), it was noted that Apple's Combine framework is "written in Swift, but _not_ safe (by Swift 6's standard), and unlikely to become safe nor even acquire `unsafe` annotations." Douglas Gregor acknowledged this as "a hole" in the model. When closed-source, binary-distributed frameworks don't adopt safety annotations, consumers must trust those decisions with no ability to audit.

## Agent-Assisted Maintenance

The [PR feedback](https://github.com/dotnet/csharplang/pull/10058#pullrequestreview-4016744830) states: "High-confidence AI-assisted automation of the migration process flow is a part of the feature design." The inference cost of the safety model directly affects how effectively automation can participate.

A low-inference model enables agents to:
- Inventory safety boundaries (`rg -w "safe"` — complete, no AST required)
- Scope reviews (check each `safe` method's interior `unsafe` for correctness)
- Detect drift (new `unsafe` blocks in a `safe` method are flagged for re-review)
- Assist migration (propose `safe` or `unsafe` annotations for methods with interior unsafe blocks)

High-inference models force agents to build ASTs or rely on LSPs. This is more expensive, fragile across environments, and harder to validate.

More broadly, as tooling improves, designs that expose safety-relevant structure directly in source should be easier to review, audit, and migrate with high confidence. Requiring less inference is a design advantage independent of any particular generation of tools.

### The LSP Doesn't Solve This

The LSP protocol's `workspace/symbol` request filters by name and `SymbolKind` — but `SymbolKind` has no variant for unsafe or safe. No language server (rust-analyzer, SourceKit-LSP, Roslyn, serve-d) can query for safety-relevant code across a workspace. The LSP adds value as a *follow-up* to grep — call graphs, type hierarchy, targeted review — but only if grep can find the starting points.

## The `unsafe` Keyword Lineage

The `unsafe` keyword — for modern mainline languages — starts with C#. Earlier languages had related concepts (Modula-3's `UNSAFE` modules in 1989), but C# 1.0 (2001) introduced `unsafe` as a compiler-enforced keyword in a mainstream C-family language — the first to give the safe/unsafe boundary a syntactic marker in that lineage.

### Silverlight's security-transparency precedent

.NET already used a three-layer safety model in the [Silverlight security transparency system](https://learn.microsoft.com/previous-versions/dotnet/framework/code-access-security/security-transparent-code):

- Transparent
- Safe Critical
- Security Critical

Transparent code could only call other transparent or safe-critical code. Safe-critical and security-critical code had similar privileged capability, but different caller contracts: safe-critical code was the reviewed boundary that remained callable from transparent code and took responsibility for validation. That makes it direct prior art for an explicit safety-boundary marker in the .NET ecosystem.

- **C# / Silverlight:** transparent, safe-critical, security-critical
- **C# (2001):** `unsafe` as a compiler-enforced keyword
- **D (2010):** Three-layer model with `@safe`, `@trusted`, `@system`
- **Rust (2015):** Extended C#'s `unsafe`: `unsafe fn` as caller contract, `unsafe {}` as scoped interior unsafe
- **Swift (2024–2025):** `@unsafe` as attribute, `unsafe` as expression prefix

The safety boundary gap has discussion and productization to support it. D addressed it directly with `@safe`, `@trusted`, and `@system`, though its unsafe-first default limits the model to the `@safe` subset. Rust has engaged with it through [RFC 2585](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html) (separating "unsafe to call" from "body does unsafe things"), [RFC 3484](https://rust-lang.github.io/rfcs/3484-unsafe-extern-blocks.html) (introducing `safe` as a contextual keyword in extern blocks), and [documentation conventions](https://internals.rust-lang.org/t/pre-rfc-rust-safety-standard/23963) (`// SAFETY:` comments). Swift's SE-0458 marks unsafe code but not safety boundaries.

## Formal Verification Parallel

Terence Tao has arrived at a similar conclusion in mathematics research with the [Lean proof language](https://leanprover-community.github.io/). Lean makes proof obligations machine-checkable; `safe` makes safety attestations machine-discoverable — same principle, different domain. Tao's vision is that large groups of mathematicians and agents work together to produce compelling and trusted proofs. That requires the proof language to be lossless — exactly the property this proposal argues for in safety attestations.

## Tokenizer Comparison

The [OpenAI Tokenizer](https://platform.openai.com/tokenizer) shows that keyword and attribute representations are not equivalent from a model's perspective.

`unsafe` keyword:

![unsafe keyword tokens](https://github.com/user-attachments/assets/59554280-faa1-480b-ba2a-af8d6325a4e0)

`safe` keyword:

![safe keyword tokens](https://github.com/user-attachments/assets/ca0fde0d-52d4-49f5-b563-da7b5d5c1cf8)

`RequiresUnsafeAttribute` tokens:

![RequiresUnsafe attribute tokens](https://github.com/user-attachments/assets/1f9c97aa-a7f3-436d-9896-e9d561a679a4)

`RequiresUnsafeAttribute(true)` tokens:

![RequiresUnsafe(true) attribute tokens](https://github.com/user-attachments/assets/31914393-6aee-446c-a540-fc25b583372e)

`RequiresUnsafeAttribute(false)` tokens:

![RequiresUnsafe(false) attribute tokens](https://github.com/user-attachments/assets/ab90356e-9425-498d-a31d-24d99f6df7b9)

`unsafe` and `safe` are each single tokens. `RequiresUnsafeAttribute(false)` spans seven tokens. While tokenization alone does not determine comprehension, it is a reasonable proxy for representational complexity. The compound, double-negative form encodes the same safety information in a representation that is strictly harder to parse — for both humans and models.

> **Note:** The tokenizer images above were captured from an earlier draft that used `trusted` as the keyword. The `safe` keyword tokenizes identically to `trusted` — both are single tokens.

## Relevant Design Specs

- C#:
  - [Memory Safety in .NET](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/memory-safety.md) — project overview and goals
  - [Annotating members as `unsafe`](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md) — the caller-unsafe design
  - [Unsafe evolution](https://github.com/dotnet/csharplang/blob/main/proposals/unsafe-evolution.md) — C# language proposal and `RequiresUnsafe` attribute
  - [Alternative syntax for caller-unsafe](https://github.com/dotnet/csharplang/blob/main/meetings/working-groups/unsafe-evolution/unsafe-alternative-syntax.md) — attribute vs keyword tradeoffs
  - [Proposed modifications to unsafe spec](https://github.com/dotnet/csharplang/pull/10058) — follow-up proposing `unsafe`/`safe` keywords (open PR)
- D: [Memory-Safe D](https://dlang.org/spec/memory-safe-d.html)
- Rust: [RFC 2585 — unsafe block in unsafe fn](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html)
- Swift: [SE-0458 — Strict Memory Safety](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md)

---

See also: [CVE analysis](cve-analysis.md) for empirical evidence, [notable patterns](notable-patterns.md) for code examples, [language comparison](language-comparison.md) for cross-language scoring, and [scoring methodology](scoring-methodology.md) for the framework.
