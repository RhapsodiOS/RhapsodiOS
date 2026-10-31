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

- [x] Implement BIOS signature detection, initAtSegmentAddress:, init and free,
  preserving allocation size and superclass calls. Implement the reference
  lookup tables and external globals owned by this unit.
- [x] Implement the seven Private methods in address order: initBIOSBuf:function:,
  setupCodeSegments, restoreCodeSegments, createDataSegment:size:,
  restoreDataSegment, doBios:dataSeg:, and loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:.
  Preserve selectors 0x80/0x88/0x90/0x98, stack 2048, address translation,
  descriptor bits, status returns and restore order.
- [x] Implement all public BIOS services and their exact function codes,
  register packing and output writes. Include querySize:size: returning 4096,
  changeRefreshRate: returning 3, DPMS accepting 0..4 then masking with 3,
  and APM accepting 0..3. Verify bytes/words against raw instruction widths.
- [x] Implement `__bios16` as symbolic instructions, including its saved stack,
  selector changes, far jump, runtime-patched six-byte operand and `retf`.
  Implement ATIbios16's offset check and entry/selector rewrite. Transcribe
  `__ATIbios32` as symbolic instructions and its six-byte far-call operand; preserve
  register/segment/flags saves, cli, register-block output and plain retn.
  Define scratch globals with the reference binding/layout. No binary blob.
- [x] Compile ATI_BIOS.m and ATIbios16.c and assemble ATI_BIOS16.s/ATIbios.s in the historical i386 environment
  using an ignored working directory. Verify actual stack cleanup and emitted symbol names. Compare both assembly
  routines to their reference extents under relocation-aware byte matching,
  including both far-jump operands.
- [x] Review BIOS-uninitialized, BIOS-return-error, aperture-misalignment and
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

- [x] Implement PCI identification/BAR sizing and restore. Reconstruct alignment,
  range reservations, low-address correction, resource-conflict handling and FB
  Address override. Inspect every original range-list count at the call site;
  preserve memory/I/O masks and diagnostic strings.
- [x] Implement initialization and query-data lifetime from the reference. Map
  8 MiB, use framebuffer +0x7ffc00 for register_base_address, preserve both
  scratch tests, ASIC feature detection and default brightness 64. Preserve
  pre-superclass and post-superclass failure ownership.
- [x] Implement mode selection, mutable table updates, validity and pending
  mode handling. Use all 72 records and preserve the reference channel-order
  strings. Implement state transitions and BIOS CRTC/VGA restoration calls.
- [x] Implement VRAM verification and cleanup exactly. Implement the four
  conversion helpers in their reference definition order after ProgramDAC's
  eventual methods, with static forward declarations where necessary.
- [x] Compile the main object and review the five focused PCI/mode cases:
  I/O versus memory BARs, conflicting address reservations, mode >=72 returning
  16, unsupported 15-bit capability returning 64, and insufficient memory returning
  2. Inspect signed/unsigned handling for negative modes and query failures.
  Check that memSizeToBytes(5) is 8,386,560. Intermediate objects are not a
  loadable complete driver until Tasks 5 and 6 supply their methods.
- [x] Update mappings only after body review. Commit as
  `drvATIRage: reconstruct PCI setup and the display lifecycle`.

### Task 5: Recover acceleration and cursor synchronization

**Files:** Complete drawing/engine/cursor functions in `LKS/ATIRageDisplayDriver.m`;
update regs/header, findings, source map and ledger.

**Interfaces:** Produces waitForFIFO, waitForIdle, doBlit and doFill using
confirmed Task 1 prototypes; ATI initEngine, resetEngine,
showCursor:frame:token:, moveCursor:frame:token:, hideCursor: and
setIntValues:forParameter:count:. Existing lifecycle code calls initEngine.

- [x] Implement FIFO and idle polling from instruction-level conditions. Pin the
  FIFO threshold calculation and idle counter comparison/increment ordering.
- [x] Implement doBlit overlap directions and doFill register writes. Preserve
  coordinate packing, signed difference handling, access width, wait placement,
  and restoration of the saved registers.
- [x] Implement initEngine/resetEngine and the three pixel-depth branches with
  reference literal constants and port/MMIO access sequence.
- [x] Implement cursor idle waits and superclass forwarding. Implement dispatcher
  names/counts (6, 5, 1) and superclass fallback for every other combination.
- [x] Compile and compare each corresponding function's rebuilt disassembly.
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

- [x] Implement the two helpers and three category methods in reference address
  order. Preserve port sequence, I/O delays, unsigned byte shifts and brightness
  scaling by 64.
- [x] Recover ASIC/DAC conditions and Sparse/Dense override precedence. Preserve
  grayscale versus RGB channel extraction, per-channel pointers, freeing and
  reallocating the combined buffer, and unsupported-colorspace behavior.
- [x] Preserve gamma array indexing and palette replication in both default and
  uploaded table paths. Review zero, negative, >256 and non-dividing counts
  explicitly in the original instructions; record input preconditions or quirks.
- [x] Verify brightness 0/64/65, absent/present transfer buffers, Sparse/Dense,
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

- [x] Restore the reference WIRE load-command semantics and Server Name,
  Instance Var and Server Version values. Keep generated instance classes in
  the normal Kernel Server rules, with version method returning 500.
- [x] Integrate main/header/data sources using preambles/postambles. Compile
  ATI_BIOS.m, ATI_BIOS16.s, ATIbios16.c and ATIbios.s before the kernel link;
  append their absolute object paths in observed text order after the generated
  instance object. Add dependencies so a clean
  build through the harness cannot silently omit the extras.
- [x] Write the dedicated POSIX-sh harness from existing guest build conventions.
  Use fresh target object/staging directories; record the exact command, flags,
  tool versions, object ordering and exit codes. Require a new artifact and
  complete package contents; do not accept an artifact left by an earlier build.
- [x] Build in the historical environment with `RC_ARCHS=i386 INCLUDED_ARCHS=i386`.
  Require compilation and kernel link success; resolve missing class/data/kernel
  imports in this project's declarations and integration before considering any
  shared infrastructure change. Verify companion version glue and generated
  VERS symbols, reporting expected build-text differences separately.
- [x] Execute the staged harness inside the historical i386 chroot. Require
  exit 0 and newly written outputs under `/build/out/i386/drvATIRage/`;
  the harness must report failure if compilation, link or resource staging fails.
- [x] Copy fresh results to ignored host output and hash them. Compare every
  packaged resource with the manifest. Commit as
  `drvATIRage: integrate the reconstructed driver build and resources`.

### Task 8: Close parity, source coverage and documentation

**Files:** Create `tools/binrecon/profiles/drvATIRage-i386-compare.json`;
finish RECON source-map/ledger/contract/checker, findings and the drvATIRage
entry in `src/drivers-i386/README` (preserving other existing edits).

**Interfaces:** Consumes the fresh Task 7 artifact. Produces the final comparison
summary, all 63 reviewed code-entry records, validated source ownership, ABI/data/
thunk/resource results and an accurate reconstruction/hardware status.

- [x] Create a comparison profile with both `${BINRECON_REFERENCE}` and
  `${BINRECON_REBUILT}`; IDA 9.4, i386/little-endian, normalized-functions
  acceptance, output `../out/drvATIRage-i386-compare`. Keep the reference-only
  profile intact. Set BINRECON_REBUILT to the freshly staged _reloc.
- [x] Run binrecon analyze and inspect `complete`, diagnostics and acceptance.
  The native-v3 run completed without diagnostics but normalized-functions failed;
  native-v12 also completes its full IDA comparison and still fails acceptance.
  The three color conversion helpers now match reference bytes after relocation
  masking. Twenty-seven paired bodies, including `_waitForFIFO` and
  `_waitForIdle`, still have byte differences, so the discrepancy-resolution
  item below remains open.
  The 2026-10-04 v86 refresh uses IDA 9.4 after filtering sign-extended
  out-of-range xrefs from the exactly-32-bit export and pairing interior offsets
  within identical single-byte strings. It also masks only IDA-identified i386
  absolute operands that encode uniquely paired string targets. It also masks
  read-only relocated data-pointer operands only when unique IDA relocation and
  symbol pairing prove their targets. The latest report records 51
  assembly-matched pairs, 10 different named pairs, and rebuilt-only
  `bios16_return`; acceptance still fails. The discrepancy-resolution item
  remains open.
- [ ] Resolve the remaining function discrepancies one by one. Verify call
  targets, control flow, constants, stack layout and access widths in IDA before
  changing source; rebuild after changes. Explain generated metadata separately.
- [x] Run `parity_check.py REFERENCE REBUILT`,
  `selector_check.py REFERENCE SOURCE_DIR`, and
  `import_check.py REFERENCE REBUILT KERNEL` with the actual intended kernel.
  No reference symbol/string/imports are missing or unresolved; selector missing,
  duplicate, and extra-source lists are empty. The 98 extra binary symbols are
  classified in the findings: typed aliases, Objective-C methods, compiler and
  assembly labels, generated methods, build paths/source labels, and one empty
  symbol-table entry.
- [x] Classify the 98 extra binary symbols in the parity report.
- [x] Run check_reconstruction.py with reference, reference analysis, repository
  root, rebuilt artifact and the final source map. Require all handwritten
  owners, exact class/category/ivar encodings and sizes, all static data and
  symbolic pointer targets, and relocation-aware comparison of the 117-byte
  transition routine and 203-byte thunk.
- [x] Regenerate the source map with binrecon source-map `--objc-methods` and
  validate using load_source_map with analysis and repo_root. The initial
  partition's expected outcome is 59 handwritten mappings and two explicitly
  generated omissions, plus the separately checked thunk. If IDA/scanner
  boundaries differ, reconcile evidence without reducing the denominator.
- [x] Review every handwritten body and advance ledger statuses only to the
  strength proven. The full semantic ledger remains bound to waitidle33; later
  native-v3 ABI/storage adjustments are recorded separately in findings. Save
  IDA names/types/comments and the database; generated outputs remain ignored.
- [x] Run only the meaningful checker tests affected by the final changes.
  Record binary hashes and tool versions. If ATI hardware/emulation is available,
  perform the spec's runtime cases with a temporary image; otherwise state that
  hardware execution remains unverified and do not substitute a VGA boot result.
- [x] Update findings and README with achieved gates and measured parity. Do not
  call the reconstruction complete while normalized-function acceptance or any
  other completion gate remains unmet. Commit after the remaining discrepancy
  and extra-symbol reviews are complete.

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

### Native resetEngine trials (2026-10-03)

IDA confirmed the reference `-[ATI resetEngine]` body is 122 bytes. Native v33
pinned its port to CX and value to EBX (134-byte body); v34 pinned only the value
to EBX (116-byte body). Both complete IDA 9.4/binrecon runs retained 24 paired
body mismatches and failed normalized-functions acceptance. The source experiment
was reverted to the byte-identical v31 source snapshot. See findings.md for
artifact hashes and details. The discrepancy-resolution and final acceptance
gates remain open.

### Native polling trials (2026-10-03, v35-v36)

v35 pinned the FIFO threshold and register base, but IDA showed a 65-byte body
versus the 52-byte reference. v36 changed the idle status read to a volatile
byte-pointer expression; GCC emitted the same load/test pair as v31, leaving a
75-byte body versus 73. Both full binrecon runs retained 24 paired body
mismatches and failed normalized-functions acceptance. Both source trials were
reverted. Details and artifact hashes are in reconstruction/findings.md.

### Native updateModeList and data-layout reconstruction (v37-v40)

The encoding selection now uses the reference-shaped switch, and the unsigned
memory comparison follows the reference operand order. Moving `_ValidModeList`
after the translation-unit code aligned it and the two mode-list symbols with
the reference addresses. v40 clears the masked-byte mismatches for
`updateModeList` and `setPendingDisplayMode`; paired-body mismatches are now 22.
All package/ABI/import/selector/data checks pass on v40, but normalized-functions
acceptance still fails. Findings.md records hashes and complete gate output.

### Native SetGammaValue register-order trial (v41)

A staged register-constraint experiment failed in the historical Objective-C
assembler with unresolved `L_OBJC_SELECTOR_REFERENCES_0..42`; no v41 binary was
produced. The source was restored exactly to the verified v40 snapshot. See
findings.md for the compiler diagnostic and current artifact identity.

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

### Native review update (waitidle33, 2026-10-03)

The active source ledger is bound to `_reloc` SHA-256 `E9911A1D5BAF839C15A341B9F6D372166AD5C12EE68B16D74EFA188E48606FF9`. A fresh IDA 9.4 comparison completes without diagnostics, but normalized-functions remains failed with 30 of 61 paired bodies byte-different after masking and one rebuilt-only `bios16_return` boundary. The ledger now has all 58 handwritten entries `control-flow-confirmed` and five generated/assembly entries `assembly-matched`; byte parity is still an independent open gate. Native rebuild was blocked because the configured QEMU guest panicked with `blkfree: freeing free block` and reset SSH on port 2121. No source sync/build completed in that attempt.
### Native v26-v30 update (2026-10-03)

Native v26 rebuilt the current source and completed the IDA comparison without diagnostics; 24 of 61 paired bodies still differ after relocation masking, plus the rebuilt-only `bios16_return` boundary. `waitForFIFO` was corrected to return the threshold and use the reference-shaped poll. Native v30 remains 60 bytes versus 52 in IDA and does not reduce the overall mismatch count. The v29 EAX register pin trial was reverted. Native v26-v30 snapshots are preserved in their versioned run directories. The full semantic ledger remains bound to v33 and was not rebound to v30 because the full source revision has not been re-reviewed. Native guest access is through the separate rescue VM; `vm.conf` is restored to port 2121 after each operation.
### Native v31 update (2026-10-03)

The v31 artifact hash is `0A0EFA71FE72FBD9055A5FDB27A8A3F820C45B7145AF854CCC67956B76345DAD`; binrecon completed without diagnostics and still reports 24 paired body differences plus `bios16_return`. `waitForIdle` uses a volatile bitfield at the GUI-status offset with an EAX-pinned base. IDA confirms the base-pointer and return flow now match; the compiler still emits a byte load/test instead of the reference direct memory test (75 bytes versus 73). The full ledger remains bound to v33 pending whole-source review.
### v32 rejected source trials (2026-10-03)

The EAX-pinned `waitForFIFO` trial produced a 63-byte body versus the 52-byte reference and was reverted. The DX-pinned `SetGammaValue` port-order trial failed native assembly/link with unresolved Objective-C selector-reference labels and was reverted. Current source SHA-256 `D09DB2E0482A62199CEB6922923E2E7FA06C24CC76AE2798AA63003AF7C9F188` exactly matches the source used by the successful v31 native build. v32 output is preserved but does not represent current source.

### Native follow-up v42 and v46-v51 (2026-10-03)

v42's `char gamma` type makes the gamma selection match the reference byte loads. A correctly staged v47 build further matched `enterLinearMode` exactly after relocation masking by preserving the CRTC pointer spill and reference-shaped pitch branch; paired masked-body differences fell from 22 to 21. v48's `__builtin_memcpy` for the 30-byte VGA CRTC record made `revertToVGAMode` masked-byte-equal and reduced the count to 20. v48 artifact SHA-256 is `AA39A988A0FA05F41D2A685B95D913659AE75C28BF2919284FE57DE77A6B29DB`; current main source SHA-256 is `B48CB0F553218C37D75A8F67E18E951662DFDB0E372E387709FC47184CF14579`.

The rebuilt checker, display-data validation, selectors, parity, and imports pass on v48; the native package build also checks its 41 resources. Normalized-functions acceptance remains failed with 20 paired masked-body differences, and ATI hardware/runtime remains unverified. v46's `doFill` register pinning increased body size and was reverted. v51's properly staged BIOS flag/register trial also increased body size and was reverted.

