# drvAdaptec2940 Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct and review all 168 handwritten functions in Apple's i386 Adaptec2940SCSI driver, verify its two generated methods, and produce a guest-built driver with complete reference/rebuilt evidence.

**Architecture:** Recover the binary contracts first, then implement the Adaptec HIM, Optima queues, configuration and sequencer code behind the reference controller and SCSIBus classes. Preserve reference layouts and hardware behavior; use readable C/Objective-C and document compiler differences through paired binrecon analysis.

**Tech Stack:** Python 3.12, repository binrecon, IDA/Hex-Rays with IDAPython, legacy DriverKit Objective-C/C, Rhapsody guest compiler and Project Builder makefiles.

**Spec:** [Approved reconstruction design](../specs/2026-10-02-adaptec2940-reconstruction-design.md).

## Global Constraints

- Reference: `C:/Users/raynorpat/Downloads/test/Drivers/i386/Adaptec2940SCSI.config/Adaptec2940SCSI_reloc`.
- Reference size: 87,676 bytes; SHA-256: `08E6C11EEC125847F485C86250C94C4AFCC025E59CF085B0C8039B94B2E79DF7`.
- i386, little-endian; 170 functions = 30 controller methods + 13 bus methods + 125 C functions + two generated methods.
- All 168 handwritten functions require at least `control-flow-confirmed`; no unresolved behavioral divergence is accepted.
- Generated methods: `+[Adaptec2940SCSIKernelServerInstance kernelServerInstance]` at `0x7f20`, and `+[Adaptec2940SCSIVersion driverKitVersionForAdaptec2940SCSI]` at `0x7f2c`.
- IDA defines the initial partition. Retain category aliases from Objective-C metadata; never use `--scope-to-objc` for this driver's complete map.
- Preserve reference types, register widths/masks, DMA conversion, polling, delay/barrier instructions, callback ordering, and firmware runtime patching.
- No Linux/BSD structural templates, new hardware support, or unrelated driver/toolchain cleanup.
- Keep binaries, databases, raw pseudocode, build products and analyzer output outside Git.
- Use a dedicated checkout and guest staging directory. Read CLAUDE.md and the spec; apply using-git-worktrees at execution time. Reuse a suitable attached worktree before creating one.
- Do not use `sync-src.ps1 -All`, buildall, or broad cleans. A guest build must target i386 explicitly.
- If booting the i386 VM for harness execution, use a task-specific temporary image with `RHAP_TEST_IMAGE`; never boot/write the original or golden image, or share another agent's test image.
- Use `drvAdaptec2940: ` commit prefixes, short descriptions, no metadata, and explicit paths when staging.
- Binary coverage, compilation, and hardware validation remain separate results.

## Review Focus

1. A DMA/SCB allocation crosses a page boundary: preserve the reference alignment and physical mapping; Task 2 layout tests and Task 7 `scb-page-boundary` case.
2. A timeout/reset coincides with completion: preserve reference ownership, queue removal and wakeup order; Task 7 `completion-timeout-order` and `completion-reset-order` cases.
3. Short transfer or CHECK CONDITION: preserve residual count, status and autosense behavior; Task 4 `short-transfer` and Task 6 `autosense-completion` cases.
4. Queue exhaustion or abort during active selection: preserve free-list/chain state and callback disposition; Task 6 `free-scb-exhaustion` and `abort-active` cases.
5. Firmware readback, EEPROM access, or host initialization fails: reproduce the reference failure and cleanup path; Task 3 `sequencer-readback-failure`, Task 5 `eeprom-failure`, and Task 7 `init-unwind` cases.

Tests reproduce reference-supported inputs and outcomes. For interleavings, only exercise those the reference's threading and locking model permits. Findings that expose a historical bug are recorded, not silently redesigned.

## File Structure and command conventions

Commands run at the execution checkout root. Set these PowerShell variables:

