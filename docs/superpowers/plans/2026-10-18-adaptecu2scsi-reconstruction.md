# AdaptecU2SCSI Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover the complete 5.6 PPC AdaptecU2SCSI controller, OSM, CHIM, firmware, and tables; integrate them into kernel-7; and demonstrate full function accounting, behavioral review, and PPC Make/Samurai compile/link acceptance.

**Architecture:** Freeze the reference inventory and typed contracts first. Recover the data and implement bounded dependency groups behind those contracts, then reconcile the controller/OSM lifecycle and integrate both PPC build systems. Verify the resulting kernels against the reference using binrecon, exact data checks, and bounded PPC routine execution with scripted external services.

**Tech Stack:** Python 3.12, existing binrecon schemas/readers, IDA/Hex-Rays, legacy C/Objective-C DriverKit, Apple cc-771.4 PPC backends, historical Make, Samurai, and test-only Unicorn 2.1.4.

**Spec:** [Approved reconstruction design](../specs/2026-10-18-adaptecu2scsi-reconstruction-design.md), committed as `d50ba35744c0a7ce1c406aab39eeba1b532cb5e0`.

## Global Constraints

- Reference: `C:\Users\raynorpat\Downloads\test\MOSXS12v3\mach_kernel`; 2,983,828 bytes; SHA-256 `D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD`.
- PPC, big-endian, 32-bit Mach-O; embedded release `Kernel Release 5.6`, `kernel-190.1.obj~4/RELEASE_PPC`.
- Working inventory: 84 OSM/controller/helper bodies plus 392 CHIM bodies. Changes require address-specific evidence, never silent exclusions.
- Reference code ranges are `[0x18770c,0x18b754)` and `[0x18b754,0x1a8adc)`, with exclusive ends. Initial profile scope covers their union.
- All shipped CHIM modes and recovery paths remain in scope. Hardware validation is tracked separately and is not a prerequisite for reconstruction acceptance.
- Every handwritten function must reach at least `control-flow-confirmed` in the existing ledger. Missing paths and unexplained differences fail acceptance.
- Preserve reference widths, signedness, packing, byte order, volatile accesses, barriers, DMA/cache contracts, callback order, and error paths.
- Keep the implementation in the existing driver subtree. C source names must produce the expected Mach-O names.
- Keep C functions and unnamed helpers in the source-map scope. An Objective-C-only map is insufficient.
- Use historical-compiler-compatible size/offset checks. Host layouts do not establish PPC layout.
- Build RELEASE_PPC and DEBUG_PPC with historical Make and Samurai in private source/output staging.
- Keep reference binaries, databases, bulk pseudocode, analyzer output, objects, and logs outside Git. Commit recovered firmware as C arrays.
- Apply AGENTS.md guest isolation: snapshot or throwaway image, distinct name/ports, SSH banner readiness, QMP ownership check, safe writable-guest reboot, resync after snapshot restart.
- At execution time read AGENTS.md and apply using-git-worktrees; reuse a suitable attached worktree. Do not overwrite unrelated work or use broad cleans/source syncs.
- Commits use `scsi: ` followed by a short descriptive message, explicit staged paths, and no trailers/metadata.
- Use plain code comments without leading skill tags. Each code batch contains at most eight functions or one documented inseparable dependency cycle.
- No i386 driver port, new adapter support, replacement SCSI framework, unrelated repairs, or new emulator device.

## Review Focus

1. A big-endian load/store, SCB bitfield, or SG address is reconstructed using the host's widths: require target layout and byte-exact mode fixtures; Tasks 3, 5, 7, and 14.
2. Timeout/reset and normal completion become runnable in the same request lifecycle: preserve reference ownership, timer cancellation, and wakeup order; Tasks 10, 11, and 14.
3. Queue exhaustion, queue freezing, or abort removes an entry twice or loses it: preserve free/host/device queue transitions and completion disposition; Tasks 7 and 11.
4. Firmware choice, EEPROM access, or initialization fails after partial acquisition: preserve mode/revision selection and reference unwind; Tasks 4, 6, 8, 12, and 14.
5. Old fixtures, missing indirect callbacks, or compiler differences conceal omitted behavior: fail stale/unknown evidence, audit dispatch slots, and inspect every paired mismatch; Tasks 1, 2, 3, and 16.

Only exercise interleavings and failure inputs supported by reference evidence. Record historical defects rather than redesigning their behavior.

## Files, ownership, and command conventions

All paths below are relative to the execution checkout. Set these in PowerShell:

```powershell
$au2Python = 'D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe'
$au2Driver = 'src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI'
$au2Recon = "$au2Driver/reconstruction"
$au2Tests = "$au2Driver/tests"
$au2Profile = 'tools/binrecon/profiles/adaptecu2scsi-ppc.json'
$au2Out = 'tools/binrecon/out/adaptecu2scsi-ppc'
$au2Reference = "$au2Out/reference"
$au2Analysis = "$au2Out/baseline/published/analysis-reference-ida.json"
$au2Objects = "$au2Out/objects"
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:/Users/raynorpat/Downloads/test/MOSXS12v3/mach_kernel'
```

Use the actual execution checkout for repository-relative paths. The Python
environment can be reused from the main checkout. Do not repurpose system
variables. Guest commands run from the private `src/kernel-7` copy with
toolchain prerequisites documented in `ninja/README.md`.

