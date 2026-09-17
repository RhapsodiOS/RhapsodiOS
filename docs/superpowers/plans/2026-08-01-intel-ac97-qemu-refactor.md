# Intel AC97 QEMU Playback and Recording Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `drvIntelAC97Sound` into a testable Rhapsody DriverKit adapter plus pure-C ICH and codec cores, providing reliable full-duplex stereo PCM audio with QEMU's Intel 82801AA AC97 device.

**Architecture:** Keep `IntelAC97Driver` as the sole `IOAudio` subclass and give it explicit ownership of one controller state. Move ICH reset, BDL, DMA, and interrupt behavior into a C89 core with injected port-I/O callbacks; convert the existing codec helper into a hostable C89 module with injected delay callbacks. Verify the cores on the host, verify the adapter through source-contract and native builds, and add an opt-in AC97 path to the disposable QEMU launcher.

**Tech Stack:** Objective-C DriverKit 3, C89, NeXT Project Builder `kernelserver.make`, host `cc`/`clang`, Python `unittest`, QEMU `AC97`, Git Bash/PowerShell VM tooling.

---

## Execution preflight

The current branch contains unrelated working-tree files. Before implementation,
use `superpowers:using-git-worktrees` and create a `codex/` worktree from commit
`e44103ee` or a later commit containing this plan. Never copy, clean, stage, or
delete the unrelated files from the current worktree.

Run host commands from the repository root unless a task says otherwise. Use:

```powershell
$DriverRoot = 'src/drivers-i386/sound/drvIntelAC97Sound'
$LinkRoot = "$DriverRoot/IntelAC97.drvproj/IntelAC97.lksproj"
```

The host test command used throughout the plan is:

```powershell
& make -C "$DriverRoot/tests" -f Makefile.host clean all check
```

On systems where GNU Make is named `gnumake`, substitute `gnumake` without
changing any target names.

## File map

### Create

- `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ICHAC97Controller.h`
  - C89 types, register constants, I/O callback contract, per-channel state,
    controller state, and the testable controller API.
- `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ICHAC97Controller.c`
  - BDL construction, DMA reset/start/stop, AC-link reset, codec register access,
    and shared-interrupt decode/acknowledgement.
- `src/drivers-i386/sound/drvIntelAC97Sound/tests/Makefile.host`
  - Host compilation of both pure-C cores and the C tests.
- `src/drivers-i386/sound/drvIntelAC97Sound/tests/intel_ac97_test.c`
  - Fake I/O backend plus controller and codec unit tests.
- `src/drivers-i386/sound/drvIntelAC97Sound/tests/driver_contract_test.py`
  - Adapter, makefile, and file-boundary source-contract checks.
- `src/drivers-i386/sound/drvIntelAC97Sound/README.md`
  - Supported QEMU target, host/native build commands, and guest smoke procedure.
- `src/drivers-i386/sound/drvIntelAC97Sound/SOURCES.md`
  - Apple/QEMU references and the adaptation boundary.

### Rename

- `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ac97.m`
  to `ac97.c` after its DriverKit imports have been removed.

### Modify

- `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ac97var.h`
  - Add injected delay callback, status codes, and status-returning reset/rate API.
- `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ac97reg.h`
  - Correct the minimum advertised VRA rate to 8 kHz and add focused masks used by
    tested mixer packing.
- `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/IntelAC97Driver.h`
  - Add the instance-owned opaque state pointer and the input-selection override.
- `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/IntelAC97Driver.m`
  - Reduce to PCI/DriverKit lifecycle, callback adapters, and audio-control mapping.
- `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/Makefile`
  - Compile C cores through `CFILES` and only the adapter through `CLASSES`.
- `vm/run-q35-ahci.sh`
  - Add quoted, opt-in `--ac97 BACKEND` QEMU arguments.
- `vm/test_ahci_scripts.py`
  - Verify AC97 dry-run arguments without changing existing launcher behavior.

## Fixed public C interfaces

All tasks use these names and types. Do not rename them during implementation.

```c
/* ICHAC97Controller.h */
typedef unsigned char ICHAC97UInt8;
typedef unsigned short ICHAC97UInt16;
typedef unsigned int ICHAC97UInt32;

typedef enum {
    kICHAC97PCMInput = 0,
    kICHAC97PCMOutput = 1,
    kICHAC97ChannelCount = 2
} ICHAC97Channel;

enum {
    kICHAC97Success = 0,
    kICHAC97InvalidArgument = -1,
    kICHAC97Timeout = -2,
    kICHAC97NotPrepared = -3
};

enum {
    kICHAC97ServiceNone = 0,
    kICHAC97ServiceInput = 1,
    kICHAC97ServiceOutput = 2,
    kICHAC97ServiceInputFIFOError = 4,
    kICHAC97ServiceOutputFIFOError = 8
};

typedef struct {
    ICHAC97UInt32 bufferAddress;
    ICHAC97UInt32 controlLength;
} ICHAC97BufferDescriptor;

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
    ICHAC97BufferDescriptor *bdl;
    ICHAC97UInt32 bdlPhysical;
    ICHAC97UInt32 bufferVirtual;
    ICHAC97UInt32 bufferPhysical;
    ICHAC97UInt32 bufferBytes;
    ICHAC97UInt32 serviceBytes;
    ICHAC97UInt8 descriptorCount;
    ICHAC97UInt8 running;
    ICHAC97UInt32 completions;
    ICHAC97UInt32 fifoErrors;
} ICHAC97ChannelState;

typedef struct {
    ICHAC97IO io;
    ICHAC97UInt32 nambar;
    ICHAC97UInt32 nabmbar;
    ICHAC97ChannelState channel[kICHAC97ChannelCount];
    ICHAC97UInt32 pendingService;
} ICHAC97Controller;

void ICHAC97ControllerInit(ICHAC97Controller *controller,
                           const ICHAC97IO *io,
                           ICHAC97UInt32 nambar,
                           ICHAC97UInt32 nabmbar);
int ICHAC97PrepareBDL(ICHAC97ChannelState *channel,
                     ICHAC97BufferDescriptor *bdl,
                     ICHAC97UInt32 bdlPhysical,
                     ICHAC97UInt32 bufferVirtual,
                     ICHAC97UInt32 bufferPhysical,
                     ICHAC97UInt32 bufferBytes,
                     ICHAC97UInt32 serviceBytes);
int ICHAC97ResetChannel(ICHAC97Controller *controller,
                       ICHAC97Channel channel,
                       ICHAC97UInt32 pollCount);
int ICHAC97ResetLink(ICHAC97Controller *controller,
                    ICHAC97UInt32 pollCount);
int ICHAC97StartChannel(ICHAC97Controller *controller,
                       ICHAC97Channel channel);
void ICHAC97StopChannel(ICHAC97Controller *controller,
                       ICHAC97Channel channel);
ICHAC97UInt32 ICHAC97ServiceInterrupt(ICHAC97Controller *controller);
ICHAC97UInt32 ICHAC97ConsumeService(ICHAC97Controller *controller);
ICHAC97UInt16 ICHAC97CodecRead(ICHAC97Controller *controller,
                              ICHAC97UInt8 reg);
void ICHAC97CodecWrite(ICHAC97Controller *controller,
                      ICHAC97UInt8 reg,
                      ICHAC97UInt16 value);
```

The codec keeps its existing function names. These signatures change:

```c
typedef void (*ac97_delay_func)(void *context, unsigned int microseconds);

/* New fields in struct ac97_codec_state. */
ac97_delay_func delay_us;
void *delay_context;

int ac97_reset(struct ac97_codec_state *codec);
int ac97_set_rate(struct ac97_codec_state *codec,
                  int which,
                  unsigned int rate);
void ac97_set_record_gain(struct ac97_codec_state *codec,
                          unsigned char left,
                          unsigned char right,
                          int mute);
```

---

### Task 1: Establish the host harness and exact BDL geometry

**Files:**
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/tests/Makefile.host`
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/tests/intel_ac97_test.c`
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ICHAC97Controller.h`
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ICHAC97Controller.c`

- [ ] **Step 1: Create the host makefile and a failing 32 KiB BDL test**

Use this makefile so every later test compiles the production C sources:

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
	rm -f $(TESTS) *.o
