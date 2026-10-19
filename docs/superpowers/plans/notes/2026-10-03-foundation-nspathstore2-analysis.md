# Foundation `NSPathStore2` analysis

Reference: Foundation i386 IDA database `d12fe2f23883`, Mach-O symbols,
and `src/Kits/Foundation/reconstruction/abi/NSPathUtilities.json`.

## Current source and ABI state

`NSPathUtilities.m` has no `NSPathStore2` implementation or definitions for
the low-level path helpers called by the class. It contains separate NSString
path and URL helpers. The ABI record defines `NSPathStore2` as an `NSString`
subclass with 8-byte fixed instance size, `_lengthAndRefCount` at offset 4,
and variable inline UTF-16 characters at offset 8. Its packed word stores the
length in the upper 12 bits and retain count in the lower 20 bits. The record
contains three class methods and 21 instance methods; IDA has named symbols for
all 24.

## Confirmed method behavior

- `pathStoreWithCharacters:length:` allocates the object with `2 * length`
  extra bytes, copies the characters, strips trailing path slashes, stores the
  resulting length and autoreleases the object.
- `pathStoreWithCString:` computes the byte length, obtains the default C
  string encoding, converts to ASCII or Unicode, returns nil on conversion
  failure, allocates inline character storage, strips trailing slashes, stores
  the converted length and autoreleases the object. The decompiler shows an
  exception path when conversion reports its first status flag.
- `pathWithComponents:` obtains component objects and lengths, copies each
  component's characters into a stack path buffer, appends components using
  `_NSAppendPathComponent`, and normalizes slash direction and trailing
  slashes before constructing the result. The disassembly-derived pseudocode
  uses a 1026-character working buffer and logs when append fails.
- `length`, `characterAtIndex:`, and `getCharacters:range:` read the packed
  length and inline characters. The indexed/range methods raise on bounds
  violations. `getCharacters:range:` permits a zero-length copy.
- `retain` and `release` update the low 20-bit count under the global retain
  lock when present. Saturated counts are left unchanged; releasing a zero
  count deallocates through `NSObject`. `retainCount` is the low bits plus one.
  `copyWithZone:` returns a retained self.
- `hash` delegates to `NSHashCharacters`. `isEqualToString:` compares inline
  UTF-16 directly for another `NSPathStore2`, otherwise obtains the other
  string's length and characters and compares those.
- Path queries and transformations delegate to the existing binary helpers:
  `_NSStartOfPathExtension`, `_NSStartOfLastPathComponent`,
  `_NSLengthAfterDeletingLastPathComponent`,
  `_NSLengthAfterDeletingPathExtension`, `_NSIsAbsolutePath`,
  `_NSPathComponents`, `_NSExpandTildeInPath`, `_NSAbbreviatePathWithTilde`,
  `_NSResolveSymlinksInPath`, and `_NSStandardizePath`.
- Appending a path component returns self for a nil component; otherwise it
  reads the component as UTF-16, invokes `_NSAppendPathComponent`, transmutates
  slashes to `/`, strips trailing slashes, and constructs a new path store. A
  failed append logs and returns self. Appending an extension uses
  `_NSAppendPathExtension`, then performs the same slash normalization and
  constructs a new path store; failure logs and returns self.
- The tilde expansion, standardization, and symlink methods use a 1024-character
  stack workspace and return a new path store. Symlink resolution expands the
  tilde, resolves links, then standardizes. Tilde abbreviation uses the same
  bounded workspace.

These descriptions reflect the decompiler output and helper calls; behavior
inside the low-level path helpers has not been re-derived here. The methods
with computed stack buffers or external helper calls need source-level designs
that preserve the reference's edge cases before implementation.

## `NSTemporaryDirectory` architecture split (2026-10-07)

The DR2 i386 `_NSTemporaryDirectory` body (`0x425553d4`) copies the result of
`_NSTempDirectory` into `+[NSPathStore2 pathStoreWithCString:]` and standardizes
it. MOSXS PPC (`0x4259a6a8`) instead obtains `NSFileManager`'s default manager,
counts the temporary path bytes, calls
`stringWithFileSystemRepresentation:length:`, and standardizes that string.
The PPC stack buffer is 1,044 bytes; i386 uses 1,028. `_NSTempDirectory` is
the same `"/tmp"` copy returning success on both targets (`0x4259d020` PPC,
`0x425550bc` i386). `NSPathUtilities.m` now keeps the two result-construction
paths and buffer sizes separate. `+[NSPathStore2 pathStoreWithCString:]` is
guarded out of the PPC build because the PPC image has no such selector. Static
comparison only; no tests or builds were run.

