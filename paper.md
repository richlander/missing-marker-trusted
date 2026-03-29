# Trust Boundary Discoverability in Memory-Safe Languages

I've been reading the design notes from C#, D, Rust, and Swift design communities. Most of the focus is on how blocks of code are decorated to highlight unsafety. The unsafe spotlight is important but doesn't deliver confidence where you need it most. The aspect that truly matters is the transition from unsafe to safe code. This transition point should be the most decorated, attracting the most scrutiny. Most of the designs accept the lack of an unsafe marker as an indication that unsafe warnings/errors can be suppressed. That's not a compelling approach. It's a priority inversion that leads to a loss of critical information.

My take:

- The value of a memory safety system is enforcement and auditing, automatic or otherwise.
- The mechanistic basis is an inherently collaborative auditing system between deterministic (compiler) and semantic (human and/or agent) actors.
- The success of the system depends on the degree to which it relies on inference in the semantic domain. High inference means low clarity means low confidence.
- We can test the cost of inference using grep as a proxy.
- Agent-assisted code migration and maintenance is a core part of our vision. A low-inference design model is _the path_ to enabling that.

We've primarily been looking at Rust and Swift. I think we can learn more from D.

Relevant design specs:

- C#: [unsafe-alternative-syntax.md](https://github.com/dotnet/csharplang/blob/main/meetings/working-groups/unsafe-evolution/unsafe-alternative-syntax.md)
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

D developers can rely on grep to find `@trusted` functions. It is powerful that grep _always_ finds the functions that need to be audited first. There is no need to look at the method implementation to determine the color of the method. There is no need to rely on an AST or LSP.

### The Silverlight Security Transparency Parallel

I was thinking about how we could elevate these terms to more generic names and came up with:

- Transparent
- Safe Critical
- Security Critical

