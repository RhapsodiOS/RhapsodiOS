# Completing the binary reconstruction of drvIBMThinkPad760EDDisplay

Finish `IBMThinkPad760EDDisplayDriver_reloc` against Apple's shipped i386
binary. The July track already replaced the invented driver with Apple's
partition and produced a compiling `_reloc`. This spec closes in-scope
byte-level extents, reconstructs `vidBIOS` and `_emu486` from **this**
binary, and emits the missing version symbols.

This continues
[2026-07-26-cirrus-thinkpad-display-reconstruction-design.md](2026-07-26-cirrus-thinkpad-display-reconstruction-design.md)
for the ThinkPad track only. Cirrus is not reopened. drvVGA is a read-only
cross-check for `vidBIOS` / `_emu486`; its sources are not copied and not
patched.

The report, source map, ledger vocabulary, `parity_check.py`,
`tools/binrecon/profiles/thinkpad760ed.json`, and
`vm/build-i386-video-recon.sh` are reused. Config tables and localized
resources already match Apple and are not in this spec.

## Motivation

`src/drivers-i386/README` marks this driver "reconstructed in part, last
verified build at fd0e7355; 29 of the driver's functions compile and produce a
`_reloc`, but only 17 match the reference and `vidBIOS.m`/`_emu486` remain
deferred to drvVGA; not yet tested."

That is accurate, and it is no longer the right end state. drvVGA has since
landed `vidBIOS.m` and `emu486.s`, so the July deferral is not blocked on a
missing reconstruction elsewhere. The ThinkPad `_reloc` still cannot load:
`.objc_class_name_vidBIOS` is undefined, `_emu486` is absent, twelve
in-scope extents still differ, the ledger's `rebuilt_sha256` is a
placeholder copy of the reference, and `_VERS_STRING` / `_VERS_NUM` were
never linked.

The July spec treated `vidBIOS` / `_emu486` as VGA's job so this driver
would not duplicate them. Completing *this* driver means reconstructing those
units from this binary (the two copies are independently linked, 156 bytes
apart) and using VGA only to notice disagreements.

## 1. Scope

### 1.1 Target

`C:\Users\raynorpat\Downloads\test\Drivers\i386\IBMThinkPad760EDDisplayDriver.config\IBMThinkPad760EDDisplayDriver_reloc`

| Property | Value |
| --- | --- |
| Mach-O type | MH_PRELOAD |
| File size | 73,168 bytes |
| SHA-256 | `47539E03C441BBFD6724EB6778D85BFACD0961B78A8DFA33D56321C938EB5AEC` |
| `cpu_subtype` | 4 (`CPU_SUBTYPE_486`) |
| `__text` | 18,204 bytes, 40 functions |
| Profile | `tools/binrecon/profiles/thinkpad760ed.json` (already present) |

`BINRECON_REFERENCE` is that `_reloc` path. Our source directory stays
`src/drivers-i386/video/drvIBMThinkPad760EDDisplay`. The Kernel Server `NAME`
stays `IBMThinkPad760EDDisplayDriver`.

The 16,724-byte `IBMThinkPad760EDDisplayDriver` MH_BUNDLE beside the
`_reloc` remains out of scope: it is dyld glue only, same as Cirrus and
`drvS3Generic`.

### 1.2 In scope

- The 29 already-written functions in `IBMThinkPad760ED.m`,
  `TransferTable.m`, and `smapi.s`, including the 12 extent mismatches.
- `vidBIOS.m` (six methods, `__text` 6552–7708) reconstructed from this
  binary.
- `emu486.s` (`_emu486` at 7708, plus the unnamed bodies at 15796 and
  15877) reconstructed from this binary.
- `_IBMThinkPad760EDDisplayDriver_VERS_STRING` and `_VERS_NUM`, emitted by
  this lksproj linking `$(VERS_OFILE)`.
- Guest rebuild, kept `_reloc`, `parity_check.py`, IDA on the rebuild,
  `binrecon compare` (`normalized-functions`), source-map refresh, ledger
  advancement, and the ThinkPad line in `src/drivers-i386/README`.

