# Foundation `NSScanner` floating-token buffer growth (2026-10-07)

Paired IDA decompilations of `_NSScanDoubleFromString` show a 64-byte local
buffer and lazy 128-byte growth when the token reaches the final writable byte.
The first heap growth copies the full 64-byte local buffer; subsequent growth
uses `NSZoneRealloc`. The source instead allocated storage sized to the entire
remaining input before knowing how much of it formed the numeric token.

`NSScanner.m` now uses the same lazy growth helper for floating and decimal
tokens. This avoids allocating for unrelated trailing text and preserves the
target's storage progression. Static comparison used PPC `_NSScanDoubleFromString`
at `0x4252b948` and i386 at `0x4252c568`. The source/ownership manifests are
unchanged. Static source checks and `git diff --check` only; no tests or builds
were run.

The same helper's decimal use was then checked against `_NSScanDecimalFromString`
in both live databases: i386 `0x425a3020` and PPC `0x4255d7c8`. Both targets
use the same 64-byte local buffer, grow by 128 bytes before overwriting the
terminator slot, copy all 64 local bytes on first growth, and reallocate on
later growth. Both use the 32-code-unit string cursor, skip-set handling,
locale decimal separator conversion to `.`, and parser-reported consumed
length for the final scan location. `NSScannerAppendNumberCharacter` matches
those allocation and cursor rules, so no further source change was needed for
the decimal path. This check was static; no tests or builds were run.

## Locale separator edge (2026-10-07)

The i386 and PPC `_NSScanDecimalFromString` bodies also use
`characterAtIndex:0` whenever the locale lookup returns a nonnil decimal
separator; neither checks its length. `NSScanner.m` now follows that behavior,
matching the floating scanner helper's locale path. A nonnil empty separator
therefore takes the target's out-of-range character access. Static comparison
only; no tests or builds were run.
