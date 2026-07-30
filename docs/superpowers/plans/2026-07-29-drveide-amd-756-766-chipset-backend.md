# drvEIDE AMD-756/766 Chipset Back-end Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tested drvEIDE chipset back-end for AMD-756 and AMD-766 with NetBSD-compatible AMD-756 policy and documented AMD-766 cable gating.

**Architecture:** A dependency-free C module owns exact chipset lookup and transforms copied PCI configuration snapshots. A thin Objective-C wrapper maps drvEIDE state into that module, performs PCI access, and plugs into the existing Intel/VIA/generic chipset-op chain.

**Tech Stack:** C89, Objective-C, NeXT/Apple DriverKit, PCI configuration space, ProjectBuilder `pb_makefiles`/`gnumake`, standalone C tests.

---

## Constraints and verification

- Execute in a clean dedicated worktree. The current checkout contains unrelated work and may be used by other agents.
- Build on the committed VIA back-end (`IdeVIA`, `VIATiming`, and `IdeModeUtils`) without refactoring it.
- Exact PCI IDs are AMD-756 `1022:7409` and AMD-766 `1022:7411`.
- AMD-756 revision `<= 3` advertises no MWDMA, but continues to advertise UDMA4. Later AMD-756 revisions advertise MWDMA2.
- AMD-756 always reports cable-qualified, matching NetBSD. AMD-766 requires a current-channel bit in `0x42[3:0]` for UDMA3-5.
- AMD-766 clears the current channel's broken FIFO/prefetch and posted-write controls. AMD-756 preserves them.
- Preserve reserved fields and the complete sibling channel. Current-channel absent drives receive compatible timing and disabled UDMA.
- Do not add AMD-755, AMD-768, AMD-8111, NVIDIA, SATA, RAID, or AHCI support.
- Real silicon is unavailable; report register tests and builds separately from hardware validation.

Standalone test command in the Rhapsody/Unix build environment:

```sh
cc -ansi -pedantic -Wall -Werror \
  -Isrc/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/AMDTiming.c \
  src/drivers-i386/ide/drvEIDE/tests/amd_timing_test.c \
  -o /tmp/amd_timing_test && /tmp/amd_timing_test
```

Expected: `amd_timing_test: all tests passed`.

Existing VIA regression command:

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
cd src/drivers-i386/ide/drvEIDE && make clean && make
```

Expected: `EIDE_reloc` compiles and links for i386 without errors.

## File responsibilities

- `AMDTiming.h/.c`: dependency-free IDs, revision-aware capability lookup, timing computation, reset, FIFO policy, and cable interpretation.
- `IdeAMD.h/.m`: DriverKit wrapper, configuration snapshot I/O, drive-state mapping, and `ideAMDOperations`.
- `tests/amd_timing_test.c`: exact lookup, timing, reset, UDMA, FIFO, cable, validation, and preservation tests.
- `IdeBMIDE.h`: pass the already-read PCI revision through the chipset match operation.
- `IdePIIX.m`, `IdeVIA.m`, `IdeGeneric.m`: match-signature updates and AMD probe insertion.
- `EIDE.lksproj/PB.project`, `EIDE.lksproj/Makefile`: production source
  registration.
- `IdeCntInit.m` and `IdeModeUtils.h`: verification only; the committed VIA work already scans IDENTIFY word 88 through UDMA5.

### Task 1: Pure chipset identification and revision policy

**Files:**
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/AMDTiming.h`
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/AMDTiming.c`
- Create: `src/drivers-i386/ide/drvEIDE/tests/amd_timing_test.c`

- [ ] **Step 1: Write the public pure-C interface and failing lookup test**

Create `AMDTiming.h` with this complete initial interface:

```c
#ifndef AMD_TIMING_H
#define AMD_TIMING_H

#define AMD_IDE_756 0x74091022UL
#define AMD_IDE_766 0x74111022UL
#define AMD_MODE_NONE 0xff

#define AMD_CONFIG_BASE 0x40
#define AMD_CONFIG_SIZE 0x14
#define AMD_CHANNEL_PRIMARY 0
#define AMD_CHANNEL_SECONDARY 1
#define AMD_XFER_PIO 0
#define AMD_XFER_MWDMA 2
#define AMD_XFER_UDMA 3

typedef enum {
    AMD_CHIP_NONE,
    AMD_CHIP_756,
    AMD_CHIP_766
} amdChip_t;

typedef struct {
    amdChip_t chip;
    const char *name;
    unsigned char maxPIO;
    unsigned char maxMWDMA;
    unsigned char maxUDMA;
} amdChipInfo_t;

typedef struct {
    unsigned char bytes[AMD_CONFIG_SIZE];
} amdConfig_t;

typedef struct {
    unsigned char present;
    unsigned char pioMode;
    unsigned char transferType;
    unsigned char transferMode;
} amdDriveTiming_t;

const amdChipInfo_t *AMDFindChip(unsigned long pciID,
                                 unsigned char revision);
void AMDComputeConfig(amdConfig_t *config, amdChip_t chip,
                      unsigned char channel,
                      const amdDriveTiming_t drives[2]);
void AMDResetConfig(amdConfig_t *config, amdChip_t chip,
                    unsigned char channel);
int AMDDetect80WireCable(const amdConfig_t *config, amdChip_t chip,
                         unsigned char channel);

