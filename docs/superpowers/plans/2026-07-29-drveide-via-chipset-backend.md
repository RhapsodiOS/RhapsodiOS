# drvEIDE VIA Chipset Back-end Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fail-closed VIA back-end for VT82C586, VT82C586A, VT82C596A, and VT82C686A at each chipset's full safe transfer ceiling.

**Architecture:** A dependency-free C module owns exact chipset lookup and PCI timing-snapshot computation, allowing the Objective-C driver and standalone tests to share the same logic. The Objective-C wrapper identifies function 0 at the IDE function's PCI bus/device, maps negotiated drive state into the pure module, and commits only changed configuration dwords.

**Tech Stack:** C89, Objective-C, NeXT/Apple DriverKit, PCI configuration space, ProjectBuilder `pb_makefiles`/`gnumake`, standalone C tests.

---

## Constraints and verification

- Execute in a clean dedicated worktree; the current checkout has unrelated changes.
- Probe order stays Intel, VIA, generic. Unknown IDs, revisions, or failed companion reads fall through without VIA writes.
- Exact ceilings: 586 PIO4/MWDMA2; 586A and 596A PIO4/MWDMA2/UDMA2; 686A PIO4/MWDMA2/UDMA4.
- Use 30 ns for conventional PCI timing and 15 ns for the 686A 66 MHz UDMA source.
- Preserve all reserved, sibling-drive, and sibling-channel fields. Only 586/586A own `0x43[6:5]`; only original 586 owns `0x4d`; original 586 never touches `0x50-0x53`.
- Do not extend support to 586B, 596B, 686B, SATA, or AHCI.
- Real silicon is unavailable; report register tests and builds separately from hardware validation.

Standalone test command, run in the Rhapsody/Unix build environment:

```sh
cc -ansi -pedantic -Wall -Werror \
  -Isrc/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/VIATiming.c \
  src/drivers-i386/ide/drvEIDE/tests/via_timing_test.c \
  -o /tmp/via_timing_test && /tmp/via_timing_test
```

Expected: `via_timing_test: all tests passed`.

Driver build command under the period toolchain on a case-sensitive filesystem:

```sh
cd src/drivers-i386/ide/drvEIDE && make
```

Expected: `EIDE_reloc` compiles and links for i386 without errors.

## File responsibilities

- `VIATiming.h/.c`: dependency-free IDs, variant lookup, ATA timing quantization, register snapshot computation/reset, and cable inference.
- `IdeModeUtils.h`: dependency-free IDENTIFY mode-bitmap selector.
- `IdeVIA.h/.m`: DriverKit PCI access and the `ideVIAOps` wrapper.
- `tests/via_timing_test.c`: exact ID boundaries, encodings, preservation, reset, cable, and mode-word tests.
- `IdeBMIDE.h`, `IdePIIX.m`, `IdeGeneric.m`: match-context/private-state seam and VIA probe insertion.
- `IdeCntInit.m`: tested UDMA word-88 selection through mode 5.
- `PB.project`, `EIDE.lksproj/Makefile`: production source registration.

### Task 1: Pure chipset identification

**Files:**
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/VIATiming.h`
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/VIATiming.c`
- Create: `src/drivers-i386/ide/drvEIDE/tests/via_timing_test.c`

- [ ] **Step 1: Write the failing lookup test**

Create `VIATiming.h`:

```c
#ifndef _VIA_TIMING_H_
#define _VIA_TIMING_H_
#define VIA_IDE_586 0x15711106UL
#define VIA_IDE_LATER 0x05711106UL
#define VIA_BRIDGE_586 0x05861106UL
#define VIA_BRIDGE_596 0x05961106UL
#define VIA_BRIDGE_686 0x06861106UL
#define VIA_MODE_NONE 0xff
typedef enum { VIA_CHIP_NONE, VIA_CHIP_586, VIA_CHIP_586A,
    VIA_CHIP_596A, VIA_CHIP_686A } viaChip_t;
typedef struct { viaChip_t chip; const char *name; unsigned char maxPIO;
    unsigned char maxMWDMA, maxUDMA; } viaChipInfo_t;
const viaChipInfo_t *VIAFindChip(unsigned long ideID,
    unsigned long bridgeID, unsigned char revision);
#endif
```