## Text symbol map

| Kind | Selector | Address |
| --- | --- | ---: |
| class | `pathStoreWithCharacters:length:` | `0x4250d45c` |
| class | `pathStoreWithCString:` | `0x42546f44` |
| class | `pathWithComponents:` | `0x42546cac` |
| instance | `getCharacters:range:` | `0x42507a1c` |
| instance | `length` | `0x4250dd78` |
| instance | `release` | `0x4250e44c` |
| instance | `isEqualToString:` | `0x425119f4` |
| instance | `stringByAppendingPathComponent:` | `0x42514a14` |
| instance | `stringByAppendingPathExtension:` | `0x425162e4` |
| instance | `retain` | `0x4251a2a8` |
| instance | `copyWithZone:` | `0x425220c8` |
| instance | `hash` | `0x42524a90` |
| instance | `pathExtension` | `0x4252aba4` |
| instance | `characterAtIndex:` | `0x4252f2b0` |
| instance | `lastPathComponent` | `0x4253005c` |
| instance | `stringByDeletingLastPathComponent` | `0x42530664` |
| instance | `stringByStandardizingPath` | `0x4253108c` |
| instance | `stringByResolvingSymlinksInPath` | `0x42532b10` |
| instance | `stringByDeletingPathExtension` | `0x425331fc` |
| instance | `isAbsolutePath` | `0x42536b08` |
| instance | `stringByAbbreviatingWithTildeInPath` | `0x4254683c` |
| instance | `retainCount` | `0x42548014` |
| instance | `pathComponents` | `0x425499f0` |
| instance | `stringByExpandingTildeInPath` | `0x425810d8` |

No source implementation, test, or build was added or run for this analysis.

## Existing source comparison

The NSString category in `NSPathUtilities.m` already implements the same path
selector family (`pathWithComponents:`, `pathComponents`, absolute-path checks,
component and extension extraction, append/delete operations, tilde expansion,
standardization, abbreviation, and symlink resolution). Those methods rely on
`NSPathNormalizeSlashes`, `NSPathAppendComponent`, and
`NSPathStartOfExtension`, which are local high-level helpers in this file.
This is a useful behavior reference, but not a drop-in implementation of the
binary class: the binary stores inline UTF-16, returns `NSPathStore2` objects
from its factories, and uses its own low-level path helpers. Any reuse must
avoid recursively dispatching the overridden path selectors and should compare
edge cases against the decompiled methods first.

## Low-level helper findings

The path helper symbols are also named in IDA and were decompiled by address.
This clarifies several edge cases that the Objective-C method pseudocode alone
does not show:

- `_NSTransmutePathSlashes` converts `/` to its requested separator while
  collapsing repeated `/`, except it preserves an initial doubled backslash
  prefix. `_NSStripTrailingPathSlashes` preserves `/` and drive roots such as
  `C:/`; it removes additional trailing slashes elsewhere.
- `_NSAppendPathComponent` treats an empty component as success with no change,
  rejects a component that would exceed its supplied capacity, and rejects an
  absolute drive or UNC component when the path is non-empty. It inserts `/`
  except when the current path is empty, `/`, or a two-character drive/UNC root.
- `_NSStartOfPathExtension` searches only the final path component and does not
  treat the dot in a two-character drive prefix as an extension. The deletion
  helper returns the original length if no extension exists. The append helper
  rejects `/` and drive-prefixed extensions, strips trailing slashes, and
  rejects extension appends to a bare tilde user path. Its decompilation has an
  indirect jump for paths of length at most three, decoded below from the
  original bytes.
- The last-component helpers recognize drive prefixes. Deleting the last
  component preserves `/` and a three-character drive root (`C:/`).
- `_NSIsAbsolutePath` returns true only for leading `~` or `/` (or false for an
  empty string); it does not classify drive-prefixed paths as absolute.
- `_NSExpandTildeInPath` substitutes the current or named user's home only
  when the replacement fits its explicit capacity. `_NSAbbreviatePathWithTilde`
  requires a complete home-directory prefix and a slash boundary, then rewrites
  it to `~`.
