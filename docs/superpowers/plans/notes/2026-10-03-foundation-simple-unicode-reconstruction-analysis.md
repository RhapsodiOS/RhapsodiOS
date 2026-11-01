# Foundation simple Unicode string reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSSimpleString.json`.

## Reconstructed selectors

`NSSimpleString.m` now implements all eight selectors that were missing for
`NSSimpleString`:

| Selector | IDA address |
| --- | --- |
| `_newSubstringWithRange:zone:` | `0x42543a1c` |
| `compare:options:range:` | `0x4253d48c` |
| `copyWithZone:` | `0x4251d69c` |
| `hash` | `0x425388e0` |
| `initWithBytes:length:encoding:` | `0x4258ee78` |
| `isEqualToString:` | `0x4251c190` |
| `rangeOfCharacterFromSet:options:range:` | `0x425438d4` |
| `stringByAppendingString:` | `0x4258efb4` |

The simple-class compare and hash methods call the corresponding IDA helper
logic: `NSCompareCharacters` at `0x4250befc` compares UTF-16 code units and
folds ASCII lowercase only when option bit 0 is set; `NSHashCharacters` at
`0x42501d4c` hashes all characters through length 16 and the first and last
eight characters for longer strings. Generic comparison and equality read
the other string in chunks of at most 32 characters.

Substring creation retains the receiver for a full range, returns the empty
singleton for an empty range, creates ordinary strings for ranges of at most
24 characters, and uses `NSUnicodeSubstring` for longer ranges. Character
set search follows the IDA forward/backward and anchored option branches.
Appending uses an owning UTF-16 buffer allocated in the receiver's zone, with
copy and empty-singleton paths when either input is empty.

The byte initializer calls `_NSConvertToASCIIorUnicode2` with its Unicode
forcing flag set, as shown in IDA. It takes ownership of allocated conversion
storage and copies inline conversion storage into the receiver's zone before
initializing the string.

## Verification

The static selector audit moved from 2,965 definitions / 410 missing
selectors to 2,973 definitions / 402 missing selectors. It reports zero
renames and duplicates, with no remaining `NSSimpleString` selector gaps.
Whitespace checks passed. No build or runtime tests were run.
