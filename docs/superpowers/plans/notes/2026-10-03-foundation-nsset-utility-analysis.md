# Foundation `NSSet` utility selector analysis

Reference: project Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSSet.json`, and current Foundation
sources.

## Confirmed NSSet gaps

The NSSet ABI lists three instance selectors that have no source definition
under the `NSSet` class: `makeObjectsPerform:`,
`makeObjectsPerform:withObject:`, and `members:notFoundMarker:`. The first two
are directly present in the reference binary as thin aliases:

- `-[NSSet makeObjectsPerform:]` at `0x42561054` sends
  `makeObjectsPerformSelector:` with its selector argument.
- `-[NSSet makeObjectsPerform:withObject:]` at `0x42561078` sends
  `makeObjectsPerformSelector:withObject:` with its selector and object
  arguments.

`-[NSSet members:notFoundMarker:]` at `0x425611a0` gets the argument array's
count, returns `[NSArray array]` when the count is zero, then visits its
elements in order. For each element it calls the receiver's `member:` and
stores the returned member, or the supplied not-found marker when `member:`
returns nil. It constructs and autoreleases an NSArray from that result buffer.
The target uses 128 pointer slots on the stack and allocates `count * 4` bytes
from the default zone for larger arrays, freeing that buffer after array
initialization.

The ABI signatures are:

- `makeObjectsPerform:`: `v12@8:12:16`
- `makeObjectsPerform:withObject:`: `v16@8:12:16@20`
- `members:notFoundMarker:`: `@16@8:12@16@20`

The source already implements the two `makeObjectsPerformSelector:` forms and
`member:`. A small source addition can therefore express all three confirmed
behaviors without new helpers. The ABI also contains methods owned by
`NSConcreteSet` and `NSConcreteMutableSet` that are not defined with those
concrete owners in source; this note does not treat those as missing base
class behavior or propose duplicating inherited implementations.

No source code, tests, or builds were added or run for this analysis.

## Implementation status (2026-10-03)

The three base-class utility methods are now present in `NSSet.m`. The two
`makeObjectsPerform:` forms forward to the corresponding selector-based
methods. `members:notFoundMarker:` uses the IDA-confirmed empty-array fast
path, preserves input order, substitutes the marker for missing members, and
uses 128 stack slots with a default-zone allocation for larger inputs. Static
selector ownership and ABI checks pass, and `git diff --check` is clean. Tests
and builds were not run.

Corrected `NSSet -makeObjectsPerformSelector:` to send the selector with no
arguments, matching IDA at `0x425610a0`; the previous source incorrectly
forwarded a nil object argument. Added ABI-owned `NSCountedSet` overrides for
both selector forms from IDA at `0x4255cf20` and `0x4255cf7c`, forwarding to
the base enumerator implementations. Static selector ownership and ABI checks
pass; tests and builds were not run.

Implemented `NSCountedSet`'s `retain`, `release`, and `retainCount` from IDA at
`0x4255d1bc`, `0x4255d0c8`, and `0x4255d1a4`, using the `_reserved` storage
slot and Foundation's internal refcount helpers with the global retain lock.


## Nil-argument exception fidelity correction (2026-10-03)

IDA at 0x4251ac64 and 0x42541ad4 confirms NSConcreteMutableSet addObject: and removeObject: route nil arguments through the shared set exception helpers. NSCountedSet addObject: and removeObject: do the same at 0x4255c188 and 0x4255d12c. The source now uses method-proem errors with the target formats "%@: attempt to insert nil" and "%@: attempt to remove nil" instead of fixed class-specific text or silently ignoring nil on removal. Static selector ownership and whitespace checks pass; tests and builds were not run.

## Current NSSet-family ABI audit (2026-10-04)

Reparsed the current `NSSet.json` ABI against `source_methods` from all
Foundation `.m` files. The audit finds 133 expected methods and 133 matching
source definitions across the ABI's set classes and categories, with no missing
or extra owners. This confirms the previously approved NSSet utility slice is
integrated in the current source inventory; it is a static owner audit only,
not a compile or runtime check.
