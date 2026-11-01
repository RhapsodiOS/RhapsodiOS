# Foundation NSConcreteMutableData method analysis

Reference: Foundation i386 IDA database d12fe2f23883 and
src/Kits/Foundation/reconstruction/abi/NSData.json.

## Reconstructed methods

NSConcreteMutableData now owns the 14 methods confirmed at these addresses:

- _bytesAreVM (0x4253e658)
- deserializeIntAtCursor: (0x4252fd9c)
- deserializeIntAtIndex: (0x4257a208)
- deserializeInts:count:atIndex: (0x4257a2a0)
- initWithBytes:length:copy:freeWhenDone:bytesAreVM: (0x42541be8)
- release (0x4252f8cc)
- retain (0x4253fa10)
- retainCount (0x42558228)
- serializeAlignedBytes:length: (0x4250dffc)
- serializeAlignedBytesLength: (0x4257a530)
- serializeInt: (0x4250bce4)
- serializeInt:atIndex: (0x42511b50)
- serializeInts:count: (0x4257a64c)
- serializeInts:count:atIndex: (0x4257a6bc)

The integer serialization and deserialization paths use little-endian 32-bit
values. Indexed writes extend the data as needed and zero any gap between the
old end and the requested index. The array methods access consecutive values
directly after one range check.

The private byte initializer delegates capacity setup, copies the input, and
ignores its copy flag. When freeWhenDone is set, it frees the source after
copying; VM storage is released with the page-rounded length. The VM query
reads storage flag bit 2. The retain-count overrides share NSConcreteData's
packed flags/count word, global lock, saturation behavior, and allocation
statistics events.

Aligned length and payload serialization use a 32-bit length header normally.
For sufficiently large payloads that would not begin on a page boundary, the
reference writes the 0x80000000 marker, byte length, page padding, and zeroed
padding. Payload serialization also rounds the record end to four bytes and
clears those trailing bytes.

The owner audit reports all 26 NSConcreteMutableData ABI methods present.
The framework selector audit moved from 2,991 to 3,005 definitions and from
384 to 370 missing selectors, with zero renames or duplicates.
git diff --check passed. No tests or builds were run.
