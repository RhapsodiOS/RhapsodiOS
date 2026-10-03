# drvATIMach64 Decompilation and Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development if the user chooses that method. Implement task by task; steps use checkbox syntax for tracking. Read the spec and this plan together.

**Goal:** Reconstruct all 52 handwritten routines in the shipped i386 ATI Mach64 kernel driver, verify its two generated methods, build its package, and account for every reference/rebuilt difference with IDA and BinRecon.

**Architecture:** Recover `ATI : IOFrameBufferDisplay`, its Private and ProgramDAC categories, and `ATI_BIOS : Object` with its private category. Keep BIOS descriptor/services and display behavior in readable C/Objective-C, use assembly for the two far-transfer routines, and bind all source and parity evidence to the actual reference and rebuilt artifacts.

**Tech Stack:** Historical C/Objective-C, i386 assembly, Rhapsody DriverKit and `pb_makefiles` / rbuild, existing BinRecon Python environment, IDA Professional 9.4, focused C/Objective-C mock harnesses and Python evidence checks.

**Spec:** [drvATIMach64 reconstruction design](../specs/2026-10-02-drvatimach64-reconstruction-design.md).

## Global Constraints

- Reference SHA-256: `AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C`; size: 62,632 bytes; architecture: `i386`; endianness: `little`.
- Completion inventory: 54 entries, comprising 52 handwritten routines and two build-generated methods. Initial stock IDA coverage is 52, not the full denominator.
- Reference behavior, access widths, ordering, ABI and relocations govern implementation. Pseudocode types and guessed skeleton behavior require independent confirmation.
- Preserve reference class/category/selector names and direct Objective-C class references. Do not replace them with `objc_getClass` lookup.
- Production record contracts: `IODisplayInfo` 136 bytes, 54 mode records, 15 CRTC records of 30 bytes, BIOS register block 48 bytes, private BIOS storage 36 bytes, BIOS stack 2,048 bytes.
- IDA profile: installed `C:/Program Files/IDA Professional 9.4/idat.exe`, version `9.4`, timeout 900 seconds, acceptance `normalized-functions`, output `../out/atimach64`.
- IDA is the selected analyzer. Ghidra/angr are initially disabled by scope; neither has been demonstrated to fail on this binary.
- Runtime privileged assembly is not executed in ordinary userspace tests. Mocked behavior, i386 ABI checks and compatible-device validation are distinct evidence.
- Build metadata: server `ATIMach64DisplayDriver`, instance `ATIMach64DisplayDriver_instance`, server version `2`, load command `WIRE`; preserve build-generated Server Name handling.
- Binaries, IDBs, analyzer exports and logs stay in ignored output directories; tracked evidence records identities and reproducible commands.
- Use private guest source/object/state/output areas; any boot experiment uses a temporary disk image. Read helper path behavior before syncing.
- Preserve unrelated workspace changes. Modify shared tooling/DriverKit/kernel only for an evidenced blocker and a narrowly tested correction.
- Commit messages begin `drvATIMach64: `, remain short, and contain no metadata trailers.

## Review Focus

- The initializer at address zero and assembly routines at `0x26e0` / `0x27b8` must survive every inventory and coverage check; Task 1 tests deletion of each.
- BIOS failure must have the reference descriptor/stack/output-write behavior; Task 3 checks restoration paths and Task 4 checks service-specific status handling.
- Aperture reservation/reprogramming failure must preserve retry/rollback order and auxiliary ranges; Task 5 checks mapping transcripts for each policy.
- Query refresh and transfer replacement must preserve allocation ownership and exact release timing; Tasks 5, 6 and 7 check pointer/free transcripts.
- Non-default pixel layouts and RAMDAC overrides must retain reference channel extraction, gamma counts and mode rejection; Tasks 5 and 7 pin them to independent byte/port fixtures.

## Paths, files and execution conventions

These aliases are exact repository-relative paths. `$atiRoot`, `$atiDrv`,
`$atiLks` and `$atiRecon` in task file lists mean the following literal paths;
shell commands below use the same variable names initialized for that shell.

| Alias | Exact path |
| --- | --- |
| `$atiRoot` | `src/drivers-i386/video/drvATIMach64` |
| `$atiDrv` | `src/drivers-i386/video/drvATIMach64/ATIMach64DisplayDriver.drvproj` |
| `$atiLks` | `src/drivers-i386/video/drvATIMach64/ATIMach64DisplayDriver.drvproj/ATIMach64DisplayDriver.lksproj` |
| `$atiRecon` | `src/drivers-i386/video/drvATIMach64/reconstruction` |
| `$atiOut` | `tools/binrecon/out/atimach64` |

