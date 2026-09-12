# Binary reconstruction of drvDPT2000

Reconstruct `drvDPT2000` against Apple's shipped i386 `DPTSCSIDriver_reloc`,
using `tools/binrecon`. A report pass maps every reference function to our
source and records the divergences. A fix pass replaces the Linux-`eata.c`
stub `DPTSCSIDriver` with Apple's two classes `EATAController` and
`EATASCSIBus`, then a guest compile stages the `_reloc` the existing project
emits.

This continues the i386 SCSI work recorded in
[scsi-reconstruction.md](../../drivers/scsi-reconstruction.md) and reuses the
binrecon report/fix pattern from
[2026-07-25-bus-driver-binary-reconstruction-design.md](2026-07-25-bus-driver-binary-reconstruction-design.md),
the 1542B pass under `src/drivers-i386/scsi/drvAdaptec1542B/reconstruction/`,
and
[2026-09-10-adaptec6x60-reconstruction-design.md](2026-09-10-adaptec6x60-reconstruction-design.md).

## Motivation

`src/drivers-i386/README` marks this driver "stub, 10/55 reference functions;
missing the whole EATASCSIBus class." That is accurate. The tree is one ObjC
class named `DPTSCSIDriver`. The tables already name the real pair,
`EATAController EATASCSIBus`. The types header says it is based on Linux
`eata.c`; the interrupt path comment says the same. Filling in the current
files under the wrong class name cannot produce Apple's driver.

This is not a 6X60-style "wrong chip protocol" clone of 1542B. It is an
EATA-shaped sketch of the right protocol, with the wrong class names, no
second class, Linux layouts, and invented selectors. The reloc is the only
structural source.

The 1542B, BusLogic, and 6X60 reconstructions already proved the
report/ledger pipeline on this SCSI series.

## 1. Scope

### 1.1 Target

`C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc`

| Property | Value |
| --- | --- |
| File size | 53,952 bytes |
| SHA-256 | `5AE7A361F645EC693444A8AFC829DB477F34DE2576AFC0EB2A0D4128D3BD68A6` |
| `__text` symbols | 55 (from the SCSI survey; the report pass is the partition of record) |
| Profile | `tools/binrecon/profiles/dpt2000.json` (add; reference-only; same shape as `adaptec6x60.json`) |

`BINRECON_REFERENCE` is that `_reloc` path. The shipped config directory is
`DPTSCSIDriver.config`, not `DPT2000.config`. Our source directory stays
`src/drivers-i386/scsi/drvDPT2000`; it is not renamed. Kernel Server
`DRIVERNAME` stays `DPT2000`. Table `"Server Name"` stays `DPTSCSIDriver`.
Source filenames become `EATAController.*` and `EATASCSIBus.*`.

### 1.2 Config tables and resources are in scope

Compared against the reference bundle:

- `Default.table`
- `DPT_EISA.table`
- `DPT_PCI.table`
- `DPT_OnBoard.table`
- `DriverInfo`
- `Load_Commands.sect`
- `English.lproj/Localizable.strings`
- `English.lproj/DPT_EISA.strings`
- `English.lproj/DPT_PCI.strings`
- `English.lproj/DPT_OnBoard.strings`
- `English.lproj/Help/DPT_ISA.rtfd`
- `English.lproj/Help/DPT_EISA.rtfd`
- `English.lproj/Help/DPT_PCI.rtfd`
- `English.lproj/Help/DPT_On_Board.rtfd`
- `English.lproj/Help/TableOfContents.rtf`

`"Driver Version"` is emitted by Apple's build and stays out of the table
comparison, same as the Intel bus reconstruction.

### 1.3 Out of scope

`English.lproj/IntrInspector.nib` and any `DYLDLINK` inspector bundle beside
the `_reloc` are user-space inspector artifacts, not kernel driver code.

No QEMU run, no hardware test, and no `binrecon compare` of a rebuilt artifact
against the reference. The rebuilt `_reloc` is staged as compile proof only.
DPT SmartRAID is not a QEMU device.

