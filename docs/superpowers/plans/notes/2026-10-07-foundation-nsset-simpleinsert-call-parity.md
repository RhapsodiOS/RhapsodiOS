# `NSSimpleSetInsert` call ABI and mutable-array insertion (2026-10-07)

The source definition in `NSSimpleHashing.m` takes five arguments:
table pointer, value pointer, hash, context, and `replaceValue`. The local
declaration in `NSSet.m` previously omitted the final `BOOL`, and its callers
passed only four arguments.

IDA confirms the set callers pass a zero replacement flag: i386
`-[NSConcreteSet initWithObjects:count:]` at `0x42545464`,
`-[NSConcreteMutableSet addObject:]` at `0x4251ac64`, and
`-[NSConcreteMutableSet addObjectsFromArray:]` at `0x42520618`; the PPC
`addObjectsFromArray:` body at `0x42547c7c` has the same final zero argument.
`NSSet.m` now declares the fifth argument and passes `NO` at each insertion.

The concrete `addObjectsFromArray:` path now hashes each saved array element,
calls `NSSimpleSetInsert` directly, and retains the element only when insertion
succeeds. This matches both targets instead of routing each element through
`addObject:`.

The concrete `initWithObjects:count:` path also inserts directly after
`initWithCapacity:` and retains only newly inserted elements. DR2 i386
`0x42533260` and MOSXS PPC `0x425589d0` confirm this sequence and the final zero
replacement flag. The source previously sent `addObject:` for every element
and skipped the loop if initialization returned nil; it now follows the
target's direct insertion loop.

Static source/IDA signature review and whitespace checks only; no tests or
builds were run.

## `NSConcreteSet -anyObject` nil-table guard (2026-10-07)

DR2 i386 IDA (`0x4255bbbc`) and MOSXS PPC IDA (`0x4256579c`) both return nil
when the backing table is null before querying its bucket count. The source
previously called `NSSimpleSetCount` first. `NSConcreteSet -anyObject` now
checks the table before the count query, preserving the target's empty-table
path. Static paired IDA/source review and whitespace checks only; no tests or
builds were run.

## `NSConcreteSet -containsObject:` direct lookup (2026-10-07)

DR2 i386 IDA (`0x4255bc08`) and MOSXS PPC IDA (`0x42565814`) reject a nil
object or null table, then hash the object and call `NSSimpleSetLookup`
directly. `NSConcreteSet -containsObject:` previously sent `member:` and
compared the result with nil. The source now follows the direct target call
path. Static paired IDA/source review and whitespace checks only; no tests or
builds were run.

## Concrete set `countForObject:` direct lookup (2026-10-07)

The paired `NSConcreteSet -countForObject:` bodies (i386 `0x4255bc78`, PPC
`0x425658bc`) and `NSConcreteMutableSet -countForObject:` bodies (i386
`0x42526fac`, PPC `0x4251d938`) return zero for nil objects and otherwise hash
and look up directly in the backing simple set, returning one on a match.
Both source methods previously dispatched through `containsObject:`. The
concrete implementations now follow the paired lookup path; the abstract
`NSSet` implementation remains unchanged. Static paired IDA/source review and
whitespace checks only; no tests or builds were run.