### 1.3 Out of scope

- `drvCirrusLogicGD5434`, `drvVGA`, and every other video driver.
- Installing `kernelserver.make.preamble` on the guest. Version symbols are
  this driver's `Makefile.preamble` only. Cirrus and VGA may keep missing
  theirs.
- QEMU, hardware, and any boot test. QEMU does not model a Trident
  TGUI9660.
- Exact match of the 1998 timestamp inside `_VERS_STRING`.
- Changing binrecon itself, unless a profile path or rebuilt artifact
  variable is wrong.
- Re-enabling Ghidra or angr. Existing disablement reasons in
  `divergences.md` stand.

## 2. Findings that shaped this design

These are already in
`src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/divergences.md`.
The implementation plan checks itself against them. A rebuild may refine
byte counts; it does not reopen §3.

### 2.1 In-scope source exists; 17 of 29 extents match

Last measured rebuild: commit `fd0e7355`. Seventeen in-scope functions
match their reference extent exactly, including all four `TransferTable`
methods, `_smapi_asm`, `_set555Mode`, and `enterLinearMode`. Twelve do not:

| Function | Δ (rebuilt − ref extent) | Status at spec time |
| --- | --- | --- |
| `initFromDeviceDescription:` | +8 | Explained: gcc merged two `IOLog` tails. Accepted compiler-only delta. |
| `updateModeTable` | −12 | Diagnosed; uncompiled edit in `1cb44e28`. |
| `revertToVGAMode` | −4 | Open; needs rebuilt instruction stream. |
| `getModeInfo:` | −4 | Open; needs rebuilt instruction stream. |
| `determineConfiguration:` | +8 | Diagnosed (control-flow error, not just bytes); uncompiled edit in `1cb44e28`. |
| `setPCIConfiguration` | −12 | Open; needs rebuilt instruction stream. |
| `setPendingDisplayMode:` | −60 | Diagnosed; uncompiled edit in `1cb44e28`. |
| `setDisplayDeviceState:` | −4 | Open; one cheap experiment left (`cx.x` association). |
| `unlockRegisters` | −16 | Diagnosed (nested `outb(inb)`); not yet applied. |
| `lockRegisters` | −16 | Same as `unlockRegisters`. |
| `reportSystemConfiguration` | +28 | Open; first check is whether the rebuilt prologue has `sub esp`. |
| `name` | −4 | Diagnosed; uncompiled edit in `1cb44e28`. |

Commit `1cb44e28` has never been compiled. Treat it as a hypothesis until
Phase 1 rebuilds it.

### 2.2 `vidBIOS` / `_emu486` are this binary's, not VGA's files

The six `vidBIOS` methods occupy 6552–7708 here and 6396–7551 in
`VGA_reloc` — the same 1,156 bytes. `_emu486` follows. That is evidence of
shared *source*, not a license to copy VGA's files into this tree.

This `_reloc` also attributes `_xxx.8` / `_xxx.11` / `_xxx.14`
(`outb`/`outw`/`outl`) to the deferred region. VGA's `vidBIOS.m` does not
include `driverkit/i386/ioPorts.h` because VGA's only `_xxx` triple lives
in `IOVGADisplay.m`. ThinkPad `vidBIOS.m` follows this binary: if those
statics belong to that TU, this file includes `ioPorts.h` even though VGA's
does not.

`vidBIOS.m` must not go in `CLASSES`. Apple links it after the generated
`IBMThinkPad760EDDisplayDriver_instance.o`. `emu486.s` must not go in
`OTHERLINKED`; that list is how `smapi.s` already sorts *before* the
instance object.

### 2.3 Version symbols are a project-local link gap

`next-sgs.make` can generate `$(NAME)_vers.c`. Nothing links `$(VERS_OFILE)`
unless `OTHER_GENERATED_OFILES` contains it. Apple's Kernel Server project
type does that in `kernelserver.make.preamble`. This spec does not install
that preamble on the guest. This lksproj's `Makefile.preamble` adds
`OTHER_GENERATED_OFILES += $(VERS_OFILE)` itself.

