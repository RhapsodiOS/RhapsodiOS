# drvATIRage i386 Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development if the user selects that approach. Implement task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct the 61 handwritten code entries and reproduce the two generated routines of Apple's i386 ATI Rage driver, then build and verify the complete package against the reference.

**Architecture:** Recover an authoritative ABI/data/routine contract from raw Mach-O metadata and IDA before translating code. Retain the main filenames, implement ATI and its ProgramDAC category there, and add ATI_BIOS plus symbolic assembly after the generated instance object. Verify coverage, ABI, data, resources and normalized function parity independently.

**Tech Stack:** Historical DriverKit Objective-C/C, i386 assembly, NeXT compiler/pb_makefiles, the existing binrecon Python environment, IDA Professional 9.4.

**Spec:** [drvATIRage reconstruction design](../specs/2026-10-02-drvatirage-reconstruction-design.md).

## Global Constraints

- Reference SHA-256: `6D08A58A44D5797DA0DD626BBEB705E3621910C99120486F69BD623DE9E61D9A`; size 63,548 bytes.
- Complete denominator: 63 code entries, 61 handwritten and two generated; initial IDA inventory: 61 functions.
- Supplemental `__bios16`: `0x2e48..0x2ebd`, 117 bytes, embedded in an initial text gap; supplemental `__ATIbios32`: `0x2f20..0x2feb`, 203 bytes. Initial text gaps total 202 bytes; classify all remaining bytes.
- ATI instance size 624, inherited prefix 552; ATI_BIOS instance size 16, private block 36 bytes.
- 72 display modes of 136 bytes; 18 CRTC records of 30 bytes; BIOS register block 48 bytes; BIOS stack 2048 bytes.
- Implement `ATI : IOFrameBufferDisplay`, `ATI_BIOS : Object`, ATI(ProgramDAC), ATI_BIOS(Private); preserve runtime type encodings.
- Use direct Objective-C class references and existing DriverKit headers. Preserve reference behavior, signedness, access widths and cleanup; no new hardware support or opportunistic fixes.
- Keep binaries, databases, generated analyzer reports, build logs and temporary test artifacts out of Git.
- Preserve other work in the dirty checkout. Implementation may use an isolated worktree, but external reference/generated evidence paths must remain explicit.
- Target acceptance is a fresh, complete binrecon reference/rebuilt run passing `normalized-functions`, with separate ABI/data/thunk/resource gates. Record failures honestly.
- Hardware verification requires an ATI Rage device/BIOS; generic QEMU graphics cannot supply that evidence.

## Review Focus

1. PCI BAR conflicts or low assigned addresses: preserve sizing/restoration, alignment and range-list counts (Task 4).
2. Mode index/format/memory boundaries: return the reference status and retain mode-table validity fields (Tasks 2 and 4).
3. BIOS failures and descriptor size limits: preserve register layout, descriptor restoration order and every observed early return (Task 3).
4. Overlapping blits or a busy engine: preserve direction selection, MMIO order, saved state and timeout comparison (Task 5).
5. RAMDAC overrides and transfer counts: preserve channel extraction, brightness, allocation ownership and palette replication (Task 6).

---

## Paths and command setup

`DRIVER` below is `src/drivers-i386/video/drvATIRage`.
`PROJ` is `DRIVER/ATIRageDisplayDriver.drvproj`.
`LKS` is `PROJ/ATIRageDisplayDriver.lksproj`.
`RECON` is `DRIVER/reconstruction/ATIRageDisplayDriver_reloc`.
These abbreviations expand to those exact paths; they are not shell variables.

From `D:\RhapsodiOS` in PowerShell:

```powershell
$binreconPython = '.\.venv-binrecon\Scripts\python.exe'
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\ATIRageDisplayDriver.config\ATIRageDisplayDriver_reloc'
```

Reference analysis:
`tools/binrecon/out/drvATIRage-i386/published/analysis-reference-ida.json`.
Read both the spec and this plan before implementation. Commit only the task's
own paths at each checkpoint, using the `drvATIRage:` subsystem prefix.

### Task 1: Seal the evidence and establish complete coverage