```

Tasks 4 and 5 add `ac97.c` and `driver_contract_test.py` to this makefile after
those files are host-buildable and present.

Start `intel_ac97_test.c` with this complete first test harness:

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

static void test_bdl_32k_uses_eight_4k_descriptors(void)
{
    ICHAC97ChannelState channel;
    ICHAC97BufferDescriptor bdl[32];
    unsigned int index;

    memset(&channel, 0, sizeof(channel));
    memset(bdl, 0xa5, sizeof(bdl));
    CHECK(ICHAC97PrepareBDL(&channel, bdl, 0x2000U,
                           0x100000U, 0x300000U,
                           32768U, 4096U) == kICHAC97Success);
    CHECK(channel.descriptorCount == 8U);
    for (index = 0; index < 8U; index++) {
        CHECK(bdl[index].bufferAddress == 0x300000U + index * 4096U);
        CHECK(bdl[index].controlLength == (0x80000000U | 2048U));
    }
    for (index = 8U; index < 32U; index++) {
        CHECK(bdl[index].bufferAddress == 0U);
        CHECK(bdl[index].controlLength == 0U);
    }
}

int main(void)
{
    test_bdl_32k_uses_eight_4k_descriptors();
    if (failures != 0) {
        fprintf(stderr, "%d Intel AC97 checks failed\n", failures);
        return 1;
    }
    puts("Intel AC97 checks passed");
    return 0;
}
```

- [ ] **Step 2: Run the test to verify the controller API is missing**

Run:

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all
```

Expected: compilation fails because `ICHAC97Controller.h` or
`ICHAC97PrepareBDL` does not exist.

- [ ] **Step 3: Add the fixed header contract and minimal BDL implementation**

Create `ICHAC97Controller.h` from the complete fixed interface above, wrapped
in `_ICH_AC97_CONTROLLER_H_` include guards. Implement initialization and BDL
preparation as follows:

```c
#include <string.h>
#include "ICHAC97Controller.h"

#define ICHAC97_BDL_COUNT 32U
#define ICHAC97_BD_IOC 0x80000000U
#define ICHAC97_BD_LENGTH_MASK 0x0000ffffU

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

int ICHAC97PrepareBDL(ICHAC97ChannelState *channel,
                     ICHAC97BufferDescriptor *bdl,
                     ICHAC97UInt32 bdlPhysical,
                     ICHAC97UInt32 bufferVirtual,
                     ICHAC97UInt32 bufferPhysical,
                     ICHAC97UInt32 bufferBytes,
                     ICHAC97UInt32 serviceBytes)
{
    ICHAC97UInt32 count;
    ICHAC97UInt32 samples;
    ICHAC97UInt32 index;

    if (channel == 0 || bdl == 0 || bufferBytes == 0U ||
        serviceBytes == 0U || (serviceBytes & 1U) != 0U ||
        bufferBytes % serviceBytes != 0U)
        return kICHAC97InvalidArgument;
    count = bufferBytes / serviceBytes;
    samples = serviceBytes / 2U;
    if (count == 0U || count > ICHAC97_BDL_COUNT ||
        samples == 0U || samples > ICHAC97_BD_LENGTH_MASK)
        return kICHAC97InvalidArgument;

    memset(bdl, 0, sizeof(*bdl) * ICHAC97_BDL_COUNT);
    for (index = 0; index < count; index++) {
        bdl[index].bufferAddress = bufferPhysical + index * serviceBytes;
        bdl[index].controlLength = ICHAC97_BD_IOC | samples;
    }
    memset(channel, 0, sizeof(*channel));
    channel->bdl = bdl;
    channel->bdlPhysical = bdlPhysical;
    channel->bufferVirtual = bufferVirtual;
    channel->bufferPhysical = bufferPhysical;
    channel->bufferBytes = bufferBytes;
    channel->serviceBytes = serviceBytes;
    channel->descriptorCount = (ICHAC97UInt8)count;
    return kICHAC97Success;
}
```

For the declarations implemented in later tasks, add these exact C89 stubs so
the module links without pretending hardware behavior exists:

```c
int ICHAC97ResetChannel(ICHAC97Controller *controller,
                       ICHAC97Channel channel,
                       ICHAC97UInt32 pollCount)
{
    (void)controller;
    (void)channel;
    (void)pollCount;
    return kICHAC97NotPrepared;
}

int ICHAC97ResetLink(ICHAC97Controller *controller,
                    ICHAC97UInt32 pollCount)
{
    (void)controller;
    (void)pollCount;
    return kICHAC97NotPrepared;
}

int ICHAC97StartChannel(ICHAC97Controller *controller,
                       ICHAC97Channel channel)
{
    (void)controller;
    (void)channel;
    return kICHAC97NotPrepared;
}

void ICHAC97StopChannel(ICHAC97Controller *controller,
                       ICHAC97Channel channel)
{
    (void)controller;
    (void)channel;
}

ICHAC97UInt32 ICHAC97ServiceInterrupt(ICHAC97Controller *controller)
{
    (void)controller;
    return 0U;
}

ICHAC97UInt32 ICHAC97ConsumeService(ICHAC97Controller *controller)
{
    (void)controller;
    return 0U;
}

ICHAC97UInt16 ICHAC97CodecRead(ICHAC97Controller *controller,
                              ICHAC97UInt8 reg)
{
    (void)controller;
    (void)reg;
    return 0xffffU;
}

void ICHAC97CodecWrite(ICHAC97Controller *controller,
                      ICHAC97UInt8 reg,
                      ICHAC97UInt16 value)
{
    (void)controller;
    (void)reg;
    (void)value;
}
```

- [ ] **Step 4: Add boundary cases and verify the BDL tests pass**

Add `test_bdl_boundaries` and call it from `main`:

```c
static void test_bdl_boundaries(void)
{
    ICHAC97ChannelState channel;
    ICHAC97BufferDescriptor bdl[32];

    CHECK(ICHAC97PrepareBDL(&channel, bdl, 0x2000U,
                           0x100000U, 0x300000U,
                           65536U, 4096U) == kICHAC97Success);
    CHECK(channel.descriptorCount == 16U);
    CHECK(bdl[15].bufferAddress == 0x30f000U);
    CHECK(bdl[15].controlLength == (0x80000000U | 2048U));
    CHECK(ICHAC97PrepareBDL(&channel, bdl, 0U, 0U, 0U,
                           0U, 4096U) == kICHAC97InvalidArgument);
    CHECK(ICHAC97PrepareBDL(&channel, bdl, 0U, 0U, 0U,
                           32768U, 4095U) == kICHAC97InvalidArgument);
    CHECK(ICHAC97PrepareBDL(&channel, bdl, 0U, 0U, 0U,
                           32769U, 4096U) == kICHAC97InvalidArgument);
    CHECK(ICHAC97PrepareBDL(&channel, bdl, 0U, 0U, 0U,
                           67584U, 2048U) == kICHAC97InvalidArgument);
}
```

Run:

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: `Intel AC97 checks passed`.

- [ ] **Step 5: Commit the BDL core**

```powershell
git add -- $LinkRoot/ICHAC97Controller.h $LinkRoot/ICHAC97Controller.c $DriverRoot/tests/Makefile.host $DriverRoot/tests/intel_ac97_test.c
git commit -m "drvIntelAC97Sound: build tested ICH descriptor rings"
```

### Task 2: Implement bounded DMA and AC-link reset sequences

**Files:**
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/tests/intel_ac97_test.c`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ICHAC97Controller.c`

- [ ] **Step 1: Add a fake port-I/O backend and failing reset tests**

Add a `FakeIO` with a 512-byte register array, delay counter, scripted
channel-reset behavior, and operation log:

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
    if ((offset == 0x0bU || offset == 0x1bU) &&
        (fake->regs[offset] & 0x02U) != 0U &&
        fake->resetReads++ >= fake->resetReadsBeforeClear)
        fake->regs[offset] &= (unsigned char)~0x02U;
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
    unsigned int lo = fake_read16(context, port);
    unsigned int hi = fake_read16(context, port + 2U);
    return lo | (hi << 16);
}

static void fake_write8(void *context, unsigned int port, unsigned char value)
{
    FakeIO *fake = (FakeIO *)context;
    unsigned int offset = port & 0x1ffU;
    fake->regs[offset] = value;
    fake->op[fake->opCount].width = 1;
    fake->op[fake->opCount].write = 1;
    fake->op[fake->opCount].port = offset;
    fake->op[fake->opCount].value = value;
    fake->opCount++;
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
```