#endif /* AMD_TIMING_H */
```

Create `amd_timing_test.c` with the test harness and lookup cases:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "AMDTiming.h"

static int failures;
#define CFG(c,o) ((c).bytes[(o) - AMD_CONFIG_BASE])
#define CHECK(e) do { if (!(e)) { \
    fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #e); \
    ++failures; } } while (0)

static void test_chip_lookup(void)
{
    const amdChipInfo_t *info;

    info = AMDFindChip(AMD_IDE_756, 3);
    CHECK(info != NULL);
    CHECK(info != NULL && info->chip == AMD_CHIP_756);
    CHECK(info != NULL && info->maxPIO == 4);
    CHECK(info != NULL && info->maxMWDMA == AMD_MODE_NONE);
    CHECK(info != NULL && info->maxUDMA == 4);

    info = AMDFindChip(AMD_IDE_756, 4);
    CHECK(info != NULL && info->maxMWDMA == 2);
    CHECK(info != NULL && info->maxUDMA == 4);

    info = AMDFindChip(AMD_IDE_766, 0);
    CHECK(info != NULL && info->chip == AMD_CHIP_766);
    CHECK(info != NULL && info->maxPIO == 4);
    CHECK(info != NULL && info->maxMWDMA == 2);
    CHECK(info != NULL && info->maxUDMA == 5);

    CHECK(AMDFindChip(AMD_IDE_756, 0) != NULL);
    CHECK(AMDFindChip(AMD_IDE_756, 2)->maxMWDMA == AMD_MODE_NONE);
    CHECK(AMDFindChip(0x74011022UL, 3) == NULL);
    CHECK(AMDFindChip(0x74411022UL, 0) == NULL);
    CHECK(AMDFindChip(0x7411106bUL, 0) == NULL);
}

int main(void)
{
    test_chip_lookup();
    if (failures) {
        fprintf(stderr, "amd_timing_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }
    printf("amd_timing_test: all tests passed\n");
    return EXIT_SUCCESS;
}
```

- [ ] **Step 2: Run the standalone command and verify RED**

Expected: link failure for undefined `AMDFindChip`.

- [ ] **Step 3: Implement the minimal revision-aware lookup**

Create `AMDTiming.c`:

```c
#include "AMDTiming.h"

static const amdChipInfo_t amd756Early = {
    AMD_CHIP_756, "AMD-756", 4, AMD_MODE_NONE, 4
};
static const amdChipInfo_t amd756Later = {
    AMD_CHIP_756, "AMD-756", 4, 2, 4
};
static const amdChipInfo_t amd766 = {
    AMD_CHIP_766, "AMD-766", 4, 2, 5
};

const amdChipInfo_t *AMDFindChip(unsigned long pciID,
                                 unsigned char revision)
{
    if (pciID == AMD_IDE_756)
        return revision <= 3 ? &amd756Early : &amd756Later;
    if (pciID == AMD_IDE_766)
        return &amd766;
    return 0;
}
```

- [ ] **Step 4: Run the standalone command and verify GREEN**

Expected: `amd_timing_test: all tests passed` with zero warnings.

- [ ] **Step 5: Commit the lookup slice**

```sh
git add \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/AMDTiming.h \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/AMDTiming.c \
  src/drivers-i386/ide/drvEIDE/tests/amd_timing_test.c
git commit -m "drvEIDE: add AMD chipset identification"
```

### Task 2: PIO/MWDMA timing and compatible reset

**Files:**
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/AMDTiming.c`
- Modify: `src/drivers-i386/ide/drvEIDE/tests/amd_timing_test.c`

- [ ] **Step 1: Add failing helpers and snapshot tests**

Add these helpers after the test macros:

```c
static void fill_config(amdConfig_t *config, unsigned char value)
{
    memset(config->bytes, value, sizeof(config->bytes));
}

static amdDriveTiming_t drive(unsigned char present, unsigned char pio,
                              unsigned char type, unsigned char mode)
{
    amdDriveTiming_t result;
    result.present = present;
    result.pioMode = pio;
    result.transferType = type;
    result.transferMode = mode;
    return result;
}
```

Add tests that call production functions and compare whole snapshots:

```c
static void test_pio_and_mwdma(void)
{
    static const unsigned char pioData[5] = {0x99,0x65,0x33,0x22,0x20};
    static const unsigned char pioCmd[5] = {0xa8,0x93,0x91,0x22,0x20};
    static const unsigned char dmaData[3] = {0x77,0x21,0x20};
    amdConfig_t c;
    amdDriveTiming_t d[2];
    unsigned char mode;

    d[1] = drive(0, 0, AMD_XFER_PIO, 0);
    for (mode = 0; mode < 5; ++mode) {
        fill_config(&c, 0x00);
        d[0] = drive(1, mode, AMD_XFER_PIO, mode);
        AMDComputeConfig(&c, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, d);
        CHECK(CFG(c,0x4b) == pioData[mode]);
        CHECK(CFG(c,0x4f) == pioCmd[mode]);
    }
    for (mode = 0; mode < 3; ++mode) {
        fill_config(&c, 0x00);
        d[0] = drive(1, 4, AMD_XFER_MWDMA, mode);
        AMDComputeConfig(&c, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, d);
        CHECK(CFG(c,0x4b) == dmaData[mode]);
        CHECK(CFG(c,0x4f) == 0x20);
    }
}

static void test_absent_and_mixed_drives(void)
{
    amdConfig_t c;
    amdDriveTiming_t d[2];

    fill_config(&c, 0x55);
    d[0] = drive(1, 4, AMD_XFER_PIO, 4);
    d[1] = drive(0, 0, AMD_XFER_PIO, 0);
    AMDComputeConfig(&c, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, d);
    CHECK(CFG(c,0x4b) == 0x20);
    CHECK(CFG(c,0x4a) == 0xa8);
    CHECK((CFG(c,0x4c) & 0x0f) == 0x0f);

    fill_config(&c, 0x00);
    d[0] = drive(1, 4, AMD_XFER_PIO, 4);
    d[1] = drive(1, 1, AMD_XFER_PIO, 1);
    AMDComputeConfig(&c, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, d);
    CHECK(CFG(c,0x4b) == 0x20);
    CHECK(CFG(c,0x4a) == 0x65);
    CHECK(CFG(c,0x4f) == 0x93);
}

