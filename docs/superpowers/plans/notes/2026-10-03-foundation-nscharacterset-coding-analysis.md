# Foundation `NSCharacterSet` coding and proxy gaps

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSCharacterSet.json`, and current
`src/Kits/Foundation/NSCharacterSet.m`.

The current ABI/source-owner audit reports these gaps:

- `NSCharacterSet`: `encodeWithCoder:`, `initWithCoder:`,
  `replacementObjectForPortCoder:`.
- `NSConcreteMutableCharacterSet`: `dump`,
  `replacementObjectForPortCoder:`.
- `NSImmutableStringCharacterSet`: `encodeWithCoder:`, `initWithCoder:`.
- `NSImmutableRangeCharacterSet`: `encodeWithCoder:`, `initWithCoder:`.

IDA confirms the following method bodies:

## `NSCharacterSet`

`encodeWithCoder:` at `0x425883c8` obtains `bitmapRepresentation` and sends
`encodePropertyList:` with it. `initWithCoder:` at `0x42588430` decodes a
property list, allocates a mutable character set in the default zone, calls
`initWithBitmapRepresentation:`, deallocates the original receiver, and
returns the mutable set. `replacementObjectForPortCoder:` at `0x425885d4`
returns `self`.

## Concrete mutable set

`dump` at `0x42588cfc` checks `bits`: a present bitmap is sent to the class's
`_dumpBitmapRepresentation:` factory; otherwise the set representation is
sent to `_dumpSetRepresentation:`.

`replacementObjectForPortCoder:` at `0x42589924` returns `self` unless the
coder is by-reference and the character set is mutable. In that case it gets
the coder's connection and returns an `NSDistantObject` from
`proxyWithLocal:connection:` for the receiver.

## Immutable representation classes

`NSImmutableStringCharacterSet -encodeWithCoder:` at `0x4258a710` constructs
an NSString from `buffer` and `numChars`, then encodes it as a property list.
Its `initWithCoder:` at `0x4258a75c` decodes the property list, stores its
length narrowed to 16 bits in `numChars`, copies that many characters into the
inline buffer, and returns the receiver.

`NSImmutableRangeCharacterSet -encodeWithCoder:` at `0x4258a4dc` encodes
`low` and `high` separately using type `i`. Its `initWithCoder:` at
`0x4258a528` decodes those two values into the receiver and returns it.

The method addresses and behaviors above are decompiler-confirmed. No source
code, tests, or builds were added or run for this analysis.

## Implementation status (2026-10-03)

Implemented the eight coding and proxy methods above, plus the five supporting
selectors confirmed in IDA: `+[NSCharacterSet allocWithZone:]`, the two dump
format factories, `+[NSConcreteMutableCharacterSet
characterSetWithBitmapRepresentation:]`, and `-[NSConcreteMutableCharacterSet
dump]`. The dump strings retain the target's bitmap bit reversal/complement,
line breaks, and set representation footer. The focused ABI-owner audit reports
zero missing selectors across `NSCharacterSet`, `NSMutableCharacterSet`,
`NSConcreteMutableCharacterSet`, `NSImmutableStringCharacterSet`, and
`NSImmutableRangeCharacterSet`. The framework selector comparison reports
3,049 definitions and 324 missing selectors, with zero renames or duplicates;
`git diff --check` is clean. Tests and builds were not run.

## Named set loader follow-up (2026-10-04)

IDA recheck of `+[NSConcreteMutableCharacterSet
_findDictOrBitmapSetNamed:]` at `0x4258698c` showed that it obtains its root
from `_NSFoundationResourceDirectory` (`0x42542c54`), checks `.dict`,
`.bitmap`, and the system catalog with `_NSFileAccessibleForMode(..., 4)`,
and returns initialized sets without autoreleasing them. If the catalog loads
but has no requested definition, it warns and converts the nil definition to
the target's empty set. An inaccessible or unreadable catalog warns and
returns nil. The warning helper at `0x425943f8` logs
`Unable to load extended character set(s); using builtin.\n` once.

`NSCharacterSet.m` now follows that path, exports
`_NSFoundationResourceDirectory`, and records its Mach-O text symbol in the
source map and ABI manifest. The named loader was compared statically against
IDA; `git diff --check` was clean. No tests or builds were run.

## Built-in character-set expansion ownership recheck (2026-10-07)

Paired IDA bodies show `-[NSBuiltinCharacterSet characterIsMember:]`
(`0x42519e94` i386, `0x42517914` PPC) stores a non-null expanded set directly
in `expandedset`, without retaining it; this includes the `self` result. The
source now matches that assignment. `bitmapRepresentation`
(`0x42587d48` i386, `0x4259ff80` PPC) always asks for expansion and returns the
expanded set's bitmap without caching or retaining that set. If expansion
returns nil or self, it caches self and builds the 0x2000-byte bitmap.
`mutableCopyWithZone:`
(`0x425880b0` i386, `0x425a0210` PPC) always asks for expansion, caches a
non-null non-self result directly and copies it with the requested zone; only
the nil/self case falls back to the bitmap path, allocating the mutable set in
the default zone even when a different zone was supplied. `NSCharacterSet.m`
now matches these branches and ownership effects. Static source and
whitespace checks only; tests and builds were not run.
