# The Missing Marker: Trust Boundary Discoverability in Memory-Safe Languages

> This paper proposes adding a marker for trust boundary methods, adding a `trusted` keyword to C#. This proposal will resultin in the only memory safety model that makes both trust boundaries and unsafe code grep-discoverable. There is no established metric for comparing safety model discoverability across languages — the absence of one may explain why the trust boundary gap has persisted. This paper proposes a scoring model based on grep difficulty, auditing design, and observable workflow problems to compare D, Rust, Swift, and three C# alternatives. The optimal C# design scores 88% at maturity — where no other language exceeds 78%.

I've been reading the excellent design notes from C#, D, Rust, and Swift design communities. Most of the focus is on how functions and interior blocks of code are decorated to highlight unsafety. The unsafe spotlight is clearly important but doesn't deliver confidence where it is most needed: the transition from unsafe to safe code — the trust boundary. Our threat-modeling tradition emphasizes focus on that boundary above all else. Trusted boundary functions (TBF) should attract the most scrutiny with the strongest gates and marquee lights around them, however, the designs I've read leave them bare. It is reasonable to conclude that there is a gap between our threat modeling tradition and language design. We're in the middle of designing C# memory safety v2. It's the moment to bridge this divide. We can make C# a strong threat modeling tool.

The key problem is that most of the language designs accept the lack of an unsafe marker as an indication that unsafe warnings/errors should be suppressed. We cannot know if the marker was deleted by accident or as a meaningful removal. In effect, these designs are storing a ternary value with a single bit. Current C# stores this information in zero bits, which is even worse. We have the opportunity to resolve this critical language design point with new versions of C#.

This gap is not obvious from the surface. Safe/unsafe reads as a clean dichotomy, and "mark the dangerous stuff" is the natural design instinct — every language has followed it. The non-obvious truth is that the _transition point_ matters more than the dangerous code itself. Rust's RFC 2585, Swift's SE-0458, and our own proposals all engage with the trust boundary problem without closing it. The grep test in this paper makes the gap visible: `rg "unsafe"` gives you an inventory of dangerous code, but no way to work upward to find an attestation of safety. Trust boundaries are the roots of the audit graph — and they are invisible in every language except D (with caveats discussed later).

Let's look at our vision for memory safety v2:

> Large Language Models (LLMs) add a new dimension to memory safety. Safe code is well-suited to generative AI. It is easier to understand, review, and modify with confidence. We recommend that developers configure their AI systems and build tools to permit only safe code. In the new AI paradigm, the compiler and analyzers become the final authority on safety.

Source: https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/memory-safety.md

