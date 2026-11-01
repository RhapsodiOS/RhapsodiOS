# `_NSSetEnumerator -initWithSet:` initialization parity (2026-10-07)

DR2 i386 IDA (`0x42533750`) and MOSXS PPC IDA (`0x425348b0`) initialize
`_slot`, identify counted sets, capture the corresponding simple dictionary or
simple set table, and set `_slot` from that table's bucket count. They retain
the set only when `_slot` is nonzero and return `self`; neither body calls
`[super init]`. `NSSet.m` now follows this sequence and no longer adds a
nil-receiver guard around the initializer body.

The paired `nextObject` bodies (i386 `0x42522c74`, PPC `0x4251c74c`) match the
source's descending bucket traversal, counted-set key versus set value result,
slot decrement, and target release when exhausted. Static paired IDA/source
review and whitespace checks only; no tests or builds were run.
