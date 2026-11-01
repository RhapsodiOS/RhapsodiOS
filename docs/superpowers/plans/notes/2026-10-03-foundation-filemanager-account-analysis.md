# Foundation file-manager account wrapper analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSFileManager.json`, and the current
Foundation sources.

## ABI and source gaps

`NSFileManager` has two ABI methods without source definitions:
`+initialize` (`0x425515c4`) and `-dealloc` (`0x4257f38c`). Its class
initializer sends `initialize` to `_NSUserAccount` and `_NSGroupAccount`.
The source currently defines neither helper class. The ABI records these
private classes and their layouts:

- `_NSUserAccount` is 24 bytes: `loginName`, `fullName`, `homeDirectory`,
  `accountNumber`, and `reserved` at offsets 4, 8, 12, 16, and 20.
- `_NSGroupAccount` is 20 bytes: `groupName`, `accountNumber`, `users`, and
  `reserved` at offsets 4, 8, 12, and 16.

The helper classes are involved in file-attribute queries for owner and group
account names and numbers. Their implementation is a connected reconstruction
slice rather than behavior that can be completed by adding only the two
`NSFileManager` methods.

## Confirmed account behavior

Both helper classes maintain a name dictionary and an integer-keyed map, plus a
one-shot flag recording whether the system account database has been scanned.
Their `initialize` methods create these caches if absent. The map uses
`NSIntMapKeyCallBacks`; its value retain callback is `retainObjectMT`, which
sends `retain` to the value.

`_NSUserAccount` provides name and numeric lookups, `currentAccount`, accessors,
equality/hash, `userDictionary`, and `initWithPasswordEntry:`. Numeric lookup
checks the UID map, optionally calls `getpwuid` before the first full scan, and
creates a placeholder account if no passwd entry exists. Name lookup scans all
passwd entries once on a miss. The scan uses `setpwent`/`getpwent`/`endpwent`
and marks the database searched afterward. Entry initialization copies the
login name, GECOS full name, and home directory, stores the UID, inserts the
account in the UID map, and indexes named accounts by login name.

`_NSGroupAccount` provides analogous name and numeric lookups, `currentAccount`,
accessors, equality/hash, `groupDictionary`, `members`, and
`initWithGroupEntry:`. Numeric lookup checks the GID map, optionally calls
`getgrgid` before the first full scan, and creates a placeholder if no group
entry exists. The full scan uses `setgrent`/`getgrent`/`endgrent` and marks the
database searched afterward. Entry initialization copies the group name and
member names, stores the GID, indexes the object in the map, and indexes named
groups by group name.

The IDA body for the group scan (`0x42585ee0`) constructs an
`NSNumber numberWithShort:` from each `gr_gid` for its existing-entry lookup,
although initialization uses `NSIntMapKeyCallBacks`. Preserve this observed
lookup until call-level evidence establishes whether it is an intentional
target quirk or a decompiler/type artifact.

## Dictionary keys and manager lifecycle

The dictionaries use the strings `Login Name`, `Full Name`, `Home Directory`,
`Account Number`, `Group Name`, and `Group Members`. IDA string cross-references
confirm the account-number key at `0x425fd8b6` and the other keys at
`0x425fd892`, `0x425fd89d`, `0x425fd8a7`, `0x425fd8c8`, and `0x425fd8d3`.
The account number is omitted when its stored value is zero; names and members
are omitted when their corresponding fields are nil.

`+[NSFileManager initialize]` initializes both helper classes. Its
`-dealloc` returns without releasing the global default manager and otherwise
forwards to `NSObject -dealloc`.

## Relevant IDA entry points

- `_NSUserAccount`: `initialize` `0x42550bec`, `accountWithName:`
  `0x4253c724`, `accountWithNumber:` `0x42550c7c`, `currentAccount`
  `0x42578188`, `initWithPasswordEntry:` `0x4254c6f4`, `_loadDictionaries`
  `0x42585e64`, and `userDictionary` `0x425840dc`.
