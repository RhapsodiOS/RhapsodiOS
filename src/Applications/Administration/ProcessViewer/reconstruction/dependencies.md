# Recovered dependency inventory

## Binary imports

The supplied executable loads AppKit Versions/C, Foundation Versions/C, and
System Versions/B, plus dyld. Its image also contains the `__cthread_init_routine`
entry. Full install names are in the reference load commands and IDA analysis;
retain the historical framework versions in the app build.

System/process imports include `_sysctl`, `_table`, `_kill`, `_getpwuid`,
`_strerror`, `_strlen`, `_strcmp`, `_strchr`, `_index`, and `_exit`; `_errno` is
an imported data symbol. Recover exact signatures and call contracts from target
headers and each owning function's disassembly before implementing.

Foundation imports provide arrays, dictionaries, sets, strings, numbers,
enumerators, notification handling, exceptions, bundles, paths/search paths,
map-table operations, zone allocation, integer map callbacks, and string helpers.
Retain original map-table behavior instead of substituting modern collection
semantics. AppKit imports include application launch, table/header/point handling,
alerts, print panels/operations, save panels, menus/actions, and system information.
Record per-symbol framework ownership and link flags while completing the
historical build setup.

## Application process interfaces

- `/bin/ps caux`: launched by `+[Process enumerateProcessesAndFetch:]` through
  Foundation's task and pipe APIs. The method skips the heading, creates a
  scanner for each newline-delimited row, scans the user field and a positive
  PID, skips the current process, extracts the remaining display fields, then
  queries the kernel record. Embedded output column keys include `USER`,
  `VSIZE`, `RSIZE`, `%CPU`, `%MEM`, `TTY`, `STAT`, `TIME`, and `NAME`. The
  i386 guest header is `USER PID %CPU %MEM VSIZE RSIZE TT STAT TIME COMMAND`;
  the live test confirms the implementation's token order through
  `TIME`, while `NAME` and `STAT` are refined from the sysctl record. `START` and
  `COMMAND` are not stored as row fields. This confirms the i386 guest behavior,
  not an independent PowerPC runtime oracle. The live test also verifies stale
  process removal on the following refresh. Target zombie diagnostics confirmed
  that `readDataToEndOfFile` returns autoreleased data; the parser must not send
  it an extra `release`. New `Process` objects retain their alloc ownership until
  `invalidate` removes them from the map and sends the reference's explicit
  release.
- `_sysctl`: used by `-[Process(Private) _update]` with the four-item MIB
  `{1, 14, 1, pid}` and a 468-byte process-record buffer. It fills parent/group
  IDs, saved/real UIDs, status, and a process name used to populate the data
  dictionary. The repository kernel header defines this record as
  `struct kinfo_proc`; `_update` reads `kp_proc.p_stat` and `kp_proc.p_comm`,
  `kp_eproc.e_ppid` and `e_pgid`, `e_pcred.p_svuid`, and
  `e_pcred.p_ruid`. Use those target structure definitions for both CPUs, not
  hand-written PPC offsets. The named error is `sysctl failed: %s`. The i386
  live probe calls `_update` for itself and compares PID, PPID, process group,
  saved UID, process name, and username with the running process APIs. If the
  UID database has no name for a transient row's real UID, `_update` preserves
  the user text parsed from `ps` instead of inserting `nil` into the dictionary;
  this fallback is an i386 runtime-driven robustness adaptation.
- `+[Process getSortContext:forKey:ascending:]`: the PPC key array is
  `NAME`, `%MEM`, `%CPU`, `RSIZE`, `VSIZE`; its data bytes are `@ffff`.
  `USER` and `STAT` table columns therefore do not receive sort contexts.
  `tests/process.m` covers all five supported keys and rejects those two
  unsupported identifiers.
- `-[Process compare:context:]`: PPC pseudocode branches by the sort-kind byte
  and directly sends `caseInsensitiveCompare:` for string keys; it has no
  missing-value branch. The i386 implementation orders a missing value before
  a present value because the target Foundation bus-errors on
  `caseInsensitiveCompare:nil`, which live enumeration can encounter for a
  process that exits during the `/bin/ps` snapshot. This is a documented
  i386-driven behavior adaptation, not confirmed PPC parity.
- `_table`: used by `-[Process arguments]` as
  `table(6, pid, buffer, 1, 4096)`. On success the method scans NUL-delimited
  entries backwards to locate the final argument terminator, then finds the end
  of the last entry without `=` and copies every entry through that point into
  a cached array. This separates the argv prefix from the trailing environment
  strings while preserving any `=` characters that occur in argv. Reproduce
  the 4096-byte bound and result behavior from the reference. The i386 live
  test invokes this call on itself with a spaced argument and an argv item
  containing `=`; it also checks the single-argument case and confirms
  environment strings are excluded.
