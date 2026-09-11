# Binary reconstruction of drvSym53C8xx

Reconstruct `drvSym53C8xx` against Apple's shipped i386 `SYM53c8_reloc`, using
`tools/binrecon`. A report pass maps every reference function to our source and
records the divergences. A fix pass replaces the BusLogic CCB clone with
Apple's CAM/SIM plus on-chip SCRIPTS, then a guest compile stages the `_reloc`
the existing project emits.

This continues the i386 SCSI work recorded in
[scsi-reconstruction.md](../../drivers/scsi-reconstruction.md) and reuses the
binrecon report/fix pattern from
[2026-07-25-bus-driver-binary-reconstruction-design.md](2026-07-25-bus-driver-binary-reconstruction-design.md),
the 1542B pass under `src/drivers-i386/scsi/drvAdaptec1542B/reconstruction/`,
and the 6X60 spec
[2026-09-10-adaptec6x60-reconstruction-design.md](2026-09-10-adaptec6x60-reconstruction-design.md).

## Motivation

`src/drivers-i386/README` marks this driver "stub, 12/158 reference functions;
reference is a 136-function CAM/SIM." That is accurate. The tree was cloned
from `drvBusLogic` (`SYM53c8Controller.m` HISTORY: "Created from BusLogic
driver") and still allocates mailbox-shaped CCBs, `runPendingCommands`, and
invented PIO helpers (`sym_reset_chip`, `sym_init_chip`). The 53C8xx is a
SCRIPTS processor: the host queues a CAM CCB, loads DSA/DSP, and the chip runs
SCSI/DMA. Filling in the current files cannot produce a working driver.

QEMU emulates `lsi53c895a`, a member of this family, so this driver is the
natural emulated SCSI path. This spec still does **not** include a QEMU or
hardware gate. The done bar is report, rewrite, guest compile — same as 6X60.

The 1542B and BusLogic reconstructions proved the report/ledger pipeline. 6X60
is the first wrong-architecture stub; this is the largest (158 `__text`
symbols).

## 1. Scope

### 1.1 Target

`C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config\SYM53c8_reloc`

| Property | Value |
| --- | --- |
| File size | 120,756 bytes |
| SHA-256 | `E0AC193DF652271D1B4249440140842B788F0BAAC13F93008B7E029A095CF6D3` |
| `__text` symbols | 158 (from the SCSI survey; the report pass is the partition of record) |
| Profile | `tools/binrecon/profiles/sym53c8xx.json` (created in this work; reference-only) |

`BINRECON_REFERENCE` is that `_reloc` path. The shipped config directory is
`SYM53c8.config`. Our source directory stays `src/drivers-i386/scsi/drvSym53C8xx`;
it is not renamed. The Kernel Server `NAME` / `PROJECTNAME` is already
`SYM53c8`, which matches the installed `_reloc` name.

The ObjC class in our headers is `SYM53c8Controller`. The reference class is
`SYM53c8`. Filenames remain `SYM53c8Controller.*`. The class must be renamed.

### 1.2 Config tables and resources are in scope

Compared against the reference bundle:

- `Default.table`
- `English.lproj/Localizable.strings`
- `English.lproj/Help/TableOfContents.rtf`
- `English.lproj/Help/Symbios_Logic_53C8xx_SCSI_Adapter.rtfd`
- `Load_Commands.sect` in the lksproj versus `Loaded Server,Load Commands` in
  the `_reloc`
- `DriverInfo` if the reference bundle actually ships one (the installed
  `SYM53c8.config` listing during brainstorming did not include it; record
  absence rather than inventing a file)

`"Driver Version"` is emitted by Apple's build and stays out of the table
comparison, same as 6X60. `"Version" = "5.00"` is in the reference table and
is in scope.

### 1.3 Out of scope

The `SYM53c8` `DYLDLINK` bundle beside the `_reloc` is a user-space inspector,
not kernel driver code. `English.lproj/SYM53c8Inspector.nib` stays in the tree
untouched.

No QEMU run, no hardware test, and no `binrecon compare` of a rebuilt artifact
against the reference. The rebuilt `_reloc` is staged as compile proof only.

Linux `ncr53c8xx` / `sym53c8xx` may be used to understand CAM/SIM ideas (CCB
queues, SCRIPTS, sync/wide). It must not donate file layout, type names,
SCRIPT bytes, or control flow. ppc `drvSymbios8xx` / `Sym8xxScript.ss` is a
different Apple driver and is not copied. Datasheets may name registers; the
`_reloc` wins on offset, width, polarity, SCRIPT bytes, and control flow.

The other i386 SCSI stubs (`drvAdaptec6X60`, `drvBusLogicFP`, `drvDPT2000`,
`drvAdaptec2940`) are not part of this spec. `scsi-reconstruction.md` is
updated for Sym53C8xx when this work finishes.

## 2. Findings that shaped this design

These come from the SCSI survey, the current tree, and a direct read of the
reference bundle during brainstorming. They are recorded so the plan can be
checked against them. The report pass may refine counts; it does not reopen
the architecture decision in §3.

### 2.1 The source implements the wrong chip protocol

`SYM53c8Types.h` defines a BusLogic-shaped `struct ccb` with `opcode`,
mailbox-style host status codes, and an SG list. `SYM53c8Thread.m` implements
`allocCcb:`, `ccbFromCmd:ccb:`, `freeCcb:`, and `runPendingCommands`.
`SYM53c8Routines.m` is invented PIO (`sym_reset_chip`, `sym_init_chip`) that
pokes SCNTL0/SIEN/DIEN and never starts SCRIPTS.

The reference has none of that as the engine. Its C surface is a CAM/SIM:

```
CCBInSIMQueue          AddToDeviceList       DeletePathFromDeviceTable
FCalcSync              FSetWide              FWideInit
FResumeXFer            FSendMsg
AutosenseSetup         BeginScan
```

plus the rest of the 136 C functions the report pass will name. The BusLogic
path is deleted, not adapted.

### 2.2 Invented symbols must go

Symbols that exist in our source and not in the reference include
`sym_reset_chip`, `sym_init_chip`, `allocCcb:`, `ccbFromCmd:ccb:`, `freeCcb:`,
`runPendingCommands`, and the ObjC class `SYM53c8Controller`. After the fix
pass they must not remain as live code. Inline helpers whose names the
reference actually has may stay; the report pass is the list of record.

### 2.3 DriverKit shells are the only current overlap

The `(PrivateMethods)` and `(IOThread)` category split is the part that was
reconstructed well. Those methods still call the BusLogic engine, so they are
rewritten to call the SIM even where the selector already matches. The class
name change is required for the source-map to resolve reference methods.

Ivar, CAM CCB, and device-table layouts are read from the reference Mach-O /
IDA during the report pass, not inferred from the current BusLogic headers.

### 2.4 The reference bundle vs our tables and help

`Default.table` keys already match the reference for Title, Family, Driver
Name, Auto Detect IDs (`0x00011000 0x00021000 0x00031000 0x00041000`), Bus
Type, Valid IRQ Levels, Wide SCSI, Synchronous, Help File, and Server Name.
The reference also has `"Version" = "5.00";` and a `"Driver Version"` line
(ignored). Auto Detect IDs cover NCR 53C810/820/825/815 only. Do not add
875/895 PCI IDs to the table unless the `_reloc` probe enumerates them.

`Localizable.strings` already matches.

Help lives under `English.lproj/DriverHelp/` in our tree and
`English.lproj/Help/` in the reference. Align to `Help/` and update
`LOCAL_RESOURCES` in `SYM53c8.drvproj/Makefile`. Copy the RTFD and
`TableOfContents.rtf` from the reference. Leave the inspector nib in
`LOCAL_RESOURCES`.

## 3. Architecture

Three layers. One ObjC class.

```
IOSCSIController client
        │
        ▼
SYM53c8  (SYM53c8Controller.m / SYM53c8Thread.m)
        │  CAM CCB / completion, not BusLogic mailbox CCBs
        ▼
CAM / SIM  (SYM53c8SIM.c / SYM53c8CAM.c)
        │  start SCRIPTS · DSA / DSP · SIR / SCSI interrupts
        ▼
On-chip SCRIPTS  (SYM53c8Scripts.c — bytes from this _reloc)
        │  PCI I/O or MMIO as the _reloc actually uses
        ▼
Symbios / LSI 53C8xx
```

`SYM53c8` is the DriverKit SCSI controller: probe, `executeRequest`,
`resetSCSIBus`, IOThread, `interruptOccurred`. The chip engine is new C. There
is no second ObjC class.

`SYM53c8Routines.m` is not kept as a PIO-init file. It is removed once every
remaining C symbol has a SIM, CAM, or Scripts home.

Linux may explain CAM/SIM ideas. It does not shape this diagram.

## 4. Components

**Keep and rewrite**

| Unit | Job |
| --- | --- |
| `SYM53c8Controller.m` / `.h` | DriverKit surface. Class becomes `SYM53c8`. Calls the SIM, never BusLogic CCBs. |
| `SYM53c8Thread.m` / `.h` | IOThread. Completions come from the SIM/ISR. |
| `SYM53c8ControllerPrivate.h` | Command-buf and DDM macros stay. `allocCcb:` / `ccbFromCmd:ccb:` / `freeCcb:` / `runPendingCommands` go. |
| `SYM53c8Types.h` / `SYM53c8Inline.h` | 53C8xx registers, CAM CCB / device-table structs, SIM state. Bit names may come from the datasheet or Linux as a reading aid; offsets come from the `_reloc`. |
| `scsivar.h` | Keep only if the reference still uses those SCSI constants. |

**Add**

| Unit | Job |
| --- | --- |
| `SYM53c8SIM.c` / `SYM53c8SIM.h` | The only API Controller/Thread call: init, ISR, queue CCB, abort, bus reset. Owns SIM instance state. |
| `SYM53c8CAM.c` | The rest of the 136 C functions: device table, scan, autosense, sync/wide, message/xfer helpers. |
| `SYM53c8Scripts.c` | SCRIPTS program bytes extracted from this `_reloc`. Not ppc `Sym8xxScript.ss`, not Linux. |
| `reconstruction/` | `source-map.json`, `ledger.json`, `divergences.md`. |
| `tools/binrecon/profiles/sym53c8xx.json` | Reference-only profile. No `rebuilt` key. |
| `vm/build-i386-scsi.sh` | Reuse or create the 6X60 guest compile harness; this spec requires it to build `drvSym53C8xx`. |

New C files are added to the Kernel Server project's `CFILES` / `OTHER_SOURCES`,
not as a second class. File names are ours; the binary only cares about symbol
names. The report pass may merge SIM+CAM into one `.c` if the call graph is one
blob; it must not merge Scripts into DriverKit `.m` files.

**Retire**

`SYM53c8Routines.m`, and every invented BusLogic / `sym_*` symbol in §2.2.

**Bundle extras**

Align the files in §1.2 with the reference bundle. No inspector work.

## 5. Data flow

**Request.** `executeRequest:buffer:client:` enqueues a `SYMCommandBuf` and
wakes the IOThread. The IOThread builds a CAM CCB from the `IOSCSIRequest`
(CDB, data pointer, DMA map, timeout, target/LUN) and calls the SIM queue
(`CCBInSIMQueue`). The SIM links the CCB, looks up the device table, programs
DSA, and starts SCRIPTS at the select/wait-reselect entry the `_reloc` uses.
The host does not drive SCSI phases in PIO.

**Interrupt.** `interruptOccurred` calls the SIM ISR (ISTAT DIP/SIP/INTF →
DSTAT / SIST0 / SIST1). A SCRIPTS interrupt (SIR) dispatches on the DSPS code.
Phase mismatch, disconnect, and reselect are SIM/SCRIPT functions, not
BusLogic mailbox-in scanning. Whether completed CCBs wake the IOThread or
finish the command buf directly is taken from the `_reloc` during the report
pass, not invented here.

**Reset / abort / probe.** `resetSCSIBus` goes through the SIM (abort running
SCRIPTS, fail outstanding CCBs). Timeouts and client abort call SIM abort, not
`sym_soft_reset` plus a mailbox-style queue drain. Probe calls SIM init after
PCI BAR / IRQ from the device description. Chip IDs are those the reference
enumerates.

**Sync / wide / autosense.** Entirely in the CAM (`FCalcSync`, `FSetWide`,
`FWideInit`, `AutosenseSetup`). DriverKit does not program SXFER/SCNTL3
itself.

## 6. Artifact layout

### 6.1 Committed

```
src/drivers-i386/scsi/drvSym53C8xx/reconstruction/
    source-map.json
    ledger.json
    divergences.md
tools/binrecon/profiles/sym53c8xx.json
```

Status updates go in `docs/drivers/scsi-reconstruction.md` and
`src/drivers-i386/README`. There is no separate
`docs/drivers/drvSym53C8xx-issues.md`; 1542B did not grow one.

### 6.2 Not committed

The reference bundle, rebuilt artifacts under `out/i386/`, and analyzer output
under `tools/binrecon/out/` (already gitignored).

## 7. The two passes

### 7.1 Report pass (no VM)

1. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/sym53c8xx.json`
   with `BINRECON_REFERENCE` set to the path in §1.1. Output lands in
   `tools/binrecon/out/sym53c8xx/`.
2. **Map.** Build `source-map.json` from the Mach-O symbol table. Every
   reference function lands in exactly one bucket: `mapped`, `unmapped`,
   `boundary_disputed`, or `duplicate_candidates`.
3. **Diff.** Compare mapped functions against our source for control-flow
   shape, literals, port addresses, struct offsets, and call targets. Record
   ivar, CAM CCB, device-table layouts, completion policy, I/O vs MMIO, and
   where SCRIPTS live (section, address, length).
4. **Tables.** Diff the bundle extras in §1.2 against our tree. §2.4 is the
   starting list, not the complete one.
5. **Report.** Write `divergences.md` and a `ledger-v1` entry for every
   function. `rebuilt_sha256` is `null`. IDA is the partition of record; Ghidra
   is a second opinion on bodies; angr `CFGFast` is not used as evidence (same
   rule as 1542B / 6X60).

**Done when** `load_source_map(..., reference_analysis=IDA, repo_root=...)`
passes, every `unmapped` entry has a stated reason class in `divergences.md`,
and no function lacks a ledger entry.

### 7.2 Fix pass (after the report is committed)

Disposition: each finding is either fixed to match the reference, after which
the ledger advances to the strongest status the new evidence supports, or
accepted as `intentional-mismatch` with a reason and a reviewer. Accepted by
default: the two build-generated Kernel Server methods (class-name
`KernelServerInstance` / `Version` glue), compiler-emitted statics, and
anything that exists only because of Apple's toolchain. The report pass
records the exact names from the symbol table.

Fixes touch only what the ledger flags. No adjacent cleanup.

Layered rewrite, each layer committed separately:

1. Rename the ObjC class to `SYM53c8`. Replace types and register headers from
   the binary. Delete BusLogic `struct ccb` and invented `sym_*` PIO APIs from
   headers.
2. Write `SYM53c8SIM.c` / `SYM53c8SIM.h`.
3. Write `SYM53c8CAM.c` (device table, scan, autosense, sync/wide, xfer
   helpers).
4. Write `SYM53c8Scripts.c` from the `_reloc` bytes recorded in the report.
5. Rewrite Controller / Thread to call the SIM. Remove `SYM53c8Routines.m` and
   leftover invented symbols.
6. Align tables, strings, and help (`Help/` not `DriverHelp/`).
7. Guest compile.

**Baseline first.** Run `vm/build-i386-scsi.sh drvSym53C8xx` before CAM/SIM
edits. If today's tree cannot produce a `_reloc`, that breakage is its own
commit.

**Compile-clean** means `gnumake` exits 0 and stages a `_reloc` under
`out/i386/drvSym53C8xx/`. Our `NAME` is already `SYM53c8`, matching the
reference bundle. Warnings are logged and reviewed; they do not gate. The
rebuilt `_reloc` is not fed to binrecon.

If the guest is unavailable, the report pass and the source rewrite still
proceed; only the compile gates wait.

## 8. Error handling

**Evidence.** Analyzer boundary disagreements go to `boundary_disputed`, not
majority vote. If a datasheet, Linux `ncr53c8xx`, or ppc `drvSymbios8xx`
disagrees with the `_reloc` on offset, width, polarity, SCRIPT bytes, or
control flow, the `_reloc` wins.

**Rewrite defects.** BusLogic leftovers, Linux-shaped stubs that have been
renamed until the source-map turns green, SCRIPT bytes that did not come from
this i386 `_reloc`, and leaving the ObjC class named `SYM53c8Controller` are
bugs. A SIM function that is only a stub, or a `CCBInSIMQueue` that still
talks BusLogic CCBs, does not count as mapped.

**Runtime (what the binary does).** SIM init failure → `probe:` returns NO.
Queue, abort, and bus-reset return the `sc_status_t` the reference produces
for that path. No extra recovery is invented. Timeouts go through SIM abort /
the reference timeout method.

**Build.** A compile failure after SIM work is a rewrite defect until the
final compile gate in §9 passes.

## 9. Testing and done bar

Same bar as 6X60: report + rewrite + guest compile. No QEMU, no hardware, no
rebuilt-vs-reference `binrecon compare`.

| Gate | Pass means |
| --- | --- |
| Report partition | `load_source_map` against the IDA reference analysis succeeds. Survey count 158 is the starting figure; IDA is the partition of record. |
| Ledger complete | One entry per reference function. After the fix pass, mapped functions are `assembly-matched`, or `control-flow-confirmed` only for the largest. Build glue is the only intentional unmapped set. |
| No invented symbols | No live `sym_reset_chip`, `sym_init_chip`, `allocCcb:`, `runPendingCommands`, `SYM53c8Controller` as the ObjC class, or other names the reference does not have. |
| SCRIPTS from this binary | `SYM53c8Scripts.c` bytes match the reference image. |
| Bundle extras | The files in §1.2 match the reference, or a listed `intentional-mismatch`. Inspector untouched. |
| Baseline compile | The build script either produces a `_reloc` from today's tree, or the link failure is fixed in its own commit. |
| Final compile | Exit 0; stages a `_reloc` under `out/i386/drvSym53C8xx/`. |
| Status docs | `scsi-reconstruction.md` and `src/drivers-i386/README` say Sym53C8xx is reconstructed against the reference, compiled, not hardware-tested. Other SCSI rows unchanged except this one. |

`pytest tools/binrecon/tests` runs if this work adds a residue test or changes
binrecon. A new `sym53c8xx.json` profile is expected; the existing Python suite
is not expected to need edits. There is no in-guest functional SCSI test.

## 10. Sequencing

**Phase 1 — Report pass.** Profile, analyze, source-map, ledger, divergences,
table diff. Commit `reconstruction/` and the profile.

*Verify:* `load_source_map` passes; every function has a ledger entry.

**Phase 2 — Baseline compile.** Reuse or add `vm/build-i386-scsi.sh` and build
the unmodified tree.

*Verify:* `_reloc` staged, or a separate compile-fix commit, then `_reloc`.

**Phase 3 — Class rename, types, and SIM.** Headers, `SYM53c8SIM.c`, BusLogic
CCB types gone from headers.

*Verify:* SIM symbols exist in source; class is `SYM53c8`; `runPendingCommands`
is gone from headers.

**Phase 4 — CAM and SCRIPTS.** `SYM53c8CAM.c`, `SYM53c8Scripts.c`.

*Verify:* The C functions listed in §2.1 have definitions. SCRIPT bytes match
the report-pass dump.

**Phase 5 — DriverKit rewrite and residue removal.** Controller / Thread call
the SIM; `SYM53c8Routines.m` and invented symbols are gone.

*Verify:* grep finds no live BusLogic residue; source-map mapped count is the
158-minus-glue set.

**Phase 6 — Tables, help, final compile, status docs.**

*Verify:* every gate in §9.

## 11. Deliverables

- `tools/binrecon/profiles/sym53c8xx.json`
- `src/drivers-i386/scsi/drvSym53C8xx/reconstruction/{source-map.json,ledger.json,divergences.md}`
- Rewritten DriverKit sources and new `SYM53c8SIM.c` / `SYM53c8SIM.h` /
  `SYM53c8CAM.c` / `SYM53c8Scripts.c`
- `English.lproj/Help/` aligned with the reference bundle
- Aligned `Default.table` (`Version` key); inspector nib untouched
- `vm/build-i386-scsi.sh` able to build `drvSym53C8xx`
- Staged `_reloc` under `out/i386/drvSym53C8xx/` (not committed)
- Updated `docs/drivers/scsi-reconstruction.md` and
  `src/drivers-i386/README`