| Files beneath the driver directory | Responsibility |
| --- | --- |
| Existing `AdaptecU2SCSI.{m,h}`, `AdaptecU2SCSIThread.m`, `OSMFunctions.{m,h}` | Recovered controller, thread category, OSM command lifecycle |
| New `AdaptecU2SCSIPrivate.h` | Shared driver request/IOB state and private category declarations |
| New `AdaptecU2CHIMTypes.h` | Reference configuration/profile/IOB/HIOB/SCB layouts and descriptors |
| New `AdaptecU2CHIM.h`, `AdaptecU2CHIMPrivate.h` | Typed public table/API and private CHIM declarations |
| New `AdaptecU2OSMServices.m` | OSM kernel/PCI/register/memory services, allocation helpers, conversion helpers |
| New `AdaptecU2CHIMFirmware.c`, `AdaptecU2CHIMTables.c` | Sequencer arrays and symbolic descriptor/dispatch/profile/device tables |
| New CHIM C files in the ownership table below | All 392 CHIM functions |
| `reconstruction/{inventory.md,interfaces.md,source-map.json,ledger.json,divergences.md,verification.md}` | Evidence records required by the spec |
| `tests/reference-cases.json`, `tests/contracts.json` | Frozen input/output observations and recovered external-call contracts |
| `tests/reference.py`, `tests/verify.py`, `tests/ppc_cases.py`, `tests/test_reconstruction.py` | Driver-specific extraction, audits, bounded execution, and tests |
| `tests/layout-checks.m`, `tests/build-objects.sh`, `tests/build-kernels.sh`, `tests/requirements.txt` | Target layout checks, private guest builds, test-only dependency |

Production headers preserve recovered names and types. Task 3 must recover
and write the actual prototypes: the binary has not supplied all signatures
during planning, and parameter types must not be guessed from names. Later
tasks consume those declarations directly. `interfaces.md` records each
prototype's reference address, callers, field use, and ownership contracts.

### Exact initial CHIM ownership

Rules operate on the 392 reference functions in `[0x18b754,0x1a8adc)`, using
C names with one Mach-O symbol prefix removed. Range ends are exclusive.
They are organizational boundaries, not claims about Apple's source files.

| Owner C file, prefix `AdaptecU2` | Exact selection rule | Count | Task |
| --- | --- | ---: | ---: |
| `CHIMSCB.c` | `SCSIh*` in `[0x18b754,0x1922a8)` | 67 | 7 |
| `CHIMConfig.c` | `SCSIh*` in `[0x1922a8,0x193bb8)` | 20 | 8 |
| `CHIMRecovery.c` | `SCSIh*` in `[0x193bb8,0x198100)` | 28 | 10 |
| `CHIMNegotiation.c` | `SCSIh*` in `[0x198100,0x19cb3c)` | 63 | 9 |
| `CHIMHardware.c` | `SCSIh*` in `[0x19cb3c,0x1a245c)` | 61 | 6 |
| `CHIMHIM.c` | `SCSIH*` | 31 | 12 |
| `CHIMResource.c` | `SCSIr*` plus `SCSIR` immediately followed by an uppercase letter | 47 | 11 |
| `CHIMTransport.c` | `SCSIx*` | 19 | 13 |
| `CHIMOSD.c` | `OSD*` | 14 | 5 |
| `CHIMAPI.c` | Remaining `SCSI*` functions after all preceding selections | 42 | 13 |

The resource rule excludes names such as `SCSIReportAdjustableAdapterProfile`.
Task 1 expands these rules into explicit address/name/owner lists in
`inventory.md`, asserting disjoint coverage and counts. Move a function only
if recovered dependencies justify it; update its owner and all counts in the
same change. No functions disappear when a file split changes.

### Test and evidence interfaces

Keep these scripts local to this driver; reuse existing Mach-O/schema/ledger
readers rather than creating a general framework.

- `reference.py --binary PATH --output DIR`: extract identity, full scoped
  function list from saved IDA evidence, targeted class/category metadata,
  tables, and image bytes into ignored `DIR`. Require an explicit saved IDA
  analysis via `--analysis PATH` for the function partition.
- `verify.py STAGE --reference DIR --repo-root PATH [--objects DIR] [--builds PATH]`:
  stages are `inventory`, `layouts`, `firmware`, `group`, and `final`;
  `group` additionally requires `--group OWNER_BASENAME`. Exit 0 only when
  that stage's assertions pass; failures identify addresses/fields/cases.
- `ppc_cases.py reference|pair --reference DIR --cases PATH --contracts PATH
  --output PATH [--rebuilt PATH]`: run reviewed fixtures against the reference
  or both images. `pair` requires `--rebuilt` and compares observations to
  frozen expectations, not newly generated expected output.
- Python entry points: `extract_reference(binary: Path, analysis: Path,
  output: Path) -> dict`, `audit(stage: str, reference: Path, repo_root: Path,
  objects: Path | None, builds: Path | None, group: str | None) -> None`, and
  `run_case(binary: Path, case: dict, contracts: dict) -> dict`.
- `build-objects.sh OUTDIR SOURCE...`: from the private kernel tree, prepare
  PPC headers and compile explicit production sources/layout checks using
  the generated kernel compiler commands. Write hashes, commands, and source
  revision to `OUTDIR/objects.json`; never add test objects to kernel link lists.
