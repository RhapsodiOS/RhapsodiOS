# Binary reconstruction of drvPCFloppy

Reconstruct `drvPCFloppy` against Apple's shipped `Floppy_reloc`, using the
`tools/binrecon` toolchain. A mechanical pre-pass repairs defects that the
reference symbol table proves directly, a report pass maps every reference
function to our source and records the divergences, and five layered fix phases
resolve them.

This continues
[2026-07-25-bus-driver-binary-reconstruction-design.md](2026-07-25-bus-driver-binary-reconstruction-design.md),
[2026-07-25-intel-bus-driver-binary-reconstruction-design.md](2026-07-25-intel-bus-driver-binary-reconstruction-design.md)
and
[2026-07-25-i386-input-driver-binary-reconstruction-design.md](2026-07-25-i386-input-driver-binary-reconstruction-design.md).
Everything those efforts built — the `binrecon source-map` subcommand, the
`load_source_map` semantic loader, the `reconstruction/` artifact layout, the
`ledger-v1` vocabulary and `tools/binrecon/parity_check.py` — is in place and is
reused unchanged. `vm/build-i386-floppy.sh` already exists and is the build
harness.

## Motivation

`src/drivers-i386/README` marks drvPCFloppy "needs compiled and then tested".
That line is stale: the driver has built since `7f1c93a6`, which staged
`out/i386/drvPCFloppy/Floppy.config/Floppy_reloc`. What it has never been is
checked against the binary Apple shipped.

Scoping this work read the reference symbol table, string table and import list
directly, before any analyzer run. Against the staged rebuild,
`parity_check.py` reports:

```
missing_strings   94
missing_symbols  163   (of the reference's 225)
extra_strings     32
extra_symbols    489
```

163 of 225 reference functions are absent by name from a driver that compiles
cleanly. The tree is a shell: the control flow was decompiled, but the selector
names, the diagnostics, the name-lookup tables and seventeen C functions were
dropped. Four of the eight findings in §2 mean the driver cannot work at all.

## 1. Scope

### 1.1 Target

`C:\Users\raynorpat\Downloads\test\Drivers\i386\Floppy.config\Floppy_reloc`.

| Property | Value |
|---|---|
| File size | 124,956 |
| `__TEXT,__text` | 37,724 bytes |
| `__text` symbols | 225 — 196 ObjC methods, 29 C functions |
| `__TEXT,__cstring` | 151 entries, 3,167 bytes |
| Undefined imports | 93 |
| Sections | 30, including the four `Loaded Server` sections |

This is the second-largest i386 driver after EIDE and roughly five times
drvPCParallel.

Our tree is `src/drivers-i386/ide/drvPCFloppy`: 19 `.m` and 20 `.h` files,
about 14,000 lines, every file carrying "From decompiled code" comments.

### 1.2 Config tables and resources are in scope

`Default.table`, `English.lproj/Localizable.strings`,
`English.lproj/Help/Floppy.rtfd`, and `Load_Commands.sect` measured against the
`Loaded Server` sections.

`Load_Commands.sect` already matches the reference's
`Loaded Server,Load Commands` byte for byte apart from a trailing space on the
first line. That is recorded here and is not a finding.

### 1.3 Out of scope

The sibling `Floppy` file. It is a 16,680-byte `MH_BUNDLE` with a 34-byte
`__text` whose only external symbols are `_Floppy_VERS_STRING` and
`_Floppy_VERS_NUM`. It is emitted by the build and has no source counterpart to
reconstruct.

Three reference functions are build-generated and are never written by hand:
`__udivdi3` (libgcc), `+[FloppyKernelServerInstance kernelServerInstance]` and
`+[FloppyVersion driverKitVersionForFloppy]` (both `kl_ld`).

Functional floppy testing — booting a guest, attaching the driver, reading a
floppy image — is out of scope. The done bar in §5 is build plus parity.
Functional testing is a separate follow-up.

## 2. Findings that shaped this design

All eight were established from the Mach-O symbol, string and import tables
before any analyzer run.

### 2.1 A systematic underscore rename breaks every override

Of 234 method definitions in our tree, 56 match a reference selector exactly,
**161 match only after dropping exactly one leading underscore**, and 17 match
neither. The rename is present in headers and implementations alike:

```objc
/* IODiskNew.h */
- _registerDevice;		// nil return means failure
- (unsigned)_diskSize;
- _free;
```

`free`, `registerDevice` and `readAt:length:buffer:actualLength:client:` are
selectors DriverKit sends. A method named `_free` overrides nothing, so the
driver cannot function.

