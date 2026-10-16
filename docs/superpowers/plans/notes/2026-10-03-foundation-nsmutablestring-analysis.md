# Foundation `NSMutableString` primitive replacement methods

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSMutableString.json`.

The ABI manifest contains two instance methods on `NSMutableString` that were
missing from the source: `replaceCharactersInRange:withCharacters:length:` and
`replaceCharactersInRange:withCString:length:`. IDA shows both wrappers
allocating an `NSString` with zone `NULL`, initializing it from the supplied
buffer, forwarding to `replaceCharactersInRange:withString:`, and releasing
the temporary string. `NSConcreteMutableString` has its own optimized
overrides and is unchanged here.

The wrappers and public declarations are now present in `NSMutableString.m`
and `NSString.h`. Verification is limited to manifest selector coverage and
source hygiene; no build or runtime check has been run.

`-[NSConcreteMutableString replaceCharactersInRange:withCString:length:]`
also takes a distinct conversion path in IDA (`0x4251af18`). When the byte
encoding differs from the Objective-C C-string encoding, ASCII input remains
on the C-string path; non-ASCII input is converted with
`_NSConvertToASCIIorUnicode2` using the default file-system encoding. Conversion
failure raises `NSCharacterConversionException` with `"%@: Bad cString"`; a
result that is still a C string raises `NSInternalInconsistencyException` with
`"%@: Didn't get Unicode"`. The converted Unicode buffer is passed to the
character replacement method and released when allocated. The source now
follows those conversion and exception branches. The existing gap-string
mutation path remains the lower-level storage implementation.

## Whole-range replacement ownership branch (2026-10-07)

Both target implementations of
-[NSConcreteMutableString replaceCharactersInRange:withString:] contain a
special branch when the range covers the entire receiver and
contentsIsMine is clear: copy the replacement into the receiver's zone,
release the old contents, then recompute the C-string and owned-gap flags.
The i386 body is at 0x4250f694; PPC is at 0x42507f9c. The source now uses
this branch before constructing a new gap buffer. This preserves the target's
copy/release and class-selection path. Static source and whitespace checks
only; tests and builds were not run.
