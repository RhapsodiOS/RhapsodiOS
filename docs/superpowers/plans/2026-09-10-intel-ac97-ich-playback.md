# Intel AC97 ICH Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `drvIntelAC97Sound` play 16-bit stereo through an Intel ICH AC'97 controller using the sequences proven by openstep-ac97, verified on the host and in QEMU.

**Architecture:** Keep `IntelAC97Driver` as the sole `IOAudio` subclass. Move ICH reset, BDL, LVI chase, IRQ ack, and CAS/RCS codec port I/O into a C89 core with injected callbacks whose kernel binding is Rhapsody `outb(port, value)`. Correct the codec helper (full 32-bit ID, VRA readback, measured volume width, muted attach). Playback only.

**Tech Stack:** Objective-C DriverKit 3, C89, Project Builder `kernelserver.make`, host `cc`, Python `unittest`, QEMU `AC97`.

**Spec:** `docs/superpowers/specs/2026-09-10-intel-ac97-ich-playback-design.md`

---

## Execution preflight

The working tree has many unrelated files. Before implementation, use `superpowers:using-git-worktrees` and create a worktree from the commit that contains this plan. Do not clean, stage, or delete unrelated files in the current worktree.

Run host commands from the repository root unless a task says otherwise:

```powershell
$DriverRoot = 'src/drivers-i386/sound/drvIntelAC97Sound'
$LinkRoot = "$DriverRoot/IntelAC97.drvproj/IntelAC97.lksproj"
```

Host tests:

```powershell
& make -C "$DriverRoot/tests" -f Makefile.host clean all check
```

If GNU Make is `gnumake`, substitute that name. On Windows, `check` still runs `./intel_ac97_test` (the makefile also removes `intel_ac97_test.exe`).

Do not implement recording, MMIO, or a driver-side `IOAudio` stereo workaround.

## File map

### Create

- `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ICHAC97Controller.h`
- `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ICHAC97Controller.c`
- `src/drivers-i386/sound/drvIntelAC97Sound/tests/Makefile.host`
- `src/drivers-i386/sound/drvIntelAC97Sound/tests/intel_ac97_test.c`
- `src/drivers-i386/sound/drvIntelAC97Sound/tests/driver_contract_test.py`
- `src/drivers-i386/sound/drvIntelAC97Sound/README.md`
- `src/drivers-i386/sound/drvIntelAC97Sound/SOURCES.md`

### Rename

- `ac97.m` → `ac97.c` after DriverKit imports are removed.

### Modify

- `ac97var.h` — delay callback, `ac97_reset` returns `int`, attenuation packing API, per-output bit width.
- `ac97reg.h` — `AC97_RATE_MIN` 8000.
- `IntelAC97Driver.h` / `IntelAC97Driver.m` — instance-owned state, port-first I/O adapters, playback DMA/IRQ.
- `Load_Commands.sect` — `SMAP` / `ADVERTISE` / `WIRE`.
- `IntelAC97.lksproj/Makefile` — `CLASSES` adapter only; `CFILES` the two C cores.
- `vm/run-q35-ahci.sh` — opt-in `--ac97 BACKEND`.
- `vm/test_ahci_scripts.py` — dry-run AC97 args.

## Fixed C interface

All later tasks use these names. Do not rename them.

```c
/* ICHAC97Controller.h */
#ifndef _ICH_AC97_CONTROLLER_H_
#define _ICH_AC97_CONTROLLER_H_

typedef unsigned char ICHAC97UInt8;
typedef unsigned short ICHAC97UInt16;
typedef unsigned int ICHAC97UInt32;

enum {
    kICHAC97Success = 0,
    kICHAC97InvalidArgument = -1,
    kICHAC97Timeout = -2,
    kICHAC97NotPrepared = -3
};

enum {
    kICHAC97ServiceNone = 0,
    kICHAC97ServiceOutput = 1,
    kICHAC97ServiceOutputFIFOError = 2
};

#define ICHAC97_BDL_COUNT       32U
#define ICHAC97_BD_IOC          0x80000000U
#define ICHAC97_BD_LENGTH_MASK  0x0000ffffU

#define ICHAC97_REG_PO_BDBAR    0x10U
#define ICHAC97_REG_PO_CIV      0x14U
#define ICHAC97_REG_PO_LVI      0x15U
#define ICHAC97_REG_PO_SR       0x16U
#define ICHAC97_REG_PO_CR       0x1bU
#define ICHAC97_REG_GLOB_CNT    0x2cU
#define ICHAC97_REG_GLOB_STA    0x30U
#define ICHAC97_REG_CAS         0x34U

#define ICHAC97_CR_RPBM         0x01U
#define ICHAC97_CR_RR           0x02U
#define ICHAC97_CR_FEIE         0x08U
#define ICHAC97_CR_IOCE         0x10U

#define ICHAC97_SR_DCH         0x01U
#define ICHAC97_SR_LVBCI        0x04U
#define ICHAC97_SR_BCIS         0x08U
#define ICHAC97_SR_FIFOE        0x10U
#define ICHAC97_SR_W1C          0x1cU

#define ICHAC97_GLOB_CNT_COLD   0x00000002U
#define ICHAC97_GLOB_CNT_WARM   0x00000004U
#define ICHAC97_GLOB_STA_POINT  0x00000040U
#define ICHAC97_GLOB_STA_PCR    0x00000100U
#define ICHAC97_GLOB_STA_RCS    0x00008000U
#define ICHAC97_GLOB_STA_S2CR   0x10000000U
#define ICHAC97_CAS_BUSY        0x01U

typedef struct {
    void *context;
    ICHAC97UInt8 (*read8)(void *context, ICHAC97UInt32 port);
    ICHAC97UInt16 (*read16)(void *context, ICHAC97UInt32 port);
    ICHAC97UInt32 (*read32)(void *context, ICHAC97UInt32 port);
    void (*write8)(void *context, ICHAC97UInt32 port, ICHAC97UInt8 value);
    void (*write16)(void *context, ICHAC97UInt32 port, ICHAC97UInt16 value);
    void (*write32)(void *context, ICHAC97UInt32 port, ICHAC97UInt32 value);
    void (*delayUS)(void *context, ICHAC97UInt32 microseconds);
} ICHAC97IO;

typedef struct {
    ICHAC97UInt32 bufferAddress;
    ICHAC97UInt32 controlLength;
} ICHAC97BufferDescriptor;

typedef struct {
    ICHAC97BufferDescriptor *bdl;
    ICHAC97UInt32 bdlPhysical;
    ICHAC97UInt32 bufferPhysical;
    ICHAC97UInt32 bufferBytes;
    ICHAC97UInt32 serviceBytes;
    ICHAC97UInt8 fragmentCount;
    ICHAC97UInt8 running;
    ICHAC97UInt32 completions;
    ICHAC97UInt32 fifoErrors;
} ICHAC97Playback;

typedef struct {
    ICHAC97IO io;
    ICHAC97UInt32 nambar;
    ICHAC97UInt32 nabmbar;
    ICHAC97Playback playback;
    ICHAC97UInt32 pendingService;
    ICHAC97UInt8 casBeenUsed;
} ICHAC97Controller;

void ICHAC97ControllerInit(ICHAC97Controller *controller,
                            const ICHAC97IO *io,
                            ICHAC97UInt32 nambar,
                            ICHAC97UInt32 nabmbar);
int ICHAC97PrepareBDL(ICHAC97Playback *playback,
                      ICHAC97BufferDescriptor *bdl,
                      ICHAC97UInt32 bdlPhysical,
                      ICHAC97UInt32 bufferPhysical,
                      ICHAC97UInt32 bufferBytes,
                      ICHAC97UInt32 serviceBytes);
int ICHAC97ResetPlayback(ICHAC97Controller *controller,
                          ICHAC97UInt32 pollCount);
int ICHAC97ResetLink(ICHAC97Controller *controller,
                     ICHAC97UInt32 pollCount);
int ICHAC97StartPlayback(ICHAC97Controller *controller);
void ICHAC97StopPlayback(ICHAC97Controller *controller);
void ICHAC97ChaseLVI(ICHAC97Controller *controller);
ICHAC97UInt32 ICHAC97ServiceInterrupt(ICHAC97Controller *controller);
ICHAC97UInt32 ICHAC97ConsumeService(ICHAC97Controller *controller);
ICHAC97UInt16 ICHAC97CodecRead(ICHAC97Controller *controller,
                               ICHAC97UInt8 reg);
void ICHAC97CodecWrite(ICHAC97Controller *controller,
                       ICHAC97UInt8 reg,
                       ICHAC97UInt16 value);

#endif
```

