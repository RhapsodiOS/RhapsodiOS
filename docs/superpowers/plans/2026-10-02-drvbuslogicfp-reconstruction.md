# drvBusLogicFP Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct all 121 nongenerated functions of Apple's i386 `BusLogicFPSCSI_reloc`, build an i386 driver, and account for its behavior and rebuilt comparison with binrecon and IDA.

**Architecture:** Restore `BLFPController` with its `PrivateMethods` and `IOThread` categories, a binary-derived command/SCCB ABI, and the `SccbMgr_*` FlashPoint engine. Recover interfaces and data first, then implement the dependent controller, manager/DMA, protocol, and SCAM/EEPROM groups. Retain the existing project directories.

**Tech Stack:** Historical Objective-C/C and DriverKit, guest `gnumake` / `pb_makefiles`, Python 3.12 in the existing binrecon environment, IDA Professional 9.2, and angr 9.3.0 as a second analyzer.

**Spec:** [2026-10-02-drvbuslogicfp-reconstruction-design.md](../specs/2026-10-02-drvbuslogicfp-reconstruction-design.md), approved by the user.

## Global Constraints

- Reference size: **77,964 bytes**; architecture: **i386 / little endian**.
- Reference SHA-256: `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E`.
- Partition: **123 functions = 28 controller methods + 93 C functions + 2 generated methods**.
- Every nongenerated function must finish at least `control-flow-confirmed`; no `unexamined`, signature-only, or placeholder implementations at completion.
- Binary instruction behavior wins over Linux source, inferred pseudocode types, or a datasheet. Preserve widths, offsets, masks, tables, ordering and return conventions.
- Class: `BLFPController`; server/artifact: `BusLogicFPSCSI` / `BusLogicFPSCSI_reloc`.
- SCCB size: **260 bytes**; SG array starts at **100**, capacity **17** entries of **8 bytes**; command/controller pointers at **236/248** and free-list links at **252/256**, subject to assembly confirmation in Task 1.
- `Default.table`: `"Auto Detect IDs" = "0x8130104b";` and `"Version" = "5.00";`.
- Use historical compiler-compatible C/Objective-C and compile-time checks; a native 64-bit layout is not an i386 ABI check.
- Keep external binaries, IDBs, analyzer outputs and build logs out of Git. Do not change other drivers or unrelated dirty/staged files.
- Do not fabricate a human reviewer name or analyzer agreement. Record the actual reviewer and evidence.
- No hardware claim without actual hardware validation; a PPC artifact is not i386 compile proof.
- Before execution, use the using-git-worktrees skill and app worktree tools to reuse/create an isolated checkout. Do not create it during plan review.
- Commits name the subsystem, describe behavior, and contain no metadata. Stage explicit task paths only.

PowerShell setup for every execution shell, from the selected checkout root:

```powershell
$blfpRepo = (Get-Location).Path
$blfpPython = 'D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe'
$blfpReference = 'C:/Users/raynorpat/Downloads/test/Drivers/i386/BusLogicFPSCSI.config/BusLogicFPSCSI_reloc'
$blfpLks = 'src/drivers-i386/scsi/drvBusLogicFP/BusLogicFP.drvproj/BusLogicFP.lksproj'
$blfpDrv = 'src/drivers-i386/scsi/drvBusLogicFP/BusLogicFP.drvproj'
$blfpRecon = 'src/drivers-i386/scsi/drvBusLogicFP/reconstruction'
$blfpProfile = 'tools/binrecon/profiles/buslogicfp.json'
$blfpOut = 'tools/binrecon/out/buslogicfp'
$blfpCompareOut = 'tools/binrecon/out/buslogicfp-compare'
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = $blfpReference
```

## Review Focus

1. Unaligned/page-ending data and more than 17 SG segments must follow the reference's transfer/chunk/residual rules; test in Task 3.
2. Malformed CDB groups/control bits and unmappable sense/data buffers must produce the reference status and avoid unintended submission; test in Task 3.
3. An interrupt on a shared IRQ without the adapter's pending bit must preserve another device's work; test the mask and service path in Task 4.
4. Timeout, abort and bus reset with outstanding/disconnected commands must preserve reference completion order and ownership; test in Tasks 3–5.
5. Unexpected messages, negotiation limits and EEPROM/SCAM polling termination must follow the reference bounds; test in Tasks 5–6.

