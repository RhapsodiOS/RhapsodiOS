# Foundation `NSData` bitvector and coding reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883`, the selector audit
against `C:\Users\raynorpat\Downloads\test\Foundation-i386`, and the
current `NSData.m` implementation.

## Reconstructed selectors

`NSData.m` now defines the following ABI gaps under their reference owners:

- `NSData`: `_compressIfNeeded`, `_decompressIfNeeded`,
  `_intersectsBitVectorMaybeCompressed:`, `classForCoder`, `encodeWithCoder:`,
  `hash`, `initWithCoder:`, `intersectionWithBitVector:`,
  `intersectsBitVector:`, `isEqualToBitVector:`, `mutableCopyWithZone:`,
  `numberOfSetBits`, `replacementObjectForPortCoder:`, and
  `unionWithBitVector:`.
- `NSMutableData`: `_unionBitVectorMaybeCompressed:`, `classForCoder`,
  `intersectBitVector:`, `serializeAlignedBytes:length:`, and
  `unionBitVector:`.

The coding methods follow the target's coder calls: NSData encodes and decodes
through `encodeDataObject:` and `decodeDataObject`, identifies as `NSData` for
coding, and returns itself as a port-coder replacement. Mutable data identifies
as `NSMutableData` and emits aligned bytes by serializing the length, appending
the payload, and extending to the next four-byte boundary. The mutable-copy
method at `0x4257d7cc` allocates `NSConcreteMutableData` in the requested zone
and initializes it from the source.

## Compressed bitvector format

IDA confirms `_compressIfNeeded` at `0x4257c600`, `_decompressIfNeeded` at
`0x4257c96c`, compressed intersection at `0x4257cb38`, ordinary set
operations at `0x4257d55c`, `0x4257d66c`, `0x4257d6f4`, `0x4257d804`, and
`0x4257d87c`, and mutable union helpers at `0x4258042c`, `0x425808b0`, and
`0x42580e40`.

The private representation removes runs of more than five zero bytes from the
payload and appends three-byte run records followed by a two-byte footer whose
first byte is the run count and second byte is zero. Record offsets address
the compressed payload. During decoding, each record copies from the current
compressed source offset to the recorded offset, then inserts the recorded
zero run. The compressor maps recorded compressed offsets back to source
coordinates by accounting for previously removed runs.

Bitvector union uses bytewise OR; intersection uses bytewise AND and truncates
to the common length. The intersection-length helper returns zero for no
overlap. The hash processes at most the final 16 bytes in reverse order and
folds any high nibble back into the low byte before clearing it, matching the
loop at `0x4257d180`.

## Verification

The selector audit after the NSData additions reported 3,034 source definitions
and 341 missing reference selectors, with zero renames and duplicates. A
follow-up owner audit found that the generic Objective-C type serialization
methods were defined under their base classes in source, while the reference
and `NSSerialization.h` declare them in `NSMutableDataObjcTypeSerialization`
and `NSDataObjCTypeDeserialization`. Their implementations in
`NSSerialization.m` now use those category owners. No method bodies changed.
After correcting the category ownership, the audit reports 3,034 definitions,
339 missing selectors, 119 extra selectors, and zero renames or duplicates.
The category ABI records now match both implementation owners.
`git diff --check` passed. No tests or builds were run.
