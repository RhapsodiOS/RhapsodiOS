# Foundation Stage 3 string-module reconnaissance

This note records the first focused analysis pass for the Foundation string
reconstruction. The reference remains the DR2 i386 Foundation slice:

- SHA-256: `1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`
- Profile: `tools/binrecon/profiles/foundation-i386-strings.json`
- Helper profile: `tools/binrecon/profiles/foundation-i386-string-support.json`
- Scoped source module: `NSString.m`
- IDA: 9.4

`binrecon module-scope --module NSString.m` produced 97 scoped functions.
This updates the older design estimate of 88 functions / 65 runs. The source
map initially matched 62 functions and left 35 unmapped. After adding the
disassembly-backed methods below and regenerating the map, it matches 80 and
leaves 17 unmapped, with zero boundary disputes and duplicate candidates.
Several remaining entries are private methods or belong to
`NSPlaceholderString`, so this is an implementation and attribution queue, not
evidence that those functions are absent from the reference.

The reference analysis completed and published
`tools/binrecon/out/foundation-i386-strings/published/analysis-reference-ida.json`.
Its scope intentionally has no rebuilt-source comparison yet, so the analyzer
reports `normalized-functions=FAIL` and exits nonzero at the comparison
acceptance step. The reference analysis itself is complete. The generated
`out` directory is ignored; rerun the analysis to recreate it.

Disassembly-backed implementations in `src/Kits/Foundation/NSString.m` now
cover `getCharacters:range:`, `getCharacters:`, `description`, `classForCoder`,
`replacementObjectForPortCoder:`, `substringFromIndex:`, `substringToIndex:`,
`isEqualToString:`, `isEqual:`, `hasPrefix:`, `hasSuffix:`, `rangeOfString:`,
`rangeOfString:options:`, the three `rangeOfCharacterFromSet:` wrappers, the
`compare:`/`compare:options:`/`compare:options:range:` wrappers,
`caseInsensitiveCompare:`, `copyWithZone:`, and `mutableCopyWithZone:`. Range
and comparison methods forward through the same selectors and arguments seen
in the reference disassembly. The `NSString` and placeholder `allocWithZone:`
methods forward to the reference helper; placeholder `init` returns the shared
empty string. `NSPlaceholderString` has the reference ABI layout
(`zoneForString` at offset 4), identity `retain`/`release`/`autorelease`,
immortal `retainCount`, no-op `dealloc`, and an `initWithCString:` forwarder.

The helper profile adds a separate IDA analysis of
`__NSPlaceholderStringFromZone` (one 339-byte function). Its disassembly
confirms that placeholder allocation reuses objects by zone, lazily creates
the placeholder array, and optionally locks the cache while reading or
updating it. The placeholder-zone helper/cache implementation and the
remaining `NSPlaceholderString` initializers are still outstanding.

The reference ABI and current source map are now checked in at
`src/Kits/Foundation/reconstruction/abi/NSString.json` and
`src/Kits/Foundation/reconstruction/strings-text/source-map.json`.

The ABI comparison showed that the old stub file combined reference modules.
The mutable-string implementation, property-list category, and encoding
category are now in `NSMutableString.m`, `NSParser.m`, and
`NSStringEncodings.m`, with ABI documents generated for those modules. UTF-8
convenience stubs absent from the reference were removed from `NSString.m`.
The rebuilt `NSString.m` object has no unexpected methods, classes, or
categories; 17 reference methods remained missing in `NSString.m` and
`NSPlaceholderString`. The compiled `NSStringEncodings.m` category matches its
reference ABI. The multi-module ABI check reported 50 divergences: those 17
string methods, four parser classes in `NSParser.m`, 15 classes or methods in
`NSMutableString.m`, and 14 other committed ABI modules without built objects.

## Follow-up reconstruction

IDA analysis of `_NSRequestConcreteImplementation` at `0x4256fb04` confirms the
abstract-method exception paths. `NSString -length` and
`-characterAtIndex:` call the helper with `[NSString class]`; the
`NSPlaceholderString` versions first log
`Did you forget to nest [NSString allocWithZone:NULL] and init?` and then call
the same helper. The helper raises `NSInvalidArgumentException`, choosing a
message for a direct abstract-class call or for a subclass that failed to
override the selector. The C `%s` formats and argument order follow the
reference helper's two `NSException +raise:format:` call sites. Its source is
assigned to `NSObjCRuntime.m` based on its runtime-helper role; that module
attribution is a source organization choice, not recovered original module
metadata.

The separate `foundation-i386-abstract-string` profile preserves the helper's
IDA output. Like the other reference-only profiles, its analyzer exits 1 at
the normalized-functions comparison gate because no rebuilt helper object is
included in that profile. `_NSRequestConcreteImplementation` is present in
the rebuilt `NSObjCRuntime.m` ABI. `NSFault.m` now calls the reconstructed
helper for `completeInitializationOfObject:`; the existing fault test's
expected exception name was updated to match the reference. No tests were run.

The six remaining `NSPlaceholderString` constructors are now implemented
from their reference paths: bytes and data conversion, C-string and no-copy
initialization, string copying/retention by zone, and formatted initialization
through `NSConcreteMutableString`. The conversion buffer follows the helper's
16-byte header and 1008-byte inline storage. The conversion and inline-string
helpers remain external dependencies for the concrete-string reconstruction.
The regenerated `strings-text/source-map.json` now maps 88 functions and has
9 unmapped private `NSString` methods, with no boundary disputes or duplicate
candidates. The six-module ABI comparison reports 40 divergences: nine
remaining `NSString` methods, four parser classes, 15 mutable-string classes
or methods, and 12 other modules without built objects. The updated
`NSString.m` compiles on the isolated i386 guest with only its existing
incomplete `NSCoding` warnings.

The first Objective-C compile found two malformed method definitions in the
existing file (`UTF8String` and `writeToURL:atomically:` had a semicolon before
the body); those syntax errors have been corrected. A subsequent compile on the
isolated Rhapsody i386 guest succeeded. The duplicate class implementation was
corrected to the declared `NSExtendedStringPropertyListParsing` category and
moved to `NSParser.m`. Remaining compiler warnings cover unimplemented
`NSCoding` methods and incompatible pointer return types in untouched stubs.
The three new module sources also compile. No test suite was run in this pass.

The follow-up pass reconstructed `NSString -initWithCoder:` and
`-encodeWithCoder:` from the decoder-version and UTF-8 byte paths, plus
`-_newSubstringWithRange:zone:` and `-_newSubstringFromRange:zone:` from the
range checks, empty/full-range cases, and zone-backed copy path. The substring
exception format uses both the concrete class name and selector. A further
`-_initWithDataOfUnknownEncoding:` uses the reference's even-length UTF-16 BOM
check and otherwise selects the default C-string encoding. The refreshed
source map now covers 93 of 97 scoped functions, with four unmapped methods,
zero boundary disputes, and zero duplicate candidates. The i386 object builds;
its module ABI check reports only those four missing NSString methods, plus 17
other ABI modules that were not supplied to this single-module check. No tests
were run.

The next pass completed the remaining four scoped NSString methods:
`-_caseCopyAux::flags:` and its uppercase, lowercase, and capitalization
dispatch; `-displayableString`; `-_stringRepresentation`; and
`-quotedStringRepresentation`. Character escaping uses the reference's
NextSTEP conversion helper as an external dependency. The map now covers all
97 scoped functions, with no unmapped functions, boundary disputes, or
duplicate candidates. The recompiled i386 object has no NSString ABI
divergences; the ABI check still notes 17 other modules for which no object was
supplied. The guest compiler emitted an implicit-declaration warning for
`NSRequestConcreteImplementation` from its staged header set. No tests were
run.