## Files and interfaces

Create:

- `tools/binrecon/profiles/buslogicfp.json`.
- `src/drivers-i386/scsi/drvBusLogicFP/reconstruction/{source-map.json,ledger.json,divergences.md,abi.md,verify_evidence.py}`.
- `src/drivers-i386/scsi/drvBusLogicFP/reconstruction/tests/{verify.sh,layout.c,queues.c,controller.m,manager.c,protocol.c,scam.c,io_mock.h,io_mock.c}` as the focused verification harness; omit no-op test files if their cases belong in another unit.
- `$blfpLks/BusLogicFPPrivate.h` and `$blfpLks/BusLogicFPThread.m`.
- `$blfpDrv/English.lproj/Localizable.strings` and reference help resources under `English.lproj/Help/`.

Modify:

- `$blfpLks/{BusLogicFPSCSI.h,BusLogicFPSCSI.m,FlashPoint.h,FlashPoint.c,Makefile,Makefile.preamble,PB.project}`.
- `$blfpDrv/{Makefile,Makefile.preamble,PB.project,Default.table}` and aggregate `src/drivers-i386/scsi/drvBusLogicFP/Makefile.preamble` only as necessary for naming/list overrides.
- `vm/build-i386-scsi.sh` only if target architecture/private build-root support is missing.
- `docs/drivers/scsi-reconstruction.md` and `src/drivers-i386/README` after final verification.

Retain `Load_Commands.sect` and its `WIRE` behavior. Do not add the inspector executable/nib. Any retired code is removed from live source lists; do not keep renamed Linux implementations as a fallback.

**Contract recovery rule:** Task 1 records actual prototypes, field layouts, calling conventions and data-table identities in `abi.md`, after checking assembly/call sites. Task 2 publishes those declarations in the headers. Later tasks consume those declarations unchanged; their function lists below are exhaustive ownership lists, not permission to invent prototypes. Decompiled `int` values that represent pointers must become correctly sized pointer types; unused return-register contents must not become invented API results.

The test harness invokes production functions/methods with mock external DriverKit/manager/port dependencies; it must not reimplement the driver algorithm. Build it as i386. For port functions compiled in `FlashPoint.c`, use a test-only guard around the six native IN/OUT definitions and link `io_mock.c`; keep the production definitions/call names intact. The harness must never execute native port instructions. Store binary-derived expected I/O/state traces with address citations in `divergences.md` before writing assertions.

`verify.sh` interface: `sh verify.sh layout|queues|controller|manager|protocol|scam|all`, nonzero on any compile/assertion failure. Accept `CC` and `CFLAGS` for the verified i386 toolchain and a private output directory; reject a non-i386 build. It prints case names and counts, not a generic success banner alone. Commands invoking this shell harness run from the private guest checkout root; Task 7 establishes that environment before earlier tasks need executable i386 tests. Read-only toolchain discovery and private test compilation may happen early; the complete build still follows Tasks 2–6.

`verify_evidence.py` interface: `--analysis PATH --source-map PATH --ledger PATH --repo-root PATH [--final] [--rebuilt PATH]`. Use existing binrecon schema/identity/ledger APIs. In initial mode validate unique partition/identities/sites; final mode also requires 121 reviewed source sites, only the two generated exceptions, per-function evidence, and the actual rebuilt hash. Exercise it on deliberately damaged copies of the real ledger to ensure missing/duplicate functions and premature evidence claims are rejected.

## Task 1: Reference partition, ABI evidence and baseline report

**Files:** Create profile, `reconstruction/{source-map.json,ledger.json,divergences.md,abi.md,verify_evidence.py}`. Raw exports go under ignored `$blfpOut/evidence/`.

**Interfaces:** Produces the 123-function partition, the recovered prototype/layout/table contract, reference-based test expectations, and validator CLI defined above. Consumes only the supplied binary and existing binrecon APIs.

