# NSRefCountingNumber reconstruction notes

Reference: Foundation i386 IDA database `d12fe2f23883`.

IDA confirms `NSRefCountingNumber` as the superclass of the eight primitive
number classes and as a direct subclass of `NSNumber`. Its instance layout
contains the `refs` word at offset 4. The source declarations now represent
that intermediate class and use it as the superclass for each primitive
number implementation.

The four class-owned methods were decompiled from:

- `retain` at `0x4251e94c`: increment `refs` with mask `-1` under
  `_NSGlobalRetainLock`, then return `self`.
- `release` at `0x4251a3f8`: decrement `refs` with mask `-1` under the same
  lock and send `dealloc` when the helper reports zero.
- `retainCount` at `0x4259f104`: return `_NSInternalRefCount(self, refs, -1)`.
- `copyWithZone:` at `0x4253fe7c`: retain when
  `NSShouldRetainWithZone` is true; otherwise `NSCopyObject` with no extra
  bytes and reset the copied `refs` word to zero.

The methods are now implemented in `NSValue.m` according to those bodies. No
tests or builds were run.

## Primitive number hash category owners (2026-10-03)

IDA confirms the `_NSHash` category methods for `NSunsignedIntNumber`,
`NSintNumber`, `NSunsignedShortNumber`, and `NSshortNumber` return the stored
`value` field directly. `NSValue.m` now implements each under the exact category
owner. The focused ABI audit reports four expected selectors with no missing or
duplicate definitions; `git diff --check` is clean. Tests and builds were not
run.