- `build-kernels.sh SCRATCH`: build and retain Make/Samurai RELEASE/DEBUG
  products under an initially absent absolute scratch directory outside the
  source tree; emit `builds.json` with tool identities, revision, commands,
  logs, configuration, and all stripped/unstripped hashes.

Results identify reference/rebuilt hashes, case/contract hashes, source
revision, runner version, and selected case IDs. Missing, skipped, stale, or
unknown-call results cannot satisfy a required check.
Observe only contract-defined returns and memory. Normalize declared pointer
fields and trace targets to symbols or named fixture regions plus offsets;
compare ordinary scalars and SCB/firmware bytes exactly. Never normalize a
value merely because it resembles an address.

`reference.py` writes a driver-local `reference.json`: `identity` contains
the existing reader's input identity, `functions` contains the frozen IDA
partition, and `owners` maps source basenames to function addresses. It
also writes targeted ABI and data evidence beneath the same output directory.
The frozen case file contains `cases`, each with an `expected` observation
object. Every record includes the evidence identity needed by its audit.

Use these commands for extraction and a group check; substitute the owning
basename from the task for `AdaptecU2CHIMHardware.c`:

```powershell
& $au2Python "$au2Tests/reference.py" --binary $env:BINRECON_REFERENCE --analysis $au2Analysis --output $au2Reference
& $au2Python "$au2Tests/verify.py" group --reference $au2Reference --repo-root (Get-Location).Path --objects $au2Objects --group AdaptecU2CHIMHardware.c
& $au2Python "$au2Tests/ppc_cases.py" reference --reference $au2Reference --cases "$au2Tests/reference-cases.json" --contracts "$au2Tests/contracts.json" --output "$au2Out/reference-results.json"
```

For each task, add the named pytest tests, run their exact names with `-k`,
and confirm the intended missing deliverable causes failure. After recovery,
run the same selection plus the owning audit and object checks. The
following assertions define the common inventory and paired-case tests;
group-specific tests add their fixture IDs and observations to this contract:

```python
def test_inventory_reference_identity_and_partition(reference):
    assert reference['identity']['sha256'] == 'D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD'
    assert reference['identity']['architecture'] == 'ppc'
    assert reference['identity']['endianness'] == 'big'
    assert len(reference['functions']) == 476
    assert len(reference['owners']['AdaptecU2CHIMResource.c']) == 47

def assert_paired_case(case, reference_result, rebuilt_result):
    assert reference_result['observations'] == case['expected']
    assert rebuilt_result['observations'] == case['expected']
    assert rebuilt_result['executed_case_id'] == case['id']
    assert rebuilt_result['unknown_calls'] == []
```

An evidence-backed inventory correction updates these initial-count
assertions in the same reviewed change; it never weakens complete coverage.

### Routine execution and intermediate verification