- `_NSResolveSymlinksInPath` converts to a filesystem representation, checks
  components with `lstat`, resolves through `realpath`, and converts back to
  UTF-16 within a bounded workspace. `_NSStandardizePath` normalizes slash
  direction, strips trailing separators, handles `.` and `..` components, may
  resolve symlinks when `..` occurs, and contains a special `/private/` path
  shortening check through `NSFileManager`.
- `_NSPathComponents` returns drive prefix and root slash as separate initial
  components, skips repeated separators between components, and creates each
  component from the original UTF-16 buffer.

Helper addresses: `_NSTransmutePathSlashes` `0x42501df8`,
`_NSStripTrailingPathSlashes` `0x42506da0`, `_NSStartOfPathExtension`
`0x425121e8`, `_NSAppendPathComponent` `0x42514578`,
`_NSAppendPathExtension` `0x42516410`, `_NSStandardizePath` `0x425179bc`,
`_NSStartOfLastPathComponent` `0x4251a7a0`,
`_NSLengthAfterDeletingLastPathComponent` `0x4251f6cc`, `_NSIsAbsolutePath`
`0x42525434`, `_NSLengthAfterDeletingPathExtension` `0x42531770`,
`_NSResolveSymlinksInPath` `0x42531c4c`, `_NSExpandTildeInPath` `0x425323c4`,
`_NSPathComponents` `0x4253aa18`, and `_NSAbbreviatePathWithTilde` `0x42542c6c`.

Additional helpers used by path standardization:

- `_pathHasDotDot` only flags a complete `..` component on an absolute path.
  For UNC input it skips the server/share prefix before scanning components.
  This predicate controls whether `_NSStandardizePath` first tries symlink
  resolution.
- `_NSFileExistsAtPath` converts UTF-16 through `NSFileManager` and checks
  `lstat`; for symlinks it also follows with `stat`. `_NSStandardizePath` uses
  this when considering removal of a leading `/private/` prefix.
- `_convertToFileSystemRepresentation` wraps the supplied UTF-16 in a cheap
  mutable string, asks `NSFileManager` for filesystem bytes, and returns the
  resulting byte length or failure. `_convertToUnichars` uses the default
  filesystem encoding, bounds the converted character count to the caller's
  capacity, and raises when the conversion helper reports its exception flag.

Addresses: `_pathHasDotDot` `0x42512120`, `_NSFileExistsAtPath`
`0x4252e394`, `_convertToUnichars` `0x42531a94`, and
`_convertToFileSystemRepresentation` `0x42531b68`.

For `_NSAppendPathExtension`'s short-path indirect jump, the table at
`0x425164a0` contains entries `0xa8`, `0x10`, `0x28`, and `0x58`, relative to
the table base. These select targets `0x42516548` (length 0), `0x425164b0`
(length 1), `0x425164c8` (length 2), and `0x425164f8` (length 3). The target
addresses overlap data in IDA. I decoded the original bytes read-only with
`get_original_bytes_at`; the database analysis was not changed. The branches
show that:

- Length 0 returns failure without appending an extension.
- Length 1 rejects `/` and the bare `~`; other paths continue to the shared
  tilde check and append path.
- Length 2 rejects an ASCII drive designator (`[A-Za-z]:`) and the doubled
  backslash root (`\\`). A tilde-prefixed path without a slash also fails in
  the shared tilde check.
- Length 3 rejects an ASCII drive root (`[A-Za-z]:/`). A tilde-prefixed path
  continues only if it contains a slash; other paths reach the shared append
  path.

The shared tilde check rejects `~` and `~user` when the path has no slash, and
accepts tilde-prefixed paths once a slash is present. The path and extension
validation occurs before this dispatch.

## Source-versus-binary fidelity notes

The generic NSString methods are a reference for intended path semantics, but
several observable details differ from the decompiled subclass:

- The source `stringByStandardizingPath` removes `.` and `..` through path
  components. The binary helper may first resolve symlinks when an absolute
  path contains a `..` component, then performs its own component reduction.
  Reusing the source method would miss filesystem-dependent results.
- For a path longer than three characters, `_NSAppendPathExtension` accepts an
  empty extension length and reaches its dot append, whereas the checked-in
  generic NSString method returns self for an empty extension. The short-path
  branch rejects empty input, root and drive-root paths, and bare tilde-user
  paths as recorded above. These cases need explicit coverage in any
  implementation design.
