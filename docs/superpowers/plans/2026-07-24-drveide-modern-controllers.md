# Post-1997 (ICH-class) EIDE Controller Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `drvEIDE` attach to and drive Intel PIIX→ICH-class PCI IDE controllers reliably, adding ICH ATA/66/100 (UDMA 3–5) with cable detection, and eliminate the interrupt-timeout / ATA-command-error failures on post-1997 hardware.

**Architecture:** Introduce a generic SFF-8038i bus-master core (`IdeController(BMIDE)`) plus a swappable chipset-ops back-end table (`ideChipsetOps_t`). Populate an Intel back-end (PIIX + ICH, in `IdePIIX.m`) and a generic fallback back-end (`IdeGeneric.m`). Add a probe-time IRQ health check with a polled-completion fallback so a misrouted/absent interrupt degrades to slow-but-correct operation instead of hanging.

**Tech Stack:** Objective-C (NeXT/Apple DriverKit, `IO_DRIVERKIT_VERSION`), i386 kernel server, ProjectBuilder `pb_makefiles` / `gnumake`. Builds only under the period Rhapsody/DR2 toolchain on a case-sensitive filesystem.

## Global Constraints

- **Architecture:** i386 only (`INCLUDED_ARCHS = i386`). Do not touch ppc.
- **Do not regress the PIIX path.** PIIX/PIIX3/PIIX4 timing programming is *moved/reused*, never rewritten. PIIX-family behavior must be byte-for-byte identical.
- **Correct PIO floor for every controller.** No code path may leave a detected drive unusable; the existing mode-fallback ladder in `resetAndInit` must always be able to reach PIO.
- **Commit messages:** short, one–two lines, start with `drvEIDE:` subsystem prefix, describe behavior. **No metadata, no trailers, no Co-Authored-By** (per repo `CLAUDE.md`, which overrides the default trailer rule).
- **Branch:** all work on `drveide-modern-controllers`.
- **Source registration:** every new `.m`/`.h` file MUST be added to `EIDE.drvproj/EIDE.lksproj/PB.project` (`CLASSES` for `.m`, `H_FILES` for `.h`) or it will not compile into the driver.
- **No host tests exist.** Verification per task = (a) builds under the Rhapsody toolchain (`make` in the drvEIDE project dir), and where noted (b) PIIX regression boot in an emulator with `"Debug" = "Yes"`.
- **ICH register semantics** for offsets `0x48`/`0x4a`/`0x54` follow Linux `drivers/ide/piix.c` (canonical for ICH0–ICH4); values are annotated `/* piix.c: ... */` and are the designated datasheet-reconciliation point.

---

## Verification primitives (referenced by every task)

**BUILD** — under the Rhapsody/DR2 toolchain on a case-sensitive FS:
```bash
cd src/drivers-i386/ide/drvEIDE && make
```
Expected: compiles and links `EIDE_reloc` for i386 with no errors. (Cannot run on the modern macOS host — this step is performed in the target build environment.)

**PIIX-REGRESSION** — boot the rebuilt driver in an emulator whose IDE is a PIIX family part (QEMU `-machine pc` = PIIX3; VMware = PIIX4; VirtualBox = PIIX3). Use a **throwaway disk image** (per `CLAUDE.md` §6) and a config with `"Debug" = "Yes"`. Expected console:
- `hcN: <PIIX/PIIX3/PIIX4> PCI IDE Controller ...`
- `hcN: Drive 0: <PIO/Multiword DMA/Ultra DMA> Mode <n>` (same mode as before the change)
- root volume mounts; **no** `interrupt timeout` and **no** `ATA command ... failed. Retrying...` lines.

---

## Task 1: Chipset-ops types, ivars, and project wiring (no behavior change)

Introduce the seam types and controller state with zero functional change. Nothing consumes them yet.

**Files:**
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.h`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCnt.h:183-197` (ivar block)
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PB.project` (`H_FILES`)

**Interfaces:**
- Produces:
  - `ideChipCaps_t { unsigned char maxPIO, maxMWDMA, maxUDMA; unsigned int flags; }` where `maxMWDMA`/`maxUDMA == ATA_MODE_NUM_NONE (0xff)` means "type unsupported"; modes are ATA mode *numbers* (0-based).
  - `#define CHIP_FLAG_BUSMASTER 0x01`, `CHIP_FLAG_HAS_IDECONFIG 0x02` (ICH 0x54 register present).
  - `#define ATA_MODE_NUM_NONE 0xff`
  - `ideChipsetOps_t { const char *name; BOOL (*match)(unsigned long pciID, unsigned char progIf, ideChipCaps_t *out); void (*setTiming)(id self, driveInfo_t *drives); void (*resetTiming)(id self); BOOL (*detectCable)(id self); }`
  - New ivars on `IdeController`: `const ideChipsetOps_t *_chipsetOps;`, `ideChipCaps_t _chipCaps;`, `BOOL _pollMode;`

- [ ] **Step 1: Create `IdeBMIDE.h`**

```objc
/*
 * IdeBMIDE.h - Generic SFF-8038i bus-master IDE core and chipset back-end
 * interface. Shared definitions between the generic core (IdeBMIDE.m) and
 * the per-chipset back-ends (IdePIIX.m Intel, IdeGeneric.m fallback).
 */
#ifndef _IDE_BMIDE_H_
#define _IDE_BMIDE_H_

#import "ata_extern.h"          /* ata_mode_t, transfer types */

/* An ATA mode number (0-based). 0xff means "this transfer type unsupported". */
#define ATA_MODE_NUM_NONE   0xff

/* PCI class-code fields (config dword at 0x08). */
#define PCI_CLASS_MASS_STORAGE  0x01
#define PCI_SUBCLASS_IDE        0x01
/* Programming-interface byte bits (SFF-8038i / PCI IDE). */
#define PCI_IDE_PRIMARY_NATIVE   0x01
#define PCI_IDE_SECONDARY_NATIVE 0x04
#define PCI_IDE_BUSMASTER        0x80

/* Chipset capability descriptor filled in by a back-end's match(). */
typedef struct {
    unsigned char maxPIO;       /* highest PIO mode number */
    unsigned char maxMWDMA;     /* highest multiword DMA mode, or ATA_MODE_NUM_NONE */
    unsigned char maxUDMA;      /* highest ultra DMA mode, or ATA_MODE_NUM_NONE */
    unsigned int  flags;
} ideChipCaps_t;

#define CHIP_FLAG_BUSMASTER      0x01   /* controller is bus-master capable */
#define CHIP_FLAG_HAS_IDECONFIG  0x02   /* ICH IDE_CONFIG (0x54) present */

/* Thin, swappable chipset back-end. Selected once at probe time. */
typedef struct {
    const char *name;
    /* Claim the device by PCI id / prog-if; fill *out on success. */
    BOOL (*match)(unsigned long pciID, unsigned char progIf, ideChipCaps_t *out);
    /* Program the chip's timing registers for the negotiated drive modes. */
    void (*setTiming)(id self, void *drives);      /* driveInfo_t * */
    /* Revert the chip to compatible/default timing. */
    void (*resetTiming)(id self);
    /* Detect an 80-conductor cable (gates UDMA > mode 2). */
    BOOL (*detectCable)(id self);
} ideChipsetOps_t;

/* Back-end op tables, defined in their respective .m files. */
extern const ideChipsetOps_t ideIntelOps;      /* IdePIIX.m */
extern const ideChipsetOps_t ideGenericOps;    /* IdeGeneric.m */

#endif /* _IDE_BMIDE_H_ */
```

