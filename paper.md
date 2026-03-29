# Safety only exists where grep can find it

I've been reading the design notes from C#, D, Rust, and Swift design communities. Most of the focus is on how blocks of code are decorated to put focus on unsafety. The unsafe spotlight is important but doesn't deliver confidence where you need it most. There is only one aspect that truly matters, which is the transition from unsafe to safe code. This transition point should be the most decorated, leading to the most scrutiny. Most of the designs accept the lack of an unsafe marker as an indication that unsafe warnings/errors can be suppressed. That's not a compelling approach. It's a strange priority inversion that leads to a loss of critical information.

My take:

- The value of a memory safety system is enforcement and auditing, automatic or otherwise.
- The mechanistic basis is an inherently collaborative auditing system between deterministic (compiler) and semantic (human and/or agent) actors.
- The success of the system is the degree to which it relies on inference in the semantic domain. High inference == low clarity == low confidence.
- We can test the cost of inference using grep as a proxy.
- Agent-assisted code migration and maintenance (of memory safety v2 code) is a core part of our vision. A low inference design model is _the path_ to enabling that.

We've primarily been looking at Rust and Swift. I think we can learn more from D.

Relevant design specs:

- C#: https://github.com/dotnet/csharplang/blob/main/meetings/working-groups/unsafe-evolution/unsafe-alternative-syntax.md
- D: https://dlang.org/spec/memory-safe-d.html
- Rust: https://rust-lang.github.io/rfcs/2585-unsafe-block-in-unsafe-fn.html
- Swift: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md

## D Memory Safety

> D is a system programming language. D has a memory-safe subset.