**Files:** Create `RECON/reference-contract.json`, `RECON/source-map.json`,
`RECON/ledger.json`, `DRIVER/reconstruction/findings.md`,
`RECON/check_reconstruction.py`, `RECON/test_check_reconstruction.py`.
Use the existing `tools/binrecon/profiles/drvATIRage-i386.json`.

**Interfaces:** Produces the authoritative list of 63 reference code entries, each
with address/extent, symbol/metadata aliases, source/generated owner and evidence;
class/category/method/ivar encodings; static-data extents/bindings/relocations;
the BIOS register/private layouts; and a resource hash manifest. Every later
task consumes this contract rather than inferred Hex-Rays declarations.

- [x] Recheck the reference identity and run the reference-only profile. Require
  `complete: true` with null diagnostic; record the expected lack of parity
  acceptance because no rebuilt image was supplied.
- [x] Reconcile all __text symbols and method IMPs with IDA. Inspect every gap
  and both transition/thunk routines' mixed code/data. Establish 63 entries and
  classify each of the 202 gap bytes, including `__bios16` at `0x2e48`. Export
  disassembly for both supplemental entries and
  pseudocode/disassembly for every other handwritten entry.
- [x] Extract raw method type encodings and category membership. Resolve C
  signatures by caller stack slots, instruction widths and DriverKit headers.
  Record the layout of IODisplayInfo, each 30-byte CRTC record, the 48-byte BIOS
  block and the 36-byte private block. Give fields semantic names while retaining
  byte offsets; record unresolved interpretation explicitly until resolved.
- [x] Build the contract and findings. Include all data bindings, all reference
  class-link symbols, lookup strings, scratch storage and resource hashes.
  Seed the ledger as `unexamined`; identify the supplemental thunk without
  pretending it belongs to the initial analyzer partition.
- [x] Implement a narrow reconstruction checker using binrecon's reader and
  semantic loader. CLI: `check_reconstruction.py --reference PATH
  --reference-analysis PATH --repo-root PATH [--source-map PATH] [--rebuilt PATH]`.
  Always validate identity, routine/gap coverage and the reference contract.
  With source-map, enforce all handwritten source owners; allow only the two
  generated omissions. With rebuilt, compare ABI, symbolic static-data pointer
  targets and thunk bytes with relocation fields accounted for.
- [x] Add meaningful negative checks: dropping __bios16 or __ATIbios32 fails coverage;
  changing ATI's size/ivar offset fails ABI; dropping a mode fails data coverage;
  changing a non-relocation thunk byte fails assembly parity. Use copies under
  ignored output, preserving the real reference. Name the unittest cases
  test_missing_bios_transition_fails_coverage, test_missing_bios_thunk_fails_coverage,
  test_changed_ivar_fails_abi,
  test_missing_mode_fails_data_coverage and test_changed_thunk_byte_fails_parity.
  Each asserts a nonzero checker result naming the violated gate. Include an
  unchanged-input case asserting exit 0. Run these checker tests once.
- [x] Generate and semantically validate the initial source map. Current source
  name collisions are candidates only, not reconstructed functions. Annotate
  the IDA database with verified types/comments and save it. Commit this evidence
  checkpoint as `drvATIRage: record the complete reference contract`.

Commands from the repository root (after creating the checker):

```powershell
& $binreconPython -m binrecon analyze --profile tools/binrecon/profiles/drvATIRage-i386.json --output tools/binrecon/out/drvATIRage-i386/run-summary.json
$rageRecon = 'src/drivers-i386/video/drvATIRage/reconstruction/ATIRageDisplayDriver_reloc'
& $binreconPython "$rageRecon/check_reconstruction.py" --reference $env:BINRECON_REFERENCE --reference-analysis tools/binrecon/out/drvATIRage-i386/published/analysis-reference-ida.json --repo-root .
& $binreconPython -m unittest discover -s $rageRecon -p test_check_reconstruction.py -v
```

The reference-only analyzer exits 1 because rebuilt parity is unavailable;
require its summary to be complete with no diagnostic. The reference checker
and all five unittest cases must pass with exit 0.

### Task 2: Recover interfaces, static tables and configuration resources

