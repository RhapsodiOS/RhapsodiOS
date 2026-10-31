# NSImmutableStringCharacterSet bitmap parity (2026-10-07)

Paired IDA decompilation confirms `-[NSImmutableStringCharacterSet
bitmapRepresentation]` reconstructs an `NSString` from its inline characters,
creates a concrete mutable character set, requests that set's bitmap, then
copies the bitmap into a newly allocated `NSData` and autoreleases the copy:

- i386 `Foundation-i386`: `bitmapRepresentation` at `0x4258a658`.
- PPC `Foundation`: `bitmapRepresentation` at `0x425a2750`.

The source previously built and returned `NSMutableData` directly. It now uses
the target's concrete-set and immutable-data-copy path. This preserves the
target's return class and ownership behavior while leaving the ABI unchanged.
Static diff and whitespace checks only; no tests or build were run.
