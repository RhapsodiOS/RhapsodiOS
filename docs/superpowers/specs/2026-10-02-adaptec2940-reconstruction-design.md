# drvAdaptec2940 i386 reconstruction

## Intent and completion standard

Complete the decompilation and reconstruction of `src/drivers-i386/scsi/drvAdaptec2940`
against Apple's shipped i386 driver, using binrecon and IDA. The user approved
the architectural approach on 2026-10-02: readable C/Objective-C, reference
interfaces and layouts, recovered sequencer data, build integration, and
function-by-function evidence with reference/rebuilt comparisons.

Completion requires implementation and behavioral review of all 168 handwritten
reference functions, plus verification of the two build-generated methods.
Resolving names or producing a compilable driver alone does not meet this
standard. Binary-analysis coverage, compilation, and hardware validation are
separate claims. This work requires the first two; hardware validation is
reported only if it is actually performed on a compatible target.

## 1. Reference and established findings

The authoritative kernel artifact is:

`C:\Users\raynorpat\Downloads\test\Drivers\i386\Adaptec2940SCSI.config\Adaptec2940SCSI_reloc`

| Property | Verified value |
| --- | --- |
| Size | 87,676 bytes |
| SHA-256 | `08E6C11EEC125847F485C86250C94C4AFCC025E59CF085B0C8039B94B2E79DF7` |
| Architecture | i386, little-endian Mach-O |
| Text section | `__TEXT,__text`, address 0, size 32,568 bytes |
| Defined text symbols / IDA functions | 170 / 170 |
| Adaptec2940 methods | 30, including nine IOThread-category methods |
| SCSIBus methods | 13, including `PrivateMethods` initialization |
| C functions | 125 |
| Generated methods | 2 |

These counts were independently checked with binrecon's Mach-O reader and IDA
function enumeration. Objective-C categories come from binrecon's method
metadata: IDA display names omit some category names. Both representations
must be reconciled in the inventory rather than treated as extra functions.

The generated methods are exactly:

- `+[Adaptec2940SCSIKernelServerInstance kernelServerInstance]` at `0x7f20`.
- `+[Adaptec2940SCSIVersion driverKitVersionForAdaptec2940SCSI]` at `0x7f2c`.

The existing [SCSI survey](../../drivers/scsi-reconstruction.md) records only
10 resolving symbols and calls this driver a stub. Its principal class name
matches, but the tree lacks `SCSIBus` and the reference C engine. Existing
matching selectors still require body review.

Direct IDA decompilation established these connections:

- `SCSIBus executeRequest:buffer:client:` creates a channel-bearing command
  buffer, forwards it to its `_direct` object's `executeCmdBuf:`, and returns
  the buffer's completion status.
- `Adaptec2940 initHostAdaptor` uses `PH_GetConfig`, `PH_InitHA`, and
  `PH_EnableInt`; allocates and aligns host data; and obtains a physical address.
  The current minimal port initialization does not implement this path.
- `Ph_LoadSequencer` selects a descriptor from `P_SeqExist`, patches
  `P_Seq_01`, downloads it through sequencer RAM ports, reads it back, and
  returns a failure if verification differs. The current tree lacks this data
  and loader.

These pseudocode observations guide analysis. Disassembly and relocations
must verify arguments, offsets, widths, and instruction ordering before they
become implementation facts; decompiler argument recovery is not authoritative.

## 2. Scope and boundaries

Include the controller and bus classes, all 125 reference C functions, their
data and callbacks, sequencer firmware, and the project metadata required to
build and register the driver. Preserve all reference paths, including Optima
queues, timeout/abort/reset, synchronous and wide negotiation, PCI discovery,
EEPROM access, cable detection, and termination.

Compare `Default.table`, `DriverInfo`, `Load_Commands.sect`, localization, and
help resources with the shipped configuration. Correct registration and
resource references while retaining the repository's packaging conventions.
The shipped `Adaptec2940SCSI` executable and `SCSIInspector.nib` belong to the
configuration inspector and are excluded from kernel-code reconstruction.

Do not modify other drivers, modernize DriverKit, add unsupported hardware,
or redesign error handling. Linux/BSD drivers may not serve as structural
templates. Hardware documentation may supply terminology; the reference
binary supplies behavior, offsets, masks, and ordering.

Readable C/Objective-C is the selected approach. Introduce assembly only where
an evidenced ABI or hardware sequence cannot be preserved by the legacy
compiler. Exact whole-image equality is not required; every functional
divergence must be resolved. Compiler/layout differences require explicit
evidence and documentation.

## 3. Architecture and source organization

