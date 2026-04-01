# Missing Marker Proposal Summary

Memory safety v2 is one of the most high-stakes features that we've taken on. It directly relates to the most foundational value propositions of the language and runtime and to other industry languages. It's where we have to adopt our most strict and critical design sensibilities.

This proposal starts with an example from an [Andy Gocke](https://github.com/agocke): [CallerUnsafe](https://github.com/dotnet/designs/blob/main/accepted/2025/memory-safety/caller-unsafe.md).

The following content is copied from the CallerUnsafe proposal, without modification.

## Andy's "CallerUnsafe" proposal (unmodified; subsetted)

We need to be able to annotate code as unsafe, even if it doesn't use pointers.

Mechanically, this would be done with a modification to the C# language and a new property to the compilation. When the compilation property "EnableRequiresUnsafe" is set to true, the `unsafe` keyword on C# _members_ would require that their uses appear in an unsafe context. An `unsafe` block would be unchanged -- the statements in the block would be in an unsafe context, while the code outside would have no requirements.

For example, the code below would produce an error:

```C#
void Caller()
{
    M(); // error, the call to M() is not in an unsafe context
}

unsafe void M() { }
```

This can be addressed by callers in two ways:

```C#
unsafe void Caller1()
{
    M();
}
void Caller2()
{
    unsafe
    {
        M();
    }
}
unsafe void M() { }
```

In the case of `Caller1`, the call to `M()` doesn't produce an error because it is inside an unsafe context. However, calls to `Caller1` will now produce an error for the same reason as `M()`.

`Caller2` will also not produce an error because `M()` is in an unsafe context. However, this code creates a responsibility for the programmer: by presenting a safe API around an unsafe call, they are asserting that all safety concerns of `M()` have been addressed.

Notably, unsafe did not change the requirement that the code in the block must be correct. It merely offset the responsibility from the language and the runtime to the user in verification.

## Rich's Critique

In general, the proposal is great.

Concerns:

- `Caller2` is more critical to audit than `M` by virtue of being safe-callable. It is holding up a safety boundary, while `M` has no such reponsibility other than via developer documentation ("this is how I can be safely used").
- `M` is trival to identify and discover via its `unsafe` marker while `Caller2` is only identifiable by looking for methods with interior `unsafe` blocks and no `unsafe` method signature. It's identification by absense.
- It's possible such a method could be actually unsafe and switched to safe-callable on purpose or accident. Changes that simultaneously become dangerous and whose right-side diff collapses to a valid empty string are a footgun.
- Caller-unsafe methods do not need to guarantee safety for safe callers, nor do `unsafe` blocks within a caller-safe method. It is only caller-safe method as a whole which has the responsibility to offer a safe facade.
- Both caller-unsafe and caller-safe unsafe methods deserve review. The same patterns should work for both or else we may find that one gets less review.

## Caller-safe Method Safety Boundary

> It is only caller-safe method as a whole which has the responsibility to offer a safe facade.

That's a big claim. It can only be interpreted one way: the discharging of safety obligations can be done in safe code.

Here's a good example from C#

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

And another from Rust:

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

In both .NET and Rust standard libraries, safe validation guarding unsafe operations appears to be the standard pattern at the public API boundary. This strengthens the claim that caller-safe methods are special and deserve at least equal treatment as caller-unsafe methods.

[More examples](./safe-guards-unsafe-examples.md).

## Rich's "safe" proposal

Require `safe` or `unsafe` on every method with interior unsafe code. Absense of a marker is an error condition. The nature of each method is on clear display.

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
```

Notes:

- `safe` doesn't change the caller contract. If `Caller2` drops both `safe` and its interior `unsafe` blocks, nothing happens.
- If it is determined that `Caller2` cannot satisfy its safety obligation and is switched to caller-unsafe, then that would be a break in the caller contract. Clearly, that's an anti-pattern.
- There is also a separate question on whether outer unsafe solely inform propogation or also encapsulation. This proposal isn't about that. I took the examples from Andy's proposal as-is.

## Grep-ability

Here's the quite nice and uniform grep pattern if both `safe` and `unsafe` keywords are required:

```bash
grep -nE '\bsafe\b.*\(' file.cs
grep -nE '\bunsafe\b.*\(' file.cs
grep -rnE 'unsafe\s*\{' files.cs
```

Those are simple and will always hit. They enable a variety of workflows, discovery of the safety boundary at its roots, the unsafe surface area at its leaves, or unsafe blocks generally.

Here's the matching grep w/no `safe` keyword for the caller-safe unsafe methods.

```bash
grep -nP '^\s*(public|private|protected|internal|static|virtual|override|abstract|sealed|async|partial|\w+)\s+\w+\s*\(' file.cs | grep -v '\bunsafe\b'
```

This one is far uglier and also won't work in many cases. It's only offered as a sort of failure case. No one is going to do this. An argument could be made that `grep` doesn't matter, but also needs to extend to clear attestation, and the git diff footgun not mattering.

Search ergonomics are a fitness property of the safety model. Language-specific tools are part of that and so is grep. Rust and Swift have the exact same challenge. This proposal offers an opportunity to evolve the memory safety domain, that explicit markings are critical for the entirety of the unsafe domain. We aspire to make our memory safety model agent friendly. This keyword is a clear leverage point for that. The addition of the keyword will make agent enablement easier and increase confidence by eliminating the footgun.