Add these tests and call both from `main`:

```c
static void test_channel_reset_is_bounded(void)
{
    FakeIO fake;
    ICHAC97Controller controller;

    memset(&fake, 0, sizeof(fake));
    fake.resetReadsBeforeClear = 1U;
    controller = fake_controller(&fake);
    CHECK(ICHAC97ResetChannel(&controller, kICHAC97PCMOutput, 3U) ==
          kICHAC97Success);
    CHECK(fake.delayCalls == 1U);
    CHECK((fake.regs[0x1bU] & 0x02U) == 0U);

    memset(&fake, 0, sizeof(fake));
    fake.resetReadsBeforeClear = 100U;
    controller = fake_controller(&fake);
    CHECK(ICHAC97ResetChannel(&controller, kICHAC97PCMInput, 3U) ==
          kICHAC97Timeout);
    CHECK(fake.delayCalls == 3U);
}

static void test_link_reset_orders_cold_reset_and_times_out(void)
{
    FakeIO fake;
    ICHAC97Controller controller;

    memset(&fake, 0, sizeof(fake));
    fake.regs[0x2cU] = 0x02U;
    fake.regs[0x31U] = 0x01U;
    controller = fake_controller(&fake);
    CHECK(ICHAC97ResetLink(&controller, 3U) == kICHAC97Success);
    CHECK(fake.opCount == 8U);
    CHECK(fake.op[0].port == 0x2cU && fake.op[0].value == 0x00U);
    CHECK(fake.op[4].port == 0x2cU && fake.op[4].value == 0x02U);
    CHECK(fake.delayCalls == 1U);

    memset(&fake, 0, sizeof(fake));
    controller = fake_controller(&fake);
    CHECK(ICHAC97ResetLink(&controller, 3U) == kICHAC97Timeout);
    CHECK(fake.delayCalls == 4U);
}
```

- [ ] **Step 2: Run the tests and confirm the reset stubs fail**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: reset assertions fail because the Task 1 stubs return
`kICHAC97NotPrepared`.

- [ ] **Step 3: Implement bounded channel reset and AC-link reset**

Add these constants and functions:

```c
#define ICHAC97_REG_GLOB_CNT 0x2cU
#define ICHAC97_REG_GLOB_STA 0x30U
#define ICHAC97_CR_RR 0x02U
#define ICHAC97_GLOB_CNT_COLD 0x00000002U
#define ICHAC97_GLOB_STA_PCR 0x00000100U

static ICHAC97UInt32 channel_base(ICHAC97Channel channel)
{
    return channel == kICHAC97PCMInput ? 0x00U : 0x10U;
}

int ICHAC97ResetChannel(ICHAC97Controller *controller,
                       ICHAC97Channel channel,
                       ICHAC97UInt32 pollCount)
{
    ICHAC97UInt32 cr;
    ICHAC97UInt32 index;
    if (controller == 0 || channel >= kICHAC97ChannelCount ||
        controller->io.read8 == 0 || controller->io.write8 == 0)
        return kICHAC97InvalidArgument;
    cr = controller->nabmbar + channel_base(channel) + 0x0bU;
    controller->io.write8(controller->io.context, cr, ICHAC97_CR_RR);
    for (index = 0; index < pollCount; index++) {
        if ((controller->io.read8(controller->io.context, cr) &
             ICHAC97_CR_RR) == 0U)
            return kICHAC97Success;
        if (controller->io.delayUS != 0)
            controller->io.delayUS(controller->io.context, 10U);
    }
    return kICHAC97Timeout;
}

int ICHAC97ResetLink(ICHAC97Controller *controller,
                    ICHAC97UInt32 pollCount)
{
    ICHAC97UInt32 control;
    ICHAC97UInt32 index;
    if (controller == 0 || controller->io.read32 == 0 ||
        controller->io.write32 == 0)
        return kICHAC97InvalidArgument;
    control = controller->io.read32(controller->io.context,
                                    controller->nabmbar + ICHAC97_REG_GLOB_CNT);
    controller->io.write32(controller->io.context,
                           controller->nabmbar + ICHAC97_REG_GLOB_CNT,
                           control & ~ICHAC97_GLOB_CNT_COLD);
    if (controller->io.delayUS != 0)
        controller->io.delayUS(controller->io.context, 1000U);
    controller->io.write32(controller->io.context,
                           controller->nabmbar + ICHAC97_REG_GLOB_CNT,
                           control | ICHAC97_GLOB_CNT_COLD);
    for (index = 0; index < pollCount; index++) {
        if ((controller->io.read32(controller->io.context,
             controller->nabmbar + ICHAC97_REG_GLOB_STA) &
             ICHAC97_GLOB_STA_PCR) != 0U)
            return kICHAC97Success;
        if (controller->io.delayUS != 0)
            controller->io.delayUS(controller->io.context, 1000U);
    }
    return kICHAC97Timeout;
}
```

- [ ] **Step 4: Run all controller tests**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: all BDL and reset tests pass with `Intel AC97 checks passed`.

- [ ] **Step 5: Commit bounded reset behavior**

```powershell
git add -- $LinkRoot/ICHAC97Controller.c $DriverRoot/tests/intel_ac97_test.c
git commit -m "drvIntelAC97Sound: bound ICH and codec-link resets"
```

### Task 3: Implement independent DMA engines and shared IRQ service

**Files:**
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/tests/intel_ac97_test.c`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ICHAC97Controller.c`

- [ ] **Step 1: Add failing start, stop, and duplex interrupt tests**

Add this complete test and call it from `main`:

```c
static void test_dma_engines_and_irq_are_independent(void)
{
    FakeIO fake;
    ICHAC97Controller controller;
    ICHAC97BufferDescriptor inputBDL[32];
    ICHAC97BufferDescriptor outputBDL[32];
    unsigned int service;

    memset(&fake, 0, sizeof(fake));
    fake.resetReadsBeforeClear = 0U;
    controller = fake_controller(&fake);
    CHECK(ICHAC97PrepareBDL(
        &controller.channel[kICHAC97PCMInput], inputBDL, 0x3000U,
        0x110000U, 0x310000U, 32768U, 4096U) == kICHAC97Success);
    CHECK(ICHAC97PrepareBDL(
        &controller.channel[kICHAC97PCMOutput], outputBDL, 0x4000U,
        0x120000U, 0x320000U, 32768U, 4096U) == kICHAC97Success);

    CHECK(ICHAC97StartChannel(&controller, kICHAC97PCMOutput) ==
          kICHAC97Success);
    CHECK(fake_read32(&fake, 0x10U) == 0x4000U);
    CHECK(fake.regs[0x15U] == 7U);
    CHECK((fake.regs[0x1bU] & 0x19U) == 0x19U);
    CHECK(controller.channel[kICHAC97PCMOutput].running == 1U);

    CHECK(ICHAC97StartChannel(&controller, kICHAC97PCMInput) ==
          kICHAC97Success);
    ICHAC97StopChannel(&controller, kICHAC97PCMOutput);
    CHECK(controller.channel[kICHAC97PCMOutput].running == 0U);
    CHECK(controller.channel[kICHAC97PCMInput].running == 1U);
    CHECK((fake.regs[0x0bU] & 0x01U) != 0U);

    fake.regs[0x30U] = 0x60U;
    fake.regs[0x06U] = 0x08U;
    fake.regs[0x16U] = 0x18U;
    service = ICHAC97ServiceInterrupt(&controller);
    CHECK(service == (kICHAC97ServiceInput |
                      kICHAC97ServiceOutput |
                      kICHAC97ServiceOutputFIFOError));
    CHECK(controller.channel[kICHAC97PCMInput].completions == 1U);
    CHECK(controller.channel[kICHAC97PCMInput].fifoErrors == 0U);
    CHECK(controller.channel[kICHAC97PCMOutput].completions == 1U);
    CHECK(controller.channel[kICHAC97PCMOutput].fifoErrors == 1U);
    CHECK(fake.regs[0x06U] == 0x08U);
    CHECK(fake.regs[0x16U] == 0x18U);
    CHECK(ICHAC97ConsumeService(&controller) == service);
    CHECK(ICHAC97ConsumeService(&controller) == 0U);
}
```

- [ ] **Step 2: Run the tests and confirm the runtime stubs fail**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: start/stop/interrupt assertions fail.

