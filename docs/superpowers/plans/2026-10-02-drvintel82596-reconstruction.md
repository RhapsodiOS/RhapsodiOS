# drvIntel82596 Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct all 84 handwritten functions in Apple's i386 `Intel82596NetworkDriver_reloc`, restore its kernel-driver package, build it, and account for reference/rebuilt differences using Binrecon and IDA.

**Architecture:** Recover the five classes, `Intel82596(Private)` category, descriptors, buffer ownership and helper interfaces from binary evidence. Restore the Aggregate / Driver / Kernel Server structure, reconstruct dependent memory, chip, packet, control and adapter paths, then build and compare the actual artifact. Preserve readable C/Objective-C and explain compiler and target-ABI differences.

**Tech Stack:** Historical C/Objective-C and DriverKit, Rhapsody guest `gnumake` / `pb_makefiles` / rbuild, the existing Python 3.12 Binrecon environment, IDA Professional 9.2.

**Spec:** [2026-10-02-drvintel82596-reconstruction-design.md](../specs/2026-10-02-drvintel82596-reconstruction-design.md), approved by the user on 2026-10-02.

## Global Constraints

- Reference: `C:/Users/raynorpat/Downloads/test/Drivers/i386/Intel82596NetworkDriver.config/Intel82596NetworkDriver_reloc`, **69,108 bytes**, **i386 / little endian**.
- Reference SHA-256: `BE6AED4264AB64119188AEE6A82AAB415940010DCF5705B6C241266AF45D0A11`.
- Partition: **86 functions = 75 handwritten Objective-C methods + 9 C functions + 2 generated methods**; text is `0x0..0x4240`.
- All 84 handwritten functions finish at least `control-flow-confirmed`; no unexamined, signature-only or placeholder entries at completion.
- Class hierarchy: `Intel82596 : IOEthernet`; Cogent/Flash32/PRO10PCI inherit `Intel82596`; `Intel82596Buf : Object`.
- Reference own ivars: base **38**, buffer pool **10**, PRO10PCI **3**, Cogent/Flash32 **0**. Reconcile inherited target layout before asserting absolute offsets.
- Server/artifact: `Intel82596NetworkDriver` / `Intel82596NetworkDriver_reloc`; Loaded Server version **2**; configuration version **5.00**; load command **WIRE**, no MIG interface.
- Package: `drvintel82596`, initial `pkgver = 1`, `arch = i386`; the kernel driver, five adapter tables, strings and help are in scope. Inspector executable/nib are excluded.
- Use binary-derived widths, signedness, constants, ordering, timeouts and return conventions. Check decompiler call arguments against assembly and declarations.
- Source C names drop exactly one Mach-O underscore: `__resetFunc` becomes `_resetFunc`; preserve reference external/local linkage.
- Binaries, IDBs, analyzer exports, reports and build logs stay in ignored output directories. Record hashes, commands and evidence paths in tracked documents.
- Report machine acceptance separately from reviewed compiler/ABI divergences. Do not turn a failed comparison into PASS by changing acceptance or broad ignores.
- Hardware operation is a separate claim. Any boot experiment uses a task-specific temporary image, per `CLAUDE.md`.
- Before implementation use `superpowers:using-git-worktrees` and app worktree tools to reuse/create an appropriate isolated checkout. Do not create one during plan review.
- Preserve unrelated local/staged changes. Commits use the `drvIntel82596: ` subsystem prefix, short descriptions, and no metadata.

Execution-shell setup, from the selected checkout:

```powershell
$i96Repo = (Get-Location).Path
$i96Python = 'D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe'
$i96ReferenceDir = 'C:/Users/raynorpat/Downloads/test/Drivers/i386/Intel82596NetworkDriver.config'
$i96Reference = "$i96ReferenceDir/Intel82596NetworkDriver_reloc"
$i96Root = 'src/drivers-i386/network/drvIntel82596'
$i96Drv = "$i96Root/Intel82596NetworkDriver.drvproj"
$i96Lks = "$i96Drv/Intel82596NetworkDriver.lksproj"
$i96Recon = "$i96Root/reconstruction"
$i96Profile = 'tools/binrecon/profiles/intel82596.json'
$i96Out = 'tools/binrecon/out/intel82596'
$i96ReferenceAnalysis = "$i96Out/published/analysis-reference-ida.json"
$i96Rebuilt = 'out/i386/drvIntel82596/Intel82596NetworkDriver_reloc'
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = $i96Reference
```