A native staging issue was corrected: sync must target `/build/source` with an explicit worktree `LocalRoot`, and the overlay must receive every changed source file before build. v43-v45 and v49-v50 did not evaluate their intended source edits and should not be cited as valid trials. The exact prior `vm.conf` contents (Port=2222) were restored after native runs.

## Native continuation (2026-10-03, v53-v60)

The selected live driver source is the v55 snapshot (SHA-256 `0A1B3B7D3B2F75197646F0132BAB7EFA809B56B70C981855EE8F1D546FB8D183`) and its native `_reloc` artifact is `9CD485EA4E69F32816C3B88793869E9FA4E2DDB9E76F5425D9B0BD8E00DA4D9E`. v53 made `doFill` masked-byte-equal and v55 made `waitForFIFO` masked-byte-equal. v60 `waitForIdle` assembly was rejected because IDA found call and CFG differences despite masked-byte equality; source was restored to v55.

On v55, selectors, symbol/string parity, imports, reconstruction contract, display-data checks and package resources pass. Strict normalized-functions acceptance remains open with 18 paired body differences plus the generated `bios16_return` boundary. ATI hardware/runtime verification is still outstanding. Native snapshots are retained under `tools/binrecon/out/drvATIRage-i386-compare/native-20261003-v55/`.

## Native continuation (2026-10-03, v61-v66)

v61 tested source-order movement for BIOS diagnostic tables. Although the signature literal reached the correct offset within `__cstring`, a 232-byte `__const` section precedes the rebuilt `__cstring` section, leaving its absolute address 192 bytes later than the reference. The trial was reverted. v62/v63 reconstructed `resetEngine`; v63 emits the reference's exact 122-byte instruction body, reducing paired masked-body differences to 17. The remaining CFG/layout finding is due to its different `__text` address. Selected v63 source SHA-256: `F5AA8956512BEC1654C43CFFA0FE5FAC8FDB93E33EB8FFEF4488D9EFD1628E14`; `_reloc` SHA-256: `DBECADBA37865251D327BD32C8BD3D40FE16797D7D3F35DD53ED55233EE947BF`.

The v64 external `_xxx_92` reference was rejected because it added an unresolvable import. v65/v66 register-pinned `SetGammaValue` attempts failed with historical compiler/assembler unresolved Objective-C selector references and were reverted. v63 selector, parity, import, source-contract, display-data and 41-resource package checks pass. Strict normalized-functions acceptance and ATI hardware/runtime validation remain open.

## Native continuation (2026-10-03, v67-v68)

v68 replaced SetGammaValue's source C register scheduling with an explicit i386 instruction body after v67 exposed unsupported +m operand syntax in the historical compiler. IDA confirms the exact 84-byte reference body, and the paired masked-body mismatch count falls to 16 when combined with the v63 resetEngine body match. The paired functions still differ in absolute __text layout. Current v68 source SHA-256: C7F37EC16AA715F1099683D00B29E070AD7192D6F18E3CF9256FC058B5BEB92A; native artifact SHA-256: 0DABC8A9AA0C06FF5DACB515E39387F5BABCBEE953EB26C76ED29D010D20863F.

Selectors, symbol/string parity, imports, reconstruction contract, display data, and the 41-resource package check pass on v68. Strict normalized-functions acceptance and hardware/runtime verification remain open.


## Native review update (v69-v76, 2026-10-03)

v69/v70 helper ordering mirrored the reference but left 16 paired masked-body differences. v71 pinned the receiver in `initFromDeviceDescription` to EBX; its body shrank from 1,806 to 1,705 bytes and the mismatch count fell to 14. v72's pinned EAX MMIO base was clobbered by `waitForFIFO` and was rejected by direct IDA inspection. v73's EBX-pinned PCI description local reduced `fixDeviceDescriptionForPCI` by 20 bytes but did not preserve two later BIOS body matches, so it was rejected.

Selected v75 reconstructs `initEngine` with the reference's receiver/info/width register use, reloads the MMIO base after each FIFO wait, uses the observed width-derived clipping bound, and emits the six-way pixel-depth jump table. IDA reports the same 566-byte method length as the reference; its body still differs in a register choice and placement, and paired masked-body differences total 16. v76's ECX-pinned clip local failed in the historical assembler with unresolved Objective-C selector references and was reverted. v75's source hash is `8559565050FC0D800EA915AD94BC5B609786C0889009D0A5160077C3D37D3546`; artifact hash is `2040E0581CF53B10475F7D66255781DB42BAFFEFF3ED2EBBA9A0100F06F2C20B`.

v75 passes selector reconciliation, symbol/string parity, imports, the 63-entry/12,267-byte reconstruction contract, display data (18 CRTC records/72 modes), and the 41-resource package check. Strict normalized-functions acceptance and ATI hardware/runtime verification remain open. The original `vm/vm.conf` bytes and Port=2222 were restored.
### Ledger binding note (v75)

The semantic ledger remains bound to rebuilt SHA-256 `E9911A1D5BAF839C15A341B9F6D372166AD5C12EE68B16D74EFA188E48606FF9`, while the selected v75 artifact is `2040E0581CF53B10475F7D66255781DB42BAFFEFF3ED2EBBA9A0100F06F2C20B`. The v75 comparison reports no ledger update. The old ledger therefore does not certify the v75 image. Rebind it only after reviewing every current source-to-reference function entry against v75.

### Native v77 rejection

The `setVGAMode:gamma:` flag-order trial built successfully in the i386 guest, but IDA measured a 161-byte body versus 153 bytes in the reference and showed a worse register/stack shape. It was rejected; live `ATI_BIOS.m` was restored to the v75 snapshot (SHA-256 `469E04A791F42CC1DE015E85C60C4B3194D0604DBFFC5EA396A1DC834FF86B68`). v77 artifact SHA-256 is `2E7C2AF2F598DF8F3F4C13D61857680CAA16D10CB41628132080AA0B5FFB6FBA`; this trial did not receive a full binrecon run and is not selected.

### Native follow-up: v78 PCI return-flow correction

IDA reference control flow and the DriverKit `IOReturn` declaration showed that `fixDeviceDescriptionForPCI:` had its success/error checks reversed. The source now enters relocation fallback on a nonzero `setMemoryRangeList:num:` result and stops probing after a successful candidate installation. Native v78 built and completed IDA/binrecon. The rebuilt method's pseudocode confirms the corrected behavior. Acceptance still fails: the fresh comparison reports 17 paired masked-body differences and unmatched `displayModeCount`, `displayModes`, and `bios16_return` boundaries. v78 hashes and remaining gates are recorded in `reconstruction/findings.md`.

### Native follow-up v84-v86 (2026-10-03)

The width-register sequence in `-[ATI initEngine]` now matches the reference exactly, and the v85 timeout literal is emitted into `__cstring`. IDA also exposed reversed PCI BAR masks; source now uses `0xFFFFFFFC` for I/O BARs and `0xFFFFFFF0` for memory BARs, matching the reference in v86. Binrecon now canonicalizes a direct call through a unique shared code symbol, matching `_ATIbios16`'s call to `__ATIbios32` despite its shifted address; duplicate target names remain a mismatch. Contract coverage, selectors, imports, and missing string/symbol parity pass on v86. The refreshed report has 20 differing function pairs, plus the rebuilt-only `bios16_return` boundary and one standalone relocation difference. Binrecon test suite: 991 passed, 4 skipped. Continue Task 8 by resolving the remaining discrepancies; do not mark reconstruction complete based on these intermediate gates. Current hashes and full counts are in `src/drivers-i386/video/drvATIRage/reconstruction/findings.md`.

### Native continuation attempt (2026-10-04)

Merged all four BIOS-probe and framebuffer failure paths in `-[ATI initFromDeviceDescription:]` into one logger. IDA shows the reference's two probe branches and map failure branch join at `_IOLog` `0x660`, with VRAM test failure falling through; v86 had separate probe calls at `0x21a` and `0x25b`. The source now has 9 direct `IOLog` sites, matching the reference's 9 call instructions. A fresh native build remains unverified: port 2121's guest panics; the rescue guest at port 46127 lacks installed private headers, and its GCC 2.7.2.1 rejects the current source's named-register variable syntax. The build harness now points at the synced driver subtree and can use staged `kernel-7` and `driverkit-3` include roots, but no artifact or comparison was produced. `vm/vm.conf` was restored to port 2121. Resume with the compatible compiler environment used for v86.

### IDA decompiler call-analysis repair (2026-10-04)

Candidate v86 could not decompile `-[ATI_BIOS createDataSegment:size:]` because `_IOLog` had a six-argument `__stdcall` type. IDA's extended failure data identifies `call analysis failed` at the logging call `0x2bbc`; the reference `_IOLog` type is variadic `int(const char *, ...)`. Applying `int __cdecl _IOLog(const char *format, ...);` to the candidate import fixes the call analysis. After saving the candidate database, a complete function sweep confirms 62/62 candidate functions and 61/61 reference functions decompile. This changes IDA metadata only and does not alter the v86 binary or comparison. The source-level shared error logger still needs a rebuild in a compatible native guest.

### Complete IDA pseudocode export and review (2026-10-04)

Saved complete pseudocode exports: candidate 62 functions / 60,255 bytes (SHA-256 `63CD3659E261B949F77F637F74FCAF915C80391452C69A6162FAA02D4D9C7EF9`), reference 61 functions / 60,815 bytes (SHA-256 `3170B0A5F4618DC7F93086876CD3D6BED0907EB1F59EFC2F061C53F054D418E6`). Side-by-side review of `_doBlit`, `-[ATI_BIOS setupCodeSegments]`, `-[ATI setGammaTable]`, `-[ATI setTransferTable:count:]`, and `-[ATI_BIOS setVGAMode:gamma:]` found equivalent behavior when accounting for register allocation, widths, endpoints, and conditions; no source change was justified.

### cc-791 native compiler experiment (2026-10-04)

The cc-791 bootstrap completed with exit status 0 in the rescue guest after building private Bison and temporarily linking it at `/usr/local/bin/bison`; cleanup removed the link. Stage 2 identifies as Apple cc-791 based on GCC 2.7.2.1, although the bootstrap's final output included `-: not found`. Both `asm("ebx")` and `__asm__("ebx")` named-register C probes fail parsing, so this compiler cannot build the driver's fixed-register source. No driver binary or comparison was produced. `/usr/bin/cc` was not modified. `vm/vm.conf` remains configured for port 2121; the separate rescue guest used port 46127.

### Private cc-771.4 guest probe (2026-10-04)

Booted the i386 bootstrapped image as a private QEMU snapshot on host port 46327. The Rhapsody 5.3 guest reports Apple cc-771.4 (GCC 2.7.2.1); a minimal `register void *x __asm__("ebx")` C probe failed with `syntax error, missing ';' after 'x'`. No driver build was attempted. The QEMU instance and temporary probe/log files were removed; the base image and `vm/vm.conf` were unchanged.

### BIOS descriptor store codegen and native guest probe (2026-10-04)

The current Binrecon report is the 10/04 00:48 root `published/comparison-ida.json`: 51 assembly-matched pairs, 10 different named pairs, and the rebuilt-only `bios16_return` boundary. `setupCodeSegments` already used a 16-bit store and a zero byte store for the thunk entry `0x2e48`, but v86's IDA pseudocode shows the optimizer folded those into a `strcpy("H.")` call. Both stores now use volatile lvalues to preserve width/order and avoid that folding. This source correction still requires a native build.

A private QEMU `-snapshot` of `vm/work/eide-ne2k-sshd.img` reached kernel startup, but host port 46427 returned no SSH server banner. The VM and temporary logs were removed; its base image and `vm/vm.conf` were unchanged. The native compiler/build environment remains unresolved.

### Current unbuilt source binding (2026-10-04)

After the shared initialization failure logger and the volatile GDT descriptor stores, current source SHA-256 values are `ATIRageDisplayDriver.m` `DAC294D40271F3C74BEE3861E74C4F38EA0F8FE4FE9901C9AE22D671D9A68F64` and `ATI_BIOS.m` `6423DA4E01F3CA7038D3811B15BE6DDE26B2EAD082C836D9413978CEA49B772B`. They are not represented by v86; its 51/10 comparison cannot validate these edits until a fresh native package is built.

### Native reconstruction checkpoint v89 (2026-10-04)

The current source builds and stages natively with the private Rhapsody 5.3 i386 snapshot guest and `vm/build-i386-atirage.sh`. The native-only shim supplies the absent `machdep/i386/features.h`; product sources remain shim-free. The v89 package has 41 resources, a 34-byte companion, and `_reloc` SHA-256 `94E003860FEE0B80A60C3C7062CD1BA4B93C7500392842B7C756629544DAED70`. Fresh IDA 9.4 analysis completes without diagnostics. The reconstruction contract and all nine checker tests pass. Strict `normalized-functions` still fails with 51 assembly-matched pairs, 10 different named pairs, the rebuilt-only `bios16_return` boundary, 9 call findings, 10 CFG findings, 20 function-range-byte findings, 10 instruction-shape findings, one missing-reference-function finding, and one standalone relocation difference. We tried intrinsic and constrained-assembly forms for the display-info copy; both changed unrelated function layout or produced worse comparison results and were reverted to the source's `bcopy`. This remains an open Task 8 gate. The ATI hardware/runtime gate also remains unavailable under generic QEMU graphics. The current semantic ledger is rebound to the v89 `_reloc` hash.

### Native reconstruction checkpoint v91 (2026-10-04)

Changed the `__bios16` return point from named `bios16_return` to a numeric local label (`1:`/`1f`), preventing IDA from creating a spurious function boundary inside the mixed-mode thunk. The checker recognizes the equivalent target at `__bios16 + 100` and passes its 63-entry/12,267-text-byte contract. Rhapsody 5.3 i386/cc-771.4 built and staged 41 package resources, the 34-byte companion, and the 224,668-byte relocatable. v91 `_reloc` SHA-256: `96A0EC5DFEDE7174038BED0C366C1BA1396B2840CA70ACD6937856A08A8A7E33`.

Fresh Binrecon with IDA 9.4 completes without diagnostics. Candidate and reference inventories each contain 61 functions; `bios16_return` is absent. A direct Hex-Rays sweep decompiles all 61 functions on both sides. Complete v91 pseudocode exports are saved under `tools/binrecon/out/drvATIRage-i386-compare/native-20261004-v91/ida-run/published/` (rebuilt 56,195 bytes, reference 58,422 bytes). Direct IDA disassembly verifies `__bios16` at `0x2ddc`, local return at `0x2e40`, and the `lret` epilogue; the `_ATIbios16` decompilation retains the range check, selector/offset setup, 32-bit thunk call, and return values. Strict `normalized-functions` remains failed with 51 assembly-matched pairs and 10 different named functions. The findings are 9 calls, 10 CFG, 20 function-range bytes, 10 instruction shapes, 18 section-layout differences, and one standalone relocation-collection difference. The ledger remains bound to the v89 checkpoint until strict acceptance is reached. ATI hardware/runtime validation is still open.

## Native reconstruction checkpoint v94 (2026-10-04)

The private Rhapsody 5.3 i386 / cc-771.4 guest built the current source after two focused edits. `setupCodeSegments` now computes the thunk descriptor base from the linked `_bios16` symbol; a v94 IDA instruction check confirms the expected `0xC0000000 + __bios16` constant and rejects the stale `0xC0002E48` address. `createDataSegment:size:` now stores the descriptor limit in both branches while preserving the existing granularity calculation. `fixDeviceDescriptionForPCI:` no longer zero-initializes the two PCI BAR output locals before `getPCIConfigData`, matching the reference's output-parameter usage; its native body shrank by 20 bytes (v93: 1,563 bytes, v94: 1,543 bytes), but still does not assembly-match.

The v94 package staged 41 resources and the 34-byte companion. `_reloc` is 224,704 bytes with SHA-256 `21A68DCFCDDDBC6D422014367C0CFA1932B141CBB6508C06678A48F6D36B96812`. The companion SHA-256 is `A7E0D0CCD8AE99248A14742A08B7D3BF97A4A850745265EFC17373D8D338683E`. Native build output is retained under `tools/binrecon/out/drvATIRage-i386-compare/native-20261004-v94/`.

