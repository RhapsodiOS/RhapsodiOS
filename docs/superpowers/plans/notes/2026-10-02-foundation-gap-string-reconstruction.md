# Foundation mutable string gap-buffer reconstruction

Reference: Foundation i386 IDA database `6c2a913dc37a`.

The mutable-string ABI record lists `NSCStringWithGap` and
`NSUnicodeStringWithGap` as 24-byte subclasses. Both add `gapBegin` at offset
16 and `gapEnd` at offset 20. Their target methods include capacity
initialization, `_setRequiredLength:gapPosition:delete:extraRoom:`, gap-copy
helpers, indexed and ranged character access, packing, and byte conversion.
The corresponding class implementations now live beside their concrete
superclass implementations in `NSSimpleCString.m` and `NSSimpleString.m`.

The gap storage keeps the logical prefix before `gapBegin` and the logical
suffix beginning at `gapEnd`. Capacity uses the target's compact 16-bit
encoding. `_setRequiredLength:` moves the requested prefix and suffix around
the new gap, grows or shrinks storage according to the target's extra-room
policy, and creates separate storage when the gap object is shared. The copy
helpers advance the gap start as characters are inserted. `_pack` moves the
suffix next to the prefix, and the character/byte accessors translate logical
indexes across the gap.

The capacity initializer records the encoded reserve while leaving the gap
indexes at zero; the reserve does not mean that a backing buffer has already
been allocated. The empty zero-length `_setRequiredLength:` path likewise
keeps the buffer unallocated.

`NSConcreteMutableString` now initializes from an existing string and handles
range replacement through the matching C-string or Unicode gap class. When
its current gap storage is owned and can represent the replacement, it moves
the gap to the range, deletes the old characters, and inserts the replacement.
Otherwise it builds a new gap from the unchanged prefix, replacement, and
unchanged suffix. Self-replacement snapshots the source before mutation. The
`withCharacters:length:` entry point uses the Unicode gap class, and
`withCString:length:` decodes with the target file-system encoding before
delegating to string replacement. The generated ABI JSON already records
both gap layouts and their selectors, so no ABI-file change was needed.

The concrete mutable-string constructors now cover `init`, formatting,
byte decoding, and no-copy C-string/Unicode inputs. `initWithBytes:length:encoding:`
uses `_NSConvertToASCIIorUnicode2` and installs its result in the matching gap
class. The custom retain/release counter, retain count, mutable copy, and
copy-and-release entry points are also present. `setStringWithFormat:` uses
the existing NSString formatter and then replaces the current contents.

The remaining `NSMutableString` class factories now allocate
`NSConcreteMutableString`, call the matching NSString initializer, and
autorelease the result. The formatting factories pass their variadic arguments
to the concrete formatter; the localized variant uses the standard defaults
dictionary. `classForCoder` reports `NSMutableString`. `initWithCoder:` follows
the target's version 0 property-list path and version 1 NSString decoding path,
raising `NSGenericException` for unsupported versions. These methods match
the corresponding implementations in Foundation i386 IDA instance
`d12fe2f23883`.

Static checks: a source scan found no trailing whitespace or unbalanced
Objective-C interface/implementation blocks; the ABI JSON parsed and
confirmed both 24-byte layouts and ivar offsets. No tests or builds were run.

## `setStringWithFormat:` source-state correction (2026-10-09)

The earlier summary that `setStringWithFormat:` uses the existing NSString
formatter is not an accurate reconstruction. Both i386 (`0x4250ab70`) and PPC
(`0x4250f9dc`) clear the receiver and parse/substitute into it directly. The
current source instead allocates an NSString and calls
`initWithFormat:locale:arguments:`; that initializer creates an
`NSConcreteMutableString` and calls `setStringWithFormat:` again, causing
recursion. The two target implementations use chunked UTF-16 scanning,
conversion records, argument-pointer resolution, and direct output
substitution. The approved direct parser is now implemented in
`NSMutableString.m`; see the 2026-10-08 current-gap audit for the source-to-IDA
mapping. Static paired IDA/source review only; no tests or builds were run.