`vers.o` is const-only. If it inserts `__text` between `smapi.o` and
`_instance.o`, that is a defect in how it is linked, not a reason to edit
reconstructed functions.

### 2.4 The ledger has never seen a real rebuild

Every ledger entry is `unexamined`. `rebuilt_sha256` is
`47539E03…B5AEC`, the reference hash. `analysis-rebuilt-ida.json` was run on
a placeholder copy of the reference. No entry leaves `unexamined` until
`rebuilt_sha256` is a guest artifact with a different hash.

### 2.5 `kl_ld` already produces a `_reloc`

A relocatable link leaves `.objc_class_name_vidBIOS` undefined instead of
failing. Phase 1 therefore still produces a `_reloc` that `parity_check.py`
can read, still missing `_emu486` and the eight `vidBIOS` strings. That is
expected until Phase 2.

## 3. Architecture

Two sequential phases against one `_reloc`. Phase 1 does not add
`vidBIOS`, `emu486`, or `_vers.o`, so `__text` 0–6552 stays comparable to
`fd0e7355`.

```
Apple IBMThinkPad760EDDisplayDriver_reloc
        │
        ▼
Phase 1  IBMThinkPad760ED.o  TransferTable.o  smapi.o  _instance.o
         close in-scope extents; keep out/i386/_reloc
        │
        ▼
Phase 2  + vers.o  + vidBIOS.o  + emu486.o   (OPTIONAL_LDFLAGS after instance)
         reconstruct from this binary; VGA is a diff, not a source
        │
        ▼
parity_check.py → IDA on rebuild → binrecon compare → ledger
```

Object order after Phase 2:

```
IBMThinkPad760ED.o
TransferTable.o
smapi.o
IBMThinkPad760EDDisplayDriver_vers.o     # __TEXT,__const only
IBMThinkPad760EDDisplayDriver_instance.o
vidBIOS.o
emu486.o
```

`vidBIOS.o` and `emu486.o` reach `kl_ld` through `OPTIONAL_LDFLAGS`, the
same path VGA uses for `emu486.o`. `vm/build-i386-video-recon.sh` compiles
`vidBIOS.m` and assembles `emu486.s`, then exports those objects into the
make invocation. It stops claiming the symbols stay undefined.

**Source of truth.** Every instruction, ivar, string, and `_xxx` static
comes from this `_reloc`. VGA's `vidBIOS.m` / `emu486.s` are read after a
first complete ThinkPad draft. Differences are recorded in `divergences.md`
with both addresses. VGA is not edited. VGA is not copied in to close a
diff.

**Accepted compiler deltas.** Exact extents where source can force them.
When gcc's merge or allocation cannot be forced from source that otherwise
matches the reference statement-for-statement, the function stays as
written, the reason goes in `divergences.md`, and the ledger is
`control-flow-confirmed`, not `assembly-matched`.
`initFromDeviceDescription:` starts on that list. Further members are
added only after a rebuilt instruction stream shows the same class of
cause.

## 4. Components

**Phase 1 — existing TUs**

| Unit | Job |
| --- | --- |
| `IBMThinkPad760ED.m` | Close the diagnosed and remaining in-scope extents. |
| `IBMThinkPad760ED.h` | Unchanged in Phase 1 (`@class vidBIOS` stays). |
| `TransferTable.m` | Already extent-exact. Do not edit unless a rebuild proves otherwise. |
| `smapi.s` | Already extent-exact. Do not edit. |

**Phase 2 — new TUs and glue**

| Unit | Job |
| --- | --- |
| `vidBIOS.m` | Six methods from this `__text` 6552–7708. Not in `CLASSES`. |
| `emu486.s` | `_emu486` plus the 15796 / 15877 bodies. Only exported symbol is `_emu486`. Labels are `L`-prefixed ThinkPad addresses so they stay out of the symbol table. Apple's three emulator defects are transcribed, not fixed. Not in `OTHERLINKED`. |
| `IBMThinkPad760ED.h` | Replace `@class vidBIOS` with `@interface vidBIOS : Object` (three ivars). Move the BIOS register block type out of `IBMThinkPad760ED.m` so both TUs share it. `extern int emu486(...)`. |
| lksproj `Makefile.preamble` | `OTHER_GENERATED_OFILES += $(VERS_OFILE)` and `OPTIONAL_LDFLAGS` for the extra objects. |
| `vm/build-i386-video-recon.sh` | Compile/assemble the extra objects; pass them in; drop the undefined-symbol note. |

