# PPC global data reconstruction

The PPC binary has 27 named `__DATA,*` symbols covered by the source-name
audit. Nineteen are application data and eight are runtime/linker data. The
application names, recovered values, and source definitions are listed below.
The names were checked against the PPC symbol table. Fixed-address string tables
and the sort-type bytes were decoded from `__DATA`; status values were recovered
from `_update` pseudocode because their pointer slots use runtime relocations.
The source definitions compile into corresponding i386 Mach-O symbols. This
records data identity, not a claim of byte-for-byte PPC output.

| PPC symbol | Reconstructed value or role | Source definition |
|---|---|---|
| `__ProcessSortTypes` | `@`, `f`, `f`, `f`, `f` sort-kind bytes | `Process.m`: `_ProcessSortTypes` |
| `__localizedProcessStatusValues` | Launching, Running, Sleeping, Suspended, Zombie | `Process.m`: `_localizedProcessStatusValues` |
| `__allProcessesByPid` | PID-to-`Process` map | `Process.m`: `_allProcessesByPid` |
| `_administratorUserName` | `root` | `ProcessControl.m`: `administratorUserName` |
| `_keyName` | `_NAME` | `Process.m`: `keyName` |
| `__allTypes` | Process-type registry | `ProcessType.m`: `_allTypes` |
| `__SelectedInspectorTabDefaultKey` | `SelectedInspectorTab` | `Inspector.m`: `_SelectedInspectorTabDefaultKey` |
| `__InspectorVisibleDefaultKey` | `InspectorVisible` | `Inspector.m`: `_InspectorVisibleDefaultKey` |
| `__TabTitles` | Process ID, Statistics, Path & Arguments | `Inspector.m`: `_TabTitles` |
| `_ProcessBecameInvalidNotification` | `ProcessBecameInvalidNotification` | `Inspector.m`: `ProcessBecameInvalidNotification` |
| `_ProcessKeys` | `NAME`, `%MEM`, `%CPU`, `RSIZE`, `VSIZE`, `USER`, `PID`, `PPID`, `PGID`, `STAT`, `TIME` | `Process.m`: `ProcessKeys` |
| `__TypePopUpDefaultKey` | `DefaultTypeTag` | `ProcessControl.m`: `_TypePopUpDefaultKey` |
| `__TypesFileDefaultKey` | `TypeDescriptionFile` | `ProcessType.m`: `_TypesFileDefaultKey` |
| `__IntervalDefaultKey` | `RefreshInterval` | `ProcessControl.m`: `_IntervalDefaultKey` |
| `__AllowKillDefaultKey` | `DeleteProtectedProcesses` | `ProcessControl.m`: `_AllowKillDefaultKey` |
| `__SortIdentifierDefaultKey` | `SortColumn` | `ProcessControl.m`: `_SortIdentifierDefaultKey` |
| `__SortAscendingDefaultKey` | `SortAscending` | `ProcessControl.m`: `_SortAscendingDefaultKey` |
| `_MachineMightCrashProcesses` | `init`, `mach_init`, `kern_loader`, `update`, `nmserver`, `portmap`, `nibindd`, `netinfod`, `lookupd`, `ppcd`, `loginwindow`, `Workspace` | `ProcessControl.m`: `MachineMightCrashProcesses` |
| `_LogoutProcesses` | `WindowServer`, `Viewer`, `pbs`, `AKServer` | `ProcessControl.m`: `LogoutProcesses` |

The remaining eight symbols are `_NXArgc`, `_NXArgv`, `_environ`, `___progname`,
`dyld_lazy_symbol_binding_entry_point`, `dyld_func_lookup_pointer`,
`__cplus_init`, and `_catch_exception_raise`. They are supplied by the NeXT
runtime or dynamic linker rather than this application's source.
