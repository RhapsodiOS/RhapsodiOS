# Foundation `NSScanner` flags and skip-set parity (2026-10-07)

The shared `NSScanner.json` ABI manifest records `NSConcreteScanner.flags` at
offset 20 as a 32-bit bitfield containing `caseSensitive:1` followed by 31
reserved bits. The source had modeled it as an `unsigned char` and manually
used bit 0. IDA confirms the architecture-specific representation: i386 reads
and writes bit 0 of the byte, while PPC reads and writes the high bit of the
32-bit word. `NSScanner.m` now declares the manifest bitfield directly and
accesses its `caseSensitive` member, allowing each target compiler's bitfield
layout to match the reference while keeping the field size and offset.

IDA also confirms that `setCharactersToBeSkipped:` autoreleases the old set
before asking the scanner for its zone and copying the new set. The source
previously fetched the zone first; the call order now matches both targets.

Addresses: i386 `setCaseSensitive:` `0x425500e8`, `caseSensitive`
`0x42541ac4`, and `setCharactersToBeSkipped:` `0x4254852c`; PPC
`setCaseSensitive:` `0x425a1be0`, `caseSensitive` `0x4255aa40`, and
`setCharactersToBeSkipped:` `0x4255b7e4`. No ABI manifest changes were needed.
Static source/decompilation comparison only; no tests or builds were run.