**Files:** Replace `LKS/ATIRageDisplayDriver.h`, `LKS/ATIRageRegs.h`;
create `LKS/ATIRageModes.h`, `LKS/ATI_BIOS.h`; restore `DRIVER/Default.table`
and the shipped resources under PROJ; update resource/header declarations
through the appropriate Makefile preamble/postamble files.

**Interfaces:** Produces the exact ATI/ATI_BIOS/category declarations from
Task 1, the ABI-compatible named BIOS layouts, and extern declarations for
`ABReturnValues`, ATI lookup tables and BIOS thunk globals. Main ATI code
consumes all 72 modes, CRTC records, gamma arrays and refresh tables. Definitions
retain reference symbol names and binding, with the mode data included once.

- [x] Replace the invented ATI class declaration with the spec's ivar order and
  encodings. Declare the recovered methods and C helper prototypes; keep the
  superclass methods' Point pointers, token/frame and IOReturn types consistent
  with DriverKit. Do not invent a new +probe: method.
- [x] Define ATI_BIOS and its Private category, BIOS register/private structures,
  and assembly-facing globals/prototypes from Task 1. Assert layout offsets in
  the i386 build or inspect emitted ABI metadata; avoid host pointer-size assumptions.
- [x] Recover the 18 CRTC records and all 72 modes in reference order. Resolve
  pointers through relocations. Preserve gamma16/gamma8 bytes, both refresh
  arrays and lookup-table names/bindings. Compare every field, not just counts.
- [x] Replace R128 definitions with the evidenced offsets and masks consumed by
  the reconstruction. Reuse repository port-I/O operations; retain their delay
  semantics and compiler-emitted counter behavior where relevant to parity.
- [x] Restore Default/PCI4Mb/PCI6Mb/PCI8Mb tables and mode files, localized
  strings and all help resources. Preserve case and path; make packaging declarations
  resolve their actual location. Record generated Driver Version separately.
- [x] Verify mode cases for each memory class and pixel encoding against raw
  reference fields, including code 5's 8,386,560-byte limit. Verify resource
  hashes and declarations. Commit as `drvATIRage: recover the ABI and display data`.

### Task 3: Implement the ATI BIOS layer and assembly transfer

**Files:** Create `LKS/ATI_BIOS.m`, `LKS/ATI_BIOS16.s`,
`LKS/ATIbios16.c`, `LKS/ATIbios.s`;
update `LKS/ATI_BIOS.h`, findings and ledger as evidence warrants.

**Interfaces:** Produces all ATI_BIOS selectors at `0x216c..0x2e46`,
`__bios16` at `0x2e48`, the ATIbios16 C wrapper at `0x2ec0`, and the
`__ATIbios32` thunk. In C, use the
identifier whose Mach-O symbol is exactly `__ATIbios32`; resolve the calling
convention from assembly, not the decompiler's guessed annotation.

- [ ] Implement BIOS signature detection, initAtSegmentAddress:, init and free,
  preserving allocation size and superclass calls. Implement the reference
  lookup tables and external globals owned by this unit.
- [ ] Implement the seven Private methods in address order: initBIOSBuf:function:,
  setupCodeSegments, restoreCodeSegments, createDataSegment:size:,
  restoreDataSegment, doBios:dataSeg:, and loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:.
  Preserve selectors 0x80/0x88/0x90/0x98, stack 2048, address translation,
  descriptor bits, status returns and restore order.
- [ ] Implement all public BIOS services and their exact function codes,
  register packing and output writes. Include querySize:size: returning 4096,
  changeRefreshRate: returning 3, DPMS accepting 0..4 then masking with 3,
  and APM accepting 0..3. Verify bytes/words against raw instruction widths.
- [ ] Implement `__bios16` as symbolic instructions, including its saved stack,
  selector changes, far jump, runtime-patched six-byte operand and `retf`.
  Implement ATIbios16's offset check and entry/selector rewrite. Transcribe
  `__ATIbios32` as symbolic instructions and its six-byte far-call operand; preserve
  register/segment/flags saves, cli, register-block output and plain retn.
  Define scratch globals with the reference binding/layout. No binary blob.
- [ ] Compile ATI_BIOS.m and ATIbios16.c and assemble ATI_BIOS16.s/ATIbios.s in the historical i386 environment
  using an ignored working directory. Verify actual stack cleanup and emitted symbol names. Compare both assembly
  routines to their reference extents under relocation-aware byte matching,
  including both far-jump operands.