Fresh Binrecon with IDA 9.4 completes without analyzer diagnostics; reference and candidate each contain 61 functions. A full Hex-Rays sweep decompiles all 61 candidate and 61 reference functions with zero failures. Pseudocode exports are saved as `ida-run/published/pseudocode-rebuilt-ida.txt` (56,743 bytes) and `ida-run/published/pseudocode-reference-ida.txt` (57,660 bytes). The candidate IDA database also has the corrected variadic `__cdecl` `_IOLog` type saved, which resolves the prior decompiler call-analysis failure without changing the binary.

The reconstruction checker passes: 63 code entries and all 12,267 `__text` bytes are accounted for. The descriptor regression passes. `normalized-functions` remains false with 51 assembly-matched pairs and 10 different named pairs; the same 9 call, 10 CFG, 20 function-range-byte, and 10 instruction-shape findings remain, along with 18 section-layout differences and one standalone relocation-collection difference. The focused parity check still fails for `fixDeviceDescriptionForPCI:` and `createDataSegment:size:` (the latter remains 186 bytes versus the 212-byte reference). The semantic ledger stays bound to v89. Strict parity and ATI hardware/runtime verification remain open; generic QEMU graphics cannot validate the ATI BIOS path.


### Native reconstruction checkpoint v98-v99 (2026-10-04)

v98 preserves the volatile descriptor access-byte self-store in `-[ATI_BIOS createDataSegment:size:]`. The focused IDA instruction-pattern regression passes, and the full IDA sweep decompiled all 61 candidate and all 61 reference functions; candidate pseudocode is retained under `tools/binrecon/out/drvATIRage-i386-compare/native-20261004-v98/ida-run/published/`. The v98 `_reloc` is 224,668 bytes (SHA-256 `8109AB49C1ACA0B02394AD88348DA4262C6A277B35FB6077125D588D73423938`).

v99 moved the large-limit granularity-bit write after rounded-limit calculation to match the reference instruction order. Its `_reloc` is 224,668 bytes (SHA-256 `232910FC5015655E745F920DCA664F6B1E1F5F63F0E172D9B183060E9E3B6721`). Native build staged 41 resources. Binrecon/IDA completes, and a direct Hex-Rays sweep decompiles 61/61 candidate functions with no failures; the candidate IDB and pseudocode export are retained under the v99 run directory. The reconstruction contract, 18 CRTC/72 mode display-data check, and self-store regression all pass.

Strict `normalized-functions` remains failed: 51 pairs assembly-match and the same 10 named methods differ. v99 reports 9 call, 10 CFG, 20 function-range-byte, and 10 instruction-shape findings, plus 18 section-layout differences and one standalone relocation difference. The branch-order change did not reduce these counts; the remaining `createDataSegment:size:` difference is now limited to CFG/byte-range/instruction-shape findings, with its descriptor self-store matching. The semantic ledger remains bound to v89 pending complete source review and strict acceptance. ATI hardware/runtime verification remains open.


### Native reconstruction checkpoint v101 (2026-10-04)
The v101 native build separates the saved data-segment descriptor pointer from the pointer used for descriptor writes. IDA shows the reference-shaped save and GDT reload; `createDataSegment:size:` is now 210 bytes versus 212 in the reference (v99 was 198). The 224,716-byte artifact is at `D:\temp\drvatirage-v101\package\ATIRageDisplayDriver.config\ATIRageDisplayDriver_reloc`. The reconstruction contract, display-data check and self-store regression pass. Binrecon still reports 51/61 assembly-matched methods and normalized-functions failure; the nine call findings remain. The verified source change is in the current worktree.


### Native reconstruction checkpoint v103 (2026-10-04)
The v102 `setVGAMode:gamma:` source-order experiment was rejected: native output stayed 157 bytes versus 153 reference, with the same 10 differing methods. v103 instead makes the six descriptor-byte self-stores in `setupCodeSegments` volatile. The exact v103 source is 20,748 bytes (SHA-256 `7D15566A3F9F1DFE042CA119C62C2A6F05AB1D804B6CF66F4772DE1244D8524B`) and is applied to the worktree.

The fresh native i386 build staged 41 resources. `_reloc` is 224,788 bytes (SHA-256 `931027FAF793B3FB0663F2DC630861CD36C90B2F2DC149368A4D37A77E044E48`). IDA 9.4 analyzed all 61 reference and 61 rebuilt functions without diagnostics. `setupCodeSegments` is 383 bytes versus 388 reference, and the volatile self-stores are present; strict normalized-functions remains false with 51/61 assembly-matched pairs and the same 10 differing methods. Contract validation passes for 63 code entries / 12,267 text bytes, and display data matches all 18 CRTC records / 72 modes. The semantic ledger remains pinned to v89; ATI hardware/runtime verification remains open. Analysis and package are retained at `D:\temp\drvatirage-v103-exact`.


### Native experiment v104 (2026-10-04)
A native trial changed `shortQuery`'s BIOS register buffer to `unsigned short registers[24]` to mirror IDA's reference stack view. The v104 build staged 41 resources and IDA analyzed all 61 functions, but the method remained 206 bytes / 75 instructions versus 202 / 74 in the reference, and all 10 function mismatches remained. The trial was discarded; the worktree stays on v103. Artifact and analysis are retained at `D:\temp\drvatirage-v104`.

### Native continuation checkpoint v105-v106 (2026-10-04)

Exact Hex-Rays review found a source correctness bug in `setupCodeSegments`: an uninitialized local, not the allocated BIOS stack, was saved in `priv[8]` and passed to `bzero`; the allocation pointer was also used as the GDT descriptor base. Both `ATI_BIOS.m` copies are corrected to save and clear the allocated stack pointer, derive its linear base, and address the descriptor at `gdt + ATI_BIOS_STACK_SELECTOR`. v105 was built natively and directly decompiled across all 61 functions. v106 folds a rounded-limit temporary into `createDataSegment:size:`; the body approaches the reference size (211 vs. 212 bytes) but retains an instruction-count difference (62 vs. 64), and strict normalized-functions remains false at 51/61 matching pairs. Both builds pass the reconstruction contract; hardware runtime remains unverified. Exact build identities and validation evidence are in `src/drivers-i386/video/drvATIRage/reconstruction/findings.md`.

### Native continuation v107-v111 (2026-10-04)

Executed compiler-shape experiments in the private Rhapsody 5.3 i386 / cc-771.4 guest. EAX/EDX register pins (v107-v110) did not reduce the 10-function mismatch list; the v110 variant added instruction-layout/semantics findings in `createDataSegment:size:` and was rejected. Both `ATI_BIOS.m` copies now use the merged `limit` form without register pins (source SHA-256 `A724A354016A0A1090EE8B347B96C6C3E2F07F75C72AE6D06D507B7759CAF947`). The current v111 native `_reloc` is 224,768 bytes (SHA-256 `3915BE3AEB4252572C1EB4A289D3BAC7BC57485AFF36B9950DEDE5AE854EE848`) and is retained at `tools/binrecon/out/drvATIRage-i386-compare/native-20261004-v111/`.

v111 passes reference-contract coverage (63 code entries / 12,267 text bytes), display data (18 CRTC records / 72 modes), and the 41-resource manifest. Fresh IDA/Binrecon analyzes 61 functions on both sides without diagnostics; 51 assembly-match, 10 differ, and `normalized-functions` remains failed. Candidate `createDataSegment:size:` is 208 bytes / 63 instructions versus 212 / 64 in the reference. A direct Hex-Rays sweep of the exact v111 candidate and reference decompiles all 61 functions per side with zero failures. Exports and SHA-256 identities are recorded in `src/drivers-i386/video/drvATIRage/reconstruction/findings.md`. Review of the remaining four mismatch methods supports source-level equivalence, but does not close the strict normalized-function gate. The semantic ledger is still pinned to v89, and ATI hardware/runtime execution remains unverified. Continue Task 8 against the ten-function list rather than declaring reconstruction complete.

### Task 8 continuation checkpoint v112-v117 (2026-10-04)

Native v112 needed a one-file header resync after a staged `ioPorts.h` was found to contain binary bytes. The build then succeeded. Later repeated guest writes corrupted that VM overlay; a fresh overlay reported disk write errors at boot. Both were stopped after verifying their QEMU process identity and QMP endpoint. The v118 source experiment was not built and has been reverted; current source corresponds to verified v117.

v114's EDX-pinned rounded limit and byte-sized high nibble make `createDataSegment:size:` match the reference instruction sequence in IDA. v117's separate byte temporaries for `setVGAMode:gamma:` likewise match the reference. The exact v117 candidate is 224,944 bytes, SHA-256 `E92E3F4ECFA1019E9EDD18AE53696CC295A80DBF95F4BDE573C5BF0431D0D689`. Fresh Binrecon is complete, with 61 functions per side and 8 differing named functions; `normalized-functions` still fails. The remaining methods and full analysis details are listed in `reconstruction/findings.md`.

The v117 IDA sweep decompiles all 61 reference and 61 candidate functions with zero failures. The reconstruction checker accepts all 63 code entries / 12,267 text bytes. Parity has no missing symbols or strings; selector validation has no missing, duplicate, or extra source selectors; import validation finds 24 imports on each side with no unresolved imports against the checked kernel. The semantic ledger remains pinned to v89. Task 8's one-by-one discrepancy review and strict parity gate remain open; ATI hardware/runtime execution is unverified.

### Native continuation v118-v121 (2026-10-04)

Native execution resumed in a fresh C:-hosted QEMU overlay after validating and flattening the v107 base image. v118-v121 are native compiler-shape experiments for `setGammaTable`. Separate loop counters plus explicit ESI/EBX register variables reproduce the reference transfer-loop register allocation. The v121 source is the current source state; its `setGammaTable` pseudocode is behaviorally aligned with the reference, but condition lowering and branch layout still prevent normalized instruction/CFG parity.

The v121 native package stages all 41 resources. `_reloc` is 224,960 bytes (SHA-256 `0B1C1FF84B6434E0E6AA7D46A59E7164D48D8A391417247BEAFEB40C78FFE533`). Fresh IDA 9.4/Binrecon completes with 61 functions on each side; direct Hex-Rays decompiles all 61 candidate functions with zero failures. Strict `normalized-functions` remains false with the same eight methods listed above; the report has 16 function-range-byte, 8 call, 8 CFG, and 8 instruction-shape findings.

The reconstruction contract, selector check, and import check pass. Symbol/string parity has no missing entries and reports 97 extra generated/debug symbols or strings. The ledger remains pinned to v89 pending strict acceptance. ATI hardware/runtime verification is still open.

### Native continuation v127-v134 (2026-10-04)

v127-v128 close the normalized `shortQuery` discrepancy by matching EBX buffer retention and byte-width EAX reads. v130 brings `_doBlit`'s unsigned absolute-difference operations closer to the reference `neg` sequence; input-register pinning was rejected. v133-v134 improve `setTransferTable` by widening shifts and casting channel bytes to unsigned values, yielding the reference `shr` instructions. Trials v129, v131, and v132 did not improve the strict comparison and were reverted or retained only when equivalent.

The current v134 artifact is 225,180 bytes (`BA7FE941A5333AD555A2C0BB6465E703AC73ACCDCFC4C0DA7D412A2480748B7B`). All 61 functions decompile; contract coverage, selector mapping, import parity and symbol/string coverage pass. Strict normalized-function parity remains open with seven differing methods. Continue one-method-at-a-time against the retained Binrecon/IDA evidence. The semantic ledger remains pinned to v89; ATI-specific runtime verification is unavailable in the generic QEMU guest.


### Task 8 continuation checkpoint v149-v150 (2026-10-04)

Native v149 corrects the resolution-129 CRTC register slots: IDA confirms EBX.low=0 at register-buffer offset 8 and EDX.low=0x88 at offset 16. An isolated v150 structure-assignment experiment for the display-info copy was built and compared, regressed code findings from 39 to 69, and was reverted.

IDA decompiled all 61 functions on both the reference and restored v149 candidate with zero failures. Side-by-side review confirms the current seven different function records reflect call-site/CFG/instruction layout, `bcopy` lowering, relocated thunk/data addresses, and register choices; no new semantic mismatch was identified. The reference contract covers all 63 entries / 12,267 text bytes; generated display data, all 41 resource hashes, 50 selectors (48 source + 2 generated), and 24 imports pass. Strict `normalized-functions` remains failed, so Task 8 is still open. The ledger and findings record the v149 evidence. ATI hardware/runtime behavior remains unverified.


### Task 8 continuation checkpoint v151 (2026-10-04)

A native `_doBlit` horizontal-branch spelling trial moved one branch encoding closer, but retained the function mismatch and regressed the whole comparison: 39 to 43 code findings and 7 to 9 differing function records. Reverted to the byte-verified v149 main source. Strict normalized-function acceptance remains open.


### Native continuation v152 `setTransferTable:count:` condition-shape trial (2026-10-04)

Rewrote the DAC/ASIC branch conditions as one short-circuit expression and rebuilt the i386 package natively. The v152 package shrank by 60 bytes to 225,372 bytes. Fresh Binrecon/IDA completed, but code findings stayed at 39 and the same seven function records remained different; `setTransferTable:count:` still has call/CFG/range/shape findings. Reverted the source to the byte-verified v149 state (SHA-256 `7AA87BDD7BC25A81F14FC42111ABB4AA32BEF52E9A5899FCD925E33E7113E6EE`). Strict normalized-function parity remains open.


### Native continuation v153-v154 BIOS store-order trial (2026-10-04)

The first v153 comparison is invalid as an isolated experiment because the guest retained the v152 `ATIRageDisplayDriver.m` while only the BIOS file was synced. Its artifact is retained for traceability but is not baseline evidence. For v154, synced both build inputs and reversed the two independent resolution-129 register stores in `loadCRTC_comm`. The native package is 225,432 bytes, SHA-256 `37B13107338173701FF6725CE694D472FC05241A31517C8E6372370034519CD9`. Fresh Binrecon/IDA completed with no diagnostics; it reports the same 39 code findings and same seven different function records as v149, including `loadCRTC_comm`. The ordering change was reverted and both source files were re-synced to the v149 baseline. Strict normalized-function parity remains open.


### Native continuation v155-v156 `setGammaTable` compiler-shape trials (2026-10-04)

v155 replaced the hand-written `SetGammaValue` inline assembly and private counter with DriverKit `outb` calls. IDA confirms that the three `outb` delay-counter references are now shared by `SetGammaValue` and `setGammaTable`, matching the reference's cross-function use pattern. Its native package is 226,168 bytes, SHA-256 `44EADA289F9161290AAA46D2327F5A0C88612B249F0323156E6F279A38651CDE`. Binrecon/IDA completed, but the overall comparison regressed from 39 to 44 code findings and from seven to eight different functions; `_SetGammaValue` became an additional differing function because its local BSS target moved. Reverted this source shape.

v156 materialized `[self displayInfo]` in a local pointer to try to order stack cleanup before the color-depth load. The native package is 225,472 bytes, SHA-256 `34438A401DFF5989C7D84101C16C817906EEE7D3461BA6F2D069A3E7F11DC90E`. Fresh Binrecon/IDA has the same 39 code findings and seven differing functions as v149; the targeted instructions remained in the same order. Reverted the experiment and synced both sources to the v149 baseline hashes (`ATIRageDisplayDriver.m` `7AA87BDD7BC25A81F14FC42111ABB4AA32BEF52E9A5899FCD925E33E7113E6EE`; `ATI_BIOS.m` `D90734E97CF66BCF967DA14BCFAFFF8F9699B38B6C7B84C9A870B716CD6B2EC4`). Strict normalized-function parity remains open.

### Native continuation v157-v160 `_doBlit` assembly reconstruction (2026-10-04)

