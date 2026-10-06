# Foundation `NSMapTable` Shared Storage Reconstruction Design

## Goal

Make `NSMapTable.m` use the shared `NSSimpleDictionary` implementation used by
both the MOSXS PPC and DR2 i386 Foundation binaries. Remove the source's private
second hash-table engine while preserving the public map-table ABI, key/value
callback behavior, and target ownership order.

## Evidence

Both reference targets use the same storage boundary:

- PPC `NSCreateMapTableWithZone` at `0x425159b0` and i386 at `0x4251f898`
  allocate a 40-byte `NSMapTable` wrapper and call
  `NSCreateSimpleDictionary(capacity, keyCallBacks.isEqual, zone)`.
- PPC/i386 `NSFreeMapTable` call `NSResetSimpleDictionary` with the
  `releaseKeyValue` callback when count is nonzero and either release callback
  is present, then `NSFreeSimpleDictionary`, then free the wrapper in its
  containing zone.
- Lookup methods call `NSSimpleDictionaryCount` and
  `NSSimpleDictionaryLookup`; mutation methods call
  `NSSimpleDictionaryInsert` or `NSSimpleDictionaryDelete`.
- Enumeration, `NSAllMapTableKeys`, `NSAllMapTableValues`, comparison, copy,
  reset, count, and string formatting use the shared count, bucket, lookup,
  insert, and reset helpers. PPC and i386 `NSNextMapEnumeratorPair` both scan
  through `NSSimpleDictionaryGetBucket`.
- `NSMapTableKeyCallBacks` and `NSMapTableValueCallBacks` remain stored inline
  after the dictionary pointer. The wrapper is 40 bytes: dictionary pointer at
  offset 0, key callbacks at offset 4, and value callbacks at offset 28.
- The current `NSMapTable.m` instead duplicates the simple dictionary's bucket
  layout, capacity selection, probing, resize, deletion, and enumeration.
  `NSSimpleHashing.m` already implements the required helper closure, including
  the same dictionary bucket layout and resize behavior.

The decompilation evidence was collected from PPC IDA instance `e9975db45baf`
and i386 IDA instance `ad50473da958`. Key entries include PPC
`NSMapMember` `0x42503438`, `NSMapInsert` `0x425016f4`, `NSMapRemove`
`0x4250aa94`, `NSNextMapEnumeratorPair` `0x4250d364`, and i386 counterparts
`0x42504eac`, `0x4250489c`, `0x4250dd88`, and `0x425034c0`.

## Design

Keep the public `NSMapTable` callback structs and exported function signatures
unchanged. Keep the wrapper layout as one `NSSimpleDictionary *` followed by
the existing key and value callback records. Replace the local dictionary,
bucket-search, resize, count, and mutation machinery with calls to the
existing shared `NSSimpleHashing` functions. Use narrow private declarations
in `NSMapTable.m` and a local bucket view only where enumeration needs the
target bucket's key and value fields; do not change the shared helper ABI or
add exported helpers.

The wrapper computes hashes through `keyCallBacks.hash` when present and uses
the original key otherwise. It passes the wrapper as the comparison context,
so the dictionary's stored `keysEqual` callback invokes
`keyCallBacks.isEqual(table, storedKey, candidateKey)` exactly as the target
does. The reserved `notAKeyMarker` checks remain in `NSMapInsert`,
`NSMapInsertKnownAbsent`, `NSMapInsertIfAbsent`, and `NSMapRemove`.
`NSMapMember` and `NSMapGet` do not add marker checks.

Preserve target ownership order around helper calls:

- `NSMapInsert` retains the incoming value before insert/replace; on a new
  entry it retains the key after successful insertion; on replacement it
  releases the old value returned through the helper.
- `NSMapInsertKnownAbsent` and `NSMapInsertIfAbsent` use non-replacing insert
  semantics. The former retains key/value after success and raises on an
  existing key; the latter returns the existing key and retains both only on
  success.
- `NSMapRemove` releases the stored key then stored value only after a
  successful dictionary deletion.
- Reset/free use `NSResetSimpleDictionary`'s reverse bucket traversal and
  release callback, then `NSFreeSimpleDictionary`.

Enumeration and collection operations traverse shared buckets from the end,
matching `NSNextMapEnumeratorPair`, `NSAllMapTableKeys`, and
`NSAllMapTableValues`. Preserve the target's 128-pointer stack buffer and
zone-allocated overflow buffer for key/value arrays. Comparison looks each
first-table key up in the second table after applying the second table's hash
callback. Copy builds a new wrapper in the requested zone and copies entries
using non-replacing simple-dictionary insertion followed by key/value retain
callbacks. String formatting continues to use the public callback `describe`
functions and target order/formatting.

Keep the standard callback constants and the C string hash/equality/describe
helpers in `NSMapTable.m`, with their existing exported names and ownership.
No public ABI or source-symbol manifest changes are expected; update stale
reconstruction divergence text that still describes map-table storage as an
unimplemented substitute if that text remains applicable after the change.

## Scope and constraints

- Modify `NSMapTable.m` only, except for a narrowly scoped divergence-record
  correction if the current record still claims a duplicate or missing map
  table implementation.
- Keep shared public headers, callback layouts, symbol names, and ABI manifests
  unchanged.
- Reuse current `NSSimpleHashing.m` helpers; do not move or duplicate their
  algorithms.
- Match PPC and i386 behavior where the two IDA bodies agree; preserve any
  directly confirmed target difference.
- Do not add or run tests or builds. Verify the wrapper and callback order
  against both IDA databases, validate any touched JSON only if metadata must
  change, and run `git diff --check` for the slice.

## Verification focus

- The table and nested dictionary retain the correct allocation zones and
  40-byte wrapper layout.
- Hash and equality callbacks receive the same keys and `NSMapTable *` context
  as the reference.
- Replace, known-absent insert, insert-if-absent, and remove preserve the
  helper-returned original key/value and the target retain/release order.
- Reset and free release entries only when the reference's release-callback
  condition holds, then free both allocations in their respective zones.
- Enumeration, key/value arrays, comparison, copy, and string formatting use
  shared helper counts and buckets in the target iteration order.
- Existing PPC/i386 ABI and symbol records remain unchanged.