Linux `eata.c` and DPT EATA programming documentation may name registers and
bits; offsets, widths, polarity, control flow, ivars, and symbol names come
from the `_reloc`. Linux is not a structural template.

The other i386 SCSI stubs (`drvAdaptec6X60`, `drvBusLogicFP`, `drvSym53C8xx`,
`drvAdaptec2940`) are not part of this spec. `scsi-reconstruction.md` is
updated for DPT2000 when this work finishes.

## 2. Findings that shaped this design

These come from the SCSI survey, the current tree, and a direct read of the
reference bundle during brainstorming. They are recorded so the plan can be
checked against them. The report pass may refine counts; it does not reopen
the architecture decision in §3.

### 2.1 Two classes, one of them missing

Reference `"Class Names"` is `EATAController EATASCSIBus` in every table.
Our headers declare `@interface DPTSCSIDriver : IOSCSIController`. After
correcting that class-name divergence, the survey resolved 10 of 55
`__text` symbols. `EATASCSIBus` is absent entirely (~19 methods across the
class and its `(PrivateMethods)` category).

`scsi-reconstruction.md` already records this. The fix is a second class,
not more methods on `DPTSCSIDriver`.

### 2.2 The current engine is Linux-shaped, not Apple-shaped

`DPTSCSIDriverTypes.h` comments that register offsets are "Based on Linux
eata.c". `DPTSCSIDriver.m` `interruptOccurred` comments "Based on Linux
eata.c interrupt handling" and reads a CP address from `REG_LOW`..`REG_MSB`.
`DPTSCSIDriverThread.m` calls `outl(ioBase + EATA_CP_ADDR, ...)` even though
`EATA_CP_ADDR` is not defined. `AUX_IRQ` and `STAT_IRQ` are used without
matching the `EATA_AUX_*` / `EATA_STAT_*` names in the types header.

`struct eata_cp` in our header glues a hardware prefix to a software
extension (`sg_list`, `in_use`, `cpQ`, `senseData`). That layout is not a
source of offsets. Ivar, CP, and SP layouts are read from the reloc.

### 2.3 Invented symbols must go

Unless the reloc uses these exact names, they do not remain as live code
after the fix pass: `DPTSCSIDriver`, `eataInitController`, `eataResetBus`,
`eataAllocateResources`, `eataFreeResources`, `allocCp`, `freeCp:`,
`runPendingCommands`, `processCmdComplete:`, and the Linux-shaped
`struct dpt_config`.

Selectors that already match the reloc still get rewritten if their bodies
call the Linux path.

### 2.4 The reference bundle disagrees with our extras and has help we lack

Our tree has `English.lproj/Localizable.strings` only (`"Driver Name" =
"DPT2000"`). The reference has `"DPTSCSIDriver" = "DPT 2021"` plus three
per-table string files we lack.

Our tree has no help RTFDs. The tables already point at
`DPT_ISA.rtfd`, `DPT_EISA.rtfd`, `DPT_PCI.rtfd`, and `DPT_On_Board.rtfd`.

Starting table drift (not complete; the report pass diffs every file in
§1.2):

- `Default.table`: ours `"Family" = "SDSI"`; reference `"SCSI"`. Reference
  also has `"Location"` and `"IRQ Levels" = "15"`.
- `DPT_PCI.table`: ours `"Share IRQ Levels" = "NO"` and a default
  `"IRQ Levels" = "15"`; reference `"YES"` and no default IRQ line.

## 3. Architecture

Two ObjC classes. One EATA host. No HIM/sequencer layer unless the reloc
has standalone C functions that need a home. EATA is a command-packet
protocol; firmware runs SCSI phases.

```
IOSCSIController client
        │
        ▼
EATASCSIBus          (new files; ~19 methods)
        │
        ▼
EATAController       (replaces DPTSCSIDriver.*)
        │  EATA CP / SP
        ▼
DPT SmartRAID / EATA ports   (ISA / EISA / PCI / onboard)
```