v157 replaced the C body with a top-level assembly transcription. It built natively (224,476 bytes; SHA-256 `3EA228A191711A0187800EA1C30FB7FB23BB4B9B90BBC192700D1FA6DF2C1B2D`), but the assembler treated named `.LdoBlit_*` labels as function starts; IDA reported 68 functions, and strict code findings increased to 46. v158 switched to numeric local labels. IDA then recovered `_doBlit` as one 330-byte function with 94 instructions versus the reference's 322-byte/94-instruction function; code findings were 40. Inspection found the shared reverse-Y entry was one instruction late and the whole routine was emitted before its FIFO helpers, changing call targets.

v159 moved the assembly after the wait helpers and corrected the reverse-Y shared entry. Its `_doBlit` now has 94 instructions and 15 blocks, matching the reference counts; the body is 321 bytes and begins one byte after the reference. Calls target helper addresses four bytes later. The complete binary regressed to 83 code findings, so this handwritten assembly was rejected. Restored `ATIRageDisplayDriver.m` byte-for-byte to v149 SHA-256 `7AA87BDD7BC25A81F14FC42111ABB4AA32BEF52E9A5899FCD925E33E7113E6EE` and rebuilt on the native guest. The v160 restored-source artifact is 225,432 bytes, SHA-256 `08E0E18CA94059D98F7FBE4888F8513F3DFE0AC76DD158178114E83C6B6C3DBC`; fresh IDA/Binrecon reports 61 functions, 39 code findings, and seven different function records, returning to the v149 comparison baseline. Strict `normalized-functions` acceptance remains open.

### Native continuation v167-v169 `loadCRTC_comm` register trial (2026-10-04)

v167 split the gamma flag into an AL-pinned byte and the final flags into a separate byte. IDA shows the code reaches the reference's `xor al,al` and `mov al,10h` sequence, and the method keeps 258 bytes with matching calls and CFG. However, the later AL/DL assignments and other instruction semantics still differ; total code findings regressed from 39 to 51. v168 additionally pinned the final byte to DL and the resolution low word to ECX, but the native compiler failed while compiling `ATI_BIOS.m`; that source was reverted to the v162 accepted state.

After restoring both build inputs on the guest, v169 rebuilt the exact local source state: main driver SHA-256 `7AA87BDD7BC25A81F14FC42111ABB4AA32BEF52E9A5899FCD925E33E7113E6EE` and nested BIOS source SHA-256 `1FD9D3CCB122CD60250FBA25122FF21FC8B256B3D7416A92232F797B65CE7AAD`. The 225,468-byte candidate was freshly analyzed by Binrecon/IDA across 61 functions and returns to 39 code findings / seven differing function records. Strict `normalized-functions` remains false. `vm/vm.conf` Port is restored to 2121.
### Native continuation v170 `loadCRTC_comm` fixed-register trial (2026-10-04)

Pinned the gamma flag to AL and final mode flags to DL. Native compilation succeeded and the targeted method's call graph and CFG now match the reference, but instruction comparison still reports ten semantic differences and total code findings rise from 39 to 50. Reverted to the v162 accepted source. The guest was resynced with the restored main/BIOS files and rebuilt successfully; source hashes and `vm.conf` port are verified at the v169 accepted state. The latest verified Binrecon report remains 61 functions / 39 code findings with strict `normalized-functions` failed.
### Execution update v173-v179 (2026-10-04)

v177 refined the PCI method's initialization, BAR scratch use, config-table guard, and direct method-argument use. Its frame size matches the reference at `0x108`; the full candidate is 225,504 bytes with 61 analyzed functions, 39 code findings, and seven differing functions. Two follow-up source-shape trials were rejected: v178's pointer locals reduced the frame to `0x100`, and v179's outer do-while loop left the global comparison unchanged at 39 findings. Both were reverted; continue from v177. Strict normalized acceptance remains open.
### Execution update v180-v182 (2026-10-04)

The restored v177 native rebuild re-analyzed cleanly: 61 functions, 39 code findings, seven differing functions, with regenerated build metadata changing the whole-file hash. v181 switched the PCI range buffers to their actual `IORange` struct type; the PCI method remains `0x108` frame and is 1,583 bytes versus 1,632 in reference. v182 initializes memory count from port count as the reference pseudocode does; it produces the same function shape. Keep this typed-range source as the current best reconstruction. Strict normalized acceptance remains open.

v183 tried explicit pointers to both typed arrays but reduced the PCI method to a `0x100` frame and 1,447 bytes, while preserving the 39-finding total. Reverted that layer and resynced/rebuilt the v182 typed-array source on the guest.

### Native continuation v184-v187 inline I/O counter investigation (2026-10-04)

The v187 restored-source build completed natively at 225,516 bytes. Fresh Binrecon/IDA processed 61 functions and confirms 39 code findings across the same seven differing methods as v182; strict `normalized-functions` acceptance remains false. The rebuilt image hash is `AE25FD0B0CFF15B754246EFAED5A673BE5278CB08EF1E041783187CF8C248E57`. Source currently contains typed `IORange` buffers and `memoryCount = portCount`; its SHA-256 is `5FD6BBB271BE3D086398EED40E54E6D0D32909EC0B231951C080D615CBFB02B4`.

IDA shows the remaining counter mismatch is source-level: reference `setGammaTable` and `_SetGammaValue` both increment `_xxx.8` at `0x6b60`, while the candidate `setGammaTable` increments `_xxx.86` at `0x6b50` and `_SetGammaValue` increments its private counter at `0x6b60`. Reference `initFromDeviceDescription:` and `resetEngine` both increment `_xxx.92` at `0x6b5c`; candidate init uses `_xxx.92` at `0x6b58` while resetEngine uses a private counter at `0x6b5c`.

v184-v186 tested DriverKit inline I/O and fixed-register variants. v184 produced 101 code findings / 27 different function records (227,804 bytes), so it was rejected. v185 and v186 each produced 46 code findings / nine different functions (227,992 and 227,816 bytes respectively); cross-function counter sharing improved, but generated code shape and counter addresses remained wrong. These trials were reverted. Next isolate the gamma counter issue by directing the three DAC `outb` operations and `_SetGammaValue` to the same existing counter at `0x6b60`, then compare the native output before touching PCI/BIOs mismatches.

### Native continuation v188-v190 shared I/O counter reconstruction (2026-10-04)

v188 replaced `setGammaTable`'s three DriverKit `outb` calls with inline writes that increment the same existing `setGammaValueWriteCounter` used by `_SetGammaValue`. This routes both functions to `0x6b60`, matching the reference `_xxx.8`; Binrecon code findings fell from 39 to 35. The v188 image is 225,136 bytes. The function still differs in instruction/register shape, but call graph and CFG match.

v189-v190 routed all four `initFromDeviceDescription:` port writes through the existing `resetEngineWriteCounter` at `0x6b5c`, matching the reference `_xxx.92` shared by init, `resetEngine`, and the register-window write. IDA confirms the candidate's `0x6b58` `_xxx.92` is now unused, while every relevant candidate write targets `0x6b5c`. Binrecon remains at 35 code findings / seven different methods; strict `normalized-functions` is still false. Keep the shared-counter helpers because IDA confirms the reference counter identities and addresses. Current v190 image is 224,532 bytes, SHA-256 `D8F6AF0465257CCE8BCBE6BC999EE8B72900DDFAC04AE3242C14F91D33EF76FA`; main source SHA-256 is `218158EFDA03C4EA65F18ACAA3CC3B2B3016456C42609C53935B92180367ADFE`. `vm.conf` has been restored to Port 2121.

### IDA full-decompilation audit and remaining code-shape gaps (2026-10-04)

On v190, IDA 9.4 Hex-Rays produced pseudocode for all 61 reference functions and all 61 candidate functions with zero failures. A focused pseudocode review found `setTransferTable:count:` behavior equivalent on both sides, and `loadCRTC_comm` has the same return and BIOS-call behavior; its visible pseudocode difference is the compiler's temporary register choice (`AL` versus `DL`).

The `setupCodeSegments` descriptor difference is a linked-address consequence rather than a hard-coded source error: the reference's `__bios16` entry is `0x2e48`, while the candidate's actual entry is `0x2e74` (44 bytes later). Both source forms use the symbol for the entry and construct the descriptor from that address. The candidate `_ATIbios16` entry is also 44 bytes after the reference (`0x2eec` versus `0x2ec0`), reflecting preceding text-layout differences. Preserve symbolic addressing; do not force the reference constant into the candidate, since that would point at the wrong entry. Strict normalized-function acceptance remains false because seven function bodies still differ in instruction/register/control-flow shape.

IDA 9.4 pseudocode exports for both sides are now preserved at `reconstruction/ida/reference-pseudocode-v190.md` and `reconstruction/ida/rebuilt-pseudocode-v190.md` (61 functions each). This makes the complete decompilation reviewable independently of the generated Binrecon output directory. The seven strict comparison gaps remain open; continue method-by-method from these exports and IDA disassembly, retaining source changes only when the native comparison improves without changing behavior.

### Native continuation v191-v192 `setGammaTable` register-order trial (2026-10-04)

v191 pinned the `[self displayInfo]` result to EDX and split the indexed depth read into two C statements, attempting to move `add esp, 8` before the field load as in the reference. The native build succeeded at 224,572 bytes, but IDA showed the instruction order was unchanged; Binrecon remained at 35 code findings / seven methods. Reverted to the v190 source (main file SHA-256 `218158EFDA03C4EA65F18ACAA3CC3B2B3016456C42609C53935B92180367ADFE`). A fresh v192 native build and Binrecon run reproduced the same 35 findings; the guest now matches the restored workspace source and `vm.conf` Port is 2121.

The v192 IDA size map is saved at `reconstruction/ida/function-size-map-v192.md`. It captures the remaining seven function size deltas and the linked `__bios16` entry addresses. Use it to prioritize work on whole-function reconstruction; byte-count adjustments alone are not sufficient for strict acceptance.

### Follow-up review checkpoint (2026-10-04)

IDA review of v192 confirms `initFromDeviceDescription:` cleanup/return paths and `fixDeviceDescriptionForPCI:` resource/PCI operations match the reference behavior. Saved comments in both IDBs and recorded evidence in `reconstruction/findings.md`. The native source and binary are unchanged; v192 remains the current baseline at 35 code findings across seven methods. Continue reviewing the remaining method pairs and make source changes only when backed by a concrete behavioral discrepancy or a native comparison improvement.

### Native trial v193 and restored rebuild v194 (2026-10-04)

Tested a 32-bit volatile PCI success local with explicit zero assignments on both error returns. The v193 native body grew by 9 bytes and left global code findings unchanged at 35 across seven methods; reverted it. Rebuilt the restored source as v194 and ran fresh Binrecon/IDA: 61 functions decompile on each side with zero failures, PCI method returns to 1,583 bytes, and normalized-function parity remains false. v194 `_reloc` hash: `6CB08D60398CCD45992A2A0124B23461426CD789C9E73BE34A60C7CC1847C7D9`; source hash: `2F27CEACE685DC3AEC521072E2D45B640AC4A53D153046638A72573DE6E542B2`; VM port restored to 2121. Continue discrepancy review from v194.

Direct v194 IDA review of `setGammaTable` confirms its data path, DAC write order, counter, loops and return match the reference; only the stack cleanup instruction crosses the independent bits-per-pixel load. `_doBlit` matches overlap handling, coordinate/direction selection, FIFO waits, MMIO order/restoration and return. Both are annotated in the reference and v194 candidate IDBs. Strict instruction-level acceptance remains open.

### Native continuation v194 full seven-function review closeout (2026-10-04)

Reviewed the remaining v194 method pairs in IDA. `setTransferTable:count:` selects the same DAC shift, allocates and fills the same three channel tables for grayscale/RGB modes, frees the table on unsupported depth, and invokes `setGammaTable`; differences are temporary allocation, register, and statement-order choices. `setupCodeSegments` saves/restores and constructs the same GDT descriptors; the candidate's `strcpy("t.")` emits the relocated `__bios16` address, so forcing the reference's linked immediate would be incorrect. `loadCRTC_comm` preserves the same initialization and resolution guards, command/data-segment setup, BIOS invocation, status logging, and return codes; the noted `AL`/`DL` temporary choice is compiler allocation.

All seven methods reported by v194 are now reviewed against the reference in IDA: `initFromDeviceDescription:`, `fixDeviceDescriptionForPCI:`, `_doBlit`, `setGammaTable`, `setTransferTable:count:`, `setupCodeSegments`, and `loadCRTC_comm`. No further behavioral source correction is supported by the evidence. Function comments for the three reviewed pairs were saved in both reference and v194 IDBs. The v194 output retains full decompilation for all 61 functions on both sides; strict normalized-function acceptance still fails with 35 findings across these seven functions. No native source change was made in this review.


### Native continuation v195-v196 volatile display-info ordering trial (2026-10-04)

The native i386 build and package checks passed: 41 resources, relocatable driver present, companion `__text` is 34 bytes. The v196 driver is 219,972 bytes (SHA-256 `1DD12BD1A1107353B151780863EA283440351B074CF8435EC464AB5DD66D37E5`). Fresh Binrecon/IDA completed all 61 function pairs and stayed at 35 code findings / seven different methods, with the standalone relocation difference still present. IDA shows the volatile pointer adds a local store/reload but leaves the field dereference before `add esp, 8`, so this trial is rejected. Restored the exact v194 main-source bytes (SHA-256 `2F27CEACE685DC3AEC521072E2D45B640AC4A53D153046638A72573DE6E542B2`); `vm.conf` remains on Port 2121. Saved the candidate and IDA/Binrecon evidence in `tools/binrecon/out/v196-native-finished/`. Do not repeat volatile pointer materialization for this cleanup-order mismatch. Strict normalized-function parity and hardware/runtime validation remain open.

### v194 complete decompilation audit and range map (2026-10-04)

Reopened the hash-verified v194 database in IDA 9.4 and directly decompiled every candidate function. All 61 completed with zero failures. Saved `reconstruction/ida/rebuilt-pseudocode-v194.md` and `reconstruction/ida/function-size-map-v194.md`. The seven remaining method-size deltas are now recorded at the current baseline; use the matched method ranges plus reference pseudocode/disassembly to guide code-shape work. Strict `normalized-functions` and ATI hardware/runtime validation remain open.

### Native continuation v197-v205: transfer-table code-shape reconstruction (2026-10-04)

The retained v205 native source schedules the ASIC query byte and DAC byte to match the reference's initial loads and stack spill, masks the ASIC value at the reference point, reuses `EDX` for the DAC comparisons, and reads RAMDAC style once through `EAX`. Package validation passed (41 resources and companion checks). Fresh Binrecon/IDA analyzed all 61 functions with 35 code findings across the same seven methods; strict acceptance remains false. `setTransferTable:count:` is now 0x1e5 bytes versus 0x1e9 in the reference; its IDA disassembly LCS is 131/153 instruction lines versus 127/153 on v194. The v202 C mask attempt regressed to 40 findings and was rejected; v203-v205 retained the closer shape at 35. v205 `_reloc` SHA-256 is `6F56172DA4301104D2C854FC9F4C9D1805734F5B79DBA11AD1C23FC293D176B2`; main source SHA-256 is `7A26CEA983C7B273C295B9428ED01D45593FEA75C4A77B6477EE2943606FAC1B`. IDA exports all 61 candidate pseudocode functions without failures. Continue with the remaining transfer-table branch/loop differences, then address the other six methods; ATI hardware/runtime remains open.

### Native continuation v206: color-space dispatch

