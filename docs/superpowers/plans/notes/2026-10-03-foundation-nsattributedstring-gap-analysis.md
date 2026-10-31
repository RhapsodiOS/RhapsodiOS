# Foundation NSAttributedString selector-gap analysis

Reference: the DR2 i386 Foundation IDA database `d12fe2f23883`.

The current Foundation selector audit reports these eight methods as missing
from `NSAttributedString.m`:

- `attributedStringByWeaklyAddingAttributes:`
- `classForCoder`
- `description`
- `encodeWithCoder:`
- `hash`
- `initWithCoder:`
- `isEqual:`
- `replacementObjectForPortCoder:`

IDA confirms the following behaviors:

- `classForCoder` returns the `NSAttributedString` class object
  (`0x42587854`).
- `replacementObjectForPortCoder:` returns `self` (`0x42587d00`).
- `hash` delegates to the receiver's string (`0x42587b3c`).
- `isEqual:` accepts only `NSAttributedString` instances, then delegates to
  `isEqualToAttributedString:` (`0x42587b6c`).
- `attributedStringByWeaklyAddingAttributes:` mutable-copies the receiver,
  weakly adds the attributes over the full string range, copies the result,
  autoreleases that copy, and releases the mutable copy (`0x42587780`).
- `initWithCoder:` creates a temporary mutable attributed string, decodes into
  it through `_NSReadMutableAttributedStringWithCoder`, initializes `self`
  from it on success, deallocates `self` on failure, and releases the
  temporary object (`0x42550524`).
- `_NSReadMutableAttributedStringWithCoder` (`0x42551c08`) decodes the plain
  string first and inserts it into the temporary mutable attributed string.
  Each subsequent run encodes a dictionary ID and run length as `"iI"`; a
  dictionary object is decoded only the first time its ID occurs. The helper
  caches decoded dictionaries by ID in 20 stack slots, growing the table in
  the default zone as needed, applies dictionaries over successive ranges,
  and frees any heap table before returning success.
- `encodeWithCoder:` encodes the string first, then traverses longest
  effective attribute ranges. It assigns IDs to distinct attribute
  dictionaries, encodes each run's ID and length, and encodes each dictionary
  the first time its ID appears. The ID map begins at capacity 8 with
  non-retained dictionary keys, and IDs start at 1 (`0x425879bc`).
- `description` allocates a string with capacity twice the attributed string
  length, then traverses effective ranges. For each run it appends the run's
  substring followed directly by that run's attributes description, using
  zero-length range insertion at the output string's current length. It
  advances by the effective range length and adds no separators
  (`0x42587878`). The insertion selector sequence matches the one confirmed
  in `NSSet` and `NSConnection` descriptions.

These eight reference bodies are present in IDA but absent from the source
class implementation. All eight function bodies are now outlined from IDA;
the decoder/encoder bodies are the largest implementation work in this slice.
This is a source-to-IDA inventory only; no runtime changes, tests, or builds
were made for NSAttributedString.

## Base behavior and weak-attribute reconstruction (2026-10-03)

IDA reconfirmed the selector bodies at `0x42587854`, `0x42587d00`,
`0x42587b3c`, `0x42587b6c`, `0x42587780`, and `0x42587878`. The source now
implements `classForCoder`, `replacementObjectForPortCoder:`, `hash`, `isEqual:`,
`description`, and `attributedStringByWeaklyAddingAttributes:` under
`NSAttributedString`. The convenience method mutable-copies, applies weak
attributes over the full length, copies, autoreleases the immutable result, and
releases the mutable copy, preserving the observed ownership sequence.

The wrapper depends on `NSMutableAttributedString addAttributesWeakly:range:`
(`0x4258acf8`), now implemented as well. It brackets nonempty ranges with
`beginEditing`/`endEditing`, walks existing effective ranges, starts each merged
dictionary with the incoming attributes, adds the existing attributes so they
win conflicts, applies it with `setAttributes:range:`, and releases the copy.
`description` reserves twice the string length and appends each effective-run
substring followed by that run's attributes description, with no separator.