The encoding follow-up recovered the reference's 128-entry Unicode-to-NextSTEP
mapping table and binary-search helper into `NSStringEncodings.m`, resolving
the representation methods' conversion dependency. The Latin and special-case
branches of `NSConvertToUpper`, `NSConvertToLower`, and `NSConvertToTitle` are
now reconstructed, including Turkish I handling, ligatures, sharp-s, and
Latin-1 ranges. The reference's three Unicode-wide helpers were traced to its
lazily loaded `CaseMapping` tables. `NSStringEncodings.m` now reads the architecture-specific
Foundation resource, builds the lower/upper/title table views from its four-word
header, and binary-searches the sorted source/destination pairs. The table
loader also retries the unsuffixed resource name as the reference does. The DR2
resource pair confirms the expected 8,184-byte layout: 703 lowercase, 673
uppercase, and 668 title mappings. Both `NSString.m` and
`NSStringEncodings.m` compile for i386. Their ABI comparison has no NSString
or encoding-category divergences; 16 other ABI modules were not included as
built objects. Existing pointer-return warnings remain in three untouched
encoding stubs. No tests were run.

The encoding-category pass now implements `getBytes:maxLength:filledLength:encoding:allowLossyConversion:range:remainingRange:`, the JIS state-switching writer, both `dataUsingEncoding:` variants, `canBeConvertedToEncoding:`, `smallestEncoding`, and `fastestEncoding`. The `getBytes:` dispatcher uses 32-code-unit reads, encoding-specific loss handling, and dedicated UTF-16 and JIS paths. The JIS writer reuses the autoreleased EUC result and emits the reference's ASCII, Katakana, and Kanji escape sequences.

The next pass extracted the reference's single-byte Unicode mapping tables and lossy-ASCII transliteration data, then reconstructed the shared table search and ASCII, NextSTEP, Adobe Cyrillic, ISO Latin 1/2, Windows 1250/1252/1253/1254, Mac Roman, Symbol, lossy ASCII, EUC, UTF-8, and common Shift-JIS converters. This pass adds the reference's EUC row FE vendor range and six defined A2-row substitutions; non-table A2 cells retain the arithmetic conversion already in place. Tracing the proprietary path shows that `_NSDefaultCStringEncoding` reads a resource setting and loads `CStringEncoding.obj` when it selects the proprietary encoding. The Objective-C module callback captures an encoding class, while the converter and callback-registration globals belong to that dynamically loaded module. The i386 compile succeeds with only the existing pointer-return warning in the untouched `availableStringEncodings` stub. A targeted ABI check for `NSString.m` and `NSStringEncodings.m` reports `ABI matches`. No tests were run.

The C-string category now reconstructs `lossyCString`, `cStringLength`, `cString`, and all three `getCString` entry points from their reference implementations. Lossy conversion starts in a 500-byte stack buffer and grows into autoreleased storage when the converter reports a remaining range; strict conversion reports `NSCharacterConversionException`. The updated encoding source compiles for i386 on the guest, with only the existing warning from the unimplemented `availableStringEncodings` stub. A targeted ABI comparison for `NSString.m` and `NSStringEncodings.m` reports `ABI matches`. No tests were run.

This pass reconstructs `_NSDefaultCStringEncoding`'s resource-file lookup and fallback, the proprietary module-load attempt, and the proprietary converter-registration adapters. It defines the reference's default Mac Roman encoding value and recovers the exact ordered list returned by `availableStringEncodings`, including the proprietary entry when that is the selected encoding. The encoding source compiles for i386 without warnings, and the targeted ABI comparison reports `ABI matches` after adding the recovered C symbols and encoding global to the module manifest.

The next pass reconstructed `localizedNameOfStringEncoding:` from its IDA disassembly and constant data. Built-in encodings map to the exact `EncodingNames` lookup keys, proprietary encoding delegates to `_NSProprietaryEncodingName`, and unknown values return `__NSEmptyString`. The reference's `__NSFoundationBundle` cache helper was recovered into `NSBundle.m`, including its `NSConcreteArray` lookup and `/System/Library/Frameworks/Foundation.framework` fallback. Compilation and ABI comparison could not be rerun: the configured i386 guest at `127.0.0.1:2222` refused the SSH connection, and no local Objective-C compiler is installed.

The `CStringEncoding.obj` provider is not present in the checkout, so its implementation remains unavailable for source-level reconstruction.

`NSString -substringWithRange:` was then reconstructed from its IDA pseudocode: it calls `_newSubstringWithRange:zone:` with `[self zone]` and autoreleases the result. The same investigation found that the placeholder-zone helper's optional lock is allocated by `__NSToDoAtFirstThreadStart` and released by `__NSToDoAtLastThreadExit`; implementing the helper alone would leave a missing global and break the reference's multithreaded path. Its lifecycle dependency is queued for reconstruction with the thread-start hooks. The guest compile remains unavailable because `127.0.0.1:2222` has no listening SSH service; the checked-in `start-vm.cmd` also has no SSH host-forwarding rule.

The strings source map's `NSString.m` line references after `substringWithRange:` were shifted to reflect its expanded implementation. JSON parsing and the exact locations of `substringWithRange:` and its two helper methods were verified; no i386 compile or ABI comparison was possible.

`NSString -hash` now follows the reference's `NSHashString` fold: start from the UTF-16 length, fold every character for lengths up to 16, and for longer strings fold the first and last eight characters, then mix in the length shifted by its low five bits. The reference ABI and source map already include the method; the map's later `NSString.m` line references were shifted by the added implementation. Compile and ABI checks remain unavailable while the i386 guest's SSH endpoint is down.

## Next work

Trace the provider-side code loaded from `CStringEncoding.obj`, then reconstruct the placeholder cache and its thread-start lock lifecycle. The concrete string
classes remain open work;
reconstruct the classes in their reference modules (`NSSimpleString.m`,
`NSSimpleCString.m`, and `NSConstantString.m`). Add source maps and ledgers for
the separated string modules, then build a comparison profile with rebuilt
Foundation sources and reconcile its source map and ABI evidence.

`NSString -rangeOfComposedCharacterSequenceAtIndex:` now follows the recovered IDA control flow: bounds checking, backward base-character search, surrogate-pair adjustment, and forward extension over nonbase characters. The one-time `NSCharacterSet` cache mirrors the binary's lazy initialization. Its runtime behavior still depends on `NSCharacterSet` methods that remain placeholders in this checkout. The NSString source-map line references were shifted for the expanded method. No tests were run.

`NSString -stringByAppendingString:` and its shared `_NSNewStringByAppendingStrings` helper now follow IDA: empty operands are copied, nonempty strings use the default C encoding when all inputs support it, and otherwise concatenate UTF-16 code units. The helper is recorded in the NSString ABI manifest and source map. No tests were run.

`NSString -stringByAppendingFormat:` now formats through the placeholder string initializer, joins the receiver and formatted result through the recovered append helper, then releases the temporary format result. Its source-map line references were updated. No tests were run.

`NSString -getLineStart:end:contentsEnd:forRange:` and `lineRangeForRange:` now scan UTF-16 code units around the range, handle CR, LF, CRLF, U+2028 and U+2029, and preserve the reference bounds check and empty-range behavior. The source-map entries after the expanded method were shifted. No tests were run.
The i386 compile could not be run in this pass: no local C/Objective-C compiler command is available, and `127.0.0.1:2222` refuses the guest connection. The NSString source map matches the six modified method/helper declarations checked directly; the ABI and source-map JSON parse, and `git diff --check` passes.