Recover the reference hierarchy and instance-variable layouts from Objective-C
metadata and code before replacing the existing headers. Do not preserve the
current `IOSCSIController` superclass or `struct scb` merely because the stub
uses them. Retain reference selector spellings and category membership.

The logical flow is `IOSCSIRequest -> SCSIBus -> Adaptec2940 command dispatch
-> Adaptec HIM -> adapter sequencer`, with completion flowing back through
the reference callbacks and command buffer. The bus object exposes a channel;
the adapter owns hardware resources, SCBs, interrupts, and HIM host state.
Derive channel counts and initialization/lifetime rules from the binary.

All new source files live in
`Adaptec2940.drvproj/Adaptec2940.lksproj/` beneath the existing driver directory.

| Source unit | Responsibility |
| --- | --- |
| `Adaptec2940.m` / `.h` | Reference controller class, initialization, resource lifetime, interrupts, statistics, configuration parameters, bus ownership, command dispatch |
| `Adaptec2940Thread.m` | The nine reference IOThread methods, SCB allocation/alignment, submission, reset, completion, and host initialization; OSM callbacks colocated here |
| `Adaptec2940Private.h` | Private declarations, command-buffer and channel contracts |
| `Adaptec2940Types.h` | Evidenced register constants and layouts shared by the Objective-C and C code |
| `SCSIBus.m` / `.h` | All 13 bus methods and reference private category |
| `Adaptec2940HIM.h` | HIM contracts, host/SCB structures, callback signatures, and function declarations |
| `Adaptec2940HIM.c` | Core `PH_*` / `Ph_*` command, interrupt, message, negotiation, and recovery engine |
| `Adaptec2940Optima.c` | Optima queue management, free-SCB handling, scratch state, and mode-specific dispatch |
| `Adaptec2940Config.c` | PCI/BIOS/configuration, EEPROM, cable, and termination routines |
| `Adaptec2940Sequencer.c` | Sequencer descriptors, firmware bytes, and sequencer loading |

Assign each C function to one definition site in the inventory, preserving
reference spelling and linkage. The functional split is for readability; it
does not claim recovery of Apple's original translation-unit boundaries.
Place private implementation helpers with their consumers and expose only
cross-file contracts needed by recovered calls or function pointers.

Retire `Adaptec2940Routines.m` and the invented `aicInitController`,
`aicResetBus`, resource routines, `runPendingCommands`, and
`processCmdComplete:` once their reference replacements are integrated.
Remove their project entries and declarations as part of that replacement.

## 4. Layout, data, and hardware requirements

Record every observed structure field as an offset, width, and evidence
address. Recover bit fields and packed hardware prefixes carefully; provide
legacy-compiler-compatible size/offset assertions for all layouts crossing
HIM, DMA, callback, or Objective-C boundaries. Preserve pointer/address
conversion, SCB page constraints, scatter/gather construction, residual
accounting, sense storage, and timeout-message layout.

Recover initialized data and tables with their original bounds and
relocations. Known symbols include `_SP_HaStat_Values`,
`_CmdMessageTemplate`, `_timeoutMsgTemplate`, `_protocols`, `_P_Seq_01`, and
`_P_SeqExist`. Version data is accounted for separately as build metadata.
Record firmware length and SHA-256, descriptor values, patch locations, and
loader readback behavior. Treat embedded sequencer bytes as data, not missing
host CPU functions. Preserve runtime modification of the firmware buffer.

Preserve port widths, register masks, barriers/delay instructions, polling
conditions, and error branches. Reproduce EEPROM-write behavior from the
reference; do not run hardware probes that write EEPROM as a validation shortcut.

## 5. Request, completion, and recovery behavior

Recover command-buffer ownership and lifetime across the bus/controller
boundary, locks, messages, and IOThread dispatch. Follow the reference's
blocking/completion mechanism and channel routing. Derive SCB queue links,
physical mappings, tagging, and HIM submission from the calls and field
accesses, rather than extending the stub's fixed 16-SCB model.

Trace `PH_IntHandler` through completion and asynchronous-event callbacks to
`commandCompleted:` and `scbComplete:`. Preserve host/SCSI status translation,
actual-transfer calculation, autosense, resource release, and wakeup order.
Review timeout and abort paths for races with normal completion and reset.

Implement initialization unwind, command rejection, selection timeout, parity
and message failures, sequencer failure, bus/device reset, and queue abort
according to the binary. Do not add plausible fallback behavior to fill an
unresolved branch. Any unresolved functional branch remains unfinished work.

## 6. Configuration and build integration

Established table differences include:

- Our `"Class Name"` key is the reference's `"Class Names"` key, with value
  `"SCSIBus Adaptec2940"`.
- Our PCI auto-detect range differs from the reference mask
  `"0x00789004&0x00ffffff"`.
