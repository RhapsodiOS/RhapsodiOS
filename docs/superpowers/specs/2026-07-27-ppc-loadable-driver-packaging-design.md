# Packaging the PowerPC drivers as loadable kernel servers

Copy nine measured kernel-resident PowerPC driver sources into
`src/drivers-ppc/` as loadable-driver projects matching the layout Apple
shipped, and scaffold stub projects for the two drivers with no in-tree source
at all.

This spec **adds** source. It is the first in the series that does, and the
first that cannot verify its own output.

## Motivation

Four measurement specs established that sixteen shipped PowerPC drivers
correspond closely to in-tree sources. Every one of them recorded the same
finding and deferred it — the **packaging gap**:

> Ten of the measured drivers build *into the kernel* via
> `src/kernel-7/conf/files.ppc` under `mk_hasdrivers`, while every shipped
> artifact is a **loadable kernel server** — a `.config` bundle with its own
> `Default.table`, `DriverInfo` and `_reloc`.

Four drivers already have loadable-driver projects: `drvPPCGNic`,
`drvPPCGem`, `drvPPCAwacs`, `drvPPCBurgundy`. This spec gives nine of the other ten
the same treatment, so the tree's structure matches what Apple actually
shipped.

### What this spec cannot do

**There is no PowerPC toolchain in this environment.** `vm/` contains only
`build-i386-*.sh`. Nothing here compiles, and nothing here is verified to
build. The layout is *shaped* correctly — byte-for-byte structurally identical
to `drvPPCGem`, which is itself modelled on Apple's — but "ready to build" is a
claim this spec explicitly does **not** make. §5 states what is actually
verified.

## 1. Scope

### 1.1 The nine drivers to package

Each is copied from `src/kernel-7/bsd/dev/ppc/` into a loadable-driver project
under `src/drivers-ppc/`. Class names and `Default.table` come verbatim from
the shipped reference bundle.

| Reference bundle | Source directory | New project | Category |
| --- | --- | --- | --- |
| `drvPPCCuda` | `drvCuda` | `input/drvPPCCuda` | ADB/RTC service |
| `drvPPCPMU` | `drvPMU` | `input/drvPPCPMU` | ADB/RTC service |
| `drvPPCOHare` | `drvOHare` | `bus/drvPPCOHare` | I/O controller |
| `drvPPCBMac` | `drvBMacEnet` | `network/drvPPCBMac` | Ethernet |
| `drvPPCMace` | `drvMaceEnet` | `network/drvPPCMace` | Ethernet |
| `drvPPCDec21040` | `drvDECchip21040` | `network/drvPPCDec21040` | Ethernet |
| `drvPPC53c96` | `drvApple96_SCSI` | `scsi/drvPPC53c96` | SCSI |
| `drvPPCMesh` | `drvAppleMesh_SCSI` | `scsi/drvPPCMesh` | SCSI |
| `drvPPCSym8xx` | `drvSymbios8xx` | `scsi/drvPPCSym8xx` | SCSI |

`scsi/` is a new category directory. `src/drivers-ppc/README` already lists
`scsi` with no entries under it.

### 1.1a `drvPPCATA` is deferred, and why

`drvPPCATA` would have merged `drvPPCATA` and `drvATADisk` into one project,
because the shipped binary carries `IdeController`, `AtapiController` and
`IdeDisk` — and `IdeDisk` is our `ATADisk`, established by the first spec at
38/38 selector correspondence.

**A collision check run before this spec was finalised found that the two
directories contain different files under the same names.** `IdeCntPublic.h`
(2298 vs 2293 bytes) and `ata_extern.h` (12268 vs 12048) are two revisions of
shared headers, and the difference is substantive, not cosmetic:

```
drvPPCATA/ata_extern.h            drvATADisk/ata_extern.h
  kControllerTypePPC      0x00      kControllerTypePPC      0x00
  kControllerTypeHeathrow 0x01      kControllerTypeCmd646X  0x01
  kControllerTypeKeyLargo 0x02
  kControllerTypeATA4     0x03
  kControllerTypeCmd646X  0x04
```

`kControllerTypeCmd646X` is **0x04 in one and 0x01 in the other**. The two
directories compile against different values for the same constant today.
Copying both into one `.lksproj` would let one silently overwrite the other and
change that enum's meaning for half the resulting code.

That is a real inconsistency in the tree, not a packaging detail, and it is
plausibly related to `drvPPCATA`'s measured absences (`setTransferRate:`,
`calcIdeConfigWord:`). Resolving it by a copy command would destroy the
evidence.

