# Trust Boundary Discoverability in Memory-Safe Languages

I've been reading the excellent design notes from C#, D, Rust, and Swift design communities. Most of the focus is on how functions and interior blocks of code are decorated to highlight unsafety. The unsafe spotlight is clearly important but doesn't deliver confidence where it is most needed, the transition from unsafe to safe code. There's a term for that: "trust boundary". Our threat-modeling tradition emphasizes focus on that boundary above all else. Trusted boundary functions (TBF) should attract the  most scrutiny with the strongest gates around them, however, the designs I've read do not bare that out. It is reasonable to conclude that there is a gap between our threat modeling tradition and language design (across much of the industry). We're in the middle of designing C# memory safety v2. It's the moment to bridge this divide.

Most of the language designs accept the lack of an unsafe marker as an indication that unsafe warnings/errors can be suppressed. We cannot know if the marker was deleted by accident or as a meaningful removal. In effect, these designs are storing a ternary value with a single bit. It's not clear why Rust and Swift chose that approach. Current C# stores this information in zero bits, which is even worse. We have the opportunity to resolve this critical language design point with new versions of C#.

Let's look at our vision for memory safety v2:

> Large Language Models (LLMs) add a new dimension to memory safety. Safe code is well-suited to generative AI. It is easier to understand, review, and modify with confidence. We recommend that developers configure their AI systems and build tools to permit only safe code. In the new AI paradigm, the compiler and analyzers become the final authority on safety.

Source: https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/memory-safety.md