| Create/modify | Responsibility |
| --- | --- |
| `$atiLks/ATIMach64DisplayDriver.h`, `.m` | Replace skeleton with recovered ATI main class and eight principal methods |
| `$atiLks/ATIPrivate.h`, `.m` | ATI private category, shared private declarations and seven query/mode/mapping methods |
| `$atiLks/ProgramDAC.m` | Three DAC methods and two DAC helper routines |
| `$atiLks/ATI_BIOS.h`, `.m` | ATI_BIOS object and all 25 service/private methods |
| `$atiLks/ATIBIOSTypes.h` | BIOS/GDT/private storage types and C/assembly ABI declarations |
| `$atiLks/ATIData.h`, `.c` | All mode/timing/gamma/value/refresh data and four conversion helpers |
| `$atiLks/ATIbios16.c`, `ATIbios.s` | C BIOS-entry wrapper and two far-transfer assembly entries |
| `$atiLks/ATIMach64Regs.h` | Only evidenced register/port/delay definitions |
| `$atiRoot/Makefile.preamble`, `$atiDrv/Makefile.preamble`, `$atiLks/Makefile.preamble` | Active project sources, resources, versioning and assembly build integration |
| `$atiLks/Load_Commands.sect`, `$atiDrv/DriverInfo`, resource files | Shipped server metadata and configuration/help/mode integration |
| `$atiRoot/apk/pkginfo`, `PB.project` files when required by the existing build workflow | Driver-local packaging and Project Builder reconciliation |
| `tools/binrecon/profiles/atimach64.json` | Portable reference/rebuilt identity inputs and analyzer configuration |
| `$atiRecon/function-worklist.md`, `divergences.md` | Complete entry ownership, reviewed findings and actual parity/build results |
| `$atiRecon/ATIMach64DisplayDriver_reloc/source-map.json`, `ledger.json` | Existing BinRecon schemas; one entry per reconciled routine |
| `$atiRecon/export_ida.py` | Task-local deterministic recovery/export of the two missed assembly routines |
| `$atiRecon/verify_evidence.py` | `--phase baseline|final` inventory/schema/source/identity/generated-exception validation |
| `$atiRecon/tests/Makefile`, `mock_runtime.h`, `mock_runtime.m` | Focused production-unit harnesses, alloc/message/port/BIOS/GDT substitutes and test targets |
| `$atiRecon/tests/test_verify_evidence.py`, `test_abi.c`, `test_data.c`, `test_bios_segments.m`, `test_bios_services.m`, `test_mapping.m`, `test_lifecycle.m`, `test_dac.m`, `verify_assembly.py` | Reference-driven checks owned by the tasks below |
| `vm/build-i386-atimach64.sh` | Target-specific isolated tests/build/staging with propagated failures |
| `src/drivers-i386/README` | Final concise reconstruction/build/parity/hardware status |

Use existing helpers rather than creating a second generic reconstruction
framework. Test substitutes live only under reconstruction/tests or the test
build's include path. Do not move production behavior into test models.

For PowerShell commands initialize:

```powershell
$atiRoot = 'src/drivers-i386/video/drvATIMach64'
$atiDrv = "$atiRoot/ATIMach64DisplayDriver.drvproj"
$atiLks = "$atiDrv/ATIMach64DisplayDriver.lksproj"
$atiRecon = "$atiRoot/reconstruction"
$atiOut = 'tools/binrecon/out/atimach64'
$atiProfile = 'tools/binrecon/profiles/atimach64.json'
$atiPython = '.venv-binrecon/Scripts/python.exe'
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\ATIMach64DisplayDriver.config\ATIMach64DisplayDriver_reloc'
```

`gnumake` checks below run in the task-private build checkout, using its native
compiler for mock behavior and its verified i386 compiler for compile-only ABI
probes and production artifacts. A PPC build guest cannot run i386 test
executables; use native portable mocks and inspect the actual i386 objects.
If an i386 execution environment exists, record and use it explicitly.
Keep expected data independent of host pointer size/endianness by serializing
scalar fields and symbolic pointer targets explicitly.

## Task 1: Establish complete binary coverage and evidence integrity

**Files:** Create the profile, worklist, divergences, source-map/ledger,
`export_ida.py`, `verify_evidence.py`, and `tests/test_verify_evidence.py`.
Only adjust shared BinRecon files if a demonstrated normalization blocker
cannot be handled by the target-specific export.

**Interfaces:** Consumes the authoritative Mach-O and spec inventory. Produces
`$atiOut/reviewed/reference-ida.json` with analysis-v1 validation, a 54-address
inventory, complete initial source-map/ledger entries, and the verifier CLI.
The export script runs inside a task-owned IDA database and uses the existing
`collect_analysis(input_path, expected_size, expected_sha256, mapping=...)`
collector followed by BinRecon normalization; it never patches input bytes.