- [ ] Verify length/hash with `Get-Item $blfpReference` and `Get-FileHash -Algorithm SHA256 $blfpReference`. Abort the reconstruction of this identity if either differs.
- [ ] Copy the existing `sym53c8xx.json` profile; set name to `drvBusLogicFP reconstruction`, output to `../out/buslogicfp`, IDA enabled, angr enabled with `$blfpPython` as its absolute executable, Ghidra disabled initially, and no rebuilt key. Keep `normalized-functions` acceptance and no blanket metadata ignores.
- [ ] Run `& $blfpPython -m binrecon validate --profile $blfpProfile`; require exit 0 and the recorded identity.
- [ ] Run `& $blfpPython -m binrecon analyze --profile $blfpProfile --output "$blfpOut/run-summary.json"`. A reference-only exit 1 is allowed only if the summary/published analyses prove successful reference analysis. Record any failed second analyzer honestly.
- [ ] Check the published IDA analysis for exactly 123 named, nonoverlapping reference functions. Reconcile any extra fragment or alias against IDA and the text-symbol partition; retain original exports and document every filtering decision. Do not discard a function just to reach the expected count.
- [ ] Through the IDA connector, call `reference` before `execute_python`; export names, ranges, full disassembly and pseudocode for every function plus relevant callers/data xrefs. Use assembly directly for any decompiler failure. Save database annotations without modifying the binary.
- [ ] Recover ObjC ivars/category declarations, manager/card/target layouts, command-buffer layout, SCCB prefix/tail, OS-hook signatures and every C prototype. Record all constants/tables consumed by DMA, phase, negotiation, SCAM and EEPROM paths; include original addresses, byte widths and hashes of table bytes in `abi.md`.
- [ ] Establish test expectations from the reference for the five Review Focus cases. For complex paths, record input card/SCCB/register state, ordered port accesses, resulting state/queue transitions and return/completion results. This makes later mock assertions independent of reconstructed source.
- [ ] Generate the baseline source map with the shared command below. Seed exactly 123 ledger entries using `new_ledger` and the four map buckets. Do not use the unmodified `seed_ledger.py` reason claiming PowerPC-only analysis; populate actual i386 analyzer evidence. Record the two generated methods at `0x7780` and `0x778c` as explicit build exceptions.
- [ ] Implement `verify_evidence.py`; require initial mode to accept the genuine report and reject temporary copies with one entry removed, one duplicate address, an incorrect reference hash, or a `control-flow-confirmed` driver entry without source/evidence.
- [ ] Record baseline class/API/layout/configuration/build differences in `divergences.md`. Do not repair the existing Linux stub merely to obtain a baseline artifact.
- [ ] Validate the profile/map/ledger, run `git diff --check`, and commit explicit Task 1 paths: `drvBusLogicFP: record reference partition and ABI`.

Source-map refresh command, reused after every source edit:

```powershell
& $blfpPython -m binrecon source-map --reference-analysis "$blfpOut/published/analysis-reference-ida.json" --binary $blfpReference --source-dir $blfpLks --repo-root $blfpRepo --objc-methods --output "$blfpRecon/source-map.json"
& $blfpPython "$blfpRecon/verify_evidence.py" --analysis "$blfpOut/published/analysis-reference-ida.json" --source-map "$blfpRecon/source-map.json" --ledger "$blfpRecon/ledger.json" --repo-root $blfpRepo
```

If reconciled analysis needs a derived file, use its documented path consistently in these commands. Refresh ledger paths/lines by function identity without resetting existing evidence statuses. No `--scope-to-objc`: the 93 C functions are required.

## Task 2: ABI types, OS hooks, queues and waits

**Files:** Replace `FlashPoint.h`; create `BusLogicFPPrivate.h`; begin the reconstructed `FlashPoint.c`; create `tests/{verify.sh,layout.c,queues.c,io_mock.h,io_mock.c}`.

**Interfaces:** Produces the complete declarations from `abi.md`, i386 layout assertions, the native OS-hook implementations and queue/wait utilities. Exports the reference symbols below with the recovered signatures. Tests supply native-port replacements only in harness builds.

Owned C functions (20):

```text
OS_InPortByte OS_InPortWord OS_InPortLong
OS_OutPortByte OS_OutPortWord OS_OutPortLong
OS_start_timer OS_stop_timer OS_Lock OS_UnLock
queueSearchSelect queueSelectFail queueCmdComplete queueDisconnect
queueFlushSccb queueAddSccb queueFindSccb utilUpdateResidual Wait1Second Wait
```