- `_getpwuid`: used for UID translation in `_NameForUID`; verify caching, null
  results, and returned-string ownership.
- `_kill`: used by `-[ProcessControl killProcessWithConfirmation:]`; recover the
  exact signal, confirmation/cancellation, selected PID handling, and errno path.
- AppKit/Foundation: NIB ownership, timers, window/selection notifications,
  save/print operations, and exception/error behavior must follow method
  evidence. NIB names alone do not specify these contracts.

The executable's observed user-default keys are `DefaultTypeTag`,
`TypeDescriptionFile`, `RefreshInterval`, `DeleteProtectedProcesses`,
`SortColumn`, and `SortAscending`. `ProcessControl` uses window autosave name
`ProcessWindow` and table configuration name `ProcessTableConfig`. The string
`20.0` is the initial refresh interval value candidate; confirm it in the
`registerDefaults:` decompilation before setting the implementation default.

## Controller contracts (IDA pseudocode)

The launch path registers defaults before reading them, loads the process types
into the Show popup, restores the saved type and sort settings, snapshots all
table columns, restores the saved visible-column configuration, connects table
column header-cell actions to the controller, assigns the table data source and
delegate, restores the search string, assigns the timer callback, and calls the
refresh-rate and process-fetch paths. If the inspector reports visible at
launch, the controller updates it and turns on the More Info switch. These
ordering and preference interactions are visible in
`-[ProcessControl applicationDidFinishLaunching:]` at `0x477c`.

`-getProcesses:` calls `+[Process enumerateProcessesAndFetch:YES]`, replaces
the full process list, updates filtering and sorting, then updates the timer.
`-updateRate` invalidates and releases any previous timer, clears the ivar, and
installs a repeating timer only when the selected interval is greater than the
minimum interval. `-bumpRate:` obtains the interval step and formatter bounds;
it beeps when the proposed interval falls outside those bounds and otherwise
sets the new value and refreshes timer scheduling. The filter accepts a process
only if the selected `ProcessType` matches and the search string is empty, the
searched process value is absent, or a case-insensitive substring match
succeeds. The refresh method preserves selected process objects across
refiltering/resorting, reloads the table, restores surviving selection, and
formats the displayed count using the three summary strings in
`Localizable.strings`.

`-exportProcessList:` presents an `NSSavePanel` with the localized default name
`Exported Processes.plist`, builds an array of each filtered process's
`dictionaryRepresentation`, and writes it as a property list. A failed write
beeps; this is not a CSV export. `-killProcesses:` maps selected table rows back
to process objects and invokes the per-process confirmation path for each.
`-killProcessWithConfirmation:` applies the recovered identity and protected
process branches. If the current user is `root`, names in the set (`init`,
`mach_init`, `kern_loader`, `update`, `nmserver`, `portmap`, `nibindd`,
`netinfod`, `lookupd`, `ppcd`, `loginwindow`, `Workspace`) first show the logout
warning. Otherwise, a user may act only on processes whose `USER` value matches
that user. The matching-owner set (`WindowServer`, `Viewer`, `pbs`, `AKServer`)
first shows the system-disruption warning; cancel returns without the final
prompt. The `DeleteProtectedProcesses` preference controls whether these
warnings offer `Go ahead` and whether the final prompt warns about unsaved work.
The ownership denial alert uses `Cancel`. In the final prompt, response `-1`
cancels, response `1` sends signal 2, and the other accepted response sends
signal 9.

These behaviors are recovered from the PowerPC reference at `0x4c48`, `0x4df4`,
`0x4ea4`, `0x4fb8`, `0x55d8`, `0x58ec`, `0x5c94`, and `0x5d3c`. The exact row
token mapping in process enumeration and target-runtime AppKit behavior remain
unverified; host syntax checks do not validate either.

The two name sets and localized strings above were extracted from the PowerPC
function's constant data at `0x91a4` and its call sites in `0x5d3c`. The i386
controller tests exercise owner denial, both final signals, the root
logout-warning sequence, and cancellation of the owner-protected `pbs` warning.
AppKit's live panel presentation remains unverified in the headless guest.

## Process-type loader contracts (IDA pseudocode)

`+[ProcessType allProcessTypes]` initializes its static result once. It
enumerates every bundled resource with extension `processType`, then searches every
`NSAllLibrariesDirectory` path for a `ProcessTypes` child directory and visits
its entries. The file helper receives the `ProcessType` class, a null directory
for the bundled file or the `ProcessTypes` directory path for a library entry,
and the file path. This gives the helper the class receiver it uses to allocate each
`ProcessType` instance; it does not receive an array or a capacity.

`_readTypesFromFile` reads a property-list object and catches exceptions from
both file reading and `strings` resource reading. A file/property-list exception
is logged as `Unable to parse contents of %@: %@` with the path and exception
reason.
For a file path, it derives the containing bundle and requests the localized
`strings` table; the built-in path uses the main bundle and the file's resource
name. A dictionary creates one type. An array creates a type for each element
that is a dictionary. Other root types and non-dictionary array elements are
ignored. Successfully initialized type objects are appended to the static
array; invalid type definitions are skipped.