static void test_reset_preserves_sibling_channel(void)
{
    amdConfig_t c, before;

    fill_config(&c, 0x5a);
    before = c;
    AMDResetConfig(&c, AMD_CHIP_756, AMD_CHANNEL_PRIMARY);
    CHECK(CFG(c,0x4b) == 0xa8 && CFG(c,0x4a) == 0xa8);
    CHECK((CFG(c,0x4c) & 0xf0) == 0xf0);
    CHECK(CFG(c,0x4f) == 0xff);
    CHECK(CFG(c,0x48) == CFG(before,0x48));
    CHECK(CFG(c,0x49) == CFG(before,0x49));
    CHECK(CFG(c,0x4e) == CFG(before,0x4e));
}
```

Call all three from `main` after `test_chip_lookup`.

- [ ] **Step 2: Run the standalone command and verify RED**

Expected: link failures for `AMDComputeConfig` and `AMDResetConfig`.

- [ ] **Step 3: Implement validation, quantization, PIO/MWDMA, and reset**

Add the ATA timing tables and helpers to `AMDTiming.c`:

```c
static const unsigned short pio[5][7] = {
    {70,290,240,600,165,150,600}, {50,290,93,383,125,100,383},
    {30,290,40,330,100,90,240}, {30,80,70,180,80,70,180},
    {25,70,25,120,70,25,120}
};
static const unsigned short mwdma[3][4] = {
    {60,215,215,480}, {45,80,50,150}, {25,70,25,120}
};

static unsigned char clocks(unsigned short ns)
{
    return (unsigned char)((ns + 29) / 30);
}

static unsigned char clamp(unsigned char value, unsigned char lo,
                           unsigned char hi)
{
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
}

static int validChip(amdChip_t chip)
{
    return chip == AMD_CHIP_756 || chip == AMD_CHIP_766;
}

static void fitCycle(unsigned char *active, unsigned char *recover,
                     unsigned char cycle)
{
    unsigned char deficit;

    if ((unsigned int)*active + *recover >= cycle)
        return;
    deficit = (unsigned char)(cycle - *active - *recover);
    *active = (unsigned char)(*active + deficit / 2);
    *recover = (unsigned char)(cycle - *active);
}
```

Add this clock calculation and encoder:

```c
typedef struct {
    unsigned char setup;
    unsigned char active8;
    unsigned char recover8;
    unsigned char active;
    unsigned char recover;
} amdClocks_t;

static unsigned char maximum(unsigned char left, unsigned char right)
{
    return left > right ? left : right;
}

static amdClocks_t computeClocks(const amdDriveTiming_t *drive)
{
    amdClocks_t result;
    unsigned char cycle8;
    unsigned char cycle;

    result.setup = clocks(pio[drive->pioMode][0]);
    result.active8 = clocks(pio[drive->pioMode][1]);
    result.recover8 = clocks(pio[drive->pioMode][2]);
    cycle8 = clocks(pio[drive->pioMode][3]);
    result.active = clocks(pio[drive->pioMode][4]);
    result.recover = clocks(pio[drive->pioMode][5]);
    cycle = clocks(pio[drive->pioMode][6]);
    if (drive->transferType == AMD_XFER_MWDMA) {
        result.setup = maximum(result.setup,
                               clocks(mwdma[drive->transferMode][0]));
        result.active = maximum(result.active,
                                clocks(mwdma[drive->transferMode][1]));
        result.recover = maximum(result.recover,
                                 clocks(mwdma[drive->transferMode][2]));
        cycle = maximum(cycle, clocks(mwdma[drive->transferMode][3]));
    }
    fitCycle(&result.active8, &result.recover8, cycle8);
    fitCycle(&result.active, &result.recover, cycle);
    result.setup = clamp(result.setup, 1, 4);
    result.active8 = clamp(result.active8, 1, 16);
    result.recover8 = clamp(result.recover8, 1, 16);
    result.active = clamp(result.active, 1, 16);
    result.recover = clamp(result.recover, 1, 16);
    return result;
}

