# `NSScanner` string-scan method parity (2026-10-07)

Compared `scanString:intoString:`, `scanUpToString:intoString:`,
`scanUpToCharactersFromSet:intoString:`, and `isAtEnd` in DR2 i386 and MOSXS
PPC with `NSScanner.m`.

The target methods consistently skip the leading configured character set by
searching for a character in its inverse, use `NSCaseInsensitiveSearch` when
`caseSensitive` is false, and leave the scan location unchanged when the
resulting search endpoint equals the post-skip start. `scanString:` returns the
substring from the post-skip start through the found string and advances past
that match. The two `scanUpTo` methods return the substring before their
delimiter and advance to the delimiter; when no delimiter is found they use
the end of the input. `isAtEnd` checks whether any non-skipped character
remains without changing the scanner.

The current source follows those sequences. Target bodies: i386
`0x4254d66c`, `0x42547d94`, `0x42552804`, and `0x4255299c`; PPC
`0x425a5cd8`, `0x425a5e7c`, `0x4255a89c`, and `0x4255ad88`. No source or ABI
change was needed. Static paired IDA/source review only; no tests or builds
were run.