- The reference names `"Server Name" = "Adaptec2940SCSI"` and
  `"Help File" = "2940.rtfd"`.

Update nested `PB.project` and relevant Makefile lists to include the bus and
C sources, remove retired files, and emit the reference server/class names.
Keep the repository directory name `drvAdaptec2940`. Verify generated class
names rather than hand-writing Kernel Server glue. Correct bundled strings
and help paths; account for build-generated driver version text separately.

Reuse `vm/build-i386-scsi.sh` and the existing legacy guest connection helpers.
Build only this driver in a dedicated guest staging directory, with i386
architecture and appropriate DriverKit/System headers explicitly selected.
Do not rebuild or clean unrelated projects. Record the actual compiler,
flags, source revision, build log, and staged `_reloc` size/hash.

## 7. Evidence and artifact layout

Commit the driver source and resource corrections, project metadata, and:

```
tools/binrecon/profiles/adaptec2940.json
src/drivers-i386/scsi/drvAdaptec2940/reconstruction/
    source-map.json
    ledger.json
    interfaces.md
    divergences.md
    verification.md
```

Use a reference-only profile for the initial inventory; configure i386,
little-endian, `normalized-functions`, and output directory
`../out/adaptec2940`. Record the actual installed analyzer versions.
Add a rebuilt artifact for paired analysis after compilation. Use separate
ignored output directories for baseline and successive paired runs so stale
analysis cannot be mistaken for current evidence.

IDA defines the initial function partition. Use raw symbols, Objective-C
metadata, disassembly, and relocations to resolve naming and boundary disputes.
Additional binrecon analyzers may provide cross-checks when available; record
exactly which analyzers ran successfully. Do not label an IDA-only run as
multi-analyzer consensus or use incomplete CFG recovery as parity proof.

Keep reference binaries, IDA databases, decompilation dumps, analyzer outputs,
paired profiles, build objects, and logs outside Git under
`tools/binrecon/out/adaptec2940/` or the existing ignored build-output tree.
The checked-in documents identify evidence by address, artifact path/hash,
and reviewed conclusion without committing raw binary/decompiler dumps.

Update the driver's row and explanatory text in
`docs/drivers/scsi-reconstruction.md` and its entry in
`src/drivers-i386/README` only after the recorded checks justify the status.

## 8. Verification and acceptance

1. Pin the reference identity, inventory every text function and relevant data
   object, and reconcile category aliases. An unexpected function-count change
   requires an explicit inventory correction backed by evidence; never silently
   drop entries to make the map pass.
2. Validate the binrecon profile and schemas. Validate the final source map with
   `load_source_map(..., reference_analysis=..., repo_root=...)` against the
   complete partition. Require 168 mapped handwritten functions, no duplicate
   or disputed entries, and exactly two generated methods accounted for as
   build outputs. The two generated entries may remain source-unmapped with
   their explicit reason; they must exist in the rebuilt binary.
3. Give every reference function a ledger entry. Each handwritten function must
   reach at least `control-flow-confirmed` with ABI, constants, field widths,
   call targets, hardware effects, and recovery paths reviewed. No handwritten
   function may remain `unexamined`, merely `signature-confirmed`, or an
   intentional mismatch hiding missing behavior. Record the reviewer and
   concrete evidence for every accepted compiler/generated-code difference.
4. Run targeted independent checks for structure offsets, firmware bytes and
   descriptors, and recovered pure logic such as status/residual translation
   and queue transitions. Derive expected results from reference evidence.
   Mocked port tests may verify recovered access sequences but are not hardware
   validation. Do not write tests that merely reproduce implementation choices.
5. Produce a fresh guest-built i386 `_reloc`. Verify its Mach-O architecture,
   all expected exports/methods, generated names, linkage, and resources.
6. Run binrecon paired analysis and normalized-function comparison against that
   exact rebuilt hash. Inspect every mismatch. Exit 0 supports normalized
   parity; exit 1 with complete analysis can support completion only when every
   difference has specific evidence of compiler/layout variation preserving
   behavior. Incomplete analysis, unexplained differences, or missing paths
   fail completion. Do not widen ignores or weaken acceptance to conceal them.
7. Record final mapped counts, ledger-state totals, analyzer versions, build
   result/hash, comparison result and reviewed divergences in `verification.md`.
   Report hardware validation as not performed unless a compatible adapter
   actually exercised the reconstructed driver.

The implementation plan must order work by the recovered dependencies:
inventory and interfaces, types/data, HIM and its supporting routines,
controller/bus integration, then build and complete parity review. Source-map
coverage and behavioral evidence advance together; no intermediate mapping
milestone is presented as completed reconstruction.
