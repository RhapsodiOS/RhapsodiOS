# `NSSet -descriptionWithLocale:` target-specific append flow (2026-10-07)

DR2 i386 IDA at `0x4256074c` and MOSXS PPC IDA at `0x4256a8d4` both obtain
the set count before constructing the result. The empty case returns the
formatted `"<%@: 0x%x> ()"` string. For a nonempty set, both allocate a
`NSMutableString` with `allocWithZone:NULL`, initialize capacity to
`count << 6`, autorelease it, and append the formatted `"<%@: 0x%x> ("`
prefix.

The target append mechanisms differ. i386 sends string appends for the comma,
each object's locale-aware (or ordinary) description, and the final `")"`.
PPC inserts the same pieces by replacing a zero-length range at the current
string length. `NSSet.m` now uses the matching mechanism under the existing
architecture guards and follows the shared capacity/prefix setup. The empty
path and element-description selection remain unchanged.

Static paired IDA/source review and whitespace checks only; no tests or builds
were run.

## `NSCountedSet` description path

DR2 i386 IDA at `0x4255c4cc` and MOSXS PPC IDA at `0x425666f4` use the same
empty result and `count << 6` mutable-string capacity. Both walk the counted
dictionary's buckets in descending index order, append each bucket key's
locale-aware (or ordinary) description, then format the count stored in that
bucket. The source previously used `objectEnumerator` and sent
`countForObject:` for each key. It now reads the backing buckets and stored
counts directly, with the same i386/PPC append difference as `NSSet`.

Static paired IDA/source review only; no tests or builds were run.