- [ ] **Step 2: Add ivars to `IdeCnt.h`**

In the PCI ivar block, immediately after `_ideChannel` (currently ending at `IdeCnt.h:197`), add:

```objc
	/*
	 * Chipset back-end and interrupt-mode state.
	 */
	const ideChipsetOps_t *_chipsetOps;	// selected back-end, NULL = legacy PIO
	ideChipCaps_t		_chipCaps;		// capabilities for this controller
	BOOL				_pollMode;		// YES: interrupts proven undeliverable
```

At the top of `IdeCnt.h`, with the other `#import`s, add:
```objc
#import "IdeBMIDE.h"
```

- [ ] **Step 3: Register `IdeBMIDE.h` in the project**

In `EIDE.lksproj/PB.project`, add `IdeBMIDE.h` to the `H_FILES` list (after `IdeCntInline.h`):
```
		IdeCntInline.h, 
		IdeBMIDE.h, 
```

- [ ] **Step 4: BUILD**

Run BUILD. Expected: compiles cleanly; no references to the new types yet, so behavior is unchanged.

- [ ] **Step 5: Commit**

```bash
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCnt.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PB.project
git commit -m "drvEIDE: add chipset-ops seam types and controller state"
```

---

## Task 2: Relocate the generic SFF-8038i core into `IdeController(BMIDE)` (pure move)

Move the chipset-independent bus-master/DMA machinery out of `IdePIIX.m` into a new `IdeBMIDE.m`, renaming `PIIX*`→`bmide*` for the *generic* pieces only. No logic changes. `IdePIIX.m` keeps everything that reads/writes PIIX config-space timing.

**Files:**
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.m`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m` (remove moved code)
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PB.project` (`CLASSES`)

**Interfaces:**
- Consumes: existing ivars `_bmRegs`, `_prdTable`, `_tablePhyAddr`, `_ideRegsAddrs`, `_driveNum`, `_interruptTimeOut`.
- Produces (methods now living in the BMIDE category, unchanged signatures):
  - `- (BOOL) bmRegisterRange:(IOPCIDeviceDescription *)devDesc;` (was `PIIXRegisterBMRange:`)
  - `- (BOOL) bmInitPRDTable;` (was `PIIXInitPRDTable`)
  - `- (ide_return_t) performDMA:(ideIoReq_t *)ideIoReq;`
  - `- (sc_status_t) performATAPIDMA:(atapiIoReq_t *)atapiIoReq buffer:(void *)buffer client:(struct vm_map *)client;`
  - static helpers moved verbatim: `IOMallocPage`, `PIIXVirtualToPhysical`→`bmVirtualToPhysical`, `PIIXStartDMA`→`bmStartDMA`, `PIIXStopDMA`→`bmStopDMA`, `PIIXGetStatus`→`bmGetStatus`, `PIIXSetupPRDTable`→`bmSetupPRDTable`, `PIIXPrepareDMA`→`bmPrepareDMA`.
  - Standard SFF-8038i register names (moved from `PIIX.h`) into `IdeBMIDE.h`: `BMIDE_BMICX 0x00`, `BMIDE_BMISX 0x02`, `BMIDE_BMIDTPX 0x04`, `BMIDE_BM_OFFSET 0x08`, `BMIDE_BM_SIZE 0x08`, `BMIDE_BM_MASK 0xfff0`, status/command bit unions (`piix_bmicx_u`→`bmide_bmicx_u`, etc.), PRD struct (`piix_prd_t`→`bmide_prd_t`), and buffer/DT alignment constants.

- [ ] **Step 1: Move the standard bus-master register defs into `IdeBMIDE.h`**

Cut from `PIIX.h` lines 186-273 (the `PIIX IO space register` block: `PIIX_BMICX`…`piix_prd_t`, and the `PIIX_DT_ALIGN`/`PIIX_BUF_*` constants) and paste into `IdeBMIDE.h` (before the `#endif`), renaming the `PIIX_`/`piix_` prefixes to `BMIDE_`/`bmide_`. These are SFF-8038i standard, not PIIX-specific. Leave `PIIX_BMIBA 0x20` in `PIIX.h` (it is read via the Intel path but is also standard BAR4 — duplicate it as `BMIDE_BMIBA 0x20` in `IdeBMIDE.h` and use the BMIDE name in moved code).

- [ ] **Step 2: Create `IdeBMIDE.m` and move the generic implementation**

Create `IdeBMIDE.m` with this skeleton, then move the function/method bodies **verbatim** from `IdePIIX.m` (only renaming identifiers per the Produces list):

