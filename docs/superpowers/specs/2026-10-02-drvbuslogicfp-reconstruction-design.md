# drvBusLogicFP binary reconstruction

## Intent and approval state

Complete the decompilation and reconstruction of the existing i386
`drvBusLogicFP` SCSI driver using `tools/binrecon` and IDA. The intended
result is readable, buildable driver source whose interfaces, data layouts,
and behavior are accounted for against Apple's shipped binary. A source map
that merely resolves names is insufficient.

The user approved the proposed architecture on 2026-10-02: recover
`BLFPController`, its categories and SCCBs; reconstruct the 93 C functions;
record function evidence; align configuration and build metadata; produce
an i386 `_reloc`; compare the reconstruction against the reference. This
document makes that design concrete. Written-spec review and implementation
planning follow; implementation has not started.

The assumed runtime target is the repository's historical i386 DriverKit
environment. Hardware validation is a separate claim requiring an actual
FlashPoint adapter or a verified compatible emulator. This reconstruction
does not require a hardware boot and must not imply hardware validation.

## Reference and observed baseline

Reference file:

`C:\Users\raynorpat\Downloads\test\Drivers\i386\BusLogicFPSCSI.config\BusLogicFPSCSI_reloc`

| Property | Observed value |
| --- | --- |
| Architecture / byte order | i386 / little endian |
| File size | 77,964 bytes |
| SHA-256 | `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E` |
| Text section | address `0x0`, size 30,616 bytes |
| IDA function partition | 123 functions |
| Driver functions | 28 Objective-C methods and 93 C functions |
| Generated methods | 2 Kernel Server methods |
| Principal class | `BLFPController` |
| Loaded Server name | `BusLogicFPSCSI` |

These values were checked with binrecon's Mach-O reader and IDA. IDA
decompilation was inspected for probe, initialization, request execution,
SCCB conversion/allocation, reset, interrupt detection, and callback dispatch.
The existing SCSI survey reports only 7 of 123 reference symbols resolving
to current source.

The live source has a `BusLogicFPSCSI` class and a Linux-derived
`FlashPoint.c`. The wrapper calls `FlashPoint_*`, whereas the reference's
adapter interface is `SccbMgr_*`. The C file's implementation is guarded by
`CONFIG_SCSI_FLASHPOINT`; the current project preamble does not enable that
guard. Its disabled branch supplies declarations rather than the driver's
implementation. Enabling that guard alone does not recover Apple's ABI.

Current project `NAME` / `PROJECTNAME` values are `BusLogicFP`, disagreeing
with the reference server name and generated methods. `Default.table`
already names `BLFPController`, but advertises `0x8138104b` and version
`1.0`; the reference has `0x8130104b` and `5.00`.

## Scope and source organization

Retain the repository directory and `.drvproj` / `.lksproj` directory names.
Keep existing source filenames where useful; rename the Objective-C class
and replace its implementation. The planned units are:

| Unit | Responsibility |
| --- | --- |
| `BusLogicFPSCSI.h` / `.m` | `BLFPController`, public DriverKit methods, probe, initialization, statistics, message dispatch |
| `BusLogicFPPrivate.h` | Private command/SCCB integration types and category declarations |
| `BusLogicFPThread.m` | The reference `IOThread` category, request conversion, submission, reset, completion, SCCB pool |
| `FlashPoint.h` / `.c` | Reference manager types, adapter/card/target state, DMA, phases, negotiation, SCAM, queues, EEPROM, OS hooks |

`PrivateMethods` may remain implemented in `BusLogicFPSCSI.m`; its two
methods do not justify another source unit. Standalone integration functions
`parseConfigSpace`, `blcTimeout`, `doesCrossPage`, and `BLCCallback` belong
with the controller/thread source that uses them. Keep the reference C
symbol names and linkage. Do not retain the Linux interface through wrappers
introduced only to make source mapping pass.

Required categories from binrecon's Objective-C metadata index:

