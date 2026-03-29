# Trust Boundary Discoverability in Memory-Safe Languages

I've been reading the design notes from C#, D, Rust, and Swift design communities. Most of the focus is on how blocks of code are decorated to highlight unsafety. The unsafe spotlight is important but doesn't deliver confidence where you need it most. The aspect that truly matters is the transition from unsafe to safe code. That's a word for that: "trust boundary". This transition point should be the most lit up, attracting the most scrutiny. Most of the designs accept the lack of an unsafe marker as an indication that unsafe warnings/errors can be suppressed. We cannot know if the marker was deleted by accident or as a meaningful removal. These designs are storing a ternary value with a single bit. It's not clear why Rust and Swift chose that approach, while we have the opportunity to resolve this critical design point with C#.

> Large Language Models (LLMs) add a new dimension to memory safety. Safe code is well-suited to generative AI. It is easier to understand, review, and modify with confidence. We recommend that developers configure their AI systems and build tools to permit only safe code. In the new AI paradigm, the compiler and analyzers become the final authority on safety.

Source: https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/memory-safety.md

That's a compelling vision. Our ambition is that agents generate most C# code going forward and that they can help with migration to our new memory safety model over the next several years. The vision implies a lossless design with clear attestation at the trust boundary. Removing `unsafe` (establishing the afforementioned absence) should result in compiler errors. Lossy designs get us into Jia Tan ([xz fame](https://en.wikipedia.org/wiki/XZ_Utils_backdoor)) territory.

My overall take:

- The value of a memory safety system is enforcement and auditing, automatic or otherwise.
- The mechanistic basis is an inherently collaborative auditing system between deterministic (compiler) and semantic (human and/or agent) actors.
- The sematic actors primilary act WITHOUT compiler assistance (like via an LSP).
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

This approach can be thought of as an information-preserving model or a high-productivity/high-confidence software auditing system.

All functions must be sound at all three layers. The `@system` code needs to be correct and safe to use after obligations are discharged by a `@trusted` caller. Sound `@system` and `@trusted` code is the responsibility of the developer, not the compiler. That's true of Rust too.

The opt-in-to-safe approach is sensible for a systems language.

#### Auditing workflow

The D community's guidance confirms that `@trusted` is where the review budget goes. The official D blog [states](https://dlang.org/blog/2016/09/28/how-to-write-trusted-code-in-d/): "`@trusted` code is never mechanically checked for safety, so every line must be reviewed for correctness. For this reason, it's always advisable to keep the code that is `@trusted` as small as possible." Ate Eskola [writes](https://dlang.org/blog/2023/01/05/memory-safety-in-a-systems-programming-language-part-3/): "`@trusted` functions...need to be just as carefully reviewed, if not more so, as `@system` functions" and "it's many times more important than usual to keep `@system` and `@trusted` functions small and simple to review." The principle is clear: `@safe` code doesn't need manual review — the compiler verifies it. The audit focus narrows to `@trusted` and `@system`.

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

### Why grep?

One might ask why grep is the right proxy rather than an LSP or compiler query. The answer is that code review — the primary context where safety-critical code is evaluated — operates at the grep level, not the LSP level. When reviewing a pull request in GitHub, GitLab, or any diff view, the reviewer sees source text. There is no LSP connected to the diff view. There is no way to "go to definition" or "find all references" from a PR comment. The reviewer's tools are their eyes and the browser's Ctrl+F.

Source code should stand on its own for safety review. An LSP enhances productivity during development, but the safety story for a language cannot depend on a live compiler being on-hand at the moment of review. If a trust boundary is only identifiable through an LSP query, it is invisible in the context where it most needs to be seen.

This is the same argument behind using `jq` as a schema design proxy. If you need a specialized tool to understand whether a schema is well-designed, the schema has failed at self-description. If you need an LSP to understand whether a method is a trust boundary, the language has failed at self-description.

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

