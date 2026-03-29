# Trust Boundary Discoverability in Memory-Safe Languages

I've been reading the design notes from C#, D, Rust, and Swift design communities. Most of the focus is on how blocks of code are decorated to highlight unsafety. The unsafe spotlight is important but doesn't deliver confidence where you need it most. The aspect that truly matters is the transition from unsafe to safe code. That's a word for that: "trust boundary". This transition point should be the most decorated, attracting the most scrutiny. Most of the designs accept the lack of an unsafe marker as an indication that unsafe warnings/errors can be suppressed. We don't know for sure if the marker was deleted by accident or as a meaningful removal. These designs are storing a ternary value with a single bit. It's not clear why Rust and Swift chose that approach, while we have the opportunity to resolve this critical design point with C#.

> Large Language Models (LLMs) add a new dimension to memory safety. Safe code is well-suited to generative AI. It is easier to understand, review, and modify with confidence. We recommend that developers configure their AI systems and build tools to permit only safe code. In the new AI paradigm, the compiler and analyzers become the final authority on safety.

Source: https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/memory-safety.md

That's a compelling vision. Our ambition is that agents generate most C# code going forward and that they can help with migration to our new memory safety model. The vision implies a lossless design with clear attestation at the trust boundary. Removing `unsafe` anywhere should result in compiler errors. Lossy designs get us into Jia Tang territory.

My overall take:

- The value of a memory safety system is enforcement and auditing, automatic or otherwise.
- The mechanistic basis is an inherently collaborative auditing system between deterministic (compiler) and semantic (human and/or agent) actors.
- The success of the system depends on the degree to which it relies on inference in the semantic domain. High inference means low clarity means low confidence.
- We can test the cost of inference using grep as a proxy.
- Agent-assisted code migration and maintenance is a core part of our vision. A low-inference design model is a critical path to enabling that.

We've primarily been looking at Rust and Swift. I think we can learn more from D.

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

### D's Explicit Trust Boundaries

> D is a system programming language. D has a memory-safe subset.

