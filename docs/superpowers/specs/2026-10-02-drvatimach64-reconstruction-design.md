# drvATIMach64 i386 decompilation and reconstruction

## Intent and completion standard

Complete the decompilation and reconstruction of
`src/drivers-i386/video/drvATIMach64` against the shipped i386 kernel driver,
using the repository's BinRecon tools and IDA. On 2026-10-02 the user approved
the proposed binary-driven direction and explicitly requested both this
detailed design and its implementation plan. This authorization covers writing
both documents without an intervening document-review round. This document
records the proposed implementation; its existence does not mean that the
driver has been reconstructed.

The reconciled baseline contains **54 routine entries: 52 handwritten and two
build-generated**. IDA's initial 52-function inventory omits two assembly entry
points; it is not the complete reconstruction denominator. Every handwritten
entry needs a readable implementation, a source location, and an individual
behavioral review. Producing pseudocode, matching selector names, or compiling
the current skeleton does not establish completion.

Completion requires an actual i386 build and function-by-function comparison
against its resulting artifact. Automated normalized-function acceptance,
reviewed behavioral equivalence, and hardware execution are distinct results.
No unexplained functional mismatch may remain. Compiler or target-ABI
differences require specific evidence; an automated acceptance failure must
remain visible even when a reviewer explains it. Hardware validation is claimed
only after execution on a compatible device and ATI BIOS.

## 1. Authoritative artifacts and established findings

The reference kernel artifact is:

`C:\Users\raynorpat\Downloads\test\Drivers\i386\ATIMach64DisplayDriver.config\ATIMach64DisplayDriver_reloc`

| Property | Verified value |
| --- | --- |
| File size | 62,632 bytes |
| SHA-256 | `AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C` |
| Architecture | i386, little-endian Mach-O |
| Text section | `__TEXT,__text`, address `0`, size `10,371` (`0x2883`) bytes |
| Initial IDA function count | 52 |
| Reconciled routine inventory | 54 |
| Handwritten Objective-C methods | 43: 18 on ATI and its categories; 25 on ATI_BIOS and its private category |
| Handwritten C/assembly routines | 9 |
| Generated methods | 2 |
| Display-mode table | 54 records of 136 bytes |
| CRTC timing tables | 15 records of 30 bytes |

BinRecon's Mach-O reader and Objective-C metadata walker were used alongside
IDA enumeration and representative decompilation/disassembly. The initial
reference-only BinRecon run completed with IDA 9.4, a null diagnostic, and no
rebuilt comparison. Its `acceptance.passed` was false. The installed executable
is `C:/Program Files/IDA Professional 9.4/idat.exe`; the old sample 9.2 path
contains no executable on this host.

The probe summary is under `tools/binrecon/out/atimach64-probe/`; its temporary
profile resolved publications under `tools/binrecon/out/out/atimach64-probe/`.
These are ignored generated files, not the intended permanent output layout.
Execution must create the tracked profile under `tools/binrecon/profiles/` so
`../out/atimach64` resolves correctly.

The binary declares `ATI : IOFrameBufferDisplay`, `ATI_BIOS : Object`, and the
two generated classes. It also declares `ATI(Private)`, `ATI(ProgramDAC)`, and
`ATI_BIOS(Private)`. IDA display names omit category names; use metadata and
addresses to reconcile them. The present source instead declares
`ATIMach64DisplayDriver`, implements a single hard-coded display mode and a
guessed MMIO path, and omits the BIOS classes, timing data, transfer tables and
aperture negotiation. Its selector collisions require body review.

The current Default table registers `"Driver Name" = "ATI"` but the source
does not implement that class. It also substitutes an empty I/O-port list and
two memory ranges for the shipped aperture, VGA, and BIOS resource ranges.
The current `Load_Commands.sect` contains section names rather than the shipped
`WIRE` load command. These are reconstruction and integration defects within
this task's scope.

## 2. Scope and implementation approach

Reconstruct the ATI display class, both ATI categories, ATI_BIOS and its private
category, all nine handwritten C/assembly routines, and all reference data
they consume. Preserve BIOS discovery, descriptor/stack management, query
services, CRTC/VGA programming, aperture changes, mode validation, PCI
configuration, gamma/brightness, transfer-table lifetime, DPMS/APM and refresh
query behavior. Even the apparent no-op `changeRefreshRate:` requires an
individual reference review.

