# Language Comparison: Safety Boundary Discoverability

This document compares safety boundary and unsafe code discoverability across languages, ordered by [discoverability score](scoring-methodology.md). The methodology uses grep as a proxy for inference cost, matching how [`jq` has been used as the arbiter of sound schema design](https://github.com/dotnet/designs/blob/main/accepted/2025/cve-schema/cve_schema.md#design-philosophy) — if a safety-relevant question can't be answered by grep, the language design has failed at explicit self-description.

Source repos used:
- D: [dlang/phobos](https://github.com/dlang/phobos)
- Rust: [rust-lang/rust](https://github.com/rust-lang/rust) (`library/`)
- Swift: [swiftlang/swift](https://github.com/swiftlang/swift) (`stdlib/`)
- C#: [dotnet/runtime](https://github.com/dotnet/runtime) (`src/libraries/`)

Scripts referenced below are in the [`scripts/`](scripts/) directory. They are triage tools with known limitations (string literals, macros, block comments can cause false positives) — reasonable approximations, not authoritative audit tools.

---

## 1. C# (optimal) — 87.5%

C# + `unsafe` + `safe` at maturity: enforcement on by default, no longer opt-in. The horizon.

**Finding safety boundaries:**

```bash
$ rg -w "safe" --type cs src/libraries       # safety boundary signatures
$ rg -w "unsafe" --type cs src/libraries     # unsafe signatures + blocks
$ rg "unsafe\s*\{" --type cs src/libraries   # unsafe blocks only
```

Pivot the keyword, narrow to blocks. Both sides of the ledger — safety boundaries and unsafe code — are directly discoverable. Together: the complete safety-critical picture. No other language in this comparison achieves both.

**Score breakdown:** Full marks on discovery (safety boundaries + unsafe declarations + safe-as-default). Full marks on auditing design (viral caller contract + constrained inner unsafe + enforcement on by default). One demerit: `unsafe` still mixes methods and blocks (backward compatibility cost).

---

## 2. Rust — 77.5%

**Finding safety boundaries** — Rust has no explicit marker for caller-safe functions that contain `unsafe` blocks. Discovering them requires parsing function bodies. See [`scripts/find-rust-trust-boundaries.sh`](scripts/find-rust-trust-boundaries.sh) — an 80-line awk script:

```bash
$ ./scripts/find-rust-trust-boundaries.sh library | head -12
```

```text
file    line    function        signature
alloc/src/alloc.rs      205     alloc_impl_runtime      fn alloc_impl_runtime(...)
alloc/src/alloc.rs      219     deallocate_impl_runtime fn deallocate_impl_runtime(...)
alloc/src/boxed.rs      284     new     pub fn new(x: T) -> Self {
alloc/src/boxed.rs      311     new_uninit      pub fn new_uninit() -> Box<mem::MaybeUninit<T>> {
...
```

Not directly discoverable — requires substantial effort to approximate.

**Finding unsafe functions** — straightforward:

```bash
$ rg "unsafe fn" --type rust library | head -10
```

```text
library/panic_unwind/src/miri.rs
15:pub(crate) unsafe fn panic(payload: Box<dyn Any + Send>) -> u32 {

library/panic_unwind/src/emcc.rs
67:pub(crate) unsafe fn cleanup(ptr: *mut u8) -> Box<dyn Any + Send> {
98:pub(crate) unsafe fn panic(data: Box<dyn Any + Send>) -> u32 {
...
```

Directly discoverable. The `unsafe fn` compound string does the heavy lifting on disambiguation. An agent can go further with `rg "unsafe fn" --type rust -A 20` to capture the signature and body context in a single pass.

**Finding unsafe blocks:**

```bash
$ rg -Un "unsafe\s*\{" library --type rust | head -10
```

Directly discoverable.

**Design tradeoff.** Rust deliberately chose fine-grained `unsafe` block scoping. [RFC 2585](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html) separated "unsafe to call" from "body does unsafe things." The Rust Book advises keeping `unsafe` blocks small; the Rustonomicon notes that standard library safe abstractions over unsafe code "have generally been rigorously manually checked." The guidance is clear — unsafe code is where the review budget goes — but the safety boundary function that wraps it remains unnamed and undiscoverable by grep.

Rust leads today because its borrow checker and safety model have always been default-on. Narrow `unsafe` blocks have a real payoff for grep-based auditing: the smaller the block, the more context a single grep with `-A N` captures. No demerits.

---

## 3. C# + `unsafe` + `safe` — 72.5%

The proposed design: `safe` keyword + `unsafe` as caller contract + interior `unsafe` as implementation-only + safe-as-default. Opt-in, so no default-on credit yet.

**Finding safety boundaries:**

```bash
$ rg -w "safe" --type cs src/libraries       # safety boundary signatures
$ rg -w "unsafe" --type cs src/libraries     # unsafe signatures + blocks
$ rg "unsafe\s*\{" --type cs src/libraries   # unsafe blocks only
```

Directly discoverable. Discoverable, with one demerit: `unsafe` still mixes methods and blocks (shared by all C# variants).

**Design tradeoff.** The gap from this design (72.5%) to C# optimal (87.5%) is model maturity — the same path Rust has already completed. Adding `safe` closes most of the gap with Rust; the rest is default-on enforcement.

---

## 4. C# + `unsafe` keyword (no `safe`) — 50.0%

The [`unsafe` keyword proposal](https://github.com/dotnet/csharplang/pull/10058): `unsafe` on a method means caller-unsafe. Safe-as-default, caller contract and implementation-only scoping. Opt-in. No safety boundary marker.

**Finding safety boundaries** — not directly discoverable. Requires a script: [`scripts/find-csharp-trust-boundaries.sh`](scripts/find-csharp-trust-boundaries.sh).

**Finding unsafe code** — `rg "unsafe" --type cs`. Discoverable but `unsafe` mixes methods and blocks.

**Design tradeoff.** This proposal gets the structural improvements right (caller contract, implementation-only scoping) but doesn't mark the safety boundary — the most critical audit target remains invisible.

---

## 5. Swift — 50.0%

**Finding safety boundaries** — Swift has the same structural challenge as Rust. See [`scripts/find-swift-trust-boundaries.sh`](scripts/find-swift-trust-boundaries.sh):

```bash
$ ./scripts/find-swift-trust-boundaries.sh stdlib | head -8
```

Not directly discoverable — requires a script.

**Finding unsafe declarations** — `@unsafe` is an attribute, typically on a separate line:

```bash
$ rg "@unsafe" --type swift stdlib -A 1 | head -10
```

```text
stdlib/public/Synchronization/Mutex/Mutex.swift
177:  @unsafe
178-  public borrowing func unsafeLock() {
--
185:  @unsafe
186-  public borrowing func unsafeTryLock() -> Bool {
```

Discoverable with `-A 1` for useful output.

**Finding unsafe expressions** — Swift uses `unsafe` as an expression prefix:

```bash
$ rg "[[:space:](=]unsafe [[:alpha:]]" --type swift Sources | head -8
```

Each `unsafe` expression is a single operation — tighter scoping than Rust's `unsafe {}` blocks.

**Swift's internal unsafe language.** Beyond `@unsafe` and `unsafe expr`, Swift has internal-only constructs like `unsafeAddress` and `unsafeMutableAddress` — accessors that return raw pointers from subscripts with no bounds checking. They look like identifiers, not safety keywords, adding auditing noise.

**Design tradeoff.** Swift chose `@unsafe` as a declaration attribute and `unsafe` as an expression prefix for composability. [SE-0458](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md) optimizes for safety expressiveness. The [memory safety vision](https://github.com/swiftlang/swift-evolution/blob/main/visions/memory-safety.md) describes an "auditing tool" that can identify all unsafe opt-outs — but the emphasis is on compiler-assisted audit rather than self-describing source. Trust boundaries remain dependent on tooling.

Swift's strict safety is opt-in (`-strict-memory-safety`) and uses warnings rather than errors — a demerit for source-distributed non-enforcement.

**Case study: swift-collections.** [apple/swift-collections](https://github.com/apple/swift-collections) demonstrates the gap:

```text
@unsafe declarations:                24 hits across 7 files
unsafe expressions:                 158 hits across 38 files
Safety boundary functions:          118 functions (via 110-line awk script)
```

The 118 safety boundary functions — the most important audit targets — are invisible to grep. Even with the compiler's `-strict-memory-safety` mode (12,526 warnings across 319 files), the output identifies unsafe *usage sites*, not safety boundaries. Neither the compiler audit tool nor grep answers the safety boundary question. See [notable-patterns.md](notable-patterns.md#swift-appleswift-collections) for concrete examples of what these functions look like inside.

---

## 6. D — 40.0%

D independently arrived at the three-layer architecture with `@safe`, `@trusted`, and `@system`. It is the only shipping language with explicit safety boundaries.

**Finding safety boundaries** — a single ripgrep command:

```bash
$ rg "@trusted" --type d
```

```text
std/random.d
1806:@property uint unpredictableSeed() @trusted nothrow @nogc
1864:        @property UIntType unpredictableSeed() @nogc nothrow @trusted
3229:    this(this) pure nothrow @nogc @trusted
...
```

Directly discoverable. One command, files, columns, function signatures.

**Finding unsafe code** — `@system` functions are implicit (undecorated), so grep alone cannot find them. The largest category of code is invisible to grep — a significant gap.

**Design tradeoff.** D's three-layer model is the right architecture, but its unsafe-first default (`@system` is implicit) limits the model's reach. Safety boundaries (`@trusted`) only exist at the `@safe`-to-`@system` edge. `@system` code calls other `@system` code directly with no safety boundary in the graph. The model provides guarantees for the safe subset rather than being a whole-system property.

D's `@trusted` does not present safe roots for all unsafe code like it does in safe-first languages. In C# or Rust, all unsafe code must be rooted by a safety boundary function or it is dead code. In D, `@system` code can be called by other `@system` code without ever passing through a `@trusted` boundary.

The D community's guidance confirms that `@trusted` is where the review budget goes — but this guidance only applies within the safe subset.

---

## 7. C# (current) — 35.0%

**Finding safety boundaries** — C# has no clean model for this. See [`scripts/find-csharp-trust-boundaries.sh`](scripts/find-csharp-trust-boundaries.sh).

**Finding unsafe code** — C# supports `unsafe` on methods, blocks, classes, and fields. A single directory shows the problem:

```bash
$ rg "unsafe" --type cs src/libraries/.../Microsoft/Win32/SafeHandles
```

```text
SafeFileHandle.Windows.cs
146:        private static unsafe SafeFileHandle CreateFile(string fullPath, ...)
280:        internal unsafe FileOptions GetFileOptions()

SafeFileHandle.OverlappedValueTaskSource.Windows.cs
47:        internal sealed unsafe class OverlappedValueTaskSource : IValueTaskSource<int>, ...

SafeFileHandle.Unix.cs
201:            unsafe
```

The auditor sees `unsafe` on method signatures, on a class declaration, and as a standalone block — all with the same keyword. No syntactic way to determine the safety role without reading context.

**The `unsafe class` problem** — members of an `unsafe class` are implicitly unsafe without any per-method marker. They are invisible to grep — a false negative.

Five demerits: `unsafe` mixes methods/blocks/types, `unsafe class` implicit members, audit-based model with binary distribution (×3).

---

## 8. C# + `RequiresUnsafe` — 35.0%

The [`RequiresUnsafe` proposal](https://github.com/dotnet/csharplang/blob/main/proposals/unsafe-evolution.md): `[RequiresUnsafe]` attribute for caller-unsafe. Safe-as-default. Opt-in.

**Finding safety boundaries** — not directly discoverable. No safety boundary marker exists.

**Finding unsafe code** — `rg "RequiresUnsafe"` returns both `[RequiresUnsafe]` (caller-unsafe) and `[RequiresUnsafe(false)]` (safety boundary) in the same result set. The auditor must use exclusion logic to separate them.

Four demerits: `unsafe` mixes methods/blocks/types, `unsafe class` implicit members, `RequiresUnsafe` mixes true/false, and duplicate marking (methods carry both `unsafe` and `[RequiresUnsafe]`). The `RequiresUnsafe` ties C# current (35.0%) — it adds real structural improvements but the attribute form introduces enough grep noise to offset those gains.

---

## The Canonical Audit Workflow

The safety audit has two activities:

1. **Safety-boundary-directed review** — discover safety boundaries, trace into the unsafe code they attest. This follows the audit graph from roots to leaves.
2. **Undirected unsafe review** — independently inventory all unsafe code, looking for patterns, known-bad operations, or code that should have been wrapped in a safety boundary but wasn't.

D handles activity 1 within the `@safe` subset: `rg "@trusted"` finds the boundaries. But D can't do activity 2 because `@system` is implicit.

Rust handles activity 2 perfectly: `rg "unsafe fn"` inventories all unsafe code. But Rust can't do activity 1 because safety boundaries have no marker.

C# (optimal) handles both:

```bash
$ rg -w "safe" --type cs                     # Activity 1: find safety boundaries
$ rg -w "unsafe" --type cs                   # Activity 2: find unsafe code
$ rg "unsafe\s*\{" --type cs                 # Activity 2b: unsafe blocks only
```

The first command finds every safety boundary — exhaustive, because safe is the default. The second finds every unsafe declaration and block. The third narrows to blocks for targeted review. No other language in this comparison achieves both activities.

---

## Summary

| Language | Score | Key strength | Key gap |
|----------|-------|-------------|---------|
| C# (optimal) | **87.5%** | Both safety boundaries and unsafe are discoverable | `unsafe` mixes methods/blocks |
| Rust | **77.5%** | Default-on enforcement, clean unsafe discovery | No safety boundary marker |
| C# + `unsafe` + `safe` | **72.5%** | Both discoverable, safe-as-default | Opt-in (not yet default-on) |
| C# + `unsafe` keyword | **50.0%** | Caller contract, safe-as-default | No safety boundary marker |
| Swift | **50.0%** | Fine-grained unsafe expressions | No safety boundary marker, opt-in warnings |
| D | **40.0%** | Only language with explicit safety boundaries | Unsafe-first default, `@system` invisible |
| C# (current) | **35.0%** | Safe-as-default, enforcement on | Ambiguous `unsafe`, no caller contract |
| C# + `RequiresUnsafe` | **35.0%** | Caller contract, safe-as-default | Attribute noise, no safety boundary marker |

See [scoring-methodology.md](scoring-methodology.md) for the full methodology and scoring detail.
