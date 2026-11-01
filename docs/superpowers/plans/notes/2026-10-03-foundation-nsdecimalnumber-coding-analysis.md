# Foundation `NSDecimalNumber` coding and equality analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSDecimalNumber.json`,
`src/Kits/Foundation/NSDecimal.h`, and current
`src/Kits/Foundation/NSDecimalNumber.m`.

## IDA behavior

- `classForCoder` at `0x4259b6ec` lazily caches the result of sending `class`
  to the `NSDecimalNumber` class reference. The selector slot is outside the
  loaded image, but it is shared with abstract-method stubs that send `class`
  to `self` before calling `NSRequestConcreteImplementation`. The source
  `[NSDecimalNumber class]` expression matches this behavior.
- `encodeWithCoder:` at `0x4259bfc4` obtains `decimalValue` and encodes the
  `NSDecimal` components in this order: signed exponent as `i`, length as `S`,
  negative and compact flags as separate `C` values, a fixed mantissa count of
  eight as `I`, then eight mantissa words as an `S` array.
- `initWithCoder:` at `0x4259c114` raises `NSInvalidArgumentException` with
  reason `Did you forget to nest alloc and initWithCoder: ?`, then returns nil.
- `replacementObjectForCoder:` at `0x4259c350` returns `self`.
- `description` at `0x4259bf14` forwards to
  `descriptionWithLocale:nil`.
- `isEqual:` at `0x4259c254` returns true for identity, rejects non-`NSNumber`
  objects, then sends an indirect selector to `self` and checks for a zero
  result. The selector slot `0x4260889c` also appears in
  `-[NSNumber isEqualToNumber:]` at `0x4253aca0`, which uses the same zero-is-
  equal check. Both classes implement `compare:` in the target, returning
  `NSComparisonResult`; this resolves the shared selector contextually as
  `compare:` even though its selector pointer is outside the IDA image. The
  source's `[self compare:object] == NSOrderedSame` matches the target shape.

`NSDecimal.h` confirms the encoded fields correspond to the packed exponent,
length, sign, compact flag, and eight-word mantissa layout.

## Implementation status

The six confirmed `NSDecimalNumber` coding/classification methods and
`NSDecimalNumberPlaceholder -initWithCoder:` are implemented in
`NSDecimalNumber.m`. Encoding writes the target's scalar fields and eight-word
mantissa; placeholder decoding reconstructs the packed `NSDecimal` fields
before delegating to `initWithDecimal:`. The equality selector recheck confirms
the existing `compare:` implementation matches the target's zero-result test.
No product code changed during this follow-up. `git diff --check` was run; no
tests or builds were run.