```objc
/*
 * IdeBMIDE.m - Generic SFF-8038i bus-master IDE core. Chipset-independent
 * DMA engine and PRD handling, shared by all chipset back-ends.
 * Moved out of IdePIIX.m; no logic changes.
 */
#import "IdeCnt.h"
#import "IdeBMIDE.h"
#import "IdeCntCmds.h"
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <mach/mach_interface.h>
#import <machdep/i386/io_inline.h>
#import "IdeDDM.h"
#if (IO_DRIVERKIT_VERSION != 330)
#import <machdep/machine/pmap.h>
#endif

extern vm_offset_t pmap_resident_extract(pmap_t pmap, vm_offset_t va);

#ifndef MIN
#define MIN(a,b)    ((a) < (b) ? (a) : (b))
#endif

/* --- moved verbatim from IdePIIX.m: IOMallocPage (lines 86-114) --- */
/* --- moved+renamed: bmVirtualToPhysical, bmStartDMA, bmStopDMA,
 *     bmGetStatus, bmSetupPRDTable, bmPrepareDMA (IdePIIX.m 829-1064) --- */

@implementation IdeController(BMIDE)
/* --- moved+renamed: bmRegisterRange:, bmInitPRDTable (IdePIIX.m 489-569) --- */
/* --- moved verbatim: performDMA: , performATAPIDMA:buffer:client:
 *     (IdePIIX.m 1103-1354), with PIIXStartDMA→bmStartDMA etc. --- */
@end
```

Note: inside `performDMA:`/`performATAPIDMA:` the `#ifdef TRUST_PIIX` blocks move **as-is** for now (Task 5 generalizes them). Keep the `#define TRUST_PIIX 1` at the top of `IdeBMIDE.m`.

- [ ] **Step 3: Delete the moved code from `IdePIIX.m`**

Remove from `IdePIIX.m`: `IOMallocPage`, `PIIXVirtualToPhysical`, `PIIXStartDMA`, `PIIXStopDMA`, `PIIXGetStatus`, `PIIXSetupPRDTable`, `PIIXPrepareDMA`, `PIIXRegisterBMRange:`, `PIIXInitPRDTable`, `performDMA:`, `performATAPIDMA:buffer:client:`. Update the two call sites inside `PIIXInitController:` to use the new names: `PIIXRegisterBMRange:` → `bmRegisterRange:`, `PIIXInitPRDTable` → `bmInitPRDTable`. `PIIXInit`/`PIIXStopDMA` usage: keep `PIIXInit` in `IdePIIX.m` but have it call the generic `bmStopDMA(_bmRegs)` (add `#import "IdeBMIDE.h"` to `IdePIIX.m`).

- [ ] **Step 4: Register `IdeBMIDE.m` in the project**

In `EIDE.lksproj/PB.project` `CLASSES`, add `IdeBMIDE.m` after `IdePIIX.m,`:
```
		IdePIIX.m, 
		IdeBMIDE.m, 
```

- [ ] **Step 5: BUILD**

Run BUILD. Expected: compiles cleanly. Resolve any missed rename (linker "undefined `_PIIXStartDMA`" ⇒ a call site still uses the old name).

- [ ] **Step 6: PIIX-REGRESSION**

Run PIIX-REGRESSION. Expected: identical behavior to before the move (same detected modes, boots, no timeouts). This proves the relocation is behavior-preserving.

- [ ] **Step 7: Commit**

```bash
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PIIX.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PB.project
git commit -m "drvEIDE: split generic SFF-8038i DMA core out of IdePIIX"
```

---

## Task 3: Intel back-end ops table; route timing through `_chipsetOps` (PIIX behavior identical)

Wrap the existing PIIX timing/reset/cable code in the `ideIntelOps` table and make the controller call it through `_chipsetOps`, without changing what PIIX does.

**Files:**
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntInit.m` (`getControllerCapability`, `setControllerCapabilities`, `resetController`)

**Interfaces:**
- Consumes: `ideChipCaps_t`, `ideChipsetOps_t`, `_chipsetOps`, `_chipCaps` (Task 1); `PIIXComputePCIConfigSpace:forDrives:`, `PIIXResetTimings:`, `PIIXDetect80WireCable:` (existing).
- Produces:
  - `const ideChipsetOps_t ideIntelOps;`
  - `static BOOL intelMatch(unsigned long pciID, unsigned char progIf, ideChipCaps_t *out);`
  - `static void intelSetTiming(id self, void *drives);`
  - `static void intelResetTiming(id self);`
  - `static BOOL intelDetectCable(id self);`

- [ ] **Step 1: Add the Intel capability table and `intelMatch` to `IdePIIX.m`**

```objc
/* Per-chip capabilities. Modes are ATA mode NUMBERS. */
typedef struct {
    unsigned long id;
    const char   *name;
    unsigned char maxPIO;    /* 4 for all these parts */
    unsigned char maxMWDMA;  /* 2, or ATA_MODE_NUM_NONE */
    unsigned char maxUDMA;   /* per chip, or ATA_MODE_NUM_NONE */
    unsigned int  flags;     /* CHIP_FLAG_HAS_IDECONFIG for ICH */
} intelChip_t;