Readable historical C/Objective-C is the chosen representation. The two far
transfer routines belong in assembly because their segment, flags, stack and
self-modifying immediate operands are part of the ABI. Recover their source
instructions and symbolic relocations; do not embed the original module or
copy relocated machine addresses as constants. `ATIbios16` remains the C
validation wrapper unless instruction review establishes an assembly need.

Compare all shipped tables, modes, DriverInfo, localization and help resources
with repository resources. Preserve the Aggregate / Driver / Kernel Server
project hierarchy and packaging conventions. The 16,712-byte companion
`ATIMach64DisplayDriver` executable is not the kernel reconstruction reference;
inspect its role only to establish whether the existing build regenerates it
or packages it as a helper. Do not silently substitute it for `_reloc`.

The task changes this driver and its reconstruction evidence. Changes to
shared DriverKit, kernel, BinRecon, or build infrastructure require a concrete
driver blocker and a narrowly scoped correction. Other ATI drivers are useful
as build-pattern references, not as behavioral authorities. Preserve reference
ordering and failure behavior, including awkward cases, rather than inventing
new hardware support or error recovery.

## 3. Source organization and interfaces

All production source remains beneath
`src/drivers-i386/video/drvATIMach64/ATIMach64DisplayDriver.drvproj/ATIMach64DisplayDriver.lksproj/`.
Retain the existing main filenames to minimize project churn; their class
declaration becomes the recovered `ATI` class.

| Source unit | Responsibility |
| --- | --- |
| `ATIMach64DisplayDriver.h` / `.m` | ATI ivars and eight principal methods: initialization, free, mode transitions and accessors |
| `ATIPrivate.h` / `.m` | Seven ATI private methods, query ownership, mode validation, hardware/table mapping |
| `ProgramDAC.m` | Three ATI ProgramDAC methods, `SetGammaValue`, and `isATI68880RevC`; keep local linkage evidenced by the binary |
| `ATI_BIOS.h` / `.m` | ATI_BIOS ivars, 18 public/class methods and seven private methods |
| `ATIData.h` / `.c` | Mode/CRTC/gamma/value/refresh tables, globals and four conversion helpers |
| `ATIBIOSTypes.h` | The BIOS register block, descriptor/private storage layouts and assembly-facing declarations |
| `ATIbios16.c` | `ATIbios16` validation and dispatch wrapper |
| `ATIbios.s` | Exact Mach-O symbols `__bios16` and `__ATIbios32`, far transfers and scratch storage |
| `ATIMach64Regs.h` | Replace guessed MMIO definitions with only constants/access operations evidenced by reconstructed consumers |

This organization follows reference category and module names where available;
it does not assert recovery of every original translation-unit boundary.
Generated version/kernel-instance methods remain products of the build.
Direct Objective-C class references must be used, consistent with BinRecon's
repository guidance; `objc_getClass` string lookups are not a substitute.

Method spellings are fixed by the inventory in section 9. Recover declaration
types from runtime type encodings, caller stack slots, DriverKit declarations
and callee access widths. Decompiler `id`/`int` choices alone are insufficient.
Use the real headers in `src/driverkit-3/driverkit/`, including `displayDefs.h`
and `IOFrameBufferDisplay.h`. Do not preserve the skeleton's unsupported
selectors or `_pciDevice` abstraction without reference evidence.

## 4. Layout and data contracts

The reference ATI instance is 620 bytes with inherited storage ending at
offset 552. Preserve this own-ivar sequence on i386:

| Offset | Field / reference encoding |
| --- | --- |
| 552, 556, 560 | `redTransferTable`, `greenTransferTable`, `blueTransferTable` / `*` |
| 564, 568, 572 | `transferTableCount`, `brightnessLevel`, `modeNumber` / `i` |
| 576, 580, 584 | `vram` / `^v`, `vramBytes` / `I`, `currentState` / `i` |
| 588 | `isPCI` / `c` |
| 592, 596, 600 | `atiBios` / `@`, `queryData` / `^v`, `queryDataSize` / `I` |
| 604, 605 | `supportsGamma`, `supportsGrey256` / `c` |
| 608, 612, 616 | `colorConfig`, `fbMapStyle`, `ramdacStyle` / `i` |