- [ ] Inspect workspace changes and attachments; establish implementation isolation following the using-git-worktrees skill. Preserve needed task inputs and point all subsequent commands at that checkout.
- [ ] Record reference identity/header/sections, all text symbols, all runtime methods/type encodings, categories, class layouts and reference resource files. Reconcile the zero-address initializer and all 54 entries against the spec; identify the two generated entries by exact names/addresses.
- [ ] Create the reference-only profile using the exact IDA configuration above and a profile-relative output path. Run `& $atiPython -m binrecon validate --profile $atiProfile`; require the intended hash/size and resolved output location.
- [ ] Run `& $atiPython -m binrecon analyze --profile $atiProfile --output "$atiOut/run-summary-reference.json"`; inspect the summary's complete flag, diagnostic, publications and actual 52-function inventory. Reference-only acceptance remains false because no rebuild exists; do not treat exit 1 alone as an analyzer failure.
- [ ] Recover the missed assembly entries in a task-owned IDB from symbols, relocations and complete bytes: `__bios16` starts at `0x26e0`, its return is at `0x2754`; `__ATIbios32` spans `0x27b8..0x2883`. Determine semantic function ends and alignment separately. Correct the data-marked far operands at `0x273d` and `0x2811`, including full selector/offset fields and control-transfer semantics, before defining/exporting functions.
- [ ] Implement `export_ida.py` to repeat those database-analysis corrections by symbol identity, export all 54 entries with real boundaries, validate input identity/mapping, retain actual analyzer version and record script/database/export hashes. Rebuilt addresses will differ: locate assembly entries by exact symbols and derive their bounds from their own instructions. Keep reviewed exports distinct from stock publication files and their summary hashes.
- [ ] Generate the initial source map with `binrecon source-map --reference-analysis "$atiOut/reviewed/reference-ida.json" --binary $env:BINRECON_REFERENCE --source-dir $atiRoot --repo-root . --objc-methods --output "$atiRecon/ATIMach64DisplayDriver_reloc/source-map.json"`. Record nominal selector collisions as unreviewed. Seed every entry unexamined through existing ledger APIs; do not copy the PowerPC-only agreement explanation from `seed_ledger.py`.
- [ ] Define verifier inputs `--phase`, `--analysis`, `--binary`, `--repo-root`, `--source-map`, `--ledger`, and final-phase `--rebuilt-analysis` / `--rebuilt`. Baseline requires the exact reconciled 54-address set, schemas and identity. Final additionally requires 52 handwritten source mappings, no duplicate/disputed/unexamined handwritten entries, valid source lines and current rebuild identity; permit only the two exact generated exceptions.
- [ ] Write `test_zero_initializer_required`, `test_both_assembly_entries_required`, `test_wrong_input_hash_rejected`, `test_duplicate_address_rejected`, `test_source_line_out_of_bounds_rejected`, and `test_generated_exception_identity_required`. Mutate copies of actual baseline evidence and require nonzero diagnostics for each specific defect. Capture failures before implementing verifier checks, then run `& $atiPython -m pytest "$atiRecon/tests/test_verify_evidence.py" -q` and require all cases pass.
- [ ] If normalization cannot represent a complete far instruction, capture the exact failure and add a minimal regression before a narrow tooling correction. Do not erase routines/operand bytes to satisfy a schema. Run the relevant BinRecon tests after any shared change.
- [ ] Commit only this task's evidence/setup files: `drvATIMach64: establish complete binary inventory`.

## Task 2: Recover ABI, declarations and all static data

**Files:** Modify the existing headers and `ATIMach64Regs.h`; create
`ATIPrivate.h`, `ATI_BIOS.h`, `ATIBIOSTypes.h`, `ATIData.h`, `ATIData.c`,
`tests/Makefile`, mock_runtime files, `test_abi.c`, and `test_data.c`.
Update active source/header lists as needed for independently compiling these
units; complete package integration remains Task 8.

**Interfaces:** Consumes Task 1's metadata, access-width/caller evidence and
exports. Produces verified ATI/ATI_BIOS declarations and category selectors;
`ATIBIOSRegisters` (48 bytes), BIOS private/descriptor declarations,
`ATIBIOSStatus` mapping 0 success / 1 not initialized / 2 BIOS error / 3 invalid;
and `ATIData.h` declarations for all reference globals and conversion helpers.
All C signatures, signedness and linkage are locked in a worklist ABI table
before dependent bodies are written. Unused register-buffer bytes remain raw
reserved fields rather than invented semantics.

