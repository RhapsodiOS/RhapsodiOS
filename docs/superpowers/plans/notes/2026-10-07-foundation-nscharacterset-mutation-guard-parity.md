# NSConcreteMutableCharacterSet mutation guard parity (2026-10-07)

Paired IDA review shows the concrete-set mutability byte is at offset 16.
`init` leaves it zero, `isMutable` returns it directly, and `makeImmutable`
also writes zero. The seven mutators (`addCharactersInRange:`,
`removeCharactersInRange:`, `addCharactersInString:`,
`removeCharactersInString:`, `formUnionWithCharacterSet:`,
`formIntersectionWithCharacterSet:`, and `invert`) raise only when that byte is
nonzero. Thus newly allocated target instances report false from `isMutable`
while their mutators proceed. The source now matches this observed state and
guard behavior, including the target's logged diagnostic and
`NSInvalidArgumentException` format.

Representative addresses:

- i386 `Foundation-i386`: `init` `0x42589348`, `isMutable` `0x425895d0`,
  `makeImmutable` `0x4258964c`, `addCharactersInRange:` `0x42588884`, and
  `addCharactersInString:` `0x42588954`.
- PPC `Foundation`: `init` `0x4255ea40`, `isMutable` `0x425a144c`,
  `makeImmutable` `0x4254ac30`, `addCharactersInRange:` `0x425a0c5c`, and
  `addCharactersInString:` `0x4255d424`.

Both targets also send `characterAtIndex:` twice per element in the string
mutators (i386 add/remove `0x42588954` / `0x425897e0`; PPC add/remove
`0x4255d424` / `0x4255f0e4`). The source now preserves both calls and their
order. No ABI fields or selectors changed. Static diff and whitespace checks
only; no tests or build were run.
