# Foundation `NSValue` base-method reconstruction

Reference: DR2 i386 Foundation IDA database `d12fe2f23883` and the current
Foundation ABI selector audit.

Implemented the remaining base and helper methods confirmed by IDA:

- `classForCoder` returns `NSValue` (`0x4259fc70`); `init` rejects direct
  initialization of the abstract class and otherwise calls `super`
  (`0x4251cec8`); `replacementObjectForPortCoder:` returns `self`
  (`0x425a0258`).
- `isEqual:` accepts identity, concrete values, and `NSValue` subclasses, then
  delegates to `isEqualToValue:` (`0x4250962c`).
- `hash` returns the first byte of the value representation, or zero for an
  empty representation (`0x4259ff20`).
- `description` obtains the value bytes in an `NSMutableData`, copies that data,
  releases the mutable instance, and returns the copy (`0x4259fd40`). This
  preserves the target's observed returned object and ownership sequence.
- `encodeWithCoder:` encodes the type string with `*`, then the bytes using the
  value's type encoding. It raises `NSInvalidArgumentException` with
  `cannot encode (void *) value: %@` for `^v` values (`0x4259fdf4`).
- `initWithCoder:` saves the receiver's zone, deallocates the placeholder, and
  returns a newly decoded `NSConcreteValue` (`0x4259ffd4`). The helper uses a
  1024-byte stack buffer and frees larger buffers and the decoded type string
  as shown by `_NSNewDecodedValue` at `0x425a3dd0`.
- `NSValueDecoder initWithCoder:` decodes type and bytes, specializes the
  one-character numeric encodings through the zone's number placeholder, falls
  back to `_NSNewValue`, deallocates itself, and frees temporary storage
  (`0x425a0294`; numeric dispatch helper `0x42554518`).
- `NSConcreteValue isEqualToValue:` compares encodings, uses the concrete
  payload fast path when possible, and otherwise obtains the other value's
  bytes before comparing (`0x42508ff4`).

The selector audit now reports 419 missing methods and 121 extras, down from
429 and 121 for the prior source state. It reports zero renames and
duplicates; no `NSValue` or `NSValueDecoder` selector remains in its missing
or extra lists. `git diff --check` passed. Tests and builds were not run.

## NSNumber base identity and description selectors (2026-10-03)

IDA confirms `-[NSNumber classForCoder]` returns the NSNumber class object
(`0x4259d398`), `-description` forwards to
`descriptionWithLocale:nil` (`0x4259d49c`), and `-isEqual:` accepts identity or
an NSNumber instance whose value compares equal (`0x4253a8fc`). The source now
implements these under `@implementation NSNumber`. The focused ABI audit reports
seven NSValue-manifest selectors still missing, with no duplicate owners;
`git diff --check` is clean. Tests and builds were not run.

## Value and number placeholder decoder paths (2026-10-03)

IDA confirms `NSPlaceholderValue getValue:` and `objCType` log `Did you forget
to nest alloc and init?` before requesting a concrete implementation, selecting
`NSNumber` as the abstract owner for number placeholders and `NSValue` otherwise.
`NSPlaceholderValue initWithCoder:` decodes through the saved placeholder zone.
`NSPlaceholderNumber initWithCoder:` calls `_newDecodedNumber` (`0x425546d4`),
which accepts one-character numeric encodings, decodes through a 1024-byte stack
buffer or a default-zone allocation, creates the typed number in the placeholder
zone, frees temporary storage, and raises
`NSInternalInconsistencyException` with the target bad-objCType message on
unsupported encodings. The source now implements these four owner methods and
the corresponding decoder helper.

The focused `NSValue.json` exact-owner audit now reports three missing selectors
and zero duplicates; `git diff --check` is clean. Tests and builds were not run.

## NSNumber copy and coder methods (2026-10-03)

IDA confirms `copyWithZone:` (`0x4259d3b0`) copies the typed value through a
1024-byte stack buffer or default-zone allocation, creates the number in the
requested zone, and raises `NSInternalInconsistencyException` with the method
proem and bad-objCType text when the encoding is unsupported. `initWithCoder:`
(`0x4259ddc0`) saves the placeholder zone, deallocates the placeholder, and
uses `_newDecodedNumber`. Both methods now use the existing source-side typed
number dispatch and decoder path. The exact-owner audit reports one missing
NSValue-manifest selector (`-[NSNumber hash]`) and zero duplicates;
`git diff --check` is clean. Tests and builds were not run.

## NSNumber hash range and conversion behavior (2026-10-03)

IDA at `0x4259db50` confirms the eight byte/short/int/long encodings hash via
`unsignedIntValue`. `Q` returns its low word only when the high word is zero;
`q` returns its low word only within `INT32_MIN...INT32_MAX`; both otherwise
return 17. Floating encodings use `doubleValue`, accept negative values down to
`-2147483648` and nonnegative values through `4294967295`, floor before
conversion, and return 17 outside those bounds. An unordered x87 comparison
falls through to the invalid `fistp` result `0x80000000`; the source handles
NaN explicitly with that result. The method is now implemented with those
branches. Exact-owner audits report no missing or duplicate selectors in
`NSValue.json` or `NSSet.json`, and `git diff --check` is clean. Tests and builds
were not run.
