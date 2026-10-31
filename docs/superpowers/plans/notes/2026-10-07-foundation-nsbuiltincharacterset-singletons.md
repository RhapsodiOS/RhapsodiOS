# NSBuiltinCharacterSet singleton dispatch parity (2026-10-07)

Paired IDA decompilation confirms `+[NSBuiltinCharacterSet _setWithOffset:]`
indexes the 12-entry singleton array directly, allocates
`NSBuiltinCharacterSet` on a cache miss, initializes it with the offset, and
stores it in the array:

- i386 `Foundation-i386`: `_setWithOffset:` at `0x425215cc`.
- PPC `Foundation`: `_setWithOffset:` at `0x4252a960`.

Representative convenience selectors (`controlCharacterSet`,
`decimalDigitCharacterSet`, `punctuationCharacterSet`) send `_setWithOffset:`
to the concrete `NSBuiltinCharacterSet` class on both targets, rather than to
the method receiver.

The source previously returned `nil` for out-of-range offsets and used `self`
for allocation and convenience dispatch. It now follows the target's direct
array access and concrete-class dispatch. No ABI fields or selectors changed.
Static diff and whitespace checks only; no tests or build were run.
