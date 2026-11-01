# Foundation `NSMutableSet` initialization selector analysis

Reference: project Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSSet.json`, and current Foundation
sources.

## Confirmed gaps

The ABI lists three `NSMutableSet` instance methods without source definitions
under that class: `classForCoder`, `initWithCoder:`, and
`initWithObjects:count:`. IDA confirms:

- `classForCoder` returns the `__NSMutableSetClass` class object.
- `initWithObjects:count:` calls `__NSSetCheckSize` with selector context and
  the count, initializes capacity to that count, then inserts each input
  object with `addObject:` and returns the initialized set.
- `initWithCoder:` decodes an unsigned count, calls `__NSSetCheckSize`,
  initializes capacity to the decoded count, then decodes each object as type
  `@`. A nil decoded object calls `__NSSetRaiseInsertNilException`; otherwise
  the object is inserted with `addObject:` and released after insertion.

The methods are at `0x42557408`, `0x4255fe9c`, and `0x4255ff70`. The shared
size helper `__NSSetCheckSize` at `0x4251f3cc` raises when the count exceeds
`0x0fffffff`, before capacity initialization or allocation. The nil-insertion
helper `__NSSetRaiseInsertNilException` is at `0x42563c14`; the coder path
calls it before attempting to add a nil decoded value.

This is a separate mutable-base-class increment from the seven `NSSet`
copy/coding methods documented in
`2026-10-03-foundation-nsset-coding-analysis.md`. No source code, tests, or
builds were added or run for this analysis.

## Implementation status (2026-10-03)

The three base-class methods are implemented in `NSSet.m`. The implementation
uses the shared count guard and matches the IDA nil-insertion exception text.
Static selector and whitespace checks are recorded with this continuation;
tests and builds were not run.
