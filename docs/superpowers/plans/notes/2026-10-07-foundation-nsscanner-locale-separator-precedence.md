# `_NSScanDoubleFromString` locale separator precedence (2026-10-07)

Paired IDA review of i386 `0x4252c568` and PPC `0x4252b948` shows that the
parser first consumes characters in `__NSNumberSet`; only after that scan does
it compare the next character with the locale decimal separator and append a
period for a match. The set includes `+`, `-`, `.`, digits, `E`, and `e`.

The original `NSScanner.m` loop checked `character == decimalSeparator` before
checking `NSScannerIsNumberCharacter(character)`. This reversed reference
precedence when a locale's decimal separator is itself in `__NSNumberSet`:
for example, `e` is parsed as an exponent marker in IDA but was rewritten to a
period by the source when the locale separator was `e`. The loop now consumes
number-set characters unchanged and rewrites a matching locale separator only
when it falls outside that set.

The remaining helper flow agrees across targets and source: skip-set handling,
32-unit input windows, 64-byte local buffer with 128-byte growth, target parser
selection (`strtod` on i386 and `_NSstrtod` on PPC), end-pointer validation,
and cursor advancement by skipped plus parsed characters. Static source/IDA
review only; no tests or builds were run.

## Decimal helper cross-check

The same precedence was checked in i386 `_NSScanDecimalFromString`
(`0x425a3020`) and PPC (`0x4255d7c8`). Both first consume
`__NSNumberSet` characters unchanged, then convert the next matching locale
separator to `.`. The current `NSScannerDecimalCursor` implementation already
has that two-stage structure, so this adjacent helper needs no source change.