static const intelChip_t intelChips[] = {
  { 0x12308086, "PIIX",   4, 2, ATA_MODE_NUM_NONE, 0 },
  { 0x70108086, "PIIX3",  4, 2, ATA_MODE_NUM_NONE, 0 },
  { 0x71118086, "PIIX4",  4, 2, 2, 0 },
  { 0x71128086, "PIIX4E", 4, 2, 2, 0 },
  { 0x71138086, "PIIX4M", 4, 2, 2, 0 },
  { 0x24218086, "ICH0",   4, 2, 2, CHIP_FLAG_HAS_IDECONFIG },
  { 0x24118086, "ICH",    4, 2, 4, CHIP_FLAG_HAS_IDECONFIG },
  { 0x244A8086, "ICH2-M", 4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
  { 0x244B8086, "ICH2",   4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
  { 0x248A8086, "ICH3-M", 4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
  { 0x248B8086, "ICH3",   4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
  { 0x24CA8086, "ICH4-M", 4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
  { 0x24CB8086, "ICH4",   4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
  { 0, 0, 0, 0, 0, 0 }
};

static const intelChip_t *intelLookup(unsigned long id)
{
    const intelChip_t *c;
    for (c = intelChips; c->id != 0; c++)
        if (c->id == id) return c;
    return NULL;
}

static BOOL intelMatch(unsigned long pciID, unsigned char progIf,
    ideChipCaps_t *out)
{
    const intelChip_t *c = intelLookup(pciID);
    if (c == NULL) return NO;
    out->maxPIO   = c->maxPIO;
    out->maxMWDMA = c->maxMWDMA;
    out->maxUDMA  = c->maxUDMA;
    out->flags    = c->flags | ((progIf & PCI_IDE_BUSMASTER) ? CHIP_FLAG_BUSMASTER : 0);
    return YES;
}
```

- [ ] **Step 2: Add the ops thunks and the ops table to `IdePIIX.m`**

```objc
static void intelSetTiming(id self, void *drives)
{
    IOPCIConfigSpace configSpace;
    [self getPCIConfigSpace:&configSpace];
    [self PIIXComputePCIConfigSpace:&configSpace forDrives:(driveInfo_t *)drives];
    [self setPCIConfigSpace:&configSpace];
}

static void intelResetTiming(id self)
{
    [self PIIXInit];
    [self PIIXResetTimings:[self deviceDescription]];
}

static BOOL intelDetectCable(id self)
{
    return [self PIIXDetect80WireCable:[self deviceDescription]];
}

const ideChipsetOps_t ideIntelOps = {
    "Intel PIIX/ICH",
    intelMatch,
    intelSetTiming,
    intelResetTiming,
    intelDetectCable
};
```

Note: the body of `setPCIControllerCapabilitiesForDrives:` currently does exactly the `getPCIConfigSpace`/compute/`setPCIConfigSpace` sequence — `intelSetTiming` duplicates it intentionally so the ops path is self-contained. Task 3 Step 4 removes the old switch-based method.

- [ ] **Step 3: Point `getControllerCapability` at `_chipCaps` (`IdeCntInit.m:596-613`)**

Replace the body of `getControllerCapability` with a caps-driven version:

```objc
- (void) getControllerCapability
{
    _controllerModes.mode.pio   = ata_mode_to_mask(ATA_MODE_0);
    _controllerModes.mode.swdma = ATA_MODE_NONE;
    _controllerModes.mode.mwdma = ATA_MODE_NONE;
    _controllerModes.mode.udma  = ATA_MODE_NONE;

    if (_chipsetOps != NULL) {
        _controllerModes.mode.pio = ata_mode_to_mask(1 << _chipCaps.maxPIO);
        if ((_chipCaps.flags & CHIP_FLAG_BUSMASTER) &&
            (_chipCaps.maxMWDMA != ATA_MODE_NUM_NONE))
            _controllerModes.mode.mwdma = ata_mode_to_mask(1 << _chipCaps.maxMWDMA);
        if ((_chipCaps.flags & CHIP_FLAG_BUSMASTER) &&
            (_chipCaps.maxUDMA != ATA_MODE_NUM_NONE))
            _controllerModes.mode.udma = ata_mode_to_mask(1 << _chipCaps.maxUDMA);
    } else {
        /* Legacy ISA / unknown: assume PIO Mode 4 like the old code. */
        _controllerModes.mode.pio = ata_mode_to_mask(ATA_MODE_4);
    }
}
```

- [ ] **Step 4: Route `setControllerCapabilities` and `resetController` through the ops (`IdeCntInit.m`)**

Replace `setControllerCapabilities` (`IdeCntInit.m:1176-1185`) body:
```objc
- (BOOL) setControllerCapabilities
{
    if (_chipsetOps != NULL && _chipsetOps->setTiming != NULL) {
        _chipsetOps->setTiming(self, _drives);
        _transferWidth = [self getPIOTransferWidth];
        return YES;
    }
    return YES;
}
```
Replace `resetController` (`IdeCntInit.m:1020-1026`) body:
```objc
- (void)resetController
{
    if (_chipsetOps != NULL && _chipsetOps->resetTiming != NULL)
        _chipsetOps->resetTiming(self);
}
```
Delete the now-unused `resetPCIController`, `setPCIControllerCapabilitiesForDrives:`, and `getPCIControllerCapabilities:` methods and their declarations in `IdePIIX.h` (their logic now lives in the ops thunks / `getControllerCapability`). Keep `PIIXComputePCIConfigSpace:forDrives:`, `PIIXResetTimings:`, `PIIXInit`, `PIIXDetect80WireCable:`, `getPIOTransferWidth`.

- [ ] **Step 5: Set `_chipsetOps = &ideIntelOps` in `PIIXInitController:` (`IdePIIX.m`)**

In `probePCIController:`, the existing switch validates the ID is PIIX-family. Replace that switch (lines 173-194) with an `intelMatch` call that also fills caps:
```objc
    if (intelMatch(_controllerID, 0 /* progIf filled in later */, &_chipCaps)) {
        _chipsetOps = &ideIntelOps;
    } else {
        IOLog("%s: Unknown PCI IDE controller (0x%08lx)\n",
            [self name], _controllerID);
        _controllerID = PCI_ID_NONE;
        return NO;   /* Task 4 replaces this with the generic fallback */
    }
    IOLog("%s: %s PCI IDE Controller at Dev:%d Func:%d Bus:%d\n",
        [self name], _chipsetOps->name, devNum, funcNum, busNum);
    return ([self PIIXInitController:devDesc]);
```
(The progIf/bus-master flag is refined in Task 4 Step 2; for now `_chipCaps.flags` bus-master bit is set from the existing `_busMaster` detection inside `PIIXInitController:` — add after `_busMaster` is determined: `if (_busMaster) _chipCaps.flags |= CHIP_FLAG_BUSMASTER;`.)

- [ ] **Step 6: BUILD**

Run BUILD. Expected: clean compile.

- [ ] **Step 7: PIIX-REGRESSION**

Run PIIX-REGRESSION. Expected: unchanged — same modes, boots, no timeouts. PIIX now flows through `ideIntelOps` but does exactly what it did before.

- [ ] **Step 8: Commit**

```bash
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntInit.m
git commit -m "drvEIDE: drive PIIX timing through chipset-ops back-end"
```

---

## Task 4: Class-code discovery, never-return-NO, and the generic fallback back-end

Attach to *any* PCI IDE-class controller: Intel via `ideIntelOps`, everything else via a new PIO(+gated MWDMA2) generic back-end.

**Files:**
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeGeneric.m`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m` (`probePCIController:`)
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PB.project` (`CLASSES`)

**Interfaces:**
- Consumes: `intelMatch` (Task 3), `bmRegisterRange:`, `bmInitPRDTable` (Task 2), `ideChipCaps_t`, PCI class-code defines (Task 1).
- Produces: `const ideChipsetOps_t ideGenericOps;` with `match` accepting any bus-master-capable IDE class device and reporting `maxPIO=4, maxMWDMA=2 (if bus-master), maxUDMA=NONE`; `setTiming`/`resetTiming` = no-ops; `detectCable` = `NO`.

- [ ] **Step 1: Create `IdeGeneric.m`**

```objc
/*
 * IdeGeneric.m - Generic SFF-8038i chipset back-end. Used for any bus-master
 * PCI IDE controller not claimed by a specific back-end. Programs no chip
 * timing registers (leaves BIOS/POST timing); offers PIO always plus an
 * MWDMA2 attempt gated by the driver's DMA self-test. UDMA is not offered
 * because we will not blind-program unknown UDMA timing.
 */
#import "IdeCnt.h"
#import "IdeBMIDE.h"
#import <driverkit/generalFuncs.h>

static BOOL genericMatch(unsigned long pciID, unsigned char progIf,
    ideChipCaps_t *out)
{
    /* Only claim bus-master-capable controllers; pure-legacy parts fall
     * through to the driver's legacy PIO path. */
    if (!(progIf & PCI_IDE_BUSMASTER))
        return NO;
    out->maxPIO   = 4;
    out->maxMWDMA = 2;
    out->maxUDMA  = ATA_MODE_NUM_NONE;
    out->flags    = CHIP_FLAG_BUSMASTER;
    return YES;
}

static void genericSetTiming(id self, void *drives)   { /* BIOS timing kept */ }
static void genericResetTiming(id self)               { /* nothing to revert */ }
static BOOL genericDetectCable(id self)               { return NO; }

const ideChipsetOps_t ideGenericOps = {
    "Generic PCI IDE",
    genericMatch,
    genericSetTiming,
    genericResetTiming,
    genericDetectCable
};
```

- [ ] **Step 2: Read class code + prog-if and select a back-end in `probePCIController:`**

In `IdePIIX.m probePCIController:`, after `_controllerID` is read (existing `getPCIConfigData ... atRegister:0x00`), add class-code discovery and back-end selection, replacing the Task-3 Step-5 block:

```objc
    {
    unsigned long classReg;
    unsigned char progIf, subClass, baseClass;

    rtn = [self_class getPCIConfigData:&classReg atRegister:0x08
        withDeviceDescription:devDesc];
    if (rtn != IO_R_SUCCESS) {
        IOLog("%s: PCI config space access error %d\n", [self name], rtn);
        return NO;
    }
    progIf    = (classReg >>  8) & 0xff;
    subClass  = (classReg >> 16) & 0xff;
    baseClass = (classReg >> 24) & 0xff;

    if (baseClass != PCI_CLASS_MASS_STORAGE || subClass != PCI_SUBCLASS_IDE) {
        IOLog("%s: not a PCI IDE controller (class 0x%02x/0x%02x)\n",
            [self name], baseClass, subClass);
        return NO;
    }
    _progIf = progIf;   /* new ivar, see Step 3 */

    if (intelMatch(_controllerID, progIf, &_chipCaps)) {
        _chipsetOps = &ideIntelOps;
    } else if (genericMatch(_controllerID, progIf, &_chipCaps)) {
        _chipsetOps = &ideGenericOps;
        IOLog("%s: Unlisted PCI IDE (0x%08lx); using generic driver\n",
            [self name], _controllerID);
    } else {
        /* IDE-class but not bus-master: fall back to legacy PIO. */
        _chipsetOps = NULL;
        _controllerID = PCI_ID_NONE;
        IOLog("%s: PCI IDE (0x%08lx) without bus-master; legacy PIO\n",
            [self name], _controllerID);
        return YES;
    }
    IOLog("%s: %s IDE Controller at Dev:%d Func:%d Bus:%d\n",
        [self name], _chipsetOps->name, devNum, funcNum, busNum);
    return ([self PIIXInitController:devDesc]);
    }
```

For the generic back-end, `PIIXInitController:` must not run PIIX-only config reads. Guard the PIIX-specific timing reset at the end of `PIIXInitController:` (`IdePIIX.m:336-350`, the `PIIXResetTimings`/80-wire block) with `if (_chipsetOps == &ideIntelOps)`. The BM range registration (`bmRegisterRange:`), PRD alloc (`bmInitPRDTable`), IRQ/enable checks, and channel detection remain common to both.

- [ ] **Step 3: Add the `_progIf` ivar**

In `IdeCnt.h`, next to the Task-1 ivars, add:
```objc
	unsigned char		_progIf;		// PCI IDE programming-interface byte
```

- [ ] **Step 4: Register `IdeGeneric.m` and declare the ops externs are reachable**

In `EIDE.lksproj/PB.project` `CLASSES`, add after `IdeBMIDE.m,`:
```
		IdeGeneric.m, 
```
`IdeGeneric.m` references only `IdeBMIDE.h`; `IdePIIX.m` references `ideGenericOps` via the `extern` in `IdeBMIDE.h` (Task 1).

- [ ] **Step 5: BUILD**

Run BUILD. Expected: clean compile; `ideGenericOps` resolves at link.

- [ ] **Step 6: PIIX-REGRESSION**

Run PIIX-REGRESSION. Expected: PIIX still selects `ideIntelOps` (log shows `Intel PIIX/ICH IDE Controller`), unchanged behavior. Confirms discovery didn't disturb the Intel path.

- [ ] **Step 7: Commit**

```bash
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeGeneric.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCnt.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PB.project
git commit -m "drvEIDE: attach to any PCI IDE via class-code discovery + generic back-end"
```

---

## Task 5: Probe-time IRQ health check, polled-completion fallback, tiered timeouts

Make a misrouted or absent interrupt degrade to polled operation instead of a 30-second-per-command hang, and generalize the "trust bus-master status" logic into the core.

**Files:**
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCnt.m` (`ideWaitForInterrupt:`, new `pollForCompletion:`)
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntInit.m` (`resetAndInit` IRQ health check)
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCnt.h` (`IDE_INTR_TIMEOUT_FAST`)

**Interfaces:**
- Consumes: `_pollMode` (Task 1), `_interruptTimeOut`, `waitForNotBusy`, `_ideRegsAddrs`.
- Produces:
  - `- (ide_return_t) pollForCompletion:(unsigned char *)status;` — poll `altStatus` until `!BUSY` or `MAX_BUSY_DELAY`, then read `status`; returns `IDER_SUCCESS`/`IDER_TIMEOUT`.
  - `#define IDE_INTR_TIMEOUT_FAST (3*1000)` — short timeout for normal disk commands and the health probe.

- [ ] **Step 1: Add `IDE_INTR_TIMEOUT_FAST` to `IdeCnt.h`**

After `#define IDE_INTR_TIMEOUT (30*1000)` (`IdeCnt.h:310`):
```objc
/* Short timeout for normal disk commands and the probe-time IRQ health
 * check; the 30s ceiling is reserved for long ATAPI operations. */
#define IDE_INTR_TIMEOUT_FAST	(3*1000)
```

- [ ] **Step 2: Add `pollForCompletion:` to `IdeCnt.m`**

Add near `waitForNotBusy` (`IdeCnt.m:362`):
```objc
- (ide_return_t)pollForCompletion:(unsigned char *)status
{
    int delay = MAX_BUSY_DELAY;
    unsigned char s;
    delay -= 2;
    while (delay > 0) {
        s = inb(_ideRegsAddrs.altStatus);   /* no interrupt ack */
        if (!(s & BUSY)) {
            if (status != NULL)
                *status = inb(_ideRegsAddrs.status);  /* ack */
            else
                inb(_ideRegsAddrs.status);
            return IDER_SUCCESS;
        }
        if (delay % 1000) { IODelay(2); delay -= 2; }
        else              { IOSleep(1); delay -= 1000; }
    }
    return IDER_TIMEOUT;
}
```

- [ ] **Step 3: Make `ideWaitForInterrupt:` honor `_pollMode` (`IdeCnt.m:224`)**

At the very top of `ideWaitForInterrupt:ideStatus:` (before the `#ifdef NO_IRQ_MSG`):
```objc
    if (_pollMode)
        return [self pollForCompletion:status];
```
This routes all completion waits to polling once the controller is in poll mode, for both the `NO_IRQ_MSG` and message paths.

- [ ] **Step 4: Add the probe-time IRQ health check to `resetAndInit` (`IdeCntInit.m:818`)**

The DMA/PIO self-tests already run at the end of `resetAndInit`. Wrap the *first* interrupt-driven command there with a short timeout and set `_pollMode` on silent completion. Immediately before the `for (unit ...)` self-test loop (`IdeCntInit.m:966`), add:

```objc
    /*
     * IRQ health check: run one interrupt-driven READ VERIFY on the first
     * present ATA drive with a short timeout. If it completes only when we
     * poll the status (no interrupt delivered), switch to polled mode so a
     * misrouted/native-mode IRQ does not hang every command.
     */
    if (!_pollMode) {
        int u;
        for (u = 0; u < MAX_IDE_DRIVES; u++) {
            unsigned char st;
            unsigned int saved;
            ideRegsVal_t rv;
            if (_drives[u].ideInfo.type == 0 || [self isAtapiDevice:u])
                continue;
            _driveNum = u;
            saved = [self interruptTimeOut];
            [self setInterruptTimeOut:IDE_INTR_TIMEOUT_FAST];
            [self clearInterrupts];
            rv = [self logToPhys:0 numOfBlocks:1];
            if ([self ideReadVerifySeekCommon:&rv command:IDE_READ_VERIFY]
                    == IDER_TIMEOUT) {
                /* No interrupt within the short window. Did it finish anyway? */
                if ([self pollForCompletion:&st] == IDER_SUCCESS) {
                    _pollMode = YES;
                    IOLog("%s: no IDE interrupt detected; using polled mode\n",
                        [self name]);
                }
            }
            [self setInterruptTimeOut:saved];
            break;
        }
    }
```

- [ ] **Step 5: Generalize "trust status" in the DMA core (`IdeBMIDE.m`)**

In `performDMA:` and `performATAPIDMA:`, the `#ifdef TRUST_PIIX` blocks already accept "BM status OK though the interrupt timed out." Keep them always-on (they are, since `TRUST_PIIX` is defined) but make the fallback read the drive status via `pollForCompletion:` when in poll mode is unnecessary — `ideWaitForInterrupt:` already polls. No code change beyond confirming `bmGetStatus(_bmRegs)` is still consulted. Add a one-line comment renaming the intent:
```objc
/* Trust bus-master status even if the completion interrupt was missed. */
```

- [ ] **Step 6: BUILD**

Run BUILD. Expected: clean compile.

- [ ] **Step 7: PIIX-REGRESSION (must NOT enter poll mode)**

Run PIIX-REGRESSION. Expected: interrupts work, so the health check's READ VERIFY completes via interrupt, `_pollMode` stays `NO`, **no** `using polled mode` line, and behavior/perf is unchanged.

- [ ] **Step 8: Commit**

```bash
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCnt.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCnt.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntInit.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.m
git commit -m "drvEIDE: add polled-mode fallback for missing IDE interrupts"
```

---

## Task 6: ICH UDMA/66/100 programming and real 80-wire cable detection

Extend the Intel back-end to program ICH UDMA modes 3–5 via the `IDE_CONFIG` register and to detect cable type for real. Follows Linux `drivers/ide/piix.c` register semantics.

**Files:**
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PIIX.h` (IDE_CONFIG defs)
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m` (`PIIXComputePCIConfigSpace:`, `PIIXDetect80WireCable:`)

**Interfaces:**
- Consumes: `_ideChannel`, `_chipCaps` (`flags & CHIP_FLAG_HAS_IDECONFIG`, `maxUDMA`), `getPCIConfigData:`/`setPCIConfigData:`, existing `piix_udmactl_u`/`piix_udmatim_u`.
- Produces: `#define PIIX_IDE_CONFIG 0x54` (16-bit); helper `ichDriveNum(channel, unit)` → 0..3.

- [ ] **Step 1: Add IDE_CONFIG defs to `PIIX.h`**

After `#define PIIX_UDMATIM 0x4a` (`PIIX.h:87`):
```objc
#define PIIX_IDE_CONFIG	0x54	// (16) ICH IDE I/O config / cable report
/*
 * IDE_CONFIG (0x54), verified vs. ICH datasheet 290655-003 §9.1.18:
 *   bit 0 PCB0 / bit 1 PCB1 / bit 2 SCB0 / bit 3 SCB1
 *                              : 1 = 66MHz base clock for UDMA (modes 3-4);
 *                                0 = 33MHz. i.e. bit (1<<dn) for drive dn.
 *   bit 4 (pri master) / bit 5 (pri slave)
 *                              : 80-conductor cable present, primary  (mask 0x30)
 *   bit 6 (sec master) / bit 7 (sec slave)
 *                              : 80-conductor cable present, secondary (mask 0xc0)
 * where dn = (channel << 1) | (drive & 1), range 0..3.
 * ICH0 (82801AB): all of bits 0-7 are Reserved (UDMA capped at mode 2).
 * UDMA100 (mode 5) 100MHz-clock bits live in the 0x54 high byte on ICH2+
 * (per Linux piix.c); not present on ICH/ICH0.
 */
#define PIIX_ICFG_CABLE_PRI	0x30
#define PIIX_ICFG_CABLE_SEC	0xc0
```

- [ ] **Step 2: Add the `dn` helper and ICH UDMA programming in `PIIXComputePCIConfigSpace:` (`IdePIIX.m:662`)**

At file scope in `IdePIIX.m`:
```objc
/* ICH drive number 0..3 = (channel<<1) | (drive&1). */
static __inline__ unsigned char ichDriveNum(int channel, int unit)
{
    return (unsigned char)(((channel == PCI_CHANNEL_SECONDARY) ? 2 : 0) | (unit & 1));
}
```

The existing method clamps UDMA to mode 2 (`if (modeDrive0 > 2) modeDrive0 = 2;` at lines 745 and 765) and writes `udmatim` only. Replace those two clamps and add IDE_CONFIG programming. For **each present drive** `unit` with `transferType == IDE_TRANSFER_ULTRA_DMA`, compute `dn = ichDriveNum(_ideChannel, unit)` and program (only when `_chipCaps.flags & CHIP_FLAG_HAS_IDECONFIG`):

```objc
    /* --- replaces the "if (modeDrive0 > 2) modeDrive0 = 2;" clamp --- */
    if (!(_chipCaps.flags & CHIP_FLAG_HAS_IDECONFIG)) {
        /* PIIX4: UDMA capped at mode 2, existing UDMATIM path. */
        if (modeDrive0 > 2) modeDrive0 = 2;
    }
    /* (same guarded clamp for modeDrive1) */
```

After the existing `udmactl`/`udmatim` writes in the method, add ICH IDE_CONFIG handling (uses a direct config read/modify/write because IDE_CONFIG spans a fixed offset independent of channel):

```objc
    if (_chipCaps.flags & CHIP_FLAG_HAS_IDECONFIG) {
        unsigned long icfg = 0;
        int u;
        [[self class] getPCIConfigData:&icfg atRegister:PIIX_IDE_CONFIG
            withDeviceDescription:[self deviceDescription]];
        for (u = 0; u < MAX_IDE_DRIVES; u++) {
            unsigned char dn = ichDriveNum(_ideChannel, u);
            unsigned int  clk66  = (1U << dn);          /* low byte  */
            unsigned int  clk100 = (1U << (dn + 8));    /* high byte */
            unsigned char m = ata_mode_to_num(drv[u].transferMode);
            icfg &= ~(clk66 | clk100);
            if (drv[u].ideInfo.type != 0 &&
                drv[u].transferType == IDE_TRANSFER_ULTRA_DMA) {
                if (m >= 3) icfg |= clk66;    /* ATA/66 (modes 3-4) */
                if (m >= 5) icfg |= clk100;   /* ATA/100 (mode 5)  */
            }
        }
        [[self class] setPCIConfigData:icfg atRegister:PIIX_IDE_CONFIG
            withDeviceDescription:[self deviceDescription]];
    }
```

Also fix the `udmatim` (SDMA_TIM, 0x4a) 2-bit field value. The existing code
sets `udmatim->bits.pct0 = modeDrive0` (raw mode number), which is wrong for
UDMA modes ≥ 1. Per the ICH datasheet (290655-003 §9.1.17, SDMA_TIM), the 2-bit
cycle-time field is **clock-dependent**:

- 33 MHz base (SDMA_CNT clock bit = 0; UDMA modes 0/1/2): `00=CT4 (UDMA0)`,
  `01=CT3 (UDMA1)`, `10=CT2 (UDMA2)` ⟹ field value = mode number.
- 66 MHz base (clock bit = 1; UDMA modes 3/4, ICH 82801AA only): `01=CT3 (UDMA3)`,
  `10=CT2 (UDMA4)` ⟹ field value = mode − 2.

Both cases are captured by the canonical Linux `piix.c` expression, which the
datasheet confirms for modes 0–4 (and which extends to UDMA5 on ICH2+):

```objc
    /* SDMA_TIM 2-bit cycle-time value by UDMA mode m.
     * Verified vs. ICH datasheet 290655-003 §9.1.17:
     *   modes 0,1,2,3,4 -> 0,1,2,1,2 . (m5 -> 1 on ICH2+.)
     */
    unsigned char utim = MIN(2 - (m & 1), m);
    /* assign utim to pct0/pct1/sct0/sct1 for this channel+drive */
```
(Apply to both drive-0 and drive-1 branches, replacing `udmatim->bits.pctN = modeDriveN;`. `MIN` is already defined in `IdePIIX.m`.)

- [ ] **Step 3: Implement real cable detection in `PIIXDetect80WireCable:` (`IdePIIX.m:1375`)**

Replace the stub body:
```objc
- (BOOL) PIIXDetect80WireCable:(IOPCIDeviceDescription *)devDesc
{
    unsigned long icfg = 0;
    unsigned char mask;
    if (!(_chipCaps.flags & CHIP_FLAG_HAS_IDECONFIG))
        return NO;   /* PIIX4 has no cable report; assume 40-wire (UDMA<=2) */
    if ([[self class] getPCIConfigData:&icfg atRegister:PIIX_IDE_CONFIG
            withDeviceDescription:devDesc] != IO_R_SUCCESS)
        return NO;
    mask = (_ideChannel == PCI_CHANNEL_SECONDARY)
        ? PIIX_ICFG_CABLE_SEC : PIIX_ICFG_CABLE_PRI;
    if (_ide_debug)
        IOLog("%s: IDE_CONFIG 0x%04lx cable %s\n", [self name],
            icfg & 0xffff, (icfg & mask) ? "80-wire" : "40-wire");
    return (icfg & mask) ? YES : NO;
}
```

- [ ] **Step 4: BUILD**

Run BUILD. Expected: clean compile. (ICH silicon is not emulated; correctness is enforced at runtime by the Task-7 cable gate + self-test ladder.)

- [ ] **Step 5: PIIX-REGRESSION**

Run PIIX-REGRESSION. Expected: PIIX4 has no `CHIP_FLAG_HAS_IDECONFIG`, so the IDE_CONFIG block is skipped and UDMA stays clamped at mode 2 — behavior identical to before.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PIIX.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m
git commit -m "drvEIDE: program ICH UDMA/66/100 timing and detect 80-wire cable"
```

---

## Task 7: Gate UDMA by cable + caps in mode negotiation; final regression

Make the negotiated mode respect the cable and per-chip UDMA ceiling, so ICH selects the right mode and the self-test ladder can fall back cleanly.

**Files:**
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntInit.m` (`resetAndInit` cable gate, `getBestTransferMode`)

**Interfaces:**
- Consumes: `_has80WireCable`, `_chipsetOps->detectCable`, `_controllerModes`, `_drives[].driveModes`/`driveMasks`.
- Produces: cable-limited controller UDMA mask applied before per-drive negotiation.

- [ ] **Step 1: Detect cable and cap the controller UDMA mask in `resetAndInit` (`IdeCntInit.m:826-836`)**

After `[self getControllerCapability];` and the mask-qualification loop, add:
```objc
    /*
     * Determine cable type and cap UDMA at mode 2 (ATA/33) unless an
     * 80-conductor cable is present. Required for UDMA modes 3-5.
     */
    if (_chipsetOps != NULL && _chipsetOps->detectCable != NULL)
        _has80WireCable = _chipsetOps->detectCable(self);
    else
        _has80WireCable = NO;

    if (!_has80WireCable) {
        ata_mask_t udma33 = ata_mode_to_mask(ATA_MODE_2);
        _controllerModes.mode.udma &= udma33;
        IOLog("%s: 40-wire cable (or none): UDMA limited to Mode 2\n",
            [self name]);
    }
```

- [ ] **Step 2: Re-qualify per-drive masks after the cable gate (`IdeCntInit.m:834-836`)**

Ensure the per-drive qualification uses the (now cable-limited) controller mask. Move the existing loop:
```objc
    for (i = 0; i < MAX_IDE_DRIVES; i++)
        _drives[i].driveMasks.modes &= _controllerModes.modes;
```
to *after* the Step-1 cable-gate block (so the UDMA cap propagates into each drive's mask). `getBestTransferMode:` already intersects `driveModes & driveMasks & _controllerModes`, so no change there.

- [ ] **Step 3: BUILD**

Run BUILD. Expected: clean compile.

- [ ] **Step 4: PIIX-REGRESSION**

Run PIIX-REGRESSION. Expected: on a PIIX4 with UDMA drives on a 40-wire cable (typical VM), UDMA stays at mode 2, MWDMA2 otherwise — unchanged. The `40-wire cable` line may appear; no timeouts, boots normally.

- [ ] **Step 5: Final review pass**

Confirm the mode-fallback ladder still masks a failing UDMA mode and retries down to PIO: read `resetAndInit`'s `do { ... } while (retry)` loop and verify the DMA self-test failure path (`IdeCntInit.m:977-985`) clears `_drives[unit].driveMasks.array.mode[transferType] &= ~transferMode` for the new UDMA modes too (it is type/mode-generic, so it does). No code change expected.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntInit.m
git commit -m "drvEIDE: gate UDMA by cable type and per-chip ceiling"
```

---

## Self-Review

**Spec coverage:**
- Chipset descriptor table / ops seam → Tasks 1, 3.
- Generic BMIDE core (class-code discovery, BAR4, PRD, DMA engine) → Tasks 2, 4.
- Never-return-NO attach policy → Task 4.
- Probe-time IRQ health check + `_pollMode` + tiered timeouts + generalized trust-status → Task 5.
- Intel capability table (PIIX unchanged; ICH ceilings) → Task 3.
- ICH `IDE_CONFIG` UDMA 3–5 + real cable detect → Task 6.
- Mode-fallback ladder wired to new caps + cable gate + PIO floor → Task 7 (+ existing `resetAndInit` loop).
- File layout / PB.project wiring → Tasks 1, 2, 4.
- Validation posture (PIIX regression gate, ICH review+self-test) → per-task PIIX-REGRESSION steps; ICH acknowledged unverifiable on silicon.

**Placeholder scan:** No `TBD`/`TODO`; the only "fill later" is Task 3 Step 5's `return NO` explicitly superseded by Task 4 Step 2 (sequenced, not a placeholder). Move-refactor steps reference exact source line ranges rather than re-pasting hundreds of unchanged lines — a deliberate, reviewable instruction for relocation, with new logic given as complete code.

**Type consistency:** `ideChipCaps_t`/`ideChipsetOps_t` field names and the `ideIntelOps`/`ideGenericOps` symbols match across Tasks 1/3/4/6. `_chipsetOps`, `_chipCaps`, `_pollMode`, `_progIf` ivars declared in Task 1/4 and used consistently. `bmRegisterRange:`/`bmInitPRDTable`/`bmStopDMA` renames applied at both definition (Task 2) and call sites (Tasks 2/3). `pollForCompletion:` signature identical in Task 5 Steps 2/3/4. `ichDriveNum`/`PIIX_IDE_CONFIG`/`PIIX_ICFG_CABLE_*` consistent across Task 6.

**Datasheet verification (done):** the ICH `0x48` (SDMA_CNT), `0x4a` (SDMA_TIM),
and `0x54` (IDE_CONFIG) bit layouts are confirmed against the Intel 82801AA/AB
datasheet 290655-003 §9.1.16–9.1.18. Confirmed: SDMA_CNT enable bits
PSDE0/1=0/1, SSDE0/1=2/3; SDMA_TIM 2-bit fields at `dn*4`; IDE_CONFIG base-clock
bits 0-3 = `(1<<dn)`, cable-report masks 0x30 (pri) / 0xC0 (sec); ICH=UDMA4,
ICH0=UDMA2. This corrected the SDMA_TIM cycle-time encoding (Task 6 Step 2).
**Residual risk:** ICH2–ICH4 (UDMA5/ATA-100) mode-5 timing + 100MHz-clock bit
are from Linux `piix.c` (a different datasheet); the cable gate + DMA self-test
ladder remain the runtime safety net for those parts.