Each shell must set these variables; persistent REPL state is not a dependency.
When using an isolated checkout, resolve output and profile paths there while
using the existing absolute Python runtime. Discover IDA tools by name; open
the explicit reference database, read API documentation, and specify its
instance ID on queries to avoid other sessions' databases.

## Review Focus

1. Address-zero Cogent probe: the metadata walker omits it, but the final partition must contain it. Task 1 checks omission/duplication and generated exceptions using damaged evidence copies.
2. Requested buffers at alignment/page boundaries: buffers must follow reference minimum, four-byte rounding and whole-page allocation without crossing a page. Task 2 tests exact boundary inputs.
3. Outstanding netbuf wrappers during pool shutdown: reference recycle, lock and deferred-release rules must avoid stale pool access/double frees. Task 2 tests the reference-derived shutdown trace.
4. An unrelated device sharing the IRQ: adapter pending/latch decisions must follow the reference without falsely consuming its interrupt. Tasks 4 and 5 test reference-derived register traces.
5. Timeout/reset with pending packets or debugger activity: queues, enable state and ownership must follow reference recovery ordering. Task 3 tests reference-derived state/call traces.

## File map and contracts

| Location | Deliverable |
| --- | --- |
| `tools/binrecon/profiles/intel82596.json` | Reference analysis and later rebuilt comparison profile |
| `$i96Recon/source-map.json`, `ledger.json`, `divergences.md` | Function source sites, reviewed evidence, differences and exact results |
| `$i96Recon/abi.md` | Address-keyed recovered prototypes, category ownership, field layouts, constants, tables and ownership transitions |
| `$i96Recon/verify_evidence.py` | Driver-specific coverage/completion validator using existing Binrecon APIs |
| `$i96Recon/tests/test_verify_evidence.py` | Rejection tests using copies of actual evidence |
| `$i96Recon/tests/layout.c`, `pool.m`, `packets.m`, `control.m`, `adapters.m`, `test_support.h`, `test_support.m`, `verify.sh` | Focused i386 checks of production declarations/behavior and reference-based traces |
| `$i96Lks/Intel82596.h`, `Intel82596Private.h`, `Intel82596Buf.h`, `CogentEMaster.h`, `IntelEEFlash32.h`, `IntelPRO10PCI.h` | Shared, recovered class/hardware/helper declarations |
| `$i96Lks/Intel82596.m`, `Intel82596Buf.m`, `CogentEMaster.m`, `IntelEEFlash32.m`, `IntelPRO10PCI.m` | The five existing implementation files, moved and reconstructed |
| `$i96Root/{Makefile,Makefile.preamble,PB.project,apk/pkginfo}` | Aggregate and package integration |
| `$i96Drv/{Makefile,Makefile.preamble,PB.project,DriverInfo,*.table,English.lproj/...}` | Driver bundle, configurations and reference strings/help |
| `$i96Lks/{Makefile,Makefile.preamble,PB.project,Load_Commands.sect}` | Kernel Server integration |
| `vm/build-i386-intel82596.sh` | Target-specific guest tests/build/staging; no shared helper changes without a demonstrated need |
| `src/drivers-i386/README` | Final evidence-backed status |

`$i96Root/Makefile.postamble` is retained only if still needed by the restored
Aggregate; remove obsolete references to nonexistent files. The current root
`Default.table` moves to the driver bundle. No retired duplicate implementation
remains on a live source list.

**Recovery contract:** Task 1 writes the actual prototype for every required
method and C function to `abi.md`, keyed by reference address. Record argument
and return encoding, use at call sites, category owner, and assembly evidence.
Task 2 publishes those declarations in the headers. Tasks 3–5 consume those
headers unchanged unless new assembly evidence requires a documented contract
correction propagated to every caller. The function lists below fix ownership;
they do not authorize guessing unknown signatures from IDA's `int` pseudotypes.

Known buffer initializer contract:
`-initWithRequestedSize:(unsigned int)requested actualSize:(unsigned int *)actual count:(unsigned int)count`,
returning an object or nil. Shared base/helper signatures, netbuf callbacks,
power-management arguments and descriptor types must be recovered before
dependent implementation; do not invent a parallel host-only API.

`verify_evidence.py` contract:
`--analysis PATH --source-map PATH --ledger PATH --repo-root PATH [--final --rebuilt PATH]`.
Initial mode checks identities, exact 86-entry partition, sizes, names,
source-map semantics and valid present source locations. Final mode also
requires 84 reviewed mapped definitions, the two permitted generated exceptions,
evidence/reasons, no duplicate/boundary disputes and the real rebuilt hash.
Return nonzero with an addressed diagnostic on failure; print actual counts
and hash on success. Evidence presence is not automatic proof of body parity.