`NSString -rangeOfString:options:range:` now validates the requested range and searches code units in the requested direction, with anchored and case-insensitive behavior taken from IDA. It returns `NSNotFound` for an empty search string, matching this Foundation build. Search pattern storage uses a 100-code-unit stack buffer and zone allocation for longer patterns. The source-map line references after this method were shifted. No tests were run.

`NSString -rangeOfCharacterFromSet:options:range:` now validates its range, returns `NSNotFound` for an empty range, and walks forward or backward according to the search flags. Anchored backward searches test only the last code unit. The source-map references after the method were shifted. Its range-set membership dependency is now implemented; builtin-set membership remains unimplemented. No tests were run.

NSString -compare:options:range:locale: now compares the selected receiver range with the argument by UTF-16 code unit, including the reference's ASCII-only case folding and length ordering. Locale-specific collation remains unimplemented; the reference delegates that case to a separate collation engine. Source-map line references after the method were shifted. No tests were run.

NSCharacterSet now reconstructs range-backed sets, small string-backed sets, and the large-string initializer path. Range-backed sets delegate to NSImmutableRangeCharacterSet, which stores 16-bit low/high bounds and checks a half-open interval; it clears bounds for an empty range or NSNotFound. Character-string sets of at most 64 UTF-16 units use NSImmutableStringCharacterSet, which copies into a fixed buffer, sorts with the recovered unsigned-short comparator, and checks membership by linear scan. Longer strings use NSConcreteMutableCharacterSet with the ABI-confirmed 20-byte instance layout (`set`, `bits`, `data`, `isMutable`); initialization expands its empty set into an 8192-byte bitmap and sets the input UTF-16 bits. Its membership method uses the reference's bitmap lookup. Bitmap initialization, copy-on-write on mutation, mutable bitmap output, and the base-class bitmap fallback are also reconstructed; bitmap APIs depend on the separate NSData implementation. These methods correspond to IDA: range factory 0x425868d0 (42 bytes), range class factory 0x42586ffc (134), range membership 0x4258a47c (38), string factory 0x425340e0 (212), string membership 0x42532384 (62), public string factory 0x4254196c (131), mutable-set init 0x42589348 (153), large-string init 0x42589194 (59), mutable string membership 0x42588b00 (311), bitmap factory 0x42586884 (76), bitmap initializer 0x42589128 (107), and make-fast 0x42589618 (50). Generated the reference ABI baseline at `src/Kits/Foundation/reconstruction/abi/NSCharacterSet.json`. File loading and builtin sets remain open. No tests were run.

The mutable concrete set now also implements range/string insertion and removal, union, intersection, inversion, and the ABI-declared mutable range/string factories. Operations detach a cached bitmap before writing; set algebra uses bytewise operations for another concrete bitmap set and character membership otherwise. The recovered selectors and layouts remain in the NSCharacterSet ABI baseline. No tests were run.

The immutable range and string classes now expose their recovered count, emptiness, equality, bitmap, copy, and mutable-copy behavior. `NSInvertedCharacterSet` now wraps and retains/copies the real set as indicated by its mutability, complements membership and bitmap data, reports the inverted count/empty state, and returns the wrapped set on a second inversion. These bitmap and copy paths still depend on the unfinished `NSData` behavior where they request bitmap storage. No tests were run.

`NSCharacterSet -isEqual:` now checks for bitmap-representation support and compares bitmap data; `-hash` delegates to the bitmap data hash. The concrete mutable set adds the reference's identity fast path before using this shared equality behavior. This matches IDA for `-[NSCharacterSet isEqual:]`, `-[NSCharacterSet hash]`, and `-[NSConcreteMutableCharacterSet isEqual:]`. The equality path still relies on `NSData -isEqual:` and bitmap generation. No tests were run.

The `.bitmap` initializer now retains and references data up to 8191 bytes, otherwise copies 8192 bytes into zone storage. The `.dict` resource index is loaded from `/System/Library/Frameworks/Foundation.framework/Resources/CharacterSets/CharacterSets.dict`; its `characters` arrays build immutable string sets, while `singles` and inclusive `ranges` are converted through a bitmap into the reference's compressed set layout. Compressed mutable sets now support membership, count, bitmap expansion on mutation, and 40-byte-header dynamic-size copies. The matching `_initWithSet:` initializer and array-to-immutable-string factory are also present. No tests were run.

The built-in `NSCharacterSet` factories now return the reference's twelve cached `NSBuiltinCharacterSet` instances. Their ASCII membership rules use the recovered predicates and six 32-byte tables; Unicode membership lazily loads the named `.dict` set through the reconstructed catalog reader. Bitmap creation, equality, mutable copy, coding, and immortal-object ownership follow the traced built-in class behavior. Bitmap creation still depends on unfinished `NSMutableData` methods. No tests were run. Static checks were limited to table values, whitespace, and ABI JSON parsing because no local C/Objective-C compiler is available.

Named character set loading now tries individual `.dict` and `.bitmap` resources before falling back to `CharacterSets.dict`; catalog definitions become compressed concrete sets. `characterSetWithName:` caches loaded objects behind a recursive lock, and `_readAndRetainFileNamed:makeCompact:` applies the requested compact and immutable state. The concrete set implements bitmap-to-compressed compaction and `isCompact`. Paired IDA review shows `init` leaves the mutable-state byte zero, `isMutable` returns it directly, `makeImmutable` writes zero, and mutators raise only when it is nonzero; the source now follows that behavior. These paths follow IDA at `_findDictOrBitmapSetNamed:` (0x4258698c), `_readAndRetainFileNamed:makeCompact:` (0x42586b2c), `characterSetWithName:` (0x42586c9c), `makeCharacterSetCompact` (0x425895e0), `isCompact` (0x42589510), `freeBitsAndReleaseDataIfNecessary` (0x425890d4), and `makeImmutable` (0x4258964c). No tests were run; compile verification remains unavailable without an Objective-C compiler.

`NSExpandedBuiltinCharacterSet` now routes its twelve class factories through `_readAndRetainFileNamed:makeCompact:` using the traced resource names and compact flags. Its four instance operations log and raise via `doesNotRecognizeSelector:` as in the reference. `NSBuiltinCharacterSet -expandSetWithOffset:` now dispatches to those factories instead of opening the catalog directly, so Unicode expansion shares the named-set cache and compact representation path. These class factories and the four failing instance methods were traced at 0x42586dec–0x42586fd0 and 0x4258a208–0x4258a2c8. No tests were run.

The abstract `NSCharacterSet -characterIsMember:` and `NSMutableCharacterSet` mutation methods now log and raise through `doesNotRecognizeSelector:` instead of returning false or doing nothing. IDA confirms this behavior for the base selectors at 0x42588328 and 0x4258b018–0x4258b220. Concrete subclasses keep their implementations.


