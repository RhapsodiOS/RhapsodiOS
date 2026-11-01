# Foundation `NSBundle` missing-selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSBundle.json`, and current
`src/Kits/Foundation/NSBundle.m`.

The current ABI/source-owner audit finds ten missing `NSBundle` instance
selectors: `dealloc`, `defaultsDictionary`, `description`,
`invalidateResourceCache`, `pathForResource:ofType:inDirectory:forLanguage:`,
`pathsForResourcesOfType:inDirectory:forLanguage:`, `retain`, `release`,
`retainCount`, and `unload`. IDA confirms their bodies at the addresses below.
The same audit finds three missing class selectors: `debugDescription`,
`loadedBundles`, and `setSystemLanguages:`.

## Class methods

`loadedBundles` at `0x42559668` creates a mutable array with capacity eight,
appends `allBundles` and then `allFrameworks`, and returns it.
`setSystemLanguages:` at `0x42576e94` has an empty body. `debugDescription` at
`0x42576d20` gets `loadedBundles` and sends it a selector whose identity remains
unresolved; do not infer its exact formatting behavior from the call shape.

## Resource lookup

`pathForResource:ofType:inDirectory:forLanguage:` at `0x42578a20` rejects a
nil name, builds the resource directory from `resourcePath` and the optional
subpath, treats an empty extension as absent, and chooses languages from the
explicit language or from user defaults with bundle languages excluded. It
calls `+[NSBundle findBundleResources:callingMethod:directory:languages:name:types:limit:]`
with limit one and returns the first path retained across a temporary
autorelease pool.

`pathsForResourcesOfType:inDirectory:forLanguage:` at `0x42578d24` follows the
same directory, extension, and language selection, calls the shared finder
with a nil resource name and unlimited results, then retains the result array
across its temporary autorelease pool.

## Resource cache and defaults

`defaultsDictionary` at `0x425786b0` checks a cached entry in
`infoDictionary` under `NSBundleDefaultsDictionary`. On a miss it calls
`pathForResource:ofType:` for `Defaults.plist`, loads a dictionary from the
returned file or creates an empty dictionary, stores it in `infoDictionary`
under that same cache key, and returns it.

`invalidateResourceCache` at `0x425787fc` removes the
`NSBundleResources` and `NSBundleStringTableTable` entries from
`infoDictionary`.

## Lifetime and status

`dealloc` at `0x42578580` first unloads when flag `0x04000000` is set. It then
checks `_flags & 0x000f0000`; for values other than `0x00010000` and
`0x00030000`, it optionally locks `_NSBundleDataLock`, removes the resolved
path mapping and the bundle from the loaded-framework or loaded-bundle table,
unlocks, releases `infoDictionary`, and calls `NSObject` deallocation. If the
dictionary is nil, it calls `NSObject` deallocation immediately.

`retain` (`0x42532974`), `release` (`0x4253552c`), and `retainCount`
(`0x4253ead8`) maintain the low seven reference-count bits in `_flags`, use
Foundation's extra-refcount helpers after saturation, and guard updates with
`_NSGlobalRetainLock` when present. Retain and release also record allocation
events when allocation statistics are enabled. Release preserves the target's
special no-deallocation cases for bundle type flags `0x00010000` and
`0x00030000`.

`unload` at `0x42578e70` calls `_NSJavaBundleCleanup(self, 0)` only when flag
`0x40000000` is set and returns `NO`.

## Description

`description` at `0x4257878c` calls two private selectors on the bundle with no
explicit Objective-C arguments, then passes both results and a status prefix to
`stringWithFormat:` with format `%@ <%@> (%sloaded)`. When bit `0x04` in the
receiver's flags byte is clear, the prefix is `"not yet "`; when set, it is an
empty string. The selector identities remain unresolved, so this evidence is not
enough to implement the method faithfully.

No source code, tests, or builds were added or run for this analysis.

A closer assembly pass confirms the status prefix: when bit `0x04` in the receiver's
flags byte is clear, the format receives `"not yet "`; when set, it receives
an empty string from an indirect constant. The method calls two private selectors
on the bundle with no explicit Objective-C arguments, then supplies both results
and the prefix to `stringWithFormat:` with format `%@ <%@> (%sloaded)`. The selector
names remain unresolved, so the source behavior is still not implemented from
this evidence alone. This assembly pass does not identify the opaque selectors.