ATI_BIOS has instance size 16: `initialized` at 4 (`c`), `segmentBase` at 8
(`I`), and `_priv` at 12 (`^v`). Its private allocation is 36 bytes: saved
descriptor slots plus a BIOS-stack pointer. Compare these against the actual
target superclass metadata. If the current DriverKit ABI differs, explain
the inherited-size change and verify every relative own-ivar access; do not
insert phantom padding or change shared classes simply to match offsets.

`IODisplayInfo` is 136 bytes in the reference. Preserve enum values rather
than treating `bitsPerPixel` as an integer bit count. The 54-mode table occupies
7,344 bytes at `0x427c`; count is at `0x5f2c`. Each mode's `parameters` points
to a recovered CRTC record. CRTC data is 15 consecutive 30-byte records starting
at `0x40b8`. Recover all fields and relocations, not just published mode names.
Gamma data is 16 bytes at `0x3621` and 256 bytes at `0x3631`.

Preserve the value/name tables `bitsPerPixelValues`, `colorConfigValues`,
`ATI_modeToRefreshRatesTable`, `ABReturnValues`, `ATI_AsicTypeValues`,
`ATI_AsicSubTypeValues`, `ATI_memSizeValues`, `ATI_dacTypeValues`, and
`ATI_busTypeValues`, plus `modeValidArray` and BIOS/assembly globals.
Names in the memory-size description table cover more values than
`memSizeToBytes` does. The latter maps codes 0..4 to 512 KiB, 1 MiB, 2 MiB,
4 MiB and 6 MiB; its default returns 2 MiB. Do not extend it based on the
description strings.

The BIOS register buffer is 48 bytes. Confirm every field by instruction
access before declaring `ATIBIOSRegisters`; established offsets are EAX `4`,
EBX `8`, ECX `12`, EDX `16`, EDI `20`, ESI `24`, EBP `28`, input code selector
`32`, input data selector `34`, output ES `36`, flags `40`, and entry offset
`44`. Preserve unnamed/reserved bytes as raw storage until a use establishes
their meaning. C/assembly boundaries must use the recovered widths and Mach-O
symbol spelling, including leading underscores.

## 5. Behavioral contracts requiring reconstruction

### BIOS execution and services

ROM discovery scans candidate bases from `0xc0000` through `0xeffff` at
`0x1000` intervals for signature `761295520` in the reference's bounded scan
window. The presence class method reports the candidate base through its
output pointer. Preserve init/free ownership and the reference's distinction
between uninitialized, success, BIOS error and invalid arguments.

Descriptor setup saves and updates GDT slots/selectors `0x80`, `0x88`, `0x90`
and `0x98` as used by the code; slot `0x88` is the optional data segment.
The stack allocation is `0x800` bytes. Descriptor base expressions contain
kernel-address translation and symbol relocations: verify them against the
i386 kernel ABI instead of copying IDA's displayed link addresses.
`initBIOSBuf:function:` clears 48 bytes and sets selectors, function/register
fields, stack frame, and entry offset. `doBios:dataSeg:` invokes the wrapper,
restores code descriptors, and conditionally restores the data descriptor.

`__bios16` switches stack/segments and patches a far-jump operand;
`__ATIbios32` saves registers/segments/flags, prepares the far-call operand,
disables interrupts for the call, copies returned registers back, and restores
the caller state. Verify full operand encodings and control transfers,
including bytes IDA initially marked as data. These routines must be wired
with the module as the reference requests. Also verify that the kernel loader
permits writes to the self-patched code operands: page residency from WIRE
alone does not establish code-page write permission. Confirm that the target
kernel exports the GDT dependency and retains the required address translation.
An ordinary userspace mock must never execute their privileged transitions.

