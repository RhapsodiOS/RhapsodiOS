# Foundation inline C string analysis

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSSimpleCString.json`.

## Reconstruction status

`NSSimpleCString.m` now implements `NSInlineCString`, `NSCSubstring`, and both
inline factory functions, alongside its existing `NSSimpleCString`,
`NSCString`, and `NSCStringWithGap` classes. The implementation follows the
IDA selectors, allocation sizes, byte-copy paths, reference-string lifetime,
and 24-byte substring threshold recorded below. The ABI manifest and symbol
map list both factory functions.

No build or runtime test was run. The implementation received source and
metadata consistency checks only.

The ABI manifest records `NSInlineCString` as an 8-byte subclass of
`NSString`, with `_flags` at offset 4. Its 16-bit length shares the flags
word; the character bytes start at the runtime class instance size and have
a trailing NUL. The inline factory allocates one extra byte per string. It
uses `NSInlineCString` up to length `0xffff`; longer inputs fall back to
`NSCString`.

## `NSInlineCString` selectors

The ABI contains 24 instance selectors: `hash`, `retain`, `release`,
`copyWithZone:`, `getCharacters:range:`, `isEqual:`, `cString`, `length`,
`isEqualToString:`, `_fastCStringContents`, `cStringLength`,
`compare:options:range:`, `characterAtIndex:`, `substringWithRange:`,
`hasSuffix:`, `getBytes:maxLength:filledLength:encoding:allowLossyConversion:range:remainingRange:`,
`hasPrefix:`, `fastestEncoding`, `_newSubstringWithRange:zone:`,
`lossyCString`, `stringByAppendingString:`, `canBeConvertedToEncoding:`,
`retainCount`, and `smallestEncoding`.

IDA shows that the C-string accessors return the inline byte address and the
length accessors read the packed 16-bit length. Character access maps bytes
above ASCII through `_NSCStringCharToUnichar`. The C encoding byte-copy path
copies at most `maxLength` bytes and reports the unfilled range; other
encodings delegate to `NSString`. Prefix and suffix checks use direct byte
comparison when the argument exposes fast C-string contents, then delegate
to `NSString` otherwise. The comparison fast path calls `NSCompareCString`;
the generic path delegates to `NSString`.

The target’s substring methods return the empty singleton for an empty
range, retain the receiver for a full-range result, and copy ranges of at
most 24 bytes into a new inline string. Longer ranges allocate
`NSCSubstring`, which retains the source C-string storage and points into its
bytes. `NSCSubstring` has four ABI selectors: `retain`, `dealloc`,
`initWithCStringNoCopy:length:`, and
`initWithCStringNoCopy:length:referencedString:`. IDA shows that the
two-argument initializer raises an exception. On first retain, a substring
with a referenced string copies its bytes, releases that string, clears the
reference, and then uses `NSCString` retain behavior.

## Helper evidence

- `__NSNewInlineCString` at `0x42507b00` allocates the inline class, copies
  the requested bytes, appends NUL, and stores the 16-bit length. Its long
  input branch creates an owning `NSCString`.
- `__NSNewInlineCStringFromString` at `0x4254afc0` uses the same inline
  representation through 65,535 characters. Longer strings use a C-string
  buffer and an owning `NSCString`.
- `NSHashCString` at `0x425011f0` hashes all bytes up to length 16; for
  longer strings it hashes the first and last eight bytes. Non-ASCII bytes
  are mapped to Unicode before accumulation. `NSSimpleCString.m` already
  contains this algorithm in its existing hash implementation.
- `NSCompareCString` at `0x42517338` compares the common prefix after mapping
  non-ASCII bytes. Option bit 0 folds ASCII lowercase to uppercase; equal
  prefixes are ordered by length.
- `isEqualCStringToString` at `0x425082f8` first compares lengths, then reads
  the NSString in chunks of at most 32 UTF-16 characters and compares them
  with the mapped C bytes.

The source search originally found no definitions for these factory or
comparison/equality helpers. `NSInlineCString` and `NSCSubstring` have since
been implemented; the comparison and chunked equality helpers now live as
static functions in `NSSimpleCString.m`. `NSInlineUnicodeString` is a separate
class in `NSSimpleString.m`.

## Method addresses

IDA method entry addresses for the 24 `NSInlineCString` selectors:

| Selector | Address |
| --- | --- |
| `hash` | `0x42503720` |
| `retain` | `0x42503878` |
| `release` | `0x42503e9c` |
| `copyWithZone:` | `0x42504974` |
| `getCharacters:range:` | `0x425053e4` |
| `isEqual:` | `0x42507278` |
| `cString` | `0x425073c8` |
| `length` | `0x42507ab0` |
| `isEqualToString:` | `0x4250ba8c` |
| `_fastCStringContents` | `0x42512f70` |
| `cStringLength` | `0x42514474` |
| `compare:options:range:` | `0x4251d034` |
| `characterAtIndex:` | `0x4251da98` |
| `substringWithRange:` | `0x4251f210` |
| `hasSuffix:` | `0x425207cc` |
| `getBytes:maxLength:filledLength:encoding:allowLossyConversion:range:remainingRange:` | `0x425221d8` |
| `hasPrefix:` | `0x42524f28` |
| `fastestEncoding` | `0x425317e8` |
| `_newSubstringWithRange:zone:` | `0x42535e1c` |
| `lossyCString` | `0x42553038` |
| `stringByAppendingString:` | `0x425578b8` |
| `canBeConvertedToEncoding:` | `0x4258a8f4` |
| `retainCount` | `0x4258a944` |
| `smallestEncoding` | `0x4258a974` |

The four `NSCSubstring` methods are `initWithCStringNoCopy:length:referencedString:`
at `0x4252e48c`, `dealloc` at `0x4252e4f8`,
`initWithCStringNoCopy:length:` at `0x42588140`, and `retain` at
`0x42588198`.