**Records (both phases)**

| Unit | Job |
| --- | --- |
| `reconstruction/divergences.md` | Extent table, compiler-only list, VGA disagreements, version-symbol note, build status. |
| `reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json` | After Phase 2, all 40 entries `mapped`. `_smapi_asm` maps to `smapi.s`; the two `_instance.m` methods map as generated glue. |
| `reconstruction/IBMThinkPad760EDDisplayDriver_reloc/ledger.json` | `rebuilt_sha256` is the guest artifact. Reviewer `Pat Raynor`. |
| `tools/binrecon/profiles/thinkpad760ed.json` | Unchanged shape. `BINRECON_REBUILT` points at the real `out/i386/` artifact for compare. |

`IBMThinkPad760EDDisplayDriver_instance.m` stays generated. Do not write it
by hand.

## 5. Data flow

**Phase 1 loop.** Edit in-scope `.m` from the extent table and queued
diagnoses. Guest-build with the four-object list. Copy the `_reloc` to
`out/i386/` and keep it for the whole session. Re-measure extents
(next-symbol gaps, padding included). Repeat until every in-scope function
is exact or listed as compiler-only.

First rebuild of Phase 1 is `1cb44e28` as it stands: confirm it compiles,
then re-measure before applying `unlockRegisters` / `lockRegisters` or
starting the five open deltas.

**Phase 2 loop.** Write `vidBIOS.m` and `emu486.s` from this disassembly.
Diff against VGA; record; do not copy. Guest-build with version object and
`OPTIONAL_LDFLAGS`. `parity_check.py` must then report 0 missing symbols
and 0 missing strings. Point `BINRECON_REBUILT` at that artifact, run IDA
on it, run `binrecon compare`, refresh the source map, advance the ledger.

**Runtime path (unchanged, for orientation).** SMAPI / CMOS / Trident
sequencer / mode table stay in `IBMThinkPad760ED.m`. Int 10h is
`IBMThinkPad760ED` → `vidBIOS` → `_emu486`. DAC / gamma stays in
`(TransferTable)`. Version symbols sit in `__TEXT,__const` and are
unreferenced.

## 6. Artifact layout

### 6.1 Committed

```
src/drivers-i386/video/drvIBMThinkPad760EDDisplay/
    IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj/
        IBMThinkPad760ED.m
        IBMThinkPad760ED.h
        TransferTable.m
        smapi.s
        vidBIOS.m          # Phase 2
        emu486.s           # Phase 2
        Makefile.preamble
    reconstruction/
        divergences.md
        IBMThinkPad760EDDisplayDriver_reloc/source-map.json
        IBMThinkPad760EDDisplayDriver_reloc/ledger.json
src/drivers-i386/README
vm/build-i386-video-recon.sh
```

### 6.2 Not committed

The reference bundle, rebuilt `_reloc` under `out/i386/`, and analyzer
output under `tools/binrecon/out/` (already gitignored).

## 7. Error handling

**Guest down or compile fails.** Stop. Do not advance the ledger, do not
claim extents, do not apply the next source batch. There is no local
cross-toolchain. If the current tree (including the uncompiled `1cb44e28`
extent edits) does not compile, fix those edits before any new extent work.

**Extent still wrong after a high-confidence edit.** Keep the rebuilt
`_reloc`. Diff *our* instruction stream against the reference. Do not stack
another hypothesized rewrite on an unmeasured binary. If the remaining
delta is compiler merge or allocation, add it to the accepted list and
ledger `control-flow-confirmed`. No helpers, no `#ifdef`s, no invented
functions to chase bytes.