The repair rule is **drop exactly one** leading underscore, never strip all of
them. Four reference selectors legitimately begin with an underscore:

```
-[IODiskPartitionNEW(Private) _freePartitions]
-[IODiskPartitionNEW(Private) _initPartition:disktab:]
-[IODiskPartitionNEW(Private) _probeLabel:]
-[IOLogicalDiskNEW(private) _diskParamCommon:length:deviceOffset:bytesToMove:]
```

Our tree writes these as `__freePartitions`, `__initPartition:`, `__probeLabel:`
and `__diskParamCommon:`, so the single-drop rule lands them correctly while a
strip-all rule would break them.

### 2.2 Ninety-four reference strings are missing

Ninety-nine reference `__cstring` entries are absent from our sources and 94 from
the rebuild; the difference is entries the compiler emits more than once. The
missing set is every diagnostic message plus the entire name-lookup layer:
`FCCMD_*` (16), `FDCMD_*` (6), `FD_DENS_*` (4), `FD_MID_*` (4), `FDIOC*` and
`DKIOC*` (13), and the error-string table — `"Disk Write Protected"`,
`"Missing Address Mark"`, `"Controller rejected command"`,
`"Unexpected controller phase change"` and the rest.

The reference imports `_IOFindNameForValue`, so these are `IONamedValue` tables
consumed by name lookup, not loose literals.

### 2.3 Seventeen C functions have no counterpart

Absent from our sources entirely:

```
FloppyControllerThread   OperationThreadStartup   HandleBsdWrite
docopy                   dowire                   fakeStrategySuccess
fdTimer                  floppyDriveType          identifyBsdDev
identifyDetachedDiskIdFromBsdDev                  numFloppyDrives
physContBlocks           queueOperationAscending  queueOperationDecending
sweepQueueInsert         sweepQueueReorder        vFloppyCopy
```

Eleven other reference C functions are present. `HandleBsdWrite` being the one
absent member of an otherwise complete `HandleBsd*` set is itself a signal.

### 2.4 Nine methods are unimplemented stubs

`IODiskNew.m` leaves `registerDevice`, `free`, `eject`,
`getIntValues:forParameter:count:`, `errnoFromReturn:`, `stringFromReturn:`,
`lockLogicalDisks` and `unlockLogicalDisks` as `TODO: Implement …`; `FloppyCnt.m`
leaves command-transfer execution the same way.

### 2.5 Three selector shapes and one category name are wrong

Surviving the rename of §2.1:

| Reference | Ours |
|---|---|
| `-[IOFloppyDisk initFromDeviceDescription::::]` | `initFromDeviceDescription:drive:capacity:writeProtected:` |
| `-[IOFloppyDrive initFromDeviceDescription:::]` | `initFromDeviceDescription:controller:unit:` |
| `-[IOFloppyDisk(Geometry) cylinderFromBlockNumber:::]` | `cylinderFromBlockNumber:head:sector:` |
| `IOLogicalDiskNEW(private)` | `IOLogicalDiskNEW(Private)` |

Apple declared the first three with empty keywords. Named keywords produce a
different selector, so these are not overrides either.

### 2.6 Four lock classes are reimplemented instead of linked

`NXLock.m` implements `NXLock`, `NXConditionLock`, `NXSpinLock` and
`NXRecursiveLock` locally. Its header is a verbatim copy of `src/machkit-1/NXLock.h`.

The reference defines none of them. It imports three as undefined symbols:

```
.objc_class_name_NXLock
.objc_class_name_NXConditionLock
.objc_class_name_NXSpinLock
```

So Apple linked them from the kernel. `NXRecursiveLock` appears nowhere in the
reference and is invented outright. This is the defect recorded in `8890be17`:
reconstructed sources must link classes, not reimplement them.

`NXLock.m` and `NXLock.h` are listed in the `Makefile` but absent from
`PB.project`, so the two build descriptions already disagree about them.

### 2.7 `Default.table` has two divergences

Ours omits `"Version" = "5.10";`, and writes `"Boot Driver" = "";` where the
reference has the bare key `"Boot Driver";`.

### 2.8 There is no `English.lproj`

The reference bundle ships `English.lproj/Localizable.strings`:

```
"Floppy" = "Floppy Disk";
"Long Name" = "Floppy Disk Drive";
```

and `English.lproj/Help/Floppy.rtfd`. Our tree has neither. drvEIDE and drvVGA
both carry theirs under `<name>.drvproj/English.lproj/`.