**`drvPPCATA` therefore gets its own spec (§5)**, which must first establish
which header revision Apple's shipped `drvPPCATA_reloc` actually compiled
against — answerable from the binary, since these enum values appear as
literals in the compiled code.

### 1.2 The two stub projects

Neither has any in-tree source. Both were measured only as binaries.

| Reference bundle | Classes in binary | New project |
| --- | --- | --- |
| `IOADBDevice` | `ADBServer` (6 methods), `IOADBDevice` (10 methods) | `input/drvIOADBDevice` |
| `DEC21x4Ethernet` | `DEC21x4` (38 methods) | `network/drvDEC21x4Ethernet` |

Method counts are defined Objective-C symbols read from each `_reloc` with
`binrecon.macho.read_macho`.

Stubs are **headers declaring the real class hierarchy and the real selector
list, plus `.m` files with empty method bodies**. They exist so a later
reconstruction spec has a verified starting point and a compiling-shaped home,
not because they implement anything. §4.2 governs what an empty body contains.

### 1.3 Copying, not moving — and its cost

The nine sources are **copied**. `src/kernel-7/conf/files.ppc` is left
untouched, so the `mk_hasdrivers` kernel build is unaffected.

**This creates two copies of every packaged driver's source with nothing
keeping them in sync.** That is a real and accepted cost, chosen deliberately.
It is the same failure mode that already bit `bucket_functions.py` — a
scratchpad copy whose docstring drifted from the plan-embedded original and
nobody noticed — here at nine times the scale.

§2.3 adds a check that detects the divergence rather than preventing it. That
is the honest mitigation: a copy that is *known* to have drifted is
recoverable; one that has drifted silently is not.

### 1.4 Out of scope

- **`IOApplePCIBus` and `IODisplay`.** Their sources are in
  `src/driverkit-3/libDriver/ppc`, shared **library** code that also serves the
  deferred `IONDRVSupport`. Copying them would duplicate framework sources
  serving three binaries — materially worse than duplicating a self-contained
  driver directory, and a different decision than the one taken in §1.3.
- **Filling IODisplay's six absent methods.** Its own spec, per §6. That is
  ~772 bytes of PowerPC reconstructed from disassembly, and mixing it with
  mechanical file copying would give the risky half less scrutiny.
- **Any build, or any claim that these build.** No PowerPC toolchain exists.
- **Modifying `src/kernel-7/conf/files.ppc`** or any kernel build wiring.
- **Modifying the copied sources.** They are copied byte-for-byte. Divergences
  the measurement specs recorded stay recorded, not repaired.
- **`BPF`, `PortServer`, `Floppy`, `PPCSerialPort`, `IONDRVSupport`,
  `adbservd`** — excluded or deferred by earlier decisions.

## 2. Design

### 2.1 Project layout

Every project mirrors `src/drivers-ppc/network/drvPPCGem`, which is the
in-tree reference for a working loadable-driver project:

```
src/drivers-ppc/<category>/<drvName>/
    Makefile
    Makefile.preamble
    dpkg/control
    <Proj>.drvproj/
        Default.table                     <- verbatim from the shipped bundle
        DriverInfo                        <- verbatim, where the bundle has one
        English.lproj/Localizable.strings
        English.lproj/DriverHelp/.gitkeep
        Makefile
        Makefile.preamble
        Makefile.postamble
        <Proj>.lksproj/
            <copied .h and .m files>
            Load_Commands.sect
            Makefile
            Makefile.preamble
            Makefile.postamble
```

The `.lksproj/Makefile` is the NeXT Project Builder form, with
`PROJECT_TYPE = Kernel Server`, `MAKEFILE = kernelserver.make`,
`CODE_GEN_STYLE = DYNAMIC`, and `CLASSES` / `HFILES` listing the copied files.

`Default.table` and `DriverInfo` are copied **verbatim from the shipped
reference bundle**, not authored. They carry Apple's own `Class Names`,
`Matching`, `Load Priority` and version strings, and reproducing them by hand
would introduce error for no benefit.

> One consequence worth recording rather than "fixing": `drvPPCDec21040`'s
> shipped `Default.table` declares `"Class Names" = "DECchip21041"` alone,
> though the binary compiles `DECchip21040`, `DECchip21041` and `DECchip2104x`.
> That is Apple's file and it is copied unchanged.

### 2.2 What identifies a copied source

Each project gets a `dpkg/control`, matching the existing four. `drvPPCGem`
carries no `PB.project` at any level, so neither do these — the reference
layout governs, not a generic description of Project Builder output. Beyond that, **the copied `.h` and `.m` files are
byte-identical to their `src/kernel-7/bsd/dev/ppc/` originals** — no header
banner, no path comment, no reformatting. A byte-identical copy is what makes
§2.3's check meaningful; a copy annotated at copy time is not.

