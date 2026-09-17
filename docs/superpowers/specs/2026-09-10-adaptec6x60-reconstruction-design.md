# Binary reconstruction of drvAdaptec6X60

Reconstruct `drvAdaptec6X60` against Apple's shipped i386 `AIC6X60SCSI_reloc`,
using `tools/binrecon`. A report pass maps every reference function to our
source and records the divergences. A fix pass replaces the AHA-154x mailbox
clone with Apple's AIC-6260/6360 HIM and SCSI sequencer, then a guest compile
stages the `_reloc` the existing project emits.

This continues the i386 SCSI work recorded in
[scsi-reconstruction.md](../../drivers/scsi-reconstruction.md) and reuses the
binrecon report/fix pattern from
[2026-07-25-bus-driver-binary-reconstruction-design.md](2026-07-25-bus-driver-binary-reconstruction-design.md)
and the 1542B pass under `src/drivers-i386/scsi/drvAdaptec1542B/reconstruction/`.

## Motivation

`src/drivers-i386/README` marks this driver "stub on the wrong architecture;
reconstruction in progress." That is accurate. The tree was cloned from
`drvAdaptec1542B` and still programs mailbox commands (`AIC_CMD_INIT`,
`AIC_CMD_START_SCSI`, `AIC_CMD_SET_MB_ENABLE`). The AIC-6260/6360 has no
onboard processor and no mailbox interface. The host drives selection,
reselection, message, and data phases directly.

Apple's driver does that. Of its 79 `__TEXT,__text` symbols, 54 are C functions
forming an Adaptec HIM plus a SCSI sequencer (`HIM6X60Initialize`,
`HIM6X60ISR`, `HIM6X60QueueSCB`, `selection`, `dataInPIO`, …). Our source
resolves about 18 of those, and they are DriverKit method shells, not the
engine. Filling in the current files cannot produce a working driver.

The 1542B and BusLogic reconstructions already proved the report/ledger
pipeline on this SCSI series. 6X60 is the first of the remaining stubs.

## 1. Scope

### 1.1 Target

`C:\Users\raynorpat\Downloads\test\Drivers\i386\AIC6X60SCSI.config\AIC6X60SCSI_reloc`

| Property | Value |
| --- | --- |
| File size | 61,892 bytes |
| SHA-256 | `E70647063BC4E6BC4BF47F73BF298BEAC59264B163C9D9D1920788CCBCE35E13` |
| `__text` symbols | 79 (from the SCSI survey; the report pass is the partition of record) |
| Profile | `tools/binrecon/profiles/adaptec6x60.json` (already present; reference-only) |

`BINRECON_REFERENCE` is that `_reloc` path. The shipped config directory is
`AIC6X60SCSI.config`, not `Adaptec6X60.config`. Our source directory stays
`src/drivers-i386/scsi/drvAdaptec6X60`; it is not renamed.

The ObjC class in our headers is already `AIC6X60`, which matches the
reference. The `scsi-reconstruction.md` row that lists ours as
`AIC6X60Controller` is stale. Source filenames remain `AIC6X60Controller.*`.

### 1.2 Config tables and resources are in scope

Compared against the reference bundle:

- `Default.table`
- `AIC_PCMCIA.table`
- `DriverInfo`
- `Load_Commands.sect`
- `English.lproj/Localizable.strings`
- `English.lproj/AIC_PCMCIA.strings`
- `English.lproj/Help/AIC_6X60_SCSI_Adapter.rtfd`
- `English.lproj/Help/AIC_6360_PCMCIA_SCSI_Adapter.rtfd`
- `English.lproj/Help/TableOfContents.rtf`

`"Driver Version"` is emitted by Apple's build and stays out of the table
comparison, same as the Intel bus reconstruction.

### 1.3 Out of scope

The 16,688-byte `AIC6X60SCSI` `DYLDLINK` bundle beside the `_reloc` is a
user-space inspector, not kernel driver code.

No QEMU run, no hardware test, and no `binrecon compare` of a rebuilt artifact
against the reference. The rebuilt `_reloc` is staged as compile proof only.

Linux / OpenBSD `aic6x60` is not a structural template. Adaptec AIC-6260/6360
programming documentation may name registers and bits; offsets, widths,
polarity, control flow, and symbol names come from the `_reloc`.

The other i386 SCSI stubs (`drvBusLogicFP`, `drvDPT2000`, `drvSym53C8xx`,
`drvAdaptec2940`) are not part of this spec. `scsi-reconstruction.md` is
updated for 6X60 when this work finishes.

