# Missing Safety Marker Proposal

Memory safety v2 is one of the highest-stakes features we have taken on. It bears directly on the most foundational value proposition of the language and to how C# is compared to other industry languages. It demands both critical and ambitious design sensibilities.

This proposal adds a `safe` keyword to C# so that safety boundaries are explicitly marked, grep-discoverable, lossless under `git blame`, and form exhaustive roots of the audit graph. The addition of `safe` makes safety markings symmetric: code participating in unsafety is marked with intent, not inferred by absence. It is important to remember that safe boundary methods harbour unsafety; they are made safe by a claim, not by compiler validation.

The two keywords work together to enforce a workflow across methods, libraries, and packages:

- `unsafe` propagates a contract with obligation documentation
- `safe` encapsulates the contract and discharges obligations with guards

The supporting [CVE Analysis](./cve-analysis.md) demonstrates that CVEs are often in safe guards and can occur as often in boundary methods as in caller-unsafe methods.

## Examples

The [`CopyTo` method](https://github.com/dotnet/runtime/blob/a8836bb928cbb045bb19a1a2a3353f4aa23302f4/src/libraries/System.Private.CoreLib/src/System/String.cs#L427) is a concrete example of a method that would benefit from the `safe` keyword.

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

`CopyTo` upholds safety with a set of `ThrowIfNull` and other `ThrowIf*` range guards. These are safe precondition checks that justify the internal unsafe operation. By contrast, [Buffer.Memmove](https://github.com/dotnet/runtime/blob/0a726991ba412269ae8bb54ed3aa829466e0d0c8/src/libraries/System.Private.CoreLib/src/System/Buffer.cs#L134) is unsafe and sits at the sharp edge: it does not discharge the obligations as broadly, nor does it depend on safe helper code in the same way. `Memmove` is an `unsafe` method, even if that is not obvious in the example.

Note: C#, at the time of writing, does not force unsafe propagation, hence the lack of `unsafe` in `CopyTo`. This situation is addressed by the [CallerUnsafe proposal](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md).

The [`swap` function](https://github.com/rust-lang/rust/blob/e6b64a2f4c696b840f8a384ec28690eed6a5d267/library/alloc/src/collections/vec_deque/mod.rs#L970) in Rust is similar:

```rust
 pub fn swap(&mut self, i: usize, j: usize) {
     assert!(i < self.len());
     assert!(j < self.len());
     let ri = self.to_physical_idx(i);
     let rj = self.to_physical_idx(j);
     unsafe { ptr::swap(self.ptr().add(ri), self.ptr().add(rj)) }
 }
```

The runtime `assert!` calls in this function play a role analogous to `ThrowIfNull` and related guards in C#. The calls to `to_physical_idx` are also part of that proof. They are safe method calls whose correctness preserves the _fragile balance_ on which the safety claim depends. An explicit `safe` marker on `swap` would make it easier to determine algorithmically which safe functions participate in this safety claim. This same fragile-balance pattern is also common in the .NET runtime libraries.

This example from Rust includes `SAFETY` documentation.

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

## Safe role

`safe` therefore indicates three starting points:

- Where the safety claim is made and the safety audit has complete information.
- Where the unsafe call graph can be discovered; provides unsafe implementations.
- Where the safe call graph can be discovered; provides "safe defence" implementations.

If a method with interior unsafe code is intended to remain safe-callable, that status should be explicit rather than inferred from the absence of `unsafe`. Otherwise one missing marker has to carry too much meaning: genuinely safe boundary method, accidentally unmarked method, or intentionally misleading code. That ambiguity is exactly what explicit `safe` is meant to remove.

Discovery and auditing can be accomplished without new syntax, relying on a sophisticated compiler and semantic analysis API, like Roslyn. The more explicit the safety markings are, the more safety review can succeed by code inspection alone. That's the pitch. This is fundamentally about reducing the amount of inference and deep language expertise required. Some concerns have been raised about the proposal being double-marking. This is not the place for reservations about economy. A single CVE outspends any perceived savings on language syntax.

No safe-by-default language marks these boundary methods today, not C#, Rust, or Swift. The [C# CallerUnsafe](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md) proposal adds propagation, but adopts the same "absence is the marker for safety" approach.

Rust has prior art with `safe`. In [RFC 3484 — unsafe extern blocks](https://rust-lang.github.io/rfcs/3484-unsafe-extern-blocks.html), Rust added `safe` in a narrow FFI context to distinguish items that are safe to call from ones that remain `unsafe`. That does not yet solve the boundary-method problem shown by `swap`, but it does establish both the keyword and the design precedent. A future Rust edition could in principle expand that usage toward ordinary safety-boundary methods and move closer to the model proposed here. The CallerUnsafe proposal also adopts `safe extern`.

The problem with absence being meaningful is that a single bit encodes a ternary state: unsafe, safe by best-effort intention, or safe by accident or malicious intention. The [xz incident with Jia Tan](https://en.wikipedia.org/wiki/XZ_Utils_backdoor) relied heavily on subtle diffs to trick reviewers and it worked. The addition of a `safe` keyword explicitly reminds code writers and reviewers to match claim with code. Diffs will always have `safe` or `unsafe` on both sides — never empty string — unless unsafe code has been removed entirely, at which point validation transitions to the compiler. These defense-in-depth measures are simultaneously our best leverage points for AI security migration (to the new model) and ongoing review at scale. Explicit keywords provide context without inference.

## Grep-ability

Here's the uniform grep pattern if both `safe` and `unsafe` keywords are required:

```bash
rg -w "safe" --type cs src/libraries         # safety boundary signatures
rg -w "unsafe" --type cs src/libraries       # unsafe signatures + blocks
rg "unsafe\s*\{" --type cs src/libraries     # unsafe blocks only
```

Pivot the keyword, narrow to blocks. Simple, symmetric, always accurate. These enable discovery of the safety boundary at its roots, the unsafe surface area at its leaves, and unsafe blocks generally.

Without the `safe` keyword, finding caller-safe unsafe methods requires something like:

```bash
grep -nP '^\s*(public|private|protected|internal|static|virtual|override|abstract|sealed|async|partial|\w+)\s+\w+\s*\(' file.cs | grep -v '\bunsafe\b'
```

This is far uglier and won't work in many cases. It's offered as a failure case — no one is going to do this. The argument that grep doesn't matter has to extend to clear attestation and the git diff footgun not mattering either.

Search ergonomics are a fitness property of the safety model. Language-specific tools are part of that and so is grep. Rust and Swift have the exact same challenge. This proposal offers an opportunity to evolve the memory safety domain: explicit markings are critical for the entirety of the unsafe domain. We aspire to make our memory safety model agent friendly. This keyword is a clear leverage point for that. The addition of an explicit keyword will make agent enablement easier and increase confidence by eliminating the footgun and offering implicit skills for agents that are asked to review C#.

## Scoring

The supporting documents below define the full scoring methodology. At a high level, the model rewards safety designs that are sound, explicit, and enforced, and penalizes designs that blur those signals.

| Design | Score |
|--------|-------|
| C# (optimal) — `unsafe` + `safe`, default-on | **87.5%** |
| Rust | **77.5%** |
| C# + `unsafe` + `safe` (opt-in) | **72.5%** |
| C# + `unsafe` keyword (no `safe`) | **50.0%** |
| Swift | **50.0%** |
| D | **40.0%** |
| C# (current) | **35.0%** |
| C# + `RequiresUnsafe` | **35.0%** |

The scoring model boils down to three questions:

- Is the safety model uniform and sound?
- Is the relevant safety information explicit and grep-discoverable in the code?
- Is the model enforced by default?

The detailed methodology then adds demerits for grep ambiguity and other audit friction. Generously, the opportunity for C# is quite significant. Moving to a stronger, explicit safety regime includes significant breaking changes. It will be important to enforce this new safety regime at some point. The existing safety system is dated and is no longer sufficient for code like the standard library whose bread-and-butter is unsafety.

## Supporting documents

- [Notable patterns](notable-patterns.md) — real-world examples from .NET, Rust, and Swift standard libraries
- [Language comparison](language-comparison.md) — grep-based discoverability across D, Rust, Swift, and C#, in ranking order
- [Scoring methodology](scoring-methodology.md) — the grep test framework and detailed scoring
- [Appendices](appendices.md) — lossless attestations, xz backdoor lesson, binary distribution, agent workflows, keyword lineage