Use a narrowly scoped Unicorn PPC32 big-endian runner, pinned only in
`tests/requirements.txt` as `unicorn==2.1.4`. PowerPC support is documented
by the [upstream project](https://github.com/unicorn-engine/unicorn), with
the pinned release documented in its [release notes](https://github.com/unicorn-engine/unicorn/releases/tag/2.1.4).
No dependency is added to the product or global binrecon requirements.

Load linked Mach-O segments at their own addresses, zero BSS, set a bounded
stack and return sentinel, and serialize arguments using recovered PPC
calling conventions. Script only external service boundaries established by
the reference. Record register access and callbacks as symbolic traces.
Unknown calls, unsupported instructions, unexpected privileged operations,
and instruction-limit exhaustion fail the case. Do not silently replace
barriers, cache operations, or hardware access with no-ops.
Hooks may model documented kernel/shared services and MMIO. They must not
replace the driver body under test or a missing internal CHIM implementation.

This is bounded routine execution, not kernel boot, physical DMA validation,
adapter simulation, or proof of concurrency/timing. For lifecycle cases,
run reference-permitted serialized event sequences and review synchronization
instructions and lock ownership separately.

Before full linking, each code group is verified through PPC object
compilation, disassembly/layout checks, source-map/ledger review, and frozen
reference fixtures. Task 16 performs required paired execution against the
linked kernels. Intermediate commits must not claim paired behavioral
acceptance. If the runner cannot execute a required case, resolve its
supported boundary or obtain another actual PPC execution environment;
do not convert the missing check into a passing static audit.

## Implementation tasks

### Task 1: Freeze the complete reference inventory and ownership

**Files:** Create `$au2Profile`, `$au2Recon/inventory.md`, initial source map/ledger,
`$au2Tests/reference.py`, `$au2Tests/verify.py`, and `$au2Tests/test_reconstruction.py`.
**Interfaces:** Consumes the pinned kernel and IDA partition. Produces the
`extract_reference`/`audit` interfaces, complete ownership lists, and ignored
`$au2Out/reference/` extraction with input identity.

- [ ] Write `test_inventory_reference_identity_and_partition`: assert exact hash/size,
  PPC/big-endian identity, ranges, 84+392 bodies, 25 metadata methods, and
  disjoint CHIM owner counts `67,20,28,63,61,31,47,19,14,42`. Add
  `test_inventory_changed_reference_and_omitted_helper_fail` using a changed identity
  and an inventory missing `0x18b2a8`; both must be rejected.
- [ ] Run `& $au2Python -m pytest "$au2Tests/test_reconstruction.py" -k inventory -v`;
  confirm failure because the extraction/audit deliverables are missing.
- [ ] Add the reference-only profile: PPC/big-endian, IDA enabled, Ghidra/angr
  disabled, normalized-functions acceptance, output under `$au2Out/baseline`,
  and the complete recovered scope. Run binrecon `validate` then `analyze`
  with that profile. Reference-only exit 1 is expected; require a complete
  published reference analysis and verify its identity/partition explicitly.
- [ ] Implement targeted extraction using existing readers; avoid the unrelated
  whole-kernel metadata failure. Reconcile seven unnamed bodies, two
  allocation helpers, and external providers. Preserve metadata category
  aliases. Generate a full source map with `--objc-methods`, without
  `--scope-to-objc`; seed the ledger with `tools/binrecon/seed_ledger.py`.
  Missing source remains visibly unmapped until implementation.
- [ ] Run the inventory tests and `verify.py inventory` with explicit reference
  output/repo root; require passing identity, complete accounting, and no
  disputed function boundaries. Commit `scsi: inventory the Ultra2 reference`.

### Task 2: Establish isolated build access and a bounded PPC test runner

**Files:** Create `$au2Tests/{requirements.txt,ppc_cases.py,reference-cases.json,contracts.json,build-objects.sh,build-kernels.sh}`;
extend `test_reconstruction.py` and `reconstruction/verification.md`.
**Interfaces:** Consumes Task 1 identity/segments/functions. Produces
`run_case`, the execution CLI, fixture/result contracts, and guest build scripts.

- [ ] Record a private snapshot/guest identity, unique ports, source/output
  roots, and available PPC compiler/SDK/DriverKit/MIG/Samurai prerequisites.
  Run an unchanged PPC baseline with the existing `ninja/tests/ppc.sh build`
  in its own absent scratch directory. Record its actual result before
  attributing later failures to this driver.
- [ ] Write `test_ppc_runner_wrap_endian_return`, `test_runner_unknown_call_fails`,
  `test_runner_instruction_limit_fails`, and `test_stale_result_fails`.
  Assert 32-bit arithmetic wrap, big-endian memory observations, a proper
  return sentinel, and rejection of unsupported calls/loops/wrong hashes.
  Run pytest `-k 'runner or stale'`; confirm the missing runner fails.
- [ ] Create a task-local environment under `$au2Out/venv` with the existing
  binrecon Python's `-m venv --system-site-packages`, install
  `$au2Tests/requirements.txt` there, and point `$au2Python` to its
  `Scripts/python.exe`. Preserve the shared binrecon environment. Implement
  only the declared bounded runner. Fixture records contain case
  ID, symbolic entry, reviewed argument/memory inputs, scripted external
  outcomes, expected return/memory/trace observations, and reference-address
  evidence. Resolve each binary's symbols independently. Include an
  independently specified smoke fixture before trusting reference results.
- [ ] Implement the two shell-script interfaces above, reusing generated
  compiler/link commands and existing guest helpers. Capture logs through
  `ninja/tests/read-log.sh`, not native `tail` on a growing file. Run
  `/bin/sh -n` on both scripts. Use `build-objects.sh` to compile the existing
  independent `bsd/libkern/locc.c` object and verify PPC Mach-O CPU type 18.
- [ ] Run the runner tests and the conversion helpers against the reference.
  Require all smoke cases, identity checks, and unknown-call rejection to
  pass; save baseline/build limitations accurately. Commit
  `scsi: add bounded PPC reconstruction checks`.

### Task 3: Recover and freeze all shared ABI contracts

**Files:** Create `AdaptecU2CHIMTypes.h`, `AdaptecU2CHIM.h`,
`AdaptecU2CHIMPrivate.h`, `AdaptecU2SCSIPrivate.h`, and `tests/layout-checks.m`;
modify existing controller/OSM headers and `reconstruction/interfaces.md`.
**Interfaces:** Consumes all reference metadata and callers. Produces exact
typed declarations for every later owner, including callback tables and
request/control blocks. Every later task consumes these headers unchanged
unless evidence requires an explicitly recorded correction.

- [ ] Write `test_target_layout_and_method_contracts`: assert class size
  `0x5d0`, configuration `0x25c/0x44`, profile `0x2ac/0x1d0`, HIM table
  `0x4cc/0xa8`, and queue offsets `0x580/0x588/0x590`. Assert
  `registerHandlerForIRQ:` is `void(int)` and `createOSMIOBPool` is `void`.
  Include `test_dispatch_headers_are_not_callbacks` for HIM `4+41 slots`
  and OSM `0+30 slots`. Run pytest `-k 'layout or dispatch'`; require failure
  against the draft declarations.
- [ ] Recover all 392 CHIM prototypes from caller/callee register use,
  accesses, and table slots. Recover OSM/private method contracts, inherited
  layout, IOB/HIOB/SCB/SG formats, unions, bitfields, signedness, alignment,
  and ownership. Record the seven unnamed helpers without guessing names
  or treating them as generated solely because symbols are absent.
- [ ] Write the typed headers and legacy-compatible size/offset assertions.
  Use metadata member names, preserve public selector spelling/category,
  and document each required kernel-7 adaptation. Keep the public getter's
  recovered size/copy semantics, including caller assumptions.
- [ ] Run `build-objects.sh` for `tests/layout-checks.m`; inspect PPC object
  constants/metadata using existing readers and IDA. Run `verify.py layouts`
  and the layout/dispatch tests; require matching offsets, encodings,
  callback types, and complete signature evidence.
- [ ] Commit `scsi: recover Ultra2 ABI and callback contracts`.

### Task 4: Recover all firmware and static data

**Files:** Create `AdaptecU2CHIMFirmware.c` and `AdaptecU2CHIMTables.c`;
extend extraction, audits, fixtures, and inventory/interfaces evidence.
**Interfaces:** Consumes Task 3 descriptors/prototypes. Produces four `Seq_*`
arrays, all firmware/hardware descriptors and selectors, `SCSIFuncPtrs`,
configuration/profile/device tables, and any additional driver-owned data.

- [ ] Write `test_firmware_bytes_lengths_and_selection` and
  `test_descriptor_targets_and_profile_scalars`. Assert image hashes/lengths
  frozen from reference descriptors/loaders, all four modes, exact scalar
  fields/sentinels, and normalized pointer targets. Add rejection fixtures
  with one changed firmware byte and one changed callback target.
  Run pytest `-k 'firmware or descriptor'`; require missing-data failures.
- [ ] Extract and review every object listed in spec section 3.3. Establish
  boundaries through loader lengths and references, preserve alignment and
  mutability, and emit byte arrays and typed symbolic C initializers.
  Record loader selection/revision predicates and runtime patch locations.
- [ ] Compile both PPC C objects. Run `verify.py firmware --objects ...` and
  the firmware/descriptor tests; require byte-exact images and pointer-aware
  table equivalence. Review zero/header entries as scalars.
- [ ] Commit `scsi: recover Ultra2 firmware and hardware tables`.

### Task 5: Recover OSM services and OSD SCB construction

**Files:** Create `AdaptecU2OSMServices.m` and `AdaptecU2CHIMOSD.c`;
remove moved definitions from `OSMFunctions.m`; extend fixture/tests/evidence.
**Interfaces:** Consumes typed OSM/CHIM/private declarations and tables.
Produces the 30 OSM services, two allocation helpers, reviewed conversion
helpers, and all 14 `OSD*` functions. The remaining thread helper belongs
to Task 14. Shared-helper reuse requires a named source/provider.

- [ ] Add `test_osm_access_width_endian_and_dma_boundary`,
  `test_osd_scb_encoding_all_modes`, and `test_osd_completion_status`.
  Fixtures assert reference read/write widths, byte order, cache/barrier
  trace, page-boundary allocation/free ownership, SCB/SG bytes for all four
  modes, and special/normal callback disposition. Run the group audits;
  require missing/incorrect implementation failures.
- [ ] Reconstruct services and OSD routines using Task 3 prototypes. Preserve
  nonvolatile-storage stubs where present. Move allocation/conversion bodies
  to the services file; remove superseded definitions and references while
  retaining explicit declarations for later lifecycle consumers.
- [ ] Compile both PPC objects, inspect byte-reversing and barrier/access
  instructions, freeze successful reference fixtures, and run
  `verify.py group` for `AdaptecU2CHIMOSD.c` plus OSM service accounting.
  Require full owner coverage, reviewed bodies, and exact target layouts.
- [ ] Refresh source-map locations and ledger evidence. Commit
  `scsi: reconstruct Ultra2 OSM services and SCB builders`.

### Task 6: Recover low-level hardware, EEPROM, and sequencer operations

**Files:** Create `AdaptecU2CHIMHardware.c` (61 functions); extend cases,
contracts, tests, source map, and ledger.
**Interfaces:** Consumes services, descriptors, and private declarations.
Produces all `SCSIh*` functions in `[0x19cb3c,0x1a245c)`.

- [ ] Add `test_hardware_pause_register_and_eeprom_trace` and
  `test_sequencer_download_patch_and_failure`. Assert exact register widths,
  masks, pause/unpause sequencing, EEPROM request/data/timeouts, firmware
  download/patch operations, and reference failure return/cleanup traces.
  Run the owner audit before implementation; require unmapped-body failure.
- [ ] Implement the 61 functions, including the reference chip-specific
  variants and workarounds. Implement in batches of at most eight functions
  or one documented inseparable dependency cycle; use actual headers and
  explicit service contracts for calls outside the batch.
- [ ] Compile/review each batch; run its object/group checks and reference
  fixtures. Record polling bounds/conditions and timing primitives without
  claiming elapsed physical time was tested. Refresh the ledger/map.
- [ ] Require the full owner's group audit to pass. Commit verified batches
  with `scsi: reconstruct Ultra2 hardware operations` or a narrower description.

### Task 7: Recover SCB queues and software-state operations

**Files:** Create `AdaptecU2CHIMSCB.c` (67 functions); extend cases/tests/evidence.
**Interfaces:** Consumes services/hardware, descriptors, and recovered SCB
state. Produces `SCSIh*` in `[0x18b754,0x1922a8)` only; embedded `SCSIH*`
functions in that range belong to Task 12.

- [ ] Add `test_scb_queue_linkage_all_modes`, `test_scb_abort_search_and_bdr`,
  and `test_scb_exhaustion_freeze_and_reset`. Assert exact head/tail/link
  changes, SCB numbers and bus addresses, busy-state clearing, search results,
  abort-bit placement, BDR preparation, and software reset state. Run the
  group audit; require missing-owner coverage to fail.
- [ ] Implement the 67 bodies in bounded batches. Preserve mode-specific
  address widths, queue representation, delivered SCB state, and stack/queue
  workarounds. Reconcile the two CHIM bodies currently in `OSMFunctions.m`
  and remove those definitions when their recovered replacements are added.
- [ ] Compile each batch and inspect reference/rebuilt object disassembly.
  Freeze queue fixtures from reference execution, run group/layout checks,
  and update the map/ledger. Require all 67 bodies to be accounted for.
- [ ] Commit verified batches as `scsi: reconstruct Ultra2 SCB queues`.

### Task 8: Recover hardware configuration and initialization

**Files:** Create `AdaptecU2CHIMConfig.c` (20 functions); extend cases/tests/evidence.
**Interfaces:** Consumes hardware/SCB operations and mode descriptors.
Produces `SCSIh*` in `[0x1922a8,0x193bb8)`.

- [ ] Add `test_chip_mode_configuration_and_sequencer_choice` and
  `test_hardware_initialization_failure`. Assert capability/SCB limits,
  firmware choice, chip/revision conditions, termination/cable behavior,
  and reference outcomes for supported initialization failures.
  Run the group audit; require missing configuration bodies to fail.
- [ ] Implement all 20 bodies from exact predicates, defaults, and writes.
  Preserve AIC78XX/Bayonet variants, SCB RAM setup, sequencer startup, and
  reference auto-termination behavior.
- [ ] Compile, inspect accesses, freeze reference cases, and run the group
  audit and layout/firmware regression cases. Update map/ledger evidence.
- [ ] Commit `scsi: reconstruct Ultra2 hardware initialization`.

### Task 9: Recover negotiation and mode-specific transfer state

**Files:** Create `AdaptecU2CHIMNegotiation.c` (63 functions); extend cases/tests/evidence.
**Interfaces:** Consumes hardware primitives, SCB layouts, and configuration.
Produces `SCSIh*` in `[0x198100,0x19cb3c)`.

- [ ] Add `test_wide_sync_messages_and_responses`,
  `test_transfer_rate_option_and_offset`, and `test_modify_data_pointer_sg`.
  Assert reference message bytes and reject/response transitions, chip rate
  mappings, fast-transfer bookkeeping, ignored-wide-residue handling, and
  mode-specific SG/data-pointer adjustments. Include narrow/asynchronous
  and reference boundary cases. Require the initial group audit to fail.
- [ ] Implement in bounded batches; retain chip and mode distinctions,
  signed arithmetic, field masks, register order, and message negotiation
  state. No substitute rate formula or generic negotiation state machine.
- [ ] Compile and review each batch; freeze reference fixtures, run owner
  and layout checks, and update map/ledger evidence for all 63 functions.
- [ ] Commit verified batches as `scsi: reconstruct Ultra2 transfer negotiation`.

### Task 10: Recover hardware interrupt, error, and abort handling

**Files:** Create `AdaptecU2CHIMRecovery.c` (28 functions); extend cases/tests/evidence.
**Interfaces:** Consumes hardware, SCB, negotiation, and callback declarations.
Produces `SCSIh*` in `[0x193bb8,0x198100)`.

- [ ] Add `test_selection_parity_and_bad_sequence`,
  `test_autosense_residual_and_completion`, and `test_active_abort_vs_completion`.
  Assert interrupt acknowledgment/access order, reference status mapping,
  autosense requests, short-transfer residuals, and abort search/removal in
  all supported modes. Include allowed completion/abort event orderings.
  Require the initial group audit to fail.
- [ ] Recover all 28 bodies, including reset/error handlers, active-abort
  variants, residue calculations, termination, status setting, and abort
  queue removal. Preserve reference callbacks and recovery order.
- [ ] Compile and review; freeze reference cases and run owner/layout checks.
  Review synchronization and remaining queue/resource calls against Task 3
  contracts. Update map/ledger; commit `scsi: reconstruct Ultra2 hardware recovery`.

### Task 11: Recover resource management and dispatch

**Files:** Create `AdaptecU2CHIMResource.c` (47 functions); extend cases/tests/evidence.
**Interfaces:** Consumes hardware/SCB/recovery operations. Produces all 34
`SCSIr*` functions and 13 uppercase resource-layer `SCSIR*` functions.

- [ ] Add `test_resource_queue_exhaustion_and_redispatch`,
  `test_host_device_abort_freeze_unfreeze`, and
  `test_resource_completion_reset_ownership`. Assert empty/exhausted queue
  outcomes, SCB allocation/return, frozen-queue disposition, abort posting,
  queue-full adjustments, callback count, and ownership after the permitted
  completion/reset orderings. Require the owner audit to fail initially.
- [ ] Implement queue, resource, completion, event, reset/abort, and public
  resource wrappers in bounded batches using the recovered contracts.
  Preserve exactly when each HIOB enters or leaves each queue and is posted.
- [ ] Compile/review batches; freeze cases and run group/layout checks.
  Audit every resource-layer dispatch target and update map/ledger evidence.
- [ ] Commit verified batches as `scsi: reconstruct Ultra2 resource management`.

### Task 12: Recover the hardware-interface wrappers

**Files:** Create `AdaptecU2CHIMHIM.c` (31 functions); extend cases/tests/evidence.
**Interfaces:** Consumes configuration, hardware, resource, and recovery
headers. Produces all `SCSIH*` bodies, including interleaved reference bodies.

- [ ] Add `test_him_memory_configuration_and_unit_handles`,
  `test_him_queue_interrupt_and_idle`, and `test_him_eeprom_profile_failures`.
  Assert memory table sizes/attributes, handle lifecycle, interrupt and
  special-HIOB dispatch, idle checks, negotiated hardware information, and
  reference EEPROM/initialization failures. Require initial audit failure.
- [ ] Reconstruct all wrappers, status/interrupt enable controls, device-table
  application, negotiation controls, external-SCB/scratch/address operations,
  and power-management behavior, including genuine reference stubs.
- [ ] Compile, inspect forwarding targets/arguments/returns, freeze cases,
  run group/layout checks, and update map/ledger evidence.
- [ ] Commit `scsi: reconstruct Ultra2 hardware interface`.

### Task 13: Recover the transport helpers and public CHIM API

**Files:** Create `AdaptecU2CHIMTransport.c` (19 functions) and
`AdaptecU2CHIMAPI.c` (42 functions); extend cases/tests/evidence.
**Interfaces:** Consumes all completed CHIM groups, services, and tables.
Produces every `SCSIx*` helper and the 42 public `SCSI*` functions, including
the versioned getter, initialization/profile interfaces, queueing, and ISRs.

- [ ] Add `test_public_table_and_memory_contract`,
  `test_scan_lun_profiles_and_firmware_mode`, and
  `test_front_back_isr_and_special_iob`. Assert getter size/copy behavior,
  all 41 dispatch identities and version 4, configuration/memory limits,
  scan/LUN state, adapter/target profiles and masks, NV behavior, error
  translation, special requests, and front/back ISR disposition. Require
  both owner audits to fail before their implementations exist.
- [ ] Recover transport helpers, then public API bodies in dependency batches.
  Preserve table order, scan callbacks, target validation, power/state/NV
  behavior, and genuine nexus/node stubs. Do not drop unexercised API slots.
- [ ] Compile and review both groups; run all completed CHIM owner audits,
  layout/firmware checks, and reference cases. Require 392/392 function
  accounting with all handwritten bodies behaviorally reviewed.
- [ ] Update map/ledger; commit verified batches as
  `scsi: reconstruct Ultra2 transport and public CHIM API`.

### Task 14: Reconstruct the controller, thread, and OSM lifecycle

**Files:** Reconcile `AdaptecU2SCSI.{m,h}`, `AdaptecU2SCSIThread.m`,
`OSMFunctions.{m,h}`, and `AdaptecU2SCSIPrivate.h`; extend cases/contracts/evidence.
**Interfaces:** Consumes complete typed CHIM/OSM services. Produces all 25
reference methods and the remaining OSM/helper bodies with one owner each.

- [ ] Add `test_controller_methods_and_single_definitions`,
  `test_request_completion_status_residual_and_autosense`,
  `test_timeout_reset_completion_event_order`, and `test_probe_init_unwind`.
  Assert exact selectors/category/type encodings; single definitions of
  probe/post/IRQ methods; request/IOB mapping; resource/timer ownership;
  completion status/residuals; and permitted lifecycle/failure traces.
  Require failures against the existing duplicate/conflicting drafts.
- [ ] Replace controller field accesses with recovered declarations, restore
  `+initialize` and the thread category, remove superseded duplicate method
  blocks, and reconcile the unnamed thread helper. Correct C symbol spelling
  and callback signatures. Retain one reference-backed probe/post path.
- [ ] Recover remaining OSM command queues, posting, freeze/unfreeze,
  auto-configuration, reset/event handling, IRQ dispatch, IOB allocation,
  request entry points, cleanup, and statistics. Verify every acquired
  resource's reference unwind and every timer's cancellation/ownership.
- [ ] Compile every production object together without linking yet; run
  layout/group audits and reference cases. Reuse `selector_check.source_methods`
  with architecture `ppc` and `selector_check.classify` inside the audit,
  supplying the 25 metadata-derived driver method names from Task 1.
  Require empty rename, duplicate, missing, and extra sets. Do not use that
  tool's standalone CLI here: it derives reference methods from text symbols
  and its exit status does not enforce missing/extra completeness.
- [ ] Require complete 476-body accounting or documented inventory correction,
  no duplicate/disputed definitions, and current source-map lines. Commit
  `scsi: reconstruct the Ultra2 controller lifecycle`.

### Task 15: Integrate and build both PPC configurations

**Files:** Modify `src/kernel-7/conf/files.ppc` and
`src/kernel-7/ninja/ppc-sources.ninja`; adjust other PPC fragments and
`driverkit/ppc/autoconf_ppc.m` only if reference evidence requires it.
Extend build scripts/tests and `reconstruction/verification.md`.
**Interfaces:** Consumes all production objects; produces four fresh build
products, `builds.json`, and retained stripped/unstripped artifacts.

- [ ] Add `test_build_lists_include_all_and_only_production_sources` and
  `test_built_ppc_driver_presence`. Assert all final controller/OSM/CHIM/data
  sources appear once under the correct condition, test sources never link,
  and the final class/category, functions, firmware, tables, and dependencies
  exist. Require failure before build integration.
- [ ] Add sources to historical configuration. Regenerate private Makefiles
  and update Samurai source edges plus both link-input lists to match.
  Check existing autoconfiguration names/matching against the reference.
  Preserve unrelated build behavior and existing compiler options.
- [ ] Run in the guest kernel root:
  `/bin/sh ninja/tests/ppc.sh compare /tmp/au2-ppc-compare-<run-id>` and
  `/bin/sh bsd/dev/ppc/drvAdaptecU2SCSI/tests/build-kernels.sh /tmp/au2-ppc-build-<run-id>`.
  Use actual fresh run IDs. Expected: `PASS: PPC compare` and four successful
  kernel builds recorded in `builds.json`.
- [ ] Historical Make setup uses `/bin/csh -f tools/doconf/doconf.csh -c -cpu ppc
  -d SCRATCH/BUILD.make RELEASE DEBUG` from `conf`; ensure the private
  `newvers` link and `assym.h` generation described by the build baseline.
  Run `gnumake MIG='mig -arch ppc' assym.h`, then
  `gnumake -j 2 MIG='mig -arch ppc' mach_kernel` in each generated directory.
  Samurai uses `build-ppc.ninja` and `build-ppc-debug.ninja` in its own copy.
- [ ] Run build-list/presence tests against explicit `builds.json`; verify PPC
  headers, unresolved/duplicate symbol checks, target metadata, command/order
  agreement, and idle incremental behavior. Archive hashes/logs and confirm
  the base image remains untouched. Commit
  `scsi: integrate Ultra2 into the PPC kernel builds`.

### Task 16: Complete paired execution, parity review, and acceptance

**Files:** Finalize source map/ledger, `divergences.md`, `verification.md`,
fixtures/audits/tests; update only the existing driver status documentation
that actually refers to this driver, if any.
**Interfaces:** Consumes four exact rebuilt unstripped kernels and frozen
reference cases. Produces complete, reproducible reconstruction/build
acceptance with hardware validation separately recorded.

- [ ] Add `test_final_rejects_missing_case_unreviewed_function_or_mismatch`.
  Assert a missing paired case, `signature-confirmed`-only body, omitted
  indirect callback, stale rebuilt hash, or unexplained mismatch fails the
  final audit. Confirm each negative fixture fails for its intended reason.
- [ ] For each build, generate an ignored paired profile using its actual
  rebuilt path/hash and independently derived function scope. Run binrecon
  `validate` and `analyze`; require complete reference/rebuilt IDA output.
  Use `binrecon function --profile PAIR_PROFILE --list` and `--name NAME`
  to inspect every mismatch without rerunning the analyzer for each body.
  Match unnamed reference helpers through the reviewed identity map and
  scoped analysis aliases, preserving original addresses. Document unrelated
  whole-kernel/section diagnostics as outside the driver scope; do not
  confuse them with unexplained scoped function or referenced-data changes.
- [ ] Run `ppc_cases.py pair` for every required fixture against each linked
  kernel, using its own symbols/addresses and frozen contracts. Compare
  return values, selected memory, SCB/SG bytes, callback/register traces,
  and permitted event sequences. Require all cases; an unknown dependency
  or unsupported operation is a failed check, never a silent skip.
- [ ] Inspect every normalized mismatch, including unchanged instructions
  with differing data/call targets. Record concrete compiler/layout or
  kernel-7 adaptation evidence, reviewer, and fixture coverage. Resolve
  actual behavioral differences. Do not widen ignores or delete entries.
- [ ] Validate the full source map with `load_source_map` against the pinned
  complete scoped analysis and execution repo root. Require all handwritten
  entries at least `control-flow-confirmed`, every generated/shared body
  verified, all four builds accepted, exact firmware/table checks, and no
  disputed/unexplained entries. Run `verify.py final --builds ...` and the
  complete `test_reconstruction.py` suite; expected exit 0 with zero required
  skips. Record exact commands, case counts, hashes, ledger totals, analyzer
  versions, and hardware status in `verification.md`. Use the Samurai
  RELEASE_PPC unstripped kernel as the canonical checked-in ledger's rebuilt
  identity. Keep per-build ledgers/comparisons in ignored output and record
  all four identities/results in `verification.md`; do not overwrite one
  ledger repeatedly and imply it describes four different hashes.
- [ ] Commit `scsi: verify the complete Ultra2 reconstruction`. Report source
  recovery, PPC build acceptance, bounded routine checks, and hardware
  qualification as separate results. Stop only when the spec's acceptance
  conditions are satisfied or an actual external prerequisite blocks progress.

## Review and execution handoff

This plan covers spec sections 1-3 through Tasks 1-14, build integration
through Tasks 2 and 15, evidence/tooling through Tasks 1-3 and 16, and all
acceptance requirements through Tasks 4-16. Every implementation task updates
its source map and ledger; final paired checks are mandatory after linking.

Review the plan before execution and select an execution method. Recommend
subagent-driven execution with the frozen Task 3 headers carried into each
task: the hardware/state-machine groups need independent review, and a
missed DMA or completion rule could corrupt storage. Native execution is
also available, with the same per-task checks and a final independent review.
Do not start reconstruction as part of writing or reviewing this plan.