Codec additions used from Task 5:

```c
typedef void (*ac97_delay_func)(void *context, unsigned int microseconds);
/* fields on struct ac97_codec_state: */
ac97_delay_func delay_us;
void *delay_context;
int out_present[3];
int out_bits[3];

int ac97_reset(struct ac97_codec_state *codec);
unsigned short ac97_attenuation_field(int atten, int bits);
int ac97_measure_volume_bits(struct ac97_codec_state *codec,
                              unsigned char reg);
void ac97_apply_output(struct ac97_codec_state *codec,
                       int leftAtten, int rightAtten, int mute);
```

---

### Task 1: Host harness and wrapping BDL

**Files:**
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/tests/Makefile.host`
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/tests/intel_ac97_test.c`
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ICHAC97Controller.h`
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ICHAC97Controller.c`

- [ ] **Step 1: Create the host makefile and a failing wrap test**

```make
CC ?= cc
CFLAGS ?= -std=c89 -Wall -Wextra -Werror -pedantic
LINKROOT = ../IntelAC97.drvproj/IntelAC97.lksproj
TESTS = intel_ac97_test

.PHONY: all check clean

all: $(TESTS)

intel_ac97_test: intel_ac97_test.c \
        $(LINKROOT)/ICHAC97Controller.c \
        $(LINKROOT)/ICHAC97Controller.h
	$(CC) $(CFLAGS) -I$(LINKROOT) -o $@ \
		intel_ac97_test.c \
		$(LINKROOT)/ICHAC97Controller.c

check: all
	./intel_ac97_test

clean:
	rm -f $(TESTS) $(TESTS).exe *.o
```

```c
#include <stdio.h>
#include <string.h>
#include "ICHAC97Controller.h"

static int failures;

#define CHECK(expression) do { \
    if (!(expression)) { \
        fprintf(stderr, "%s:%d: CHECK failed: %s\n", \
                __FILE__, __LINE__, #expression); \
        failures++; \
    } \
} while (0)

static void test_bdl_wraps_unique_fragments_into_32_slots(void)
{
    ICHAC97Playback playback;
    ICHAC97BufferDescriptor bdl[32];
    unsigned int i;

    memset(&playback, 0, sizeof(playback));
    memset(bdl, 0xa5, sizeof(bdl));
    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0x2000U,
                            0x300000U, 32768U, 4096U) == kICHAC97Success);
    CHECK(playback.fragmentCount == 8U);
    CHECK(playback.serviceBytes == 4096U);
    for (i = 0; i < 32U; i++) {
        CHECK(bdl[i].bufferAddress == 0x300000U + (i % 8U) * 4096U);
        CHECK(bdl[i].controlLength == (ICHAC97_BD_IOC | 2048U));
    }
    CHECK(bdl[8].bufferAddress == 0x300000U);
    CHECK(bdl[31].bufferAddress == 0x300000U + (31U % 8U) * 4096U);
}

static void test_bdl_64k_8k_and_rejects(void)
{
    ICHAC97Playback playback;
    ICHAC97BufferDescriptor bdl[32];

    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0x2000U,
                            0x300000U, 65536U, 8192U) == kICHAC97Success);
    CHECK(playback.fragmentCount == 8U);
    CHECK(bdl[0].controlLength == (ICHAC97_BD_IOC | 4096U));
    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0U, 0U,
                            0U, 4096U) == kICHAC97InvalidArgument);
    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0U, 0U,
                            32768U, 4095U) == kICHAC97InvalidArgument);
    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0U, 0U,
                            32769U, 4096U) == kICHAC97InvalidArgument);
    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0U, 0U,
                            67584U, 2048U) == kICHAC97InvalidArgument);
}

int main(void)
{
    test_bdl_wraps_unique_fragments_into_32_slots();
    test_bdl_64k_8k_and_rejects();
    if (failures != 0) {
        fprintf(stderr, "%d Intel AC97 checks failed\n", failures);
        return 1;
    }
    puts("Intel AC97 checks passed");
    return 0;
}
```