`verify.sh` contract:
`sh verify.sh layout|pool|packets|control|adapters|all`.
Use a verified i386 guest compiler and task-private object directory; accept
`CC` and `CFLAGS`. Fail on compile/assertion errors or a non-32-bit pointer ABI.
Print individual case names/counts. Tests use production headers/functions/
methods with only external DriverKit/netbuf/allocation/timer/I/O dependencies
mocked. Native port instructions must never execute in the harness; intercept
at the existing port access boundary with a minimal test-only shim. Do not
reimplement production algorithms in test code or add a generic mock framework.
Record binary-derived expectations before writing the assertions.

Guest setup and test-toolchain discovery may happen before Task 2 tests run;
the complete production build remains Task 6. Tests exercise isolated behavior
and cannot prove physical DMA or network traffic.

## Task 1: Reference analysis, ABI contract and complete coverage validator

**Files:** Create the profile, `reconstruction/{source-map.json,ledger.json,divergences.md,abi.md,verify_evidence.py,tests/test_verify_evidence.py}`. Export raw evidence under ignored `$i96Out/evidence/`.

**Interfaces:** Consumes the reference and existing Binrecon/IDA APIs. Produces the 86-function partition, address-keyed prototypes/layout/ownership/test expectations, and validator CLI defined above.

- [ ] Check `Get-Item $i96Reference` and `Get-FileHash -Algorithm SHA256 $i96Reference` against the exact size/hash. A different identity requires an explicit discrepancy report before continuing this reference's inventory.
- [ ] Create the profile from `tools/binrecon/profiles/adaptec6x60.json`: name `drvIntel82596 reconstruction`, i386/little endian, output `../out/intel82596`, IDA enabled at the installed 9.2 path, other analyzers initially disabled, no rebuilt key, `normalized-functions`, no blanket metadata ignores. Keep the template's executable version/timeout fields.
- [ ] Run `& $i96Python -m binrecon validate --profile $i96Profile`; require exit 0 and the recorded identity.
- [ ] Run `& $i96Python -m binrecon analyze --profile $i96Profile --ledger "$i96Recon/ledger.json" --output "$i96Out/run-summary.json"`. Inspect the summary: require successful published IDA reference analysis with all 86 functions and the expected identity. A reference-only lack of comparison is recorded separately from analyzer failure.
- [ ] Open the reference in IDA and export every function's pseudocode, assembly, callers/callees, and method metadata into ignored evidence. Reconcile IDA names with category-qualified symbols. Explicitly include `0x0`; preserve both generated methods. Resolve unsupported decompilation through assembly rather than dropping functions.
- [ ] Recover complete headers/contracts from `__OBJC` metadata and instruction/call-site use. Record all 38/10/3 own fields, target `IOEthernet` inheritance, the 13 Private methods, descriptor layouts and zeroing sizes, nine C prototypes/linkage, MAC format, port/register tables, pool and packet ownership, callback lifetime, and actual return conventions.
- [ ] For each Task 2–5 test case record an independent expected layout/state/I/O trace and reference address in `abi.md` or `divergences.md`. Include page packing, pool shutdown/recycle, descriptor linking, shared IRQ, reset/timeouts and debugger restore. Resolve missing pseudocode call arguments by reading assembly and real DriverKit declarations.
- [ ] Generate the initial source map without filtering away C functions or address zero:

```powershell
& $i96Python -m binrecon source-map --reference-analysis $i96ReferenceAnalysis --binary $i96Reference --source-dir $i96Root --repo-root $i96Repo --output "$i96Recon/source-map.json" --objc-methods
```

  Record initial mapping as name-resolution evidence only; stub matches remain unexamined.
- [ ] Add `test_verify_evidence.py` initial-mode cases against copied actual documents: `test_probe_at_zero_required` deletes address 0; `test_duplicate_address_rejected` repeats an entry; `test_generated_names_at_expected_addresses` changes a generated method's address/name association. Require nonzero and a diagnostic identifying each specific defect, and initial-mode success for the intact 86-function partition. Identify build-generated exceptions by the exact two names/addresses, not by the ledger's `analyzer_agreement.generated` field, which describes tool-created entries. Final-mode tests use actual finished evidence in Task 7; do not fabricate reviewed entries to make tests pass.
- [ ] Run `& $i96Python -m pytest "$i96Recon/tests/test_verify_evidence.py" -q` and observe the missing-validator failures before implementation. Implement the validator using `binrecon.schema.load_json/load_source_map`, `binrecon.ledger` identity/validation APIs and the actual function partition; rerun and require all available cases pass.
- [ ] Record the broken baseline build lists, nonexistent superclass import, fabricated ivars/overrides and helper prototypes. Do not repair the baseline merely to generate a stub artifact.
- [ ] Commit explicit profile and reconstruction paths with `drvIntel82596: establish reference coverage and ABI evidence`.

