# Foundation `NSCharacterSet` immutable mutable-copy parity

Paired IDA references:

- i386 `-[NSImmutableRangeCharacterSet mutableCopyWithZone:]` at
  `0x4258a608` and `-[NSImmutableStringCharacterSet mutableCopyWithZone:]`
  at `0x4258a894`.
- PPC `-[NSImmutableRangeCharacterSet mutableCopyWithZone:]` at
  `0x425a26f0` and `-[NSImmutableStringCharacterSet mutableCopyWithZone:]`
  at `0x425a29f0`.

Both range-copy bodies call
`+[NSConcreteMutableCharacterSet characterSetWithRange:]` using the stored
low bound and `high - low`, then retain the factory result. Both string-copy
bodies create an `NSString` from the inline buffer and character count, call
`+[NSConcreteMutableCharacterSet characterSetWithCharactersInString:]`, then
retain the factory result. The `zone` argument is unused on both targets.

`NSCharacterSet.m` now follows those factory, conversion, and ownership paths
instead of allocating directly in the requested zone and populating the
mutable set with per-character range calls. No tests or builds were run.
