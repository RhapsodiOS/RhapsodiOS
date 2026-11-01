# Foundation `NSScanner` integer scan parity (2026-10-07)

Compared the existing `scanHexInt:`, `scanInt:`, and `scanLongLong:` paths in
`NSScanner.m` with the DR2 i386 and MOSXS PPC IDA databases. The wrapper
accessor order for `scanLongLong:` is scan location, skipped-character set,
then string on both targets; the source now evaluates those getters
sequentially in that order instead of relying on C argument evaluation. The
source integer helpers match the targets' 32-code-unit cursor, optional sign and
post-sign skip-set pass, decimal-digit-set check, saturating overflow, output
write, and consumed-location update.

Both `NSConcreteScanner scanInt:` wrappers pass `&_scanLocation` directly to
`_NSScanIntFromString`. Source previously parsed into a local cursor and then
called `setScanLocation:`; it now passes the ivar directly, preserving the
target's direct mutation and avoiding an extra setter call.

`scanDecimal:` now explicitly evaluates scan location, locale, skipped set,
then string, matching both target wrappers. `scanHexInt:` fetches the string,
scan location, string length, then
skipped-character set, matching the order in both targets. It preserves the
target's unusual prefix handling: after `0x` or `0X`, a missing or invalid
first hex digit succeeds with value zero and leaves the scan location
immediately after the leading zero. Hex overflow saturates to `UINT_MAX`, and
an invalid initial character leaves the location unchanged. The PPC and i386
implementations agree on these behaviors.

The digit conversion preserves another target edge case: after membership in
`decimalDigitCharacterSet` succeeds, both binaries map code units outside ASCII
`'0'` through `'9'` to `-1` during accumulation. The source helpers now use that
same conversion in both 32-bit and long-long scans; they previously subtracted
`'0'` from every decimal-set member. This keeps the target's signed result and
overflow behavior for non-ASCII decimal digits.

The same cursor/API pass found the target reads string, scan location, length,
then skip set in `scanString:intoString:`, `scanCharactersFromSet:intoString:`,
both `scanUpTo…intoString:` methods, and `isAtEnd`. The source now follows this
order. The source also discarded `caseSensitive` in
`scanCharactersFromSet:intoString:`; both targets pass the inverse of that flag
as the options argument when searching the inverted caller set. The source now
uses that option while keeping the skip-set search case-sensitive as in IDA.
The range-method addresses are i386 `scanString:` `0x4254d66c`,
`scanCharactersFromSet:` `0x4258dd44`, `scanUpToString:` `0x42547d94`,
`scanUpToCharactersFromSet:` `0x42552804`, and `isAtEnd` `0x4255299c`; PPC
addresses are `0x425a5cd8`, `0x425a52c8`, `0x425a5e7c`, `0x4255a89c`, and
`0x4255ad88`, respectively.

IDA addresses: i386 `scanHexInt:` `0x4258def4`, `scanInt:` `0x4258e43c`,
`scanLongLong:` `0x4258e4fc`, and `scanDecimal:` `0x4259f120`; PPC
`scanHexInt:` `0x425a554c`, `scanInt:` `0x425a5b38`, `scanLongLong:`
`0x425a5c34`, and `scanDecimal:` `0x4255d6dc`. The source call-order
corrections do not alter ABI metadata. Static
decompilation/source comparison only; no tests or builds were run.