- [ ] Write i386 layout assertions before replacing the types: `sizeof(SCCB)==260`, callback/base/SG/command/controller/free-list offsets equal `40/44/100/236/248/252/256`, SG entry size 8 and capacity 17. Also assert every manager/card/target/command offset recovered in Task 1.
- [ ] Run `sh src/drivers-i386/scsi/drvBusLogicFP/reconstruction/tests/verify.sh layout` on the selected i386 toolchain; record the old layout's failure. A native 64-bit failure is not the required baseline.
- [ ] Define the binary-derived types and declarations in the headers; use `typedef char check[(condition)?1:-1]` or another historical compiler-compatible assertion. Remove the duplicate incompatible Linux type declarations and disabled implementation guard when replacing the C source.
- [ ] Reconstruct each owned OS hook, queue function and wait loop against its Task 1 instruction evidence. Preserve no-op hooks where proven, the exact I/O widths and queue-link ownership. Record wraparound/empty-list behavior from assembly rather than inventing checks.
- [ ] Add queue tests for empty/singleton/multiple entries, disconnect/requeue/search/flush and completion order. Add wait-loop trace assertions from Task 1, with mocked time/ports so tests terminate without physical I/O.
- [ ] Run layout and queue/wait harness cases; require exact size/offset checks and reference trace/state results. Compile production OS hooks separately and review the emitted IN/OUT widths against IDA.
- [ ] Refresh source map/ledger; review all 20 functions and attach evidence. Commit: `drvBusLogicFP: recover SCCB ABI and queue primitives`.

## Task 3: BLFPController lifecycle and request/completion protocol

**Files:** Replace `BusLogicFPSCSI.h` / `.m`; create `BusLogicFPThread.m`; extend `BusLogicFPPrivate.h`, `tests/controller.m` and evidence.

**Interfaces:** Consumes Task 2 headers/queues and the recovered `SccbMgr_*` declarations. Produces the reference 28 methods and four integration C functions. Preserve `-resetHardware`'s integer result: 0 success, 1 failure. Export `doesCrossPage` with its assembly-checked 32-bit address/length signature; do not add a zero-length policy absent from the binary.

Owned main methods (17):

```text
+probe: -initFromDeviceDescription: -maxTransfer -numberOfTargets -free
-numQueueSamples -sumQueueLengths -maxQueueLength -resetStats
-executeRequest:buffer:client: -resetSCSIBus -interruptOccurred
-interruptOccurredAt: -otherOccurred: -receiveMsg -timeoutOccurred
-commandRequestOccurred
```

Owned categories: the two `PrivateMethods` and nine `IOThread` methods in the spec. Owned C functions: `parseConfigSpace`, `blcTimeout`, `doesCrossPage`, `BLCCallback`.

- [ ] Write page-boundary tests using page size 4096: address `0x1000`, length 260 => no crossing; `0x1efc`, length 260 => no crossing; `0x1efd`, length 260 => crossing. Test the actual recovered helper, with fixture page mask `0xfff`.
- [ ] Write controller tests from Task 1 for CDB groups/invalid control bits, zero data, unmapped sense/data, one-page/direct transfers, page-ending transfers, 17 segments and requests needing more segments. Assert request status, mapped transfer/residual, SCCB fields and whether submission occurred.
- [ ] Run the tests against the current wrapper to demonstrate failure/missing methods; retain the results.
- [ ] Implement `BLFPController` with recovered ivars and exact category placement. Recover PCI/config table handling, instance limits, resource acquisition, IRQ sharing, target reservations, registration, stats and failure/free ordering. Verify misleading decompiler branches with assembly before writing cleanup.
- [ ] Implement the 48-byte command-buffer submission/wait protocol, thread request/reset paths, SCCB page pool, request conversion, callback, completion/status/residual translation and timeout/free paths. Remove the invented command-port/controller-thread API and Linux `FlashPoint_*` calls.
- [ ] Add tests for timeout/abort/reset/free while work is outstanding: compare callback order and SCCB/command ownership with Task 1. Check successful reset calls config once, stores the handle, waits 10000 ms, returns 0; failure handle `0xffffffff` returns 1 without success processing.
- [ ] Run controller tests with mocked external manager/DriverKit calls, then selector check: `& $blfpPython tools/binrecon/selector_check.py $blfpReference $blfpLks`. Require no extra/renamed/duplicate driver selectors and only the two generated missing selectors; the script's exit code alone does not enforce missing/extra counts.
- [ ] Refresh source map/evidence for these 32 driver functions and commit: `drvBusLogicFP: reconstruct controller request lifecycle`.

