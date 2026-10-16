# Foundation NSCalendarDate distant date singletons

Reference: Foundation i386 IDA database instance `d12fe2f23883`.

`+[NSCalendarDate distantFuture]` (`0x42596920`) and
`+[NSCalendarDate distantPast]` (`0x42596978`) lazily cache an allocated
calendar date initialized with reference-date intervals `63113990400.0` and
`-63113817600.0`, respectively. The target returns the cached instance
directly without autoreleasing it and does not lock the cache.

`NSCalendarDate.m` now implements both class methods with separate static
caches and the target intervals. The source selector audit now recognizes both
methods; its totals changed from 752 to 745 missing selectors, with zero
renames or duplicates and 135 extra selectors remaining.

The same pass filled the remaining IDA-confirmed `NSCalendarDate` lifecycle
overrides: `init` initializes from `_NSCurrentTime`, coder methods serialize
and restore the reference interval, time zone, and format string, and
`classForCoder` returns `NSCalendarDate`. `replacementObjectForPortCoder:`
returns the date for by-copy coding and a local distant-object proxy for
by-reference coding.

The source-only checks confirmed balanced Objective-C implementation blocks
and no trailing whitespace. No tests or builds were run.