- [ ] Recover all method signatures from type encodings and stack/access evidence; reconcile imported superclass and DriverKit selectors with `src/driverkit-3/driverkit/IOFrameBufferDisplay.h` and `displayDefs.h`. Record the exact declarations for the nine C/assembly routines and symbol spelling. Do not infer a meaningful return value merely from incidental EAX left by a void routine.
- [ ] Capture failing ABI checks against the current header/data: ATI class identity and own-ivar sequence, ATI_BIOS offsets 4/8/12, BIOS register-field offsets in spec section 4, descriptor size/fields, IODisplayInfo field layout and size 136. Use compile-time assertions compatible with the legacy compiler and inspect target-emitted class metadata; mocked inherited layout alone is not proof.
- [ ] Define test-only runtime substitutions for allocation/free recording, configurable superclass/message returns, fake ROM/GDT memory, BIOS-call capture and port/delay transcripts. Native test builds replace privileged paths; production builds retain actual kernel/port definitions. Add Makefile targets `check-abi`, `check-data`, `check-bios-segments`, `check-bios-services`, `check-mapping`, `check-lifecycle`, and `check-dac`.
- [ ] Recover 54 IODisplayInfo initializers, 15 CRTC records, gamma16/gamma8 and every value/refresh table from original section bytes and relocations. Test serialized scalars against the reference, compare pointer fields by symbolic table identity, and check order/count/terminators and initialized-vs-zero-fill storage. Keep immutable fixtures in ignored evidence with their input hash; use fixed independently reviewed literals for boundary tests.
- [ ] Implement the four conversion helpers in `ATIData.c`: `displayInfoToColorSpace`, `colorDepthToColorSpace`, `displayInfoToColorDepth`, and `memSizeToBytes`. Preserve invalid-input log/panic paths, enum meaning and width/signedness established above. Pin memory codes 0..4 to `0x80000`, `0x100000`, `0x200000`, `0x400000`, `0x600000` and all other encoded byte values to the evidenced `0x200000` default.
- [ ] Replace skeleton ivars with ATI's recovered sequence and declare ATI_BIOS with its recovered state. If target superclass sizes differ from reference 552/4, investigate actual target definitions, check all relative accesses, and record the specific ABI divergence rather than padding it away.
- [ ] Run `gnumake -C "$atiRecon/tests" check-abi check-data` with the defined native/mock and i386 compile-only paths. Require data fixtures and enums to agree and target layouts to pass or have explicitly evidenced target-ABI differences awaiting final artifact checks.
- [ ] Record source/evidence for these four helpers and data objects; commit `drvATIMach64: recover driver ABI and mode tables`.

## Task 3: Implement BIOS descriptor management and far-transfer execution

**Files:** Create `ATI_BIOS.m`, `ATIbios16.c`, `ATIbios.s`,
`test_bios_segments.m`, and `verify_assembly.py`; refine Task 2 ABI headers
only when new instruction evidence requires it.

**Interfaces:** Consumes `ATIBIOSRegisters` and descriptor/private layouts.
Produces seven `ATI_BIOS(Private)` methods, the `ATIbios16` wrapper and exact
assembly symbols `__bios16` / `__ATIbios32`. The private category's
`loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:` is included
here so public services in Task 4 can call the proven common path.