For each public BIOS service recover function codes, register packing,
initialization checks, bounds, output writes, and return status independently.
Do not impose AH-error checks uniformly: different methods have different
checks. Known boundary cases include DPMS input 4 accepted and masked to 0,
APM inputs above 3 rejected, data-segment sizes above `0x10000` rejected,
CRTC resolution `0x80` rejected, and resolution `0x81` using a 30-byte data
segment. Refresh query uses a 20-byte buffer. Review zero-size descriptor
underflow and createDataSegment failure paths directly rather than improving
their cleanup by assumption.

### Initialization, mode and mapping flow

Initialization calls the superclass, discovers/creates ATI_BIOS, obtains
query data and capability bits, updates mode information, reads configuration
strings, selects/validates a mode, negotiates aperture/table mappings, enables
the aperture, maps VRAM, and verifies the mapping. Preserve this actual order,
including the initial updateModeList call before configuration overrides.
Initial brightness is 64; state begins at 0. Linear mode becomes state 1 only
after successful BIOS mode programming and clears all VRAM before gamma load.
Successful VGA reversion frees the owned transfer allocation and sets state 2.

Mapping policy accepts Default/BIOS/Table preferences, checks the BIOS's
aperture restriction, and can retry at `0x07800000`. The PCI path writes and
reads configuration register `0x10`. Table mapping requires exactly three
memory ranges and preserves the two auxiliary ranges; failed replacement
attempts restore the original range. Preserve returned IOReturn values and
the order of resource release/reacquisition.

Mode validity has independent unsupported-color and VRAM-size checks.
Established return bits are `0x10` for an index beyond the list, `0x40` for
unsupported color capability/configuration, and `0x02` for insufficient VRAM.
Verify signed-index behavior and exact count boundaries without introducing
checks the reference lacks. The VRAM test saves/writes/checks 64 bytes; failure
returns before the success-path restore. Document that behavior explicitly.

### DAC, brightness and transfer ownership

Recover actual port I/O and delay operations. Representative DAC operations
use `0x62ec`, `0x5eec`, `0x5eed` and `0x5eef`; no generic MMIO rewrite is implied.
`SetGammaValue` scales each component by brightness and shifts right by six,
then writes RGB in order with the reference delay after each write. Determine
whether IDA's InterlockedIncrement rendering represents the project's I/O
delay implementation before coding it.

Brightness 0..64 succeeds and reloads gamma; other values return nil without
updating state. Transfer-table storage is one allocation of `3 * count` with
three channel slices. Recover grayscale/RGB byte extraction, Sparse/Dense
overrides, ASIC/DAC exceptions, the ATI68880 revision read, replacement/free
ownership and fallback gamma loops. Preserve the behavior for supported table
counts; investigate 0, negative and non-dividing counts through callers and
the reference before defining their test expectations.

## 6. BinRecon and evidence architecture

Create `tools/binrecon/profiles/atimach64.json` as a reference-only profile
initially: architecture `i386`, endianness `little`, reference
`${BINRECON_REFERENCE}`, IDA 9.4 at the installed path, timeout 900 seconds,
acceptance `normalized-functions`, and output directory `../out/atimach64`.
Add `${BINRECON_REBUILT}` after an actual build exists. IDA is the selected
analyzer for this task. Ghidra/angr are initially disabled by scope; do not
claim they failed on this binary or that single-analyzer consensus supplies
independent corroboration.

Keep binaries, IDBs, pseudocode, disassembly, normalized analyses, transcripts
and logs under ignored `tools/binrecon/out/atimach64/` or `out/i386/drvATIMach64/`.
Track these review artifacts under `src/drivers-i386/video/drvATIMach64/reconstruction/`:

- `function-worklist.md`: all 54 entries, responsible source unit, evidence
  addresses, review conclusions and actual check results.
- `divergences.md`: reference/rebuild identities, tools, ABI/build differences,
  analyzer limitations and hardware-validation status.
- `ATIMach64DisplayDriver_reloc/source-map.json` and `ledger.json`: valid
  existing BinRecon schemas with individual reviewed evidence.
- Target-specific analysis/export and evidence-verification scripts plus
  focused test sources, as laid out in the implementation plan.

Three observed tool limitations need explicit handling:

