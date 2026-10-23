# AdaptecU2SCSI PPC reconstruction

## Intent and completion standard

Reconstruct the complete AdaptecU2SCSI implementation shipped in Mac OS X
Server 1.2v3's 5.6 PPC kernel and integrate it into RhapsodiOS. The user
approved the reference-first architecture, component split, recovery order,
and verification design on 2026-10-18.

The deliverable is readable C/Objective-C source for the controller, OSM,
and complete CHIM library; recovered sequencer firmware and hardware tables;
function-level evidence; and successful PPC kernel compilation and linking
through historical Make and Samurai. All shipped CHIM modes and recovery
paths remain in scope. Hardware validation is tracked separately and is not
a prerequisite for reconstruction acceptance.

This document specifies the reconstruction. It does not claim that the
existing drafts compile, that their behavior has been verified, or that the
reconstructed driver has run on an adapter.

## 1. Reference and established findings

The authoritative reference is:

`C:\Users\raynorpat\Downloads\test\MOSXS12v3\mach_kernel`

| Property | Measured value |
| --- | --- |
| Size | 2,983,828 bytes |
| SHA-256 | `D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD` |
| Architecture | PPC, big-endian, 32-bit Mach-O executable |
| Embedded release | `Kernel Release 5.6`, `kernel-190.1.obj~4/RELEASE_PPC` |
| Embedded build date | Tue Aug 8 18:54:21 PDT 2000 |
| Controller methods | 25 implementation addresses: 21 primary-class methods and four thread-category methods |
| OSM-region function bodies | 84, totaling 16,456 code bytes |
| CHIM function bodies | 392, totaling 119,688 code bytes |

These findings were checked using the repository's Mach-O reader and IDA.
Objective-C metadata establishes category membership; IDA's displayed method
names omit the thread category. Addresses below are reference virtual
addresses, and range ends are exclusive.

| Region | Address range | Current partition |
| --- | --- | --- |
| Controller, thread, OSM, and helpers | `0x18770c` to `0x18b754` | 84 bodies |
| CHIM | `0x18b754` to `0x1a8adc` | 392 bodies |

The stated 75 OSM functions account for 25 methods and 50 named C routines.
The wider region also contains `AdptMallocContiguous`, `AdptFreeContiguous`,
and seven unnamed bodies. Six unnamed bodies contain conversion operations;
the remaining body at `0x18b2a8` is a candidate for the draft's I/O-thread
helper. Their precise ownership and identities require review. None may be
dropped from coverage merely because it lacks an exported name.

The working inventory is therefore 476 function bodies. Freeze the final
inventory after reviewing boundaries, aliases, shared helpers, and generated
code. Any correction requires an address-specific explanation.

CHIM's 392 named bodies comprise 378 `SCSI...` routines and 14 `OSD...`
routines. Prefix counts include 239 `SCSIh...`, 34 `SCSIr...`, and 19
`SCSIx...` routines; prefixes inform organization but do not replace a
recovered dependency graph.

### 1.1 ABI anchors

Targeted extraction of `AdaptecU2SCSI.m` metadata establishes superclass
`IOSCSIController`, instance size `0x5d0`, and the following fields:

| Field | Offset | Size established by adjacent metadata fields |
| --- | --- | --- |
| `configuration` | `0x25c` | `0x44` bytes |
| `pTscb` | `0x2a0` | Four-byte pointer |
| `profile` | `0x2ac` | `0x1d0` bytes |
| `iobReserveSize` | `0x47c` | Four bytes |
| `HIMFunc` | `0x4cc` | `0xa8` bytes |
| `numIOBs` | `0x574` | Four bytes |
| `iobQ`, `handleQ`, `commandQ` | `0x580`, `0x588`, `0x590` | Eight bytes each |

Metadata also records names and type encodings for the configuration,
profile, and HIM function-table members. Recover those declarations before
implementing their consumers. `registerHandlerForIRQ:` takes an `int` and
returns `void`; `createOSMIOBPool` also returns `void`.