This is the same as our [security transparency model from Silverlight](https://learn.microsoft.com/previous-versions/dotnet/framework/code-access-security/security-transparent-code).

That model had three layers with clear markings throughout, making auditing straightforward. "Transparent" code could only call other transparent or "safe critical" code. "Safe critical" code was the trust boundary — it could call "security critical" code and present a transparent-safe surface. "Security critical" code had full access.

The mapping is direct:

| D | Silverlight | Role |
|---|-------------|------|
| `@safe` | Transparent | Safe subset, restricted callees |
| `@trusted` | Safe Critical | Trust boundary, attests safety to callers |
| `@system` | Security Critical | Unrestricted, unsafe operations |

The Silverlight model was abandoned when Silverlight was abandoned — not because the model was flawed. The design was sound. We already solved this problem once. The lesson is that a three-layer system with explicit trust boundaries is a recurring, validated pattern. We should reclaim it.

You can imagine asking an agent to review all "safe critical" methods. It is trivial for the agent to find them. This is a definitional characteristic of a well-designed safety model.

## Applying the Model to C#

C# is the opposite of D: unsafe code is marked and safe isn't. The difference doesn't matter for effective memory safety. That's an audience and form factor bias. It's the decorative approach for the middle layer that matters most.

If caller-unsafe methods are marked as `unsafe`, then caller-safe methods with `unsafe` blocks should be marked as `safe`. That's the same as `@trusted`. The presence of a `safe` marking provides a language-required location to place an attestation and equally operates as a grep target for code review.

The migration approach:

- A tool marks all methods with interior unsafe blocks as `unsafe`.
- Developers mark those methods as `safe` or address the errors presented by downstream callers.

This approach is lossless and grep-friendly. It preserves the three-layer model. It's actually better suited than D's approach for auditing: in D, `@safe` and `@trusted` code are easy to inventory, but in practice you want `@trusted` and `@system` code to be easy to inventory and audit. With a `safe`/`unsafe` pairing in C#, the audit focus falls naturally on the trust boundaries (`safe`) and the unsafe implementations (`unsafe`) rather than on purely safe code.

## Measuring Discoverability: The Grep Test

For JSON schemas, I use [`jq` as the arbiter of sound schema design](https://github.com/dotnet/designs/blob/main/accepted/2025/cve-schema/cve_schema.md#design-philosophy). If the `jq` queries are awkward, the schema is too, by implication. We can use grep as our proxy for sound language design.

The question: how easily can we find trust boundary code — `@trusted` in D parlance — across each language?

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

Directly discoverable. The `unsafe fn` keyword in the signature does the heavy lifting on disambiguation with `unsafe` blocks.

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

## Summary Scorecard

| Criterion | D | Rust | Swift | C# (current) | C# (proposed) |
|-----------|---|------|-------|---------------|----------------|
| Trust boundary discoverable via grep | Yes (`@trusted`) | No (needs script) | No (needs script) | No (needs script) | Yes (`safe`) |
| Unsafe declarations discoverable via grep | No (implicit `@system`) | Yes (`unsafe fn`) | Partial (`@unsafe` on separate line) | Yes (`unsafe` keyword) | Yes (`unsafe`) |
| Unsafe blocks discoverable via grep | N/A | Yes (`unsafe {}`) | N/A (`unsafe expr`) | Partial (mixed with methods) | Partial |
| Signature carries safety info | Yes | Yes | Partial (attribute) | Yes | Yes |
| Outer vs. interior unsafe disambiguated | Yes (`@trusted` vs `@system`) | Partial (`unsafe fn` vs `unsafe {}`) | Partial (`@unsafe` vs `unsafe expr`) | No | Yes (`safe` vs `unsafe`) |
| Requires AST/LSP for trust boundary audit | No | Yes | Yes | Yes | No |
| Attestation lossless under git blame | Yes | No | No | No | Yes |

Each language has strengths. D leads on trust boundary discoverability. Rust leads on unsafe code and unsafe block discoverability. Swift takes a composable attribute-based approach. C# has room for improvement across the board — and a clear path to first place on the metrics that matter most for auditing.

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

D's `@trusted` and the proposed C# `safe` keyword both produce lossless attestations. Rust's and Swift's trust boundaries do not.

## Agent-Assisted Maintenance

Agent-assisted code migration and maintenance is a core part of our vision for memory safety adoption. The inference cost of a safety model directly determines how effectively agents can participate.

A low-inference model enables agents to:

- **Inventory trust boundaries** — `grep safe` returns a complete, accurate list. No AST parsing required.
- **Scope reviews** — given a list of `safe` methods, an agent can review each one for correctness, checking that the interior `unsafe` operations are properly bounded.
- **Detect drift** — when code changes introduce new `unsafe` blocks inside a `safe` method, the attestation is already there to flag for re-review.
- **Assist migration** — when adopting the new model, an agent can identify methods with interior `unsafe` blocks and propose the appropriate `safe` or `unsafe` annotation.

High-inference models force agents to build ASTs or rely on LSPs to answer the same questions. This is not only more expensive — it's fragile. LSP availability varies across environments, AST parsers must track language evolution, and the results are harder to validate.

The grep test is not just a theoretical metric. It's a practical measure of how accessible a safety model is to the tools that will increasingly be responsible for maintaining it.

## Developing the C# Proposal

### The `safe` keyword

If caller-unsafe methods are marked `unsafe`, then caller-safe methods with interior `unsafe` blocks should be marked `safe`. This creates the three-layer model:

| Layer | C# syntax | Meaning |
|-------|-----------|---------|
| Safe | (unmarked) | No unsafe operations, can only call safe and `safe` methods |
| Trust boundary | `safe` | Contains `unsafe` blocks, attests safety to callers |
| Unsafe | `unsafe` | Caller-unsafe, obligations must be discharged by caller |

### Interaction with `unsafe class`

Today, members of an `unsafe class` are implicitly unsafe. Under the proposed model, methods inside an `unsafe class` that present a safe surface to callers should still use the `safe` keyword. The `unsafe class` declaration establishes that the type _works with_ unsafe constructs, but individual methods that attest safety to their callers should say so explicitly. This eliminates the "implicit unsafe type" audit gap.

### Lambdas and local functions

Interior lambdas and local functions that use `unsafe` blocks within a `safe` method are covered by the enclosing method's attestation. The `safe` marking on the outer method is the attestation that all interior unsafe operations — including those in lambdas — are correctly bounded. This matches D's model, where `@trusted` covers the entire function body.

### Breaking changes

Adding `safe` as a new keyword is not inherently breaking — it's an additive language feature. The migration path:

1. **Phase 1: Analyzer** — a diagnostic warns on methods with interior `unsafe` blocks that lack a `safe` or `unsafe` modifier. This is advisory and non-breaking.
2. **Phase 2: Language feature** — `safe` becomes a recognized modifier. Opt-in via project property or `LangVersion`.
3. **Phase 3: Default-on** — in a future `LangVersion`, the analyzer diagnostic becomes an error. Methods with interior `unsafe` blocks must be annotated.

This phased approach avoids a cliff and gives the ecosystem time to adopt.

### Migration tooling

The migration tool should:

1. Scan for all methods with interior `unsafe` blocks (similar to what [`scripts/find-csharp-trust-boundaries.sh`](scripts/find-csharp-trust-boundaries.sh) does today).
2. Mark those methods as `unsafe` (the conservative default — this is correct and safe).
3. Developers then triage: methods that present a safe surface to callers are changed from `unsafe` to `safe`. Methods that are genuinely caller-unsafe remain `unsafe`.

The tool should also handle `unsafe class` members, flagging each method for individual annotation.

## Design Tradeoffs

Each language in this comparison made deliberate design choices. None of the designs are wrong — they optimize for different concerns:

**D** prioritized explicit trust boundaries with `@trusted`, enabling grep-based auditing at the cost of making unsafe code (`@system`) implicit and invisible to grep.

**Rust** prioritized fine-grained unsafe scoping, enabling auditors to pinpoint exact unsafe operations at the cost of making trust boundaries require inference.

**Swift** prioritized composability with its attribute system (`@unsafe`, `unsafe expr`), integrating safety annotations into the existing language design at the cost of multi-line signatures for auditing.

**C#** has an opportunity to learn from all three. The proposed `safe` keyword borrows D's explicit trust boundary concept while preserving C#'s existing `unsafe` discoverability. The result would combine the auditing strengths of D with the unsafe-code discoverability of Rust — a combination none of the four languages currently achieves.

## Conclusion

The characteristics we want, in order of importance:

1. **Explicit marking where ambiguity exists** — trust boundaries should be explicitly annotated, not inferred from the absence of other markers.
2. **Disambiguation between outer and interior unsafe** — the distinction between "this method is unsafe to call" and "this method uses unsafe internally but is safe to call" should be syntactically clear.
3. **Signature-carried safety information** — safety annotations should appear in the method signature, ideally on a single line, to maximize grep utility.

The inference cost of a safety design is a primary metric for its practical value. Designs that require scripts, ASTs, or LSPs to answer the question "where are the trust boundaries?" impose a tax on every auditor, every agent, and every review cycle.

C# has the opportunity to lead on this metric. The `safe` keyword is a small addition with an outsized effect: it makes trust boundaries directly discoverable, produces lossless attestations under `git blame`, and enables the agent-assisted workflows that will be central to memory safety adoption at scale.
