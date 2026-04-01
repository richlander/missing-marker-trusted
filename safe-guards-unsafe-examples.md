# Safe Code Guards Unsafe Block — Real-World Examples

## C# / .NET Runtime (dotnet/runtime)

> **Note:** Modern .NET avoids literal `unsafe { }` blocks in favor of `Unsafe.*` APIs
> and `Buffer.Memmove`, which are equally unchecked — the pattern is the same.

### [C#] Span.cs — `Span<T>.Slice`
**File:** src/libraries/System.Private.CoreLib/src/System/Span.cs (lines 414-431)
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
**File:** src/libraries/System.Private.CoreLib/src/System/Buffer.cs (lines 18-55)
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
**File:** src/libraries/System.Private.CoreLib/src/System/String.cs (lines 427-441)
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
**File:** src/libraries/System.Private.CoreLib/src/System/MemoryExtensions.cs (lines 192-211)
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
**File:** library/alloc/src/vec/mod.rs (lines 2216-2238)
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

### [Rust] slice/mod.rs — `[T]::swap`
**File:** library/core/src/slice/mod.rs (lines 905-917)
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
**File:** library/core/src/slice/mod.rs (lines 2153-2161)
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
**File:** library/alloc/src/string.rs (lines 1912-1916)
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
**File:** library/core/src/str/mod.rs (lines 1966-1970)
**Pattern:** The `Searcher` API guarantees valid byte indices; `get_unchecked` trusts those indices to avoid redundant bounds checks.

```rust
pub fn split_once<P: Pattern>(&self, delimiter: P) -> Option<(&'_ str, &'_ str)> {
    let (start, end) = delimiter.into_searcher(self).next_match()?;
    // SAFETY: `Searcher` is known to return valid indices.
    unsafe { Some((self.get_unchecked(..start), self.get_unchecked(end..))) }
}
```

**Why this matters:** A buggy `Searcher` implementation returning indices that don't land on char boundaries would cause `get_unchecked` to produce invalid `&str` slices — the safety of this method depends entirely on the correctness of the `Searcher` trait contract (safe code).