```powershell
$adaptecPython = 'D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe'
$adaptecDriver = 'src/drivers-i386/scsi/drvAdaptec2940'
$adaptecLks = "$adaptecDriver/Adaptec2940.drvproj/Adaptec2940.lksproj"
$adaptecRecon = "$adaptecDriver/reconstruction"
$adaptecProfile = 'tools/binrecon/profiles/adaptec2940.json'
$adaptecOut = 'tools/binrecon/out/adaptec2940'
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:/Users/raynorpat/Downloads/test/Drivers/i386/Adaptec2940SCSI.config/Adaptec2940SCSI_reloc'
```

Create production files under `$adaptecLks`:
`SCSIBus.{m,h}`, `Adaptec2940HIM.{c,h}`, `Adaptec2940Optima.c`,
`Adaptec2940Config.c`, and `Adaptec2940Sequencer.c`.
Rewrite `Adaptec2940.{m,h}`, `Adaptec2940Private.h`,
`Adaptec2940Types.h`, and `Adaptec2940Thread.m` there.
Retire `Adaptec2940Routines.m` when Task 7 removes its last live consumer.

Create `$adaptecRecon/{source-map.json,ledger.json,interfaces.md,divergences.md,verification.md}`
and `$adaptecProfile`. Test sources live under `$adaptecLks/tests/` and are
excluded from driver source lists and packaging:
`test_reconstruction.py`, `reference-cases.json`, `adaptec2940-checks.c`,
and `run-checks.sh`.

Modify the driver's `Default.table`, `DriverInfo`, top-level
`Makefile.preamble`, nested project `PB.project` files and makefile lists,
plus localization/help resources under its `English.lproj/` as required.
Use preambles for overrides where Project Builder supplies generated lists;
keep PB.project and effective build inputs consistent.
Final status changes are limited to `docs/drivers/scsi-reconstruction.md`
and `src/drivers-i386/README`.

The test script exposes `--audit inventory|layouts|firmware|coverage|final`,
`--analysis PATH`, and `--repo-root PATH` for direct audits, and contains pytest
tests for source/binary contracts and reference-case results. Audits exit 0
only when all required assertions pass; exit 1 includes failing assertions.
Test expected values come from frozen reference evidence, never rebuilt output.
Guest harness output goes to `$adaptecOut/checks/results.json`; pytest reads
that explicit file. Missing/stale results fail, rather than skip, required cases.

Every code task refreshes source-map lines, adds its evidence to the ledger,
runs its targeted tests, and commits only its files after verification. While
the rewrite is incomplete, compilation of independent C units/harnesses is
the task check; the complete driver-link gate belongs to Task 8.

## C ownership partition

The following 125 names were enumerated in IDA during planning. They are C
identifiers without Mach-O's leading underscore. Each has exactly one owner.
This split is organizational, not a claim about Apple's original source files.
Task 1 verifies signatures from callers/disassembly and records them in
`interfaces.md`; dependent tasks consume those exact declarations. IDA has
no stored type for several entry points, so the plan deliberately does not
invent parameter or return types from symbol names.

**Adaptec2940Thread.m: five callbacks/OSM functions**

```text
PH_ReadConfigOSM PH_WriteConfigOSM PH_GetNumOfBusesOSM
PH_ScbCompleted a2940Timeout
```

**Adaptec2940HIM.c: 71 core functions**

