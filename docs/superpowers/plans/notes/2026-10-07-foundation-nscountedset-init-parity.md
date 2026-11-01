# `NSCountedSet -initWithObjects:count:` direct bucket insertion (2026-10-07)

DR2 i386 IDA at `0x4255c9d0` and MOSXS PPC IDA at `0x42566c5c` both check the
requested count, initialize capacity, then walk the input pointers in order.
Each nonnil object is hashed and passed to `NSSimpleDictionaryIncrementValue`
with the input pointer and null context. The object is retained only when the
helper inserts a new key; duplicate objects increment the existing bucket
count without an extra retain.

`NSSet.m` previously routed each item through `addObject:`. It now follows the
direct helper and retain path in both targets.

`initWithCoder:` follows a related transfer path. DR2 i386 IDA at
`0x4255c874` and MOSXS PPC IDA at `0x42566ad0` decode each object and its
archived multiplicity, consume but ignore the multiplicity, then increment
the dictionary once. The decoded object's ownership transfers into a new
bucket; when the key already exists, the target releases the decoded object.
The source now uses that direct increment/release flow rather than routing
through `addObject:` and releasing every decoded object afterward.

Static paired IDA/source review only; no tests or builds were run.

## Counted-set table access guards (2026-10-07)

Paired i386/PPC IDA bodies for `count` (`0x4255c448`/`0x4256664c`),
`countForObject:` (`0x4255c3f8`/`0x425665dc`), `member:`
(`0x4255cfdc`/`0x4256736c`), `allObjects` (`0x4255c1f4`/`0x425663c4`),
`removeAllObjects` (`0x4255d108`/`0x425675ac`), and `removeObject:`
(`0x4255d12c`/`0x425675e8`) access the backing simple dictionary directly.
The source had additional null-table guards in these paths. The simple
dictionary count, lookup, and reset helpers dereference the table, so the
target methods rely on successful initialization; `NSSet.m` now follows that
assumption and retains only the target's argument checks. Static paired
IDA/source review and whitespace checks only; no tests or builds were run.

## `NSCountedSet -allObjects` captured count (2026-10-07)

Both target bodies (i386 `0x4255c1f4`, PPC `0x425663c4`) snapshot the simple
dictionary count and pass that value to `NSArray -initWithObjects:count:`
after collecting keys in descending bucket order. The source passed its local
occupied-bucket scan count. It now passes the captured dictionary count,
matching the target if stored count and scanned occupancy diverge. Static
paired IDA/source review and whitespace checks only; no tests or builds were
run.

## `NSCountedSet -descriptionWithLocale:` class-name formatting (2026-10-07)

Paired IDA bodies (i386 `0x4255c4cc`, PPC `0x425666f4`) use the formats
`<%s: 0x%x> ()` and `<%s: 0x%x> (` and pass `self->isa->name` directly for
both empty and nonempty sets. The source used `%@` with `NSStringFromClass`,
which could route through class-name conversion and class-object formatting.
`NSSet.m` now passes the raw class name through `%s`, matching both target
paths. Static paired IDA/source review only; no tests or builds were run.

## `NSCountedSet -intersectSet:` initialized-table assumptions (2026-10-07)

Paired IDA bodies (i386 `0x4255cc28`, PPC `0x42566f14`) return immediately
for self-intersection, reset `_table` directly when the other set is nil or
empty, and otherwise query its bucket count without a null-table guard.
`NSSet.m` had two extra `_table` checks in those branches. Removed them so the
method follows the direct simple-dictionary path and successful-initialization
assumption in both targets. Static paired IDA/source review only; no tests or
builds were run.