## Task 4: Adapter manager and DMA/sequencer

**Files:** `FlashPoint.c`, `tests/manager.c`, header definitions only if evidence requires a documented correction, source map/ledger/divergences.

**Interfaces:** Consumes ABI/queue/OS hooks from Task 2. Produces actual adapter handles and `SccbMgr_*` entry-point behavior consumed by Task 3; uses protocol declarations implemented in Task 5.

Owned C functions (22):

```text
SccbMgr_sense_adapter SccbMgr_config_adapter SccbMgr_start_sccb
SccbMgr_abort_sccb SccbMgr_my_int SccbMgr_isr SccbMgr_bad_isr
SccbMgr_scsi_reset SccbMgr_timer_expired
SccbMgrTableInitAll SccbMgrTableInitCard SccbMgrTableInitTarget
autoLoadDefaultMap autoCmdCmplt dataXferProcessor
busMstrSGDataXferStart busMstrDataXferStart busMstrTimeOut
hostDataXferAbort hostDataXferRestart XbowInit BusMasterInit
```

- [ ] Write shared-IRQ tests: with card base recovered at offset 8, `SccbMgr_my_int` reads base+55; byte values `0x00/0x20/0x80/0xa0` produce false/true/false/true. Assert read width and no unexpected writes.
- [ ] Write reference trace tests for adapter failure/success, direct/SG startup, DMA timeout/abort/restart and command completion. Use Task 1 fixtures for register values, tables, resulting counts and exact ordered accesses; do not infer expected values from new code.
- [ ] Run `sh src/drivers-i386/scsi/drvBusLogicFP/reconstruction/tests/verify.sh manager` with unimplemented functions to establish failing cases.
- [ ] Reconstruct the 12 manager functions, including card/target table initial states, handle sentinel, interrupt ownership and reset semantics.
- [ ] Reconstruct the 10 DMA functions and exact sequencer/default-map bytes; preserve register widths, residual bookkeeping and timeout/abort conditions.
- [ ] Run manager tests, compare table bytes/hashes against binary evidence and inspect every branch/store/call for all 22 functions. Refresh ledger and commit: `drvBusLogicFP: reconstruct adapter manager and DMA`.

## Task 5: SCSI phases, selection, negotiation and autosense

**Files:** `FlashPoint.c`, `tests/protocol.c`, evidence records.

**Interfaces:** Consumes card/target/SCCB/queue declarations and DMA behavior. Produces phase decoding and the protocol functions called by the manager/ISR; preserves reference completion callbacks and residual/sense fields.

Owned C functions (27):

```text
phaseDecode phaseDataOut phaseDataIn phaseCommand phaseStatus
phaseMsgOut phaseMsgIn phaseIllegal phaseChkFifo phaseBusFree
scsiFetchMsg scsiSelect scsiReselection scsiDecodeMsg scsiHandleExtMsg
scsiInitSyncNego scsiTargSyncNego scsiInitSyncRespond
scsiInitWideNego scsiTargWideNego scsiInitWideRespond scsiSetSyncValue
scsiResetBus scsiSenseSetup scsiXferPad scsiChkDmaDone scsiInitSCCB
```

- [ ] Write reference trace/state tests for each phase-dispatch entry, unexpected messages, selection/reselection, disconnect with outstanding work, short/long negotiation messages, target sync/wide limits, sense setup, DMA-done/residual and reset completions. Record expected bytes/fields before implementation, from Task 1.
- [ ] Run protocol tests and record missing/failing cases.
- [ ] Reconstruct phase handlers and FIFO/bus-free behavior, checking each port width and phase-to-state transition.
- [ ] Reconstruct message/selection/negotiation/reset/sense/DMA-completion functions. Preserve the reference's rejection/response behavior, negotiation table values, and order of status/residual/callback updates.
- [ ] Run `sh src/drivers-i386/scsi/drvBusLogicFP/reconstruction/tests/verify.sh protocol`, then rerun manager/controller cases affected by completion. Review all 27 functions, refresh map/ledger and commit: `drvBusLogicFP: reconstruct SCSI phases and negotiation`.

## Task 6: SCAM discovery and EEPROM

**Files:** `FlashPoint.c`, `tests/scam.c`, evidence records.

**Interfaces:** Consumes OS hooks, adapter/target state and recovered device/EEPROM tables. Produces reference bus arbitration/discovery/ID assignment and EEPROM serial operations used by configuration.