```text
PH_EnableInt PH_DisableInt Ph_NonInit PH_Special Ph_Abort Ph_IntSrst
Ph_ResetChannel Ph_CheckSyncNego Ph_CheckLength Ph_CdbAbort Ph_ResetSCSI
Ph_BadSeq Ph_CheckCondition Ph_TargetAbort Ph_SendTrmMsg Ph_TrmCmplt
Ph_BusReset Ph_SendMsgo Ph_SetNeedNego Ph_Negotiate Ph_SyncSet Ph_SyncNego
Ph_ExtMsgi Ph_ExtMsgo Ph_HandleMsgi Ph_IntSelto Ph_IntFree Ph_ParityError
Ph_Wt4Req Ph_MemorySet Ph_Pause Ph_UnPause Ph_WriteHcntrl Ph_ReadIntstat
Ph_Delay Ph_ScbRenego Ph_ClearFast20Reg Ph_LogFast20Map PH_ScbSend
PH_IntHandler PH_PollInt PH_RelocatePointers Ph_ChainAppendEnd
Ph_ChainInsertFront Ph_ChainRemove Ph_ChainPrevious Ph_ScbPrepare
Ph_SendCommand Ph_TerminateCommand Ph_PostCommand Ph_RemoveAndPostScb
Ph_PostNonActiveScb Ph_TermPostNonActiveScb Ph_AbortChannel Ph_HaHardReset
Ph_SetHaData Ph_SetScbMark Ph_HaSoftReset Ph_BusDeviceReset Ph_SoftReset
Ph_GetScbStatus Ph_SetMgrStat Ph_WriteBiosInfo Ph_ReadBiosInfo Ph_OutBuffer
Ph_InBuffer Ph_ScbAbort SWAPCurrScratchRam Ph_InsertBookmark
Ph_RemoveBookmark Ph_AsynchEvent
```

**Adaptec2940Config.c: 26 functions**

```text
Ph_GetDrvrConfig Ph_InitDrvrHA PH_GetBiosInfo PH_CalcDataSize
Ph_CheckBiosPresence PH_GetNumOfBuses PH_FindMechanism PH_FindHA
PH_GetConfig PH_InitHA Ph_ReadConfig Ph_WriteConfig Ph_AccessConfig
Ph_AutoTermCable Ph_NoAssistTerm Ph_RebuildEEControl Ph_ReadEeprom
Ph_UpdateEeprom Ph_ReadE2Register Ph_WriteE2Register Ph_EnableEraseWriteEE
Ph_DisableEraseWriteEE Ph_SendStartBitEE Ph_SendAddressEE Ph_Wait2usec
Ph_ReadCableStatus
```

**Adaptec2940Optima.c: 22 functions**

```text
Ph_GetOptimaConfig Ph_CalcOptimaSize Ph_OptimaEnque Ph_OptimaEnqueHead
Ph_OptimaQHead Ph_OptimaCmdComplete Ph_OptimaRequestSense
Ph_OptimaClearDevQue Ph_OptimaIndexClearBusy Ph_OptimaClearTargetBusy
Ph_OptimaClearChannelBusy Ph_SetOptimaHaData Ph_SetOptimaScratch
Ph_ScbPageJustifyQIN Ph_OptimaMoreFreeScb Ph_OptimaGetFreeScb
Ph_OptimaReturnFreeScb Ph_OptimaClearQinFifo Ph_MovPtrToScratch
Ph_OptimaLoadFuncPtrs Ph_OptimaAbortActive Ph_OptimaEnableNextScbArray
```

**Adaptec2940Sequencer.c: one function**: `Ph_LoadSequencer`.

### Task 1: Establish complete inventory and recovered contracts

**Files:** Create `$adaptecProfile`, `$adaptecRecon/*` listed above,
`$adaptecLks/tests/test_reconstruction.py`, and `reference-cases.json`.

**Interfaces:** Consumes the pinned reference. Produces a complete IDA
`analysis-v1`, source-map partition, 170-entry `ledger-v1`, and a contract
table for all 168 handwritten functions: identifier/selector, category,
calling convention, return/argument types, owner, and evidence addresses.
Also produces class superclasses/ivars and offset/width tables for every
shared structure, data object, callback, and hardware sequence.

- [ ] Write `test_reference_identity` asserting the exact hash, size,
  architecture and text extent; `test_inventory_partition` asserts
  `(controller,bus,C,generated) == (30,13,125,2)`, unique addresses, and
  the generated names/addresses in Global Constraints. First run
  `& $adaptecPython -m pytest "$adaptecLks/tests/test_reconstruction.py" -q`;
  expect missing-analysis failure until the profile/export exists.
