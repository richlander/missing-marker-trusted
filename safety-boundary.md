# The Safety Boundary

## Safety is Established by Safe Code

In every memory-safe language with unsafe escape hatches, a recurring pattern emerges: safe code validates inputs before unsafe code ever sees them. Bounds checks, null checks, type validations, range constraints — all written in safe code, all guarding unsafe operations that would be unsound without them.

Here's a C# example from `String.CopyTo`:

```csharp
public void CopyTo(int sourceIndex, char[] destination, int destinationIndex, int count)
{
    ArgumentNullException.ThrowIfNull(destination);
    ArgumentOutOfRangeException.ThrowIfNegative(count);
    ArgumentOutOfRangeException.ThrowIfNegative(sourceIndex);
    ArgumentOutOfRangeException.ThrowIfGreaterThan(count, Length - sourceIndex, nameof(sourceIndex));
    ArgumentOutOfRangeException.ThrowIfGreaterThan(destinationIndex, destination.Length - count);
    ArgumentOutOfRangeException.ThrowIfNegative(destinationIndex);

    Buffer.Memmove(
        destination: ref Unsafe.Add(ref MemoryMarshal.GetArrayDataReference(destination), destinationIndex),
        source: ref Unsafe.Add(ref _firstChar, sourceIndex),
        elementCount: (uint)count);
}
```

Five lines of safe validation guard a single unchecked `Buffer.Memmove` call. Removing any one check could allow `Memmove` to read past the string or write past the destination array. The safety of the unsafe operation is entirely the responsibility of the safe code.

And from Rust:

```rust
pub const fn split_at_checked(&self, mid: usize) -> Option<(&[T], &[T])> {
    if mid <= self.len() {
        // SAFETY: `[ptr; mid]` and `[mid; len]` are inside `self`, which
        // fulfills the requirements of `split_at_unchecked`.
        Some(unsafe { self.split_at_unchecked(mid) })
    } else {
        None
    }
}
```

A single `mid <= self.len()` check guards `split_at_unchecked`, which does raw pointer arithmetic. Change `<=` to `<` and valid splits at the end are rejected. Remove the check entirely and arbitrary pointer arithmetic is exposed to callers.

In both .NET and Rust standard libraries, safe validation guarding unsafe operations is the standard pattern at the public API boundary. More examples are in [safe-guards-unsafe-examples.md](safe-guards-unsafe-examples.md).

The function that contains this pattern — safe validation guarding unsafe operations, presenting a safe interface to callers — is the **safety boundary**. It is the most critical audit target in any codebase that uses unsafe code.

## The Three-Layer Model

A three-layer safety model — safe, safety boundary, unsafe — is a recurring pattern in memory-safe language design:

| Layer | Role | Verified by |
|-------|------|-------------|
| Safe | Compiler-enforced safe subset | Compiler |
| Safety boundary | Contains unsafe operations, attests safety to callers | Human or agent |
| Unsafe | Raw operations, unsafe to call | Human or agent |

Safe code doesn't need manual review — the compiler verifies it by construction. Unsafe code needs review, but it's the safety boundary where the claim is made: "I have reviewed the interior unsafe code and attest that this function is safe to call." If that claim is wrong, the safe code that depends on it is silently unsound.