Owned C functions (20):

```text
ScamInit ScamArbitration ScamBusFree ScamAssignID ScamSelect
ScamXferCycle ScamSendIsolate ScamIsolate ScamWireOrData ScamWireOrSig
ScamValidQ ScamSelLegacy ScamWaitSelection initScamInfo
scamMatchId scamSaveDeviceInfo
utilEEWriteOnOff utilEEWrite utilEERead utilEESendCmdAddr
```

- [ ] Write reference trace tests for EEPROM command/address/data bit ordering and write enable/disable; SCAM no-device/legacy selection, ID match/allocation, arbitration/isolation and polling-limit termination. Use binary-derived counts, masks, bit sequences and device table results from Task 1.
- [ ] Run `sh src/drivers-i386/scsi/drvBusLogicFP/reconstruction/tests/verify.sh scam` and record failures before implementing this group.
- [ ] Implement all 16 SCAM functions and four EEPROM functions with the recovered tables, loop bounds and register ordering.
- [ ] Run scam tests and affected adapter-configuration tests. Confirm the complete C ownership lists total 93 distinct reference symbols; review all 20 functions and commit: `drvBusLogicFP: reconstruct SCAM and EEPROM`.

## Task 7: Bundle alignment and complete i386 build

**Files:** Project files/configuration/resources listed above; optional scoped build-script fix; reconstruction evidence.

**Interfaces:** Produces staged `out/i386/drvBusLogicFP/BusLogicFPSCSI_reloc` and a matching driver bundle, with actual toolchain/build identity. Consumes all reconstructed source and the reference bundle.

- [ ] Align nested `NAME`, `PROJECTNAME` and `DRIVERNAME` to `BusLogicFPSCSI`; list `BusLogicFPSCSI.m`, `BusLogicFPThread.m`, `FlashPoint.c` and headers consistently. Use preamble overrides when sufficient and fix stale aggregate file lists. Preserve project directory names and `WIRE` behavior.
- [ ] Set `Default.table` PCI ID/version to the exact Global Constraints values. Compare all other keys with the reference and account only for generated version metadata differences.
- [ ] Copy `Localizable.strings`, `Help/TableOfContents.rtf`, and every `BusLogicFP_PCI.rtfd` attachment from the supplied reference. Set resources consistently in Makefile/PB.project; check relative file inventory and byte hashes.
- [ ] Select the configured guest and identify its available i386 compiler/linker with a small object-header check. Read `vm/rhap-remote.ps1` for the existing connection API; never print credentials. Use a private task source/object/destination area and preserve unrelated builds.
- [ ] Transfer only this driver and its tests to the private build area. If `build-i386-scsi.sh` needs a private destination or architecture override, add only that support. Require an actual i386 object before the full build; an architecture variable without inspecting output is insufficient.
- [ ] Run the guest equivalent of `SRCROOT=<private source root> sh vm/build-i386-scsi.sh drvBusLogicFP` with the confirmed i386 flags. Record full log and exit status. Fix compile/link failures; record compiler version, flags and reviewed warnings.
- [ ] Run all focused tests as i386: `sh src/drivers-i386/scsi/drvBusLogicFP/reconstruction/tests/verify.sh all`. Require zero assertion/compile failures and print case counts.
- [ ] Retrieve the artifact to the required staging path. Check `read_macho(Path(...))['input']['architecture'] == 'i386'`, hash it and inspect generated Kernel Server methods/server name/imports. Preserve resource/install proof and commit explicit source/project/resource/build-script changes: `drvBusLogicFP: align bundle and verify i386 build`.

Guest access failure does not authorize a passing build claim. Continue available source/evidence work and leave this gate open until an i386 artifact exists.

## Task 8: Rebuilt comparison, final evidence and status

**Files:** Reference/rebuild profile configuration as needed, reconstruction reports/checker, status docs. Comparison outputs stay under `$blfpOut`.

**Interfaces:** Consumes the verified Task 7 artifact and the reviewed reference partition. Produces final hash-bound ledger, full comparison dispositions, accurate documentation and a reviewable source change.