- [ ] Configure the reference-only profile with IDA enabled and a real batch
  executable/version. This machine has `C:/Program Files/IDA Professional 9.4/idat.exe`;
  verify its emitted version. The 9.2 directory contains only a license here.
  Leave unavailable additional analyzers disabled and record the choice.
  Run `binrecon validate --profile $adaptecProfile` through `$adaptecPython -m`;
  expect exit 0 and the pinned identity.
- [ ] Run `binrecon analyze --profile $adaptecProfile --ledger "$adaptecRecon/ledger.json" --output "$adaptecOut/baseline/run-summary.json"`.
  Set profile output_dir to the baseline directory as well. A reference-only
  comparison exit 1 is acceptable only with `complete: true` and a valid
  published IDA analysis. Locate the reference analysis from the summary,
  then set `$adaptecAnalysis` to that published path.
- [ ] In IDA, call `reference` before unfamiliar APIs. Inspect all functions,
  callers, relocations, types, category metadata and global-data references.
  Save raw pseudocode/disassembly under the ignored output directory. Recover
  contracts by checking stack arguments, return-register use, signedness,
  pointer widths and callbacks; stored/decompiled signatures alone do not pass.
  No caller/callee contract may remain unresolved before Task 2.
- [ ] Freeze reference cases with input, expected status/field changes,
  callback order, port widths/values/order and evidence addresses for every
  case named in Review Focus. Include queue insertion/removal, SCB layout,
  negotiation messages, PCI masks and firmware patch/readback cases.
  Record unresolved semantic findings as unfinished analysis, not guesses.
- [ ] Generate the map with `binrecon source-map --reference-analysis $adaptecAnalysis --binary $env:BINRECON_REFERENCE --source-dir $adaptecLks --repo-root . --objc-methods --output "$adaptecRecon/source-map.json"`.
  Validate it with `load_source_map` against the complete analysis and repo.
  Missing implementations are allowed at this baseline; all 170 entries
  must belong to one schema bucket and one ledger entry.
- [ ] Run the two inventory tests and `--audit inventory --analysis $adaptecAnalysis --repo-root .`.
  Require exact partition, full C ownership, complete contracts and valid
  artifact links. Commit `drvAdaptec2940: record reference inventory and contracts`.

### Task 2: Restore shared types and an independent test harness

**Files:** Rewrite `$adaptecLks/Adaptec2940Types.h`, `Adaptec2940Private.h`,
`Adaptec2940.h`; create `Adaptec2940HIM.h`, `SCSIBus.h`,
`tests/adaptec2940-checks.c`, and `tests/run-checks.sh`; update test cases.

**Interfaces:** Consumes Task 1's exact recovered types and signatures.
Produces compile-ready headers shared by Tasks 3-7, with matching calling
conventions, callbacks, selector declarations, and legacy C layout assertions.

- [ ] Add `test_shared_layouts`: assert every reference-shared type size,
  field offset/width, ivar offset and hardware prefix against Task 1's
  independently frozen table. Include SCB alignment, scatter/gather entries,
  command/timeout buffers, host state, sense and channel data. Run the layouts
  audit; expect the current stub's layout mismatches.
- [ ] Replace the stub types and class declarations with the recovered
  contracts. Keep Objective-C-only imports out of pure C headers unless the
  recovered API requires Objective-C compilation. Add compile-time
  `typedef char` size/offset assertions compatible with the guest compiler.
- [ ] Implement a guest test translation unit that exercises the actual
  recovered routines and returns case IDs, results, event logs and build hash.
  Substitute only external services, callbacks and hardware access for tests;
  no driver-logic reimplementation or duplicated expected-result calculation.
  Production instruction widths/order remain verified against disassembly.
  `run-checks.sh` accepts a group name: `layouts`, `firmware`, `him`, `config`,
  `optima`, `integration`, or `all`, and emits machine-readable results.