`EATASCSIBus` is the SCSI-facing class: likely what clients talk to.
`EATAController` owns the adapter: probe, ports, IRQ/DMA, command packets
and status packets. Superclasses, who implements `executeRequest`,
IOThread vs direct call, whether there are extra C helpers, and whether
the reloc instantiates one `EATASCSIBus` per channel or one per controller
are report-pass facts. This spec does not invent them.

`DPTSCSIDriver.*` is retired once the new names are in place.
`DPTSCSIDriverRoutines.m` is not kept as a Linux-eata file. It either
becomes helpers the reloc defines, or it is removed.

## 4. Components

**Rewrite (rename files)**

| Unit | Job |
| --- | --- |
| `EATAController.m` / `.h` | Host adapter. Probe, ports, IRQ/DMA, EATA CP/SP. Replaces `DPTSCSIDriver.m` / `.h`. |
| `EATAControllerThread.m` | IOThread if the reloc has `(IOThread)`. Completions come from status packets. |
| `EATAControllerPrivate.h` | Command-buf and private selectors. No Linux `allocCp` / `runPendingCommands` unless those exact names are in the reloc. |
| `EATAControllerTypes.h` | Registers, CP, SP, config. Bit names may come from EATA docs; offsets come from the reloc. |

**Add**

| Unit | Job |
| --- | --- |
| `EATASCSIBus.m` / `.h` (+ Private if the reloc has a category) | The missing second class. Superclass and its relationship to `EATAController` come from the report pass. |
| `reconstruction/` | `source-map.json`, `ledger.json`, `divergences.md`. |
| `tools/binrecon/profiles/dpt2000.json` | Reference-only profile. Output dir `../out/dpt2000`. |
| `vm/build-i386-scsi.sh` | Guest compile harness, shared with the 6X60 spec. Reuse it if it already exists; otherwise add it here with a DPT target. Do not create a second builder. |
| Kernel Server `PB.project` | `CLASSES` becomes the two class `.m` files (plus Thread/Routines only if they still exist). Extra `.c` files go in `CFILES` / `OTHER_SOURCES` only if the report pass finds standalone C symbols. |

**Retire**

Every `DPTSCSIDriver.*` source file once the new names are in place, the
Linux-shaped structs in §2.2, and every invented selector in §2.3.

**Bundle extras**

Align the files in §1.2 with the reference bundle. No inspector work.

## 5. Data flow

**Request.** An `IOSCSIController` client calls
`executeRequest:buffer:client:` on whichever class the reloc implements
it (likely `EATASCSIBus`). That class turns the `IOSCSIRequest` (CDB,
target/LUN, data, timeout) into a host-adapter request.
`EATAController` builds an EATA command packet and submits it with the
send-CP sequence the reloc uses — not AHA mailboxes, not Linux `outl`
guesses. Firmware runs the SCSI command and DMA. Host does not bit-bang
phases. Enqueue / IOThread / direct call is whichever the reloc does.

**Interrupt.** `interruptOccurred` on the class that owns the IRQ (almost
certainly `EATAController`) reads EATA status and the status packet,
matches the completed CP, and translates host-adapter and SCSI status
into `sc_status_t`. Completion lands on `EATASCSIBus` or finishes the
command buf directly; the ledger records the split. Do not keep the Linux
"read CP address from `REG_LOW`..`MSB` and index our array" path unless
the reloc does that.

**Probe / reset / abort.** ISA uses the I/O window in `Default.table`.
EISA/PCI/onboard use Auto Detect IDs already in the tables. Signature and
config come from the EATA read-config command the reloc issues.
`resetSCSIBus` goes through the class the reloc uses, then fails
outstanding CPs. Timeouts and abort use the reloc's selectors, not an
`IOLog` stub.

## 6. Artifact layout

### 6.1 Committed

```
src/drivers-i386/scsi/drvDPT2000/reconstruction/
    source-map.json
    ledger.json
    divergences.md
tools/binrecon/profiles/dpt2000.json
```