- [ ] Write `test_init_buffer_layout`, `test_gdt_code_and_stack_restore`, `test_optional_data_descriptor_restore`, `test_data_segment_size_boundary`, `test_bios_entry_offset_boundary`, and `test_crtc_common_argument_rules` using original instruction-derived buffer/write traces. Check descriptors are saved/restored byte-for-byte, stack allocation/free is exactly 2,048 bytes, data segment size `0x10000` is accepted and `0x10001` returns invalid, and entry offset `0xffff` passes while `0x10000` returns `-1` without entering assembly.
- [ ] Decode kernel base translation and GDT dependencies against the current i386 kernel declarations and shipped relocations. Confirm GDT symbol availability and code-page write permissions for both self-patched far operands in the kernel loader; WIRE establishes residency separately. Resolve the code/data/stack selector contracts `0x80`, `0x88`, `0x90`, `0x98` and `_kernDataSel = 0x10`. Distinguish symbol-relative addresses from actual fixed ABI constants.
- [ ] Implement `initBIOSBuf:function:`, `setupCodeSegments`, `restoreCodeSegments`, `createDataSegment:size:`, `restoreDataSegment`, and `doBios:dataSeg:` using verified C declarations. Capture size-zero underflow and createDataSegment-error cleanup behavior from the reference and assert that behavior; no speculative cleanup or synchronization change.
- [ ] Implement the common CRTC method: uninitialized returns 1; resolution `0x80` returns 3; resolution `0x81` creates the 30-byte data segment; preserve function/color/gamma/pitch register packing, transport status and AH-status handling. Confirm each early exit's descriptor state in the tests.
- [ ] Implement `ATIbios16` validation/dispatch in C and reconstruct both far-transfer routines with named assembly labels, scratch storage and relocatable self-patched operands. Preserve register/segment/flags saves, stack order, interrupt handling, far transfer and return sequence. Preserve shared scratch behavior; do not add a lock without evidence of the caller/kernel contract.
- [ ] Assemble the production i386 objects without executing them. Implement `verify_assembly.py --reference <Mach-O> --rebuilt <Mach-O-or-object>` to inspect symbol ranges, full instruction bytes, relocations, operand widths, both far-transfer operand fields and ABI save/restore ordering. Address/relocation normalization must use symbolic targets, never blanket zeroing of differing immediate bytes.
- [ ] Run `gnumake -C "$atiRecon/tests" check-bios-segments` with assembly-call mocks and run the assembly verifier on the compiled objects. Require all buffer/descriptor/wrapper cases to pass and individually explain any assembly encoding difference. Ordinary userspace tests must not call CLI/far transfers.
- [ ] Update evidence for these ten routines; commit `drvATIMach64: restore protected mode BIOS transitions`.

## Task 4: Implement all ATI BIOS public services

**Files:** Extend `ATI_BIOS.m`; create `test_bios_services.m` and its native
test fixtures/capture cases. Update BIOS data declarations only as required
by confirmed queries.

**Interfaces:** Consumes Task 3's private BIOS contract. Produces all 18
public/class methods listed in spec section 9; every method keeps its exact
selector and Task 2 declaration. Tests substitute the lowest assembly entry,
not the production service being checked.

- [ ] Create a per-service contract matrix containing function byte, input/output register fields, initialization checks, data-segment requirement/size, return conditions and output-write timing. Review each service independently; getters must not inherit setters' bounds or a universal AH-error rule.
- [ ] Write `test_rom_signature_scan_boundaries`, `test_init_and_free_ownership`, `test_query_size_and_device_query`, `test_short_query_outputs`, `test_aperture_alignment_and_encoding`, `test_crtc_vga_service_packing`, `test_dpms_bounds_and_masks`, `test_apm_bounds_and_masks`, `test_io_base_query`, `test_refresh_buffer_and_failure`, and `test_change_refresh_reference_noop`. Capture failures before implementations and assert literal independent buffer/call traces from the matrix.
- [ ] Implement `+[ATI_BIOS ATIPresent:]`, `init`, `initAtSegmentAddress:` and `free`: signature `761295520`, ROM bases `0xc0000..0xeffff` in `0x1000` increments, exact inner scan bound and output/base behavior, private allocation size 36 and original init/free ordering. Include match/no-match and first/last candidate cases.
- [ ] Implement CRTC/VGA/aperture services `loadCRTC:gamma:pitchSize:resolution:crtTable:`, `setVGAMode:gamma:`, `loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:`, and `setApertureEnable:VGAAperture:apertureAdrs:` using the proven common path and actual alignment/packing rules.
- [ ] Implement `shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:`, `querySize:size:`, and `deviceQuery:bufferSize:buffer:`. Verify success and transport/AH-failure paths, boolean masks, pointer outputs and which outputs remain untouched on each failure.
- [ ] Implement DPMS/APM getters/setters and `getIOBaseAddress:relocatable:`. Pin DPMS 0..4 accepted, 4 encoded as 0, >4 invalid; APM 0..3 accepted and >3 invalid; all uninitialized returns 1. Confirm function bytes and service-specific output/status handling from the matrix.
- [ ] Implement `getRefreshRate:` with its 20-byte data segment and implement `changeRefreshRate:` exactly as evidenced, including an apparent no-op if instruction review confirms it.
- [ ] Run `gnumake -C "$atiRecon/tests" check-bios-services`; require the matrix's success/failure/output-write cases to pass. Update evidence for all 18 methods; commit `drvATIMach64: reconstruct ATI BIOS services`.

## Task 5: Implement query ownership, mode validation and aperture mapping

**Files:** Create `ATIPrivate.m`, `test_mapping.m`; extend data/mocks only
where the actual private paths require declarations or captured interactions.

**Interfaces:** Consumes recovered ATI ivars, Task 2 mode/helper data and
Task 4 BIOS services. Produces all seven ATI(Private) methods. `getQueryData`
returns its reference success/failure code and owns `queryData/queryDataSize`;
`isModeValid:` returns the reference reason bits; mapping methods retain the
actual signed IOReturn/status declarations.