1. `objc_method_index` drops IMP address zero because it tests truthiness.
   Recover `-[ATI initFromDeviceDescription:]` at zero from the defined text
   symbol and module/class metadata; assert it remains in every inventory.
2. Stock IDA analysis exports 52 functions, omitting `__bios16` at `0x26e0`
   and `__ATIbios32` at `0x27b8`. Recover function boundaries and embedded far
   operands in a task-owned IDB without altering input bytes. Export the
   corrected database using BinRecon's existing collector/normalizer and
   validate the resulting analysis-v1 document. Keep this reviewed export
   distinct from stock runner publications and their summary hashes.
3. BinRecon source scanning recognizes `.m` and `.c`, not `.s`. Add the two
   assembly source mappings using verified global labels and actual line
   numbers, then run the semantic source-map loader. Do not introduce fake
   C definitions to make the source scanner count assembly.

If valid normalization of the self-modifying far operands needs a tool change,
first demonstrate the failing reference instruction and create a focused
regression. A narrowed tooling correction is permissible; silently deleting
those routines, accepting partial decode, masking arbitrary constants, or
editing evidence into a passing state is not. Any remaining machine-analysis
limitation must be reported as such and prevents a full automated-parity claim.

Final coverage is 54 accounted entries, 52 handwritten source mappings and
two explicitly identified build-generated exceptions. Generated source may
live outside the repository, so its two source-map entries can remain unmapped
with precise worklist/ledger explanations. No handwritten entry may remain
unmapped, duplicated, boundary-disputed or unexamined. Reviewed statuses
describe evidence; matching names or tool-generated ledger entries do not
justify `assembly-matched` or reviewer approval.

## 7. Verification and build integration

Use reference-driven focused checks for:

- i386 object/record layouts and mode/CRTC/gamma/value-table content;
- BIOS-buffer packing, service status/output rules and descriptor restoration;
- mode validity, mapping preference/retry/rollback and VRAM-test behavior;
- mode-transition order, query ownership and transfer-table free behavior;
- DAC read/write/delay traces, brightness limits and color-channel extraction;
- complete inventories, source-map/ledger partition and generated exceptions.

Test drivers must compile the production units with test-only substitutes for
BIOS calls, GDT storage, allocation, port I/O and the necessary DriverKit
message interfaces. They must observe call/write transcripts and allocation
ownership, not duplicate the production algorithms in a second model.
Expected constants/transcripts come from independently reviewed instructions
and reference bytes. Host tests cannot establish the i386 ABI; verify layouts
using the actual i386 compiler and emitted production metadata.

Build the driver's real Aggregate / Driver / Kernel Server projects using a
verified Rhapsody-era i386 compiler/toolchain and existing `pb_makefiles` /
rbuild workflow. Read `vm/sync-src.ps1`, `vm/guest-remote.ps1` and their local
configuration/path behavior before syncing. Use private source, object, state,
output and package areas as required by the helpers; do not overwrite another
ongoing build. If a boot/runtime experiment is performed, use a temporary disk
image as CLAUDE.md requires.

Fix active source/header/assembly lists through `Makefile.preamble` /
`Makefile.postamble` where possible; reconcile PB.project files if needed.
Restore shipped `WIRE`, server name `ATIMach64DisplayDriver`, instance symbol
`ATIMach64DisplayDriver_instance`, and server version `2`. Preserve the existing
build-generated Server Name table behavior rather than reintroducing a
duplicate field. Validate all four configuration/mode variants and help paths.
Provide driver-local package metadata only where required by the chosen
existing build workflow.

Retain compiler/linker versions, complete build command, exit status, warning
review, artifact/package manifest and hashes. Compare this actual rebuilt
`ATIMach64DisplayDriver_reloc`, not an old binary or intermediate object.
Produce stock BinRecon comparisons and, where necessary, explicit comparisons
of the corrected complete IDA analyses. Validate imports, class references,
category selectors, globals, table identities, loaded-server metadata and
all 54 routine pairings. Explain compiler differences individually instead
of treating relocation masking as a universal equivalence proof.

## 8. Acceptance gates and risks

