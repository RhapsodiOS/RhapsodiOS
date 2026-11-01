# Foundation `NSTimeZone` base-method analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSTimeZone.json`, and current
`NSTimeZone.m`.

## ABI gaps and IDA behavior

The base `NSTimeZone` ABI had eight selectors without an exact-owner source
implementation. IDA confirms:

| Selector | Address | Behavior |
| --- | ---: | --- |
| `classForCoder` | `0x4259f410` | Return the `NSTimeZone` class object. |
| `copyWithZone:` | `0x4259f428` | Read data, then name; allocate the dynamic class in the requested zone and initialize it with both. |
| `encodeWithCoder:` | `0x4259f548` | Encode name, then data, each with Objective-C type `@`. |
| `hash` | `0x4259f5bc` | Return the name's hash. |
| `initWithCoder:` | `0x4259f5ec` | For nonzero class version decode name/data and initialize exactly; for version zero decode a legacy abbreviation, reuse its matching zone when found, or initialize by name. |
| `initWithExactName:data:` | `0x4259f72c` | Raise `NSInvalidArgumentException` with the abstract-initializer message and return nil. |
| `isEqual:` | `0x4259f818` | Accept identity or another `NSTimeZone` instance and delegate to `isEqualToTimeZone:`. |
| `replacementObjectForPortCoder:` | `0x4259f938` | Return self for non-byref coding; otherwise return an `NSDistantObject` proxy for self and the coder's connection. |

The source now implements these selectors under `@implementation NSTimeZone`.

IDA also confirms `-[NSTimeZoneDetailDecoder initWithCoder:]` at
`0x4259fb54` decodes a timezone name, abbreviation, and integer offset; it
uses the named zone's current daylight-saving state when available, then
returns a fixed timezone using the decoded abbreviation and offset.
`-[NSWindowsDefaultTimeZoneDecoder initWithCoder:]` at `0x425a03d0` logs the
legacy-decoder message and returns the retained default timezone. Both
decoder classes are mapped by `NSUnarchiver` class-name substitutions in
`NSArchiver.m`; their implementation now lives in `NSTimeZone.m`.

The focused `NSTimeZone.json` exact-owner audit reports zero missing selectors
and zero duplicates. The Foundation-wide selector inventory reports 313
missing selectors, down from 323 before this slice. Static ABI and whitespace
checks only; tests and builds were not run.