Create the test harness with this exact frame, placing each task's assertions
inside a named `static void` test and calling it from `main`:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "VIATiming.h"
static int failures;
#define CHECK(e) do { if (!(e)) { \
    fprintf(stderr,"%s:%d: %s failed\n",__FILE__,__LINE__,#e); \
    failures++; } } while (0)
static void test_chip_lookup(void)
{
    /* Insert the lookup assertions immediately below. */
}
int main(void)
{
    test_chip_lookup();
    if (failures) {
        fprintf(stderr,"via_timing_test: %d failure(s)\n",failures);
        return EXIT_FAILURE;
    }
    puts("via_timing_test: all tests passed");
    return EXIT_SUCCESS;
}
```

Use these assertions as the complete body of `test_chip_lookup`:

```c
CHECK(VIAFindChip(VIA_IDE_586, VIA_BRIDGE_586, 0x00)->chip == VIA_CHIP_586);
CHECK(VIAFindChip(VIA_IDE_586, VIA_BRIDGE_586, 0x0f)->maxUDMA == VIA_MODE_NONE);
CHECK(VIAFindChip(VIA_IDE_586, VIA_BRIDGE_586, 0x10) == 0);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_586, 0x20)->chip == VIA_CHIP_586A);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_586, 0x2f)->maxUDMA == 2);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_586, 0x1f) == 0);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_586, 0x30) == 0);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_596, 0x00)->chip == VIA_CHIP_596A);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_596, 0x0f)->maxUDMA == 2);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_596, 0x10) == 0);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_686, 0x10)->chip == VIA_CHIP_686A);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_686, 0x2f)->maxUDMA == 4);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_686, 0x0f) == 0);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_686, 0x30) == 0);
CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_586, 0x00) == 0);
CHECK(VIAFindChip(0x12348086UL, VIA_BRIDGE_586, 0x20) == 0);
```

The harness exits nonzero on failures and prints the expected success line only when the count is zero.

- [ ] **Step 2: Run the standalone command and verify RED**

Expected: missing `VIATiming.c`/undefined `VIAFindChip`.

- [ ] **Step 3: Implement the lookup table**

```c
typedef struct { unsigned long ideID, bridgeID; unsigned char lo, hi;
    viaChipInfo_t info; } viaEntry_t;
static const viaEntry_t viaChips[] = {
 { VIA_IDE_586, VIA_BRIDGE_586, 0x00, 0x0f,
   { VIA_CHIP_586, "VT82C586", 4, 2, VIA_MODE_NONE } },
 { VIA_IDE_LATER, VIA_BRIDGE_586, 0x20, 0x2f,
   { VIA_CHIP_586A, "VT82C586A", 4, 2, 2 } },
 { VIA_IDE_LATER, VIA_BRIDGE_596, 0x00, 0x0f,
   { VIA_CHIP_596A, "VT82C596A", 4, 2, 2 } },
 { VIA_IDE_LATER, VIA_BRIDGE_686, 0x10, 0x2f,
   { VIA_CHIP_686A, "VT82C686A", 4, 2, 4 } }
};
const viaChipInfo_t *VIAFindChip(unsigned long ide, unsigned long bridge,
    unsigned char rev)
{
    unsigned int i;
    for (i = 0; i < sizeof(viaChips) / sizeof(viaChips[0]); i++)
        if (viaChips[i].ideID == ide && viaChips[i].bridgeID == bridge &&
            rev >= viaChips[i].lo && rev <= viaChips[i].hi)
            return &viaChips[i].info;
    return 0;
}
```

- [ ] **Step 4: Run tests and verify GREEN**

- [ ] **Step 5: Commit**

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/VIATiming.* \
        src/drivers-i386/ide/drvEIDE/tests/via_timing_test.c
git commit -m "drvEIDE: add tested VIA chipset identification"
```

### Task 2: Pure PIO/MWDMA register computation

**Files:** modify `VIATiming.h`, `VIATiming.c`, and `via_timing_test.c`.

- [ ] **Step 1: Add snapshot types and declarations**

