# `NSScanner` text scanning methods (2026-10-07)

Compared the four text scanning methods in `NSScanner.m` against DR2 i386 and
MOSXS PPC IDA pseudocode:

| Method | i386 | PPC |
| --- | ---: | ---: |
| `scanString:intoString:` | `0x4254d66c` | `0x425a5cd8` |
| `scanCharactersFromSet:intoString:` | `0x4258dd44` | `0x425a52c8` |
| `scanUpToString:intoString:` | `0x42547d94` | `0x425a5e7c` |
| `scanUpToCharactersFromSet:intoString:` | `0x42552804` | `0x4255a89c` |

All four first locate the first character outside `charactersToBeSkipped`,
when a skip set exists. `scanString:intoString:` then performs an anchored
search, adding case-insensitive search when `caseSensitive` is false; success
returns the substring from the post-skip position through the match and moves
the cursor to the match end. The source follows that range and cursor behavior.

`scanCharactersFromSet:intoString:` searches the inverted input set, while
`scanUpToCharactersFromSet:intoString:` searches the supplied set. Both use
the scanner's case option, treat no match as the end of the input, fail when
the consumed range is empty, and otherwise return the consumed substring and
advance to its end. The source follows those branches on both targets.

`scanUpToString:intoString:` searches for the delimiter from the post-skip
position, applies the scanner's case option, and consumes to the input end
when no delimiter is found. It fails when the resulting range is empty. The
source matches these rules, including the empty-delimiter result implied by
the target's zero-length search handling.

No source or ABI change was needed. This is a paired static IDA/source review;
no tests or builds were run.
