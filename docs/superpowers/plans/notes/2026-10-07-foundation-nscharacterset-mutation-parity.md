# Foundation `NSCharacterSet` mutation parity

Paired IDA references:

- i386 `-[NSConcreteMutableCharacterSet addCharactersInRange:]` at
  `0x42588884`, `removeCharactersInRange:` at `0x42589710`,
  `formUnionWithCharacterSet:` at `0x42588f4c`, and
  `formIntersectionWithCharacterSet:` at `0x42588d40`.
- PPC `addCharactersInRange:` at `0x425a0c5c`,
  `removeCharactersInRange:` at `0x425a1574`,
  `formUnionWithCharacterSet:` at `0x425604d0`, and
  `formIntersectionWithCharacterSet:` at `0x425a0e80`.

Both targets perform range mutation only when the length is nonzero, compute
the inclusive end as `location + length - 1`, narrow the initial cursor to
16 bits, and narrow it again on each increment. The source had instead
clamped the range to the Unicode BMP boundary and used a nonwrapping cursor.
`NSConcreteMutableCharacterSet` now follows the target arithmetic and cursor
width in both add and remove.

Both union and intersection targets first make the receiver mutable and fast,
then select their optimized same-class, bitmap, or character-membership path.
They do not return early when the argument is the receiver itself. The source
now follows that state transition and operation path, including the
representation change on a self-operation.

The optimized path uses exact class identity, calls `makeCharacterSetFast` on
the matching argument, and reads its bitmap. For other classes, both targets
check for `bitmapRepresentation` and combine the returned bitmap when
available; only objects without that selector use per-character membership.
The source now follows those branches. This preserves overridden bitmap
representations on subclasses rather than reading their concrete-set ivars.

The paired `-[NSConcreteMutableCharacterSet characterIsMember:]` bodies
(i386 `0x42588b00`, PPC `0x4254ada4`) first use the bitmap when present.
Compact-set membership requires type 1 and a matching plane mask, checks the
single-value min/max before searching singletons, and uses binary search for
more than nine singletons or ranges. Smaller arrays use linear search. The
source helper now uses those gates and thresholds.

The paired `bitmapRepresentation` bodies (i386 `0x42588a98`, PPC
`0x425a0d64`) allocate bitmap bytes directly from the compact set when needed
and retain the no-copy `NSData` result without freeing the compact set. The
source now preserves that dual representation instead of routing through
`makeCharacterSetFast`, which frees and clears the compact set.

No tests or builds were run. Static source and whitespace checks are used for
this slice.

## Bitmap dispatch and intersection call parity

The i386 and PPC `formUnionWithCharacterSet:` / `formIntersectionWithCharacterSet:`
bodies select the bitmap path from exact class identity or
`respondsToSelector:@selector(bitmapRepresentation)`. They do not check
whether the returned `bytes` pointer is non-null before entering that path.
The source previously used the pointer as the branch condition, which sent an
object that advertises the selector but returns nil through the membership
fallback. The source now uses the target's selector-path decision. In the
membership intersection path, IDA also short-circuits membership queries for
characters whose receiver bit is clear; the source now makes the same calls.
References: i386 union `0x42588f4c`, intersection `0x42588d40`; PPC union
`0x425604d0`, intersection `0x425a0e80`. Static source and whitespace checks
only; no tests or builds were run.
