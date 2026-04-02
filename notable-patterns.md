# Notable Patterns in Safety-Boundary Code

## The Same Algorithm, Three Languages

Bounds-checked element access is the most fundamental safety boundary operation. All three languages implement it the same way: validate the index in safe code, then return a reference via unsafe pointer arithmetic.

### C# — `Span<T>` indexer

**File:** [src/libraries/System.Private.CoreLib/src/System/Span.cs#L148](https://github.com/dotnet/runtime/blob/a8836bb928cbb045bb19a1a2a3353f4aa23302f4/src/libraries/System.Private.CoreLib/src/System/Span.cs#L148) (dotnet/runtime)

```csharp
public ref T this[int index]
{
    get
    {
        if ((uint)index >= (uint)_length)
            ThrowHelper.ThrowIndexOutOfRangeException();
        return ref Unsafe.Add(ref _reference, (nint)(uint)index);
    }
}
```

### Rust — `[T]` slice indexing

**File:** [library/core/src/slice/index.rs#L218](https://github.com/rust-lang/rust/blob/e6b64a2f4c696b840f8a384ec28690eed6a5d267/library/core/src/slice/index.rs#L218) (rust-lang/rust)

```rust
fn get(self, slice: &[T]) -> Option<&T> {
    if self < slice.len() {
        // SAFETY: `self` is checked to be in bounds.
        unsafe { Some(slice_get_unchecked(slice, self)) }
    } else {
        None
    }
}
```

### Swift — `InputSpan<T>` subscript

**File:** [Sources/ContainersPreview/Types/InputSpan.swift#L246](https://github.com/apple/swift-collections/blob/63bfbed01a39126550b0f1ac87ac48027697831a/Sources/ContainersPreview/Types/InputSpan.swift#L246) (apple/swift-collections)

```swift
public subscript(_ index: Index) -> Element {
    unsafeAddress {
      precondition(indices.contains(index), "Index out of bounds")
      return unsafe UnsafePointer(_unsafeAddressOfElement(uncheckedOffset: index))
    }
}
```

### Summary

**Why this matters:** Three languages, three teams, the same conclusion: a safe bounds check is the only thing between a valid element access and undefined behavior. The unsafe pointer arithmetic is identical in purpose — offset a base pointer by an index — and the safe guard is what makes it sound. Remove or weaken the check in any of them and the result is an out-of-bounds read or write.

This is the safety boundary pattern. The safety boundary function is the one that performs the check and calls the unsafe operation. It is the most critical audit target in all three codebases — and in none of these safe-by-default languages is it marked. D's `@trusted` is the sole prior art for explicit marking, but D is unsafe-by-default, so its safety boundaries only cover the `@safe` subset. When these guards fail, the result is a CVE — see the [CVE analysis](cve-analysis.md) for real examples of this pattern breaking.

## C# / .NET Runtime (dotnet/runtime)

> **Note:** Modern .NET avoids literal `unsafe { }` blocks in favor of `Unsafe.*` APIs
> and `Buffer.Memmove`, which are equally unchecked — the pattern is the same.

### [C#] Span.cs — `Span<T>.Slice`
**File:** [src/libraries/System.Private.CoreLib/src/System/Span.cs#L414](https://github.com/dotnet/runtime/blob/a8836bb928cbb045bb19a1a2a3353f4aa23302f4/src/libraries/System.Private.CoreLib/src/System/Span.cs#L414)
**Pattern:** Bounds-checks `start + length` against `_length` using overflow-safe unsigned arithmetic, then constructs a new span via unchecked `Unsafe.Add`.

```csharp
public Span<T> Slice(int start, int length)
{
#if TARGET_64BIT
    // The cast to uint before ulong ensures zero-extension, not sign-extension.
    // If either input is negative or if start+length overflows Int32.MaxValue,
    // that's captured in the comparison against _length.
    if ((ulong)(uint)start + (ulong)(uint)length > (ulong)(uint)_length)
        ThrowHelper.ThrowArgumentOutOfRangeException();
#else
    if ((uint)start > (uint)_length || (uint)length > (uint)(_length - start))
        ThrowHelper.ThrowArgumentOutOfRangeException();
#endif

    return new Span<T>(ref Unsafe.Add(ref _reference, (nint)(uint)start), length);
}
```

**Why this matters:** An off-by-one in the bounds check (e.g., `>=` instead of `>`) would let `Unsafe.Add` produce a reference past the buffer — an out-of-bounds read/write with no further checks.

---

### [C#] Buffer.cs — `Buffer.BlockCopy`
**File:** [src/libraries/System.Private.CoreLib/src/System/Buffer.cs#L18](https://github.com/dotnet/runtime/blob/a8836bb928cbb045bb19a1a2a3353f4aa23302f4/src/libraries/System.Private.CoreLib/src/System/Buffer.cs#L18)
**Pattern:** Validates nulls, primitive-array types, negative offsets, and total byte ranges, then calls `Memmove` with unchecked pointer arithmetic.

```csharp
public static void BlockCopy(Array src, int srcOffset, Array dst, int dstOffset, int count)
{
    ArgumentNullException.ThrowIfNull(src);
    ArgumentNullException.ThrowIfNull(dst);

    nuint uSrcLen = src.NativeLength;
    if (src.GetType() != typeof(byte[]))
    {
        if (!src.GetCorElementTypeOfElementType().IsPrimitiveType())
            throw new ArgumentException(SR.Arg_MustBePrimArray, nameof(src));
        uSrcLen *= (nuint)src.GetElementSize();
    }
    // ... same for dst ...

    ArgumentOutOfRangeException.ThrowIfNegative(srcOffset);
    ArgumentOutOfRangeException.ThrowIfNegative(dstOffset);
    ArgumentOutOfRangeException.ThrowIfNegative(count);

    if ((uSrcLen < uSrcOffset + uCount) || (uDstLen < uDstOffset + uCount))
        throw new ArgumentException(SR.Argument_InvalidOffLen);

    Memmove(
        ref Unsafe.AddByteOffset(ref MemoryMarshal.GetArrayDataReference(dst), uDstOffset),
        ref Unsafe.AddByteOffset(ref MemoryMarshal.GetArrayDataReference(src), uSrcOffset),
        uCount);
}
```

**Why this matters:** If the range check on line 51 used `<=` instead of `<`, or if the element-size multiplication overflowed, `Memmove` would copy past allocated memory — a classic buffer overread/overwrite.

---

### [C#] String.cs — `String.CopyTo`
**File:** [src/libraries/System.Private.CoreLib/src/System/String.cs#L427](https://github.com/dotnet/runtime/blob/a8836bb928cbb045bb19a1a2a3353f4aa23302f4/src/libraries/System.Private.CoreLib/src/System/String.cs#L427)
**Pattern:** Five separate argument validations guard a single unchecked `Buffer.Memmove` call on the string's raw internal char data.

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

**Why this matters:** Removing any single check could allow `Memmove` to read past the string or write past the destination array — the safety of the `unsafe` operation is entirely the responsibility of these five lines of safe code.

---

### [C#] MemoryExtensions.cs — `string.AsSpan(start, length)`
**File:** [src/libraries/System.Private.CoreLib/src/System/MemoryExtensions.cs#L192](https://github.com/dotnet/runtime/blob/a8836bb928cbb045bb19a1a2a3353f4aa23302f4/src/libraries/System.Private.CoreLib/src/System/MemoryExtensions.cs#L192)
**Pattern:** Null-checks the string and bounds-checks the slice range before constructing a `ReadOnlySpan<char>` from the string's raw internal data via `Unsafe.Add`.

```csharp
public static ReadOnlySpan<char> AsSpan(this string? text, int start, int length)
{
    if (text == null)
    {
        if (start != 0 || length != 0)
            ThrowHelper.ThrowArgumentOutOfRangeException(ExceptionArgument.start);
        return default;
    }

#if TARGET_64BIT
    if ((ulong)(uint)start + (ulong)(uint)length > (ulong)(uint)text.Length)
        ThrowHelper.ThrowArgumentOutOfRangeException(ExceptionArgument.start);
#else
    if ((uint)start > (uint)text.Length || (uint)length > (uint)(text.Length - start))
        ThrowHelper.ThrowArgumentOutOfRangeException(ExceptionArgument.start);
#endif

    return new ReadOnlySpan<char>(ref Unsafe.Add(ref text.GetRawStringData(), (nint)(uint)start), length);
}
```

**Why this matters:** This creates a span that aliases a string's internal buffer. A wrong bounds check means the span could extend past the string's allocation — exposing arbitrary heap memory to safe callers.

---

## Rust Standard Library (rust-lang/rust)

### [Rust] vec/mod.rs — `Vec::swap_remove`
**File:** [library/alloc/src/vec/mod.rs#L2224](https://github.com/rust-lang/rust/blob/e6b64a2f4c696b840f8a384ec28690eed6a5d267/library/alloc/src/vec/mod.rs#L2224)
**Pattern:** Bounds-checks `index < len`, then enters `unsafe` to do raw pointer read/copy and `set_len`.

```rust
pub fn swap_remove(&mut self, index: usize) -> T {
    #[cold]
    fn assert_failed(index: usize, len: usize) -> ! {
        panic!("swap_remove index (is {index}) should be < len (is {len})");
    }

    let len = self.len();
    if index >= len {
        assert_failed(index, len);
    }
    unsafe {
        let value = ptr::read(self.as_ptr().add(index));
        let base_ptr = self.as_mut_ptr();
        ptr::copy(base_ptr.add(len - 1), base_ptr.add(index), 1);
        self.set_len(len - 1);
        value
    }
}
```

**Why this matters:** If the bounds check used `>` instead of `>=`, passing `index == len` would cause `ptr::read` to read one element past the end — UB from a one-character typo in the *safe* code.

---

### [Rust] vec/mod.rs — `Vec::set_len`
**File:** [library/alloc/src/vec/mod.rs#L2188](https://github.com/rust-lang/rust/blob/e6b64a2f4c696b840f8a384ec28690eed6a5d267/library/alloc/src/vec/mod.rs#L2188)
**Pattern:** An `unsafe fn` protects a private field on [`Vec`](https://github.com/rust-lang/rust/blob/e6b64a2f4c696b840f8a384ec28690eed6a5d267/library/alloc/src/vec/mod.rs#L438-L441) by enforcing a language-backed but convention-driven invariant: `len <= capacity()`.

```rust
pub unsafe fn set_len(&mut self, new_len: usize) {
    ub_checks::assert_unsafe_precondition!(
        check_library_ub,
        "Vec::set_len requires that new_len <= capacity()",
        (new_len: usize = new_len, capacity: usize = self.capacity()) => new_len <= capacity
    );
    self.len = new_len;
}
```

**Why this matters:** `self.len` is just a normal private field assignment inside the standard library, but writing the wrong value would break `Vec`'s core representation invariant and make later safe operations unsound. Rust does enforce the API boundary — external callers cannot mutate `len` directly, and `set_len` is explicitly `unsafe fn` — but the invariant itself is not fully enforced by the type system at the write site. This is a notable Rust pattern: the rule is language-backed and documented, yet correctness still depends on convention, review, and the caller honoring the contract.

---

### [Rust] slice/mod.rs — `[T]::swap`
**File:** [library/core/src/slice/mod.rs#L905](https://github.com/rust-lang/rust/blob/e6b64a2f4c696b840f8a384ec28690eed6a5d267/library/core/src/slice/mod.rs#L905)
**Pattern:** Safe indexing (`self[a]`, `self[b]`) panics on out-of-bounds, producing raw pointers that are then swapped via `unsafe { ptr::swap }`.

```rust
pub const fn swap(&mut self, a: usize, b: usize) {
    let pa = &raw mut self[a];
    let pb = &raw mut self[b];
    // SAFETY: `pa` and `pb` have been created from safe mutable references and refer
    // to elements in the slice and therefore are guaranteed to be valid and aligned.
    unsafe {
        ptr::swap(pa, pb);
    }
}
```

**Why this matters:** The safe indexing *is* the bounds check. If this used `get_unchecked_mut` instead of `self[a]`, out-of-bounds indices would silently produce dangling pointers.

---

### [Rust] slice/mod.rs — `[T]::split_at_checked`
**File:** [library/core/src/slice/mod.rs#L2153](https://github.com/rust-lang/rust/blob/e6b64a2f4c696b840f8a384ec28690eed6a5d267/library/core/src/slice/mod.rs#L2153)
**Pattern:** A single `mid <= self.len()` check guards `split_at_unchecked`, which does raw pointer arithmetic.

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

**Why this matters:** Changing `<=` to `<` would reject `mid == len` (a valid split at the end). Changing it to omit the check entirely would allow arbitrary pointer arithmetic inside `split_at_unchecked`.

---

### [Rust] string.rs — `String::split_off`
**File:** [library/alloc/src/string.rs#L1912](https://github.com/rust-lang/rust/blob/e6b64a2f4c696b840f8a384ec28690eed6a5d267/library/alloc/src/string.rs#L1912)
**Pattern:** Asserts the split point is a UTF-8 char boundary before calling `from_utf8_unchecked`.

```rust
pub fn split_off(&mut self, at: usize) -> String {
    assert!(self.is_char_boundary(at));
    let other = self.vec.split_off(at);
    unsafe { String::from_utf8_unchecked(other) }
}
```

**Why this matters:** Without the `is_char_boundary` check, splitting mid-codepoint would create a `String` containing invalid UTF-8 — violating Rust's type invariant and causing UB in any code that assumes strings are valid UTF-8.

---

### [Rust] str/mod.rs — `str::split_once`
**File:** [library/core/src/str/mod.rs#L1966](https://github.com/rust-lang/rust/blob/e6b64a2f4c696b840f8a384ec28690eed6a5d267/library/core/src/str/mod.rs#L1966)
**Pattern:** The `Searcher` API guarantees valid byte indices; `get_unchecked` trusts those indices to avoid redundant bounds checks.

```rust
pub fn split_once<P: Pattern>(&self, delimiter: P) -> Option<(&'_ str, &'_ str)> {
    let (start, end) = delimiter.into_searcher(self).next_match()?;
    // SAFETY: `Searcher` is known to return valid indices.
    unsafe { Some((self.get_unchecked(..start), self.get_unchecked(end..))) }
}
```

**Why this matters:** A buggy `Searcher` implementation returning indices that don't land on char boundaries would cause `get_unchecked` to produce invalid `&str` slices — the safety of this method depends entirely on the correctness of the `Searcher` trait contract (safe code).

---

## Swift (apple/swift-collections)

[apple/swift-collections](https://github.com/apple/swift-collections) is one of the first libraries to adopt [SE-0458](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md) strict memory safety annotations.

### [Swift] InputSpan.swift — `subscript(_:)`
**File:** [Sources/ContainersPreview/Types/InputSpan.swift#L246](https://github.com/apple/swift-collections/blob/63bfbed01a39126550b0f1ac87ac48027697831a/Sources/ContainersPreview/Types/InputSpan.swift#L246)
**Pattern:** Bounds-checks the index against the initialized range before returning a raw pointer to the element via `_unsafeAddressOfElement`.

```swift
public subscript(_ index: Index) -> Element {
    unsafeAddress {
      precondition(indices.contains(index), "Index out of bounds")
      return unsafe UnsafePointer(_unsafeAddressOfElement(uncheckedOffset: index))
    }

    @_lifetime(self: copy self)
    unsafeMutableAddress {
      precondition(indices.contains(index), "Index out of bounds")
      return unsafe _unsafeAddressOfElement(uncheckedOffset: index)
    }
  }
```

**Why this matters:** Without the `precondition`, an out-of-bounds index would produce a raw pointer into uninitialized or unowned memory — reads would return garbage, writes would corrupt the heap. The safe bounds check is the only thing between the caller and undefined behavior. Note the companion `subscript(unchecked:)` which skips this check and is marked `@unsafe`.

---

### [Swift] InputSpan.swift — `swapAt(_:_:)`
**File:** [Sources/ContainersPreview/Types/InputSpan.swift#L284](https://github.com/apple/swift-collections/blob/63bfbed01a39126550b0f1ac87ac48027697831a/Sources/ContainersPreview/Types/InputSpan.swift#L284)
**Pattern:** Validates both indices against the initialized range, then delegates to the unchecked `@unsafe` variant which does raw pointer moves.

```swift
public mutating func swapAt(_ i: Index, _ j: Index) {
    precondition(indices.contains(Index(i)))
    precondition(indices.contains(Index(j)))
    unsafe swapAt(unchecked: i, unchecked: j)
  }

  @unsafe
  public mutating func swapAt(unchecked i: Index, unchecked j: Index) {
    guard i != j else { return }
    let pi = unsafe _unsafeAddressOfElement(uncheckedOffset: i)
    let pj = unsafe _unsafeAddressOfElement(uncheckedOffset: j)
    let temporary = unsafe pi.move()
    unsafe pi.initialize(to: pj.move())
    unsafe pj.initialize(to: consume temporary)
  }
```

**Why this matters:** The safe `swapAt` validates both indices before calling the unsafe variant that performs raw pointer `move()` and `initialize(to:)` operations. Passing an out-of-bounds index to the unchecked version would move from uninitialized memory or overwrite an unrelated heap object. This is a direct parallel to Rust's `[T]::swap` — safe indexing guards unsafe pointer operations.

---

## The common thread

Every example above follows the same structure: safe code validates inputs, then delegates to an unsafe operation that trusts the validation. The safety boundary is the function where that handoff occurs. None of these functions are marked in any safe-by-default language — they are invisible to grep and indistinguishable from functions that are safe all the way down. An explicit `safe` keyword would make every one of these functions discoverable.

The [CVE analysis](cve-analysis.md) shows what happens when these guards fail. The [language comparison](language-comparison.md) scores how discoverable these patterns are across D, Rust, Swift, and C#.