Source: [D Tour: Memory](https://tour.dlang.org/tour/en/basics/memory)

D has three safety tiers:

- `@safe`
- `@trusted`
- `@system`

That's a pyramid. Reasoning from the bottom:

- `@system` functions are assumed to be unsafe. Undecorated functions are implicitly `@system`.
- `@trusted` functions can call `@system` or any other functions and present a caller-safe surface.
- `@safe` functions operate within the safe subset and may only call `@safe` and `@trusted` functions.

All functions must be sound. The `@system` code needs to be correct and safe to use after obligations are discharged by a `@trusted` caller. Sound `@system` and `@trusted` code is the responsibility of the developer, not the compiler. That's true of Rust too.

The opt-in-to-safe approach is sensible for a systems language.

#### Auditing characteristics

Experienced D developers reviewing a new codebase for safety concerns presumably search for `@trusted` functions as the starting point. Safe code doesn't need to be reviewed, while `@system` code can be best understood by starting from the safe surface area and the assumptions that it makes. `@trusted` is the most fundamental "safe surface area".

D developers can rely on grep to find `@trusted` functions. It is powerful that grep _always_ finds the functions that need to be audited first. There is no need to look at the method implementation to determine the color of the method, or to rely on an AST or LSP.

### The Silverlight Security Transparency Parallel

I was thinking about how we could elevate these terms to more generic names.

Flashback terms:

- Transparent
- Safe Critical
- Security Critical

These are from our [security transparency model from Silverlight](https://learn.microsoft.com/previous-versions/dotnet/framework/code-access-security/security-transparent-code). I realized that D recreated the same thing, frankly with better names.

That model had three layers with clear markings throughout, making auditing straightforward. "Transparent" code could only call other transparent or "safe critical" code. "Safe critical" and "security critical" code had the same access to privileged operations — the difference was caller contract, not capability. "Safe critical" code was the trust boundary: it could be called by transparent code and took on the obligation of validating inputs and presenting a safe surface. "Security critical" code could only be called by other critical code.

The mapping is direct:

| D | Silverlight | Role |
|---|-------------|------|
| `@safe` | Transparent | Safe subset, restricted callees |
| `@trusted` | Safe Critical | Trust boundary, attests safety to callers |
| `@system` | Security Critical | Unrestricted, unsafe operations |

The Silverlight model was abandoned when Silverlight was abandoned — not because the model was flawed. The design was sound. We already solved this problem once. The lesson is that a three-layer system with explicit trust boundaries is a recurring, validated pattern. We should reclaim it.

You can imagine asking an agent to review all "safe critical" methods. It is trivial for the agent to find them. This is a definitional characteristic of a well-designed safety model.

## Trust Boundary Functions

Trust Boundary Functions (TBF) are unsafe in the same way as any other unsafe function. They handle unsafe currency and must do so soundly. They only differ in that they have the special character that they are considered safe to call by developers who (in the general case) have no basis or intent of applying scrutiny. They take on a double duty.

My initial thinking -- in C# parlance -- was to call TBFs `safe` since that's the opposite of `unsafe`. However, these functions are in no way the opposite of unsafe. They _are_ unsafe plus a special bit. Another view is that the compiler can make a clear guarantee about `unsafe` code: "I've got no earthly idea what is going on!". And so the marker fits. However the same guarantee applies equally to TBFs. The concept of `safe` should only be applied when the compiler can guarantee that: "I know exactly what is going on and it aligns 100% with my model of safety." That's not remotely the case for TBFs.

"trusted" is a good term and aligns with "safe critical". What we really want is "attested-safe". That's a mouthfull. I also think it's a virtue to remove "safe" from the marking entirely. I like "trusted" as the term, matching the D language.

## Applying the Model to C\#

C# has the opposite model as D: unsafe code is marked and safe isn't. The difference doesn't matter for effective memory safety. That's an audience and form factor bias. It's the decorative approach for the middle layer that matters most.

The [caller-unsafe design](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md) recognizes trust boundary functions but does not mark them. Its `Caller2` example illustrates the pattern:

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

The design notes: "by presenting a safe API around an unsafe call, [the programmer is] asserting that all safety concerns of `M()` have been addressed." That assertion is the trust boundary — but `Caller2` has no marker on its signature. It is indistinguishable from a method that has never touched unsafe code.

The [unsafe evolution proposal](https://github.com/dotnet/csharplang/blob/main/proposals/unsafe-evolution.md) introduces `RequiresUnsafe` for caller-unsafe methods but similarly leaves trust boundary functions unmarked. The [alternative syntax proposal](https://github.com/dotnet/csharplang/blob/main/meetings/working-groups/unsafe-evolution/unsafe-alternative-syntax.md) explicitly notes that `[RequiresUnsafe]` "does not imply that the member is an unsafe context" — the author scopes `unsafe` blocks as they see fit, but the enclosing method gets no marker.

If caller-unsafe methods are marked as `unsafe`, then caller-safe methods with `unsafe` blocks should be marked as `trusted`. That's the same as D's `@trusted`. The presence of a `trusted` marking provides a language-required location to place an attestation and equally operates as a grep target for code review.

Another benefit of `trusted` is that we can say that all unmarked methods are implicitly marked as `safe` and no other methods can take on that marking. Complete separation of kind.

The migration approach:

- A tool marks all methods with interior unsafe blocks as `unsafe`.
- Developers mark those methods as `trusted` or address the errors presented by downstream callers.

This approach is lossless and grep-friendly. It preserves the three-layer model. It's actually better suited for auditing than D's approach: in D, `@safe` and `@trusted` code are easy to inventory, but in practice you want `@trusted` and `@system` code to be easy to inventory and audit. With a `trusted`/`unsafe` pairing in C#, the audit focus falls naturally on the trust boundaries (`trusted`) and the unsafe implementations (`unsafe`) rather than on purely safe code. To a large degree, safe code doesn't matter.

## Measuring Discoverability: The Grep Test

Memory safety across all languages inherently relies on human and agent auditing. The compiler verifies safe code by construction — that's the value proposition. But `trusted` and `unsafe` code cannot be verified by the compiler. They require semantic review: a human or agent must confirm that the unsafe operations are correctly bounded and that the trust boundary's safety attestation is valid. The audit value of methods is therefore inherently asymmetric. Safe code doesn't need review. Trust boundary functions need the most review — they are where human judgment meets compiler enforcement. Unsafe functions need review too, but the trust boundary is where the claim is made.

For JSON schemas, I use [`jq` as the arbiter of sound schema design](https://github.com/dotnet/designs/blob/main/accepted/2025/cve-schema/cve_schema.md#design-philosophy). If the `jq` queries are awkward, the schema is too, by implication. We can use grep as our proxy for sound language design as it relates to where human or agent auditing is required.

The question: how easily can we find the code that needs review — trust boundaries and unsafe implementations — across each language?

The analysis below uses [ripgrep](https://github.com/BurntSushi/ripgrep) and a set of awk-based scripts for the more complex queries. The scripts are triage tools with known limitations (string literals, macros, block comments can cause false positives). They are not authoritative audit tools but are reasonable approximations. All scripts are in the [`scripts/`](scripts/) directory.

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

Files, columns, and function signatures. One command, complete results. The `@trusted` attribute on the function signature makes trust boundaries directly discoverable.

**Finding unsafe code** — `@system` functions are implicit (undecorated), so grep alone cannot find them. An AST or LSP is needed to distinguish `@system` from `@safe` on undecorated code. This is a significant gap in D's discoverability model — the largest category of code (default `@system`) is invisible to grep.

### Rust

Source: [rust-lang/rust](https://github.com/rust-lang/rust) (`library/`)

**Finding trust boundaries** — Rust has no explicit marker for safe functions that contain `unsafe` blocks. Discovering them requires parsing function bodies. See [`scripts/find-rust-trust-boundaries.sh`](scripts/find-rust-trust-boundaries.sh) — an 80-line awk script that walks brace depth to approximate this:

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

This requires substantial effort to approximate what D achieves with a single grep. The script has acknowledged limitations (block comments, string literals, macros) and is a triage tool at best.

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

Directly discoverable. The `unsafe fn` keyword in the signature does the heavy lifting on disambiguation with `unsafe` blocks. An agent can go further with `rg "unsafe fn" --type rust -A 20` to capture the signature and body context in a single pass — typically enough to understand the function's contract and review its safety obligations without opening a file.

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

#### Design tradeoff acknowledgment

Rust's design deliberately chose fine-grained `unsafe` block scoping within safe functions. This gives auditors a different benefit: you can grep for every `unsafe {}` block and review the actual unsafe operation in isolation. The inference cost is higher for "which function attests safety?" but lower for "which exact line does the dangerous thing?" [RFC 2585](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html) (`unsafe_op_in_unsafe_fn`) was a step toward separating "the function is unsafe to call" from "the function body does unsafe things." The community made a considered tradeoff favoring composability and granularity over trust-boundary discoverability.

Rust's guidance to keep `unsafe` blocks narrow — ideally a few lines — has a real payoff for grep-based auditing. A narrow block means `rg -Un "unsafe\s*\{" -A 3` captures the entire unsafe operation in context. An agent reviewing unsafe code can start with the grep results and ask for more context only when needed. The same applies to Swift's `unsafe expr` prefix, which scopes unsafety to a single expression. Both designs make the unsafe *operations* easy to review even though the trust *boundaries* remain hidden.

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

The `@unsafe` attribute is discoverable, but because it typically appears on its own line, it doesn't carry the function signature. Adding one line of context (`-A 1`) helps:

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

Partially discoverable. The Rust one-line syntax (`unsafe fn`) is more ergonomic here, but Swift's approach is still better than having no marker at all.

#### Design tradeoff acknowledgment

Swift chose `@unsafe` as a declaration attribute and `unsafe` as an expression prefix (in Swift 6.2) for composability — it integrates with the existing attribute system and allows unsafe to compose with other annotations. [SE-0458](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md) is a considered design that optimizes for safety expressiveness. The argument here is specifically about discoverability, not about whether the Swift model is sound.

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

**Finding unsafe code** — C# supports `unsafe` on both methods and blocks, but doesn't syntactically distinguish between them:

```bash
$ rg "unsafe" --type cs src/libraries | head -10
```

```text
src/libraries/System.IO.Ports/src/System/IO/Ports/SerialStream.Windows.cs
63:        private static readonly unsafe IOCompletionCallback s_IOCallback = ...
859:        public override unsafe int EndRead(IAsyncResult asyncResult)
934:        public override unsafe void EndWrite(IAsyncResult asyncResult)
1008:        internal unsafe int Read(byte[] array, int offset, int count, int timeout)
1070:        internal unsafe void Write(byte[] array, int offset, int count, int timeout)
...
```

At first glance, this matches D and Rust in discoverability for finding `unsafe` methods. But it breaks down when `unsafe` methods and `unsafe` blocks are both present in results — there is no syntactic way to distinguish outer (caller) unsafety from interior (implementation) unsafety without reading the method body.

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

## Discoverability Grades

We score each language on three audit tasks — finding trust boundaries, finding unsafe declarations, and disambiguating outer (caller) vs. interior unsafe — weighted by importance to the audit workflow. The grading methodology is detailed in [Appendix: Scoring Methodology](#appendix-scoring-methodology).

| Language | Grade | Summary |
|----------|-------|---------|
| C# (proposed) | **A** | Both trust boundaries (`trusted`) and unsafe declarations (`unsafe`) are discoverable via clean grep. The only language where the complete audit graph is constructible from grep alone. |
| D | **B** | Trust boundaries (`@trusted`) are perfectly discoverable. Unsafe code (`@system`) is implicit and invisible to grep — you can find the boundaries but not the code they depend on. |
| Rust | **C** | Unsafe declarations (`unsafe fn`) are perfectly discoverable. Trust boundaries require an 80-line awk script to approximate. You can find the unsafe code but not the attestations. |
| Swift | **D** | Unsafe declarations (`@unsafe`) require `-A 1` context. Trust boundaries require a script. Neither side is cleanly discoverable. |
| C# (current) | **D** | Unsafe declarations are discoverable but ambiguous (mixed with blocks). Trust boundaries require a script. No disambiguation between outer and interior unsafe. |

C# moves from **D** to **A** with the addition of `trusted` — from trailing last to leading on the metrics that matter most for auditing.

## Lossless Attestations

The meaning of "lossless" is that safety attestations — the explicit claims that a trust boundary is correctly implemented — are recorded in code and source control. There is never a compiler-accepted state where information is lost.

In a lossless system:

- `git blame` can find the point of attestation: who claimed this method was safe, and when.
- `grep` can inventory every attestation with complete accuracy.
- Code review tools can automatically flag changes to attested methods for re-review.
- Compliance and audit trails are inherent in the source history.

Contrast this with "absence means safe" designs, where a method's safety role is inferred from the _absence_ of an `unsafe` marker. In those designs:

- There is no recorded attestation to find.
- There is no diff when a method transitions from "happens to be safe" to "deliberately attests safety."
- An auditor cannot distinguish between "reviewed and confirmed safe" and "never reviewed."

This distinction matters for incident response. When a safety-critical bug is found, the first question is "who reviewed this boundary and what assumptions did they make?" In a lossless system, `git blame` answers that question directly. In an inference-based system, the answer is "we don't know — there's nothing to find."

D's `@trusted` and the proposed C# `trusted` keyword both produce lossless attestations. Rust's and Swift's trust boundaries do not.

## Agent-Assisted Maintenance

Agent-assisted code migration and maintenance is a core part of our vision for memory safety adoption. The [memory safety design](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/memory-safety.md) states: "We recommend that developers configure their AI systems and build tools to permit only safe code. In the new AI paradigm, the compiler and analyzers become the final authority on safety." The [follow-up PR](https://github.com/dotnet/csharplang/pull/10058) goes further: "High-confidence AI-assisted automation of the migration process flow is a part of the feature design."

The inference cost of a safety model directly determines how effectively agents can participate.

A low-inference model enables agents to:

- **Inventory trust boundaries** — `grep trusted` returns a complete, accurate list. No AST parsing required.
- **Scope reviews** — given a list of `trusted` methods, an agent can review each one for correctness, checking that the interior `unsafe` operations are properly bounded.
- **Detect drift** — when code changes introduce new `unsafe` blocks inside a `trusted` method, the attestation is already there to flag for re-review.
- **Assist migration** — when adopting the new model, an agent can identify methods with interior `unsafe` blocks and propose the appropriate `trusted` or `unsafe` annotation.

High-inference models force agents to build ASTs or rely on LSPs to answer the same questions. This is not only more expensive — it's fragile. LSP availability varies across environments, AST parsers must track language evolution, and the results are harder to validate.

The grep test is not just a theoretical metric. It's a practical measure of how accessible a safety model is to the tools that will increasingly be responsible for maintaining it.

## Developing the C# Proposal

A [follow-up PR](https://github.com/dotnet/csharplang/pull/10058) proposes going back to `unsafe`/`safe` keywords, motivated by practical experience annotating dotnet/runtime: 97% of methods with pointers should be `RequiresUnsafe`, making the attribute approach high-churn for little benefit. The PR also introduces `safe` for extern methods that wrap safe native code (e.g., a P/Invoke into a safe Rust function). That PR's goals align with this paper:

> 1) clear, simple rules on which methods are caller unsafe vs. use unsafe
> 2) users annotate their code based on the rules of unsafev2, not unsafev1
> 3) annotation is easily auditable, meaning we can see whether a given project has aligned their code with unsafev2
> 4) support for multitargeting with unsafev1-only TFMs
>
> This feature will introduce compilation errors in existing unsafe code when opted into. High-confidence AI-assisted automation of the migration process flow is a part of the feature design.

The PR uses `safe` as the keyword for trust boundary functions. This paper argues for `trusted` instead, for the reasons discussed in [Trust Boundary Functions](#trust-boundary-functions): these methods are not safe in the compiler-verified sense — they are unsafe code that attests safety to callers. `trusted` avoids that confusion and aligns with D's `@trusted` and our Silverlight "safe critical" precedent.

It's worth noting that `[RequiresUnsafe(false)]` — suggested in the PR comments for extern methods — would be model-equivalent to `trusted`. Both say "this method handles unsafe concerns internally and is safe to call." The mechanical behavior would be the same. However, the clarity of meaning is not. `RequiresUnsafe(false)` is a double negative that tells you what the method _doesn't_ require rather than what it _does_ — it negates a property rather than asserting one. `trusted` is a positive declaration: this method has been reviewed, the unsafe operations are bounded, and the author attests to its safety. The grep story is also different: `rg "RequiresUnsafe(false)"` works but reads as an implementation detail, while `rg "trusted"` reads as intent.

### The `trusted` keyword

If caller-unsafe methods are marked `unsafe`, then caller-safe methods with interior `unsafe` blocks should be marked `trusted`. This creates the three-layer model:

| Layer | C# syntax | Meaning |
|-------|-----------|---------|
| Safe | (unmarked) | No unsafe operations, can only call safe and `trusted` methods |
| Trust boundary | `trusted` | Contains `unsafe` blocks, attests safety to callers |
| Unsafe | `unsafe` | Caller-unsafe, obligations must be discharged by caller |

### Interaction with `unsafe class`

Today, members of an `unsafe class` are implicitly unsafe. Under the proposed model, methods inside an `unsafe class` that present a safe surface to callers should still use the `trusted` keyword. The `unsafe class` declaration establishes that the type _works with_ unsafe constructs, but individual methods that attest safety to their callers should say so explicitly. This eliminates the "implicit unsafe type" audit gap.

### Lambdas and local functions

Interior lambdas and local functions that use `unsafe` blocks within a `trusted` method are covered by the enclosing method's attestation. The `trusted` marking on the outer method is the attestation that all interior unsafe operations — including those in lambdas — are correctly bounded. This matches D's model, where `@trusted` covers the entire function body.

### Breaking changes

Adding `trusted` as a new contextual keyword is not inherently breaking — it's an additive language feature. The migration path:

1. **Phase 1: Analyzer** — a diagnostic warns on methods with interior `unsafe` blocks that lack a `trusted` or `unsafe` modifier. This is advisory and non-breaking.
2. **Phase 2: Language feature** — `trusted` becomes a recognized modifier. Opt-in via project property or `LangVersion`.
3. **Phase 3: Default-on** — in a future `LangVersion`, the analyzer diagnostic becomes an error. Methods with interior `unsafe` blocks must be annotated.

This phased approach avoids a cliff and gives the ecosystem time to adopt.

### Migration tooling

The migration tool should:

1. Scan for all methods with interior `unsafe` blocks (similar to what [`scripts/find-csharp-trust-boundaries.sh`](scripts/find-csharp-trust-boundaries.sh) does today).
2. Mark those methods as `unsafe` (the conservative default — this is correct and safe).
3. Developers then triage: methods that present a safe surface to callers are changed from `unsafe` to `trusted`. Methods that are genuinely caller-unsafe remain `unsafe`.

The tool should also handle `unsafe class` members, flagging each method for individual annotation.

## Design Tradeoffs

Each language in this comparison made deliberate design choices. None of the designs are wrong — they optimize for different concerns:

**D** prioritized explicit trust boundaries with `@trusted`, enabling grep-based auditing at the cost of making unsafe code (`@system`) implicit and invisible to grep.

**Rust** prioritized fine-grained unsafe scoping, enabling auditors to pinpoint exact unsafe operations at the cost of making trust boundaries require inference.

**Swift** prioritized composability with its attribute system (`@unsafe`, `unsafe expr`), integrating safety annotations into the existing language design at the cost of multi-line signatures for auditing.

**C#** has an opportunity to learn from all three. The proposed `trusted` keyword borrows D's explicit trust boundary concept while preserving C#'s existing `unsafe` discoverability. The result would combine the auditing strengths of D with the unsafe-code discoverability of Rust — a combination none of the four languages currently achieves.

## Conclusion

The characteristics we want, in order of importance:

1. **Explicit marking where ambiguity exists** — trust boundaries should be explicitly annotated, not inferred from the absence of other markers.
2. **Disambiguation between outer and interior unsafe** — the distinction between "this method is unsafe to call" and "this method uses unsafe internally but is safe to call" should be syntactically clear.
3. **Signature-carried safety information** — safety annotations should appear in the method signature, ideally on a single line, to maximize grep utility.

The inference cost of a safety design is a primary metric for its practical value. Designs that require scripts, ASTs, or LSPs to answer the question "where are the trust boundaries?" impose a tax on every auditor, every agent, and every review cycle.

C# has the opportunity to lead on this metric. The `trusted` keyword is a small addition with an outsized effect: it makes trust boundaries directly discoverable, produces lossless attestations under `git blame`, and enables the agent-assisted workflows that will be central to memory safety adoption at scale.

## Appendix: Scoring Methodology

### Grep difficulty scale

Each audit task is scored on a 0–2 scale based on the grep difficulty required:

| Method | Score | Rationale |
|--------|-------|-----------|
| Clean grep | 2 | One command, exact results, no false positives |
| Grep with regex | 1.5 | One command, requires pattern knowledge, may have edge cases |
| Grep with context flag (`-A 1`) | 1 | One command, results require visual pairing across lines |
| Script (awk/parser) | 0.5 | Approximation with known false positives, not authoritative |
| Not possible / invisible | 0 | Requires AST/LSP or information doesn't exist in the source |

### Audit tasks and weights

Three tasks are scored, weighted by importance to the audit workflow:

| Task | Weight | Rationale |
|------|--------|-----------|
| Find trust boundaries | 6 | The most important audit target — where human judgment attests safety |
| Find unsafe declarations | 3 | The unsafe code that trust boundaries depend on |
| Disambiguate outer vs. interior unsafe | 1 | Quality-of-life for auditors; lowest weight because Rust and Swift explicitly opted out of this distinction |

Total possible: (2 × 6) + (2 × 3) + (2 × 1) = **20**

### Scoring detail

| Task | Weight | D | Rust | Swift | C# (current) | C# (proposed) |
|------|--------|---|------|-------|---------------|----------------|
| Find trust boundaries | 6 | 2 — clean grep `@trusted` | 0.5 — script | 0.5 — script | 0.5 — script | 2 — clean grep `trusted` |
| Find unsafe declarations | 3 | 0 — implicit `@system` | 2 — clean grep `unsafe fn` | 1 — `@unsafe` needs `-A 1` | 1.5 — regex to separate from blocks | 1.5 — regex to separate from blocks |
| Disambiguate outer vs interior | 1 | 2 — distinct keywords | 1.5 — `unsafe fn` is clean, `unsafe {` has line-break edge cases | 1.5 — `@unsafe` vs `unsafe expr` via regex | 0 — same token, same position | 2 — distinct keywords |
| **Weighted total** | | **14** | **10.5** | **7.5** | **7.5** | **18.5** |

### Grade boundaries

| Grade | Score range | Percentage |
|-------|-----------|------------|
| A | 18–20 | 90–100% |
| B | 14–17.9 | 70–89% |
| C | 10–13.9 | 50–69% |
| D | 7–9.9 | 35–49% |
| F | < 7 | < 35% |

### Results

| Language | Score | % | Grade |
|----------|-------|---|-------|
| C# (proposed) | 18.5 | 92.5% | **A** |
| D | 14 | 70% | **B** |
| Rust | 10.5 | 52.5% | **C** |
| Swift | 7.5 | 37.5% | **D** |
| C# (current) | 7.5 | 37.5% | **D** |