## Task 2: Real headers, project structure and memory/buffer ownership

**Files:** Move the five `.m` files to `$i96Lks`; create the six headers, Aggregate/Driver/Kernel Server manifests and makefiles needed to compile them, `Load_Commands.sect`, and `tests/{layout.c,pool.m,test_support.h,test_support.m,verify.sh}`. Update ABI/source-map/ledger/divergences.

**Interfaces:** Consumes Task 1's recovered contracts. Produces the shared headers, reference allocation helpers, `Intel82596Buf`, and test harness; later tasks use these declarations and production methods.

**Owned functions (9):** `0x033c IOIsPhysicallyContiguous`, `0x03c8 IOMallocPage`, `0x0408 IOMallocNonCached`, `0x2b6c getNetBuffer`, `0x2c48 recycleNetbuf`, and all four `Intel82596Buf` methods at `0x2cf8`, `0x2e90`, `0x2f48`, `0x2f58`.

- [ ] Move the implementations and Default table, place the three recovered allocation helpers in `Intel82596Buf.m` so the pool harness compiles independently, update live source lists, and establish `pb_makefiles` projects using `drvIntelE100` as the build-structure reference. Set the server identity and WIRE semantics from the spec; do not copy E100 algorithms or its license attribution.
- [ ] Replace inline/duplicate interfaces with recovered headers and actual DriverKit imports. Match own-field order/widths, superclass/category identity, and external/local helper linkage. Remove only proven invented declarations/overrides; retain genuine reference no-op overrides.
- [ ] Write `layout.c` assertions for `sizeof(void *) == 4`, descriptor sizes/offsets from Task 1, buffer-owner/guard/netbuf/link/end-guard positions at `0/4/8/12/16`, and any target superclass adjustments. Fail explicitly if inherited layout differs from the recorded target contract.
- [ ] Write `pool.m` tests calling the production allocator/pool methods with mock external services. Pin these reference-derived values: requested sizes 0, 1514 and 1516 produce user capacity 1516 and stride 1540; 1517 produces capacity 1520 and stride 1544; with a mocked 4096-byte page and aligned two-page allocation, count 3 creates four buffers (two per page), and no buffer crosses a page; size 4072 produces stride 4096, while 4073 exceeds a page and takes the reference panic path. Check allocation-failure return and reported actual size as recovered in Task 1.
- [ ] Add `test_pool_shutdown_with_outstanding_wrapper`: reproduce Task 1's pool-free then recycle trace, asserting the exact reference lock/free order and counts. Test guard corruption and duplicate initialization against their reference behavior, without adding speculative recovery logic.
- [ ] Run `sh "$i96Recon/tests/verify.sh" layout` and `... pool` in the private guest checkout; observe ABI/behavior failures before implementing the nine functions. Recover their bodies, spinlock/page/noncached logic and callback lifetime, then rerun and require all cases pass.
- [ ] Review all nine functions against IDA, record evidence and actual reviewer, advance only justified ledger states, refresh the source map, and run the initial coverage validator. Commit `drvIntel82596: recover layouts and buffer allocation`.

## Task 3: Complete shared chip and network engine

This task owns the complete `Intel82596.m` implementation: 45 handwritten
methods and `_resetFunc`, reconstructed in the three dependent groups below.
Keep one commit/review boundary after all three groups compile and their
focused checks pass. Remove the obsolete base implementation as recovery
proceeds; use an ignored baseline snapshot as evidence, without introducing
placeholder production bodies to make intermediate tests link.

### Group A: Shared chip initialization and lifecycle

**Files:** `$i96Lks/Intel82596.m`, recovered headers only for demonstrated contract corrections, `tests/layout.c`, ABI/source-map/ledger/divergences.

**Interfaces:** Consumes Task 2's descriptors/allocation/pool declarations and Task 1's method signatures. Produces chip setup, descriptor initialization and inherited DriverKit lifecycle integration used by packet/control/adapter paths.