- [ ] **Step 2: Run the test and confirm it fails to compile**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all
```

Expected: missing `ICHAC97Controller.h` or `ICHAC97PrepareBDL`.

- [ ] **Step 3: Add the header (the fixed interface above) and implement `ICHAC97ControllerInit` plus `ICHAC97PrepareBDL`**

`ICHAC97PrepareBDL` must fill **all 32** descriptors by wrapping `i % fragmentCount`, length in samples (`serviceBytes / 2`), `IOC` set. Other functions stub: reset/start return `kICHAC97NotPrepared`; stop/chase are no-ops; service/consume return 0; codec read returns `0xffff`.

```c
void ICHAC97ControllerInit(ICHAC97Controller *controller,
                            const ICHAC97IO *io,
                            ICHAC97UInt32 nambar,
                            ICHAC97UInt32 nabmbar)
{
    if (controller == 0 || io == 0)
        return;
    memset(controller, 0, sizeof(*controller));
    controller->io = *io;
    controller->nambar = nambar;
    controller->nabmbar = nabmbar;
}

int ICHAC97PrepareBDL(ICHAC97Playback *playback,
                        ICHAC97BufferDescriptor *bdl,
                        ICHAC97UInt32 bdlPhysical,
                        ICHAC97UInt32 bufferPhysical,
                        ICHAC97UInt32 bufferBytes,
                        ICHAC97UInt32 serviceBytes)
{
    ICHAC97UInt32 nFrags;
    ICHAC97UInt32 samples;
    ICHAC97UInt32 i;

    if (playback == 0 || bdl == 0 || bufferBytes == 0U ||
        serviceBytes == 0U || (serviceBytes & 1U) != 0U ||
        (bufferBytes % serviceBytes) != 0U)
        return kICHAC97InvalidArgument;
    nFrags = bufferBytes / serviceBytes;
    samples = serviceBytes / 2U;
    if (nFrags == 0U || nFrags > ICHAC97_BDL_COUNT ||
        samples == 0U || samples > ICHAC97_BD_LENGTH_MASK)
        return kICHAC97InvalidArgument;

    memset(bdl, 0, sizeof(*bdl) * ICHAC97_BDL_COUNT);
    for (i = 0; i < ICHAC97_BDL_COUNT; i++) {
        bdl[i].bufferAddress = bufferPhysical + (i % nFrags) * serviceBytes;
        bdl[i].controlLength = ICHAC97_BD_IOC | samples;
    }
    memset(playback, 0, sizeof(*playback));
    playback->bdl = bdl;
    playback->bdlPhysical = bdlPhysical;
    playback->bufferPhysical = bufferPhysical;
    playback->bufferBytes = bufferBytes;
    playback->serviceBytes = serviceBytes;
    playback->fragmentCount = (ICHAC97UInt8)nFrags;
    return kICHAC97Success;
}
```

- [ ] **Step 4: Run host checks**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: `Intel AC97 checks passed`.

- [ ] **Step 5: Commit**

```powershell
git add -- $LinkRoot/ICHAC97Controller.h $LinkRoot/ICHAC97Controller.c $DriverRoot/tests/Makefile.host $DriverRoot/tests/intel_ac97_test.c
git commit -m "drvIntelAC97Sound: wrap ICH playback descriptors into 32 slots"
```

---

### Task 2: RR clears BDBAR; start programs it after reset

**Files:**
- Modify: `intel_ac97_test.c`
- Modify: `ICHAC97Controller.c`

- [ ] **Step 1: Add FakeIO and failing reset/start tests**

Fake I/O is a 512-byte register file. `write8` to `ICHAC97_REG_PO_CR` with `ICHAC97_CR_RR` set must zero BDBAR at offsets `0x10..0x13`. Polling `read8` of CR clears `RR` after `resetReadsBeforeClear` reads (same pattern as a bounded wait).

```c
typedef struct {
    unsigned char regs[512];
    unsigned int delayCalls;
    unsigned int resetReadsBeforeClear;
    unsigned int resetReads;
    unsigned int opCount;
    struct {
        char width;
        char write;
        unsigned int port;
        unsigned int value;
    } op[128];
} FakeIO;

static unsigned char fake_read8(void *context, unsigned int port)
{
    FakeIO *fake = (FakeIO *)context;
    unsigned int offset = port & 0x1ffU;
    if (offset == ICHAC97_REG_PO_CR &&
        (fake->regs[offset] & ICHAC97_CR_RR) != 0U &&
        fake->resetReads++ >= fake->resetReadsBeforeClear)
        fake->regs[offset] = (unsigned char)(fake->regs[offset] & ~ICHAC97_CR_RR);
    return fake->regs[offset];
}

static unsigned short fake_read16(void *context, unsigned int port)
{
    FakeIO *fake = (FakeIO *)context;
    unsigned int offset = port & 0x1ffU;
    return (unsigned short)(fake->regs[offset] |
                            ((unsigned short)fake->regs[offset + 1U] << 8));
}

static unsigned int fake_read32(void *context, unsigned int port)
{
    return fake_read16(context, port) |
           ((unsigned int)fake_read16(context, port + 2U) << 16);
}

static void fake_write8(void *context, unsigned int port, unsigned char value)
{
    FakeIO *fake = (FakeIO *)context;
    unsigned int offset = port & 0x1ffU;
    fake->regs[offset] = value;
    if (offset == ICHAC97_REG_PO_CR && (value & ICHAC97_CR_RR) != 0U) {
        fake->regs[ICHAC97_REG_PO_BDBAR] = 0;
        fake->regs[ICHAC97_REG_PO_BDBAR + 1U] = 0;
        fake->regs[ICHAC97_REG_PO_BDBAR + 2U] = 0;
        fake->regs[ICHAC97_REG_PO_BDBAR + 3U] = 0;
    }
    if (fake->opCount < 128U) {
        fake->op[fake->opCount].width = 1;
        fake->op[fake->opCount].write = 1;
        fake->op[fake->opCount].port = offset;
        fake->op[fake->opCount].value = value;
        fake->opCount++;
    }
}

