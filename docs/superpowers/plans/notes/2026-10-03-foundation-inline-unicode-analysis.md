# Foundation inline Unicode string analysis

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSSimpleString.json`.

## Source gap at start of this increment

At the start of this increment, `NSSimpleString.m` implemented
`NSSimpleString`, `NSUnicodeString`, and `NSUnicodeStringWithGap`, but not
`NSInlineUnicodeString` or `NSUnicodeSubstring`. `NSString.m` declared and called
`_NSNewInlineUnicodeString` and `_NSNewInlineUnicodeStringFromString`, but
the Foundation source tree has no definitions for those helpers.

The ABI describes `NSInlineUnicodeString` as an 8-byte `NSString` subclass.
Its `_flags` field is at offset 4; the 16-bit character count shares the
flags word. Inline UTF-16 characters begin at the runtime class instance
size. `NSUnicodeSubstring` has a 20-byte instance size and stores its
`_referenceString` at offset 16.

## `NSInlineUnicodeString` selectors

The ABI records 11 selectors: `release`, `retainCount`, `retain`, `hash`,
`isEqualToString:`, `isEqual:`, `copyWithZone:`,
`canBeConvertedToEncoding:`, `length`, `getCharacters:range:`, and
`characterAtIndex:`.

IDA shows that `length` reads the 16-bit character count. Character access
checks the bounds and reads inline UTF-16 storage; ranged access checks the
end offset and copies `2 * range.length` bytes. Both raise `NSRangeException`
on an out-of-bounds range. Equality compares inline strings by length and
memory contents. For a different NSString instance, it checks equal lengths
and retrieves characters in chunks of at most 32 UTF-16 units. `hash` calls
`NSHashCharacters`; `copyWithZone:` retains the receiver when its zone is
compatible and otherwise copies through `_NSNewInlineUnicodeString`.
`canBeConvertedToEncoding:` returns true for encoding 10 and delegates
other encodings to NSString. Retain and release use the same packed local
counter and external extra-count pattern as `NSInlineCString`.

## Helper evidence

- `__NSNewInlineUnicodeString` at `0x42503b7c` allocates an inline object
  with `2 * length` extra bytes and copies UTF-16 characters when length is
  at most `0xffff`. Longer strings use `NSUnicodeString` initialized with
  the characters.
- `__NSNewInlineUnicodeStringFromString` at `0x425475e8` uses the inline
  allocation for lengths through `0xffff`. Longer strings allocate a
  `2 * length` character buffer, fill it with `getCharacters:range:`, and
  transfer it to an owning `NSUnicodeString`.
- `NSHashCharacters` at `0x42501d4c` hashes all characters up to length 16;
  for longer strings it hashes the first and last eight characters. It
  accumulates each 16-bit character and finishes with a length-based shift.

The ABI records five `NSUnicodeSubstring` selectors: `retain`,
`substringWithRange:`, `dealloc`,
`initWithCharactersNoCopy:length:freeWhenDone:`, and
`initWithCharactersNoCopy:length:referencedString:`. The full-repository
source search found no implementation for this class either. This is a
separate source gap from the inline C-string increment.

IDA shows that the free-when-done initializer raises an exception. The
referenced-string initializer calls `NSUnicodeString` with
`freeWhenDone:NO` and stores a copy of the source string in the same zone.
`substringWithRange:` raises `NSRangeException` when the end exceeds the
current length, returns the empty singleton for an empty range, copies the
receiver for a full range, and otherwise creates another referenced
`NSUnicodeSubstring`. `dealloc` releases the referenced string and clears
the character pointer before delegating to `NSUnicodeString`. On retain, a
referenced substring copies its characters and detaches from the source only
when its length is less than 90 percent of the source length; it then
delegates to `NSUnicodeString` retain behavior.

The analysis itself added no tests or builds. The reconstruction that followed
is recorded below.

## Follow-up method details

The remaining selector bodies were checked directly in IDA:

- `-[NSInlineUnicodeString hash]` at `0x425039e0` passes the inline character
  pointer and packed 16-bit length to `NSHashCharacters`. `copyWithZone:` at
  `0x42503f74` uses `NSShouldRetainWithZone`; otherwise it calls
  `_NSNewInlineUnicodeString` with the requested zone.
- `isEqualToString:` at `0x4253d604` accepts any object responding to the
  string length and ranged-character selectors, compares equal lengths, and
  retrieves the other string in chunks of at most 32 UTF-16 units. `isEqual:`
  at `0x4250ccd4` first handles identity and nil, then only uses that path for
  `NSString` instances. When the other object has the same concrete class, it
  compares lengths and the inline character bytes directly.
- `canBeConvertedToEncoding:` at `0x4258a98c` returns true for encoding 10
  and delegates every other value to `NSString`.
- `NSUnicodeSubstring`'s free-when-done initializer at `0x4259085c` always
  raises using the exception-name and format constants at `0x42606a70` and
  `0x42608144`, passing the selector and receiver's description into the
  format call. Its `dealloc` at `0x42547ca0` clears the
  borrowed `characters` pointer before releasing `_referenceString`, then
  delegates to `NSUnicodeString` deallocation. This ordering prevents the
  superclass from freeing storage owned by the referenced string.
- `substringWithRange:` at `0x425908b4` validates the end offset, returns the
  empty singleton for length zero, copies the receiver for a full-range view,
  and otherwise creates an autoreleased referenced substring. On `retain`,
  the detach threshold is exactly `length < sourceLength - sourceLength / 10`;
  the detach allocates and copies the UTF-16 buffer, marks it owned, releases
  the source, clears `_referenceString`, and then delegates to
  `NSUnicodeString` retain.

## Reconstruction status

`NSSimpleString.m` now implements `NSInlineUnicodeString`,
`NSUnicodeSubstring`, `_NSNewInlineUnicodeString`, and
`_NSNewInlineUnicodeStringFromString`. The two factory symbols are recorded in
the `NSSimpleString.m` ABI and symbol maps. A static source-to-ABI selector scan
found all 11 inline-string and all 5 substring selectors exactly once. The
Foundation selector audit against the thin DR2 i386 binary reported no renames
or duplicates; it is broader than this module and still reports other missing
and extra selectors. No build or runtime check was run.
