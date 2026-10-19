# `NSDecimalNumber -doubleValue` precision (2026-10-07)

Compared `-[NSDecimalNumber doubleValue]` in both IDA targets:

- DR2 i386: `0x4259bf34` accumulates the mantissa, applies the decimal
  exponent, and applies the sign using `long double` operations.
- MOSXS PPC: `0x425bf924` uses `double` throughout. Its constants at
  `0x425e2538`, `0x425e2540`, `0x425e2548`, and `0x425e2550` are respectively
  `0.0`, `65536.0`, `4503601774854144.0` (the biased integer-conversion
  adjustment), and `10.0`.

`NSDecimalNumber.m` now uses a `double` accumulator and `double` constants on
PPC, preserving rounding at each operation, and retains the `long double`
accumulator on i386. Both paths walk the mantissa from the highest stored word,
apply the decimal exponent one step at a time, and apply the sign last.

The implementation is limited to `-doubleValue`; no ABI changes were needed.
Static paired IDA/source review and whitespace validation only; no tests or
builds were run.