`SCSIFuncPtrs` contains a version word with value 4 and 41 function pointers,
for `0xa8` bytes total. `OSMRoutines` contains a first word with value zero
and 30 callback pointers, for `0x7c` bytes total. Preserve the first words as
separately typed fields when recovering the contracts; they are not callable
slots. `SCSIGetFunctionPointers` copies the public table to its caller.

### 1.2 Existing tree

The driver directory is
`src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/`, containing controller, thread,
and OSM drafts plus two headers. It has no complete CHIM library or firmware
implementation. Two CHIM-named routines embedded in `OSMFunctions.m` also
need reconciliation with the reference and their eventual owning source.

`AdaptecU2SCSI.m` repeats a substantial block of methods. `OSMFunctions.m`
contains conflicting `_PostProbe` implementations and competing probe
implementations. The header has inconsistent field names, types, and sizes;
for example, its 64-word configuration buffer overlaps later claimed
offsets. Metadata confirms incorrect return types in the drafts as well.
Removing duplicates alone cannot establish a valid driver.

`driverkit/ppc/autoconf_ppc.m` already names the driver and matches
`ADPT,2940U2B ADPT,3950U2B ADPT,2930CU ADPT,2930U`.
`conf/files.ppc` and the Samurai PPC source manifest currently omit its
sources. Existing autoconfiguration entries must be checked against reference
evidence when the driver is integrated.

## 2. Scope and component boundaries

Keep the implementation in the existing driver subtree. Retain source that
survives reference review and replace incorrect or conflicting drafts as
their recovered implementations become available. Every changed line must
serve this reconstruction or its build and verification requirements.

| Component | Responsibility | Principal dependencies |
| --- | --- | --- |
| Controller `.m` and headers | Discovery, initialization/unwind, request entry points, adapter lifecycle, statistics | DriverKit, OSM contracts, CHIM public API |
| Thread `.m` and category declarations | Request dispatch, deferred interrupt processing, completion, timeout/reset coordination | Controller state, locks, OSM/CHIM callbacks |
| `OSMFunctions.m` and declarations | Memory/DMA services, PCI/register access, callback table, IOB management, status translation | Kernel services and recovered shared types |
| CHIM C sources and private headers | Public API, resource management, hardware primitives, SCB operations, negotiation, interrupt handling, recovery | Recovered OSM callbacks, hardware and firmware descriptors |
| Firmware and table C sources | Four sequencer images, hardware/firmware tables, device tables, configuration/profile data | Recovered descriptor declarations and symbolic function references |
| `reconstruction/` | Inventory, interfaces, source map, review ledger, differences, acceptance record | Pinned reference and build identities |

Split CHIM by recovered responsibilities and dependencies. File boundaries
must make each group reviewable without inventing a new driver framework.
Keep related hardware-mode implementations together where that makes their
differences clear. Preserve reference linkage and mutability. C source names
must produce the expected Mach-O names; a raw Mach-O leading underscore is
not automatically part of the C identifier.

Include all reference behavior, including reference stubs and modes that
cannot currently be exercised. Preserve the distinction between an actual
reference stub and missing reconstruction. Standard64, Swapping32,
StandardAdv, and SwappingAdv are recovered CHIM modes; their names do not
change the 32-bit PPC host ABI.

An i386 port, additional adapter support, a replacement SCSI framework,
unrelated driver repairs, and a new emulator device are outside this work.

## 3. Recovery order and exit criteria

### 3.1 Freeze the inventory and external dependencies

Record the reference hash, architecture, analyzer versions, function ranges,
Objective-C methods/categories, named and unnamed helpers, and relevant data
objects. Follow code and data references beyond the contiguous regions to
identify additional driver-owned objects and shared kernel dependencies.
Record shared dependencies explicitly so reconstruction does not duplicate
existing kernel services.

