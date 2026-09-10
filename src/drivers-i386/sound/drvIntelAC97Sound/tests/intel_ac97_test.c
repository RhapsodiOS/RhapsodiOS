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
    test_rr_clears_bdbar_and_start_rewrites_it();
    if (failures != 0) {
        fprintf(stderr, "%d Intel AC97 checks failed\n", failures);
        return 1;
    }
    puts("Intel AC97 checks passed");
    return 0;
}