- [ ] **Step 3: Implement DMA programming with per-channel state**

Use the register block base from Task 2. Start must require a prepared BDL,
reset the chosen engine, program BDBAR and LVI, clear only W1C causes, and set
`RPBM | FEIE | IOCE`:

```c
#define ICHAC97_REG_BDBAR 0x00U
#define ICHAC97_REG_LVI 0x05U
#define ICHAC97_REG_SR 0x06U
#define ICHAC97_REG_CR 0x0bU
#define ICHAC97_CR_RPBM 0x01U
#define ICHAC97_CR_FEIE 0x08U
#define ICHAC97_CR_IOCE 0x10U
#define ICHAC97_SR_LVBCI 0x04U
#define ICHAC97_SR_BCIS 0x08U
#define ICHAC97_SR_FIFOE 0x10U
#define ICHAC97_SR_W1C 0x1cU

int ICHAC97StartChannel(ICHAC97Controller *controller,
                       ICHAC97Channel channel)
{
    ICHAC97ChannelState *state;
    ICHAC97UInt32 base;
    ICHAC97UInt16 status;
    int result;
    if (controller == 0 || channel >= kICHAC97ChannelCount)
        return kICHAC97InvalidArgument;
    state = &controller->channel[channel];
    if (state->bdl == 0 || state->descriptorCount == 0U)
        return kICHAC97NotPrepared;
    result = ICHAC97ResetChannel(controller, channel, 100U);
    if (result != kICHAC97Success)
        return result;
    base = controller->nabmbar + channel_base(channel);
    controller->io.write32(controller->io.context,
                           base + ICHAC97_REG_BDBAR,
                           state->bdlPhysical);
    controller->io.write8(controller->io.context,
                          base + ICHAC97_REG_LVI,
                          (ICHAC97UInt8)(state->descriptorCount - 1U));
    status = controller->io.read16(controller->io.context,
                                   base + ICHAC97_REG_SR);
    controller->io.write16(controller->io.context,
                           base + ICHAC97_REG_SR,
                           (ICHAC97UInt16)(status & ICHAC97_SR_W1C));
    controller->io.write8(controller->io.context,
                          base + ICHAC97_REG_CR,
                          ICHAC97_CR_RPBM | ICHAC97_CR_FEIE |
                          ICHAC97_CR_IOCE);
    state->running = 1U;
    return kICHAC97Success;
}

void ICHAC97StopChannel(ICHAC97Controller *controller,
                       ICHAC97Channel channel)
{
    ICHAC97UInt32 base;
    ICHAC97UInt16 status;
    if (controller == 0 || channel >= kICHAC97ChannelCount)
        return;
    base = controller->nabmbar + channel_base(channel);
    controller->io.write8(controller->io.context,
                          base + ICHAC97_REG_CR, 0U);
    status = controller->io.read16(controller->io.context,
                                   base + ICHAC97_REG_SR);
    controller->io.write16(controller->io.context,
                           base + ICHAC97_REG_SR,
                           (ICHAC97UInt16)(status & ICHAC97_SR_W1C));
    controller->channel[channel].running = 0U;
}
```

- [ ] **Step 4: Implement shared IRQ decoding and one-shot service consumption**

Map global input/output bits to their respective blocks with this exact helper
and public functions:

```c
#define ICHAC97_GLOB_STA_PIINT 0x00000020U
#define ICHAC97_GLOB_STA_POINT 0x00000040U

static ICHAC97UInt32 service_channel(ICHAC97Controller *controller,
                                    ICHAC97Channel channel)
{
    ICHAC97UInt32 base = controller->nabmbar + channel_base(channel);
    ICHAC97UInt16 status = controller->io.read16(
        controller->io.context, base + ICHAC97_REG_SR);
    ICHAC97UInt16 ack = (ICHAC97UInt16)(status & ICHAC97_SR_W1C);
    ICHAC97UInt32 service = 0U;
    ICHAC97ChannelState *state = &controller->channel[channel];
    if (ack != 0U)
        controller->io.write16(controller->io.context,
                               base + ICHAC97_REG_SR, ack);
    if ((status & ICHAC97_SR_BCIS) != 0U)
        state->completions++;
    if ((status & ICHAC97_SR_FIFOE) != 0U) {
        state->fifoErrors++;
        service |= channel == kICHAC97PCMInput ?
            kICHAC97ServiceInputFIFOError :
            kICHAC97ServiceOutputFIFOError;
    }
    if ((status & (ICHAC97_SR_BCIS | ICHAC97_SR_LVBCI)) != 0U)
        service |= channel == kICHAC97PCMInput ?
            kICHAC97ServiceInput : kICHAC97ServiceOutput;
    return service;
}

ICHAC97UInt32 ICHAC97ServiceInterrupt(ICHAC97Controller *controller)
{
    ICHAC97UInt32 globalStatus;
    ICHAC97UInt32 service = 0U;
    if (controller == 0)
        return 0U;
    globalStatus = controller->io.read32(
        controller->io.context,
        controller->nabmbar + ICHAC97_REG_GLOB_STA);
    if ((globalStatus & ICHAC97_GLOB_STA_PIINT) != 0U)
        service |= service_channel(controller, kICHAC97PCMInput);
    if ((globalStatus & ICHAC97_GLOB_STA_POINT) != 0U)
        service |= service_channel(controller, kICHAC97PCMOutput);
    controller->pendingService |= service;
    return service;
}

ICHAC97UInt32 ICHAC97ConsumeService(ICHAC97Controller *controller)
{
    ICHAC97UInt32 service;
    if (controller == 0)
        return 0U;
    service = controller->pendingService;
    controller->pendingService = 0U;
    return service;
}
```

Also implement codec access as direct NAMBAR 16-bit operations:

```c
ICHAC97UInt16 ICHAC97CodecRead(ICHAC97Controller *controller,
                              ICHAC97UInt8 reg)
{
    return controller->io.read16(controller->io.context,
                                 controller->nambar + reg);
}

void ICHAC97CodecWrite(ICHAC97Controller *controller,
                      ICHAC97UInt8 reg,
                      ICHAC97UInt16 value)
{
    controller->io.write16(controller->io.context,
                           controller->nambar + reg, value);
}
```

- [ ] **Step 5: Run the full controller suite**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: BDL, reset, independent stop, simultaneous IRQ, FIFO, and consume
tests all pass.

- [ ] **Step 6: Commit DMA and interrupt behavior**

```powershell
git add -- $LinkRoot/ICHAC97Controller.c $DriverRoot/tests/intel_ac97_test.c
git commit -m "drvIntelAC97Sound: isolate duplex DMA interrupt state"
```

### Task 4: Convert the codec helper to hostable C with verified readback

**Files:**
- Rename: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ac97.m` to `ac97.c`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ac97var.h`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/ac97reg.h`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/tests/Makefile.host`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/tests/intel_ac97_test.c`

- [ ] **Step 1: Rename the source and add failing codec tests**

```powershell
git mv -- $LinkRoot/ac97.m $LinkRoot/ac97.c
```

Replace the `intel_ac97_test` rule with this permanent codec-aware rule, then
add the fake codec and test below and call the test from `main`:

```make
intel_ac97_test: intel_ac97_test.c \
        $(LINKROOT)/ICHAC97Controller.c \
        $(LINKROOT)/ICHAC97Controller.h \
        $(LINKROOT)/ac97.c \
        $(LINKROOT)/ac97var.h \
        $(LINKROOT)/ac97reg.h
	$(CC) $(CFLAGS) -I$(LINKROOT) -o $@ \
		intel_ac97_test.c \
		$(LINKROOT)/ICHAC97Controller.c \
		$(LINKROOT)/ac97.c
```

```c
#include "ac97var.h"

typedef struct {
    unsigned short regs[64];
    unsigned int delays;
    int rejectVRA;
    int rejectRate;
} FakeCodec;

static unsigned short fake_codec_read(void *context, unsigned char reg)
{
    FakeCodec *fake = (FakeCodec *)context;
    return fake->regs[reg >> 1];
}

static void fake_codec_write(void *context, unsigned char reg,
                             unsigned short value)
{
    FakeCodec *fake = (FakeCodec *)context;
    if (reg == AC97_REG_EXT_AUDIO_CTRL && fake->rejectVRA)
        return;
    if ((reg == AC97_REG_PCM_FRONT_DAC_RATE ||
         reg == AC97_REG_PCM_LR_ADC_RATE) && fake->rejectRate)
        return;
    fake->regs[reg >> 1] = value;
}

