# Foundation autorelease-pool `addObject:` parity

Paired IDA review of `-[NSAutoreleasePool addObject:]` (i386
`0x425732d8`, PPC `0x42582fe0`) found that both targets ignore nil, call
`NSAutoreleaseObject` first, then read the current thread's pool data. When a
pool stack exists, they move the just-autoreleased object from the current page
into each intervening pool record until reaching the receiver's token. The
target only skips the transfer when the receiver is already the top pool.

`NSAutoreleasePool.m` previously rejected missing data or tokens at/above the
current depth before autoreleasing. It now preserves the target call order,
checks for a missing/empty pool stack after autoreleasing, skips transfer only
for the top token, and uses the target's `token < depth - 1` loop condition.
This also preserves the target behavior for a stale token beyond the active
depth. Static paired IDA/source review and `git diff --check` only; no tests or
builds were run.

The paired drain implementations also match the current `NSPopAutoreleasePool`
source: i386 `0x425073e8`, PPC `0x425104c0`. Both drain page objects down to
the selected cursor, catch release exceptions and continue pool teardown,
recycle up to four exact `NSAutoreleasePool` instances, clear the affected
records, update subclass routing, and return empty pages to the free list.
The retain/autorelease/dealloc guards match the paired i386 bodies at
`0x42573454`, `0x425733d0`, and `0x4257341c`. These checks establish static
source parity; runtime warning and exception behavior remains untested.