**Owned methods (15):** `_recAllocateNetbuf` `0x0458`, `_init596` `0x059c`, `_initRfdList` `0x0714`, `_initTcbList` `0x09b4`, `_memAlloc:` `0x0bb0`, `_resetAndSelfTest` `0x0be8`, `free` `0x1428`, `resetAndEnable:` `0x154c`, `clearIrqLatch` `0x15fc`, `hwInit` `0x1604`, `swInit` `0x16a0`, `coldInit` `0x1714`, `setIOBase:` `0x2ad8`, `sendChannelAttention` `0x2af0`, `sendPortCommand:with:` `0x2af8`. Private ownership follows the reference category.

- [ ] Extend independent checks to the initial SCP/ISCP/SCB bytes and descriptor links from Task 1: SCP 12 bytes, ISCP 8, SCB 40, SCP configuration word `0x54`, ISCP busy byte 1, SCP alignment 16. Verify each physical-address call's actual arguments with mocks, not decompiler pseudotypes.
- [ ] Pin the recovered shared-memory allocation sequence: reservations 28/8/40/24/864/108/1024/1514 bytes, aligned SCP/self-test pointers, zeroing ranges and failure returns. Check the binary-derived exhaustion/failure path without assuming allocator behavior not observed in the reference.
- [ ] Run the relevant layout/pool cases to observe failures; implement the 15 bodies in reference order, including the actual self-test and initialization polling bounds and genuine no-op base hardware methods.
- [ ] Remove the invented base initialization and generic running/timeout/interrupt overrides once superclass evidence confirms inheritance. Check target inherited selectors and super dispatch; do not reimplement DriverKit state locally.
- [ ] Review all 15 bodies and descriptor uses against assembly and update evidence/maps. Record focused-case results and any dependencies on unrecovered Groups B–C; close those failures before this task's final commit.

### Group B: Packet queues, command/receive units and core interrupts

**Files:** `$i96Lks/Intel82596.m`, `tests/packets.m`, ABI/source-map/ledger/divergences.

**Interfaces:** Consumes recovered queue/descriptors, allocation and lifecycle. Produces the packet ownership, unit start/wait and base interrupt operations consumed by reset/debugger/adapter paths.

**Owned methods (13):** `_abortReceiveUnit` `0x04dc`, `_startCommandUnit` `0x0e54`, `_startReceiveUnit` `0x0f40`, `_transmitPacket:` `0x1044`, `_waitCu:` `0x1270`, `_waitScb` `0x12f8`, `serviceTransmitQueue` `0x1350`, `acknowledgeInterrupts:` `0x139c`, `processRecInterrupt` `0x197c`, `processXmtInterrupt` `0x1d14`, `setThrottleTimers` `0x1ed8`, `interruptOccurred` `0x241c`, `transmit:` `0x2494`.

- [ ] Write production-path tests for empty/full/free/active/pending transmit lists and completed receive descriptors, using Task 1's state snapshots. Assert descriptor status/command masks, physical links, packet ownership/free counts, statistic deltas and restart conditions. Include receive-error and replacement-buffer-allocation failure traces as recovered.
- [ ] Pin command-unit and receive-unit start/wait/abort traces: exact status masks, register access widths, acknowledgement order, delay counts and failure results. Mocks record state transitions at the actual external boundaries.
- [ ] Run `sh "$i96Recon/tests/verify.sh" packets` before implementation and record the relevant failures. Implement these 13 functions using production descriptors and target netbuf APIs; preserve filtering/error handling and queue ownership from the reference.
- [ ] Review all paths against assembly, including status-bit combinations, `_nb_shrink_bot` use and throttle behavior; update evidence. Record packet-check results and any dependence on Group C without claiming this task complete yet.

### Group C: Configuration, modes, reset scheduling, power and debugger

**Files:** `$i96Lks/Intel82596.m`, `tests/control.m`, ABI/source-map/ledger/divergences.

**Interfaces:** Consumes Task 2 and Groups A–B's ownership/unit operations and recovered callback contracts. Produces all remaining base-class behavior required by adapters and DriverKit.

**Owned functions (18):** `_resetFunc` `0x04a0`, `_scheduleReset` `0x0df0`, `config` `0x1fb0`, `iaSetup` `0x2128`, `mcSetup` `0x224c`, `timeoutOccurred` `0x2514`, `enablePromiscuousMode` `0x2544`, `disablePromiscuousMode` `0x2570`, `enableMulticastMode` `0x2598`, `disableMulticastMode` `0x25b0`, `addMulticastAddress:` `0x25fc`, `removeMulticastAddress:` `0x2640`, `receivePacket:length:timeout:` `0x267c`, `sendPacket:length:` `0x28cc`, `getPowerState:` `0x2b00`, `setPowerState:` `0x2b0c`, `getPowerManagement:` `0x2b54`, `setPowerManagement:` `0x2b60`.

