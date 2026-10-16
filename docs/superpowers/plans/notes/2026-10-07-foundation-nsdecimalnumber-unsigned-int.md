# `NSDecimalNumber` unsigned conversion target paths (2026-10-07)

Paired IDA review:

- DR2 i386 `unsignedCharValue` (`0x4259c3c8`), `unsignedShortValue`
  (`0x4259c4b0`), `unsignedIntValue` (`0x4259c408`), and `unsignedLongValue`
  (`0x4259c470`) send `doubleValue`, set the x87 rounding mode to truncate,
  convert to a 64-bit signed integer, and return the declared low-width result.
- MOSXS PPC `unsignedCharValue` (`0x425bff74`) and `unsignedShortValue`
  (`0x425c00e8`) convert the `doubleValue` result to signed 32-bit with
  `fctiwz`, then return the declared low-width result.
- MOSXS PPC `unsignedIntValue` (`0x425bffb8`) and `unsignedLongValue`
  (`0x425c006c`) compare against binary64 `2^31` (`0x425e2558` and
  `0x425e2560`). Values at or above `2^31` subtract that threshold before
  signed 32-bit conversion, then XOR the result with `0x80000000`; smaller
  values convert directly to signed 32-bit.
- `unsignedLongLongValue` is separate: i386 converts through `long double` to
  `double` and then unsigned 64-bit (`0x4259c448`); PPC casts the `double`
  result directly to unsigned 64-bit (`0x425c0034`). The existing source
  preserves that distinction.

`NSDecimalNumber.m` routed the first four methods through a 64-bit signed
conversion before narrowing. That expresses the i386 route, but does not
preserve PPC's target-specific 32-bit conversion sequence for values outside
the signed 32-bit range. The source now keeps the existing i386 path and adds
the PPC-specific signed 32-bit conversion for the narrow methods plus the
observed `2^31` adjustment and sign-bit XOR for `unsignedIntValue` and
`unsignedLongValue`. `unsignedLongLongValue` remains unchanged because its
target-specific paths were already preserved. No ABI change was needed. Static
paired IDA/source review and whitespace checks only; no tests or builds were
run.

The neighboring methods were checked in the same pass. `boolValue`,
`floatValue`, `intValue`, and `longValue` send `doubleValue` and cast to their
declared result type on both targets, matching the current source. `isEqual:`
checks identity, verifies the other object is an `NSNumber`, and compares the
result with `NSOrderedSame`; its current source follows the same sequence.