- `_NSGroupAccount`: `initialize` `0x42550d2c`, `accountWithName:`
  `0x4257804c`, `accountWithNumber:` `0x425780ac`, `currentAccount`
  `0x4257815c`, `initWithGroupEntry:` `0x42583d98`, `_loadGroupDictionaries`
  `0x42585ee0`, and `groupDictionary` `0x42583cb8`.
- `NSFileManager`: `+initialize` `0x425515c4` and `-dealloc` `0x4257f38c`.

## Implementation status (2026-10-03)

`-[NSFileManager dealloc]` now matches IDA: it returns without releasing the
global default manager and otherwise calls `NSObject`'s `dealloc`. The
`+[NSFileManager initialize]` selector remains unimplemented because it calls
`_NSUserAccount` and `_NSGroupAccount`, whose cache initialization depends on
the not-yet-reconstructed account classes described above. Tests and builds
were not run. The initial `NSFileManager.json` module audit reported 36 missing selectors
across the account helpers and `NSDictionary(NSFileAttributes)`. For the
`NSFileManager` class itself, `+initialize` was the remaining missing selector.

## Owner audit and loader recheck (2026-10-03)

A fresh exact-owner comparison of `NSFileManager.json` against Foundation
sources confirms the 36-selector breakdown: 13 `_NSUserAccount` methods, 12
`_NSGroupAccount` methods, `+[NSFileManager initialize]`, and 10
`NSDictionary(NSFileAttributes)` methods. The manager initializer's complete
body only sends `initialize` to `_NSUserAccount` and `_NSGroupAccount`.

Re-decompilation of `_loadDictionaries` (`0x42585e64`) confirms the passwd scan
checks the UID map before constructing an account from each entry, calls
`endpwent`, and then marks the cache searched. `_loadGroupDictionaries`
(`0x42585ee0`) follows the corresponding group-entry flow, but its existing
entry check passes `[NSNumber numberWithShort:(short)gr_gid]` to `NSMapGet`
even though the GID map is initialized with `NSIntMapKeyCallBacks`. Preserve
this observed call unless lower-level evidence shows it is a decompiler type
artifact. The account-helper implementation boundary is therefore 25 class
methods plus the manager initializer; the ten dictionary category methods
remain a separate follow-up slice.

## `NSDictionary(NSFileAttributes)` accessors (2026-10-03)

IDA identifies ten category methods compiled on `NSDictionary`: `fileSize`,
`fileModificationDate`, `fileType`, `filePosixPermissions`, owner/group account
names and numbers, `fileSystemNumber`, and `fileSystemFileNumber`. The eight
object/numeric lookups use their matching `NSFile...` dictionary keys; size
uses `longLongValue`, permissions uses `unsignedIntValue & 0xFFF`, and both
filesystem number accessors use `unsignedIntValue`. The two account-number
accessors return zero unconditionally in the reference. The source now adds
these ten methods under the exact category owner and declares the two account
number methods in `NSFileManager.h`.

The exact-owner ABI audit reports all 10 selectors present once, and
`git diff --check` is clean. Tests and builds were not run.
The full `NSFileManager.json` exact-owner audit now reports 26 remaining
selectors, all within `_NSUserAccount`, `_NSGroupAccount`, and
`+[NSFileManager initialize]`; the ten dictionary-category gaps are closed.

## Account helper implementation (2026-10-04)

Implemented the 25 `_NSUserAccount` and `_NSGroupAccount` methods and
`+[NSFileManager initialize]` in `NSFileManager.m`. The private class ivars
match the ABI offsets. The account maps use `NSIntMapKeyCallBacks` and the
target value retain callback; name dictionaries and one-shot passwd/group scans
follow the decompiled paths. The group scan preserves its observed
`NSNumber numberWithShort:` lookup against the integer-key map, including the
resulting pointer-key mismatch.

The exact-owner audit reports 59 expected methods and 59 definitions across
`NSFileManager`, `_NSUserAccount`, and `_NSGroupAccount`, with no missing,
extra, or duplicate methods. The global selector audit now reports six missing
selectors, zero renames, and zero duplicates. `git diff --check` is clean. No
tests or builds were run.

