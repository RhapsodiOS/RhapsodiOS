# Foundation `NSScanner` numeric accessor order (2026-10-07)

Paired IDA decompilations of `-[NSScanner scanFloat:]` and
`-[NSScanner scanDouble:]` show both targets call the scanner accessors in this
order: `scanLocation`, `locale`, `charactersToBeSkipped`, then `string`. The
source previously called the latter three in the `_NSScanDoubleFromString`
argument list, where C does not guarantee their evaluation order.

`NSScanner.m` now stores each accessor result in a local in the observed order
before invoking the numeric parser. The i386 methods are at `0x4253af20` and
`0x4253afc0`; the PPC methods are at `0x425a547c` and `0x42557780`. Both
architectures agree. No ABI or parser behavior changed. Static source-order
checks and `git diff --check` only; no tests or builds were run.
