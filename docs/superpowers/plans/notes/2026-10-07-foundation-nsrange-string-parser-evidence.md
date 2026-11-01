# `NSRangeFromString` paired IDA evidence (2026-10-07)

The current `NSRangeFromString` in `NSRange.m` uses one decimal-digit scanner
for both targets. The paired implementations differ:

- DR2 i386 `_NSRangeFromString` at `0x425a22d0` allocates an `NSScanner`,
  disables its skipped-character set, then scans up to and matches
  `"location = "`, scans an integer, scans up to and matches `"length = "`,
  and scans the second integer. If any required scan fails, it returns
  `{0, 0}`. It releases the scanner before returning.
- MOSXS PPC `_NSRangeFromString` at `0x425c59ac` converts the string to a
  C string using a 1,024-byte stack buffer, allocating `length + 1` bytes
  when the string length exceeds 1,023. It searches for a digit or `+`, calls
  `__NSCStringToUnsignedLong`, searches from that end pointer for the next
  digit or `+`, and parses the second value. The helper supports signs and
  base autodetection, saturates overflow to `UINT_MAX`, and updates errno.

The i386 delimiter constants resolve to `"location = "` and `"length = "`.
`NSRange.m` now implements the scanner sequence on i386 and the target's
C-string and unsigned-parser path on PPC. The shared decimal-only helper was
removed. Neither target checks for nil before sending its length or
scanner-initializer message, so the source-level nil shortcut was removed to
preserve those target call paths.

As a neighboring check, `NSSubtractRange` at i386 `0x425a28a0` and PPC
`0x425c6134` matches the source branches and output ranges. No tests or builds
were run.
