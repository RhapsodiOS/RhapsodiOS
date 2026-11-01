# Foundation character conversion dispatcher

Reconstructed the missing dispatch cases in `NSCharConversion.m` against both
Foundation IDA databases:

- i386 `_NSConvertToASCIIorUnicode2`: `0x42505944`.
- PPC `_NSConvertToASCIIorUnicode2`: `0x425044e8`.

The single-byte switch confirms ISO Latin-2 (encoding 9) uses
`NSISOLatin2ToPrecompUnicode`, CP1251 (11) uses
`NSAdobeStandardCyrillicToUnicode`, and the existing CP1252/1253/1254/1250,
NEXTSTEP, and MacRoman handlers match the target switch. ISO-2022-JP (21) uses
eight two-byte escape sequences with states for ASCII, Kana, and JIS X 0208,
converting the Japanese payload through `NSNextEUCToUnicode`. The sequences
and modes in the implementation match the `_IsoJISSequences` data in both
databases.

Both targets use a cursor-advancing decoder signature for UTF-8, EUC, Shift-JIS,
and the proprietary callback. Updated the private proprietary callback typedef
and forwarding wrapper to preserve that ABI, then connected the dispatcher to
the existing EUC, Shift-JIS, and proprietary decoders. The UTF-8 and shared
multibyte paths preserve the ASCII C-string fast path and clear allocated
result state on decoder failure, as in IDA. Updated the NSParser declaration
for `NSNextEUCToUnicode` to keep the shared prototype consistent.

Static review and `git diff --check` only; no build or tests were run.

## `NSShiftJISToUnicode` current source parity recheck (2026-10-08)

Re-decompiled the live i386 body at `0x4259203c` and PPC body at
`0x425a97cc`. Both return ASCII and half-width-kana directly after advancing
the source cursor by one byte. Other inputs pass through `NSShiftJISToEUC`; a
nonzero consumed count advances the source cursor and delegates the temporary
EUC bytes to `NSNextEUCToUnicode` with the original remaining-length argument.
Failed conversions advance one source byte and return zero. The current
`NSCharConversion.m` implementation follows these branches and cursor updates,
so the earlier “remains unimplemented” entry in the C-symbol inventory is
stale. Static paired IDA/source review only; no tests or builds were run.