- `BLFPController(PrivateMethods)`: `probeForBoard`, `executeCmdBuf:`.
- `BLFPController(IOThread)`: `threadExecuteRequest:`, `threadResetBus:`,
  `sccbFromCmd:`, `sccbComplete:reason:`, `cmdComplete:`, `allocSccb`,
  `freeSccb:`, `createSCCBs`, `resetHardware`.

The 17 remaining controller methods belong to the main implementation.
`probe:` is counted from the text symbols and IDA even if the metadata
walker omits its metaclass method; the symbol partition remains authoritative.

Touch build lists, metadata, configuration, and status documentation only
where this reconstruction requires it. Other SCSI drivers, general DriverKit
interfaces, kernel behavior, and unrelated local changes are outside scope.
The adjacent user-space inspector executable and nib are outside the kernel
driver reconstruction.

## ABI and data flow

Recover the Objective-C instance-variable names, offsets, encodings, and
instance size from `__OBJC` metadata. Recover manager/card/target/SCCB types
from loads, stores, allocation sizes, and call sites. Resolve pointer,
integer, signedness, and packing decisions with disassembly. Decompiled
argument lists are evidence to investigate, not authoritative prototypes.

Initial SCCB evidence, to be checked against assembly before implementation:

| Offset / size | Use observed in the reference |
| --- | --- |
| Total size 260 (`0x104`) | `createSCCBs` allocation stride and zeroing size |
| Offset 40 | Completion callback, assigned `BLCCallback` |
| Offset 44 | Adapter I/O base |
| Offset 100 | Embedded scatter/gather array, up to 17 entries of 8 bytes |
| Offset 236 | Owning command buffer pointer |
| Offset 248 | Controller pointer used by `BLCCallback` |
| Offsets 252 / 256 | Driver free-list links |

The hardware-manager queue links and the driver free-list links must be
separate fields if the reference uses separate offsets. Preserve the
reference's manager-visible prefix and OS-private tail. Add compile-time
layout checks usable with the historical compiler for recovered critical
sizes and offsets; do not rely on a 64-bit host's native pointer layout.

The reference's client flow is:

1. `executeRequest:buffer:client:` clears a 48-byte command buffer, stores
   the request, data buffer and client task, calls `executeCmdBuf:`, and
   returns the command's result.
2. The controller queues the command and uses its DriverKit interrupt/message
   path and lock/wait protocol. Recover the exact command ownership and
   wakeup transitions from `executeCmdBuf:`, message dispatch, and completion.
3. `threadExecuteRequest:` obtains an SCCB; `sccbFromCmd:` validates the CDB
   and creates direct or scatter/gather transfer state.
4. `SccbMgr_start_sccb` and the phase/DMA engine submit and process the request.
5. Interrupt handling and `BLCCallback` reach `sccbComplete:reason:`;
   completion translates status, residual and sense data, recycles the SCCB,
   and wakes the waiting command through `cmdComplete:`.

Recover abort, timeout, reset, and free paths as part of this same ownership
model. Do not replace the reference protocol with the current ad hoc command
port/thread loop. Preserve queue statistics, IRQ sharing, target reservations,
and configured-instance handling where the binary implements them.

`resetHardware` calls `SccbMgr_config_adapter`, treats `0xffffffff` as failure,
stores the returned card handle on success, and waits 10 seconds. It returns
0 on success and 1 on failure. Preserve this convention rather than assuming
a `BOOL` success result.

## FlashPoint engine

All 93 C functions must receive individual source and evidence coverage.
Reconstruct these related groups without importing Linux control flow:

- Adapter manager: sensing/configuration, start/abort, interrupt detection
  and service, bad-interrupt handling, reset, timer hooks, table initialization.
- DMA and sequencer: `autoLoadDefaultMap`, `autoCmdCmplt`, data-transfer
  dispatch, direct/SG bus-master startup, timeouts, abort/restart, `XbowInit`,
  and `BusMasterInit`.
- SCSI phases: decode, data-in/out, command, status, message-in/out,
  illegal phase, FIFO checks and bus-free transitions.