The Rust community's review guidance reinforces this focus on the unsafe side. The Rust Book [advises](https://doc.rust-lang.org/book/ch20-01-unsafe-rust.html): "Keep `unsafe` blocks small; you'll be thankful later when you investigate memory bugs." The Rustonomicon [describes](https://doc.rust-lang.org/nomicon/safe-unsafe-meaning.html) the trust model: "The `unsafe` keyword has two uses: to declare the existence of contracts the compiler can't check, and to declare that a programmer has checked that these contracts have been upheld." It also notes that standard library safe abstractions over unsafe code "have generally been rigorously manually checked." Effective Rust [adds](https://effective-rust.com/unsafe.html): "when something goes wrong, the `unsafe` wrapper can be the first suspect." The guidance is clear — unsafe code is where the review budget goes — but the trust boundary function that wraps it remains unnamed and undiscoverable by grep.

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

Swift's review guidance focuses on tooling rather than manual grep. The [memory safety vision](https://github.com/swiftlang/swift-evolution/blob/main/visions/memory-safety.md) states: "An auditing tool should be able to identify and report Swift modules that were compiled without strict memory safety as well as all of the places where the opt-out mechanism...is used." SE-0458 describes the feature as making "it easy to audit unsafe calls." The emphasis is on compiler-assisted audit rather than text-based discovery — a reasonable approach for a source-distributed language, but one that leaves the trust boundary (safe functions wrapping `unsafe` expressions) dependent on tooling rather than self-describing in the source.

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

## Discoverability and Auditing Grades

