# drvIntel82596 reconstruction findings

## Baseline defects

The source-only baseline is not a valid package: it has no `.drvproj`/`.lksproj` hierarchy or shared headers, and its generated top-level Makefile source lists refer to nonexistent/retired files. The implementation imports nonexistent `driverkit/IOEthernetDriver.h` and declares `Intel82596 : IOEthernetDriver`, while reference metadata and the shipped driver use `Intel82596 : IOEthernet`. Several inline class declarations duplicate adapter declarations.

The baseline contains a stub initializer and stubs for network-buffer allocation, interrupt disabling, debugger locking, timeout registration/cancellation, run-state access and interrupt enable. It invents selectors absent from the reference including `disableAllInterrupts`, `reserveDebuggerLock`, `releaseDebuggerLock`, `allocateNetbuf`, `setRunning:`, `isRunning`, and `setThrottleTimers` return-type/body assumptions. It also uses an incorrect `_nb_map` prototype and mismatched checksum/adapter types. These cannot count as function evidence.

The two source-map exceptions are the kernel-server/version methods emitted by the project framework. Binrecon marks every newly imported analyzer entry with `analyzer_agreement.generated=true`; this does not identify compiler-generated methods.

## Evidence and environment

* Reference identity is verified by the profile and the IDA export: 69,108 bytes, SHA-256 `BE6AED4264AB64119188AEE6A82AAB415940010DCF5705B6C241266AF45D0A11`.
* IDA 9.4 is installed and produced all 86 functions, including the address-zero Cogent probe. The approved plan template said 9.2; that path exists only as a license file on this machine. The profile therefore records the installed 9.4 `idat.exe`.
* Full pseudocode, disassembly, call edges and stored signatures are in ignored `tools/binrecon/out/intel82596/evidence/ida-functions.json`; no function failed decompilation.
* `analyze` successfully published IDA analysis and consensus reference files. It reported normalized-functions `FAIL` because there was no rebuilt artifact or comparison. This is the expected reference-only state, not a failed IDA analysis.
* Initial source-map mode resolves 75 Objective-C definitions. Nine C helpers plus two generated methods remain unmapped under `--objc-methods`; the initial map still contains all 86 addresses and the validator checks the partition.