- The binary tilde expansion, standardization, and symlink methods pass a
  1024-character workspace to their helpers. Their pseudocode copies at most
  1024 source characters but retains the original length variable for later
  calls. For inputs over that limit, the decompiler output suggests a potential
  out-of-bounds read when constructing the result. This initial caution is
  superseded by the NSPathStore2 parity correction below, which confirms the
  fixed workspace and original-length flow in both target binaries. The generic
  NSString methods retain their distinct capped-length behavior.
- `pathWithComponents:` in the binary builds into a fixed 1026-character
  buffer and logs failed appends; the source class method builds dynamically.
  The source also skips components that the generic append helper rejects.

These differences mean the class should not simply forward each override to
the matching NSString category method. The primitive storage and comparison
methods can be independent, while path methods need direct helper-backed
implementations or carefully factored equivalents with their capacity and
filesystem behavior preserved.

## String implementation dependencies

`NSSimpleString.m` now implements `NSInlineUnicodeString` and both
`_NSNewInlineUnicodeString` / `_NSNewInlineUnicodeStringFromString` factories.
`NSPathStore2` is a distinct variable-length NSString subclass, with its own
packed length/refcount word and path-specific normalization; it must not be
treated as an alias for the inline Unicode string class. Its factory can
allocate the class directly through `NSAllocateObject`, as the binary does.

## Source helper availability audit

The current Foundation source already provides `_NSConvertToASCIIorUnicode2`
in `NSCharConversion.m`, `NSAllocateObject`, and the zone allocation APIs.
However, a source-wide search finds no implementations or declarations for the
low-level path helper family called by `NSPathStore2` (`_NSAppendPathComponent`,
`_NSAppendPathExtension`, `_NSStandardizePath`, `_NSResolveSymlinksInPath`,
and the query, tilde, slash, and component helpers). It also finds no
`NSHashCharacters` or `NSCompareCharacters` implementation. These binary
dependencies cannot be linked by adding only the Objective-C class methods.

`NSPathUtilities.m`'s existing NSString category has local higher-level helpers
with different names and dispatches through NSString operations. It can serve
as a behavioral reference, but it does not supply the missing low-level ABI
functions and its edge cases differ as listed above. A source implementation
of the full `NSPathStore2` class therefore needs to provide equivalent local
helpers (or direct method logic) alongside the class, while using the existing
character converter and Foundation allocation APIs.

## Rechecked factory and bounded-buffer paths

Re-decompiled the factories and workspace methods in the same IDA database.
`pathStoreWithCString:` counts the source bytes, obtains the default C-string
encoding, and passes both to `_NSConvertToASCIIorUnicode2`. Conversion failure
returns nil. On success, it allocates inline capacity from twice the original
byte count, raises if the converter's exception flag is set, copies any
converted buffer into inline storage, frees that temporary buffer when its
ownership flag is set, strips trailing path slashes, and packs the final
converted length with the existing retain-count bits.

`pathWithComponents:` first obtains each component and its length, then builds
the result using a fixed 1026-character path buffer. It normalizes and strips
slashes when the accumulated path plus the next component exceeds 1018 code
units; if `_NSAppendPathComponent` still rejects the append, it logs the
component and current path and continues. The maximum component length also
determines a separate temporary stack allocation used for `getCharacters:`.
The decompilation also shows two `alloca(4 * componentCount)` tables for the
component objects and lengths, plus that longest-component buffer. These
stack allocations scale with the input array and component lengths, so a
faithful implementation should preserve the order of collection and append
operations without copying the reference's unbounded stack-allocation risk.

The three workspace methods copy `min(pathLength, 1024)` UTF-16 units into a
2048-byte stack buffer but initialize the helper length with the full source
length. Standardization expands tilde and standardizes; symlink resolution
expands tilde, resolves links, then standardizes; tilde expansion calls only
the expansion helper. Each passes the helper-updated length to
`pathStoreWithCharacters:length:`. This confirms the long-input truncation
hazard is in the reference pseudocode's call sequence; an implementation must
not read beyond the copied stack region while attempting to mimic it.

