# Scratch pad

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