`-initWithDictionary:strings:` requires `Name`; without it, it logs `No Name
specified in type dictionary %@` and releases itself. `Name` is looked up in the localized strings dictionary and
falls back to the original value. `Key` is optional. `Values` is accepted only
when it is an array; if absent or not an array, key `USER` receives the current
user as its sole value, a non-null key other than `USER` logs `No Values specified
in type dictionary %@` and invalidates the type, and a null key remains an
unfiltered type. Valid values are copied into an
`NSSet`. `-matchesProcess:` returns true when either key or values is null;
otherwise it tests whether the set contains the process value for the key.

These contracts are from Hex-Rays output for `0x6928`, `0x6594`, `0x6b58`, and
`0x6d74`; details such as the exact file-reading exception text and ownership
must be retained from the pseudocode/disassembly when implementing the helper.

## Architecture questions

This PowerPC image is 32-bit big-endian. Its `Process` fields and Objective-C
ivars have recorded PPC encodings/offsets in `abi.md`; these must not be copied as
the i386 runtime layout. Task 2 will record exact compiler and target headers,
then establish i386 structure sizes, alignments, signedness, syscall
availability, and API differences. The available reference set currently
contains no i386 ProcessViewer oracle.

## Static analyzer limits

The current `binrecon analyze` export contains addresses, sizes, instructions,
basic blocks, imports, relocations, and references for 128 IDA function records.
It does not include Hex-Rays pseudocode. The installed `idat.exe` is available;
this check did not establish whether a GUI decompiler is installed. Record that
availability before claiming pseudocode review. Instruction listings remain
the primary evidence when pseudocode cannot be obtained.

## Reconstruction progress: controller

`ProcessControl.m` implements launch/default setup, type and name filtering, refresh,
selection retention, supported sort contexts, count summaries, interval timers,
table data-source methods, column visibility, plist export, printing, inspector
routing, and termination prompts. The search field examines `NAME`; an absent name
value remains visible with a nonempty filter, as the reference pseudocode
specifies. Export uses Foundation collection property-list writing because the
guest Rhapsody headers do not provide `NSPropertyListSerialization`.

The PPC `updateRate` disassembly loads its threshold from function-relative
address `0x4ea4 + 0x311c = 0x7fc0`, whose reference bytes are zero. The controller
test checks timer invalidation at zero and scheduling for a positive interval.
Other i386 controller assertions cover type filtering, case-insensitive matching,
missing values, selected-row retention/removal, row values, menu enablement, and
filtered counts. These run against test doubles, not NIB-backed controls.

The i386 controller and table tests pass in the Rhapsody guest. Full launch, NIB
action auditing, alert response branches, export-panel interaction, printing,
column preference restoration, and GUI behavior remain unverified. The controller
still needs an instruction-level review against the complete PPC methods before
parity can be claimed; no i386 reference binary has been found.
## Reconstruction progress: Inspector and entry point

`Inspector.m` now implements the inspector tab model, split-view sizing,
visibility defaults, process invalidation observation, process fields, and the
arguments table. `_loadInspectorNib` preserves the nib's original tab height as
`_minTabContainerHeight` while sizing it to the split-view width; the i386
geometry test covers that frame calculation. The i386 `inspector` test verifies
argument-row count/value and empty/single-argument cases. `main` lives in
`ProcessControl.m`, matching the
reference source ownership, and forwards `argc`/`argv` to `NSApplicationMain`.
The full source set links to a Mach-O i386 executable in the disposable guest.

NIB-backed view transitions, split-view resizing, remembered tab state, process
invalidation during a live inspector session, and GUI launch remain unverified.
The PPC build target is unavailable, and source-level parity review for controller
and inspector view geometry remains open.

An i386 probe that loaded the real inspector NIB from a small test bundle failed
in the headless guest after pasteboard and `RulebookServer` lookup errors, with
an uncaught nil-value insertion into a Foundation dictionary. This is recorded
as an unverified NIB integration result; it does not validate the GUI path.

The staged ProcessViewer bundle and a minimal bundle that only calls
`NSApplicationMain` both exit with SIGBUS in the headless i386 guest after the
distributed-notification-server lookup fails. This isolates the observed failure
to the guest's GUI launch path; it does not verify GUI integration or establish a
ProcessViewer-specific launch defect.
The Inspector and entry point are implemented. A target `inspector` test checks
argument rows; the `main` function is in `ProcessControl.m`, the reference owner.
The full source set links as a Mach-O i386 executable. The staged test bundle
cannot be treated as GUI integration evidence because the guest's minimal
`NSApplicationMain` probe fails the same way.