## 2. Findings that shaped this design

These come from the SCSI survey, the current tree, and a direct read of the
reference bundle during brainstorming. They are recorded so the plan can be
checked against them. The report pass may refine counts; it does not reopen
the architecture decision in §3.

### 2.1 The source implements the wrong chip protocol

`AIC6X60Types.h` defines AHA-154x mailbox commands and an `aic_mb_area`.
`AIC6X60Routines.m` sends `AIC_CMD_INIT` with `mb_cnt`, `AIC_CMD_START_SCSI`,
`AIC_CMD_SET_MB_ENABLE`, and `AIC_CMD_GET_BIOS_INFO`. `AIC6X60Thread.m`
allocates CCBs and calls `runPendingCommands`.

The reference has none of that. Its engine is:

```
HIM6X60Initialize   HIM6X60ISR         HIM6X60QueueSCB    HIM6X60AbortSCB
selection           reselection        scsiBusFree        scsiBusReset
targetREQuest       samePhaseREQuest   interpretMessageIn prepareMessageOut
negotiateSDTR       updateSDTR         resetSDTR
dataInPIO           dataOutPIO         dataPhaseDMA
repinsb repinsw repinsd   repoutsb repoutsw repoutsd
```

The mailbox path is deleted, not adapted.

### 2.2 Invented symbols must go

Symbols that exist in our source and not in the reference include `_aic_cmd`,
`_aic_probe_cmd`, `_aicTimeout`, `allocCcb:`, `ccbFromCmd:ccb:`, `freeCcb:`,
and `runPendingCommands`. They are residue of the 1542B clone. After the fix
pass they must not remain as live code.

### 2.3 DriverKit shells are the only current overlap

The class, `(PrivateMethods)`, and `(IOThread)` category split is the part
that was reconstructed well. Those methods still call the mailbox engine, so
they are rewritten to call the HIM even where the selector already matches.

Ivar and SCB layouts are read from the reference Mach-O / IDA during the
report pass, not inferred from the current mailbox headers.

### 2.4 The reference bundle disagrees with our tables and has help we lack

Our tree has no `English.lproj`. The reference ships both string tables and
both help RTFDs named by the PCMCIA table.

`Default.table` in the reference includes `"Valid DMA Channels" = "0 5 6 7";`
and `"Help File" = "AIC_6X60_SCSI_Adapter.rtfd";`. Ours omits the DMA line and
points Help File at a stale project path.

`AIC_PCMCIA.table` in the reference uses `"Class Names" = "AIC6X60";` and
`"Auto Detect IDs" = "MFR=AdaptecInc.,PROD=APA-1460SCSIHostAdapter";`. Ours
uses `"Driver Name"` and has no Auto Detect IDs.

## 3. Architecture

Two layers. One ObjC class.

```
IOSCSIController client
        │
        ▼
AIC6X60  (AIC6X60Controller.m / AIC6X60Thread.m)
        │  SCB, not mailbox
        ▼
HIM + sequencer  (HIM6X60.c / AIC6X60Sequencer.c)
        │  programmed I/O
        ▼
AIC-6260 / 6360 ports
```

`AIC6X60` stays the DriverKit SCSI controller: probe, `executeRequest`,
`resetSCSIBus`, IOThread, `interruptOccurred`. The chip engine is new C. There
is no second ObjC class.

`AIC6X60Routines.m` is not kept as a mailbox file. It is removed once every
remaining C symbol has a HIM or sequencer home.

## 4. Components

**Keep and rewrite**

| Unit | Job |
| --- | --- |
| `AIC6X60Controller.m` / `.h` | DriverKit surface. Calls HIM, never mailboxes. |
| `AIC6X60Thread.m` / `.h` | IOThread. Completions come from HIM/ISR. |
| `AIC6X60ControllerPrivate.h` | Command-buf and DDM macros stay. Mailbox CCB APIs go. |
| `AIC6X60Types.h` / `AIC6X60Inline.h` | AIC-6x60 registers, SCB, HIM state. Bit names may come from the datasheet; offsets come from the `_reloc`. |
| `scsivar.h` | SCSI message / opcode constants. Keep if the sequencer still uses them. |

**Add**