- [ ] Cross-compile the layout group for i386, execute on an i386-compatible
  guest, and run `test_shared_layouts` / `--audit layouts`. A ppc guest can
  compile i386 but cannot execute that harness; identify a compatible runner
  before claiming runtime cases pass. The repository's `vm/README.md` documents
  an i386 QEMU guest and task-specific `RHAP_TEST_IMAGE` overrides; use a
  temporary image and the existing guest-console helper if a boot is needed.
  Compiler assertions must pass on the
  actual legacy compiler in either case. Commit the verified types/harness.

### Task 3: Recover sequencer data and loader

**Files:** Create `$adaptecLks/Adaptec2940Sequencer.c`; update headers, tests,
`interfaces.md`, `ledger.json` and `divergences.md`.

**Interfaces:** Consumes Task 2's host configuration and port contracts.
Produces `P_Seq_01`, `P_SeqExist`, and `Ph_LoadSequencer` with Task 1's types
and linkage. The firmware array must remain mutable where the reference patches it.

- [ ] Add `test_sequencer_bytes` asserting independently extracted length,
  SHA-256 and descriptor/patch values. Add harness cases `sequencer-success`,
  `sequencer-absent`, and `sequencer-readback-failure`: assert reference return
  values, patch effects and exact port traces from reference-cases.json.
  Run the firmware group; expect missing production definitions.
- [ ] Recover data bounds from symbols/relocations and loader uses, then
  implement the exact bytes, descriptors and loader. Verify all branches
  against `_Ph_LoadSequencer` at `0x7ba8`; preserve writes/readback and delays.
- [ ] Run the firmware harness, pytest firmware cases, and `--audit firmware`.
  Require byte/descriptor identity and matching success/failure traces.
  Advance only this function's supported ledger status and commit.

### Task 4: Reconstruct the 71-function core HIM

**Files:** Create `$adaptecLks/Adaptec2940HIM.c`; update HIM headers, harness,
tests and reconstruction evidence.

**Interfaces:** Consumes Tasks 1-3 contracts, globals and firmware.
Produces the 71 exact identifiers in the ownership partition, including
`PH_ScbSend`, `PH_IntHandler`, `PH_Special`, queue/chain utilities, negotiation,
status and recovery callbacks. Preserve function-pointer dispatch contracts.

- [ ] Add failing harness cases `chain-empty`, `chain-front-middle-tail`,
  `short-transfer`, `selection-timeout`, `parity-error`, `sync-wide-message`,
  and `reset-abort`. Assert reference queue links, return/status values,
  register traces, residuals and callback order. Run the HIM group;
  missing required routines must fail, not use success-returning substitutes.
- [ ] Implement in dependency batches: memory/port/pause/chain helpers,
  submission/status/completion, then messages/interrupts/recovery. Review
  disassembly and callers for every body, including tiny trampolines.
  Where a callee belongs to Task 5 or 6, link only an explicitly recorded
  test service double until that production callee exists.
- [ ] Run the HIM cases after each batch and independently compare instruction
  effects to the pinned addresses. Record exact field widths, masks, call
  targets and branch outcomes for all 71 functions. Commit verified batches;
  do not promote untouched routines or claim complete driver linkage.

### Task 5: Reconstruct PCI, configuration, EEPROM and termination

**Files:** Create `$adaptecLks/Adaptec2940Config.c`; update headers, harness,
tests and evidence.

**Interfaces:** Consumes host/HIM and sequencer contracts. Produces the 26
configuration identifiers in the ownership partition, including `PH_GetConfig`,
`PH_InitHA`, PCI/BIOS discovery and EEPROM/cable access; consumes the OSM
callback signatures that Task 7 will implement.

- [ ] Add `pci-detection`, `bios-presence`, `eeprom-read-write`,
  `eeprom-failure`, `cable-termination`, and `host-init-failure` cases.
  Assert reference masks/return values, EEPROM command bit order, timing
  accesses and failure trace. Freeze all expected values before implementation.
- [ ] Implement all 26 bodies with reference-sized fields and I/O operations.
  Trace `PH_InitHA` into the real Task 3/4 functions; retain cleanup/failure
  paths, BIOS/config mode selection and source-defined polling semantics.