That's a compelling vision. Our ambition is that agents generate most C# code going forward and that they can self-drive migration to our new memory safety model over the next several years. The question is what "final authority on safety" means. It is a heavy lift in the text. It's describing a model that is lossless in intent and produces errors where the code is found to be wrong or subject to ambiguity. Removing `unsafe` (establishing the aforementioned absence) is an example of dangerous ambiguity. Lossy designs are an invitation for Jia Tan ([xz fame](https://en.wikipedia.org/wiki/XZ_Utils_backdoor)) to make a  visit.

C#/.NET is primarily binary-distributed — consumers receive compiled assemblies, not source code. Compiler warnings during the library author's build are invisible downstream. Errors are the only safety signal that reliably crosses the binary boundary. Rust and Swift are primarily source-distributed; their consumers compile from source and see warnings themselves. This asymmetry raises the bar for C#: anything that is "just a warning" is effectively invisible to the majority of consumers. We need a safety model built on errors, not warnings.

AI models will get better. Their capacity to fundamentally self-drive security work is a function of the language not AI innovation. Handcuffing agents with stringent language requirements will objectively produce better and more trustworthy results.

My overall take on a memory safety system:

- The value is enforcement and auditing, both automatic and manual. It is inherently a collaboration between a deterministic tool (compiler or analyzer) and a semantic mind (human or agent).
- It should increase confidence while reducing (or at least focusing) manual effort, by simplifying workflows and limiting the search space.
- Agent-assisted code migration and maintenance is a core part of our vision. We need to cater to that with a specific plan on how to durably deliver on it.
- The success (and cost) of the system depends on the degree to which it relies on inference in the semantic domain. High inference means low clarity means low confidence means high cost.
- We can easily test the cost of inference using grep as a proxy.

We've primarily been looking at Rust and Swift. I think we can also learn from D. D's three-layer architecture — with explicit trust boundaries — is the right model. We're in the enviable position where we can pick from the best ideas of the last couple decades. One can argue that C# established this modern domain, of safe languages with first-class memory access and FFI. The spoiler is that the optimal solution is well within reach, with just a few tweaks to our current plan. C# can establish a strong memory safety model for the 2030s, the decade of agents.

Relevant design specs:

- C#:
  - [Memory Safety in .NET](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/memory-safety.md) — project overview and goals
  - [Annotating members as `unsafe`](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md) — the caller-unsafe design
  - [Unsafe evolution](https://github.com/dotnet/csharplang/blob/main/proposals/unsafe-evolution.md) — C# language proposal and `RequiresUnsafe` attribute
  - [Alternative syntax for caller-unsafe](https://github.com/dotnet/csharplang/blob/main/meetings/working-groups/unsafe-evolution/unsafe-alternative-syntax.md) — attribute vs keyword tradeoffs
  - [Proposed modifications to unsafe spec](https://github.com/dotnet/csharplang/pull/10058) — follow-up proposing `unsafe`/`safe` keywords (open PR)
- D: [Memory-Safe D](https://dlang.org/spec/memory-safe-d.html)
- Rust: [RFC 2585 — unsafe block in unsafe fn](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html)
- Swift: [SE-0458 — Strict Memory Safety](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md)

## The Three-Layer Safety Model

A three-layer safety model — safe, trust boundary, unsafe — is a recurring pattern in platform design. .NET pioneered it with Silverlight. D independently arrived at the same architecture. Both validate the approach.

### The Silverlight Security Transparency Precedent

.NET already solved this problem once. The [Silverlight security transparency model](https://learn.microsoft.com/previous-versions/dotnet/framework/code-access-security/security-transparent-code) had three layers:

- Transparent
- Safe Critical
- Security Critical

"Transparent" code could only call other transparent or "safe critical" code. "Safe critical" and "security critical" code had unencumbered access to privileged operations — the difference was caller contract, not capability. "Safe critical" code was the trust boundary: it could be called by transparent code and took on the obligation of validating inputs and presenting a safe surface. The model made auditing straightforward with clear markings throughout.

You can imagine asking an agent to review all "safe critical" methods. It is trivial for the agent to find them. This is a definitional characteristic of a well-designed safety model.

The Silverlight model was abandoned when Silverlight was abandoned — not because the model was flawed. The design was sound. The lesson: a three-layer system with explicit trust boundaries is a validated .NET pattern. We should reclaim it.

### D's Three-Layer Model

D independently arrived at the same three-layer architecture.

> D is a system programming language. D has a memory-safe subset.

Source: [D Tour: Memory](https://tour.dlang.org/tour/en/basics/memory)

D has three safety tiers:

- `@safe`
- `@trusted`
- `@system`

That's a pyramid. Reasoning from the bottom:

- `@system` functions have full system access and are considered unsafe. Undecorated functions are implicitly `@system`.
- `@trusted` functions attest to presenting a safe facade for safe callers, while using `@system` functions for their implementation.
- `@safe` functions operate within the safe compiler-enforced subset and may only call `@safe` and `@trusted` functions.

The mapping to Silverlight is direct:

| D | Silverlight | Role |
|---|-------------|------|
| `@safe` | Transparent | Safe subset, restricted callees |
| `@trusted` | Safe Critical | Trust boundary, attests safety to callers; unrestricted, unsafe operations |
| `@system` | Security Critical | Unrestricted, unsafe operations |

All functions must be sound at all three layers. `@system` code must be correct given the preconditions that a `@trusted` caller guarantees — "safe" in the sense that a naive caller in `@safe` land cannot break memory safety invariants. Sound `@system` and `@trusted` code is the responsibility of the developer, not the compiler. That's true of Rust too.

D is the only shipping language with explicit trust boundaries, and the three-layer architecture is compelling. However, D's unsafe-first default (`@system` is implicit) limits the model's reach. In Silverlight, every method was classified — Transparent, SafeCritical, or SecurityCritical — with Transparent as the default. D's model is closer to a Silverlight where SecurityCritical was implicit and the transparency model only applied to code that explicitly opted in. Trust boundaries (`@trusted`) only exist at the boundary where `@safe` code needs to cross into `@system` code. `@system` code can call other `@system` code directly, with no trust boundary in the graph. The model provides guarantees for the safe subset rather than being a whole-system property.

#### Auditing workflow

The D community's guidance confirms that `@trusted` is where the review budget goes. [Steven Schveighoffer describes the workflow](https://dlang.org/blog/2016/09/28/how-to-write-trusted-code-in-d/): "`@trusted` code is never mechanically checked for safety, so every line must be reviewed for correctness. For this reason, it's always advisable to keep the code that is `@trusted` as small as possible." Ate Eskola [further emphasizes this idea](https://dlang.org/blog/2023/01/05/memory-safety-in-a-systems-programming-language-part-3/): "`@trusted` functions...need to be just as carefully reviewed, if not more so, as `@system` functions" and "it's many times more important than usual to keep `@system` and `@trusted` functions small and simple to review." The principle is clear: `@safe` code doesn't need manual review — the compiler verifies it. The audit focus narrows to `@trusted` and `@system`.

D developers can rely on grep to find `@trusted` functions — a genuine advantage no other shipping language offers. But as noted above, the audit workflow is confined to the safe subset.

## Proposed Design for C\#

C# has the opposite default as D: safe is implicit, unsafe is marked. This difference matters more than it appears. In a safe-first language, all unsafe code must be rooted by trust boundary functions or it is dead code — no safe caller can reach it. Trust boundaries become the exhaustive roots of the audit graph, not just entry points from a safe subset. The decorative approach for the middle layer is what matters most. This paper proposes a `trusted` keyword as that marker. The primary point is that we need an explicit trust boundary marker; the specific form of the marker is secondary.

### The `trusted` keyword

| Layer | C# syntax | Meaning |
|-------|-----------|---------|
| Safe | (unmarked) | No unsafe operations, can only call safe and `trusted` methods |
| Trust boundary | `trusted` | Contains `unsafe` blocks, attests safety to callers |
| Unsafe | `unsafe` | Caller-unsafe, obligations must be discharged by caller |

The [caller-unsafe design](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md) recognizes trust boundary functions but does not mark them. Its `Caller2` example illustrates the gap:

```csharp
void Caller2()
{
    unsafe
    {
        M();
    }
}
unsafe void M() { }
```

The design notes: "by presenting a safe API around an unsafe call, [the programmer is] asserting that all safety concerns of `M()` have been addressed." That assertion is the trust boundary — but `Caller2` has no marker on its signature. It is indistinguishable via its signature from a method that does not touch unsafe code.

With `trusted`, the three roles become visible:

```csharp
trusted void Caller2()
{
    unsafe
    {
        M();
    }
}

unsafe void M() { }

void SafeCaller()
{
    Caller2();  // OK — trusted is callable from safe code
    // M();     // Error — unsafe requires unsafe context
}
```

`Caller2` is now grep-discoverable as a trust boundary. The three roles — safe (`SafeCaller`), trust boundary (`Caller2`), and unsafe (`M`) — are each unambiguously identifiable from their signatures alone.

All unmarked methods are implicitly safe. The three-layer model is exhaustive and non-overlapping — every path from safe to unsafe passes through `trusted` — which is the formal property that makes the grep test work.

**Design details:** As a contextual keyword modifier, `trusted` occupies the same syntactic position as `unsafe` and inherits its design answers for interfaces, virtual methods, async methods, and delegates. If `unsafe` is valid on a method signature, `trusted` is valid there too — they are complementary markers in the same design space. Methods inside an `unsafe class` that present a safe surface must use `trusted` explicitly — eliminating the "implicit unsafe type" audit gap. Interior lambdas and local functions are covered by the enclosing `trusted` method's attestation, matching D's `@trusted` model.

**Migration and workflow:** Like all the proposals in this space, opting in is a breaking change that requires work to compile without errors — the difference is degree, not kind.

1. Migration tooling scans for methods with interior `unsafe` blocks and marks them `unsafe` conservatively.
2. Developers triage each method: mark as `trusted` (attests safety to callers) or leave as `unsafe` (propagates to callers). Methods can be temporarily marked as `trusted` with accompanying comments that describe that auditing is needed.
3. The codebase compiles cleanly — every trust boundary is explicitly marked, enforced by errors.
4. Binaries built this way and distributed via NuGet are marked as "Memory Safety v2" giving consumers a new signal on security posture.

Ongoing, it is easy to track transitions between `unsafe` and `trusted` with git — less so when one side of the diff is an empty string. AI agents can be asked to periodically review the safety obligations of all `trusted` methods, relying on source code and git history as inputs.

This approach is lossless and grep-friendly. It preserves the three-layer model while improving on D: trust boundaries are exhaustive (safe-first default) and both `trusted` and `unsafe` are grep-discoverable (D's `@system` is not). Safe code requires zero safety-model scrutiny — the compiler has verified it by construction.

### The end state

Zooming out, we see that the performance substrate of the product becomes `ref`, `trusted`, and `unsafe`.

- `ref` — safe pointer. Compiler-verified. Zero-copy access with lifetime tracking. No audit needed.
- `trusted` — safe-to-call wrapper around unsafe code. Human-verified. The audit target.
- `unsafe` — raw operations. Human-verified. The implementation detail inside `trusted`.

The grep-friendly audit surface is `trusted` and `unsafe`. The performance surface migrates (as is already the case) to `ref`, in the safe subset.

In fact, with a fully-specified model, there is no end of agent prompts that users can ask about a codebase and expect an accurate and efficient answer. The fully-specified model enables a natural and cheap query engine. The key is discoverability on one hand and inference cost on the other.

Here are some prompts to consider:

- "Describe the primary concerns of the trust boundary within System.IO classes."
- "Describe the split between performance optimization and interop of unsafe code in System.Collections."
- "Which trusted or unsafe methods would be better written as ref?"
- "List all trusted methods in System.Security that were modified in the last 6 months."
- "What is the ratio of trusted to unsafe methods in System.Runtime.InteropServices?"
- "What are the median and max body sizes of trusted and unsafe methods in that namespace?"
- "For this PR, review every trusted method that was added or modified."

These prompts are currently expensive in C# — and in D, Rust, and Swift. Testing the first prompt against dotnet/runtime required ~14 grep commands and significant manual inference just to distinguish trust boundary functions from fully-unsafe methods. The second required ~8 commands plus semantic reasoning to categorize results by purpose. The third is effectively unbounded without a starting set of trust boundaries to evaluate. With `trusted`, prompt 1 becomes a single `rg "trusted" --type cs src/libraries/System.IO*` command. The model reads the bodies of the results and answers directly. We can make these prompts cheap.

## The case against `safe` for Trust Boundary Functions

My initial thinking -- in C# parlance -- was to mark TBFs `safe` since that's the opposite of `unsafe` and the intent is to provide a safe wrapper. The strongest argument for `safe` is that it's the natural antonym — C# developers expect it as the counterpart to `unsafe`, and Rust's RFC 3484 introduced `safe` as a contextual keyword in extern blocks for exactly this pairing.

However, these functions are in no way the opposite of unsafe. They contain and rely on unsafe code with no help from the compiler to offer a safe facade.

TBFs handle unsafe currency and must do so soundly. They only differ in that they have the special character that they are considered safe to call by developers who typically have no basis or intent of applying safety scrutiny. TBFs are unsafe code that do double duty. It's that single bit and what it represents again.

Another view is that the compiler can make a single statement about `unsafe` code: "I've got no earthly idea what is going on!". And so the marker fits. The same statement equally applies to TBFs. The concept of `safe` should only be applied when the compiler can make a guarantee: "I know exactly what is going on and it 100% aligns with my safety model."

I was thinking about terms. The obvious terms are:

- caller-unsafe
- caller-safe

These terms are confusingly asymmetric. They can be expanded to prose this way:

- caller-unsafe: "can only be called by unsafe callers"
- caller-safe: "can (specifically) be called by safe callers (among others)" or put more directly and truthfully "the only unsafe methods that safe callers can call"

This tells us two things:

- TBFs are unsafe
- safe code can call a class of unsafe methods

`safe` is a compiler attestation while `trusted` is a human or agent attestation. Don't confuse the two as they are not similar.

## Analysis of Current Proposals

A [follow-up PR](https://github.com/dotnet/csharplang/pull/10058) proposes going back to `unsafe`/`safe` keywords, motivated by practical experience annotating dotnet/runtime: 97% of methods with pointers should be `RequiresUnsafe`, making the attribute approach high-churn for little benefit. The PR also introduces `safe` for extern methods that wrap safe native code (e.g., a P/Invoke into a safe Rust function). That PR's goals align with this paper:

> 1) clear, simple rules on which methods are caller unsafe vs. use unsafe
> 2) users annotate their code based on the rules of unsafev2, not unsafev1
> 3) annotation is easily auditable, meaning we can see whether a given project has aligned their code with unsafev2
> 4) support for multitargeting with unsafev1-only TFMs
>
> This feature will introduce compilation errors in existing unsafe code when opted into. High-confidence AI-assisted automation of the migration process flow is a part of the feature design.

The PR uses `safe` as the keyword. This paper argues for `trusted` instead: these methods are not safe in the compiler-verified sense — they are unsafe code that attests safety to callers. `trusted` avoids that confusion and aligns with D's `@trusted` and our Silverlight "safe critical" precedent. The same applies to `safe` for `extern` methods — the C# compiler cannot verify what happens across the FFI boundary (with a high emphasis on _Foreign_), and the implementation behind that boundary can change without the C# declaration changing. `trusted` is the right marker for a human claim about code the compiler cannot see. `[RequiresUnsafe(false)]` would be model-equivalent but is a double negative — it negates a property rather than asserting one. `rg "trusted"` reads as intent; `rg "RequiresUnsafe(false)"` reads as an implementation detail.

The [unsafe evolution proposal](https://github.com/dotnet/csharplang/blob/main/proposals/unsafe-evolution.md) introduces `RequiresUnsafe` for caller-unsafe methods but similarly leaves trust boundary functions unmarked. The [alternative syntax proposal](https://github.com/dotnet/csharplang/blob/main/meetings/working-groups/unsafe-evolution/unsafe-alternative-syntax.md) explicitly notes that `[RequiresUnsafe]` "does not imply that the member is an unsafe context" — the author scopes `unsafe` blocks as they see fit, but the enclosing method gets no marker.

### `[RequiresUnsafe(bool)]` is a poor substitute for `trusted`

The `RequiresUnsafe` attribute in the current language proposal marks which color of methods can call the target method. It's a compound term that harbors a double-negative. That's not great. We know that humans have low comprehension for double negatives. The same is true for models. We're back to high inference.

The tokenizer representation of these terms is not equivalent: `trusted` and `unsafe` are each single tokens while `RequiresUnsafeAttribute(false)` spans seven. Like grep, the tokenizer is a proxy for representational complexity — and like grep, it favors simple, direct terms over compound double-negative ones. This matters most during direct code review — in a PR, editor, or context window — where the reviewer performs both discovery and safety analysis in one pass. Compound double-negative terms consume cognitive budget on disambiguation rather than the safety question itself. See [Appendix: Tokenizer Comparison](#appendix-tokenizer-comparison) for details.

## Measuring Discoverability: The Grep Test

Memory safety across all languages inherently relies on human and agent auditing. The compiler verifies safe code by construction. But `trusted` and `unsafe` code cannot be verified by the compiler. They require semantic review: a human or agent must confirm that the unsafe operations are correctly bounded and that the trust boundary's safety attestation is valid. The audit value of methods is therefore inherently asymmetric. Safe code doesn't need review. Trust boundary functions need the most review. Unsafe functions need review too, but the trust boundary is where the claim is made.

Auditing can be thought of as a subset of threat modeling. The search space of memory safety auditing is the divide between defined and undefined behavior — the same search space as vulnerabilities. It's two different views — one defensive, the other offensive — on the same activity. Threat modeling asks "where can an attacker violate assumptions? Memory safety auditing asks "where can code violate safety invariants?" Trust boundary functions are where someone claims that undefined behavior has been correctly bounded. If that claim is wrong, the result is both a bug and a potential vulnerability.

There is a structural reason trust boundaries matter more than unsafe declarations for discovery: trust boundaries are the _roots of the audit graph_. A trust boundary function contains unsafe callsites in its body — the unsafe callees are the leaves. If you can find the roots, you can find the leaves by reading the body or grepping within the file. But if you can only find the leaves (unsafe functions and blocks), you cannot easily work upward to find which enclosing function attested their safety.

We can use grep as our proxy for sound language design. It matches how I've used [`jq` as the arbiter of sound schema design](https://github.com/dotnet/designs/blob/main/accepted/2025/cve-schema/cve_schema.md#design-philosophy). If a safety-relevant question can't be answered by grep, the language design has failed at self-description.

### Why grep?

Code review — the primary context where safety-critical code is evaluated — operates at the grep level. When reviewing a pull request in GitHub or any diff view, there is no sophisticated language-specific tooling. The reviewer's tools are their eyes and Ctrl/CMD-F. An agent is more likely to use grep. Source code should stand on its own for safety review.

The analysis below uses [ripgrep](https://github.com/BurntSushi/ripgrep) and a set of awk-based scripts for the more complex queries. The scripts are triage tools with known limitations (string literals, macros, block comments can cause false positives). They are not authoritative audit tools but are reasonable approximations. They are also sadly presented as SOTA. All scripts are in the [`scripts/`](scripts/) directory.

Source repos used:

- D: [dlang/phobos](https://github.com/dlang/phobos)
- Rust: [rust-lang/rust](https://github.com/rust-lang/rust) (`library/`)
- Swift: [swiftlang/swift](https://github.com/swiftlang/swift) (`stdlib/`)
- C#: [dotnet/runtime](https://github.com/dotnet/runtime) (`src/libraries/`)

### D Language

Source: [dlang/phobos](https://github.com/dlang/phobos)

**Finding trust boundaries** — a single ripgrep command:

```bash
$ rg "@trusted" --type d
```

```text
phobos/sys/traits.d
5860:            struct S { void foo() @trusted { auto v = cast() local; } }

std/sumtype.d
323:    @trusted

std/random.d
1806:@property uint unpredictableSeed() @trusted nothrow @nogc
1864:        @property UIntType unpredictableSeed() @nogc nothrow @trusted
3229:    this(this) pure nothrow @nogc @trusted
3242:    this(size_t numChoices) pure nothrow @nogc @trusted
3257:    ~this() pure nothrow @nogc @trusted
3265:    bool opIndex(size_t index) const pure nothrow @nogc @trusted
...
```

Files, columns, and function signatures. One command, directly discoverable. However, as discussed above, these trust boundaries only cover the `@safe`-to-`@system` edge.

**Finding unsafe code** — `@system` functions are implicit (undecorated), so grep alone cannot find them. This is a significant gap in D's discoverability model — the largest category of code (default `@system`) is invisible to grep.

### Rust

Source: [rust-lang/rust](https://github.com/rust-lang/rust) (`library/`)

**Finding trust boundaries** — Rust has no explicit marker for caller-safe functions that contain `unsafe` blocks. Discovering them requires parsing function bodies. See [`scripts/find-rust-trust-boundaries.sh`](scripts/find-rust-trust-boundaries.sh) — an 80-line awk script that walks brace depth to approximate this:

```bash
$ ./scripts/find-rust-trust-boundaries.sh library | head -12
```

```text
file    line    function        signature
alloc/src/alloc.rs      205     alloc_impl_runtime      fn alloc_impl_runtime(...)
alloc/src/alloc.rs      219     deallocate_impl_runtime fn deallocate_impl_runtime(...)
alloc/src/boxed.rs      284     new     pub fn new(x: T) -> Self {
alloc/src/boxed.rs      311     new_uninit      pub fn new_uninit() -> Box<mem::MaybeUninit<T>> {
alloc/src/boxed.rs      444     map     pub fn map<U>(this: Self, f: impl FnOnce(T) -> U) -> Box<U> {
alloc/src/boxed.rs      520     new_in  pub fn new_in(x: T, alloc: A) -> Self
alloc/src/boxed.rs      546     try_new_in      pub fn try_new_in(x: T, alloc: A) -> ...
alloc/src/boxed.rs      606     try_new_uninit_in       pub fn try_new_uninit_in(alloc: A) -> ...
alloc/src/boxed.rs      678     try_new_zeroed_in       pub fn try_new_zeroed_in(alloc: A) -> ...
alloc/src/boxed.rs      713     into_boxed_slice        pub fn into_boxed_slice(boxed: Self) -> Box<[T], A> {
```

This requires substantial effort to approximate what D achieves with a single grep. The script has acknowledged limitations (block comments, string literals, macros) and is a decent triage tool.

**Finding unsafe functions** — straightforward:

```bash
$ rg "unsafe fn" --type rust library | head -10
```

```text
library/panic_unwind/src/miri.rs
15:pub(crate) unsafe fn panic(payload: Box<dyn Any + Send>) -> u32 {
22:pub(crate) unsafe fn cleanup(payload_box: *mut u8) -> Box<dyn Any + Send> {

library/panic_unwind/src/emcc.rs
67:pub(crate) unsafe fn cleanup(ptr: *mut u8) -> Box<dyn Any + Send> {
98:pub(crate) unsafe fn panic(data: Box<dyn Any + Send>) -> u32 {
...
```

Directly discoverable. The `unsafe fn` compound string in the signature does the heavy lifting on disambiguation with `unsafe` blocks. An agent can go further with `rg "unsafe fn" --type rust -A 20` to capture the signature and body context in a single pass — typically enough to understand the function's contract and review its safety obligations without opening a file.

**Finding unsafe blocks** — also straightforward:

```bash
$ rg -Un "unsafe\s*\{" library --type rust | head -10
```

```text
library/stdarch/examples/wasm.rs
13:    unsafe {

library/unwind/src/unwinding.rs
54:    let ctx = unsafe { &mut *(ctx as *mut UnwindContext<'_>) };
59:    let ctx = unsafe { &mut *(ctx as *mut UnwindContext<'_>) };
...
```

Directly discoverable.

#### Design tradeoff

Rust deliberately chose fine-grained `unsafe` block scoping. [RFC 2585](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html) separated "unsafe to call" from "body does unsafe things." The Rust Book [advises](https://doc.rust-lang.org/book/ch20-01-unsafe-rust.html) keeping `unsafe` blocks small; the Rustonomicon [notes](https://doc.rust-lang.org/nomicon/safe-unsafe-meaning.html) that standard library safe abstractions over unsafe code "have generally been rigorously manually checked." The guidance is clear — unsafe code is where the review budget goes — but the trust boundary function that wraps it remains unnamed and undiscoverable by grep.

Narrow `unsafe` blocks have a real payoff for grep-based auditing: the smaller the block, the more context a single grep with `-A N` captures.

### Swift

Source: [swiftlang/swift](https://github.com/swiftlang/swift) (`stdlib/`)

**Finding trust boundaries** — Swift has the same structural challenge as Rust. See [`scripts/find-swift-trust-boundaries.sh`](scripts/find-swift-trust-boundaries.sh):

```bash
$ ./scripts/find-swift-trust-boundaries.sh stdlib | head -12
```

```text
file	line	function	signature
public/Concurrency/AsyncStreamBuffer.swift	43	_lockWordCount	func _lockWordCount() -> Int
public/Concurrency/AsyncStreamBuffer.swift	298	init	init(limit: ...)
public/Concurrency/AsyncStreamBuffer.swift	313	lock	private func lock()
public/Concurrency/AsyncStreamBuffer.swift	319	unlock	private func unlock()
public/Concurrency/AsyncStreamBuffer.swift	340	cancel	@Sendable func cancel()
public/Concurrency/AsyncStreamBuffer.swift	353	yield	func yield(_ value: ...) -> ...
public/Concurrency/CFExecutor.swift	18	dlopen_noload	private func dlopen_noload(...)
public/Concurrency/CFExecutor.swift	58	stop	override public func stop()
public/Concurrency/CheckedContinuation.swift	146	init	public init(...)
public/Concurrency/CheckedContinuation.swift	164	resume	public func resume(...)
```

Not directly discoverable — requires the same script-based approach as Rust.

**Finding unsafe declarations** — `@unsafe` is an attribute, which means it appears on a separate line from the function signature:

```bash
$ rg "@unsafe" --type swift stdlib | head -10
```

```text
stdlib/toolchain/CompatibilitySpan/FakeStdlib.swift
36:@unsafe
49:@unsafe

stdlib/public/Synchronization/Mutex/Mutex.swift
177:  @unsafe
185:  @unsafe

stdlib/public/Concurrency/AsyncStreamBuffer.swift
61:    @unsafe struct State {
```

The `@unsafe` attribute is discoverable, but because it typically appears on its own line, it doesn't carry the function signature. Adding one line of context (`-A 1`) is a simple solution to the problem:

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
--
193:  @unsafe
194-  public borrowing func unsafeUnlock() {
```

Perfectly workable after you realize the pattern. The Rust one-line syntax (`unsafe fn`) is more ergonomic — the safety marker and declaration appear on the same line, which matters for grep output readability.

**Finding unsafe expressions** — Swift uses `unsafe` as an expression prefix (not a block). In libraries that have adopted SE-0458 (e.g., [apple/swift-collections](https://github.com/apple/swift-collections)):

```bash
$ rg "[[:space:](=]unsafe [[:alpha:]]" --type swift Sources | head -8
```

```text
ContainersPreview/Types/Box.swift:74:      unsafe UnsafePointer<T>(_pointer)
ContainersPreview/Types/Box.swift:100:    let result = unsafe Inout<T>(unsafeImmortalAddress: _pointer)
ContainersPreview/Types/Box.swift:113:    unsafe Borrow(unsafeAddress: UnsafePointer(_pointer), borrowing: self)
ContainersPreview/Types/Inout.swift:79:      unsafe UnsafePointer<Target>(_pointer)
ContainersPreview/Types/Inout.swift:121:    let pointer = unsafe UnsafeMutablePointer<Wrapped>(
ContainersPreview/Types/Borrow.swift:87:    let pointer = unsafe UnsafePointer<Wrapped>(
```

Each `unsafe` expression is a single operation — tighter scoping than Rust's `unsafe {}` blocks. Discoverable via regex, though the pattern is more complex than Rust's `unsafe {` (which also has a newline edge case).

**Swift's internal unsafe language** — beyond `@unsafe` and `unsafe expr`, Swift has internal-only unsafe constructs that add auditing burden. From [Box.swift](https://github.com/apple/swift-collections/blob/main/Sources/ContainersPreview/Types/Box.swift) in swift-collections:

```swift
public subscript() -> T {
    @_transparent
    unsafeAddress {
      unsafe UnsafePointer<T>(_pointer)
    }

    @_transparent
    unsafeMutableAddress {
      unsafe _pointer
    }
  }
```

`unsafeAddress` and `unsafeMutableAddress` are accessors that return raw pointers from a subscript (Swift's equivalent of a C# indexer) — zero-copy performance but with no bounds checking or lifetime tracking. The caller writes `box[]` with no indication that a raw pointer dereference is happening underneath. It's basically unsafe operator overloading in C# parlance. They look like identifiers, not safety keywords. An auditor grepping for `unsafe` gets noise from them; an auditor not grepping for them misses fundamentally unsafe accessors. C# solves the same zero-copy access problem with `ref` returns, which stay within the safe type system.

#### Design tradeoff

Swift chose `@unsafe` as a declaration attribute and `unsafe` as an expression prefix for composability. [SE-0458](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md) optimizes for safety expressiveness. The [memory safety vision](https://github.com/swiftlang/swift-evolution/blob/main/visions/memory-safety.md) describes an "auditing tool" that can identify all unsafe opt-outs. The emphasis is on compiler-assisted audit — reasonable for a source-distributed language, but it leaves trust boundaries dependent on tooling rather than self-describing in source.

#### Case study: swift-collections

[apple/swift-collections](https://github.com/apple/swift-collections) is one of the first libraries to adopt SE-0458's strict memory safety annotations. It demonstrates both the strengths and gaps of Swift's current model.

**Grep-based discovery:**

```text
@unsafe declarations:                24 hits across 7 files
unsafe expressions:                 158 hits across 38 files
Trust boundary functions:           118 functions (via 110-line awk script)
```

The unsafe side is well-covered: `rg "@unsafe"` finds the 24 declarations, and `rg "[[:space:](=]unsafe [[:alpha:]]"` finds the 158 unsafe expressions. An auditor can inventory every unsafe operation in the library with two grep commands.

But the 118 trust boundary functions — safe functions that contain `unsafe` expressions — are invisible to grep. They require [`scripts/find-swift-trust-boundaries.sh`](scripts/find-swift-trust-boundaries.sh) to approximate. These are the functions where a developer attested that the interior unsafe operations are correctly bounded. They are the most important audit targets, and they are the hardest to find.

**Compiler-assisted audit** (`-strict-memory-safety`):

```text
StrictMemorySafety warnings:      12,526 across 319 files
```

The compiler mode is comprehensive — it finds every expression that uses unsafe constructs but isn't marked with `unsafe`. This is authoritative in a way grep cannot be (no false negatives from templates, type inference, or implicit unsafety). However, the 12,526 warnings identify unsafe *usage sites*, not trust boundaries. The output tells you where unsafe code is used but not which functions attest that the usage is safe. An auditor reviewing these warnings would need to manually determine which enclosing function is the trust boundary — the same inference problem that grep has, just with a more complete starting list.

The compiler audit tool and grep serve the same side of the ledger: inventorying unsafe code. Neither answers the trust boundary question. Finding the 118 trust boundary functions still requires the 110-line awk script — even with the compiler's authoritative unsafe inventory, there is no way to go from leaves to roots without a parser. It is indeed an awkward script.

### C# (Current State)

Source: [dotnet/runtime](https://github.com/dotnet/runtime) (`src/libraries/`)

**Finding trust boundaries** — C# has no clean model for this. See [`scripts/find-csharp-trust-boundaries.sh`](scripts/find-csharp-trust-boundaries.sh):

```bash
$ ./scripts/find-csharp-trust-boundaries.sh src/libraries | head -8
```

```text
file	line	method	signature
Common/src/Interop/Linux/procfs/Interop.ProcFsStat.ParseMapModules.cs	34	ParseMapsModulesCore	...
Common/src/Interop/OSX/Interop.CoreFoundation.CFString.cs	25	CFStringCreateExternalRepresentation	...
Common/src/Interop/Windows/BCrypt/Interop.BCryptEncryptDecrypt.cs	15	BCryptEncrypt	...
Common/src/Interop/Windows/BCrypt/Interop.BCryptEncryptDecrypt.cs	36	BCryptDecrypt	...
Common/src/Interop/Windows/NCrypt/Interop.NCryptDeriveKeyMaterial.cs	19	NCryptDeriveKey	...
Common/src/System/Net/Security/CertificateValidation.Windows.cs	17	BuildChainAndVerifyProperties ...
```

Not directly discoverable.

**Finding unsafe code** — C# supports `unsafe` on methods, blocks, classes, and fields. It falls apart when methods and blocks are both present. A single directory shows the problem:

```bash
$ rg "unsafe" --type cs src/libraries/.../Microsoft/Win32/SafeHandles
```

```text
SafeFileHandle.Windows.cs
146:        private static unsafe SafeFileHandle CreateFile(string fullPath, ...)
197:        private static unsafe void Preallocate(string fullPath, ...)
280:        internal unsafe FileOptions GetFileOptions()
355:        private unsafe FileHandleType GetPipeOrSocketType()
374:        private unsafe FileHandleType GetDiskBasedType()
421:            unsafe long GetFileLengthCore()

SafeFileHandle.OverlappedValueTaskSource.Windows.cs
47:        internal sealed unsafe class OverlappedValueTaskSource : IValueTaskSource<int>, ...

SafeFileHandle.Unix.cs
201:            unsafe
```

The auditor sees `unsafe` on method signatures, on a class declaration, and as a standalone block — all with the same keyword. There is no syntactic way to determine the safety role of a hit without reading the surrounding context.

**The `unsafe class` problem** — members of an `unsafe class` are implicitly unsafe without any per-method marker. See [`scripts/find-csharp-unsafe-methods.sh`](scripts/find-csharp-unsafe-methods.sh):

```bash
$ ./scripts/find-csharp-unsafe-methods.sh src/libraries | grep implicit | head -8
```

```text
Common/src/Interop/FreeBSD/Interop.Process.GetProcInfo.cs	127	size	...	implicit (unsafe type)
Common/src/Interop/Interop.Ldap.cs	195	GetPinnableReference	...	implicit (unsafe type)
Common/src/Interop/OSX/Swift.Runtime/UnsafeBufferPointer.cs	13	UnsafeBufferPointer	...	implicit (unsafe type)
Common/src/Interop/Unix/System.Native/Interop.IPAddress.cs	35	GetHashCode	...	implicit (unsafe type)
Common/src/Interop/Windows/BCrypt/Interop.Blobs.cs	391	Create	...	implicit (unsafe type)
Common/src/System/IO/MemoryMappedFiles/MemoryMappedFileMemoryManager.cs	15	MemoryMappedFileMemoryManager ...	implicit (unsafe type)
Common/src/System/Memory/PointerMemoryManager.cs	11	PointerMemoryManager	...	implicit (unsafe type)
```

These methods are unsafe by inheritance from the containing type — invisible to a simple `rg "unsafe"` search focused on method signatures. This is a significant audit gap.

C# currently offers the least discoverability among the four languages.

## Discoverability and Auditing Scores

We score each language on three dimensions — **discovery** (can you find the code that needs review?), **auditing design** (does the model support an effective workflow?), and **grep target reliability** (can you trust what grep tells you?) — with demerits for observable workflow problems. The scoring methodology is detailed in [Appendix: Scoring Methodology](#appendix-scoring-methodology).

Discovery has three equally-weighted dimensions: trust boundary discovery, unsafe declaration discovery, and safe-as-default. The first two measure grep difficulty. The third captures a structural property: in a safe-first language, trust boundaries are exhaustive roots of the audit graph. In an unsafe-first language like D, they only cover the safe subset. Auditing design includes whether enforcement is on by default — Rust's borrow checker and unsafe propagation run without opt-in, as does C#'s current `unsafe` gate, while new C# proposals, Swift, and D require explicit opt-in. For grep target reliability, enforcement (errors vs warnings) determines whether grep results are authoritative.

| Language | Score | Summary |
|----------|-------|---------|
| C# (optimal) | **87.5%** | C# + `unsafe` + `trusted` at maturity: enforcement on by default, no longer opt-in. The horizon. |
| Rust | **77.5%** | Unsafe declarations (`unsafe fn`) are perfectly discoverable. Safe-as-default, caller contract and implementation-only scoping, enforcement on by default via borrow checker and unsafe propagation. Trust boundaries require an 80-line awk script. No demerits. |
| C# + `unsafe` + `trusted` | **72.5%** | The proposed design: `trusted` keyword + `unsafe` as caller contract + interior `unsafe` as implementation-only + safe-as-default. Opt-in, so no default-on credit. Loses 1.5 discovery points and 1 demerit because `unsafe` methods and blocks share a keyword. |
| C# + `unsafe` keyword | **50.0%** | The [`unsafe` proposal](https://github.com/dotnet/csharplang/pull/10058): `unsafe` on a method means caller-unsafe. Safe-as-default, caller contract and implementation-only scoping. Opt-in. One demerit: `unsafe` still mixes methods and blocks. No trust boundary marker. |
| Swift | **50.0%** | Unsafe declarations (`@unsafe`) require `-A 1` context. Safe-as-default, caller contract and implementation-only scoping, but strict safety is opt-in (`-strict-memory-safety`) — demerit for source-distributed non-enforcement. Trust boundaries require a script. |
| D | **40.0%** | Trust boundaries (`@trusted`) are perfectly discoverable. But unsafe-first default means trust boundaries only cover the `@safe` subset, and `@safe` is opt-in. Unsafe code (`@system`) is implicit and invisible to grep. No demerits. |
| C# (current) | **35.0%** | Unsafe declarations are discoverable but ambiguous. Safe-as-default, enforcement on by default. Trust boundaries require a script. No caller contract or implementation-only scoping. Five demerits: `unsafe` mixes methods/blocks/types, `unsafe class` implicit members, audit-based model with binary distribution (×3). |
| C# + `RequiresUnsafe` | **30.0%** | The [`RequiresUnsafe` proposal](https://github.com/dotnet/csharplang/blob/main/proposals/unsafe-evolution.md): `[RequiresUnsafe]` attribute for caller-unsafe. Safe-as-default. Opt-in. Five demerits: `unsafe` mixes methods/blocks/types, `unsafe class` implicit members, `RequiresUnsafe` mixes true/false, non-standard terminology, and duplicate marking. No trust boundary marker. |

The two active C# proposals — `unsafe` keyword and `[RequiresUnsafe]` — land at 50.0% and 30.0% respectively without `trusted`. Adding `trusted` lifts C# to 72.5% — competitive with Rust — and the `unsafe` vs `RequiresUnsafe` debate is worth 4 points in demerits, driven by observable grep workflow problems rather than syntax preference.

C# (optimal) represents the mature state: `unsafe` keyword + `trusted` keyword + enforcement on by default (no longer opt-in). Rust leads today at 77.5% because its borrow checker and unsafe propagation have always been default-on. The distance from C# + `unsafe` + `trusted` (72.5%) to C# (optimal) (87.5%) is model maturity — the same path Rust has already completed. The remaining gap to 100% is the inherent ambiguity of `unsafe` serving as both method modifier and block keyword — a cost C# pays for backward compatibility.

## Design Tradeoffs

Each language made deliberate choices. **D** prioritized trust boundary discoverability (`@trusted`) but its unsafe-first default confines the model to the safe subset. **Rust** prioritized unsafe scoping and invested in [Miri](https://github.com/rust-lang/miri) for soundness verification while leaving trust boundary discovery to conventions — its safe-first default means trust boundaries are structurally exhaustive but unmarked. **Swift** prioritized composability and shipped [strict memory safety checking](https://docs.swift.org/compiler/documentation/diagnostics/strict-memory-safety/) as a compiler audit mode — but it inventories unsafe usage sites, not trust boundaries, and uses warnings rather than errors. **C#** can combine D's trust boundary discoverability with Rust's safe-first exhaustiveness and unsafe-code discoverability — a combination none of the four currently achieves.

## Conclusion

The inference cost of a safety design is a primary metric for its practical value. Designs that require scripts, ASTs, or LSPs to answer "where are the trust boundaries?" impose a tax on every auditor, every agent, and every review cycle.

C# introduced `unsafe`. Rust and Swift evolved it. D arrived at the right architecture — three explicit layers — but not the right default. C# can combine D's insight with a safe-first default where trust boundaries are exhaustive, closing the gap that every language in this lineage has left open. The `trusted` keyword makes trust boundaries directly discoverable, produces lossless attestations under `git blame`, and enables the agent-assisted workflows that will be central to memory safety adoption at scale. The language that introduced `unsafe` can be the first to complete the model.

## Appendix: Scoring Methodology

### Grep difficulty scale

Each discovery task is scored on a 0–2 scale based on the grep difficulty required:

| Method | Score | Rationale |
|--------|-------|-----------|
| Clean grep | 2 | Easy grep, always accurate |
| Grep with pattern knowledge | 1.5 | Harder grep (regex, `-A 1`, multiline), always accurate |
| Script (awk/parser) | 0.5 | Approximation with known false positives, not authoritative |
| Not possible / invisible | 0 | Requires AST/LSP or information doesn't exist in the source |

### Metric descriptions

Scores are organized into two categories: **positive metrics** (discovery capability and auditing design) and **demerits** (observable problems in the grep workflow). Positive metrics measure how well the design supports auditing. Demerits measure friction an auditor or agent encounters when interpreting grep results. Each demerit includes an observable test — a concrete demonstration that can be performed in a terminal.

#### Discovery: Find trust boundaries (weight: 3)

Trust boundary functions are where human judgment meets compiler enforcement. A developer has reviewed the interior unsafe code and attests that the function is safe to call. These are the highest-value audit targets — if a trust boundary attestation is wrong, the safe code that depends on it is silently unsound.

#### Discovery: Find unsafe declarations (weight: 3)

Unsafe declarations — functions that are unsafe to call — are the second audit priority. They contain the operations that trust boundaries depend on. An auditor reviewing a trust boundary needs to understand what unsafe functions it calls and what contracts those functions require.

#### Discovery: Safe as default (weight: 3)

Safe-as-default makes trust boundaries exhaustive roots of the audit graph, as explained in the [D section](#ds-three-layer-model). Scored as a binary property: 3 points if safe is the default, 0 if not. This is related to but distinct from enforcement: safe-as-default determines whether grep targets are *exhaustive* (all paths covered), while enforcement determines whether they are *correct* (annotations are authoritative). D satisfies enforcement but not exhaustiveness. Swift satisfies exhaustiveness but not enforcement.

#### Auditing design: Outer unsafe is viral contract (+1)

When `unsafe` on a function signature propagates to callers — requiring them to also be in an unsafe context — the unsafety spreads upward through the call chain until a `trusted` method absorbs it. This creates a traceable chain from unsafe operations through to their trust boundary. Without this property, `unsafe` merely enables a scope and the call graph carries no safety information.

#### Auditing design: Inner unsafe is constrained (+1)

When interior `unsafe` blocks are implementation-only — hidden from callers, absorbed by the enclosing trust boundary — the audit surface is minimized. The compiler verifies everything outside the `unsafe` blocks; the semantic auditor (human or agent) focuses only on what's inside them. This is the discipline that makes the three-layer model work: maximize what the compiler checks, minimize what the auditor must review.

#### Auditing design: Enforcement on by default (+3)

When the safety model runs without opt-in, grep results reflect ground truth from the start — there is no adoption gap where annotations are incomplete. Rust's borrow checker, lifetime system, and unsafe propagation are active in every Rust project by default. C#'s current `unsafe` gate is similarly default-on: you cannot use pointers or unsafe operations without explicitly entering an `unsafe` context. New C# proposals (including `trusted`) require opting in to the new model, so they lose this credit until the model matures. Swift's strict memory safety requires `-strict-memory-safety`. D's `@safe` is opt-in per function.

The weight of 3 reflects that default-on enforcement is a significant advantage — it is what allows Rust's safety model to be trusted across the ecosystem without per-project verification. This also partially accounts for Rust's borrow checker, which is a comprehensive verification system that this paper's discoverability-focused scoring does not otherwise measure.

#### Demerit: Grep ambiguity (-1 each)

A grep ambiguity demerit applies when a single grep pattern returns results with mixed safety roles — the auditor cannot determine from the grep output alone what kind of hit they're looking at. Each distinct source of ambiguity is an independent -1 demerit. Ambiguity is additive in the same way that the grep difficulty scale is — each source compounds the auditor's inference burden.

**`unsafe` mixes methods, blocks, and types (-1).** Observable: run `rg "unsafe"` on a C# codebase. The results include `unsafe void M()` (method signatures), `unsafe { }` (blocks), `unsafe class` (type declarations), and `unsafe` fields. The auditor cannot determine the safety role of a hit without reading the surrounding context. Applies to (to greater or lesser degrees): all C# variants.

**`unsafe class` makes members implicitly unsafe (-1).** Observable: run `rg "unsafe"` and note that methods inside an `unsafe class` have no per-method `unsafe` marker. They are invisible to grep — a false negative, not a false positive. The auditor's grep results are silently incomplete. See [`scripts/find-csharp-unsafe-methods.sh`](scripts/find-csharp-unsafe-methods.sh) for examples. Applies to: C# (current), and C# + `RequiresUnsafe`. Does not apply to C# + `unsafe` keyword, C# + `unsafe` + `trusted`, or C# (optimal) — under those designs, `unsafe class` is an error, requiring every method to be correctly marked. Note: this is a proposal design difference, not an attribute-vs-keyword consequence — the `RequiresUnsafe` proposal could have addressed `unsafe class` but didn't.

**`RequiresUnsafe` mixes true and false (-1).** Observable: in a codebase with both `[RequiresUnsafe]` (caller-unsafe) and `[RequiresUnsafe(false)]` (trust boundary), run `rg "RequiresUnsafe"`. Both roles appear in the same result set. To separate them, the auditor must use exclusion logic (`grep -v "false"`) and account for the bare `[RequiresUnsafe]` (default true) vs explicit `[RequiresUnsafe(true)]` — a ternary value encoded in a single attribute name. No other language in this comparison encodes two distinct safety roles in a single identifier distinguished by a boolean parameter. For comparison, Swift's `@unsafe` has no `@unsafe(false)` — declaring a safe wrapper is simply the absence of `@unsafe`, not a negation of it. Applies to: C# + `RequiresUnsafe`.

#### Demerit: Audit-based model (varies)

An enforcement-based model (errors, not warnings) guarantees that grep results are complete: if the code compiles, the annotations are correct and present. An audit-based model (warnings) means annotations are aspirational — the code compiles regardless of whether the migration is complete. Grep results in an audit-based model reflect migration progress, not final state.

Observable: build [apple/swift-collections](https://github.com/apple/swift-collections) with `-strict-memory-safety`. The compiler produces 12,526 warnings across 319 files. Grep for explicit `unsafe` expressions finds 158 hits — 11% of what the compiler finds. The remaining 89% are unmarked because the migration is incomplete. The code compiles and ships regardless.

The demerit is scaled by distribution model. For source-distributed languages, consumers can run the compiler themselves and see warnings — the demerit is -1. For binary-distributed languages like C#/.NET, warnings are invisible to consumers (they receive compiled assemblies, not source) — the demerit is -3. Binary distribution is not incidental to .NET — it is a consequence of language design. .NET's stable metadata format made binary distribution possible; NuGet followed. Rust's lack of a stable ABI forces crates.io to distribute source — consumers recompile and see warnings themselves. Both are compiler decisions, not packaging decisions. C#'s language design must account for the distribution model it created: errors are the only safety signal that crosses the binary boundary.

#### Demerit: Non-standard terminology (-1)

Observable: `[RequiresUnsafe(false)]` is a compound double negative — the attribute name says "requires unsafe" and the parameter says "no it doesn't." During code review, the reviewer must mentally resolve the negation before reaching the safety question. This is the same cognitive cost that makes `if (!disabled)` harder to read than `if (enabled)`. A keyword (`trusted`) asserts intent directly; a double-negative attribute encodes it indirectly.

#### Demerit: Duplicate marking (-1)

Observable: under the `[RequiresUnsafe]` attribute approach, run `rg "RequiresUnsafe.*unsafe\|unsafe.*RequiresUnsafe"` on a C# codebase with pointer-bearing methods. Methods carry both `unsafe` (legacy scope enabler) and `[RequiresUnsafe]` (new caller-unsafe semantics): `[RequiresUnsafe] unsafe void M(int* p)`. As noted in the [follow-up PR](https://github.com/dotnet/csharplang/pull/10058): "Having both `RequiresUnsafe` and `unsafe` on a method is confusing. Without consulting the language specification, these terms appear to be duplicated." In dotnet/runtime, 97% of methods with pointers would require this dual annotation. The auditor must understand both annotations together to determine the method's safety role.

Of the five demerits against C# + `RequiresUnsafe`: three are driven by the attribute representation (true/false mixing, double-negative terminology, duplicate marking), one is a proposal design choice unrelated to the attribute form (`unsafe class` implicit members — the proposal could have addressed this), and one is shared by all C# variants (`unsafe` mixing). Swift's `@unsafe` demonstrates that even a clean attribute has a grep cost — it loses 0.5 discovery points because `@unsafe` lands on a separate line, requiring `-A 1` for useful output — but Swift avoids the three `RequiresUnsafe`-specific demerits because `@unsafe` is a single-purpose marker with no boolean parameter, no double negative, and no duplicate keyword.

### Scoring detail

**Discovery** (max 15):

| Task | Weight | D | Rust | Swift | C# (current) | C# + `unsafe` keyword | C# + `RequiresUnsafe` | C# + `unsafe` + `trusted` | C# (optimal) |
|------|--------|---|------|-------|---------------|------------------------|------------------------|----------------------------|---------------|
| Find trust boundaries | 3 | 2 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 2 | 2 |
| Find unsafe declarations | 3 | 0 | 2 | 1.5 | 1.5 | 1.5 | 1.5 | 1.5 | 1.5 |
| Safe as default | 3 | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Discovery subtotal** | | **6** | **10.5** | **9** | **9** | **9** | **9** | **13.5** | **13.5** |

**Auditing design** (max 5):

| Sub-point | D | Rust | Swift | C# (current) | C# + `unsafe` keyword | C# + `RequiresUnsafe` | C# + `unsafe` + `trusted` | C# (optimal) |
|-----------|---|------|-------|---------------|------------------------|------------------------|----------------------------|---------------|
| Outer unsafe is caller contract | 1 | 1 | 1 | 0 | 1 | 1 | 1 | 1 |
| Inner unsafe is implementation-only | 1 | 1 | 1 | 0 | 1 | 1 | 1 | 1 |
| Enforcement on by default | — | 3 | — | 3 | — | — | — | 3 |
| **Auditing subtotal** | **2** | **5** | **2** | **3** | **2** | **2** | **2** | **5** |

**Demerits:**

| Condition | D | Rust | Swift | C# (current) | C# + `unsafe` keyword | C# + `RequiresUnsafe` | C# + `unsafe` + `trusted` | C# (optimal) |
|-----------|---|------|-------|---------------|------------------------|------------------------|----------------------------|---------------|
| `unsafe` mixes methods, blocks, and types | — | — | — | -1 | -1 | -1 | -1 | -1 |
| `unsafe class` makes members implicitly unsafe | — | — | — | -1 | — | -1 | — | — |
| `RequiresUnsafe` mixes true and false | — | — | — | — | — | -1 | — | — |
| Audit-based, source-delivered | — | — | -1 | — | — | — | — | — |
| Audit-based, binary-delivered | — | — | — | -3 | — | — | — | — |
| Non-standard terminology | — | — | — | — | — | -1 | — | — |
| Duplicate marking | — | — | — | — | — | -1 | — | — |
| **Total demerits** | **0** | **0** | **-1** | **-5** | **-1** | **-5** | **-1** | **-1** |

### Combined results

Base possible: 15 (discovery) + 5 (auditing) = **20**

| Language | Discovery | Auditing | Demerits | Total | % |
|----------|-----------|----------|----------|-------|---|
| C# (optimal) | 13.5 | 5 | -1 | 17.5 | 87.5% |
| Rust | 10.5 | 5 | 0 | 15.5 | 77.5% |
| C# + `unsafe` + `trusted` | 13.5 | 2 | -1 | 14.5 | 72.5% |
| C# + `unsafe` keyword | 9 | 2 | -1 | 10 | 50.0% |
| Swift | 9 | 2 | -1 | 10 | 50.0% |
| D | 6 | 2 | 0 | 8 | 40.0% |
| C# (current) | 9 | 3 | -5 | 7 | 35.0% |
| C# + `RequiresUnsafe` | 9 | 2 | -5 | 6 | 30.0% |

### Note on weighting

The three discovery dimensions are equally weighted at 3 points each. The safe-as-default dimension is what separates D from the safe-first languages: D scores perfectly on trust boundary discovery but its unsafe-first default means those boundaries only cover the safe subset. Rust has the opposite profile — safe-as-default but no trust boundary marker. Enforcement on by default (+3) recognizes that Rust's borrow checker and C#'s current `unsafe` gate run without opt-in, while new C# proposals, Swift, and D require explicit adoption. C# (optimal) represents the mature state where the `trusted`/`unsafe` model is no longer opt-in.

### Roadmap

| Step | Change | Score |
|------|--------|-------|
| C# (current) | — | **35.0%** |
| + `unsafe` keyword (caller contract) | Caller contract, implementation-only scoping | **50.0%** |
| + `trusted` keyword | Trust boundaries become grep-discoverable | **72.5%** |
| + default-on | Model maturity, no longer opt-in | **87.5%** |

## Appendix: The `unsafe` Keyword Lineage and Trust Boundary Gap

The trust boundary gap has discussion and productization to support it. Rust has engaged with it through [RFC 2585](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html) (separating "unsafe to call" from "body does unsafe things"), [RFC 3484](https://rust-lang.github.io/rfcs/3484-unsafe-extern-blocks.html) (introducing `safe` as a contextual keyword in extern blocks — someone [asked](https://github.com/rust-lang/rfcs/pull/3484) "why not `trusted`?"), [RFC 3768](https://github.com/rust-lang/rfcs/pull/3768) (safe blocks, closed), and [documentation conventions](https://internals.rust-lang.org/t/pre-rfc-rust-safety-standard/23963) (`// SAFETY:` comments). Swift's SE-0458 marks unsafe code but not trust boundaries. D addressed it at the language level with `@trusted` from the start, though its unsafe-first default limits the model to the safe subset.

The `unsafe` keyword — for modern mainline languages — starts with C#. Earlier languages had related concepts (Modula-3's `UNSAFE` modules in 1989, for example), but C# 1.0 (2001) introduced `unsafe` as a compiler-enforced keyword in a mainstream C-family language — the first to give the safe/unsafe boundary a syntactic marker in that lineage. D (2010) built a three-layer model with `@safe`, `@trusted`, and `@system` — the only language to address trust boundaries from the start. Rust (2015) extended C#'s `unsafe` keyword: `unsafe fn` as a caller contract, `unsafe {}` as scoped interior unsafe. Swift (2024–2025) went further with `@unsafe` as an attribute and `unsafe` as an expression prefix.

## Lossless Attestations

"Lossless" means every safety attestation is recorded in code and source control. There is never a compiler-accepted state where information is lost. `git blame` finds who attested safety and when. `grep` inventories every attestation. Code review tools can flag changes to attested methods for re-review.

In "absence means safe" designs, there is no attestation to find. An auditor cannot distinguish "reviewed and confirmed safe" from "never reviewed." When a safety-critical bug is found, `git blame` answers the question in a lossless system. In an inference-based system, there's nothing to find.

### Defense in depth: the xz backdoor lesson

The [xz/liblzma backdoor](https://en.wikipedia.org/wiki/XZ_Utils_backdoor) illustrates why enforcement matters. There are three tiers of defense against malicious changes:

1. **Compiler errors** — the change cannot land without explicitly modifying the safety annotation. The strongest defense.
2. **Tool warnings** (valgrind, analyzers, etc.) — the change can land, but produces signals after the fact. An attacker with commit access can volunteer to "fix" the warnings.
3. **Diff review** — the change is visible in version control but has no structural salience. Requires a reviewer to notice the significance. The weakest defense.

The xz attacker operated at tiers 2 and 3: the diffs were structurally unremarkable, and when valgrind flagged stack layout mismatches, the attacker [misdirected the fix](https://github.com/tukaani-project/xz/commit/82ecc538193b380a21622aea02b0ba078e7ade92) and [disabled oss-fuzz detection](https://github.com/google/oss-fuzz/pull/10667). Advisory warnings were subverted because they were advisory. Compiler errors cannot be quietly absorbed — they require an explicit change to the safety model itself.

A `trusted` design operates at tier 1. Removing `trusted` from a method with interior `unsafe` blocks is a compiler error — the method becomes safe and safe methods cannot contain `unsafe` blocks. Removing the `unsafe` blocks from a `trusted` method is a compiler warning (unnecessary attestation). The attacker would have to explicitly change the safety annotations, producing a structurally remarkable diff that names the safety model directly — not a diff that looks like routine cleanup.

Lossy designs — where a trust boundary has no marker — operate at tier 3 at best. The diff that removes an `unsafe` block from an unmarked method looks like routine cleanup. There is no compiler error. There is no annotation change in the signature. The safety attestation simply vanishes from the code without any toolchain signal that something important happened.

D's `@trusted` and the proposed C# `trusted` keyword both produce lossless attestations at tier 1. Rust's and Swift's trust boundaries do not.

### Binary distribution raises the bar

As noted in the introduction, C#'s binary distribution model means errors are the only safety signal that crosses to consumers. The defense tiers above interact differently: source-distributed languages let consumers see warnings during their own builds, but binary-distributed languages swallow them.

Swift faces a related challenge with Apple's own frameworks. During the [SE-0458 discussion](https://forums.swift.org/t/se-0458-opt-in-strict-memory-safety-checking/77274), it was noted that Apple's Combine framework is "written in Swift, but _not_ safe (by Swift 6's standard), and unlikely to become safe nor even acquire `unsafe` annotations." Douglas Gregor acknowledged this as "a hole" in the model. When closed-source, binary-distributed frameworks don't adopt safety annotations, consumers must trust those decisions with no ability to audit or even see the warnings that were (or weren't) produced during the framework's build. The safety model's guarantees stop at the binary boundary.

## Agent-Assisted Maintenance

The [PR feedback](https://github.com/dotnet/csharplang/pull/10058#pullrequestreview-4016744830) states: "High-confidence AI-assisted automation of the migration process flow is a part of the feature design." The inference cost of the safety model directly determines how effectively agents can participate.

A low-inference model enables agents to: inventory trust boundaries (`grep trusted` — complete, no AST required), scope reviews (check each `trusted` method's interior `unsafe` for correctness), detect drift (new `unsafe` blocks in a `trusted` method are flagged for re-review), and assist migration (propose `trusted` or `unsafe` annotations for methods with interior unsafe blocks).

High-inference models force agents to build ASTs or rely on LSPs. This is more expensive, fragile across environments, and harder to validate.

### The LSP doesn't solve this

The LSP protocol's `workspace/symbol` request filters by name and `SymbolKind` — but `SymbolKind` has no variant for unsafe or trusted. No language server (rust-analyzer, SourceKit-LSP, Roslyn, serve-d) can query for safety-relevant code across a workspace. The LSP adds value as a *follow-up* to grep — call graphs, type hierarchy, targeted review — but only if grep can find the starting points. A design that makes grep effective makes the entire toolchain more effective.

### The canonical audit workflow

The safety audit has two activities: **TBF-directed review** (discover trust boundaries, trace into the unsafe code they attest) and **undirected unsafe review** (independently inventory all unsafe code, looking for patterns, known-bad operations, or code that should have been wrapped in a trust boundary but wasn't). TBF-directed review is the hard requirement — it follows the audit graph from roots to leaves. Undirected review is supplementary but important.

D handles TBF-directed review within the `@safe` subset: `rg "@trusted"` finds the boundaries, and reading the body traces into the `@system` calls. But D can't do undirected review because `@system` is implicit. Rust handles undirected review perfectly: `rg "unsafe fn"` inventories all unsafe code. But Rust can't do TBF-directed review because trust boundaries have no marker. The workflow below uses real code from real repos to demonstrate both activities.

**Step 1: Discover trust boundaries** (D, [dlang/phobos](https://github.com/dlang/phobos))

```bash
$ rg "@trusted" --type d std/array.d
```

```text
997:auto uninitializedArray(T, I...)(I sizes) nothrow @trusted
1041:auto minimallyInitializedArray(T, I...)(I sizes) nothrow @trusted
1261:CommonType!(T[], U[]) overlap(T, U)(T[] a, U[] b) @trusted
1549:        @trusted static void moveToRight(T[] arr, size_t gap)
1863:@trusted
3596:    this(A arr) @trusted
3665:    @property inout(T)[] opSlice() inout @trusted
3920:        void clear() @trusted pure nothrow
...
```

One command. The auditor immediately sees `uninitializedArray` — a function that returns an array with uninitialized memory and attests that it's safe to call. The function signature, file, and line number are all present. The auditor can pick this method, read its body, and verify the attestation. No script. No LSP. No inference.

**Step 2: Inspect unsafe blocks** (Rust, [rust-lang/rust](https://github.com/rust-lang/rust) `library/`)

```bash
$ rg "unsafe fn" --type rust library/alloc/src/alloc.rs -A 10
```

```text
pub unsafe fn alloc(layout: Layout) -> *mut u8 {
    unsafe {
        // Make sure we don't accidentally allow omitting the allocator shim in
        // stable code until it is actually stabilized.
        __rust_no_alloc_shim_is_unstable_v2();

        __rust_alloc(layout.size(), layout.alignment())
    }
}
...
pub unsafe fn dealloc(ptr: *mut u8, layout: Layout) {
    unsafe { dealloc_nonnull(NonNull::new_unchecked(ptr), layout) }
}
```

One command. The auditor sees the full function: its unsafe contract (`unsafe fn` — callers must ensure valid layout), its interior unsafe operations (`__rust_alloc`, `NonNull::new_unchecked`), and the `// SAFETY:`-style comments. An agent can review this in a single pass and ask for more context only if needed.

**The gap:** D gives you step 1 (within the `@safe` subset) but not step 2. Rust gives you step 2 but not step 1. Each language provides part of the workflow.

**C# (optimal)** would provide both steps in a single codebase:

```bash
$ rg "trusted" --type cs                    # Step 1: find trust boundaries
$ rg "unsafe" --type cs -A 20               # Step 2: inspect unsafe code
```

The first command finds every trust boundary — exhaustive, because safe is the default. The second finds every unsafe operation with body context. Together: the complete safety-critical picture. No other language in this comparison achieves both.

## Appendix: Formal Verification Parallel

Terence Tao has arrived at a similar conclusion in mathematics research with the [Lean proof language](https://leanprover-community.github.io/). Lean makes proof obligations machine-checkable; `trusted` makes safety attestations machine-discoverable — same principle, different domain. The relationship between mathematics and computer science is circular and reinforcing — the foundations of modern cryptography come from mathematics, and the tools for machine-verified proofs come from computer science. Tao's vision is that large groups of mathematicians and agents work together to produce compelling and trusted proofs. That requires the proof language to be lossless — exactly the property this paper argues for in safety attestations.

## Appendix: Tokenizer Comparison

The [OpenAI Tokenizer](https://platform.openai.com/tokenizer) shows that the keyword and attribute representations are not equivalent from a model's perspective.

`unsafe` keyword:

![unsafe keyword tokens](https://github.com/user-attachments/assets/59554280-faa1-480b-ba2a-af8d6325a4e0)

`trusted` keyword:

![trusted keyword tokens](https://github.com/user-attachments/assets/ca0fde0d-52d4-49f5-b563-da7b5d5c1cf8)

`RequiresUnsafeAttribute` tokens:

![RequiresUnsafe attribute tokens](https://github.com/user-attachments/assets/1f9c97aa-a7f3-436d-9896-e9d561a679a4)

`RequiresUnsafeAttribute(true)` tokens:

![RequiresUnsafe(true) attribute tokens](https://github.com/user-attachments/assets/31914393-6aee-446c-a540-fc25b583372e)

`RequiresUnsafeAttribute(false)` tokens:

![RequiresUnsafe(false) attribute tokens](https://github.com/user-attachments/assets/ab90356e-9425-498d-a31d-24d99f6df7b9)

`unsafe` and `trusted` are each single tokens. `RequiresUnsafeAttribute(false)` spans seven tokens. While tokenization alone does not determine comprehension, it is a reasonable proxy for representational complexity. The compound, double-negative form encodes the same safety information in a representation that is strictly harder to parse — for both humans and models. This aligns with the grep-based findings: simpler representations yield lower inference cost across every review context.