v206 changed the transfer-table color-space `if` chain to a `switch` with the same values and default cleanup. Native build emitted a 220,040-byte `_reloc` (SHA-256 `3810540B44BAC37380B431F9B94FDDBAF910B7A47CEC42C0125C0B75609509A6`); Binrecon remains at 35 code findings over the same seven methods. IDA instruction LCS for `setTransferTable:count:` improved from 131/153 to 133/153 with the method still 0x1e5 bytes. All 61 functions decompile with zero failures; see `reconstruction/ida/rebuilt-pseudocode-v206.md` and `function-size-map-v206.md`. Source SHA-256: `DD64604033195B8A7A4C47C5FC4A92260A47C216C6F40A30B782F6447D99A5F1`. Strict normalized-function parity and ATI runtime validation remain open.

### Native continuation v207-v213: `setTransferTable:count:`

- v207 narrowed `isATI68880RevC` to an unsigned-byte return and reached 134/153 common normalized disassembly instructions. v208 changed the two loop bounds to `i < count`, reaching 138/153. v209's RAMDAC-style switch regressed from 35 to 41 code findings; v210's unpinned blue pointer regressed to 47; both were discarded.
- v211 pinned the grayscale blue-table base to EDX and transfer value to EAX, reaching 143/153 at 35 findings. v212 made the DAC type 2 equality branch explicit (144/153). v213 expressed RAMDAC style as the observed range/equality structure: function size now exactly matches the reference at 0x1e9 and LCS is 145/153; Binrecon remains 35 code findings across the same seven methods.
- Native v213 build and package checks passed (41 resources, required version symbols/string, 34-byte companion). `_reloc`: 220,084 bytes, SHA-256 `6904175F0998C9D4AD97D9009D3E4F6DBDBD2480491C573ED39E92A55BE9D019`. IDA decompiled 61/61 functions with zero failures; exports are `reconstruction/ida/rebuilt-pseudocode-v213.md` and `function-size-map-v213.md`. Source SHA-256: `A2B3FB27E093931CC23D7EA5143550959CE5CAFF6F60D5D03880BC949795FF6B`; vm.conf Port remains 2121. Strict parity and ATI runtime validation are still open.

### Native follow-up v214-v216: BIOS register trials

v214 pinning the CRTC mode-flags byte to AL reduced local instruction LCS to 80/93 from 84/93. v215 splitting AL gamma and DL final flags increased global findings to 43. v216 pinning `self`/private storage to EBX/ESI in `setupCodeSegments` matched the prologue but increased the method to 0x19a versus 0x184 and lowered its LCS to 40/110 from 42/110. All three trials were discarded. Both sources were restored to v213 and rebuilt natively; fresh Binrecon remains at 35 code findings across the same seven methods. Final `_reloc` is 220,084 bytes, SHA-256 `6904175F0998C9D4AD97D9009D3E4F6DBDBD2480491C573ED39E92A55BE9D019`. IDA decompiled 61/61 with zero failures and refreshed the v213 pseudocode/size exports. Source hashes: main `A2B3FB27E093931CC23D7EA5143550959CE5CAFF6F60D5D03880BC949795FF6B`, BIOS `1FD9D3CCB122CD60250FBA25122FF21FC8B256B3D7416A92232F797B65CE7AAD`. `vm.conf` Port 2121. Strict parity and ATI runtime validation remain open.

### Native continuation v217-v227: gamma call order and `_doBlit`

- v217/v219 rewrote the `[self displayInfo]` call sequence so i386 stack cleanup precedes the depth read. v219 removed all `setGammaTable` Binrecon findings and reduced total code findings from 35 to 30; its method is 126/130 normalized IDA instructions. v218 was a regression. v220’s DL-only CRTC flags experiment raised findings to 38 and was rejected.
- During v221 the first sync landed outside the chroot build source. Subsequent runs now sync to `/build/bootstrap-root/build/source/src`, confirmed by the built CRTC body returning to the v219 baseline. `vm.conf` remains at `Port=2121`; the SSH forwarded port override is applied only in the invocation.
- v221’s ESI pin did not change `_doBlit` machine code. v222’s in-place destination-X form reached 42/96 instruction LCS; v223’s ECX-only local fell to 37/96. v224’s branch-order rewrite stayed at 42/96 and reduced size to 328 bytes. v225 pins source X/destination X to EAX/ECX and is retained at 45/96, 328 bytes, with 30 global code findings. v226’s ESI destination-Y pin reduced the method to 317 bytes but fell to 41/96, so it was rejected.
- Final retained native rebuild v227: `_reloc` 220,268 bytes, SHA-256 `8D7904E2FC7A565C9899446095E66CC5A1FD1608DE387E019B14B0BF65D66870`. Binrecon processed 61 functions and remains at 30 code findings across six methods; `normalized-functions` is false. IDA decompiled 61/61 with zero failures; `_doBlit` is 328 bytes and 45/96 normalized instructions in common with the reference. Main source SHA-256 `2E0CD5CE1A6054BB324B4A8AD8728A74CFF26548A8F874FDCD386D3C63C80060`; BIOS source remains v213 SHA-256 `1FD9D3CCB122CD60250FBA25122FF21FC8B256B3D7416A92232F797B65CE7AAD`. Strict parity and ATI runtime validation remain open.
IDA v227 exports are saved at `reconstruction/ida/rebuilt-pseudocode-v227.md` and `function-size-map-v227.md` (61 functions; zero decompilation failures).

### Native continuation v235-v237 (2026-10-05)

v235 reorders the grayscale red/green pointer loads in `setTransferTable:count:`. Binrecon's function difference score improves from 28 to 27, with no change to the 30 code findings across six methods. The 220,244-byte `_reloc` SHA-256 is `57C016AA253B8DCF069DB4FC0C887B3C1AC601E0475661159FCDEC3FCE1BB4E2`. Direct IDA 9.4 decompilation succeeded for all 61 candidate and all 61 reference functions; complete pseudocode exports are under `reconstruction/ida/*pseudocode-v235.md`.

The local v237 trial reloads the blue transfer-table base inside the grayscale loop before the shifted source-byte load, following the reference instruction order. Source SHA-256 is `71D9765C1501563E6A5008CA53E75CD11FDE4284D3CD62C48185B713ED590389`. The automatic review rejected syncing this file to the native guest with “blocked by policy”; it is unbuilt and unverified. Keep v235 as the best proven candidate until a native build and Binrecon comparison establish otherwise. `vm.conf` remains at Port 2121. Strict parity and ATI hardware/runtime validation remain open.

The v235 comparison's six code-different method sizes are: `initFromDeviceDescription:` 1,664/1,764 bytes (reference/candidate); `fixDeviceDescriptionForPCI:` 1,632/1,583; `_doBlit` 322/328; `setTransferTable:count:` 489/485; `setupCodeSegments` 388/390; and `loadCRTC_comm` 258/254. IDA identifies a concrete next source-shape experiment in the first method: its 136-byte `IODisplayInfo` copy is `_bcopy` in the candidate, while the reference emits `cld`, loads a 34-dword count, and executes `rep movsd`. Keep the established behavior and test this shape only through a fresh native build and Binrecon comparison.


### IDA typing follow-up (2026-10-05)

Applied the recovered ATI object layout to the v235 IDA candidate as a named 624-byte struct, preserving the 552-byte inherited prefix and matching each ivar offset. A separate complete pseudocode export, `reconstruction/ida/rebuilt-pseudocode-v235-typed.md`, captures the resulting member-aware Hex-Rays output (61/61 decompiled; 23/23 ATI methods typed; SHA-256 `941dbd9c3db2f452f576e85fc63d44d92f8f001f59c5cdff78a7cb8e0cc60477`). Type metadata improved field naming only; the binary and strict Binrecon results are unchanged.

The initializer mismatch is localized to its final display-info copy: reference copies the 136-byte mode record with cld; mov ecx, 0x22; rep movsd, while candidate calls _bcopy with the same source and destination. Record this as the next source-shape experiment; retain a change only after native build and Binrecon comparison.

The IDA candidate now has a recovered `IODisplayInfo`-layout type (136 bytes) applied to `_AtiModeList` at `0x42dc` as 72 records (9,792 bytes), ending at `_AtiModeListCount` `0x691c`; the count is typed as 32-bit unsigned. These boundaries match the 136-byte instruction stride and table count. Hex-Rays still emits raw pointer arithmetic for several table references, so this is a verified data-layout annotation and not a complete field-aware rewrite of every table access.

The candidate and reference IDA databases now both carry the same 72-entry mode-table type and 32-bit count type. In `updateModeList`, the remaining raw expressions map to `IODisplayInfo` members by byte offset: `+20 frameBuffer`, `+24 bitsPerPixel`, `+32 pixelEncoding`, `+96 flags`, `+104 memorySize`, and `+128 modeUnavailableFlag`. This map is grounded in `displayDefs.h` and the table's 136-byte stride; Hex-Rays output remains pointer arithmetic for these accesses.

### BIOS class typed decompilation pass

Applied the recovered ATI_BIOS object layout (16 bytes), private block (36 bytes), BIOS register block with unions (48 bytes), and CRTC record (30 bytes) to both v235 IDA databases. All 24 BIOS instance methods on both sides now have typed receivers and recovered argument types. Fresh candidate/reference typed pseudocode exports cover 61 functions each with zero failures. This improves the BIOS helper decompilation only; machine-code parity and native validation remain open.

The 48-byte BIOS register locals are now typed in `shortQuery` and `loadCRTC_comm` on both sides. The exported pseudocode resolves the BIOS response through AX/BX/CX/DX union members and shows the mode setup writes through ECX/EDX/EBX members, removing the previous opaque 16-bit array indexing. A follow-up layout pass added the 8-byte `ATI_SegmentDescriptor` and a 36-byte `ATI_BIOSPrivate_Layout` to both databases. Saved GDT entries in setup/restore now decompile as named descriptor records, while raw hardware bit writes remain byte-offset operations. Candidate and reference exports were refreshed (61 functions each, zero failures; SHA-256 `941dbd9c3db2f452f576e85fc63d44d92f8f001f59c5cdff78a7cb8e0cc60477` and `9dcdb9437668c995083596a116cf1fd9c7a88e2ad7017c7eb8d661838a8c80de`). The database annotation does not change machine code or Binrecon parity.

### PCI range typing and configuration selector correction (2026-10-05)

Saved both v235 IDBs with `IOConfigTable *configTable` in `fixDeviceDescriptionForPCI:`. In the reference IDB, also typed the source-declared `unsigned int barRegisters[18]`, `IORange portRanges[9]`, and `IORange memoryRanges[8]`; Hex-Rays now presents range member accesses by `start` and `size`. Refreshed the reference typed export preamble; current export hashes are candidate `7283E616FD266FCB3AE78EC5D376D45448A1F9E35245EB38117E7F1199DB30F0` and reference `5E95AF50723DA0772486892012562F29B54978F5737C5E8AB2D7F2712B88C859`.

Reference pseudocode for `fixDeviceDescriptionForPCI:` shows `valueForStringKey:` and `IOConfigTable.h` declares the same selector. Corrected the four source config lookups to that selector, added the direct header import, and removed the unsupported `ATIRageLegacy` category. The candidate v235 binary still contains the old selector and remains unchanged. Source SHA-256 for `ATIRageDisplayDriver.m`: `F1C4D46265F06EBD08603DE75C9FCA5B5B07A60F954CA9023580BC907B664221`. The prior automatic review rejected syncing to the native guest with “blocked by policy”; therefore this edit has no native build or Binrecon result. Keep v235 as the accepted binary until a permitted native build can verify this source correction and the other outstanding method-shape trials.

Regenerated `source-map.json` after the source-line shifts. Binrecon's source-map command returned successfully with 59 mapped handwritten entries and no disputed boundaries; `check_reconstruction.py` then reported `reference contract valid: 63 code entries; 12267 text bytes accounted for`. Source-map SHA-256: `E5E1482B75CEFA081A3C6F7A9AE4607995403CD387FCBAF2D31144CE8EBF1EFC`.

Re-audited ordered call targets across the six v235 code mismatches using the published IDA analysis. `fixDeviceDescriptionForPCI:`, `_doBlit`, `setTransferTable:count:`, `setupCodeSegments`, and `loadCRTC_comm` retain identical ordered call targets in the reference and candidate; only call offsets move. The Objective-C selector loads also match for `setTransferTable:count:` and `loadCRTC_comm`; the PCI method's 24 selector loads were already confirmed in the earlier audit. `initFromDeviceDescription:` is the exception: both sides have 54 calls, but call-target order differs, with the reference's 9 diagnostics and `rep movsd` versus candidate v235's 8 diagnostics and `_bcopy`. This focuses the next compiler-shape experiment on initializer topology and the final 136-byte copy. Comparison JSON SHA-256: `114479882064565252C2676E974A801AAFC13881F0112AEE8C88F6F2DD5BF3CE`.

Frequency counts narrow the initializer target-set delta to one missing reference `_IOLog` and one candidate-only `_bcopy`; the counts of all other call targets match. The missing reference log is for `No Display Mode found; aborting` at function offset `0x475`, and current source contains it at line 179. Current source also uses structure assignment for the 136-byte copy. These source changes are newer than the v235 artifact and still require a native rebuild plus full Binrecon run to confirm their effect.

Ran the repository's selector-definition audit against the reference binary and the reconstructed LKS sources: 50 reference selectors, 48 handwritten source definitions, and two generated accessors; missing, extra, renamed, and duplicate selectors are all empty. The check does not inspect Objective-C message-send expressions, so the corrected `IOConfigTable valueForStringKey:` call remains separately grounded in the framework header and reference IDA decompilation.

Adjusted the missing Display Mode branch to log and reach the shared `[driver free]` return. Reference decompilation places that log in the null branch and returns through a single common cleanup after the Display Mode logic; the old source returned separately from the null branch. Regenerated source map and reran the reference contract checker: 59 mappings, no disputed boundaries, all 63 code entries and 12,267 text bytes accounted for. Selector-definition audit remains clean. Main-source SHA-256 is `FC4FF461628A08D9ABED488F3E7A192382601F8591A801D88A4F968D35B9A14E`; source-map SHA-256 is `05D8A33ED4FA64CFA203080E138F8DFFB2586D053A5B1755B4BA7230302251A9`. This source-shape adjustment is unbuilt pending a permitted native guest build.

Ran the reconstruction checker again with accepted v235 supplied as `--rebuilt`; exit code 0 confirms the ABI, static-data/pointer-target, and BIOS transition/thunk gates pass for that binary. Its 63-entry/12,267-byte coverage is valid. `normalized-functions` remains a separate failing Binrecon gate across six methods, and v235 predates the current source edits.

### Candidate ATI receiver type refinement (2026-10-05)

The candidate IDB now has a source-faithful 624-byte ATI struct matching the reference database's size and ivar offsets. It has a 552-byte inherited prefix and ATI fields at offsets 552-620, including id atiBios, void *queryData, and alignment before baseAddress. All 23 candidate ATI method receivers now use ATI *; fresh pseudocode uses the original class name in method calls. The 61-function candidate export has zero failures (SHA-256 941dbd9c3db2f452f576e85fc63d44d92f8f001f59c5cdff78a7cb8e0cc60477). No binary bytes changed; strict Binrecon parity remains open.

### ATI displayModes return annotation (2026-10-05)

Corrected the displayModes prototype in both v235 IDBs to return IODisplayInfo_Recovered *, matching the public header and the actual 72-entry mode table. Hex-Rays now renders the body as return AtiModeList; without the previous Class * or opaque synthetic return type. Candidate and reference exports each contain 61 functions with zero failures (SHA-256 941dbd9c3db2f452f576e85fc63d44d92f8f001f59c5cdff78a7cb8e0cc60477 and 9dcdb9437668c995083596a116cf1fd9c7a88e2ad7017c7eb8d661838a8c80de). Type metadata only; binaries and Binrecon parity are unchanged.

### Cursor Point parameter types (2026-10-05)