static void fake_write16(void *context, unsigned int port, unsigned short value)
{
    fake_write8(context, port, (unsigned char)value);
    fake_write8(context, port + 1U, (unsigned char)(value >> 8));
}

static void fake_write32(void *context, unsigned int port, unsigned int value)
{
    fake_write16(context, port, (unsigned short)value);
    fake_write16(context, port + 2U, (unsigned short)(value >> 16));
}

static void fake_delay(void *context, unsigned int microseconds)
{
    FakeIO *fake = (FakeIO *)context;
    (void)microseconds;
    fake->delayCalls++;
}

static ICHAC97Controller fake_controller(FakeIO *fake)
{
    ICHAC97Controller controller;
    ICHAC97IO io;
    memset(&io, 0, sizeof(io));
    io.context = fake;
    io.read8 = fake_read8;
    io.read16 = fake_read16;
    io.read32 = fake_read32;
    io.write8 = fake_write8;
    io.write16 = fake_write16;
    io.write32 = fake_write32;
    io.delayUS = fake_delay;
    ICHAC97ControllerInit(&controller, &io, 0U, 0U);
    return controller;
}

static void test_rr_clears_bdbar_and_start_rewrites_it(void)
{
    FakeIO fake;
    ICHAC97Controller controller;
    ICHAC97BufferDescriptor bdl[32];

    memset(&fake, 0, sizeof(fake));
    fake.resetReadsBeforeClear = 0U;
    controller = fake_controller(&fake);
    CHECK(ICHAC97PrepareBDL(&controller.playback, bdl, 0x4000U,
                            0x320000U, 32768U, 4096U) == kICHAC97Success);
    fake_write32(&fake, ICHAC97_REG_PO_BDBAR, 0xdeadbeefU);
    CHECK(ICHAC97ResetPlayback(&controller, 3U) == kICHAC97Success);
    CHECK(fake_read32(&fake, ICHAC97_REG_PO_BDBAR) == 0U);
    CHECK(ICHAC97StartPlayback(&controller) == kICHAC97Success);
    CHECK(fake_read32(&fake, ICHAC97_REG_PO_BDBAR) == 0x4000U);
    CHECK(fake.regs[ICHAC97_REG_PO_LVI] == 31U);
    CHECK((fake.regs[ICHAC97_REG_PO_CR] &
           (ICHAC97_CR_RPBM | ICHAC97_CR_FEIE | ICHAC97_CR_IOCE)) ==
          (ICHAC97_CR_RPBM | ICHAC97_CR_FEIE | ICHAC97_CR_IOCE));
    CHECK(controller.playback.running == 1U);
    ICHAC97StopPlayback(&controller);
    CHECK(controller.playback.running == 0U);
    CHECK((fake.regs[ICHAC97_REG_PO_CR] & ICHAC97_CR_RPBM) == 0U);
}
```

Call the new test from `main`.

- [ ] **Step 2: Run tests — stubs fail**

Expected: `kICHAC97NotPrepared` or failed CHECKs.

- [ ] **Step 3: Implement reset/start/stop**

`ICHAC97ResetPlayback`: `write8(CR, RR)`, poll `read8` until RR clear (delay 10 µs per try), return timeout if not. Do not write BDBAR here.

`ICHAC97StartPlayback`: require prepared BDL; call reset; **then** `write32(BDBAR, bdlPhysical)`; `write8(LVI, 31)`; ack `SR & W1C`; `write8(CR, RPBM|FEIE|IOCE)`; `running = 1`.

`ICHAC97StopPlayback`: `write8(CR, 0)`; ack W1C; `running = 0`.

- [ ] **Step 4: Host checks pass**

- [ ] **Step 5: Commit**

```powershell
git add -- $LinkRoot/ICHAC97Controller.c $DriverRoot/tests/intel_ac97_test.c
git commit -m "drvIntelAC97Sound: program BDBAR after channel reset"
```

---

### Task 3: LVI chase and output IRQ service

**Files:**
- Modify: `intel_ac97_test.c`
- Modify: `ICHAC97Controller.c`

- [ ] **Step 1: Add failing LVI and IRQ tests**

```c
static void test_lvi_chase_and_output_irq(void)
{
    FakeIO fake;
    ICHAC97Controller controller;
    ICHAC97BufferDescriptor bdl[32];
    unsigned int service;

    memset(&fake, 0, sizeof(fake));
    controller = fake_controller(&fake);
    CHECK(ICHAC97PrepareBDL(&controller.playback, bdl, 0x4000U,
                            0x320000U, 32768U, 4096U) == kICHAC97Success);
    CHECK(ICHAC97StartPlayback(&controller) == kICHAC97Success);

    fake.regs[ICHAC97_REG_PO_CIV] = 4U;
    ICHAC97ChaseLVI(&controller);
    CHECK(fake.regs[ICHAC97_REG_PO_LVI] == 3U);

    fake.regs[ICHAC97_REG_GLOB_STA] = (unsigned char)ICHAC97_GLOB_STA_POINT;
    fake.regs[ICHAC97_REG_GLOB_STA + 1U] = 0;
    fake.regs[ICHAC97_REG_PO_SR] = ICHAC97_SR_BCIS;
    fake.regs[ICHAC97_REG_PO_CIV] = 5U;
    service = ICHAC97ServiceInterrupt(&controller);
    CHECK((service & kICHAC97ServiceOutput) != 0U);
    CHECK(controller.playback.completions == 1U);
    CHECK(fake.regs[ICHAC97_REG_PO_LVI] == 4U);
    CHECK(fake.regs[ICHAC97_REG_PO_SR] == ICHAC97_SR_BCIS);
    CHECK(ICHAC97ConsumeService(&controller) == service);
    CHECK(ICHAC97ConsumeService(&controller) == 0U);

    fake.regs[ICHAC97_REG_GLOB_STA] = (unsigned char)ICHAC97_GLOB_STA_POINT;
    fake.regs[ICHAC97_REG_PO_SR] = ICHAC97_SR_FIFOE | ICHAC97_SR_BCIS;
    service = ICHAC97ServiceInterrupt(&controller);
    CHECK((service & kICHAC97ServiceOutputFIFOError) != 0U);
    CHECK(controller.playback.fifoErrors == 1U);
}
```

- [ ] **Step 2: Confirm stubs fail**

- [ ] **Step 3: Implement chase and service**

`ICHAC97ChaseLVI`: `civ = read8(PO_CIV)`; `write8(PO_LVI, (civ - 1) & 31)`.

`ICHAC97ServiceInterrupt`: read `GLOB_STA`; if `POINT`, read `PO_SR`, ack `SR & W1C` via `write16`, ack `POINT` via `write32` of `GLOB_STA` with only that bit; on `BCIS` increment completions, chase LVI, set `kICHAC97ServiceOutput`; on `FIFOE` increment fifoErrors and set FIFO flag. Or the bits into `pendingService`. Return the new bits.

`ICHAC97ConsumeService`: return `pendingService` and clear it.

- [ ] **Step 4: Host checks pass**

- [ ] **Step 5: Commit**

```powershell
git commit -m "drvIntelAC97Sound: chase LVI on playback completion"
```

---

### Task 4: CAS/RCS codec access and warm/cold link reset

**Files:**
- Modify: `intel_ac97_test.c`
- Modify: `ICHAC97Controller.c`

- [ ] **Step 1: Add failing codec-port and link-reset tests**

Extend FakeIO: `casBusyReads` — `read8(CAS)` returns `ICHAC97_CAS_BUSY` until that many reads, then 0. Codec NAMBAR is 0 in these tests, so mixer registers live in `regs[0..0xff]`.

```c
static void test_codec_cas_rcs_and_link_reset(void)
{
    FakeIO fake;
    ICHAC97Controller controller;
    unsigned short value;

    memset(&fake, 0, sizeof(fake));
    fake.casBusyReads = 1U;
    fake.regs[0x02] = 0x08;
    fake.regs[0x03] = 0x08;
    controller = fake_controller(&fake);
    value = ICHAC97CodecRead(&controller, 0x02);
    CHECK(value == 0x0808U);
    CHECK(fake.delayCalls >= 1U);

    memset(&fake, 0, sizeof(fake));
    fake.regs[ICHAC97_REG_GLOB_STA] = 0;
    fake.regs[ICHAC97_REG_GLOB_STA + 1U] = 0x80; /* RCS in bit 15 */
    controller = fake_controller(&fake);
    CHECK(ICHAC97CodecRead(&controller, 0x02) == 0xffffU);

    memset(&fake, 0, sizeof(fake));
    fake.regs[ICHAC97_REG_GLOB_CNT] = (unsigned char)ICHAC97_GLOB_CNT_COLD;
    fake.regs[ICHAC97_REG_GLOB_STA + 1U] = 0x01; /* PCR bit 8 */
    controller = fake_controller(&fake);
    CHECK(ICHAC97ResetLink(&controller, 3U) == kICHAC97Success);
    CHECK(fake.delayCalls >= 1U);

    memset(&fake, 0, sizeof(fake));
    controller = fake_controller(&fake);
    CHECK(ICHAC97ResetLink(&controller, 2U) == kICHAC97Timeout);
}
```

CAS busy helper: in `fake_read8`, if `offset == ICHAC97_REG_CAS` and a new `casReads` counter `< casBusyReads`, return `ICHAC97_CAS_BUSY`.

- [ ] **Step 2: Confirm stubs fail** (codec read is `0xffff`)

- [ ] **Step 3: Implement**

Wait for `CAS` bit 0 to drop (poll + 1 µs delay, max 100 tries) before each codec access; skip the wait if already waited once this command (`casBeenUsed` is optional; a wait every time is correct). After NAMBAR `read16`/`write16`, read `GLOB_STA`; if `RCS`, write `RCS` to clear it and return `0xffff` on read.

`ICHAC97ResetLink`: read `GLOB_CNT`. If `COLD` is set, set `WARM`; else clear `COLD`, delay 1 ms, set `COLD`. Poll `PCR` with 1 ms delays.

- [ ] **Step 4: Host checks pass**

- [ ] **Step 5: Commit**

```powershell
git commit -m "drvIntelAC97Sound: wait CAS and use warm reset when the link is up"
```

---

### Task 5: Hostable codec — ID, VRA readback, volume packing, muted attach

**Files:**
- Rename: `ac97.m` → `ac97.c`
- Modify: `ac97var.h`, `ac97reg.h`
- Modify: `tests/Makefile.host`, `intel_ac97_test.c`

- [ ] **Step 1: `git mv` ac97.m to ac97.c and add failing codec tests**

Link `ac97.c` into `intel_ac97_test`. Tests:

```c
#include "ac97var.h"

