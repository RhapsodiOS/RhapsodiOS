# `NSGeometryFromString` paired IDA evidence (2026-10-07)

The current `NSGeometry.m` shares `NSGeometryScanNumber` across i386 and PPC.
The target parsers instead use architecture-specific paths:

- DR2 i386 `NSPointFromString` (`0x425a2180`), `NSSizeFromString`
  (`0x425a2648`), and `NSRectFromString` (`0x425a2420`) allocate an
  `NSScanner`, disable skipped characters, and require each geometry
  punctuation token before scanning each float. Point and size return their
  zero struct when any required scan fails; rect writes four zero floats on
  failure. The final closing token is not scanned after the last value.
- MOSXS PPC `NSPointFromString` (`0x425c5814`), `NSSizeFromString`
  (`0x425c5d8c`), and `NSRectFromString` (`0x425c5b00`) convert to a
  C-string buffer (1,024-byte stack buffer, `length + 1` allocation above
  1,023), skip to candidate signs or digits, and parse values with
  `__NSstrtod`. They then scan from each end pointer to the next candidate
  sign or digit. These paths do not validate the punctuation grammar.

The shared source accepted arbitrary nonnumeric separators and treated each
missing number as zero, so it did not reproduce the i386 grammar. Its
character-by-character numeric tokenization also differed from PPC's
`_NSstrtod` input and end-pointer handling.

## Reconstruction (2026-10-07)

`NSGeometry.m` now uses the i386 labeled `NSScanner` path and the PPC C-string
path. The PPC disassembly confirms that point and size write a terminator at
`buffer[length - 1]`, while rect writes it at `buffer[length]`; the source
preserves that difference, including the before-buffer store for an empty
point/size string. PPC scans candidate digits, `-`, `.`, and `+`, calls
`_NSstrtod`, and resumes at its end pointer. The i386 helpers require the
exact `x = `, `y = `, `width = `, and `height = ` labels and zero the full
result when a required scan fails. No ABI manifest or selector changes were
needed. Static checks only; no tests or builds were run.