```c
#define VIA_CONFIG_BASE 0x40
#define VIA_CONFIG_SIZE 0x14
#define VIA_CHANNEL_PRIMARY 0
#define VIA_CHANNEL_SECONDARY 1
#define VIA_XFER_PIO 0
#define VIA_XFER_MWDMA 2
#define VIA_XFER_UDMA 3
typedef struct { unsigned char bytes[VIA_CONFIG_SIZE]; } viaConfig_t;
typedef struct { unsigned char present, pioMode, transferType,
    transferMode; } viaDriveTiming_t;
void VIAComputeConfig(viaConfig_t *, viaChip_t, unsigned char,
    const viaDriveTiming_t[2]);
void VIAResetConfig(viaConfig_t *, viaChip_t, unsigned char);
int VIADetect80WireCable(const viaConfig_t *, viaChip_t, unsigned char);
```

- [ ] **Step 2: Write failing snapshot tests**

Use `#define CFG(c,o) ((c).bytes[(o)-VIA_CONFIG_BASE])` and nonzero sentinels. Assert:

```c
/* PIO4, primary master, both channels enabled, initial bytes 0x5a. */
CHECK(CFG(c,0x43) == 0x3a); /* FIFO 8/8, other bits preserved */
CHECK(CFG(c,0x4b) == 0x20); /* active 3T, recovery 1T */
CHECK(CFG(c,0x4c) == 0x1a); /* only setup bits 7:6 changed */
CHECK(CFG(c,0x4d) == 0x0a); /* original-586 primary half clocks clear */
CHECK(CFG(c,0x4f) == 0x20);
CHECK(CFG(c,0x48) == 0x5a && CFG(c,0x4e) == 0x5a);
/* MWDMA1 + PIO4 on 586A produces 3T active/2T recovery. */
CHECK(CFG(c,0x4b) == 0x21);
CHECK(CFG(c,0x4d) == 0xa5); /* reserved and preserved */
/* Secondary reset changes 48/49, 4c low nibble, 4d low nibble, 4e only. */
CHECK(CFG(c,0x48) == 0xa8 && CFG(c,0x49) == 0xa8);
CHECK(CFG(c,0x4a) == 0x5a && CFG(c,0x4b) == 0x5a);
CHECK(CFG(c,0x4c) == 0x5f && CFG(c,0x4d) == 0x50);
CHECK(CFG(c,0x4e) == 0xff && CFG(c,0x4f) == 0x5a);
```

- [ ] **Step 3: Run tests and verify RED**

- [ ] **Step 4: Implement ATA tables and quantization**

Use these nanosecond rows (`setup, act8, rec8, cycle8, active, recover, cycle`):

```c
static const unsigned short pio[5][7] = {
 {70,290,240,600,165,150,600}, {50,290,93,383,125,100,383},
 {30,290,40,330,100,90,240}, {30,80,70,180,80,70,180},
 {25,70,25,120,70,25,120}
};
static const unsigned short mwdma[3][4] = {
 {60,215,215,480}, {45,80,50,150}, {25,70,25,120}
};
```

Quantize with `(ns + period - 1) / period`; extend active/recovery symmetrically when their sum is below cycle; clamp setup to 1-4 clocks and active/recovery to 1-16. For `dn=channel*2+unit`, write data byte `0x48+(3-dn)`, setup shift `(3-dn)*2`, and channel command byte `0x4e+(1-channel)`. Merge command timing by maxima across both present drives. For 586/586A, preserve `0x43 & 0x9f` and choose `0x00` primary-only, `0x60` secondary-only, or `0x20` otherwise. Only 586 clears current-channel `0x4d` fields.

`VIAResetConfig` sets current drive bytes to `0xa8`, setup fields to `3` (4T), command byte to `0xff`, applies early FIFO splitting, and clears current-channel 586 half clocks.

- [ ] **Step 5: Run tests and verify GREEN**

- [ ] **Step 6: Commit**

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/VIATiming.* \
        src/drivers-i386/ide/drvEIDE/tests/via_timing_test.c
