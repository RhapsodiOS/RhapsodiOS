# Foundation `__NSParseStringsFile` analysis

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/NSBundle.m`.

## IDA behavior

IDA decompiles `_NSParseStringsFile` at `0x42570c64` as a path-based parser
with a logging flag. It reads the file into `NSData`, returns `nil` when the
read fails, and recognizes the legacy serialized-property-list header when
the length is greater than seven, divisible by four, and the first four bytes
are a small tag followed by three zero bytes. That branch calls
`NSDeserializer` with a zero cursor and immutable containers.

Other inputs are initialized as an `NSString` from the file data and parsed
with `propertyListFromStringsFileFormat`. The function installs an exception
handler around that parse. `NSParser.m` confirms this parser raises
`NSParseErrorException` for syntax failures. IDA handles that exception by
logging the reason only when the flag is set and returning `nil`; other
exceptions release the temporary objects and are rethrown. The loaded data is
released on both normal parser paths.

The reference has no callers for this export in the current IDA database.

## Existing source equivalent and differences

`NSBundle.m` has the static `NSBundleParseStringsFile(path, logErrors)`
helper, which implements the same binary-header test, immutable binary plist
decode, strings-file parse, optional syntax-error logging, and data cleanup.
It additionally requires the parsed result to be an `NSDictionary`, and its
exception handler logs every caught exception rather than rethrowing
non-syntax exceptions.

The apparent text-encoding difference is not material: IDA chooses Unicode
for either UTF-16 byte-order mark and otherwise uses
`+[NSString defaultCStringEncoding]`. The existing `-[NSString
_initWithDataOfUnknownEncoding:]`, used by `-initWithContentsOfFile:`, makes
the same choice before calling `initWithData:encoding:`. Thus the current
helper's text path has matching encoding selection, while its result filter
and exception policy remain distinct from the export.

The exported `_NSParseStringsFile` is now implemented in `NSBundle.m`. Its
text path explicitly applies the recovered UTF-16 BOM/default-encoding rule,
and its exception handler returns `nil` only for `NSParseErrorException`,
rethrowing other exceptions after releasing the temporary string and data.
The `NSBundle` caller retains its dictionary-only contract in a small wrapper.
The ABI, symbol, and ownership manifests now claim the export. No tests or
builds were run.