- SCAM: arbitration, assignment, selection, isolation, transfer cycles,
  wire protocols, legacy selection, matching and saving device information.
- SCSI protocol: selection/reselection, messages, extended messages,
  synchronous and wide negotiation, reset, autosense, padding, DMA completion
  and SCCB initialization.
- Queues and utilities: pending/selection/disconnect/completion/flush/search,
  residual updates, wait routines and EEPROM bit operations.
- OS hooks and the four controller integration functions.

Copy register offsets, access widths, masks, polling conditions, timeout
counts, tables and sequencer words from binary evidence. Preserve port-I/O
ordering and signed/unsigned arithmetic. Functions that are no-ops in the
reference, such as an OS hook, remain no-ops only after confirming that fact.
Every required data table, global initial value, and state layout receives
evidence coverage alongside its consuming functions.

The existing Linux file can identify topics to investigate, but is not the
implementation template. The reference wins whenever the source and binary
disagree. Do not attribute newly reconstructed source to Apple as recovered
original text; preserve applicable existing notices and describe the source
as reconstruction.

## Evidence and comparison workflow

Create `tools/binrecon/profiles/buslogicfp.json`, initially reference-only,
using `BINRECON_REFERENCE` and output directory `../out/buslogicfp`. Use IDA
for function boundaries, assembly, pseudocode, cross-references and types.
Enable another supported analyzer for the i386 consensus where it runs
successfully; record failures or boundary disputes explicitly. No majority
vote overrides a demonstrated symbol boundary or instruction trace.

Commit driver-local `reconstruction/source-map.json`, `ledger.json`, and
`divergences.md`. Keep binaries, IDA databases, decompiler dumps, analyzer
output and build logs outside Git under ignored output/evidence directories.
Record commands, hashes and evidence paths so results can be reproduced.

The ledger has exactly one entry for each of the 123 reference functions.
Map all 121 driver functions to actual definitions and review their behavior.
Use `assembly-matched` only with supporting instruction-level evidence;
`control-flow-confirmed` requires reviewed branches, calls, state updates,
constants, widths and return values. Names or prototypes alone cannot justify
either status. No driver function may finish `unexamined` or merely
`signature-confirmed`.

The only default generated-code exceptions are:

- `+[BusLogicFPSCSIKernelServerInstance kernelServerInstance]` at `0x7780`.
- `+[BusLogicFPSCSIVersion driverKitVersionForBusLogicFPSCSI]` at `0x778c`.

Record them as build-generated exceptions with reasons. Check their presence
and server identity in the rebuilt artifact rather than hand-writing them.
Do not hide substantive implementation omissions as intentional mismatches.

After producing the rebuilt artifact, bind its actual SHA-256 into the
ledger, run binrecon analysis/comparison of reference and rebuild, and retain
the machine-readable comparison. Use Objective-C metadata to reconcile
category names or symbol aliases. Resolve every behavioral mismatch; review
compiler/register-allocation differences against disassembly and document
them without reporting byte identity. Symbol, selector, string and import
checks supplement function review and cannot replace it.

A reference-only analysis exit code of 1 can mean a missing comparison;
inspect the summary rather than treating it as a driver failure or a passing
parity gate. Publish separate counts for source coverage, evidence status,
and rebuilt comparison results.

## Build, bundle and resources

Align the nested project's emitted driver/server name to `BusLogicFPSCSI`
while retaining the directory names. Keep Makefile source lists and
`PB.project` lists consistent with the reconstructed files. Prefer preamble
overrides for generated Makefile variables where the build framework permits
them; make explicit list changes when needed. Remove aggregate preamble
entries that incorrectly prescribe the replaced source units.

Correct `Default.table` to the reference PCI ID and version. Treat the
build-generated `Driver Version` string as compiler metadata rather than
requiring the 1998 developer name/timestamp. Preserve `BLFPController`, the
reference server name, IRQ sharing, valid IRQs, boot-driver flag and help key.