- [ ] Write mode/configuration tests with Task 1's command bytes, station MAC layout, multicast flags/address lists and return conventions. Check empty/multiple multicast lists, duplicate address and enable/disable transitions according to observed reference behavior.
- [ ] Add `test_reset_with_pending_packets` and `test_timeout_while_debugger_active` against production methods, pinning reference call/state/ownership traces. Verify scheduled callback target/argument signature and reset failure logging; do not invent callback prototype or extra timers.
- [ ] Add debugger tests for reserved TCB/buffer use, physical pointers, lock balance, polling/timeout and descriptor/state restoration. Include the reference send/receive length boundaries and observed timeout result.
- [ ] Add power-method cases with actual signatures/results from `abi.md`, including every no-op or unsupported operation shown by the reference.
- [ ] Run `sh "$i96Recon/tests/verify.sh" control` and observe failures. Implement these 18 functions, preserving flags, command layouts, signed arithmetic and super calls. Once the complete base class links, run layout, pool, packets and control groups; require all cases PASS. Review every body and update evidence. Missing group implementations or unresolved inherited/callback calls must be fixed before the task ends.
- [ ] Commit all three groups together as `drvIntel82596: reconstruct shared chip and network engine`.

## Task 4: Cogent EISA and Flash32 adapters

**Files:** `$i96Lks/{CogentEMaster.m,IntelEEFlash32.m}`, matching headers only for evidence-backed corrections, `tests/adapters.m`, ABI/source-map/ledger/divergences.

**Interfaces:** Consumes shared base/IOEthernet initialization, descriptors and control operations. Produces two complete EISA adapters and their local helpers; neither adapter declares own instance fields.

**Owned functions (16):** All five Cogent methods at `0x0000`, `0x0094`, `0x02cc`, `0x02f0`, `0x030c`; Flash32 local helpers `card_irq` `0x2f68`, `get_connector_type` `0x2fb8`, `set_connector_type` `0x2fcc`; all eight Flash32 methods at `0x3004`, `0x309c`, `0x3340`, `0x3390`, `0x344c`, `0x3680`, `0x3728`, `0x3744`.

- [ ] Write adapter tests for the reference Cogent board/IRQ tables and resource/probe decisions, initialization ordering, port command/latch/channel-attention sequences. Include all IDs covered by Default/EM932/EM945 tables and the reference's rejection cases.
- [ ] Add Flash32 checksum and connector tests with binary-derived byte ranges, constants, masks, retry limits and port sequences. Include auto-detection failure and unknown IRQ/connector values following the reference's actual behavior.
- [ ] Add `test_flash32_shared_irq_not_pending`: inject Task 1's not-pending register state and assert the reference's calls/acknowledgements. Contrast with its pending-state trace in the test assertions, preserving access widths/order.
- [ ] Run `sh "$i96Recon/tests/verify.sh" adapters` before reconstruction; implement these 16 functions. Use the correct `checksum_OK:` selector, real super calls, and reference field reuse rather than invented adapter storage.
- [ ] Rerun cases; review each adapter/helper function, table and static initial value against IDA. Refresh the map with the address-zero Cogent probe intact and commit `drvIntel82596: reconstruct Cogent and Flash32 adapters`.

## Task 5: PRO/10 PCI bridge, connectors and interrupt gating

**Files:** `$i96Lks/IntelPRO10PCI.m`, matching header only for recovered contract corrections, `tests/adapters.m`, ABI/source-map/ledger/divergences.

**Interfaces:** Consumes the completed base, DriverKit PCI interfaces and Task 1's recovered bridge/register contract. Produces the 13-method PCI adapter, adding only connector/RJ45Only/autoDetectedPort fields.

**Owned methods (13):** `probe:` `0x3774`, `_setConnectorType:` `0x3a14`, `doAutoConnectorDetect` `0x3a64`, `initFromDeviceDescription:` `0x3cb0`, `interruptOccurred` `0x3f7c`, `clearIrqLatch` `0x401c`, `initPLXchip` `0x4038`, `resetPLXchip` `0x4088`, `sendPortCommand:with:` `0x40cc`, `sendChannelAttention` `0x40fc`, `_enableAdapterInterrupts` `0x411c`, `_disableAdapterInterrupts` `0x413c`, `resetAndEnable:` `0x415c`.