Instruction-level review of `0x4253108c`, `0x42532b10`, and `0x425810d8`
confirms this is not a decompiler variable-recovery artifact: each method stores
the full packed length in its local length slot, caps only the `memmove` count
at `0x400`, passes that same length slot to its helper, then passes the possibly
updated slot to `pathStoreWithCharacters:length:`. The target can therefore
hand a length larger than the copied stack buffer to the factory when the
helper leaves it unchanged. The same sequence is present in
`stringByAbbreviatingWithTildeInPath` (`0x4254683c`): it caps the copy at
`0x400`, passes the original length pointer to `_NSAbbreviatePathWithTilde`,
and passes the resulting length and stack buffer to the factory. This is a
reference bug; a reconstruction should keep the observable path operation
while using storage large enough for the length it passes onward.

The `_NSAbbreviatePathWithTilde` helper (`0x42542c6c`) adds a second long-input
hazard. It compares the path against `NSHomeDirectory()` and, when the prefix
matches and the next character is `/`, calls `memmove` with `2 * (*length -
homeLength)` bytes. The helper receives no workspace-capacity argument. Thus an
over-limit path copied into the method's 1024-unit stack buffer can make the
helper read and write beyond that buffer before the result factory is reached.
A safe reconstruction needs a workspace sized for the full path before calling
this helper; merely bounding the factory copy would not be sufficient.

The other helpers also receive the unbounded length value. `_NSExpandTildeInPath`
scans to the first slash using `*length` and may move the full suffix; its
`capacity` parameter only guards the replacement-size calculation. It is safe
for a long non-tilde path because it returns without scanning, but long tilde
paths can read beyond the truncated caller buffer. `_NSStandardizePath` indexes
the source according to `*length` while trimming and reducing components. Its
`_NSResolveSymlinksInPath` branch copies at most 1024 units into a local buffer,
then passes the original length to `_convertToFileSystemRepresentation`, which
uses that length while converting. These are additional read hazards before
the final factory call. The caller should provide full-length storage to each
helper; the helper capacity remains a separate bound on output growth.

## Symlink resolver fallback recheck (2026-10-06)

Re-decompiled `_NSResolveSymlinksInPath` in both the i386 and PPC databases
(`0x42531c4c` and `0x4252e0b0`). Both walk path prefixes with `lstat`, stop on
the first failed lookup or symlink, and call `realpath` after that stop. They
return without `realpath` only when the complete path exists and no component
is a symlink. `NSPathStoreResolveSymlinks` now follows this fallback control
flow while retaining the existing filesystem-representation capacity check
and bounded UTF-16 result conversion.

## Primitive-selector decompilation recheck

Re-decompiled the fixed-storage and path-query methods for the design review:

- `pathStoreWithCharacters:length:` allocates `2 * inputLength` extra bytes,
  copies all input code units, lets `_NSStripTrailingPathSlashes` adjust the
  local length, then stores `(adjustedLength << 20) | (oldWord & 0xFFFFF)`.
  There is no explicit length clamp in this method; the packed public length
  therefore retains only the upper 12 bits. The factory autoreleases the new
  object. Its zero-length path skips both the copy and slash helper.
- `pathStoreWithCString:` allocates extra storage from the original C byte
  length, but packs the converter's output code-unit length after any temporary
  conversion buffer has been copied and freed. It raises on the converter's
  first status byte before copying output. This is distinct from the character
  factory's direct input-length packing.
- `getCharacters:range:` implements its range check as
  `range.location + range.length > publicLength`; thus an empty range at the
  end is accepted and copied ranges use exactly twice the requested code-unit
  count. `characterAtIndex:` raises when `index >= publicLength`.

- `length` reads `_lengthAndRefCount >> 20`. `characterAtIndex:` raises when
  the index is greater than or equal to that length. `getCharacters:range:`
  raises when `location + length` exceeds the string length, skips the copy for
  an empty range, and otherwise copies exactly `2 * range.length` bytes. An
  empty range at the end is accepted.
- `retain` and `release` update the packed low 20 bits while holding
  `_NSGlobalRetainLock` when present. `retain` saturates at `0xFFFFF`; `release`
  leaves that saturated value unchanged and delegates to `-[NSObject dealloc]`
  when releasing a zero count. Allocation statistics are recorded after the
  retain update and before the release lock, respectively. `retainCount` is the
  low bits plus one, and `copyWithZone:` calls `retain` regardless of zone.
- `isEqualToString:` handles identity and nil first. For an object whose `isa`
  is exactly `NSPathStore2`, it compares the inline characters directly. Other
  strings are read through `length` and `getCharacters:range:` into a 2080-byte
  local buffer when their length is at most `0x410`; longer strings use a zone
  allocation that is freed after `_NSCompareCharacters` returns. The comparison
  helper receives mode zero in both branches.