The same `NSData.m` pass now implements the shared byte-read methods, `isEqualToData:`, and `isEqual:`: full and length-limited reads copy from the immutable byte view, range reads reject a nonempty range beginning at or beyond the end and clamp its tail, and object equality accepts only NSData instances before delegating to byte equality. IDA evidence includes `-[NSData getBytes:]`, `getBytes:length:`, `getBytes:range:`, `isEqualToData:`, and `isEqual:` (0x425220e8). A follow-up trace found that concrete immutable data uses a 20-byte base object with inline storage up to 16 bytes, owned heap or page-backed storage for copied buffers, and optional ownership of no-copy buffers. The public byte constructors, `initWithData:`, immutable copying, and `NSSubrangeData` are now reconstructed. Large concrete-data ranges use the reference's 64-byte view threshold; other views follow its 32-KiB threshold, and nested subranges coalesce onto their original backing object. IDA evidence includes concrete initialization (0x4252430c), `NSData` allocation redirection (0x4251d3ec), copy (0x4253e478), subdata selection (0x42543ebc), and subrange initialization/access/teardown (0x42582ff8, 0x42582ad0, 0x425831a4, 0x42582b18). File and URL reads/writes and mapped-file construction remain open. No tests were run; no local C/Objective-C compiler is available.

The `NSData` file path now includes file reads, mapped reads, writes, and file-URL forwarding. Reads check for a regular file and retain the reference's single-read behavior; mapped reads use Mach `map_fd` and mark backing pages for VM teardown. Writes preserve existing permissions, fsync output, use exclusive same-directory temporary files for atomic replacement, and restore the original file if the replacement fallback fails. The high-level flows follow `initWithContentsOfFile:` (0x42520398), `initWithContentsOfURL:` (0x4257d504), mapped initialization (0x4255339c), `writeToFile:atomically:` (0x4253b9ec), `writeToURL:atomically:` (0x4257d998), and helpers `_NSReadBytesFromFile` (0x425204fc), `_NSMapBytesFromFile` (0x42551dbc), and `_NSWriteBytesToFile` (0x4253bc54). As of 2026-10-04, `NSDataGetFileSystemPath` delegates to NSString's `getFileSystemRepresentation:maxLength:` method, which uses `_NSDefaultFileSystemEncoding` (0x42514354) and caps converted path bytes at the reference's 1024-byte limit. URL methods delegate to NSURL, whose file-URL parsing and path accessors are still placeholders. No tests were run; no local C/Objective-C compiler is available.

NSURL's file-URL slice now implements scheme/host/path construction, file URL factories, URL string/base storage, scheme and resource-specifier access, absolute-string forwarding, file-scheme recognition, direct path extraction, and URL teardown. IDA confirms the construction format %@://%@%@ and the localhost file host (0x42608330, 0x42608354), plus the initializer/accessor behavior traced at 0x42594684–0x425958bc. The implementation deliberately leaves general relative URL resolution, escaping, path standardization, and other URL components for later: their parser and NSString path/escape dependencies are not implemented in source. git diff --check passes; no tests were run, and no local Objective-C compiler is available.

The follow-up NSURL pass added a shared component-range parser for scheme, user, password, host, port, path, parameters, query, and fragment; these slots were mapped from the _NSParseStringToGenericURLComponents call sites. IDA's parser is now available at `0x4259596c`, and the source parser has been replaced with its scan order, including first-`@` and first-colon handling and authority termination at slash. Component accessors now share that parser while keeping their internal missing-component sentinels. `standardizedURL` normalizes the resolved path. Percent escape decoding and host/scheme escaping remain open. No tests or builds were run.

A later NSURL review filled out the traced accessors (host, port, user, password, fragment, parameters, and query), added relative file-path URL construction and initializer argument exceptions, and tightened base-component fallback. The latest absoluteString implementation follows the reference's cases for authority, path, query, and fragment inheritance; standardizedURL applies dot-segment normalization to the resolved path. The source still lacks percent-escape decoding/encoding, file-manager directory detection for trailing slashes, and full validation parity with the reference parser.

NSString URL/path support now implements stringByAddingPercentEscapes, stringByRemovingPercentEscapes, standardizedURLPath, and standardizedNativePath in NSPathUtilities.m. IDA evidence: escape method 0x425965a4 preserves the traced ASCII allowlist and delegates each other UTF-16 character to 0x425958f8, which emits uppercase percent plus two low-byte hex digits; removal at 0x4259633c decodes percent triplets to one UTF-16 code unit. `standardizedURLPath` uses `pathComponents` (collapsing repeated separators and exposing the root marker), while `standardizedNativePath` uses `componentsSeparatedByString:@"/"` and retains empty components. PPC URL standardization skips a leading `/` or `~` component during escaping and rebuilds a trailing slash; i386 applies escaping before checking the transformed root component, so an escaped root is no longer recognized as `/`. The reconstruction now follows the architecture-specific order. PPC methods abort with nil if a component conversion returns nil; i386 retains its different observed behavior. NSURL now uses those methods for path construction, decoding, and escaped accessors. git diff --check passes; no tests were run, and no local Objective-C compiler is available.

NSString -isAbsolutePath now implements the traced POSIX absolute-path check by examining the leading slash; NSURL path initializers use this selector as the reference does.

The NSPathUtilities pass now implements pathComponents and pathWithComponents with the reference's optional drive prefix, root marker, and repeated-separator handling; isAbsolutePath recognizes leading slash or tilde. Added lastPathComponent, stringByDeletingLastPathComponent, stringByAppendingPathComponent, pathExtension, stringByDeletingPathExtension, and stringByAppendingPathExtension from their IDA helper behavior. IDA helper evidence: _NSPathComponents 0x4253aa18, _NSIsAbsolutePath 0x42525434, _NSStartOfLastPathComponent 0x4251a7a0, _NSLengthAfterDeletingLastPathComponent 0x4251f6cc, _NSAppendPathComponent 0x42514578, and extension helpers 0x4251d578 / 0x42541618 / 0x425446a0. Full stringByStandardizingPath and filesystem home/symlink functions remain open.

NSPathUtilities now implements stringByExpandingTildeInPath, lexical stringByStandardizingPath, and stringByResolvingSymlinksInPath, plus NSUserName, NSFullUserName, NSHomeDirectory, NSHomeDirectoryForUser, NSTemporaryDirectory, and NSOpenStepRootDirectory. User/home lookup follows passwd records with the reference's USER/HOME fallback and identity-sensitive cache invalidation; temporary and OpenStep root behavior follows /tmp and NEXT_ROOT. Relative file URL initialization now uses stringByStandardizingPath. The symlink resolver uses realpath; full _NSStandardizePath parity for symlink-aware dot-dot resolution and private-root rewriting remains open. git diff --check passes; no tests were run and no local Objective-C compiler is available.

The next NSPathUtilities trace found that `-[NSString getFileSystemRepresentation:maxLength:]` at `0x42519920` delegates to `NSFileManager`'s `getFileSystemRepresentation:maxLength:withPath:` using the default manager, and `-[NSString fileSystemRepresentation]` at `0x4254595c` delegates to `fileSystemRepresentationWithPath:`. `-[NSString stringsByAppendingPaths:]` at `0x425829b8` returns an autoreleased copy of the input array when the receiver equals the empty string; otherwise it allocates a mutable array with matching capacity and appends each entry using `stringByAppendingPathComponent:`. The two NSString filesystem methods therefore depend on the still-unimplemented NSFileManager path conversion methods. No source code changed in this trace pass.

The dependent NSFileManager filesystem-representation path is now traced. `+[NSFileManager defaultManager]` at `0x42514fe8` lazily allocates and retains one process-wide manager. `-[NSFileManager fileSystemRepresentationWithPath:]` at `0x42540424` raises for nil or empty paths, converts the path with `_NSDefaultFileSystemEncoding`, allows up to 1024 output bytes, raises if conversion fails, NUL-terminates the bytes, and returns the bytes owned by a new NSData object. `-[NSFileManager getFileSystemRepresentation:maxLength:withPath:]` at `0x42510300` returns NO for nil/empty input or failed conversion, clears the first output byte on nil/failure, and otherwise appends NUL after the converted bytes. `-[NSFileManager stringWithFileSystemRepresentation:length:]` at `0x42542fb4` creates an NSString with `initWithBytes:length:encoding:` using the default filesystem encoding and autoreleases it. `_NSDefaultFileSystemEncoding` at `0x42514354` reads the decimal value from the Foundation resource path `/FileSystemEncoding`, caches a positive result, and falls back to `_NSDefaultCStringEncoding` when unavailable or invalid. These behaviors are direct dependencies of the NSString wrappers at `0x42519920` and `0x4254595c`. No source code changed in this trace pass.