### 2.9 The DMA bounce-buffer path is absent, not merely divergent

Comparing the reference's 93 undefined symbols against the staged rebuild's,
seven reference imports are ones we never call:

```
_alloc_cnvmem            _get_dma_addr        _dma_xfer_abort
_vm_map_pageable         _vm_map_pmap_EXTERNAL
_strcpy                  .objc_category_name_IOLogicalDiskNEW_private
```

The first five are the DMA bounce-buffer path, and they correspond exactly to the
missing C functions `docopy`, `dowire`, `vFloppyCopy` and `physContBlocks` from
§2.3. The last is the category-name divergence from §2.5. Import parity is
therefore a third verification axis, orthogonal to string and symbol parity and
just as cheap, and §5 adopts it.

## 3. Artifact layout

### 3.1 Committed

```
src/drivers-i386/ide/drvPCFloppy/reconstruction/
    source-map.json      # source-map-v1, complete 225-function partition
    ledger.json          # ledger-v1, human-reviewed parity ledger
    divergences.md       # report-pass findings, including table divergences
tools/binrecon/profiles/floppy.json
```

`floppy.json` is copied from `parallelport.json` with `output_dir` set to
`../out/floppy`, IDA 9.2 and angr 9.3.0 enabled and Ghidra disabled, with one
difference from every other committed i386 profile: it carries a `rebuilt` block
resolving `${BINRECON_REBUILT}` alongside `reference`. Unlike drvPCParallel and
its siblings we already have a staged rebuild, so `binrecon compare` can run and
the ledger can carry a real `rebuilt_sha256` instead of `null`. `acceptance` is
`normalized-functions`; our build is unstripped, so `exact-image` is
unreachable.

### 3.2 Not committed

Everything under `tools/binrecon/out/floppy/`, which `.gitignore:17` already
excludes. The `.i64` databases, `.log` files and `.lock` files are machine- and
run-specific. The durable evidence is the source map, the ledger and the
divergence document, all of which are text.

`out/i386/drvPCFloppy/Floppy.config/Floppy_reloc` is a 791 KB binary still
tracked in the repository. `6713ce0c` set the policy that rebuilt artifacts under
`out/` are guest build output rather than source, added `out/` to `.gitignore`
and untracked drvSerialPointingDevice's staged files — but it missed
drvPCFloppy's. Untracking them is part of this work (§7). The files stay on disk
and `vm/build-i386-floppy.sh` regenerates them; only the Git tracking changes.

### 3.3 Reference paths

Per shell session:

```
BINRECON_REFERENCE = C:\Users\raynorpat\Downloads\test\Drivers\i386\Floppy.config\Floppy_reloc
BINRECON_REBUILT   = <repo>\out\i386\drvPCFloppy\Floppy.config\Floppy_reloc
```

## 4. The three kinds of pass

### 4.1 Mechanical pre-pass

A deliberate carve-out from the standing discipline that fixes touch only what
the ledger flags. It is justified because every change rests on evidence stronger
than a decompilation: the reference symbol table, the reference bundle's own
files, or a contradiction internal to our tree. No analyzer run is needed and no
ledger entry authorises them, because the ledger does not exist yet.

Without it, a report pass would flag essentially every function for one reason
and drown the real per-function findings.

Each step is its own commit and each ends with a green build.

| Step | Change | Verify |
|---|---|---|
| 0a | Drop exactly one leading underscore from the 161 renamed method declarations, definitions and call sites (§2.1) | No underscore-prefixed selector remains except the four listed in §2.1; build exits 0 |
| 0b | Reshape the three selectors to Apple's empty-keyword form and correct the category name to `(private)` (§2.5) | All four names appear in the rebuilt symbol table |
| 0c | Delete `NXLock.m` and `NXLock.h`, drop them from the `Makefile`, import `machkit/NXLock.h` and link the kernel's classes; drop `NXRecursiveLock` (§2.6) | Rebuild imports `.objc_class_name_NXLock`, `NXConditionLock` and `NXSpinLock` and defines none of them |
| 0d | `Default.table`: add `"Version" = "5.10";`, change `"Boot Driver" = "";` to the bare `"Boot Driver";` (§2.7) | Diff against the reference table is empty but for `"Driver Version"` |
| 0e | Add `English.lproj/Localizable.strings` and `English.lproj/Help/Floppy.rtfd` from the reference bundle; register them in `PB.project` (§2.8) | The harness stages both into `Floppy.config` |

Step 0c gates everything after it and is attempted first within the pre-pass, for
the reason given in §6.