static unsigned char encode(unsigned char active, unsigned char recover)
{
    return (unsigned char)(((active - 1) << 4) | (recover - 1));
}
```

Add this complete initial computation. It validates every input before the
first write, initializes both current-channel units to PIO0, programs each
present unit, and merges the shared command timing. UDMA ownership is added in
Task 3.

```c
void AMDComputeConfig(amdConfig_t *config, amdChip_t chip,
                      unsigned char channel,
                      const amdDriveTiming_t drives[2])
{
    amdClocks_t timing;
    unsigned char commandActive;
    unsigned char commandRecover;
    unsigned char commandOffset;
    unsigned char dataOffset;
    unsigned char dn;
    unsigned char setupMask;
    unsigned char setupShift;
    unsigned char unit;

    if (config == 0 || drives == 0 || !validChip(chip) ||
        channel > AMD_CHANNEL_SECONDARY)
        return;
    for (unit = 0; unit < 2; ++unit) {
        if (!drives[unit].present)
            continue;
        if (drives[unit].pioMode > 4 ||
            (drives[unit].transferType == AMD_XFER_MWDMA &&
             drives[unit].transferMode > 2))
            return;
    }

    commandActive = 0;
    commandRecover = 0;
    commandOffset = (unsigned char)(0x4e + (1 - channel) -
                                    AMD_CONFIG_BASE);
    for (unit = 0; unit < 2; ++unit) {
        dn = (unsigned char)(channel * 2 + unit);
        dataOffset = (unsigned char)(0x48 + (3 - dn) - AMD_CONFIG_BASE);
        setupShift = (unsigned char)((3 - dn) * 2);
        setupMask = (unsigned char)(3U << setupShift);
        config->bytes[dataOffset] = 0xa8;
        config->bytes[0x4c - AMD_CONFIG_BASE] =
            (unsigned char)((config->bytes[0x4c - AMD_CONFIG_BASE] &
                             ~setupMask) | (3U << setupShift));
        if (!drives[unit].present)
            continue;
        timing = computeClocks(&drives[unit]);
        config->bytes[dataOffset] = encode(timing.active, timing.recover);
        config->bytes[0x4c - AMD_CONFIG_BASE] =
            (unsigned char)((config->bytes[0x4c - AMD_CONFIG_BASE] &
                             ~setupMask) |
                            ((timing.setup - 1) << setupShift));
        commandActive = maximum(commandActive, timing.active8);
        commandRecover = maximum(commandRecover, timing.recover8);
    }
    if (commandActive == 0)
        config->bytes[commandOffset] = 0xff;
    else
        config->bytes[commandOffset] =
            encode(commandActive, commandRecover);
}
```

Add the complete initial reset implementation:

```c
void AMDResetConfig(amdConfig_t *config, amdChip_t chip,
                    unsigned char channel)
{
    unsigned char dn;
    unsigned char shift;
    unsigned char unit;

    if (config == 0 || !validChip(chip) ||
        channel > AMD_CHANNEL_SECONDARY)
        return;
    for (unit = 0; unit < 2; ++unit) {
        dn = (unsigned char)(channel * 2 + unit);
        config->bytes[0x48 + (3 - dn) - AMD_CONFIG_BASE] = 0xa8;
        shift = (unsigned char)((3 - dn) * 2);
        config->bytes[0x4c - AMD_CONFIG_BASE] =
            (unsigned char)((config->bytes[0x4c - AMD_CONFIG_BASE] &
            ~(3U << shift)) | (3U << shift));
    }
    config->bytes[0x4e + (1 - channel) - AMD_CONFIG_BASE] = 0xff;
}
```

- [ ] **Step 4: Run the standalone command and verify GREEN**

Expected: `amd_timing_test: all tests passed` with zero warnings.

- [ ] **Step 5: Commit the PIO/MWDMA slice**

```sh
git add \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/AMDTiming.c \
  src/drivers-i386/ide/drvEIDE/tests/amd_timing_test.c
git commit -m "drvEIDE: compute AMD PIO and MWDMA timings"
```

### Task 3: UDMA, cable, FIFO, and preservation rules

**Files:**
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/AMDTiming.c`
- Modify: `src/drivers-i386/ide/drvEIDE/tests/amd_timing_test.c`

- [ ] **Step 1: Add failing UDMA, cable, FIFO, and fail-closed tests**

Add these complete behavior tests and call them from `main`:

```c
static void test_all_udma_modes(void)
{
    static const unsigned char encoded[6] = {2,1,0,4,5,6};
    amdConfig_t c;
    amdDriveTiming_t d[2];
    unsigned char mode;

    d[1] = drive(0, 0, AMD_XFER_PIO, 0);
    for (mode = 0; mode < 6; ++mode) {
        fill_config(&c, 0x38);
        d[0] = drive(1, 4, AMD_XFER_UDMA, mode);
        AMDComputeConfig(&c, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, d);
        CHECK(CFG(c,0x53) == (unsigned char)(0xf8 | encoded[mode]));
        CHECK(CFG(c,0x52) == 0x3b);
    }
}

static void test_cable_policy(void)
{
    amdConfig_t c, before;

    fill_config(&c, 0x00);
    before = c;
    CHECK(AMDDetect80WireCable(&c, AMD_CHIP_756,
                               AMD_CHANNEL_PRIMARY) == 1);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
    CHECK(AMDDetect80WireCable(&c, AMD_CHIP_756,
                               AMD_CHANNEL_SECONDARY) == 1);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
    CHECK(AMDDetect80WireCable(&c, AMD_CHIP_766,
                               AMD_CHANNEL_PRIMARY) == 0);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
    CFG(c,0x42) = 0x01;
    before = c;
    CHECK(AMDDetect80WireCable(&c, AMD_CHIP_766,
                               AMD_CHANNEL_PRIMARY) == 1);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
    CHECK(AMDDetect80WireCable(&c, AMD_CHIP_766,
                               AMD_CHANNEL_SECONDARY) == 0);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
    CFG(c,0x42) = 0x08;
    before = c;
    CHECK(AMDDetect80WireCable(&c, AMD_CHIP_766,
                               AMD_CHANNEL_SECONDARY) == 1);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
    CHECK(AMDDetect80WireCable(&c, AMD_CHIP_766,
                               AMD_CHANNEL_PRIMARY) == 0);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
    CHECK(AMDDetect80WireCable(&c, AMD_CHIP_NONE,
                               AMD_CHANNEL_PRIMARY) == 0);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
}

static void test_766_fifo_and_756_preservation(void)
{
    amdConfig_t c;
    amdDriveTiming_t d[2];

    d[0] = drive(1, 4, AMD_XFER_PIO, 4);
    d[1] = drive(0, 0, AMD_XFER_PIO, 0);
    fill_config(&c, 0xff);
    AMDComputeConfig(&c, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, d);
    CHECK(CFG(c,0x41) == 0xff);
    fill_config(&c, 0xff);
    AMDComputeConfig(&c, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, d);
    CHECK(CFG(c,0x41) == 0x3f);
    fill_config(&c, 0xff);
    AMDResetConfig(&c, AMD_CHIP_766, AMD_CHANNEL_SECONDARY);
    CHECK(CFG(c,0x41) == 0xcf);
}

static void test_invalid_inputs_preserve_snapshot(void)
{
    amdConfig_t c, before;
    amdDriveTiming_t d[2];

    fill_config(&c, 0x5a);
    before = c;
    d[0] = drive(1, 5, AMD_XFER_PIO, 4);
    d[1] = drive(0, 0, AMD_XFER_PIO, 0);
    AMDComputeConfig(&c, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, d);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
    AMDComputeConfig(&c, AMD_CHIP_NONE, AMD_CHANNEL_PRIMARY, d);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
    AMDResetConfig(&c, AMD_CHIP_766, 2);
    CHECK(memcmp(c.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
}
```