## Method-level account recheck (2026-10-03)

Decompiled every missing account-helper method and both database loaders in the
Foundation i386 IDA database. The simple accessors return the corresponding
stored ivar. Each `description` returns the description of its generated
dictionary; each `hash` delegates to the stored name's `hash`; and each
`isEqual:` accepts identity first, then requires the matching helper class and
compares both account name and numeric account identifier.

`userDictionary` conditionally includes the stored login name, full name, and
home directory, and includes a decimal-string account number only when that
number is nonzero. `groupDictionary` conditionally includes group name, decimal
account number, and member list under the matching legacy keys. Both dictionary
methods create a fresh mutable dictionary per call.

Name lookup consults the name dictionary and performs a single full database
scan on the first miss. Numeric lookup first checks its integer map, attempts
`getpwuid` or `getgrgid` before the full scan, and creates a number-only
placeholder when no entry is returned. Entry initialization copies the C
strings, inserts the helper into the number map, releases the initial
allocation ownership, and indexes named entries. The class `initialize`
methods lazily create the integer maps and name dictionaries; `currentAccount`
uses `getuid()` or `getgid()` and forwards to numeric lookup.

The GID loader's `NSNumber numberWithShort:` argument to `NSMapGet` was initially
ambiguous against the integer-key callback configuration. The raw machine-code
and lookup recheck below resolves the key representation and leaves a confirmed
target inconsistency. No source code, tests, or builds changed in this recheck.

### GID map lookup machine-code confirmation

Raw disassembly resolves whether the `NSNumber` lookup was only a Hex-Rays
type artifact. At `0x42550d2c`, `+[_NSGroupAccount initialize]` copies all six
dwords from `_NSIntMapKeyCallBacks_ptr` into the callback argument for
`_NSCreateMapTableWithZone`. At `0x42585ee0`, `_NSGroupAccount`'s group-database
loader sign-extends the low word of `gr_gid`, sends that value to
`+[NSNumber numberWithShort:]`, and pushes the returned object pointer directly
as the key argument to `NSMapGet`. The loader's actual instructions therefore
confirm the decompiler's object-valued key; this is not a guessed selector
type.

The reference `_NSIntMapKeyCallBacks` data at `0x42603094` contains six dwords:
five null callbacks followed by the `0x80000000` not-a-key marker. Reference
`NSMapGet` falls back to the key pointer when the hash callback is null, and
`_NSSimpleDictFindBucketMatch` compares stored and requested key pointers
directly when the equality callback is null. This confirms the loader's
`NSNumber` object cannot match the numeric pointer keys used by
`accountWithNumber:` and `initWithGroupEntry:`. It is a target inconsistency,
not just a mismatch inferred from local source types. The reconstruction should
preserve it unless further evidence shows the loader's lookup intentionally
uses a different map state; substituting a numeric key would repair the target
behavior.

## Duplicate file-attribute implementation removal (2026-10-04)

`NSFileManager.json` assigns the ten file-attribute accessors to the
`NSDictionary(NSFileAttributes)` category. The source already had that exact
category at line 1596, but a later flat `@implementation NSDictionary` also
defined eight of those selectors. The flat duplicates were removed; the
category methods, including both account-number accessors, remain. The global
selector audit now reports 3,253 reference selectors, zero missing, renamed,
or duplicate selectors, and 49 source extras; the eight flat dictionary
extras are gone. `git diff --check` is clean for the source change. No tests or
builds were run.

## Source-state recheck (2026-10-09)

The current `NSFileManager.m` now contains both private account helper classes
and `+[NSFileManager initialize]`, resolving the original dependency gap. A
fresh check found that `-[NSFileManager dealloc]` was still absent despite the
ABI owner record; it has now been restored. i386 (`0x4257f38c`) and PPC
(`0x42593dc8`) both skip superclass deallocation for the global default
manager and otherwise call `NSObject -dealloc`. Static paired IDA/source
review only; no tests or builds were run.
