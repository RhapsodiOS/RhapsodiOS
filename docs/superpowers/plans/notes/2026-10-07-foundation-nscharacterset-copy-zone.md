# NSConcreteMutableCharacterSet copy-zone parity (2026-10-07)

Paired IDA decompilation confirms `-[NSConcreteMutableCharacterSet
mutableCopyWithZone:]` allocates the destination in the requested zone but
copies existing backing `data` with `copyWithZone:NULL` on both targets:

- i386 `Foundation-i386`: method at `0x4258965c`.
- PPC `Foundation`: method at `0x425a14b4`.

The source previously passed the requested zone to the backing-data copy. It
now passes `NULL` as the target does. The separate bitmap and compact-set copy
paths continue using the requested zone. No ABI fields or selectors changed.
Static diff and whitespace checks only; no tests or build were run.