Include the reference `English.lproj/Localizable.strings` and
`English.lproj/Help` resources in the driver project, including the
`BusLogicFP_PCI.rtfd` attachments and `TableOfContents.rtf`. Compare copied
resource bytes with the supplied reference and register resource lists.
Do not copy the user-space inspector or its nib into this kernel-only work.
The existing `Load_Commands.sect` already has the reference `WIRE` behavior;
retain it and compare the emitted load-command section semantically.

Use the existing guest build facilities in a task-specific source/object/
destination area, avoiding interference with ongoing guest builds. A PPC
guest can serve as the build host only if the output is confirmed i386;
a native PPC `_reloc` does not pass. Record compiler/linker versions,
architecture flags, warnings and exit status. Adapt `vm/build-i386-scsi.sh`
only if needed to stage the target correctly. Stage the final artifact under
`out/i386/drvBusLogicFP/BusLogicFPSCSI_reloc` and keep it out of Git.

Baseline-build failures are recorded as existing defects; fixing a doomed
stub merely to produce a baseline artifact is not required. A final compile
failure must be fixed. Guest unavailability permits independent source and
evidence work but leaves the build and comparison gates incomplete.

## Verification and completion criteria

| Gate | Required result |
| --- | --- |
| Reference identity | Profile resolves the recorded i386 binary and SHA-256 |
| Partition | 123 unique ledger entries, with boundary/alias questions resolved |
| Source coverage | 28 controller methods and 93 C functions have real definitions; exactly two generated exceptions |
| ABI | Assembly-checked ivars, SCCB/command/card/target layouts, SG entries and callback/queue offsets; i386 layout checks pass |
| Behavioral evidence | All 121 driver functions reach at least `control-flow-confirmed`; no unresolved behavioral omissions |
| Residue | No live `BusLogicFPSCSI` controller class, Linux `FlashPoint_*` API, disabled implementation guard, or invented replacement protocol |
| Bundle | Class/server identity, PCI ID, version, source lists, strings/help and load commands agree with reference, apart from documented generated metadata |
| Build | Guest compiler/linker exit 0; staged Mach-O is i386; imports and generated server methods are reviewed |
| Rebuilt comparison | Reports exist for the actual rebuilt hash; every divergence is resolved or explained with evidence as a nonbehavioral compiler/build difference |
| Documentation | SCSI report and i386 README state exact evidence counts, build/comparison results, and hardware-validation status |

Use focused tests where they check recovered behavior independently: SCCB
layout/page-crossing boundaries, CDB-length/direction decisions, direct/SG
transfer limits, residual/status conversion and queue ownership. For low-level
paths that can be isolated without changing production behavior, exercise
register-access sequences with a mock I/O trace. Base expectations on the
reference instructions, not the reconstructed implementation. No test may
claim physical SCSI/DMA operation from mocks.

Run schema/source-map validation and appropriate selector/symbol/import
checks. Run the binrecon test suite if shared tool code changes; adding a
driver profile alone does not justify unrelated tooling changes. Keep
unrelated local changes untouched.

Completion means all required gates pass. If build access, decompilation or
comparison remains unavailable, report precisely which gates are incomplete
and continue other authorized work; do not label a partial source rewrite
as a completed reconstruction.

## Implementation sequence for subsequent planning

1. Establish the profile, symbol/category partition, source map, ledger and
   baseline divergences; export reference evidence.
2. Recover and check ABI types, constants, data tables and OS hooks.
3. Reconstruct controller lifecycle, command/message protocol, SCCB pool,
   conversion, timeout/reset and completion.
4. Reconstruct manager, queue and DMA/sequencer paths, then phase/protocol,
   negotiation, SCAM and EEPROM groups; review every function against IDA.
5. Align project metadata/configuration/resources; compile in the guest and
   resolve compile/link defects.
6. Analyze the actual rebuild, resolve comparison differences, refresh the
   source map/ledger, run focused verification and publish accurate status.

The implementation plan must preserve these dependencies and acceptance
criteria. It will specify executable commands and evidence checkpoints after
the user reviews this written spec.
