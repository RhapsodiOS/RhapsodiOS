# Foundation `NSTimeZone(NSBackwardsCompatibility)` analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSTimeZone.json`, and current
`NSTimeZone.m`.

## ABI owner gap

The ABI assigns eight selectors to
`NSTimeZone(NSBackwardsCompatibility)`:

| Kind | Selector | Encoding | IDA address |
| --- | --- | --- | ---: |
| class | `timeZoneArray` | `@8@8:12` | `0x42598f84` |
| instance | `timeZoneAbbreviation` | `@8@8:12` | `0x4259fa1c` |
| instance | `timeZoneDetailArray` | `@8@8:12` | `0x4259fa3c` |
| instance | `timeZoneDetailForDate:` | `@12@8:12@16` | `0x4259fa60` |
| instance | `timeZoneForDate:` | `@12@8:12@16` | `0x4259fa84` |
| instance | `timeZoneName` | `@8@8:12` | `0x4259fb14` |
| instance | `timeZoneSecondsFromGMT` | `i8@8:12` | `0x4259fb34` |
| instance | `isDaylightSavingTimeZone` | `c8@8:12` | `0x4259f9fc` |

No implementation of this named category is present in current source. The
same selector `timeZoneForDate:` already has an implementation in the main
`NSTimeZone` class body; the ABI assigns that method to the compatibility
category. That body matches IDA and can move without behavioral change.

## Confirmed behavior

- `timeZoneAbbreviation` forwards to `abbreviation`.
- `+timeZoneArray` sends `propertyList` to the static object at
  `off_426086FC` and returns that result.
- `timeZoneDetailArray` returns `[NSArray array]`.
- `timeZoneDetailForDate:` forwards to `timeZoneForDate:`.
- `timeZoneForDate:` obtains `secondsFromGMTForDate:`,
  `abbreviationForDate:`, and `isDaylightSavingTimeForDate:` from the receiver,
  passes the offset, lossy C-string abbreviation, and daylight flag to
  `_NSConcoctFixedTimeZone`, then autoreleases the result.
- `timeZoneName` forwards to the receiver's `name` selector.
- `timeZoneSecondsFromGMT` forwards to `secondsFromGMT`.
- `isDaylightSavingTimeZone` forwards to `isDaylightSavingTime`.

The base `NSTimeZone` source already implements all forwarded methods used by
these wrappers. The compatibility slice therefore needs a named category and
the seven methods that are absent from source, plus relocating the existing
`timeZoneForDate:` body into that category to match ABI ownership.

## Relationship to local-time-zone gap

`NSLocalTimeZone(NSBackwardsCompatibility)` separately owns a forwarding
`timeZoneForDate:` method in the ABI. It has its own IDA body and is documented
in `2026-10-03-foundation-nslocaltimezone-analysis.md`; it is not part of this
seven-selector `NSTimeZone` category slice.

No source code, tests, or builds were changed or run for this analysis.

## Implementation status (2026-10-03)

Implemented all eight `NSTimeZone(NSBackwardsCompatibility)` selectors in the
named category. `timeZoneForDate:` moved from the main class body with its IDA-
matching body intact. The `+timeZoneArray` receiver is an `NSConstantString`
whose text is the embedded timezone property list at `0x425ffb63`; the source
now sends `propertyList` to the same text. The remaining methods follow their
IDA-confirmed forwarding, empty-array, or fixed-timezone behavior.

The focused `NSTimeZone.json` exact-owner audit reports 10 missing methods,
all outside this compatibility category, and zero duplicates. Static ABI and
whitespace checks only; tests and builds were not run.
