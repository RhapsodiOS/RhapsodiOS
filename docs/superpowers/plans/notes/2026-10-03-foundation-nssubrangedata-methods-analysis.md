# Foundation NSSubrangeData method analysis

Reference: Foundation i386 IDA database d12fe2f23883 and
src/Kits/Foundation/reconstruction/abi/NSData.json.

## Reconstructed methods

NSSubrangeData now owns the ten methods confirmed at these addresses:

- copyWithZone: (0x42582af8)
- deserializeIntAtCursor: (0x42582b64)
- deserializeIntAtIndex: (0x42582c28)
- deserializeInts:count:atIndex: (0x42582cdc)
- getBytes: (0x42582de0)
- getBytes:length: (0x42582e64)
- init (0x4258315c)
- release (0x425831b4)
- retainCount (0x4258326c)
- retain (0x42583280)

The copy method ignores its zone and returns a retained self. The two byte-copy
methods read from the beginning of the represented range and use page copying
for aligned whole pages. The integer readers bounds-check against the subrange
length, decode little-endian 32-bit values, and translate offsets through the
backing data's byte pointer. The cursor reader advances only after a successful
bounds check.

The no-argument initializer raises NSGenericException with the reference
message that it should never be called. Retain, release, and retainCount use
the reference count stored in the high bits of _reserved, preserve its low
three bits, and follow the shared global-lock and allocation-statistics paths.

The owner audit reports all 16 NSSubrangeData ABI methods present. The
framework selector audit moved from 3,005 to 3,015 definitions and from 370
to 360 missing selectors, with zero renames or duplicates.
git diff --check passed. No tests or builds were run.