- [ ] **Step 2: Run the standalone command and verify RED**

Expected: UDMA bytes, cable results, and AMD-766 FIFO assertions fail.

- [ ] **Step 3: Implement exact UDMA ownership and cable policy**

Add the direct mode table:

```c
static const unsigned char amdUDMA[6] = {2, 1, 0, 4, 5, 6};
```

Replace the validation loop in `AMDComputeConfig` with this complete loop:

```c
for (unit = 0; unit < 2; ++unit) {
    if (!drives[unit].present)
        continue;
    if (drives[unit].pioMode > 4 ||
        (drives[unit].transferType == AMD_XFER_MWDMA &&
         drives[unit].transferMode > 2) ||
        (drives[unit].transferType == AMD_XFER_UDMA &&
         drives[unit].transferMode >
             (chip == AMD_CHIP_756 ? 4 : 5)))
        return;
}
```

Add these complete helpers. They own only enable `bits[7:6]` and cycle
`bits[2:0]`, preserving read-only `bits[5:3]`:

```c
static unsigned char udmaOffset(unsigned char channel, unsigned char unit)
{
    unsigned char dn;

    dn = (unsigned char)(channel * 2 + unit);
    return (unsigned char)(0x50 + (3 - dn) - AMD_CONFIG_BASE);
}

static void configureUDMA(amdConfig_t *config, unsigned char channel,
                          const amdDriveTiming_t drives[2])
{
    unsigned char offset;
    unsigned char unit;
    unsigned char value;

    for (unit = 0; unit < 2; ++unit) {
        offset = udmaOffset(channel, unit);
        value = (unsigned char)((config->bytes[offset] & 0x38) | 0x03);
        if (drives[unit].present &&
            drives[unit].transferType == AMD_XFER_UDMA)
            value = (unsigned char)((config->bytes[offset] & 0x38) |
                                    0xc0 |
                                    amdUDMA[drives[unit].transferMode]);
        config->bytes[offset] = value;
    }
}

static void resetUDMA(amdConfig_t *config, unsigned char channel)
{
    unsigned char offset;
    unsigned char unit;

    for (unit = 0; unit < 2; ++unit) {
        offset = udmaOffset(channel, unit);
        config->bytes[offset] =
            (unsigned char)((config->bytes[offset] & 0x38) | 0x03);
    }
}

static void applyFIFOPolicy(amdConfig_t *config, amdChip_t chip,
                            unsigned char channel)
{
    unsigned char mask;

    if (chip != AMD_CHIP_766)
        return;
    mask = channel == AMD_CHANNEL_PRIMARY ? 0xc0 : 0x30;
    config->bytes[0x41 - AMD_CONFIG_BASE] &= (unsigned char)~mask;
}
```

In `AMDComputeConfig`, call `applyFIFOPolicy(config, chip, channel)` directly
after the complete validation loop and call
`configureUDMA(config, channel, drives)` after the PIO/MWDMA loop. In
`AMDResetConfig`, call `applyFIFOPolicy(config, chip, channel)` immediately
after validation and `resetUDMA(config, channel)` after setting the command
timing byte. These calls ensure invalid input still leaves all 20 bytes
unchanged.

Implement cable interpretation without modifying the snapshot:

```c
int AMDDetect80WireCable(const amdConfig_t *config, amdChip_t chip,
                         unsigned char channel)
{
    unsigned char mask;

    if (config == 0 || channel > AMD_CHANNEL_SECONDARY)
        return 0;
    if (chip == AMD_CHIP_756)
        return 1;
    if (chip != AMD_CHIP_766)
        return 0;
    mask = channel == AMD_CHANNEL_PRIMARY ? 0x03 : 0x0c;
    return (config->bytes[0x42 - AMD_CONFIG_BASE] & mask) != 0;
}
```

- [ ] **Step 4: Strengthen whole-snapshot preservation assertions**

Add this helper after `drive()`:

```c
static void check_only_offsets_changed(const amdConfig_t *before,
                                       const amdConfig_t *after,
                                       const unsigned char *allowed,
                                       unsigned int allowedCount)
{
    unsigned int i;
    unsigned int j;
    int mayChange;

    for (i = 0; i < AMD_CONFIG_SIZE; ++i) {
        mayChange = 0;
        for (j = 0; j < allowedCount; ++j) {
            if (i + AMD_CONFIG_BASE == allowed[j])
                mayChange = 1;
        }
        if (!mayChange)
            CHECK(before->bytes[i] == after->bytes[i]);
    }
}
```

Add this test and call it from `main`. The allowed lists cover the complete
snapshot: any write outside the current channel's owned fields fails. The
UDMA checks separately prove that nonzero read-only `bits[5:3]` survive.