git commit -m "drvEIDE: compute VIA PIO and MWDMA timings"
```

### Task 3: Variant-specific UDMA and cable inference

**Files:** modify `VIATiming.c` and `via_timing_test.c`.

- [ ] **Step 1: Write failing variant tests**

Create one present drive with PIO4 and the requested UDMA mode, then assert:

```c
/* 586A UDMA2, initial 0x3c: own 7,6,1,0; preserve 5:2. */
CHECK(CFG(c,0x53) == 0xfc);
CHECK(CFG(c,0x4d) == 0x3c);
/* 596A UDMA2, initial 0x18: preserve reserved 4 and 3. */
CHECK(CFG(c,0x53) == 0xf8);
CHECK(CFG(c,0x43) == 0x18 && CFG(c,0x4d) == 0x18);
/* 686A primary-master UDMA4, initial 0x10. */
CHECK(CFG(c,0x53) == 0xf0); /* 2T at 66 MHz */
CHECK(CFG(c,0x52) == 0x18); /* primary shared clock-source bit */
CHECK(VIADetect80WireCable(&c,VIA_CHIP_686A,VIA_CHANNEL_PRIMARY));
CFG(c,0x52) &= (unsigned char)~0x08;
CHECK(!VIADetect80WireCable(&c,VIA_CHIP_686A,VIA_CHANNEL_PRIMARY));
/* Reset disables both primary UDMA bytes and selects 33 MHz. */
CHECK((CFG(c,0x52) & 0x08) == 0);
CHECK((CFG(c,0x52) & 0xe7) == 0x03);
CHECK((CFG(c,0x53) & 0xe7) == 0x03);
```

- [ ] **Step 2: Run tests and verify RED**

- [ ] **Step 3: Implement the exact UDMA ownership rules**

Add `udmaCycleNs = {120,80,60,45,30}` and these helpers:

```c
static unsigned char udmaOffset(unsigned char dn) { return 0x50+(3-dn); }
static unsigned char clockOffset(unsigned char ch)
{ return ch == VIA_CHANNEL_PRIMARY ? 0x52 : 0x50; }
```

For 586, return without reading/writing UDMA bytes. For 586A use owned mask
`0xc3`, enabled value `0xc0|(clocks-2)`, and disabled value `0x03`, preserving
read-only bit 5 and reserved bits 4:2. For 596A use mask `0xe7`, enabled value
`0xe0|(clocks-2)`, and disabled value `0x03`, preserving bits 4 and 3.

For 686A, first choose one clock per channel: if either present drive requests
UDMA3/4, set `clockOffset(channel) & 0x08` and quantize every UDMA drive at
15 ns; otherwise clear that bit and use 30 ns. Then use mask `0xe7` and the
same enabled/disabled values. Clamp 586A cycles to 2-5 and later cycles to 2-9.

Implement cable evidence exactly:

```c
if (chip != VIA_CHIP_686A || !(CBYTE(c,clockOffset(ch)) & 0x08)) return 0;
for (unit=0; unit<2; unit++) {
    unsigned char v=CBYTE(c,udmaOffset((unsigned char)(ch*2+unit)));
    if ((v & 0x20) && ((v & 7) < 2)) return 1;
}
return 0;
```

- [ ] **Step 4: Run tests and verify GREEN**

- [ ] **Step 5: Add sentinel assertions for every unowned field**

The final test must compare all `VIA_CONFIG_SIZE` bytes against a saved copy,
allowing differences only in the documented current-channel masks. This catches
unexpected `0x41`, `0x42`, `0x44-0x47`, `0x54`, sibling, and reserved writes.

- [ ] **Step 6: Commit**

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/VIATiming.c \
        src/drivers-i386/ide/drvEIDE/tests/via_timing_test.c
git commit -m "drvEIDE: encode VIA UDMA timing and cable checks"
```

### Task 4: IDENTIFY UDMA modes through mode 5

**Files:**
- Create: `EIDE.lksproj/IdeModeUtils.h`
- Modify: `EIDE.lksproj/IdeCntInit.m:1238-1263`
- Modify: `tests/via_timing_test.c`

- [ ] **Step 1: Add the failing mode-bitmap test**

Include `IdeModeUtils.h`, then add:

```c
CHECK(ideHighestModeBit(0x003f,5) == 0x20);
CHECK(ideHighestModeBit(0x001f,5) == 0x10);
CHECK(ideHighestModeBit(0x0008,5) == 0x08);
CHECK(ideHighestModeBit(0x003f,2) == 0x04);
CHECK(ideHighestModeBit(0x0000,5) == 0x00);
```

- [ ] **Step 2: Run tests and verify RED because the header is absent**

- [ ] **Step 3: Create the helper**