- [ ] Write `test_query_replacement_and_failure`, `test_mode_selection_and_validity`, `test_color_config_precedence`, `test_mode_derived_fields`, `test_hardware_mapping_pci_and_bios`, `test_table_mapping_count_and_rollback`, and `test_vram_probe_success_and_failure`. Use allocation, message and write transcripts to check ownership/order; preserve reference behavior for malformed/failed queries rather than inventing new recovery.
- [ ] Implement `getQueryData` and `parseModeString:` with exact allocation/copy/query-size ownership and `selectMode:count:valid:` behavior. Compare argument handling rather than assuming the supplied string is parsed locally.
- [ ] Implement `updateModeList` and `isModeValid:` over all 54 modes. Pin unsupported color `0x40`, VRAM shortage `0x02`, index >= count `0x10`, success 0, rowBytes/pixelEncoding/flags/memorySize updates and configuration precedence. Review negative index and unusual input capabilities through reference callers; do not introduce a generic index guard without evidence.
- [ ] Implement `changeHardwareMapping:` with BIOS aperture setup, PCI register `0x10` write/readback where enabled, query refresh and readback comparison. Tests inject failure independently at each call and assert original returns/output/state effects.
- [ ] Implement `changeTableMapping:` requiring exactly three memory ranges, clearing/reacquiring resources in the reference order, preserving ranges 1/2, and restoring range 0 on failed replacement. Pin the no-ranges/wrong-count IOReturn using instruction evidence; separately inject restoration failure and assert its diagnostic and retained state.
- [ ] Implement `verifyMemoryMap` with the exact 64-byte save, 16 dword writes/readbacks and success restore. Assert failure exits before restoration, as the binary does; do not make a test expect improved behavior.
- [ ] Run `gnumake -C "$atiRecon/tests" check-mapping`; require boundary/ownership/rollback cases to pass. Update evidence for all seven methods; commit `drvATIMach64: reconstruct mode and aperture management`.

## Task 6: Restore ATI initialization and display-state lifecycle

**Files:** Replace `ATIMach64DisplayDriver.m`; create `test_lifecycle.m`;
update mocks with exact superclass/device-description/config-table interfaces.

**Interfaces:** Consumes Task 5 private methods and Task 4 services. Produces
the eight ATI principal methods at `0x0..0xd84`. Calls `setGammaTable` through
the recovered category declaration; its production implementation is Task 7.
Lifecycle tests substitute that method only when testing the main flow.

- [ ] Write `test_init_bios_and_query_failures`, `test_init_configuration_and_mode_order`, `test_mapping_preferences_and_fallback`, `test_init_mapping_and_vram_failure`, `test_linear_state_transition_order`, `test_vga_transition_and_transfer_free`, and `test_free_and_accessors`. Record a reference trace for every superclass/BIOS/query/table/hardware-map failure point.
- [ ] Implement `initFromDeviceDescription:` in the actual reference order: superclass init, presence/create/query, capability logging, mode update, configuration reads/frees, mode selection, memory/aperture reconciliation, enable/map/test, initial transfer pointers/count, brightness 64 and state 0. Preserve which failure paths call super free and which call self free.
- [ ] Encode Default/BIOS/Table mapping preference and the BIOS restriction exactly. Test same-address fast path, successful preferred changes, reserved-table failure, hardware change failure and retry at `0x07800000`, including abort when the fallback itself fails. Preserve table and BIOS address ownership independently.
- [ ] Implement `free`, `enterLinearMode` and `revertToVGAMode`; verify successful linear transition enables the aperture, calls CRTC programming, zeroes all `vramBytes`, sets state 1 and loads gamma, while successful VGA reversion frees the owned transfer allocation and sets state 2. Failed mode programming must have the reference state/memory effects.
- [ ] Implement `displayModeCount`, `displayModes`, `displayMemorySize` and `setPendingDisplayMode:` using recovered fields/table globals and superclass delegation. Pin rejected upper-bound modes, private validity failures and update ordering; account for caller-supported signed inputs.
- [ ] Run `gnumake -C "$atiRecon/tests" check-lifecycle`; require original cleanup/order/state transcripts. Update evidence for all eight methods; commit `drvATIMach64: restore display initialization and mode lifecycle`.

## Task 7: Implement DAC, gamma, brightness and transfer tables

**Files:** Create `ProgramDAC.m`, `test_dac.m`; refine only evidenced port
constants/delay primitives in `ATIMach64Regs.h` and related declarations.

