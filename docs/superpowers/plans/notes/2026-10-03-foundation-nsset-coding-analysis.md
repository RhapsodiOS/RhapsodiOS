# Foundation `NSSet` coding and copy selector analysis

Reference: project Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSSet.json`, and current Foundation
sources.

## Confirmed base-class gaps

The ABI contains seven `NSSet` instance methods with no definition owned by
`NSSet`: `classForCoder`, `copyWithZone:`, `encodeWithCoder:`, `hash`,
`initWithCoder:`, `mutableCopyWithZone:`, and
`replacementObjectForPortCoder:`. IDA confirms the following behavior:

- `classForCoder` returns the `__NSSetClass` class object.
- `copyWithZone:` allocates `__NSConcreteSetClass` in the requested zone and
  initializes it with `initWithSet:copyItems:YES`.
- `mutableCopyWithZone:` allocates `__NSConcreteMutableSetClass` in the
  requested zone and initializes it with `initWithSet:copyItems:NO`.
- `hash` returns the receiver's `count`.
- `encodeWithCoder:` encodes the unsigned count with Objective-C type `I`;
  when nonzero, it enumerates the set and encodes each member using
  `encodeBycopyObject:`.
- `initWithCoder:` decodes the count. A zero count initializes with a null
  object buffer and count zero. Otherwise it calls `_NSSetCheckSize`, decodes
  each object using type `@` into a 128-pointer stack buffer or a default-zone
  allocation for larger counts, initializes the set from the buffer, releases
  each decoded object, and frees a heap buffer when used.
- `replacementObjectForPortCoder:` returns `self` unless the coder is byref;
  for byref it obtains the coder's connection and returns an
  `NSDistantObject` proxy for the set and connection.

The functions are at `0x425606a4`, `0x425606bc`, `0x42560998`, `0x42560a30`,
`0x42560a50`, `0x425612d4`, and `0x42561338`, respectively. The body for
`initWithCoder:` calls `_NSSetCheckSize` before allocating its temporary
object buffer.

These seven methods form a separate base-class increment from the three
previously approved utility methods. This analysis does not propose adding
the similarly named `NSConcreteSet` or `NSConcreteMutableSet` overrides; those
remain separate class-owner gaps in the ABI inventory.

No source code, tests, or builds were added or run for this analysis.

## Implementation status (2026-10-03)

The seven base-class methods above are now implemented in `NSSet.m`, including
the shared size guard used by `initWithCoder:`. Static source checks found each
approved selector exactly once under `@implementation NSSet`, and
`git diff --check` is clean. Tests and builds were not run.

## Concrete set owner gaps (2026-10-03)

IDA at database `d12fe2f23883` confirms `-[NSConcreteSet encodeWithCoder:]`
at `0x4255bcf4` writes the count using type `I`, then writes each member with
`encodeBycopyObject:` in descending hash-bucket order. The source now provides
this owner override using the already IDA-checked `NSHashEnumerator` traversal.

The ABI audit then found 16 remaining `NSConcreteMutableSet` selectors. IDA
confirmed their implementation details at `0x42520618` (`addObjectsFromArray:`),
`0x4251a630` (`anyObject`), `0x42526fac` (`countForObject:`), `0x42550194`
(`encodeWithCoder:`), `0x42530c9c` (`init`), `0x4253893c` (`initWithCoder:`),
`0x4255b848` (`intersectSet:`), `0x42541b4c` (`intersectsSet:`), `0x42539250`
(`isEqualToSet:`), `0x4255b94c` (`isSubsetOfSet:`), `0x42534424` and
`0x4255b9e8` (selector forwarding), `0x4252e230` (`mutableCopyWithZone:`), and
`0x4252f8a0`, `0x4252158c`, `0x4255ba48` (retain, release, and retainCount).
The source now owns all these methods. `initWithCoder:` delegates to the
existing mutable-set decoder, which performs the same size check, nil rejection,
and decode-object ownership balancing. `mutableCopyWithZone:` builds a new
mutable table and retains its members; `addObjectsFromArray:` preserves the
target's reverse insertion order and proxy-specific array access.

Static ABI-owner comparison now reports zero missing instance selectors for
`NSConcreteSet`, `NSConcreteMutableSet`, and `NSCountedSet`. No tests or builds
were run.

## Mutable-set intersection traversal correction (2026-10-03)

Rechecking `-[NSConcreteMutableSet intersectSet:]` at IDA address
`0x4255b848` found that it traverses the receiver's buckets from highest index
to lowest and deletes absent members in place. Each membership check sends
`member:` to the other set. The prior source took an `allObjects` snapshot,
then called `containsObject:` and `removeObject:`. The source now uses its
descending `NSHashEnumerator`, calls `member:`, and removes absent entries with
`NSHashRemove`; empty/nil input resets the table directly. The local enumerator
uses the same descending bucket order. `NSHashRemove` performs in-place
deletion and moves the final compact bucket when the table is in its smallest
capacity levels, so the already-visited bucket is not revisited. The local
hash-table representation clears that final slot, while the binary helper
marks it as a tombstone; this representation difference remains owned by the
separate `NSHashTable` implementation. No tests or builds were run.


## NSCountedSet decoder fidelity correction (2026-10-03)

IDA at 0x4255c874 decodes the archive version and rejects versions above 1 using the method proem and format "%@: NSCountedSet cannot decode class version %u". It decodes the entry count, calls the shared set-size guard before capacity initialization, then decodes each object and its archived count. The archived per-object count is consumed but never used: the target calls NSSimpleDictionaryIncrementValue, which increments each decoded member once, and releases the decoded object only when the member already existed. The source now mirrors this with the existing addObject: method and balances the decoder-owned object after insertion. This also avoids the previous behavior of restoring the archived count directly and leaking the decoded ownership. Static source/whitespace checks passed; no tests or builds were run.

## Mutable-set counted intersection correction (2026-10-03)

IDA at `0x4255ffec` shows `-[NSMutableSet intersectSet:]` must account for
`countForObject:` on both sets. For each receiver member, it records
`ownCount - otherCount` copies when the receiver has more occurrences, then
removes those copies after enumeration in reverse buffer order. This inherited
implementation is what lets `NSCountedSet` intersection preserve the
minimum count for each member. The source previously removed an entire member
based on `containsObject:`. It now queues each excess occurrence in a
128-pointer stack buffer, grows into default-zone storage from 512 slots, and
dispatches `removeObject:` after the enumeration completes. Buffer growth
continues as needed to avoid the large-count overflow suggested by the
reference's single resize check. Nil or empty input still removes everything;
self-intersection returns immediately. Selector ownership is unchanged. No
tests or builds were run.

## Mutable-set set-algebra multiplicity correction (2026-10-03)

IDA confirms `-[NSMutableSet minusSet:]` (`0x425601ec`) removes each member
from the receiver once per occurrence in the argument set, and
`-[NSMutableSet unionSet:]` (`0x425260d4`) adds it once per occurrence. Both
obtain the multiplicity through `countForObject:`. `-[NSMutableSet setSet:]`
(`0x42560454`) is a no-op for nil or self; otherwise it clears the receiver
and adds each argument member with its full multiplicity. The source previously
processed each distinct member only once and cleared the receiver for a nil
`setSet:` argument. These methods now follow the IDA count loops, preserving
`NSCountedSet` behavior. No tests or builds were run.

## Counted-set intersection traversal correction (2026-10-03)

IDA at `0x4255cc28` confirms `-[NSCountedSet intersectSet:]` scans dictionary
buckets in descending order, lowers each stored multiplicity to the other
set's count when needed, and deletes/releases entries whose other count is
zero. Nil or empty input resets the dictionary; self-intersection returns.
The source now performs that operation through `NSMapEnumerator` and the
existing `NSMapInsert`, `NSMapRemove`, and `NSResetMapTable` APIs instead of
snapshotting `allObjects`. The map enumerator walks the same descending bucket
order, and `NSMapRemove` uses the same compact-table swap behavior; its local
map representation clears the final slot where the binary marks a tombstone.
No tests or builds were run.

## Counted-set initializer and copy fidelity correction (2026-10-03)

IDA confirms `-[NSCountedSet initWithCapacity:]` (`0x4255c82c`) checks the
capacity before creating its table in the zone containing `self`.
`initWithObjects:count:` (`0x4255c9d0`) checks the count, initializes capacity,
then inserts objects in reverse order and raises nil insertion with that
initializer's selector. `initWithSet:` (`0x4255ca88`) dispatches through
`super`. `copyWithZone:` (`0x4255c3c0`) ignores its zone argument, allocates
from the default zone, and initializes with `copyItems:YES`; `mutableCopyWithZone:`
(`0x4255d02c`) also uses the default zone with `copyItems:NO`. The source now
matches these details. No tests or builds were run.

## Mutable-set bulk operation order correction (2026-10-03)

IDA at `0x4255fd3c` shows `-[NSMutableSet addObjectsFromArray:]` reads a
snapshot through `getObjects:range:` or indexed access for proxy arrays, then
adds elements from last to first. `-[NSMutableSet removeAllObjects]` at
`0x425602bc` first gets `allObjects`, copies it through the same proxy-aware
paths, and removes elements in reverse order. Both use 128 stack slots and
default-zone allocation for larger snapshots. The source now follows those
orders and proxy paths. No tests or builds were run.

## Concrete-set initializer exception fidelity (2026-10-03)

IDA at `0x42545464` confirms `-[NSConcreteSet initWithObjects:count:]`
checks nonzero counts with `_NSSetCheckSize`, creates its table in the zone
containing `self`, and raises the set insertion-nil exception with the
initializer selector before inserting a nil element. The source now applies
the same size guard, zone selection, and method-specific nil exception while
preserving the empty-set singleton path. No tests or builds were run.

IDA at `0x4252375c` and `0x42533260` confirms the corresponding concrete
mutable-set capacity and object-count initializers also guard their sizes and
allocate in the zone containing `self`. The object-count initializer raises
nil insertion with its own selector before forwarding to `addObject:`. The
source now follows those checks; `initWithCapacity:` no longer calls the
superclass initializer, matching the reference body. No tests or builds were
run.

## Concrete-set singleton and copy paths (2026-10-03)

IDA at `0x4255bd9c` shows `-[NSConcreteSet init]` forwards to
`initWithObjects:count:` with a null buffer and zero count, canonicalizing the
empty-set singleton. The source now follows that path. `-[NSConcreteSet
mutableCopyWithZone:]` (`0x4255c0a0`) and
`-[NSConcreteMutableSet mutableCopyWithZone:]` (`0x4252e230`) copy the backing
simple set into the requested zone and retain each member. The source now uses
`NSCopyHashTableWithZone` to create the corresponding copied table directly;
an uninitialized immutable set still returns an empty mutable set from the
default zone, as in the reference. No tests or builds were run.

IDA at `0x4255b774` confirms `-[NSConcreteMutableSet copyWithZone:]` returns
the default-zone empty-set singleton when the set is empty; otherwise it
allocates an immutable concrete set in the requested zone, copies the backing
simple set, and retains its members. The source now uses the matching empty
and copied-table paths. No tests or builds were run.

## Set member identity and counted-set updates (2026-10-03)

IDA confirms `-[NSConcreteSet initWithObjects:count:]` and
`-[NSConcreteMutableSet addObject:]` retain an inserted object only when
`NSSimpleSetInsert` reports a new member (`0x42545464`, `0x425332f0`). Their
source paths now use `NSHashInsertIfAbsent`, which preserves the first stored
object for equal members and retains only a new insertion. `-[NSCountedSet
addObject:]` and `-removeObject:` (`0x4255c188`, `0x4255c228`) already match
the map behavior: `NSMapInsert` changes the value for an equal key while
keeping the original stored key, and `NSMapRemove` releases that stored key
when its count reaches zero. No counted-set source change was needed. Static
source/whitespace checks only; no tests or builds were run.

## Counted-set set-copy ownership correction (2026-10-03)

IDA at `0x4255cac0` shows `-[NSCountedSet initWithSet:copyItems:]` obtains a
retained or copied key, inserts it with `NSSimpleDictionaryInsert`, then sends
another `retain` only when insertion succeeds. The primitive at `0x425032fc`
stores the key without invoking an ownership callback, and the method does not
release its preliminary ownership. Source `NSMapInsert` performs the table's
key retain itself, so the prior `[key release]` canceled the reference-count
increment that the binary leaves in place. That release was removed; on a new
key, the local path now keeps both the preliminary ownership and map-table
ownership, matching the target's two retains. This preserves the target's
extra retain rather than normalizing it. No tests or builds were run.

## Counted-set decoder ownership equivalence (2026-10-03)

IDA at `0x4255c874` increments the table once for each decoded object and
releases the decoded reference only when that object compares equal to an
existing member. The source calls `addObject:` and then releases the decoded
reference unconditionally. These paths are ownership-equivalent with the
current `NSObjectMapKeyCallBacks`: `NSMapInsert` retains a new key into the
table before the source balances the decoder-owned reference, while an equal
key triggers no key retain and the decoded duplicate is released. Both paths
consume but ignore the archived per-member count. No source change is needed.

## Base-set copy initialization buffer fidelity (2026-10-03)

IDA at `0x42560cac` uses 128 pointer slots on the stack for
`-[NSSet initWithSet:copyItems:]`, switches to default-zone storage only above
128 members, and obtains the receiver's zone once when copying items. It
passes the set's reported count to `initWithObjects:count:` and releases the
copied items across that same count. The source previously allocated a heap
buffer for every nonempty set and passed only the number actually returned by
the enumerator. It now matches the target's buffer threshold, zone lookup,
count, cleanup, and free behavior. No tests or builds were run.

## Set-intersection dispatch and traversal fidelity (2026-10-03)

IDA confirms `-[NSSet intersectsSet:]` (`0x42560e28`) guards both set counts
and tests members with `member:`. `-[NSCountedSet intersectsSet:]`
(`0x4255cd34`) scans the counted dictionary's buckets in descending order and
also tests the other set with `member:`. The source previously called
`containsObject:` for the base implementation and `countForObject:` while
walking an object-enumerator snapshot for counted sets. It now uses the exact
`member:` dispatch in both paths; counted-set intersection uses
`NSMapEnumerator`, which follows the same descending bucket order in the local
map implementation. Static whitespace check only; no tests or builds were
run.

## Set-comparison dispatch fidelity (2026-10-03)

IDA's base `NSSet` equality and subset methods (`0x42560ec4`, `0x42560f8c`)
compare `countForObject:` results. The concrete immutable and mutable set
implementations (`0x4255be50`, `0x4255bef8`, `0x42539250`, `0x4255b94c`)
scan their hash buckets and ask the other set for `member:`. Their intersection
methods (`0x4255bdc0`, `0x42541b4c`) use the same direct member lookup. Source
previously routed concrete comparisons through `containsObject:` and used
containment in the base equality/subset methods. These paths now call the same
selectors as the reference. Static whitespace check only; no tests or builds
were run. Concrete mutable-set intersection, equality, and subset now also
read their backing count directly with `NSCountHashTable`, matching the
target's `NSSimpleSetCount` calls instead of adding a virtual `count` dispatch.
The base equality method also has no self-identity shortcut in IDA, so source
now preserves its count and `countForObject:` dispatches when comparing an
instance to itself.

## Set description format fidelity (2026-10-03)

IDA at `0x4256074c` and `0x4255c4cc` uses `"<%s: 0x%x> ()"` for an empty
set and starts nonempty descriptions with `"<%s: 0x%x> ("`; both methods
close the list with `)`. `NSCountedSet` appends each multiplicity as
`" [%d]"` (`0x426054ec`). Source had brace delimiters and rendered counts
as `:count`. `NSSet` and `NSCountedSet` descriptions now follow the observed
parentheses and bracketed-count formats. Their separators, member descriptions,
and closing delimiters use `replaceCharactersInRange:withString:` with a
zero-length range at the current string length. `NSCountedSet` appends its
`" [%d]"` multiplicity with a separate `appendFormat:` call. Static whitespace
check only; no tests or builds were run.

## Counted-set decode multiplicity recheck (2026-10-05)

Re-decompiled `-[NSCountedSet initWithCoder:]` at `0x4255c874` against the
current source. IDA reads each encoded multiplicity as an unsigned integer,
then ignores that value and calls `NSSimpleDictionaryIncrementValue` once for
the decoded object. The source's `(void)decodedCount` followed by one
`addObject:` call per encoded entry preserves this target behavior, despite
the encoder writing the multiplicity. No source change is warranted; no tests
or builds were run.

## Counted-set initializer insertion order (2026-10-05)

Re-decompiled `-[NSMutableSet initWithObjects:count:]` (`0x4255ff70`),
`-[NSCountedSet initWithObjects:count:]` (`0x4255c9d0`), and
`-[NSConcreteMutableSet initWithObjects:count:]` (`0x42533260`). All three
advance the input pointer from the first element to the last after capacity
initialization. `NSCountedSet`'s source initializer had instead consumed the
array backward. Changed it to the target's forward order so hash-table
insertion order and resulting enumeration stay aligned. No tests or builds
were run.

## MOSXS PowerPC cross-architecture recheck (2026-10-05)

The live PPC Foundation database confirms the i386 initializer and counted-set decoder findings. `-[NSCountedSet initWithObjects:count:]` at `0x42566c5c`, `-[NSMutableSet initWithObjects:count:]` at `0x4256a12c`, and `-[NSConcreteMutableSet initWithObjects:count:]` at `0x425589d0` all advance the input object pointer from first to last. This confirms the source's forward traversal on both architectures.

PPC `-[NSCountedSet initWithCoder:]` at `0x42566ad0` decodes the version and entry count, applies the shared size check, initializes capacity, then decodes each object and archived multiplicity. It consumes but does not use the multiplicity; each decoded object increments its set count once. PPC `-[NSCountedSet encodeWithCoder:]` at `0x42566954` writes the set entry count and, for each occupied dictionary bucket in descending index order, writes the object and its stored multiplicity. The current `NSSet.m` preserves these encode/decode contracts. No source or ABI changes were needed.

## Counted-set storage path recheck (2026-10-07)

Paired i386 and PPC IDA bodies confirm `-[NSCountedSet initWithCapacity:]`
stores a direct `NSSimpleDictionary *`, created with `_NSSetAreObjectsEqual`
and the receiver's zone. `addObject:`, `removeObject:`, `countForObject:`, and
`count` call `NSSimpleDictionaryIncrementValue`,
`NSSimpleDictionaryDecrementValue`, `NSSimpleDictionaryLookup`, and
`NSSimpleDictionaryCount` respectively; their IDA addresses are i386
`0x4255c82c`, `0x4255c188`, `0x4255d12c`, `0x4255c3f8`, and `0x4255c448`, and
PPC `0x42566a70`, `0x42566344`, `0x425675e8`, `0x425665dc`, and `0x4256664c`.
The current source stores an `NSMapTable` wrapper around the shared dictionary
and routes these operations through map APIs. This preserves the audited
ownership and results but differs in the private storage path and allocation
shape; exact raw-dictionary reconstruction remains a separate fidelity item.
No code, tests, or builds changed in this recheck.

## Counted-set raw dictionary reconstruction (2026-10-07)

`NSCountedSet` now stores the IDA-confirmed raw `NSSimpleDictionary *` created
with `_NSSetAreObjectsEqual` and the receiver's zone. Count, lookup, insertion,
removal, intersection, reset, and teardown use the corresponding simple
dictionary primitives; retained keys are acquired only for new entries and
released when their final count is removed. `allObjects` and the counted-set
enumerator walk occupied buckets in descending order, and `_NSSetEnumerator`
now declares the four ABI-listed fields at the matching offsets. Its ordinary
`NSSet` path still used the worktree's `NSHashTable` wrapper at this point.
Static source and whitespace checks only; no tests or builds were run.

## Immutable and mutable set raw storage reconstruction (2026-10-07)

Paired IDA bodies for `NSConcreteSet` and `NSConcreteMutableSet` confirm their
`_table` fields also hold raw `NSSimpleSet *` values created with
`_NSSetAreObjectsEqual`. Their insertion and deletion paths call
`NSSimpleSetInsert` and `NSSimpleSetDelete`, retain only new members, and
release members only when deletion succeeds. Count, membership, bucket
enumeration, set algebra, copying, reset, and teardown use the raw simple-set
helpers. The source now follows these calls for both immutable and mutable
sets; `_NSSetEnumerator` directly walks either an `NSSimpleSet` or a counted
set's `NSSimpleDictionary`, and copies retain the copied bucket values. This
removes the `NSHashTable` wrapper representation from the concrete set classes.
The paired initializer/mutator/deallocator bodies were checked at i386
`0x42545464`, `0x4252375c`, `0x4251ac64`, `0x42541ad4`, `0x42558090`, and
`0x42524ad4`, and PPC `0x42565ab0`, `0x42530a00`, `0x425192f8`, `0x42558b94`,
`0x4256596c`, and `0x42532440`. Copy paths were also checked at i386
`0x4255b774`/`0x4252e230` and PPC `0x42565188`/`0x42548340`.
Static IDA/source and whitespace checks only; no tests or builds were run.

## Empty-set singleton initialization correction (2026-10-07)

Paired i386/PPC `+[NSSet set]` bodies (`0x4252cf7c` / `0x42558c20`) lazily
allocate the exported `__NSEmptySet` with `NSAllocateObject` and return it
directly. `-[NSConcreteSet initWithObjects:count:]`
(`0x42545464` / `0x42565ab0`) uses the same allocation when count is zero,
calls `NSDeallocateObject` on the temporary receiver, and returns a retained
singleton. The
source helper previously invoked `init` while lazily constructing the
singleton, which re-entered the empty initializer before storing the pointer.
It now allocates directly into `__NSEmptySet`, and concrete set retain,
release, and retain-count methods no longer special-case the singleton; both
targets use the regular internal retain-count path. Static paired IDA/source
review only; no tests or builds were run.

## Concrete set copy-zone recheck (2026-10-07)

Paired i386/PPC IDA confirms `NSConcreteSet -copyWithZone:` simply retains
the immutable receiver (`0x4255bc58` / `0x42565888`). Its
`mutableCopyWithZone:` copies the raw set into the requested zone and retains
copied members when `_table` is nonnull; the null-table fallback creates an
empty mutable set in the default zone (`0x4255c0a0` / `0x42566004`).
`NSConcreteMutableSet -copyWithZone:` copies nonempty storage and retains its
members in the requested zone, but returns a newly initialized immutable empty
set from the default zone when count is zero (`0x4255b774` / `0x42565188`).
Its `mutableCopyWithZone:` always copies storage and retains copied members in
the requested zone (`0x4252e230` / `0x42548340`). The current `NSSet.m` bodies
match these branches and ownership calls; no source correction was indicated.
Static paired IDA/source review only; no tests or builds were run.