- [ ] Add tests for valid/wrong PCI identity (`0x12268086` for the shipped table), every variant branch recovered by probe, MAC reads, RJ-45-only and AUTO/BNC/AUI/RJ-45 configuration. Assert actual resource/IRQ handling and config-string ownership.
- [ ] Pin the PLX reset/init and adapter enable/disable traces, including register widths, masks and delays. Add `test_pro10_shared_irq_not_pending` and reset-with-disabled-adapter cases from Task 1's disassembly traces.
- [ ] Run adapter cases to observe the missing behavior. Implement all 13 methods with reference super-call ordering and field layout; do not carry guessed subsystem/EEPROM fields forward.
- [ ] Rerun the adapters and affected controls; review all 13 bodies and bridge constants against assembly. Check every handwritten function now has a reviewed real definition, refresh evidence and commit `drvIntel82596: reconstruct PRO10 PCI adapter control`.

## Task 6: Configuration/resources, package and guest production build

**Files:** `$i96Root/{Makefile,Makefile.preamble,Makefile.postamble,PB.project,apk/pkginfo}` as needed; `$i96Drv/{Makefile,Makefile.preamble,PB.project,DriverInfo,Default.table,EM932.table,EM945.table,EEFlash32.table,IntelPRO10PCI.table,English.lproj/...}`; `$i96Lks/{Makefile,Makefile.preamble,PB.project,Load_Commands.sect}`; create `vm/build-i386-intel82596.sh`. Update divergences for actual build evidence.

**Interfaces:** Consumes all reconstructed production source and the five adapter configurations. Produces an i386 `.config` package, staged `_reloc` and reproducible build evidence for Task 7.

- [ ] Copy supplied tables, localizable strings and corresponding help resources into the driver project; exclude the original inspector and nib. Correct Default title to `CogentEM935XL`, preserve EISA/PCI IDs, class/server names, configuration version `5.00`, PCI `Connector = AUTO` and shared IRQ. Register every resource, following the existing DriverHelp-to-Help convention.
- [ ] Check source/header lists match between Makefiles and `PB.project`; set DriverInfo version consistently; ensure Kernel Server load metadata has name `Intel82596NetworkDriver`, instance symbol, server version `2` and WIRE behavior. Check emitted fields rather than assuming a build variable produces the right section.
- [ ] Add `apk/pkginfo` with `pkgname = drvintel82596`, `pkgver = 1`, `arch = i386`, appropriate driver description, and `build-base, drivertools, driverkit, kernload` dependencies. Follow existing repository maintainer/license policy and preserve applicable notices; record reconstructed-source provenance.
- [ ] Implement the target-specific guest build script with a private build/output root (for example `/build/out/drvIntel82596-rbuild`), the isolated driver's source path, all focused tests, and `rbuild buildpackage --arch i386 --dir --target all`. Use a separate destination/object area and document any state/repository writes rbuild requires. Do not disturb ongoing guest builds. Print actual test/build exit codes and produced paths, propagate failures, and stage the actual reloc as `/build/out/drvIntel82596-rbuild/Intel82596NetworkDriver_reloc` plus package `/build/out/drvIntel82596-rbuild/drvintel82596.apk` for stable fetch paths.
- [ ] Set up the isolated checkout's local guest configuration by using existing configuration without printing credentials. Read the sync/remote helpers' path behavior and sync only the driver:

```powershell
powershell.exe -NoProfile -File vm/sync-src.ps1 -Path drivers-i386/network/drvIntel82596
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/build-i386-intel82596.sh
```

  Require focused tests PASS, compiler/linker exit 0 and actual i386 output. If a PPC host is used, pass/verify the i386 toolchain explicitly. Correct compile/link/prototype errors using binary/target ABI evidence and rerun only affected checks.
- [ ] Fetch into the selected checkout's ignored staging area after creating its directory:

```powershell
New-Item -ItemType Directory -Force -Path 'out/i386/drvIntel82596' | Out-Null
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Fetch /build/out/drvIntel82596-rbuild/Intel82596NetworkDriver_reloc -To $i96Rebuilt
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Fetch /build/out/drvIntel82596-rbuild/drvintel82596.apk -To out/i386/drvIntel82596/drvintel82596.apk
```

- [ ] Inspect architecture, own ivars, imports, class refs, generated methods and Loaded Server sections with Binrecon/IDA. Compare staged table/resource bytes, recording only generated version metadata differences. Confirm the package includes the rebuilt kernel artifact and no inspector dependency.
- [ ] Record guest compiler/linker versions, invocation, exit status, warnings, hashes and package manifest in ignored evidence and tracked divergences. Commit `drvIntel82596: restore driver packaging and i386 build`.

