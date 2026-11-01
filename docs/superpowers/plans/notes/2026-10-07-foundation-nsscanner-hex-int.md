# Foundation `NSScanner scanHexInt:` paired IDA evidence (2026-10-07)

DR2 i386 implements `-[NSScanner scanHexInt:]` at `0x4258def4`; MOSXS PPC
implements it at `0x425a554c`. Both skip leading characters in the configured
skip set, accept hexadecimal digits with an optional `0x`/`0X` prefix, and
accumulate into an unsigned result that saturates at `UINT_MAX`. A nonzero
prefix with no following hex digit is still a successful scan of zero, and the
cursor is left on the `x`/`X`; an unprefixed invalid first character fails
without advancing the cursor. A lone zero scans successfully as zero.

`-[NSScanner scanHexInt:]` in `NSScanner.m` now reads up to 32 UTF-16 code units
with `getCharacters:range:` and refills the local buffer as scanning advances.
The existing skip-set, optional-prefix, overflow, and scan-location behavior
is preserved, including the target's success-with-zero result for an invalid
first digit after `0x`/`0X`. This also matches the target's string access
dispatch for NSString subclasses. Static source/IDA review and `git diff
--check` only; no tests or builds were run.