- [ ] Review BIOS-uninitialized, BIOS-return-error, aperture-misalignment and
  data-segment-size >64 KiB branches. Record exactly which branches restore
  descriptors/free the stack; preserve observed behavior rather than adding
  error cleanup. Verify non-relocation mutation tests fail the thunk check.
  Commit as `drvATIRage: reconstruct the ATI BIOS calls and transitions`.

### Task 4: Reconstruct ATI initialization, PCI resource setup and mode lifecycle

**Files:** Replace `LKS/ATIRageDisplayDriver.m`; update its header, findings,
source map and ledger. Retain the existing filename and use `@implementation ATI`.

**Interfaces:** Produces initFromDeviceDescription:, fixDeviceDescriptionForPCI:,
getQueryData, parseModeString:, updateModeList, isModeValid:, verifyMemoryMap,
free, enterLinearMode, revertToVGAMode, displayModeCount, displayModes,
displayMemorySize and setPendingDisplayMode:. Produces displayInfoToColorSpace,
colorDepthToColorSpace, displayInfoToColorDepth and memSizeToBytes with Task 1's
confirmed signatures. Calls the BIOS interface from Task 3 and declares future
engine/gamma methods without temporary implementations.

- [ ] Implement PCI identification/BAR sizing and restore. Reconstruct alignment,
  range reservations, low-address correction, resource-conflict handling and FB
  Address override. Inspect every original range-list count at the call site;
  preserve memory/I/O masks and diagnostic strings.
- [ ] Implement initialization and query-data lifetime from the reference. Map
  8 MiB, use framebuffer +0x7ffc00 for register_base_address, preserve both
  scratch tests, ASIC feature detection and default brightness 64. Preserve
  pre-superclass and post-superclass failure ownership.
- [ ] Implement mode selection, mutable table updates, validity and pending
  mode handling. Use all 72 records and preserve the reference channel-order
  strings. Implement state transitions and BIOS CRTC/VGA restoration calls.
- [ ] Implement VRAM verification and cleanup exactly. Implement the four
  conversion helpers in their reference definition order after ProgramDAC's
  eventual methods, with static forward declarations where necessary.
- [ ] Compile the main object and review the five focused PCI/mode cases:
  I/O versus memory BARs, conflicting address reservations, mode >=72 returning
  16, unsupported 15-bit capability returning 64, and insufficient memory returning
  2. Inspect signed/unsigned handling for negative modes and query failures.
  Check that memSizeToBytes(5) is 8,386,560. Intermediate objects are not a
  loadable complete driver until Tasks 5 and 6 supply their methods.
- [ ] Update mappings only after body review. Commit as
  `drvATIRage: reconstruct PCI setup and the display lifecycle`.

### Task 5: Recover acceleration and cursor synchronization

**Files:** Complete drawing/engine/cursor functions in `LKS/ATIRageDisplayDriver.m`;
update regs/header, findings, source map and ledger.

**Interfaces:** Produces waitForFIFO, waitForIdle, doBlit and doFill using
confirmed Task 1 prototypes; ATI initEngine, resetEngine,
showCursor:frame:token:, moveCursor:frame:token:, hideCursor: and
setIntValues:forParameter:count:. Existing lifecycle code calls initEngine.

- [ ] Implement FIFO and idle polling from instruction-level conditions. Pin the
  FIFO threshold calculation and idle counter comparison/increment ordering.
- [ ] Implement doBlit overlap directions and doFill register writes. Preserve
  coordinate packing, signed difference handling, access width, wait placement,
  and restoration of the saved registers.
- [ ] Implement initEngine/resetEngine and the three pixel-depth branches with
  reference literal constants and port/MMIO access sequence.
- [ ] Implement cursor idle waits and superclass forwarding. Implement dispatcher
  names/counts (6, 5, 1) and superclass fallback for every other combination.
- [ ] Compile and compare each corresponding function's rebuilt disassembly.
  Review overlapping versus non-overlapping copies in both axes, saved-register
  restoration, busy-engine timeout, all three depth branches and dispatcher
  fallback. Count an MMIO-order/width difference as a behavioral failure,
  regardless of matching strings or symbols. Commit as
  `drvATIRage: reconstruct drawing and cursor synchronization`.