The remaining path-completion category was traced. `-[NSArray pathsMatchingExtensions:]` at `0x4253ee98` returns a mutable array containing each original path whose `pathExtension` is nonempty and appears in the supplied extension array; matching uses `containsObject:` (and therefore the array's normal equality behavior). `_NSDirectoryContentsMatchingPrefixAndSuffixes` at `0x425849a8` expands the directory tilde, enumerates directory contents, filters by a nonempty filename prefix, and accepts entries whose extension matches `filterTypes`; when the extension does not match, it still includes extensionless entries that are directories. A nil or empty filter array disables extension filtering. `-[NSString completePathIntoString:caseSensitive:matchesIntoArray:filterTypes:]` at `0x425824a4` has two paths: `~prefix` enumerates passwd usernames and prefixes matches with `~`; ordinary paths derive directory and final-component prefix, call the helper, and descend through a sole directory match until ambiguous matches or a file are found. Optional outputs receive either the common prefix/match list or the unique completion. `_NSFindCommonPrefixInStringArray` at `0x42584c3c` advances by composed-character sequence and checks each candidate at offset zero, using case-insensitive search unless the caller requested case-sensitive completion. This path depends on NSFileManager directory enumeration and `fileExistsAtPath:isDirectory:`. No source code changed in this trace pass.

The supporting NSFileManager file checks and directory listing were also traced. `fileExistsAtPath:` and `fileExistsAtPath:isDirectory:` (`0x42533adc`, `0x4253251c`) obtain the UTF-16 length, cap it at 1026 code units, request UTF-8 contents without copying into a temporary mutable string, then call `_NSFileExistsAtPath` (`0x4252e394`); the latter converts through the file manager, uses `lstat` and conditionally follows symbolic links with `stat`. The directory output is derived from `st_mode & S_IFMT == S_IFDIR`. The readable/writable/executable methods (`0x4253a7f0`, `0x42553064`, `0x4253ca0c`) all route through `_NSFileAccessibleForMode` (`0x4253591c`), which converts the path then calls `access` with R_OK/W_OK/X_OK. `fileAttributesAtPath:traverseLink:` (`0x4252e338`) chooses `lstat` or `stat` and converts a successful result through `NSFileAttributes attributesWithStat:`. `directoryContentsAtPath:` (`0x42532aac`) delegates to the extension/options variant (`0x42531800`), which converts its path and optional extension, then calls `_NSDirectoryList` (`0x42521d4c`). That helper opens the directory, iterates legacy `getdirentries` records, skips `.` and `..`, applies extension and case options, converts names with `_convertToUTF8`, and returns an NSStringArray backed by no-copy NSData. No source code changed in this trace pass.

The filesystem-representation trace is now implemented. `_NSDefaultFileSystemEncoding` caches the decimal value from `Resources/FileSystemEncoding` and falls back to `_NSDefaultCStringEncoding`; `NSFileManager` now provides its singleton and all three traced conversion methods, including the 1024-byte conversion limit, NUL handling, nil/empty behavior, and failed-conversion exception. The two NSString filesystem-representation methods forward through the default manager. `stringsByAppendingPaths:` and `NSArray -pathsMatchingExtensions:` now follow the recovered loops and empty-input/filter behavior. Added scoped ABI entries for the new NSFileManager methods and the encoding helper. Static checks: `git diff --check` and JSON parsing pass. No tests were run; no Objective-C compiler command was found on PATH.

`NSString -completePathIntoString:caseSensitive:matchesIntoArray:filterTypes:` is now implemented from IDA at `0x425824a4`, with `_NSDirectoryContentsMatchingPrefixAndSuffixes` (`0x425849a8`) and `_NSFindCommonPrefixInStringArray` (`0x42584c3c`) reconstructed as local helpers. Completion handles `~user` enumeration through passwd entries, extension-filtered directory matches (retaining extensionless directories), case-aware common prefixes at composed-character boundaries, and repeated descent through a unique directory result. `git diff --check` passes; no tests were run and no Objective-C compiler command is available on PATH.

`NSFileManager -isDeletableFileAtPath:` now follows IDA at `0x4257f5c8` and its `fileStat` helper at `0x4252f24c`: it checks the containing directory's writability and `lstat` mode, then applies sticky-directory owner rules to an existing target using `lstat` and `getuid`. Added the selector to the scoped NSFileManager ABI manifest. `git diff --check` passes; no tests were run and no Objective-C compiler command is available on PATH.

`NSFileManager -pathContentOfSymbolicLinkAtPath:` now follows IDA at `0x42557b3c`: it converts the input path, reads at most 1024 bytes with `readlink`, and decodes exactly the returned byte count with the filesystem encoding. Added the selector to the scoped NSFileManager ABI manifest. No tests were run and no Objective-C compiler command is available on PATH.

`NSFileManager -createSymbolicLinkAtPath:pathContent:` now follows IDA at `0x4257f2f0`, converting both arguments with the filesystem encoding before calling `symlink`. Added its i386 selector signature to the scoped NSFileManager ABI manifest. No tests were run and no Objective-C compiler command is available on PATH.

`NSFileManager -contentsAtPath:` now follows IDA at `0x4257ebe0`, allocating NSData, initializing it from the file path, and autoreleasing it. `-createDirectoryAtPath:attributes:` follows `0x42557bb8` and `_NSCreateDirectory2` (`0x4251f7c0`): convert the path, call `mkdir` with mode `0777`, then pass nonnil attributes to the existing attribute-change method while preserving the reference's return behavior. Added both selectors to the scoped NSFileManager ABI manifest. No tests were run and no Objective-C compiler command is available on PATH.

The `NSDictionary (NSFileAttributes)` accessors now follow IDA at `0x4257dc1c` (size), `0x4257db80` (modification date), `0x4257dcc4` (type), `0x4257dbdc` (permissions), `0x4257dba8` (owner), `0x4257db4c` (group owner), `0x4257dc8c` (filesystem number), and `0x4257dc54` (filesystem file number). `fileSize` reads `NSFileSize` through `longLongValue`; date, type, and owner names return the keyed values; POSIX permissions mask the unsigned value with `0xFFF`; and filesystem/file numbers use `unsignedIntValue`. Added all eight category selectors to the NSFileManager ABI manifest with their recovered i386 encodings. No tests were run and no Objective-C compiler command is available on PATH.

The public `NSFileManager.h` file-attribute key exports had no definitions elsewhere in the Foundation sources. Added definitions for all 21 declared `NSFileType*`, `NSFile*`, and `NSFileSystem*` keys using their IDA string literals at `0x425fd6d4`–`0x425fd87c`, and recorded their exported data symbols in `NSFileManager.json`. Reconstructed private `NSFileAttributes` from IDA: its `dict` pointer is at object offset 4, followed by the 96-byte stat record at offset 8; `attributesWithStat:` copies the stat record; `fileAttributesAtPath:traverseLink:` now selects `stat` or `lstat` and returns the class; keyed reads and specialized file-attribute accessors read that record, while count, key enumeration, and hash lazily materialize the dictionary. Those lazy dictionary operations still depend on the incomplete NSMutableDictionary and NSDate implementations. Added the class layout and selector encodings to the ABI manifest. No tests were run.

The next NSFileManager pass implements `currentDirectoryPath` and `changeCurrentDirectoryPath:` from `_NSGetDirectory2`/`_NSSetDirectory2` (`getcwd`/`chdir`, at `0x4254135c`/`0x425362f0`). It also implements `fileExistsAtPath:`, its directory-reporting variant, and the readable, writable, and executable checks, following the traced path conversion and `lstat`/conditional `stat` or `access` behavior (`0x42533adc`, `0x4253251c`, `0x4253a7f0`, `0x42553064`, `0x4253ca0c`; helpers `0x4252e394`, `0x4253591c`). The scoped NSFileManager ABI manifest now includes these selectors. No compiler was found on PATH; no tests were run.

`NSFileManager -directoryContentsAtPath:` and its extension/options/keep-extension variant are now implemented from the `_NSDirectoryList` trace (`0x42532aac`, `0x42531800`, helper `0x42521d4c`). The implementation converts paths and entry names with the filesystem encoding, omits `.` and `..`, applies the traced dot-extension suffix filtering and option-bit case-insensitive comparison, and strips the matched suffix when requested. It uses `opendir`/`readdir` to obtain directory entries rather than parsing `getdirentries` records directly; the result remains an NSArray of decoded names. Added both selectors to the scoped NSFileManager ABI manifest. `git diff --check` and manifest JSON parsing pass; no compiler was found on PATH and no tests were run.

NSDate now reconstructs `_NSCurrentTime` with `gettimeofday` relative to the 2001 reference epoch, redirects plain NSDate allocation to the private 16-byte NSConcreteDate, and implements its interval constructors, date arithmetic, ordering, equality, copy, and hash methods. IDA traces confirm NSConcreteDate's refcount at offset 4 and double at offset 8, plus its initializer/accessor and the date factories and epoch conversion (`0x42507ac0`, `0x4250f0c8`, `0x425120d4`, `0x42520be8`, `0x42539188`, `0x4253936c`, `0x4259afe8`, `0x4259b0e8`). Distant past/future now use the immortal NSDistantDate implementation and exact reference intervals `-63113817600` and `63113990400` from `_NSToDoAtProcessStart` (`0x4254aee8`); source initializes the shared instances on first request, while the reference creates them at process start. Description still delegates to the unfinished NSCalendarDate category. Added both private class layouts and their reconstructed selectors to NSDate.json. No tests were run.

NSMutableDictionary now redirects base allocation to NSConcreteMutableDictionary and implements capacity construction, keyed reads and writes, removals, count, hash/equality, removal of all entries, and key enumeration. The private table follows IDA's three-word header, bucket state bits, dense mode at the first two capacities, open addressing thereafter, and the recovered capacity/bucket sequences (`0x425012dc`, `0x42501328`, `0x42501370`, `0x425032fc`, `0x42503a3c`, `0x42503550`, `0x425065f0`, `0x4250df5c`; arrays at `0x425a44c0` and `0x425a4530`). A later data check confirmed capacity levels 3/7/11/... map to bucket counts 4/8/16/...; allocation and probe masks now use that bucket sequence. The NSFileAttributes lazy dictionary can now use a mutable concrete dictionary. Property-list serialization remains unfinished. Added the private dictionary and enumerator layouts to NSDictionary.json. `git diff --check` and the ABI JSON parse pass; no tests were run.

NSDictionary now redirects base allocation to NSConcreteDictionary and implements array/pointer factories, object/key varargs construction, dictionary copying, designated initialization, key lookup/enumeration, dictionary equality, and the reference's count-based hash. The immutable concrete class uses the same table representation as the mutable implementation, copying keys and retaining values; the base equality/hash methods are inherited by both concrete classes. IDA evidence includes base allocation/factories (`0x42514dec`, `0x4251a804`, `0x42539138`, `0x4253b398`, `0x4251d210`), concrete initialization and lookup (`0x425086c4`, `0x42515034`, `0x4250455c`), equality (`0x4253b14c`), and hash (`0x4255e818`). Added NSDictionary and NSConcreteDictionary selectors/layout to NSDictionary.json and corrected the mutable concrete selector list. File/URL property-list reads, serialization, and descriptions remain open. `git diff --check` and ABI JSON parsing pass; no tests or builds were run.

The dictionary read surface now includes `getObjects:` and `getObjects:andKeys:`, `allKeys`, `allKeysForObject:`, `allValues`, `objectEnumerator`, and `objectsForKeys:notFoundMarker:`. These follow IDA's key-enumerator loops and identity/equality checks at `0x4255e708`, `0x4255e788`, `0x4255d4b4`, `0x4255d350`, `0x4255d5e0`, `0x425247a0`, and `0x4255ed38`. Object enumeration snapshots the dictionary values and retains the dictionary through the private enumerator, matching the reference's snapshot lifetime. Added both `getObjects` declarations and ABI entries. No tests or builds were run.

NSArray's immutable core now redirects base allocation to NSConcreteArray and implements the recovered concrete layout (`_info` count at offset 4, `_items` pointer at offset 8), empty-array singleton, retained object storage, count/index access, ranged copies, and pointer/array/varargs construction. IDA evidence: `+[NSArray allocWithZone:]` 0x425106a8, `-[NSArray count]` 0x425033c8, `-[NSArray objectAtIndex:]` 0x425013c0, `-[NSConcreteArray initWithObjects:count:]` 0x4250dc64, init 0x4255823c, dealloc 0x4250d65c, and `getObjects:`/`getObjects:range:` 0x4255a338 / 0x42518518. Added NSArray.json with the reconstructed layouts and selectors. This supplies immutable arrays used by NSDictionary constructors and read methods. No tests or builds were run.

NSMutableArray now redirects allocation to NSConcreteMutableArray and reconstructs its `_info`/`_items`/`_size` layout, capacity and object-array initialization, storage growth, insertion, replacement, removal, bulk removal, range replacement, and array copying/appending methods. IDA evidence includes `initWithCapacity:` 0x425151f0, `initWithObjects:count:` 0x4251981c, growth helper 0x4250f044, `addObject:` 0x42509204, insert 0x42519b44, indexed/last removal 0x425187d8 / 0x425189a0, replacement 0x425311f8, remove-all 0x4251a56c, index removal 0x4255f4d0, and range replacement 0x4255f7f0. Added NSMutableArray and NSConcreteMutableArray ABI entries to NSArray.json. Sorting, object coding, and array property-list I/O remain open. No tests or builds were run.

NSArray now also implements append-by-object/array, equality and identity searches, common-object lookup, array equality, last-object access, range slicing, and forward/reverse object enumeration. IDA evidence: `arrayByAddingObject:` 0x42550910, `arrayByAddingObjectsFromArray:` 0x42558474, contains/index lookup 0x42507874 / 0x42524910 / 0x4255a68c, `firstObjectCommonWithArray:` 0x42558304, identity search 0x425049c8 / 0x4255a6b8, `isEqualToArray:` 0x4251bbd8, `lastObject` 0x4252b76c, enumerator factories 0x42534c08 / 0x4255a8dc, and `subarrayWithRange:` 0x4255402c. NSIdEnumerator reconstructs retained-target lifetime, forward/reverse cursor behavior, `allObjects`, and owned snapshot cleanup from 0x4251d188, 0x42506d1c, 0x4255f0f0, and 0x42519780. `initWithArray:copyItems:` and `copyWithZone:` follow 0x4251ea6c / 0x4252e1f0. Added the method encodings and enumerator layout to NSArray.json. Sorting and property-list I/O remain open. No tests or builds were run.

NSArray sorting now implements `sortedArrayHint`, stable comparator sorting, selector-based sorting, and hash-hint ordering. IDA evidence: hint generation 0x4255aa64, stable `_NSMergeSort` 0x4251c878, plain sorting 0x4252c100, hint reuse 0x4255abd8, selector comparator wrapper 0x4250d584, and selector entry point 0x42525c20. The hint path now uses the reconstructed NSMapTable implementation to retain reference hash-bucket ordering. To make hints round-trip, NSSerialization now implements integer serialization, indexed integer reads, and integer-array reads following 0x42580c48, 0x4257d04c, and 0x4257d0a0. Added the sort selectors to NSArray.json and the serialization selectors to NSSerialization.json. No tests or builds were run.

NSMapTable now reconstructs its callback ABI tables, zone-aware creation, dense small-capacity and open-addressed sparse bucket storage, resizing, lookup/insertion/removal, copy and comparison, enumeration, reset/free, and all-key/all-value snapshots. IDA evidence includes creation 0x4251f898 / 0x42540f34, `NSMapGet` 0x42503468, insert 0x4250489c / known-absent 0x4251301c / if-absent 0x425293cc, member 0x42504eac, removal 0x4250dd88, reset 0x42546198, count 0x425251f0, map enumeration 0x42525e48 / next pair 0x425034c0, compare 0x42562edc, copy 0x42563054, and key/value extraction 0x42530314 / 0x42562ccc. Callback table values were read from 0x42603094–0x42603154; object key hashing/equality/ownership/description wrappers were traced at 0x42503530, 0x42508164, 0x4250bb8c, 0x425103a0, and 0x42563f10. Added NSMapTable.json and registered its C symbols and callback data exports in symbols.json. No tests or builds were run.

NSSerialization now covers integer-array writes, indexed integer writes, cursor reads/writes, and page-aligned payload length markers. IDA traces: serializeInt:atIndex: 0x42580c90, serializeInts:count: 0x42580ce4, serializeInts:count:atIndex: 0x42580d24, aligned length encoding 0x42580ba0, cursor integer/array reads 0x4257d020 / 0x42506510, aligned length decoding 0x42534df0, and cursor byte reads 0x42508668. The ABI manifest now includes these selectors. No tests or builds were run.

NSMutableArray now implements in-place sorting by function and selector. IDA confirms the reference copies values into temporary storage, merge-sorts, writes directly to concrete array storage, and retain/replaces/releases for non-concrete subclasses (sortUsingFunction:context: 0x4253c79c; sortUsingSelector: 0x42548104). The implementation reuses the stable merge sorter reconstructed for NSArray and adds both selector encodings to NSArray.json. No tests or builds were run.

NSArray now implements both makeObjectsPerformSelector variants. IDA traces show the no-argument selector forwarding nil and the main implementation dispatching directly over concrete storage or in 128-object batches for other subclasses (0x425042b4, 0x42504018). The selector encodings were already present in NSArray.json. No tests or builds were run.

NSArray componentsJoinedByString: now joins each element's description with the separator using a Unicode character buffer; it returns the empty string for an empty array and a copied description for a one-element array, matching IDA at 0x42530cbc. The selector was already present in NSArray.json. No tests or builds were run.

NSEnumerator now raises the reference concrete-implementation exception for the abstract nextObject: method, and allObjects drains nextObject into a mutable array until nil. IDA evidence: 0x4255f0b4 and 0x4255f050. Added NSEnumerator.json with both selectors. No tests or builds were run.

NSData description now emits a bracketed lowercase hex dump, appending a space after each four-byte group as in the reference. IDA traces: -[NSData description] 0x4257cd88, _to2HexDigits 0x4258628c, and _toHexDigit 0x425862c0. The implementation uses an inline buffer for short values and zone memory for larger dumps. No tests or builds were run.

NSFormatter now matches the recovered base behavior: stringForObjectValue: and getObjectValue:forString:errorDescription: call NSRequestConcreteImplementation; editingStringForObjectValue: delegates; attributed formatting returns nil; and partial-string validation returns YES. IDA addresses: 0x4258a308, 0x4258a334, 0x4258a360, 0x4258a39c, and 0x4258a3a8. Added NSFormatter.json. No tests or builds were run.

NSDateFormatter now implements its initializer and format/natural-language accessors. IDA confirms format strings are copied, nil selects the embedded default `%Y-%m-%d %H:%M:%S %z`, and the flag is stored directly (0x4258a0d0, 0x42589e70, 0x42589e60). Added NSDateFormatter.json with the reconstructed method encodings and instance layout. No tests or builds were run.

Expanded NSDateFormatter to cover its remaining binary methods: default initialization, versioned coding, format ownership on deallocation, date-to-string formatting, and string parsing with optional natural-language fallback and localized parse failure. IDA traces: init 0x4258a140, dealloc 0x42589e80, encodeWithCoder: 0x42589ecc, initWithCoder: 0x42557c04, stringForObjectValue: 0x4258a164, and getObjectValue:forString:errorDescription: 0x42589f28. No tests or builds were run.

NSLock, NSConditionLock, and NSRecursiveLock now reconstruct their extra-byte mutex/condition storage, blocking and timed acquisition, nonblocking acquisition, condition handoff, recursion tracking, wakeup/deallocation handling, allocators, and descriptions. The NSLock traces include init 0x42539968, allocWithZone: 0x42539a94, lock/unlock 0x42501508 / 0x42501384, tryLock/lockBeforeDate: 0x4257ff20 / 0x4257fe78, dealloc 0x4254e998, and description 0x4257fe24. NSConditionLock and NSRecursiveLock methods were traced at 0x42576e9c–0x4257c5b4 and 0x42545260–0x425818dc. Added their records to NSLock.json. Timed waits use the repository cthreads API's millisecond units. No tests or builds were run.

NSDistributedLock now reconstructs path validation, directory acquisition/release, lock-date lookup, descriptions, and deallocation. Added the private NSFileManager directory feasibility method, recursive removeFileAtPath:handler: behavior, and `_NSFileModificationUNIXTime` helper needed by its traces. IDA traces: NSDistributedLock methods at 0x4254f634–0x42551798 and 0x4257ddd8–0x4257de6c; directory feasibility 0x4254f438; modification-time lookup 0x42525754; recursive removal 0x4254ecd0. Added NSDistributedLock.json and registered the new NSFileManager selector and C helper. The note's original recursive-removal slice did not yet include the target's sticky-directory rename and ENOTEMPTY fallbacks; these were reconstructed later. No tests or builds were run.


## 2026-10-02 — NSMutableString concrete forwarding slice

Added IDA-confirmed NSConcreteMutableString capacity initialization and forwarding methods for length, encoding, character/byte access, CString access, copying, appending, equality, hash, ranges, comparison, substring creation, and teardown in NSMutableString.m. The 12-byte private object layout matches reconstruction/abi/NSMutableString.json: 8-bit refcount, four single-bit flags/reserved, 16-bit capacity, then contents. IDA shows initializer capacity compression above 0x7fff using _capacityToInternal, and the source mirrors that formula. Mutable replacement and initWithString remain open because target mutation paths depend on the missing NSCString/NSUnicodeString and gap-backed storage classes; this slice does not make mutable edits operational yet. No tests or builds were run.


## 2026-10-02 — simple string storage decompilation

IDA confirms NSSimpleCString is a 12-byte NSString subclass with bytes at offset 4 and numBytes at offset 8; NSSimpleString has the same layout with UTF-16 characters and numCharacters. -[NSSimpleCString length] returns numBytes, characterAtIndex: bounds-checks then maps high-bit bytes through _NSCStringCharToUnichar, and getCharacters:range: performs the same conversion per byte. _fastCStringContents returns bytes directly; hash delegates to NSHashCString; copyWithZone: either retains by zone or creates an inline C string. -[NSSimpleString length], characterAtIndex:, and getCharacters:range: operate directly on UTF-16 storage, with a range check before memmove; hash delegates to NSHashCharacters. NSCString and NSUnicodeString extend the simple classes by four bytes of ownership/capacity flags; their no-copy initializers forward to the base initializer and store the freeWhenDone bit. This is the required base layer for NSCStringWithGap and NSUnicodeStringWithGap. Neither module has a source implementation in this checkout; next implement core storage methods in the ABI-named modules, then reconnect the mutable gap classes.


The UTF-16 storage base is now implemented in NSSimpleString.m and registered in the Foundation Makefile. NSSimpleString provides the recovered no-copy initializer, length, bounds-checked character access, range copy, direct _characters access, and zone-aware buffer teardown. NSUnicodeString adds the recovered ownership-bit initializer/deallocator and compact 8-bit retain-count path with external overflow counts, retain locking, and allocation-statistics events. This supplies the superclass behavior used by the Unicode gap string; CString storage still needs its encoding conversion helper and corresponding module.


NSSimpleString.m now supplies the Unicode backing layer and is included in Makefile.preamble. ABI coverage is still partial: the two classes retain additional copy/encoding selectors, and the CString storage module plus mutable gap subclasses remain unfinished. The source implements NSUnicodeString ownership/refcount paths confirmed in IDA. `NSSimpleString`'s `characterAtIndex:` and `getCharacters:range:` now use the target's method proem in their range exceptions; the target format strings are preserved. No tests or builds were run.


## 2026-10-02 — CString storage core

Added NSSimpleCString.m and registered it in the Foundation build list. The module reconstructs the 12-byte NSSimpleCString storage layout already declared in NSString.h, no-copy initialization, length/encoding accessors, direct C-string access, IDA-shaped byte/character range reads, the target CString hash fold, and NSCString's 16-byte ownership/refcount layout and initializers. At the time of this note high-byte decoding still depended on `_NSCStringCharToUnichar`; the 2026-10-02 addendum below records its recovered default converter and replaceable function-pointer slot. Copy/substring and additional comparison selectors remain ABI gaps. No tests or builds were run.
# 2026-10-02 MacRoman byte-to-Unicode hook

The IDA function at `0x42591650` is `_NSMacOSRomanToPrecompUnicode`: bytes at
or below `0x7f` are returned directly and high bytes index the 128-entry
MacRoman table at `0x425A89E0` (the high-byte half of the word data beginning
at `0x425A88E0`). The exported `_NSCStringCharToUnichar` slot initially points
to this function, leaving the slot replaceable by an encoding provider.

`NSStringEncodings.m` now defines that default converter and initializes the
function-pointer slot; `NSSimpleCString.m` declares the slot with the matching
indirect-call type. Table values were read from the IDA database. No tests or
builds were run.

## 2026-10-02 initial NSCharConversion reconstruction

Added `NSCharConversion.m` to provide the missing `_NSConvertToASCIIorUnicode2`
entry point. Its 16-byte header and 1008-byte inline payload match the caller's
`NSStringConversionBuffer` layout. The confirmed paths implemented so far are
empty input, byte-order-marked or big-endian Unicode, Non-lossy ASCII escapes,
ASCII, NEXTSTEP, ISO Latin-1, Symbol, Mac Roman, Windows 1250/1251/1252/1253/1254,
and UTF-8. The single-byte and UTF-8 offset tables were extracted directly from
IDA. The ABI manifest and Foundation build list now include the module. ISO
Latin-2, EUC, Shift-JIS, ISO-2022-JP, and proprietary decoders remain; no tests
or builds were run.

## 2026-10-07 — directory-listing reconstruction

`NSFileManager.m` now routes the extension-filtered directory method through
the same packed-entry flow as the i386 and PPC helpers. The public method still
converts the path and prefixes a supplied extension with `.`. The helper uses
`open` and `getdirentries`, skips unused records and `.`/`..`, applies the
case-sensitive or option-bit-0 case-insensitive suffix test, and converts each
filesystem name through the default filesystem encoding to UTF-8. It packs the
NUL-terminated UTF-8 names into a no-copy `NSData` and returns
`NSStringArray stringArrayWithUTF8Data:`. A directory-read error returns nil.

IDA references: i386 `_NSDirectoryList` at `0x42521d4c`, PPC
`_NSDirectoryList` at `0x42530ca8`, and i386 `_convertToUTF8` at
`0x42585654`. The scratch conversion string and conversion buffer follow the
target ownership path. No build or runtime tests were run.

The PPC recursive-removal ENOTEMPTY path
(`-[NSFileManager removeFileAtPath:handler:]` at `0x42594704`) also uses `_NSDirectoryList` and
recursively removes the remaining children with a nil handler. The i386 path
at `0x4254ecd0` instead clears entries with `opendir`/`readdir` and retries
`rmdir`. `NSFileManager.m` now preserves that architecture split.

## `NSString stringsByAppendingPaths:` implementation (2026-10-07)

The i386 method at `0x425829b8` returns a copy of `paths` in the receiver's
zone when the receiver is the empty string. Otherwise it creates a mutable
array with matching capacity and appends each path with
`stringByAppendingPathComponent:`. The PPC image has no matching method.
`NSPathUtilities.m` now implements the i386-only path, matching the existing
selector and type encoding in `NSPathUtilities.json`. Static source/metadata
checks only; no tests or builds were run.

## URL percent-escape architecture parity (2026-10-07)

The i386 methods at `0x425965a4` and `0x4259633c` escape and decode UTF-16
characters. PPC methods at `0x425b07ec` and `0x425b05c8` first convert through
the default filesystem encoding, operate on bytes, then decode the result with
that encoding. `NSPathUtilities.m` now keeps the i386 character path and uses
PPC byte buffers for both methods, including nil on conversion failure and
returning the receiver when no byte needs conversion. PPC initializes the
escaping accumulator from the byte prefix at the first escape, while the
decoding accumulator starts with capacity and appends byte ranges. The
`NSURLPathUtilities.json` module now names the actual compiled source file,
`NSPathUtilities.m`. Static source/metadata checks only; no tests or builds
were run.

### `_NSStandardizePath` paired source recheck (2026-10-07)

Recompared the existing `_NSStandardizePath` implementation in
`NSPathUtilities.m` against DR2 i386 `0x425179bc` and MOSXS PPC
`0x425296ac`. The current source follows the paired bodies' order for slash
transmutation, trailing-slash handling, UNC detection, symlink resolution for
absolute paths containing `..`, `/.` removal, leading `./` removal, embedded
`/./` and `/../` reduction, final slash cleanup, and `/private/` stripping
when the stripped path exists. The helper bodies for slash transmutation,
trailing-slash trimming, absolute-path detection, and `..` detection also
match the current IDA control flow. Symlink conversion uses the existing
NSFileManager filesystem-representation methods, corresponding to the target's
conversion helpers. The earlier statement that full standardization remained
open is superseded for this source path. Static paired IDA/source review only;
no tests or builds were run.