Resolve function boundaries and aliases using machine code, symbols, and
metadata. Give unnamed bodies stable analysis identities with their original
addresses retained. Record candidate generated constructs provisionally;
final compiler-generated classification requires evidence of the generating
construct and its rebuilt counterpart during build verification.

Exit criterion: every candidate body and data object has an identity and
owner; all external dependencies have a declared provider; disputed entries
are resolved before the implementation inventory is frozen.

### 3.2 Recover interfaces and layouts

Recover controller ivars, inherited layout, configuration/profile records,
adapter and target control blocks, IOB/HIOB structures, SCBs, scatter/gather
entries, request wrappers, callback signatures, and dispatch tables.
Establish field widths, signedness, alignment, packing, ownership, and lifetime
from metadata and machine-code use. Host-native 64-bit structures cannot
stand in for the target layout.

Build a table-slot map for public HIM calls, OSM callbacks, hardware
operations, and firmware operations. Follow assignments as well as calls.
Indirect dispatch makes a direct-call graph insufficient. Keep uncertain
fields visibly unresolved in working evidence until accesses establish
their contracts; do not invent meanings to make the drafts compile.

Check recovered interfaces against the kernel-7 headers. Document any
necessary compatibility adjustment, its reason, and its verification
separately from the reference contract.

Exit criterion: declarations needed by each implementation group agree with
the evidence, with no conflicting signatures or overlapping fields.

### 3.3 Recover firmware and static tables

Recover `Seq_s64`, `Seq_w32`, `Seq_sAdv`, and `Seq_wAdv`, together with
`SCSIFirmwareStandard64`, `SCSIFirmwareSwapping32`,
`SCSIFirmwareStandardAdv`, `SCSIFirmwareSwappingAdv`, and the firmware
selection table. Establish image boundaries and lengths from descriptors
and loader accesses, cross-checking neighboring symbols.

Recover `SCSIHardwareAIC78XX`, `SCSIHardwareAICBayonet`, the hardware selection
table, host/subsystem device tables, public dispatch table, configuration,
default and adjustable adapter/target profiles, and other referenced data.
Preserve bytes, scalar widths, sentinels, alignment, and reference mutability.
Replace embedded reference addresses with verified symbolic targets in C.

Review firmware selection, download, runtime patching, and hardware-revision
conditions. Preserve any source image versus patched image distinction made
by the reference. Do not substitute another sequencer revision.

Exit criterion: firmware has exact byte counts and hashes; every descriptor
and table entry has a recovered interpretation, including pointer targets
where applicable; loader and patch rules have evidence.

### 3.4 Reconstruct CHIM by dependency groups

Start with hardware access primitives and mode-specific SCB operations,
then resource and queue management, and then their public API consumers.
Use the recovered graph to order discovery/configuration, initialization,
submission, negotiation, interrupt processing, completion, and recovery.
Cycles can be implemented together once their shared contracts are fixed.
The exact function batches belong in the implementation plan.

Review each function for arguments and returns, constants, field widths,
signed comparisons, direct and indirect calls, hardware effects, and all
reference branches. Pay particular attention to PPC byte-reversing loads
and stores, volatile accesses, barriers, DMA addresses, and cache operations.
Preserve the reference's register widths and operation order.

Exit criterion for a group: it compiles with the historical PPC compiler,
its targeted checks pass, and each function has recorded behavioral review.
Compilation alone does not advance a function to verified behavior.

### 3.5 Reconcile OSM and the controller lifecycle

Use the recovered declarations to repair the drafts. Select implementations
by reference evidence, remove superseded duplicates, and put CHIM routines
in their recovered owning component. Restore the reference class
initialization and category methods using the existing Objective-C build
and runtime conventions.

Trace the complete request path:

`IOSCSIRequest -> driver thread -> IOB/HIOB -> resource management -> SCB/sequencer`

Trace completion through interrupt handling, CHIM processing, OSM callbacks,
host/SCSI status and residual translation, resource release, requester
wakeup, and queue restart. Review queue freezing/unfreezing, discovery,
initialization failure/unwind, selection timeout, autosense, abort,
device/bus reset, and reference error paths in the same lifecycle.

