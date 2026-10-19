# Foundation `NSPort` coding selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSPort.json`, and current
`src/Kits/Foundation/NSPort.m`.

## Confirmed owner gaps

The ABI lists six `NSPort` instance methods without source definitions under
`NSPort`: `classForCoder`, `copyWithZone:`, `encodeWithCoder:`,
`initWithCoder:`, `replacementObjectForCoder:`, and
`replacementObjectForPortCoder:`. IDA confirms:

- `classForCoder` (`0x425812d8`) returns the `__NSPortClass` class object.
- `copyWithZone:` (`0x425812f0`) returns the receiver retained through
  `NSObject`'s retain implementation; the zone is unused.
- `encodeWithCoder:` (`0x42581338`) sends `encodePortObject:self` to the coder.
- `initWithCoder:` (`0x4258135c`) deallocates the allocated `NSPort`, decodes a
  port object, and returns that decoded object retained.
- `replacementObjectForCoder:` (`0x42581464`) returns nil.
- `replacementObjectForPortCoder:` (`0x42581470`) returns `self`.

At the time of the initial analysis, `NSPort.m` contained no definitions for
these six selectors. No tests or builds were run for that analysis.

## Implementation status (2026-10-03)

All six methods are now implemented in `NSPort.m`. `copyWithZone:` calls
the NSObject retain implementation through `[super retain]`, and
`initWithCoder:` deallocates the uninitialized receiver through
`[super dealloc]` before decoding and retaining the archived port.
`encodeWithCoder:` uses the port-specific coder methods declared by
`NSPortCoder.h`. The `classForCoder` declaration in `NSPort.h` returns
`id`, matching the target's `@` type encoding rather than NSObject's
general `Class` encoding.

The focused ABI owner audit reports 20 expected NSPort selectors, 20 source
definitions, and no missing, extra, or duplicate selectors.
`git diff --check` is clean. No tests or builds were run.