We score each language on two dimensions — **discovery** (can you find the code that needs review?) and **auditing** (does the design support the review workflow?) — weighted by importance. The grading methodology is detailed in [Appendix: Scoring Methodology](#appendix-scoring-methodology).

| Language | Grade | Summary |
|----------|-------|---------|
| C# (proposed)* | **B+** | Both trust boundaries (`trusted`) and unsafe declarations (`unsafe`) are discoverable via clean grep. Auditing clarity depends on design decisions not yet made. With those decisions: **A**. |
| D | **C+** | Trust boundaries (`@trusted`) are perfectly discoverable. Unsafe code (`@system`) is implicit and invisible to grep. Outer/inner disambiguation is clear, but `@system` is not a caller contract. |
| Rust | **C** | Unsafe declarations (`unsafe fn`) are perfectly discoverable with full auditing clarity — outer unsafe is a caller contract, inner unsafe is implementation-only. Trust boundaries require an 80-line awk script. |
| Swift | **D+** | Unsafe declarations (`@unsafe`) require `-A 1` context. Trust boundaries require a script. Has full auditing clarity like Rust. |
| C# (current) | **D** | Unsafe declarations are discoverable but ambiguous. Trust boundaries require a script. No outer/inner disambiguation, no caller contract, no implementation-only scoping. |

*C# (proposed) scores reflect only the `trusted` keyword addition. Two further design decisions — making `unsafe` on a method a caller contract and ensuring interior `unsafe` blocks are implementation-only — would raise the grade to **A**. Both Rust and Swift have already made these decisions.

## Trust Boundary Marking: Language Design History

The grep results show that no language besides D explicitly marks trust boundary functions. This is not for lack of discussion — the Rust and Swift communities have engaged with the problem and made deliberate choices. Understanding that history is important for C#'s design.

### Rust

Rust's design has evolved through several RFCs, each addressing part of the trust boundary question without fully resolving it.

[**RFC 2585 — Unsafe Block in Unsafe Fn**](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html) (accepted) separated "this function is unsafe to call" from "this function body does unsafe things" via the `unsafe_op_in_unsafe_fn` lint. This was the closest approach to the trust boundary question — it acknowledged that `unsafe fn` was doing double duty — but it addressed the problem from inside `unsafe fn` rather than marking the safe-wrapper-around-unsafe pattern.

[**RFC 3484 — Unsafe Extern Blocks**](https://rust-lang.github.io/rfcs/3484-unsafe-extern-blocks.html) (accepted) introduced `safe` as a contextual keyword inside `extern` blocks — marking foreign functions as safe to call. During the [discussion](https://github.com/rust-lang/rfcs/pull/3484), a reviewer asked why not use `trusted` rather than `safe`. The response was that Rust already has established semantics for "safe" and introducing "trusted" would need a larger plan that "does not yet exist in any concrete form." The `safe` keyword in extern blocks is the exact pattern Andy Gocke's [C# PR](https://github.com/dotnet/csharplang/pull/10058) proposes for extern methods.

[**RFC 3768 — Safe Blocks**](https://github.com/rust-lang/rfcs/pull/3768) (closed) proposed `safe {}` blocks inside `unsafe` contexts — the inverse direction. It was closed because "every single motivating example can be solved better by reducing the overly large scope of the unsafe block."

The [Unsafe Code Annotations](https://internals.rust-lang.org/t/unsafe-code-annotations/9239) discussion on Rust Internals proposed structured metadata (`reason`, `review`, `author`, `hash`) on `unsafe` blocks — a documentation-level approach rather than a language-level one. The [Pre-RFC: Rust Safety Standard](https://internals.rust-lang.org/t/pre-rfc-rust-safety-standard/23963) similarly recommends `// SAFETY:` comments for documenting why unsafe code is sound.

The pattern is consistent: Rust has addressed pieces of the trust boundary problem through lints (RFC 2585), contextual keywords in narrow contexts (RFC 3484), and documentation conventions (`// SAFETY:` comments). But it has not introduced a general-purpose marker for "this safe function wraps unsafe code and attests to its safety." The `// SAFETY:` comment convention is the closest equivalent to D's `@trusted` — it serves the same purpose but is invisible to grep, the compiler, and any automated tooling.

### Swift

Swift's [SE-0458 — Strict Memory Safety](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md) introduced `@unsafe` as a declaration attribute and `unsafe` as an expression prefix. This creates a clear story for marking unsafe code and for scoping unsafe operations to single expressions.

However, SE-0458 does not introduce a marker for trust boundary functions — safe functions that use `unsafe` expressions internally. The [Swift memory safety vision document](https://github.com/swiftlang/swift-evolution/blob/main/visions/memory-safety.md) describes the goal but the design relies on the absence of `@unsafe` to indicate safety, with no explicit attestation.

### D

D is the outlier. `@trusted` has been a language keyword since D's safety system was introduced. It is not an annotation or a lint or a comment convention — it is a first-class part of the type system's safety model. The [D specification](https://dlang.org/spec/memory-safe-d.html) defines the three-layer system (`@safe`, `@trusted`, `@system`) as foundational.

### Summary

The trust boundary gap is a known design space. Rust has engaged with it repeatedly and chosen documentation conventions. Swift has opted for absence-means-safe. D solved it at the language level from the start. C# has the opportunity to learn from all three and adopt a language-level solution — `trusted` — informed by the experience of each community.

### The `unsafe` keyword lineage

The `unsafe` keyword — at least for modern mainline languages — starts with C#. C# 1.0 (2001) introduced `unsafe` as a compiler-enforced keyword with a distinct context, the first mainstream language to give the safe/unsafe boundary a syntactic marker. Before that, the C/C++ world had no such distinction — everything was implicitly unsafe.

Rust (2015) took the C# innovation and extended it: `unsafe fn` as a caller contract, `unsafe {}` as scoped interior unsafe, the `// SAFETY:` documentation convention, and eventually `unsafe_op_in_unsafe_fn` to separate the two roles. Rust made `unsafe` do more work.

Swift (2024–2025, SE-0458) went further with `@unsafe` as a declaration attribute and `unsafe` as an expression prefix, scoping unsafety to individual expressions rather than blocks.

But both Rust and Swift evolved the _unsafe_ side of the model without addressing the _attestation_ side. They made it easier to find and scope unsafe code but left the trust boundary — the point where someone claims "I've reviewed this and it's safe to call" — unmarked. D is the only language that addressed attestation with `@trusted`, but D built its own model independently rather than evolving from C#'s keyword.

C# introduced `unsafe`. Rust and Swift evolved it to stronger utility. C# has the opportunity to evolve it again — pairing `unsafe` with `trusted` to close the trust boundary gap that every language in this lineage has left open. The language that started the `unsafe` keyword can be the first mainline language to complete the model.

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

### Defense in depth: the xz backdoor lesson

The introduction references "Jia Tan territory" — the [xz/liblzma backdoor](https://en.wikipedia.org/wiki/XZ_Utils_backdoor) discovered in 2024, where a contributor using the name "Jia Tan" spent years building trust and then introduced a backdoor into the xz compression library through diffs that didn't attract scrutiny. There are three tiers of defense against this kind of change:

1. **Compiler errors** — the change cannot land without being addressed. The author must explicitly modify the safety annotation. This is the gold standard.
2. **Tool warnings** (valgrind, analyzers, etc.) — the change can land, but produces signals after the fact. Helpful, but the attacker can volunteer to "fix" the warnings.
3. **Diff review** — the change is visible in version control but has no structural salience. Requires a reviewer to notice and understand the significance. This is the weakest defense.

The xz backdoor is instructive because it engaged all three tiers:

- **Tier 3 (diff review)** — the malicious changes existed in version control. Reviewers missed them. The diffs were structurally unremarkable.
- **Tier 2 (tool warnings)** — the backdoor caused valgrind errors due to stack layout mismatches. Valgrind detected the problem. But Jia Tan [claimed it was a GCC bug](https://github.com/tukaani-project/xz/commit/82ecc538193b380a21622aea02b0ba078e7ade92), submitted a misdirecting "fix," and then quietly updated the malicious test files the next day. He had also preemptively [disabled ifunc in oss-fuzz builds](https://github.com/google/oss-fuzz/pull/10667) months earlier to prevent the fuzzer from catching the backdoor. The attacker actively subverted the tier 2 tooling because he had commit access and the warnings were advisory.
- **Tier 1 (compiler errors)** — no compiler enforcement existed for the affected code path. The backdoor was never subjected to this tier.

The key distinction between tier 2 and tier 1 is that advisory warnings can be "fixed" by an attacker with commit access. Compiler errors cannot be quietly absorbed — they require an explicit change to the safety model itself.

A `trusted` design operates at tier 1. Removing `trusted` from a method with interior `unsafe` blocks is a compiler error. Removing the `unsafe` blocks from a `trusted` method is a compiler warning (unnecessary attestation). The attacker would have to explicitly change the safety annotations, producing a structurally remarkable diff that names the safety model directly — not a diff that looks like routine cleanup.

Lossy designs — where a trust boundary has no marker — operate at tier 3 at best. The diff that removes an `unsafe` block from an unmarked method looks like routine cleanup. There is no compiler error. There is no annotation change in the signature. The safety attestation simply vanishes from the code without any toolchain signal that something important happened.

D's `@trusted` and the proposed C# `trusted` keyword both produce lossless attestations at tier 1. Rust's and Swift's trust boundaries do not.

### Binary distribution raises the bar

The defense tiers interact differently depending on how code is distributed. Rust and Swift are primarily source-distributed — consumers compile from source and see compiler warnings during their own builds. A pragma that suppresses a warning is visible in the source diff. Consumers can audit safety decisions themselves.

C#/.NET is primarily binary-distributed. Consumers get compiled assemblies. Compiler warnings during the library author's build are invisible to consumers. The consumer sees only the result: either the API compiles cleanly against their code or it doesn't. This means **errors are the only defense that reliably reaches consumers**. Warnings are swallowed at build time by the library author and never cross the binary boundary.

This raises the bar for C#: anything that is "just a warning" in the C# world is effectively invisible to the majority of consumers. The design should bias toward errors for safety-critical signals.

Swift faces a related challenge with Apple's own frameworks. During the [SE-0458 discussion](https://forums.swift.org/t/se-0458-opt-in-strict-memory-safety-checking/77274), it was noted that Apple's Combine framework is "written in Swift, but _not_ safe (by Swift 6's standard), and unlikely to become safe nor even acquire `unsafe` annotations." Douglas Gregor acknowledged this as "a hole" in the model. When closed-source, binary-distributed frameworks don't adopt safety annotations, consumers must trust those decisions with no ability to audit or even see the warnings that were (or weren't) produced during the framework's build. The safety model's guarantees stop at the binary boundary.

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

### Beyond grep: LSP integration

While this paper focuses on grep as the baseline, a low-inference design has a compounding benefit when paired with an LSP. Grep identifies the starting points — `trusted` and `unsafe` methods — and an LSP can then build the full picture:

- **Call graphs from trust boundaries** — starting from a `trusted` method, an LSP can trace the call graph downward into `unsafe` code and upward into safe callers. The result is a complete view of the safety-critical path: which unsafe operations are being attested, and who depends on that attestation. Each node carries a function signature and file+line location.
- **Mermaid diagrams** — the same call graph data can generate visual diagrams showing the class structure around trust boundaries. A mermaid diagram rooted at a `trusted` method shows the type hierarchy, the unsafe methods it calls, and the safe public surface it presents. This is useful for code review, onboarding, and incident investigation.
- **Targeted review scoping** — an agent or reviewer can start with `grep trusted`, pick a method, and ask the LSP for its call graph. This is a fundamentally different workflow than asking an LSP to find all safety-relevant code from scratch. Grep provides the index; the LSP provides the depth.

The key insight is that grep and LSP are complementary, not competing. Grep is the entry point — fast, universal, available in every environment. The LSP is the follow-up — rich, structured, environment-dependent. A design that makes grep effective makes the entire toolchain more effective. A design that requires an LSP for the entry point loses the fast path entirely.

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

**Rust** prioritized fine-grained unsafe scoping, enabling auditors to pinpoint exact unsafe operations at the cost of making trust boundaries require inference. Rust also invested in [Miri](https://github.com/rust-lang/miri), an interpreter for Rust's MIR that detects undefined behavior at runtime. Miri is a powerful soundness verification tool — it has [found dozens of real-world bugs](https://www.ralfj.de/blog/2025/12/22/miri.html) and is integrated into CI for the standard library and many prominent crates. However, Miri addresses a different problem than this paper's thesis. It is a deep soundness review tool for code and algorithms, not a discovery or syntax tool. It operates at what might be called step three of the audit workflow: (1) discover trust boundary functions, (2) enumerate unsafe blocks and generate call graphs, (3) verify soundness of the unsafe operations. Miri excels at step three but does not help with steps one or two. A productive safety system benefits from both strong decoration (steps 1–2) and automated verification tooling (step 3). Rust chose to invest heavily in step 3 while leaving steps 1–2 to conventions and scripts.

**Swift** prioritized composability with its attribute system (`@unsafe`, `unsafe expr`), integrating safety annotations into the existing language design at the cost of multi-line signatures for auditing. Swift 6.2 shipped [strict memory safety checking](https://docs.swift.org/compiler/documentation/diagnostics/strict-memory-safety/) (`-strict-memory-safety`), a compiler mode that produces warnings for all unsafe constructs — the "auditing tool" described in the [memory safety vision](https://github.com/swiftlang/swift-evolution/blob/main/visions/memory-safety.md). This helps inventory unsafe *usage sites* but does not identify trust boundaries — functions that wrap unsafe and present a safe surface.

**C#** has an opportunity to learn from all three. The proposed `trusted` keyword borrows D's explicit trust boundary concept while preserving C#'s existing `unsafe` discoverability. The result would combine the auditing strengths of D with the unsafe-code discoverability of Rust — a combination none of the four languages currently achieves.

## Conclusion

The characteristics we want, in order of importance:

1. **Explicit marking where ambiguity exists** — trust boundaries should be explicitly annotated, not inferred from the absence of other markers.
2. **Disambiguation between outer and interior unsafe** — the distinction between "this method is unsafe to call" and "this method uses unsafe internally but is safe to call" should be syntactically clear.
3. **Signature-carried safety information** — safety annotations should appear in the method signature, ideally on a single line, to maximize grep utility.

The inference cost of a safety design is a primary metric for its practical value. Designs that require scripts, ASTs, or LSPs to answer the question "where are the trust boundaries?" impose a tax on every auditor, every agent, and every review cycle.

C# has the opportunity to lead on this metric. The `unsafe` keyword — for modern mainline languages — starts with C#. Rust and Swift evolved it to stronger utility. C# can evolve it again by pairing `unsafe` with `trusted`, closing the trust boundary gap that every language in this lineage has left open. The `trusted` keyword is a small addition with an outsized effect: it makes trust boundaries directly discoverable, produces lossless attestations under `git blame`, and enables the agent-assisted workflows that will be central to memory safety adoption at scale. The language that introduced `unsafe` can be the first to complete the model.

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

Scores are organized into two categories: **discovery** and **auditing**.

### Discovery tasks

Discovery tasks use the grep difficulty scale and are weighted by importance:

| Task | Weight | Rationale |
|------|--------|-----------|
| Find trust boundaries | 6 | The most important audit target — where human judgment attests safety |
| Find unsafe declarations | 3 | The unsafe code that trust boundaries depend on |

### Auditing clarity

Auditing clarity measures whether the design supports the review workflow once code is found. Each sub-point is binary (0 or 1):

| Sub-point | Weight | Rationale |
|-----------|--------|-----------|
| Outer/inner disambiguation | 1 | Syntactically distinct forms for caller-unsafe vs. interior-unsafe |
| Outer unsafe is caller contract | 1 | `unsafe` on a signature means callers must be in an unsafe context — not just a scope enabler |
| Inner unsafe is implementation-only | 1 | Interior `unsafe` blocks are hidden from callers — the trust boundary absorbs the obligation |

### Scoring detail

**Discovery** (max 18):

| Task | Weight | D | Rust | Swift | C# (current) | C# (proposed) |
|------|--------|---|------|-------|---------------|----------------|
| Find trust boundaries | 6 | 2 — clean grep `@trusted` | 0.5 — script | 0.5 — script | 0.5 — script | 2 — clean grep `trusted` |
| Find unsafe declarations | 3 | 0 — implicit `@system` | 2 — clean grep `unsafe fn` | 1 — `@unsafe` needs `-A 1` | 1.5 — regex to separate from blocks | 1.5 — regex to separate from blocks |
| **Discovery subtotal** | | **12** | **9** | **6** | **7.5** | **16.5** |

**Auditing clarity** (max 3):

| Sub-point | D | Rust | Swift | C# (current) | C# (proposed) |
|-----------|---|------|-------|---------------|----------------|
| Outer/inner disambiguation | 1 (`@trusted` vs `@system`) | 1 (`unsafe fn` vs `unsafe {}`) | 1 (`@unsafe` vs `unsafe expr`) | 0 (same token) | 0 (not yet decided) |
| Outer unsafe is caller contract | 0 (implicit `@system`) | 1 (`unsafe fn` requires callers to use `unsafe`) | 1 (`@unsafe` requires callers to use `unsafe`) | 0 (`unsafe` just enables a scope) | 0 (not yet decided) |
| Inner unsafe is implementation-only | 1 (`@trusted` hides interior) | 1 (`unsafe {}` is interior-only) | 1 (`unsafe expr` is interior-only) | 0 (no distinction) | 0 (not yet decided) |
| **Auditing subtotal** | **2** | **3** | **3** | **0** | **0*** |

*C# (proposed) has not committed to these design decisions. With all three: +3.

### Combined results

Total possible: 18 (discovery) + 3 (auditing) = **21**

| Language | Discovery | Auditing | Total | % | Grade |
|----------|-----------|----------|-------|---|-------|
| C# (proposed)* | 16.5 | 0 | 16.5 | 78.6% | **B+** |
| D | 12 | 2 | 14 | 66.7% | **C+** |
| Rust | 9 | 3 | 12 | 57.1% | **C** |
| Swift | 6 | 3 | 9 | 42.9% | **D+** |
| C# (current) | 7.5 | 0 | 7.5 | 35.7% | **D** |

*With auditing decisions made, C# (proposed) would score 19.5/21 = 92.9% = **A**.

### Grade boundaries

| Grade | Score range | Percentage |
|-------|-----------|------------|
| A | 18.9–21 | 90–100% |
| B | 14.7–18.8 | 70–89% |
| C | 10.5–14.6 | 50–69% |
| D | 7.4–10.4 | 35–49% |
| F | < 7.4 | < 35% |