| Gate | Required result |
| --- | --- |
| Inventory | 54 entries reconciled by address; zero-address initializer and both assembly entries retained |
| Reconstruction | All 52 handwritten routines implemented and individually reviewed; both generated methods checked |
| ABI/data | Target layouts checked; 54 modes, 15 CRTC records, gamma/value/refresh tables and relocations accounted for |
| Behavior | Focused reference-driven checks pass for BIOS, descriptors, mapping, mode state and DAC/ownership paths |
| Build/package | Actual i386 driver/package build succeeds; resources, class identity and WIRE/server fields are correct |
| Parity evidence | Every routine paired with rebuild or explained; no unresolved functional mismatch; actual machine acceptance reported |
| Evidence integrity | Valid source map and ledger, 52 handwritten mappings, two documented generated exceptions, current artifact hashes |
| Runtime claim | Explicit compatible-device result, or explicit statement that hardware validation was not performed |

The largest risks are the privileged BIOS far transfers, changes in the kernel
virtual/GDT ABI, decompiler register/selector ambiguity, configuration mapping
rollback, and transfer-table ownership. Handle them early through ABI capture,
instruction review, isolated tests and narrow assembly comparisons. Failure
to establish one of these is a real incomplete item, not a reason to replace
it with a guessed implementation or reduce the completion denominator.

## 9. Complete address inventory

Addresses are reference entry addresses. `G` identifies build-generated methods.
Category names are recovered from Objective-C metadata. The two assembly
entries absent from the initial IDA function list are marked `A`.