## Task 7: Rebuilt parity, final evidence and accurate status

**Files:** `$i96Profile`, source-map/ledger/divergences, verifier/test files for newly exposed checks, production files only for demonstrated mismatches, `src/drivers-i386/README`. Reports remain ignored.

**Interfaces:** Consumes Task 6's actual reloc/package and all reviewed evidence. Produces verified final coverage, honest comparison results and completed status only when every spec gate passes.

- [ ] Add the profile's rebuilt artifact path `${BINRECON_REBUILT}`, export the actual `$i96Rebuilt`, and run validation plus analysis:

```powershell
$env:BINRECON_REBUILT = (Resolve-Path -LiteralPath $i96Rebuilt).Path
& $i96Python -m binrecon validate --profile $i96Profile
& $i96Python -m binrecon analyze --profile $i96Profile --ledger "$i96Recon/ledger.json" --output "$i96Out/run-summary.json"
```

  Require correctly hashed reference/rebuilt IDA reports and a machine comparison for the actual artifact. Record exact `complete` / `acceptance.passed` rather than assuming exit 0.
- [ ] Inspect the whole function worklist with `& $i96Python -m binrecon function --profile $i96Profile --analyzer ida --list`. For each failed/unaligned function use `--name` with its actual published name and IDA disassembly/xrefs to distinguish behavior, inherited-layout, compiler and generated-code differences.
- [ ] Correct behavioral mismatches and rerun affected tests/build/comparison for the resulting hash. Each of the 84 handwritten functions needs its own recorded conclusion; unresolved pairing/normalization is a reported limitation, not evidence of parity. If shared Binrecon code needs a blocker fix, add a focused reproduction and run `& $i96Python -m pytest tools/binrecon/tests -q` after it.
- [ ] Bind the rebuilt identity through the ledger APIs, record actual reviewer/reasons/evidence, and mark only the two generated exceptions as such. Check their presence, returned behavior and server identity in the rebuild. Ensure analysis refreshes have not erased reviewed reasoning or substituted stale artifact evidence.
- [ ] Regenerate the source map against `$i96Lks` without `--scope-to-objc`; validate exactly 84 mapped handwritten definitions and two explained generated unmapped entries, with no duplicates or boundary disputes. Run:

```powershell
& $i96Python -m binrecon source-map --reference-analysis $i96ReferenceAnalysis --binary $i96Reference --source-dir $i96Lks --repo-root $i96Repo --output "$i96Recon/source-map.json" --objc-methods
& $i96Python "$i96Recon/verify_evidence.py" --analysis $i96ReferenceAnalysis --source-map "$i96Recon/source-map.json" --ledger "$i96Recon/ledger.json" --repo-root $i96Repo --final --rebuilt $i96Rebuilt
& $i96Python -m pytest "$i96Recon/tests/test_verify_evidence.py" -q
```

  Add `test_actual_final_evidence_passes` using the real finished documents, `test_signature_only_is_incomplete` changing one handwritten reviewed entry to signature-only, and `test_wrong_rebuilt_hash_rejected` supplying a changed artifact. Require a diagnostic identifying the actual corruption, verify earlier damaged-copy cases still fail, and require final validator exit 0 with `86 total / 84 reviewed mapped / 2 generated` and matching actual artifact hash.
- [ ] Review the complete spec gate table: ABI checks, focused tests, all methods/helpers/tables, no fabricated overrides or missing imports, correct package/configuration/resources and actual guest build/comparison. Check source for remaining stub logs/nonexistent header names, then manually distinguish valid reference no-ops from reconstruction omissions.
- [ ] Update `src/drivers-i386/README` with exact evidence counts, rebuilt size, guest build/package result, machine acceptance result, explained compiler/ABI differences and hardware-validation status. Keep detailed function findings in `divergences.md`; do not claim hardware validation from mocks or unrelated QEMU NICs.
- [ ] Run `git diff --check`, inspect the final diff for unrelated changes, and commit `drvIntel82596: verify reconstruction and report parity`. Proceed through the selected execution workflow's final review before claiming all work complete.

## Plan review and execution

This plan implements one driver with tightly shared ABI and ownership rules.
Native execution is recommended to keep that evidence consistent across the
seven tasks, with an independent final review under the execution workflow.
Subagent-driven execution is also available, with a fresh implementer and
reviewer at each task boundary and a final whole-change review.

The user must review this plan and select the execution method before
implementation, as required by the invoked brainstorming and writing-plans
skills. No implementation, worktree creation or guest mutation has occurred
during planning.
