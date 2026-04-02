# Missing Safety Marker Proposal

Memory safety v2 is one of the highest-stakes features we have taken on. It bears directly on the most foundational value propositions of the language and runtime and on C#'s relationship to other industry languages. It demands our strictest design sensibilities.

This proposal adds a `safe` keyword to C# so that safety boundaries are explicitly marked, grep-discoverable, lossless under `git blame`, and exhaustive roots of the audit graph. The addition of `safe` makes safety markings symmetric: code participating in unsafety is marked with intent, not inferred by absence. It is important to remember that safe boundary methods still participate in unsafe code; they are made safe by a claim, not by compiler validation alone.

The `CopyTo` method is a concrete example of a method that would benefit from the `safe` keyword.

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

`CopyTo` upholds safety with a set of `ThrowIfNull` and range guards. These are safe precondition checks that justify the internal unsafe operation. By contrast, [Buffer.Memmove](https://github.com/dotnet/runtime/blob/0a726991ba412269ae8bb54ed3aa829466e0d0c8/src/libraries/System.Private.CoreLib/src/System/Buffer.cs#L134) sits closer to the sharp edge: it does not discharge the same obligations as broadly, nor does it depend on safe helper code in the same way. `Memmove` is unsafe code, even if that is not obvious in the example.

Note: C#, at the time of writing, does not force unsafe propagation, hence the lack of `unsafe` in `CopyTo`. This situation is addressed by the [CallerUnsafe proposal](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md).

The following Rust code is similar:

```rust
 pub fn swap(&mut self, i: usize, j: usize) {
     assert!(i < self.len());
     assert!(j < self.len());
     let ri = self.to_physical_idx(i);
     let rj = self.to_physical_idx(j);
     unsafe { ptr::swap(self.ptr().add(ri), self.ptr().add(rj)) }
 }
```

The runtime `assert!` calls in this function play a role analogous to `ThrowIfNull` and related guards in C#: they are safe precondition checks that justify the internal unsafe operation. The calls to `to_physical_idx` are also part of that proof. They are safe method calls whose correctness preserves the _fragile balance_ on which the safety claim depends. An explicit `safe` marker on `swap` would make it easier to determine algorithmically which safe functions participate in this safety claim. This same fragile-balance pattern is also common in the .NET runtime libraries.

`safe` therefore indicates three starting points:

- Where the safety claim is made and the safety audit has the most information.
- Where the unsafe call graph can be discovered.
- Where the safe call graph participating in safety validation can be discovered.

All of that can be done with a sophisticated compiler and semantic analysis API, like Roslyn. The more explicit the safety markings are, the more safety review can succeed by code inspection alone. It is fundamentally a statement about complexity and about reducing the amount of inference and deep language expertise required.

No safe-by-default language marks these boundary methods today, not C#, Rust, or Swift. Boundary methods are instead represented by the absence of an `unsafe` signature marking, as can be seen most clearly in the Rust example. The [C# CallerUnsafe](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md) proposal adds propagation, but adopts the same "absence is the marker for safety" approach.

The problem with absence being meaningful is that a single bit encodes a ternary state: unsafe, safe by best-effort intention, or safe by accident or malicious intention. The addition of a `safe` keyword explicitly reminds code writers and reviewers to match claim with code. Explicit `safe`/`unsafe` markings and unsafe propagation are likely our best leverage points for AI security migration (to the new model) and ongoing review at scale.

This proposal includes additional evidence and context that supports the idea that `safe` is beneficial. Part of that is a scoring scheme, based on the documented findings.

| Design | Score |
|--------|-------|
| C# (optimal) — `unsafe` + `safe`, default-on | **87.5%** |
| Rust | **77.5%** |
| C# + `unsafe` + `safe` (opt-in) | **72.5%** |
| Swift | **50.0%** |
| C# (current) | **35.0%** |

The scoring scheme boils down to three simple rules:

- Is the safety model uniform and sound?
- Is it explicit and clear in the code?
- Is it required to be used?

Generously, the opportunity for C# is quite significant. The combination of this proposal and CallerUnsafe includes significant breaking changes. It will be important to enable this new safety regime by default at some point. The existing safety system is dated and  is no longer sufficient for code like the standard library whose bread-and-butter is unsafety.

Proposal backing documents:

- A
- B

Related:

- [The `safe` keyword proposal](proposal.md) — critique of CallerUnsafe, the safety boundary pattern, the `safe` keyword, and grep-ability
- [The safety boundary concept](safety-boundary.md) — three-layer model, propagation vs encapsulation, detailed design
- [Safe code guarding unsafe operations](safe-guards-unsafe-examples.md) — real-world examples from .NET, Rust, and Swift standard libraries
- [Language comparison](language-comparison.md) — grep-based discoverability across D, Rust, Swift, and C#, in ranking order
- [Scoring methodology](scoring-methodology.md) — the grep test framework and detailed scoring
- [Appendices](appendices.md) — lossless attestations, xz backdoor lesson, binary distribution, agent workflows, keyword lineage