| Entry | Reference name | Definition unit | Kind |
| --- | --- | --- | --- |
| `0x0000` | `-[ATI initFromDeviceDescription:]` | `ATIMach64DisplayDriver.m` |  |
| `0x0aa0` | `-[ATI free]` | `ATIMach64DisplayDriver.m` |  |
| `0x0b30` | `-[ATI enterLinearMode]` | `ATIMach64DisplayDriver.m` |  |
| `0x0c48` | `-[ATI revertToVGAMode]` | `ATIMach64DisplayDriver.m` |  |
| `0x0cd4` | `-[ATI displayModeCount]` | `ATIMach64DisplayDriver.m` |  |
| `0x0ce0` | `-[ATI displayModes]` | `ATIMach64DisplayDriver.m` |  |
| `0x0cec` | `-[ATI displayMemorySize]` | `ATIMach64DisplayDriver.m` |  |
| `0x0d08` | `-[ATI setPendingDisplayMode:]` | `ATIMach64DisplayDriver.m` |  |
| `0x0d84` | `-[ATI(Private) getQueryData]` | `ATIPrivate.m` |  |
| `0x0eb4` | `-[ATI(Private) parseModeString:]` | `ATIPrivate.m` |  |
| `0x0f4c` | `-[ATI(Private) updateModeList]` | `ATIPrivate.m` |  |
| `0x10e8` | `-[ATI(Private) isModeValid:]` | `ATIPrivate.m` |  |
| `0x1170` | `-[ATI(Private) verifyMemoryMap]` | `ATIPrivate.m` |  |
| `0x11d4` | `-[ATI(Private) changeHardwareMapping:]` | `ATIPrivate.m` |  |
| `0x1334` | `-[ATI(Private) changeTableMapping:]` | `ATIPrivate.m` |  |
| `0x1490` | `_isATI68880RevC` | `ProgramDAC.m` |  |
| `0x14c0` | `_SetGammaValue` | `ProgramDAC.m` |  |
| `0x1514` | `-[ATI(ProgramDAC) setGammaTable]` | `ProgramDAC.m` |  |
| `0x1648` | `-[ATI(ProgramDAC) setBrightness:token:]` | `ProgramDAC.m` |  |
| `0x1684` | `-[ATI(ProgramDAC) setTransferTable:count:]` | `ProgramDAC.m` |  |
| `0x1870` | `_displayInfoToColorSpace` | `ATIData.c` |  |
| `0x18d8` | `_colorDepthToColorSpace` | `ATIData.c` |  |
| `0x1928` | `_displayInfoToColorDepth` | `ATIData.c` |  |
| `0x1978` | `_memSizeToBytes` | `ATIData.c` |  |
| `0x19ec` | `+[ATIMach64DisplayDriverKernelServerInstance kernelServerInstance]` | `Build-generated` | G |
| `0x19f8` | `+[ATIMach64DisplayDriverVersion driverKitVersionForATIMach64DisplayDriver]` | `Build-generated` | G |
| `0x1a04` | `+[ATI_BIOS ATIPresent:]` | `ATI_BIOS.m` |  |
| `0x1aa0` | `-[ATI_BIOS init]` | `ATI_BIOS.m` |  |
| `0x1b44` | `-[ATI_BIOS initAtSegmentAddress:]` | `ATI_BIOS.m` |  |
| `0x1b88` | `-[ATI_BIOS free]` | `ATI_BIOS.m` |  |
| `0x1bcc` | `-[ATI_BIOS loadCRTC:gamma:pitchSize:resolution:crtTable:]` | `ATI_BIOS.m` |  |
| `0x1c00` | `-[ATI_BIOS setVGAMode:gamma:]` | `ATI_BIOS.m` |  |
| `0x1c9c` | `-[ATI_BIOS loadCRTCSetMode:gamma:pitchSize:resolution:crtTable:]` | `ATI_BIOS.m` |  |
| `0x1cd0` | `-[ATI_BIOS setApertureEnable:VGAAperture:apertureAdrs:]` | `ATI_BIOS.m` |  |
| `0x1da0` | `-[ATI_BIOS shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:]` | `ATI_BIOS.m` |  |
| `0x1e6c` | `-[ATI_BIOS querySize:size:]` | `ATI_BIOS.m` |  |
| `0x1e80` | `-[ATI_BIOS deviceQuery:bufferSize:buffer:]` | `ATI_BIOS.m` |  |
| `0x1f40` | `-[ATI_BIOS setDPMSMode:]` | `ATI_BIOS.m` |  |
| `0x1fc8` | `-[ATI_BIOS getDPMSMode:]` | `ATI_BIOS.m` |  |
| `0x203c` | `-[ATI_BIOS setAPMState:]` | `ATI_BIOS.m` |  |
| `0x20c4` | `-[ATI_BIOS getAPMState:]` | `ATI_BIOS.m` |  |
| `0x2138` | `-[ATI_BIOS getIOBaseAddress:relocatable:]` | `ATI_BIOS.m` |  |
| `0x21b4` | `-[ATI_BIOS getRefreshRate:]` | `ATI_BIOS.m` |  |
| `0x2258` | `-[ATI_BIOS changeRefreshRate:]` | `ATI_BIOS.m` |  |
| `0x2264` | `-[ATI_BIOS(Private) initBIOSBuf:function:]` | `ATI_BIOS.m` |  |
| `0x22b4` | `-[ATI_BIOS(Private) setupCodeSegments]` | `ATI_BIOS.m` |  |
| `0x2438` | `-[ATI_BIOS(Private) restoreCodeSegments]` | `ATI_BIOS.m` |  |
| `0x24a0` | `-[ATI_BIOS(Private) createDataSegment:size:]` | `ATI_BIOS.m` |  |
| `0x2574` | `-[ATI_BIOS(Private) restoreDataSegment]` | `ATI_BIOS.m` |  |
| `0x2598` | `-[ATI_BIOS(Private) doBios:dataSeg:]` | `ATI_BIOS.m` |  |
| `0x25dc` | `-[ATI_BIOS(Private) loadCRTC_comm:gamma:pitchSize:resolution:crtTable:function:name:]` | `ATI_BIOS.m` |  |
| `0x26e0` | `__bios16` | `ATIbios.s` | A |
| `0x2758` | `_ATIbios16` | `ATIbios16.c` |  |
| `0x27b8` | `__ATIbios32` | `ATIbios.s` | A |

## 10. Implementation handoff

Execute the companion plan
`docs/superpowers/plans/2026-10-02-drvatimach64-reconstruction.md` after review.
Its tasks proceed through evidence/ABI recovery, BIOS execution/services,
mapping/modes, principal display flow, DAC handling, build integration and
final parity review. Native execution is recommended because the descriptor,
register-buffer and source-mapping details are shared across dependent tasks.
No driver implementation or guest mutation was performed while preparing
these documents.