static void test_codec_id_vra_volume_and_muted_attach(void)
{
    struct ac97_codec_state codec;
    FakeCodec fake;

    CHECK(ac97_attenuation_field(0, 5) == 0U);
    CHECK(ac97_attenuation_field(-42, 5) == 15U);
    CHECK(ac97_attenuation_field(-84, 5) == 31U);
    CHECK(ac97_attenuation_field(-42, 6) == 31U);
    CHECK(ac97_attenuation_field(-84, 6) == 63U);

    memset(&fake, 0, sizeof(fake));
    fake.regs[AC97_REG_POWERDOWN >> 1] =
        AC97_PWR_REF | AC97_PWR_ANL | AC97_PWR_DAC;
    fake.regs[AC97_REG_VENDOR_ID1 >> 1] = 0x4144U;
    fake.regs[AC97_REG_VENDOR_ID2 >> 1] = 0x5370U;
    fake.regs[AC97_REG_EXT_AUDIO_ID >> 1] = AC97_EXT_AUDIO_VRA;
    fake.regs[AC97_REG_MASTER_VOLUME >> 1] = 0x1f1fU;
    init_fake_codec(&codec, &fake);
    CHECK(ac97_attach(&codec, AC97_CODEC_TYPE_AUDIO) == 0);
    CHECK(codec.vendor_id == 0x41445370U);
    CHECK(strcmp(codec.codec_name, "AD1980") == 0);
    CHECK(codec.vra_enabled == 1);
    CHECK(codec.master_mute == 1);

    fake.rejectVRA = 1;
    memset(&codec, 0, sizeof(codec));
    memset(&fake, 0, sizeof(fake));
    fake.regs[AC97_REG_POWERDOWN >> 1] =
        AC97_PWR_REF | AC97_PWR_ANL | AC97_PWR_DAC;
    fake.regs[AC97_REG_EXT_AUDIO_ID >> 1] = AC97_EXT_AUDIO_VRA;
    init_fake_codec(&codec, &fake);
    CHECK(ac97_attach(&codec, AC97_CODEC_TYPE_AUDIO) == 0);
    CHECK(codec.vra_enabled == 0);
    CHECK(ac97_set_rate(&codec, AC97_RATE_DAC, 44100U) == -1);
    CHECK(ac97_set_rate(&codec, AC97_RATE_DAC, 48000U) == 0);
}
```

```c
typedef struct {
    unsigned short regs[64];
    unsigned int delays;
    int rejectVRA;
} FakeCodec;