```c
#ifndef _IDE_MODE_UTILS_H_
#define _IDE_MODE_UTILS_H_
static unsigned char ideHighestModeBit(unsigned short supported,
    unsigned char maxMode)
{
    int mode;
    for (mode=maxMode; mode>=0; mode--)
        if (supported & (1U<<mode)) return (unsigned char)(1U<<mode);
    return 0;
}
#endif
```

- [ ] **Step 4: Run tests and verify GREEN**

- [ ] **Step 5: Use the helper in production**

Import `IdeModeUtils.h`. Replace the word-63 scan with
`m=ideHighestModeBit(infoPtr->mwDma,2);`. Replace the word-88 block with:

```objc
m=ATA_MODE_NONE;
if (infoPtr->fieldValidity & IDE_WORD88_SUPPORTED)
    m=ideHighestModeBit(infoPtr->UDma,5);
```

Remove the now-unused local `i`.

- [ ] **Step 6: Run tests and commit**

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeModeUtils.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntInit.m \
        src/drivers-i386/ide/drvEIDE/tests/via_timing_test.c
git commit -m "drvEIDE: recognize UDMA modes through mode 5"
```

### Task 5: DriverKit VIA wrapper and probe integration

**Files:** create `IdeVIA.h/.m`; modify `IdeBMIDE.h`, `IdePIIX.m`,
`IdeGeneric.m`, `PB.project`, and `EIDE.lksproj/Makefile`.

- [ ] **Step 1: Extend match context and verify a deliberate link failure**

Add `unsigned int privateData;` to `ideChipCaps_t`. Change `match` to:

```c
BOOL (*match)(id deviceDescription,unsigned long pciID,
    unsigned char progIf,ideChipCaps_t *out);