- `pathExtension` returns the empty string if `_NSStartOfPathExtension` returns
  zero or less; otherwise it asks `NSString` for the substring following the
  dot. `lastPathComponent` returns the receiver when its helper result is zero
  or less and makes a path-store copy of the suffix otherwise. Both deletion
  methods always pass the helper-computed length to the path-store factory.
- `isAbsolutePath` and `pathComponents` are direct wrappers over their helpers.
  `hash` delegates to `_NSHashCharacters`.

These observations came from the decompiled bodies at `0x42507a1c`,
`0x4250dd78`, `0x4250e44c`, `0x425119f4`, `0x4251a2a8`, `0x425220c8`,
`0x42524a90`, `0x4252aba4`, `0x4252f2b0`, `0x4253005c`, `0x42530664`,
`0x425331fc`, `0x42536b08`, `0x4254683c`, `0x42548014`, and `0x425499f0`.

## Conversion-buffer contract rechecked in IDA

The decompiled `_NSConvertToASCIIorUnicode2` confirms the output layout used
by `+[NSPathStore2 pathStoreWithCString:]`: the first bytes are `isCString`
and `allocated`, followed by the C-string pointer, UTF-16 pointer, converted
length, and inline storage beginning at offset 16. The conversion buffer has
1008 inline bytes. C-string conversions allocate above 1008 bytes; UTF-16
conversions allocate above 504 code units. The factory raises if `isCString`
is set, then copies the UTF-16 pointer and converted length into the path
store's inline tail and frees the converter buffer when `allocated` is set.

The converter initializes its result fields before branching. Unsupported
encodings return failure with cleared result fields. Malformed UTF-8 also
returns failure and frees its allocated conversion buffer first. Other
encoding branches include UTF-16 byte-order marks, non-lossy ASCII escapes,
single-byte tables, and the proprietary converter. The worktree's
`NSCharConversionBuffer` declaration and thresholds match this IDA layout;
the path-store factory can reuse that ABI directly instead of duplicating a
second conversion structure.

## Character hash and comparison helper recheck

IDA decompilation confirms `_NSHashCharacters` at `0x42501d4c` starts the hash
with the UTF-16 length. For lengths through 16 it folds every code unit using
`hash = hash + (hash << 8) + character`. For longer strings it folds the first
eight and last eight code units, then returns `hash + (hash << (length & 31))`.
This is the same algorithm already present in `NSString.m` and
`NSSimpleString.m`, so `NSPathStore2 -hash` can share that behavior without
adding a new exported symbol.

`_NSCompareCharacters` at `0x4250befc` compares the common prefix as unsigned
UTF-16 code units and returns `-1` or `1` at the first differing unit. Its
mode bit 0 folds only ASCII lowercase `a` through `z` to uppercase before each
comparison; mode zero performs exact code-unit comparison. If the common prefix
matches, it returns the sign of the length comparison. `NSPathStore2
-isEqualToString:` calls it with mode zero. This is small enough to implement
as a file-local helper alongside the class, avoiding a new external helper
surface.

These findings were rechecked against the source hash loops at
`NSSimpleString.m:307` and `NSString.m:1077`. No source implementation, test,
or build was added or run for this helper analysis.

## Source ownership check

The current ABI manifest assigns `NSPathStore2` to `NSPathUtilities.m`, and
`PB.project` already lists that source file. Keeping the class and its helpers
in `NSPathUtilities.m` therefore matches the current module ownership without
requiring a build-project entry or ABI module reassignment.

An exact owner comparison against `NSPathUtilities.json` confirms all 24
`NSPathStore2` selectors are absent from source. The same audit finds both
`NSArrayPathExtensions` selectors implemented and identifies two separate
missing `NSString` category selectors: `stringByConvertingPathToURL` and
`stringByConvertingURLToPath`. Those URL-conversion methods are outside this
class slice.

## Source owner correction (2026-10-03)

Current source inspection found that the 16 implemented NSString path methods
were inside an unterminated plain `@implementation NSString` block rather than
the ABI-owned `NSString(NSPathUtilities)` category. The unfinished
`stringByAddingPercentEscapes` declaration in that block had no body; its
implementation remains in `NSString(NSURLPathUtilities)`. The path methods now
belong to `NSString(NSPathUtilities)`, including the two URL conversion methods
that were already implemented in a second block of that category. The two
NSArray path extension methods now belong to
`NSArray(NSArrayPathExtensions)`.

