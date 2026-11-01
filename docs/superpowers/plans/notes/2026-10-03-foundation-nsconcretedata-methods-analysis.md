# Foundation NSConcreteData method analysis

Reference: Foundation i386 IDA database d12fe2f23883 and
src/Kits/Foundation/reconstruction/abi/NSData.json.

## Reconstructed methods

NSConcreteData now owns the ten methods confirmed at these IDA addresses:

- getBytes: (0x42579040)
- getBytes:length: (0x425790b4)
- getBytes:range: (0x42579134)
- deserializeIntAtIndex: (0x42578ea0)
- deserializeInts:count:atIndex: (0x42578f50)
- deserializeIntAtCursor: (0x4250156c)
- deserializeAlignedBytesLengthAtCursor: (0x42502d7c)
- retain (0x42512f90)
- release (0x42513984)
- retainCount (0x42579244)

The byte-copy methods use NSCopyMemoryPages for aligned whole pages and
memmove for the remaining bytes. The range form is a no-op for zero length,
raises when a nonempty range starts at or beyond the data length, and truncates
a range that extends past the end. The two scalar integer readers decode
little-endian values. The cursor readers use the same byte layout; the aligned
length form advances the cursor by four bytes before checking the two-word
extended-length record, matching the reference even when that check raises.

The array integer reader validates index + count * 4. In inline-storage mode
(_flags & 1), IDA starts at the first inline byte and ignores index; the source
preserves this behavior. In external-storage mode it starts at _bytes + index.

The retain-count word consists of _flags, _padding[3], and the retain count in
the high bits. The overrides preserve the low three storage flags, use
_NSGlobalRetainLock, saturate at 0x1fffffff, and record the internal reference
events when allocation statistics are enabled.

Static selector audit moved from 2,981 to 2,991 definitions and reduced
missing selectors from 394 to 384, with zero renames or duplicates.
git diff --check passed. No tests or builds were run.