static unsigned short fake_codec_read(void *context, unsigned char reg)
{
    return ((FakeCodec *)context)->regs[reg >> 1];
}

static void fake_codec_write(void *context, unsigned char reg,
                             unsigned short value)
{
    FakeCodec *fake = (FakeCodec *)context;
    if (reg == AC97_REG_EXT_AUDIO_CTRL && fake->rejectVRA)
        return;
    fake->regs[reg >> 1] = value;
}

static void fake_codec_delay(void *context, unsigned int microseconds)
{
    (void)microseconds;
    ((FakeCodec *)context)->delays++;
}

static void init_fake_codec(struct ac97_codec_state *codec, FakeCodec *fake)
{
    memset(codec, 0, sizeof(*codec));
    codec->host_priv = fake;
    codec->read_reg = fake_codec_read;
    codec->write_reg = fake_codec_write;
    codec->delay_us = fake_codec_delay;
    codec->delay_context = fake;
}
```

Identify must **not** use `vendor_id & AC97_VENDOR_ID_MASK == table[i].id`.

- [ ] **Step 2: Build fails on DriverKit imports / old signatures**

- [ ] **Step 3: Make `ac97.c` hostable**

- `#include` std headers, not DriverKit.
- Add `delay_us` / `delay_context`; route `IODelay` through them.
- `ac97_reset` returns `-1` on timeout, `0` on success; `ac97_attach` returns `-1` if reset fails.
- Identify: exact `vendor_id == ac97_codecs[i].id`.
- After writing `VRA`, read `EXT_AUDIO_CTRL`; `vra_enabled` only if the bit stuck.
- Attach sets master/PCM **muted** (`mute=1`), no record setup.
- `ac97_set_rate`: reject outside 8000–48000; reject non-48000 when `!vra_enabled`; write; read back; update cache only on exact match; return `-1` otherwise (leave cache unchanged).
- `AC97_RATE_MIN` → 8000.
- Implement `ac97_attenuation_field` as `(-atten * ((1<<bits)-1)) / 84` with atten clamped to 0…−84.
- `ac97_measure_volume_bits`: write `AC97_MUTE | 0x003f`, read, count low bits, restore; clamp result to 5..6.
- `ac97_apply_output`: for each present output, pack left/right with that register’s bits, preserve mute bit.
- Remove `IOLog` from the normal attach path (adapter logs after success).

- [ ] **Step 4: Host checks pass with no C89 warnings**

- [ ] **Step 5: Commit**

```powershell
git add -A -- $LinkRoot/ac97.m $LinkRoot/ac97.c $LinkRoot/ac97var.h $LinkRoot/ac97reg.h $DriverRoot/tests
git commit -m "drvIntelAC97Sound: identify codecs and pack volume from measured width"
```

---

### Task 6: SoundKit load commands, makefile lists, source-contract harness

**Files:**
- Modify: `Load_Commands.sect`
- Modify: `IntelAC97.lksproj/Makefile`
- Create: `tests/driver_contract_test.py`
- Modify: `tests/Makefile.host` `check` rule

- [ ] **Step 1: Write failing contract tests**

```python
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
LINK = ROOT / "IntelAC97.drvproj" / "IntelAC97.lksproj"


class DriverContractTests(unittest.TestCase):
    def test_load_commands_wire_soundkit(self):
        text = (LINK / "Load_Commands.sect").read_text(encoding="utf-8")
        self.assertIn("SMAP", text)
        self.assertIn("audio0", text)
        self.assertIn("ADVERTISE", text)
        self.assertIn("WIRE", text)
        self.assertNotIn("sectcreate", text)

    def test_makefile_splits_c_and_objc(self):
        makefile = (LINK / "Makefile").read_text(encoding="utf-8")
        self.assertIn("CLASSES = IntelAC97Driver.m", makefile)
        self.assertIn("CFILES = ac97.c ICHAC97Controller.c", makefile)
        self.assertFalse((LINK / "ac97.m").exists())
        for name in ("ac97.c", "ICHAC97Controller.c"):
            source = (LINK / name).read_text(encoding="utf-8")
            self.assertNotIn("@interface", source)
            self.assertNotIn("<driverkit/", source)
            self.assertNotIn("outb(", source)
            self.assertNotIn("outw(", source)
            self.assertNotIn("outl(", source)

    def test_kernel_io_is_port_then_value(self):
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        self.assertIn("outb((IOEISAPortAddress)port, value)", source)
        self.assertNotIn("outb(value, port)", source)
        self.assertNotIn("outw(value, port)", source)
        self.assertNotIn("outl(value, port)", source)
        self.assertIn("ICHAC97Controller controller;", source)
        self.assertNotIn("static struct ich_state", source)


if __name__ == "__main__":
    unittest.main()
```

`check` runs `./intel_ac97_test` then `python3 driver_contract_test.py` (or `python` on Windows if `python3` is missing — try `python3` first).

- [ ] **Step 2: Run the Python tests; they fail on current Load_Commands / CLASSES / global `s`**

- [ ] **Step 3: Replace `Load_Commands.sect` with:**

```
#
# Audio drivers must use these load commands to connect to
# NeXT user-level sound API.
#
SMAP		audio0 audioMessages 0
ADVERTISE	audio0
WIRE
```

Set makefile:

```make
CLASSES = IntelAC97Driver.m

CFILES = ac97.c ICHAC97Controller.c

HFILES = ac97reg.h ac97var.h ICHAC97Controller.h IntelAC97Driver.h
```

Do not yet rewrite the whole adapter; the port-order and `ICHAC97Controller` assertions will still fail until Task 7.

