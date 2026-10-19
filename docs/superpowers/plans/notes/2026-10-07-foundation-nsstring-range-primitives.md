# `NSString` range search primitives (2026-10-07)

Compared `rangeOfString:options:range:` and
`rangeOfCharacterFromSet:options:range:` in `NSString.m` with both IDA
targets:

| Method | i386 | PPC |
| --- | ---: | ---: |
| `rangeOfString:options:range:` | `0x4250162c` | `0x42548d50` |
| `rangeOfCharacterFromSet:options:range:` | `0x425397f8` | `0x42559868` |

Both targets validate that the requested receiver range ends within the
string. String search returns `{NSNotFound, 0}` for an empty search range, an
empty search string, or a search string longer than the range. The source
matches these checks.

The string search copies the search characters into a 100-unit stack buffer
or a zone allocation for longer searches. It lowercases the search and
receiver characters when case-insensitive search is requested, then compares
the receiver in windows of at most 32 UTF-16 units. Forward, backwards, and
anchored masks determine the first candidate and step direction. The source
uses the same buffer sizes, case conversion, candidate bounds, window refill,
and result range. Heap storage is freed through its owning zone in both
targets and source.

Character-set search returns `{NSNotFound, 0}` for an empty range. Otherwise,
it steps through the requested range in the direction selected by the
backwards mask, limits the scan to one character when anchored, and tests each
unit with `characterIsMember:`. The target does not transform characters for
the case-insensitive mask; the source likewise passes each original unit to
the set.

No source or ABI change was needed. This is a paired static IDA/source review;
no tests or builds were run.