**Interfaces:** Consumes ATI state/query data, gamma tables and exact port
substitutes. Produces three ATI(ProgramDAC) methods, `SetGammaValue` and
`isATI68880RevC`. Tests capture production read/write/delay calls; they do not
execute real I/O on the host.

- [ ] Write `test_gamma_port_order_and_scale`, `test_default_gamma_tables`, `test_brightness_boundaries`, `test_transfer_channel_extraction`, `test_ramdac_sparse_dense_and_exceptions`, and `test_transfer_replace_and_vga_free`. Pin brightness 0/64 accepted and -1/65 rejected, RGB write order and `(brightness * component) >> 6`, DAC index/control reads/writes and intervening delays.
- [ ] Review the exact delay instructions in disassembly; identify the project's I/O delay primitive rather than copying IDA's InterlockedIncrement rendering. Reconstruct `isATI68880RevC` using control port `0x62ec`, DAC read `0x5eef` and revision value `0xd0` with original side effects.
- [ ] Implement `SetGammaValue` and `setGammaTable` with ports `0x5eec` / `0x5eed`, control masking at `0x62ec`, default gamma loops, user-table replication and exact loop counts for each supported pixel format/count. Validate 256 output entries where the reference produces them; record any non-dividing-count behavior separately.
- [ ] Implement `setBrightness:token:` preserving accepted range, nil return/no state change for invalid values, and gamma reload for valid values.
- [ ] Implement `setTransferTable:count:` with one `3 * count` allocation, three slices, reference grayscale/RGB byte extraction, shift selection by capabilities/ASIC/DAC/revision and Sparse/Dense overrides. Test replacement, unsupported format/free/fallback behavior and interaction with Task 6 VGA/free paths.
- [ ] Inspect count 0, negative count and count not dividing 256 through the DriverKit caller contract and original instructions. Document whether each is supported, rejected elsewhere or hazardous in the reference; do not run a privileged/hanging probe or invent a new accepted-domain rule.
- [ ] Run `gnumake -C "$atiRecon/tests" check-dac check-lifecycle`; require traces, counts and ownership cases to pass. Update evidence for all five routines; commit `drvATIMach64: restore DAC and transfer table behavior`.

## Task 8: Restore resources, kernel-server integration and real i386 build

**Files:** Modify driver-local Makefile.preamble/postamble files,
Load_Commands.sect, DriverInfo and affected tables/modes/localization/help;
create/update PB.project and apk/pkginfo only as the supported build requires;
create `vm/build-i386-atimach64.sh`. Record build findings in divergences.

**Interfaces:** Consumes all reconstructed production units and tests. Produces
the real i386 `_reloc` and driver package, target class/record metadata, package
manifest and an actual rebuilt identity for Task 9.

- [ ] Compare all four configuration/mode variants against the shipped bundle; restore aperture/VGA/BIOS memory ranges, I/O-port resources, ATI class registration, correct help paths and mode content. Keep build-generated Server Name behavior and repository packaging conventions. Inspect the companion executable's packaging role separately.
- [ ] Reconcile active C/Objective-C/assembly/header lists in project customizations and any PB.project files. Restore Load_Commands.sect to WIRE and verify emitted server name, instance symbol and version 2; source-file presence alone does not prove build inclusion.
- [ ] Add driver-local package metadata if required, following existing maintainer/license/provenance policy and dependency names established by neighboring successful driver builds. Do not fabricate original source-history or license attribution for reconstructed files.
- [ ] Read existing guest helper/config behavior without printing credentials. Choose task-private source, object, output and any mutable state/repository paths before transfer. Verify the compiler can emit i386 and identify where native mock tests can run; do not assume an existing PPC guest runs i386 binaries.
- [ ] Implement the build script to run focused native checks, compile-only target ABI/assembly checks, and `rbuild buildpackage --arch i386 --dir --target all` with explicit private paths and required state/repository arguments. Propagate every failure and retain logs/warnings. Stage fixed fetch paths for the actual reloc and package beneath `/build/out/drvATIMach64-rbuild/`.
- [ ] Use the inspected helpers with a task-owned guest destination. Where local configuration maps them safely, the invocations are:

```powershell
powershell.exe -NoProfile -File vm/sync-src.ps1 -Path drivers-i386/video/drvATIMach64
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/build-i386-atimach64.sh
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Fetch /build/out/drvATIMach64-rbuild/ATIMach64DisplayDriver_reloc -To out/i386/drvATIMach64/ATIMach64DisplayDriver_reloc
```

