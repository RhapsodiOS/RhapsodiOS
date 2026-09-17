#include <stdio.h>
#include <string.h>
#include "ICHAC97Controller.h"
#include "ac97var.h"

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
    unsigned int casBusyReads;
    unsigned int casReads;
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
    if (offset == ICHAC97_REG_CAS &&
        fake->casReads < fake->casBusyReads) {
        fake->casReads++;
        return ICHAC97_CAS_BUSY;
    }
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

    memset(&codec, 0, sizeof(codec));
    memset(&fake, 0, sizeof(fake));
    fake.regs[AC97_REG_POWERDOWN >> 1] =
        AC97_PWR_REF | AC97_PWR_ANL | AC97_PWR_DAC;
    fake.regs[AC97_REG_EXT_AUDIO_ID >> 1] = AC97_EXT_AUDIO_VRA;
    fake.rejectVRA = 1;
    init_fake_codec(&codec, &fake);
    CHECK(ac97_attach(&codec, AC97_CODEC_TYPE_AUDIO) == 0);
    CHECK(codec.vra_enabled == 0);
    CHECK((codec.regs[AC97_REG_EXT_AUDIO_CTRL >> 1] & AC97_EXT_CTRL_VRA) == 0U);
    CHECK(codec.regs[AC97_REG_EXT_AUDIO_CTRL >> 1] ==
          ac97_read(&codec, AC97_REG_EXT_AUDIO_CTRL));
    CHECK(ac97_set_rate(&codec, AC97_RATE_DAC, 44100U) == -1);
    CHECK(ac97_set_rate(&codec, AC97_RATE_DAC, 48000U) == 0);
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
    test_lvi_chase_and_output_irq();
    test_codec_cas_rcs_and_link_reset();
    test_codec_id_vra_volume_and_muted_attach();
    if (failures != 0) {
        fprintf(stderr, "%d Intel AC97 checks failed\n", failures);
        return 1;
    }
    puts("Intel AC97 checks passed");
    return 0;
}