The focused exact-owner audit reports eight remaining gaps: `NSAttributedString`
`initWithCoder:` and `encodeWithCoder:`, `NSRLEArray description`, and five
`NSConcreteMutableAttributedString` overrides (`initWithCoder:`, `classForCoder`,
`attribute:atIndex:longestEffectiveRange:inRange:`, `addAttribute:value:range:`,
and `replaceCharactersInRange:withAttributedString:`). Across the full Foundation
selector audit, missing definitions decreased from 348 to 341, with zero renames
or duplicates. `git diff --check` is clean. Tests and builds were not run.

## Base attributed-string coding reconstruction (2026-10-03)

IDA at `0x42550524` confirms `-[NSAttributedString initWithCoder:]` creates a
temporary mutable attributed string, fills it through
`_NSReadMutableAttributedStringWithCoder`, initializes the receiver from it on
success, and releases the temporary object. The helper at `0x42551c08` decodes
the string followed by `"iI"` dictionary-ID/run-length records. It caches each
decoded dictionary by ID in 20 stack slots, grows with default-zone allocation
or reallocation, applies each run, and frees heap storage. Its stack-to-heap
growth has no copy of the previous stack entries in the disassembly; source
preserves that behavior. The helper returns success after decoding.

IDA at `0x425879bc` confirms `encodeWithCoder:` writes the string first, then
effective runs as `"iI"` records. An eight-slot map with non-retained object
keys assigns dictionary IDs from 1; each distinct attributes dictionary is
encoded once, on first use. The source now implements both base coder methods
and the exported helper.

The exact-owner audit now reports six remaining entries: `NSRLEArray
description`; five `NSConcreteMutableAttributedString` overrides
(`initWithCoder:`, `classForCoder`,
`attribute:atIndex:longestEffectiveRange:inRange:`, `addAttribute:value:range:`,
and `replaceCharactersInRange:withAttributedString:`). Full Foundation selector
audit reports 339 missing definitions, zero renames, and zero duplicates.
`git diff --check` is clean. Tests and builds were not run.

## NSRLEArray description reconstruction (2026-10-03)

IDA at `0x4258db58` confirms `-[NSRLEArray description]` allocates a mutable
string with capacity 100, appends the storage length/capacity/run count/block
index/block length summary, then appends one line per run with its length,
object address, and object description. The source now owns this selector under
`NSRLEArray` and uses the observed format strings. The exact-owner audit leaves
five `NSConcreteMutableAttributedString` methods: `initWithCoder:`,
`classForCoder`, `attribute:atIndex:longestEffectiveRange:inRange:`,
`addAttribute:value:range:`, and
`replaceCharactersInRange:withAttributedString:`. The base attributed-string
coder selectors and `_NSReadMutableAttributedStringWithCoder` are now present.

## Concrete mutable attributed-string owner completion (2026-10-03)

IDA confirms `NSConcreteMutableAttributedString classForCoder` returns the
`NSMutableAttributedString` class and its `initWithCoder:` calls `super init`,
then the shared reader, deallocating the receiver on a false result
(`0x42588688`, `0x425886ac`). Its longest-range attribute lookup
(`0x42511f14`) scans adjacent run dictionaries and extends while the requested
attribute values are pointer-identical or equal; the result is intersected
with the caller's range. `addAttribute:value:range:` (`0x4251f9a4`) copies each
run dictionary with `newWithKey:object:`, replaces changed runs, and calls the
edited hook once for a nonempty range. `replaceCharactersInRange:withAttributedString:`
(`0x42522d04`) inserts copied source attribute runs at the replacement offset,
deletes the old attribute span after those insertions, replaces the string, and
calls the edited hook with mask 3 and the length delta.

The exported `_NSAttributeDictionaryClass` helper (`0x42510f40`) now shares the
configured class lookup used by this source; it looks up `NSAttributeDictionary`
and falls back to `NSSimpleAttributeDictionary`. The exact-owner audit now
reports every `NSAttributedString.json` method present exactly once. The full
Foundation selector audit reports 333 missing definitions, zero renames, and
zero duplicates. `git diff --check` is clean. Tests and builds were not run.
