# `NSHashTable` reset payload preservation (2026-10-07)

Paired IDA decompilation shows `_NSResetHashTable` delegates to
`NSResetSimpleSet` on i386 (`0x42563274` → `0x42517fe0`) and PPC
(`0x4256d760` → `0x4253c158`). The shared helper invokes the release callback
for each live bucket, then clears only the bucket's hash/state word before
resetting the table count and preserving its capacity level. It leaves the
payload word untouched.

`NSResetHashTable` in `NSHashTable.m` previously zeroed both words after the
callback. It now clears only `bucket[0]`, matching both targets' post-reset
bucket state and callback order. No ABI metadata changed. Static paired
IDA/source review only; no tests or builds were run.

## `NSCompareHashTables` bucket order

The comparison entry points also match on identity and count checks but walk
the first table's buckets from high to low: i386 `0x42562e24` and PPC
`0x4256d198` both decrement from `NSSimpleSetNumBuckets` before each lookup.
`NSCompareHashTables` previously walked low to high, changing the order of
custom hash/equality callback dispatch. Its source loop now descends through
the bucket array as the targets do. Static paired IDA/source review only; no
tests or builds were run.

## `NSHashRemove` low-capacity tombstone state

Both `NSHashRemove` wrappers (i386 `0x4251a118`, PPC `0x4252a2cc`) delegate
to `NSSimpleSetDelete` (i386 `0x4251a4a8`, PPC `0x4252a3b8`). The helper
compacts the final bucket when the table is at level 0 or 1, then marks the
vacated final bucket with `0x40000000` and clears its payload. The source used
zero for that state word in the compacting branch; `NSHashTable.m` now writes
the tombstone value on both branches. Static paired IDA/source review only;
no tests or builds were run.


## Hash-table insertion/removal exception fidelity

Paired i386/PPC wrappers use identical exception text for null values:
`NSHashInsert`, `NSHashInsertKnownAbsent`, `NSHashInsertIfAbsent`, and
`NSHashRemove` report the operation-specific `attempt to insert/remove NULL
pointer` message. A duplicate `NSHashInsertKnownAbsent` reports
`*** NSHashInsertKnownAbsent(): item already in table: %@`, formatting the
value through the table's `describe` callback or as `0x%x` when no callback is
installed. `NSHashTable.m` now matches these strings and the duplicate-value
description path. The evidence is from i386 wrappers at `0x42518658`,
`0x42512e48`, `0x4253ad18`, `0x4251a118` and PPC wrappers at `0x42528544`,
`0x4250df88`, `0x4252d004`, `0x4252a2cc`; the constant strings match across
both images. Static source/IDA review only; no tests or builds were run.

## `NSStringFromHashTable` output and callback insertion

Paired IDA decompilation confirms i386 `0x425635bc` and PPC `0x4256dc88`
render an empty table as `<NSHashTable: 0x%x> ()`, then render nonempty tables
inside parentheses with `, ` separators in descending bucket order. Without a
describe callback, each stored pointer is formatted as `0x%x`. With a callback,
the returned string is inserted directly at the current end of the mutable
string. Both targets allocate the mutable string with capacity `count << 6`;
the i386 disassembly confirms the capacity argument obscured by pseudocode.
`NSStringFromHashTable` now matches these paths, replacing the former brace,
newline, and `%p` formatting and nil-description fallback. Static IDA/source
review only; no tests or builds were run.

## Hash-table bucket initialization

Both targets' `NSCreateHashTableWithZone` call `NSCreateSimpleSet`. Paired
decompilation of `NSCreateSimpleSet` (i386 `0x4250d3dc`, PPC `0x4251d6dc`)
shows it initializes the packed count/capacity, zeroes the mutation count,
stores the equality callback, then clears only each bucket's hash/state word.
The local `NSHashTableCreateSet` helper previously `memset` the entire set,
which also cleared payload words. It now follows the target field and bucket
initialization sequence; this helper also creates resized sets. Static paired
IDA/source review only; no tests or builds were run.

## Small-set identity and equality lookup order

`_NSSimpleSetFindBuckets` in i386 (`0x4250bd38`) and PPC
(`0x4250bca0`) first scans all occupied payloads for pointer identity, then
scans from the lowest bucket upward for a matching hash and equality callback.
The pointer-identity scan is ascending on i386 and descending on PPC. The
source previously combined identity and equality checks in one ascending pass,
so an equality callback could run before finding an identical pointer in a later
bucket. `NSHashTableFindBucket` now separates the passes and keeps the target
order for each architecture. Static paired IDA/source review only; no tests or
builds were run.

## Shared simple-set and simple-dictionary identity search

The same small-table search order appears in shared helpers. i386
`_NSSimpleDictionaryFindBuckets` (`0x42503550`) and
`_NSSimpleSetFindBuckets` (`0x4250bd38`) search pointer identity forward; PPC
(`0x42501098`, `0x4250bca0`) search it backward. Both targets then perform
equality-callback searches forward only after the identity pass finds no match.
`NSSimpleHashing.m` previously used a forward identity pass on both targets.
Its dictionary and set helpers now preserve the per-target identity order while
keeping callback order forward. This also serves NSMapTable and NSSet callers.
Static paired IDA/source review only; no tests or builds were run.
