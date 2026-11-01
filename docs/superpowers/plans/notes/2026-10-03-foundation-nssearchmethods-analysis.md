# Foundation `NSString(NSSearchMethods)` analysis

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSNumberFormatter.json`.

## Current source and ABI state

The ABI manifest assigns six missing instance methods to
`NSString(NSSearchMethods)`: `_componentsSeparatedBySet:`, `_containsChar:`,
`_containsCharFromSet:`, `_containsString:`, `_stringWithSeparator:atFrequency:`,
and `_copyToUnicharBuffer:saveLength:`. A source search found no definitions for
these selectors. IDA has named method symbols for all six in the exact
`Foundation-i386` target.

## Decompiled behavior

- `_copyToUnicharBuffer:saveLength:` reads the string length, stores it through
  the length pointer, allocates `(length + 1) * sizeof(unichar)` bytes from the
  default zone for non-empty strings, copies the UTF-16 characters, frees any
  previously supplied buffer through its owning zone, then stores the new
  pointer. The body does not explicitly write a terminating zero.
- `_stringWithSeparator:atFrequency:` returns the empty-string singleton for
  an empty receiver. Otherwise it allocates an output buffer sized
  `length + (length - 1) / frequency`, copies the source characters, then walks
  backward to insert the separator at each frequency boundary. The body has no
  zero-frequency guard.
- `_containsCharFromSet:` creates an `NSScanner` for the receiver, scans up to
  the supplied character set, and returns true when the scanner has not
  reached the end.
- `_componentsSeparatedBySet:` creates a mutable array with capacity 3 and a
  scanner with no skipped characters. It repeatedly scans up to the supplied
  set, adds each scanned component, advances the scan location by exactly one
  code unit when a separator remains, and returns the mutable array.
- `_containsChar:` converts the argument's low byte to an NSString and searches
  the receiver with `rangeOfString:options:range:` over the full receiver
  range. The method returns true exactly when the returned range length is
  non-zero; a zero byte becomes a zero-length search string and returns false.
- `_containsString:` performs that same full-range search for the supplied
  string and returns true exactly when the returned range length is non-zero.

## Caller evidence and open points

There are no direct call xrefs to these method bodies; their selectors occur
in Objective-C method metadata. This does not rule out dynamic dispatch. The
instructions show both containment methods testing the returned `NSRange`'s
length word (`EDX`) and returning whether it is non-zero. They also confirm
that `_stringWithSeparator:atFrequency:` divides by the frequency for every
non-empty receiver, with no zero-frequency guard, and that
`_copyToUnicharBuffer:saveLength:` frees a prior pointer through
`NSZoneFromPointer` before replacing it. Empty-component behavior still
depends on `NSScanner`'s output-pointer contract. IDA's
`-[NSScanner scanUpToCharactersFromSet:intoString:]` at `0x42552804` confirms
that it returns false without writing through the output pointer when the next
character is already in the separator set. `_componentsSeparatedBySet:` does
not check that return value before adding its local component, then advances by
one code unit. Leading or repeated separators therefore reach the array-add
call with an uninitialized or stale component pointer in the target. This is a
target bug; reproduction should be an explicit fidelity decision rather than
assuming empty components are handled cleanly.

No source code, tests, or builds were added or run for this analysis.

## Implementation status (2026-10-03)

Implemented the six IDA-confirmed selectors in `NSString(NSSearchMethods)` in
`NSString.m`. The buffer copier preserves the target's `(length + 1)` allocation,
copy, old-buffer zone free, and lack of an explicit terminator. Separator insertion
runs backward with the target's `length + (length - 1) / frequency` sizing and
retains its zero-frequency divide behavior. The set scanner methods preserve the
reference scanner configuration and separator stepping; containment methods
use the same whole-string range searches.

Ruling: on an immediate separator, `_componentsSeparatedBySet:` adds `@""`
instead of passing the target's uninitialized/stale local pointer — the binary
has no defined object value for this case, so the implementation returns the
logical empty component without reproducing undefined memory use.

The exact-owner audit reports 6 expected selectors, 0 missing, and 0 duplicate
owners. `git diff --check` is clean. No tests or builds were run.
