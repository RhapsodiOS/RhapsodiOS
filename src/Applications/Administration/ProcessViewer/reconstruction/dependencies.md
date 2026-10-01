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
  Foundation's task and pipe APIs. The method reads newline-delimited rows after
  the heading and extracts process IDs and displayed fields. Embedded output
  column keys include `USER`, `VSIZE`, `RSIZE`, `%CPU`, `%MEM`, `TTY`, `STAT`,
  `TIME`, and `NAME`; retain exact whitespace/token parsing from pseudocode.
- `_sysctl`: used by `-[Process(Private) _update]` with the four-item MIB
  `{1, 14, 1, pid}` and a 468-byte process-record buffer. It fills parent/group
  IDs, saved/real UIDs, status, and a process name used to populate the data
  dictionary. The named error is `sysctl failed: %s`; the source implementation
  must use the target's actual constants and `struct` definitions.
- `_table`: used by `-[Process arguments]` as
  `table(6, pid, buffer, 1, 4096)`. On success the method scans NUL-delimited
  entries, skips strings containing `=`, and builds a cached argument array.
  Reproduce the 4096-byte bound and result behavior from the reference.
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

The built-in protected process names include `root`, `Workspace`, `loginwindow`,
`ppcd`, `lookupd`, `netinfod`, `nibindd`, `portmap`, `nmserver`, `update`,
`kern_loader`, `mach_init`, `init`, `AKServer`, `Viewer`, and `WindowServer`.
Termination uses the recovered selected process identity and confirmation paths;
the positive alert result selects signal 2 and the default confirmation selects
signal 9. Preserve owner/protection behavior and alert text from localized
resources rather than simplifying the policy.

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