Corrected showCursor:frame:token: and moveCursor:frame:token: to use Point * in both IDBs, matching the driver header. The candidate Point definition is the 4-byte pair of short coordinates from the local i386 ev_types.h; the reference database's existing Point typedef is also 4 bytes. Both methods are superclass pass-throughs, so the change clarifies their ABI without changing code. Refreshed exports: 61 functions each, zero failures; candidate SHA-256 941dbd9c3db2f452f576e85fc63d44d92f8f001f59c5cdff78a7cb8e0cc60477; reference 9dcdb9437668c995083596a116cf1fd9c7a88e2ad7017c7eb8d661838a8c80de.


### Reassessment of the v150 initializer-copy trial (2026-10-05)

The v150 structure-assignment run used the older v149 source baseline, so its rise from 39 to 69 global code findings does not isolate the copy change against current v235. Its IDA disassembly does establish that structure assignment emits the reference copy instructions exactly: cld; mov ecx, 0x22; rep movsd. An independent LCS over IDA normalized mnemonic/operand pairs finds 321/504 reference instructions in v150 versus 237/504 in v235 (candidate totals 518 and 520). Both still differ in initializer calls, CFG, range, and instruction shape. This makes the v150 source form a strong current-v235 experiment candidate, but not a retained reconstruction until a fresh native build and Binrecon comparison establish its effect on the full current image. Evidence: v150 published analysis/comparison at tools/binrecon/out/drvATIRage-i386-compare/native-20261004-v150/published, and current v235 comparison at tools/binrecon/out/v235-transfer-gray-load-order/published.

### Current initializer-copy source trial and native execution block (2026-10-05)

The current source changes the initializer's `bcopy` call to `*([super displayInfo]) = AtiModeList[driver->modeNumber]`, using the structure-assignment form supported by the v150 disassembly evidence. IDA inspection of the exact v235/reference pair confirms v235 calls `_bcopy`, while the reference emits `cld; rep movsd`. A second source-shape trial removes `_doBlit`'s `blitControl` local and writes `(savedRegister304 & 0x80) | direction | 0x18` directly to register 76. The exact IDA disassemblies show the reference frame reserves 0x1c bytes and forms this value in EAX; v235 reserves 0x20 bytes and spills the temporary through the stack. A third trial in `ATI_BIOS.m` pins `loadCRTC_comm`'s gamma byte to AL and assembled mode flags to DL. IDA shows the reference uses `xor al,al`, transfers AL to DL, and stores the resolution byte from CL; v235 computes the flag directly in DL and moves resolution through EAX/AL. The grayscale loop was also changed: the reference loads `blueTransferTable` into EDX before loading and shifting the input byte, while v235 performs the table-byte load/shift first and fetches the blue pointer afterward. Because an earlier source ordering alone did not survive optimization in v235, the current source adds a compiler memory-clobber barrier after the blue-pointer assignment. Main-source SHA-256 is `9413BF427D6D31F4C7D33EA524A01FE5926A793F73C537122C146006E580EE6F`; ATI_BIOS.m SHA-256 is `0FDEFB23D5A1DADB7A5B08ECF234DE23AE46751F57E2BBF755A2A4E603B2ADD5`. These remain unbuilt and unverified against the current full source baseline. The prior automatic review blocked syncing the trial to the native guest with “blocked by policy.” The user approved native execution, but that approval does not override the review block, so no sync/build was attempted. v235 remains the latest accepted binary. When an allowed native path is available, run Binrecon against the same reference and inspect acceptance plus all changed functions' instructions.

### PCI method argument typing (2026-10-05)

The declaration for `fixDeviceDescriptionForPCI:` now uses `IOPCIDeviceDescription *` in the source header and implementation; the binary ABI remains an Objective-C object pointer. Applied the corresponding opaque class-pointer prototype in the candidate v235 IDB and saved it. Recovered the target i386 `IORange` layout from `driverTypes.h` (`unsigned int start; unsigned int size;`, 8 bytes) and applied arrays of 9 port ranges and 8 memory ranges plus the 18-word BAR register array to the PCI method locals. Hex-Rays now expresses the range starts and sizes by field name and resolves range/config-table selectors as `IOPCIDeviceDescription` methods instead of generic `objc_msgSend`. Refreshed that method's candidate pseudocode section; all 61 functions still decompile with zero failures. Candidate typed-export SHA-256 is `4503950ACC16B508B63A2E43C796B2D20FDF8E910E65EBC3F45197A81F9D8EBE`. This is type metadata and improves the decompilation without changing candidate bytes or Binrecon results.

### Initializer PCI parameter typing (2026-10-05)

Typed the `initFromDeviceDescription:` method parameter as `IOPCIDeviceDescription *` in the header and implementation, consistent with its PCI config, memory-range, and config-table selectors. Applied the same opaque pointer prototype to the candidate v235 IDB. Also applied an opaque `IOConfigTable *` type to the initializer's table local, which lets Hex-Rays resolve the legacy `valueForString:` and `freeString:` calls as IOConfigTable selectors. The refreshed initializer pseudocode now resolves `getPCIdevice:function:bus:`, `memoryRangeList`, and `configTable` against `IOPCIDeviceDescription`, then the table operations against `IOConfigTable`. The complete candidate export still contains 61 functions; all 61 decompile without failures. Updated candidate pseudocode SHA-256: `86335006DFDFB516677099C26CAF4156DB04D6E318F6385943C74BD2B9423AC5`. This is type recovery only and does not alter the native binary or Binrecon comparison.

### GDT descriptor disassembly and local types (2026-10-05)

Applied the recovered 8-byte `ATI_SegmentDescriptor` pointer type to the `setupCodeSegments` GDT locals in both candidate and reference IDBs. The refreshed decompilations express `base_low`, `base_mid`, `base_high`, `access`, `limit_low`, and `limit_flags` directly. Comparing raw IDA disassembly establishes the descriptor base immediate is image-specific: reference 0xC0002E48, candidate 0xC0002E7C. The source derives the base from its `_bios16` symbol; retain that symbolic relation rather than hard-coding the reference image address. Hex-Rays renders the candidate's immediate bytes as `strcpy("|.")`; the adjacent export note points to raw disassembly for the exact value. Both exports have 61 sections and all functions decompile without failures. Candidate and reference typed-export SHA-256 values are `B43FD0E7B7F62E600F8059F6483EEE5A3F12865410FB2EC9E369945DEE20C74D` and `4F3A633E578A3C8A3D040926E5958393AE127D4309C79E990F018C4AFE66C71E`. Type annotations changed no binary bytes.

### BIOS class receiver type (2026-10-05)

Applied the Objective-C class receiver type to `+[ATI_BIOS ATIPresent:]` in both the v235 candidate and reference IDBs: `char __cdecl ATIPresent(Class self, SEL cmd, unsigned int *biosBase)`. The argument type and return type agree with `ATI_BIOS.h`; only the generic `id` receiver was narrowed to `Class`. Both IDBs were saved and the function decompiles with the updated prototype. Refreshed the matching function signature in both 61-function typed pseudocode exports; no machine-code bytes or Binrecon comparison inputs changed. Current SHA-256 values are candidate `B43FD0E7B7F62E600F8059F6483EEE5A3F12865410FB2EC9E369945DEE20C74D` and reference `4F3A633E578A3C8A3D040926E5958393AE127D4309C79E990F018C4AFE66C71E`.

### PCI call-sequence audit (2026-10-05)

IDA disassembly and Binrecon's saved analysis both show 26 calls in reference and v235 `fixDeviceDescriptionForPCI:` with identical ordered targets: 24 Objective-C message sends, `_strtol`, and `_IOLog`. The 24 selector loads match in order as well. Binrecon's `_canonical_calls` includes function-relative call-site offsets, and the offsets shift with compiler layout, so `calls_equal=false` overstates the call-sequence difference for this method. Keep the call-location and instruction-range mismatch visible, but distinguish it from target/selector order; do not change the source on the basis of this flag alone. The function remains byte-different (1,632 reference bytes / 1,583 candidate bytes), and its strict Binrecon acceptance is still open.

The initializer audit shows reference v235 has nine `_IOLog` call sites and seven `free` selector loads, while candidate v235 has eight `_IOLog` sites, eight `free` loads, and one `_bcopy`. The source factors several diagnostics through `initFailure`; current source also uses structure assignment for the 136-byte display-info copy, but has not been rebuilt. Candidate pseudocode retains each reviewed failure case and the successful state initialization. This is evidence of code-shape divergence, not a verified behavioral defect; keep the unbuilt source trial separate from the v235 binary until a permitted rebuild is available.

### Reference PCI parameter typing (2026-10-05)

Applied the same source-backed `struct IOPCIDeviceDescription *deviceDescription` parameter to reference IDB methods `initFromDeviceDescription:` and `fixDeviceDescriptionForPCI:` that was already present in the candidate IDB. Refreshed both corresponding sections in `reference-pseudocode-v235-typed.md`; Hex-Rays now resolves `getPCIdevice:function:bus:`, `configTable`, `memoryRangeList`, `portRangeList`, and range setters as `IOPCIDeviceDescription` methods. Saved the reference IDB at `C:\Users\raynorpat\Downloads\test\Drivers\i386\ATIRageDisplayDriver.config\ATIRageDisplayDriver_reloc.i64`. This is type metadata only; reference bytes and Binrecon comparison data are unchanged. The complete reference pseudocode export hash is now `0AEBAEFE7093954AD02DF327EEB249FFD18C6141F33960798EE7ECFE75608C8C`.

### Existing v236 grayscale candidate (2026-10-05)

The existing v236 Binrecon artifact (`tools/binrecon/out/v236-transfer-gray-blue-preload`) is 220,256 bytes with SHA-256 `29D237CBFE2EF8F4DB0FE87D19EEB4C46DD40F2A91D55A623E24549B8FB860E0`. Its complete comparison still fails `normalized-functions` with the same 30 findings across the same six methods and unchanged method sizes, so v235 remains the latest accepted candidate. IDA disassembly shows v236 preloads the grayscale blue destination pointer before entering its loop; the reference loads it inside each iteration before reading the source byte. The independent normalized-instruction LCS for `setTransferTable:count:` is 124 pairs for v235 and v236 against 149 reference instructions (candidate totals 148 and 150 respectively), providing no local improvement for v236. Do not treat it as a proven reconstruction.

### Current source-map line anchors (2026-10-05)

Refreshed `source-map.json` against the current source tree. All 59 mapped function anchors now resolve to their current definition lines; 58 line numbers changed as source files grew during reconstruction, and the `_ATIbios16` anchor remains at line 7. The two generated class methods remain intentionally unmapped to source and are identified in the existing `assembly-matched` ledger entries. This only repairs navigation metadata; it does not change code, ledger review baselines, or binary acceptance.
### Generated kernel-server accessor return type (2026-10-05)

The runtime method metadata encodes `+[ATIRageDisplayDriverKernelServerInstance kernelServerInstance]` as `^^{?}8@8:12`, and both binaries contain the same six-instruction stub that returns the address of `_ATIRageDisplayDriver_instance`. Corrected both IDBs to `void ** __cdecl kernelServerInstance(Class self, SEL cmd)`, retaining the two pointer levels while leaving the pointee opaque. This replaces the candidate's unrelated `IODisplayInfo_Recovered **` and the reference's synthetic hash-named struct pointer. Refreshed the method section in both typed pseudocode exports and saved both IDBs. The annotations do not alter either binary or Binrecon results. Export SHA-256 values: candidate `00359ECBD38989E9D7A60B61CC11C60E1FFEC48AEA79643DFD20F42EB59C765C`; reference `D5085A4C9E96A455325183BE9AF139DDB24D5E7882CFD252E2180BEEEFDC83E0`.
### C helper prototype recovery (2026-10-05)

Reconciled the candidate and reference IDBs for four C helpers against their declarations in `ATIRageDisplayDriver.m`: `waitForFIFO(unsigned int count)`, `waitForIdle(void)`, `doBlit` with six named `unsigned int` parameters, and `doFill` with five named `unsigned int` parameters. The earlier IDB typed the FIFO count as `char` and the fill arguments as signed `int`; those contradicted the source declarations. Refreshed the four pseudocode sections in both typed exports and saved both IDBs. This is type metadata only; the binaries and Binrecon comparison are unchanged. Current export SHA-256 values: candidate `00359ECBD38989E9D7A60B61CC11C60E1FFEC48AEA79643DFD20F42EB59C765C`; reference `D5085A4C9E96A455325183BE9AF139DDB24D5E7882CFD252E2180BEEEFDC83E0`.
### BIOS command local typing (2026-10-05)

Refined `loadCRTC_comm` locals in both IDBs using the source declarations and verified register roles: candidate `v10` is named `modeFlags` (DL), while reference `v10` is named `gammaFlag` (AL); the reference's separate temporary reflects its AL-to-DL transfer. In both databases, the BIOS call result local is explicitly `int biosResult` rather than an object pointer, the byte flag is `restoreData`, and the 48-byte register block is `registers`. This makes the decompilation's status test numeric and preserves the real reference/candidate register distinction. Refreshed this function in both exports and saved both IDBs. Type and local-name metadata only; binaries and Binrecon output are unchanged. Current export SHA-256 values: candidate `00359ECBD38989E9D7A60B61CC11C60E1FFEC48AEA79643DFD20F42EB59C765C`; reference `D5085A4C9E96A455325183BE9AF139DDB24D5E7882CFD252E2180BEEEFDC83E0`.

### Transfer-table IDA annotations (2026-10-05)

Renamed source-supported locals in `-[ATI setTransferTable:count:]` in both v235 IDBs: `_cmd`, `table`, `count`, `initialShift`, `chipId`, `allocatedTransferTables`, `bitsPerPixel`, `grayValue`, `grayIndex`, `rgbIndex`, `ramdacType`, and `componentShift`. The names expose the grayscale/RGB paths and transfer shift in Hex-Rays while preserving the exact v235 code. Refreshed the matching method sections in both typed pseudocode exports and saved both databases. Candidate export SHA-256: `9FAF2ACBFA7193E62CBABAB2784039516BBBC873F69BEE77CA4A18958B273B61`; reference export SHA-256: `4C45A55925F4EFE255286FDA8216C5FD8DF5796A0919EBFA82E66C9C91B8FD4E`. No binary or Binrecon comparison input changed.
### Blit helper IDA annotations (2026-10-05)

Renamed `_doBlit` locals in both v235 IDBs from register-oriented Hex-Rays names to source-supported names: `destinationXReg`, `overlapXDistance`, `overlapYDistance`, `destinationYStart`, `registers`, `direction`, source/destination start coordinates, and the three saved MMIO registers. The candidate and reference use different temporary layouts, so candidate `blitSize`/`blitControl` and reference `blitControl`/`blitSize` follow their actual roles. Refreshed both export sections and saved the IDBs. Candidate typed-export SHA-256: `4DA45B014DA0AF56DAD8D65299F84B460BAB2B51597E18B99F583F7D616144E4`; reference typed-export SHA-256: `8849BD8519A8CFCD9E24625B5D026E76C94BB02756F6FABC8403872C99A6C5BF`. This documents v235's actual stack/register allocation; no binary bytes or Binrecon input changed.
### Initializer IDA local recovery (2026-10-05)

Expanded the v235 `initFromDeviceDescription:` decompilation in both IDBs using the source and DriverKit declarations. Named the port probes and saved port state, BIOS base, mode/config strings, ASIC and memory names, range list, framebuffer pointer, and diagnostic arguments; corrected the candidate display-info copy destination name. Typed the memory-range locals as `IORange *`, framebuffer locals as `void *`, BIOS base as `unsigned int`, config-table locals as `IOConfigTable *`, returned names/config strings as `const char *`, the candidate copy destination as `IODisplayInfo_Recovered *`, and its free selector as `SEL`. The annotations keep v235 faithful to the built `valueForString:` selector and `_bcopy` call. Candidate export SHA-256: `C380E19453A7EEB4407BE5A2C21CC07F411D7299EFE93EE6C62C76A7E1236BBD`; reference export SHA-256: `36DC4C671A6221D963135544F6E8222C6A03F6072BC6F3A44F61118881A68FDA`. No binary bytes or Binrecon comparison inputs changed.
### PCI method local-variable recovery (2026-10-05)