- [ ] Run the configuration group and record body-level comparison evidence.
  Use mocked EEPROM access only; no physical EEPROM writes are part of the
  test. Map and review all 26 functions, then commit.

### Task 6: Reconstruct the 22-function Optima queue engine

**Files:** Create `$adaptecLks/Adaptec2940Optima.c`; update shared declarations,
harness, tests and evidence.

**Interfaces:** Consumes Task 2 host/SCB layouts and Task 4 completion and
abort contracts. Produces all 22 Optima identifiers in the partition,
including function-table installation, free-SCB management and autosense.

- [ ] Add `free-scb-exhaustion`, `qin-page-boundary`, `queue-head-insertion`,
  `autosense-completion`, and `abort-active` cases asserting reference free-list
  state, queue order, scratch/FIFO writes and callback order. Run and confirm
  failure before required routines exist.
- [ ] Implement all 22 functions. Preserve short no-op bodies where the
  reference really has them; never infer missing operations from their names.
  Check indirect-call tables and each scratch-RAM offset against relocations.
- [ ] Run Optima cases with the real core HIM routines now available. Review
  each function, update its map/ledger evidence, and commit. Remove temporary
  doubles for production routines implemented by Tasks 4-6.

### Task 7: Restore controller, IOThread, callbacks and SCSIBus

**Files:** Rewrite `$adaptecLks/Adaptec2940.m`, `Adaptec2940Thread.m` and
associated headers; create `SCSIBus.m`; retire `Adaptec2940Routines.m`;
update tests and evidence.

**Interfaces:** Consumes the real Tasks 3-6 HIM functions. Produces all 30
controller methods, all 13 SCSIBus methods, and the five C/OSM functions
assigned to Thread.m. Exact types/categories come from Task 1, including
`executeCmdBuf:`, `threadExecuteRequest:`, `threadResetBus:channel:reason:`,
`commandCompleted:`, `scbComplete:`, `initHostAdaptor`, and
`SCSIBus executeRequest:buffer:client:` / `resetSCSIBus`.

- [ ] Add failing cases `scb-page-boundary`, `channel-routing`, `request-status`,
  `completion-timeout-order`, `completion-reset-order`, and `init-unwind`.
  Assert physical-address service calls, buffer ownership, reference status,
  one prescribed completion/wakeup disposition per request, and unwind order.
- [ ] Implement controller lifetime, statistics/parameters and bus ownership;
  then IOThread SCBs, dispatch, timeout/reset and completion; then SCSIBus.
  Preserve superclass, ivar offsets, selectors and category metadata from
  Task 1. Replace the existing direct-completion and fixed queue model.
- [ ] Implement the five callbacks/OSM functions with the exact recovered
  ABI and callback ownership. Remove obsolete methods/types and all live
  consumers of Routines.m; remove its source lists in the same change.
- [ ] Run the integration group with real production HIM/Optima/config code
  and mocked external DriverKit/hardware services. All Review Focus cases
  must now exercise production routines. Refresh the source map and require
  168 handwritten definitions, no duplicate/disputed entries, and only the
  two generated source-unmapped methods. Commit the controller/bus integration.

### Task 8: Align registration/resources and produce a fresh i386 driver

**Files:** Modify driver `Default.table`, `DriverInfo`, project/preamble lists,
localization/help resources; update `verification.md` and test checks.
Reuse `vm/build-i386-scsi.sh`; change it only if this target demonstrably needs
a narrow compatibility fix.

**Interfaces:** Consumes the complete production sources. Produces a fresh
guest-built `_reloc` and matching bundle registration/resource manifest.

- [ ] Add `test_bundle_contract`: require `Class Names = SCSIBus Adaptec2940`,
  PCI mask `0x00789004&0x00ffffff`, `Server Name = Adaptec2940SCSI`, help path
  `2940.rtfd`, resource existence, all production source inputs, no retired
  Routines.m/test inputs, and the two generated method names. Expect failure
  against the current table/project settings.