Source: [D Tour: Memory] (https://tour.dlang.org/tour/en/basics/memory)

### Safety tiers

D has three safety tiers:

- `@safe`
- `@trusted`
- `@system`

That's a pyramid. Let's reason about it starting from the bottom:

- `@system` functions are assumed to be unsafe. Undecorated functions are implictly `@system`.
- `@trusted` functions can call `@system` or any other functions and present a caller-safe surface.
- `@safe` functions live in the beautiful safe world unemcumbered by nasty safety concerns and are only able to call `@safe` and `@trusted` functions in trade.

All functions must be sound. The scariest `@system` code needs to be correct and to be safe to use after obligations and discharged by a `@trusted` caller. Sound `@system` and `@trusted` code is the responibility of the developer not the compiler. That's true of Rust, too.

The opt-into-safe approach seems sensible for a systems language.

### Auditing

Experienced D developers reviewing a new codebase for safety concerns presuably search the codebase for `@trusted` functions as the starting point. Safe code doesn't need to be reviewed, while `@system` code can be best understood by starting from the safe surface area and the assumptions that it makes. `@trusted` is the most fundamental "safe surface area".

One can imagine a query that finds clusters of `@trusted` and `@system` code that need to be reviewed together.

D developers can rely on grep to find `@trusted` functions. It's _very powerful_ that grep _always_ hit the functions that need to audited first. There is no need to look at the method implementation to determine the color of the method. There is no need to rely on an AST or LSP.

### Prior art

I was thinking about how we could elevate these terms to more generic names.

I came up with:

- Transparent
- Safe Critical
- Security Critical

Hey, this is the same as our abandoned [security model from Silverlight](https://learn.microsoft.com/previous-versions/dotnet/framework/code-access-security/security-transparent-code)!

The conclusion is that a three-layer system with clear markings throughout makes auditing straightforward. Our old system achieved that. For example, you can ask an agent to review all "safe critical" methods for review. It is trivial for the agent to find them. This is a definitional characteristic.

## Applying this model to C#

C# is the the opposite of D, where unsafe code is marked and safe isn't. The difference doesn't matter for effective memory safety. That's an audience and form factor bias. It's the decorative approach for the middle part of the model that matters most.

If caller-unsafe methods are marked as `unsafe`, then caller-safe methods with `unsafe` blocks should be marked as `safe`. That's the same as `@trusted`. Perfect! The presence of the `safe` marking provides a language-required location to place an attestation and equally operates as a grep target for code review.

We will need migration tools for the new model. The rough model should be the following:

- A tool marks all methods with interior unsafe blocks as unsafe.
- Developers mark those methods as safe or address the errors presented by the downstream callers.

This approach has the characteristic of being lossless and grep-friendly. It preserves our old three-layer model. It's actually better than D, which makes `@safe` and `@trusted` code easy to inventory and audit when in practice you want `@trusted` and `@system` code to easy to inventory and audit. That's the characteristic we'd have this this system. Who cares about reviewing `@safe` code!

The meaning of "lossless" is that safe (`@trusted`) attestations are recorded in code and source control. There is never a compiler-accepted state where infromation is list. `git blame` can find the point of attestation and `grep` can inventory them with complete accuracy and clarity.

## Grep ergonomics

For JSON schemas, I use [`jq` as the arbiter of sound schema design](https://github.com/dotnet/designs/blob/main/accepted/2025/cve-schema/cve_schema.md#design-philosophy). If the `jq` queries suck, so does the schema by implication. We can use grep as our proxy for sound language design.

We want to find `@trusted` code in D parlance.

### D Language

Source: https://github.com/dlang/phobos.git


We should start with D. First, seach for "trusted" code.

```bash=
$ rg "@trusted" --type d --pretty | head -36
phobos/sys/traits.d
5860:            struct S { void foo() @trusted { auto v = cast() local; } }
9718:        static void func() @trusted { useGC(); throws(); impure(); unsafe(); }
9719:        static assert( is(typeof(func) == ToFunctionType!(void function() @trusted)));
9720:        static assert( is(SymbolType!func == ToFunctionType!(void function() @trusted)));

std/sumtype.d
323:    @trusted
562:         * An individual assignment can be `@trusted` if the caller can
602:             * An individual assignment can be `@trusted` if the caller can
1140:    assert((() @trusted =>
1155:    assert((() @trusted =>

std/random.d
1806:@property uint unpredictableSeed() @trusted nothrow @nogc
1813:        const status = (() @trusted => getEntropy(&buffer, buffer.sizeof, EntropySource.tryAll))();
1864:        @property UIntType unpredictableSeed() @nogc nothrow @trusted
1871:                const status = (() @trusted => getEntropy(&buffer, buffer.sizeof, EntropySource.tryAll))();
3229:    this(this) pure nothrow @nogc @trusted
3242:    this(size_t numChoices) pure nothrow @nogc @trusted
3257:    ~this() pure nothrow @nogc @trusted
3265:    bool opIndex(size_t index) const pure nothrow @nogc @trusted
3275:    void opIndexAssign(bool value, size_t index) pure nothrow @nogc @trusted

std/bitmanip.d
202:    enum storage_accessor = "@property ref size_t " ~ store ~ "() return @trusted pure nothrow @nogc const { "
204:        ~ "@property void " ~ store ~ "(size_t v) @trusted pure nothrow @nogc { "
209:    enum ref_accessor = "@property "~T.stringof~" "~name~"() @trusted pure nothrow @nogc const { auto result = "
213:        ~"@property void "~name~"("~T.stringof~" v) @trusted pure nothrow @nogc { "
1448:                bitCount += (() @trusted => countBitsSet(_ptr[i]))();
1450:                bitCount += (() @trusted => countBitsSet(_ptr[fullWords] & endMask))();
2961:auto nativeToBigEndian(T)(const T val) @trusted pure nothrow @nogc
3088:T bigEndianToNative(T, size_t n)(ubyte[n] val) @trusted pure nothrow @nogc
3130:auto nativeToLittleEndian(T)(const T val) @trusted pure nothrow @nogc
3230:T littleEndianToNative(T, size_t n)(ubyte[n] val) @trusted pure nothrow @nogc
```

Lovely. You get files, columns, and nice function signatures. 

Gold star.

There is no good way to find unsafe code without an AST/LSP. Fail.

### Rust

Source: https://github.com/rust-lang/rust.git

First, search for "trusted" code.

There is no good way to find the trusted transition methods. This is the script Copilot wrote for this purpose, with the realization that it's an approximation on a compiler-driven search.


```bash=
#!/usr/bin/env bash
#
# find-rust-trust-boundaries.sh
#
# Find safe functions that contain unsafe {} blocks — Rust's implicit
# trust boundary. This is what D marks explicitly with @trusted.
#
# No LSP. Just grep + awk.
#
# Output: TSV to stdout (file, line, function, signature)
# Summary: to stderr
#
# Limitations (unfixable without a real parser):
#   - Block comments /* { } */ may skew brace counts
#   - String literals containing braces or "unsafe" cause false positives
#   - Macro invocations may hide or fabricate unsafe blocks
#   - This is a triage tool, not an authoritative audit tool
#
# Usage:
#   ./find-rust-trust-boundaries.sh [dir]
#   ./find-rust-trust-boundaries.sh ~/git/rust/library

set -euo pipefail

DIR="${1:-$(pwd)}"

if [[ ! -d "$DIR" ]]; then
    echo "Error: $DIR is not a directory" >&2
    exit 1
fi

echo "Scanning $DIR for safe fns wrapping unsafe blocks ..." >&2

printf "file\tline\tfunction\tsignature\n"

find "$DIR" -name '*.rs' -print0 | sort -z | while IFS= read -r -d '' file; do
    awk '
    { lines[NR] = $0 }
    END {
        for (n = 1; n <= NR; n++) {
            raw = lines[n]

            # Does this line declare a (safe) fn?
            if (raw !~ /^[[:space:]]*(pub(\([a-z]+\))?[[:space:]]+)?(const[[:space:]]+)?(async[[:space:]]+)?(extern[[:space:]]+"[^"]*"[[:space:]]+)?fn[[:space:]]+[a-z_]/) continue
            if (raw ~ /unsafe[[:space:]]+fn/) continue

            fn_line = n
            fn_sig = raw
            sub(/^[[:space:]]+/, "", fn_sig)

            # Extract function name
            fn_name = raw
            sub(/.*fn[[:space:]]+/, "", fn_name)
            sub(/[^a-zA-Z_0-9].*/, "", fn_name)

            # Walk the body tracking brace depth
            depth = 0; started = 0; has_unsafe = 0

            for (j = n; j <= NR; j++) {
                line = lines[j]
                sub(/\/\/.*$/, "", line)  # strip line comments

                for (k = 1; k <= length(line); k++) {
                    c = substr(line, k, 1)
                    if (c == "{") { depth++; started = 1 }
                    if (c == "}") depth--
                }
                if (line ~ /unsafe[[:space:]]*\{/) has_unsafe = 1
                if (started && depth <= 0) break
            }

            if (has_unsafe) {
                printf "%s\t%d\t%s\t%s\n", RELFILE, fn_line, fn_name, fn_sig
            }

            # Skip past the body regardless of whether it had unsafe
            n = j
        }
    }
    ' RELFILE="${file#"$DIR"/}" "$file"
done
```

Result:

```bash=
../scripts/find-rust-trust-boundaries.sh library | head -36
Scanning library for safe fns wrapping unsafe blocks ...
file    line    function        signature
alloc/src/alloc.rs      205     alloc_impl_runtime      fn alloc_impl_runtime(layout: Layout, zeroed: bool) -> Result<NonNull<[u8]>, AllocError> {
alloc/src/alloc.rs      219     deallocate_impl_runtime fn deallocate_impl_runtime(ptr: NonNull<u8>, layout: Layout) {
alloc/src/alloc.rs      236     grow_impl_runtime       fn grow_impl_runtime(
alloc/src/alloc.rs      284     shrink_impl_runtime     fn shrink_impl_runtime(
alloc/src/alloc.rs      389     alloc_impl_const        const fn alloc_impl_const(layout: Layout, zeroed: bool) -> Result<NonNull<[u8]>, AllocError> {
alloc/src/alloc.rs      408     deallocate_impl_const   const fn deallocate_impl_const(ptr: NonNull<u8>, layout: Layout) {
alloc/src/alloc.rs      420     grow_shrink_impl_const  const fn grow_shrink_impl_const(
alloc/src/alloc.rs      549     rt_error        fn rt_error(layout: Layout) -> ! {
alloc/src/boxed.rs      262     box_assume_init_into_vec_unsafe pub fn box_assume_init_into_vec_unsafe<T, const N: usize>(
alloc/src/boxed.rs      284     new     pub fn new(x: T) -> Self {
alloc/src/boxed.rs      311     new_uninit      pub fn new_uninit() -> Box<mem::MaybeUninit<T>> {
alloc/src/boxed.rs      444     map     pub fn map<U>(this: Self, f: impl FnOnce(T) -> U) -> Box<U> {
alloc/src/boxed.rs      476     try_map pub fn try_map<R>(
alloc/src/boxed.rs      520     new_in  pub fn new_in(x: T, alloc: A) -> Self
alloc/src/boxed.rs      546     try_new_in      pub fn try_new_in(x: T, alloc: A) -> Result<Self, AllocError>
alloc/src/boxed.rs      606     try_new_uninit_in       pub fn try_new_uninit_in(alloc: A) -> Result<Box<mem::MaybeUninit<T>, A>, AllocError>
alloc/src/boxed.rs      678     try_new_zeroed_in       pub fn try_new_zeroed_in(alloc: A) -> Result<Box<mem::MaybeUninit<T>, A>, AllocError>
alloc/src/boxed.rs      713     into_boxed_slice        pub fn into_boxed_slice(boxed: Self) -> Box<[T], A> {
alloc/src/boxed.rs      757     take    pub fn take(boxed: Self) -> (T, Box<mem::MaybeUninit<T>, A>) {
alloc/src/boxed.rs      856     try_clone_from_ref_in   pub fn try_clone_from_ref_in(src: &T, alloc: A) -> Result<Box<T, A>, AllocError> {
alloc/src/boxed.rs      907     new_uninit_slice        pub fn new_uninit_slice(len: usize) -> Box<[mem::MaybeUninit<T>]> {
alloc/src/boxed.rs      930     new_zeroed_slice        pub fn new_zeroed_slice(len: usize) -> Box<[mem::MaybeUninit<T>]> {
alloc/src/boxed.rs      954     try_new_uninit_slice    pub fn try_new_uninit_slice(len: usize) -> Result<Box<[mem::MaybeUninit<T>]>, AllocError> {
alloc/src/boxed.rs      988     try_new_zeroed_slice    pub fn try_new_zeroed_slice(len: usize) -> Result<Box<[mem::MaybeUninit<T>]>, AllocError> {
alloc/src/boxed.rs      1009    into_array      pub fn into_array<const N: usize>(self) -> Option<Box<[T; N]>> {
alloc/src/boxed.rs      1044    new_uninit_slice_in     pub fn new_uninit_slice_in(len: usize, alloc: A) -> Box<[mem::MaybeUninit<T>], A> {
alloc/src/boxed.rs      1071    new_zeroed_slice_in     pub fn new_zeroed_slice_in(len: usize, alloc: A) -> Box<[mem::MaybeUninit<T>], A> {
alloc/src/boxed.rs      1097    try_new_uninit_slice_in pub fn try_new_uninit_slice_in(
alloc/src/boxed.rs      1136    try_new_zeroed_slice_in pub fn try_new_zeroed_slice_in(
alloc/src/boxed.rs      1212    write   pub fn write(mut boxed: Self, value: T) -> Box<T, A> {
alloc/src/boxed.rs      1470    into_non_null   pub fn into_non_null(b: Self) -> NonNull<T> {
alloc/src/boxed.rs      1633    into_raw_with_allocator pub fn into_raw_with_allocator(b: Self) -> (*mut T, A) {
alloc/src/boxed.rs      1694    into_non_null_with_allocator    pub fn into_non_null_with_allocator(b: Self) -> (NonNull<T>, A) {
alloc/src/boxed.rs      1707    into_unique     pub fn into_unique(b: Self) -> (Unique<T>, A) {
alloc/src/boxed.rs      1859    leak    pub fn leak<'a>(b: Self) -> &'a mut T
```

That's a fail. That's a metric boatload of inference.

Next, search for unsafe code.

```bash=
$ rich@richs-MacBook-Pro rust % rg "unsafe fn" --type rust library --pretty | head -36  
library/panic_unwind/src/miri.rs
15:pub(crate) unsafe fn panic(payload: Box<dyn Any + Send>) -> u32 {
22:pub(crate) unsafe fn cleanup(payload_box: *mut u8) -> Box<dyn Any + Send> {

library/panic_unwind/src/emcc.rs
67:pub(crate) unsafe fn cleanup(ptr: *mut u8) -> Box<dyn Any + Send> {
98:pub(crate) unsafe fn panic(data: Box<dyn Any + Send>) -> u32 {

library/panic_unwind/src/lib.rs
104:pub unsafe fn __rust_start_panic(payload: &mut dyn PanicPayload) -> u32 {

library/panic_unwind/src/seh.rs
301:pub(crate) unsafe fn panic(data: Box<dyn Any + Send>) -> u32 {
305:unsafe fn throw_exception(data: Option<Box<dyn Any + Send>>) -> ! {
372:pub(crate) unsafe fn cleanup(payload: *mut u8) -> Box<dyn Any + Send> {

library/panic_unwind/src/dummy.rs
9:pub(crate) unsafe fn cleanup(_ptr: *mut u8) -> Box<dyn Any + Send> {
13:pub(crate) unsafe fn panic(_data: Box<dyn Any + Send>) -> u32 {

library/panic_unwind/src/gcc.rs
61:pub(crate) unsafe fn panic(data: Box<dyn Any + Send>) -> u32 {
85:pub(crate) unsafe fn cleanup(ptr: *mut u8) -> Box<dyn Any + Send> {

library/panic_unwind/src/hermit.rs
14:pub(crate) unsafe fn cleanup(_ptr: *mut u8) -> Box<dyn Any + Send> {
18:pub(crate) unsafe fn panic(_data: Box<dyn Any + Send>) -> u32 {

library/panic_abort/src/android.rs
18:pub(crate) unsafe fn android_set_abort_message(payload: &mut dyn PanicPayload) {

library/panic_abort/src/zkvm.rs
6:pub(crate) unsafe fn zkvm_set_abort_message(payload: &mut dyn PanicPayload) {

library/panic_abort/src/lib.rs
33:pub unsafe fn __rust_start_panic(_payload: &mut dyn PanicPayload) -> u32 {
```

Gold star.

We can also query for unsafe blocks.

```bash=
rg -Un "unsafe\s*\{" library --type rust --pretty | head -36
library/stdarch/examples/wasm.rs
13:    unsafe {
35:    unsafe {

library/portable-simd/crates/test_helpers/src/wasm.rs
24:                    unsafe { core::mem::transmute(self.inner.current()) }

library/unwind/src/unwinding.rs
54:    let ctx = unsafe { &mut *(ctx as *mut UnwindContext<'_>) };
59:    let ctx = unsafe { &mut *(ctx as *mut UnwindContext<'_>) };
64:    let ctx = unsafe { &mut *(ctx as *mut UnwindContext<'_>) };
69:    let ctx = unsafe { &mut *(ctx as *mut UnwindContext<'_>) };
74:    let ctx = unsafe { &mut *(ctx as *mut UnwindContext<'_>) };
82:    let ctx = unsafe { &mut *(ctx as *mut UnwindContext<'_>) };
83:    let ip_before_insn = unsafe { &mut *(ip_before_insn as *mut c_int) };
84:    unsafe { &*(unwinding::abi::_Unwind_GetIPInfo(ctx, ip_before_insn) as _Unwind_Word) }
88:    let ctx = unsafe { &mut *(ctx as *mut UnwindContext<'_>) };
93:    let exception = unsafe { &mut *(exception as *mut UnwindException) };
94:    unsafe { core::mem::transmute(unwinding::abi::_Unwind_RaiseException(exception)) }
98:    let exception = unsafe { &mut *(exception as *mut UnwindException) };
99:    unsafe { unwinding::abi::_Unwind_DeleteException(exception) }

library/panic_abort/src/android.rs
19:    let func_addr = unsafe {
41:    let buf = unsafe { libc::malloc(size) as *mut libc::c_char };
45:    unsafe {

library/alloctests/benches/vec_deque.rs
86:    mem::forget(mem::replace(v, unsafe { Vec::from_raw_parts(ptr, len, len) }));

library/unwind/src/wasm.rs
61:    if let Some(exception_cleanup) = unsafe { (*exception).exception_cleanup } {
100:            unsafe { wasm_throw(CPP_EXCEPTION_TAG, exception.cast()) }

library/panic_abort/src/lib.rs
36:    unsafe {
```

Very nice. Gold star.

It is important to note that `unsafe fn` is doing a (very) heavy lift on disambiguation with `unsafe` blocks.

## Swift

Source [swiftlang/swift.git](https://github.com/swiftlang/swift.git).

Swift has the same problem as Rust. The transition methods require a script or LSP.

Here's the script that Copilot wrote.

```bash=
#!/usr/bin/env bash
#
# find-swift-trust-boundaries.sh
#
# Find safe functions that use `unsafe` expressions — Swift's implicit
# trust boundary. This is what D marks explicitly with @trusted.
#
# In Swift 6.2, `unsafe` is an expression prefix (not a block):
#   let p = unsafe someUnsafeCall()
# A trust boundary is a func NOT marked @unsafe that contains these.
#
# No LSP. Just grep + awk.
#
# Output: TSV to stdout (file, line, function, signature)
# Summary: to stderr
#
# Limitations (unfixable without a real parser):
#   - String literals containing "unsafe" cause false positives
#   - Multi-line string literals with braces skew brace counting
#   - Macros may hide or fabricate unsafe expressions
#   - @unsafe on a preceding line is detected with a lookback heuristic
#     (up to 8 lines); unusual formatting may cause misclassification
#   - This is a triage tool, not an authoritative audit tool
#
# Usage:
#   ./find-swift-trust-boundaries.sh [dir]
#   ./find-swift-trust-boundaries.sh ~/git/swiftlang-swift/stdlib

set -euo pipefail

DIR="${1:-$(pwd)}"

if [[ ! -d "$DIR" ]]; then
    echo "Error: $DIR is not a directory" >&2
    exit 1
fi

echo "Scanning $DIR for safe funcs wrapping unsafe expressions ..." >&2

printf "file\tline\tfunction\tsignature\n"

find "$DIR" -name '*.swift' -print0 | sort -z | while IFS= read -r -d '' file; do
    awk '
    { lines[NR] = $0 }
    END {
        for (n = 1; n <= NR; n++) {
            raw = lines[n]

            # Match func or init declarations
            is_func = 0
            if (raw ~ /[[:space:]]*(public|internal|private|fileprivate|open|package)?[[:space:]]*(static[[:space:]]+)?(mutating[[:space:]]+)?func[[:space:]]+/) is_func = 1
            if (raw ~ /[[:space:]]*(public|internal|private|fileprivate|open|package)?[[:space:]]*(static[[:space:]]+)?(required[[:space:]]+)?(convenience[[:space:]]+)?init[[:space:]]*[\(<]/) is_func = 1
            if (!is_func) continue

            # Check if this func is itself @unsafe by looking back up to 8 lines
            is_unsafe_decl = 0
            for (b = n - 1; b >= 1 && b >= n - 8; b--) {
                prev = lines[b]
                # Stop at blank lines or closing braces (different decl)
                if (prev ~ /^[[:space:]]*$/) break
                if (prev ~ /\}/) break
                if (prev ~ /^[[:space:]]*@unsafe[[:space:]]*$/) {
                    is_unsafe_decl = 1
                    break
                }
            }
            if (is_unsafe_decl) continue

            fn_line = n
            fn_sig = raw
            sub(/^[[:space:]]+/, "", fn_sig)

            # Extract function name
            fn_name = ""
            if (raw ~ /func[[:space:]]/) {
                fn_name = raw
                sub(/.*func[[:space:]]+/, "", fn_name)
                sub(/[^a-zA-Z_0-9].*/, "", fn_name)
            } else {
                fn_name = "init"
            }

            # Walk the body tracking brace depth, looking for unsafe expressions
            depth = 0; started = 0; has_unsafe = 0

            for (j = n; j <= NR; j++) {
                line = lines[j]
                sub(/\/\/.*$/, "", line)  # strip line comments

                for (k = 1; k <= length(line); k++) {
                    c = substr(line, k, 1)
                    if (c == "{") { depth++; started = 1 }
                    if (c == "}") depth--
                }

                # Swift unsafe expressions: `unsafe expr` (not @unsafe, not "unsafe" in a string)
                # Match `unsafe` preceded by space/=/( and followed by space/letter
                if (j > n && line ~ /[[:space:](=]unsafe[[:space:]]/) has_unsafe = 1

                if (started && depth <= 0) break
            }

            if (has_unsafe) {
                printf "%s\t%d\t%s\t%s\n", RELFILE, fn_line, fn_name, fn_sig
            }

            # Skip past the body regardless of whether it had unsafe
            n = j
        }
    }
    ' RELFILE="${file#"$DIR"/}" "$file"
done
```

Result:

```bash=
../scripts/find-swift-trust-boundaries.sh stdlib | head -36
Scanning stdlib for safe funcs wrapping unsafe expressions ...
file	line	function	signature
public/Concurrency/AsyncStreamBuffer.swift	43	_lockWordCount	func _lockWordCount() -> Int
public/Concurrency/AsyncStreamBuffer.swift	298	init	init(limit: Continuation.BufferingPolicy) {
public/Concurrency/AsyncStreamBuffer.swift	313	lock	private func lock() {
public/Concurrency/AsyncStreamBuffer.swift	319	unlock	private func unlock() {
public/Concurrency/AsyncStreamBuffer.swift	325	getOnTermination	func getOnTermination() -> TerminationHandler? {
public/Concurrency/AsyncStreamBuffer.swift	332	setOnTermination	func setOnTermination(_ newValue: TerminationHandler?) {
public/Concurrency/AsyncStreamBuffer.swift	340	cancel	@Sendable func cancel() {
public/Concurrency/AsyncStreamBuffer.swift	353	yield	func yield(_ value: __owned Element) -> Continuation.YieldResult {
public/Concurrency/AsyncStreamBuffer.swift	447	finish	func finish(throwing error: __owned Failure? = nil) {
public/Concurrency/AsyncStreamBuffer.swift	486	next	func next(_ continuation: UnsafeContinuation<Element?, Error>) {
public/Concurrency/AsyncStreamBuffer.swift	512	next	func next() async throws -> Element? {
public/Concurrency/AsyncStreamBuffer.swift	522	create	static func create(limit: Continuation.BufferingPolicy) -> _Storage {
public/Concurrency/AsyncStreamBuffer.swift	548	lock	private func lock() {
public/Concurrency/AsyncStreamBuffer.swift	554	unlock	private func unlock() {
public/Concurrency/AsyncStreamBuffer.swift	577	create	static func create(_ initial: Contents) -> _AsyncStreamCriticalStorage {
public/Concurrency/CFExecutor.swift	18	dlopen_noload	private func dlopen_noload(_ path: UnsafePointer<CChar>?) -> OpaquePointer?
public/Concurrency/CFExecutor.swift	58	stop	override public func stop() {
public/Concurrency/CheckedContinuation.swift	17	logFailedCheck	internal func logFailedCheck(_ message: UnsafeRawPointer)
public/Concurrency/CheckedContinuation.swift	146	init	public init(continuation: UnsafeContinuation<T, E>, function: String = #function) {
public/Concurrency/CheckedContinuation.swift	164	resume	public func resume(returning value: sending T) {
public/Concurrency/CheckedContinuation.swift	188	resume	public func resume(throwing error: __owned E) {
public/Concurrency/CheckedContinuation.swift	299	withCheckedContinuationNonisolatedNonsending	nonisolated(nonsending) func withCheckedContinuationNonisolatedNonsending<T>(
public/Concurrency/CheckedContinuation.swift	322	withCheckedContinuation	public func withCheckedContinuation<T>( // source-compatibility overload
public/Concurrency/CheckedContinuation.swift	343	_unsafeInheritExecutor_withCheckedContinuation	public func _unsafeInheritExecutor_withCheckedContinuation<T>(
public/Concurrency/CheckedContinuation.swift	387	withCheckedThrowingContinuationNonisolatedNonsending	nonisolated(nonsending) func withCheckedThrowingContinuationNonisolatedNonsending<T, E>(
public/Concurrency/CheckedContinuation.swift	413	withCheckedThrowingContinuationNonisolatedNonsending	nonisolated(nonsending) func withCheckedThrowingContinuationNonisolatedNonsending<T>(
public/Concurrency/CheckedContinuation.swift	436	withCheckedThrowingContinuation	public func withCheckedThrowingContinuation<T>(
public/Concurrency/CheckedContinuation.swift	457	_unsafeInheritExecutor_withCheckedThrowingContinuation	public func _unsafeInheritExecutor_withCheckedThrowingContinuation<T>(
public/Concurrency/CheckedContinuation.swift	471	_createCheckedContinuation	internal func _createCheckedContinuation<T>(
public/Concurrency/CheckedContinuation.swift	479	_createCheckedThrowingContinuation	internal func _createCheckedThrowingContinuation<T>(
public/Concurrency/CooperativeExecutor.swift	73	setupCooperativeExecutorTimestamp	fileprivate mutating func setupCooperativeExecutorTimestamp() {
public/Concurrency/CooperativeExecutor.swift	87	clearCooperativeExecutorTimestamp	fileprivate mutating func clearCooperativeExecutorTimestamp() {
public/Concurrency/CooperativeExecutor.swift	254	currentTime	func currentTime(clock: _ClockID) -> Timestamp {
public/Concurrency/CooperativeExecutor.swift	291	runUntil	public func runUntil(_ condition: () -> Bool) throws {
public/Concurrency/Deque/_UnsafeWrappedBuffer.swift	23	init	internal init(
```

Same fail rating.

Let's search for unsafe functions.

```bash=
$ rg "@unsafe" --type swift --pretty stdlib | head -36
stdlib/toolchain/CompatibilitySpan/FakeStdlib.swift
36:@unsafe
49:@unsafe
62:@unsafe
77:  @unsafe

stdlib/public/Synchronization/Mutex/Mutex.swift
177:  @unsafe
185:  @unsafe
193:  @unsafe

stdlib/public/Concurrency/AsyncStreamBuffer.swift
61:    @unsafe struct State {
291:    @unsafe struct State {

stdlib/public/Concurrency/Task.swift
756:@unsafe
890:extension UnsafeCurrentTask: @unsafe Hashable {

stdlib/public/Concurrency/PartialAsyncTask.swift
693:@unsafe
897:@unsafe
910:@unsafe
949:@unsafe
964:@unsafe
977:@unsafe

stdlib/public/core/ContiguousArrayBuffer.swift
73:@unsafe
1160:@unsafe

stdlib/public/Cxx/CxxSpan.swift
26:@unsafe
46:@unsafe
93:  @unsafe
108:  @unsafe
```

That's a fail. However, it can be easily mitigated by asking ripgrep to add another line of context.


```bash=
rg "@unsafe" --type swift --pretty stdlib -A 1 | head -36
stdlib/toolchain/CompatibilitySpan/FakeStdlib.swift
36:@unsafe
37-@_unsafeNonescapableResult
--
49:@unsafe
50-@_unsafeNonescapableResult
--
62:@unsafe
63-@_unsafeNonescapableResult
--
77:  @unsafe
78-  @_alwaysEmitIntoClient

stdlib/public/Concurrency/AsyncStreamBuffer.swift
61:    @unsafe struct State {
62-      var continuations = unsafe [UnsafeContinuation<Element?, Never>]()
--
291:    @unsafe struct State {
292-      var continuation: UnsafeContinuation<Element?, Error>?

stdlib/public/Synchronization/Mutex/Mutex.swift
177:  @unsafe
178-  public borrowing func unsafeLock() {
--
185:  @unsafe
186-  public borrowing func unsafeTryLock() -> Bool {
--
193:  @unsafe
194-  public borrowing func unsafeUnlock() {

stdlib/public/Concurrency/Task.swift
756:@unsafe
757-public struct UnsafeCurrentTask {
--
890:extension UnsafeCurrentTask: @unsafe Hashable {
891-  public func hash(into hasher: inout Hasher) {
```

The Rust one-line syntax is much preferred, however, this is still much better than D.

## C# (existing)

Source: https://github.com/dotnet/runtime

Let's start with transition methods. C# doesn't have a clean model for this since C# has a limited concept for propation. I asked Copilot to find `unsafe` methods with no pointers as a (questionable) proxy for transition methods. It produced  another script.

```bash=
#!/usr/bin/env bash
#
# find-csharp-trust-boundaries.sh
#
# Find safe methods that contain unsafe {} blocks — C#'s implicit trust
# boundary. This is what D marks explicitly with @trusted.
#
# A trust boundary is a method NOT marked unsafe, NOT inside an unsafe
# type, that contains unsafe { } blocks in its body.
#
# No LSP. Just grep + awk.
#
# Output: TSV to stdout (file, line, method, signature)
# Summary: to stderr
#
# Limitations (unfixable without a real parser):
#   - String literals containing braces or "unsafe" cause false positives
#   - Preprocessor directives (#if etc.) may hide or reveal code
#   - Partial classes may split an unsafe class across files
#   - This is a triage tool, not an authoritative audit tool
#
# Usage:
#   ./find-csharp-trust-boundaries.sh [dir]
#   ./find-csharp-trust-boundaries.sh ~/git/runtime/src/libraries

set -euo pipefail

DIR="${1:-$(pwd)}"

if [[ ! -d "$DIR" ]]; then
    echo "Error: $DIR is not a directory" >&2
    exit 1
fi

echo "Scanning $DIR for safe methods wrapping unsafe blocks ..." >&2

printf "file\tline\tmethod\tsignature\n"

find "$DIR" -name '*.cs' -print0 | sort -z | while IFS= read -r -d '' file; do
    awk '
    { lines[NR] = $0 }
    END {
        # First pass: find unsafe type ranges (unsafe class/struct)
        # Store as start_line -> end_line pairs
        unsafe_type_count = 0
        for (i = 1; i <= NR; i++) {
            line = lines[i]
            if (line ~ /unsafe[[:space:]]+(class|struct|interface)/) {
                # Find the opening brace
                depth = 0; started = 0
                for (j = i; j <= NR; j++) {
                    s = lines[j]
                    sub(/\/\/.*$/, "", s)
                    for (k = 1; k <= length(s); k++) {
                        c = substr(s, k, 1)
                        if (c == "{") { depth++; started = 1 }
                        if (c == "}") depth--
                    }
                    if (started && depth <= 0) {
                        unsafe_type_count++
                        ut_start[unsafe_type_count] = i
                        ut_end[unsafe_type_count] = j
                        break
                    }
                }
            }
        }

        # Second pass: find methods
        for (n = 1; n <= NR; n++) {
            raw = lines[n]
            stripped = raw
            sub(/\/\/.*$/, "", stripped)

            # Skip lines inside unsafe types
            in_unsafe_type = 0
            for (u = 1; u <= unsafe_type_count; u++) {
                if (n > ut_start[u] && n < ut_end[u]) {
                    in_unsafe_type = 1
                    break
                }
            }
            if (in_unsafe_type) continue

            # Match method declarations (not marked unsafe)
            is_method = 0
            if (stripped ~ /(public|private|protected|internal)/ && stripped ~ /[a-zA-Z_]+[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(/) is_method = 1
            if (!is_method) continue
            if (stripped ~ /[[:space:]]unsafe[[:space:]]/) continue
            if (stripped ~ /(^|[[:space:]])(class|struct|interface|enum|delegate)[[:space:]]/) continue

            fn_line = n
            fn_sig = raw
            sub(/^[[:space:]]+/, "", fn_sig)

            # Extract method name: last identifier before (
            fn_name = stripped
            sub(/[[:space:]]*\(.*/, "", fn_name)
            sub(/.*[[:space:]]/, "", fn_name)
            sub(/[<>].*/, "", fn_name)

            # Walk the body tracking brace depth
            depth = 0; started = 0; has_unsafe_block = 0
            prev_was_unsafe = 0

            for (j = n; j <= NR; j++) {
                line = lines[j]
                sub(/\/\/.*$/, "", line)

                # Allman style: "unsafe" alone on one line, "{" on the next
                if (prev_was_unsafe && line ~ /^[[:space:]]*\{/) has_unsafe_block = 1
                prev_was_unsafe = 0
                if (line ~ /[[:space:]]unsafe[[:space:]]*$/ || line ~ /^[[:space:]]*unsafe[[:space:]]*$/) prev_was_unsafe = 1

                for (k = 1; k <= length(line); k++) {
                    c = substr(line, k, 1)
                    if (c == "{") { depth++; started = 1 }
                    if (c == "}") depth--
                }
                # Same-line style: unsafe { ... }
                if (line ~ /unsafe[[:space:]]*\{/) has_unsafe_block = 1
                if (started && depth <= 0) break
            }

            if (has_unsafe_block) {
                printf "%s\t%d\t%s\t%s\n", RELFILE, fn_line, fn_name, fn_sig
            }

            # Skip past the body
            n = j
        }
    }
    ' RELFILE="${file#"$DIR"/}" "$file"
done


Result:

```bash
$ ../scripts/find-csharp-trust-boundaries.sh src/libraries | head -36
Scanning src/libraries for safe methods wrapping unsafe blocks ...
file	line	method	signature
Common/src/Interop/Linux/procfs/Interop.ProcFsStat.ParseMapModules.cs	34	ParseMapsModulesCore	private static ProcessModuleCollection ParseMapsModulesCore(IEnumerable<string> lines)
Common/src/Interop/OSX/Interop.CoreFoundation.CFString.cs	25	CFStringCreateExternalRepresentation	private static partial SafeCFDataHandle CFStringCreateExternalRepresentation(
Common/src/Interop/Unix/System.Native/Interop.GetUnixVersion.cs	15	GetUnixVersion	private static partial int GetUnixVersion(byte[] version, ref int capacity);
Common/src/Interop/Windows/Advapi32/Interop.CryptGetProvParam.cs	27	CryptSetProvParam	public static partial bool CryptSetProvParam(
Common/src/Interop/Windows/BCrypt/Interop.BCryptEncryptDecrypt.cs	15	BCryptEncrypt	internal static int BCryptEncrypt(SafeKeyHandle hKey, ReadOnlySpan<byte> input, byte[]? iv, Span<byte> output)
Common/src/Interop/Windows/BCrypt/Interop.BCryptEncryptDecrypt.cs	36	BCryptDecrypt	internal static int BCryptDecrypt(SafeKeyHandle hKey, ReadOnlySpan<byte> input, byte[]? iv, Span<byte> output)
Common/src/Interop/Windows/NCrypt/Interop.NCryptDeriveKeyMaterial.cs	19	NCryptDeriveKey	private static partial ErrorCode NCryptDeriveKey(
Common/src/Microsoft/Win32/SafeHandles/SafeCertContextHandleWithKeyContainerDeletion.cs	26	DeleteKeyContainer	internal static void DeleteKeyContainer(SafeCertContextHandle pCertContext)
Common/src/System/Net/Security/CertificateValidation.Windows.cs	17	BuildChainAndVerifyProperties	internal static SslPolicyErrors BuildChainAndVerifyProperties(X509Chain chain, X509Certificate2 remoteCertificate, bool checkCertName, bool isServer, string? hostName, Span<byte> certificateBuffer)
Common/src/System/Security/Cryptography/CngHelpers.cs	36	SetExportPolicy	internal static void SetExportPolicy(this SafeNCryptKeyHandle keyHandle, CngExportPolicies exportPolicy)
Common/src/System/Security/Cryptography/DSACng.ImportExport.cs	311	ExportParameters	public override DSAParameters ExportParameters(bool includePrivateParameters)
Common/src/System/Security/Cryptography/DSACng.SignVerify.cs	81	VerifySignatureCore	protected override bool VerifySignatureCore(
Common/src/System/Security/Cryptography/DSACng.SignVerify.cs	144	ComputeQLength	private int ComputeQLength()
Common/src/System/Security/Cryptography/ECCng.ImportExport.cs	161	ExportPrimeCurveParameters	internal static void ExportPrimeCurveParameters(ref ECParameters ecParams, byte[] ecBlob, bool includePrivateParameters)
Common/src/System/Security/Cryptography/ECCng.ImportExport.NamedCurve.cs	144	ImportKeyBlob	internal static SafeNCryptKeyHandle ImportKeyBlob(
Common/src/System/Security/Cryptography/ECDsaCng.SignVerify.cs	86	VerifyHash	public override bool VerifyHash(ReadOnlySpan<byte> hash, ReadOnlySpan<byte> signature) =>
Common/src/System/Security/Cryptography/X509Certificates/X509CertificateLoader.cs	418	LoadPkcs12Collection	public static X509Certificate2Collection LoadPkcs12Collection(
Microsoft.Bcl.Cryptography/src/Microsoft/Win32/SafeHandles/SafePasswordHandle.cs	36	SafePasswordHandle	public SafePasswordHandle(ReadOnlySpan<char> password, bool passwordProvided)
Microsoft.Extensions.Logging.Console/src/JsonConsoleFormatter.cs	56	WriteInternal	private void WriteInternal(IExternalScopeProvider? scopeProvider, TextWriter textWriter, string? message, LogLevel logLevel,
Microsoft.Win32.SystemEvents/src/Microsoft/Win32/SystemEvents.cs	749	InvokeOnEventsThread	public static void InvokeOnEventsThread(Delegate method)
System.Data.OleDb/src/SafeHandles.cs	255	MemoryCompare	internal static bool MemoryCompare(System.IntPtr buf1, System.IntPtr buf2, int count)
System.Data.OleDb/src/SafeHandles.cs	271	MemoryCopy	internal static void MemoryCopy(System.IntPtr dst, System.IntPtr src, int count)
System.Data.OleDb/src/System/Data/ProviderBase/DbConnectionPool.cs	1084	TryGetConnection	private bool TryGetConnection(DbConnection owningObject, uint waitForMultipleObjectsTimeout, bool allowCreate, bool onlyOneCheckConnection, DbConnectionOptions? userOptions, out DbConnectionInternal? connection)
System.Diagnostics.PerformanceCounter/src/System/Diagnostics/PerformanceData/CounterSet.cs	173	CreateCounterSetInstance	public CounterSetInstance CreateCounterSetInstance(string instanceName)
System.Diagnostics.PerformanceCounter/src/System/Diagnostics/PerformanceData/CounterSetInstance.cs	86	Dispose	private void Dispose(bool disposing)
System.Diagnostics.PerformanceCounter/src/System/Diagnostics/PerformanceData/CounterSetInstanceCounterDataSet.cs	5Increment	public void Increment()
System.Diagnostics.PerformanceCounter/src/System/Diagnostics/PerformanceData/CounterSetInstanceCounterDataSet.cs	5Decrement	public void Decrement()
System.Diagnostics.PerformanceCounter/src/System/Diagnostics/PerformanceData/CounterSetInstanceCounterDataSet.cs	6IncrementBy	public void IncrementBy(long value)
System.Diagnostics.PerformanceCounter/src/System/Diagnostics/PerformanceData/CounterSetInstanceCounterDataSet.cs	109	CounterSetInstanceCounterDataSet	internal CounterSetInstanceCounterDataSet(CounterSetInstance thisInst)
System.Diagnostics.PerformanceCounter/src/System/Diagnostics/PerformanceData/CounterSetInstanceCounterDataSet.cs	174	DisposeCore	private void DisposeCore()
System.Diagnostics.Process/src/System/Diagnostics/Process.Win32.cs	195	GetMainWindowTitle	private string GetMainWindowTitle()
System.Diagnostics.Process/src/System/Diagnostics/Process.Win32.cs	272	IsRespondingCore	private bool IsRespondingCore()
System.Diagnostics.Tracing/tests/CustomEventSources/EventSourceTest.cs	112	LogTaskScheduledBad	public void LogTaskScheduledBad(Guid RelatedActivityId, string message)
System.Diagnostics.Tracing/tests/CustomEventSources/EventSourceTest.cs	153	EventWithXferManyTypeArgs	public void EventWithXferManyTypeArgs(Guid RelatedActivityId, long l, uint ui, ulong ui64, char ch,
System.Diagnostics.Tracing/tests/CustomEventSources/EventSourceTest.cs	195	EventWithXferWeirdArgs	public void EventWithXferWeirdArgs(Guid RelatedActivityId, IntPtr iptr, bool b, MyLongEnum le /*, decimal dec */)
```

This is very clearly a fail.

We can grep for `unsafe` code:

```bash=
rg "unsafe" --type cs --pretty src/libraries | head -36
src/libraries/System.IO.Ports/src/System/IO/Ports/SerialStream.Windows.cs
63:        private static readonly unsafe IOCompletionCallback s_IOCallback = new IOCompletionCallback(AsyncFSCallback);
859:        public override unsafe int EndRead(IAsyncResult asyncResult)
934:        public override unsafe void EndWrite(IAsyncResult asyncResult)
1008:        internal unsafe int Read(byte[] array, int offset, int count, int timeout)
1037:        internal unsafe int ReadByte(int _/*timeout*/)
1070:        internal unsafe void Write(byte[] array, int offset, int count, int timeout)
1107:        public override unsafe void WriteByte(byte value)
1151:        private unsafe void InitializeDCB(int baudRate, Parity parity, int dataBits, StopBits stopBits, bool discardNull)
1346:        private unsafe SerialStreamAsyncResult BeginReadCore(byte[] array, int offset, int numBytes, AsyncCallback userCallback, object stateObject)
1392:        private unsafe SerialStreamAsyncResult BeginWriteCore(byte[] array, int offset, int numBytes, AsyncCallback userCallback, object stateObject)
1439:        private unsafe int ReadFileNative(byte[] bytes, int offset, int count, NativeOverlapped* overlapped, out int hr)
1486:        private unsafe int WriteFileNative(byte[] bytes, int offset, int count, NativeOverlapped* overlapped, out int hr)
1537:        private static unsafe void AsyncFSCallback(uint errorCode, uint numBytes, NativeOverlapped* pOverlapped)
1589:            internal unsafe EventLoopRunner(SerialStream stream)
1614:            internal unsafe void WaitForCommEvent()
1708:            private unsafe void FreeNativeOverlappedCallback(uint errorCode, uint numBytes, NativeOverlapped* pOverlapped)
1835:        internal sealed unsafe class SerialStreamAsyncResult : IAsyncResult

src/libraries/System.Net.WebSockets/src/System/Net/WebSockets/Compression/WebSocketDeflater.cs
122:        private unsafe void UnsafeDeflate(ReadOnlySpan<byte> input, Span<byte> output, out int consumed, out int written, out bool needsMoreBuffer)
153:        private unsafe int UnsafeFlush(Span<byte> output, out bool needsMoreBuffer)

src/libraries/System.Net.WebSockets/src/System/Net/WebSockets/Compression/WebSocketInflater.cs
126:        public unsafe bool Inflate(Span<byte> output, out int written)
228:        private static unsafe int Inflate(ZLibStreamHandle stream, Span<byte> destination, FlushCode flushCode)

src/libraries/System.Net.Primitives/src/System/Net/NetworkCredential.cs
178:        private unsafe SecureString MarshalToSecureString(string str)

src/libraries/System.Net.WebSockets/src/System/Net/WebSockets/ManagedWebSocket.cs
1660:        private static unsafe int ApplyMask(Span<byte> toMask, int mask, int maskIndex)

src/libraries/System.IO.Ports/src/System/IO/Ports/SerialStream.Unix.cs
777:        private unsafe int ProcessRead(SerialStreamIORequest r)
810:        private unsafe int ProcessWrite(SerialStreamIORequest r)
```

This seems on first glance to matches D and Rust.

It falls apart a bit when we `unsafe` methods and `unsafe` blocks are both present.

```bash=
rg "unsafe" --type cs --pretty src/libraries/System.Private.CoreLib/src/Microsoft/Win32/SafeHandles | head -36
src/libraries/System.Private.CoreLib/src/Microsoft/Win32/SafeHandles/SafeFileHandle.ThreadPoolValueTaskSource.cs
42:            // Used by simple reads and writes. Will be unsafely cast to a memory when performing a read.

src/libraries/System.Private.CoreLib/src/Microsoft/Win32/SafeHandles/SafeFileHandle.Windows.cs
146:        private static unsafe SafeFileHandle CreateFile(string fullPath, FileMode mode, FileAccess access, FileShare share, FileOptions options)
197:        private static unsafe void Preallocate(string fullPath, long preallocationSize, SafeFileHandle fileHandle)
280:        internal unsafe FileOptions GetFileOptions()
355:        private unsafe FileHandleType GetPipeOrSocketType()
374:        private unsafe FileHandleType GetDiskBasedType()
421:            unsafe long GetFileLengthCore()

src/libraries/System.Private.CoreLib/src/Microsoft/Win32/SafeHandles/SafeFileHandle.OverlappedValueTaskSource.Windows.cs
47:        internal sealed unsafe class OverlappedValueTaskSource : IValueTaskSource<int>, IValueTaskSource

src/libraries/System.Private.CoreLib/src/Microsoft/Win32/SafeHandles/SafeFileHandle.Unix.cs
201:            unsafe
```
Here's a bit more insight.

```bash=
rg -Un "unsafe\s*\{" src/libraries --type cs --pretty | head -36
src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarWriter.Unix.cs
78:                unsafe
79:                {

src/libraries/System.Threading.Tasks.Parallel/src/System/Threading/Tasks/ParallelRangeManager.cs
119:                        unsafe
120:                        {

src/libraries/System.Threading.Tasks.Parallel/src/System/Threading/Tasks/ParallelETWProvider.cs
112:                unsafe
113:                {
172:                unsafe
173:                {
222:                unsafe
223:                {

src/libraries/System.Runtime.InteropServices.JavaScript/src/System/Runtime/InteropServices/JavaScript/JSProxyContext.cs
401:                unsafe
402:                {
566:                        unsafe
567:                        {

src/libraries/System.Security.Cryptography.Pkcs/src/Internal/Cryptography/Pal/Windows/DecryptorPalWindows.DecodeRecipients.cs
42:                unsafe
43:                {

src/libraries/System.Security.Cryptography.Pkcs/src/Internal/Cryptography/Pal/Windows/KeyTransRecipientInfoPalWindows.cs
28:                unsafe
29:                {
43:                unsafe
44:                {
59:                unsafe
60:                {
75:                unsafe
76:                {
92:            unsafe
```

I asked Copilot to write another script that that found both `unsafe` marked methods and those implied via a `unsafe class`.

```bash
#!/usr/bin/env bash
#
# find-csharp-trust-boundaries.sh
#
# Find safe methods that contain unsafe {} blocks — C#'s implicit trust
# boundary. This is what D marks explicitly with @trusted.
#
# A trust boundary is a method NOT marked unsafe, NOT inside an unsafe
# type, that contains unsafe { } blocks in its body.
#
# No LSP. Just grep + awk.
#
# Output: TSV to stdout (file, line, method, signature)
# Summary: to stderr
#
# Limitations (unfixable without a real parser):
#   - String literals containing braces or "unsafe" cause false positives
#   - Preprocessor directives (#if etc.) may hide or reveal code
#   - Partial classes may split an unsafe class across files
#   - This is a triage tool, not an authoritative audit tool
#
# Usage:
#   ./find-csharp-trust-boundaries.sh [dir]
#   ./find-csharp-trust-boundaries.sh ~/git/runtime/src/libraries

set -euo pipefail

DIR="${1:-$(pwd)}"

if [[ ! -d "$DIR" ]]; then
    echo "Error: $DIR is not a directory" >&2
    exit 1
fi

echo "Scanning $DIR for safe methods wrapping unsafe blocks ..." >&2

printf "file\tline\tmethod\tsignature\n"

find "$DIR" -name '*.cs' -print0 | sort -z | while IFS= read -r -d '' file; do
    awk '
    { lines[NR] = $0 }
    END {
        # First pass: find unsafe type ranges (unsafe class/struct)
        # Store as start_line -> end_line pairs
        unsafe_type_count = 0
        for (i = 1; i <= NR; i++) {
            line = lines[i]
            if (line ~ /unsafe[[:space:]]+(class|struct|interface)/) {
                # Find the opening brace
                depth = 0; started = 0
                for (j = i; j <= NR; j++) {
                    s = lines[j]
                    sub(/\/\/.*$/, "", s)
                    for (k = 1; k <= length(s); k++) {
                        c = substr(s, k, 1)
                        if (c == "{") { depth++; started = 1 }
                        if (c == "}") depth--
                    }
                    if (started && depth <= 0) {
                        unsafe_type_count++
                        ut_start[unsafe_type_count] = i
                        ut_end[unsafe_type_count] = j
                        break
                    }
                }
            }
        }

        # Second pass: find methods
        for (n = 1; n <= NR; n++) {
            raw = lines[n]
            stripped = raw
            sub(/\/\/.*$/, "", stripped)

            # Skip lines inside unsafe types
            in_unsafe_type = 0
            for (u = 1; u <= unsafe_type_count; u++) {
                if (n > ut_start[u] && n < ut_end[u]) {
                    in_unsafe_type = 1
                    break
                }
            }
            if (in_unsafe_type) continue

            # Match method declarations (not marked unsafe)
            is_method = 0
            if (stripped ~ /(public|private|protected|internal)/ && stripped ~ /[a-zA-Z_]+[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(/) is_method = 1
            if (!is_method) continue
            if (stripped ~ /[[:space:]]unsafe[[:space:]]/) continue
            if (stripped ~ /(^|[[:space:]])(class|struct|interface|enum|delegate)[[:space:]]/) continue

            fn_line = n
            fn_sig = raw
            sub(/^[[:space:]]+/, "", fn_sig)

            # Extract method name: last identifier before (
            fn_name = stripped
            sub(/[[:space:]]*\(.*/, "", fn_name)
            sub(/.*[[:space:]]/, "", fn_name)
            sub(/[<>].*/, "", fn_name)

            # Walk the body tracking brace depth
            depth = 0; started = 0; has_unsafe_block = 0
            prev_was_unsafe = 0

            for (j = n; j <= NR; j++) {
                line = lines[j]
                sub(/\/\/.*$/, "", line)

                # Allman style: "unsafe" alone on one line, "{" on the next
                if (prev_was_unsafe && line ~ /^[[:space:]]*\{/) has_unsafe_block = 1
                prev_was_unsafe = 0
                if (line ~ /[[:space:]]unsafe[[:space:]]*$/ || line ~ /^[[:space:]]*unsafe[[:space:]]*$/) prev_was_unsafe = 1

                for (k = 1; k <= length(line); k++) {
                    c = substr(line, k, 1)
                    if (c == "{") { depth++; started = 1 }
                    if (c == "}") depth--
                }
                # Same-line style: unsafe { ... }
                if (line ~ /unsafe[[:space:]]*\{/) has_unsafe_block = 1
                if (started && depth <= 0) break
            }

            if (has_unsafe_block) {
                printf "%s\t%d\t%s\t%s\n", RELFILE, fn_line, fn_name, fn_sig
            }

            # Skip past the body
            n = j
        }
    }
    ' RELFILE="${file#"$DIR"/}" "$file"
done
```

Results:

```bash
../scripts/find-csharp-unsafe-methods.sh src/libraries | head -36 
Scanning src/libraries for unsafe methods (explicit + implicit) ...
file	line	method	signature	reason
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Bignum.cs	14	BigNumToBinary	private static unsafe partial int BigNumToBinary(SafeBignumHandle a, byte* to);	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Cipher.cs	67	EvpCipherReset	private static unsafe partial bool EvpCipherReset(SafeEvpCipherCtxHandle ctx, byte* pIv, int cIv);	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Cipher.cs	141	EvpAeadCipherFinalEx	private static unsafe partial bool EvpAeadCipherFinalEx(	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Err.cs	30	ErrErrorStringN	private static unsafe partial void ErrErrorStringN(ulong e, byte* buf, int len);	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Evp.cs	33	EvpDigestOneShot	internal static unsafe partial int EvpDigestOneShot(IntPtr type, byte* source, int sourceSize, byte* md, uint* mdSize);	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Evp.cs	87	EvpDigestFinalXOF	internal static unsafe int EvpDigestFinalXOF(SafeEvpMdCtxHandle ctx, Span<byte> destination)	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Evp.cs	96	EvpDigestCurrentXOF	internal static unsafe int EvpDigestCurrentXOF(SafeEvpMdCtxHandle ctx, Span<byte> destination)	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Hmac.cs	32	HmacOneShot	private static unsafe partial int HmacOneShot(IntPtr type, byte* key, int keySize, byte* source, int sourceSize, byte* md, ref int mdSize);	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Random.cs	11	GetRandomBytes	internal static unsafe bool GetRandomBytes(byte* pbBuffer, int count)	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Random.cs	20	CryptoNative_GetRandomBytes	private static unsafe partial bool CryptoNative_GetRandomBytes(byte* buf, int num);	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Ssl.cs	71	RegisterRemoteCertificateValidationCallback	internal static unsafe partial void RegisterRemoteCertificateValidationCallback(	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Ssl.cs	129	SSLStreamSetApplicationProtocols	private static unsafe partial int SSLStreamSetApplicationProtocols(SafeSslHandle sslHandle, ApplicationProtocolData[] protocolData, int count);	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Ssl.cs	192	SSLStreamRead	private static unsafe partial PAL_SSLStreamStatus SSLStreamRead(	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.Ssl.cs	209	SSLStreamWrite	private static unsafe partial PAL_SSLStreamStatus SSLStreamWrite(	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.X509Chain.cs	76	X509ChainGetErrorprivate static unsafe partial int X509ChainGetErrors(	explicit
Common/src/Interop/Android/System.Security.Cryptography.Native.Android/Interop.X509Store.cs	16	X509StoreAddCertificate	internal static unsafe partial bool X509StoreAddCertificate(	explicit
Common/src/Interop/Browser/Interop.Locale.CoreCLR.cs	12	GetLocaleInfo	public static unsafe partial nint GetLocaleInfo(char* locale, int localeLength, char* culture, int cultureLength, char* buffer, int bufferLength, out int resultLength);	explicit
Common/src/Interop/Browser/Interop.Locale.Mono.cs	11	GetLocaleInfo	internal static extern unsafe nint GetLocaleInfo(char* locale, int localeLength, char* culture, int cultureLength, char* buffer, int bufferLength, out int resultLength);	explicit
Common/src/Interop/Browser/Interop.Runtime.CoreCLR.cs	14	BindJSImportST	public static unsafe partial nint BindJSImportST(void* signature);	explicit
Common/src/Interop/Browser/Interop.Runtime.Mono.cs	61	BindJSImportST	public static extern unsafe nint BindJSImportST(void* signature);	explicit
Common/src/Interop/BSD/System.Native/Interop.ProtocolStatistics.cs	37	GetTcpGlobalStatistics	public static unsafe partial int GetTcpGlobalStatistics(TcpGlobalStatistics* statistics);	explicit
Common/src/Interop/BSD/System.Native/Interop.ProtocolStatistics.cs	59	GetIPv4GlobalStatistics	public static unsafe partial int GetIPv4GlobalStatistics(IPv4GlobalStatistics* statistics);	explicit
Common/src/Interop/BSD/System.Native/Interop.ProtocolStatistics.cs	72	GetUdpGlobalStatistics	public static unsafe partial int GetUdpGlobalStatistics(UdpGlobalStatistics* statistics);	explicit
Common/src/Interop/BSD/System.Native/Interop.ProtocolStatistics.cs	102	GetIcmpv4GlobalStatistics	public static unsafe partial int GetIcmpv4GlobalStatistics(Icmpv4GlobalStatistics* statistics);	explicit
Common/src/Interop/BSD/System.Native/Interop.ProtocolStatistics.cs	138	GetIcmpv6GlobalStatistics	public static unsafe partial int GetIcmpv6GlobalStatistics(Icmpv6GlobalStatistics* statistics);	explicit
Common/src/Interop/BSD/System.Native/Interop.Sysctl.cs	18	Sysctl	private static unsafe partial int Sysctl(int* name, uint namelen, void* value, nuint* len);	explicit
Common/src/Interop/BSD/System.Native/Interop.TcpConnectionInfo.cs	33	GetActiveTcpConnectionInfos	public static unsafe partial int GetActiveTcpConnectionInfos(NativeTcpConnectionInformation* infos, int* infoCount);	explicit
Common/src/Interop/FreeBSD/Interop.Process.cs	79	GetProcPath	public static unsafe string GetProcPath(int pid)	explicit
Common/src/Interop/FreeBSD/Interop.Process.cs	104	GetProcessInfoById	public static unsafe ProcessInfo GetProcessInfoById(int pid)	explicit
Common/src/Interop/FreeBSD/Interop.Process.cs	156	GetThreadInfo	public static unsafe proc_stats GetThreadInfo(int pid, int tid)	explicit
Common/src/Interop/FreeBSD/Interop.Process.GetProcInfo.cs	127	size	private long ki_tsize;                      /* text size (pages) XXX */	implicit (unsafe type)
Common/src/Interop/Interop.Brotli.cs	17	BrotliDecoderDecompressStream	internal static unsafe partial int BrotliDecoderDecompressStream(	explicit
Common/src/Interop/Interop.Calendar.cs	16	GetCalendarInfo	internal static unsafe partial ResultCode GetCalendarInfo(string localeName, CalendarId calendarId, CalendarDataType calendarDataType, char* result, int resultCapacity);	explicit
Common/src/Interop/Interop.Calendar.cs	27	EnumCalendarInfo	private static unsafe partial bool EnumCalendarInfo(IntPtr callback, string localeName, CalendarId calendarId, CalendarDataType calendarDataType, IntPtr context);	explicit
Common/src/Interop/Interop.Casing.cs	12	ChangeCase	internal static unsafe partial void ChangeCase(char* src, int srcLen, char* dstBuffer, int dstBufferCapacity, [MarshalAs(UnmanagedType.Bool)] bool bToUpper);	explicit
```

Filtering for implicit:


```bash
../scripts/find-csharp-unsafe-methods.sh src/libraries | grep implicit |  head -36
Scanning src/libraries for unsafe methods (explicit + implicit) ...
Common/src/Interop/FreeBSD/Interop.Process.GetProcInfo.cs	127	size	private long ki_tsize;                      /* text size (pages) XXX */	implicit (unsafe type)
Common/src/Interop/Interop.Ldap.cs	195	GetPinnableReference	public static ref CLong GetPinnableReference(BerVal managed) => ref (managed is null ? ref Unsafe.NullRef<CLong>() : ref managed.bv_len);	implicit (unsafe type)
Common/src/Interop/Interop.Ldap.cs	244	FromManaged	public void FromManaged(LdapReferralCallback managed)	implicit (unsafe type)
Common/src/Interop/Interop.Ldap.cs	253	ToUnmanaged	public Native ToUnmanaged() => _native;	implicit (unsafe type)
Common/src/Interop/Interop.Ldap.cs	268	OnInvoked	public void OnInvoked() => GC.KeepAlive(_managed);	implicit (unsafe type)
Common/src/Interop/OSX/Swift.Runtime/UnsafeBufferPointer.cs	13	UnsafeBufferPointer	public UnsafeBufferPointer(T* baseAddress, nint count)	implicit (unsafe type)
Common/src/Interop/OSX/Swift.Runtime/UnsafeBufferPointer.cs	30	UnsafeMutableBufferPointer	public UnsafeMutableBufferPointer(T* baseAddress, nint count)	implicit (unsafe type)
Common/src/Interop/Unix/System.Native/Interop.IPAddress.cs	35	GetHashCode	public override int GetHashCode()implicit (unsafe type)
Common/src/Interop/Unix/System.Native/Interop.IPAddress.cs	42	Equals	public override bool Equals([NotNullWhen(true)] object? obj) =>	implicit (unsafe type)
Common/src/Interop/Unix/System.Net.Security.Native/Interop.GssBuffer.cs	19	Copy	internal int Copy(byte[] destination, int offset)	implicit (unsafe type)
Common/src/Interop/Unix/System.Net.Security.Native/Interop.GssBuffer.cs	58	Dispose	public void Dispose()	implicit (unsafe type)
Common/src/Interop/Windows/BCrypt/Interop.Blobs.cs	391	Create	public static BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO Create()	implicit (unsafe type)
Common/src/Interop/Windows/Interop.OBJECT_ATTRIBUTES.cs	46	OBJECT_ATTRIBUTES	public OBJECT_ATTRIBUTES(UNICODE_STRING* objectName, ObjectAttributes attributes, IntPtr rootDirectory, SECURITY_QUALITY_OF_SERVICE* securityQualityOfService = null)	implicit (unsafe type)
Common/src/Interop/Windows/Interop.SECURITY_QUALITY_OF_SERVICE.cs	18	SECURITY_QUALITY_OF_SERVICE	public SECURITY_QUALITY_OF_SERVICE(ImpersonationLevel impersonationLevel, ContextTrackingMode contextTrackingMode, bool effectiveOnly)	implicit (unsafe type)
Common/src/Interop/Windows/IpHlpApi/Interop.FIXED_INFO.cs	35	CreateString	private static string CreateString(ref byte firstByte, int maxLength)	implicit (unsafe type)
Common/src/Interop/Windows/IpHlpApi/Interop.NetworkInformation.cs	60	MarshalIPAddress	internal IPAddress MarshalIPAddress()	implicit (unsafe type)
Common/src/Interop/Windows/IpHlpApi/Interop.NetworkInformation.cs	79	MarshalIpAddressCollection	internal static InternalIPAddressCollection MarshalIpAddressCollection(IntPtr ptr)	implicit (unsafe type)
Common/src/Interop/Windows/IpHlpApi/Interop.NetworkInformation.cs	93	MarshalIpAddressInformationCollection	internal static IPAddressInformationCollection MarshalIpAddressInformationCollection(IntPtr ptr)	implicit (unsafe type)
Common/src/Interop/Windows/SspiCli/Interop.SSPI.cs	314	SecBufferDesc	public SecBufferDesc(int count)	implicit (unsafe type)
Common/src/Interop/Windows/WinHttp/Interop.winhttp.cs	72	Free	public static void Free(void* value) => NativeMemory.Free(value);	implicit (unsafe type)
Common/src/System/IO/MemoryMappedFiles/MemoryMappedFileMemoryManager.cs	15	MemoryMappedFileMemoryManager	public MemoryMappedFileMemoryManager(	implicit (unsafe type)
Common/src/System/IO/MemoryMappedFiles/MemoryMappedFileMemoryManager.cs	36	CreateFromFileClamped	internal static MemoryMappedFileMemoryManager CreateFromFileClamped(	implicit (unsafe type)
Common/src/System/IO/MemoryMappedFiles/MemoryMappedFileMemoryManager.cs	67	Dispose	protected override void Dispose(bool disposing)	implicit (unsafe type)
Common/src/System/IO/MemoryMappedFiles/MemoryMappedFileMemoryManager.cs	84	Pin	public override MemoryHandle Pin(int elementIndex = 0)	implicit (unsafe type)
Common/src/System/IO/MemoryMappedFiles/MemoryMappedFileMemoryManager.cs	90	Unpin	public override void Unpin()	implicit (unsafe type)
Common/src/System/IO/MemoryMappedFiles/MemoryMappedFileMemoryManager.cs	96	ThrowIfDisposed	private void ThrowIfDisposed()	implicit (unsafe type)
Common/src/System/Memory/PointerMemoryManager.cs	11	PointerMemoryManager	internal PointerMemoryManager(void* pointer, int length)	implicit (unsafe type)
Common/src/System/Memory/PointerMemoryManager.cs	17	Dispose	protected override void Dispose(bool disposing)	implicit (unsafe type)
Common/src/System/Memory/PointerMemoryManager.cs	26	Pin	public override MemoryHandle Pin(int elementIndex = 0)	implicit (unsafe type)
Common/src/System/Memory/PointerMemoryManager.cs	31	Unpin	public override void Unpin()	implicit (unsafe type)
Common/src/System/Runtime/InteropServices/SpanOfCharAsUtf8StringMarshaller.cs	33	FromManaged	public void FromManaged(ReadOnlySpan<char> managed, Span<byte> buffer)	implicit (unsafe type)
Common/src/System/Runtime/InteropServices/SpanOfCharAsUtf8StringMarshaller.cs	68	Free	public void Free()	implicit (unsafe type)
Common/tests/StreamConformanceTests/System/IO/StreamConformanceTests.cs	634	NativeMemoryManager	public NativeMemoryManager(int length) => _ptr = Marshal.AllocHGlobal(_length = length);	implicit (unsafe type)
Common/tests/StreamConformanceTests/System/IO/StreamConformanceTests.cs	642	Pin	public override MemoryHandle Pin(int elementIndex = 0)	implicit (unsafe type)
Common/tests/StreamConformanceTests/System/IO/StreamConformanceTests.cs	649	Unpin	public override void Unpin() => Interlocked.Decrement(ref PinRefCount);	implicit (unsafe type)
Common/tests/System/FunctionPointerEqualityTests.cs	111	MethodIntReturnValue1	public int MethodIntReturnValue1() => default;	implicit (unsafe type)
awk: towc: multibyte conversion failure on: '??", "ii" };'

 input record number 402, file src/libraries/System.Memory/tests/ReadOnlySpan/Count.T.cs
 source line number 7
```

C# is a very hard fail.

## Conclusion

The thesis on the inference task being a strong metric for descriptive quality is pretty much proven out. It's hard to imagine human, tool, or agentic flows being successful with high-inference requirements. It is true that ASTs and LSPs can help, but that's a poor substitute for a strong design. Strong designs are on clear display and we're very within reach of adopting one.

The characteristics we want are (in order):

- Explicit marking wher ambiguity/inference exists
- Disambuation between outer and interior unsafe
- Strong preference to signatures carrying safety information (all one line)

C# is currently in trailing last place for the languages considered. Without a lot of change, we could be in first place for this low inference metric. The argument is that the inference metric is _the_ metric.