### Task 6: Recover the ProgramDAC transfer and brightness behavior

**Files:** Complete ProgramDAC category and two helpers in
`LKS/ATIRageDisplayDriver.m`; update header, findings, source map and ledger.

**Interfaces:** Produces isATI68880RevC, SetGammaValue, ATI(ProgramDAC)
setGammaTable, setBrightness:token: and setTransferTable:count: with confirmed
metadata declarations. Lifecycle code calls setGammaTable; transfer channels
share a single allocation owned by redTransferTable.

- [ ] Implement the two helpers and three category methods in reference address
  order. Preserve port sequence, I/O delays, unsigned byte shifts and brightness
  scaling by 64.
- [ ] Recover ASIC/DAC conditions and Sparse/Dense override precedence. Preserve
  grayscale versus RGB channel extraction, per-channel pointers, freeing and
  reallocating the combined buffer, and unsupported-colorspace behavior.
- [ ] Preserve gamma array indexing and palette replication in both default and
  uploaded table paths. Review zero, negative, >256 and non-dividing counts
  explicitly in the original instructions; record input preconditions or quirks.
- [ ] Verify brightness 0/64/65, absent/present transfer buffers, Sparse/Dense,
  supported ASIC/DAC variants, grayscale/RGB and unsupported colorspaces through
  the rebuilt function comparison and branch review. Confirm allocation ownership
  and integer rounding. Commit as `drvATIRage: reconstruct gamma and transfer tables`.

### Task 7: Integrate a fresh build and complete package

**Files:** Create `vm/build-i386-atirage.sh`; update LKS Makefile preamble/postamble
and Load_Commands.sect, driver resource declarations, and reconstruction findings.

**Interfaces:** Produces a fresh i386 `ATIRageDisplayDriver.config` staged under
`/build/out/i386/drvATIRage/`, including _reloc, companion executable and the
manifest's complete resources. Exports `ATI_BIOS_I386` and `ATI_THUNK_I386` so
LKS's postamble appends those objects to LOADABLES after generated instance glue.

- [ ] Restore the reference WIRE load-command semantics and Server Name,
  Instance Var and Server Version values. Keep generated instance classes in
  the normal Kernel Server rules, with version method returning 500.
- [ ] Integrate main/header/data sources using preambles/postambles. Compile
  ATI_BIOS.m, ATI_BIOS16.s, ATIbios16.c and ATIbios.s before the kernel link;
  append their absolute object paths in observed text order after the generated
  instance object. Add dependencies so a clean
  build through the harness cannot silently omit the extras.
- [ ] Write the dedicated POSIX-sh harness from existing guest build conventions.
  Use fresh target object/staging directories; record the exact command, flags,
  tool versions, object ordering and exit codes. Require a new artifact and
  complete package contents; do not accept an artifact left by an earlier build.
- [ ] Build in the historical environment with `RC_ARCHS=i386 INCLUDED_ARCHS=i386`.
  Require compilation and kernel link success; resolve missing class/data/kernel
  imports in this project's declarations and integration before considering any
  shared infrastructure change. Verify companion version glue and generated
  VERS symbols, reporting expected build-text differences separately.
- [ ] Execute `sh /build/source/vm/build-i386-atirage.sh` in the guest. Require
  exit 0 and newly written outputs under `/build/out/i386/drvATIRage/`;
  the harness must report failure if compilation, link or resource staging fails.
- [ ] Copy fresh results to ignored host output and hash them. Compare every
  packaged resource with the manifest. Commit as
  `drvATIRage: integrate the reconstructed driver build and resources`.

### Task 8: Close parity, source coverage and documentation

**Files:** Create `tools/binrecon/profiles/drvATIRage-i386-compare.json`;
finish RECON source-map/ledger/contract/checker, findings and the drvATIRage
entry in `src/drivers-i386/README` (preserving other existing edits).

**Interfaces:** Consumes the fresh Task 7 artifact. Produces the final comparison
summary, all 63 reviewed code-entry records, validated source ownership, ABI/data/
thunk/resource results and an accurate reconstruction/hardware status.