Expected after 0a–0e: `parity_check.py` `missing_symbols` falls from 163 to about
20 — the 17 absent C functions of §2.3 plus the 3 build-generated entries of
§1.3.

### 4.2 Report pass

Needs no guest.

1. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/floppy.json`
   produces IDA 9.2 and angr 9.3.0 analyses plus `consensus-reference.json`
   under the gitignored `tools/binrecon/out/floppy/`. The run exits 1 on
   `normalized-functions` acceptance, because our unstripped 791 KB build cannot
   match a 125 KB reference. That is expected, is not a gate, and still writes a
   machine-readable summary.

2. **Map.** `binrecon source-map --reference-analysis … --binary … --source-dir …
   --repo-root … --output …`, anchored on the Mach-O symbol table, then
   hand-resolve the residue. Every one of the 225 functions lands in exactly one
   bucket:

   - `mapped` — resolved to a file and line.
   - `unmapped` — with a stated reason class. Two classes are used here:
     `absent-from-sources` for the 17 C functions of §2.3, and
     `build-generated` for the 3 of §1.3.
   - `boundary_disputed` — analyzers disagree on function extent.
   - `duplicate_candidates` — a name resolves to two or more plausible sites.

3. **Diff.** Decompile every `mapped` function and compare against our source,
   batched by source file. The comparison covers control-flow shape, literal
   constants, I/O port addresses, struct field offsets and call targets.

4. **Compare tables.** Diff `Default.table` and `Localizable.strings` against the
   reference copies, ignoring `"Driver Version"`. Both are expected clean after
   0d and 0e; a residual difference is a pre-pass defect, not a new finding.

5. **Report.** Write `divergences.md` with the reference decompilation beside our
   source for each finding, and assign every function a `ledger-v1` status. The
   ledger records parity confidence, not a repair queue; its vocabulary is
   `unexamined`, `signature-confirmed`, `control-flow-confirmed`,
   `assembly-matched` and `intentional-mismatch`. A function that matches gets
   the strongest status the evidence supports. A function that diverges stays
   `unexamined` and gets an entry in `divergences.md`, per the convention
   established by the drvPCIBus pass.

**Done when** `load_source_map(path, reference_analysis=…, repo_root=…)` passes —
it enforces the complete function partition, names, full function sizes and
source-line bounds — every `unmapped` entry has a stated reason class in
`divergences.md`, and no function remains without a ledger entry.

### 4.3 Fix phases

Five phases, each a separate commit series, each beginning only after the report
pass is committed. Per phase: fix, run `vm/build-i386-floppy.sh`, run
`parity_check.py` and the import diff, advance the ledger, commit. A phase that
raises `missing_symbols`, `missing_strings` or the import gap is a regression and
does not commit.

The order is bottom-up by dependency. The controller layer comes first because it
is the smallest phase and depends on nothing, which makes it a cheap pilot for
the fix-verify loop. The generic disk family comes second rather than fourth
because `IOFloppyDisk` and `IOFloppyDrive` inherit from `IODiskNEW` and
`IODriveNEW`, and all nine stubs of §2.4 live in that family; repairing a
subclass whose superclass is still a stub cannot be validated.

| # | Phase | Files | Functions | `__text` bytes | Carries |
|---|---|---|---|---|---|
| 1 | Controller | `FloppyCnt.m`, `FloppyCntIo.m`, `FloppyCmds.m`, `FloppyArch.m` | 28 | 7,132 | `FloppyControllerThread`, `fdTimer`, the `FCCMD_*` and error-string tables |
| 2 | Generic disk family | `IODiskNew.m`, `IODriveNEW.m`, `IOLogicalDiskNEW.m`, `IODiskPartitionNEW.m`, `kernelDiskMethodsNEW.m` | 83 | 7,508 | all nine stubs of §2.4, the `DKIOC*` and disk-label strings |
| 3 | Drive | `IOFloppyDrive.m`, `FloppyDriveInt.m`, `FloppyDriveInt2.m`, `VolCheck.m` | 50 | 6,824 | `floppyDriveType`, `numFloppyDrives`, the `FDCMD_*`, `FD_DENS_*` and `FD_MID_*` tables |
| 4 | Disk and geometry | `IOFloppyDisk.m`, `Geometry.m`, `Request.m`, `Thread.m`, `Support.m` | 50 | 11,612 | `OperationThreadStartup`, `queueOperationAscending`, `queueOperationDecending`, `sweepQueueInsert`, `sweepQueueReorder`, and the DMA bounce path of §2.9 |
| 5 | BSD | `Bsd.m` | 11 | 4,360 | `HandleBsdWrite`, `identifyBsdDev`, `identifyDetachedDiskIdFromBsdDev`, `fakeStrategySuccess` |

Counts cover 222 of the 225 reference functions; the remaining three are the
build-generated entries of §1.3.

**Disposition.** Every finding in `divergences.md` is resolved one of two ways.
Either the source is changed to match the reference, after which the function's
ledger status advances to the level the new evidence supports, or the divergence
is accepted and the status becomes `intentional-mismatch` with a reason and a
reviewer, both of which the ledger CLI requires. Accepted by default:
build-generated glue, compiler-emitted statics, and anything whose reference form
depends on Apple's toolchain rather than on our source.

**Discipline.** Fixes touch only code the ledger flags. The pre-pass of §4.1 is
the single exception, and it completes before the ledger exists. No adjacent
cleanup, no refactoring of code that is not divergent.

## 5. Verification and the done bar

Three axes against the rebuilt `Floppy_reloc`, all reported per phase and gating
at the end.

1. **Build.** `vm/build-i386-floppy.sh` exits 0 and `Floppy_reloc` stages to
   `out/i386/drvPCFloppy/`. This gates every phase, not just the last.
   Warnings are captured to a log and reviewed but do not gate.

2. **String and symbol parity.** `tools/binrecon/parity_check.py` against the
   reference's `__TEXT,__cstring` set and `__TEXT,__text` symbol names.
   Baseline today: 94 missing strings, 163 missing symbols.

3. **Import parity.** Reference undefined symbols absent from our rebuild.
   Baseline today: 7 (§2.9). This axis catches calling the wrong kernel API,
   which neither string nor symbol parity detects.

Extras on our side are never findings on their own: the build is unstripped and
today carries 489 extra symbols and 32 extra strings.

`parity_check.py` compares symbol names as a set, so a name defined more than
once in one binary collapses to a single entry. drvPCFloppy's 225 `__text`
symbol names are fully distinct, so this is not a limitation here.

**Done when** all of the following hold:

- the build is green and `Floppy_reloc` is staged;
- `missing_symbols` is 0 but for the three build-generated entries of §1.3;
- `missing_strings` is 0, or every remainder carries an `intentional-mismatch`
  ledger entry with a reason and a reviewer;
- the import gap is 0, or every remainder is dispositioned the same way as a
  missing string;
- `load_source_map` passes against the committed source map;
- all 225 functions carry a ledger status of `signature-confirmed` or better, or
  `intentional-mismatch`.

## 6. Failure modes

**`machkit/NXLock.h` is not reachable from a loadable kernel driver's include
path.** Then step 0c cannot link and the whole pre-pass stalls. It is attempted
first within the pre-pass for exactly this reason. Fallback: keep the local file
reduced to declarations only, link nothing, and record `intentional-mismatch`
against the affected functions with the include-path constraint as the reason.

**Some of the 17 absent C functions are inlined into callers rather than
missing.** Then the fix is extraction, not authorship, and writing them fresh
would introduce a second divergence. The report pass distinguishes the two cases
before any code is written, which is the reason the map precedes the fixes.

**IDA and angr disagree on function boundaries** across 37 KB of `__text`. The
`boundary_disputed` bucket absorbs this; a disputed function receives a weaker
ledger status rather than a guess.

**Phase 4 is the largest and least constrained.** At 11,612 bytes it is a third
of `__text`, and the DMA bounce path within it is absent wholesale rather than
divergent, which puts it closest to authorship rather than reconstruction. If it
overruns, it splits at the `Request.m` / `Thread.m` boundary rather than being
rushed.

**The report pass finds far more per-function divergence than the eight findings
of §2 suggest.** The findings above are what the symbol, string and import tables
alone reveal; control-flow divergence is invisible to them. If the divergence
count makes a phase impractical, that phase splits by file rather than dropping
findings, and `divergences.md` records the split.

## 7. Deliverables

- `tools/binrecon/profiles/floppy.json`.
- `src/drivers-i386/ide/drvPCFloppy/reconstruction/source-map.json`,
  `ledger.json` and `divergences.md`.
- The five pre-pass commits of §4.1.
- The five fix-phase commit series of §4.3.
- `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/English.lproj/` with
  `Localizable.strings` and `Help/Floppy.rtfd`.
- A corrected drvPCFloppy status line in `src/drivers-i386/README`.
- `out/i386/drvPCFloppy/` untracked, completing the policy `6713ce0c` set (§3.2).
