# Foundation `NSDecimalNumber` NSNumber compatibility analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSDecimalNumber.json`, and current
`src/Kits/Foundation/NSDecimalNumber.m` / `NSValue.m`.

## Source gaps

The ABI records 13 `NSNumberCompatibility` class methods on `NSDecimalNumber`
(`numberWithBool:` through `numberWithUnsignedLongLong:`) and 13 matching
`NSNumberCompatibility` initializers on `NSDecimalNumberPlaceholder`. Neither
category currently appears in source. `NSDecimalNumber.m` implements the
placeholder's decimal, mantissa, and string initializers; `NSValue.m`'s
`NSPlaceholderNumber` implementations are owned by a different class and do
not provide these selectors to the decimal-number placeholder.

## Factory behavior

Each class factory allocates through `+[NSDecimalNumber allocWithZone:]`,
sends the matching `NSNumber -initWith…:` selector to the result, then
autoreleases the initializer result. This is the same pattern for the bool,
signed and unsigned integer, float, and double factories. The allocation
method itself returns `_NSDecimalNumberPlaceholderWithZone(zone)`.

Thus the factory call path depends on the placeholder compatibility category;
implementing only the class factories would leave their initializer sends
unhandled. These wrappers also preserve the target's use of the shared cached
placeholder returned for the requested zone.

## Placeholder initializer behavior

- `initWithBool:`, `initWithChar:`, `initWithShort:`, `initWithInt:`,
  `initWithLong:`, and `initWithLongLong:` convert to signed 64-bit input and
  call `initWithMantissa:exponent:isNegative:` with exponent zero.
- `initWithUnsignedChar:`, `initWithUnsignedShort:`, `initWithUnsignedInt:`,
  `initWithUnsignedLong:`, and `initWithUnsignedLongLong:` convert to unsigned
  64-bit input and call the same mantissa initializer with exponent zero and
  negative false.
- `initWithFloat:` forwards to `initWithDouble:`.
- `initWithDouble:` creates an `NSNumber` with `numberWithDouble:`, asks it for
  `decimalValue`, then initializes the decimal-number placeholder with that
  decimal.

`initWithLongLong:` tests the sign and negates a negative input as a 64-bit
two's-complement operation before passing its magnitude as the unsigned
mantissa. The instruction sequence (`neg` low word, `adc` high word, `neg`
high word) preserves the `0x8000000000000000` magnitude for `LLONG_MIN`.
Source should compute that magnitude in unsigned arithmetic to avoid signed
overflow while matching the reference result.

The `initWithDouble:` path depends on `NSNumber -decimalValue`, which is
already implemented in `NSDecimalNumber.m` as a string conversion followed by
`NSScanner -scanDecimal:`; the IDA body at `0x4259ed38` has the same flow.
The fallback obtains `NSDecimalNumber +notANumber` and returns its decimal
value. Therefore the double initializer can reuse the existing `NSNumber`
conversion path rather than introduce another binary-to-decimal algorithm.

The factory methods span `0x4259837c` through `0x42598728`; the placeholder
initializer methods span `0x4259c8c4` through `0x4259cb44`. This is analysis
only. No source code, tests, or builds were changed or run.

## NSNumber compatibility implementation status (2026-10-03)

Implemented the 13 `NSDecimalNumber(NSNumberCompatibility)` factories and 13
`NSDecimalNumberPlaceholder(NSNumberCompatibility)` scalar initializers from the
confirmed IDA call paths. Signed 64-bit initialization computes the magnitude
in unsigned arithmetic, preserving the `LLONG_MIN` case; floating-point
initialization reuses `NSNumber -decimalValue` as the reference does.

Added `NSString(NSDecimalExtension) -decimalValue` and moved the existing
`NSNumber -decimalValue` implementation under its ABI owner,
`NSNumber(NSDecimalNumberExtensions)`. Declared the NSString category method in
`NSDecimalNumber.h`. The exact-owner audit for `NSDecimalNumber.json` reports
106 expected selectors, 0 missing, and 0 duplicates. `git diff --check` reports
no whitespace errors (Git notes the source file's existing CRLF normalization).
No tests or builds were run.