That's a compelling vision. Our ambition is that agents generate most C# code going forward and that they can drive migration to our new memory safety model over the next several years. The question is what "final authority on safety" means. It is relied on in the text for a heavy lift. It's describing a model that is lossless in intent and producing errors where the code is found to be wrong or subject to ambiguity. Removing `unsafe` (establishing the aforementioned absence) is an example of ambiguity. Lossy designs are an invitation for a visit from Jia Tan ([xz fame](https://en.wikipedia.org/wiki/XZ_Utils_backdoor)).

My overall take on a memory safety system:

- The value is enforcement and auditing, both automatic and manual. It is inherently a collaboration between a deterministic tool (compiler or analyzer) and a semantic mind (human or agent).
- It should increase confidence while reducing (or at least focusing) manual effort, by simplying workflows and limiting the search space.
- Agent-assisted code migration and maintenance is a core part of our vision. We need to cater to that with a specific plan on how to deliver on it.
- The success (and cost) of the system depends on the degree to which it relies on inference in the semantic domain. High inference means low clarity means low confidence.
- We can test the cost of inference using grep as a proxy.

We've primarily been looking at Rust and Swift. I think we can learn more from D. We're in the enviable position where we can pick amount the best ideas of the last one to two decades. One can argue that C# established this domain, of safe languages with first-class FFI. The spoiler is that the optimal answer is well within reach, with just a few tweaks to our current plan. C# can establish a strong memory safety model for the 2030s, which we truly expect will be the decade of agents.

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

This approach is presented as an lossless safety model, enabling  high-productivity and high-confidence software auditing workflows.

All functions must be sound at all three layers. The `@system` code needs to written to be correct and safe after safety obligations are discharaged bya `@trusted` caller. Sound `@system` and `@trusted` code is the responsibility of the developer, not the compiler. That's true of Rust too.

Note: The opt-in-to-safe approach is sensible for a systems language. That may seem awkward for C#-oriented readers.

#### Auditing workflow

The D community's guidance confirms that `@trusted` is where the review budget goes. The official D blog [states](https://dlang.org/blog/2016/09/28/how-to-write-trusted-code-in-d/): "`@trusted` code is never mechanically checked for safety, so every line must be reviewed for correctness. For this reason, it's always advisable to keep the code that is `@trusted` as small as possible." Ate Eskola [further emphasizes this idea](https://dlang.org/blog/2023/01/05/memory-safety-in-a-systems-programming-language-part-3/): "`@trusted` functions...need to be just as carefully reviewed, if not more so, as `@system` functions" and "it's many times more important than usual to keep `@system` and `@trusted` functions small and simple to review." The principle is clear: `@safe` code doesn't need manual review — the compiler verifies it. The audit focus narrows to `@trusted` and `@system`.

D developers can rely on grep to find `@trusted` functions. It is powerful that grep _always_ finds the functions that need to be audited first. There is no need to look at the method implementation to determine the color of the method, or rely on complex tools that may or may not be available.

### The Silverlight Security Transparency Parallel

I was thinking about how we could elevate these terms to more generic names.

Flashback terms:

- Transparent
- Safe Critical
- Security Critical

These are from our [security transparency model from Silverlight](https://learn.microsoft.com/previous-versions/dotnet/framework/code-access-security/security-transparent-code). I realized that D recreated the same thing, frankly with better names.

That Silverlight model had three layers with clear markings throughout, making auditing straightforward. "Transparent" code could only call other transparent or "safe critical" code. "Safe critical" and "security critical" code had unencumbered access to privileged operations — the difference was caller contract, not capability. "Safe critical" code was the trust boundary: it could be called by transparent code and took on the obligation of validating inputs and presenting a safe surface. "Security critical" code not be called from transparent code.

The obvious mapping:

| D | Silverlight | Role |
|---|-------------|------|
| `@safe` | Transparent | Safe subset, restricted callees |
| `@trusted` | Safe Critical | Trust boundary, attests safety to callers |
| `@system` | Security Critical | Unrestricted, unsafe operations |

The Silverlight model was abandoned when Silverlight was abandoned — not because the model was flawed. The design was sound. We already solved this problem once. The lesson is that a three-layer system with explicit trust boundaries is a recurring, validated pattern. We should reclaim it.

You can imagine asking an agent to review all "safe critical" methods. It is trivial for the agent to find them. This is a definitional characteristic of a well-designed safety model.

## The case for TBFs as `safe`

My initial thinking -- in C# parlance -- was to mark TBFs `safe` since that's the opposite of `unsafe` and the intent is to provide a safe wrapper. However, these functions are in no way the opposite of unsafe. They contain and rely on unsafe code with no help from the compiler to offer a safe fascade.

TBFs handle unsafe currency and must do so soundly. They only differ in that they have the special character that they are considered safe to call by developers who typically have no basis or intent of applying safety scrutiny. TBFs are unsafe code that do double duty. It's that single bit and what it represents again.

Another view is that the compiler can make a single statement about `unsafe` code: "I've got no earthly idea what is going on!". And so the marker fits. The same statement equally applies to TBFs. The concept of `safe` should only be applied when the compiler can make a  guarantee: "I know exactly what is going on and it 100% aligns with my safety model."

## Applying the Model to C\#

C# has the opposite model as D: unsafe code is marked and safe isn't. The difference is an audience and form factor bias. It doesn't matter for effective memory safety. The decorative approach for the middle layer is what matters most.

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

C# should adopt a `trusted` keyword to describe transition methods with `unsafe` blocks, making them safe-caller-callable. That matches D's `@trusted`. The presence of a `trusted` marker provides a location to place a language-enforced attestation and operates as a grep target for code review.

Another benefit of `trusted` as opposed to `safe` is that we can say that all unmarked methods are implicitly marked as `safe` and no other methods can take on that marking. Complete separation of kind, the same as D.

We've been talking a fair bit about migration. `trusted` seems to fix that.

- A tool marks all methods with interior unsafe blocks as `unsafe`.
- Developers either mark `unsafe` methods as `trusted` or address errors presented by downstream callers.
- It is easy to track transitions between `unsafe` and `trusted` with git, less so when one side of the diff is an empty string.

This approach is lossless and grep-friendly. It preserves the three-layer model. It's actually better suited for auditing than D's approach: in D, `@safe` and `@trusted` code are easy to inventory, but in practice you want `@trusted` and `@system` code to be easy to discover and audit. With a `trusted`/`unsafe` pairing in C#, the audit focus falls naturally on the trust boundary (`trusted`) and the unsafe implementations (`unsafe`) rather than on purely safe code. To a large degree, safe code doesn't matter.

## Measuring Discoverability: The Grep Test

Memory safety across all languages inherently relies on human and agent auditing. The compiler verifies safe code by construction — that's the value proposition. But `trusted` and `unsafe` code cannot be verified by the compiler. They require semantic review: a human or agent must confirm that the unsafe operations are correctly bounded and that the trust boundary's safety attestation is valid. The audit value of methods is therefore inherently asymmetric. Safe code doesn't need review. Trust boundary functions need the most review. Unsafe functions need review too, but the trust boundary is where the claim is made.

Auditing can be thought of as a subset of threat modeling. The search space of memory safety auditing is the divide between defined and undefined behavior — the same search space as vulnerabilities. It's two different views -- one defensive the other offensive -- on the same activity. Threat modeling asks "where can an attacker violate assumptions?Memory safety auditing asks "where can code violate safety invariants?" Trust boundary functions are where someone claims that undefined behavior has been correctly bounded. If that claim is wrong, the result is both a bug and a potential vulnerability.

There is a structural reason trust boundaries matter more than unsafe declarations for discovery: trust boundaries are the _roots of the audit graph_. A trust boundary function contains unsafe code in its body — the unsafe calls are the leaves. If you can find the roots, you can find the leaves by reading the body or grepping within the file. But if you can only find the leaves (unsafe functions and blocks), you cannot work upward to find which enclosing function attested their safety.

We can use grep as our proxy for sound language design, in the same way I've used [`jq` as the arbiter of sound schema design](https://github.com/dotnet/designs/blob/main/accepted/2025/cve-schema/cve_schema.md#design-philosophy). If a safety-relevant question can't be answered by grep, the language design has failed at self-description.

### Why grep?

Code review — the primary context where safety-critical code is evaluated — operates at the grep level. When reviewing a pull request in GitHub or any diff view, there is no sophisticated language-specific tooling. The reviewer's tools are their eyes and Ctrl+F. Source code should stand on its own for safety review. An agent is more likely to use grep.

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

**Finding unsafe code** — `@system` functions are implicit (undecorated), so grep alone cannot find them. This is a significant gap in D's discoverability model — the largest category of code (default `@system`) is invisible to grep. As mentioned earlier, `@system` functions are disoverable from `@trusted` functions.

### Rust

Source: [rust-lang/rust](https://github.com/rust-lang/rust) (`library/`)

**Finding trust boundaries** — Rust has no explicit marker for safe-caller-callable functions that contain `unsafe` blocks. Discovering them requires parsing function bodies. See [`scripts/find-rust-trust-boundaries.sh`](scripts/find-rust-trust-boundaries.sh) — an 80-line awk script that walks brace depth to approximate this:

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

Perfectly workable after you realize the pattern. The Rust one-line syntax (`unsafe fn`) is more ergonomic, however.

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

The compiler audit tool and grep serve the same side of the ledger: inventorying unsafe code. Neither answers the trust boundary question.

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

We score each language on three dimensions — **discovery** (can you find the code that needs review?), **auditing clarity** (does the design support the review workflow?), and **enforcement** (are grep results backed by compiler guarantees?) — with demerits for non-standard terminology, duplicate marking, and audit-based models. The grading methodology is detailed in [Appendix: Scoring Methodology](#appendix-scoring-methodology).

| Language | Grade | Summary |
|----------|-------|---------|
| C# (optimal) | **A** | `trusted` keyword + `unsafe` as caller contract + interior `unsafe` as implementation-only + enforcement via errors. Full marks, no demerits. |
| D | **B** | Trust boundaries (`@trusted`) are perfectly discoverable with enforcement. Unsafe code (`@system`) is implicit and invisible to grep. No demerits. |
| Rust | **C** | Unsafe declarations (`unsafe fn`) are perfectly discoverable with full auditing design and enforcement. Trust boundaries require an 80-line awk script. No demerits. |
| C# + `unsafe` keyword | **D+** | The [runtime team proposal](https://github.com/dotnet/csharplang/pull/10058): `unsafe` on a method means caller-unsafe. Full auditing design, enforcement via errors, no demerits. No trust boundary marker. |
| Swift | **D** | Unsafe declarations (`@unsafe`) require `-A 1` context. Trust boundaries require a script. Full auditing design but audit-based (warnings, not errors) — demerit for source-distributed non-enforcement. |
| C# + `RequiresUnsafe` | **F** | The [language team proposal](https://github.com/dotnet/csharplang/blob/main/proposals/unsafe-evolution.md): `[RequiresUnsafe]` attribute for caller-unsafe. Four demerits: `unsafe` mixes methods and blocks, `RequiresUnsafe` mixes true and false, non-standard terminology, and duplicate marking. No trust boundary marker. |
| C# (current) | **F** | Unsafe declarations are discoverable but ambiguous. Trust boundaries require a script. No auditing design. Four demerits: `unsafe` mixes methods and blocks, audit-based model with binary distribution (×3). |

The two active C# proposals — `unsafe` keyword and `[RequiresUnsafe]` — land at D+ and F respectively without `trusted`. The `trusted` keyword is the differentiator that separates C# (optimal) from the pack — it's worth 9 points. The `unsafe` vs `RequiresUnsafe` debate is worth 4 points in demerits, driven by observable grep workflow problems rather than syntax preference.

C# (optimal) represents the `unsafe` keyword proposal plus `trusted`. The distance from **F** to **A** is one keyword (`trusted`) and two semantic commitments (caller contract, implementation-only interior). All have prior art — D has the keyword, Rust and Swift have the semantics.

## The `unsafe` Keyword Lineage and Trust Boundary Gap

The trust boundary gap is not for lack of discussion. Rust has engaged with it through [RFC 2585](https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html) (separating "unsafe to call" from "body does unsafe things"), [RFC 3484](https://rust-lang.github.io/rfcs/3484-unsafe-extern-blocks.html) (introducing `safe` as a contextual keyword in extern blocks — someone [asked](https://github.com/rust-lang/rfcs/pull/3484) "why not `trusted`?"), [RFC 3768](https://github.com/rust-lang/rfcs/pull/3768) (safe blocks, closed), and [documentation conventions](https://internals.rust-lang.org/t/pre-rfc-rust-safety-standard/23963) (`// SAFETY:` comments). Swift's SE-0458 marks unsafe code but not trust boundaries. D solved it at the language level with `@trusted` from the start.

The `unsafe` keyword — for modern mainline languages — starts with C#. C# 1.0 (2001) introduced it as a compiler-enforced keyword, the first mainstream language to give the safe/unsafe boundary a syntactic marker. Rust (2015) extended it: `unsafe fn` as a caller contract, `unsafe {}` as scoped interior unsafe. Swift (2024–2025) went further with `@unsafe` as an attribute and `unsafe` as an expression prefix.

But both Rust and Swift evolved the _unsafe_ side without addressing the _attestation_ side. D is the only language with a trust boundary marker, but it built its model independently. C# introduced `unsafe`. Rust and Swift evolved it. C# can evolve it again — pairing `unsafe` with `trusted` to close the gap. The language that started the keyword can be the first to complete the model.

## Lossless Attestations

"Lossless" means every safety attestation is recorded in code and source control. There is never a compiler-accepted state where information is lost. `git blame` finds who attested safety and when. `grep` inventories every attestation. Code review tools can flag changes to attested methods for re-review.

In "absence means safe" designs, there is no attestation to find. An auditor cannot distinguish "reviewed and confirmed safe" from "never reviewed." When a safety-critical bug is found, `git blame` answers the question in a lossless system. In an inference-based system, there's nothing to find.

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

The [follow-up PR](https://github.com/dotnet/csharplang/pull/10058) states: "High-confidence AI-assisted automation of the migration process flow is a part of the feature design." The inference cost of the safety model directly determines how effectively agents can participate.

A low-inference model enables agents to: inventory trust boundaries (`grep trusted` — complete, no AST required), scope reviews (check each `trusted` method's interior `unsafe` for correctness), detect drift (new `unsafe` blocks in a `trusted` method are flagged for re-review), and assist migration (propose `trusted` or `unsafe` annotations for methods with interior unsafe blocks).

High-inference models force agents to build ASTs or rely on LSPs. This is more expensive, fragile across environments, and harder to validate.

### Beyond grep: LSP integration

Grep and LSP are complementary. Grep identifies the starting points — `trusted` and `unsafe` methods. An LSP builds the full picture: call graphs from trust boundaries (which unsafe operations are attested, who depends on that attestation), mermaid diagrams showing type hierarchy around trust boundaries, and targeted review scoping (start with `grep trusted`, ask the LSP for the call graph).

Grep is the entry point — fast, universal, available in every environment. The LSP is the follow-up — rich, structured, environment-dependent. A design that makes grep effective makes the entire toolchain more effective.

### The canonical audit workflow

The complete safety audit has two steps: (1) discover and inspect trust boundaries, (2) discover and inspect the unsafe code they depend on. No single language besides D handles step 1, and D can't do step 2. The workflow below uses real code from real repos to demonstrate both steps, with D providing step 1 and Rust providing step 2.

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

**The gap:** D gives you step 1 but not step 2 — `@system` code is implicit, so the auditor can't grep for the unsafe functions that `uninitializedArray` depends on. Rust gives you step 2 but not step 1 — there's no way to grep for which safe functions wrap those unsafe operations. Each language provides half the workflow.

**C# (optimal)** would provide both steps in a single codebase:

```bash
$ rg "trusted" --type cs                    # Step 1: find trust boundaries
$ rg "unsafe" --type cs -A 20               # Step 2: inspect unsafe code
```

The first command finds every trust boundary. The second finds every unsafe operation with body context. Together they give the auditor the complete safety-critical picture: who attested what, and what unsafe operations they're attesting to. No other language in this comparison achieves both.

## Developing the C# Proposal

A [follow-up PR](https://github.com/dotnet/csharplang/pull/10058) proposes going back to `unsafe`/`safe` keywords, motivated by practical experience annotating dotnet/runtime: 97% of methods with pointers should be `RequiresUnsafe`, making the attribute approach high-churn for little benefit. The PR also introduces `safe` for extern methods that wrap safe native code (e.g., a P/Invoke into a safe Rust function). That PR's goals align with this paper:

> 1) clear, simple rules on which methods are caller unsafe vs. use unsafe
> 2) users annotate their code based on the rules of unsafev2, not unsafev1
> 3) annotation is easily auditable, meaning we can see whether a given project has aligned their code with unsafev2
> 4) support for multitargeting with unsafev1-only TFMs
>
> This feature will introduce compilation errors in existing unsafe code when opted into. High-confidence AI-assisted automation of the migration process flow is a part of the feature design.

The PR uses `safe` as the keyword. This paper argues for `trusted` instead: these methods are not safe in the compiler-verified sense — they are unsafe code that attests safety to callers. `trusted` avoids that confusion and aligns with D's `@trusted` and our Silverlight "safe critical" precedent. `[RequiresUnsafe(false)]` would be model-equivalent but is a double negative — it negates a property rather than asserting one. `rg "trusted"` reads as intent; `rg "RequiresUnsafe(false)"` reads as an implementation detail.

### The `trusted` keyword

| Layer | C# syntax | Meaning |
|-------|-----------|---------|
| Safe | (unmarked) | No unsafe operations, can only call safe and `trusted` methods |
| Trust boundary | `trusted` | Contains `unsafe` blocks, attests safety to callers |
| Unsafe | `unsafe` | Caller-unsafe, obligations must be discharged by caller |

**Design details:** Methods inside an `unsafe class` that present a safe surface should still use `trusted` explicitly — eliminating the "implicit unsafe type" audit gap. Interior lambdas and local functions are covered by the enclosing `trusted` method's attestation, matching D's `@trusted` model.

**Migration path:** `trusted` is an additive contextual keyword — not inherently breaking. Phase 1: analyzer warns on unannotated trust boundaries. Phase 2: `trusted` becomes a recognized modifier, opt-in via `LangVersion`. Phase 3: the warning becomes an error. Migration tooling scans for methods with interior `unsafe` blocks, marks them `unsafe` conservatively, and developers triage to `trusted` where appropriate.

## Design Tradeoffs

Each language made deliberate choices. **D** prioritized trust boundary discoverability (`@trusted`) at the cost of invisible unsafe code. **Rust** prioritized unsafe scoping and invested in [Miri](https://github.com/rust-lang/miri) for soundness verification (step 3 of the audit workflow) while leaving trust boundary discovery (step 1) to conventions. **Swift** prioritized composability and shipped [strict memory safety checking](https://docs.swift.org/compiler/documentation/diagnostics/strict-memory-safety/) as a compiler audit mode — but it inventories unsafe usage sites, not trust boundaries. **C#** can combine D's trust boundary discoverability with Rust's unsafe-code discoverability — a combination none of the four currently achieves.

## Conclusion

The inference cost of a safety design is a primary metric for its practical value. Designs that require scripts, ASTs, or LSPs to answer "where are the trust boundaries?" impose a tax on every auditor, every agent, and every review cycle.

C# introduced `unsafe`. Rust and Swift evolved it. C# can evolve it again by pairing `unsafe` with `trusted` — closing the trust boundary gap that every language in this lineage has left open. The `trusted` keyword makes trust boundaries directly discoverable, produces lossless attestations under `git blame`, and enables the agent-assisted workflows that will be central to memory safety adoption at scale. The language that introduced `unsafe` can be the first to complete the model.

## Appendix: Scoring Methodology

### Grep difficulty scale

Each discovery task is scored on a 0–2 scale based on the grep difficulty required:

| Method | Score | Rationale |
|--------|-------|-----------|
| Clean grep | 2 | One command, exact results, no false positives |
| Grep with regex | 1.5 | One command, requires pattern knowledge, may have edge cases |
| Grep with context flag (`-A 1`) | 1 | One command, results require visual pairing across lines |
| Script (awk/parser) | 0.5 | Approximation with known false positives, not authoritative |
| Not possible / invisible | 0 | Requires AST/LSP or information doesn't exist in the source |

### Metric descriptions

Scores are organized into two categories: **positive metrics** (discovery capability and auditing design) and **demerits** (observable problems in the grep workflow). Positive metrics measure how well the design supports auditing. Demerits measure friction an auditor or agent encounters when interpreting grep results. Each demerit includes an observable test — a concrete demonstration that can be performed in a terminal.

#### Discovery: Find trust boundaries (weight: 6)

Trust boundary functions are where human judgment meets compiler enforcement. A developer has reviewed the interior unsafe code and attests that the function is safe to call. These are the highest-value audit targets — if a trust boundary attestation is wrong, the safe code that depends on it is silently unsound.

The weight of 6 reflects this paper's central thesis: the trust boundary is the most important thing to find. If an auditor or agent has time to review only one category of code, it should be the trust boundaries.

#### Discovery: Find unsafe declarations (weight: 3)

Unsafe declarations — functions that are unsafe to call — are the second audit priority. They contain the operations that trust boundaries depend on. An auditor reviewing a trust boundary needs to understand what unsafe functions it calls and what contracts those functions require.

The weight of 3 reflects that unsafe code is important but secondary to the trust boundary. You need to find it for the full audit picture, but knowing where the attestations are matters more than knowing where the raw unsafe operations are.

#### Auditing design: Outer unsafe is caller contract (+1)

When `unsafe` on a function signature means "callers must be in an unsafe context to call this function," the annotation carries a semantic contract. The compiler enforces that callers acknowledge the unsafety. This is stronger than `unsafe` merely enabling a scope — it propagates responsibility upward through the call chain.

This matters because it makes the call graph safety-aware. An auditor can trace from a trust boundary to its unsafe callees and know that each callee's contract is compiler-enforced.

#### Auditing design: Inner unsafe is implementation-only (+1)

When interior `unsafe` blocks are implementation-only — hidden from callers, absorbed by the enclosing trust boundary — the trust boundary's attestation is the single point of responsibility. Callers don't need to know about or account for the interior unsafe operations.

This matters for review scoping. If interior unsafe leaks to callers, every caller must also be reviewed. If it's implementation-only, only the trust boundary needs review.

#### Demerit: Grep ambiguity (-1 each)

A grep ambiguity demerit applies when a single grep pattern returns results with mixed safety roles — the auditor cannot determine from the grep output alone what kind of hit they're looking at. Each distinct source of ambiguity is an independent -1 demerit. Ambiguity is additive in the same way that the grep difficulty scale is — each source compounds the auditor's inference burden.

**`unsafe` mixes methods and blocks (-1).** Observable: run `rg "unsafe"` on a C# codebase. The results include `unsafe void M()` (method signatures), `unsafe { }` (blocks), `unsafe class` (type declarations), and `unsafe` fields. The auditor cannot determine the safety role of a hit without reading the surrounding context. Applies to: C# (current), C# + `RequiresUnsafe`.

**`RequiresUnsafe` mixes true and false (-1).** Observable: in a codebase with both `[RequiresUnsafe]` (caller-unsafe) and `[RequiresUnsafe(false)]` (trust boundary), run `rg "RequiresUnsafe"`. Both roles appear in the same result set. To separate them, the auditor must use exclusion logic (`grep -v "false"`) and account for the bare `[RequiresUnsafe]` (default true) vs explicit `[RequiresUnsafe(true)]` — a ternary value encoded in a single attribute name. Applies to: C# + `RequiresUnsafe`.

#### Demerit: Audit-based model (varies)

An enforcement-based model (errors, not warnings) guarantees that grep results are complete: if the code compiles, the annotations are correct and present. An audit-based model (warnings) means annotations are aspirational — the code compiles regardless of whether the migration is complete. Grep results in an audit-based model reflect migration progress, not final state.

Observable: build [apple/swift-collections](https://github.com/apple/swift-collections) with `-strict-memory-safety`. The compiler produces 12,526 warnings across 319 files. Grep for explicit `unsafe` expressions finds 158 hits — 11% of what the compiler finds. The remaining 89% are unmarked because the migration is incomplete. The code compiles and ships regardless.

The demerit is scaled by distribution model. For source-distributed languages, consumers can run the compiler themselves and see warnings — the demerit is -1. For binary-distributed languages, warnings are invisible to consumers (they receive compiled assemblies, not source) — the demerit is -3. This reflects that errors are the only safety signal that crosses the binary boundary.

#### Demerit: Non-standard terminology (-1)

Observable: compare `unsafe fn` (Rust), `@unsafe` (Swift), `unsafe` (C#, D) with `[RequiresUnsafe]`. The first four use a term shared across every language in this comparison. `[RequiresUnsafe]` is a C#-only attribute name. `[RequiresUnsafe(false)]` is a double negative — the attribute name says "requires unsafe" and the parameter says "no it doesn't." No other language platform uses this pattern. An auditor crossing language boundaries must learn a C#-specific concept that maps to a universal one.

#### Demerit: Duplicate marking (-1)

Observable: under the `[RequiresUnsafe]` attribute approach, run `rg "RequiresUnsafe.*unsafe\|unsafe.*RequiresUnsafe"` on a C# codebase with pointer-bearing methods. Methods carry both `unsafe` (legacy scope enabler) and `[RequiresUnsafe]` (new caller-unsafe semantics): `[RequiresUnsafe] unsafe void M(int* p)`. As noted in the [follow-up PR](https://github.com/dotnet/csharplang/pull/10058): "Having both `RequiresUnsafe` and `unsafe` on a method is confusing. Without consulting the language specification, these terms appear to be duplicated." In dotnet/runtime, 97% of methods with pointers would require this dual annotation. The auditor must understand both annotations together to determine the method's safety role.

### Scoring detail

**Discovery** (max 18):

| Task | Weight | D | Rust | Swift | C# (current) | C# + `unsafe` keyword | C# + `RequiresUnsafe` | C# (optimal) |
|------|--------|---|------|-------|---------------|------------------------|------------------------|---------------|
| Find trust boundaries | 6 | 2 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 2 |
| Find unsafe declarations | 3 | 0 | 2 | 1 | 1.5 | 1.5 | 1.5 | 1.5 |
| **Discovery subtotal** | | **12** | **9** | **6** | **7.5** | **7.5** | **7.5** | **16.5** |

**Auditing design** (max 2):

| Sub-point | D | Rust | Swift | C# (current) | C# + `unsafe` keyword | C# + `RequiresUnsafe` | C# (optimal) |
|-----------|---|------|-------|---------------|------------------------|------------------------|---------------|
| Outer unsafe is caller contract | 1 | 1 | 1 | 0 | 1 | 1 | 1 |
| Inner unsafe is implementation-only | 1 | 1 | 1 | 0 | 1 | 1 | 1 |
| **Auditing subtotal** | **2** | **2** | **2** | **0** | **2** | **2** | **2** |

**Demerits:**

| Condition | D | Rust | Swift | C# (current) | C# + `unsafe` keyword | C# + `RequiresUnsafe` | C# (optimal) |
|-----------|---|------|-------|---------------|------------------------|------------------------|---------------|
| `unsafe` mixes methods and blocks | — | — | — | -1 | — | -1 | — |
| `RequiresUnsafe` mixes true and false | — | — | — | — | — | -1 | — |
| Audit-based, source-delivered | — | — | -1 | — | — | — | — |
| Audit-based, binary-delivered | — | — | — | -3 | — | — | — |
| Non-standard terminology | — | — | — | — | — | -1 | — |
| Duplicate marking | — | — | — | — | — | -1 | — |
| **Total demerits** | **0** | **0** | **-1** | **-4** | **0** | **-4** | **0** |

### Combined results

Base possible: 18 (discovery) + 2 (auditing) = **20**

| Language | Discovery | Auditing | Demerits | Total | % | Grade |
|----------|-----------|----------|----------|-------|---|-------|
| C# (optimal) | 16.5 | 2 | 0 | 18.5 | 92.5% | **A** |
| D | 12 | 2 | 0 | 14 | 70.0% | **B** |
| Rust | 9 | 2 | 0 | 11 | 55.0% | **C** |
| C# + `unsafe` keyword | 7.5 | 2 | 0 | 9.5 | 47.5% | **D+** |
| Swift | 6 | 2 | -1 | 7 | 35.0% | **D** |
| C# + `RequiresUnsafe` | 7.5 | 2 | -4 | 5.5 | 27.5% | **F** |
| C# (current) | 7.5 | 0 | -4 | 3.5 | 17.5% | **F** |

### Grade boundaries

| Grade | Percentage |
|-------|------------|
| A | 90–100% |
| B | 70–89% |
| C | 50–69% |
| D | 30–49% |
| F | < 30% |

### Roadmap

| Step | Change | Grade |
|------|--------|-------|
| C# (current) | — | **F** |
| + `unsafe` keyword (caller contract) | Auditing design, enforcement, no demerits | **D+** |
| + `trusted` keyword | Trust boundaries become grep-discoverable | **A** |