The exact-owner audit for `NSPathUtilities.json` now reports only the 24
`NSPathStore2` selectors missing, with zero duplicate owners. The global
Foundation inventory is 294 missing selectors, down from 313. `git diff
--check` is clean; no tests or builds were run.

## Inline storage primitives and factories (2026-10-03)

`NSPathUtilities.m` now defines `NSPathStore2` with its single packed
`_lengthAndRefCount` word and inline UTF-16 access at the ABI-confirmed offset.
The initial implementation slice adds both path-store factories, length and
character access, range copying, equality, hash, retain/release/retainCount,
and retained-self `copyWithZone:`. It preserves the reference's 12-bit packed
length, 20-bit retain count, saturating internal refcount, and 0x410-character
comparison stack threshold. The factories copy into variable-sized object
storage, strip trailing `/` while preserving `/` and `C:/`, and use the existing
character conversion routine for C strings.

The focused exact-owner audit now reports 11 of 24 NSPathStore2 selectors
implemented, 13 missing, and no duplicates. `git diff --check` is clean. No
tests or builds were run. The remaining path transforms and `pathWithComponents:`
are still unimplemented; their low-level helpers are not present in this source.

## Remaining NSPathStore2 selectors (2026-10-03)

The source now owns all 24 selectors in the `NSPathUtilities.json` NSPathStore2
record. Added the IDA-derived path queries and transformations: path component
and extension extraction/appending/deletion, absolute-path checks, component
splitting/construction, tilde expansion/abbreviation, standardization, and
symlink resolution. Local UTF-16 helpers reproduce the observed drive-root,
UNC-prefix, separator-collapse, append-capacity, and `/private/` path rules.

At the time of the initial implementation, workspace buffers for tilde
expansion, standardization, and symlink resolution were sized for the full
input (with a 1024-unit minimum). That implementation choice was later found to
diverge from the reference and was corrected below. The standardizer uses a
component reduction implementation based on the IDA helper branches;
filesystem-dependent symlink canonicalization is applied when an absolute
`..` path crosses a symbolic link. This is source reconstruction, not runtime
equivalence proof.

The NSPathStore2 exact-owner audit reports 24 expected selectors, 0 missing,
and 0 duplicate owners. `git diff --check` is clean. Tests and builds were not
run.

Full `NSPathUtilities.json` exact-owner audit after this change: 45 expected
class/category selectors, 0 missing, 0 duplicates. `git diff --check` remains
clean. No runtime tests or builds were run.

## NSPathStore2 fixed-workspace parity correction (2026-10-06)

The prior full-input workspace was safer but diverged from both target binaries.
IDA confirms that `-[NSPathStore2 stringByExpandingTildeInPath]`,
`stringByAbbreviatingWithTildeInPath`, `stringByStandardizingPath`, and
`stringByResolvingSymlinksInPath` each copy at most 1,024 UTF-16 units into a
fixed stack workspace while preserving the original length variable for helper
calls and the result factory. The i386 bodies are at `0x425810d8`,
`0x4254683c`, `0x4253108c`, and `0x42532b10`; PPC confirms the same behavior at
`0x425966a8`, `0x42596628`, `0x42535e10`, and `0x425315f4`. `NSPathUtilities.m`
now follows that sequence instead of allocating and copying the full input.
This restores the target's long-path behavior, including its read-past-copy
edge case. The generic `NSString` methods retain their separate capped-input
flow. Source/IDA sequence audit and whitespace check only; no tests or builds
were run.

## `_NSStandardizePath` symlink scratch parity correction (2026-10-06)

The i386 body at `0x425179bc` and PPC body at `0x425296ac` both keep a 2,048-byte
stack workspace, copy `min(inputLength, 1024)` UTF-16 units into it, preserve
the original length for `_NSResolveSymlinksInPath`, and pass capacity 1,024.
`NSPathUtilities.m` previously allocated a full-length heap buffer for this
internal symlink pass. It now uses the fixed 1,024-unit stack buffer and keeps
the original length, restoring the target's long-path read-past-copy behavior.
The resolver's post-`realpath` conversion also matches both targets: it
reports success after the filesystem path resolves, sets output length to zero
if conversion fails, and truncates converted UTF-16 to the requested capacity
before copying. Static source/IDA sequence and whitespace checks only; no
tests or builds were run.