- [ ] **Step 4: Run C tests (must still pass). Python: load-commands and makefile assertions pass; adapter assertions still fail.**

- [ ] **Step 5: Commit the load commands and makefile (leave failing adapter tests in the file — they become Task 7’s red bar). If you prefer green `check` at every commit, keep the adapter assertions commented until Task 7, then enable them in Task 7 Step 1.**

Prefer: enable all assertions in Task 7 Step 1. This task commits Load_Commands + makefile + the two tests that already pass.

```powershell
git commit -m "drvIntelAC97Sound: wire SoundKit load commands"
```

---

### Task 7: Instance-owned state and port-first kernel I/O

**Files:**
- Modify: `IntelAC97Driver.h`
- Modify: `IntelAC97Driver.m`
- Modify: `driver_contract_test.py` — enable the adapter assertions from Task 6

- [ ] **Step 1: Enable the remaining contract tests; run them; they fail**

- [ ] **Step 2: Replace global `s` with instance state**

Header: forward-declare `struct ich97_driver_state;` add ivar `struct ich97_driver_state *state;`

Implementation:

```c
struct ich97_driver_state {
    ICHAC97Controller controller;
    struct ac97_codec_state codec;
    IOInterruptHandler oldHandler;
    simple_lock_t lock;
    BOOL ioAudioInitialized;
    BOOL interruptRegistered;
    BOOL mixerRangeRegistered;
    BOOL busMasterRangeRegistered;
    BOOL codecAttached;
    unsigned int bufVirt;
    unsigned int lastService;
};

static struct ich97_driver_state *activeInterruptState;

static unsigned char kernel_read8(void *context, unsigned int port)
{
    (void)context;
    return inb((IOEISAPortAddress)port);
}
/* kernel_read16 / kernel_read32 likewise */

static void kernel_write8(void *context, unsigned int port, unsigned char value)
{
    (void)context;
    outb((IOEISAPortAddress)port, value);
}
static void kernel_write16(void *context, unsigned int port, unsigned short value)
{
    (void)context;
    outw((IOEISAPortAddress)port, value);
}
static void kernel_write32(void *context, unsigned int port, unsigned int value)
{
    (void)context;
    outl((IOEISAPortAddress)port, value);
}
static void kernel_delay(void *context, unsigned int microseconds)
{
    (void)context;
    IODelay(microseconds);
}
```

Define if missing:

```c
#ifndef PCI_COMMAND_IO_ENABLE
#define PCI_COMMAND_IO_ENABLE     0x0001
#define PCI_COMMAND_MEM_ENABLE    0x0002
#define PCI_COMMAND_MASTER_ENABLE 0x0004
#endif
#define ICH97_PCI_BASE_IO(x) ((unsigned int)((x) & ~3UL))
```

`initFromDeviceDescription:`: BAR0 I/O → NAMBAR, BAR1 I/O → NABMBAR; reject otherwise. Enable command bits `IO|MEM|MASTER`. Allocate `state`, `ICHAC97ControllerInit` with kernel callbacks, nambar/nabmbar. Reject if `activeInterruptState != 0`. Set `activeInterruptState` **before** `[super initFromDeviceDescription:]`. Set `ioAudioInitialized` after super succeeds. Every failure calls `-ich97_release_state` and returns `nil`.

`-ich97_release_state`: stop playback, clear active bridge if it points here, `releaseInterrupt:0` / port ranges 0 and 1 if flagged, `IOFree` BDL if present, `simple_lock_free`, `IOFree` state. Idempotent.

`-free`: release helper then `[super free]`.

Keep existing PCI device-ID switch, `getDataEncodings` (`NX_SoundStreamDataEncoding_Linear16`), and `channelCountLimit` of 2. Mixer port range size 256, bus-master 64. Do not call `outb(value, port)` anywhere in this file.

`-reset`: `ICHAC97ResetPlayback`, `ICHAC97ResetLink`, fill codec callbacks from `ICHAC97CodecRead/Write` and `kernel_delay`, `ac97_attach`. On success `codecAttached = YES` and log vendor/name. Return `NO` on timeout.

After super init returns, call a helper that reads `[self outputAttenuationLeft/Right]` and `[self isOutputMuted]` and `ac97_apply_output` with mute forced on (`mute=1`) until playback `running`.

- [ ] **Step 3: `python driver_contract_test.py` and C tests pass**

- [ ] **Step 4: Commit**

```powershell
git commit -m "drvIntelAC97Sound: own ICH state and write ports in Rhapsody order"
```

---

### Task 8: Bind playback DMA and shared IRQ

**Files:**
- Modify: `IntelAC97Driver.m`
- Modify: `driver_contract_test.py`

- [ ] **Step 1: Add failing contracts**

```python
    def test_playback_dma_and_irq_paths(self):
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        create = source[source.index("createDMABufferFor:"):source.index("startDMAForChannel:")]
        start = source[source.index("startDMAForChannel:"):source.index("stopDMAForChannel:")]
        stop = source[source.index("stopDMAForChannel:"):source.index("interruptClearFunc")]
        self.assertIn("return NULL", create)
        self.assertNotIn("ICHAC97PrepareBDL", create)
        self.assertIn("ICHAC97PrepareBDL", start)
        self.assertIn("bufferSizeForInterrupts", start)
        self.assertIn("ICHAC97StartPlayback", start)
        self.assertIn("isRead", start)
        self.assertIn("ICHAC97StopPlayback", stop)
        self.assertNotIn("disableAllInterrupts", stop)
        self.assertGreaterEqual(source.count("IOEnableInterrupt"), 2)
        handler = source[source.index("static void clearInt"):]
        self.assertIn("IOEnableInterrupt(identity)", handler)
```

- [ ] **Step 2: Run; fail on current 32-way split / disableAllInterrupts**

- [ ] **Step 3: Implement**

`createDMABufferFor:`: if `isRead`, return `NULL`. Map `*physicalAddress` with `IOPhysicalFromVirtual`. Store `bufVirt` and `bufferPhysical`/`bufferBytes`. `IOMalloc` 32 descriptors; map BDL physical; return `(IOEISADMABuffer)physAddr`. Do not write BDBAR.