- [ ] Add the profile's rebuilt artifact as `{"path":"${BINRECON_REBUILT}"}` once the artifact exists; change its `output_dir` to `../out/buslogicfp-compare`, and export the rebuilt absolute path in every subsequent shell. Set the ledger's rebuilt identity explicitly with binrecon validation; do not silently reset evidence on identity change.
- [ ] Run `& $blfpPython -m binrecon analyze --profile $blfpProfile --output "$blfpCompareOut/run-summary.json"`. The changed profile output directory keeps comparison publications separate from original reference exports. Inspect every analyzer's status and published reference/rebuilt function partition.
- [ ] Run `binrecon compare` with the profile, published reference/rebuilt IDA analyses, `--require normalized-functions`, JSON output and text output. Record matched/differing/missing counts and exit code; mismatch exit 1 is evidence to inspect, not a completion claim.
- [ ] Run supplemental checks below. Normalize only proved category/symbol aliases; never mask register offsets, widths, status values or behavior under blanket ignores.
- [ ] Review every difference against instruction-level evidence. Fix behavioral differences, rerun affected focused tests, rebuild and repeat comparison when source changes. For compiler/build-only differences, cite the reference/rebuilt ranges and explain preserved behavior. No driver omission may be labeled intentional mismatch.
- [ ] Refresh the source map and ledger one final time; run checker `--final --rebuilt <absolute rebuilt path>`. Require 123 unique entries, 121 real mapped/reviewed driver functions, exactly two generated exceptions, valid evidence/line references and matching hashes. Check negative fixtures still fail.
- [ ] Confirm the selector report has 28 driver method definitions and only generated omissions. Check no live old class/API/disabled guard remains and all 93 C definitions are accounted for. Record actual source/evidence/comparison counts separately.
- [ ] Update SCSI status docs and README with those counts, actual i386 build result and comparison disposition; state hardware validation status accurately.
- [ ] Run `git diff --check`, focused tests affected by any final change, and `& $blfpPython -m pytest tools/binrecon/tests` only if shared tooling changed. Stage explicit task paths and commit: `drvBusLogicFP: verify reconstruction against reference`.
- [ ] Complete the selected execution method's code review, resolve findings with the same evidence/build checks, and use the finishing-a-development-branch skill for integration. Do not merge/publish based solely on a source-map count.

Comparison/check commands after exporting `BINRECON_REBUILT`:

```powershell
& $blfpPython -m binrecon validate --profile $blfpProfile
& $blfpPython -m binrecon compare --profile $blfpProfile --reference-analysis "$blfpCompareOut/published/analysis-reference-ida.json" --rebuilt-analysis "$blfpCompareOut/published/analysis-rebuilt-ida.json" --output "$blfpCompareOut/comparison.json" --text-output "$blfpCompareOut/comparison.txt" --require normalized-functions
& $blfpPython tools/binrecon/parity_check.py $blfpReference $env:BINRECON_REBUILT
& $blfpPython tools/binrecon/selector_check.py $blfpReference $blfpLks
& $blfpPython tools/binrecon/import_check.py $blfpReference $env:BINRECON_REBUILT
& $blfpPython "$blfpRecon/verify_evidence.py" --analysis "$blfpOut/published/analysis-reference-ida.json" --source-map "$blfpRecon/source-map.json" --ledger "$blfpRecon/ledger.json" --repo-root $blfpRepo --final --rebuilt $env:BINRECON_REBUILT
```

`import_check.py` without a kernel checks missing reference imports only; separately resolve additional undefined imports against the matching guest kernel/DriverKit loader exports and record the provider for each. Require the parity/selector report's actual missing sets to be accounted for even where a tool's exit status is lenient.

## Plan self-review and execution handoff

Coverage check: Task 1 establishes identity, partition, types, data and evidence; Tasks 2–6 reconstruct all 121 driver functions; Task 7 covers naming/configuration/resources/layout/build; Task 8 covers hash-bound comparison and documentation. All five Review Focus items have assigned tests. Task ownership totals: C functions **20 + 4 + 22 + 27 + 20 = 93**; controller methods **28**; generated exceptions **2**.

This plan preserves the approved ABI and source organization and does not invent low-level prototypes where recovery is itself required. The Task 1 contract must be verified before implementation consumes it. Any evidence correction is recorded and propagated through headers, tests and consumers together.

Recommend native execution in this chat because all reconstruction groups share the recovered card/SCCB state and benefit from continuous IDA context. Subagent-driven execution remains an option with additional independent task reviews. Wait for the user's plan review and execution-method choice before starting implementation.