```c
static void test_channel_and_reserved_preservation(void)
{
    static const unsigned char primaryAllowed[] = {
        0x41, 0x4a, 0x4b, 0x4c, 0x4f, 0x52, 0x53
    };
    static const unsigned char secondaryAllowed[] = {
        0x41, 0x48, 0x49, 0x4c, 0x4e, 0x50, 0x51
    };
    amdConfig_t c, before;
    amdDriveTiming_t d[2];

    d[0] = drive(1, 4, AMD_XFER_UDMA, 5);
    d[1] = drive(0, 0, AMD_XFER_PIO, 0);

    fill_config(&c, 0x28);
    CFG(c,0x41) = 0xff;
    before = c;
    AMDComputeConfig(&c, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, d);
    check_only_offsets_changed(&before, &c, primaryAllowed,
        sizeof(primaryAllowed) / sizeof(primaryAllowed[0]));
    CHECK((CFG(c,0x53) & 0x38) == (CFG(before,0x53) & 0x38));
    CHECK((CFG(c,0x52) & 0x38) == (CFG(before,0x52) & 0x38));
    CHECK(CFG(c,0x41) == 0x3f);

    fill_config(&c, 0x28);
    CFG(c,0x41) = 0xff;
    before = c;
    AMDComputeConfig(&c, AMD_CHIP_766, AMD_CHANNEL_SECONDARY, d);
    check_only_offsets_changed(&before, &c, secondaryAllowed,
        sizeof(secondaryAllowed) / sizeof(secondaryAllowed[0]));
    CHECK((CFG(c,0x51) & 0x38) == (CFG(before,0x51) & 0x38));
    CHECK((CFG(c,0x50) & 0x38) == (CFG(before,0x50) & 0x38));
    CHECK(CFG(c,0x41) == 0xcf);
}
```

- [ ] **Step 5: Run the standalone command and verify GREEN**

Expected: `amd_timing_test: all tests passed` with zero warnings.

- [ ] **Step 6: Commit the UDMA/cable slice**

```sh
git add \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/AMDTiming.c \
  src/drivers-i386/ide/drvEIDE/tests/amd_timing_test.c
git commit -m "drvEIDE: encode AMD UDMA and cable policy"
```

### Task 4: DriverKit wrapper, revision plumbing, and probe integration

**Files:**
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeAMD.h`
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeAMD.m`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.h`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeVIA.m`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeGeneric.m`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PB.project`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/Makefile`

- [ ] **Step 1: Pass the already-read revision through every match function**

Change `ideChipsetOps_t.match` in `IdeBMIDE.h` to:

```c
BOOL (*match)(id deviceDescription, unsigned long pciID,
    unsigned char revision, unsigned char progIf, ideChipCaps_t *out);