Preserve lock ownership/order, interrupt state, deferred work, timer
registration/cancellation, and the ordering of normal completion versus
timeout/reset. Recovery must account for outstanding and waiting requests
and reference rules for releasing each resource. Unresolved functional
branches remain unfinished work.

Exit criterion: declarations and implementations are consistent, duplicates
are removed, and the lifecycle is covered by source mapping, review, and
targeted reference-derived checks.

## 4. Build integration

Add the final source list to `conf/files.ppc` under the appropriate existing
driver condition. Update `ninja/ppc-sources.ninja` source edges and ordered
link lists to agree with generated historical Makefiles. Change other PPC
manifest fragments only where the existing build layout requires it.
Verify the class and thread category are retained and registered, and that
all CHIM functions, callbacks, firmware, and tables are linked.

Use the documented i386-hosted historical PPC compiler backends on a
case-sensitive guest filesystem. Existing build guidance and successful
baseline evidence are in `src/kernel-7/ninja/README.md` and
`docs/build/kernel-samurai-ppc-validation.md`. Recheck actual availability
when implementation begins; prior build logs are not acceptance of this
driver.

Build RELEASE_PPC and DEBUG_PPC with historical Make and Samurai in private
source/output staging. Run the existing PPC command/order comparison suite
and record matched configuration, source lists, and link inputs. Verify
both stripped and unstripped products, target architecture, unresolved and
duplicate symbols, class/category metadata, and expected driver code/data.
Save compiler/flags, source revision, logs, and product hashes. Retain
unstripped products for function comparison.

Use a snapshot or throwaway copy of the build image, never a writable base
`vm/rhap-i386-bootstrapped-v2.img`. Any guest must have its own name and SSH,
QMP, and monitor ports. Confirm its name before shutdown through QMP; follow
AGENTS.md for writable-guest synchronization, reboot, and snapshot resync.
An i386 build guest is a PPC compilation environment, not a PPC execution
test or adapter validation.

## 5. Evidence and tooling

Reuse binrecon's existing profile, analysis, source-map, and ledger formats.
Add `tools/binrecon/profiles/adaptecu2scsi-ppc.json`, configured for big-endian
PPC and the complete recovered function scope. Begin with reference-only
analysis and add a rebuilt artifact once compilation succeeds. Use the
rebuilt symbol/metadata inventory to establish its own scope; reference
addresses cannot be reused as rebuilt addresses.

Use IDA for the initial function partition and disassembly/decompilation.
Record actual analyzer versions. Additional analyzers can cross-check
supported portions, but only successful runs count as evidence. Do not
require a new generic analysis framework.

Whole-kernel Objective-C extraction currently encounters an unrelated
unbacked symbol-table address. Targeted extraction of the two Adaptec class
and category modules succeeds. Scope extraction to those modules and verify
all their records; a limitation in an unrelated module must not silently
remove driver metadata. Make a narrow tooling correction only if needed
for a required driver check.

Keep C functions and unnamed helpers in the source-map scope. An
Objective-C-only map is insufficient. Validate the map with
`load_source_map(..., reference_analysis=..., repo_root=...)` against the
complete saved driver partition and pinned reference identity. Reconcile
all mapped names, full function sizes, aliases, source locations, and
explicit boundary classifications.

Check in the reconstructed sources and firmware arrays, build integration,
profile, and the following records beneath the driver directory:

```text
reconstruction/
    inventory.md
    interfaces.md
    source-map.json
    ledger.json
    divergences.md
    verification.md
```

`inventory.md` records reference identity, functions/data, ownership,
boundary decisions, and dependency providers. `interfaces.md` records the
recovered ABI, layouts, tables, lifecycle, and concurrency contracts.
`divergences.md` explains each accepted compiler or kernel-7 compatibility
difference with evidence. `verification.md` records exact checks, results,
product hashes, and the separate hardware-validation status.

