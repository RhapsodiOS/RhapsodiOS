# Foundation `NSDecimalNumber` scalar conversion analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSDecimalNumber.json`, and current
`src/Kits/Foundation/NSDecimalNumber.m`.

## Confirmed source gaps

The ABI/source-owner audit finds these `NSDecimalNumber` instance selectors
missing from source: `boolValue`, `charValue`, `shortValue`, `intValue`,
`longValue`, `longLongValue`, `unsignedCharValue`, `unsignedShortValue`,
`unsignedIntValue`, `unsignedLongValue`, `unsignedLongLongValue`, and
`floatValue`. The source already implements `doubleValue` at
`NSDecimalNumber.m:390`.

## IDA behavior

Each method calls `doubleValue` and converts its result to the method's return
type. The i386 bodies are:

- `boolValue` (`0x4259b674`) and `charValue` (`0x4259b6b0`): cast to `int`,
  returned as the narrower signed-char ABI type.
- `shortValue` (`0x4259c38c`), `intValue` (`0x4259c218`), and `longValue`
  (`0x4259c300`): cast to `int`.
- `longLongValue` (`0x4259c2bc`): cast to signed 64-bit integer.
- `unsignedCharValue` (`0x4259c3c8`), `unsignedShortValue` (`0x4259c4b0`),
  `unsignedIntValue` (`0x4259c408`), and `unsignedLongValue` (`0x4259c470`):
  cast to signed 64-bit integer before returning through the narrower unsigned
  ABI type.
- `unsignedLongLongValue` (`0x4259c448`): cast through `double` to unsigned
  64-bit integer.
- `floatValue` (`0x4259c0c4`): return the `doubleValue` result through the
  float ABI type.

The instruction trace distinguishes the wide conversions: `longLongValue`
temporarily sets the x87 rounding mode to truncate toward zero and uses
`fistp` to produce a signed 64-bit result, then restores the prior control word.
`unsignedLongLongValue` stores the `doubleValue` result and calls
`__fixunsdfdi` for an unsigned 64-bit conversion. The narrower unsigned getters
use the signed 64-bit `fistp` path before returning through their declared
unsigned widths.

## Implementation status (2026-10-03)

Implemented all twelve scalar conversion getters in `NSDecimalNumber.m`.
Each delegates through `doubleValue`; signed and narrower unsigned conversions
preserve the IDA-confirmed intermediate casts, and `unsignedLongLongValue`
converts through `double`. ABI-owner and whitespace checks pass. Tests and
builds were not run.