```

Update Intel/generic signatures, ignore `deviceDescription`, initialize
`privateData=0`, and pass `devDesc` at call sites. Create `IdeVIA.h`:

```objc
#ifndef _IDE_VIA_H_
#define _IDE_VIA_H_
#import "IdeBMIDE.h"
#import "VIATiming.h"
extern const ideChipsetOps_t ideVIAOps;
#endif
```

Import it in `IdePIIX.m` and insert:

```objc
} else if (ideVIAOps.match(devDesc,_controllerID,progIf,&_chipCaps)) {
    _chipsetOps=&ideVIAOps;
```

Run the driver build. Expected: undefined `ideVIAOps`, proving selection is compiled.

- [ ] **Step 2: Implement exact same-BDF matching in `IdeVIA.m`**

Import `IdeCnt.h`, `IdeVIA.h`, `KernBus.h`, `IOPCIDeviceDescription.h`,
`IOPCIDirectDevice.h`, and `generalFuncs.h`. Declare an `Object` category for
`getRegister:device:function:bus:data:` so the compiler knows the PCI-bus method.

Implement `viaMatch` as:

```objc
if ([desc getPCIdevice:&dev function:&fun bus:&bus] != IO_R_SUCCESS || fun != 1)
    return NO;
pci=[KernBus lookupBusInstanceWithName:"PCI" busId:0];
if (pci==nil || [pci getRegister:0 device:dev function:0 bus:bus data:&bridge]
    != IO_R_SUCCESS || [pci getRegister:8 device:dev function:0 bus:bus
    data:&classRev] != IO_R_SUCCESS) return NO;
chip=VIAFindChip(pciID,bridge,(unsigned char)classRev);
if (!chip) return NO;
out->maxPIO=chip->maxPIO; out->maxMWDMA=chip->maxMWDMA;
out->maxUDMA=chip->maxUDMA;
out->flags=(progIf&PCI_IDE_BUSMASTER)?CHIP_FLAG_BUSMASTER:0;
out->privateData=(unsigned int)chip->chip;
return YES;
```

- [ ] **Step 3: Implement safe snapshot I/O and ops**

`viaReadConfig` reads aligned dwords `0x40,0x44,0x48,0x4c,0x50` through
`getPCIConfigData`, explicitly unpacks little-endian bytes, and returns `NO` on
the first failure. `viaWriteChanges` explicitly repacks each dword and calls
`setPCIConfigData` only when before/after differ, logging any failed write.

Implement `VIAReadConfig:`, `VIAWriteChangesFrom:to:`, `VIASetTiming:`,
`VIAResetTiming`, and `VIADetectCable` as methods of an
`IdeController(VIA)` category. Category methods can access the controller's
private ivars just as the existing `IdeController(PIIX)` category does; the
file-scope ops callbacks remain typed as `id` and only send these messages.

`VIASetTiming:` maps each `driveInfo_t` to:

```objc
t[u].present=drives[u].ideInfo.type!=0;
t[u].pioMode=ata_mode_to_num(ata_mask_to_mode(drives[u].driveModes.mode.pio));
if (t[u].pioMode>4) t[u].pioMode=4;
t[u].transferType=(unsigned char)drives[u].transferType;
t[u].transferMode=ata_mode_to_num(drives[u].transferMode);
```

It reads, copies, calls `VIAComputeConfig` with `_chipCaps.privateData`, and
writes changes. `VIAResetTiming` stops BMIDE, reads/copies, calls
`VIAResetConfig`, and writes changes. `VIADetectCable` reads and calls the pure
helper. Convert `_ideChannel` explicitly to the pure primary/secondary constants.
The file-scope adapters and ops table are:

```objc
static void viaSetTiming(id self,void *d) { [self VIASetTiming:d]; }
static void viaResetTiming(id self) { [self VIAResetTiming]; }
static BOOL viaDetectCable(id self) { return [self VIADetectCable]; }
const ideChipsetOps_t ideVIAOps={"VIA VT82C5xx/686A",viaMatch,
    viaSetTiming,viaResetTiming,viaDetectCable};
```

- [ ] **Step 4: Register sources and headers**

Add `IdeVIA.m` to `CLASSES`, `VIATiming.c` to `C_FILES`/`CFILES`, and
`IdeVIA.h VIATiming.h IdeModeUtils.h` to both header lists. Do not reformat
unrelated manifest entries.

- [ ] **Step 5: Run standalone tests and driver build; verify GREEN**

- [ ] **Step 6: Inspect fallback and commit**

Verify Intel is first, VIA second, generic last; matching performs no writes;
and all back-ends initialize `privateData`.

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeGeneric.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeVIA.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeVIA.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/VIATiming.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/VIATiming.c \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeModeUtils.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PB.project \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/Makefile
git commit -m "drvEIDE: add VIA chipset timing backend"
```

### Task 6: Final verification

**Files:** change only previously listed files if verification exposes a defect.

- [ ] **Step 1: Run a fresh standalone build/test**

Remove `/tmp/via_timing_test`, rerun the full standalone command, and require
the success line with zero warnings.

- [ ] **Step 2: Run `make clean && make` for drvEIDE**

Expected: clean i386 compile/link and rebuilt `EIDE_reloc`.

- [ ] **Step 3: Audit write ownership against the design spec**

Confirm exact masks for `0x43`, `0x4d`, and `0x50-0x53`; no differences at
`0x41`, `0x42`, `0x44-0x47`, or `0x54`; and no sibling channel/drive clobber.

- [ ] **Step 4: Audit ceilings and runtime safety flow**

Confirm the four table ceilings, pre-reset cable detection, negative-cable
UDMA2 cap, existing DMA self-test/demotion loop, and generic fallback.

- [ ] **Step 5: Check scope and formatting**

```sh
git status --short
git diff --check HEAD~4..HEAD
git diff --stat HEAD~4..HEAD
```

Expected: only planned files, no whitespace errors, no unrelated staged work.

- [ ] **Step 6: Report evidence without a silicon claim**

```text
Standalone register tests: passed
Period-toolchain drvEIDE build: passed
Real VT82C586/586A/596A/686A hardware: not tested
```

## Self-review checklist

- Spec coverage: Tasks 1-6 cover exact IDs/revisions, ceilings, same-BDF
  matching, four timing layouts, cable gating, fail-closed fallback, tests,
  manifests, and build.
- Type consistency: `viaChip_t`, `viaChipInfo_t`, `viaConfig_t`,
  `viaDriveTiming_t`, `privateData`, and all pure function names are identical
  between tests, C implementation, and Objective-C wrapper.
- TDD order: pure behaviors start RED then become GREEN; Objective-C selection
  is proven compiled by an intentional undefined-symbol build before its backend.
- Surgical scope: no ATA-command, BMIDE-transfer, Intel-timing, generic-timing,
  SATA, configuration-table, or unrelated driver work is included.