```

Replace the opening of each existing matcher with the corresponding signature
and unused-argument handling; retain the remaining existing declarations and
body after the shown lines:

```objc
static BOOL intelMatch(id deviceDescription, unsigned long pciID,
    unsigned char revision, unsigned char progIf, ideChipCaps_t *out)
{
    const intelChip_t *c = intelLookup(pciID);
    (void)deviceDescription;
    (void)revision;
```

```objc
static BOOL viaMatch(id deviceDescription, unsigned long pciID,
    unsigned char revision, unsigned char progIf, ideChipCaps_t *out)
{
    unsigned char dev;
    unsigned char fun;
    unsigned char bus;
    unsigned long bridge;
    unsigned long classRev;
    const viaChipInfo_t *chip;
    id pci;
    IOReturn rtn;

    (void)revision;
```

```objc
static BOOL genericMatch(id deviceDescription, unsigned long pciID,
    unsigned char revision, unsigned char progIf, ideChipCaps_t *out)
{
    (void)deviceDescription;
    (void)pciID;
    (void)revision;
```

In `IdePIIX.m`, add `revision` beside the existing class-byte declarations and
derive it from `classReg`:

```objc
unsigned char revision;
revision = classReg & 0xff;
```

Replace the existing probe-call fragment with:

```objc
if (ideIntelOps.match(devDesc, _controllerID, revision, progIf,
                      &_chipCaps)) {
    _chipsetOps = &ideIntelOps;
} else if (ideVIAOps.match(devDesc, _controllerID, revision, progIf,
                           &_chipCaps)) {
    _chipsetOps = &ideVIAOps;
} else if (ideGenericOps.match(devDesc, _controllerID, revision, progIf,
                               &_chipCaps)) {
```

Keep the existing generic and legacy bodies after this fragment. Run the
driver build and require compilation to reach the link stage before adding
AMD; signature mismatches must be fixed in this step.

- [ ] **Step 2: Add the AMD declaration and deliberate undefined-symbol probe**

Create `IdeAMD.h`:

```objc
#ifndef _IDE_AMD_H_
#define _IDE_AMD_H_

#import "IdeBMIDE.h"
#import "AMDTiming.h"

extern const ideChipsetOps_t ideAMDOperations;

@interface IdeController(AMD)
- (BOOL) AMDSetTiming:(void *)drives;
- (BOOL) AMDResetTiming;
- (BOOL) AMDDetectCable;
@end

#endif /* _IDE_AMD_H_ */
```

Import `IdeAMD.h` in `IdePIIX.m` and insert AMD after VIA but before generic:

```objc
} else if (ideAMDOperations.match(devDesc, _controllerID, revision,
                                  progIf, &_chipCaps)) {
    _chipsetOps = &ideAMDOperations;
```

Run the driver build. Expected: undefined `ideAMDOperations`, proving the new
selection path is compiled and linked.

- [ ] **Step 3: Implement matching and the ops table**

Start `IdeAMD.m` with:

```objc
#import "IdeCnt.h"
#import "IdeAMD.h"
#import "IdeBMIDE.h"
#import <driverkit/generalFuncs.h>

static BOOL amdMatch(id deviceDescription, unsigned long pciID,
    unsigned char revision, unsigned char progIf, ideChipCaps_t *out)
{
    const amdChipInfo_t *chip;
    (void)deviceDescription;
    chip = AMDFindChip(pciID, revision);
    if (chip == NULL)
        return NO;
    out->maxPIO = chip->maxPIO;
    out->maxMWDMA = chip->maxMWDMA;
    out->maxUDMA = chip->maxUDMA;
    out->flags = (progIf & PCI_IDE_BUSMASTER) ? CHIP_FLAG_BUSMASTER : 0;
    out->privateData = (unsigned int)chip->chip;
    return YES;
}

static void amdSetTiming(id self, void *drives) { [self AMDSetTiming:drives]; }
static void amdResetTiming(id self) { [self AMDResetTiming]; }
static BOOL amdDetectCable(id self) { return [self AMDDetectCable]; }

const ideChipsetOps_t ideAMDOperations = {
    "AMD-756/766", amdMatch, amdSetTiming, amdResetTiming, amdDetectCable
};
```

- [ ] **Step 4: Implement snapshot I/O and channel mapping**

Add `<string.h>` to the imports, then add this category implementation. It
reads aligned dwords `0x40`, `0x44`, `0x48`, `0x4c`, and `0x50`, explicitly
unpacks and repacks little-endian bytes, stops on the first read failure, and
attempts every changed write while returning aggregate success:

```objc
@implementation IdeController(AMD)

- (BOOL) AMDChannel:(unsigned char *)channel
{
    switch (_ideChannel) {
        case PCI_CHANNEL_PRIMARY:
            *channel = AMD_CHANNEL_PRIMARY;
            return YES;
        case PCI_CHANNEL_SECONDARY:
            *channel = AMD_CHANNEL_SECONDARY;
            return YES;
        default:
            return NO;
    }
}

- (BOOL) AMDReadConfig:(amdConfig_t *)config
{
    unsigned int index;
    unsigned int offset;
    unsigned long data;
    IOReturn rtn;

    for (offset = AMD_CONFIG_BASE;
         offset < AMD_CONFIG_BASE + AMD_CONFIG_SIZE; offset += 4) {
        rtn = [[self class] getPCIConfigData:&data
            atRegister:(unsigned char)offset
            withDeviceDescription:[self deviceDescription]];
        if (rtn != IO_R_SUCCESS)
            return NO;
        index = offset - AMD_CONFIG_BASE;
        config->bytes[index] = (unsigned char)(data & 0xff);
        config->bytes[index + 1] = (unsigned char)((data >> 8) & 0xff);
        config->bytes[index + 2] = (unsigned char)((data >> 16) & 0xff);
        config->bytes[index + 3] = (unsigned char)((data >> 24) & 0xff);
    }
    return YES;
}

- (BOOL) AMDWriteChangesFrom:(const amdConfig_t *)before
    to:(const amdConfig_t *)after
{
    unsigned int index;
    unsigned int offset;
    unsigned long beforeData;
    unsigned long afterData;
    IOReturn rtn;
    BOOL success;

    success = YES;
    for (offset = AMD_CONFIG_BASE;
         offset < AMD_CONFIG_BASE + AMD_CONFIG_SIZE; offset += 4) {
        index = offset - AMD_CONFIG_BASE;
        beforeData = (unsigned long)before->bytes[index] |
            ((unsigned long)before->bytes[index + 1] << 8) |
            ((unsigned long)before->bytes[index + 2] << 16) |
            ((unsigned long)before->bytes[index + 3] << 24);
        afterData = (unsigned long)after->bytes[index] |
            ((unsigned long)after->bytes[index + 1] << 8) |
            ((unsigned long)after->bytes[index + 2] << 16) |
            ((unsigned long)after->bytes[index + 3] << 24);
        if (beforeData == afterData)
            continue;
        rtn = [[self class] setPCIConfigData:afterData
            atRegister:(unsigned char)offset
            withDeviceDescription:[self deviceDescription]];
        if (rtn != IO_R_SUCCESS) {
            IOLog("%s: AMD PCI config write failed at 0x%02x\n",
                [self name], offset);
            success = NO;
        }
    }
    return success;
}
```

- [ ] **Step 5: Implement timing, reset, and cable methods**

Append these complete methods to the category implementation, then close it
with `@end`:

```objc
- (BOOL) AMDSetTiming:(void *)drives
{
    driveInfo_t *drv;
    amdConfig_t before;
    amdConfig_t after;
    amdDriveTiming_t timings[2];
    unsigned char channel;
    unsigned char pioMode;
    unsigned int unit;

    if (![self AMDChannel:&channel])
        return NO;
    if (![self AMDReadConfig:&before]) {
        IOLog("%s: AMD PCI config read failed\n", [self name]);
        return NO;
    }
    drv = (driveInfo_t *)drives;
    for (unit = 0; unit < 2; ++unit) {
        pioMode = ata_mode_to_num(
            ata_mask_to_mode(drv[unit].driveModes.mode.pio));
        if (pioMode > 4)
            pioMode = 4;
        timings[unit].present = (drv[unit].ideInfo.type != 0);
        timings[unit].pioMode = pioMode;
        timings[unit].transferType =
            (unsigned char)drv[unit].transferType;
        timings[unit].transferMode =
            ata_mode_to_num(drv[unit].transferMode);
    }
    after = before;
    AMDComputeConfig(&after, (amdChip_t)_chipCaps.privateData, channel,
        timings);
    return [self AMDWriteChangesFrom:&before to:&after];
}

- (BOOL) AMDResetTiming
{
    amdConfig_t before;
    amdConfig_t after;
    unsigned char channel;

    if ((_chipCaps.flags & CHIP_FLAG_BUSMASTER) && _bmRegs != 0)
        bmStopDMA(_bmRegs);
    if (![self AMDChannel:&channel])
        return NO;
    if (![self AMDReadConfig:&before]) {
        IOLog("%s: AMD PCI config read failed\n", [self name]);
        return NO;
    }
    after = before;
    AMDResetConfig(&after, (amdChip_t)_chipCaps.privateData, channel);
    return [self AMDWriteChangesFrom:&before to:&after];
}

- (BOOL) AMDDetectCable
{
    amdConfig_t config;
    amdChip_t chip;
    unsigned char channel;

    chip = (amdChip_t)_chipCaps.privateData;
    if (chip == AMD_CHIP_756)
        return YES;
    if (![self AMDChannel:&channel])
        return NO;
    if (![self AMDReadConfig:&config]) {
        IOLog("%s: AMD PCI config read failed\n", [self name]);
        return NO;
    }
    return AMDDetect80WireCable(&config, chip, channel) ? YES : NO;
}

@end
```

- [ ] **Step 6: Register production files**

In `EIDE.lksproj/Makefile`, make these exact replacements:

```make
CFILES = VIATiming.c AMDTiming.c

CLASSES = AtapiCnt.m AtapiCntCmds.m AtapiCntInternal.m DualEide.m\
          IdeCnt.m IdeCntCmds.m IdeCntInit.m\
          IdePIIX.m IdeVIA.m IdeAMD.m IdeBMIDE.m IdeGeneric.m IdeDisk.m IdeDiskInternal.m IdeKernel.m

HFILES = AtapiCnt.h AtapiCntCmds.h AtapiCntInternal.h AtapiCntPublic.h\
         atapi_extern.h ata_extern.h DualEide.h IdeCnt.h IdeCntCmds.h\
         IdeCntInit.h IdePIIX.h IdeCntInline.h IdeBMIDE.h\
         IdeCntPublic.h IdeDDM.h IdeDisk.h IdeDiskInternal.h\
         IdeKernel.h IdeShared.h PIIXTiming.h PIIX.h IdeVIA.h VIATiming.h IdeAMD.h AMDTiming.h IdeModeUtils.h
```

In `EIDE.lksproj/PB.project`, replace the three affected list fragments with:

```
            IdePIIX.m,
            IdeVIA.m,
            IdeAMD.m,
            IdeBMIDE.m,
```

```
        C_FILES = (VIATiming.c, AMDTiming.c);
```

```
            IdePIIX.h,
            IdeVIA.h,
            IdeAMD.h,
            IdeCntInline.h,
```

and:

```
			VIATiming.h,
			AMDTiming.h,
			IdeModeUtils.h
```

Keep every other manifest entry byte-for-byte unchanged.

- [ ] **Step 7: Run pure tests and the driver build**

Run the AMD standalone command, the VIA regression command, and
`make clean && make`. Expected: both success lines and a successful
`EIDE_reloc` link with no new warnings.

- [ ] **Step 8: Inspect probe order and commit**

Verify the order is Intel, VIA, AMD, generic; exact AMD match performs no
writes; every back-end initializes `privateData`; AMD-756 revision reaches the
pure lookup; and AMD-766 cable failure returns `NO`.

```sh
git add \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeAMD.h \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeAMD.m \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.h \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdePIIX.m \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeVIA.m \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeGeneric.m \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PB.project \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/Makefile
git commit -m "drvEIDE: add AMD 756 and 766 backend"
```

### Task 5: Final verification and evidence audit

**Files:** Change only the files listed above if verification exposes a defect.

- [ ] **Step 1: Run fresh standalone builds**

```sh
rm -f /tmp/amd_timing_test /tmp/via_timing_test
cc -ansi -pedantic -Wall -Werror \
  -Isrc/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/AMDTiming.c \
  src/drivers-i386/ide/drvEIDE/tests/amd_timing_test.c \
  -o /tmp/amd_timing_test && /tmp/amd_timing_test
cc -ansi -pedantic -Wall -Werror \
  -Isrc/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/VIATiming.c \
  src/drivers-i386/ide/drvEIDE/tests/via_timing_test.c \
  -o /tmp/via_timing_test && /tmp/via_timing_test
```

Require both success lines and zero compiler warnings.

- [ ] **Step 2: Run a clean period-toolchain driver build**

```sh
cd src/drivers-i386/ide/drvEIDE
make clean && make
```

Require a successful `EIDE_reloc` compile/link.

- [ ] **Step 3: Audit requirements against source**

Confirm all of the following directly:

- only `1022:7409` and `1022:7411` select AMD;
- AMD-756 revision `<= 3` has no MWDMA but retains UDMA4;
- AMD-756 cable detection always returns qualified;
- AMD-766 requires `0x03` for primary or `0x0c` for secondary cable evidence;
- AMD-766 clears only `0xc0` or `0x30` at `0x41`;
- UDMA mapping is `{2,1,0,4,5,6}` and preserves `bits[5:3]`;
- current-channel absent drives receive PIO0 and disabled UDMA;
- sibling channel bytes are unchanged;
- failed reads cause no writes;
- Intel, VIA, and generic behavior remains intact;
- `IdeCntInit.m` still uses `ideHighestModeBit(infoPtr->UDma, 5)`.

- [ ] **Step 4: Check scope, formatting, and commits**

```sh
git status --short
git diff --check HEAD~4..HEAD
git diff --stat HEAD~4..HEAD
git log -4 --oneline
```

Require only planned files, no whitespace errors, and four focused drvEIDE
implementation commits.

- [ ] **Step 5: Report evidence without a silicon claim**

Use this exact separation in the handoff:

```text
AMD register tests: passed
VIA regression tests: passed
Period-toolchain drvEIDE build: passed
Real AMD-756/766 hardware: not tested
```

## Self-review checklist

- Spec coverage: Tasks 1-5 cover exact IDs, revision policy, ceilings, timing,
  reset, AMD-756 and AMD-766 cable policies, AMD-766 FIFO behavior, failure
  handling, preservation, manifests, regression tests, and build evidence.
- Current-tree adaptation: UDMA word-88 scanning through mode 5 already exists
  from the VIA work, so the plan verifies it instead of editing it again.
- Type consistency: `amdChip_t`, `amdChipInfo_t`, `amdConfig_t`,
  `amdDriveTiming_t`, `ideAMDOperations`, and every pure function name are
  consistent between declarations, tests, implementation, and wrapper.
- TDD order: Tasks 1-3 start RED and become GREEN; Task 4 uses an intentional
  undefined-symbol build before the wrapper exists.
- Surgical scope: no ATA command, BMIDE engine, Intel timing, VIA timing,
  configuration personality, SATA, RAID, or unrelated driver work is included.