### 2.3 The divergence check

`tools/ppc_package_check.py` compares every packaged source file against its
`src/kernel-7/bsd/dev/ppc/` origin and reports any that differ, plus any file
present in one tree and not the other.

It is not a build step and blocks nothing. It exists so that the cost accepted
in §1.3 is *detectable*: run it and you learn immediately whether the two
copies have drifted apart, and where.

It ships with a test covering three cases: identical trees report nothing, a
modified file is reported, and a file added to one side only is reported.

### 2.4 Stub content

A stub `.m` defines every selector the binary carries, with a body that
**returns a zero value of the declared return type and does nothing else**. No
`IOLog`, no `return nil` chains dressed up as logic, no speculative parameter
validation.

Each stub project carries a `STUB` note in its `dpkg/control` description and a
comment at the top of each `.m` stating: the class list came from the shipped
binary's Objective-C metadata, no source exists in the tree, and every body is
empty. A reader must not be able to mistake a stub for an implementation.

Selector lists are extracted with `read_macho`, which preserves Objective-C
category tags where IDA's export strips them — established by the first spec's
`IdeController` finding.

## 3. Method

Copy, scaffold, check. There is nothing to measure and nothing to analyse; the
measurement specs already produced the evidence this one acts on.

Each project is created, then its file list is compared against the source
directory it came from, then the divergence check is run over the whole tree.

## 4. Acceptance

Done when all of the following hold, with output shown:

1. Nine packaged projects exist at the §1.1 paths, each with the complete §2.1
   layout — no missing `Makefile`, `Load_Commands.sect` or `dpkg/control`.
2. Every copied `.h` and `.m` is **byte-identical** to its
   `src/kernel-7/bsd/dev/ppc/` origin, verified by hash, with **no source file
   from those nine directories left uncopied**.
3. Each project's `Default.table` and `DriverInfo` are byte-identical to the
   shipped reference bundle's.
4. Each `.lksproj/Makefile`'s `CLASSES` and `HFILES` list exactly the `.m` and
   `.h` files present in that directory — no omissions, no phantom entries.
5. Two stub projects exist with every selector the corresponding binary
   carries: `ADBServer` 6, `IOADBDevice` 10, `DEC21x4` 38. Every body is empty
   per §2.4, and every file says so.
6. `tools/ppc_package_check.py` runs and reports **zero divergences**, and its
   own tests pass.
7. The binrecon suite is still green at **845 passed, 4 skipped** — this spec
   touches no binrecon code, so any change is a regression.
8. `src/drivers-ppc/README` lists the nine new projects and the two stubs, with
   the stubs marked as such.

**Not claimed:** that any of this compiles, links, loads or runs. There is no
PowerPC toolchain here. Acceptance verifies **structure and fidelity of
copying**, nothing more.

### 4.1 The risk this spec carries

The mechanical parts are low-risk and checkable. The two real hazards:

- **A wrong `CLASSES`/`HFILES` list** produces a project that looks complete and
  would fail at build time, which nothing here can detect. Item 4 exists
  precisely for this and must be verified by listing the directory, not by
  reading the Makefile.
- **A stub mistaken for an implementation.** Item 5's requirement that every
  file say so is not decoration.

## 5. Follow-on work

- **`drvPPCATA`**, blocked on the conflicting-header question in §1.1a. Its
  spec must determine which revision the shipped binary compiled against
  before any packaging happens.
- **IODisplay's six absent methods** — `_UnpackString` (232 bytes),
  `findADBDisplayInfoForType:` (324), `IOSMADBGetAVDeviceID:size:` (44),
  `IOSMADBGetLogicalRegister:size:result:size:` (104),
  `IOSMADBSetLogicalRegister:size:` (68), and `probe:`. Its own spec, written
  from disassembly with per-method review. The SCSITape spec did this kind of
  work and its reviews caught four material errors.
- **A PowerPC toolchain.** The tree carries the pieces — `src/cctools-2`
  (`as/ppc.c`, `ld/ppc_reloc.c`) and GCC's `rs6000` configuration in
  `src/cc-1`. Standing one up would turn every "not claimed" in §4 into
  something checkable, and is now the single highest-value item in the whole
  series.
- **Reconstructing `IOADBDevice` and `DEC21x4Ethernet`** from their binaries,
  starting from this spec's stubs.
- **Packaging `IOApplePCIBus` and `IODisplay`**, once the shared-library
  question in §1.4 has an answer.
- **Naming IDA's PowerPC glue stubs**, which unblocks `Floppy`,
  `PPCSerialPort` and `IONDRVSupport`.