`startDMAForChannel:`: if `isRead`, return `NO`. `ICHAC97PrepareBDL(..., bufferSizeForInterrupts)`. `ac97_set_rate(DAC, [self sampleRate])`. `ICHAC97StartPlayback`. `ac97_apply_output` with real mute flag (engine now running). `[self enableAllInterrupts]`. Return `YES` only if start succeeded.

`stopDMAForChannel:`: `ICHAC97StopPlayback` only. Do not `disableAllInterrupts`.

`clearInterrupts` / `clearInt`: if `activeInterruptState == 0`, `clearInt` still `IOEnableInterrupt` and return. Else lock, `ICHAC97ServiceInterrupt`, unlock. `clearInt`: if service has output, call `oldHandler`; **always** `IOEnableInterrupt` on every path.

`interruptOccurredForInput:forOutput:`: consume service; `*serviceInput = NO`; `*serviceOutput = (service & kICHAC97ServiceOutput) != 0`. Log FIFO on first and every 256th `fifoErrors`.

`timeoutOccurred`: `IOLog` timeout; do not restart.

- [ ] **Step 4: Host C + Python checks pass**

- [ ] **Step 5: Commit**

```powershell
git commit -m "drvIntelAC97Sound: start playback from IOAudio fragment size"
```

---

### Task 9: Rates and mixer callbacks

**Files:**
- Modify: `IntelAC97Driver.m`
- Modify: `driver_contract_test.py`

- [ ] **Step 1: Failing contracts**

Assert `acceptsContinuousSamplingRates` uses `codec.vra_enabled`; `getSamplingRates` writes `48000` only when VRA is off; `updateSampleRate` calls `ac97_set_rate(..., AC97_RATE_DAC` and not `AC97_RATE_ADC`; `updateOutputAttenuationLeft` calls `ac97_apply_output`; `updateInputGainLeft` has no `ac97_` call.

- [ ] **Step 2: Run; fail on current 7-rate list / ADC set / `*31/13`**

- [ ] **Step 3: Implement**

`acceptsContinuousSamplingRates` → `state && state->codec.vra_enabled`.

Without VRA: `getSamplingRatesLow:high:` both 48000; `getSamplingRates:count:` one entry 48000. With VRA: 8000–48000 and the seven conventional rates.

`updateSampleRate`: DAC only; log if `ac97_set_rate` fails.

`updateOutputMute` / Left / Right: if `!codecAttached` return. `mute = [self isOutputMuted] || !controller.playback.running`. `ac97_apply_output(codec, left, right, mute)`.

Input gain methods: empty bodies.

During attach, `ac97_measure_volume_bits` for master `0x02`, headphone `0x04`, surround `0x38`; `out_present[i] = (read != 0xffff)`.

- [ ] **Step 4: All host checks pass**

- [ ] **Step 5: Commit**

```powershell
git commit -m "drvIntelAC97Sound: apply IOAudio attenuation with codec bit widths"
```

---

### Task 10: QEMU `--ac97` and operator docs

**Files:**
- Modify: `vm/run-q35-ahci.sh`
- Modify: `vm/test_ahci_scripts.py`
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/README.md`
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/SOURCES.md`

- [ ] **Step 1: Add failing dry-run test** (same structure as existing `test_launcher_dry_run_has_q35_ports_root_keys_and_logs`): `--ac97 dsound` must print `-audiodev` / `dsound,id=ac97` and `-device` / `AC97,audiodev=ac97`; without `--ac97` those strings are absent.

- [ ] **Step 2: Run; launcher usage-fails `--ac97`**

- [ ] **Step 3: Parse `--ac97 BACKEND`** (`none|dbus|dsound|jack|sdl|spice|wav`). After optional disks/ISO:

```sh
if [ -n "$ac97_backend" ]; then
    set -- "$@" -audiodev "$ac97_backend,id=ac97" \
        -device AC97,audiodev=ac97
fi
```

- [ ] **Step 4: `python -m unittest vm.test_ahci_scripts -v` passes**

- [ ] **Step 5: README** — PCI `8086:2415`, playback-only, host `make -C tests -f Makefile.host check`, guest `gnumake` from driver root, disposable `--ac97 dsound` example, play long enough for several ring wraps, no FIFO/timeout. **SOURCES.md** — NetBSD `auich`/`ac97`, openstep-ac97 as protocol confirmation (not copied), Rhapsody `ioPorts.h` port-first, GPLv2 on these files.

- [ ] **Step 6: Commit**

```powershell
git commit -m "drvIntelAC97Sound: document QEMU AC97 playback checks"
```

---

### Task 11: Native build and QEMU playback gate

**Files:** in-scope only if a gate finds a defect.

- [ ] **Step 1:** `make -C tests -f Makefile.host clean all check` and `python -m unittest vm.test_ahci_scripts -v` and `git diff --check`

- [ ] **Step 2:** Sync and `gnumake clean all` in the Rhapsody guest under `src/drivers-i386/sound/drvIntelAC97Sound`. Expect `IntelAC97_reloc` with no implicit-declaration warnings from the new files.

- [ ] **Step 3:** Disposable `--ac97 dsound` boot. Serial log: `8086:2415` or ICH name, codec ready, identified codec. Play 16-bit stereo ≥2 s. No FIFO, no `Timeout waiting for interrupt`.

- [ ] **Step 4:** If a gate required a fix, commit only that fix as `drvIntelAC97Sound: fix QEMU playback issue`. Do not create an empty commit.

---

## Spec coverage

| Spec requirement | Task |
|---|---|
| 32-slot wrapping BDL, sample lengths, IOC | 1 |
| RR clears BDBAR; BDBAR after RR; LVI=31; FEIE | 2 |
| LVI chase; GSTS.POINT ack; always re-enable IRQ (adapter) | 3, 8 |
| CAS/RCS; warm vs cold reset | 4 |
| Full 32-bit ID; VRA readback; packing; muted attach | 5, 9 |
| `SMAP`/`ADVERTISE`/`WIRE` | 6 |
| Port-first `outb`; no global `s`; staged free | 7 |
| Playback-only DMA; no `disableAllInterrupts` on stop | 8 |
| Mixer after super init; no unmute until running | 7, 9 |
| QEMU `--ac97` playback smoke | 10, 11 |
| Capture / MMIO / kernel workaround / import their `.m` | none (out of scope) |