Source cross-check: `NSJavaSetup.h` declares `NSJavaBundleCleanup(NSBundle *,
NSDictionary *)`; the IDA call's second argument is null, so the reconstruction can call
`NSJavaBundleCleanup(self, nil)` without adding another declaration.

## Implementation status (2026-10-03)

Implemented `+[NSBundle loadedBundles]` and `+[NSBundle
setSystemLanguages:]` at `0x42559668` and `0x42576e94`. The first builds an
autoreleased mutable array with `allBundles` followed by `allFrameworks`; the
second remains empty as in the reference. The focused ABI audit now reports 24
of 35 NSBundle selectors defined, with 11 remaining gaps; `debugDescription`
remains excluded because its selector behavior is unresolved. The framework
selector comparison reports 3,051 definitions and 322 missing selectors, with
zero renames or duplicates. `git diff --check` is clean. Tests and builds were
not run.

Implemented five additional methods confirmed above: `defaultsDictionary`,
`invalidateResourceCache`, `unload`, and the two language-specific resource
lookup methods. Both lookup methods hold their results across the target's
capacity-20 autorelease pool, and the default language path uses
`arrayByExcludingToObjectsInArray:` as observed in IDA. The focused ABI audit
now reports 29 of 35 NSBundle selectors defined, with six remaining gaps. The
framework selector comparison reports 3,056 definitions and 317 missing
selectors, with zero renames or duplicates. `git diff --check` is clean. Tests
and builds were not run.

Implemented `retain`, `release`, `retainCount`, and `dealloc` from the IDA
addresses recorded above. The retain methods preserve the seven-bit inline
count, extra-refcount flag, global retain lock, allocation events, and the
main-bundle/static-framework release exceptions. `dealloc` preserves the
main/static bundle early returns and removes ordinary bundles from the resolved
path and loaded bundle/framework collections before releasing the info
dictionary. The focused audit now reports 33 of 35 NSBundle selectors defined;
only `debugDescription` and `description` remain. The framework selector
comparison reports 3,060 definitions and 313 missing selectors, with zero
renames or duplicates. `git diff --check` is clean. Tests and builds were not
run.

## Remaining description selectors (2026-10-03)

IDA resolves the two final NSBundle gaps. `+[NSBundle debugDescription]` at
`0x42576d20` sends `loadedBundles`, then sends `description` to the returned
array. The selector slot matches the one used by `+[NSObject
debugDescription]`, which directly forwards to `description`.

`-[NSBundle description]` at `0x4257878c` reads flag bit `0x4`, obtains
`bundlePath`, obtains the receiver's class, and formats them with
`"%@ <%@> (%sloaded)"`. The `%s` argument is `""` when bit `0x4` is set and
`"not yet "` otherwise. Both methods are now implemented in `NSBundle.m`,
bringing its ABI class selectors to full source coverage. Static owner and
whitespace checks only; no tests or builds were run.

## Path-record helper ownership correction (2026-10-04)

IDA confirms `__NSLookupOrCreateBundle` (`0x4253a52c`) calls the internal C
helper `_initWithPathRecordNoLock` (`0x4253ba54`) after bundle validation and
allocation. The helper sets the bundle/framework flag, optionally creates and
updates the corresponding loaded list, retains the initial and resolved paths
into ivars at offsets 20 and 24, and returns the retained resolved path. It
does not set the Resources flag. The source had represented this work as an
extra `-[NSBundle _setPath:resolvedPath:addToLoadedList:]` selector and also
set the Resources flag eagerly. The source now uses a file-local C helper with
a layout matching `NSBundle.h`; resource-flag detection remains in
`_initInfoDictionary`, where the target performs it. The focused selector
comparison has no missing NSBundle selectors; the existing `+[NSBundle
initialize]` was an extra source definition. A follow-up xref audit found
that the target initializes `_NSBundleDataLock` in
`__NSToDoAtFirstThreadStart` (`0x425547f8`), after the class initialization
messages, and releases it in `__NSToDoAtLastThreadExit` (`0x42571898`). The
source now removes the `NSBundle +initialize` override and initializes the
lock in its existing first-thread hook in `NSThread.m`. The selector audit
therefore has neither a missing nor an extra `NSBundle` selector. Teardown
fidelity remains part of the broader thread-lifecycle audit. `git diff --check`
is clean. Tests and builds were not run.