**Prior art.** D independently arrived at this architecture with `@safe`, `@trusted`, and `@system`. .NET had it earlier with the [Silverlight security transparency model](https://learn.microsoft.com/previous-versions/dotnet/framework/code-access-security/security-transparent-code) (Transparent, Safe Critical, Security Critical). Both validate the three-layer approach.

Neither fully realized it. D's unsafe-first default (`@system` is implicit) confines the model to code that explicitly opts into `@safe`. Safety boundaries (`@trusted`) only exist at the `@safe`-to-`@system` edge — `@system` code calls other `@system` code directly with no safety boundary in the graph. Silverlight's model was abandoned with the platform, not because the design was flawed.

**The safe-first property.** In a safe-first language like C# or Rust, the three-layer model has a critical structural property: all unsafe code must be rooted by safety boundary functions or it is dead code — no safe caller can reach it. Safety boundaries become the exhaustive roots of the audit graph, not just entry points from a safe subset. This is what separates safe-first languages from D's approach.

## Propagation and Encapsulation

The `unsafe` keyword operates through two parallel mechanisms:

**Propagation (virality).** When `unsafe` appears on a method signature, it propagates to callers — they must also be in an unsafe context to call it. The unsafety spreads upward through the call chain until it reaches a safety boundary that absorbs it. This creates a traceable chain from unsafe operations through to their safety boundary.

**Encapsulation (suppression).** When `unsafe` appears as an interior block within a method, the unsafety is encapsulated — hidden from callers, absorbed by the enclosing method. The method presents a safe interface. The caller has no indication that unsafe operations happen inside.

A key property of encapsulation: the implementation could change to use only safe code. The interior `unsafe` blocks would be removed, but the method's contract with its callers remains constant. The method was safe to call before; it's safe to call now. Nothing changes.

This means the safety boundary is defined by the method's **contract**, not its **implementation**. A method that is safe to call is safe to call regardless of whether it uses unsafe internally. The keyword should describe the contract.

## The `safe` Keyword for C\#

The [caller-unsafe design](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md) recognizes safety boundary functions but does not mark them. The proposal here: require `safe` or `unsafe` on every method with interior unsafe code. Absence of a marker is an error condition. The nature of each method is on clear display.

| Layer | C# syntax | Meaning |
|-------|-----------|---------|
| Safe | (unmarked) | No unsafe operations, can only call safe and `safe`-marked methods |
| Safety boundary | `safe` | Contains `unsafe` blocks, attests safety to callers |
| Unsafe | `unsafe` | Caller-unsafe, obligations must be discharged by caller |

```csharp
unsafe void Caller1()
{
    M();
}

safe void Caller2()
{
    unsafe
    {
        M();
    }
}

unsafe void M() { }

void SafeCaller()
{
    Caller2();  // OK — safe is callable from safe code
    // M();     // Error — unsafe requires unsafe context
}
```

- `Caller1` is caller-unsafe — its `unsafe` propagates to callers.
- `Caller2` is a safety boundary — it encapsulates `M()`'s unsafety and presents a safe interface.
- `SafeCaller` is pure safe code — the compiler verifies it by construction.
- `M` is unsafe — it requires an unsafe context to call.

All unmarked methods are implicitly safe. The three-layer model is exhaustive and non-overlapping — every path from safe to unsafe passes through `safe`.

**Why `safe`?** These methods operate as safe. The keyword describes what the method IS from its caller's perspective: safe to call. If the implementation evolves to use only safe operations, the `safe` keyword stays — the contract hasn't changed. `safe` and `unsafe` are natural antonyms. Rust's [RFC 3484](https://rust-lang.github.io/rfcs/3484-unsafe-extern-blocks.html) uses `safe` as a contextual keyword in extern blocks for exactly this pairing.

The compiler makes the same determination about both `safe` and `unsafe` methods: "I cannot verify the correctness of the unsafe operations inside." The difference is in the caller contract: `unsafe` says callers must handle the unsafety themselves; `safe` says the method has handled it.

**Design details.** As a contextual keyword modifier, `safe` occupies the same syntactic position as `unsafe` and inherits its design answers for interfaces, virtual methods, async methods, and delegates. If `unsafe` is valid on a method signature, `safe` is valid there too — they are complementary markers in the same design space. Methods inside an `unsafe class` that present a safe surface must use `safe` explicitly — eliminating the "implicit unsafe type" audit gap. Interior lambdas and local functions are covered by the enclosing `safe` method's attestation.

**Notes:**

- `safe` doesn't change the caller contract. If `Caller2` drops both `safe` and its interior `unsafe` blocks, nothing happens.
- If it is determined that `Caller2` cannot satisfy its safety obligation and is switched to caller-unsafe, that would be a break in the caller contract.
- There is also a separate question on whether outer `unsafe` solely informs propagation or also enables encapsulation. This proposal isn't about that.

### Migration

Like all the proposals in this space, opting in is a breaking change that requires work to compile without errors — the difference is degree, not kind.

1. Migration tooling scans for methods with interior `unsafe` blocks and marks them `unsafe` conservatively.
2. Developers triage each method: mark as `safe` (attests safety to callers) or leave as `unsafe` (propagates to callers). Methods can be temporarily marked as `safe` with accompanying comments that describe that auditing is needed.
3. The codebase compiles cleanly — every safety boundary is explicitly marked, enforced by errors.
4. Binaries built this way and distributed via NuGet are marked as "Memory Safety v2" giving consumers a new signal on security posture.

Ongoing, it is easy to track transitions between `unsafe` and `safe` with git. AI agents can be asked to periodically review the safety obligations of all `safe` methods, relying on source code and git history as inputs.

## Analysis of Alternatives

### `[RequiresUnsafe(bool)]`

The [unsafe evolution proposal](https://github.com/dotnet/csharplang/blob/main/proposals/unsafe-evolution.md) introduces `RequiresUnsafe` for caller-unsafe methods but leaves safety boundary functions unmarked. The attribute harbors a double-negative: `RequiresUnsafe(false)` means "does not require unsafe context" — negating a property rather than asserting one.

The tokenizer representation is not equivalent: `safe` and `unsafe` are each single tokens while `RequiresUnsafeAttribute(false)` spans seven. Like grep, the tokenizer is a proxy for representational complexity. Compound double-negative terms consume cognitive budget on disambiguation rather than the safety question itself.

See [Tokenizer Comparison](appendices.md#tokenizer-comparison) for details.

### No marker (current state and caller-unsafe proposals)

The [caller-unsafe design](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md) notes: "by presenting a safe API around an unsafe call, [the programmer is] asserting that all safety concerns of `M()` have been addressed." That assertion is the safety boundary — but the method has no marker on its signature. It is indistinguishable from a method that does not touch unsafe code.

The absence of a marker stores a ternary value with a single bit. We cannot know if a marker was deleted by accident or as a meaningful removal. Current C# stores this information in zero bits, which is even worse. A method that presents a safe facade over unsafe operations is the most critical audit target — and it is invisible.

## The End State

The performance substrate of C# becomes `ref`, `safe`, and `unsafe`:

- `ref` — safe pointer. Compiler-verified. Zero-copy access with lifetime tracking. No audit needed.
- `safe` — safety boundary. Human-verified. The audit target.
- `unsafe` — raw operations. Human-verified. The implementation detail inside `safe`.

The grep-friendly audit surface is `safe` and `unsafe`. The performance surface migrates (as is already the case) to `ref`, in the safe subset.

With a fully-specified model, there is no end of agent prompts that users can ask about a codebase and expect an accurate and efficient answer:

- "Describe the primary concerns of the safety boundary within System.IO classes."
- "Which safe or unsafe methods would be better written as ref?"
- "List all safe methods in System.Security that were modified in the last 6 months."
- "For this PR, review every safe method that was added or modified."

These prompts are currently expensive in C# — and in D, Rust, and Swift. With `safe`, prompt 1 becomes a single `rg -w "safe" --type cs src/libraries/System.IO*` command. The model reads the bodies of the results and answers directly.

## Grep-ability

The uniform grep pattern with both `safe` and `unsafe` keywords:

```bash
rg -w 'safe' --type cs           # Find safety boundaries
rg 'unsafe fn\|unsafe void\|unsafe static' --type cs   # Find unsafe declarations  
rg 'unsafe\s*\{' --type cs       # Find unsafe blocks
```

These are simple and will always hit. They enable a variety of workflows: discovery of the safety boundary at its roots, the unsafe surface area at its leaves, or unsafe blocks generally.

Without a `safe` keyword, finding safety boundary methods requires a script that parses function bodies to look for interior `unsafe` blocks — an approximation with known false positives, not an authoritative answer. See [language-comparison.md](language-comparison.md) for grep commands and results across D, Rust, Swift, and C#.