Recovered clean IDA output for `-[ATI fixDeviceDescriptionForPCI:]` in both v235 databases. The candidate and reference had 30 and 31 saved local-variable entries from the failed annotation pass. Clearing those entries alone left the cached Hex-Rays warning; flushing the function cache with `ida_hexrays.mark_cfunc_dirty` removed it. Reapplied only the three source-backed arrays, matched by exact stack offset and width in each IDB: `barRegisters[18]` (`unsigned __int32`, 72 bytes), `portRanges[9]` (`IORange`, 72 bytes), and `memoryRanges[8]` (`IORange`, 64 bytes). Both methods now decompile without the allocation warning. Refreshed the PCI method in the candidate and reference typed exports and saved both IDBs. Full export SHA-256: candidate `F1DB39B840EEA56B20C717FBB79E2DE5476DB8F71F69FC9028475BC9961CFB6C`; reference `F7017F0417BD3A77208A1ECB3D4FC099925ED142AFFBC8CC2AE1C51992288DED`. This updates type/name metadata only; v235 bytes and Binrecon comparison results are unchanged.

### Full v235 pseudocode pass (2026-10-05)

Re-decompiled all 61 functions in the saved candidate and reference IDBs after recovering `fixDeviceDescriptionForPCI:`. Both databases report zero decompilation exceptions and zero local-variable allocation warnings. This verifies that every function represented in the 61-function exports produces current pseudocode; it does not change the six-function `normalized-functions` parity result or claim semantic/runtime validation. Binary bytes are unchanged.

### GDT setup local recovery (2026-10-05)

Renamed the setup-method temporaries in both v235 IDBs to `code16BaseAdjusted`, `stackAllocation`, and `stackBaseAdjusted`, and named the selector argument `_cmd`. Refreshed both setup-method export sections. This clarifies the descriptor address calculations and stack allocation while keeping candidate and reference pseudocode faithful to their respective linked bytes. No code or Binrecon inputs changed; native rebuild remains blocked by the existing automatic review rejection.

### PCI range reconstruction locals (2026-10-05)

Used the source and each side's pseudocode to name the BAR probe, range-count, alignment, low-address override, framebuffer-base search, setter-result, and diagnostic locals in candidate and reference `fixDeviceDescriptionForPCI:`. Refreshed both PCI method export sections and saved both authoritative IDBs. This is IDA reconstruction metadata only; v235 bytes and the published comparison remain unchanged.

### GPU fill and engine setup IDA recovery (2026-10-05)

Recovered source-backed local names and types in both authoritative v235 IDBs for `_doFill` and `-[ATI initEngine]`. `_doFill` now identifies the volatile MMIO register pointer and the three saved register values. `initEngine` now types `info` as `IODisplayInfo_Recovered *`, exposing `width` and `bitsPerPixel`, and names pitch, the staged MMIO pointers, selector, and driver name. Candidate and reference method exports match live Hex-Rays output exactly for both methods (25 lines each for `_doFill`; 79 each for `initEngine`). Full typed-export SHA-256: candidate `3FE60D883E8DDB877F35D81DDA43DEB5BBE00DE7E47EA625CE0EED161A50FDEB`; reference `C40979F72A800C93468E343FA7D12BBAC17D21180AE86C1192739E5AB154E4F3`. Saved both IDBs. Metadata only: v235 binary bytes and Binrecon comparison results are unchanged.

### BIOS VGA-mode IDA recovery (2026-10-05)

Recovered the locals in `-[ATI_BIOS setVGAMode:gamma:]` in both v235 IDBs using `ATI_BIOS.m` and the 48-byte `ATI_BIOSRegisters` definition: named `gammaFlag`, `biosResult`, and `registers`; applied `char`, `int`, and `ATI_BIOSRegisters` types; and named the selector `_cmd`. Hex-Rays now identifies the mode/gamma flags in `registers.ecx.bytes.low` and the BIOS status byte in `registers.eax.bytes.high`. Candidate and reference exports match live IDA output exactly (26 lines each). Full typed-export SHA-256: candidate `79367DBEFB779C583AF759062C15B25226C8CE9D8A224E4354CD88C337570E1D`; reference `CFB7C66328771A419527132165A8B6E309260D19547FB76CBC3670C910914DDA`. Both IDBs are saved; v235 bytes and Binrecon inputs are unchanged.

### BIOS aperture setup IDA recovery (2026-10-05)

Annotated both v235 `-[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:]` methods from source: named the BIOS return value `biosResult`, the six-word local prefix `registerWords`, the ECX flag byte `apertureFlags`, and the selector `_cmd`. The source-backed names expose the enable/VGA/aperture flag construction, 1 MiB alignment check, address encoding, and BIOS status path. The candidate and reference exports match live IDA output exactly (40 lines each). Full typed-export SHA-256: candidate `5B03AE6BA3041BB7FA6FC669722641D803539225D2CB30D5C49F7CF1E5EDB5FA`; reference `0C304126DDA48046DBA6894484F514A93476A5002836B22681804BFABC4CCDBF`. Saved both databases; binary bytes and Binrecon comparison inputs are unchanged.

### BIOS device-query IDA recovery (2026-10-05)

Recovered the `-[ATI_BIOS deviceQuery:bufferSize:buffer:]` local roles in both v235 IDBs from `ATI_BIOS.m`: `_cmd`, `biosResult` (`int`), the register-word prefix, the query flag byte, and the 16-bit BIOS buffer offset (`136`). The decompilation now exposes the buffer setup, query flag, segmented BIOS call, and return/status paths with source-supported names and widths. Candidate and reference method exports match live IDA output exactly (42 lines each). Full typed-export SHA-256: candidate `C06B63899D625029BCB3859106CD2D29BB25A736B28C9FA2D04ADA2C9EF3E5F2`; reference `3375CFCD4536AD03988AF517C8CC19C9E533C854F115929920BC051C2FD99641`. Both IDBs saved; v235 binary bytes and Binrecon comparison unchanged.

### BIOS DPMS and APM IDA recovery (2026-10-05)

Recovered source-backed names and types in both v235 IDBs for `setDPMSMode:`, `getDPMSMode:`, `setAPMState:`, and `getAPMState:`. Setter methods now expose `ATI_BIOSRegisters`, the integer BIOS result, and `registers.ecx.bytes.low` mode/state writes. Getter methods now distinguish the register prefix, result byte, and BIOS return code. The four candidate and four reference exports match live Hex-Rays output exactly (28 lines per setter; 22 lines per getter). Full typed-export SHA-256: candidate `6052919B17B404EC278A86BAD3CE42A4F37B1933B3D7762E5899A34B67223D13`; reference `BDA585D3AED402916D8D27B28B9A29BC065B9784F0A64147C61CAB50DDC212DD`. Both IDBs saved; v235 binary and Binrecon comparison are unchanged.

### BIOS address and refresh query IDA recovery (2026-10-05)

Recovered source-backed locals and selector names in both v235 IDBs for `getIOBaseAddress:relocatable:`, `getRefreshRate:`, and `shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:`. Address query now identifies the register prefix, relocatable flag, returned base address, and BIOS result; the refresh query identifies the BIOS result, register prefix, EBX input word, and 0x88 query buffer offset. `shortQuery` names its 48-byte `ATI_BIOSRegisters` block and integer BIOS result, and uses the source's signed-byte `ATIByte` output pointers. All three candidate and reference method exports match live IDA output exactly (28, 36, and 41 lines). Full typed-export SHA-256: candidate `FEA43E016AFEE1DD609B1F0A26E7DC8D50C0B168F3941BB836C381D89E323C65`; reference `C05B7A0348F1992BA52EBDAC8B980E478FC22EB349415E8DDA09E48312714498`. Both IDBs saved; binary bytes and Binrecon comparison remain unchanged.

### Query-data acquisition IDA recovery (2026-10-05)

Named and typed the `-[ATI getQueryData]` temporaries in both v235 IDBs from the implementation: query-size and device-query return codes, query size, temporary 16-bit buffer, returned data length, allocated persistent buffer, and driver/error log strings; also named `_cmd`. This exposes the query allocation/copy/free path and both failure logs in the decompilation. Candidate and reference method blocks match live Hex-Rays output exactly (48 lines each). Full typed-export SHA-256: candidate `AC36D8727BD829980111EEF41DD74A935BBD12DB9167405B3458DBACDECEE122`; reference `3420B99751AE08D54826A2D53808546477BFE017FE3249F9D98B48A9CDAFDFCC`. Both IDBs saved; binary bytes and Binrecon result remain unchanged.

### Driver query and mode-parse IDA recovery (2026-10-05)

Recovered the remaining source-backed locals in `-[ATI getQueryData]` and `-[ATI parseModeString:]` in both v235 IDBs. The query routine now exposes its size/device-query result codes, buffer size, temporary/persistent buffer roles, and diagnostic strings. The parser now exposes the selected mode, unsigned validation error, and the distinct log-name temporaries. Both candidate and reference method exports match live Hex-Rays output exactly (48 lines for `getQueryData`; 26 for `parseModeString:`). Full typed-export SHA-256: candidate `E57B2B38697F8F8A21FA7B9F9ED5B3EB49F2880B2CD465099DF96BE2AEDFF69F`; reference `493FAF725801A4E71C026F196EC6992DEDB74167604CD497AED5FDE23024EF56`. Both IDBs saved; v235 bytes and Binrecon comparison unchanged.

### Mode-list update IDA recovery (2026-10-05)

Named and typed the source-backed `-[ATI updateModeList]` locals in both v235 IDBs: device description, config string and its free/log lifetimes, driver name, pixel encoding, mode index and field-index temporary, and `IOConfigTable *configTable`; named the selector `_cmd`. The decompilation now shows RGBx/BGRx/xRGB/xBGR mapping, per-mode framebuffer/gamma/encoding updates, and memory-based unavailability handling. The candidate binary uses `valueForString:` while the reference analysis uses `valueForStringKey:`; retained each IDB's observed selector. Candidate and reference blocks match live Hex-Rays output exactly (85 lines each). Full typed-export SHA-256: candidate `F7999A46DE344DB9B5F58FB9E0FEB42BB4DFCDECFC7577931966BE845CF780D5`; reference `0B469392C5BDFBEAAF848F27073904380077AFDE3FA96928DF5981A91350952D`. Both IDBs saved. Full decompile pass: 61/61 functions, no exceptions per IDB. This is analysis metadata; v235 binary bytes and Binrecon comparison are unchanged.
### Display-mode path IDA recovery (2026-10-05)

Recovered source-backed local names and types in both v235 IDBs for `-[ATI isModeValid:]`, `-[ATI enterLinearMode]`, `-[ATI verifyMemoryMap]`, and `-[ATI revertToVGAMode]`. Mode validation now exposes the mode index, `IODisplayInfo_Recovered *`, bits-per-pixel, and required framebuffer bytes. Linear-mode entry exposes display info, color depth, pitch, BIOS result, CRTC record pointer, and separate driver/error strings. VRAM verification exposes its 16-word saved buffer and separate write/read indices. VGA restore now uses the 32-byte `ATI_CRTCRecord` plus distinct CRTC/VGA results and log temporaries. Each side's four method blocks match live Hex-Rays exactly (27, 49, 19, and 43 lines). Full typed-export SHA-256: candidate `E88846B90C971CC1F96794427EFA8C47E1F33E2FF43D1ECFE3BB22426E55239C`; reference `5425886103CB9C3E0010952A39FD029D4EE65E17D2E37076E30567B09698C264`. Both IDBs saved; full decompile pass remains 61/61 with no exceptions in either database. This pass changes analysis metadata only; binary bytes and Binrecon comparison inputs remain unchanged.
### Gamma programming and idle wait IDA recovery (2026-10-05)

Recovered `-[ATI setGammaTable]` locals in both v235 IDBs: DAC port/value and display depth, preserving the source-backed transfer-table and gamma loop indices; named the selector `_cmd`. Recovered `_waitForIdle`'s assembly-derived loop counter and pre-increment value. Candidate and reference method blocks match live Hex-Rays exactly (61/62 lines for `setGammaTable`, including the reference's existing semantic note; 20 lines for `waitForIdle`). Full typed-export SHA-256: candidate `82571EF806CD26D8262FE152E9CEEF2C1D41ABF7B0055B022E30BD347BA67BEE`; reference `3FF13CB179D5F66C5AFFF450BFC140AC379A43035AA026FCE26BFA59F69B8F79`. Both IDBs saved; each still decompiles all 61 functions without exceptions. Analysis metadata only; binary bytes and Binrecon comparison inputs are unchanged.
### Display-control method IDA recovery (2026-10-05)

Named and typed the arguments and source-backed temporaries in both v235 IDBs for `-[ATI setPendingDisplayMode:]`, `-[ATI setIntValues:forParameter:count:]`, `-[ATI free]`, and `-[ATI setBrightness:token:]`. These now show the mode index, integer-value array/name/count, the super-call records, brightness, and token; selector arguments are `_cmd`. Candidate and reference blocks match live Hex-Rays output exactly (23, 40, 14, and 14 lines per side). Full typed-export SHA-256: candidate `977DD1C77B38BDA9A7682FB8D605E4B4FA4DE350A6C2EF0AF103C032D3707906`; reference `BEFCD221527F184FE3119AD2F3C105D10A270FDDA5D58E1DC350009A4217C4D2`. Saved both IDBs; all 61 functions decompile without exceptions in each. Analysis metadata only; binary bytes and Binrecon inputs are unchanged.
### BIOS segment and lifecycle IDA recovery (2026-10-05)

Recovered source-backed locals in both v235 IDBs for `restoreCodeSegments`, `createDataSegment:size:`, `restoreDataSegment`, `doBios:dataSeg:`, `+[ATI_BIOS ATIPresent:]`, `init`, `initAtSegmentAddress:`, and `free`. The decompilation now labels the 16-bit and stack descriptor pointers, constructed data-segment byte pointer and encoded limit value, BIOS call result, scan base/offset/signature, and super-call records. Updated blocks match live Hex-Rays exactly (14, 45, 4, 14, 19, 17, 11, and 10 lines per side). Full typed-export SHA-256: candidate `9C2C7FEF54962384D30A883D7A395EBDB62A8AA9D21F12A2E6ED6B762C8A357B`; reference `9B544134460D674E966D9F285F7D803731C8BF18577605E47AA3911828FACCA2`. Both IDBs saved; both retain a clean 61-function decompile pass. This is IDA metadata and export work; binary bytes and Binrecon comparison inputs are unchanged.
### Cursor forwarding methods IDA recovery (2026-10-05)

Named the selector and superclass forwarding records in `showCursor:frame:token:`, `moveCursor:frame:token:`, and `hideCursor:` in both v235 IDBs; cursor, frame, and token parameter types/names were already source-typed. All six candidate/reference blocks match live Hex-Rays exactly (9 lines each). Full typed-export SHA-256: candidate `F0A4931C5FB3664B726871057BF3AF8BE9C33909900754AC4104126090DF8DAE`; reference `7DBBF43D354381B0CC9156BDFEF09F094DC34CFFF34EE8629AB9C4C076D1BB23`. Both IDBs saved, with all 61 functions decompiling without exceptions. Binary bytes and Binrecon inputs are unchanged.
### C helper signature and local IDA recovery (2026-10-05)

Recovered source-backed arguments and local roles in both v235 IDBs for `isATI68880RevC`, `SetGammaValue`, `displayInfoToColorSpace`, `colorDepthToColorSpace`, `displayInfoToColorDepth`, and `memSizeToBytes`. Display-info helpers now use the recovered const display-info pointer so Hex-Rays names `bitsPerPixel` and `colorSpace`; gamma helper arguments now identify RGB channels and brightness. Candidate/reference blocks match live Hex-Rays exactly (7, 13, 27, 23, 26, and 30 lines). Full typed-export SHA-256: candidate `575BF6EC3101D2FA9991CD22FD53A67F5BA8D1834E3D813ED3902565E91639E0`; reference `8700EEF2D654A9F9BF5A54C8EC50D8830D015FCE6B99E4BB94D27DDA21164985`. Both IDBs saved; 61/61 functions decompile without exceptions. Binary bytes and Binrecon inputs remain unchanged.
### Objective-C selector argument recovery (2026-10-05)