static void fake_codec_delay(void *context, unsigned int microseconds)
{
    FakeCodec *fake = (FakeCodec *)context;
    (void)microseconds;
    fake->delays++;
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

static void test_codec_vra_rates_and_gain_are_verified(void)
{
    struct ac97_codec_state codec;
    FakeCodec fake;

    memset(&fake, 0, sizeof(fake));
    fake.regs[AC97_REG_POWERDOWN >> 1] =
        AC97_PWR_REF | AC97_PWR_ANL | AC97_PWR_DAC;
    fake.regs[AC97_REG_VENDOR_ID1 >> 1] = 0x8384U;
    fake.regs[AC97_REG_VENDOR_ID2 >> 1] = 0x7600U;
    fake.regs[AC97_REG_EXT_AUDIO_ID >> 1] = AC97_EXT_AUDIO_VRA;
    init_fake_codec(&codec, &fake);
    CHECK(ac97_attach(&codec, AC97_CODEC_TYPE_AUDIO) == 0);
    CHECK(codec.vendor_id == 0x83847600U);
    CHECK(strcmp(codec.vendor_name, "SigmaTel") == 0);
    CHECK(codec.vra_enabled == 1U);
    CHECK(ac97_set_rate(&codec, AC97_RATE_DAC, 44100U) == 0);
    CHECK(codec.dac_rate == 44100U);
    fake.rejectRate = 1;
    CHECK(ac97_set_rate(&codec, AC97_RATE_ADC, 32000U) == -1);
    CHECK(codec.adc_rate == 48000U);
    ac97_set_record_gain(&codec, 20U, 7U, 1);
    CHECK(fake.regs[AC97_REG_RECORD_GAIN >> 1] == 0x8f07U);
    ac97_set_master_volume(&codec, 40U, 50U, 0);
    CHECK(fake.regs[AC97_REG_MASTER_VOLUME >> 1] == 0x1f1fU);

    memset(&fake, 0, sizeof(fake));
    fake.regs[AC97_REG_POWERDOWN >> 1] =
        AC97_PWR_REF | AC97_PWR_ANL | AC97_PWR_DAC;
    fake.regs[AC97_REG_EXT_AUDIO_ID >> 1] = AC97_EXT_AUDIO_VRA;
    fake.rejectVRA = 1;
    init_fake_codec(&codec, &fake);
    CHECK(ac97_attach(&codec, AC97_CODEC_TYPE_AUDIO) == 0);
    CHECK(codec.vra_enabled == 0U);
    CHECK(ac97_set_rate(&codec, AC97_RATE_DAC, 44100U) == -1);
    CHECK(ac97_set_rate(&codec, AC97_RATE_DAC, 48000U) == 0);

    memset(&fake, 0, sizeof(fake));
    init_fake_codec(&codec, &fake);
    CHECK(ac97_reset(&codec) == -1);
    CHECK(fake.delays == 101U);
}
```

- [ ] **Step 2: Run the tests and confirm DriverKit imports or old signatures fail**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all
```

Expected: compilation fails on DriverKit headers, `IODelay`, `IOLog`, or the
old codec signatures.

- [ ] **Step 3: Remove kernel dependencies and make reset return status**

Replace DriverKit imports with standard C headers:

```c
#include <stdio.h>
#include <string.h>
#include "ac97var.h"
#include "ac97reg.h"
```

Add `delay_us` and `delay_context` fields from the fixed interface. Route all
delays through this helper:

```c
static void ac97_delay(struct ac97_codec_state *codec,
                       unsigned int microseconds)
{
    if (codec->delay_us != 0)
        codec->delay_us(codec->delay_context, microseconds);
}
```

Change `ac97_wait_ready` to call `ac97_delay(codec, 1000U)`. Change
`ac97_reset` to return `-1` on invalid state or timeout and `0` after the cache
has been populated. Make `ac97_attach` stop and return `-1` if reset fails.
Remove normal-path `IOLog` calls; the adapter logs the populated vendor and
codec names after successful attach.

- [ ] **Step 4: Require VRA and sample-rate readback**

After setting `AC97_EXT_CTRL_VRA`, read `AC97_REG_EXT_AUDIO_CTRL` again and set
`vra_enabled` only if the bit remains set. In `ac97_set_rate`, reject values
outside 8000–48000, reject non-48-kHz values when VRA is disabled, write the
selected register, and update the cached DAC/ADC rate only when the register
reads back exactly.

Change `AC97_RATE_MIN` in `ac97reg.h` from `4000` to `8000`.

- [ ] **Step 5: Implement mute-preserving record gain**

Use the fixed signature and exact packing:

```c
void ac97_set_record_gain(struct ac97_codec_state *codec,
                          unsigned char left,
                          unsigned char right,
                          int mute)
{
    unsigned short value;
    if (codec == 0)
        return;
    if (left > 15U)
        left = 15U;
    if (right > 15U)
        right = 15U;
    value = (unsigned short)(((unsigned short)left << 8) | right);
    if (mute)
        value |= AC97_MUTE;
    ac97_write(codec, AC97_REG_RECORD_GAIN, value);
}
```

Update both call sites to pass an explicit mute value.

- [ ] **Step 6: Run the controller and codec suite**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: `Intel AC97 checks passed`, with no C89 warnings.

- [ ] **Step 7: Commit the hostable codec core**

```powershell
git add -A -- $LinkRoot/ac97.m $LinkRoot/ac97.c $LinkRoot/ac97var.h $LinkRoot/ac97reg.h $DriverRoot/tests/Makefile.host $DriverRoot/tests/intel_ac97_test.c
git commit -m "drvIntelAC97Sound: make codec setup host testable"
```

### Task 5: Give the DriverKit adapter explicit ownership and staged cleanup

**Files:**
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/tests/driver_contract_test.py`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/tests/Makefile.host`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/IntelAC97Driver.h`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/IntelAC97Driver.m`

- [ ] **Step 1: Add failing adapter ownership contract tests**

Create a Python `unittest` that reads the adapter and asserts:

```python
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
LINK = ROOT / "IntelAC97.drvproj" / "IntelAC97.lksproj"


class DriverContractTests(unittest.TestCase):
    def test_adapter_owns_state_and_core_owns_registers(self):
        header = (LINK / "IntelAC97Driver.h").read_text(encoding="utf-8")
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        self.assertIn("struct ich97_driver_state *state;", header)
        self.assertNotIn("static struct ich_state     *s", source)
        self.assertNotIn("#define ICH_REG_", source)
        self.assertIn("ICHAC97Controller controller;", source)
        self.assertIn("static struct ich97_driver_state *activeInterruptState", source)

    def test_cleanup_tracks_each_acquired_resource(self):
        source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
        for token in (
            "ioAudioInitialized", "interruptRegistered",
            "mixerRangeRegistered", "busMasterRangeRegistered",
            "codecAttached", "ich97_release_state"):
            self.assertIn(token, source)


if __name__ == "__main__":
    unittest.main()
```

Replace the `check` rule with:

```make
check: all
	./intel_ac97_test
	python3 driver_contract_test.py
```

- [ ] **Step 2: Run the contract test and verify it fails on global state**

```powershell
python $DriverRoot/tests/driver_contract_test.py
```

Expected: failures for the missing ivar, controller, and cleanup flags.

- [ ] **Step 3: Add the opaque state ivar and kernel I/O adapters**

Forward-declare `struct ich97_driver_state` before the interface and add its
pointer as the only new ivar. In the implementation define:

```objc
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
};

static struct ich97_driver_state *activeInterruptState;

static unsigned char kernel_read8(void *context, unsigned int port)
{
    (void)context;
    return inb(port);
}

static unsigned short kernel_read16(void *context, unsigned int port)
{
    (void)context;
    return inw(port);
}

static unsigned int kernel_read32(void *context, unsigned int port)
{
    (void)context;
    return inl(port);
}

static void kernel_write8(void *context, unsigned int port,
                          unsigned char value)
{
    (void)context;
    outb(value, port);
}

static void kernel_write16(void *context, unsigned int port,
                           unsigned short value)
{
    (void)context;
    outw(value, port);
}

static void kernel_write32(void *context, unsigned int port,
                           unsigned int value)
{
    (void)context;
    outl(value, port);
}

static void kernel_delay(void *context, unsigned int microseconds)
{
    (void)context;
    IODelay(microseconds);
}
```

- [ ] **Step 4: Replace BAR scanning with exact BAR0/BAR1 validation**

Require `BaseAddress[0]` and `[1]` to be I/O BARs, decode BAR0 as NAMBAR and
BAR1 as NABMBAR, reject zero decoded addresses, and initialize the controller
with the kernel callback table before calling `[super
initFromDeviceDescription:]`. Keep the existing Intel device-ID switch and
log the untested IDs as compatible matches rather than claiming verification.

Set each acquisition flag immediately after the corresponding DriverKit call
succeeds. Reject a second `activeInterruptState`, then install
`activeInterruptState = state` immediately before calling the superclass:

```objc
if (activeInterruptState != 0) {
    IOLog("%s: only one active controller is supported\n", DRV_TITLE);
    [self ich97_release_state];
    return nil;
}
activeInterruptState = state;
if (![super initFromDeviceDescription:deviceDescription]) {
    [self ich97_release_state];
    return nil;
}
state->ioAudioInitialized = YES;
```

The bridge must exist before the superclass call because `IOAudio` invokes
`[self reset]` and installs the interrupt handler inside its initializer. The
cleanup method clears the bridge if superclass initialization fails.

- [ ] **Step 5: Add one idempotent cleanup helper and route every failure to it**

Add this idempotent private method. Each initialization failure logs one reason,
calls it, and returns `nil`; normal `-free` calls it and then `[super free]`.

```objc
- (void)ich97_release_state
{
    struct ich97_driver_state *owned = state;
    unsigned int index;
    if (owned == 0)
        return;
    ICHAC97StopChannel(&owned->controller, kICHAC97PCMInput);
    ICHAC97StopChannel(&owned->controller, kICHAC97PCMOutput);
    if (activeInterruptState == owned)
        activeInterruptState = 0;
    if (owned->interruptRegistered)
        [self releaseInterrupt:0];
    if (owned->mixerRangeRegistered)
        [self releasePortRange:0];
    if (owned->busMasterRangeRegistered)
        [self releasePortRange:1];
    for (index = 0; index < kICHAC97ChannelCount; index++) {
        if (owned->controller.channel[index].bdl != 0)
            IOFree(owned->controller.channel[index].bdl,
                   sizeof(ICHAC97BufferDescriptor) * 32U);
    }
    if (owned->lock != 0)
        simple_lock_free(owned->lock);
    state = 0;
    IOFree(owned, sizeof(*owned));
}
```

Do not call codec power-down during partial initialization. A normal successful
shutdown may call `ac97_power_down` before this helper only when
`codecAttached` is true.

- [ ] **Step 6: Run contract and C tests**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: C tests and both adapter ownership tests pass.

- [ ] **Step 7: Commit instance ownership and staged cleanup**

```powershell
git add -- $LinkRoot/IntelAC97Driver.h $LinkRoot/IntelAC97Driver.m $DriverRoot/tests/driver_contract_test.py $DriverRoot/tests/Makefile.host
git commit -m "drvIntelAC97Sound: own controller resources per instance"
```

### Task 6: Bind DriverKit DMA buffers to tested BDL construction

**Files:**
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/tests/driver_contract_test.py`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/IntelAC97Driver.m`

- [ ] **Step 1: Add failing source-contract checks for deferred BDL construction**

Assert that `createDMABufferFor:` calls `IOPhysicalFromVirtual`, stores
`bufferVirtual`, `bufferPhysical`, and `bufferBytes`, but does not call
`ICHAC97PrepareBDL`. Assert that `startDMAForChannel:` calls
`ICHAC97PrepareBDL` with `bufferSizeForInterrupts` and then
`ICHAC97StartChannel`.

Add this method to `DriverContractTests`:

```python
def test_bdl_is_built_only_after_ioaudio_supplies_service_size(self):
    source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
    create_start = source.index("createDMABufferFor:")
    start_start = source.index("startDMAForChannel:")
    stop_start = source.index("stopDMAForChannel:")
    create_body = source[create_start:start_start]
    start_body = source[start_start:stop_start]
    self.assertIn("IOPhysicalFromVirtual", create_body)
    self.assertIn("bufferVirtual", create_body)
    self.assertIn("bufferPhysical", create_body)
    self.assertIn("bufferBytes", create_body)
    self.assertNotIn("ICHAC97PrepareBDL", create_body)
    self.assertIn("bufferSizeForInterrupts", start_body)
    self.assertIn("ICHAC97PrepareBDL", start_body)
    self.assertIn("ICHAC97StartChannel", start_body)
```

- [ ] **Step 2: Run the contract test and verify the old 32-way split fails**

```powershell
python $DriverRoot/tests/driver_contract_test.py
```

Expected: failure because `createDMABufferFor:` still computes
`numBytes / ICH_BD_COUNT` and builds descriptors early.

- [ ] **Step 3: Make buffer creation map and remember, not partition**

For the selected direction, map `*physicalAddress` with
`IOPhysicalFromVirtual`, store the original virtual address, physical address,
and byte count in the core channel state, allocate and zero one 32-entry BDL,
map the BDL physical address, and return the sample-buffer physical address as
the `IOEISADMABuffer` handle. On any mapping or allocation failure, free only
the just-created BDL and clear that channel's stored fields.

- [ ] **Step 4: Build the ring when `IOAudio` supplies its service size**

Map `isRead` to `kICHAC97PCMInput` and output otherwise. Reject a buffer handle
that differs from the stored physical address. Call `ICHAC97PrepareBDL` with
the stored virtual/physical/total byte values and the passed
`bufferSizeForInterrupts`. Update the applicable DAC or ADC rate only after BDL
validation succeeds, then call `ICHAC97StartChannel`. Return `NO` for either
failure and leave the engine stopped.

`stopDMAForChannel:` calls only `ICHAC97StopChannel` for the selected direction;
it calls `[self disableAllInterrupts]` only when both core channel `running`
fields are zero.

After a successful `ICHAC97StartChannel`, call `[self enableAllInterrupts]`
before returning `YES`. This call is intentionally idempotent when the opposite
direction is already running.

- [ ] **Step 5: Run all host checks**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: all C and source-contract checks pass.

- [ ] **Step 6: Commit the DriverKit DMA binding**

```powershell
git add -- $LinkRoot/IntelAC97Driver.m $DriverRoot/tests/driver_contract_test.py
git commit -m "drvIntelAC97Sound: match DMA rings to IOAudio cadence"
```

### Task 7: Bind the context-free interrupt bridge without losing duplex causes

**Files:**
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/tests/driver_contract_test.py`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/IntelAC97Driver.m`

- [ ] **Step 1: Add failing interrupt-bridge contract checks**

Require `clearInterrupts(void)` and the custom hardware handler to call
`ICHAC97ServiceInterrupt(&activeInterruptState->controller)`. Require
`interruptOccurredForInput:forOutput:` to call `ICHAC97ConsumeService`, assign
both booleans from the returned input/output bits, and not derive either value
from a `running` flag. Require the custom handler to call the saved superclass
handler only when service flags are nonzero.

Add this method:

```python
def test_interrupt_bridge_latches_and_consumes_both_directions(self):
    source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
    self.assertGreaterEqual(source.count("ICHAC97ServiceInterrupt("), 2)
    self.assertIn("ICHAC97ConsumeService(&state->controller)", source)
    self.assertIn("kICHAC97ServiceInput", source)
    self.assertIn("kICHAC97ServiceOutput", source)
    interrupt_start = source.index("interruptOccurredForInput:")
    handler_start = source.index("getHandler:")
    interrupt_body = source[interrupt_start:handler_start]
    self.assertNotIn(".running", interrupt_body)
    self.assertNotIn("->running", interrupt_body)
    self.assertIn("*serviceInput", interrupt_body)
    self.assertIn("*serviceOutput", interrupt_body)
    self.assertIn("if (service != 0U && activeInterruptState->oldHandler != 0)",
                  source)
```

- [ ] **Step 2: Run the contract test and verify the old output-only path fails**

```powershell
python $DriverRoot/tests/driver_contract_test.py
```

Expected: failure because input is hard-coded to `NO` and output follows
`out_running`.

- [ ] **Step 3: Implement the narrow active-instance bridge**

Use the bridge installed immediately before superclass initialization in Task
5. Both raw acknowledgement entry points take `state->lock`, call
`ICHAC97ServiceInterrupt`, and release the lock. The custom handler invokes
`oldHandler` once if any input/output service bit was newly latched, then
re-enables the interrupt. FIFO flags are logged on the first occurrence and
each 256th occurrence using the monotonically increasing per-channel counters.

- [ ] **Step 4: Consume both directions atomically under the driver lock**

In `interruptOccurredForInput:forOutput:`, take the state lock, consume the
latched service mask, release the lock, and set:

```objc
*serviceInput = (service & kICHAC97ServiceInput) != 0U;
*serviceOutput = (service & kICHAC97ServiceOutput) != 0U;
```

Never clear a pending direction before it has been reflected in these outputs.

- [ ] **Step 5: Run host checks**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: core duplex IRQ tests and adapter bridge checks pass.

- [ ] **Step 6: Commit duplex interrupt integration**

```powershell
git add -- $LinkRoot/IntelAC97Driver.m $DriverRoot/tests/driver_contract_test.py
git commit -m "drvIntelAC97Sound: preserve duplex interrupt service"
```

### Task 8: Complete codec initialization, rates, attenuation, and input gain

**Files:**
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/tests/driver_contract_test.py`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/IntelAC97Driver.h`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/IntelAC97Driver.m`

- [ ] **Step 1: Add failing adapter-control contract tests**

Require reset to call both core channel resets, `ICHAC97ResetLink`, and
`ac97_attach`, and to return `NO` on any failure. Require continuous rates only
when `codec.vra_enabled` is true, fixed-rate enumeration to expose only 48000,
`updateSampleRate` to program DAC and ADC independently, both input-gain
methods to call one shared record-gain helper, and `setInput:enable:` to map
line and microphone tags to AC97 record-select values.

Add this method:

```python
def test_reset_rates_and_controls_bind_the_tested_cores(self):
    header = (LINK / "IntelAC97Driver.h").read_text(encoding="utf-8")
    source = (LINK / "IntelAC97Driver.m").read_text(encoding="utf-8")
    self.assertIn("setInput:(NXSoundParameterTag)ptag enable:(BOOL)enable", header)
    self.assertGreaterEqual(source.count("ICHAC97ResetChannel("), 2)
    self.assertIn("ICHAC97ResetLink(", source)
    self.assertIn("ac97_attach(&state->codec", source)
    self.assertIn("state->codec.vra_enabled", source)
    self.assertIn("rates[0] = 48000", source)
    self.assertIn("ac97_set_rate(&state->codec, AC97_RATE_DAC", source)
    self.assertIn("ac97_set_rate(&state->codec, AC97_RATE_ADC", source)
    self.assertGreaterEqual(source.count("update_record_gain"), 3)
    self.assertIn("NX_SoundDeviceLineIn", source)
    self.assertIn("NX_SoundDeviceMicIn", source)
    self.assertIn("AC97_RECMUX_LINE", source)
    self.assertIn("AC97_RECMUX_MIC", source)
```

- [ ] **Step 2: Run the contract tests and verify incomplete controls fail**

```powershell
python $DriverRoot/tests/driver_contract_test.py
```

Expected: failures for empty input-gain methods and unconditional rate ranges.

- [ ] **Step 3: Bind codec callbacks and make reset fail closed**

Provide codec callbacks that call `ICHAC97CodecRead` and
`ICHAC97CodecWrite`, and bind codec delay to `kernel_delay`. During reset,
reset both PCM engines with bounded polling, reset the link, initialize the
codec state, and call `ac97_attach`. Log the identified vendor/name only after
attach succeeds. Set `codecAttached` at that point. A timeout or codec failure
returns `NO` with both engines stopped.

- [ ] **Step 4: Expose accurate sample-rate capabilities**

When VRA is disabled, `acceptsContinuousSamplingRates` returns `NO`,
`getSamplingRates:count:` writes one entry `48000`, and
`getSamplingRatesLow:high:` writes `48000` to both. With VRA enabled, expose
8000–48000 and the existing seven conventional values. `updateSampleRate`
programs both DAC and ADC and logs a rejected readback without changing the
codec caches.

- [ ] **Step 5: Clamp output attenuation and implement stereo record gain**

Convert Rhapsody output attenuation `0..13` to AC97 `0..31` with explicit
clamping before the multiply. Convert each input gain `0..32768` to AC97
`0..15` with:

```c
static unsigned char input_gain_to_ac97(unsigned int gain)
{
    if (gain >= 32768U)
        return 15U;
    return (unsigned char)((gain * 15U) / 32768U);
}
```

Both left and right update methods call a shared helper that reads both current
`IOAudio` gains and writes one record-gain register value. Implement
`setInput:enable:` so enabling line or microphone selects that source; disabling
the currently selected source leaves a stable selection because QEMU ignores
the mux for PCM input.

- [ ] **Step 6: Run all host checks**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: controller, codec, ownership, DMA, IRQ, rate, and control checks pass.

- [ ] **Step 7: Commit completed audio controls**

```powershell
git add -- $LinkRoot/IntelAC97Driver.h $LinkRoot/IntelAC97Driver.m $DriverRoot/tests/driver_contract_test.py
git commit -m "drvIntelAC97Sound: finish QEMU codec controls"
```

### Task 9: Wire the historical build and verify the native driver

**Files:**
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/tests/driver_contract_test.py`
- Modify: `src/drivers-i386/sound/drvIntelAC97Sound/IntelAC97.drvproj/IntelAC97.lksproj/Makefile`

- [ ] **Step 1: Add a failing makefile boundary test**

Assert the makefile contains exactly:

```make
CLASSES = IntelAC97Driver.m

CFILES = ac97.c ICHAC97Controller.c

HFILES = ac97reg.h ac97var.h ICHAC97Controller.h IntelAC97Driver.h
```

Also assert `ac97.m` does not exist and both C files contain no `@interface`,
`@implementation`, or DriverKit imports.

Add this method:

```python
def test_project_builder_compiles_only_adapter_as_objective_c(self):
    makefile = (LINK / "Makefile").read_text(encoding="utf-8")
    self.assertIn("CLASSES = IntelAC97Driver.m", makefile)
    self.assertIn("CFILES = ac97.c ICHAC97Controller.c", makefile)
    self.assertIn(
        "HFILES = ac97reg.h ac97var.h ICHAC97Controller.h IntelAC97Driver.h",
        makefile)
    self.assertFalse((LINK / "ac97.m").exists())
    for name in ("ac97.c", "ICHAC97Controller.c"):
        source = (LINK / name).read_text(encoding="utf-8")
        self.assertNotIn("@interface", source)
        self.assertNotIn("@implementation", source)
        self.assertNotIn("<driverkit/", source)
```

- [ ] **Step 2: Run the contract test and verify the generated makefile is stale**

```powershell
python $DriverRoot/tests/driver_contract_test.py
```

Expected: failure because `CLASSES` still names `ac97.m`.

- [ ] **Step 3: Update the link-project source lists**

Apply the exact `CLASSES`, `CFILES`, and `HFILES` assignments above. Do not
modify other generated Project Builder settings.

- [ ] **Step 4: Run host tests before the guest build**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
```

Expected: all host checks pass.

- [ ] **Step 5: Sync and build in the Rhapsody build guest**

```powershell
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/sound/drvIntelAC97Sound && gnumake clean all"
```

Expected: the link project compiles `ac97.c`, `ICHAC97Controller.c`, and
`IntelAC97Driver.m`, links `IntelAC97_reloc`, and emits no implicit-declaration,
pointer-width, or packed-layout warnings from the changed files.

- [ ] **Step 6: Inspect the linked symbols**

```powershell
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/sound/drvIntelAC97Sound && find . -name 'IntelAC97_reloc' -exec nm -g {} \;"
```

Expected: exported Objective-C class symbols plus the referenced
`ICHAC97*` and `ac97_*` functions, with no unresolved symbols other than the
normal kernel/DriverKit imports.

- [ ] **Step 7: Commit build integration**

```powershell
git add -- $LinkRoot/Makefile $DriverRoot/tests/driver_contract_test.py
git commit -m "drvIntelAC97Sound: build split controller and codec cores"
```

### Task 10: Add opt-in QEMU AC97 launch coverage and operator documentation

**Files:**
- Modify: `vm/test_ahci_scripts.py`
- Modify: `vm/run-q35-ahci.sh`
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/README.md`
- Create: `src/drivers-i386/sound/drvIntelAC97Sound/SOURCES.md`

- [ ] **Step 1: Add a failing AC97 dry-run test**

Add this method to `AHCIScriptTests`:

```python
def test_launcher_adds_ac97_only_when_requested(self):
    work_dir = VM / "work" / "script-test-ac97"
    shutil.rmtree(work_dir, ignore_errors=True)
    work_dir.mkdir(parents=True)
    self.addCleanup(lambda: shutil.rmtree(work_dir, ignore_errors=True))
    source = work_dir / "source.img"
    target = work_dir / "boot.img"
    source.write_bytes(b"test")

    enabled = self.run_sh(
        RUN, "--dry-run", "--ac97", "dsound",
        self.sh_path(source), self.sh_path(target))
    self.assertEqual(enabled.returncode, 0, enabled.stdout)
    self.assertIn("\n  -audiodev\n  dsound,id=ac97\n", enabled.stdout)
    self.assertIn("\n  -device\n  AC97,audiodev=ac97\n", enabled.stdout)
    self.assertFalse(target.exists())

    disabled = self.run_sh(
        RUN, "--dry-run", self.sh_path(source), self.sh_path(target))
    self.assertEqual(disabled.returncode, 0, disabled.stdout)
    self.assertNotIn("AC97,audiodev=ac97", disabled.stdout)
```

- [ ] **Step 2: Run the launcher test and verify `--ac97` is rejected**

```powershell
python -m unittest vm.test_ahci_scripts.AHCIScriptTests.test_launcher_adds_ac97_only_when_requested -v
```

Expected: FAIL because the launcher prints usage for `--ac97`.

- [ ] **Step 3: Add quoted `--ac97 BACKEND` parsing**

Update usage to include `[--ac97 BACKEND]`. Initialize `ac97_backend=`. Parse:

```sh
--ac97)
    [ $# -ge 2 ] || usage
    ac97_backend=$2
    case "$ac97_backend" in
        none|dbus|dsound|jack|sdl|spice|wav) ;;
        *) die "unsupported QEMU audio backend: $ac97_backend" ;;
    esac
    shift 2
    ;;
```

After optional disks and ISO arguments are appended, add:

```sh
if [ -n "$ac97_backend" ]; then
    set -- "$@" -audiodev "$ac97_backend,id=ac97" \
        -device AC97,audiodev=ac97
fi
```

No AC97 device is added unless the option is present. Keep every backend value
as one quoted QEMU argument.

- [ ] **Step 4: Run the full VM script suite**

```powershell
python -m unittest vm.test_ahci_scripts -v
```

Expected: the new AC97 test and all existing AHCI safety tests pass.

- [ ] **Step 5: Write the driver README with exact verification paths**

Document:

- supported PCI ID `8086:2415`, one primary codec, stereo signed 16-bit PCM;
- host command `make -C tests -f Makefile.host clean all check`;
- native guest command `gnumake clean all` from the driver root;
- Windows launch example:

```powershell
$env:RHAPSODY_SOURCE_IMAGE = 'D:\VMs\rhapsody-source.img'
& 'C:\Users\raynorpat\AppData\Local\Programs\Git\bin\bash.exe' \
  'vm/run-q35-ahci.sh' --ac97 dsound \
  $env:RHAPSODY_SOURCE_IMAGE 'vm/work/rhapsody-ac97.img'
```

- JACK launch uses the same command with `--ac97 jack` and a host JACK graph
  connecting a known tone source to `ac97.pi`;
- guest playback must cross three ring wraps with no FIFO/timeout logs;
- guest capture must contain changing, nonzero samples and play back audibly;
- concurrent capture/playback and independent stop checks;
- DSound microphone capture is the Windows fallback when routable JACK input
  is unavailable.

- [ ] **Step 6: Write the source/provenance note**

Link AppleIntelAC97Driver, AppleAC97Audio, QEMU `hw/audio/ac97.c`, and the AC97
2.3 specification. State that controller/codec/engine separation, bounded
reset sequencing, channel state, and W1C handling were independently adapted
to Rhapsody's API; no IOKit class implementation was copied. Note the local
GPLv2-or-later licensing already present in the driver files.

- [ ] **Step 7: Commit the launcher and documentation**

```powershell
git add -- vm/run-q35-ahci.sh vm/test_ahci_scripts.py $DriverRoot/README.md $DriverRoot/SOURCES.md
git commit -m "drvIntelAC97Sound: document and launch QEMU AC97 tests"
```

### Task 11: Run final native and QEMU acceptance gates

**Files:**
- Modify only if a gate exposes a defect in an in-scope file.

- [ ] **Step 1: Run every host verification from a clean test directory**

```powershell
& make -C $DriverRoot/tests -f Makefile.host clean all check
python -m unittest vm.test_ahci_scripts -v
git diff --check
```

Expected: all tests pass and `git diff --check` prints nothing.

- [ ] **Step 2: Rebuild the driver in the Rhapsody guest**

```powershell
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/sound/drvIntelAC97Sound && gnumake clean all"
```

Expected: clean compile and link.

- [ ] **Step 3: Boot a disposable DSound image and verify probe**

First require a real source image path:

```powershell
if (-not $env:RHAPSODY_SOURCE_IMAGE) { throw 'Set RHAPSODY_SOURCE_IMAGE to the immutable source image' }
& 'C:\Users\raynorpat\AppData\Local\Programs\Git\bin\bash.exe' \
  'vm/run-q35-ahci.sh' --ac97 dsound \
  $env:RHAPSODY_SOURCE_IMAGE 'vm/work/rhapsody-ac97.img'
```

Expected serial log: Intel `8086:2415`, primary codec ready, identified primary
codec, no reset timeout, and no immediate FIFO or `IOAudio` timeout.

- [ ] **Step 4: Exercise playback for at least three ring wraps**

In the guest, play a known signed 16-bit stereo PCM sound for at least two
seconds. Confirm audible output or backend capture. Inspect
`vm/logs/ahci-serial.log`; expected: no DMA FIFO errors, codec errors, or
`Timeout waiting for interrupt` messages.

- [ ] **Step 5: Exercise capture and guest playback of the capture**

Feed a continuous host tone through the selected QEMU input. Record at least
two seconds in the guest, verify the captured buffer contains changing nonzero
samples, then play the saved capture. With DSound, use the configured Windows
input; with JACK, connect the tone source to the QEMU `ac97.pi` input port.

Expected: recognizable captured tone and no input FIFO/timeout log.

- [ ] **Step 6: Exercise full duplex and independent stops**

Run playback and capture concurrently for at least two seconds. Stop playback
while capture continues, restart playback, then stop capture while playback
continues.

Expected: the continuing direction remains active after each stop and neither
direction logs a DMA halt, FIFO error, or `IOAudio` timeout.

- [ ] **Step 7: Review the final scope and history**

```powershell
git status --short
git log --oneline e44103ee..HEAD
git diff --stat e44103ee..HEAD
git diff --check e44103ee..HEAD
```

Expected: only the files named in this plan changed, commits are subsystem
prefixed, no unrelated working-tree files are staged, and the range diff has no
whitespace errors.

- [ ] **Step 8: Commit only a gate-discovered correction, if one was necessary**

When all gates passed without code changes, do not create an empty commit. If
an in-scope correction was required, rerun Steps 1–7 and commit only those
files:

```powershell
git add -- $DriverRoot vm/run-q35-ahci.sh vm/test_ahci_scripts.py
git commit -m "drvIntelAC97Sound: fix QEMU acceptance issue"
```

## Completion criteria

- Host controller and codec tests pass under strict C89 warnings.
- Adapter source-contract tests pass.
- The historical Rhapsody link project builds and links the split C cores.
- The opt-in QEMU dry-run emits a quoted AC97 device and selected audio backend.
- QEMU playback and capture each survive multiple BDL wraps.
- Full-duplex operation and independent stop behavior are demonstrated.
- No secondary codec, S/PDIF, multichannel, modem, non-Intel controller, or
  generalized family code was added.
- Every changed line belongs to the AC97 driver, its tests/docs, or the opt-in
  QEMU launch/test path.