**`vidBIOS` / `_emu486` disagree with VGA.** This `_reloc` wins. Record the
range and the VGA address. Do not patch drvVGA. Do not copy VGA source in.
Transcribe Apple's three emulator defects.

**`parity_check.py` / `binrecon compare`.** Stab extras from `-g` (source
filenames, `:f19`, empty name) are extras, not failures. Missing `_emu486`,
missing `vidBIOS` strings, extra real `__text` symbols, or invented
selectors are failures: fix source or the link list, then rebuild.

`normalized-functions` requires every compared function to be
`assembly-matched`. Accepted compiler-only functions will make
`acceptance.passed` false. That is expected. Compare is still run; the
report is evidence. Done does **not** require `normalized-functions=PASS`
while any accepted compiler-only function remains. It does require that
every function *not* on that list is `assembly-matched` in the compare
report.

**`vers.o` shifts `__text`.** Defect in `Makefile.preamble` / harness, not
in reconstructed functions. Fix the link so instance stays at 6528 and
`vidBIOS` at 6552 relative to the in-scope span.

**Placeholder analysis.** IDA on a copy of the reference is not a rebuild.
`rebuilt_sha256` must change before any ledger entry leaves `unexamined`.

## 8. Testing and done bar

No QEMU, no hardware, no boot.

| Gate | Pass means |
| --- | --- |
| Phase 1 compile | `make` exits 0; three in-scope objects compile; `_reloc` kept in `out/i386/`. |
| Phase 1 extents | Each of the 29 is exact, or named in `divergences.md` as compiler-only with a mechanism. `1cb44e28` has been through the compiler. |
| Phase 1 parity | Still allowed to miss `_emu486` and the eight `vidBIOS` strings. No extra in-scope strings. |
| Phase 2 link | `kl_ld` list is the order in §3. `.objc_class_name_vidBIOS` is not in `nm -u`. `_emu486` is defined. |
| Version symbols | `_IBMThinkPad760EDDisplayDriver_VERS_STRING` and `_VERS_NUM` exist in `__TEXT,__const`. Timestamp may differ from 1998. |
| Phase 2 parity | 0 missing symbols, 0 missing strings. Stab extras only. |
| Compare | `binrecon compare` run on the real rebuild. Every function not on the compiler-only list is `assembly-matched`. |
| Source map | 40 `mapped`, 0 deferred-unmapped. |
| Ledger | `rebuilt_sha256` is the guest artifact, not `47539E03…`. Matching functions `assembly-matched`; accepted compiler deltas `control-flow-confirmed`; generated instance glue `assembly-matched` if the rebuild matches, else recorded. Reviewer `Pat Raynor`. |
| README | ThinkPad line says reconstructed against the reference, built, ledger advanced, not hardware-tested. |

`pytest tools/binrecon/tests` runs only if this work changes binrecon. It is
not expected to.

## 9. Sequencing

**Phase 1 — Close in-scope extents.**

1. Rebuild the current tree, including the uncompiled `1cb44e28` extent
   edits. Keep the `_reloc`.
2. Re-measure the twelve. Apply `unlockRegisters` / `lockRegisters` if
   still open. Settle the five unexplained deltas against that instruction
   stream.
3. Update `divergences.md` with the new table and any accepted
   compiler-only entries.

*Verify:* Phase 1 compile and extent gates.

**Phase 2 — Complete the `_reloc`.**

1. Write `vidBIOS.m` and `emu486.s` from this binary. Promote the BIOS
   register type and `vidBIOS` interface into `IBMThinkPad760ED.h`.
2. Diff against VGA; record disagreements.
3. `Makefile.preamble`: `$(VERS_OFILE)` and `OPTIONAL_LDFLAGS`. Update
   `vm/build-i386-video-recon.sh`.
4. Guest build. `parity_check.py`. IDA on the rebuild. `binrecon compare`.
5. Refresh source map and ledger. Update `src/drivers-i386/README`.

*Verify:* every remaining gate in §8.

Phase 2 source may be drafted on the host before the guest is up; it is
not committed as "done" without the Phase 2 compile and compare gates.