| Unit | Job |
| --- | --- |
| `HIM6X60.c` / `HIM6X60.h` | `HIM6X60Initialize`, `HIM6X60ISR`, `HIM6X60QueueSCB`, `HIM6X60AbortSCB`, SCB queue, HIM instance state. This is the only API Controller/Thread call. |
| `AIC6X60Sequencer.c` | Phase machine and data path the HIM calls: selection, reselection, bus free/reset, messages, SDTR, PIO, DMA, `repins*` / `repouts*`. |
| `reconstruction/` | `source-map.json`, `ledger.json`, `divergences.md`. |
| `vm/build-i386-scsi.sh` | Guest compile harness. None exists. This spec only requires it to build 6X60. |

New C files are added to the Kernel Server project's `CFILES` / `OTHER_SOURCES`,
not as a second class. File names are ours; the binary only cares about symbol
names.

**Retire**

`AIC6X60Routines.m` as a mailbox file, and every invented mailbox symbol in §2.2.

**Bundle extras**

Align the files in §1.2 with the reference bundle. No inspector work.

## 5. Data flow

**Request.** `executeRequest:buffer:client:` enqueues an `AIC6X60CommandBuf` and
wakes the IOThread. The IOThread builds an SCB from the `IOSCSIRequest` (CDB,
data pointer, DMA map, timeout) and calls `HIM6X60QueueSCB`. If the chip is
idle, the HIM starts selection. The sequencer drives MESSAGE / COMMAND / DATA /
STATUS / MESSAGE IN on the chip ports. PIO uses `repins*` / `repouts*`. DMA is
used only when the reference `dataPhaseDMA` path does.

**Interrupt.** `interruptOccurred` calls `HIM6X60ISR`. The ISR reads chip status
and either continues the current phase or completes / disconnects the SCB.
Reselection is a sequencer function. Whether completed SCBs wake the IOThread
or finish the command buf directly is taken from the `_reloc` during the report
pass, not invented here.

**Reset / abort / probe.** `resetSCSIBus` goes through the HIM and
`scsiBusReset`, then fails outstanding SCBs. Timeouts and client abort call
`HIM6X60AbortSCB`. Probe calls `HIM6X60Initialize` after port/IRQ from the
device description. No `AIC_CMD_INIT`, no mailbox enable, no BIOS-info command.

**SDTR.** Entirely in the sequencer (`negotiateSDTR` / `updateSDTR` /
`resetSDTR`). DriverKit does not program sync rates itself.

## 6. Artifact layout

### 6.1 Committed

```
src/drivers-i386/scsi/drvAdaptec6X60/reconstruction/
    source-map.json
    ledger.json
    divergences.md
```

`tools/binrecon/profiles/adaptec6x60.json` already exists. Status updates go in
`docs/drivers/scsi-reconstruction.md` and `src/drivers-i386/README`. There is
no separate `docs/drivers/drvAdaptec6X60-issues.md`; 1542B did not grow one.

### 6.2 Not committed

The reference bundle, rebuilt artifacts under `out/i386/`, and analyzer output
under `tools/binrecon/out/` (already gitignored).

## 7. The two passes

### 7.1 Report pass (no VM)

1. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/adaptec6x60.json`
   with `BINRECON_REFERENCE` set to the path in §1.1. Output lands in
   `tools/binrecon/out/adaptec6x60/`.
2. **Map.** Build `source-map.json` from the Mach-O symbol table. Every
   reference function lands in exactly one bucket: `mapped`, `unmapped`,
   `boundary_disputed`, or `duplicate_candidates`.
3. **Diff.** Compare mapped functions against our source for control-flow
   shape, literals, port addresses, struct offsets, and call targets. Record
   ivar and SCB layouts from the binary.
4. **Tables.** Diff the bundle extras in §1.2 against our tree. §2.4 is the
   starting list, not the complete one.
5. **Report.** Write `divergences.md` and a `ledger-v1` entry for every
   function. `rebuilt_sha256` is `null`. IDA is the partition of record; Ghidra
   is a second opinion on bodies; angr `CFGFast` is not used as evidence (same
   rule as 1542B).

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

1. Replace types and register headers from the binary. Delete mailbox structs
   and `AIC_CMD_*`.
2. Write `HIM6X60.c` / `HIM6X60.h`.
3. Write `AIC6X60Sequencer.c` (phases, then data path).
4. Rewrite Controller / Thread to call the HIM. Remove `AIC6X60Routines.m`
   and leftover invented symbols.
5. Align tables, strings, and help RTFDs.
6. Guest compile.

**Baseline first.** Run `vm/build-i386-scsi.sh` before HIM edits. If today's
tree cannot produce a `_reloc`, that breakage is its own commit.

**Compile-clean** means `gnumake` exits 0 and stages a `_reloc` under
`out/i386/drvAdaptec6X60/`. Our `DRIVERNAME` is `Adaptec6X60`; the reference
bundle is `AIC6X60SCSI.config`. The installed config name is a Phase 6
bundle divergence, not a reason to rename `drvAdaptec6X60`. Warnings are
logged and reviewed; they do not gate. The rebuilt `_reloc` is not fed to
binrecon.

If the guest is unavailable, the report pass and the source rewrite still
proceed; only the compile gates wait.

## 8. Error handling

**Evidence.** Analyzer boundary disagreements go to `boundary_disputed`, not
majority vote. If a datasheet and the `_reloc` disagree on offset, width, or
polarity, the `_reloc` wins.

**Rewrite defects.** Mailbox leftovers and Linux-shaped stubs that have been
renamed until the source-map turns green are bugs. A HIM function that is only
a stub, or an `HIM6X60Initialize` that still talks mailboxes, does not count
as mapped.

**Runtime (what the binary does).** `HIM6X60Initialize` failure → `probe:`
returns NO. Queue, abort, and bus-reset return the `sc_status_t` the
reference produces for that path. No extra recovery is invented. Timeouts go
through `HIM6X60AbortSCB` / the reference timeout method.

**Build.** A compile failure after HIM work is a rewrite defect until the
final compile gate in §9 passes.

## 9. Testing and done bar

Same bar as 1542B, plus a guest compile (1542B never compiled).

| Gate | Pass means |
| --- | --- |
| Report partition | `load_source_map` against the IDA reference analysis succeeds. |
| Ledger complete | One entry per reference function. After the fix pass, mapped functions are `assembly-matched`, or `control-flow-confirmed` only for the largest. Build glue is the only intentional unmapped set. |
| No invented symbols | No live `aic_cmd`, `AIC_CMD_*` mailbox commands, `allocCcb:`, `runPendingCommands`, or other names the reference does not have. |
| Bundle extras | The files in §1.2 match the reference, or a listed `intentional-mismatch`. |
| Baseline compile | The build script either produces a `_reloc` from today's tree, or the link failure is fixed in its own commit. |
| Final compile | Exit 0; stages a `_reloc` under `out/i386/drvAdaptec6X60/`. |
| Status docs | `scsi-reconstruction.md` and `src/drivers-i386/README` say 6X60 is reconstructed against the reference, compiled, not hardware-tested. |

`pytest tools/binrecon/tests` runs only if this work changes binrecon. It is
not expected to. There is no in-guest functional SCSI test.

## 10. Sequencing

**Phase 1 — Report pass.** Analyze, source-map, ledger, divergences, table
diff. Commit `reconstruction/`.

*Verify:* `load_source_map` passes; every function has a ledger entry.

**Phase 2 — Baseline compile.** Add `vm/build-i386-scsi.sh` and build the
unmodified tree.

*Verify:* `_reloc` staged, or a separate compile-fix commit, then `_reloc`.

**Phase 3 — Types and HIM.** Headers, `HIM6X60.c`, mailbox types gone.

*Verify:* HIM symbols exist in source; mailbox commands
(`AIC_CMD_INIT`, `AIC_CMD_START_SCSI`, `AIC_CMD_SET_MB_ENABLE`,
`AIC_CMD_GET_BIOS_INFO`) are gone from headers.

**Phase 4 — Sequencer and data path.** `AIC6X60Sequencer.c`.

*Verify:* The C functions listed in §2.1 have definitions.

**Phase 5 — DriverKit rewrite and residue removal.** Controller / Thread call
HIM; `AIC6X60Routines.m` and invented symbols are gone.

*Verify:* grep finds no live mailbox residue; source-map mapped count is the
79-minus-glue set.

**Phase 6 — Tables, help, final compile, status docs.**

*Verify:* every gate in §9.

## 11. Deliverables

- `src/drivers-i386/scsi/drvAdaptec6X60/reconstruction/{source-map.json,ledger.json,divergences.md}`
- Rewritten DriverKit sources and new `HIM6X60.c` / `HIM6X60.h` /
  `AIC6X60Sequencer.c`
- `English.lproj` help and strings from the reference bundle
- Aligned `Default.table` and `AIC_PCMCIA.table`
- `vm/build-i386-scsi.sh`
- Staged `_reloc` under `out/i386/drvAdaptec6X60/` (not committed)
- Updated `docs/drivers/scsi-reconstruction.md` and
  `src/drivers-i386/README`