- [ ] Create a comparison profile with both `${BINRECON_REFERENCE}` and
  `${BINRECON_REBUILT}`; IDA 9.4, i386/little-endian, normalized-functions
  acceptance, output `../out/drvATIRage-i386-compare`. Keep the reference-only
  profile intact. Set BINRECON_REBUILT to the freshly staged _reloc.
- [ ] Run binrecon analyze and inspect `complete`, diagnostics and acceptance.
  Iterate function-by-function on every discrepancy. Verify call targets,
  control flow, constants, stack layout and access widths in IDA before changing
  source; rebuild after changes. Explain generated metadata separately.
- [ ] Run `parity_check.py REFERENCE REBUILT`,
  `selector_check.py REFERENCE SOURCE_DIR`, and
  `import_check.py REFERENCE REBUILT KERNEL` with the actual intended kernel.
  Require no unexplained missing reference symbol/string/import and no
  unresolvable import. Inspect selector missing/extra lists explicitly; the
  script's exit status alone is weaker than this task's requirement.
- [ ] Run check_reconstruction.py with reference, reference analysis, repository
  root, rebuilt artifact and the final source map. Require all handwritten
  owners, exact class/category/ivar encodings and sizes, all static data and
  symbolic pointer targets, and relocation-aware comparison of the 117-byte transition routine and 203-byte thunk.
- [ ] Regenerate the source map with binrecon source-map `--objc-methods` and
  validate using load_source_map with analysis and repo_root. The initial
  partition's expected outcome is 59 handwritten mappings and two explicitly
  generated omissions, plus the separately checked thunk. If IDA/scanner
  boundaries differ, reconcile evidence without reducing the denominator.
- [ ] Review every handwritten body and advance ledger statuses only to the
  strength proven. Include actual reviewer identity and artifacts. Save IDA
  names/types/comments and the database; generated outputs remain ignored.
- [ ] Run only the meaningful checker tests affected by the final changes.
  Record binary hashes and tool versions. If ATI hardware/emulation is available,
  perform the spec's runtime cases with a temporary image; otherwise state that
  hardware execution remains unverified and do not substitute a VGA boot result.
- [ ] Update findings and README with achieved gates and measured parity. Do not
  call the reconstruction complete while normalized-function acceptance or any
  other completion gate remains unmet. Commit as
  `drvATIRage: verify reconstruction parity and record the result`.

Final host commands, with BINRECON_REBUILT set to the freshly copied artifact
and BINRECON_KERNEL set to the intended kernel file:

```powershell
& $binreconPython -m binrecon analyze --profile tools/binrecon/profiles/drvATIRage-i386-compare.json --output tools/binrecon/out/drvATIRage-i386-compare/run-summary.json
& $binreconPython tools/binrecon/parity_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT
& $binreconPython tools/binrecon/selector_check.py $env:BINRECON_REFERENCE src/drivers-i386/video/drvATIRage/ATIRageDisplayDriver.drvproj/ATIRageDisplayDriver.lksproj
& $binreconPython tools/binrecon/import_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT $env:BINRECON_KERNEL
& $binreconPython "$rageRecon/check_reconstruction.py" --reference $env:BINRECON_REFERENCE --reference-analysis tools/binrecon/out/drvATIRage-i386-compare/published/analysis-reference-ida.json --repo-root . --source-map "$rageRecon/source-map.json" --rebuilt $env:BINRECON_REBUILT
```

All commands must exit 0, the comparison summary must be complete with passing
acceptance, and reported selector missing/extra lists must be empty. Record any
extra generated strings/symbols separately; exit status alone is not the full gate.

## Dependency order and execution choice

Task 1 precedes all others. Task 2 establishes the shared types/data. Task 3
supplies the BIOS layer; Task 4 consumes it. Tasks 5 and 6 complete the main
driver; Task 7 integrates all sources; Task 8 closes verification. Stages that
only compile individual objects are intermediate checkpoints, not deployable
driver builds.

Native execution is recommended because all tasks share a precise recovered
ABI and the main translation unit. Subagent-driven execution is available if
the user selects it, but would need serialized main-file ownership and review
of the same contract at each handoff.
