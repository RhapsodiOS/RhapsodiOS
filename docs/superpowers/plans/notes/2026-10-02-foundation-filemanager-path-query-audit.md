# Foundation NSFileManager path query audit

Reference: Foundation i386 IDA database `6c2a913dc37a`.

## Target path flow

`-[NSFileManager fileExistsAtPath:]` (`0x42533adc`) and
`-[NSFileManager fileExistsAtPath:isDirectory:]` (`0x4253251c`) obtain the
NSString length, cap it at `0x402` (1026), and copy that many UTF-16
characters into a stack buffer with `getCharacters:range:`. Both pass that
buffer and character count to `__NSFileExistsAtPath` (`0x4252e394`). The helper
wraps the characters in an `NSCheapMutableString` with the Unicode flag set,
converts it with `getFileSystemRepresentation:maxLength:withPath:` using a
1026-byte output capacity, then performs `lstat` and follows a symbolic link
with `stat` except for dangling links.

The source helper `NSFileExistsAtPath` at `NSFileManager.m:215` now caps the
NSString length at 1026, copies that prefix as UTF-16, wraps the stack buffer
in `NSCheapMutableString` with the Unicode flag set, and converts it with the
same 1026-byte output capacity. `NSMutableString.m` now implements the private
class methods used by that conversion from the extracted class ABI and IDA
bodies. The source and target otherwise agree on permission modes, symlink
handling, directory mode extraction, and the deletability sticky-directory/
owner checks.

Supporting target bodies: `getFileSystemRepresentation:maxLength:withPath:`
at `0x42510300`, `__NSFileAccessibleForMode` at `0x4253591c`, `_fileStat` at
`0x4252f24c`, and `_fileStatFollow` at `0x42535414`.

## Directory enumeration

`directoryContentsAtPath:matchingExtension:options:keepExtension:`
(`0x42531800`) delegates enumeration to `__NSDirectoryList` (`0x42521d4c`).
The helper skips `.` and `..`, treats the supplied extension as a dot-prefixed
suffix, uses option bit 0 for case-insensitive matching, and removes the
suffix only when `keepExtension` is false. A directory read error makes the
method return nil. The current source at `NSFileManager.m:430` applies the same
filter, option bit, extension-retention choice, dot-entry skip, and read-error
result. Its use of `opendir`/`readdir` and an `NSMutableArray` differs from the
target's `open`/`getdirentries` and packed UTF-8 `NSStringArray`, while the
public enumeration behavior checked here agrees.

The recursive `NSAllDescendantPathsEnumerator` also matches the target's
checked flow: it yields each matching child before descending, carries the
child's attributes into its nested enumerator, skips nested volumes when
`cross` is false, propagates `skipDescendents` to deeper levels, and returns
paths relative to `prepend` when provided. The abstract `NSDirectoryEnumerator`
methods match the target's `NSRequestConcreteImplementation` calls. Relevant
target bodies: `newWithPath:prepend:attributes:cross:` (`0x42576c3c`),
`nextObject` (`0x4257828c`), `skipDescendents` (`0x4257851c`), and the abstract
methods at `0x4257dcec`–`0x4257dda0`.

## Default file-manager callback methods

`fileManager:shouldProceedAfterError:` and `fileManager:willProcessPath:` are
declared as optional handler selectors, but neither DR2 i386 nor MOSXS PPC
implements them on `NSObject`. The source's empty/default `NSObject`
implementations therefore diverged from the reference and made every object
respond to both callbacks. Those implementations have been removed; the
file-manager operations already test `respondsToSelector:` and only send a
callback when the handler provides it. The public category declarations remain.

## Atomic file creation architecture split

IDA confirms different implementations for
`-[NSFileManager createFileAtPath:contents:attributes:]`: i386 `0x4257f168`
creates a globally unique temporary sibling, opens it through
`_NSOpenFileDescriptor`, writes and closes it through the file-descriptor
helpers, then renames it to the destination and removes it on rename failure.
PPC `0x42593c98` substitutes `[NSData data]` when contents is nil and calls
`writeToFile:atomically:` directly. `NSFileManager.m` now has target-guarded
branches for those flows; both apply attributes only after a successful write.
No tests or builds were run.

## Attribute owner and date conversion

The i386 `changeFileAttributes:atPath:` body at `0x4253c450` and PPC body at
`0x425454f4` resolve owner and group names through `_NSUserAccount` and
`_NSGroupAccount`, then pass the returned account numbers through signed
16-bit values to `chown`. The source had bypassed those caches with
`getpwnam`/`getgrnam`; it now uses the target account objects and narrowing.
For modification dates, i386 converts the reference-date interval plus
`978307200` through a long-double signed 64-bit conversion, while PPC splits
values at `2^31` before restoring the unsigned 32-bit bit pattern. The source
now preserves those target-specific conversions before calling
`_NSSetFileModificationUNIXTime`. No tests or builds were run.

### Static callback audit (2026-10-07)

The optional `fileManager:shouldProceedAfterError:` and
`fileManager:willProcessPath:` declarations remain in `NSFileManager.h`. A
source implementation scan finds only guarded call sites in `NSFileManager.m`,
with no `NSObject` callback method definitions. The current selector audits
report i386: 3,253 reference selectors and 3,404 source definitions, with zero
missing, renamed, or duplicate selectors; PPC: 3,397 reference selectors and
3,404 source definitions, also with zero missing, renamed, or duplicate
selectors. Extra counts (151 i386, 7 PPC) are from the textual audit and include
architecture-guarded methods. `git diff --check` reports no whitespace errors
for the tracked source and divergence files. No tests or builds were run.