Renamed the implicit `SEL a2` parameter to `_cmd` in both authoritative v235 IDBs for 13 methods: `verifyMemoryMap`, `enterLinearMode`, `resetEngine`, `displayModeCount`, `displayModes`, `displayMemorySize`, `loadCRTC:gamma:pitchSize:resolution:crtTable:`, `loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:`, `querySize:size:`, `changeRefreshRate:`, `initBIOSBuf:function:`, `loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:`, and `+[ATIRageDisplayDriverVersion driverKitVersionForATIRageDisplayDriver]`. The candidate and reference typed exports were refreshed from live Hex-Rays output for those sections; all 13 sections per export now match exactly. Both IDBs decompile all 61 functions without exceptions, and the selector-local inventory contains no remaining `SEL a2`. Full export SHA-256: candidate `DDAFEA2DF4135BF33EF4644413703407696ED16436C63948E504A026EA8A0407`; reference `1D06F5F1486ACB5EC88E36BF1F2E04FA2F925A008A77FB936767FCBEFBAE55C7`. Metadata/export updates only; v235 bytes and Binrecon comparison inputs are unchanged.

### Linear-mode and VRAM-check local cleanup (2026-10-05)

Finished the source-backed local names in candidate v235 `-[ATI enterLinearMode]` (`info`, `depth`, `pitch`, `biosResult`, `driverName`, and `errorName`) and `-[ATI verifyMemoryMap]` (`savedVram`). The reference IDB already carried the corresponding names. Refreshed the candidate export sections from Hex-Rays; candidate and reference sections match live IDA exactly. Both databases decompile 61/61 functions without exceptions. Candidate export SHA-256: `96427086F21CC438714CCFDA93A7C6BDAC9778AB1E3FBEF7BF94131AD836B10F`; reference remains `1D06F5F1486ACB5EC88E36BF1F2E04FA2F925A008A77FB936767FCBEFBAE55C7`. These are IDA metadata and export updates only; v235 bytes and Binrecon comparison inputs are unchanged.

### BIOS transition wrapper typing and generated receiver (2026-10-05)

Typed `_ATIbios16`'s argument as `ATI_BIOSRegisters *` and named it `registers` in both v235 IDBs, matching the checked-in wrapper source and exposing field accesses at the established register layout. Named the generated version method's class receiver `self`. Refreshed both export sections from live IDA. Both IDBs still decompile 61/61 functions without exceptions, and the two affected export sections match live pseudocode exactly. Full export SHA-256: candidate `B85FC9CCE7AC0CD8E18B78A481BFB03CD606A5493187AF0FBDDC25442C93F1EE`; reference `C034D026A31D8CCB887C053BF757783A76F66EAD644796E0596E91934210B9D3`. Type/name metadata only; binary bytes and Binrecon results are unchanged.

### Engine-reset temporary recovery (2026-10-05)

Named the seven source/disassembly-backed temporaries in `-[ATI resetEngine]` in both v235 IDBs: the two D0 port values/addresses, their clear/set forms, and the A0 configuration value. Candidate and reference disassembly are instruction-for-instruction identical, including the three locked increments; only the counter symbol differs (`resetEngineWriteCounter` vs. reference `_xxx_92`). Refreshed both export sections; each matches live Hex-Rays, and both IDBs still decompile 61/61 functions without exceptions. Full typed-export SHA-256: candidate `6A63B3A2D612E16B00D915B90792B73F67980EA37EDBB37F7D01174320C1021B`; reference `565A485B03DFA14C89ECEFDFB058795CB7A5FC059CFE8D6AD321A38B24DAAA73`. This is annotation/export work only; binary and Binrecon comparison remain unchanged.

### Initializer failure-site reconstruction (2026-10-05)

IDA's full reference `-[ATI initFromDeviceDescription:]` decompilation has 12 `IOLog` sites; v235 has 8. The current source had combined four reference paths (both reset-port probes, VRAM verification, and framebuffer mapping) through one `initFailure` logger. Replaced that shared block with the four distinct reference messages and `[driver free]` returns, preserving the messages, branch conditions, and cleanup. The initializer source now contains 12 direct `IOLog` sites; the pre-existing missing-display-mode log and structure-assignment copy remain in the unbuilt source trial. Regenerated `source-map.json`: 59 mapped handwritten entries, no disputed boundaries, and two generated methods left unmapped. Main-source SHA-256: `226C3F389877DB38393DC0E879EC8350B10ABC1130CEC5FFC0F910EB08C9C27C`; source-map SHA-256: `BCBA165A99653AD28A119305D1380A4148F0F07C99035745B0CA4285C4E5AF9A`. No tests or native build were run; the last accepted binary remains v235 (`57C016AA253B8DCF069DB4FC0C887B3C1AC601E0475661159FCDEC3FCE1BB4E2`), so the compiler-shape effect and Binrecon parity of this source trial remain unverified. The prior native sync/build remains blocked by the automatic review result.

### PCI range control-flow audit (2026-10-05)

Compared current `fixDeviceDescriptionForPCI:` source with the complete typed candidate and reference pseudocode. The retry bound (`memoryRangeCount - 2`) equals the reference's separately materialized count (`memoryRangeCountTotal - 2`); its loop runs once per probed memory BAR, and each per-BAR scan resets the candidate to the chosen framebuffer base and advances by that BAR's size. The restoration loop similarly writes one memory BAR per probed memory range, with the same `0x10..0x27` register bound as the reference. BAR probing, low-address relocation, alignment arithmetic, VGA ranges, three legacy port ranges, setter reset/call/error paths, and the `FB Address` mask/threshold match. Differences in temporary counts, loop form, and register allocation are compiler/dataflow shape only; no source change is supported by this audit. The saved candidate/reference call sequences have identical ordered targets; Binrecon's call-site-relative mismatch is a layout consequence. Current source remains unbuilt, and v235's strict function-byte findings remain unchanged.

### BIOS CRTC command audit (2026-10-05)

Compared `-[ATI_BIOS loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` source with the complete reference pseudocode. Initialization and `resolution == 128` guards, BIOS buffer setup, mode/gamma/pitch flag composition in ECX low byte, resolution byte in ECX high byte, resolution-129 CRTC-table data segment setup (30 bytes, offset 136, BX 0), BIOS invocation, AH/error logging, and return values (0/1/2/3 or propagated setup error) match. The source's byte-buffer writes represent the same register fields as the reference's `ATI_BIOSRegisters` member accesses. Strict code parity remains a code-generation/layout finding; this audit found no semantic source correction.

### Transfer-table gray-loop instruction ordering (2026-10-05)

Inspected live IDA disassembly for candidate v235, candidate v236, and the reference `-[ATI setTransferTable:count:]`. The reference loads red and green bases, then reloads the blue base inside each grayscale iteration before reading `table[i]`; v235 loads the blue base after reading and shifting `table[i]`; v236 hoists the blue-base load before the loop. This explains why v236's extra normalized instruction did not improve the 124-instruction LCS against the reference. Current source places a blue-base read inside the loop before a compiler memory barrier and the source-byte read, but no accepted candidate was built from that current source state. Do not infer target parity from the source ordering; a compiler run and regenerated IDA/Binrecon comparison are needed to evaluate it. No source change was made in this audit.

### BIOS thunk entry relocation and blit semantics (2026-10-05)

Live IDA name/xref queries confirm the immediate descriptor targets in `setupCodeSegments` are each binary's own `__bios16` symbol: candidate target `0x2E7C` and reference target `0x2E48`. The current source computes the descriptor base from `_bios16 + 0xC0000000`, so the immediate difference is correct link relocation, not a hard-coded source defect. Also compared candidate/reference `_doBlit` pseudocode and current source: signed-direction absolute overlap distances, strict width/height overlap checks, source/destination reverse starts, direction bits, MMIO save/write/restore order, FIFO waits, and returned register base agree. No behavior change is indicated for either method; their strict findings are instruction/CFG layout differences.

The `_doBlit` comparison did uncover a source type mismatch: IDA gives `sourceYStart`, `destinationXStart`, and `sourceXStart` unsigned 32-bit locals on both binaries, but source had them as signed `int`. Changed those three declarations to `unsigned int` so coordinate packing and the `<< 16` operations use the recovered unsigned arithmetic. This is source-only and unbuilt; the v235 comparison remains unchanged.

Live IDA local-variable queries for `setTransferTable:count:` also show `initialShift` and `componentShift` as `char` in both candidate and reference. Narrowed the source's corresponding `shift` and `selectedShift` locals from `unsigned int` to `char`; all assigned shift values are 0 or 2, so their right-shift behavior is unchanged while the reconstructed types match the recovered byte-sized locals. This remains an unbuilt source edit.

The initializer's `queryData` local is `unsigned __int8 *` in both IDBs, while source declared `unsigned int *` and cast it back for each byte access. Changed the source local to `unsigned char *` and removed those redundant casts. Byte offsets and values are unchanged, and the method's source line count is stable; compilation remains unverified.

Added the IDA-recovered `ATI_SegmentDescriptor` source type (8 bytes, fields at offsets 0/2/4/5/6/7) and changed the four saved-descriptor byte arrays in `ATI_BIOSPrivate` to typed descriptors. The order and sizes remain 8 bytes each, followed by `stack_address` at offset 32; the existing 36-byte private-layout assertion remains, with a new 8-byte descriptor assertion. At the time of this note, setup code had not yet been converted to the recovered descriptor type; the layout assertions were uncompiled.

### CRTC loader register-allocation trial (2026-10-05)

Live IDA disassembly shows v235 initializes the gamma flag directly in `DL` (`xor dl,dl`; conditional `mov dl,10h`), whereas the reference initializes `AL`, copies it into `DL`, then reuses `AL` for the shifted pitch. Current `ATI_BIOS.m` has source-level `EAX`/`EDX` register variables (`gammaFlag`, `modeFlags`) and `ESI`/`EDI`/`EBX` constraints for resolution, receiver, and register buffer, specifically expressing the reference's register roles. This source trial is newer than the v235/v236 binaries and remains uncompiled; the expected instruction order is a hypothesis until a new native artifact can be produced and reanalyzed.


### Typed GDT descriptor reconstruction (2026-10-05)

Converted `-[ATI_BIOS setupCodeSegments]` to use `ATI_BIOSPrivate` and `ATI_SegmentDescriptor` members instead of saved raw descriptor bytes and offsets. The method still saves the original code16, thunk, and stack descriptors; computes the code16 and stack linear bases; derives the thunk base from `_bios16`; allocates and clears the 2048-byte BIOS stack; and writes the same access, limit, granularity, and present bits with volatile self-stores at the existing access/limit barriers. The saved descriptor fields remain in the IDA-confirmed offsets (0, 8, 16, and 24), with `stack_address` at 32 and a 36-byte private record. Source-map entry for `setupCodeSegments` is line 418. No native compile or Binrecon comparison was run; v235 remains the last accepted binary, and native execution remains blocked by the earlier automatic-review rejection. Static whitespace validation passed.


### PCI BAR local signedness reconstruction (2026-10-05)

Live reference IDA locals for `-[ATI fixDeviceDescriptionForPCI:]` type `reg`, `mask`, `probed`, `memoryCount`, `portCount`, the total range counts, and placement indices as signed `int`; `override` is `char`. The per-BAR retry count (`memoryRangeCount` in the reference) and current PCI register are `unsigned int`. Source now uses those signedness distinctions; the total count stays `int` while `count` and `current` are unsigned. The BAR masks are `-4` and `-16`, as in the reference. BAR counters stay bounded by six probed slots and their fixed legacy ranges; `reg` spans only 16 through 39, and address/size values remain unsigned. The declarations preserve those bounded control-flow domains. This remains uncompiled; the v235 binary, strict findings, and parity status remain unchanged.


The same PCI source block still declared its framebuffer-address config-table local as generic `id`, although reference Hex-Rays types it as `IOConfigTable *`, and the source calls `valueForStringKey:` through it. Changed that local to `IOConfigTable *`, matching the already typed config-table local in the initializer and mode-list updater. This pointer refinement preserves the same Objective-C object representation and selector sends; it is source-only and uncompiled.


### Typed BIOS descriptor save and restore (2026-10-05)

Replaced raw `unsigned int` indexing in the BIOS GDT save/restore paths with the recovered private record and `ATI_SegmentDescriptor` fields. `createDataSegment:size:` now saves the data descriptor as a typed 8-byte record; `restoreDataSegment` restores that record; `restoreCodeSegments` restores code16, thunk, and stack descriptors from their named private fields and frees `stack_address`. This follows reference IDA pseudocode, which expresses the same descriptor assignments and stack pointer. Updated BIOS source-map lines after the method bodies shortened. The two project source paths resolve to the same file and have identical SHA-256. Source-map schema validation passed with 59 mapped entries, two generated entries unmapped, and no disputed boundaries; `git diff --check` passed. No native build or Binrecon binary comparison has run.


### Typed BIOS register-block accesses (2026-10-05)

Replaced raw byte/word indexing in `initBIOSBuf:function:` and `loadCRTC_comm` with the recovered `ATI_BIOSRegisters` union fields. The writes still target EAX low byte, code/data selectors, entry offset, EBP stack offset, ECX mode/resolution bytes, EDX table offset, and EBX zero; the AH check/log now reads EAX high byte by name. The structure remains 48 bytes and the EBX-pinned pointer remains explicit in `loadCRTC_comm`. This follows reference Hex-Rays pseudocode and the recovered register-block layout. Native compilation and Binrecon comparison remain unverified.


### Typed BIOS service register accesses (2026-10-05)

Replaced remaining BIOS service byte/word pointer indexing with `ATI_BIOSRegisters` union members in `setVGAMode:`, `setApertureEnable:`, `shortQuery:`, `deviceQuery:`, DPMS/APM setters and getters, `getIOBaseAddress:`, and `getRefreshRate:`. Register roles now follow the live reference pseudocode: EAX low/high, EBX word/low, ECX low/high, and EDX word/dword. The 48-byte block and call/status flow are unchanged at source level. Refreshed BIOS source-line entries in the map. The remaining BIOS unit has no raw register-byte/word indexing in these service methods. Native compilation and binary parity remain unverified.


### BIOS private-record lifetime size (2026-10-05)

Changed the `ATI_BIOSPrivate` allocation and free sizes from duplicated `36` literals to `sizeof(ATI_BIOSPrivate)`. Reference IDA confirms both calls use 36 bytes, and the recovered private-record declaration has a compile-time 36-byte size assertion, so the emitted allocation extent remains the observed value while following the reconstructed type.


A follow-up comparison of the same method's reference locals showed separate unsigned `memoryRetryIndex`, `candidateRangeIndex`, `memoryBARIndex`, and `currentPCIRegister` roles. Replaced the source's shared `index`/`candidate`/`current` use in those two loops with these explicit counters, retaining signed `index` for the BAR-detection and placement scans. Their loop bounds and list counts remain the IDA-observed values. The source map's later main-file lines were advanced by four to track the added locals and assignment.


### Typed `ATI_BIOS` private-record ivar (2026-10-05)

Changed the `_priv` ivar from `void *` to `ATI_BIOSPrivate *` and removed the redundant casts at allocation and all four descriptor save/restore access sites. Reference IDA already renders `_priv` as `ATI_BIOSPrivate_Layout *`; the source type is now the matching reconstructed record. The ivar's pointer size and object layout stay unchanged on i386; the 36-byte record assertion remains authoritative for allocation extent.