Keep reference binaries, IDA databases, bulk decompilation, analyzer output,
paired run profiles, build objects, and logs outside Git under
`tools/binrecon/out/adaptecu2scsi-ppc/` or the existing ignored build tree.
Separate baseline and successive paired runs to prevent stale output from
being mistaken for evidence about the current source or rebuilt hash.

## 6. Verification and acceptance

### Complete accounting and behavioral review

Every in-scope reference body must map to recovered/reused source or be
demonstrated to be generated from a specific source construct and verified
in the rebuild. Shared/generated classification alone is not an exemption
from accounting. Resolve all boundary disputes and explain any change from
the initial 476-body inventory.

Every handwritten function must reach at least `control-flow-confirmed`
in the existing ledger, with concrete evidence and reviewer recorded.
Review ABI, constants, widths, call targets, data references, hardware
effects, and error/recovery branches. Missing implementation cannot be
accepted as an intentional mismatch. Reference stubs require evidence and
their reference behavior must be reproduced.

### ABI and data checks

Compare rebuilt PPC class/category metadata, instance size, ivar offsets,
and method encodings with the reference. Use historical-compiler-compatible
size/offset checks for C structures and table layouts. Target-compiled
layout probes or object inspection establish PPC layout; host layouts do
not establish it.

Require byte-identical firmware arrays and exact sizes/hashes. Compare
table scalar fields and sentinels exactly. Normalize pointer fields to
verified target symbols and offsets when comparing rebuilt tables, since
their numeric addresses change. Verify firmware selection, load lengths,
and runtime patch rules separately from the unmodified image hashes.

### Targeted behavioral checks

Derive expected results from reference metadata, machine code, and data.
Cover byte ordering, mode-specific SCB and scatter/gather encoding,
status/residual translation, request/queue transitions, and the recovered
initialization and recovery sequences. Exercise reference edge and failure
branches, including resource ownership during completion, timeout, and
reset. Keep tests focused on meaningful externally observable results.

Mocked register and callback traces can check recovered operation widths,
values, ordering, and state transitions. They do not establish timing,
physical DMA/cache behavior, sequencer execution, or successful adapter I/O.
Do not create tests whose expected result merely repeats the implementation.

### Fresh builds and paired analysis

Require successful RELEASE_PPC and DEBUG_PPC kernel compile/link through
both historical Make and Samurai, with consistent source/flag/link-input
checks. Confirm the expected driver functions, metadata, firmware, and
tables in the resulting kernels. Existing unrelated code differences from
kernel-190.1 are outside the driver comparison scope; necessary shared ABI
compatibility adjustments require their own recorded evidence.

Run paired analysis against the exact recorded rebuilt hashes. Inspect every
normalized-function mismatch. Exact normalized matches support parity;
complete analysis with differing instructions can support acceptance only
when each difference has specific evidence of compiler/layout variation
preserving behavior or an approved, verified kernel-7 compatibility
adjustment. Do not broaden ignores or suppress functions to pass acceptance.
Incomplete analysis, missing paths, and unexplained differences fail it.

Finish `verification.md` with final function/data counts, source-map result,
ledger totals, targeted-check results, analyzer identities, four build
results and hashes, paired comparison results, and reviewed differences.
Only then may reconstruction and PPC build acceptance be reported complete.
Record hardware validation as not performed unless a compatible adapter
actually exercised the reconstructed driver.

## 7. Planning handoff

After the user reviews and approves this written spec, create the detailed
implementation plan using the writing-plans workflow. Order its tasks by
the recovery stages and dependency groups above, with file-level changes,
reference-derived checks, and concrete exit criteria. Reconstruction,
mapping, and behavioral review advance together throughout the plan.

The user reviews that plan and selects its execution method before
implementation begins. This spec authorizes no claim of completed recovery,
compilation, PPC execution, or hardware qualification by itself.