- [ ] Align effective build lists and project names, retaining the repository
  driver directory name. Correct strings/help references from the shipped
  bundle; exclude inspector executable/nib and generated version timestamps.
  Set `RC_ARCHS = i386` and `INCLUDED_ARCHS = i386` plus verified guest sysroot
  header paths in the lksproj preamble. Do not assume ppc host defaults work.
- [ ] Sync only this driver to a dedicated guest checkout using the existing
  remote helper with explicit source/destination paths. Run
  `SRCROOT=<dedicated-guest-checkout> sh vm/build-i386-scsi.sh drvAdaptec2940`
  there; ensure the existing harness/helper is present. Verify the resolved
  staging/temporary paths belong to this checkout before any cleanup.
- [ ] Retrieve the fresh artifact to an ignored directory; record compiler,
  command/flags, revision, complete log, size and SHA-256. Use binrecon's
  Mach-O reader and IDA to verify i386, linkage and generated methods.
  Run all harness groups on an i386-compatible runner and `test_bundle_contract`.
  Commit only registration/resource/build corrections and verified evidence.

### Task 9: Complete paired analysis, parity review and status reporting

**Files:** Update `$adaptecProfile`, all reconstruction records, tests,
`docs/drivers/scsi-reconstruction.md` and `src/drivers-i386/README`.
Further driver edits are limited to parity findings.

**Interfaces:** Consumes the exact Task 8 artifact hash and complete
reference analysis. Produces final source/ledger coverage, paired comparison,
all reviewed divergences and accurate reconstruction/build/hardware status.

- [ ] Set `BINRECON_REBUILT` to that artifact and include it in a paired
  profile. Give every rerun a fresh ignored output_dir; keep the committed
  profile portable with environment-variable artifact paths. Validate it,
  then analyze reference/rebuilt together with ledger reconciliation.
- [ ] Inspect `complete`, diagnostics, emitted analyzer versions, artifact
  hashes and every comparison result. Use `binrecon function --profile
  <paired-profile> --list`, then `--name <reference-name>` to inspect each
  difference; use IDA disassembly/xrefs for semantic decisions. Resolve all
  functional differences, rebuild after code changes, and compare the new
  hash. Do not reuse evidence from a previous build.
- [ ] Regenerate the complete source map with the Task 1 command. Validate it
  semantically with `load_source_map` and validate the 170-entry ledger.
  Require 168 mapped handwritten entries, no duplicate/boundary disputes,
  and verified generated outputs. Require every handwritten status to be
  `control-flow-confirmed` or `assembly-matched` with concrete review evidence.
- [ ] Run `& $adaptecPython -m pytest "$adaptecLks/tests/test_reconstruction.py" -q`
  and `& $adaptecPython "$adaptecLks/tests/test_reconstruction.py" --audit final --analysis $adaptecAnalysis --repo-root .`.
  The final audit must check reference/rebuilt identities, firmware/layout
  evidence, all required case results, coverage/status totals and comparison
  disposition. Reject stale artifacts, missing cases, incomplete analysis,
  unexplained differences and unsupported parity claims.
- [ ] Record normalized comparison as passing only for exit 0. A complete
  exit-1 comparison may be recorded as reviewed compiler/layout divergence
  only with evidence for every mismatch and no behavioral difference.
  Record hardware testing as not performed unless actually exercised.
  Update the survey/README to those exact results and commit.
- [ ] Obtain whole-change review using the selected execution workflow;
  fix findings and rerun affected checks before reporting completion.
  Provide final counts, built artifact identity, comparison outcome and any
  remaining limitation. Any missing functional path or required check keeps
  reconstruction incomplete.

## Execution handoff

Recommend **native execution** for this plan: shared layouts, function-pointer
contracts, and callback state span nearly every task, so keeping one
implementer with the recovered context reduces repeated analysis. A fresh
whole-change reviewer follows the final checks. Subagent-driven execution is
also available, with task-level implementation and independent reviews.

The user must review this written plan and choose the execution method before
implementation, as required by the explicitly invoked brainstorming workflow.