Status updates go in `docs/drivers/scsi-reconstruction.md` and
`src/drivers-i386/README`. There is no separate
`docs/drivers/drvDPT2000-issues.md`; 1542B did not grow one.

### 6.2 Not committed

The reference bundle, rebuilt artifacts under `out/i386/`, and analyzer
output under `tools/binrecon/out/` (already gitignored).

## 7. The two passes

### 7.1 Report pass (no VM)

1. **Profile.** Add `tools/binrecon/profiles/dpt2000.json`, reference-only,
   same analyzer block as `adaptec6x60.json`, `output_dir` `../out/dpt2000`.
2. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/dpt2000.json`
   with `BINRECON_REFERENCE` set to the path in §1.1. Output lands in
   `tools/binrecon/out/dpt2000/`.
3. **Map.** Build `source-map.json` from the Mach-O symbol table. Every
   reference function lands in exactly one bucket: `mapped`, `unmapped`,
   `boundary_disputed`, or `duplicate_candidates`.
4. **Diff.** Compare mapped functions against our source for control-flow
   shape, literals, port addresses, struct offsets, and call targets.
   Record both classes' superclasses, ivars, CP/SP layouts, and every
   selector from the binary.
5. **Tables.** Diff the bundle extras in §1.2 against our tree. §2.4 is the
   starting list, not the complete one.
6. **Report.** Write `divergences.md` and a `ledger-v1` entry for every
   function. `rebuilt_sha256` is `null`. IDA is the partition of record;
   Ghidra is a second opinion on bodies; angr `CFGFast` is not used as
   evidence (same rule as 1542B).

**Done when** `load_source_map(..., reference_analysis=IDA, repo_root=...)`
passes, every `unmapped` entry has a stated reason class in
`divergences.md`, and no function lacks a ledger entry.

### 7.2 Fix pass (after the report is committed)

Disposition: each finding is either fixed to match the reference, after
which the ledger advances to the strongest status the new evidence
supports, or accepted as `intentional-mismatch` with a reason and a
reviewer. Accepted by default: build-generated Kernel Server methods
(class-name `KernelServerInstance` / `Version` glue — the report pass
records the exact names; two classes may emit more than two),
compiler-emitted statics, and anything that exists only because of
Apple's toolchain.

Fixes touch only what the ledger flags. No adjacent cleanup.

Layered rewrite, each layer committed separately:

1. Replace types and register headers from the binary. Delete Linux-shaped
   structs in §2.2.
2. Write `EATAController.*`. Retire `DPTSCSIDriver.m` / `.h` as the live
   class.
3. Write `EATASCSIBus.*`. Wire it to the controller the way the reloc
   does.
4. Remove leftover invented symbols and `DPTSCSIDriverRoutines.m` if it
   has no reloc home. Update `PB.project` `CLASSES`.
5. Align tables, strings, and help RTFDs.
6. Guest compile.

**Baseline first.** Run `vm/build-i386-scsi.sh` against today's tree
before the two-class rewrite. Today's sources already have undefined
macros (`EATA_CP_ADDR`, `AUX_IRQ`, `STAT_IRQ`). If that means no
`_reloc`, the breakage is its own commit.

**Compile-clean** means `gnumake` exits 0 and stages a `_reloc` under
`out/i386/drvDPT2000/`. Our `DRIVERNAME` is `DPT2000`; the reference
bundle is `DPTSCSIDriver.config`. The installed config name is a Phase 6
bundle divergence, not a reason to rename `drvDPT2000`. Warnings are
logged and reviewed; they do not gate. The rebuilt `_reloc` is not fed to
binrecon.

If the guest is unavailable, the report pass and the source rewrite still
proceed; only the compile gates wait.

## 8. Error handling

**Evidence.** Analyzer boundary disagreements go to `boundary_disputed`,
not majority vote. If Linux `eata.c` or an EATA manual and the `_reloc`
disagree on offset, width, polarity, or control flow, the `_reloc` wins.

**Rewrite defects.** A live `DPTSCSIDriver` class after the rename is a
bug. An `EATASCSIBus` that is only empty `@interface` shells does not
count as mapped. Linux leftovers listed in §2.3 that have been renamed
until the source-map turns green are bugs.

**Runtime (what the binary does).** Probe failure (bad signature, config
read fails, resources fail) → `probe:` returns NO. Queue, abort, and bus
reset return the `sc_status_t` the reference produces for that path. No
extra recovery is invented. Timeouts go through the reloc's timeout/abort
selectors.

**Build.** A compile failure after the two-class rewrite is a rewrite
defect until the final compile gate in §9 passes.

## 9. Testing and done bar

Same bar as 6X60. No QEMU, no hardware, no rebuilt-vs-reference compare.

| Gate | Pass means |
| --- | --- |
| Report partition | `load_source_map` against the IDA reference analysis succeeds. |
| Ledger complete | One entry per reference function. After the fix pass, mapped functions are `assembly-matched`, or `control-flow-confirmed` only for the largest. Build glue is the only intentional unmapped set. |
| Both classes present | `EATAController` and `EATASCSIBus` exist. No live `DPTSCSIDriver` class. No Linux-invented selectors the reloc does not have. |
| Bundle extras | The files in §1.2 match the reference, or a listed `intentional-mismatch`. Inspector nib not required. |
| Baseline compile | The build script either produces a `_reloc` from today's tree, or the link failure (including today's undefined macros) is fixed in its own commit. |
| Final compile | Exit 0; stages a `_reloc` under `out/i386/drvDPT2000/`. |
| Status docs | `scsi-reconstruction.md` and `src/drivers-i386/README` say DPT2000 is reconstructed against the reference, compiled, not hardware-tested. |

`pytest tools/binrecon/tests` runs only if this work changes binrecon. It
is not expected to beyond adding `dpt2000.json`. There is no in-guest
functional SCSI test.

## 10. Sequencing

**Phase 1 — Report pass.** Add the profile. Analyze, source-map, ledger,
divergences, table diff. Commit `reconstruction/` and the profile.

*Verify:* `load_source_map` passes; every function has a ledger entry.

**Phase 2 — Baseline compile.** Ensure `vm/build-i386-scsi.sh` exists
(shared with 6X60) and build today's tree.

*Verify:* `_reloc` staged, or a separate compile-fix commit, then `_reloc`.

**Phase 3 — Types and EATAController.** Headers from the binary;
`EATAController.*` written; `DPTSCSIDriver` no longer the live class;
Linux-shaped structs in §2.2 gone.

*Verify:* grep finds no `@interface DPTSCSIDriver`; types match reloc
offsets recorded in the report.

**Phase 4 — EATASCSIBus.** New class, wired as the reloc wires it.

*Verify:* source-map mapped count includes the ~19 bus methods; empty
shells are not counted as mapped.

**Phase 5 — Residue removal and PB.project.** Invented symbols gone;
`CLASSES` lists the real files.

*Verify:* grep finds no live names from §2.3 unless the reloc has them;
source-map mapped count is the 55-minus-glue set.

**Phase 6 — Tables, help, final compile, status docs.**

*Verify:* every gate in §9.

## 11. Deliverables

- `tools/binrecon/profiles/dpt2000.json`
- `src/drivers-i386/scsi/drvDPT2000/reconstruction/{source-map.json,ledger.json,divergences.md}`
- `EATAController.*` and `EATASCSIBus.*` sources; `DPTSCSIDriver.*`
  sources gone
- `English.lproj` strings and help RTFDs from the reference bundle
- Aligned tables listed in §1.2
- `vm/build-i386-scsi.sh` (shared with 6X60; added here if it does not
  already exist)
- Staged `_reloc` under `out/i386/drvDPT2000/` (not committed)
- Updated `docs/drivers/scsi-reconstruction.md` and
  `src/drivers-i386/README`
