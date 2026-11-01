# Foundation C-symbol coverage follow-up

## Current paired coverage snapshot (2026-10-08)

Re-ran the static C-export audit against the current `symbols.json` and
reference images. Both i386 (`Foundation-i386-thin`) and PPC report zero
unclaimed exported text functions.

Re-ran `selector_check.py` for both target images. Neither target has missing,
renamed, or duplicate selectors. The raw source parser reports 151 extra
definitions for i386 and 7 for PPC because it scans source text without
evaluating architecture preprocessor guards. Spot checks confirmed opposite-
architecture definitions among the extras, including PPC-only coder methods
and i386-only `NSPathStore2`/`NSTask` methods. Treat these raw extra totals as
review leads, not target-specific ABI mismatches; a target-aware selector pass
is needed before drawing conclusions from them.

These are source/metadata inventory checks only; no tests or builds were run.

Reference: Foundation i386 IDA database `d12fe2f23883` and the generated ABI
manifests under `src/Kits/Foundation/reconstruction/abi/`.

## `NSAttributedString` empty value

IDA names the helper at `0x4259435c` `_emptyAttributedString`. Its pseudocode
caches one result, obtains an `NSConcreteAttributedString` with
`+[NSAttributedString allocWithZone:]` using a null zone, sends `init`, stores
the returned object, and returns it. The selector slot is shared with
initializer call sites; in `-[NSConditionLock initWithCondition:]` and
`-[NSConcreteMutableCharacterSet _initWithSet:]`, it is sent to the newly
allocated receiver before further initialization, corroborating `init`.

IDA decompiles `-[NSMutableAttributedString deleteCharactersInRange:]` at
`0x4258ae18` as a call to `_emptyAttributedString`, followed by
`replaceCharactersInRange:withAttributedString:`. The source now exports the
cached helper and uses that same replacement path.

## `NSConnection` hash-table callbacks

The ABI manifest lists `_hashConnection` and `_isEqualConnection` as C text
symbols. IDA decompiles `_hashConnection` at `0x42526c20` to the sum of the
receive-port and send-port pointer fields (offsets 4 and 8). At `0x42528fe0`,
`_isEqualConnection` compares those two fields for pointer equality. The
existing callbacks already had those operations; they were file-local and
had reconstruction-specific names. They are now global `hashConnection` and
`isEqualConnection` definitions, matching the Mach-O symbol names, and remain
the callbacks used to initialize the connection table.

The source-map ABI audit now finds all three previously missing C symbols.
This is a source-name/definition audit only; no tests or builds were run.

## Character conversion ownership follow-up (2026-10-04)

`NSUTF8ToUnicode` at `0x4254137c` is an external text symbol in the existing
`NSCharConversion` ABI manifest, but its source definition was file-local.
Its source linkage is now external, and both C exports in
`NSCharConversion.m` are assigned in `symbols.json`.

`NSMacOSRomanToPrecompUnicode` at `0x42591650` is an external text symbol
whose source body maps bytes below `0x80` directly and higher bytes through
the Mac OS Roman table. Its existing source implementation matches that
behavior; the missing text-symbol ABI and module ownership entries are now
recorded. The Foundation symbol audit decreased from 204 to 201 unclaimed
exports. JSON parsing and `git diff --check` passed; no tests or builds were
run.

IDA also confirms `__NSIndentSpace` at `0x42540044` recursively grows the
cached indentation array by one indentation step, matching the existing global
`_NSIndentSpace` implementation. Its missing `NSDictionary` text-symbol ABI
entry and source ownership are now recorded.

`__NSIsPList` at `0x42514670` also matches the existing `_NSIsPList` source
implementation: it returns type codes for scalar, data, array, and dictionary
property-list values and recurses into containers only when requested. Its
`NSUserDefaults` text-symbol ABI entry and module ownership are now recorded.
The symbol audit now reports 199 unclaimed exports.

`__NSFoundationBundle` at `0x425460ec` confirms the cached Foundation bundle
lookup in `NSBundle.m`, including the main-bundle fallback to the framework
path and retain. Its `NSBundle` text-symbol ABI entry and module ownership are
now recorded.

## Run-loop receive timeout follow-up (2026-10-04)

IDA identifies `_NSCheapPortSetAcceptInput` at `0x4251829c` as an exported
function. It treats its third argument as a relative interval and passes that
interval in milliseconds to `msg_receive`. Its finite-timeout caller supplies
`beforeTime - _NSCurrentTime()`, so the source helper's additional subtraction
of the current time caused finite waits to collapse to zero. The helper now
converts the supplied interval directly and is externally linked. Its
`NSRunLoop` text-symbol ABI entry and source ownership are recorded.

## NSValue constructor export follow-up (2026-10-04)

IDA identifies `__NSNewValue` at `0x4251ec18` as the shared concrete-value
constructor. It retrieves or creates cached type information, obtains size
and alignment through `NSGetSizeAndAlignment`, allocates `NSConcreteValue`
with the requested zone and extra byte count, initializes it, stores the type
info pointer, and copies the value bytes immediately after the class instance
storage. The existing source helper follows this path and was only file-local;
it is now externally linked with its `NSValue` ABI and symbol ownership
recorded.

## Unicode encoder callback exports (2026-10-04)

The Foundation symbol audit lists fifteen `NSUnicodeTo…` encoder callbacks as
unclaimed exports. IDA has matching named functions at `0x4259221c`,
`0x42592400`, `0x425924fc`, `0x425925c8`, `0x4259269c`, `0x425927c4`,
`0x42507948`, `0x42592898`, `0x42592bf0`, `0x42592c28`, `0x42592c50`,
`0x42592ee0`, `0x42592fb4`, `0x42593088`, and `0x4259315c`. Their source
counterparts already exist in `NSStringEncodings.m` as conversion callbacks;
IDA spot checks of ASCII, ISO Latin-1, NEXTSTEP, and UTF-8 confirm the shared
reader state and callback contract. Their linkage is now external, and all
fifteen symbols are recorded in the module ABI manifest and ownership map.
No conversion logic changed.

## Notification suspension flag helper export (2026-10-04)

IDA identifies `_NSNotificationSuspensionBehaviorFromFlags` at
`0x4254c6a8` as returning its argument masked by `7`. The existing source
helper performs the same mask and was file-local. It is now externally linked
with its `NSNotification` text-symbol ABI and ownership entry recorded.

## Notification suspension comparison helper export (2026-10-04)

IDA identifies `_NSHigherNotificationSuspensionBehavior` at `0x4254c6b8` as
returning the larger of its two unsigned arguments. The existing notification
source had the same comparison under a file-local helper name. It now uses the
reference symbol name with external linkage, and the `NSNotification` ABI and
ownership manifests include the export.

## Distributed notification flag decoder exports (2026-10-04)

IDA confirms `_NSNotificationDeliveryBehaviorFromFlags` at `0x4256f8cc`
returns its byte argument masked by `7`, and
`_NSNotificationSuspendActionFromFlags` at `0x4256f8ec` masks by `1`.
Both decoders are now implemented beside the matching flag encoders in
`NSDistributedNotificationCenter.m`, with ABI and symbol ownership entries.

## Simple dictionary and set primitive reconstruction (2026-10-04)

IDA confirmed the standalone `NSSimpleHashing` API family uses 12-byte table
headers followed by 12-byte dictionary buckets or 8-byte set buckets. The
header stores count/capacity, a simple retain count, and an equality callback;
callbacks receive a context plus stored and queried values. Small-capacity
levels use packed buckets, larger levels use open addressing with tombstones
and the reference's secondary-hash probe sequence. The target exports creation,
copy, free, reset, count, bucket count, bucket access, lookup, insert, delete,
counted-value updates, and dictionary value deletion operations.

A new `NSSimpleHashing.m` implements the IDA-confirmed create/copy/free/reset,
lookup/accessor, insert/delete, resize, and counted-value paths. Its 23 covered
exports are listed in the module ABI and ownership manifests, and the new source
is included in the Foundation source list. The separate retain/release entry
points were outside the initial implementation slice. No tests or builds were
run.

IDA's `NSSimpleDictionaryDeleteEntriesWithValue` pseudocode confirms its unusual
return contract: an initially empty table returns itself; a nonempty table
returns `_NSHashTableCapacities2` unless shrinking triggers a resize, in which
case it returns and installs the resized table. This remains true when the
deletion removes every entry. The source now matches these branches exactly.

IDA confirms the remaining dictionary/set reference-count functions share the
optional `_NSSimpleHashingLock`, initialized by `__NSToDoAtFirstThreadStart`
and released/reset by `__NSToDoAtLastThreadExit`. Retain increments unless the
stored count is `UINT_MAX`, returning true only for that saturated case.
Release decrements a nonzero, non-`UINT_MAX` count; it returns true when the
stored count was already zero. The two retain-count accessors return the stored
count plus one. This analysis is recorded for the next implementation slice;
the source and manifests have not yet been changed for these six exports.

### Retain/release source reconciliation (2026-10-08)

The current `NSSimpleHashing.m` now defines all six functions and the shared
ABI and symbol assignment already list them. Re-read i386 IDA at
`0x4256328c`, `0x42563194`, `0x4256359c`, `0x425632f8`, `0x42563204`, and
`0x425635ac`, and PPC IDA at `0x4256d7cc`, `0x4256d5c8`, `0x4256dc60`,
`0x4256d88c`, `0x4256d694`, and `0x4256dc74`. Both targets match the source:
retain saturates and reports whether it was already saturated; release leaves
the saturated count unchanged and reports whether it was already zero; each
retain-count accessor returns the stored count plus one. i386 conditionally
uses `_NSSimpleHashingLock`; PPC conditionally uses the exported spin word
`___NSSimpleHashingRetainLock` while `_NSIsMultiThreaded` is set. The stale
"not yet changed" status above describes the earlier audit only; these methods
are implemented and recorded now. No behavior change, tests, or builds were
needed for this reconciliation.

## C-string hash export (2026-10-04)

IDA identifies `_NSHashCString` at `0x425011f0`. `-[NSSimpleCString hash]`
and `-[NSInlineCString hash]` both call it. Its length-seeded hash, first/last
eight-byte sampling for inputs longer than 16 bytes, high-byte conversion via
`_NSCStringCharToUnichar`, and final shift match the existing helper in
`NSSimpleCString.m`. That helper is now externally linked as `NSHashCString`,
and the `_NSHashCString` module ABI and symbol ownership entries are recorded.
No hash behavior changed. Targeted manifest/definition checks and the symbol
audit passed; the audit reports 153 unclaimed exports. No tests or builds were
run.

IDA identifies `_NSCompareCString` at `0x42517338`; `-[NSSimpleCString
compare:options:range:]` and `-[NSInlineCString compare:options:range:]` call it.
Its byte comparison, high-byte conversion through `_NSCStringCharToUnichar`,
ASCII-only case folding for option bit 0, and length tie-break match the existing
`NSCompareCStringBytes` helper. The helper is now externally linked as
`NSCompareCString`, with its module ABI and ownership entries recorded. No
comparison logic changed. Targeted definition/manifest checks and `git diff
--check` passed; the symbol audit reports 152 unclaimed exports. No tests or
builds were run.

### `_NSFastFuncList` source-owner confirmation (2026-10-07)

Rechecked the live table bytes in both IDA databases. i386 `_NSFastFuncList` at
`0x42602480` contains `_encodeFastByte`, `_encodeFastInt`,
`_encodeFastCharStar`, and `_encodeFastData` in that order; PPC's table at
`0x426263ac` contains the same four function pointers in the same order.
`NSPortCoder.m` defines the corresponding table as
`NSPortCoderEncodeFastByte`, `NSPortCoderEncodeFastInt`,
`NSPortCoderEncodeFastCString`, and `NSPortCoderEncodeFastData`, and current
ABI, symbol, and ownership records assign `_NSFastFuncList` to that module.
This confirms the later source assignment and supersedes the earlier inventory
entry that left the table's source owner unresolved. No source or ABI changes
were needed in this recheck; no tests or builds were run.

## Unicode and generic string hash exports (2026-10-04)

IDA confirms `_NSHashCharacters` at `0x42501d4c` is called by both
`-[NSSimpleString hash]` and `-[NSInlineUnicodeString hash]`; its length seed,
first/last eight-character sampling for strings longer than 16 characters, and
final length-based shift match the shared local helper and inline hash body.
That logic now lives in externally linked `NSHashCharacters`.

IDA confirms `_NSHashString` at `0x42538a50` is called by `-[NSString hash]`.
Its length query, 16-character stack buffer, `getCharacters:range:` calls,
sampling loops, and final shift match the existing method body, now factored
into externally linked `NSHashString`. The module ABI and ownership entries for
both functions are recorded. Static definition/manifest checks passed, and the
symbol audit reports 150 unclaimed exports. No tests or builds were run.

## Unicode string comparison export (2026-10-04)

IDA identifies `_NSCompareCharacters` at `0x4250befc`; it is used by
`-[NSSimpleString compare:options:range:]` and the generic locale comparison
path. The existing simple-string comparator matches its common-prefix scan,
ASCII-only uppercasing when option bit 0 is set, and length tie-break. It is
now externally linked as `NSCompareCharacters`, used by the existing simple
string comparison paths, and recorded in the `NSSimpleString` ABI and
ownership manifests. Static source/manifest checks and `git diff --check`
passed; the symbol audit reports 149 unclaimed exports. No tests or builds were
run.

## Notification no-interest export (2026-10-04)

IDA identifies `_NSNotificationSuspensionBehaviorNoInterest` at `0x4254c69c`
as an exported function returning zero; the notification center calls it while
naming suspension behavior. The source now defines the same function and lists
it in the `NSNotification` ABI and symbol ownership manifests. Static
manifest checks and `git diff --check` passed; the export audit reports 148
unclaimed functions. No tests or builds were run.

## Autorelease-pool count exports (2026-10-04)

IDA confirms `_NSAutoreleasePoolCount` and `_NSTopAutoreleasePoolCount` are the
count paths used by `+[NSAutoreleasePool autoreleasedObjectCount]` and
`+[NSAutoreleasePool topAutoreleasePoolCount]`. The source now exposes both
functions and routes the class methods through them. They report counts from
the reconstruction's existing process-global pool stack; the target's
per-thread storage remains a separate fidelity limitation. ABI/ownership checks
and `git diff --check` passed; the symbol audit reports 146 unclaimed exports.
No tests or builds were run.

### Allocation-event sender dependency recheck (2026-10-05)

The current `NSThread.m` already allocates `__NSDebugRecordLock` in
`_NSToDoAtFirstThreadStart` and frees it in `_NSToDoAtLastThreadExit`, matching
the target sender's optional `mutex_try_lock` / `mutex_wait_lock` and release
of the lock word on exit. The earlier statement that sender work still needed
the lock lifecycle is stale for the current source. The unresolved data-model
difference is `NSAutoreleasePoolCountForObject`: the target walks the current
thread's paged pool list through `_NSCurrentThread()->autoreleasePool`, while
`NSAutoreleasePool.m` counts a process-global array of pool frames. A bounded
sender implementation can reuse that existing count helper only by accepting
and documenting the multi-threaded negative-retain divergence; reconstructing
per-thread pool storage remains a separate pool-system change.

## Per-object autorelease count export (2026-10-04)

IDA confirms `_NSAutoreleasePoolCountForObject` at `0x425751bc` walks every
active autorelease page and counts pointer-identity matches. The reconstruction
stores active autoreleases in frame arrays, so the new export scans each
current frame's object entries and counts identical pointers. The function is
recorded in the `NSAutoreleasePool` ABI and ownership manifests. Static
manifest/body checks and `git diff --check` passed; the symbol audit reports
145 unclaimed exports. No tests or builds were run.

## Autorelease of previously freed objects (2026-10-04)

IDA confirms `__NSPopAutoreleasePool` checks the per-thread freed-object flag
while draining and calls `__NSHasBeenFreed` before releasing each object.
`__NSHasBeenFreed` checks only whether `isa` equals the runtime freed-object
class; it does not include zombie subclasses, unlike the public
`NSIsFreedObject` predicate. When a match is found, the drain calls
`__NSAutoreleaseFreedObject`, whose diagnostic identifies the object and says
the release was ignored. The reconstruction now mirrors those branches using
its existing global pool stack and a process-global option flag. Its simplified
one-string `_NSBasicStdErrLog` preserves the diagnostic text, but does not
reproduce the reference logger's process-information prefix. The C symbol is
recorded in the autorelease-pool ABI and ownership manifests. Targeted static
checks and `git diff --check` passed; the symbol audit reports 143 unclaimed
exports. No tests or builds were run.

## Simple-set reference counting (2026-10-04)

IDA confirms `_NSRetainSimpleSet` and `_NSReleaseSimpleSet` protect the set's
stored retain count with the optional `_NSSimpleHashingLock`. Retain increments
unless the count is `UINT_MAX`, returning true only when already saturated.
Release decrements a nonzero, nonsaturated count and returns true only if the
count was already zero. `_NSSimpleSetRetainCount` returns the stored count plus
one without taking the lock. These three set-side exports now match those
branches. `NSThread.m` creates `_NSSimpleHashingLock` during
`__NSToDoAtFirstThreadStart`, as IDA confirms. The reconstruction does not yet
implement `__NSToDoAtLastThreadExit`, so it does not release and clear this lock
when the last thread exits; dictionary retain/release exports remain outside
this approved set slice. ABI/source ownership checks and `git diff --check`
passed; the symbol audit reports 140 unclaimed exports. No tests or builds were
run.

### Thread-exit hashing-lock cleanup recheck (2026-10-07)

The source now defines `_NSToDoAtLastThreadExit` in `NSThread.m`. The i386
body at `0x42571898` releases and clears `_NSSimpleHashingLock` after the
global-retain lock; the PPC body at `0x4257fdfc` has no corresponding lock
operation. The source's `!__ppc__` guard around both first-thread creation and
last-thread cleanup matches that difference. In both targets the function
calls `+[NSRunLoop _taskNowSingleThreaded]` first and then releases/clears the
remaining object locks and frees/clears the i386 raw mutexes in target order.
The older statement above that the cleanup is not implemented describes the
earlier reconstruction state and is now resolved. No code or ABI changes were
needed in this recheck; no tests or builds were run.

The dictionary counterparts are confirmed at `_NSReleaseSimpleDictionary`
(`0x42563194`), `_NSRetainSimpleDictionary` (`0x4256328c`), and
`_NSSimpleDictionaryRetainCount` (`0x4256359c`). Their IDA pseudocode has the
same saturated/zero handling and optional `_NSSimpleHashingLock` behavior as
the set functions above. The dictionary counterparts are now implemented in
`NSSimpleHashing.m` with the same lock, saturation, zero, and retain-count
branches. Their source ownership and module ABI claims are recorded. Static
definition/manifest checks only; no tests or builds were run.

## Simple-hashing review follow-up (2026-10-04)

IDA confirms `_NSResetSimpleDictionary` and `_NSResetSimpleSet` initialize
their fallback return value to `_NSHashTableNBuckets2`, represented by the
source's `NSSimpleHashingBucketCounts` array. That fallback was already
correct. The reset loops also update their result on each bucket: the
dictionary helper stores `3 * bucketIndex` when no callback is supplied, and
stores bucket state (or the callback result for an occupied bucket) when a
callback is supplied. The set helper stores bucket state or the callback
result only when a callback is supplied. `NSSimpleHashing.m` now follows those
per-bucket result assignments. `_NSSimpleDictionaryDecrementValue` updates
the caller's key pointer only when the decremented value reaches zero; the
existing source already matches this. `_NSSimpleDictionaryDeleteEntriesWithValue`
intentionally returns `_NSHashTableCapacities2` when a nonempty table does not
resize; that unusual reference behavior also already matches the source.
Targeted source and manifest checks only; no tests or builds were run.

## Autorelease diagnostics follow-up (2026-10-04)

IDA decompiles `__NSAutoreleaseNoPool` at `0x42575450` as an `NSLog` call
using the literal `*** _NSAutoreleaseNoPool(): Object 0x%x of class %s
autoreleased with no pool in place - just leaking\n`. Its only caller is
`_NSAutoreleaseObject` at `0x42503d8c`. When the current thread has no
autorelease data or no active pool, that caller optionally records allocation
statistics and invokes this warning helper instead of silently dropping the
object. IDA decompiles `__NSAutoreleaseHighWaterLog` at `0x42575434` as a call
to the variadic stderr logger with `*** _NSAutoreleaseHighWaterLog(): %d
objects in top autorelease pool\n`; it too is called by `_NSAutoreleaseObject`
after an autorelease is recorded and the configured count/resolution
threshold is met. The current reconstruction has global counters and settings
instead of the target's per-thread AP data. `NSAutoreleaseObject` now calls
`_NSAutoreleaseNoPool` when no pool is active and checks the active object
count after recording an autorelease, logging when the configured high-water
mark/resolution fires. Both C helpers are present in the `NSAutoreleasePool`
ABI and symbol maps. The allocation-statistics event calls in the reference
remain outside this slice. Static definition/trigger/manifest checks and
`git diff --check` passed; the symbol audit reports 136 unclaimed exports. No
tests or builds were run.

## Autorelease-pool printer (2026-10-04)

IDA confirms `_NSPrintAutoreleasePools` at `0x42575214` is called by
`+[NSAutoreleasePool showPools]`. With no active pool it writes `No autorelease
pools.` Otherwise it visits pools from innermost to outermost, prints each
level and object count, then prints that pool's objects in reverse
autorelease order as `0x<address> (<class name>)`. The source now exposes
`NSPrintAutoreleasePools`, routes `showPools` through it, and reproduces those
headers, lines, and traversal order using the reconstruction's flat frame
arrays. Its simplified one-string stderr logger adds each newline and omits
the reference logger's process-information prefix; the helper's integer
return is also reduced to zero because the local logger returns `void`. ABI
and symbol ownership checks plus `git diff --check` passed; the symbol audit
reports 135 unclaimed exports. No tests or builds were run.

## Boolean string conversion exports (2026-10-04)

IDA identifies `_NSBOOLFromString` at `0x4256eca8` and
`_NSStringFromBOOL` at `0x425921dc`. `_NSBOOLFromString` obtains the input
length and compares the string case-insensitively (option bit 0) with `"yes"`
and `"y"`, returning true when either comparison is equal. `_NSStringFromBOOL`
returns the constant `"YES"` for any nonzero argument and `"NO"` otherwise.
The source now defines both functions in `NSString.m`, and the module ABI and
symbol ownership manifests claim both exports. The implementation retains the
observed nil-receiver result: `NSBOOLFromString(nil)` returns true because the
target's message sends return zero and zero is `NSOrderedSame`. Static
source/manifest checks and `git diff --check` passed; the symbol audit reports
138 unclaimed exports. No tests or builds were run.

## UNIX-time helper exports (2026-10-04)

IDA confirms `_NSCurrentUNIXTime` at `0x4251f880` calls `gettimeofday` and
returns `tv_sec`; the source now exposes that wrapper from `NSProcessInfo.m`.
`_NSCurrentFileSystemUNIXTime` at `0x425257c8` converts a path to a filesystem
representation, creates the directory, returns its `st_mtime` when `stat`
succeeds, and removes it. `NSUserDefaults.m` already had the same
create/stat/remove behavior in a file-local helper; the exported wrapper now
uses that implementation. Both ABI/symbol entries are recorded. Static
source/manifest checks and `git diff --check` passed; the symbol audit reports
133 unclaimed exports. No tests or builds were run.

## Integer log2 helper (2026-10-04)

IDA identifies `_NSLog2` at `0x4253dd14`. Its branch tree returns the
zero-based index of the highest set bit for values greater than one, and zero
for values zero and one. `-[HashTable initWithCoder:]` uses it to size the
decoded table; `__NSFastBSearchInt` uses it to choose its search step. The
source now exposes this helper from `NSHashTable.m`, with ABI and symbol
ownership entries. Static definition/manifest checks and `git diff --check`
passed; the symbol audit reports 132 unclaimed exports. No tests or builds were
run.

## Temporary-directory helper (2026-10-04)

IDA identifies `__NSTempDirectory` at `0x425550bc` as copying `"/tmp"` to
its output buffer, including the terminator, and returning 1. Its caller,
`_NSTemporaryDirectory`, uses a 1028-byte stack buffer, creates an
`NSPathStore2` from the C string, and returns its standardized path. The source
now implements the helper in `NSPathUtilities.m` and routes
`NSTemporaryDirectory` through that same path-store flow. ABI and symbol
ownership entries are recorded. Static definition/manifest checks and
`git diff --check` passed; the symbol audit reports 131 unclaimed exports. No
tests or builds were run.

IDA identifies `_NSNeXTRootDirectory` at `0x42555494` as a direct call to
`NSOpenStepRootDirectory` with the return value passed through unchanged. The
compatibility alias is now implemented and declared in `NSPathUtilities.h`;
its ABI and symbol ownership entries are recorded. The export audit reports
130 unclaimed functions. No tests or builds were run.

IDA identifies `_NSOpenStepDirectoryForUser` at `0x425461b8`. It appends
`".OpenStep"` to the user's home directory. If the directory is not
accessible and creation was requested, it creates the directory with the
requested username (or the current username) as owner and mode `0755`; it
returns the path regardless of the create call's result. The implementation
uses the existing accessibility, path, and file-manager helpers and is
declared in `NSPathUtilities.h`. ABI and symbol ownership entries are
recorded. No tests or builds were run.

IDA identifies `NSStandardApplicationPaths` at `0x42584380` and
`NSStandardLibraryPaths` at `0x425843d0`; they return one-element arrays
containing the expanded `~/Applications` and `~/Library` paths. At
`0x42538f44`, `NSSearchPathForDirectoriesInDomains` uses the Libc search-path
enumerator, optionally expands entries beginning with `~`, and returns an
immutable array or the empty array. The three exports now follow those paths in
`NSPathUtilities.m`, with ABI and symbol ownership entries. Static
source/manifest checks and `git diff --check` passed; the export audit reports
126 unclaimed functions. No tests or builds were run.

## Decimal short-integer helpers (2026-10-04)

IDA confirms `_NSIntegerCompare` (`0x425a16b4`), `_NSIntegerCopy`
(`0x425a170c`), `_NSIntegerAddShort` (`0x425a1650`), `_NSIntegerSubShort`
(`0x425a1f9c`), `_NSIntegerMultiplyByShort` (`0x425a1f0c`), and
`_NSIntegerDivideByShort` (`0x425a1b14`) operate on little-endian 16-bit
words. The source now exposes those helpers from `NSDecimal.m`, preserving
the observed capacity checks, output-length trimming, in-place behavior, and
error values. `_NSIntegerSubShort` has no IDA callers; its carry-state update
follows the disassembled instructions. ABI and symbol ownership entries are
recorded. Static source/manifest checks and `git diff --check` passed; the
export audit reports 120 unclaimed functions. No tests or builds were run.

IDA confirms `_NSIntegerAdd` at `0x425a1510` and `_NSIntegerSubtract` at
`0x425a2020` operate on two little-endian word arrays. Addition propagates
carry through both lengths and checks the caller-provided result capacity only
when a final carry remains. Subtraction follows the target's borrow state,
returns overflow when that state clears, and trims leading zero words after a
successful result. `_NSIntegerMaxPowerOf10Multiplier` at `0x425a1bb0` returns
the floored product of `4.81647993` and the unsigned-short length difference;
its first argument is unused. These three helpers are now defined in
`NSDecimal.m` with ABI and symbol ownership entries. Static source/manifest
checks and `git diff --check` passed; the export audit reports 117 unclaimed
functions. No tests or builds were run.

### ISO Latin-2 byte-to-Unicode export (2026-10-04)

IDA at `0x42591620` confirms `_NSISOLatin2ToPrecompUnicode` returns bytes
through `0x9f` unchanged and indexes the `_decomposable` word table for
`0xa0`–`0xff`. The source now contains that 96-word range and exposes the
wrapper in `NSCharConversion.m`; a full word-for-word comparison against IDA
matched all 96 values. The ABI and ownership manifests claim the export. The
static symbol audit reports 76 unclaimed functions. No tests or builds were
run.

### Adobe Standard, NEXTSTEP, and Symbol byte-to-Unicode exports (2026-10-04)

IDA confirms `_NSNEXTSTEPToPrecompUnicode` at `0x425058c0` passes bytes through
through `0x7f` and maps higher bytes with the NEXTSTEP table;
`_NSSymbolToPrecompUnicode` at `0x42592200` indexes the Symbol table for every
byte; and `_NSAdobeStandardToPrecompUnicode` at `0x42590a4c` passes bytes
through through `0x9f` and maps `0xa0`–`0xff` with the Adobe Standard table.
The IDA words match the source arrays entry-for-entry: 128 NEXTSTEP entries,
256 Symbol entries, and 96 Adobe Standard high-byte entries. The source now
exports all three wrappers and claims their Mach-O symbols. The static export
audit reports 77 unclaimed functions. No tests or builds were run.

IDA confirms `_NSIntegerMultiply` at `0x425a1c14` forms a little-endian
word product, allocates a temporary product when the destination aliases the
left operand, trims high zero words, and returns success. `_NSIntegerDivide`
at `0x425a1748` returns divide-by-zero for a zero divisor, zero length when
the dividend is smaller, and delegates one-word divisors to
`_NSIntegerDivideByShort`; the general path normalizes and performs word
division. The reconstruction uses its existing bounded `BigInteger` divider
for that general path, which covers the eight-word `NSDecimal` values and its
internal scaling intermediates. ABI and symbol ownership entries are recorded.
Static source/manifest checks and `git diff --check` passed; the export audit
reports 115 unclaimed functions. No tests or builds were run.

IDA confirms `_NSIntegerMultiplyByPowerOf10` at `0x425a1d70` has signature
`int (unsigned short *destination, unsigned short *destinationLength,
unsigned short *source, unsigned short sourceLength, short power)`. Its callers
are `NSDecimalDivide` (`0x425a0a34`) and `NSDecimalNormalize` (`0x425a0fb0`).
The power table at `0x425bba06` has 39 rows with a stride of nine 16-bit words:
the first eight words encode `10^n` little-endian, and the ninth is the word
length. The separate capacity increment for a 38-digit chunk is 8 words.
Positive powers check destination capacity before multiplying. Negative powers
divide, truncating discarded digits. When the destination differs from the
source, the helper copies first; a zero power then returns success. Its ABI
record and `_NSIntegerMultiplyByPowerOf10` symbol-ownership entry remain
unclaimed.

### `_NSIntegerMultiplyByPowerOf10` execution-loop recheck (2026-10-04)

The instruction-level pass narrows the earlier chunk interpretation. The
positive-power preflight subtracts 38 repeatedly to estimate capacity, adding
the table's eight-word increment for each full chunk and then the remainder
row's length. The execution loop also subtracts 38, but indexes the power table
using the remaining power before it reaches the final operation; the final
multiply or divide then uses the original source pointer and length. The table
contains rows only for powers 0 through 38, so the execution path for a
remaining power above 38 does not match the ordinary “38 plus remainder”
interpretation and may index past the table. The two callers are
`NSDecimalDivide`, which passes 38, and `NSDecimalNormalize`, which can pass an
exponent difference or adjusted difference. Until the reachable range of that
second caller is established, this function is not ready for direct source
implementation; the earlier chunk description should not be treated as a
verified behavior summary.

IDA decompiles the unclaimed `__NSCStringToDecimal` symbol at `0x425a2950`
as a nonstandard i386 usercall returning the destination `NSDecimal *` in
`EAX` and receiving that destination in `EBX`, followed by a C-string and an
optional end-pointer output. It skips ASCII space and bytes 9 through 13,
accepts an optional sign, accumulates integer and fractional digits through
`_NSIntegerMultiplyByShort` and `_NSIntegerAddShort`, then parses an optional
`e`/`E` exponent. It snapshots the decimal before each mantissa digit; when
adding a digit overflows, it restores the snapshot and adjusts the exponent
for dropped integer digits, while dropped fractional digits do not change the
exponent. Exponent overflow sets the decimal's not-a-number flag. On success
it compacts the result and updates the optional end pointer; on the overflow
path the end pointer remains at the initial input address. Its only IDA caller
is `__NSScanDecimalFromString` at `0x425a3020`. `NSScanner.m` currently has a
separate Unicode/locale-aware parser, so it is not an equivalent direct
replacement. No parser source or ABI ownership changes were made.

IDA decompiles the unclaimed `__NSMergeSort` export at `0x4251c878` as a
recursive, stable merge sort over object pointers, using a caller-supplied
comparator and context. Counts 0 and 1 return the input buffer; counts 2 and 3
use direct comparator networks. Larger counts split into floor/ceiling halves
and alternate the source, destination, and scratch buffers. The final merge
preserves left-side order on comparator ties. Its last argument enables an
already-ordered boundary check that can skip the merge copy. IDA lists callers
in `NSArray sortedArrayUsingFunction:context:`, `NSMutableArray
sortUsingFunction:context:`, and `NSArray
sortedArrayUsingFunction:context:hint:`. `NSArray.m` currently implements a
separate static recursive merge sort with an unconditional ordered-boundary
check, but without the target's small-count networks, alternating buffers,
return-pointer behavior, or conditional fast path. No array source or ABI
ownership changes were made.

IDA decompiles `__NSFastBSearchInt` at `0x42570448` as a lower-bound search
over an ascending `unsigned int` array: it returns the first index whose value
is greater than or equal to the key, or `count` when every value is smaller.
Counts through three use explicit comparisons; larger counts seed an unrolled
binary search from `NSLog2(count)` and a power-of-two pivot. The function has
no direct callers in this IDA database. The `NSMethodSignature.m` reconstruction
comment describes this export as the reference cache's lookup routine, but the
available xrefs do not confirm that relationship. No source or ABI ownership
changes were made.

### Implementation status (2026-10-04)

Added `_NSFastBSearchInt` to `NSHashTable.m` as a lower-bound binary search and
claimed its Mach-O symbol `__NSFastBSearchInt` in the `NSHashTable` ABI and
symbol map. The implementation preserves the confirmed return contract; IDA's
unrolled search sequence is represented by the equivalent midpoint loop. The
symbol audit decreased from 96 to 95 unclaimed exports. ABI-manifest,
symbol-map, definition-count, and whitespace checks passed. No tests or builds
were run.

### `__NSMergeSort` caller flags and source delta (2026-10-04 recheck)

The three IDA callers pass the final boundary-check flag differently:
`NSArray -sortedArrayUsingFunction:context:` and
`NSMutableArray -sortUsingFunction:context:` pass `count > 0x3f`, while
`NSArray -sortedArrayUsingFunction:context:hint:` passes `1` after routing
counts at most three through the non-hint method. The two ordinary sort callers
use a 1536-byte stack buffer for up to 128 pointers per region and allocate
`12 * count` bytes above that threshold. The hint path allocates
`16 * count` bytes for its hash-informed order and sort buffers.

The current `NSArrayMergeSort` has stable comparison ordering and an ordered
boundary check, but it always recurses in place and uses only a source/scratch
pair. The target helper alternates source, destination, and alternate buffers;
returns either the input or destination pointer; applies explicit sorting
networks for counts two and three; and skips the ordered-boundary check when
its final flag is zero. A faithful exported helper should preserve that
pointer-return contract and route all three array callers through it, retaining
the caller-specific boundary flags and observed storage sizing.

### `__NSMergeSort` implementation (2026-10-04)

Replaced the private two-buffer sort in `NSArray.m` with the exported
`_NSMergeSort` helper. It handles counts zero through three with the observed
return-pointer behavior and stable comparison network, then alternates the
source, destination, and alternate buffers for larger counts. The ordered
boundary check is controlled by the final flag, and the merge emits the left
item first on ties. The NSArray and NSMutableArray callers now reserve three
pointer regions, pass `count > 0x3f`, and consume the returned sorted pointer;
the hint caller retains its four-region allocation and passes `1`. Added the
`__NSMergeSort` ABI symbol and `_NSMergeSort` ownership record. Static manifest,
source-reference, and whitespace checks passed. No tests or builds were run.

### `__NSCStringToDecimal` call-site ABI recheck (2026-10-04)

The caller disassembly confirms the i386 convention: it loads the destination
`NSDecimal *` into `EBX`, pushes the C-string and end-pointer arguments, calls
the helper, then removes eight stack bytes. A plain cdecl three-argument C
definition would expect the destination on the stack and would not match this
call site. The parser semantics are recoverable, but an exported implementation
needs a verified toolchain-supported way to reproduce this convention (or a
separately justified call-site/source change); no ABI ownership claim should be
added solely from a C prototype.

### Unclaimed path-helper cluster (2026-10-04)

IDA confirms a connected cluster of unclaimed C exports operating on 16-bit
path buffers: `__NSStripTrailingPathSlashes` (`0x42506da0`),
`__NSStartOfPathExtension` (`0x425121e8`),
`__NSStartOfLastPathComponent` (`0x4251a7a0`),
`__NSLengthAfterDeletingLastPathComponent` (`0x4251f6cc`),
`__NSLengthAfterDeletingPathExtension` (`0x42531770`),
`__NSAppendPathComponent` (`0x42514578`), and
`__NSAppendPathExtension` (`0x42516410`). Their callers include both
`NSPathStore2` and `NSString` path methods, so these exports are live framework
paths rather than unused inventory entries.

`NSPathUtilities.m` already has internal `unichar` helpers with matching
operations for trailing-slash stripping, extension start, last-component
start, delete lengths, and component appending. The inspected bodies match the
IDA drive-root and separator handling for those operations. Its
`NSPathStoreAppendExtension` also covers the observed capacity check, slash and
drive-prefix rejection, trailing-slash trim, short-root exclusions, and tilde
user-path check. The indirect short-length branch table was resolved from
instructions and matches that source helper. This cluster can likely be
reconstructed as thin C entry points over the existing `NSPathStore` helpers,
without changing the NSString or NSPathStore2 behavior; `__NSStandardizePath`
is a separate, substantially larger routine and is outside this candidate
slice.

### `__NSAppendPathExtension` branch-table resolution

The indirect jump at `0x42516410` is a short-length switch; its resolved
branches agree with `NSPathStoreAppendExtension`. After the capacity and
extension checks and trailing-slash trim, an empty path is rejected. A path
starting with `~` is accepted only when a slash follows the tilde user portion;
therefore bare `~` and `~user` are rejected, while `~/...` and `~user/...`
are accepted. Non-tilde paths of length at most three are accepted only when
they are not `/`, a two-character drive/UNC root, or a three-character drive
root ending in `/`. The helper then appends `.` and copies the extension.

The current manifest pattern supports implementing this cluster as file-local
reconstruction work: add the seven IDA C names to
`reconstruction/abi/NSPathUtilities.json` `text_symbols` and
`reconstruction/symbols.json` under `NSPathUtilities.m`, then define the
matching external functions in `NSPathUtilities.m` over the existing private
`unichar` helpers. `NSPathUtilities.h` currently exposes public Foundation
path APIs but none of these internal C helpers, so this slice needs no new
public-header declarations. The ownership map records Objective-C selectors
and selected C exports separately; check its existing convention before
adding entries there.

### Implementation status (2026-10-04)

Added all seven exported C entry points in `NSPathUtilities.m` over the
matching existing `NSPathStore` helpers. `_NSStripTrailingPathSlashes` also
returns the target's changed-length flag. Added the seven Mach-O text names to
`NSPathUtilities.json` and `symbols.json`; no public-header or
Objective-C-selector ownership entries were needed. The focused export audit
now reports 108 unclaimed functions, down from 115 before this cluster was
claimed. No tests or builds were run.

### Additional path buffer exports (2026-10-04)

IDA also confirms five more path buffer functions whose operations match
existing helpers: `_NSTransmutePathSlashes` (`0x42501df8`),
`_NSIsAbsolutePath` (`0x42525434`), `_NSExpandTildeInPath` (`0x425323c4`),
`_NSPathComponents` (`0x4253aa18`), and `_NSAbbreviatePathWithTilde`
(`0x42542c6c`). The source now exports these functions through the existing
slash, tilde, absolute-path, and component helpers. The abbreviation helper
returns whether it changed the buffer, matching the C export's return value.
Their text names are claimed in the ABI and symbol manifests. No public header
declarations were added. No tests or builds were run.

### Symlink and filesystem-name exports (2026-10-04)

Added `_NSResolveSymlinksInPath` (`0x42531c4c`) over the existing
`NSPathStoreResolveSymlinks` implementation and added the target's
`_NSConvertPathToLongFileSystemName` (`0x42584980`) no-op stub. Both Mach-O
text names are claimed in the path utility manifests. The export audit now
reports 101 unclaimed functions. No tests or builds were run.

### `_NSStandardizePath` entrypoint recheck (2026-10-04)

IDA confirms `_NSStandardizePath` (`0x425179bc`) is an in-place C entry point
with an integer result. It transmutates and strips slashes, checks absolute
paths for `..`, and resolves those paths using a bounded 1024-word scratch
buffer. If the resolved length exceeds the caller's capacity, it returns the
initial slash-change flag without copying the scratch result. Otherwise it
performs lexical cleanup of terminal `/.`, leading `./`, interior `/./`, and
parent components, removes an existing `/private/` prefix, and returns 1.

The supporting `__pathHasDotDot` at `0x42512120` only reports parent
components for paths `_NSIsAbsolutePath` accepts. For UNC paths it begins the
scan after the server and share portions; otherwise it scans from the root.
It requires `..` to begin at a component boundary and to end at a slash or the
path end. `_NSTransmutePathSlashes` preserves the two leading backslashes of
UNC paths while collapsing repeated forward slashes, and
`_NSStripTrailingPathSlashes` preserves `/` and drive roots. These details
mean the current `NSPathStoreHasAbsoluteDotDot` and component-stack reducer
cannot stand in for the target; the next source pass should port the bounded
buffer and the target's in-place scan rather than claim a thin wrapper.

The source's `NSPathStoreStandardize` already performs slash handling,
symlink-aware cleanup, component reduction, and the `/private/` check, but it
normalizes through a separate component-stack algorithm and has no integer
result. In particular, directly exporting it would lose the target's bounded
scratch fallback and return behavior. This entry point remains unclaimed while
those control-flow differences are reconciled.

### `_NSNewStringFromCString` (2026-10-04)

IDA confirms `_NSNewStringFromCString` at `0x42570b44` scans to the C-string
terminator, calls `+[NSString stringWithCString:length:]`, and retains the
result. `NSString.m` now implements that export with the same bounded-string
constructor and ownership. Its Mach-O name is claimed in the NSString ABI and
symbol manifests. No tests or builds were run.

### `_NSBundleDisableCodeLoading` (2026-10-04)

IDA at `0x425841bc` confirms this export clears the internal
`_NSBundleCodeLoadEnabled` flag. Its `call $+5` / `pop eax` sequence is the
i386 PIC base-address idiom used to address that global; the decompiler's
apparent integer return (`0x425841c4`) is the leftover PIC base, not a
meaningful value. IDA reports no callers, so the source exposes the operation
as a void setter. The implementation and Mach-O symbol claims are in
`NSBundle.m` and its ABI/symbol manifests. No tests or builds were run.
The export audit decreased from 95 to 94 unclaimed functions.

### NSHashTable C-string callbacks (2026-10-04)

IDA confirms `_NSHashTableHashCString` at `0x4251c748` hashes signed C-string
bytes into successive 8-bit lanes of an unsigned result, resetting the lane
after four bytes; a null pointer returns zero. `_NSHashTableIsEqualCString`
at `0x425419f0` performs bytewise NUL-terminated equality, and
`_NSHashTableDescribeCString` at `0x42570874` returns
`+[NSString stringWithCString:length:]` using the scanned byte length. The
callbacks ignore their table argument. All three C exports are now defined in
`NSHashTable.m` and claimed in its ABI and symbol manifests. No tests or builds
were run. The export audit decreased from 94 to 91 unclaimed functions.

### `_NSMapTableDescribeCString` (2026-10-04)

IDA at `0x425709bc` confirms this callback scans its C-string key to the NUL
terminator and returns `+[NSString stringWithCString:length:]` with that byte
length. It ignores the map-table argument and has a data reference from the
map callback table. The export is now defined in `NSMapTable.m` and claimed in
its ABI and symbol manifests. No tests or builds were run; the export audit
decreased from 91 to 90 unclaimed functions.

### `_NSGenericFree` (2026-10-04)

IDA at `0x4250cee8` confirms this helper records `NSZoneFreeEvent` with the
pointer and three zero arguments when allocation statistics are enabled, then
calls libc `free`. Its callers are `-[NSConcreteData dealloc]` and
`-[NSConcreteMutableData initWithBytes:length:copy:freeWhenDone:bytesAreVM:]`;
the source now uses the helper at both matching non-VM free sites. The helper
is defined in `NSZone.m` and claimed in its ABI and symbol manifests. No tests
or builds were run; the export audit decreased from 90 to 89 unclaimed
functions.

### `_NSSubtractRange` (2026-10-04)

IDA at `0x425a28a0` confirms this helper subtracts one `NSRange` from another,
writes up to two non-overlapping remainder ranges, zeroes both outputs for
disjoint inputs, and returns the subtracted range's end. The source mirrors
the target's unsigned endpoint arithmetic and overlap branches. It is defined
in `NSRange.m` and claimed in the NSRange ABI and symbol manifests. No tests or
builds were run.

### Single-byte byte-to-Unicode exports (2026-10-04)

IDA confirms seven byte-to-Unicode entry points: `_NSASCIIToPrecompUnicode`
(`0x42590a10`) and `_NSISOLatin1ToPrecompUnicode` (`0x42591614`) return their
byte unchanged; `_NSAdobeStandardCyrillicToUnicode` (`0x42590a1c`) uses the
CP1251 table; `_NSWinCodePage1250ToUnicode` (`0x42593238`),
`_NSWinCodePage1253ToUnicode` (`0x42593268`), and
`_NSWinCodePage1254ToUnicode` (`0x42593298`) use their matching code-page
tables; `_NSWinLatin1ToUnicode` (`0x425932c8`) maps CP1252 control bytes and
passes other bytes through. The IDA word tables match the existing tables in
`NSCharConversion.m`; the source now exports wrappers over its existing
decoder and claims all seven Mach-O symbols. No tests or builds were run.

The five exported names use one leading underscore in the reconstruction
manifests, matching the reference Mach-O names. Their C identifiers omit that
Mach-O underscore. The static export audit later reports 80 unclaimed
functions after adding `_NSRequestConcreteObject`.

### `_NSRequestConcreteObject` (2026-10-04)

IDA at `0x42571848` confirms this helper raises
`NSInvalidArgumentException` with the abstract-object format used by
`NSRequestConcreteImplementation`, passing its second argument directly as
the selector-name string and the receiver class name. It is defined in
`NSObjCRuntime.m` as `_NSRequestConcreteObject`
and claimed under its Mach-O spelling `__NSRequestConcreteObject` in the ABI
and ownership manifests. The final static symbol audit reports 80 unclaimed
functions. No tests or builds were run.

### Zapf Dingbats byte-to-Unicode export (2026-10-04)

IDA at `0x42593308` confirms `_NSZapfDingbatToPrecompUnicode` directly indexes the 256-word `_Zapf_to_Uni` table at `0x425a7368`. The source now contains the recovered table and direct wrapper in `NSCharConversion.m`; all 256 entries match IDA. Its ABI and ownership entries are recorded. The static symbol audit reports 75 unclaimed functions. No tests or builds were run.

### Unicode-to-Dingbats encoder (2026-10-04)

IDA at `0x425924d4` confirms `_NSUnicodeToDingbat` delegates to the generic 8-bit encoder with 188 sorted records from `_uni_to_ding_tab` at `0x425a78b8`. `NSStringEncodings.m` now contains the recovered Unicode-to-byte table and wrapper. The static check found 188 strictly sorted records and verified the C definition plus ABI and ownership entries. The reference-image symbol audit reports 74 unclaimed exported functions. No tests or builds were run.

### Adobe Standard Unicode encoder (2026-10-04)

IDA at `0x425922e8` confirms `_NSUnicodeToAdobeStandard` passes U+0000–U+009F through, maps U+2029 to LF, and otherwise searches 55 sorted records in `_adobestandard_from_tab` at `0x425a6d08`. `NSStringEncodings.m` now implements those three paths. Source records exactly match all 55 IDA mappings, and the function is claimed in the ABI and ownership manifests. The reference-image symbol audit reports 73 unclaimed exported functions. No tests or builds were run.

### Unicode decomposition exports (2026-10-04)

IDA confirms `_NSDecomposeCharacter` (`0x42591350`) recursively applies direct decomposition to each component, while `_NSSimplyDecomposeCharacter` (`0x425920c0`) copies the direct decomposition sequence. Both fall back to the input character when the table cannot load or the character is not in `decomposableCharacterSet`; a set member missing from the sorted table raises the respective internal-error exception. `_NSReadDecompFile` (`0x42591d64`) lazily loads `CharacterSets/NonHangulDecomp.data`, reads the record count at byte offset 4, and retains the decomposable character set. The source and ABI now include these functions and the four backing globals.

The reference resource is 10,626 bytes and has 1,052 strictly sorted records; every record offset points to a terminated UTF-16 sequence. The static Foundation symbol audit reports 71 unclaimed exported functions. No tests or builds were run.

### EUC byte-to-Unicode export (2026-10-04)

IDA at `0x42591b94` confirms `_NSNextEUCToUnicode` loads `EUCToUnicode` lazily, then decodes ASCII, 0x8E-prefixed JIS X 0201 bytes, 0xA0-prefixed NEXTSTEP bytes, and mapped JIS X 0208 pairs, falling back to the NEXTSTEP decoder for other single bytes. `NSCharConversion.m` now implements those branches with the existing table loader and binary-search helper, plus the recovered 256-word JIS X 0201 table at `0x425a8d9e`. The table matches every IDA word; the local little-endian EUC mapping resource contains 7,064 sorted entries. ABI and ownership records are present. The symbol audit reports 70 unclaimed functions. No tests or builds were run.

### URL escape sequence helper export (2026-10-04)

IDA decompiles `__NSURLEscapeSequenceForCharacter` at `0x425958f8` as a
single-character percent escape builder. It takes the low byte of the UTF-16
input, emits `%` followed by two uppercase hexadecimal digits, and returns an
NSString created from three UTF-16 characters. Its sole caller is
`-[NSString stringByAddingPercentEscapes]`.

`NSPathUtilities.m` already has a static
`NSURLEscapeSequenceForCharacter(unichar)` with the same three-character
construction and same percent-escaping caller. The source function is not
externally linked or assigned in the `NSPathUtilities` text-symbol manifest.
This gap can be closed by aligning the C identifier/linkage and recording the
ABI ownership without changing the escaping behavior.

Implementation status (2026-10-04): the helper is now externally linked as
`_NSURLEscapeSequenceForCharacter`, and its Mach-O name is present in the
`NSPathUtilities` ABI and symbol maps with source ownership recorded. The
source caller uses the exported definition; the percent-escape behavior did
not change. Static mapping checks passed and the export audit reports 42
unclaimed functions. No tests or builds were run.

### NSData atomic-write helper export and fallback (2026-10-04)

IDA decompiles `__NSWriteBytesToFile` at `0x4253bc54` as the implementation
behind `-[NSData writeToFile:atomically:]`. It preserves existing file mode or
uses `0666 & ~umask`, writes and syncs the destination or a same-directory
temporary file, then attempts replacement. If replacement fails with
`EINVAL`, it tries the reference's second same-directory move sequence
regardless of whether the destination existed before the write.

The source helper now uses the filesystem-representation path and the
`EINVAL` fallback no longer adds a destination-exists condition. It is
externally linked as `_NSWriteBytesToFile` and claimed in the `NSData` ABI,
symbol, and ownership maps. `_NSmkstemp83` now shares the IDA-confirmed
four-character prefix, 16-bit process suffix, 12-bit counter, mode-0600
exclusive creation, and counter-lock gate across atomic writes, replacement
fallbacks, and directory removal. Its Mach-O symbol is claimed in the
NSFileManager ABI and symbol maps, with source ownership recorded. The symbol
audit reports 40 unclaimed exports. No tests or builds were run.


### `_NSReleaseLock` (2026-10-04)

IDA at `0x42525300` confirms the three-argument defaults lock-release helper
constructs the per-domain `.lock` directory path, changes it to mode `0700`,
removes it, and—when the store changed effective user—restores root identity,
resumes every other task thread, and returns the thread-array deallocation
status. Its callers are the `NSLockedPropertyListFile` methods and defaults
conversion paths. `NSUserDefaults.m` now exports `_NSReleaseLock` and routes its
existing release call sites through it; the source returns the observed
`kern_return_t` result. Its Mach-O symbol is claimed in the `NSUserDefaults`
ABI and symbol maps with source ownership recorded. Static consistency checks
passed; the symbol audit reports 39 unclaimed functions. No tests or builds
were run.


### `_NSFileAccessModes` (2026-10-04)

IDA at `0x42535290` confirms `_NSFileAccessModes` initializes its optional
outputs, converts the path with a 1024-byte limit, follows links with `stat`,
then reports existence, read/write/execute access, directory status, and the
`st_ctimespec.tv_nsec` / `st_birthtimespec.tv_sec` values. Its caller
`_NSCouldBeBundle` uses the existence, readable, and directory outputs.
`NSFileManager.m` now exports the helper, and `NSBundleLookupOrCreate` uses a
source-side bundle predicate backed by it. The Mach-O export is claimed in the
NSFileManager ABI and symbol maps, with source ownership recorded. Static
consistency checks passed; the symbol audit reports 38 unclaimed functions.
No tests or builds were run.

### Notification-center table exports (2026-10-04)

Promoted the existing notification registry helpers to the IDA-exported
`_addToTables`, `_redoTables`, and `_replaceInTables` entry points in
`NSNotification.m`. Their signatures and table updates now match the
decompiled helper contracts, and observer insertion/removal calls these
exports directly. The ABI, symbol, and ownership maps now claim all three.
The reference symbol audit now reports 16 unclaimed exports. No tests or
builds were run.

### `NXReadNSObject` and `NXWriteNSObject` (2026-10-04)

IDA at `0x4256fde8` confirms `NXReadNSObject` reads an integer byte count and
typedstream character array, wraps the bytes in no-copy `NSData`, and
unarchives its root object. IDA at `0x4256ff18` confirms `NXWriteNSObject`
archives its object, writes the byte count, then returns the typedstream array
writer's result. Both implementations are in `NSCoder.m`, and their Mach-O
symbols are claimed in the NSCoder ABI and symbol maps with source ownership
recorded. The reference-image symbol audit now reports 32 unclaimed exported
functions, down from 34. No tests or builds were run.


### `_NSSetMainBundle` (2026-10-04)

IDA at `0x42585490` confirms the setter accepts only non-null regular bundles,
retains the replacement, moves a prior main bundle into the loaded-bundle
array, initializes the new bundle's info dictionary if needed, applies its
main-bundle flags, and copies `NSBundleResolvedPath` to
`NSBundleInitialPath` when present. `NSBundle.m` now exports this operation
using its existing singleton, flags, loaded-bundle array, and initializer.
The Mach-O symbol is claimed in the NSBundle ABI and symbol maps, with source
ownership recorded. No tests or builds were run.

### Distributed notification parser wrappers (2026-10-04)

IDA confirms `NSParseRegisterMessage` (`0x4256fa8c`) forwards to
`_NSParseMessage` with kind 0 and null user-info outputs, while
`NSParseSuspendMessage` (`0x4256fabc`) forwards with kind 2 and null name,
object, and user-info outputs. Added both wrappers beside the existing post
parser in `NSDistributedNotificationCenter.m`, and claimed their Mach-O names
in the ABI, symbol, and ownership manifests. The reference-image symbol audit
now reports 34 unclaimed exported functions, down from 36. No tests or builds
were run.

### `NSWaitForAllocationEvent` implementation (2026-10-04)

Added the IDA-confirmed Mach message receive path to `NSDebug.m`. It receives
into a 7608-byte buffer using the event port and millisecond timeout, then
reallocates the caller's buffer in its existing zone and copies the message.
The ABI, symbol, and ownership maps now claim `_NSWaitForAllocationEvent`.
No tests or builds were run.

### `NSParseAllocationEvent` implementation (2026-10-04)

Added the IDA-confirmed allocation-message parser to `NSDebug.m`. It copies
the fixed event fields and class name, byte-swaps the two time words, returns
the backtrace count, and grows/fills the caller's backtrace buffer in its
existing zone. The ABI, symbol, and ownership maps now claim
`_NSParseAllocationEvent`. No tests or builds were run.

### `_NSConvertToASCIIorUnicode` implementation (2026-10-04)

Added the IDA-confirmed wrapper around `_NSConvertToASCIIorUnicode2` in
`NSCharConversion.m`. It transfers heap storage produced by the helper, or
copies inline storage into the requested zone, then returns the converted
length and ASCII/Unicode flag. The ABI and symbol maps now claim
`__NSConvertToASCIIorUnicode`, with source ownership recorded. The reference
symbol audit now reports 21 unclaimed exports. No tests or builds were run.

### Localized-string marker helpers (2026-10-04)

IDA at `0x425851f4` confirms `_NSIsLocalizedString` checks whether its
argument is an `NSDebugString`; `_NSLocalizedString` at `0x4258523c` returns
marked strings unchanged or wraps them in an autoreleased `NSDebugString`.
`NSBundle.m` already owns that class and had equivalent inline wrapping.
Exported both helpers there and routed the existing localized-string path
through `_NSLocalizedString`. Added their Mach-O names to the NSBundle ABI and
symbol maps and recorded source ownership. The reference-image symbol audit
now reports 30 unclaimed exported functions, down from 32. No tests or builds
were run.

### Locale string comparator recheck (2026-10-04)

IDA decompiles `_NSCompareStringsWithLocale` at `0x42590a7c`; its only caller
is `-[NSString compare:options:range:locale:]`. The comparator uses the
`keyRanges`, `baseTable`, and `ligatureTable` data to map UTF-16 characters to
collation weights, expands table-marked ligatures in mutable copies, and
tracks primary, secondary, and tertiary differences; the case-insensitive
flag suppresses the tertiary comparison. `NSString.m` currently compares raw
UTF-16 code units for all locales, so this remains a fidelity gap. The tables
are position-independent and recovered from the function's call/pop base at
`0x42590a8a`: `keyRanges` begins at `0x425a9314` and contains 33 inclusive
UTF-16 intervals (from `0x0000–0x0217` through `0xfe20–0xfffd`),
`baseTable` begins at `0x425a939c`; the range arithmetic yields 7,772 indexes
of four signed 16-bit weights (62,176 bytes), ending exactly at the
`ligatureTable` base `0x425b867c`. Its first field reaches 1,295, selecting all
direct ligature indexes 0–1,293. Nineteen direct entries have negative
lengths and chain through signed indexes before or after that base. Following
those links reaches 1,316 distinct records, with indexes from -18,175 through
30,062; their expanded strings total 63,074 UTF-16 units using the helper's
four-unit fallback for nonpositive lengths. All referenced record and string
bytes were readable in IDA. The data can be exported as indexed records and
separate strings without copying intervening binary data. No comparator
implementation changes were made.

IDA extraction fingerprints for a later export check: `keyRanges`
`82d16201f6cc641c181c9eb54e0e9d9c5e8df1935c0fe1d51962260a4aefdaf7`,
`baseTable` `ebc6ea925193a5173f823cccac28017caafae6de608b1fa07d12c1a5c88b72c9`,
and the index-sorted reachable ligature records plus their expansion units
`2df5c1418e9f35b33e7e01a719ba94d9d57f65bd8192cde264a093ac7ae54371` (139,308
bytes in the fingerprint stream).

The caller at `0x4258f434` dispatches to `_NSCompareStringsWithLocale` only
when its locale argument is non-null. The null-locale path compares chunks of
up to 32 UTF-16 units through `NSCompareCharacters`, which is already defined
in `NSSimpleString.m`. Therefore the source change should route only the
non-null-locale case through the reconstructed table comparator and preserve
the existing non-locale behavior.

### Locale comparator table fingerprint recheck (2026-10-04)

Re-read the live IDA database before exporting comparator data. The key-range
table is 136 bytes and matches its recorded SHA-256; its 33 inclusive
intervals cover 7,772 code units. The base-weight table is 62,176 bytes and
also matches its recorded SHA-256. Its 7,772 rows reference 1,294 direct
ligature indexes. IDA reads a negative-length chain link from
`ligatureTable + 10 * index - 2`, as shown by the decompilation expression
`*(__int16 *)(8 * index + 2 * index + base - 2)`. Re-following links from
each direct index reaches 1,302 distinct records spanning -19,851 through
28,051, with a maximum chain length of five and no cycles. Each nonpositive
record length contributes four UTF-16 units; unique reachable records contain
61,600 such units, while summing every direct index's expansion path gives
93,335 units. The earlier 1,316-record / 63,074-unit count followed the wrong
link (the first expansion character) and must not be used.

Disassembly at `0x42590cc0` confirms expansion order: replace the original
character with the first record's characters, then insert each linked record
at the original character index plus the number of UTF-16 units already
expanded. The loop follows the negative-length link until it reaches a
nonnegative-length record, using four characters for each nonpositive record.

The previously recorded 139,308-byte ligature fingerprint and attempted
serializations used the incorrect chain traversal. Discard those fingerprints
and the temporary export. The range and base-weight fingerprints remain valid.
No table export or comparator implementation was made; the following
serialization defines the replacement fingerprint for source generation.

For a reproducible replacement, sorted unique reachable records are the raw
10 bytes at `ligatureTable + 10 * index`; their SHA-256 is
`7b89bd73ad223a7d2557202d6bec290419153d79afcab55018eddfc2a744d55a`. Adding
each signed 32-bit little-endian record index before its 10 bytes yields
`c1b5dffae0d94be09e3cab90580e74046d095410d33a8f1e5a9ddcbbb0ebe726`. The
expansion stream walks direct indexes in ascending order and each chain in
traversal order, reading the positive record length in UTF-16 units or four
units for nonpositive lengths from `base + 10 * index + 2`; its 93,335-unit
SHA-256 is `54c239f5985c6915779b1f094e84e702cfbbe46e9e4ac35650e20fb8fb578c89`.
The combined fingerprint over raw key ranges, raw base weights, and the
index-prefixed unique records is
`7622e3a33a9f79a1d5942a1157ae22e11695059708da40667c5ba0838c81f6c7`.

### Locale string comparator reconstruction (2026-10-04)

Added `NSStringLocalizedCompare.m` and generated
`NSStringLocalizedCompareData.inc` from the corrected IDA traversal above.
The include contains the 33 key ranges, the sentinel plus 7,772 four-weight
rows, 1,302 reachable ligature records, and 61,600 UTF-16 units. Its sorted
record/unit serialization digest is
`4827606431431645224665c24345c58f807c0dd5a46adb25fd1a7933e251b3f8`.
The helper preserves the decompiled per-side ligature expansion, primary /
secondary / tertiary comparisons, ignorable-weight advancement, and
case-insensitive tertiary suppression. `NSString` dispatches to it only when
the locale argument is non-null; the existing null-locale path remains in
place. Build lists, ABI metadata, symbol assignment, and source ownership now
include the helper. No tests or builds were run.

### Locale comparator include integrity recheck (2026-10-05)

A fresh read from the live Foundation-i386 IDA database confirms the 33 key
range pairs (132 bytes, SHA-256
`f83241e2fda9455a5055296f98163fbfb234880ab38274bd492756769aea30aa`) and the
62,176-byte base-weight table (SHA-256
`ebc6ea925193a5173f823cccac28017caafae6de608b1fa07d12c1a5c88b72c9`) match
the checked-in data. Following the IDA pseudocode's signed-link negation, the
1,294 direct indexes reach 1,302 unique records (range -19,851 through 28,051),
with maximum chain depth five, 61,600 units across unique records, and 93,335
units across all direct-index expansion paths. The IDA-derived canonical
index/length/link/count/UTF-16 serialization has SHA-256
`4827606431431645224665c24345c58f807c0dd5a46adb25fd1a7933e251b3f8`, exactly
matching the checked-in include's integrity digest. The include's unit ranges
and effective lengths are in bounds, every negative-length link resolves, and
no chain cycles were found. No comparator source changes were needed.

### Locale comparator control-flow parity recheck (2026-10-05)

Compared the current `NSStringLocalizedCompare.m` helper against the live IDA
pseudocode for `_NSCompareStringsWithLocale` at `0x42590a7c`. The source
preserves the target's first-string range start/count and full second-string
length, independently expands ligatures on each side, compares primary then
secondary and optional tertiary weights, handles ignorable-weight advancement,
and resolves remaining lengths before the primary difference. The out-of-table
sentinel path also matches IDA's negative weight row. No control-flow or
comparison-order discrepancy was found in this static pass. No code changes,
tests, or builds were made.

### Locale comparator PowerPC control-flow parity recheck (2026-10-05)

Re-decompiled the MOSXS PowerPC `_NSCompareStringsWithLocale` at
`0x42556df4` and compared its dispatch, fallback row, ligature expansion,
weight precedence, ignorable-character advancement, and final tie resolution
with the current source. The target uses the same 33 key ranges and the same
five-short ligature records already recovered for i386; source selects the
PPC-specific weight table under the PowerPC compiler guards. The `options & 1`
tertiary-weight suppression and empty-range comparison agree with the PPC
entry and exit branches. No additional source discrepancy was found. No code
changes, tests, or builds were made.

### Nonlocalized NSString comparison dispatch correction (2026-10-07)

The i386 and PPC `-[NSString compare:options:range:locale:]` entries use
`getCharacters:range:` to fetch each side in chunks of at most 32 UTF-16 units,
then call `_NSCompareCharacters`. The source's nonlocalized path had the same
ordinary code-unit ordering but sent `characterAtIndex:` one character at a
time. `NSString.m` now follows the target chunk and selector dispatch, which
also preserves range-exception behavior for invalid receiver ranges. Locale
collation remains delegated to the separately reconstructed table comparator.
No tests or builds were run.

### `_NSJavaBundleClassPath` gap (2026-10-04)

IDA decompiles `_NSJavaBundleClassPath` at `0x425708b8` as a two-argument
bundle/key helper. It reads the bundle's info dictionary and returns `nil` if
`NSJavaNeedsVirtualMachine` is false. For the `NSJavaPath` key it returns
`_NSJavaAbsolutePath(bundle, info, key, nil)`; for other keys it returns the
dictionary value. `NSJavaSetup.m` already defined both supporting helpers but
did not define or claim `_NSJavaBundleClassPath`. The helper is now implemented
there and declared in `NSJavaSetup.h`; its Mach-O symbol is claimed in the
NSJavaSetup ABI and symbol maps, and source ownership is recorded. Its behavior
follows the IDA branches, with no call-site changes. IDA has no callers for the
exported function in the loaded reference image. The reference symbol audit now
reports 28 unclaimed exported functions. No tests or builds were run.

### `_NSUniqueCString` gap (2026-10-04)

IDA decompiles the exported `_NSUniqueCString` at `0x42538dec`. It returns
`NULL` for a null input, lazily creates a C-string `NSHashTable` with capacity
27, interns a copied NUL-terminated string, and optionally protects lookup and
insertion with `_NSUniqueCStringLock`. The reference has no source definition
in the current tree, and its lock, table, and C-string callback globals also
need to be accounted for before implementation. No code changes were made.

### `_NSUniqueCString` implementation (2026-10-04)

Implemented the IDA-confirmed string interner in `NSSimpleCString.m`. It
returns null for null input, lazily creates the 27-capacity C-string hash
table with the existing C-string callbacks, copies and inserts missing
strings, and returns the table's canonical pointer. Added the missing lock
global and first-thread initialization in `NSThread.m`; registered the
function and lock in the ABI and symbol maps and recorded function ownership.
The reference symbol audit now reports 23 unclaimed exports. No tests or
builds were run.

### `_decodeFastByte` cursor contract (2026-10-04)

IDA decompiles `_decodeFastByte` at `0x4251875c` as a byte read from the fast-decoder context: the cursor pointer is at offset 4, the end pointer is at offset 8, and the function raises the decoder's bounds exception when the end pointer is less than the cursor. Otherwise it returns the next unsigned byte and increments the cursor. Callers are `__NSWalkData` (`0x4251db30`) and `_decodeFastCharStar` (`0x42524898`); the latter then reads a 32-bit length, checks the requested span against the same end pointer, and advances the cursor over the string bytes. The related context consumers have no source implementation in the current tree, and no existing `_decodeFastByte` source definition was found. This helper's ABI is recoverable, but reproducing its context layout and exception path in a source-owned unit should be reviewed together with the fast-decoder call sites. No implementation changes were made.

### `_decodeFastByte` implementation recheck (2026-10-05)

The current worktree now implements `decodeFastByte` in `NSSerialization.m`,
with ABI, symbol, and ownership entries. A fresh IDA comparison at
`0x4251875c` confirms the context layout: cursor at offset 4 and end at offset
8. Both implementations raise `NSInternalInconsistencyException` when the end
pointer precedes the cursor, advance one byte, and return it unsigned. This
supersedes the earlier note that no source definition existed; `_NSWalkData`
and `_decodeFastCharStar` remain separate gaps.

### `_NSParseAnd*` wrapper contracts (2026-10-04)

IDA identifies three thin exports that all delegate to `_NSWalkData` at
`0x4251DB30`: `_NSParseAndAutorelease` (`0x4252E978`) passes mode 4,
`_NSParseAndRelease` (`0x425761A4`) passes mode 2, and `_NSParseAndRetain`
(`0x425761C0`) passes mode 3. Each passes flag 1, a null context, the caller's
cursor, and the type string, then returns the helper's byte count. Their
behavior is straightforward, but source definitions depend on reconstructing
the shared walker and its serialization context; do not duplicate a guessed
walker in each wrapper. No source changes were made.

### `_NSWalkData` dispatch map (2026-10-04)

IDA pseudocode for `_NSWalkData` shows the shared worker is a recursive
Objective-C type-encoding walker with a mode argument. Modes 0 and 1 read and
write data through a fast-decoder / serializer context; modes 2, 3, and 4
perform ownership and copy side effects. For `@`, those modes call `release`,
`retain`, and `autorelease` respectively. For `*`, mode 2 frees through
`NSZoneFromPointer`, mode 3 copies the NUL-terminated bytes into the default
zone and replaces the pointer, and mode 4 constructs `NSData` from the bytes
(the decompiled return value is ignored). Primitive encodings use their ABI
widths (1, 2, 4, or 8 bytes); classes, selectors, C strings, and percent
strings use a nullable length-prefixed representation when reading. Object
encodings dispatch to the serializer callback, including separate bycopy /
byref handling. Pointer encodings recurse only at the root and when the
serialized presence byte is set. Arrays recurse for the encoded element count,
while structs align each field using `NSGetSizeAndAlignment` and delegate
bitfield runs to `getBitfieldSize` / `walkBitfields`.

The context layout is now corroborated by the IDA callers. `-[NSData
deserializeDataAt:ofObjCType:atCursor:context:]` builds a 26-byte context with
the owning data object at offset 0, cursor at offset 4, end pointer at offset
8, zeroed words at offsets 12 and 16, callback object at offset 20, and zeroed
flags at offsets 24 and 25. It invokes the walker in mode 0 at the root, then
sets the caller's cursor from the advanced pointer. `-[NSMutableData
serializeDataAt:ofObjCType:context:]` builds the same-size context with the
destination data at offset 0, zeroed words at 4/8/12, `NSDataFuncList` at
offset 16, callback object at 20, and zeroed flags at 24/25; it invokes mode
1 at the root. Both recurse with the root flag cleared. The source's existing
`NSWalkObjCType` and `NSObjCTypeSerializationCallBack` cover related type
semantics, but they do not implement this compact callback-table context or
the mode 2/3/4 memory-management operations. The `_NSParseAnd*` wrappers
remain thin delegates, and `decodeFastByte` is only one dependency of the
larger reconstruction. No source changes were made.

### Full Objective-C selector audit refresh (2026-10-04)

Ran `tools/binrecon/selector_check.py` against the current Foundation source and
`Foundation-i386`. The audit reports 3,253 reference selectors, 3,300 source
definitions, zero missing selectors, zero renames, and zero duplicates. It lists
47 source extras. Some extras are APIs outside this target's selector inventory;
several `NSURLHandle` entries include a trailing semicolon from source comments,
so the extra list is not a clean version-difference inventory. The selector
coverage result confirms current source definitions cover every selector in
the reference. The separate C-symbol audit has 29 unclaimed exports, so
remaining target-backed work is concentrated in C functions and non-selector
symbols. No tests or builds were run.

### `_NSDebugRecordObjectAndStack` implementation (2026-10-04)

IDA at `0x4256edb4` contains an empty function body for
`NSDebugRecordObjectAndStack`. Added the matching no-op function to
`NSDebug.m` and claimed its Mach-O symbol in `NSDebug.json` and
`symbols.json`. Static checks report one ABI entry, one symbol-map owner, and
one source definition; the reference symbol audit decreased from 30 to 29
unclaimed exports. No tests or builds were run.

### Shift-JIS byte conversion exports (2026-10-04)

IDA decompilation of `NSEUCToShiftJIS` at `0x42591480` confirms the low-level
EUC-to-Shift-JIS conversion contract: it reports the number of source bytes
consumed separately from the number of output bytes returned, passes ASCII
through, maps EUC half-width kana (`8E A1`–`8E FE`) to one Shift-JIS byte,
replaces malformed input with `?`, and maps valid two-byte EUC characters by
the standard row/cell arithmetic. It also maps the NEXTSTEP row `FE A2`–`FE F9`
and six `A2` vendor characters to Shift-JIS lead byte `87`.

`NSEUCToShiftJIS` is called by the exported `NSUnicodeToShiftJIS` at
`0x42592BF0`. Its computed branch resolves to six inline vendor cases for
`A2 DC`, `A2 DD`, `A2 E1`, `A2 E2`, `A2 E5`, and `A2 E9`, producing trails
`97`, `96`, `91`, `90`, `95`, and `92` respectively. `NSStringEncodings.m` now
exports this low-level converter with the IDA-confirmed consumed-byte output,
and the Unicode encoder delegates to it rather than duplicating the mapping.
The function is claimed in the ABI and symbol maps, with source ownership
recorded. The reference symbol audit now reports 27 unclaimed exports.

IDA decompilation of `NSShiftJISToEUC` at `0x42591E64` confirms the reverse
arithmetic, including ASCII passthrough, half-width-kana prefixing, the
two-byte JIS conversion, and the `87` vendor-extension cases. Its computed
table maps `87 90`–`87 92`, `87 95`–`87 97` to the six `A2` vendor bytes;
`87 93` and `87 94` use the `FE` extension path. `NSCharConversion.m` now
implements the byte converter, including the `F0`–`FC` replacement behavior,
and claims its Mach-O symbol in the ABI and symbol maps with source ownership
recorded. The reference symbol audit now reports 26 unclaimed exports.

The exported `NSShiftJISToUnicode` at `0x4259203C` remains unimplemented. It
handles ASCII and half-width kana directly, otherwise converts through
`NSShiftJISToEUC` and `NSNextEUCToUnicode`; on conversion failure it advances
the input by one byte and returns zero. No tests or builds were run.

### `NSShiftJISToUnicode` implementation (2026-10-04)

Implemented the IDA-confirmed wrapper in `NSCharConversion.m`. ASCII and
half-width kana advance the input by one byte and return directly. Other input
is converted through `NSShiftJISToEUC`; a successful conversion advances by
the reported source-byte count and delegates to `NSNextEUCToUnicode`, while a
failed conversion advances one byte and returns zero. The two-byte EUC buffer
and original remaining-length argument follow the decompiled call sequence.
The function is listed in the ABI and symbol maps and has source ownership
recorded. The reference symbol audit now reports 25 unclaimed exports. No
tests or builds were run.

### `_NSStandardizePath` source gap (2026-10-04)

IDA locates the exported helper at `0x425179bc`. It mutates a UTF-16 path
buffer and length and accepts a capacity. Its normal path returns `1`, even
when no normalization was needed. If a path contains an eligible `..` and the
temporary resolved length exceeds capacity, it returns the flag accumulated
from the initial slash transmutation / trailing-slash cleanup instead. All four target
wrappers call it: `NSPathStore2` and generic `NSString` implementations of
`stringByStandardizingPath` and `stringByResolvingSymlinksInPath`. Each copies
up to 1,024 UTF-16 units and expands a leading tilde; the resolving variants
also call `_NSResolveSymlinksInPath` before standardization.

Its `_pathHasDotDot` predicate at `0x42512120` only enables real-path
resolution for absolute paths containing a complete `..` component. It has a
branch to skip UNC server and share components, but that branch is gated by
`_NSIsAbsolutePath` (`0x42525434`), which returns true only for leading `/` or
`~`; the slash transmuter preserves a leading `\\`, so ordinary UNC paths do
not reach the UNC scan. The existing `NSPathStoreStandardize` in
`NSPathUtilities.m` likewise returns void and its
`NSPathStoreHasAbsoluteDotDot` gate checks `/` or `~` prefixes. The reference
export is therefore not represented by merely adding a symbol alias to the
current helper. A faithful implementation should reconstruct the C helper and
route the four existing wrappers through it. No source changes were made.

The decompilation further confirms this sequence: collapse slash runs and
remove trailing slashes; if `_pathHasDotDot` succeeds, resolve a temporary
copy using a 1,024-unit capacity and copy it back only when its resulting
length fits the caller's capacity; trim terminal `/.`; remove leading `./`
components for non-UNC paths; collapse `/./`; reduce `/../` while keeping the
UNC server/share prefix; then transmute and trim slashes again. A leading
`/private/` is removed only when the remainder exists. `_NSStandardizePath`
returns `1` after this normal path regardless of whether those later stages
changed the buffer. Each target wrapper uses a 1,024-unit stack buffer and
returns a `NSPathStore2`; the generic source methods currently use separate
object-array and UTF-8 `realpath` paths instead.

The current source call sites are `NSPathStore2`'s methods at lines 1102 and
1119. The standardizing method expands tilde and invokes the private void
normalizer; the resolving method first invokes `NSPathStoreResolveSymlinks`,
then the same normalizer. Generic `NSString` has separate implementations at
lines 1379 and 1412: standardization reduces `pathComponents` in an object
array, while symlink resolution calls `realpath` on the whole UTF-8 path and
falls back to that standardizer. Neither generic method uses the target's
buffer-based helper. The `NSPathUtilities` ABI manifest and symbol ownership
map currently omit `_NSStandardizePath`; the adjacent slash and symlink
helpers are already registered. Routing all four methods through the
reconstructed helper would replace these separate normalization paths, so
their target return and fallback behavior should be checked against the
wrappers before coding.

A fresh caller pass confirms the four target call sites at `0x4253108c`
(`NSPathStore2` standardization), `0x42532b10` (`NSPathStore2` symlink
resolution), `0x42541a1c` (`NSString` standardization), and `0x42545148`
(`NSString` symlink resolution). All return
`+[NSPathStore2 pathStoreWithCharacters:length:]`; the resolving paths invoke
`_NSResolveSymlinksInPath` before `_NSStandardizePath`. This confirms routing
the generic NSString methods through the helper also changes their concrete
result type to `NSPathStore2`, matching the reference call graph.

A fresh helper pass confirms `_pathHasDotDot` first requires
`_NSIsAbsolutePath` and recognizes only complete `..` components bounded by
`/` or the path end. Its optional UNC prefix scan is unreachable for ordinary
UNC input here because `_NSIsAbsolutePath` accepts only `/` and `~`. The
`/private/` check calls `_NSFileExistsAtPath`, which converts the supplied
UTF-16 suffix to filesystem bytes, uses `lstat`, and follows symlinks with
`stat`; the current source helper already provides this filesystem check.

The exact-profile `symbol-audit` on 2026-10-04 reports nine unclaimed
Foundation exports: `_NSRecordAllocationEvent`, `__NSParseAndAutorelease`,
`__NSParseAndRelease`, `__NSParseAndRetain`, `__NSPrintExtraRefCount`,
`__NSPrintForDebugger`, `__NSStandardizePath`, `__NSToDoAtLastThreadExit`, and
`__NSWalkData`. `_NSStandardizePath` is therefore an active export gap rather
than a missing helper already covered under another source symbol.

### Remaining `NSDebug` C exports (2026-10-04)

IDA decompiles `_NSStringFromStack` at `0x4256FBFC` as a formatter over the
existing frame helpers. The machine code reads two arguments (format and
separator), creates an autoreleased mutable string, walks from
`_NSFirstFrameAddress` using `_NSNextFrameAddress`, and appends the format with
each frame's return address until the next frame address is at or below
`0x7ff`. The defaults are `@"0x%x"` for the address format and `@" "` for the
separator. The separator is inserted at the string's end with
`replaceCharactersInRange:NSMakeRange(length, 0) withString:`. This function is
now implemented in `NSDebug.m` and registered in the ABI, symbol, and ownership
manifests. The frame walk preserves IDA's ordering: it inserts a separator
before validating the next frame and appends the current frame's return address
only when that next frame exceeds `0x7ff`.

`_NSRecordAllocationEvent` at `0x4256FAE4` forwards its event and first
argument to `__NSRecordAllocationEvent` at `0x42571124`. The latter first
performs negative-retain checks for event types 3, 5, and 7 when enabled. When
the event's bit is enabled in `NSAllocationStatisticsOutputMask`, it locks the
record path, resolves `NSAllocationStatisticsOutputPortName` (including the
`mach-port://host/port` form), looks up the send port, and dispatches event
payloads through a switch for event types through `0x18`. The lower-level
dispatcher and the message layout need further analysis before restoring this
subsystem; source call sites already invoke the missing variadic public helper.

IDA decompiles `__NSPrintForDebugger` at `0x42570F58` as a guarded
`debugDescription` call. It releases the previously cached string, validates
the receiver with `isReadableAddr` and `isClass`, checks
`respondsToSelector:debugDescription`, establishes an exception handler around
the message, and returns fixed C-string diagnostics on invalid receivers,
exceptions, or empty descriptions. A non-empty description is retained and
returned through `lossyCString`. `_NSPrintExtraRefCount` at `0x42575650`
formats the compact and map-table extra-retain counts into one allocation,
logs that buffer, and frees it. These debugger-print helpers depend on object
validation and the exception-handler internals, so they are not isolated
formatting wrappers. No implementation changes were made.

The target `_NSPrintExtraRefCount` walks `fewCounter`'s compact tagged-object
array, then enumerates `manyCounter` with `NSEnumerateMapTable` and
`NSNextMapEnumeratorPair`; both paths format
`Object 0x%x of class %s: extra RefCount = %d\n` before one `NSLog` call.
Current `NSZone.m` does not have those target tables: it stores low counts in
an open-addressed tagged-slot array and larger counts in a separate overflow
vector, exposed by `NSExtraRefCount`. An implementation would need to enumerate
those current structures while preserving the target's row format and log
behavior, and belongs with the private count state in `NSZone.m`.

### `_decodeFastByte` implementation (2026-10-04)

Added `decodeFastByte` to `NSSerialization.m` using the IDA-confirmed decoder
context layout: an opaque owner pointer followed by the cursor and end
pointers. It raises `NSInternalInconsistencyException` with the recovered
message when the cursor is beyond the end pointer, then reads and advances one
unsigned byte. The ABI and symbol maps now claim `_decodeFastByte`, and source
ownership is recorded. The reference symbol audit now reports 24 unclaimed
exports. No tests or builds were run.

### `_NSsnprintf` implementation (2026-10-04)

Added the IDA-confirmed variadic wrapper to `NSObjCRuntime.m`. It forwards
the format and `va_list` to `vsnprintf` and returns that result. The ABI and
symbol maps now claim `__NSsnprintf`, with source ownership recorded. The
reference symbol audit now reports 22 unclaimed exports. No tests or builds
were run.

### `_NSParseStringsFile` implementation (2026-10-04)

Implemented the IDA-confirmed exported strings-file parser in `NSBundle.m`.
It reads serialized property lists through the existing binary path, selects
Unicode for UTF-16 BOMs and the default C-string encoding otherwise, and
returns `nil` only for the parser's syntax exception while rethrowing other
exceptions. `NSBundle` keeps its dictionary-only caller contract in a wrapper.
The ABI and ownership manifests now claim the export. No tests or builds were
run.

### `__NSToDoAtLastThreadExit` teardown scope (2026-10-04)

IDA decompilation of `__NSToDoAtLastThreadExit` at `0x42571898` confirms it
first calls `+[NSRunLoop _taskNowSingleThreaded]`, then releases and clears 32
Objective-C lock globals, including `_NSSimpleHashingLock`, in a fixed order.
It then frees and clears four separately allocated low-level lock blocks:
`__NSDebugRecordLock`, `__NSAllocatorLock`, `__NSRefCountLock`, and
`__NSSequenceLock`. IDA reports no direct in-image code-call xrefs to the
export, so its lifecycle trigger is not established by this database. The
source still has no implementation or ownership entry for this export; any
reconstruction needs the complete teardown set and should not invent a
`-[NSThread _exit]` call based on the export name alone.

### `_NSDeserializeObject` export (2026-10-04)

IDA's `__NSDeserializeObject` at `0x42509a48` is the recursive serializer
decoder: the six stack arguments carry the serializer, data, cursor,
mutable-container flag, allocation zone, and lazy threshold. Its callers
include both `NSDeserializer` entry points and the lazy array/dictionary fault
paths. `NSSerialization.m` already had this full switch-based decoder as a
file-local function, with matching recursive calls. It is now externally
linked under the reference name, and the ABI, symbol, and ownership manifests
claim the Mach-O export. Decoder behavior did not change. No tests or builds
were run.

### `_NSParseStringToGenericURLComponents` export (2026-10-04)

IDA at `0x4259596c` confirms the generic URL range parser's ten-argument
contract and component order: scheme, user, password, host, port, path,
parameters, query, and fragment follow the input string. `NSURL.m` now exports
that function and routes its internal component parser through the same scan.
The implementation follows IDA's first-`@` and first-colon user/host parsing,
stops authority at slash, then cuts fragment, query, parameters, and path in
the recovered order. The ABI, symbol, and ownership manifests claim the
export. No tests or builds were run.

### `_NSCStringToDecimal` implementation (2026-10-04)

IDA at `0x425a2950` confirms `_NSCStringToDecimal` parses ASCII whitespace,
an optional sign, decimal digits, a decimal point, and an optional signed
`e`/`E` exponent into `NSDecimal`. `NSDecimal.m` now implements that path
using the existing `NSIntegerMultiplyByShort`, `NSIntegerAddShort`, and
`NSDecimalCompact` routines. It preserves the reference's end-pointer rules,
precision overflow behavior (discarding excess integer digits by increasing
the exponent), and NaN result on mantissa or exponent overflow. ABI, symbol,
and ownership entries claim the exported `__NSCStringToDecimal`; the static
symbol audit now reports 11 unclaimed exports. JSON parsing and `git diff --check`
passed. No tests or builds were run.

### `_NSScanDecimalFromString` implementation (2026-10-04)

IDA at `0x425a3020` confirms this scanner helper skips the supplied character
set, rejects an unskipped ASCII whitespace character, and gathers the numeric
token from 32-character Unicode chunks. Its numeric set is `+`, `-`, digits,
`E`, and `e`; the locale decimal separator is copied as `.`. The collected
token is parsed through `_NSCStringToDecimal`, and the scan location advances
only when that parser consumes at least one byte. `NSScanner.m` now exports
the helper and routes `-scanDecimal:` through it. ABI, symbol, and ownership
manifests claim the export; the static symbol audit reports 10 unclaimed
exports. JSON validation and `git diff --check` passed. No tests or builds were
run.

### Locale comparator symbol ownership correction (2026-10-04)

The first registration used `__NSCompareStringsWithLocale`, but a fresh audit
against the exact `Foundation-i386` profile showed the reference export is
`_NSCompareStringsWithLocale`. In this source tree the corresponding C
identifier is `NSCompareStringsWithLocale` (without the Mach-O leading
underscore). Renamed the local declaration, definition, and call accordingly,
and aligned the ABI and symbol maps. The ownership key remains the Mach-O
symbol. The reference symbol audit now reports 9 unclaimed exports, down from
10. ABI, symbol-map, ownership JSON parsing, and `git diff --check` passed; no
tests or builds were run.

### `_NSRecordAllocationEvent` switch and message path (2026-10-04)

Decoded the 25-entry relative jump table at `0x425713cc` from raw IDA bytes;
the existing database marks the switch body as data, so the normal listing
does not render the target instructions. The entries are indexed by the event
IDs in `NSDebug.h`. IDs 0, 2, 4–10, and 16–24 have per-event setup blocks;
IDs 1, 3, and 11 enter the shared block at `0x4257158f`; IDs 12–15 branch to
the function epilogue at `0x42571820`. Specific setup addresses are 0→
`0x42571430`, 2→`0x42571468`, 4–7→`0x425714b0`, 8–9→`0x425714e8`, 10 and
20→`0x42571530`, 16→`0x425714f8`, 17→`0x42571508`, 18→`0x42571514`, 19→
`0x42571501`, 21→`0x4257153c`, 22→`0x42571548`, 23→`0x42571564`, and 24→
`0x4257157e`. The shared block prepares the timestamp and message fields,
walks frames using `_NSFirstFrameAddress`, `_NSNextFrameAddress`, and
`_NSReturnAddressFromFrameAddress`, and caps the stored trace at 0x398
addresses. It sends through `_msg_send`; when that returns `-0x67`, it retries
with the alternate `0x20` option before clearing the record lock. Existing
`NSWaitForAllocationEvent` and `NSParseAllocationEvent` provide the receiver
side layout and decoding path in `NSDebug.m`. No source implementation was
changed; individual event-field assignments still need to be reconciled with
the parser's word offsets before implementing the sender.

### `_NSRecordAllocationEvent` wire-field reconciliation (2026-10-04)

The sender buffer starts at `[ebp-0x1db8]`, the address passed to `_msg_send`.
This matches `NSWaitForAllocationEvent`'s 7,608-byte receive buffer: the sender
copies 0x76e dwords from its static message template before overwriting event
fields. `NSParseAllocationEvent` confirms the wire-word mapping: words 39/40
are the two timestamp halves; 42 is sequence number; 43 is event type; 44 is
allocation size; 45 is backtrace count; 50–57 are the event struct's thread,
zone, pointer, and data fields; words 7–38 hold the 128-byte class field; and
backtrace pairs begin at words 62–63. The sender assigns size from local
`-0x1dd4`, zone from `-0x1de4/-0x1de0`, pointer from the first variadic
argument, and data from `-0x1ddc/-0x1dd8`. It increments the sequence counter
at context offset `0x9107b`, gets the thread identifier from
`_ur_cthread_self()+4`, and gets the timestamp from `__NSCurrentTime`.

The handler assignments further constrain event payloads. Events 0 and 2
derive the zone with `_NXZoneFromPtr`; event 0 uses its object and event 2 uses
the copied-to object. Both calculate size as the object's class instance size
plus the extra-byte argument. Events 4–7 store the receiver's `retainCount` in
the data field. Events 16–19 take the zone from variadic argument 2 and the
size from argument 3 where applicable; event 18 also stores argument 4 in the
data field. Event 20 stores argument 2 as size; 21 stores argument 2 as size;
22 stores argument 2 as size and argument 3 as data; 23 stores the zone,
start size, and granularity in zone, size, and data; 24 stores the zone. These
assignments match the existing `NSZone.m` callers, which pass a zone argument
for events 16–19 even though the older prototypes in `NSDebug.h` omit it for
malloc and calloc. Events 12–15 remain unsupported jump-table slots that go
straight to the epilogue.

The class field is cleared first. Object events obtain the name through the
object's class pointer and copy at most 127 bytes; events 8–9 leave it empty,
and events above 15 skip the object-class path. Events 10–11 copy from the
pointer at `[ebp+0x14]`. That is the class-name argument for event 10, but the
third variadic argument for event 11 according to the public prototype, so
event 11's machine-code behavior conflicts with the documented
`(curJavaObj, className, javaStackTrace)` ordering. The Java event prototypes
have no call sites in this Foundation image to resolve that discrepancy. The
Event 11's machine-code behavior and the record-lock lifecycle still need
review before implementation.

The static template at `0x425a45bc` is 7,608 bytes and has only four nonzero
dwords: word 0 bytes `00 00 00 01`, word 6 `09 08 88 10`, word 41
`02 20 07 10`, and word 49 `0a 40 9e 13`. The sender overwrites the message
size at word 1 with `0xf8 + 8 * backtraceCount`; the receiver's maximum buffer
matches the template copy size. The record mutex pointer is allocated with
`calloc(1, 8)` in `__NSToDoAtFirstThreadStart` and freed by
`__NSToDoAtLastThreadExit`. The current `NSThread.m` initializes only
`__NSSequenceLock`, so allocation-event reconstruction also requires adding
the record-lock lifecycle at those existing thread hooks. The sender uses
`msg_send(buffer, 1, 0)` and retries with `msg_send(buffer, 0x20, 0)` only when
the first result is `-0x67`.

### `_NSAutoreleasePoolCountForObject` dependency (2026-10-04)

The negative-retain branch calls `_NSAutoreleasePoolCountForObject` at
`0x425751bc`. IDA shows it obtains the current thread's autorelease-pool list
from offset `+24`, visits each linked pool, and counts entries whose object
pointer matches the argument. No source definition exists in the current tree.
Because an Objective-C instance has its `isa` word at offset 0, `+24` is the
`autoreleasePool` ivar declared in `NSThread.h`, not `doQueue`.
`NSAutoreleasePool.m` already exports `NSAutoreleasePoolCountForObject`, but it
counts over this reconstruction's process-global pool stack. Reusing it under
the private underscore name would match the current single-threaded pool
storage, while preserving target per-thread behavior requires first
reconstructing the thread-owned pool list. This dependency constrains the
negative-retain portion of `_NSRecordAllocationEvent` and should be explicit
in its design.

Further IDA cross-checking resolves the target layout: `_NSCurrentThread`
returns the `NSThread` instance, and the word at offset `+24` is its
`autoreleasePool` ivar after the `isa` word. `NSPushAutoreleasePool`,
`NSPopAutoreleasePool`, and `NSAutoreleaseObject` all use the same per-thread
AP-data pointer. The AP-data header stores the page-list head at offset 0,
total autoreleased count at 4, high-water mark at 8, resolution at 12, pool
depth at 44, and 12-byte pool records starting at 48. `_NSAPDataCreate`
allocates 0x90 bytes for the header and eight initial records, copies the two
high-water settings, stores release and freed-object-check flags at bytes 16
and 17, sets pool capacity to 8, and starts with depth zero. Each page uses
words 0–2 for backward link, forward link, and object count; objects start at
byte 12. `_NSAPAddPage` recycles the free-page list at header offset 20 or
allocates one `__NSPageSize` page, then links it at the page-list head. This
confirms that the source's process-global pool stack is a substitute, rather
than an alternate representation of the target layout; a direct rewrite of
the pool machinery is out of scope for the allocation-event sender, so its
negative-retain helper needs to use the existing substitute while recording
the multi-threaded divergence.

### `_NSWalkData` mode and aggregate contract (2026-10-04)

Re-decompiled `_NSWalkData` at `0x4251db30` and its three wrapper functions.
The five-argument walker takes `(mode, recurse, context, value, type)` and
returns the consumed in-memory size. `__NSParseAndAutorelease` at
`0x4252e978` invokes mode 4 with recursion enabled; `__NSParseAndRelease` at
`0x425761a4` invokes mode 2; `__NSParseAndRetain` at `0x425761c0` invokes mode
3. These wrappers have no callers in the loaded image.

Mode 0 is fast decoding: scalar integers use `decodeFastInt`, byte and short
encodings use direct byte reads, and `#`, `%`, `:`, `*`, and `@` use their
special encoded forms. Class and selector names are interned through
`_NSUniqueCString`; class lookup falls back to `_NSAltClassNameFromString`.
Mode 1 writes through a context callback. Modes 2, 3, and 4 release, retain,
and autorelease object values; the `*` pointer handler frees the pointed-to
zone allocation in mode 2, duplicates it in the default zone in mode 3, and
constructs an `NSData` in mode 4. Qualifiers `N`, `V`, `n`, `o`, and `r` are
skipped; `O` and `R` set by-copy and by-reference flags for subsequent object
handling.

The local, non-exported `decodeFastInt` at `0x42517540` reads a signed-byte
marker, uses its magnitude as the payload byte count, copies that many
little-endian bytes, and sign-fills the remainder of the requested width.
Marker-read and payload-span failures call `rareBug` with codes 1 and 2;
payloads wider than the destination take the decoder's invalid-width
exception path. The current `NSDataReadFastInteger` has the same compact
integer representation but raises on width mismatch and relies on `NSData`
range exceptions rather than the target decoder context's end pointer.

Arrays recurse over each element using its ABI element size and require a
closing `]`. Structs skip the name through `=`, align each field using
`NSGetSizeAndAlignment`, delegate bitfields to `getBitfieldSize` and
`walkBitfields`, and round the final size to the maximum field alignment.
Pointer encodings are ignored when `recurse` is false; otherwise only mode 0
and mode 1 traverse their pointee. The mode-1 pointer-object branch requires
an `@` pointee and selects `O@`, `R@`, or the encoded pointee form based on
qualifiers.

`NSSerialization.m` already has a related `NSWalkObjCType`, but it is scoped
to modes 0/1 with a boolean serialization flag and its own `root` pointer
policy. It cannot directly stand in for the recovered walker: it lacks the
ownership-only modes, `recurse` control, fast-decoder context, class-name
fallback, and the target's exact pointer branches. This confirms the gap is a
separate C helper with meaningful cross-file dependencies, rather than a
missing alias for the existing serializer. No source implementation was
changed.

### `_NSPrintForDebugger` implementation (2026-10-04)

Implemented `_NSPrintForDebugger` in `NSDebug.m` following IDA at
`0x42570f58`. It checks readable object memory and validates either the
object's `isa` or the input itself against `objc_getClasses()`, catches an
exception from `debugDescription`, and preserves the cached description's
retain/release lifetime and debugger status strings. Registered the
`__NSPrintForDebugger` export in the NSDebug ABI and symbol manifests and
recorded source ownership. The exact-profile symbol audit now reports eight
unclaimed exports, down from nine. JSON parsing and `git diff --check` passed;
no tests or builds were run.

### `_NSPrintExtraRefCount` implementation (2026-10-04)

Implemented `_NSPrintExtraRefCount` inside `NSZone.m`, which owns this
reconstruction's extra-reference table. The helper walks occupied tagged
slots, resolves each count (including overflow entries), formats the target's
`Object 0x%x of class %s: extra RefCount = %d` lines into a bounded buffer,
logs them together, and frees the buffer. Registered the
`__NSPrintExtraRefCount` export in the NSZone ABI and symbol manifests and
recorded source ownership. The exact-profile symbol audit now reports seven
unclaimed exports, down from eight. JSON parsing and `git diff --check` passed;
no tests or builds were run.

### `_NSToDoAtLastThreadExit` source ownership recheck (2026-10-04)

IDA at `0x42571898` confirms this callback releases 32 Objective-C lock
globals and frees four raw mutex pointers: `__NSDebugRecordLock`,
`__NSAllocatorLock`, `__NSRefCountLock`, and `__NSSequenceLock`. A current
source search finds declarations/definitions for only 23 of the 36 names.
Thirteen names are absent from Foundation source: notification-center,
time-zone, logging, perform-timer, URL formatter, URL handler, natural-language,
placeholder-decimal-number, placeholder-value, and user-defaults locks, plus
the debug-record, allocator, and refcount mutexes. `NSThread.m`'s
`_NSToDoAtFirstThreadStart` initializes only a subset of the target lock set,
and there is no source definition of `_NSToDoAtLastThreadExit`. The exit export
therefore depends on reconciling these lock owners and the first-thread
allocation lifecycle; adding only a cleanup loop would leave target-owned lock
state unrepresented. No source changes were made.

IDA's first-thread hook at `0x425547f8` confirms the paired lifecycle: it
allocates all four raw mutexes, runs eight class initialization hooks, creates
the 32 lock objects (including the 13 whose globals are absent from this
Foundation source tree), and calls `+[NSRunLoop _taskNowMultiThreaded]`.
The current `_NSToDoAtFirstThreadStart` only allocates `__NSSequenceLock`,
creates its represented subset of lock objects, and does not call those class
hooks or the run-loop transition. This makes reconstruction of either thread
hook dependent on the shared lifecycle rather than an isolated exit callback.

The only code caller of the first-thread hook is
`+[NSThread detachNewThreadSelector:toTarget:withObject:]` at `0x42558f94`.
It runs after `objc_setMultithreaded(true)` and setting `_NSIsMultiThreaded`,
but before posting `NSWillBecomeMultiThreadedNotification`, switching malloc
out of single-threaded mode, and forking/detaching the new thread. IDA reports
no code callers of `_NSToDoAtLastThreadExit`; adding teardown to an inferred
thread-exit path would therefore invent a lifecycle edge not present in this
database. The current source uses the same first-start ordering.

### Allocation-event call-site recheck (2026-10-04)

IDA cross-references show the allocation-event sender body at `0x42571124` is
reached through the exported entry at `0x4256fae4`. Its only in-image callers
are `__NSDecrementInternalRefCountWasZero` at `0x42506554` and
`__NSIncrementInternalRefCount` at `0x4250b348`. Their call sites pass event
7 and event 6 respectively, both with the object receiver. No in-image caller
passes events 10 or 11, so the Java event-11 argument discrepancy remains
unresolved rather than being contradicted by a call-site example. This narrows
the exercised sender path but does not justify omitting the other exported
event cases from a faithful reconstruction.

### `_NSWalkData` entry-context recheck (2026-10-04)

IDA callers at `0x42575dfc` (`-[NSData deserializeDataAt:ofObjCType:atCursor:context:]`)
and `0x42575e94` (`-[NSMutableData serializeDataAt:ofObjCType:context:]`)
confirm the context layouts consumed by `_NSWalkData`. Deserialization places
the `NSData` object at offset 0, the byte cursor at offset 4, the data end at
offset 8, zeroed words at offsets 12 and 16, the caller callback at offset 20,
and zeroed flag bytes at offsets 24 and 25. After mode 0 returns, the caller
stores `cursor - bytes` through its cursor argument.

Serialization places the mutable data object at offset 0, zeroes offsets 4,
8, and 12, stores `NSDataFuncList` at offset 16, the caller callback at offset
20, and zeroes the same two flag bytes. Mode 1 uses function slots at table
offsets 0, 4, and 8 for byte, width-bearing scalar, and pointer/name writes.
For object encodings, offset 24 selects the bycopy/byref callback path; without
that flag it uses the ordinary object-at/type/data callback. These entrypoints
show that the existing `NSWalkObjCType` methods have different context
contracts even where the Objective-C encodings overlap. No source changes were
made; the approval-gated `_NSWalkData` implementation remains untouched.

### Allocation-event dispatcher lift limitation (2026-10-04)

The current IDA pseudocode for `__NSRecordAllocationEvent` at `0x42571124`
does not expose the event payload switch: it only shows the `event <= 0x18`
guard and an indirect `jmp edx`. The disassembly computes that target from a
position-independent offset table indexed by the event number, but IDA
currently presents the table and following handler bytes as data in the
function listing. This confirms that the earlier per-event payload analysis
cannot be completed from the decompiled switch alone; the jump targets and
their variadic argument reads must be recovered before implementing the
sender. No source changes were made.

### Allocation-event class-name field trace (2026-10-04)

Decoded the switch targets and shared block with `db.instructions.get_at` and
raw bytes; the IDA database was not modified. Events 8 and 9 branch around
class-name extraction. Events 10 and 11 share the direct-string path at
`0x4257167f`: it reads a C string from `[ebp+0x14]`, computes its length, caps
the copied length at 127 bytes, and copies it into the record's 128-byte class
field. Other eligible object events take the class-name path at
`0x425716ac`, reading the object's class name through `isa + 8`, also capped
at 127 bytes.

This confirms the event-11 prototype discrepancy against the actual shared
machine code. With `eventType` at `[ebp+8]`, the header documents event 10 as
`(newJavaObj, size, className, javaStackTrace)` and event 11 as
`(curJavaObj, className, javaStackTrace)`. The `[ebp+0x14]` slot is event 10's
`className`, but event 11's `javaStackTrace`; the target therefore writes the
stack-trace pointer's C string into the class field for event 11. No in-image
callers exercise events 10 or 11, so there is no call-site evidence that
resolves this target behavior into a different intended ordering. Preserve
the machine-code behavior if the sender is implemented; do not silently
correct it to the header comment. No source changes were made.

### Allocation-event sender control flow (2026-10-04)

IDA decompiles the exported `NSRecordAllocationEvent` entry at `0x4256fae4` as
a call to `__NSRecordAllocationEvent`. Its wrapper loads and forwards the
event word plus four following argument words from the original stack before
calling `0x42571124`, so the Java and zone event arguments remain available to
the body. The sender first performs the negative-retain check only for event
types 3, 5, and 7 when
`NSNegativeRetainCheckEnabled` is set: it subtracts
`_NSAutoreleasePoolCountForObject(object)` from `-retainCount`, subtracts one,
and calls `_NSNegativeRetain` for a negative result. It then checks
`(1 << eventType) & NSAllocationStatisticsOutputMask`. When that mask is
disabled, it returns without taking the record lock or resolving the output
port. Otherwise it tries `__NSDebugRecordLock` and waits only if the try-lock
fails.

With the lock held, a zero `sending_event_port` triggers lazy lookup of
`NSAllocationStatisticsOutputPortName`. A `mach-port://host/name` value is
split into host and name; other values pass the empty string as the host name
(the default pointer is `0x425f9e2e`, a NUL byte in the image). Lookup calls
`netname_look_up` using
`__NSMachNMServerPort`'s Mach port and clears `sending_event_port` on error.
The event is serialized and sent only when the resulting port is nonzero.
The sender copies the 7,608-byte message template, captures frame return
addresses up to 0x398 entries, sets message size to `0xf8 + 8 * traceCount`,
and calls `msg_send(buffer, 1, 0)`. Only result `-0x67` triggers a retry with
option `0x20`. The lock word is cleared on the common exit path.

The current source already has the event receiver/parser and output-port
set/get functions, plus the three frame-walking helpers. Reconstructing the
sender still requires defining its record-lock lifecycle and resolving the
per-thread autorelease-count helper; `NSAutoreleasePoolCountForObject` is only
a process-global substitute in the current pool implementation. No source
changes were made.

### Remaining exported C-symbol audit (2026-10-05)

Re-ran `binrecon symbol-audit` against the current `Foundation-i386` profile and
source symbol map. Seven exported functions remain unclaimed:
`_NSRecordAllocationEvent`, `__NSParseAndAutorelease`, `__NSParseAndRelease`,
`__NSParseAndRetain`, `__NSStandardizePath`, `__NSToDoAtLastThreadExit`, and
`__NSWalkData`. The three parse wrappers delegate to `_NSWalkData`, whose
implementation is explicitly approval-gated; `_NSStandardizePath` is also
approval-gated. `_NSToDoAtLastThreadExit` has no code callers in the loaded
image and participates in a shared thread-lock lifecycle. The allocation-event
sender is IDA-documented, but depends on that lifecycle and a per-thread
autorelease count while the current source pool storage is process-global.
These remaining exports therefore need their existing approval gates or the
underlying pool/thread design resolved before implementation.

### Autorelease-pool public-method recheck (2026-10-05)

Fresh decompilation of the public pool methods confirms that `-initWithCapacity:`
pushes a pool token, writes the pool object into the depth record at AP-data
offset `56 + 12 * depth`, and sets byte 19 to distinguish the base pool class
from subclasses. `-release` delegates directly to pop with that token. The
decompiled initializer does not pass its capacity argument to the push helper.
`+autoreleasePoolExists` reads depth at offset 44; total and top counts delegate
to the AP-data helpers. High-water mark and resolution are per-thread words at
offsets 8 and 12, and the release/freed-object-check switches are bytes 16 and
17.

Pop drains each page back to the pool's saved page/count checkpoint, in reverse
insertion order, decrements the AP-data total, and brackets object releases
with an exception handler. A release exception is logged; nested pool objects
are then deallocated, and empty pages are detached and linked onto the AP-data
free-page list after their payloads are cleared. `+releaseAllPools` pops token
zero, clears the current thread's AP-data pointer, deallocates active and free
pages, releases the four cached AP-data objects at offsets 24 through 36, and
frees the AP-data block. This confirms a faithful source rewrite must preserve
exception handling, nested-pool teardown, page recycling, and thread cleanup,
not only replace the global frame array with a page list.

The full pop path also recycles up to four exact `NSAutoreleasePool` instances
in AP-data slots at offsets 24, 28, 32, and 36. Pool subclasses bypass those
slots and are deallocated; the AP-data byte at offset 19 is restored from the
remaining top pool's class behavior after nested records are cleared. The
target `-release` only calls pop, which owns this recycling/deallocation
decision. The current source's explicit `NSDeallocateObject(self)` after pop
is therefore a known mismatch to correct as part of a faithful storage rewrite.

`+[NSAutoreleasePool allocWithZone:]` uses the four cached instances only for
the exact base class, taking the first non-null slot at offsets 24 through 36;
subclasses are allocated in the requested zone. If no cached base instance is
available, the target allocates it in the default zone. `_NSAPDataCreate`
allocates 0x90 bytes, initializes eight 12-byte records, and copies default
high-water, release, and freed-object-check settings into the per-thread block.
`__NSAPAddPage` takes the next page from the free list when possible, otherwise
allocates one `__NSPageSize` page, then links it at the page-list head. The
current source allocates every pool object and every frame buffer afresh, so
both object and page reuse belong in the design scope.

### `Object(NSCompatibility)` approved-slice body recheck (2026-10-05)

Compared the 32 approved `Object` class and instance methods in
`NSCompatibility.m` against their current IDA bodies. The legacy forwarding
selectors, default-zone handling, `awake` / `finishUnarchiving` sequence,
retain-count helpers, extra-reference release path, and coder replacement
behavior match the decompiled calls and return paths. No discrepancy was found
in this slice; no source changes were made.

### `NSUserDefaults` exported data-symbol coverage (2026-10-05)

The exact-profile function audit does not cover exported data. A separate
read-only comparison found 30 `NSString * const` globals already defined at
the top of `NSUserDefaults.m` and exported by the reference in
`__DATA,__const`, but absent from both the module ABI's `data_symbols` and
`symbols.json`. Added those 30 exact Mach-O names to `NSUserDefaults.json` and
the `NSUserDefaults.m` symbol assignment. Static checks confirmed all 30
source declarations map to one exported reference symbol, each appears once in
the ownership list, the ABI list matches the source set exactly, and the JSON
list is sorted. `git diff --check` passed; no tests or builds were run.

The same exported-constant sweep found 21 more source-defined globals missing
from the module ABI and symbol assignment across `NSArchiver`, `NSBundle`,
`NSConnection`, `NSDecimalNumber`, `NSDistributedNotificationCenter`, `NSPort`,
`NSThread`, `NSTimeZone`, and `NSUndoManager`. Added the confirmed constants to
their module ABI files and `symbols.json`. A follow-up scan of all Foundation
`.m` files reconciled 116 exported `NSString * const` globals across 15 module
ABIs with zero missing or duplicate symbol-assignment entries. `git diff --check`
passed; no tests or builds were run.

Also assigned ten other existing data definitions that were exported by the
target: the bundle, character-set, and port-coder locks; six thread globals
(`_NSIsMultiThreaded`, `_NSSequenceLock`, and four lock pointers); and
`NSURLFileScheme`. Their ABI and symbol-map entries match the definition
owners and exact external Mach-O names. Static reconciliation found no missing
or duplicate entries; no runtime source changed.

### Missing public string globals restored (2026-10-05)

IDA's exported data symbols include `NSDefaultRunLoopMode`,
`NSParseErrorException`, and `NSCharacterConversionException`, but their source
headers had declarations without definitions. Reading each target constant
object confirmed the string contents equal the symbol names (lengths 20, 21,
and 30). Added the three definitions to `NSRunLoop.m` and `NSString.m`, and
registered each in its module ABI and symbol assignment. Static checks verified
one source definition and one matching reference export per name; no tests or
builds were run.

### `NSBundle` exported metadata-key globals (2026-10-05)

The target exports nine additional `NSBundle` data symbols whose exact string
values match the keys already used in `NSBundle.m`: the initial, resolved,
executable, and resource paths; languages list; defaults dictionary; string
table table; resources; and `NSExecutable`. IDA's constant objects confirm
each value and length. Added the nine `NSString * const` definitions and
registered their exact Mach-O names in `NSBundle.json` and `symbols.json`.
Static checks confirmed one definition and one ABI/assignment entry for each;
no tests or builds were run.

### Canonical empty string export (2026-10-05)

The target's `___NSEmptyString` global points to a zero-length constant string
object whose `isa` is the target's `NSConstantString` class reference. The
source already declared and used this global throughout NSString and
serialization code but had no definition. Defined it as the address of the
empty string literal in `NSConstantString.m` and registered the data export in
its ABI and symbol assignment. Static checks confirmed one definition, the
exact external name, and one ABI/assignment entry; no tests or builds were run.

### Dictionary property-list and file identifier globals (2026-10-05)

IDA confirms five exported `NSDictionary` operation-name constants and the
`NSFileIdentifier` key are string objects whose contents equal their symbol
names. Added the five definitions to `NSDictionary.m` and the file-identifier
definition alongside the existing file-attribute keys in `NSFileManager.m`.
Registered all six in their ABI and symbol-assignment metadata. Static checks
confirmed their values against the IDA objects and found one matching source,
ABI, and assignment entry per export; no tests or builds were run.

The updated data-symbol pass now reconciles 134 source-defined
`NSString * const` globals with exported symbols, module ABI entries, and unique symbol
assignments. Four additional `NSJavaSetup` header constants have no export in
this target and remain outside this audit. The canonical `___NSEmptyString`
pointer also matches its external `__DATA,__data` symbol. The static check found
no metadata issues; no tests or builds were run.

### Foundation Objective-C selector coverage audit (2026-10-05)

Ran `selector_check.py` against the current `Foundation-i386` reference and
`src/Kits/Foundation`. The reference contains 3,253 Objective-C selectors and
the source contains 3,300 method definitions. The audit reports no missing
reference selectors, no selector renames, and no duplicate definitions; it
reports 47 source definitions without a matching selector in this target.
Those extras need individual version-scope disposition before any source
removal, since this name-level comparison does not establish whether a method
is an intentional compatibility addition or an implementation mismatch. No
tests or builds were run.

### `_NSStandardizePath` raw i386 signature check (2026-10-05)

Decoded the target bytes with Capstone from the verified `Foundation-i386`
image. The function spans `0x425179bc–0x42517f47` (1,419 bytes; SHA-256
`6774770c0423c2dec7203770f91819fc3796b2d6e1ac2ac0d5753bf885be8501`). Its
entry reads the path buffer at `[ebp+8]`, the in/out length pointer at
`[ebp+0xc]`, and integer capacity at `[ebp+0x10]`, confirming
`int _NSStandardizePath(unichar *, unsigned *, int)`. The early capacity
failure returns the initial slash/trailing-cleanup flag; normal completion
returns `1`. This resolves the signature and return edge previously left for
reconfirmation. Raw disassembly of all four callers confirms 1,024-unit stack
buffers and capacity `0x400`. Both generic `NSString` wrappers clamp their
copied input length to 1,024; the two `NSPathStore2` wrappers copy at most
1,024 units but pass the stored length through unchanged. All four return via
`+[NSPathStore2 pathStoreWithCharacters:length:]`; the resolving wrappers call
`_NSResolveSymlinksInPath` before the standardizer. No source code changes,
tests, or builds were made.

### `NSStringEncodings` converter function pointer export (2026-10-05)

The current `NSStringEncodings.m` already defines the external data global
`_NSCStringCharToUnichar` as a pointer to `NSMacOSRomanToPrecompUnicode`.
The target's `__NSCStringCharToUnichar` at `0x42602714` stores the exact
address of `_NSMacOSRomanToPrecompUnicode` (`0x42591650`). Added the data
symbol to `NSStringEncodings.json` and its source-symbol assignment. No tests
or builds were run.

### `NSUserDefaults` exported lock global (2026-10-05)

The external data symbol `__NSUserDefaultsLock` at `0x4260202c` corresponds to
the defaults subsystem's lazily initialized process lock. `NSUserDefaults.m`
already held that lock as a file-static `NSUserDefaultsLock`; renamed the
storage to the matching C identifier `_NSUserDefaultsLock` and gave it
external linkage without changing its initialization or lock sites. Added
`__NSUserDefaultsLock` to the module ABI and source-symbol assignment. No
tests or builds were run.

### `NSBundle` exported lazy-state and principal-class globals (2026-10-05)

The target exports four zero-initialized byte globals at `0x426024a8–0x426024ab`
for dynamic-class-load and safe-bundle-loading state. `NSBundle.m` already had
the same four lazy flags as file-static variables, so exposed them with the
target C identifiers while preserving their state transitions. The target's
`_NSPrincipalClass` at `0x426032e0` points to a constant-string object whose
contents are exactly `NSPrincipalClass`; added the exported string global and
used it at both existing dictionary-key sites. Registered all five in the
NSBundle ABI and source-symbol assignment. No tests or builds were run.

### Exported Foundation cache-lock globals (2026-10-05)

Five target `__DATA,__data` exports correspond to existing file-static cache
locks: `__NSNotificationCenterLock` (`NSNotification.m`, `0x42602380`),
`__NSTimeZoneLock` (`NSTimeZone.m`, `0x42602394`),
`__NSPerformTimerCacheLock` (`NSPerformTimer.m`, `0x4260239c`),
`__NSNaturalLanguageCacheLock` (`NSCalendarDate.m`, `0x426023b4`), and
`__NSPlaceholderDecimalNumberLock` (`NSDecimalNumber.m`, `0x426023bc`). Exposed
the corresponding source storage under the target C identifiers without
changing lazy initialization or lock sites, then added each Mach-O name to
its module ABI and symbol assignment. No tests or builds were run.

### Remaining external data-symbol inventory (2026-10-05)

Compared all reference external `__DATA,__data` and `__DATA,__const` symbols
against module ABI data-symbol entries. The image has 134 data-section and 145
const-section exports; 75 data-section entries remained unclaimed after
registering the converter pointer, defaults and cache locks, bundle flags,
and principal-class constant. Three more source-backed pointer globals are
now registered. `__NSLogLock` is also registered below. A fresh exact-name
comparison against IDA's current public names then found 72 unclaimed
data-section exports and no duplicate ABI owners. After the class-pointer
registrations below, the current exact-name comparison finds 19. IDA's
public-name bit is
misleading for `__NSUserDefaultsLock`: the exact symbol at `0x4260202c` is
nonpublic but has many code reads; `__NSUserDefaultsLock_0` at `0x426023c4` is
a separate lock slot initialized and released by the thread lifecycle hooks.
The remaining exports still need source-owner classification; this is an
ABI/source-assignment inventory, not a claim that each symbol needs a
hand-written global definition. No tests or builds were run.

### Exported distant-date and Mach name-server port globals (2026-10-05)

IDA identifies zero-initialized pointer exports `___NSDistantFutureDate`
(`0x42602344`), `___NSDistantPastDate` (`0x42602348`), and
`___NSMachNMServerPort` (`0x42602340`). The date slots have a single read and
write at their lazy factory paths (`0x4254aee8/0x4254af1f` and
`0x4254af28/0x4254af5f`); the port slot is initialized by
`_NSToDoAtProcessStart` at `0x4254afb3`. Exposed the corresponding existing
cached-object storage in `NSDate.m` and `NSPortNameServer.m` with matching C
identifiers, preserving initialization and return behavior. Added the three
Mach-O names to their module ABI and symbol assignments. JSON parsing and
`git diff --check` passed; no tests or builds were run.

### Exported recursive logging lock (2026-10-05)

IDA identifies `__NSLogLock` at `0x42602398` as a recursively initialized
lock. `_NSToDoAtFirstThreadStart` creates it with `+[NSRecursiveLock
allocWithZone:]`, and `_NSToDoAtLastThreadExit` releases and clears it; the
source thread-start hook had omitted this slot. Added the external
`_NSLogLock` storage and the IDA-confirmed first-thread initialization to
`NSThread.m`, and registered `__NSLogLock` in its ABI and symbol maps. No
logging call-site lock behavior was added because IDA shows no such data
references. JSON parsing and `git diff --check` passed; no tests or builds
were run.

### Process-start class-pointer globals (2026-10-05)

IDA decompiles `_NSToDoAtProcessStart` at `0x4254a77c` with 53 exported class
pointer slots. Each is initialized only when null by `objc_getClass` using the
class name corresponding to its `...Class` symbol; all 53 slots have reads and
writes in this startup function. Added the matching `Class` globals and
conditional lookups to `NSPortNameServer.m`, the source owner of the process
start hook, and registered all 53 Mach-O data names in that module's ABI and
symbol maps. This includes `NSURLFormatter`, for which this source tree has no
class implementation. At the time of this pass, the function's separate
class-init calls, empty-object creation, and eager distant-date initialization
remained to be reconstructed. The distant-date and empty-object follow-up work
is recorded below, and the six class-init calls were later resolved in
`_NSToDoAtProcessStart` class version initialization (2026-10-06).
The exact-name data export comparison now leaves 19 unclaimed symbols. JSON
parsing and `git diff --check` passed; no tests or builds were run.

### Process-start distant-date caches (2026-10-05)

IDA's `_NSToDoAtProcessStart` initializes `__NSDistantFutureDate` and
`__NSDistantPastDate` after the four empty-object slots and before port reset.
The two `objc_msgSend` calls use `initWithTimeIntervalSinceReferenceDate:` on
`__NSDistantDateClass`; their split i386 double arguments correspond to
`63113990400.0` and `-63113817600.0`. `NSDate.m` already implements
`+[NSDate distantFuture]` and `+[NSDate distantPast]` by allocating
`NSDistantDate`, initializing the same exported global slots with those exact
values, and returning the cached objects. Added these two calls to
`_NSToDoAtProcessStart` immediately before the existing port reset, preserving
the target's relative ordering without duplicating its date factory logic.
Source inspection and `git diff --check` passed; no tests or builds were run.

### Process-start empty collection slots (2026-10-05)

IDA allocates `__NSEmptyArray`, `__NSEmptyDictionary`, `__NSEmptySet`, and
`__NSEmptyStringArray` as zero-filled `NSConcreteArray`, `NSConcreteDictionary`,
`NSConcreteSet`, and `NSStringArray` instances in `_NSToDoAtProcessStart`. Added separate
exported globals and eager raw allocations from the IDA-resolved concrete
class pointers, then registered their Mach-O names in the corresponding module
ABIs and symbol map. IDA's data-xref lists show that these exported slots are
read and written only by the startup function, so the source's existing lazy
API singleton caches remain separate; wiring those caches to these globals
would not match the observed references. `NSConcreteSet` operations accept a
null hash-table pointer for its startup-created empty object. Source/metadata
checks and `git diff --check` passed; no tests or builds were run.

### Cheap port input counters (2026-10-05)

IDA's `_NSCheapPortSetAcceptInput` increments `__NSMsgReceiveCount` immediately
before `msg_receive` and `__NSMsgResizeCount` after each `NSZoneRealloc` for a
too-large message (`0x42518332` and `0x42518383`). Added the corresponding
32-bit source globals and increments to `NSRunLoop.m`, then registered both
exports in its ABI and symbol map. The source's existing null-port early
return remains before the receive counter, matching the target. Static source,
ABI, symbol-map checks and `git diff --check` passed; no tests or builds were
run.

### Process-start class initialization sends recheck (2026-10-05)

The six `objc_msgSend` calls at `0x4254adbc–0x4254ae50` target class-name
references for `NSString`, `NSMutableString`, `NSCountedSet`, `NSTimeZone`,
`NSNumberFormatter`, and `NSDateFormatter`, passing integer arguments
`1, 1, 1, 1, 4, 41`. All six use the selector reference `off_42608EBC`; its
stored value is `0x4140679c`, an address in a mapped System-image segment.
That slot is zero-initialized in the IDA image, and neither database resolves
its runtime selector name. The Foundation image's local `initialize` string
has no cross-reference from this selector slot. No source call was added
because the selector's identity and the purpose of its per-class argument
values remain unconfirmed.

A follow-up found `+[NSObject setVersion:]` at i386 `0x4252d020` and PPC
`0x42518548`; both bodies store the argument directly in the class record's
version field at offset `+12`. This confirms the matching method and semantics
exist in both Foundation images, but does not prove that the shared,
zero-filled selector slot used by the six startup sends resolves to
`setVersion:` at runtime. The existing source `setVersion:` calls therefore
remain consistent with the observed values but are not closed as an
IDA-confirmed match.

The i386 System database contains the C string `setVersion:` at
`0x4141d390`, referenced from three Objective-C metadata locations, while the
runtime selector slot `0x4140679c` has no static references in the System
database. The C-string evidence establishes selector metadata availability,
but still does not connect it to the Foundation startup slot.

### Refreshed external data-symbol inventory (2026-10-05)

Reconciled the current module `data_symbols` entries against IDA's public
names in the Foundation data range `0x42602000–0x42603fff`. Thirteen public
data exports remain unclaimed:
`__NSMsgSendCount`, `___NSMethodDescriptionForSelectorSignature`,
`___NSReleaseSignature`, `__NSURLFormatterRegistrarLock`,
`__NSURLHandlerRegistrarLock`, `__NSPlaceholderValueLock`,
`__NSUserDefaultsLock_0`, `___NSDebugRecordLock`, `___NSAllocatorLock`,
`___NSRefCountLock`, `__NSAltClassNameFromString`, `_NULL`, and
`_NSFastFuncList`. This corrects the earlier inventory's stale count of 19.

The formatter, handler, placeholder-value, defaults-suffix, debug, allocator,
and ref-count locks are initialized or released by the thread lifecycle hooks;
they remain in the broader lock-lifecycle scope. `__NSAltClassNameFromString`
is zero-initialized at `0x42602434`, has reads only in `NSClassFromString`, and
no Foundation-side writes. The current source has no corresponding global or
fallback call. `_NSFastFuncList` at `0x42602480` contains the address of
`_encodeFastByte` (`0x425186f4`) and is referenced through
`_NSFastFuncList_ptr` at `0x42602d98`. `__NSMsgSendCount`,
the two signature-named exports, and `_NULL` also have no data xrefs in this
database. No source or ABI changes were made in this inventory pass.

### `_NSFastFuncList` encoder table recheck (2026-10-05)

A fresh read of the public 16-byte object at `0x42602480` shows four function
pointers, in order: `_encodeFastByte` (`0x425186f4`), `_encodeFastInt`
(`0x42513fa8`), `_encodeFastCharStar` (`0x4251d764`), and `_encodeFastData`
(`0x42535fa0`). The byte, integer, and raw-data encoders share a context with
cursor, end, and buffer pointers at offsets 4, 8, and 12. The character-string
encoder also dispatches through the function-table pointer at context offset
16; it writes a presence byte, a fast length including the trailing NUL, and
the bytes. `NSSerialization.m` has related `NSSerializerAppendFastInteger`
and `NSSerializerAppendCString` helpers, but they operate through `NSMutableData`
and do not define this exported context table or its entry points. The source
and ABI owner for `_NSFastFuncList` remain unresolved; no code changes were
made.

### `NSClassFromString` fallback export follow-up (2026-10-05)

IDA decompilation of `_NSClassFromString` at `0x42517610` shows it obtains the
name by sending `-cString`, calls `objc_getClass`, and, on a miss, invokes the
function pointer in `__NSAltClassNameFromString` at `0x42602434` with the
original `NSString *` when that pointer is non-null. The pointer is zero in
the image, has no Foundation-side writes, and is read directly by this
function. `_NSWalkData` also uses it through the indirect symbol pointer
`__NSAltClassNameFromString_ptr` at `0x42602de4` while decoding the `#` type
encoding: after `objc_getClass` fails, it builds an `NSString` from the decoded
class name and calls the fallback.
The current `NSObjCRuntime.m` instead reads the project's constant-string
record directly and calls `objc_lookUpClass`; it has no fallback pointer.
This distinction matters because this runtime's `objc_getClass` invokes the
registered `objc_classHandler` on a miss, while `objc_lookUpClass` only probes
the class table. `NSSerialization.m` currently decodes `#` using
`objc_getClass` but omits the alternate-name fallback. Proposed source scope
is to match both target lookup/fallback paths and register the zero-initialized
function-pointer export in the `NSObjCRuntime` ABI, symbol, and ownership maps.
Awaiting design approval before source or manifest changes.

### Public code-function coverage follow-up (2026-10-05)

Compared the 445 C text symbols currently claimed by the Foundation ABI files
with IDA's public names in the Foundation image. Six named code functions in
the image are not claimed by those ABI/source-owner maps:

- `__NSStandardizePath` at `0x425179bc` (1,419 bytes), already covered by the
  separate standardization spec and plan.
- `__NSWalkData` at `0x4251db30` (2,923 bytes), with no corresponding source
  symbol implementation found by symbol search. The adjacent
  `NSData`/`NSMutableData` serialization category methods are implemented in
  `NSSerialization.m` using static `NSWalkObjCType`, but that walker is not yet
  proven equivalent to the target's operation-coded `_NSWalkData` helper.
- `__NSParseAndAutorelease` at `0x4252e978` (35 bytes),
  `__NSParseAndRelease` at `0x425761a4` (26 bytes), and
  `__NSParseAndRetain` at `0x425761c0` (26 bytes). Each is an IDA-confirmed
  wrapper around `_NSWalkData` with a distinct operation code.
- `_NSRecordAllocationEvent` at `0x4256fae4` (32 bytes) forwards its variadic
  arguments to the separate `__NSRecordAllocationEvent` implementation at
  `0x42571124` (1,826 bytes). The latter performs negative-retain checks and
  routes enabled events through a lazily resolved Mach port. The only source
  definition found is the aborting test link stub in
  `reconstruction/tests/link_stubs.m`; `NSDebug.m` has the related flags and
  port state but no event recorder.

The standardization and parser-wrapper slices have separate approval gates
already recorded in the active task history. The remaining `NSWalkData` and
allocation-event paths need source-level ownership/design analysis before
implementation; no source changes were made in this audit.

### Expanded public data-symbol coverage (2026-10-05)

Expanded the ABI comparison from the writable data range to all public
non-function names in the Foundation image (`0x42500000–0x42603fff`). Of the
299 data symbols claimed by the current ABI files, 21 public names are not
claimed by an ABI file or source-owner map:

`_YES`, `_dummyPad1`, `_NO`, `_dummyPad2`, `_nil`, `_Nil`,
`_lossyNEXTSTEPToASCIITable`, `___NSNumberSet`,
`__NSMsgSendCount`, `___NSMethodDescriptionForSelectorSignature`,
`___NSReleaseSignature`, `__NSURLFormatterRegistrarLock`,
`__NSURLHandlerRegistrarLock`, `__NSPlaceholderValueLock`,
`__NSUserDefaultsLock_0`, `___NSDebugRecordLock`, `___NSAllocatorLock`,
`___NSRefCountLock`, `__NSAltClassNameFromString`, `_NULL`, and
`_NSFastFuncList`.

The previous 13-name inventory covered only the writable data range; it is a
subset of this 21-name list. `__NSTimeZoneData` now has a matching ABI and
source-owner claim in `NSTimeZone.m`; its source layout is recorded below.
Other read-only objects still need source-owner checks before adding
definitions. No source or ABI changes were made in this expanded inventory
pass.

The initial source comparison confirmed all 497 names in order, but represented
them as a C-string pointer array. The packed-record reconstruction below
replaces that representation and gives the data symbol its target layout.

### `__NSTimeZoneData` packed-record reconstruction evidence (2026-10-05)

Reconstructed the target record layout from IDA at `0x425bbe54`. It starts
with count `497`, then 996 little-endian 32-bit offsets, then a 7,932-byte
packed, four-byte-aligned name area, followed by 233,222 bytes of embedded
zone data. The first 498 offsets address the names and terminate at `0x1efc`;
the next offset sequence starts with zero and is followed by the 497 cumulative
zone-data offsets, ending at `0x38f06`. The 3,984-byte offset table rebuilt
from `NSTimeZoneNameTable.inc` plus the leading zero and
`NSTimeZoneDataTable.inc` hashes to
`e020e98d62d662807a24682ed52e43f4435351071dedad98d912929dc799dcc6`, matching
IDA. Four-byte-padded source names hash to
`97018f7239d38390b94afac0cc20d755e2d8b2e2b6d8ed4f9fb5e1b5f312135e`, also
matching the target name area; the source embedded-data array is 233,222 bytes
and hashes to `317ef7fb6e0070dc82c13f17e0fd9a332f559e404808fc314cf708cf16632453`,
matching the target data payload.

The next named object begins 26 bytes after the reconstructed header, offsets,
names, and payload. Those trailing bytes are
`000000000000000000803f40000000000000000000803f400000`. A C struct with this
layout naturally pads the 245,142-byte payload to four-byte alignment; that
padding matches the first two target bytes. The remaining 24 bytes have no
xrefs and remain outside the exported record. The generated initializer's
245,142 serialized bytes hash to
`f2cafa4ef931aa18ae5c345f8e766d88076b0300bd62ca89566701750b2386a9`, matching
IDA. `NSTimeZone.m` now exports the packed record as `__NSTimeZoneData` and
routes canonical-name and embedded-data lookup through it. ABI, symbol-map,
and source-ownership records include the export. Static initializer and JSON
checks passed; no tests or builds were run.

### Lossy NEXTSTEP-to-ASCII table reconstruction (2026-10-05)

IDA defines `_lossyNEXTSTEPToASCIITable` at `0x425a6de4` as a 512-byte table of 128 packed 32-bit ASCII mappings for NEXTSTEP bytes `0x80–0xff`, ending before `_latin2_from_tab` at `0x425a6fe4`. Its SHA-256 is `8d197582878749f89287a33928346e96d60b5bf0cf7cfd20ecd4ed1096508a09`.

The bytes exactly match entries 128–255 of `NSLossyASCIIFromNextStep` in `NSStringEncodings.m`. The source table is split into a private low-byte half and the exported 128-entry high-byte table; `NSUnicodeToLossyASCII` selects the corresponding half, preserving all 256 mappings. ABI, source-symbol, and ownership maps assign the export to `NSStringEncodings.m`. The static count and digest checks pass; no tests or builds were run.

### Foundation version data exports (2026-10-05)

Rechecked the two version exports in the attached `Foundation-i386` IDA
database. `_NSFoundationVersionString` at `0x425a445c` is in `__const` and
contains the bytes for
`@(#)PROGRAM:Foundation  PROJECT:Foundation-275  DEVELOPER:root  BUILT:03/28/98 06:22:40\n`,
followed by a NUL terminator. `_NSFoundationVersionNumber` at `0x425a44b8`
is also in `__const`; its eight bytes decode as IEEE-754 `275.0`. Neither
symbol has data xrefs in the database. Both are now defined in
`NSObjCRuntime.m` with ABI, source-map, and ownership entries. The public
`NSFoundationVersionNumber` declaration is in `NSObjCRuntime.h`, imported by
`Foundation.h`; `NSFoundationVersionString` remains an exported data symbol
without a public header declaration. Source values match the IDA string bytes
and double value. JSON and exact-profile symbol checks passed; no tests or
builds were run.

### `__NSMsgSendCount` owner check (2026-10-05)

IDA places `__NSMsgSendCount` at `0x42602078` in `__data`; the next named
object starts at `0x4260207c`, and the counter's four bytes are zero in the
reference image. It has no read or write xrefs. Source already defines and
claims `_NSMsgReceiveCount` and `_NSMsgResizeCount` in `NSRunLoop.m`, but has
no send-count definition. With no xrefs and no proven source owner, the
similar counter names alone are insufficient to assign this export to
`NSRunLoop.m`; no source or ABI change was made.

### Registrar and runtime lock source-owner check (2026-10-05)

Searched the Foundation source for the exact names behind the missing
`__NSURLFormatterRegistrarLock`, `__NSURLHandlerRegistrarLock`,
`__NSPlaceholderValueLock`, `___NSDebugRecordLock`, `___NSAllocatorLock`, and
`___NSRefCountLock` exports. No direct definitions are present. The only
defaults lock definition is `_NSUserDefaultsLock` in `NSUserDefaults.m`,
already claimed as `__NSUserDefaultsLock`; this is distinct from the other
IDA name `__NSUserDefaultsLock_0`. `_NSRefCountLock` appears in comments but
has no source definition. These globals need owner and layout evidence before
they can be added as aliases or reconstructed; no ABI or source change was
made.

### Unicode scalar limit data exports (2026-10-05)

IDA places four consecutive four-byte constants in `__const`:
`_kReplacementCharacter` (`0x425a8fa0`) is `0xfffd`, `_kMaximumUCS2`
(`0x425a8fa4`) is `0xffff`, `_kMaximumUTF16` (`0x425a8fa8`) is `0x10ffff`,
and `_kMaximumUCS4` (`0x425a8fac`) is `0x7fffffff`. None has data xrefs in
the current database. Added these four 32-bit constants to
`NSStringEncodings.m` and registered their symbols in the NSStringEncodings
ABI, source-symbol, and ownership maps. No conversion behavior changed; no
public header declarations were added. JSON and symbol-map checks passed; no
tests or builds were run.

### `_NSFastFuncList` encoder callback contracts (2026-10-05)

Freshly decompiled the four pointers in `_NSFastFuncList` at `0x42602480`:
`_encodeFastByte` (`0x425186f4`), `_encodeFastInt` (`0x42513fa8`),
`_encodeFastCharStar` (`0x4251d764`), and `_encodeFastData` (`0x42535fa0`).
`NSConcretePortCoder`'s stream context offset 16 points to this table through
the global pointer at `0x42602d98`.

All four callbacks use the same output context fields: cursor at offset 4,
end at 8, allocation base at 12. On insufficient capacity they recover the
allocation zone with `NSZoneFromPointer`, reallocate, restore the cursor's
offset from the base, and update the end pointer. Byte writes reserve one
byte; data writes copy the requested raw span. Both architectures serialize
fast integers as minimal signed little-endian payloads prefixed by a signed
byte giving the payload length. i386 writes its native little-endian bytes;
PPC reverses its big-endian native bytes before trimming and restores native
byte order in its decoder. The i386 integer callback returns the encoded byte
count, while PPC returns a pointer. The C-string callback emits a presence
byte through table slot 0; for non-null strings it then writes
`strlen(string) + 1` through slot 1 and copies the bytes including the NUL
terminator. `NSSerialization.m`'s existing
`NSMutableData` helpers do not share this cursor/end/base context, so they are
not direct definitions of these table entries. No source or ABI changes were
made.

### `_NSStandardizePath` caller buffer recheck (2026-10-05)

Freshly decompiled the four callers at `0x4253108c`, `0x42532b10`,
`0x42541a1c`, and `0x42545148`. All use a 1,024-unit stack buffer, expand
tilde first, call `_NSResolveSymlinksInPath` only in the resolving methods,
then pass capacity `0x400` to `_NSStandardizePath` and return
`+[NSPathStore2 pathStoreWithCharacters:length:]` with the resulting buffer
and length. The two generic `NSString` methods clamp the copied length to
1,024 and also initialize the in/out length to that clamped value. The two
`NSPathStore2` methods instead preserve the original in/out length while
clamping only the copy count to 1,024. That distinction is present in the
target pseudocode and must be retained when routing the source methods.

### `_NSWalkData` local-byte control-flow corroboration (2026-10-05)

The loaded `Foundation-i386` file still matches the profile's expected size
and SHA-256. I mapped `_NSWalkData` at `0x4251db30` into `__TEXT,__text` and
disassembled its 2,923 bytes locally with Capstone after the IDA trace writer
reported that its logging volume had no free space. The machine code confirms
recursive self-calls at `0x4251e352`, `0x4251e3f5`, `0x4251e525`, and
`0x4251e5e9`; direct calls to `_decodeFastByte`, `_decodeFastInt`,
`_NSGetSizeAndAlignment`, `_NSUniqueCString`, `_getBitfieldSize`, and
`_walkBitfields`; and indirect callback/Objective-C dispatch paths. This
supports keeping array/struct recursion, bitfield traversal, and fast decoder
interactions in the shared-walker spec. It does not replace the existing IDA
evidence for branch semantics. No source or ABI changes were made.

The same local disassembly confirms the three thin ownership wrappers each
call `_NSWalkData` directly: `__NSParseAndAutorelease` pushes operation `4`,
`__NSParseAndRelease` pushes operation `2`, and `__NSParseAndRetain` pushes
operation `3`. Each passes its two incoming arguments followed by the same
zero and one control values before the call. No source or ABI changes were
made.

The walker entry reads operation at `[ebp+8]`, a byte flag at `[ebp+0xc]`,
context at `[ebp+0x10]`, the data address at `[ebp+0x14]`, and the type string
at `[ebp+0x18]`. The wrappers push their type argument before their data
argument, followed by context `0`, flag `1`, and operation. This gives the
internal call shape `(operation, flag, context, data, type)` and the wrapper
shape `(type, data)` directly from the i386 calling convention.

The entry dispatch also uses a PIC-relative table for the signed type byte at
argument offset 24. Decoding its 91 entries for characters `!` through `{`
groups the recognized type cases as follows: `c`, `C`, `$`; `s`, `S`; `i`,
`l`, `f`, `I`, `L`; `q`, `d`, `Q`; `#`; `@`; `*`; `%`; `:`; `^`; `{`; and
`[`. Qualifiers `N`, `V`, `n`, `o`, `r`, `O`, and `R` each have dispatch
entries, while `!`, `(`, and `v` route to a separate unsupported-type block;
all other table characters route to the default invalid-type block. This
confirms the exact type-byte boundary and case grouping independently of the
decompiler pseudocode.

Handler targets from the table are `0x4251dcf0` for `c`/`C`/`$`,
`0x4251dd2c` for `s`/`S`, `0x4251dd84` for `i`/`l`/`f`/`I`/`L`,
`0x4251dd88` for `q`/`d`/`Q`, `0x4251ddc8` for `#`, `0x4251dec4` for `@`,
`0x4251e008` for `*`, `0x4251e19c` for `%`, `0x4251e240` for `:`,
`0x4251e2e8` for unsupported `!`/`(`/`v`, `0x4251e31c` for `^`,
`0x4251e414` for `{`, and `0x4251e59c` for `[`. The qualifier targets
are `0x4251dcdc` for `O`, `0x4251dce0` for `N`/`V`/`n`/`o`/`r`, and
`0x4251dce8` for `R`; the default invalid-type block is `0x4251e63c`.

Focused disassembly of the `@` block confirms it branches on operations `0`
and `1` before handling ownership operations. Both serialization paths branch
on the context byte at offset `0x18`: the callback-enabled path sends the
bycopy/byref object callback, while the other path sends the generic object
serialize/deserialize callback. Operations `2`, `3`, and `4` dispatch the
pointed-to object through `release`, `retain`, and `autorelease`, respectively.
The `#` block has a separate class-name decode path and checks the alternate
class-name function pointer after ordinary class lookup. This matches the
operation split and fallback already captured in the written design.

The `^` handler uses the flag argument as a root-pointer gate: with flag `0`
it returns the four-byte pointer size without traversing the pointee. At a
root pointer, operation `0` reads a presence byte; absent sets the pointer
slot to null, while present recursively decodes into the caller-provided
pointee address. Operation `1` emits a presence byte and recursively encodes a
non-null pointee. The root encode path enforces that bycopy/byref pointer
qualifiers point to an object encoding. The array handler parses a decimal
count and recursively walks each element, advancing by each recursive return
size. The struct handler aligns ordinary fields, delegates bitfields to the
dedicated helpers, clears bitfield storage on decode, and rounds the final size
to the maximum field alignment. Recursive array and struct calls preserve the
operation but clear the root-pointer flag, so nested pointers remain opaque.

Comparing those paths with the existing `NSWalkObjCType` identifies concrete
source deltas for the shared-walker implementation: source arrays advance by a
fixed `NSGetSizeAndAlignment` element stride and return the size of the full
encoding, while the target accumulates each recursive walk's returned size
before checking the closing `]`; source pointer recursion does not enforce the
target's bycopy/byref object-pointee restriction; and source class decoding
still lacks the target's alternate-name fallback. The source also uses its
`NSMutableData` serialization helpers instead of the target fast-context
callbacks. The existing design already scopes those compatibility changes.

### `_NSWalkData` primitive scalar handler follow-up (2026-10-05)

The scalar dispatch is width-based and preserves raw bytes. `c`, `C`, and `$`
use the byte callback/decoder and return size 1. `s` and `S` serialize as two
independent byte callbacks in address order and decode with two byte reads;
they return size 2. `i`, `l`, `f`, `I`, and `L` pass width 4 to the fast
integer callback/decoder, while `q`, `d`, and `Q` pass width 8. These cases
return the same widths and have no retain/release/autorelease branch. No source
or ABI changes were made.

### `_NSWalkData` string and selector handler follow-up (2026-10-05)

Focused machine-code inspection confirms that `*`, `%`, and `:` serialize
through function-table slot 2, the fast C-string encoder. The `*` decoder
reads a fast length, checks it against the context end pointer, advances the
cursor, allocates a zone-owned NUL-terminated copy, and writes that pointer to
the caller's slot. Operation `2` frees that allocation using its
pointer-derived zone; operation `3` creates another zone-owned copy. Operation
`4` sends `dataWithBytes:length:` to the `NSData` class with the original
pointer and `strlen + 1`; the method result is ignored. The selector name
`dataWithBytes:length:` and class name `NSData` are present at the pointers
loaded by this call. The Objective-C stub table independently resolves the
conversion routine at `0x42600e14` as `_sel_registerName`. The `:` type decodes
by reading and interning a C string with `_NSUniqueCString`, then calls
`_sel_registerName` and stores the returned selector. The `%` type stops after
`_NSUniqueCString` and stores the resulting character pointer; it stays
C-string-valued in the target, matching the current source. Both encode paths
send their stored pointer to the fast C-string callback. Neither type handles
ownership operations `2`, `3`, or `4`.
No source or ABI changes were made.

### Defined external data symbol inventory recheck (2026-10-05)

Parsed the current Foundation-i386 Mach-O symbol table and compared defined external symbols with `reconstruction/symbols.json`. Besides the seven unclaimed text exports listed above, 18 defined external data symbols remain unclaimed by the source-symbol map:
`_YES`, `_dummyPad1`, `_NO`, `_dummyPad2`, `_nil`, `_Nil`,
`___NSNumberSet`, `__NSMsgSendCount`, `__NSURLFormatterRegistrarLock`,
`__NSURLHandlerRegistrarLock`, `__NSPlaceholderValueLock`,
`___NSDebugRecordLock`, `___NSAllocatorLock`, `___NSRefCountLock`,
`__NSAltClassNameFromString`, `_NULL`, `_NSFastFuncList`, and
`__NSConstantStringClassReference`. `_lossyNEXTSTEPToASCIITable` and the two proxy signature globals are now defined and claimed by `NSStringEncodings.m` and `NSDistantObject.m`, respectively. The remaining set spans runtime globals and Objective-C support symbols; each still needs its storage width, source owner, and ABI treatment checked before definition or manifest claim. No source or ABI changes were made in this inventory pass.

### Foundation reconstruction coverage recheck (2026-10-05)

Re-ran the exact-profile C-symbol audit against the current
`Foundation-i386` image and `reconstruction/symbols.json`. It still reports
seven unclaimed exported functions: `_NSRecordAllocationEvent`,
`__NSParseAndAutorelease`, `__NSParseAndRelease`, `__NSParseAndRetain`,
`__NSStandardizePath`, `__NSToDoAtLastThreadExit`, and `__NSWalkData`. This
matches the prior inventory; each remaining function is either approval-gated
or depends on the unresolved shared thread/pool lifecycle.

The source selector audit reports 3,253 reference selectors and 3,300 source
definitions, with zero missing, renamed, or duplicate selectors. The 47 extra
definitions are outside the target selector inventory. No source or ABI
changes were made.

### Compiler-emitted constant-string class reference (2026-10-05)

The public i386 data symbol `__NSConstantStringClassReference` at
`0x4260af94` contains a pointer to `0x4260cc04`. `NSString.h` declares the
corresponding C symbol `_NSConstantStringClassReference`, and
`NSConstantString.m` contains the compiler-emitted literal `@""` in its
`__NSEmptyString` definition. Registered the generated export under
`NSConstantString.m` in its ABI, symbol-assignment, and ownership maps; no
runtime storage definition was added.


### Distant proxy special signature globals (2026-10-05)

IDA decompiles `-[NSDistantObject methodSignatureForSelector:]` at `0x425304a8` to return `___NSMethodDescriptionForSelectorSignature` for `methodDescriptionForSelector:` and `___NSReleaseSignature` for `release`. The globals at `0x42602338` and `0x4260233c` are adjacent four-byte zero-initialized slots; IDA reports no writes to either. The source previously constructed signatures on demand. `NSDistantObject.m` now returns the corresponding globals, and both data exports are registered in its ABI, symbol, and ownership maps. No tests or builds were run.

### Thread lock lifecycle hooks (2026-10-05)

IDA confirms `_NSToDoAtFirstThreadStart` at `0x425547f8` allocates four raw
mutex blocks, initializes the lock globals in the same order used by
`_NSToDoAtLastThreadExit` at `0x42571898`, then calls
`+[NSRunLoop _taskNowMultiThreaded]`. The source now covers those raw locks
and all 32 object locks; the last-thread hook calls
`+[NSRunLoop _taskNowSingleThreaded]`, releases and clears the 32 object locks
in target order, then frees and clears the four raw mutexes. Three
`NSConnection.m` lock declarations were made externally visible because the
target exports them and both lifecycle hooks access them. Added the missing
thread-owned lock and lifecycle exports to the NSThread ABI, symbol, and
ownership maps. The eight class warm-up messages at the beginning of the
reference first-thread hook are not yet represented in source; their selector
identity still needs to be resolved. No tests or builds were run.
A repeat of the exact-profile Foundation-i386 symbol audit after these changes
reports six unclaimed exported functions; `__NSToDoAtLastThreadExit` is no
longer among them. JSON parsing and `git diff --check` passed. No tests or
builds were run.

### Current Foundation-i386 C export audit (2026-10-05)

Re-ran `binrecon symbol-audit` against the exact Foundation-i386 profile and
current `reconstruction/symbols.json`. It now reports one unclaimed exported
function: `_NSRecordAllocationEvent`. The previously listed serialization,
path-standardization, and thread-exit exports are now claimed by the current
source-symbol map; the allocation-event sender remains the outstanding C
export gap.
### First-thread class warm-up selector address check (2026-10-05)

The eight initial class messages in `_NSToDoAtFirstThreadStart` all load the
selector reference at `0x42608918`; its raw pointer value is `0x41406988`,
outside the Foundation IDA image. The adjacent word at `0x4260891c` points to
the local `sel_hasSuffix:` string, but the disassembly loads the preceding
word for these calls. That adjacent selector therefore does not identify the
warm-up messages. The selector remains unresolved and has not been guessed in
source.

### Allocation-event export dispatch audit (2026-10-05)

The current Foundation-i386 IDA database names the public entry point
`_NSRecordAllocationEvent` at `0x4256fae4`; it forwards to
`__NSRecordAllocationEvent` at `0x42571124`. The core first handles negative
retain checks for autorelease, extra-ref decrement, and internal-ref decrement
events (types 3, 5, and 7), subtracting
`_NSAutoreleasePoolCountForObject` from `retainCount`. Recording then depends
on the event bit in `NSAllocationStatisticsOutputMask`. It lazily resolves
`NSAllocationStatisticsOutputPortName`, accepts a `mach-port://host/port`
form, and uses `netname_look_up`; a non-null lock is acquired with
`mutex_try_lock` / `mutex_wait_lock` and cleared on exit.

The header documents 21 event types (0–11 and 16–24) and their variadic
arguments. The IDA core dispatches event payload construction through a
25-entry relative jump table based at `0x425713cc`; the overlapping table
region masks the i386 case bodies from disassembly. The function uses a
`0x1e10`-byte stack frame. `NSDebug.m` currently has no production definition,
while `reconstruction/tests/link_stubs.m` supplies a test-only no-op. Case
semantics are now cross-checked against the PPC Foundation build below; packet
serialization still needs a byte-level comparison against the i386 target.

### Allocation-event case mapping from the PPC Foundation build (2026-10-05)

A second IDA database, `Frameworks/Foundation.framework/Versions/C/Foundation`,
decompiles the same internal helper at `0x4257f0c8` with a structured switch.
This supplies case semantics that the i386 database's overlapping jump-table
data suppresses. The i386 dispatch at `0x425713c8` uses a relative table based
at `0x425713cc`; its 25 entries map event indices 0–24 to handler offsets:
`0:64`, `1:1c3`, `2:9c`, `3:1c3`, `4–7:e4`, `8–9:11c`, `10:164`,
`11:1c3`, `12–15:454` (default), `16:12c`, `17:13c`, `18:148`, `19:135`,
`20:164`, `21:170`, `22:17c`, `23:198`, `24:1b2`.

The decoded PPC switch groups object events as follows: allocation records
zone, class instance size plus extra bytes, and object; copy records the new
object's zone, original class size plus extra bytes, source, and destination;
reference-count events record `retainCount`; pool start/finish events suppress
the object pointer; Java allocation/finalization use the class-name argument;
zone and VM events route size, zone, source, and destination into the generic
event slots. The helper initializes a 0xDB8-byte packet template, fills
version, port, time, event counter/type, current thread ID, and a bounded
stack trace, then calls `msg_send` with a retry option when the first send
returns `-103`. The PPC routine only takes the debug-record lock when the
runtime is multithreaded; the i386 routine instead uses its mutex pointer when
non-null, so locking must follow the i386 path for this target.

The Foundation header's event comments are incomplete for zone events: current
call sites pass zone and trailing zero fields as well as the documented
pointer/size values. The helper's target-side argument routing, rather than
the header comments, is the reconstruction source for these cases.

### Allocation-event port-name parser architecture difference (2026-10-05)

Rechecked the live `_NSRecordAllocationEvent` pseudocode at i386
`0x42571124` and PPC `0x4257f0c8`. Both consult
`NSAllocationStatisticsOutputPortName`, recognize the `mach-port://` prefix,
split host and port at the next slash, and resolve the pair with
`netname_look_up`. Their host-buffer handling differs: i386 allocates exactly
the host substring size and frees it after lookup; PPC starts with a zeroed
260-byte stack buffer and clamps the copied host component to 259 bytes before
adding a terminator. This is another target-specific sender detail, in
addition to the previously recorded lock and packet-layout differences. No
source or ABI changes were made.

### i386 allocation-event packet template recovery (2026-10-05)

Reopened a copy of the Foundation-i386 binary in an isolated IDA database and
decoded the switch targets there, leaving the shared IDA database untouched.
The i386 common event block at `0x4257158f` copies `0x76e` dwords (7,608
bytes) from `0x425a45bc` into its stack packet. This confirms the i386 packet
is larger than the PPC build's 0xDB8-byte template, so the PPC bytes cannot be
reused. The i386 template SHA-256 is
`28544f6e86a1e5b930a4c6c55f41aa5ff307a81052d75724f1844db31c7cda30`; its
only nonzero little-endian dwords are offsets `0:0x01000000`,
`24:0x10880809`, `164:0x10072002`, and `196:0x139e400a`. The common block
then fills the version, port, timestamp, event counter/type, current thread,
event arguments, and bounded stack frames before sending the Mach message.

The final i386 packet writes place the zone in words 52–53, object/pointer in
words 54–55, and event-specific data in words 56–57; the event object itself
is at word 44. The sequence number and event type occupy words 42–43, the
thread identifier words 50–51, and the trace count word 45. Backtrace frames
start at word 62 and each frame occupies two words. The i386 loop caps the
trace at 0x398 frames, and sends a message size of `0xf8 + 8 * frameCount`.
These offsets match `NSParseAllocationEvent` and its 7,608-byte receive
buffer in the current source.

The isolated decode also recovered the i386 handler bodies directly. Event 0
stores the object's zone and class instance size plus extra bytes; event 2
stores the destination object's zone, the same size calculation, source, and
destination. Events 4–7 call `retainCount`; events 8–9 clear the object slot.
Events 10, 20, and 21 route their first variadic argument to the size/value
slot. Events 16–19 and 22–24 route zone/VM arguments into the generic zone,
size, and destination slots, matching the PPC case analysis. Events 1, 3,
and 11 enter the common packet path without additional per-case setup; 12–15
and values above 24 take the default exit.

### `_NSWalkData` IDA behavior audit (2026-10-05)

Decompiled `_NSWalkData` at `0x4251db30` from the live Foundation-i386 IDA
database and its three public wrappers. The worker takes `(operation,
walkPointers, archiveContext, value, typeEncoding)`. `__NSParseAndRelease`
(`0x425761a4`), `__NSParseAndRetain` (`0x425761c0`), and
`__NSParseAndAutorelease` (`0x4252e978`) call it with operation codes 2, 3,
and 4, `walkPointers = 1`, and a null archive context. The two
`NSData`/`NSMutableData` typed serialization methods call the same worker in
decode/encode modes 0/1 with `walkPointers = 1` and a live fast archive
context. The worker passes `walkPointers = 0` to recursive array, struct, and
pointee walks, so the flag permits traversal of only a top-level pointer.

Operation 0 decodes the target's compact byte/integer representation and
advances the archive cursor; operation 1 encodes through archive callbacks.
Operations 2/3/4 release, retain, or autorelease object fields and free, copy,
or wrap C strings according to the type. The `@` case also honors `O`/`R`
qualifiers by using the bycopy/byref callback, and the `^` case descends into
the pointee only when `walkPointers` is set. Arrays recurse across their
element count. Structs recurse with `NSGetSizeAndAlignment`, explicit field
alignment, and separate bitfield sizing/walking. Class (`#`) decode resolves
through `objc_getClass` and then the zero-initialized
`__NSAltClassNameFromString` fallback when available. Unsupported `!`, `(`,
and `v` encodings raise `NSInvalidArgumentException`.

The current `NSSerialization.m` `NSWalkObjCType` already handles archive
operations 0/1, compact integer helpers, arrays, structs, bitfields, the
qualifier flags, and root-only pointer traversal. The recovered pointer flag
therefore agrees with its root-walk contract; standalone bitfields are
unsupported in both implementations. Confirmed differences are the exported
worker's additional ownership modes 2/3/4 and its class decode fallback via
`__NSAltClassNameFromString`. The typed archive methods also construct a
function-table context (`NSDataFuncList`) for mode 1 and a bounds/cursor
context for mode 0, whereas the current source walker directly calls its
storage and callback objects. This confirms `NSSerialization.m` as the
natural source owner for the exported worker and wrappers, but implementation
must compare and preserve archive dispatch semantics as well as add explicit
ownership modes. The class fallback depends on the separately
approval-gated `__NSAltClassNameFromString` source/ABI slice; no source or
manifest changes were made in this audit.

The mode-1 table at `0x42602460` contains `_encodeNSDataByte` (`0x425765a8`),
`_encodeNSDataInt` (`0x42576668`), and `_encodeNSDataCharStar` (`0x425765dc`).
Their byte append, compact signed-integer, and nullable C-string behavior
matches the existing `NSSerializerAppendFastInteger` and
`NSSerializerAppendCString` helpers, plus direct byte appends in
`NSSerialization.m`. Mode 0 uses the corresponding fast byte/integer decoder
callbacks. Thus the archive byte representation is already present in source;
the remaining archive-side design work is wiring the export and callbacks
without changing existing category behavior, alongside implementing modes
2/3/4 and resolving the approved class-fallback dependency.

### `_NSFastFuncList` ownership and context separation (2026-10-05)

Resolved the source-owner question for `_NSFastFuncList` (`0x42602480`). Its
indirect symbol pointer `_NSFastFuncList_ptr` at `0x42602d98` is read from
`-[NSConcretePortCoder encodeObject:isBycopy:isByref:]`,
`-[NSConcretePortCoder initWithConnection:components:msgid:]`, and
`-[NSConcretePortCoder encodeDataObject:]`; these methods are implemented in
`NSPortCoder.m`. The 16-byte table contains the four buffer-writer callbacks
documented above, and the port coder's stream context has matching cursor,
end, base, and function-table fields at offsets 4, 8, 12, and 16.

This is a different table from `_NSDataFuncList` at `0x42602460`, which the
`_NSWalkData` typed serializer context uses for appending bytes, compact
integers, and C strings to `NSMutableData`. The existing source
`NSPortCoderFastFunctions` table has eight read/write callbacks and a
different slot order; it is not a definition of the exported four-entry
`_NSFastFuncList`. `NSPortCoder.m` is the confirmed source owner, but the
exact source representation and integration of the four-entry export still
need design review. No source or manifest changes were made.

### `_NSFastFuncList` callback and source-layout recheck (2026-10-05)

Decoded the four table entries from IDA at `0x42602480`: `_encodeFastByte`
(`0x425186f4`), `_encodeFastInt` (`0x42513fa8`), `_encodeFastCharStar`
(`0x4251d764`), and `_encodeFastData` (`0x42535fa0`). Their signatures are
respectively `(context, byte)`, `(context, value, size)`, `(context, C string)`,
and `(context, bytes, length)`. The C-string callback writes a presence byte,
encodes `strlen + 1` through the integer callback, then appends the NUL-ended
bytes through the data callback.

`NSPortCoderStream` already has a function-table pointer at offset 16, and
`NSPortCoderFastFunctions` starts with the corresponding byte, integer,
C-string, and byte-span callbacks. However, the eight-entry table is private,
the context's `functions` field is only assigned, and the current writer
helpers call one another directly. The remaining integration gap is the
four-entry exported table and its use by the writer context; no source or
manifest changes were made in this recheck.

Direct reads of `_NSFastFuncList_ptr` occur in
`-[NSConcretePortCoder encodeObject:isBycopy:isByref:]`,
`-[NSConcretePortCoder initWithConnection:components:msgid:]`, and
`-[NSConcretePortCoder encodeDataObject:]`. The callers use slot 0 for the
presence/marker byte, slot 1 for compact integers, slot 2 for C strings, and
slot 3 for raw data. The current source's first four private table entries
have the corresponding order and operations, but the exported table is not
defined and the stream's stored table is not used for dispatch.

### `NSPortCoder` zero-valued fast integer correction (2026-10-05)

Compared IDA's `_encodeFastInt` (`0x42513fa8`), used by the
`NSConcretePortCoder` writer table, with `NSPortCoderWriteFastInt`. For an
all-zero value, IDA trims the payload length to zero, writes marker `0`, and
advances by one marker byte. The source loop stopped at payload length one,
writing marker `1` plus a zero byte. Its reader also rejected a zero-length
marker, although IDA's decoder sign-extends/fills the full-width result from
that marker. Updated the paired source helpers in `NSPortCoder.m`: zero
payloads now encode as one zero marker and the reader accepts that encoding.
Nonzero positive and negative payload trimming is unchanged. No tests or
builds were run; runtime behavior remains unverified.

### `_NSWalkData` implementation (2026-10-05)

Replaced the archive-only `NSWalkObjCType` entry with the exported
`_NSWalkData` worker in `NSSerialization.m`. The existing typed
`NSData`/`NSMutableData` category methods now construct an archive context and
use operation 0/1 through the shared worker. Added the release, retain, and
autorelease wrappers for operations 2/3/4. The walker keeps recursive array,
aligned-struct, bitfield, qualifier, and top-level pointer handling; ownership
operations now visit object fields and apply the target's `*` string actions.
Bitfield reads use the archive cursor/end bounds, and the `NSData` category
rejects a cursor beyond the buffer before forming its initial cursor pointer.
Class decoding consults `_NSAltClassNameFromString` after a failed
`objc_getClass` lookup.

Defined the zero-initialized `_NSAltClassNameFromString` function pointer in
`NSObjCRuntime.m`; `NSClassFromString` uses it after the ordinary runtime
lookup misses. Registered the four function exports and the callback data
export in their ABI, symbol, and ownership maps. The exact-profile
`symbol-audit` now reports two unclaimed functions, down from six:
`_NSRecordAllocationEvent` and `__NSStandardizePath`. All four JSON metadata
files parse successfully, and `git diff --check` reports no whitespace errors.
No tests or builds were run; runtime behavior remains unverified.

### `_NSStandardizePath` implementation (2026-10-05)

Implemented the exported in-place `_NSStandardizePath` in `NSPathUtilities.m`
from the live i386 IDA pseudocode at `0x425179bc`. The source follows the
target's initial slash-change flag, bounded 1,024-unit symlink scratch path and
capacity fallback, terminal `/.` trimming, non-UNC leading `./` removal,
`/./` collapse, root-bounded `/../` reduction, final slash cleanup, and
conditional `/private/` existence check. Routed both `NSPathStore2` and generic
`NSString` standardizing/resolving methods through the fixed 1,024-unit caller
buffers and `NSPathStore2` result factory, preserving the target's distinct
copy-length handling for the two caller families. Registered
`__NSStandardizePath` in the `NSPathUtilities` ABI, symbol, and ownership maps.

The exact-profile symbol audit reports one unclaimed exported function,
`_NSRecordAllocationEvent`. The selector audit reports zero missing, renamed,
or duplicate selectors (47 extra definitions remain). The edited JSON files
parse and `git diff --check` passes. A follow-up review identified the target's
truncated-copy/full-length hazard in the two `NSPathStore2` callers. Those
callers now use dynamically sized full-length workspaces, as required by the
saved NSPathStore2 safety analysis, while preserving the helper's 1,024-unit
capacity. `_NSStandardizePath` also uses full-length scratch storage for its
symlink-resolution path and keeps the target capacity check. Runtime path
behavior remains unverified; no tests or builds were run.

### `_NSWalkData` callback-mode review correction (2026-10-05)

Validated the fresh reviewer findings against the current `NSSerialization.m`
and live IDA pseudocode. The context's pointer fields already match the target
offsets (storage 0, cursor 4, end 8, reserved 12, function table 16, callback
20). The actual mismatch was semantic: source had treated bytes 24 and 25 as
the bycopy/byref qualifiers, while IDA initializes local qualifier flags to
zero on each invocation and uses context byte 24 independently to select the
special object callback path. Renamed the context fields to `callbackMode` and
`reservedFlag`, kept `O`/`R` state local to each walk, and routed object encode
and decode through the special callback only when byte 24 is set. The typed
category contexts initialize both bytes to zero, matching IDA.

The review's other reported issues were already resolved in the current source:
operation 4 ignores the `NSData` result and passes `strlen + 1`; arrays advance
and return accumulated recursive sizes; `%` decodes through
`_NSUniqueCString`; bycopy/byref root-pointer validation is present; and
unsupported type bytes reach the invalid-type exception. No tests or builds
were run; runtime behavior remains unverified.

A separate ownership pass found that the `#` decoder freed the result of
`_NSUniqueCString` after class lookup. The table owns those canonical strings
for reuse; the target keeps the interned pointer, while only the temporary
decoded input is freed. Removed the invalid free and retained the temporary
buffer release after interning.

The parity pass also found that struct fields advanced by the size reported by
`NSGetSizeAndAlignment` instead of the recursive walk result. Live IDA advances
the aligned offset by `_NSWalkData`'s return value, just as its array case does.
Changed the source to use that recursive result and retained the alignment
query only for field placement and maximum-structure alignment.

The `#`, `%`, and `:` decoders now intern directly from the bounded archive
cursor, matching IDA's cursor-based `_NSUniqueCString` calls without an
intermediate allocation. The `*` decoder remains separately allocated and
zone-owned for the retain/release/autorelease operations.

### `_NSWalkData` bitfield helper parity recheck (2026-10-05)

Re-decompiled live i386 helpers `_getBitfieldSize` (`0x42576790`),
`_getBitfieldSizeAndAdvance` (`0x425767b4`), `_walkBitfields` (`0x42576acc`),
`_extract_field_elmt` (`0x42576704`), and `_insert_field_elmt`
(`0x4257687c`). The source's 32-bit storage-unit accounting, zero-width
alignment, field retry when the width crosses a unit, LSB-first extraction,
and masked insertion follow those routines for widths through 32. Source
retains an explicit `width <= 32` exception guard where IDA has no
corresponding guard. The helper disassembly shows why removing it is not a
local parity change: `_extract_field_elmt` copies
`ceil((bitOffset + width) / 8)` bytes into a four-byte stack local, so widths
above 32 write beyond that local; `_insert_field_elmt` also forms its mask
with a 32-bit `1 << width` expression. The source keeps the guard as a
deliberate safety divergence for malformed or unsupported encodings rather
than reproduce the target's stack overwrite. No further bitfield changes were
indicated by this comparison.

### Thread-local autorelease prerequisite recheck (2026-10-05)

Rechecked the current worktree before selecting the allocation-event scope.
`NSThread.m` already allocates `__NSDebugRecordLock` in
`_NSToDoAtFirstThreadStart` and frees it in `_NSToDoAtLastThreadExit`; the
earlier note that this lifecycle still needed adding is stale. Its
`_NSCurrentThread` also uses the per-thread cthread data slot, creates the
thread object lazily, and checks the stack-page cache when multithreaded,
matching the target's `__NSCurrentThread` path. No new thread-lock or current-
thread implementation is needed for the allocation-event sender.

The remaining prerequisite is in `NSAutoreleasePool.m`: its live implementation
still stores frames and pool configuration in process-global variables,
whereas IDA's push, pop, autorelease, and count-for-object functions read the
current thread's AP-data pointer at `NSThread + 24`. The AP-data/page layout,
depth-token behavior, pool-instance recycling, and exception-protected drain
requirements are recorded in the earlier autorelease-pool recheck above. This
narrows the faithful reconstruction boundary to the pool backing plus the
event sender; it does not justify treating the existing global count as a
per-thread equivalent.

### Exported data-symbol ownership inventory (2026-10-05)

A fresh static comparison of the Foundation-i386 defined external data symbols
against the ABI manifests and `symbols.json` leaves ten symbols unclaimed:
`_NO`, `_NSFastFuncList`, `_NULL`, `_Nil`, `_YES`, `__NSMsgSendCount`,
`___NSNumberSet`, `_dummyPad1`, `_dummyPad2`, and `_nil`. The inventory
excludes `__TEXT,__text` and Objective-C method symbols.

IDA shows `_YES` as byte `01`; `_NO`, `_nil`, `_Nil`, `_NULL`, and both
`_dummyPad` symbols begin with zero bytes. Their addresses have no direct
cross-references in the loaded image, so their runtime or source ownership is
not established by this audit. `__NSMsgSendCount` at `0x42602078` is zeroed
and has no direct cross-references. `___NSNumberSet` at `0x425a916b` and
`_NSFastFuncList` at `0x42602480` each have an offset reference from a symbol
pointer slot; `_NSFastFuncList`'s table contents and `NSPortCoder.m` source
owner are already documented above. The indirect reference to `___NSNumberSet`
does not yet identify a source owner. No source or metadata changes were made.

### `___NSNumberSet` data-owner recheck (2026-10-05)

Traced `___NSNumberSet` (`0x425a916b`) through the live IDA database. Its only
incoming reference is the offset entry at `0x42602fd0`, named
`___NSNumberSet_ptr`; the pointer slot has no code cross-references. The data
immediately following the symbol begins at `_ALTERNATECHAR` (`0x425a917c`),
but that string has no code cross-references either. The adjacent bytes and
symbol names do not establish the object's type or owning source module, so no
definition or manifest ownership was added based on this evidence alone. The
companion AppKit binary imports `objc_class_name_NSNumber` but has no
`___NSNumberSet` import or named reference, so it does not supply an external
consumer that identifies the data's role.

### `___NSNumberSet` PPC cross-architecture owner evidence (2026-10-05)

The PPC Foundation database (`Foundation`, instance `75ffa72daeee`) changes
the earlier i386-only picture. `___NSNumberSet` is at `0x425cf700`; its 16-byte
bitmap is `00 00 00 00 00 28 ff 03 20 00 00 00 20 00 00 00`. Both
`_NSScanDoubleFromString` (`0x4252b948`) and `_NSScanDecimalFromString`
(`0x4255d7c8`) index it as `set[character >> 3]`, then test bit
`character & 7`. The set contains `+`, `-`, ASCII digits, `E`, and `e`.
`NSScanner.m` now uses the exported bitmap through
`NSScannerIsNumberCharacter` in both numeric scan paths, with the locale
decimal separator handled separately. The PPC scanner bodies read this exact
global, establishing `NSScanner.m` as its source owner. The i386 object at
`0x425a916b` contains the same 16-byte bitmap and is reached through its
pointer slot. The shared source now defines the exported array, and the shared
ABI, source-symbol, and ownership records assign `___NSNumberSet` to
`NSScanner.m`.

### Locale comparator empty-range parity correction (2026-10-05)

A closer check of the initial `a4 >= a4 + a5` branch in IDA at
`0x42590a7c` found that the empty receiver range compares the second string
from index zero: an empty second string yields `NSOrderedSame`, while any
nonempty second string yields `NSOrderedAscending`. The helper had compared
`rangeLocation` against the second string length, which could incorrectly
return same when the receiver range location exceeded that length. Updated the
empty-range branch to use the already-read second string length. This corrects
the prior control-flow parity note, which covered the loop and final weights
but missed this entry branch. No tests or builds were run.

### `_NSFastFuncList` callback return ABI recheck (2026-10-05)

The live i386 IDA pseudocode confirms that `_encodeFastByte` returns a pointer,
`_encodeFastInt` returns the encoded byte count, and `_encodeFastCharStar` and
`_encodeFastData` return pointers. The PPC recheck confirms the same argument
shapes but a pointer return for `_encodeFastInt`; PPC fast integers also reverse
native big-endian bytes to preserve the little-endian wire payload. Its decoder
reverses those payload bytes into native order. `_encodeFastCharStar`
uses the context's slot 0 for its presence byte and slot 1 for the NUL-inclusive
length, then appends the string bytes itself. The current NSPortCoder private
writer functions return `void`, so directly exporting the existing table would
not reproduce those function-pointer signatures. A faithful source table also
needs to dispatch through the stream's four writer slots and retain the
existing direct read helpers. No source or ABI edits were made; the bounded
implementation design needs to account for these return contracts.

The cross-architecture check confirms `_NSFastFuncList` is also exported by
MOSXS PPC at `0x426263ac`, with four pointers to `_encodeFastByte`,
`_encodeFastInt`, `_encodeFastCharStar`, and `_encodeFastData` in the same
order. The source change therefore belongs in shared `NSPortCoder.m` and the
shared ABI/source-owner records. The implementation design is saved in
`docs/superpowers/specs/2026-10-05-foundation-nsportcoder-fast-functions-design.md`;
no code changes were made pending design review.

### `_NSFastFuncList` implementation (2026-10-05)

Added the exported four-slot writer table to `NSPortCoder.m`, assigned it to
the stream function field, and routed byte, integer, C-string, and raw-data
writes through the table. The i386 integer callback returns its encoded length;
the PPC callback returns a pointer and reverses native bytes to retain the
little-endian wire encoding. The PPC read helper reverses payload bytes back
to host order. Direct read helpers remain outside the writer table. Registered
the data symbol in the shared ABI, symbol, and ownership records. JSON parsing, unique-definition and ownership checks, callback wiring checks, and whitespace checks pass; no tests or builds were run.

### Autorelease-pool capacity and backing-model recheck (2026-10-05)

Freshly decompiled `-[NSAutoreleasePool initWithCapacity:]` at `0x4250d5cc`
and `_NSPushAutoreleasePool` at `0x425096a8`. The target initializer calls the
no-argument push helper; the capacity parameter is not forwarded. The current
source passes `numSlots` to `NSPushAutoreleasePool`, which uses it to size a
frame array. The target instead stores the pool token and pool object in the
current thread's AP-data depth record and uses page checkpoints for draining.
This confirms the capacity behavior is part of the broader backing-model
divergence; changing only the call argument would leave frame allocation and
thread ownership inconsistent with the reference. No source code changed.

### Autorelease-pool thread-storage source boundary (2026-10-05)

The checked-in `NSThread` ABI already contains the target's `autoreleasePool`
pointer at instance offset 24, so a faithful AP-data pointer does not require
changing the class layout. The current `NSThread.m` does not read or write that
ivar: `_NSCurrentThread` establishes the thread object, while teardown calls
`NSPushAutoreleasePool(0)` and later `+[NSAutoreleasePool releaseAllPools]`.
`NSAutoreleasePool.m` still owns a process-global frame stack and process-global
configuration counters. IDA's pool implementation instead uses the current
thread's offset-24 pointer for AP data, including clearing it during
`releaseAllPools`. The source boundary therefore permits preserving the public
and private instance layouts while replacing the storage implementation; it
does not make a sender-only `_NSRecordAllocationEvent` shim faithful. No source
or ABI changes were made.

### Autorelease-pool page-layout detail recheck (2026-10-05)

Fresh decompilation of `__NSAPDataCreate` (`0x425479a8`), `__NSAPAddPage`
(`0x4254502c`), `_NSPushAutoreleasePool` (`0x425096a8`), and
`_NSPopAutoreleasePool` (`0x425073e8`) confirms the base AP-data allocation is
`0x90` bytes for eight depth records. The header stores the active-page head
at offset 0, autoreleased-object total at 4, high-water settings at 8 and 12,
release/freed-object-check/reentrant-log state at bytes 16 through 18, pool
subclass state at byte 19, free-page head at 20, four cached base-pool objects
at 24 through 36, depth capacity at 40, and depth at 44. Each 12-byte depth
record begins at 48 and stores an object-count checkpoint, page checkpoint,
and pool object. Pages use a three-word link/count header followed by object
slots and are allocated at `__NSPageSize`; pop drains back to each checkpoint,
then clears and recycles empty pages. This sharpens the rewrite boundary: the
pool implementation must migrate all current global counters and frame-stack
operations together, while keeping the existing `NSThread` and pool object
layouts unchanged. No source or ABI changes were made.

### MOSXS PowerPC Foundation target availability and selector delta (2026-10-05)

Opened `C:\Users\raynorpat\Downloads\test\Frameworks\Foundation.framework\Versions\C\Foundation`
in IDA. It is a PowerPC Mach-O dylib and contains the URL/HTTP implementation
classes reserved for stage 10 in the Foundation reconstruction design. A
selector comparison normalized to sign, class, and selector (to avoid treating
category names as dispatch differences) finds 3,396 target methods, 3,291
source methods, 125 target methods missing from the source tree, and 20 source
methods absent from the target. Of the missing methods, 97 belong to the six
stage-10 classes: `NSURLHandle` (8), `NSFileURLHandle` (14), `NSHTTPURLHandle`
(28), `NSHTTPConnection` (28), `NSHTTPRequest` (12), and `NSHTTPSocket` (7).
The remaining 28 are in existing modules. The source tree has only
`NSURLHandle.m` among those six classes, and its methods are TODO bodies; the
other five implementations are absent. This provides a concrete MOSXS target
for stage 10, which the DR2 i386 binary could not supply. No source or ABI
changes were made.

### NSURL resource-loading flow recheck (2026-10-05)

Decompiled the five MOSXS PowerPC `NSURL` callbacks at `0x425af418`,
`0x425af4c8`, `0x425af4d4`, `0x425af644`, and `0x425af7b0`, and traced their
caller `-[NSURL loadResourceDataNotifyingClient:usingCache:]` at `0x425aef38`.
The caller reads the handle status: cached success notifies the client with
available bytes and completion; in-progress and not-loaded cases register the
client-to-handle pair in `_clients` and start or continue the handle load; a
failed handle sends its reason. It builds `_clients` as an `NSMapTable` only
when needed. `resourceDataUsingCache:` gets the selected handle and asks for
its resource data. The five callback methods route data, completion, cancel,
and failure notifications only to registered clients whose mapped handle is
the sender; terminal paths snapshot matching keys, notify, remove each entry,
notify the handle, and free `_clients` when empty. Begin-loading is an empty
target method.

The current `NSURL.m` has TODO bodies for `resourceDataUsingCache:`,
`loadResourceDataNotifyingClient:usingCache:`, property/data forwarding, and
`URLHandleUsingCache:`. Its four client notification methods are TODOs on an
`NSObject` category, while the target callbacks belong to `NSURL`. Thus the
callbacks are not an isolated bounded slice: a faithful reconstruction needs
the coordinated `NSURL` loading/cache/client flow and must account for the
still-unimplemented `NSURLHandle` factories and concrete URL handlers. This
supersedes the earlier note that described the callbacks as bounded on their
own. No source or ABI changes were made.

### NSString URL-path helpers in the MOSXS PowerPC target (2026-10-05)

The MOSXS PowerPC Foundation binary contains three `NSString` methods with no
matching source definitions: `urlPathRelativeToPath:` at `0x425b0a48`,
`urlPathByAppendingComponent:` at `0x425b0c64`, and
`urlPathByDeletingLastComponent` at `0x425b0dd0`. Their selector strings are
present at `0x42649174`, `0x42649300`, and `0x426492e0`, respectively. A fresh
Objective-C method index assigns all three to
`NSString(NSURLPathUtilities)`; the DR2 i386 method index has no corresponding
entries. `NSPathUtilities.m` already has that category, but it does not
implement these methods; `NSPathUtilities.h` and the shared i386 ABI record
also omit them.

Live PPC pseudocode confirms category ownership as
`NSString(NSURLPathUtilities)`. `urlPathRelativeToPath:` applies
`standardizedURLPath`, splits both strings with `componentsSeparatedByString:@"/"`,
finds their common component prefix, appends `..` for each remaining base
directory component (excluding the base's final component), appends the
receiver's unmatched components, then joins with `/`. It returns the receiver
for a nil base, absent component arrays, identical inputs, a zero-length common
prefix, or the observed empty-component guard at common-prefix length one.

`urlPathByDeletingLastComponent` shortens the search range by one when the
receiver ends in `/`, searches backward for `/`, and returns the substring
through that separator; when no separator is found it returns the empty string.
`urlPathByAppendingComponent:` keeps a receiver already ending in `/`; otherwise
it first sends `urlPathByDeletingLastComponent`, so it replaces the receiver's
last component. It then strips a component's leading slash by repeatedly taking
`substringFromIndex:3` while its length exceeds three, or resetting it to `/`
when its length is at most three. The raw loop returns to the receiver check
after each strip; the short-prefix case does not make progress. Finally it
removes one leading slash if present and joins the receiver prefix and component
with the target's `"%@%@"` format string. These odd edge cases are in the target
instructions and must be explicitly decided in the implementation design.

The old description that these methods use `pathComponents` and
`pathWithComponents:` was incorrect: the live selector references show direct
string splitting and joining. Filesystem helpers such as `NSPathAppendComponent`
are not substitutes. The three methods are PPC-only in the current IDA
databases; the DR2 i386 method index has no entries. No source or ABI changes
were made, and implementation remains pending the in-chat design approval.

### NSString UTF-8 convenience methods in the MOSXS PowerPC target (2026-10-05)

A selector-to-method-list cross-reference confirms the target implements
`-[NSString initWithUTF8String:]` at `0x425a75cc`,
`-[NSString UTF8String]` at `0x425a79dc`, and
`+[NSString stringWithUTF8String:]` at `0x4259f488`. The initializer computes
`strlen` and delegates to `initWithBytes:length:encoding:` with encoding 4
(UTF-8); a null input takes the target's invalid-argument exception path. The
class factory allocates in the default zone, initializes with the same UTF-8
encoding, and autoreleases. `UTF8String` delegates to the target's
`bytesInEncoding` helper, which returns NUL-terminated bytes from
`_NSAutoreleasedMallocMemory`, using the exact UTF-8 conversion and raising a
character-conversion exception when conversion fails. The source header
already declares the three selectors, but neither `NSString.m` nor
`NSStringEncodings.m` defines them; `NSStringEncodings.m` does contain related
`cString` and `lossyCString` implementations plus the shared autoreleased-memory
class. No source or ABI changes were made.

### NSMachPort date-based message-send override gap (2026-10-05)

The MOSXS PowerPC target implements `-[NSMachPort
sendBeforeDate:components:from:reserved:]` at `0x425760a0`, while the current
source only provides `-[NSPort sendBeforeDate:components:from:reserved:]` as a
concrete-implementation trap. Disassembly resolves the first selector load to
`timeIntervalSinceReferenceDate` and the class message to
`NSPortMessage sendBeforeTime:streamData:components:to:from:msgid:reserved:`.
The target passes `nil` stream data, the supplied components, `self` as the send
port, the supplied receive port, message ID zero, and reserved bytes zero; its
`reserved` parameter is unused. `NSPortMessage.m` already implements the exact
class-level send primitive. This is a small missing `NSMachPort` override in
`NSPort.m`; no source or ABI changes were made.

### NSMachPort date-based message-send override implemented (2026-10-05)

Added the PPC-only override in the existing
`NSMachPort(NSPortMessageSpeedups)` category. It converts the date to a
reference-time interval and delegates to `NSPortMessage` with nil stream data,
the supplied components and receive port, `self` as send port, and zero message
ID/reserved size. The caller's reserved-space argument is intentionally unused,
matching the PPC body at `0x425760a0`. The i386 database has no matching method,
and the shared i386 ABI remains unchanged. The fresh PPC selector audit reports
120 missing selectors, zero renames, and zero duplicates. No tests or builds
were run.

### NSPathStore2 standardization workspace review recheck (2026-10-05)

Rechecked the `NSPathStore2` wrappers in the current worktree after a review
reported a 1,024-unit copy with the full source length passed downstream. The
current `stringByStandardizingPath` and `stringByResolvingSymlinksInPath`
allocate `max(length, 1024)` UTF-16 units, copy the complete stored string, and
keep the target helper/resolution capacity at 1,024. The reported truncated
copy is not present in the current source, so no code change is indicated.

### Fresh MOSXS PowerPC selector coverage audit (2026-10-05)

Ran `tools/binrecon/selector_check.py` against the current MOSXS PowerPC
Foundation binary and `src/Kits/Foundation`. Its raw category-sensitive report
finds 3,397 reference selectors and 3,300 source definitions, with zero
reported renames or duplicate definitions, 127 missing entries, and 30
source-only entries. The raw report distinguishes Objective-C category names,
so its 127/30 counts should not be compared directly with the earlier
category-normalized 125/20 comparison. The target-only stage-10 HTTP classes
still account for the 97 missing methods previously grouped under
`NSURLHandle`, `NSFileURLHandle`, `NSHTTPURLHandle`, `NSHTTPConnection`,
`NSHTTPRequest`, and `NSHTTPSocket`. The remaining report includes the now
confirmed NSString UTF-8 convenience methods, three URL-path helpers, five
NSURL loading callbacks, `NSMachPort sendBeforeDate:components:from:reserved:`,
and smaller existing-module gaps such as NSBundle, NSInvocation,
NSNotificationCenter, and NSUndoManager. No source or ABI changes were made.

### NSInvocation inline-frame factory gap in the MOSXS PowerPC target (2026-10-05)

IDA confirms `+[NSInvocation newInvocationWithMethodSignature:]` at
`0x42523884`, which allocates `frameLength` extra bytes, points the invocation's
argument-frame field into that trailing storage, and then sends
`initWithMethodSignature:`. The target initializer records the frame length and
calls `establishArgumentFrame` only when that field is still null. The current
source provides only the autoreleased `invocationWithMethodSignature:` factory;
its initializer always allocates a separate argument frame. Therefore this
MOSXS-only selector is not a safe one-method addition: matching it requires
coordinating factory allocation, initializer behavior, and frame ownership in
`NSInvocation.m`. No source or ABI changes were made.

PPC recheck at `-[NSInvocation dealloc]` (`0x42521370`) and
`_establishArgumentFrame` (`0x425868e8`) confirms the ownership distinction:
the initializer calls `_establishArgumentFrame` only when the argument-frame
field is null; that helper zone-allocates and zeroes `frameLength` bytes and
sets flag `0x08000000`; deallocation frees the frame only when that flag is
set. The new inline-frame factory preloads the argument-frame pointer without
setting the flag, so its frame storage is released with the `NSInvocation`
allocation. The current source's `externalArgFrame` bit only models borrowed
frames installed by `_setArgFrame:`; a faithful PPC implementation must
distinguish borrowed, heap-owned, and allocation-tail frames.

### NSBundle Java setup flag selector gap (2026-10-05)

The three selector-check entries are genuine MOSXS gaps, not merely category
renames: `NSJavaSetup.m` contains no `NSBundle` category methods with these
selectors, and `NSBundle.m` does not define them either. IDA decompiles the
class setter/getter at `0x42577680` and `0x425776c0`; both access the same
four-byte global `__usesFastJavaBundleSetup` at `0x426260c0` (initialized to 1).
`_NSJavaBundleSetup` and `_NSJavaSpecifiedClassesForBundle` read this flag to
select the fast Java setup path. `-[NSBundle _setJavaClassesLoaded]` at
`0x42578034` ORs `0x60000000` into the bundle flags. These are small existing-
module gaps with direct target behavior and no discovered source definition;
no source or ABI changes were made.

Follow-up on this cluster: the flag is not a standalone three-method slice.
IDA shows its default value is true and `_NSJavaBundleSetup` immediately dispatches
to `__NSFastJavaBundleSetup` when set. The target helper is a 0x69c-byte
function at `0x4257dd78`; `NSJavaSetup.m` has no corresponding helper or flag,
and its current `NSJavaBundleSetup` is the non-fast path. Adding only the setter
and getter would leave the target's default dispatch without an implementation.
The cluster therefore needs a broader Java setup design that includes the fast
helper (or an explicitly justified source-level equivalent) before code work.

### NSConcreteTask process identifier getter gap (2026-10-05)

IDA decompiles `-[NSConcreteTask processIdentifier]` at `0x4258f590` as a
direct return of the concrete task's `_pid` field. The current source already
stores the child PID in `NSConcreteTask::_pid` and has a private `-_procid`
getter returning that field, but it does not define `processIdentifier` in
`NSTask.m`, declare it in `NSTask.h`, or list it in `reconstruction/abi/NSTask.json`.
This is present in the MOSXS PowerPC target, while a fresh selector audit of
the DR2 i386 reference reports no missing methods; the i386 ABI manifest must
therefore remain unchanged. The getter's backing state is already available,
but any source/header addition needs to be recorded as a PowerPC-only
divergence. No source or ABI changes were made.

### Fresh DR2 i386 selector coverage audit (2026-10-05)

Ran `tools/binrecon/selector_check.py` against the DR2 i386 Foundation slice
(`C:\Users\raynorpat\Downloads\test\Foundation-i386`) and the current
`src/Kits/Foundation` tree. The report finds 3,253 reference selectors and
3,300 source definitions, with zero missing selectors, renames, or duplicate
definitions; it reports 47 source-only entries. This result is specific to
the DR2 i386 target and does not supersede the separate MOSXS PowerPC audit,
which still has 125 missing selectors after category normalization, including
the 97 stage-10 URL/HTTP methods. The newly identified
`-[NSConcreteTask processIdentifier]` is therefore a MOSXS PowerPC-only
selector gap relative to this i386 audit. No source or ABI changes were made.

### Fresh MOSXS PowerPC selector coverage recheck (2026-10-05)

Re-ran `tools/binrecon/selector_check.py` against the live
`Frameworks/Foundation.framework/Versions/C/Foundation` PowerPC dylib and the
current source tree. The raw category-sensitive report remains at 3,397 target
selectors and 3,300 source definitions, with zero renames or duplicates, 127
missing entries, and 30 source-only entries. The missing list still contains
the 97 stage-10 URL/HTTP methods and the previously documented smaller gaps,
including `-[NSConcreteTask processIdentifier]`; this confirms the prior
category-normalized audit's unresolved target/source delta remains actionable.
No source or ABI changes were made.

### Two notification-center selector bodies confirmed in IDA (2026-10-05)

The live MOSXS PowerPC database decompiles
`+[NSNotificationCenter setNotificationCenterSerializeRemoves:]` at
`0x4257778c` as a single byte store of its argument to PIC-relative target
state. `+[NSDistributedNotificationCenter enableLogging:]` at `0x425776f0`
is likewise a single byte store. Neither selector currently has a source
definition. These are not yet ready for isolated implementation: tracing the
notification-center flag identifies it as `__NSNotificationCenterSerializeRemoves`
at `0x426260cc`; `_postNotification` reads it before observer delivery to link a
stack record into the center's pending-post list, then locks the center, unlinks
the record, broadcasts, and unlocks after callbacks finish. The current source
instead snapshots matching observers under the lock and delivers from that
snapshot, with no serialization flag or pending-post list. Faithful support
therefore requires a coordinated posting/removal design, not only the setter.
No source or ABI changes were made.

### NSDecimalNumberPlaceholder zone allocator body (2026-10-05)

IDA decompiles `+[NSDecimalNumberPlaceholder allocWithZone:]` at `0x425b95c8`
as a direct call to `_NSDecimalNumberPlaceholderWithZone(zone)`. That helper
returns the cached placeholder for the requested zone or creates and caches a
new placeholder. `NSDecimalNumber.m` already has the same per-zone cache in
`NSDecimalNumberPlaceholderForZone`, and `+[NSDecimalNumber allocWithZone:]`
already uses it; the private placeholder class lacks the corresponding class
method. This supports a narrow forwarding implementation while preserving the
DR2 i386 ABI manifest, where the selector is absent. The bounded addition is
pending user approval. No source or ABI changes were made.

Architecture correction after live IDA recheck (2026-10-05): address
`0x425b95c8` is in the MOSXS PowerPC Foundation database, where the method is
present and decompiles to a direct call to `_NSDecimalNumberPlaceholderWithZone`.
The open DR2 i386 database has no function at that address and has no named
`+[NSDecimalNumberPlaceholder allocWithZone:]`; it does contain
`__NSDecimalNumberPlaceholderWithZone` at `0x425a2d78`. The existing source
helper already mirrors that zone cache. Any source addition must therefore be
PowerPC-only, and the i386 ABI manifest must remain unchanged. No source or ABI
changes were made.

Further helper comparison (2026-10-05): the existing source helper is not an
implementation-level match for either target. The i386 helper lazily works
through an `NSMutableArray`, scans from the last entry, and takes
`_NSPlaceholderDecimalNumberLock` only when that global is nonzero. The PPC
helper gates an atomic spin lock on `_NSIsMultiThreaded`, initializes its
`NSMutableArray` with capacity 8, and releases the spin lock on its return
paths. `NSDecimalNumber.m` currently uses a singly linked list and lazily
creates an `NSLock`, so adding only the PPC forwarding selector would still
route into cache/concurrency behavior that differs from the PPC target. The
next design must cover the helper representation and architecture-specific
locking as well as the PPC-only selector. This replaces the earlier narrow
forwarding-only proposal; no source or ABI changes were made.

The i386 lock lifecycle is already connected to thread transitions: IDA's
`__NSToDoAtFirstThreadStart` creates `_NSPlaceholderDecimalNumberLock`, and
`__NSToDoAtLastThreadExit` releases and clears it. `NSThread.m` contains the
same initialization and cleanup calls. That lifecycle should be preserved
while reconciling the cache container. The PPC helper uses its own static
spin-lock word and `_NSIsMultiThreaded` predicate instead; its lock references
are confined to the helper. This confirms the parity work belongs in both the
placeholder helper and the PPC-specific path, while i386's thread lock setup
already has a matching source owner.

### Allocation-event message template architecture comparison (2026-10-05)

Fresh IDA byte reads of the PPC template at `0x425c9b58` (`0xdb8` bytes)
and the i386 template at `0x425a45bc` (`0x1db8` bytes) find only four
nonzero dwords in each. Both have `00000001` at offset 0, but the remaining
raw words differ: offset 24 is `09080888` on PPC versus `09088810` on i386;
offset 164 is `02200078` versus `02200710`; and offset 196 is `0a4019e8`
versus `0a409e13`. The target-generated message prefix therefore cannot be
shared as a literal template across these architectures. The PPC sender's
frame loop stores at most 408 trace entries and sets message size to
`0xf8 + 8 * count` (maximum `0xdb8`); i386's message/receiver storage is
`0x1db8` bytes and its sender allows up to 920 entries (`0x398`). The parser's
common event-field offsets remain useful, but a faithful sender needs separate
architecture-specific message headers and trace caps. No source or ABI changes
were made.

### Locale comparator cross-architecture table fidelity recheck (2026-10-05)

Resolved the current live PowerPC symbol addresses from IDA instead of reusing
the i386 addresses: `_keyRanges` is at `0x425cf938`, `_baseTable` at
`0x425cf9c0`, and `_ligatureTable` at `0x425deca0`; the corresponding i386
symbols remain at `0x425a9314`, `0x425a939c`, and `0x425b867c`. Decoding the
34 key-range pairs in target endianness yields the same 33 intervals on both
architectures. Decoding the 31,088 signed weight values to canonical
little-endian form yields different table digests: PPC
`91eeae04de26b56430af73ad0c147be7cbed0a863561ced69ed6abce9b170750`, i386
`ebc6ea925193a5173f823cccac28017caafae6de608b1fa07d12c1a5c88b72c9`. The
arrays differ at 242 values across 242 rows: 10 field-0 values and 232
field-2 values. The field-0 differences occur for U+002D, U+00B6, U+0386,
U+0588, U+06D3, U+2023, U+3001, U+FE51, U+FF0D, and U+FF60; each is 0 in PPC
and 1 in i386. Field 2 supplies the comparator's secondary weight. Thus the
current i386-derived include does not reproduce the PPC table even though the
ranges and comparator control flow match. The current helper needs target-
specific weight data before it is faithful on both supported architectures.
No comparator code or ABI files changed.

### Locale comparator architecture-specific data and ligature-layout correction (2026-10-05)

Corrected the comparator's table extraction against both live IDA databases. The
PPC and i386 key ranges are semantically identical, but their 7,772-row weight
tables differ at 242 values. Added a PPC-only weight include selected by the
project's `__ppc__` / `__POWERPC__` macros while keeping the i386 table for the
other target. The canonical SHA-256 values, including the shared four-weight
fallback row, are i386 `3b65b6b8752ebbaa12295060f1c14d3bbafb97d5b7aaba53f775b0f5ea1e3463`
and PPC `1e12202f4fc1117698cc72fd9e5502d7949e24f4db298433465d384a9368e426`.

The prior 1,302-record map with separately extracted link fields and UTF-16
units was not the target's runtime table layout. Both binaries index the
ligature rows directly as five signed shorts: a signed length/link followed by
four UTF-16 units. A nonpositive length contributes four units; a negative
length links to row `-length`. The first 1,316 rows are byte-for-byte equal
between targets after endian normalization, SHA-256
`0e3d7744788896b891bf1c54f364c2655444a6601c0fad90f1424195dff7b8ef`. Both
weight tables select 1,294 direct rows, and following negative lengths reaches
all 1,316 rows with maximum chain depth four, no out-of-range links, and no
cycles. Replaced the source's sorted lookup/next-index model with this direct
layout and shared table. The previous `482760...` extracted-record digest is
not a valid runtime-table fingerprint and should be disregarded.

Static parsing of the generated includes matches all three IDA digests and
row counts. No ABI changes or tests/builds were made.

### NSJavaSetup exported TODOs (2026-10-05)

The two source TODOs at `NSJavaSetupVirtualMachine` and `NSJavaObjectNamedInPath` are not uniform cross-architecture gaps. Current IDA databases show neither function in the i386 Foundation binary. PPC defines `_NSJavaObjectNamedInPath` at `0x4257c89c` and `_NSJavaSetupVirtualMachine` at `0x4257cae0`.

PPC `_NSJavaObjectNamedInPath(name, path)` gets a class loader with `NSJavaClassLoaderForPath(path, YES)`, resolves the class named by `_NSJavaPathResourceLocatorClassName`, and returns `-[class instantiate::](loader, name)`. This is a narrow implementation using existing Java loader support, but behavior would be PPC-only because i386 has no corresponding symbol.

PPC `_NSJavaSetupVirtualMachine()` copies the main bundle's info dictionary, sets `NSJavaOwnVirtualMachine` to true, calls `NSJavaSetup`, releases the copy, and returns that result. This wrapper delegates into the existing source `NSJavaSetup` / `NSJavaBundleSetup` implementation, which still has known divergence from PPC's fast setup path. Implementing the wrapper is mechanically bounded, but the returned behavior will inherit that broader path divergence.

Fresh decompilation of `_NSJavaSetupVirtualMachine` at `0x4257cae0` confirms the exact wrapper: obtain `[NSBundle mainBundle]`, copy its `infoDictionary`, set `NSJavaOwnVirtualMachine` to the constant string `@"YES"`, call `NSJavaSetup` with the copy, release the copy, and return the setup result. The shallow wrapper is fully understood; the unresolved fidelity remains in the delegated `NSJavaBundleSetup` fast branch and its supporting bundle state.

No source or ABI changes were made. Before implementation, decide whether to (a) add only the two PPC-confirmed wrappers, documenting their architecture coverage and existing delegated-path limitation, or (b) leave them deferred until the fast Java bundle setup design is resolved. The target does not support adding either symbol to i386 on this evidence.

### `_NSJavaObjectNamedInPath` PPC implementation (2026-10-05)

Following the approved bounded design, `NSJavaObjectNamedInPath` now implements
the PPC call path and its declaration and definition are guarded by the PPC
compiler macros. It delegates to the existing `NSJavaClassLoaderForPath(path,
YES)` helper, resolves the existing path-resource-locator class name, and sends
`instantiate::` with the loader and requested name. The i386 ABI manifest and
shared symbol inventory remain unchanged; the PPC-only export is documented in
`reconstruction/divergences.md`. `_NSJavaSetupVirtualMachine` remains an
unimplemented TODO pending resolution of the delegated fast-setup divergence.
Static source checks only; no tests or builds were run.

### PPC Java fast-setup divergence recheck (2026-10-05)

The PPC `_NSJavaBundleSetup` at `0x4257bb14` checks the
`_usesFastJavaBundleSetup` flag before its normal initialization path and
returns `_NSFastJavaBundleSetup` when the flag is set. The current source
`NSJavaBundleSetup` has no corresponding flag check or fast-path implementation.
In the normal path, PPC enumerates `allFrameworks` before `allBundles`, while
the source currently appends `allBundles` before `allFrameworks`. The fast
implementation at `0x4257dd78` builds its own VM class path and invokes
`NSJavaClassLoaderForPath` with an empty array; the source always combines the
configured paths, VM default class path, and user paths before VM creation.
These differences confirm that simply adding the PPC
`_NSJavaSetupVirtualMachine` wrapper would inherit unresolved setup behavior.
No source change was made for this recheck.

### Normal Java bundle enumeration order correction (2026-10-06)

The non-fast `_NSJavaBundleSetup` path has a confirmed architecture-specific
load order. PPC `0x4257bb14` appends `[NSBundle allFrameworks]` before
`[NSBundle allBundles]`; i386 `0x425554a0` appends all bundles before all
frameworks. `NSJavaSetup.m` now selects that order with the existing PPC
compiler guard and retains the i386 sequence. The order affects the sequence
of bundle `load` messages after VM creation. No selectors or ABI records
changed; no tests or builds were run.

The global flag at `0x426260c0` is initialized to `1`. The target's
`_NSJavaSpecifiedClassesForBundle` at `0x4257cb78` uses the same flag to choose
between global fast setup and per-bundle loading: when fast setup is disabled,
it removes `NSJavaPath`, `NSJavaUserPath`, and `NSJavaClasses` before creating
the VM, then separately loads the requested and discovered classes. The fast
helper's `_NSJavaPathCompsForBundle` at `0x4257ea94` resolves a bundle's
definitive setup dictionary and returns either its absolute `NSJavaPath` or
its array-valued `NSJavaUserPath`. The PPC bundle methods also include
`+[NSBundle _setUsesFastJavaBundleSetup:]`,
`+[NSBundle _usesFastJavaBundleSetup]`, and
`-[NSBundle _setJavaClassesLoaded]`; the first two read/write the shared
default-true global, and the last sets `_flags |= 0x60000000`. The current
source lacks these selectors and both fast helpers. These call paths make the
repair a coordinated PPC-only NSBundle/NSJavaSetup change, not a standalone
wrapper.

`_NSJavaSpecifiedClassesForBundle` also has a flag-dependent contract. With no
VM and fast mode enabled, it leaves `NSJavaPath`, `NSJavaUserPath`, and
`NSJavaClasses` in the setup dictionary so the global fast helper consumes
them. With fast mode disabled, it removes those keys for VM setup and then
does per-bundle class-loader work; a supplied class list is loaded explicitly,
while a null list requests classes discovered from the resource locator. The
current source always removes all three keys during first VM setup and then
does per-bundle loading regardless of mode. `_NSBundleLoadJavaCode` already
matches the target's high-bit short circuit, so the fast-path change can reuse
that bundle-loading behavior after the new marker selector sets the bits.

Architecture-specific ABI recording can use the existing verifier without
changing its schema: `abi-v1` has no architecture field, while
`abi-check --abi-dir` reads only the JSON files in the supplied directory and
`abi` accepts a caller-selected `--symbols` map. A PPC baseline can therefore
live in a dedicated `reconstruction/abi-ppc/` directory with a matching
PPC-specific symbol assignment, leaving `reconstruction/abi/` and
`reconstruction/symbols.json` as the existing i386 baseline. The PPC check
must use PPC-built objects.

The live i386 and PPC databases also confirm a pre-existing Java data-symbol
gap. Both export `_NSJavaBundleClassLoaderClassName`,
`_NSJavaStandardClassLoaderClassName`, and
`_NSJavaPathResourceLocatorClassName`; their constant strings are
`com.apple.misc.BundleClassLoader`, `com.apple.misc.StandardClassLoader`, and
`com.apple.util.PathResourceLocator`, respectively. `NSJavaSetup.json` records
all three data symbols, but the source makes the first and third constants
`static` and does not define the standard-loader constant. This should be
handled in the Java ABI scope alongside the PPC fast-path work; the exported
`NSJavaPathSeparator` is already present in source.

Source cross-check for the task getter: `NSTask.m` stores the `vfork()` result in `NSConcreteTask::_pid` and its existing private `-_procid` returns that field. The PPC IDA body for `-[NSConcreteTask processIdentifier]` is exactly `return self->_pid;`. Added the selector to the public header and implementation under PPC compiler guards, and recorded the architecture-specific availability in `reconstruction/divergences.md`; the shared i386 ABI manifest remains unchanged. Static source checks only; no tests or builds were run.

### PPC Java fast-setup ABI encoding recheck (2026-10-05)

Freshly extracted the PPC `NSBundle` and `NSJavaSetup` ABI manifests to check
category ownership and Objective-C encodings. The three fast-setup selectors
are emitted under the `_NSJavaSetupPrivate` category on `NSBundle` in
`NSJavaSetup.m`, not under the `NSBundle.m` module: the class methods encode as
`_setUsesFastJavaBundleSetup:` `v5@4:8c12` and `_usesFastJavaBundleSetup`
`i4@4:8`, while `_setJavaClassesLoaded` encodes as `v4@4:8`. The fresh PPC
`NSJavaSetup.json` also confirms all three loader class-name constants are
owned by that module. The extracted manifests were kept in the temporary ABI
output directory; no tracked ABI baseline or source was changed by this check.

### Java class-name data exports implemented (2026-10-05)

Resolved the Java data-symbol gap recorded above: both target architectures
export all three class-name constants, while the previous source made the
bundle-loader and path-resource-locator definitions `static` and omitted the
standard-loader definition. The source now declares and defines the three
constants with their IDA-confirmed string values, and `ownership.json` records
`NSJavaSetup.m` as their source module. The shared ABI manifest and symbol
assignment already listed the exports and remain unchanged. `git diff --check`
passed; no tests or builds were run.

### PPC-only `NSString` UTF-8 convenience implementations (2026-10-05)

Implemented the three methods confirmed at PPC addresses `0x425a75cc`,
`0x425a79dc`, and `0x4259f488` under PowerPC compiler guards in
`NSStringEncodings.m`, and guarded their existing header declarations. The
initializers/factory compute the NUL-terminated input length and delegate to
`initWithBytes:length:encoding:` with encoding 4; the factory allocates in the
default zone and autoreleases. The `bytesInEncoding` helper follows IDA's
1,000-byte stack path for strings of at most 165 UTF-16 units, then the
two-pass size/query and conversion path through `_NSAutoreleasedMallocMemory`;
conversion failure raises `NSCharacterConversionException`. The DR2 i386 IDA
string list contains none of the three selectors, so the i386 ABI baseline was
left unchanged. Static source checks only; no tests or builds were run.

### PPC NSString UTF-8 method ownership correction (2026-10-05)

Re-extracted Objective-C ownership from the live MOSXS PPC method lists with
`objc_method_index`. `+[NSString stringWithUTF8String:]` at `0x4259f488` and
`-[NSString initWithUTF8String:]` at `0x425a75cc` belong to the primary
`NSString` class. `-[NSString(NSStringOtherEncodings) UTF8String]` at
`0x425a79dc` belongs to the `NSStringOtherEncodings` category. The i386 target
has no corresponding NSString selectors. Moved only the factory and
initializer into the guarded primary `NSString` implementation in
`NSString.m`; `UTF8String` remains in `NSStringEncodings.m` with its private
`bytesInEncoding` helper. This corrects the earlier implementation placement
without changing method bodies or the shared i386 ABI baseline. Static
selector/source checks only; no tests or builds were run.

### PPC-only undo light-invocation argument getter (2026-10-05)

The MOSXS PowerPC target implements `-[_NSUndoLightInvocation _argument]` at
`0x4257afb8` as a direct return of `_arg`; the DR2 i386 database has no method
with that name. Added the private declaration and direct getter under PPC
compiler guards in `NSUndoManager.m`, and recorded the target-specific selector
in `reconstruction/divergences.md`. No ivar or ownership changes were needed;
the existing initializer retains `_arg`. Static selector/source checks only;
no tests or builds were run.

### PPC-only undo-manager stack accessor (2026-10-05)

IDA decompiles `-[NSUndoManager _undoStack]` at `0x4256184c` as a direct return
of the `_undoStack` ivar; the DR2 i386 database has no corresponding method.
Added the private declaration and getter under PPC compiler guards in the
existing `NSUndoManagerPrivate` category, with no storage change. The selector
is recorded in `reconstruction/divergences.md`; the shared i386 ABI manifest
remains unchanged. Static selector/source checks only; no tests or builds were
run.

The fresh PPC raw selector audit now reports 3,397 reference selectors and
3,306 source definitions, with zero renames or duplicates and 123 missing
selectors. The two PPC-only undo accessors account for two fewer missing
selectors than the preceding audit; remaining gaps are independently listed
above and include the broader Java fast-setup and URL/HTTP work.

### `NSConcretePortCoder` debug-description architecture correction (2026-10-05)

The live DR2 i386 IDA body is `+[NSConcretePortCoder debugDescription]` at
`0x42566ce8`; MOSXS PPC instead implements
`-[NSConcretePortCoder debugDescription]` at `0x425733d4`. Both format the
same connection, components, imported-object table, component index, message
ID, and bycopy/byref/valid flags. Updated `NSPortCoder.m` to preserve the i386
class method and compile the instance method only for PPC. The existing shared
ABI record remains the i386 baseline. Static source/selector checks only; no
tests or builds were run.

The subsequent raw `selector_check.py` run reports 122 missing selectors,
zero renames, and zero duplicates. It scans source text without evaluating
architecture preprocessor branches, so it also reports the preserved i386
class-method branch as a source-only PPC entry; architecture-specific
correctness remains the guarded-source plus per-target IDA evidence.

### PPC-only distributed-notification logging setter (2026-10-05)

The MOSXS PPC IDA body for `+[NSDistributedNotificationCenter
enableLogging:]` at `0x425776f0` saves the BOOL argument with one byte store
to local data symbol `__NSDistributedNotificationCenterLogging` at
`0x426260b4`. That byte is zero-initialized, and IDA reports no xrefs to it;
the setter itself performs no logging work. The DR2 i386 database has no
function by this selector. Added the PPC-guarded class declaration and setter,
backed by the same local byte, without changing the shared i386 ABI or symbol
map. The PPC selector audit now reports 3,397 reference selectors and 3,308
source definitions, with 121 missing, zero renames, and zero duplicates. The
audit scans source text without preprocessing, so the guarded method still
appears as an extra when comparing against i386.

### `NSCoder` NXObject methods matched across architectures (2026-10-05)

Fresh IDA pseudocode shows the NXObject methods differ by target. DR2 i386's
`-[NSCoder encodeNXObject:]` writes a root object with
`NXWriteRootObjectToBuffer`, wraps the result with `_NSNewImmutableData`, sends
`encodeDataObject:`, then releases the data and frees the typedstream buffer.
Its decoder obtains `decodeDataObject`, then calls
`NXReadObjectFromBuffer(bytes, length)`. MOSXS PPC instead creates archived
data with `+[NSArchiver archivedDataWithRootObject:]` and sends it through
`encodeDataObject:`; decode uses `+[NSUnarchiver unarchiveObjectWithData:]`.
Both targets issue the same one-time compatibility warning per method, but the
i386 binary owns the methods through the
`NSCoder(NSTypedstreamCompatibility)` category while PPC places them on the
primary `NSCoder` class.

`NSCompatibility.m` now preserves the i386 typedstream bodies under an
i386-only guard, and `NSCoder.m` supplies the PPC primary-class methods under a
PPC guard. The existing `NSCompatibility.json` category record remains the
i386 ABI baseline. The PPC selector audit reports 3,397 reference selectors
and 3,311 source definitions, with 118 missing and zero renames or duplicates;
it scans raw source and therefore still lists the inactive i386 category pair
as source-only entries. Static source and whitespace checks passed. No tests or
builds were run.

### Current i386 exported C-symbol audit (2026-10-05)

Ran `binrecon symbol-audit` with `profiles/foundation-i386.json`, the pinned
`Foundation-i386` reference, and the current `reconstruction/symbols.json`.
The audit reports one unclaimed exported function: `_NSRecordAllocationEvent`.
`NSDebug.h` declares it, but `NSDebug.m` has no production definition; the
only non-header occurrence outside call sites is a test-only no-op stub in
`reconstruction/tests/link_stubs.m`. The existing IDA trace documents its
sender body, but faithful implementation still depends on the record-lock
lifecycle and the target's per-thread autorelease-pool list described above.
No tests or builds were run.

### Live i386 allocation-event sender recheck (2026-10-05)

Queried the attached Foundation-i386 IDA database at `0x4256fae4` and
`0x42571124`. The public entry forwards its two machine-level arguments to
the separate sender core. The core first handles negative-retain checks for
event types 3, 5, and 7, then gates output with
`(1 << eventType) & NSAllocationStatisticsOutputMask`. When enabled, it uses
the optional `__NSDebugRecordLock`, resolves
`NSAllocationStatisticsOutputPortName` through `netname_look_up`, and dispatches
event types through a jump table. The current source already supplies the lock
lifecycle; the remaining known semantic mismatch is the sender's per-thread
autorelease-pool count versus the reconstruction's process-global pool stack.
No implementation or manifest changes were made; sender implementation still
awaits design approval.

### NSWalkData review finding reconciliation (2026-10-05)

Rechecked the completed review against the current `NSSerialization.m` and the
approved `NSWalkData` design. The seven reported mismatches are already
addressed in the current source: `NSWalkDataArchiveContext` has the target
fields and offsets; operation 4 serializes `*` through `NSData` with
`strlen + 1` without replacing the caller pointer; arrays advance by each
recursive return size; object callback selection uses `callbackMode`; `%`
decoding uses `_NSUniqueCString`; bycopy/byref root pointers validate an
object pointee; and unsupported `B`/`?` encodings reach the invalid-type
branch. The review's cited line numbers map to different current code, so it
was based on an earlier source snapshot. No code or ABI changes were needed.
No tests or builds were run.

### NSPathStore2 workspace review finding reconciliation (2026-10-05)

Checked the completed path review's claim that the two `NSPathStore2` wrappers
truncate their input copy to 1,024 UTF-16 units but pass the original length
to the helpers. In the current `NSPathUtilities.m`, both methods allocate
`max(length, 1024) + 1` units and copy the full input before calling helpers
with output/resolution capacity 1,024. The generic `NSString` category does
clamp its stack-buffer copy to 1,024, but resets `length` to `copyLength` before
calling either helper. The alleged mismatch is absent in the current source;
this review item refers to an earlier snapshot. No source or ABI changes were
needed. No tests or builds were run.

### PPC `NSInvocation` factory gap decompilation (2026-10-05)

The refreshed PPC selector audit reports `+[NSInvocation
newInvocationWithMethodSignature:]` as missing. It is a PPC text symbol at
`0x42523884` (local binding in the linked image); the i386 Foundation binary
has no corresponding `__TEXT,__text` method symbol. The PPC factory allocates
the invocation with `NSAllocateObject`,
using the method signature's frame length as extra inline bytes, sets the
argument-frame ivar to the address immediately after the class instance, then
sends `initWithMethodSignature:` and returns its result. PPC
`-[NSInvocation initWithMethodSignature:]` stores the signature and only calls
`establishArgumentFrame` when the argument-frame ivar is null. Current
`NSInvocation.m` instead allocates a standalone argument frame in its shared
initializer, and `NSInvocation.json` has no `newInvocationWithMethodSignature:`
ABI entry. This selector therefore cannot be added faithfully as a simple
`alloc`/`init` alias; its PPC inline-frame layout and initializer interaction
need a design before implementation. No source or ABI changes were made.
No tests or builds were run.

The matching i386 initializer at `0x4252298c` and PPC initializer at
`0x42525774` also dispatch on the signature's return-type encoding. Scalar
types initialize the `NSObjCValue` tag; struct returns allocate and zero
`methodReturnLength` bytes for return storage. In both binaries,
`establishArgumentFrame` allocates `frameLength` bytes from `[self zone]`,
zeroes the frame, and marks the frame as owned (i386 byte flag `+28 |= 0x10`,
PPC word flag `+28 |= 0x08000000`). `-[NSInvocation dealloc]` frees the argument
frame only when that ownership bit is set. The PPC factory's inline frame
leaves the bit clear, so deallocation does not free memory inside the object.
The current source initializer allocates with the default zone, does not zero
the frame, and does not initialize the return-value tag/storage from the
signature; its inverse `externalArgFrame` bit expresses the ownership condition
in `dealloc` and `_setArgFrame:`. This confirms that reconstructing the PPC
factory alone would leave the shared initializer's already-visible i386 gaps
unresolved.

### PPC notification removal serialization gap (2026-10-05)

The missing PPC selector `+[NSNotificationCenter
setNotificationCenterSerializeRemoves:]` at `0x4257778c` stores its BOOL byte
in `___NSNotificationCenterSerializeRemoves` at `0x426260cc`; the global's
initial byte is 1 in `__data`. This is not an isolated setter. PPC
`_postNotification` (`0x425270b0`) checks the flag before delivery, registers
per-center post records with `_init_post_info` (`0x42581044`), unlocks the
center while observers run, then relocks, removes the record with
`_clear_post_info` (`0x42580d54`), broadcasts, and unlocks. The PPC
`removeObserver:name:object:` path (`0x4251cb34`) checks the same flag and
waits through `_wait_while_posting` (`0x42581508`); `_is_in_posting`
(`0x425811f8`) avoids self-deadlock by clearing matching observer entries for
the current thread before scanning other active posts.

Current `NSNotification.m` has no serialization global or setter. Its posting
helper invokes observers without post-record tracking, and removal only locks
while mutating the registry; it does not wait for in-flight delivery. Thus
adding just the missing selector would not reproduce the PPC contract. The
reconstruction slice needs a design spanning the flag, post records, callback
delivery, and removal wait path, with PPC-only ABI treatment. No source or ABI
changes were made. An exact-image i386 symbol scan confirms that the setter
and data export are absent from that target.

The i386 class factory at `0x4251fbb0` also allocates with
`NSAllocateObject(class, signature frameLength, NULL)`, installs the inline
argument-frame pointer at the object's extra-byte boundary, calls
`initWithMethodSignature:`, and autoreleases the result. PPC's
`+[NSInvocation invocationWithMethodSignature:]` at `0x4258220c` instead calls
`+[NSInvocation newInvocationWithMethodSignature:]` and autoreleases that
result. The current source's single `invocationWithMethodSignature:` path uses
`allocWithZone:` and the shared initializer's standalone heap allocation, so
it reproduces neither factory's storage layout. A faithful follow-up needs the
i386 factory body preserved, the PPC new factory plus its autorelease wrapper,
and initializer logic that retains a preinstalled inline frame without
replacing it; ABI registration must remain architecture-aware because the
`new...` selector does not exist in i386.

### Locale comparator stale record-type cleanup (2026-10-05)

The direct five-short ligature-table conversion left two checks in
`NSStringLocalizedCompare.m` using the removed `NSLocaleLigatureRecord` type.
Replaced these locals with direct null checks of `NSLocaleLigatureForIndex`,
whose current return type is `const short *`. Static source inspection confirms
there are no remaining references to the removed type and no trailing
whitespace. No tests or builds were run.

### PPC NSURLHandle base-method decompilation (2026-10-05)

Re-decompiled the MOSXS PPC `NSURLHandle` base methods from the live IDA
image. `-[NSURLHandle status]` at `0x425b6898` returns `_status` directly.
`-[NSURLHandle availableResourceData]` at `0x425b65bc` returns `_data` for
statuses 0, 1, and 2, and nil for `NSURLHandleLoadFailed` (3). These bodies use
only the existing public ivars in `NSURLHandle.h` and do not depend on a
concrete file or HTTP handler. In contrast, `resourceData`, client delivery,
background load transitions, and registry/cache methods call one another and
require coordinated behavior; the abstract primitive methods intentionally
raise the concrete-implementation request. The class is PPC-only in the
MOSXS ABI baseline. No source or ABI changes were made.

### DR2 Foundation selector audit refresh (2026-10-05)

Re-ran `selector_check.py` against the current Foundation sources for the
Foundation-i386 reference and separately extracted PPC slice of the DR2 fat
Foundation binary. Both report 3,253 reference selectors and 3,316 source
definitions, with zero missing, renamed, or duplicate selectors and 63 extras.
The tool scans raw source without preprocessing, so architecture-guarded
methods count as source definitions for both comparisons. This is the DR2
PPC slice, not the separate MOSXS PPC image used for PPC-specific ABI work.
No source or ABI changes were made from this audit; no tests or builds were
run.

### MOSXS PPC exported C-symbol audit (2026-10-05)

Audited the live MOSXS PPC Foundation image at
`C:\Users\raynorpat\Downloads\test\Frameworks\Foundation.framework\Versions\C\Foundation`
against the shared source-symbol assignment. The image is PPC big-endian and
has ten unclaimed exported functions after adding the already-implemented
`_NSJavaObjectNamedInPath` and `_NSJavaSetupVirtualMachine` definitions to
`symbols.json`. The remaining exports are `_NSJavaGetSystemProperty`,
`_NSJavaGetSystemPropertyOrUseDefault`, `_NSJavaSetSystemProperty`,
`_NSRecordAllocationEvent`, `__NSCStringToUnsignedLong`,
`__NSExceptionRaiser`, `__NSFastJavaBundleSetup`, `__NSSetExceptionRaiser`,
`__NSstrtod`, and `__NSvsnprintf`. The i386 audit remains at one unclaimed
export, `_NSRecordAllocationEvent`. No tests or builds were run.

The three unclaimed Java property exports are thin wrappers around the runtime
bridge: `NSJavaGetSystemProperty` at `0x4257c820` calls
`NSJavaGetSystemPropertyOrUseDefault` with a null default; the latter at
`0x4257c844` initializes the VM, resolves the bridge class, and sends
`getProperty::`; `NSJavaSetSystemProperty` at `0x4257ca34` initializes the VM,
gets the properties object, sends `put` with the key and value, then sends
`setProperties:`. These depend on the existing PPC
`NSJavaSetupVirtualMachine` implementation, whose setup behavior diverges from
the target's delegated path, and therefore need a separate fidelity decision
before adding the wrappers.

### MOSXS PPC exception-raiser exports (2026-10-05)

IDA decompiles `__NSExceptionRaiser` at `0x425861f0` as a getter for the
function pointer stored in `___NSExceptionRaiser` at `0x42626348`.
`__NSSetExceptionRaiser` at `0x425867e8` stores its callback argument there,
substitutes `_NSRaiseError` when passed null, and returns the original argument.
The current `NSException.m` defines `_NSRaiseError` and calls it directly from
`-raise` and internal assertion paths; it has no replaceable raiser pointer.
A faithful slice therefore needs both exported functions and routing from the
PPC exception-raise path through the pointer. The i386 ABI remains unchanged.
No source or ABI changes were made for this analysis.

Implemented the getter and setter in `NSException.m` under the PPC compiler
guard, initialized the local callback pointer to `_NSRaiseError`, and routed
PPC `-[NSException raise]` through that pointer. The i386 body still calls
`_NSRaiseError` directly. Updated the class convenience and assertion
exception paths to dispatch through `-[NSException raise]`, matching both
reference architectures and honoring the PPC callback. Added the two exports
to the PPC ABI overlay, shared symbol assignment, and ownership map. The live
PPC symbol audit now reports eight unclaimed functions; the i386 audit remains
at one. JSON parsing and `git diff --check` passed; no tests or builds were
run.

### MOSXS PPC Java system-property wrappers (2026-10-05)

Recovered the bridge class constant as `java/lang/System` from the PPC
constant-string record at `0x4262a770`; its selectors are `getProperty::`,
`getProperties`, `put::`, and `setProperties:`. Implemented the three thin C
wrappers in `NSJavaSetup.m` under PPC guards. The default getter delegates to
the two-argument getter with nil; both getters and the setter invoke
`NSJavaSetupVirtualMachine` before messaging the bridge class. Registered the
exports in `NSJavaSetup.h`, the PPC ABI overlay, shared symbol map, ownership
map, and divergence record. The live MOSXS PPC audit now reports five
unclaimed functions; the i386 audit remains at `_NSRecordAllocationEvent`.
Static metadata checks and `git diff --check` passed; no tests or builds were
run. The wrappers inherit the existing delegated VM-setup fidelity gap.

### i386/PPC allocation-event reconstruction (2026-10-05)

Implemented the exported `NSRecordAllocationEvent` path in `NSDebug.m` for both
targets, plus target-sized receive buffers and timestamp parsing. The i386
packet is 7,608 bytes with raw template dwords at byte offsets 0, 24, 164, and
196: `00000001`, `09088810`, `02200710`, and `0a409e13`. The PPC packet is
3,512 bytes with corresponding raw template bytes `00000001`, `09080888`,
`02200078`, and `0a4019e8`. The packet reserves 248 bytes before frame pairs,
so the target limits are 920 i386 frames and 408 PPC frames.

The source now routes object, Java, zone, and VM payloads using the IDA cases;
preserves the event-11 class-name read from its third variadic argument; does
the target-specific lock and host-buffer paths; and retries `msg_send` with
`0x20` only after `-103`. `NSThread.m` now models the PPC record lock as the
target's zero-initialized atomic word and retains the allocated `mutex_t` on
i386. The parser copies the native PPC timestamp and keeps the i386 word swap.

The negative-retain branch still calls the current process-global
`NSAutoreleasePoolCountForObject`; IDA confirms the original helper counts the
current thread's pool list. The pool-storage mismatch is documented in
`reconstruction/divergences.md`. The edited ABI, symbol, and ownership JSON
files parse successfully, and `git diff --check` reports no whitespace errors
(Git prints existing line-ending warnings for other modified files). No tests
or builds were run; runtime behavior remains unverified.

### Foundation C-symbol audit after allocation-event reconstruction (2026-10-05)

Re-ran `binrecon symbol-audit` against the DR2 i386 Foundation image and the
current shared `symbols.json`; it reports zero unclaimed exported functions,
including `_NSRecordAllocationEvent`. The MOSXS PPC audit note above listed
five unclaimed exports before the allocation-event implementation. With
`_NSRecordAllocationEvent` now assigned, the four remaining PPC exports are
`__NSCStringToUnsignedLong`, `__NSFastJavaBundleSetup`, `__NSstrtod`, and
`__NSvsnprintf`. The PPC list is derived by reconciling the earlier IDA export
inventory with the current symbol assignment; the i386 count comes from the
current `binrecon` audit command. No tests or builds were run.

### PPC fast Java bundle setup export analysis (2026-10-05)

IDA decompiles `__NSFastJavaBundleSetup` at `0x4257dd78` as a full Java VM and
bundle initialization path, not a thin wrapper. It obtains the Java VM bundle
and `NSJavaVirtualMachine` class, builds the class path from VM defaults,
configured paths, and Java-capable bundles/frameworks, posts the setup and VM
creation notifications, constructs the VM, adds native library paths, creates
the system class loader, marks Java bundles as loaded, loads explicitly named
classes, and posts the setup-complete notification.

The current `NSJavaBundleSetup` in `NSJavaSetup.m` uses a different path: it
builds one VM class path, loads other bundles, adds native library paths, and
loads requested classes, but does not perform the target's bundle class-path
collection, VM/class-loader notification sequence, or Java-bundle loaded-state
updates. Its bundle/framework enumeration order also differs. The helper
therefore cannot be represented faithfully by aliasing `NSJavaBundleSetup`;
reconstruction needs to address this existing Java setup divergence as a
coordinated PPC change. No source or ABI changes were made.

#### PPC fast setup call and state order recheck (2026-10-05)

Live IDA decompilation confirms `__NSFastJavaBundleSetup` spans
`0x4257dd78..0x4257e414` (1,692 bytes). It enters the setup path when
`_NSJavaVM` is nil or the supplied `NSJavaOwnVirtualMachine` value passes the
target's string-class check. It posts `NSJavaWillSetupVirtualMachineNotification`
before resolving the Java VM bundle; a missing bundle returns nil. After
building the definitive setup dictionary, it appends VM-default class paths,
user paths, then class paths from Java-providing frameworks followed by bundles
(with the target's two `_NSJavaPathCompsForBundle` results kept in separate
ordered arrays). It posts the will-create notification, initializes the VM
with the joined path, posts did-create even if initialization returned nil,
and returns immediately on that nil result. On success it stores `_NSJavaVM`
only if the global was nil, adds configured native-library paths to
`NSJavaVirtualMachine`, creates the system class loader, marks each Java bundle
loaded and sends its loaded notification, loads explicitly configured classes,
then posts `NSJavaDidSetupVirtualMachineNotification`. This confirms the helper
owns ordering and notification semantics across several existing helpers;
reusing `NSJavaBundleSetup` without restructuring that path would not match.

#### PPC fast-setup selector routing recheck (2026-10-06)

The live call graph shows `NSJavaBundleSetup` at `0x4257bb14` selects
`__NSFastJavaBundleSetup` when its `_usesFastJavaBundleSetup` global is
nonzero. `+[NSBundle _setUsesFastJavaBundleSetup:]` stores the normalized
Boolean value; `+[NSBundle _usesFastJavaBundleSetup]` returns the same flag.
`__NSInitializeStaticFrameworks` calls `_NSBundleLoadJavaCode` for each
eligible static framework and consults the getter when deciding whether to
log a Java-load failure. The current Foundation source has no definitions for
these two `NSBundle` selectors and does not route `NSJavaBundleSetup` through
the fast helper. A faithful reconstruction therefore requires the helper,
flag accessors, and setup-path routing as one PPC slice; changing only the C
export would leave the target's selector-controlled path unavailable. This
does not require changing the body of `NSJavaSetupVirtualMachine`, whose
existing delegated setup behavior remains a separate fidelity decision. No
source or ABI changes were made.

### PPC `__NSvsnprintf` formatter dependency analysis (2026-10-05)

IDA decompiles the public `__NSvsnprintf` at `0x425138d0` as a bounded
memory-stream adapter around the private `_NSvfprintf` at `0x425121b8`. The
adapter returns `-1` for a zero-sized buffer, initializes the stream with
`size - 1` writable bytes, delegates formatting, and NUL-terminates at the
stream's current output pointer. `_NSvfprintf` is a custom formatter with its
own format parsing and buffering path; it is not a call to libc `vfprintf`.

The current source's `_NSsnprintf` in `NSObjCRuntime.m` delegates directly to
libc `vsnprintf`. It therefore does not supply the target's `_NSvfprintf`
behavior, and a standalone `__NSvsnprintf` adapter would still route formatting
through the wrong implementation. A faithful reconstruction needs the private
formatter dependency as a coordinated PPC change. No source or ABI changes
were made.

### PPC `__NSstrtod` scanner dependency analysis (2026-10-05)

IDA shows the sole direct caller of `__NSstrtod` at `0x4252abdc` is
`__NSScanDoubleFromString` at `0x4252b948`. That scanner builds an ASCII token
using the locale's decimal separator, then calls the custom converter and
advances its scan location by the converter's returned end pointer. The
converter parses sign, decimal digits, fraction, and exponent itself, retains
up to sixteen significant digits for the initial estimate, and uses the
target's big-integer/double-rounding helpers for the final value. It sets
`errno` to 34 on overflow or underflow paths.

The current `NSScanner.m` scanner similarly builds a locale-adjusted buffer,
but calls libc `strtod` and uses libc's end pointer. Thus the exported PPC
helper and the scanner's rounding, accepted-input, range-error, and end-pointer
behavior form one fidelity slice. No source or ABI changes were made.

#### Converter dependency closure recheck (2026-10-05)

Re-decompiling `__NSstrtod` (`0x4252abdc`) confirms that its long-decimal
rounding path calls the private big-integer family `s2b`, `Balloc`, `Bfree`,
`d2b`, `i2b`, `pow5mult`, `mult`, `lshift`, `diff`, `cmp`, `ratio`, and `ulp`,
and uses the `tens`, `tinytens`, `bigtens`, and double power tables. A source
search found no definitions for those helpers in `src/Kits/Foundation`. The
scanner at `0x4252b948` is the converter's sole direct caller and consumes its
end pointer to advance the original scan location. Consequently, a libc
`strtod` substitution cannot reproduce the target's decimal-to-binary
rounding or consumption rules; a faithful PPC slice must include the helper
family and preserve the scanner's end-pointer integration. The i386 scanner
path remains outside this PPC-only export reconstruction. No source, ABI, or
symbol changes were made.

#### Live PPC lexical and range-path recheck (2026-10-05)

Re-decompiled `__NSstrtod` from the currently attached MOSXS PPC database at
`0x4252abdc`. The lexical path skips only the six ASCII C whitespace bytes,
accepts one sign, skips leading integer zeroes, and accumulates at most sixteen
significant decimal digits while tracking discarded fractional places. An
exponent is accepted only when followed by digits; otherwise the cursor rolls
back to the `e`/`E`. The exponent parser consumes the whole digit run and caps
its magnitude at 19,999. When no numeric token is accepted, the returned end
pointer is the original input pointer; successful parses store the first
unconsumed byte.

The fast conversion path uses the `tens`, `tinytens`, `bigtens`, and double
power tables. Longer inputs enter the binary rounding loop using the `Bigint`
helper family; overflow returns infinity with `errno = 34`, while underflow
returns zero with `errno = 34`. The live database maps the full helper family:
`_Balloc` (`0x4254d554`), `_d2b` (`0x4254f410`), `_Bfree` (`0x42550160`),
`_cmp` (`0x4255b488`), `_mult` (`0x4255eb88`), `_lshift` (`0x4255ef9c`),
`_i2b` (`0x42560700`), `_pow5mult` (`0x42560da0`), `_diff`
(`0x425ac954`), `_ratio` (`0x425acb74`), `_s2b` (`0x425acc10`), and `_ulp`
(`0x425acd04`). This pass made no source or ABI changes.

#### Transitive helper and allocator layout recheck (2026-10-06)

Decompiling the complete helper bodies shows three additional routines in the
closure: `_multadd` at `0x4255b4ec`, `_lo0bits` at `0x4254f640`,
`_hi0bits` at `0x42560e9c`, and `_b2d` at `0x425ac75c`. `_s2b` and
`_pow5mult` call `_multadd`; `_d2b` calls both bit-count routines; `_ratio`
calls `_b2d` twice. `_multadd` multiplies each 32-bit `Bigint` word
by a small factor, adds a carry, grows the allocation when necessary, and
returns the prior allocation to `_Bfree` after copying.

The recovered `Bigint` header is five 32-bit fields: freelist link at byte 0,
size class at 4, allocated word capacity at 8, sign at 12, and used word count
at 16; limbs begin at byte 20. `_Balloc(k)` reuses one of sixteen freelists or
allocates `20 + 4 * (1 << k)` bytes. `_Bfree` links the allocation back into
the list selected by its size class. `_pow5mult` lazily creates the first
cached square as 625 and extends its linked square chain as requested.

The converter's direct scaling tables are 23 `tens` values, five `bigtens`
values, and five `tinytens` powers. The initial estimate's combine expression
uses an offset view into `_tens` for powers 10 through 10^7. Xrefs show
`_Balloc`, `_Bfree`, `_multadd`, `_hi0bits`, `_d2b`, `_b2d`, and related
arithmetic helpers are shared with `___dtoa`; the freelist and power-of-five
cache therefore form common subsystem state rather than converter-local
scratch. This transitive recheck expands the earlier helper closure; no source
or ABI changes were made.

### PPC allocation-event wait timeout conversion (2026-10-05)

A follow-up comparison of `NSWaitForAllocationEvent` at PPC `0x4257d5ac`
found that its timeout conversion is not a direct double-to-unsigned cast.
IDA computes `milliseconds = timeout * 1000.0`; for values at or above
`2147483648.0`, it converts `milliseconds - 2147483648.0` to signed `int` and
XORs the result with `0x80000000`; lower values convert through signed `int`
and then to `msg_timeout_t`. This preserves the high half of the unsigned
32-bit timeout range. The source now mirrors that PPC path and preserves the
existing direct conversion on i386. The 3,512-byte receive buffer and
message-copy path were already aligned. No tests or builds were run.

### Allocation-event unsupported-ID dispatch recheck (2026-10-05)

A follow-up pseudocode read of both senders corrected the preceding
interpretation: the output-mask test, record lock, and lazy output-port lookup
run before the event switch. IDs 12–15 and values above 24 reach the switch
default and emit no packet; when the mask bit is enabled, they still perform
the preceding lock/lookup work. The source now preserves that order. The mask
shift explicitly uses the target's 5-bit shift count behavior for out-of-range
event values. No tests or builds were run.

### Allocation-event pool payload recheck (superseded 2026-10-07)

IDA call-site disassembly shows `NSPopAutoreleasePool` calls event IDs 8 and 9
with only the event ID argument on both i386 and PPC. The sender switch clears
its class-name object for those cases but leaves the first variadic register or
stack word as the packet pointer (`word 55`). That value is caller residue, not
a defined pool payload; the public `NSDebug.h` comments confirm the event calls
have no additional arguments. The earlier reconstruction emitted a zero
pointer as a defined approximation. On 2026-10-07, `NSDebug.m` was changed to
read the first variadic slot for events 8 and 9, matching the target's raw
packet field despite the source-level missing argument. The resulting value
remains ABI- and call-site-dependent.

### Allocation-event argument-dispatch order correction (2026-10-05)

Re-read the live i386 sender at `0x42571124` and PPC sender at `0x4257f0c8`
against the current `NSDebug.m`. Both targets perform the negative-retain
check, output-mask check, record-lock acquisition, and lazy output-port lookup
before dispatching event-specific arguments. The source previously consumed
the event varargs before checking the mask or resolving the port, which could
read arguments for suppressed or unsupported events. The switch now runs only
after the mask is enabled and a port is available. For enabled negative-retain
events 3, 5, and 7, the first object argument is read before the mask as the
target does, then reused by the later event switch rather than consumed twice.
No tests or builds were run.

### Fresh MOSXS PPC selector audit after current reconstruction updates (2026-10-05)

Re-ran `selector_check.py` against the live MOSXS PPC Foundation image and the
current source tree. It reports 3,397 reference selectors, 3,317 source method
definitions, zero renames or duplicates, and 110 raw missing selectors. Most
remaining entries are the concrete file/HTTP URL handlers (the previously
identified 97-method URL/HTTP cluster). Smaller independent gaps include the
fast Java bundle setup flag/helper cluster, decimal placeholder zone allocation,
`NSInvocation` inline-frame factories, notification-removal serialization,
and several `NSURL`/`NSURLHandle` methods. The raw report is category-sensitive
and includes parser artifacts such as semicolon suffixes; it is a backlog signal,
not a normalized completion count. No source or ABI changes were made.

### Current allocation-event source recheck against both live targets (2026-10-05)

Recompared `NSDebug.m` with the live i386 sender at `0x42571124` and PPC
sender at `0x4257f0c8`. Event-field routing matches for object allocation and
copy, retain-count changes, Java allocation/finalization, zone and VM events,
and the target-specific packet sizes, timestamp ordering, lock conditions,
host-name handling, trace caps, and send retry. IDs 8 and 9 still use zero for
the target's undefined caller-residue pointer, and the negative-retain path
still uses process-global autorelease counts instead of the target's
per-thread counts; both differences remain explicitly documented. No further
source mismatch was found. No tests or builds were run.

### Negative-retain autorelease-count correction (2026-10-08)

The preceding statement about process-global counts is stale. Both live IDA
senders call `NSAutoreleasePoolCountForObject(object)` in the negative-retain
path (i386 `0x42571124`, PPC `0x4257f0c8`). The current `NSDebug.m` calls that
same helper, and its implementation reads the current thread's autorelease
pages through `_NSCurrentThread()` in `NSAutoreleasePool.m`. The path therefore
uses per-thread counts as the targets do. No source change was needed. Static
paired IDA/source review only; no tests or builds were run.

### PPC `_NSCStringToUnsignedLong` behavior recheck (2026-10-05)

IDA places the unclaimed export at `0x4257d6a4`; its function ends at
`0x4257d910` (620 bytes). Its two incoming references are data references,
with no code callers in the live MOSXS PPC image. The parser skips current-
locale whitespace, accepts an optional sign, chooses decimal by default and
octal or hexadecimal after a leading zero, and checks multiply/add overflow
against `UINT_MAX`. On overflow it returns `UINT_MAX` and sets `errno` to 34;
otherwise a leading minus negates the unsigned result.

The end pointer is the first unconsumed byte in the ordinary parse path. The
decompiled pointer arithmetic also means that when a sign or `0x`/`0X` prefix
has been consumed but no valid digit follows, the end pointer is after that
sign or prefix. The target uses current-rune flags for whitespace, alphabetic,
and uppercase checks, and default-rune flags for digits. The repository's BSD
`ctype.h` maps `isspace`, `isalpha`, `isupper`, and `isdigit` to those same
locale tables/flags, so there is no need to duplicate rune-table access or
delegate the parse to `strtoul`. The lack of code callers means no Foundation
call path needs rewiring. `NSScanner.m` is a proposed source owner because it
already contains the C-string numeric parsers; that ownership choice is an
implementation design decision, not an IDA fact. No source or ABI changes
were made.

### Fresh MOSXS PPC export assignment audit (2026-10-05)

Compared all 730 IDA entries in the live MOSXS PPC Foundation image with the
current shared `symbols.json`. Thirty-five exported names are unassigned: four
text exports (`__NSCStringToUnsignedLong`, `__NSFastJavaBundleSetup`,
`__NSstrtod`, and `__NSvsnprintf`) and 31 data exports, including Java
notification strings, runtime globals, retain-lock globals, and padding
symbols. The earlier four-export backlog refers to text exports only; it did
not count data exports. The exact-profile i386 `binrecon symbol-audit` still
reports zero unclaimed exported functions. This pass made no source, ABI, or
symbol-assignment changes.

### PPC Java notification data-symbol assignments (2026-10-05)

Assigned the four Java setup/create notification strings already defined by
`NSJavaSetup.m` and present in the PPC export table. Added them to the PPC-only
`NSJavaSetup.json` data-symbol list, the shared source-symbol assignment, and
`ownership.json`; they remain absent from the i386 ABI manifest because the
i386 image does not export them. Rechecking all PPC entries leaves the same
four unassigned text exports and 27 unassigned data exports. JSON parsing,
source-definition uniqueness, ownership, and whitespace checks pass. No tests
or builds were run.

### PPC `_NSCStringToUnsignedLong` implementation (2026-10-05)

Implemented the unclaimed PPC parser in `NSScanner.m` under the PowerPC guard.
It preserves the IDA scan cursor, rune-locale classification, base selection,
overflow consumption, and cthread plus `errno` side effects. Added its export
to `abi-ppc/NSScanner.json`, `symbols.json`, and `ownership.json`, and recorded
the architecture difference in `reconstruction/divergences.md`. Static JSON,
ownership, symbol, and whitespace checks only; no tests or builds were run.


### Live PPC `__NSvsnprintf` formatter closure recheck (2026-10-06)

Re-decompiled `__NSvsnprintf` at `0x425138d0` and its callee
`__NSvfprintf` at `0x425121b8` from the attached MOSXS PPC database. The
wrapper returns `-1` for a zero-sized destination. Otherwise it builds the
target memory-stream state with `size - 1` writable bytes, delegates to
`__NSvfprintf`, writes a terminating NUL at the stream's current output
pointer, and returns the formatter result. Its callers include
`_SubstituteFormat`; `__NSsnprintf` also calls the same formatter directly.

`__NSvfprintf` is a substantial custom formatter rather than a thin libc
adapter. The observed body parses flags, width, precision, length modifiers,
and conversions; accumulates output segments through `___sprint`; uses
`___ultoa` and `___uqtoa` for integer forms; calls `_cvt` and `_exponent` for
floating forms; and calls `memchr` for bounded string precision. None of these
private formatter helpers is present as a Foundation source definition under
its observed name, and the current `_NSsnprintf` in `NSObjCRuntime.m` delegates
to libc `vsnprintf`. Therefore an isolated `__NSvsnprintf` wrapper would not
reconstruct target formatting behavior; a faithful slice needs the custom
formatter and its conversion/segment helpers together. No source or ABI
changes were made.

#### Decimal-conversion call closure (2026-10-06)

The live PPC IDA call graph confirms `___dtoa` calls `_Bfree`, `_d2b`,
`_Balloc`, `_i2b`, `_pow5mult`, `_mult`, `_hi0bits`, `_lshift`, `_cmp`,
`_multadd`, `_memmove`, `_quorem`, and `_diff`; `_quorem` calls only `_cmp`.
The formatter reaches `___dtoa` through `_cvt`, and `_exponent` has no
callees. All Bigint arithmetic helpers in that closure have existing
Foundation source owners. `_quorem` and the formatter routines remain the
unimplemented portion. The current shared symbol map leaves the PPC-only
`__NSFastJavaBundleSetup` and `__NSvsnprintf` text exports unassigned; the
latter belongs to the pending formatter design. The current exact-profile
i386 symbol audit reports zero unclaimed exported functions. No source or
metadata code was changed in this audit.

### PPC shared `Bigint` quotient/remainder helper (2026-10-06)

Implemented the private `_quorem` arithmetic helper as
`NSBigintQuoRem` in `NSBigint.m`. The PPC body at `0x4255b5e0` estimates a
quotient from the divisor's top limb, subtracts that multiple in place,
trims a zero top limb, then compares and subtracts the divisor once if the
estimate was low. The source helper uses the existing `NSBigintCompare` for
the comparison and remains internal: it adds no public symbol, ABI, or
ownership entry. The IDA call graph shows `_quorem` calls only `_cmp`, so its
dependency is already present. Static inspection and whitespace checks only;
no tests or builds were run.

### PPC URL selector audit parser correction (2026-10-06)

The fresh PPC selector audit reported URL methods as missing even though their
bodies were present. Source inspection found 13 method definitions in
`NSURL.m` and `NSURLHandle.m` written with a declaration semicolon before an
inline `//` comment; each intended opening brace was therefore inside the
comment. Moved the explanatory comments above the definitions and removed the
semicolons. Re-running the same audit changed its report from 21 missing and
29 extra selectors to 15 missing and 23 extra, with zero renames or
duplicates. The remaining missing selectors are separate reconstruction
gaps. `git diff --check` passed; no tests or builds were run.

### Concrete dictionary copy initializer (2026-10-06)

The refreshed PPC selector audit then isolated
`-[NSConcreteDictionary initWithDictionary:copyItems:]`. IDA confirms this
method in both the PPC image (`0x425278f4`) and i386 image (`0x42515034`):
concrete dictionary sources copy their simple-hash table into the receiver's
zone, copy every key, then either copy or retain each value according to
`copyItems`; other dictionary classes delegate to `NSDictionary`. Added the
missing `NSConcreteDictionary` override using the existing
`NSSimpleDictionaryInitializeFromConcreteDictionary` helper, which already
implements those branches and also serves the mutable concrete override. The
selector audit now reports zero missing i386 selectors and 14 missing PPC
selectors, with no renames or duplicates. `git diff --check` passed; no tests
or builds were run.

### PPC `NSString(NSURLPathUtilities)` gap decompilation (2026-10-06)

The current PPC selector audit still reports three unimplemented
`NSString` URL-path category methods. IDA locates them at
`urlPathRelativeToPath:` (`0x425b0a48`), `urlPathByAppendingComponent:`
(`0x425b0c64`), and `urlPathByDeletingLastComponent` (`0x425b0dd0`). The
append method consumes each leading `../` from the component while moving the
receiver path to its parent, trims trailing slashes from the remainder, and
joins the pieces with one slash. The
delete method searches backward for the last path separator, accounting for a
trailing slash, returns the substring through that separator, and returns an
empty string when no separator is found. The
relative method compares URL path components until the first difference,
retains the original receiver when the paths are equal or have no common
prefix, emits one `..` component per remaining base directory component,
appends the unmatched target components, and joins them with `/`. The source
category already uses the same Foundation string and array primitives, so the
PPC-only definitions can be added there without changing the shared path
standardizer.

### PPC `NSURL` equality and hashing gap recheck (2026-10-06)

IDA confirms `-[NSURL isEqual:]` at `0x425ad9b4` first checks that its argument
is an `NSURL`, then compares the two base URLs with nil-aware equality, and
finally compares the relative strings. `-[NSURL hash]` at `0x425adac4` sends
`relativeString`, then loads its next selector reference from `0x4262cf58`.
That word contains `0x4141d258`, which is outside every segment in the IDA
database; it therefore does not resolve to a selector string. The nearby
`unsignedShortValue` reference at `0x4262df58` is a different slot and was
incorrectly attributed to this method in an earlier note. The hash send remains
unresolved pending inspection of the original image's relocation/reference
data. The DR2 i386 image has no NSURL-specific `isEqual:` or `hash` body. The
earlier equality/hash analysis did not change source or ABI records.

The PPC hash selector value at `0x4262cf58` is `0x4141d258`, outside the mapped
image. That same value appears at `0x4263a408` as the selector entry paired
with the `-[NSString hash]` implementation at `0x42545f30`, and at
`0x4263a67c` paired with `-[NSURL hash]` at `0x425adac4`. The call in
`-[NSURL hash]` therefore sends `hash` to `relativeString`; the reconstructed
implementation returns that string's hash.

`-[NSURL URLRelativeToBaseURL:]` at `0x425aec78` first resolves both URLs and
compares scheme and host case-insensitively. It then compares their relative
strings, computes a relative path, standardizes it, preserves the suffix after
the parsed path range, and calls `+[NSURL URLWithString:relativeToURL:]`. One
path-accessor selector slot at `0x4262da4c` contains `0x4141d978`, outside the
mapped image. That same selector value appears in the `NSURL` method-list entry
whose implementation is `-[NSURL path]` at `0x425ae9c4`. The path body sends
`_absoluteURLPath` and then `standardizedNativePath`, identifying the accessor
used by `URLRelativeToBaseURL:` as `path`.

The DR2 i386 Foundation image does contain `-[NSURL relativePath]` at
`0x42595288` and its selector string at `0x42622d6d`. Its body parses the URL
path component and standardizes it. This provides cross-architecture context;
the PPC selector identity is established by its own method-list and body
references as described above.

### PPC invocation factory dependency recheck (2026-10-06)

A fresh selector audit against the attached MOSXS PPC image reports 3,397
reference selectors, 3,406 source definitions, zero renames or duplicates, and
14 missing selectors. The remaining missing list includes
`+[NSInvocation newInvocationWithMethodSignature:]` and
`-[NSURL initWithCoder:]` / `encodeWithCoder:` alongside the previously noted
URL path and equality gaps.

IDA decompiles `+[NSInvocation newInvocationWithMethodSignature:]` at
`0x42523884` as an allocation of `signature->frameLength` extra bytes, then
sets the invocation's `argumentFrame` field to the inline bytes at
`object + class->instance_size`, and calls `initWithMethodSignature:`. The PPC
initializer at `0x42525774` retains the signature and calls
`establishArgumentFrame` only when the frame pointer is null; only selected
return types take the separate allocation path. The current source initializer
unconditionally allocates an external frame, and the existing class factory
uses `allocWithZone:` plus `initWithMethodSignature:`. Therefore, adding only
the missing factory would not reproduce the PPC allocation and ownership
flow. A faithful slice must reconstruct the initializer's preallocated-frame
branch and align deallocation with the target's inline-versus-external frame
state before wiring the new factory. No source or ABI changes were made in
this analysis.

### PPC `NSDecimalNumberPlaceholder` zone allocator (2026-10-06)

Implemented the missing `+[NSDecimalNumberPlaceholder allocWithZone:]` in
`NSDecimalNumber.m` as a PPC-only forwarder to the existing per-zone
placeholder cache. This matches the target wrapper at `0x425b95c8`, which
passes its zone argument to `_NSDecimalNumberPlaceholderWithZone` and returns
the result. Added the PPC ABI class record and selector ownership entry, plus
the i386 availability divergence. The PPC audit now reports 13 missing
selectors, zero renames, and zero duplicates. The i386 audit remains at zero
missing selectors; its parser reports the guarded PPC method among architecture
extras because it does not evaluate preprocessor guards. JSON parsing and
`git diff --check` passed. No tests or builds were run.

### PPC notification removal serialization (2026-10-06)

Reconstructed `+[NSNotificationCenter setNotificationCenterSerializeRemoves:]`
and the PPC active-post list used by observer removal. IDA confirms the setter,
default-enabled flag, post-list linkage, same-thread self-removal handling, and
condition wait/broadcast flow. The callback snapshot pointer selects the stack
snapshot for up to 16 observers and the heap snapshot for larger posts. Added
the PPC ABI record, selector owner, and i386 availability divergence. Static
JSON, selector-ownership, and whitespace checks only; no tests or builds were
run.

### PPC fast Java bundle setup current-source recheck (2026-10-06)

Reopened the MOSXS PPC Foundation binary in IDA and rechecked
`__NSFastJavaBundleSetup` at `0x4257dd78..0x4257e414`, its caller
`NSJavaBundleSetup` at `0x4257bb14`, and the private
`__NSJavaPathCompsForBundle` helper at `0x4257ea94..0x4257eb48`. The fast
routine takes the incoming bundle and settings dictionary, builds its class
path from the definitive setup dictionary, JavaVM defaults, configured user
paths, and two ordered path lists returned for each Java-providing bundle or
framework. It posts the setup and VM-creation notifications, creates the VM,
adds native library paths, creates the system class loader, marks Java bundles
loaded, loads requested classes, and posts setup completion. Its caller checks
`_usesFastJavaBundleSetup` before entering the existing non-fast path and
passes the same bundle/settings arguments to the fast routine.

The path helper defaults a missing setup dictionary from the bundle's info
dictionary and normalizes it with `NSJavaDefinitiveSetupDictionary`; its flag
selects either absolute `NSJavaPath` entries or the type-checked
`NSJavaUserPath` entries. The existing source already defines the PPC flag,
`+[NSBundle _setUsesFastJavaBundleSetup:]`,
`+[NSBundle _usesFastJavaBundleSetup]`, and
`-[NSBundle _setJavaClassesLoaded]`. The missing source pieces are the path
helper, the fast setup body, and the flag-controlled routing in
`NSJavaBundleSetup`; the PPC `NSJavaSetup.json` overlay and symbol/ownership
records do not yet claim the `__NSFastJavaBundleSetup` export. This confirms
the prior note's call-graph and ordering analysis while correcting its stale
statement that the flag accessors and loaded-state hook are absent from source.
`NSJavaSetupVirtualMachine` remains outside the proposed slice. Re-running
`binrecon symbol-audit` against the current PPC reference and
`symbols.json` reports exactly one unclaimed exported function:
`__NSFastJavaBundleSetup`.

### PPC formatter implementation registration and adapter recheck (2026-10-06)

Rechecked `__NSvsnprintf` at `0x425138d0` against the current `NSPrintf.m`
adapter. The source matches the live PPC body: size zero returns `-1`; the
memory stream stores the destination pointer, `size - 1` writable bytes, flags
`0x0208`, and the same destination/size in its buffer record; it calls the
private formatter, writes a terminating NUL at the updated cursor, and returns
the formatter result. The `NSPrintfFile` field sequence gives these target
offsets directly. `NSObjCRuntime.m` routes only PPC `_NSsnprintf` through this
adapter; i386 remains on libc `vsnprintf`.

Static checks confirm one PPC ABI entry, one shared source-symbol assignment,
the `_NSvsnprintf` ownership entry for `NSPrintf.m`, one source definition,
and registration in both `PB.project` and `Makefile.preamble`. This corrects
the earlier backlog entries that described `__NSvsnprintf` as unimplemented
and unassigned; the large `_NSvfprintf` conversion engine still requires its
own full source-to-IDA verification. No tests or builds were run.

### PPC formatter vector writer IDA recheck (2026-10-06)

Compared `__sprint` at `0x42511f28..0x42511f7c` and `__sfvwrite` at
`0x42511f7c..0x42512180` with the corresponding `NSPrintf.m` helpers. The
source preserves the zero-vector fast return, clears vector state after a
flush, drains at most 1024 bytes per unbuffered write, and follows the target's
string-stream, buffered-stream, and callback-write branches. It also preserves
the target's successful line-buffered return without consuming the vectors,
and sets the file error flag on failed writes. No helper mismatch was found.
No tests or builds were run.

### PPC non-fast Java setup notifications (2026-10-06)

Rechecked `_NSJavaBundleSetup` at PPC `0x4257bb14` against the normal setup
path in `NSJavaSetup.m`. The PPC path posts
`NSJavaWillSetupVirtualMachineNotification` before resolving the VM bundle,
`NSJavaWillCreateVirtualMachineNotification` immediately before VM allocation
and initialization, `NSJavaDidCreateVirtualMachineNotification` immediately
after initialization (including a nil result), and
`NSJavaDidSetupVirtualMachineNotification` after loading configured classes.
The DR2 i386 function at `0x425554a0` has no corresponding posts. The source
now matches this architecture-specific sequence with PPC compiler guards;
the pre-existing PPC fast path remains unchanged. Static source and whitespace
checks only; no tests or builds were run.

### PPC formatter parser and integer-dispatch recheck (2026-10-06)

Compared the opening format scan and conversion dispatch of `_NSvfprintf` at
`0x425121b8` with `NSPrintf.m`. Literal-run vector creation and return-count
updates match. The flag parser agrees on space/plus precedence, alternate
form, negative dynamic width, negative dynamic precision, zero padding, and
decimal width/precision accumulation. The `h`, `l`, `q`, `L`, `D`, `O`, and
`U` modifiers set the target flag bits; integer argument selection and signed
negative handling agree for regular, short, long, and quad forms. `%e`/`%E`
default to seven significant digits, matching `DEFPREC + 1`; `%g`/`%G` use
`DEFPREC`. No mismatch was found in this parser and dispatch range. Floating
rounding remained to be compared separately. Final field emission and
unrecognized conversion behavior were checked in the follow-up below. No tests
or builds were run.

### PPC formatter floating-conversion recheck (2026-10-06)

Compared the floating dispatch and output sizing in `_NSvfprintf` at
`0x425121b8` with `NSPrintf.m`, and checked its `cvt`/`__dtoa` dependencies at
`0x4254f2e0` and `0x4254e138`. Precision defaults and `%g` fixed/scientific
selection agree. Exponent formatting, decimal-point sizing, sign propagation,
and the `f`/`e`/`g` output fragment control flow agree for finite-value paths.

One special-value behavior differs: the source returns `"NaN"` directly via
`isnan`, before enabling floating-point fragment output. The PPC formatter
only short-circuits infinity. Its `__dtoa` returns `"NaN"`, sets the decimal
position to `9999`, and reports a three-byte digit span; `_NSvfprintf` then
continues through ordinary sizing and emission (for example, `%f` uses the
large decimal position when padding). This is an IDA-confirmed behavior and a
source reconstruction discrepancy. Removed the early `isnan` return in
`NSPrintf.m` so NaNs use the same dtoa and fragment-sizing path as the target;
the source comment records the PPC decimal-position behavior. No tests or
builds were run.

### PPC formatter field emission and conversion helpers (2026-10-06)

Compared the common `_NSvfprintf` field-emission path with the source macros
and conversion code. The target computes the same effective field width from
converted digits, sign or hex prefix, and precision; it emits blank padding,
sign/prefix, zero padding, and converted output in the same order as the
source. Left adjustment and return-count accounting also agree. PPC float
emission matches the source's exponent form, fixed decimal placement, zero
special case, alternate-form decimal point, and 16-byte padding chunks.

Compared `_exponent` (`0x42560cc0`), `___ultoa` (`0x4252733c`), and
`___uqtoa` (`0x425ac214`) with their source helpers. Exponent sign and minimum
two-digit width match. Unsigned decimal handling uses the same one-step
unsigned division before signed divisions for high-bit values; octal and
hexadecimal digit generation and alternate octal prefixing also match. The
unknown-conversion path prints the conversion character as one byte, while a
trailing `%` ends formatting, matching the source. No mismatch was found in
these ranges. Numeric rounding inside `__dtoa` remains to be compared. No
tests or builds were run.

### PPC dtoa rounding and quotient/remainder recheck (2026-10-06)

Compared `NSDtoa.m`'s `__dtoa` phase order with the full live PPC body at
`0x4254e138`. The non-finite and zero returns, binary decomposition, decimal
exponent estimate, mode normalization, precision limits, small-integer path,
quick floating estimate and fallback, Bigint numerator/divisor/tolerance
construction, quotient digit loop, tie handling, final carry/trim, and Bigint
recycling follow the target's control flow. The target's `%f` and `%e` callers
use modes 3 and 2 respectively; the reconstructed shared mode paths preserve
the additional mode branches present in the IDA body as well.

Compared `NSDtoaQuorem` with `_quorem` at `0x4255b5e0`. Both return zero when
the numerator has fewer limbs, estimate the quotient from the top limbs,
subtract the estimated divisor product with carry/borrow across every limb,
trim a zero high limb, compare the remainder, and perform at most one quotient
increment and divisor subtraction. The source's 32-bit limb arithmetic
produces the same low-word and borrow results as IDA's PPC half-word sequence.
No additional dtoa or quorem mismatch was found. This closes the numeric
rounding audit noted above. No tests or builds were run.

### PPC `_NSvfprintf` conversion and exit-path closure (2026-10-07)

Compared the remaining conversion cases and function exit in `_NSvfprintf`
(`0x425121b8`) with `NSPrintf.m`. `%c` consumes one promoted integer and emits
its low byte; `%n` stores the accumulated count at the target width; `%p`
consumes a pointer and applies the lowercase hexadecimal prefix; and `%s`
handles null input and precision-bounded NUL search as in the source. The
default conversion emits one byte, while a trailing `%` ends the scan. Count
updates, final vector flush, and the file error-flag `-1` return also agree.
Together with the earlier parser, integer, float, field-emission, vector-writer,
and dtoa comparisons, this closes the PPC `_NSvfprintf` source-to-IDA audit.
No source change was needed. Static IDA/source review and whitespace
validation only; no tests or builds were run.

### Current PPC selector and export audit (2026-10-06)

Re-ran `selector_check.py` against the live MOSXS PPC Foundation image and the
current source tree. It reports 3,397 reference selectors and 3,416 source
definitions, with zero missing selectors, renames, or duplicates. The 19 extra
definitions are source-only/category methods and runtime compatibility methods;
the current audit finds no remaining PPC selector body gap.

Compared public non-function names in the current IDA database with
`reconstruction/symbols.json`. Twenty-five data exports remain unassigned:
`_YES`, `_NO`, `_nil`, `_Nil`, `_NULL`, `_dummyPad1`, `_dummyPad2`,
`___NSConvertOldDefaults`, `__NSMsgSendCount`, `___NSObjectAllocatorLock`,
`___NSExternRefCountLock`, `___NSArrayRetainLock`,
`___NSDictionaryRetainLock`, `___NSSetRetainLock`,
`___NSSimpleHashingRetainLock`, `___NSStringArrayRetainLock`,
`___NSNumberRetainLock`, `___NSStringRetainLock`, `___NSDataRetainLock`,
`___NSDateRetainLock`, `___NSDistantObjectRetainLock`,
`___NSStringPlaceholderLock`, `___NSValuePlaceholderLock`,
`___NSDecimalNumberPlaceholderLock`, and `__NSJavaArchiverCallout`. The only
unassigned exported function remains `__NSFastJavaBundleSetup`. Existing source
uses a shared retain lock in several places, while these PPC exports name
separate per-class lock globals; their definitions and initialization require
target-specific investigation before assigning source ownership. An IDA
cross-reference check narrows that investigation: `___NSObjectAllocatorLock`
has no references; `___NSExternRefCountLock` is read by the extra-refcount
helpers; `___NSSimpleHashingRetainLock` and `___NSStringArrayRetainLock` are
read by their corresponding table/array reference helpers; and the three
placeholder locks are read by their placeholder factories. The other class
retain-lock slots have one data reference apiece in class metadata. No source,
ABI, or symbol changes were made during this audit. No tests or builds were
run.

### PPC placeholder-lock body recheck (2026-10-06)

Decompiled `__NSPlaceholderStringFromZone` (`0x42503a70`),
`__NSPlaceholderFromZone` (`0x4251b458`), and
`__NSDecimalNumberPlaceholderWithZone` (`0x4255b0d8`). Each checks
`_NSIsMultiThreaded` before entering the lock. The PPC path acquires its
zero-initialized word with `lwarx`/`stwcx.`, calls `cthread_yield()` while
contended, executes `__isync()` after acquisition, then executes `__sync()`
and writes zero on release. `__NSPlaceholderFromZone` uses the single
`__NSValuePlaceholderLock` for both NSValue and NSNumber placeholders. The
current source instead uses Objective-C `NSLock` objects in `NSString.m`,
`NSValue.m`, and `NSDecimalNumber.m` and linked-list caches for NSValue,
NSNumber, and NSDecimalNumber. The i386 IDA database confirms the same array
cache behavior on both targets and Objective-C `NSLock` pointer globals on
i386; PPC uses integer spinlock words. No source, ABI, or symbol changes were
made; no tests or builds were run.

The thread lifecycle hooks differ too: i386 `__NSToDoAtFirstThreadStart`
(`0x425547f8`) creates the three placeholder `NSLock` objects and
`__NSToDoAtLastThreadExit` (`0x42571898`) releases them. PPC
`__NSToDoAtFirstThreadStart` (`0x4257f6dc`) and
`__NSToDoAtLastThreadExit` (`0x4257fdfc`) omit all three placeholder locks.
Current `NSThread.m` performs this object lifecycle unconditionally, so the
PPC reconstruction also needs architecture-specific startup and teardown.

The i386 thread hooks do create/release `_NSPlaceholderStringLock`,
`_NSPlaceholderDecimalNumberLock`, and `_NSPlaceholderValueLock` as `NSLock`
instances. Their PPC counterparts do not mention any of these globals. The
source currently stores the three globals as object pointers and includes them
in the shared thread-start/exit lifecycle without a PPC guard. A faithful
change therefore needs to keep object-pointer declarations and lifecycle on
i386, use zero-initialized 32-bit words on PPC, and omit their startup/teardown
object messages on PPC.

### PPC unassigned data storage recheck (2026-10-06)

Read the item sizes, initial bytes, and incoming references for the 25 data
exports listed above. `_YES` is a one-byte value `1`; `_NO`, `_nil`, `_Nil`,
`_NULL`, `_dummyPad1`, `_dummyPad2`, `___NSConvertOldDefaults`,
`__NSMsgSendCount`, `___NSObjectAllocatorLock`, and
`__NSJavaArchiverCallout` are zero-valued items with no direct IDA references.
The per-class retain-lock slots have class-metadata
offset references, while `___NSExternRefCountLock`,
`___NSSimpleHashingRetainLock`, `___NSStringArrayRetainLock`, and the three
placeholder locks have code read/write references. This confirms storage and
use sites but does not by itself identify source owners for the unreferenced
compatibility symbols.

The constants and unreferenced globals in that recheck are public IDA names.
`_YES`, `_NO`, `_nil`, `_Nil`, and both dummy-pad symbols reside in `__const`;
`___NSConvertOldDefaults`, `__NSMsgSendCount`, `_NULL`, and
`__NSJavaArchiverCallout` reside in `__data`. This confirms they are defined
exports rather than imports, but still does not establish the source type or
module owner for the unreferenced entries.

A source-tree search found no definitions using the exported spellings
`_YES`, `_NO`, `_nil`, `_Nil`, `_NULL`, `_dummyPad1`, or `_dummyPad2`.
`objc/objc.h` and `NSObjCRuntime.h` define `YES`, `NO`, `nil`, and `Nil` as
macros, which explains their inlining at source use sites but does not identify
which source object emitted the target's public data symbols. No definitions
were added without a source-owner match.

### Architecture-specific allocator/refcount lock symbol audit (2026-10-06)

Compared the Foundation-i386 and MOSXS PPC IDA databases against the shared
`NSThread` ABI/source ownership records. i386 exports
`___NSAllocatorLock` and `___NSRefCountLock`; its thread-start hook writes
those globals and thread-exit hook frees/clears them, matching the current
`NSThread.m` lifecycle. PPC has neither public symbol. It instead exports the
zero-initialized `___NSExternRefCountLock`, which has code read/write
references in the extra-refcount helpers, plus `___NSObjectAllocatorLock`,
which has no references. PPC's thread-start/exit hooks do not mention the
i386 allocator/refcount globals. The shared `abi/NSThread.json` and source map
currently claim `___NSAllocatorLock` and `___NSRefCountLock` without a PPC
exclusion record; source also allocates/frees their mutex pointers on PPC.
This is a real architecture-specific ABI/lifecycle discrepancy; the exact
PPC source owner and replacement for allocator locking still need recovery.

### PPC placeholder-lock export assignment update (2026-10-06)

The three placeholder-lock exports previously listed as unassigned are now
defined and assigned from the confirmed PPC factories: `___NSStringPlaceholderLock`
in `NSString.m`, `___NSValuePlaceholderLock` in `NSValue.m`, and
`___NSDecimalNumberPlaceholderLock` in `NSDecimalNumber.m`. Each is a
zero-initialized 32-bit spin word. The corresponding DR2 i386 object-pointer
exports remain `__NSPlaceholderStringLock`, `__NSPlaceholderValueLock`, and
`__NSPlaceholderDecimalNumberLock`; the shared `__NSPlaceholderValueLock` is
owned by `NSThread.m` on i386. The three PPC names have ABI, source-symbol, and
ownership records. The earlier 25-symbol PPC data-export inventory predates
these assignments; its unclaimed count must be rechecked before reuse.

### Current exported-function assignment audit (2026-10-06)

Re-ran the exact-profile i386 `binrecon symbol-audit` against the matching
`Foundation-i386` reference image (1,630,488 bytes): zero exported functions
are unclaimed. In the live MOSXS PPC IDA database, compared every public
function name (415 total) against `reconstruction/symbols.json`; all 415 have
an exact source assignment. This updates the older unclaimed-function counts;
the remaining documented refcount work is a behavioral lock mismatch, not an
unassigned exported function.

### Extra-reference count synchronization audit (2026-10-06)

IDA confirms the exported extra-reference helpers synchronize their table
access differently by target. PPC `NSIncrementExtraRefCount`,
`NSDecrementExtraRefCountWasZero`, and `NSExtraRefCount` use the
zero-initialized `___NSExternRefCountLock` spin word when
`_NSIsMultiThreaded` is nonzero; increment creates the compact and overflow
tables before taking that lock. The read and decrement paths return before
locking when the tables have not been initialized. DR2 i386 instead uses the
`__NSRefCountLock` pointer with `mutex_try_lock` and optional
`mutex_wait_lock`; increment also initializes its tables before acquiring the
mutex. Current `NSZone.m` accesses its reconstructed tagged-slot and overflow
tables without this target synchronization. Current `NSThread.m` also
allocates and frees `__NSRefCountLock` on PPC even though PPC uses the
separate spin word. No source or ABI changes were made from this audit; the
existing shared table representation and its locking contract need a
designed reconstruction slice before implementation.

IDA entry points for the three helper bodies are PPC `NSIncrementExtraRefCount`
at `0x4250239c`, `NSDecrementExtraRefCountWasZero` at `0x42502034`, and
`NSExtraRefCount` at `0x42528d58`; DR2 i386 equivalents are `0x42506878`,
`0x42505204`, and `0x42514880`. The PPC lock is the public BSS symbol
`___NSExternRefCountLock` at `0x42626258`; its only code xrefs are the three
helpers. The i386 public `___NSRefCountLock` is at `0x426023d8`; the first-
thread hook allocates its mutex pointer and the last-thread hook frees and
clears it. Those lifecycle hooks do not reference the PPC spin word.

`_NSPrintExtraRefCount` is outside that synchronization boundary on both
targets: its PPC body at `0x425863f0` and i386 body at `0x42575650` walk the
compact table and enumerate the overflow table without acquiring either lock.
The reconstruction should preserve that observed reader behavior rather than
expanding the lock scope to the diagnostic printer.

### Current PPC assignment recheck (2026-10-06)

Compared the live MOSXS PPC database's public names against the current
`reconstruction/symbols.json`. Every public function is assigned, including
`__NSFastJavaBundleSetup`; the formerly unassigned `_NSFastFuncList` data
export is now assigned to `NSPortCoder.m`. Twenty-two public data exports
remain unassigned: `_YES`, `_dummyPad1`, `_NO`, `_dummyPad2`, `_nil`, `_Nil`,
`___NSConvertOldDefaults`, `__NSMsgSendCount`, `___NSObjectAllocatorLock`,
`___NSExternRefCountLock`, `___NSArrayRetainLock`,
`___NSDictionaryRetainLock`, `___NSSetRetainLock`,
`___NSSimpleHashingRetainLock`, `___NSStringArrayRetainLock`,
`___NSNumberRetainLock`, `___NSStringRetainLock`, `___NSDataRetainLock`,
`___NSDateRetainLock`, `___NSDistantObjectRetainLock`, `_NULL`, and
`__NSJavaArchiverCallout`. This supersedes the preceding 25-data/one-function
count; the three placeholder locks and fast-Java function now have source
assignments. No code, ABI, or symbol changes were made during this recheck.

### Cross-target simple retain-lock paths (2026-10-06)

PPC `NSRetainSimpleDictionary`, `NSReleaseSimpleDictionary`,
`NSRetainSimpleSet`, and `NSReleaseSimpleSet` at `0x4256d7cc`, `0x4256d5c8`,
`0x4256d88c`, and `0x4256d694` use the zero-initialized
`___NSSimpleHashingRetainLock` spin word only when `_NSIsMultiThreaded` is
nonzero. Each acquires with `lwarx`/`stwcx.`, yields on contention, issues
`isync`, updates the signed sentinel counter, then issues `sync` and clears the
word. DR2 i386 equivalents at `0x4256328c`, `0x42563194`, `0x425632f8`, and
`0x42563204` perform the same counter updates under the `_NSSimpleHashingLock`
Objective-C lock pointer. The current `NSSimpleHashing.m` preserves the
architecture split: PPC uses the spin word, while i386 uses
`_NSSimpleHashingLock`.

PPC `retainArray` and `releaseArray` at `0x4253758c` and `0x4252ffdc` use the
same spinlock pattern with `___NSStringArrayRetainLock`; the i386 pair at
`0x42514484` and `0x4251840c` uses `_NSGlobalRetainLock` messages. Current
`NSStringArray.m` preserves this split, using the PPC spin word and the i386
global lock. The PPC retain helper records allocation event 6 after unlocking;
the release helper records event 7 before locking. Both paths preserve
saturating counter behavior. These two helper families' lock paths now match
their respective targets.

The lifecycle is architecture-specific as well. DR2 i386 exports
`__NSSimpleHashingLock`; `__NSToDoAtFirstThreadStart` at `0x425547f8`
initializes it as an `NSLock`, and `__NSToDoAtLastThreadExit` at `0x42571898`
releases and clears it. MOSXS PPC has no `__NSSimpleHashingLock` export and
its corresponding hooks at `0x4257f6dc` and `0x4257fdfc` do not create or
release it. The PPC simple-hashing spin word is zero-initialized. Current
`NSThread.m` declares, creates, and releases `_NSSimpleHashingLock` only in
non-PPC branches; `abi-ppc/NSThread.json` does not claim that symbol. The
lifecycle and ABI overlay match both references.

### PPC class retain/release synchronization inventory (2026-10-06)

A read-only paired decompilation of the live PPC and DR2 i386 databases confirms that the lock mismatch extends beyond the simple hashing helpers and `NSStringArray`. For every pair below, PPC retain and release contain the inline `lwarx`/`stwcx.` acquisition pattern and paired `__sync()`/zero release; i386 retain and release use `_NSGlobalRetainLock` directly or call the generic internal-refcount helpers with that lock:

| Class | PPC retain / release | i386 retain / release | Source |
|---|---|---|---|
| `NSArray` | `0x4250bac0` / `0x42508fe0` | `0x42506c28` / `0x425063f4` | `NSArray.m` |
| `NSConcreteDictionary` | `0x4251b318` / `0x425139b0` | `0x425187ac` / `0x42510444` | `NSDictionary.m` |
| `NSConcreteMutableDictionary` | `0x42518064` / `0x425115ac` | `0x42518c34` / `0x4250d000` | `NSDictionary.m` |
| `NSConcreteSet` | `0x4256626c` / `0x42566154` | `0x42557fc0` / `0x42557fec` | `NSSet.m` |
| `NSConcreteMutableSet` | `0x4252c63c` / `0x42527fa4` | `0x4252f8a0` / `0x4252158c` | `NSSet.m` |
| `NSCountedSet` | `0x42567688` / `0x425674a8` | `0x4255d1bc` / `0x4255d0c8` | `NSSet.m` |
| `NSRefCountingNumber` | `0x4251bf18` / `0x425167d8` | `0x4251e94c` / `0x4251a3f8` | `NSValue.m` |
| `NSConcreteData` | `0x4251ca4c` / `0x425177dc` | `0x42512f90` / `0x42513984` | `NSData.m` |
| `NSConcreteMutableData` | `0x4253908c` / `0x4252fec8` | `0x4253fa10` / `0x4252f8cc` | `NSData.m` |
| `NSConcreteDate` | `0x42543e68` / `0x4252678c` | `0x425199fc` / `0x4250d040` | `NSDate.m` |
| `NSDistantObject` | `0x425281ec` / `0x42527e24` | `0x425371f0` / `0x425452c4` | `NSDistantObject.m` |
| `NSCString` | `0x42507968` / `0x42507c6c` | `0x4250f5b0` / `0x4250d6dc` | `NSSimpleCString.m` |
| `NSUnicodeString` | `0x42526598` / `0x42514290` | `0x4251cc80` / `0x4251804c` | `NSSimpleString.m` |
| `NSConcreteMutableString` | `0x42545e2c` / `0x4250f708` | `0x4253ca24` / `0x42512718` | `NSMutableString.m` |

`NSArray` and the three string classes also use the extra-reference-count helpers for overflow. The dictionary, set, number, data, date, and distant-object i386 implementations use the generic `_NSIncrementInternalRefCount` / `_NSDecrementInternalRefCountWasZero` helpers; their PPC implementations inline the class metadata's lock word and update their local counter. The paired source methods for the classes listed in this table still use the i386 locking route on both targets.

`NSPathStore2` is a separate implementation shape, not part of the inline-spinlock group. PPC `retain`/`release` (`0x4251b0c8` / `0x4250e220`) send lock/unlock messages around the packed counter update; the indirect receiver resolves to `__NSGlobalRetainLock_ptr` at `0x42626dc0`. i386 `retain`/`release` (`0x4251a2a8` / `0x4250e44c`) explicitly use `_NSGlobalRetainLock`. The current `NSPathUtilities.m` methods use `_NSGlobalRetainLock` on both targets and match the observed counter saturation, allocation-event order, and deallocation-after-unlock flow. The PPC pointer confirms the source uses the same global lock; this is not an additional lock-identity divergence.

This inventory materially expands any all-class retain-lock correction beyond the two-helper design. The approved two-module slice remains coherent, but it should not be presented as full cross-target class-retain parity. No source or ABI files changed from this audit; no tests or builds were run.

### NSMapTable callback and reset-order recheck (2026-10-06)

A paired read of the reconstructed `NSMapTable.m` and current PPC IDA wrappers found behavior-affecting differences beyond the resize-count defect corrected at `NSMapTable.m:154`.

- The initial `_NSMapInsert` (`0x425016f4`) source used a shared retain order. The approved correction below now retains the value before insertion and a new key after insertion and any resize.
- The initial `_NSMapInsertKnownAbsent` (`0x425094bc`) and `_NSMapInsertIfAbsent` (`0x42525930`) source retained before storing. The approved correction below now inserts first, then retains key and value, with duplicate handling before callbacks.
- The initial `_NSResetMapTable` (`0x4256d78c`) source cleared the entire bucket. The approved correction below now follows `NSResetSimpleDictionary` (`0x425110e8`): release callbacks on live buckets, clear only each hash/state word, then reset the count/level header.
- `_NSNextMapEnumeratorPair` (PPC `0x4250d364`, i386 `0x425034c0`) unconditionally writes both output pointers for a found pair. At the time of this audit the source skipped either write when its output pointer was null; the approved correction below changed the helper to unconditional stores, and the 2026-10-07 paired recheck confirms both architectures now match.

The resize correction passes the post-insertion `NSMapTableCount(old)` value to dictionary creation. This section records the initial findings; the implementation follow-up below records their resolution.

### Approved implementation follow-up (2026-10-06)

Implemented the reviewed map-table callback/reset/enumerator corrections in
`NSMapTable.m`. The insertion helper now supports both observed value-retain
timings: `_NSMapInsert` retains a new value before storage, then retains a new
key after insertion and resize; the known-absent and if-absent paths retain the
key and value after insertion and resize. Reset invokes release callbacks and
clears only each bucket's state word. The enumerator writes both outputs
unconditionally for a found pair. The previously corrected resize count remains
the post-insertion count.

Implemented the reviewed PPC retain-lock paths in `NSSimpleHashing.m` and
`NSStringArray.m` using the PPC spin-word pattern and `_NSIsMultiThreaded`
guard. The i386 Objective-C lock paths remain, with `_NSSimpleHashingLock`
creation and teardown now i386-only in `NSThread.m`. Added PPC ABI records and
symbol/ownership assignments for the two spin words. Added the six existing
`NSCharConversion.m` data exports to `symbols.json`; their ABI records and
source ownership entries already existed or were completed in
`ownership.json`.

Static verification only: reconstruction JSON parses, assignments for the new
PPC lock symbols and all six `NSCharConversion` data exports resolve to the
expected modules, and `git diff --check` reports no whitespace errors. No tests
or builds were run.

### Extra-reference count synchronization implementation (2026-10-06)

Implemented the target-specific synchronization confirmed above. `NSZone.m`
now uses the zero-initialized PPC `__NSExternRefCountLock` spin word in
`NSExtraRefCount`, `NSIncrementExtraRefCount`, and
`NSDecrementExtraRefCountWasZero`, guarded by `_NSIsMultiThreaded`. The i386
path uses `__NSRefCountLock`, including the observed try-lock/wait sequence and
zero-store unlock. The allocation events remain outside the lock in the same
order as the reference, and `_NSPrintExtraRefCount` still reads without taking
a table-wide lock. `NSThread.m` allocates and frees the mutex only on i386.
Added the PPC lock data export to the NSZone symbol map, ownership map, and PPC
ABI overlay. The side-table representation itself is still a private vector
for overflow counts and differs from the reference's `NSMapTable`; that remains
an explicit reconstruction gap. Static verification only; no tests or builds.

### Extra-reference table reconstruction follow-up (2026-10-06)

Replaced the custom overflow vector in `NSZone.m` with the same
`NSMapTable` representation used by the reference. Initialization uses
`NSNonOwnedPointerMapKeyCallBacks`, `NSIntMapValueCallBacks`, capacity 42,
and the default zone; overflow keys are `object + 1` and counts are integer
values carried as pointers. The compact table now starts at 256 slots, grows
when its pre-insertion count is above half capacity, shrinks below one-quarter
after removal down to the 256-slot floor, and rehashes the following cluster
when it does not shrink. The diagnostic printer enumerates compact entries and
then `manyCounter`, using the recovered statistics prefix and row format.

### Zombie-class cache reconstruction (2026-10-06)

Replaced the private `NSZombieClassEntry` array in `NSZone.m` with the
reference's lazily created `classToZombie` map. Paired `_NSDeallocateObject`
decompilations confirm identity key callbacks, zeroed value callbacks, initial
capacity 1, and the default zone. Both targets look up the original `isa`
before cloning; after `objc_addClass`, they create the map if needed and insert
the original-class/zombie-class pair. The existing class clone, metaclass
cache, synthesized name, and `NSDeallocateZombies` flow remain in place.

### `NSArray` retain-lock target split (2026-10-06)

Implemented the audited `NSArray` retain/release split in `NSArray.m`. PPC
uses the class-local `__NSArrayRetainLock` spin word and checks
`_NSIsMultiThreaded`; i386 continues to use `_NSGlobalRetainLock`. Both
implementations preserve retain allocation-event recording after unlocking,
release-event recording before locking, and deallocation after unlock. The
concrete-storage test now compares the receiver's `isa` directly, as both IDA
bodies do, instead of messaging `-class`. Added the PPC data-symbol ABI,
symbol, and ownership records. Reference entry points: PPC
`-[NSArray retain]`/`release` at `0x4250bac0`/`0x42508fe0`, i386 at
`0x42506c28`/`0x425063f4`.

### `NSSet` concrete retain locks (2026-10-06)

Implemented the IDA-confirmed concrete-set retain-count paths in `NSSet.m`.
Both `NSConcreteSet` and `NSConcreteMutableSet` now keep their local count in
the ABI-declared `_retainCount` slot at offset 8. PPC uses the class-local
`__NSSetRetainLock` spin word when `_NSIsMultiThreaded` is set and records
retain/release events on the observed sides of the lock. i386 continues to use
`_NSGlobalRetainLock` through the generic internal-refcount helpers. The
`NSSetEmptySet` immortal-singleton handling remains in place. Added the PPC
lock's ABI, source-symbol, and ownership records. Reference entry points:
PPC `NSConcreteSet` at `0x4256626c`/`0x42566154` and
`NSConcreteMutableSet` at `0x4252c63c`/`0x42527fa4`; i386 at
`0x42557fc0`/`0x42557fec` and `0x4252f8a0`/`0x4252158c`, respectively.
Static verification only; no tests or builds were run.

Extended the lock split to `NSCountedSet`. PPC retain/release now use the same
`__NSSetRetainLock`, saturate `_reserved` at `UINT_MAX` without the extra-ref
table, and keep allocation events on the observed sides of the lock. PPC
`retainCount` returns `_reserved + 1`; i386 retains its generic helper calls.
Paired PPC/i386 IDA bodies at `0x42567688`/`0x425674a8`/`0x42567674` and
`0x4255d1bc`/`0x4255d0c8`/`0x4255d1a4` confirm the divergence.

Implemented the same target split for `NSRefCountingNumber` in `NSValue.m`.
PPC uses `__NSNumberRetainLock`, its local saturating `refs` count, and the
observed allocation-event order; i386 uses the generic helpers with the
target's `0xFFFF` mask. Added the PPC lock's ABI, symbol, and ownership records.
Reference methods: PPC retain/release/retainCount at
`0x4251bf18`/`0x425167d8`/`0x425c2930`; i386 at
`0x4251e94c`/`0x4251a3f8`/`0x4259f104`.

Implemented the PPC counter-lock paths for `NSConcreteData` and
`NSConcreteMutableData` in `NSData.m`. PPC manipulates the low 29 count bits
and preserves the high three flag bits in the packed word at offset 4; i386
retains its low-three-bit flag layout under `_NSGlobalRetainLock`. Both paths
keep retain events after unlock, release events before lock, and deallocation
after unlock. Added `__NSDataRetainLock` to the PPC ABI, symbol, and ownership
records. Reference retain/release methods: PPC
`0x4251ca4c`/`0x425177dc` and `0x4253908c`/`0x4252fec8`; i386
`0x42512f90`/`0x42513984` and `0x4253fa10`/`0x4252f8cc`.

Implemented `NSConcreteDate`'s PPC retain-lock path in `NSDate.m`. PPC uses
`__NSDateRetainLock` under `_NSIsMultiThreaded`, saturates `_refCount` at
`UINT_MAX`, records the release event before locking and the retain event after
unlocking, and reports `_refCount + 1`. i386 keeps the generic helper path.
Added the PPC ABI, source-symbol, and ownership records. Reference methods:
PPC retain/release/retainCount at `0x42543e68`/`0x4252678c`/`0x425bdcfc`;
i386 at `0x425199fc`/`0x4250d040`/`0x4259ac40`.

Implemented the PPC `NSDistantObject` retain-state lock path in
`NSDistantObject.m`. The class-local lock protects the packed 24-bit reference
count together with `wireCount`; `retain` saturates the PPC field at
`0xFFFFFF`, and event order and post-unlock callbacks match IDA. Wire-count
retain/release operations use the same lock. `_anticipateRelease` keeps the
target's PPC unlocked read and i386 locked read. Added the PPC ABI, symbol, and
ownership records. Reference methods: PPC retain/release/retainCount at
`0x425281ec`/`0x42527e24`/`0x42575710`, retainWireCount/
`_releaseWireCount:`/`_anticipateRelease` at
`0x42575724`/`0x42561a60`/`0x42574c30`; i386 retain/release and wire methods
at `0x425371f0`/`0x425452c4`/`0x42569254`/`0x425688ac`.

Implemented PPC `__NSStringRetainLock` spin-word use for `NSCString`,
`NSInlineCString`, `NSUnicodeString`, `NSInlineUnicodeString`, and
`NSConcreteMutableString`. The existing 8-bit reference/overflow-table logic
and allocation-event order stay intact; i386 continues to use the
`_NSStringRetainLock` object. Added the zero-initialized PPC spin word to
`NSThread.m` and recorded its PPC ABI and ownership. IDA retain entry points:
PPC `NSCString`/`NSInlineCString`/`NSUnicodeString`/
`NSInlineUnicodeString`/`NSConcreteMutableString` at
`0x42507968`/`0x42502298`/`0x42526598`/`0x42503d20`/`0x42545e2c`; i386 at
`0x4250f5b0`/`0x42503878`/`0x4251cc80`/`0x425031fc`/`0x4253ca24`.

### Current DR2 i386 selector coverage (2026-10-06)

Extracted the i386 slice from the current fat Foundation image and reran
`selector_check.py` against the Foundation source tree. The audit reports
3,253 reference selectors and 3,416 source definitions, with zero missing
selectors, renames, or duplicates. The 163 extra definitions include the
documented PPC-only selectors, PPC built-in URL loading classes, and source
compatibility methods; this is source-level selector coverage and does not
verify compiled ABI encodings or instance layouts. The extracted slice matches
the profile identity: 1,630,488 bytes and SHA-256
`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`.
No tests or builds were run.

Ran the same source-selector audit against the MOSXS PPC Foundation image.
It reports 3,397 reference selectors and 3,416 source definitions, with zero
missing selectors, renames, or duplicates. The 19 extras are listed by the
audit; they include source-only compatibility methods and selectors whose
category ownership differs from the reference metadata. This verifies selector
names only, not the target's compiled encodings or instance layouts. No tests
or builds were run.

### Current unassigned PPC data exports (2026-10-06)

After the dictionary retain-lock reconstruction, nine public PPC data
exports remain unassigned: `_YES`, `_NO`, `_nil`, `_Nil`, `_NULL`,
`_dummyPad1`, `_dummyPad2`, `__NSMsgSendCount`, and
`___NSObjectAllocatorLock`. These have no direct IDA xrefs or clear source
owner; keep them unresolved. `__NSJavaArchiverCallout` is assigned to
`NSArchiver.m` based on its PPC data cluster beside the archiver debug flag
and encode/decode maps; `___NSConvertOldDefaults` is assigned to
`NSUserDefaults.m` based on its cluster beside the defaults globals and
conversion routines. Both slots have no in-image references.
`___NSDictionaryRetainLock`
is now defined and owned by `NSDictionary.m`, and appears in the PPC ABI
overlay. IDA locates the word at `0x42626260`, with its incoming offset
reference from `___NSDictionaryRetainLock_ptr` at `0x42626c90` and accesses
through both concrete dictionary classes' metadata.

### `NSJavaSetupVirtualMachine` wrapper fidelity recheck (2026-10-06)

PPC `_NSJavaSetupVirtualMachine` (`0x4257cae0`) obtains the main bundle's
`infoDictionary`, makes a mutable copy, stores `@"YES"` under
`NSJavaOwnVirtualMachine`, calls `NSJavaSetup`, releases the copy, and returns
that result. The source now follows this sequence. The wrapper remains absent
from the DR2 i386 image and ABI.
A PPC follow-up reconstructed the dictionary concrete-class retain paths.
`NSConcreteDictionary` and `NSConcreteMutableDictionary` now use the
IDA-confirmed `___NSDictionaryRetainLock` spin word and inline saturated
counter logic, with allocation-statistics events and deallocation after unlock.
Their DR2 i386 branches still call the generic retain-count helpers with
`_NSGlobalRetainLock`. The PPC data export is assigned to `NSDictionary.m` in
the ABI, symbol, and ownership records. Static source/order and metadata checks
were run; no tests or builds were run.

The PPC ABI-owner audit found that the eleven `NSURLLoading` and
`NSURLHandleClient` methods were implemented under `@implementation NSURL`
instead of the categories in the PPC ABI overlay. Their PPC implementations
now live in the matching category blocks, with ownership keys updated to those
owners; the i386 TODO methods stay in the class implementation. The cross-file
exact class/category audit reports zero missing and zero duplicate owners for
the shared-plus-PPC ABI method set.

### PPC/i386 default logging sink audit (2026-10-06)

Compared PPC `__NSDefaultLogCString` (`0x4259b8b4`), `__NSBasicStdErrLog`
(`0x4259aad0`), and `NSLogv` (`0x4259a338`) with the DR2 i386 bodies at
`0x42547748`, `0x42584770`, and `0x42547a78`. Both targets use the same
default-sink behavior: lock `_NSLogLock` when present, increment the
`_NSLocalizeLogDate` reentrancy counter, format a non-reentrant display log
with `NSDate` and `%b %d %H:%M:%S`, and use `ctime` for reentrant display logs,
append the process name and PID, normalize output to one trailing newline,
write to descriptor 2, and fall back to `openlog`/`syslog`/`closelog` when the
descriptor is unavailable or the write fails. Non-display logs use `%s  `.
`NSLogv` already formats an `NSString`, takes its displayable lossy C string,
calls the active sink with display set, and drains its autorelease pool in both
images.

Both `__NSBasicStdErrLog` bodies are variadic. They allocate a 1024-byte
temporary buffer, prefix `%s[%d] ` with process name and PID, format the
arguments into the remaining buffer (`__NSvsnprintf` on PPC and libc
`vsnprintf` on i386), write the resulting bytes to descriptor 2, and free the
buffer. `NSObjCRuntime.m` currently treats the input as a completed message,
adds a newline, and flushes `stderr`; its default sink copies the input and
routes it through that helper. The sink and helper remain source-to-IDA
divergences pending implementation. No tests or builds were run.

### `_NSAutoreleasedMallocMemory` thread-local cache recheck (2026-10-06)

Compared PPC `+mallocMemoryWithCapacity:` (`0x42525c40`),
`-remainingCapacity` (`0x42528480`), and `-dealloc` (`0x42531fb8`) with DR2
i386 at `0x4251ba24`, `0x42518bb4`, and `0x425282b4`. Both targets use the
current thread's `threadDictionary` and the key `NSAutoreleaseMalloc`, stored
as an `NSValue` nonretaining wrapper. Requests over 500 bytes get an exact-size
autoreleased chunk. Smaller requests reuse a chunk with sufficient space;
otherwise the target either allocates a dedicated exact-size chunk or creates
a new 500-byte cached chunk and stores its nonretaining wrapper according to
the same `500 - capacity > remainingCapacity` test. Chunk deallocation removes
the key only when its wrapped object is the chunk being deallocated.

Both targets' `NSThread.threadDictionary` getters lazily create the dictionary
(PPC `0x42507a6c`, i386 `0x42509414`). The current `NSPrivate.m` cache instead
uses one process-global chunk pointer. The `NSThread` deallocators release and
clear `threadDictionary` before draining autorelease pools (PPC `0x42599728`,
i386 `0x42583904`); the current source follows that same order. This slice's
target storage and teardown consequences should therefore remain coupled to
those confirmed call sequences. No tests or builds were run.

### PPC unsigned environment parsing call sites (2026-10-06)

IDA confirms `_NSInitializePlatform` at PPC `0x42513ab4` uses
`_NSCStringToUnsignedLong` with radix autodetection for `NSMallocDebugMask`,
`NSAutoreleaseHighWaterMark`, `NSAutoreleaseHighWaterResolution`, and
`NSAllocationStatisticsOutputMask`. DR2 i386 `0x42534f0c` instead uses libc
`strtoul`, with radix 10 for the two high-water settings and radix 0 for the
other two. `NSDebug.m` now dispatches these conversions through the PPC parser
and preserves the existing i386 radix arguments. No tests or builds were run.

### `NSZoneName` private-field layout recheck (2026-10-06)

PPC `NSZoneName` (`0x4259a740`) and DR2 i386 `NSZoneName` (`0x42584420`)
both substitute the default-zone pointer for nil, read the zone name pointer
at byte offset 36, return `__NSEmptyString` when it is null, and otherwise
create an NSString with `+stringWithCString:`. Both `NSSetZoneName` bodies
(`0x42554214` and `0x42542d88`) obtain `-[NSString lossyCString]` and call
`NXNameZone` only for nonnull, nondefault zones; neither stores a Foundation
side-table entry. The 32-bit `zone_t` definition in
`src/Libc-1/gen.subproj/malloc.c` places `name` at offset 36 after the NXZone
function table, free-array metadata, granularity, and parent-zone pointer.
`NSZone.m` now uses this layout directly, calls `-[NSString lossyCString]`
before `NXNameZone`, and returns `__NSEmptyString` or
`+[NSString stringWithCString:]` from the field as the targets do. The old
retained NSString side table and its recycle cleanup have been removed. Static
source comparison and whitespace checks passed; no tests or builds were run.

### NSThread PPC bootstrap and sequence-lock fidelity (2026-10-06)

The PPC `-[NSThread init]` body at `0x425561c0` checks `_NSIsMultiThreaded`,
acquires `___NSSequenceLock` with `lwarx` / `stwcx.`, yields while the prior
word is nonzero, assigns the sequence number, then releases with `sync` and a
zero store. The symbol is at `0x42626294`. DR2 i386 instead checks the nullable
`__NSSequenceLock` mutex pointer with `mutex_try_lock` / `mutex_wait_lock`,
increments the same counter, then clears the lock word. Its first-thread hook
allocates that mutex with the other three raw locks. The PPC
first-thread hook has no such allocations and begins with eight class messages.
The selector cell `0x4262CF44` points to `0x4141D57C`; the matching System
framework IDA database names that address `sel_self`, resolving the messages
as `self`. `NSThread.m` now keeps the i386 mutex path, uses the PPC static
spin-word path, and sends the eight class `self` messages before object-lock
setup. The PPC ABI overlay now records `___NSSequenceLock`. Static source,
metadata, and whitespace checks only; no tests or builds were run.

### PPC/i386 default logging sink reconstruction (2026-10-06)

Replaced the simplified `NSObjCRuntime.m` logging sink and one-string helper
with the behavior confirmed in both IDA images. The sink now serializes through
`_NSLogLock`, tracks date-format reentrancy, builds the target display and
non-display prefixes, normalizes the trailing newline, writes to descriptor 2,
and falls back to `openlog`/`syslog`/`closelog` on the target failure path.
`_NSBasicStdErrLog` now takes a format and varargs, prepends process name and
PID, formats into the target 1024-byte buffer, and writes through
`_NSWriteToFileDescriptor`. PPC uses `_NSvsnprintf`; i386 uses libc
`vsnprintf`. The existing `NSLogv` route already matched both targets. The C
symbol names and ABI manifests are unchanged. Static source and JSON checks
only; no tests or builds were run.

### `NSDefaultMallocZone` bootstrap fidelity (2026-10-06)

PPC `NSDefaultMallocZone` (`0x425034ec`) and DR2 i386
`NSDefaultMallocZone` (`0x42503d78`) both return the shared
`__NSDefaultMallocZone` pointer. In both images, `_NSInitializePlatform`
initializes that pointer from `NXDefaultMallocZone` when it is null, then
passes the pointer to `NXNameZone`. `NSZone.m` now defines and returns that
shared pointer; `NSDebug.m` performs the initialization in the bootstrap path.
This removes the previous source-only lazy initialization on the first API
call. No public ABI or export records changed. Static source checks only; no
tests or builds were run.

### Current cross-architecture code coverage baseline (2026-10-06)

Re-ran the source selector audit against the live DR2 i386 and MOSXS PPC
Foundation images. The i386 audit reports zero missing selectors, renames, or
duplicates. The raw PPC audit reports 11 class-owner misses paired with the
same 11 source methods under `NSURLLoading` and `NSURLHandleClient`; after
normalizing category ownership, both target selector sets have zero missing
source implementations. The remaining 9 PPC extras are source-only methods.

Re-ran `binrecon symbol-audit` for i386 and compared PPC exported text symbols
directly with `symbols.json`. Both report zero unclaimed exported functions.
The remaining known export assignment gap is the nine PPC data symbols listed
in “Current unassigned PPC data exports”; their owner and contract remain
unresolved because they have no direct IDA references. These checks establish
coverage names only, not compiled ABI encodings, class layouts, or runtime
behavior. No tests or builds were run.

### Unassigned data exports cross-target recheck (2026-10-06)

Rechecked the remaining public data exports in both live IDA databases. The
shared symbols `_YES`, `_dummyPad1`, `_NO`, `_dummyPad2`, `_nil`, `_Nil`,
`__NSMsgSendCount`, and `_NULL` begin with the same bytes in both images:
`_YES` contains `01` and the others contain `00`. IDA currently types these as
one-byte data items, but that does not establish their source object widths.
All nine PPC symbols and all eight i386 counterparts have zero direct xrefs.
The Foundation source defines `YES`, `NO`, `nil`, and `Nil` as macros and has
no matching storage definitions for the padding, message-send counter, or
allocator lock.

The PPC-only `___NSObjectAllocatorLock` is a zero item at `0x42626254`, before
`___NSExternRefCountLock` at `0x42626258`; the allocator-lock item has no xrefs,
while the next lock has 16. The i386 image instead has `___NSAllocatorLock`
at `0x426023d4`, a four-byte item with three xrefs. The name, typed width, and
reference difference do not support assigning the PPC symbol to the i386
owner. No source owner or declaration contract is established, so no storage
or ABI claim was added.

### `_NSAutoreleasedMallocMemory` per-thread cache supersedes earlier inventory (2026-10-06)

The earlier `_NSAutoreleasedMallocMemory thread-local cache recheck` above
described `NSPrivate.m` as using one process-global chunk. That statement was
true at the time of the audit and is now superseded: `NSPrivate.m` uses the
current thread's `threadDictionary` and the `NSAutoreleaseMalloc` key, wrapping
the cached chunk in `NSValue`'s nonretained-object representation. The PPC and
i386 allocation branches, exact replacement boundary, conditional deallocation
cleanup, and `NSThread` teardown ordering are recorded in
`docs/superpowers/plans/2026-10-06-foundation-autoreleased-malloc.md`. The
per-thread cache gap is closed; the nine unrelated unassigned data exports
remain unresolved for the reasons documented immediately above.

### `_NSWalkData` alternate-name fallback call fidelity (2026-10-06)

The earlier walker comparison recorded the source's missing alternate-name
fallback as an open difference. PPC and i386 `__NSWalkData` both call
`objc_getClass` on the decoded name, then invoke `_NSAltClassNameFromString`
whenever lookup returns `Nil` and the callback is installed. The source now
matches that sequence, including passing an absent name through the runtime and
callback, and creates the callback argument with the target's
`+[NSString stringWithCString:]` selector. The existing ABI, symbol, and
ownership records already claim both functions and the callback pointer.
Static source/metadata checks only; no tests or builds were run.

### Stale allocation-event and thread-warm-up findings superseded (2026-10-06)

Two earlier open findings above have since been resolved. The allocation-event
negative-retain calculation uses `NSAutoreleasePoolCountForObject`, which reads
the current thread's AP-data and active pages; the per-thread pool layout and
helper are recorded in `docs/superpowers/plans/2026-10-06-foundation-autoreleasepool.md`.
The first-thread warm-up selector was resolved through the System IDA database
as `sel_self` at `0x4141d57c`, and the PPC source now sends the eight class
`self` messages before object-lock setup. The six process-start class messages
remain unresolved because their selector reference at `0x4140679c` is still a
zero-filled System-image slot with no recovered selector identity.

### `_NSToDoAtProcessStart` class version initialization (2026-10-06)

The six process-start class messages are now resolved. PPC's selector reference
at `0x4262d4e8` contains the address of `sel_setVersion:` at System address
`0x4141d390`; its string is `setVersion:`. The matching i386 selector
reference at `0x42608ebc` points to a zero-filled System slot, but its six
callers match PPC in receiver order and integer arguments. Both decompilations
confirm calls to `NSString`, `NSMutableString`, `NSCountedSet`, `NSTimeZone`,
`NSNumberFormatter`, and `NSDateFormatter` with values `1, 1, 1, 1, 4, 41`.
`NSPortNameServer.m` now performs those calls in that order before creating
the empty singleton objects. The selector is inherited from `NSObject`'s
existing `+setVersion:` implementation. Static checks only; no build or tests
were run.

### i386-only `NSThread` lock globals and attributed-dictionary retain flow (2026-10-06)

The PPC and i386 `__NSToDoAtFirstThreadStart` and
`__NSToDoAtLastThreadExit` bodies differ in their lock globals: PPC does not
create or release the i386 `_NSStringRetainLock`,
`_NSURLFormatterRegistrarLock`, or `_NSURLHandlerRegistrarLock` objects. PPC
uses the static `___NSStringRetainLock` word, while i386 uses the nullable
`_NSStringRetainLock` object. `NSThread.m` now guards those object globals and
their lifecycle to i386; `NSSimpleAttributeDictionary` uses the shared
architecture-aware string-retain lock helper. Both IDA bodies also gate
allocation events around retain/release; PPC saturates the count at
`UINT_MAX`, while i386 increments unconditionally. Its source now matches
those behaviors and preserves the target's event-before-lock order on release.
Static source checks only; no tests or builds were run.

### `_NSUserDefaultsLock` thread lifecycle split (2026-10-06)

The first-thread hooks differ across the two IDA targets. DR2 i386 initializes
and releases `_NSUserDefaultsLock_0` as an `NSRecursiveLock`; MOSXS PPC instead
initializes and releases the `NSUserDefaults.m` `_NSUserDefaultsLock` with an
`NSRecursiveLock`. `NSThread.m` previously initialized and released
`_NSUserDefaultsLock_0` unconditionally, introducing the i386-only symbol on
PPC and omitting PPC's thread-start initialization and teardown of the actual
defaults lock. The source now guards `_NSUserDefaultsLock_0` storage and uses
the target-specific pointer in both lifecycle hooks. Existing symbol ownership
remains unchanged: `_NSUserDefaultsLock_0` is i386-only in `NSThread.m`, while
`_NSUserDefaultsLock` is owned by `NSUserDefaults.m`. Static source and
manifest checks only; no tests or builds were run.

### PPC `NSString(NSURLPathUtilities)` implementation repair (2026-10-06)

The three PPC methods are implemented in `NSPathUtilities.m` and recorded in
`abi-ppc/NSURLPathUtilities.json` and the selector ownership map. A fresh
comparison with the live PPC bodies confirms that the relative-path method
standardizes and splits both paths, finds their common prefix, preserves the
receiver for the target's nil/equality/no-common-prefix/root guard cases, then
adds parent markers and unmatched target components. The deletion method
shortens its reverse-search range for a trailing slash and returns through the
last separator or an empty string. The append method's initial parent step,
repeated `../` consumption, two leading-slash removals, and `"%@%@"` formatting
match the decompiled branches. The source had two
malformed `hasPrefix:` conditions; both now have the missing closing bracket.
The recheck also supersedes the earlier summary that said the append helper
trims trailing slashes from the component: the live body performs no such
operation. The helpers remain PPC-only. Static source and metadata checks only;
no tests or builds were run.

### `NSProcessInfo` executable search allocation path (2026-10-07)

DR2 i386 `__NSSearchForNameInPath` (`0x42585314`) and MOSXS PPC
`__NSSearchForNameInPath` (`0x4259cc80`) both use the `NSZoneMalloc` result
directly while scanning `PATH`, with no null check after allocation. The
source previously returned `NULL` when that allocation failed. Removed the
extra guard in `NSProcessInfo.m` to preserve the target's allocation-failure
path. No ABI entries changed; no tests or builds were run.

### `NSProcessInfo` malformed environment entry allocation (2026-10-07)

The i386 `-[NSProcessInfo environment]` body at `0x42533bc0` and PPC body at
`0x42596d08` both allocate an NSString key from each environment entry before
checking whether it contains `=`. Entries without `=` release that key and are
not inserted into the dictionary. `NSProcessInfo.m` now preserves that
temporary allocation and release flow instead of skipping such entries before
constructing a key. Dictionary contents are unchanged; allocation side effects
now follow both targets. No ABI entries changed; no tests or builds were run.

### `NSProcessInfo` PATH search traversal recheck (2026-10-07)

Rechecked i386 `__NSSearchForNameInPath` (`0x42585314`) and PPC
`__NSSearchForNameInPath` (`0x4259cc80`). Both temporarily terminate one
colon-delimited PATH component, concatenate that component, `/`, and the
executable name, accept only a regular-file `stat` result, and restore the
colon before continuing or returning. They free the candidate after the final
failed component. `NSProcessInfo.m` uses direct byte copies instead of the
target's `_NSFastMultiCStringConcat` helper, whose body performs the same
sequential concatenation; the search and cleanup paths match. Static paired
IDA/source review only; no tests or builds were run.

### Exact-profile coverage rerun (2026-10-07)

The current i386 selector audit reports 3,253 reference selectors and 3,406
source definitions, with zero missing selectors, renames, or duplicates and
153 source extras. The current PPC audit reports 3,397 reference selectors
and 3,406 source definitions, with 11 class-owner misses and 20 extras. Those
11 missing/extra pairs are the `NSURLLoading` and `NSURLHandleClient` methods
implemented in `NSURL.m` under category ownership and recorded in the PPC
`NSURL.json` overlay. After category normalization, PPC has zero missing,
renamed, or duplicate selectors and nine source extras. The i386 and PPC
`binrecon symbol-audit` commands each report zero unclaimed exported text
functions. These counts cover selector and text-export names only; they do
not establish object encodings, layouts, or runtime behavior. No tests or
builds were run.

### `NSCharacterSet` compacting dispatch fidelity (2026-10-07)

Both i386 `+[NSConcreteMutableCharacterSet _readAndRetainFileNamed:makeCompact:]`
(`0x42586b2c`) and PPC (`0x4254b718`) call `makeCharacterSetCompact` directly
when the flag is true, then call `makeImmutable`. `characterSetWithName:`
returns the concrete mutable class on this path. Removed the source-only
`respondsToSelector:` guard so the dispatch matches both target bodies. Static
source checks only; no tests or builds were run.

### `NSClassFromString` alternate-name fallback status correction (2026-10-07)

The earlier entry above that marked the fallback as awaiting design approval is
historical and superseded. `NSObjCRuntime.m` now defines the null-initialized
`_NSAltClassNameFromString` function pointer and `NSClassFromString` calls it
with the original NSString after `objc_getClass` misses. `NSSerialization.m`
uses the same fallback after resolving an archived class name. The symbol,
ABI, and ownership records assign the pointer to `NSObjCRuntime.m`. This agrees
with the paired i386/PPC IDA call paths; the later `_NSWalkData` entry above
records the walker-side correction. Static source/metadata review only; no
tests or builds were run.

### Default logging sink status correction (2026-10-07)

The 2026-10-06 entry above is stale and is superseded by the current
`NSObjCRuntime.m` implementation. Rechecking the live i386 bodies at
`0x42547748` (`_NSDefaultLogCString`), `0x42584770`
(`_NSBasicStdErrLog`), and `0x42547a78` (`NSLogv`) and PPC bodies at
`0x4259b8b4`, `0x4259aad0`, and `0x4259a338` confirms the source's locked
date-reentrancy flow, display/non-display format strings, newline handling,
descriptor-write/syslog fallback, 1024-byte variadic stderr buffer, and
`NSLogv` autorelease-pool lifecycle. The i386/PPC process-name and process-ID
call orders, plus the target-specific `_NSvsnprintf` versus libc `vsnprintf`
paths, are represented in the source. No additional source or ABI change was
needed. Static paired IDA/source review only; no tests or builds were run.

### NSMapTable paired implementation recheck (2026-10-07)

Rechecked the current source against both IDA databases after the approved
callback/reset/enumerator correction. i386 `_NSMapInsert` (`0x4250489c`) and
PPC `_NSMapInsert` (`0x425016f4`) retain the value before insertion, retain a
new key after successful insertion, and release the replaced value otherwise.
The known-absent and if-absent paths on both targets insert first, then retain
key and value; duplicate known-absent keys take the description/exception path.
Both targets' `_NSResetMapTable` wrappers call `NSResetSimpleDictionary`, and
both enumerators unconditionally write key and value outputs for a found
bucket. `NSMapTable.m` and `NSSimpleHashing.m` already match these paths, so no
source edit was needed. Static paired source/IDA review only; no tests or builds
were run.

### `_NSToDoAtLastThreadExit` status and PPC return correction (2026-10-07)

The earlier entry above claiming this export had no source implementation is
stale: `NSThread.m` and its ABI, symbol, and ownership records now contain the
cleanup routine. Paired IDA signatures are i386 `void()` at `0x42571898` and
PPC `id()` at `0x4257fdfc`. The PPC tail returns the result of the final
`objc_msgSend(..., release)` when `_NSUniqueStringCounterLock` is nonnull, or
nil otherwise; the i386 routine returns void. `NSThread.m` now preserves that
PPC return contract with an explicitly typed `objc_msgSend` cast while keeping
the existing i386 cleanup path and both targets' lock-release order. Static
IDA/source review and whitespace checks only; no tests or builds were run.

### Allocation-event autorelease count status correction (2026-10-07)

The 2026-10-05 allocation-event recheck above incorrectly described
`NSAutoreleasePoolCountForObject` as process-global. The current helper in
`NSAutoreleasePool.m` obtains its pool data from `_NSCurrentThread()` and
counts matching objects across that thread's pool pages. The i386 helper at
`0x425751bc` and PPC helper at `0x42585bd4` both read the pool-data pointer
from thread offset 24 and walk the same page/object layout. The i386 event
sender at `0x42571124` and PPC sender at `0x4257f0c8` call this helper for the
negative-retain check. The source already matches this per-thread path; no
code change is required. Static source/IDA comparison only; no tests or builds
were run.

### Autorelease-pool storage status correction (2026-10-07)

The older 2026-10-04 entries above that describe the current autorelease
storage as a process-global stack or array are also stale. The current
`NSAutoreleasePool.m` stores its pool-data pointer in the current
`NSThread` at offset 24, keeps the active page chain and pool records in that
thread's data, and routes count and drain operations through
`NSAutoreleasePoolDataForThread`. This matches the target's per-thread storage
model; the source uses its reconstructed page/data layout. The allocation-
event count helper is therefore not a process-global substitute. Static
source/IDA review only; no tests or builds were run.

### Exact-profile coverage correction (2026-10-07)

Re-ran `selector_check.py` against the current source and both live Foundation
images. The i386 audit reports 3,253 reference selectors and 3,404 source
definitions; the PPC audit reports 3,397 reference selectors and the same
3,404 definitions. Both have zero missing, renamed, or duplicate selectors.
The seven PPC extras are the documented architecture and category-placement
differences in `2026-10-07-foundation-selector-coverage-audit.md`. This
supersedes the preceding current-source audit's 3,406-definition and 11
category-owner-miss counts. Re-running `binrecon symbol-audit` for i386 reports
zero unclaimed exported functions; the exact-profile note above records zero
unclaimed PPC text exports as well. This establishes name coverage, not runtime
behavior, data-symbol ownership, or compiled ABI. No tests or builds were run.


### `_NSFastFuncList` implementation status correction (2026-10-07)

The 2026-10-05 inventory above that left the source/ABI owner unresolved is
stale. The current tree defines the four-entry table in `NSPortCoder.m` and
claims `_NSFastFuncList` in its ABI, symbols, and ownership records. Paired IDA
confirms the table's function-pointer order and that each current encoder
implementation matches the target's buffer-growth and serialization flow.
This supersedes the unresolved status; no source or metadata change was needed.
Static paired IDA/source review only; no tests or builds were run.

### Current Foundation export and selector audit (2026-10-08)

Re-ran the selector inventory against the current source tree and both live
Foundation images. PPC reports 3,397 reference selectors and 3,404 source
definitions, with zero missing selectors, renames, or duplicates; its seven
extras are source-only/category selectors absent from that image. i386 reports
3,253 reference selectors and the same 3,404 source definitions, with zero
missing selectors, renames, or duplicates; its extras include the PPC-guarded
surface because this inventory does not preprocess target guards.

Re-ran the C text-export audit using the current `symbols.json`: i386 has zero
unclaimed exported functions, and the PPC Mach-O parsed through `binrecon` also
has zero. This includes the now-claimed `__NSFastJavaBundleSetup` export, which
an earlier inventory listed as unresolved. The nine PPC data exports recorded
in `2026-10-07-foundation-ppc-unassigned-data-exports.md` remain outside this
text audit; their owners and storage widths are still unproven. Static audits
only; no tests or builds were run.

### PPC Java-needed key correction (2026-10-08)

Freshly decompiled PPC `_NSJavaSetupVirtualMachine` at `0x4257cae0` and read
its constant-string operands: the wrapper stores `@"YES"` under
`@"NSJavaNeeded"`, not `NSJavaOwnVirtualMachine` or `NSJavaRoot`. PPC
`NSJavaNeedsVirtualMachine` at `0x42555e98` checks `NSJavaNeeded` first and
falls back to `NSJavaAware` only when the first value is absent or not a
string; i386 `0x42551e94` checks only `NSJavaAware`. `NSJavaSetup.m` now
preserves that architecture split and uses the wrapper's target key. The
earlier wrapper-key descriptions above are superseded by this correction. No
ABI exports changed. Static IDA/source review and whitespace validation only;
no tests or builds were run.

### Allocation-event packet template cross-target revalidation (2026-10-08)

Re-read the mapped packet templates from the current i386 and PPC IDA
instances (`0x425a45bc`, 7,608 bytes; `0x425c9b58`, 3,512 bytes). Their
SHA-256 values are respectively
`28544f6e86a1e5b930a4c6c55f41aa5ff307a81052d75724f1844db31c7cda30` and
`3f9a4cc9d54e4ca53bad1248aa68b49a9344990d747168c33fbf789867a004b2`. Each
contains only four nonzero dwords, at offsets 0, 24, 164, and 196. Those
values and the target-specific endian encoding exactly match
`NSDebugInitializeAllocationPacket` after its zero-fill. The source initializer
therefore reproduces both template byte sequences. No source or ABI changes
were needed. Static IDA/source verification only; no tests or builds were run.

### Autorelease-pool object recycling closure (2026-10-08)

The 2026-10-05 note above that called `-[NSAutoreleasePool release]`'s
`NSDeallocateObject(self)` a known mismatch is superseded by the current
page-data reconstruction. Rechecked i386 and PPC `init`, `initWithCapacity:`,
`release`, `allocWithZone:`, and `dealloc` (i386 `0x4250d5ac`, `0x4250d5cc`,
`0x4250d648`, `0x42512888`, `0x4257341c`; PPC `0x4251a5b0`, `0x4251a5e8`,
`0x4251a874`, `0x4251a694`, `0x4258316c`). The source now matches both
architectures: release only pops the token; base-class allocation takes one of
the four recycled objects or allocates in the default zone; subclass allocation
uses the requested zone; and teardown owns cached-pool deallocation. No
NSAutoreleasePool source change was indicated. Static paired IDA/source review
only; no tests or builds were run.

## Correction: default logging sink implementation status (2026-10-08)

The 2026-10-06 note above that `NSDefaultLogCString` and
`NSBasicStdErrLog` remained source-to-IDA divergences predates the current
`NSObjCRuntime.m` implementation and is stale. Rechecked i386
(`__NSDefaultLogCString` `0x42547748`, `__NSBasicStdErrLog` `0x42584770`,
`NSLogv` `0x42547a78`) and PPC (`0x4259b8b4`, `0x4259aad0`, `0x4259a338`)
against the source. The default sink matches process/date formatting,
reentrancy fallback, two-space formatting and newline trimming, descriptor
write and syslog fallback, and lock/counter teardown. The variadic helper
matches the 1024-byte allocation, process prefix, target-specific formatting
call (`vsnprintf` on i386, `__NSvsnprintf` on PPC), descriptor write, and free.
`NSLogv` matches format construction, displayable lossy conversion, callback,
and autorelease-pool cleanup. No source change was indicated. Static paired
IDA/source comparison only; no tests or builds were run.