- [ ] Require actual successful build/package exit codes. Inspect the fetched artifact's i386 architecture, actual ATI/ATI_BIOS metadata, tables, imports, class references, assembly symbols and Loaded Server fields. Compare target own-ivar offsets/record sizes against Task 2 rather than relying on native mock layouts.
- [ ] Record compiler/linker versions, command, warning disposition, package manifest, artifact size/hash and private build paths. Commit `drvATIMach64: restore resources and i386 driver build`.

## Task 9: Close all routine comparisons and deliver reviewed evidence

**Files:** Add rebuilt input to the profile; finalize worklist, divergences,
source-map, ledger, evidence-verifier tests and `src/drivers-i386/README`.
Correct production files only for demonstrated parity defects, rerunning their
focused checks and rebuilding as needed.

**Interfaces:** Consumes Task 8's actual rebuilt artifact. Produces current
reference/rebuilt analyses, all 54 routine pairing/review conclusions, valid
final evidence and precise build/automated-parity/hardware-status claims.

- [ ] Set `$env:BINRECON_REBUILT` to the fetched actual reloc and add `${BINRECON_REBUILT}` to the profile. Run `binrecon validate` and `binrecon analyze` with a task-owned summary. Inspect complete/acceptance flags and actual publication hashes rather than describing stock 52-function coverage as full coverage.
- [ ] Apply Task 1's target-specific symbol-driven IDA corrections/export to the rebuild. Require 54 reference entries and their rebuilt counterparts to be represented, with full far-instruction operands. Validate both corrected documents and run `binrecon compare --profile $atiProfile --reference-analysis "$atiOut/reviewed/reference-ida.json" --rebuilt-analysis "$atiOut/reviewed/rebuilt-ida.json" --output "$atiOut/reviewed/comparison.json" --text-output "$atiOut/reviewed/comparison.txt" --require normalized-functions`.
- [ ] Review every handwritten pairing for signature, relative ivar/structure accesses, signed branches, constants/widths, calls/order, allocation/cleanup and output writes. Confirm data comparisons, globals/imports/category selectors, direct class references, generated method behavior and server fields. Address compiler transformations with individual instruction/semantic evidence; never mark every differing function as an intentional mismatch in one blanket transition.
- [ ] Resolve functional differences, rerun the owning focused check, rebuild, rehash and refresh affected analyses. If shared BinRecon code changes, add the exact regression and run `& $atiPython -m pytest tools/binrecon/tests -q`; retain failing normalization as a limitation until corrected, not as a passing comparison.
- [ ] Regenerate the final source map from the corrected reference analysis. Because the scanner ignores `.s`, assign verified assembly-label source locations for the two trampolines explicitly; validate them through `load_source_map(..., reference_analysis=..., repo_root=...)`. Require 52 mapped handwritten entries; only the two exact build-generated exceptions may remain unmapped.
- [ ] Reconcile ledger identities via its APIs, retain actual reviewer/reason/evidence for each entry and mark statuses only as supported. Check all 54 entries, no stale rebuild hash, no unexamined handwritten entries, no unresolved boundary conflicts and no source-line errors. Do not confuse analyzer-generated ledger records with the two compiler-generated methods.
- [ ] Extend verifier tests using copies of real completed evidence: `test_final_unexamined_entry_rejected`, `test_final_missing_handwritten_source_rejected`, `test_stale_rebuilt_identity_rejected`, `test_assembly_source_label_required`, and `test_only_exact_generated_exceptions_allowed`. Require the intact finished evidence to pass and each mutation to fail for its own stated defect; do not fabricate final reviewer transitions for a passing fixture.
- [ ] Run the evidence verifier in final mode and all focused checks once for the final unchanged artifact. Record actual normalized acceptance separately from reviewed behavioral conclusions. If compatible ATI hardware/ROM execution is available, use an isolated image and capture its result; otherwise explicitly record that hardware validation was not performed.
- [ ] Self-review all spec gates and the 54-entry inventory; update README with exact coverage, build result, actual automated comparison status and hardware status. Review only task changes and commit `drvATIMach64: document completed reconstruction evidence` when the required work is actually complete. Follow the chosen execution workflow's review/branch-finishing steps; do not merge or publish implicitly.

## Plan review and execution handoff

The plan covers every spec source unit, all 54 reference entries, static data,
the three observed analysis/source-mapping limitations, ABI differences,
focused behavior checks, package/build integration and final artifact-bound
evidence. Its task dependencies are 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9;
each task ends with a checkable deliverable and scoped commit.

Native execution is recommended: the BIOS register block, descriptor state,
mode data, mapping policy and evidence partition are tightly shared across
tasks. The user may instead select subagent-driven execution with fresh
implementation/review contexts. Review this plan and choose the execution
method before implementation. Writing these documents did not reconstruct
the driver, create an implementation worktree or mutate the guest.
