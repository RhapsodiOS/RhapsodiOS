#include "VIATiming.h"

typedef struct {
    unsigned long ideID;
    unsigned long bridgeID;
    unsigned char lo;
    unsigned char hi;
    viaChipInfo_t info;
} viaEntry_t;

static const viaEntry_t viaTable[] = {
    { VIA_IDE_586, VIA_BRIDGE_586, 0x00, 0x0f,
      { VIA_CHIP_586, "VT82C586", 4, 2, VIA_MODE_NONE } },
    { VIA_IDE_LATER, VIA_BRIDGE_586, 0x20, 0x2f,
      { VIA_CHIP_586A, "VT82C586A", 4, 2, 2 } },
    { VIA_IDE_LATER, VIA_BRIDGE_596, 0x00, 0x0f,
      { VIA_CHIP_596A, "VT82C596A", 4, 2, 2 } },
    { VIA_IDE_LATER, VIA_BRIDGE_686, 0x10, 0x2f,
      { VIA_CHIP_686A, "VT82C686A", 4, 2, 4 } }
};

typedef struct {
    unsigned short setup;
    unsigned short active8;
    unsigned short recover8;
    unsigned short cycle8;
    unsigned short active;
    unsigned short recover;
    unsigned short cycle;
} viaPIOTiming_t;

typedef struct {
    unsigned short setup;
    unsigned short active;
    unsigned short recover;
    unsigned short cycle;
} viaMWDMATiming_t;

typedef struct {
    unsigned char setup;
    unsigned char active8;
    unsigned char recover8;
    unsigned char active;
    unsigned char recover;
} viaClocks_t;

static const viaPIOTiming_t viaPIOTiming[] = {
    { 70, 290, 240, 600, 165, 150, 600 },
    { 50, 290,  93, 383, 125, 100, 383 },
    { 30, 290,  40, 330, 100,  90, 240 },
    { 30,  80,  70, 180,  80,  70, 180 },
    { 25,  70,  25, 120,  70,  25, 120 }
};

static const viaMWDMATiming_t viaMWDMATiming[] = {
    { 60, 215, 215, 480 },
    { 45,  80,  50, 150 },
    { 25,  70,  25, 120 }
};

static unsigned char VIAQuantize(unsigned short nanoseconds)
{
    return (unsigned char)((nanoseconds + 29) / 30);
}

static unsigned char VIAMax(unsigned char left, unsigned char right)
{
    return left > right ? left : right;
}

static unsigned char VIAClamp(unsigned char clocks, unsigned char maximum)
{
    if (clocks < 1)
        return 1;
    if (clocks > maximum)
        return maximum;
    return clocks;
}

static void VIAFitCycle(unsigned char *active, unsigned char *recover,
                        unsigned char cycle)
{
    unsigned char deficit;

    if ((unsigned int)*active + *recover >= cycle)
        return;

    deficit = (unsigned char)(cycle - *active - *recover);
    *active = (unsigned char)(*active + deficit / 2);
    *recover = (unsigned char)(cycle - *active);
}

static viaClocks_t VIAComputeClocks(const viaDriveTiming_t *drive)
{
    const viaPIOTiming_t *pio;
    const viaMWDMATiming_t *mwdma;
    viaClocks_t clocks;
    unsigned char cycle8;
    unsigned char cycle;

    pio = &viaPIOTiming[drive->pioMode];
    clocks.setup = VIAQuantize(pio->setup);
    clocks.active8 = VIAQuantize(pio->active8);
    clocks.recover8 = VIAQuantize(pio->recover8);
    cycle8 = VIAQuantize(pio->cycle8);
    clocks.active = VIAQuantize(pio->active);
    clocks.recover = VIAQuantize(pio->recover);
    cycle = VIAQuantize(pio->cycle);

    if (drive->transferType == VIA_XFER_MWDMA) {
        mwdma = &viaMWDMATiming[drive->transferMode];
        clocks.setup = VIAMax(clocks.setup, VIAQuantize(mwdma->setup));
        clocks.active = VIAMax(clocks.active, VIAQuantize(mwdma->active));
        clocks.recover = VIAMax(clocks.recover,
                                VIAQuantize(mwdma->recover));
        cycle = VIAMax(cycle, VIAQuantize(mwdma->cycle));
    }

    VIAFitCycle(&clocks.active8, &clocks.recover8, cycle8);
    VIAFitCycle(&clocks.active, &clocks.recover, cycle);
    clocks.setup = VIAClamp(clocks.setup, 4);
    clocks.active8 = VIAClamp(clocks.active8, 16);
    clocks.recover8 = VIAClamp(clocks.recover8, 16);
    clocks.active = VIAClamp(clocks.active, 16);
    clocks.recover = VIAClamp(clocks.recover, 16);
    return clocks;
}

static unsigned char VIAEncodeTiming(unsigned char active,
                                     unsigned char recover)
{
    return (unsigned char)(((active - 1) << 4) | (recover - 1));
}

static void VIAConfigureEarlyFIFO(viaConfig_t *config, viaChip_t chip)
{
    unsigned char enabled;
    unsigned char split;

    if (chip != VIA_CHIP_586 && chip != VIA_CHIP_586A)
        return;

    enabled = (unsigned char)(config->bytes[0] & 0x03);
    if (enabled == 0x02)
        split = 0x00;
    else if (enabled == 0x01)
        split = 0x60;
    else
        split = 0x20;
    config->bytes[0x43 - VIA_CONFIG_BASE] =
        (unsigned char)((config->bytes[0x43 - VIA_CONFIG_BASE] & 0x9f) |
                        split);
}

static void VIAClearHalfClock(viaConfig_t *config, viaChip_t chip,
                              unsigned char channel)
{
    unsigned char mask;

    if (chip != VIA_CHIP_586)
        return;

    mask = channel == VIA_CHANNEL_PRIMARY ? 0x0f : 0xf0;
    config->bytes[0x4d - VIA_CONFIG_BASE] &= mask;
}

const viaChipInfo_t *VIAFindChip(unsigned long ideID,
                                 unsigned long bridgeID,
                                 unsigned char revision)
{
    unsigned long i;

    for (i = 0; i < sizeof(viaTable) / sizeof(viaTable[0]); ++i) {
        if (viaTable[i].ideID == ideID &&
            viaTable[i].bridgeID == bridgeID &&
            revision >= viaTable[i].lo && revision <= viaTable[i].hi)
            return &viaTable[i].info;
    }

    return 0;
}

void VIAComputeConfig(viaConfig_t *config, viaChip_t chip,
                      unsigned char channel,
                      const viaDriveTiming_t drives[2])
{
    viaClocks_t clocks;
    unsigned char commandActive;
    unsigned char commandRecover;
    unsigned char commandPresent;
    unsigned char dataOffset;
    unsigned char setupOffset;
    unsigned char setupShift;
    unsigned char setupMask;
    unsigned char unit;
    unsigned char dn;

    if (chip <= VIA_CHIP_NONE || chip > VIA_CHIP_686A ||
        channel > VIA_CHANNEL_SECONDARY)
        return;
    for (unit = 0; unit < 2; ++unit) {
        if (!drives[unit].present)
            continue;
        if (drives[unit].pioMode > 4 ||
            (drives[unit].transferType == VIA_XFER_MWDMA &&
             drives[unit].transferMode > 2))
            return;
    }

    VIAConfigureEarlyFIFO(config, chip);
    VIAClearHalfClock(config, chip, channel);
    commandActive = 0;
    commandRecover = 0;
    commandPresent = 0;
    setupOffset = 0x4c - VIA_CONFIG_BASE;

    for (unit = 0; unit < 2; ++unit) {
        if (!drives[unit].present)
            continue;

        clocks = VIAComputeClocks(&drives[unit]);
        dn = (unsigned char)(channel * 2 + unit);
        dataOffset = (unsigned char)(0x48 + (3 - dn) - VIA_CONFIG_BASE);
        setupShift = (unsigned char)((3 - dn) * 2);
        setupMask = (unsigned char)(0x03 << setupShift);
        config->bytes[dataOffset] =
            VIAEncodeTiming(clocks.active, clocks.recover);
        config->bytes[setupOffset] =
            (unsigned char)((config->bytes[setupOffset] & ~setupMask) |
                            ((clocks.setup - 1) << setupShift));
        commandActive = VIAMax(commandActive, clocks.active8);
        commandRecover = VIAMax(commandRecover, clocks.recover8);
        commandPresent = 1;
    }

    if (commandPresent)
        config->bytes[0x4e + (1 - channel) - VIA_CONFIG_BASE] =
            VIAEncodeTiming(commandActive, commandRecover);
}

void VIAResetConfig(viaConfig_t *config, viaChip_t chip,
                    unsigned char channel)
{
    unsigned char dn;
    unsigned char dataOffset;
    unsigned char setupShift;
    unsigned char setupMask;
    unsigned char unit;

    VIAConfigureEarlyFIFO(config, chip);
    VIAClearHalfClock(config, chip, channel);

    for (unit = 0; unit < 2; ++unit) {
        dn = (unsigned char)(channel * 2 + unit);
        dataOffset = (unsigned char)(0x48 + (3 - dn) - VIA_CONFIG_BASE);
        setupShift = (unsigned char)((3 - dn) * 2);
        setupMask = (unsigned char)(0x03 << setupShift);
        config->bytes[dataOffset] = 0xa8;
        config->bytes[0x4c - VIA_CONFIG_BASE] =
            (unsigned char)((config->bytes[0x4c - VIA_CONFIG_BASE] &
                             ~setupMask) | (0x03 << setupShift));
    }

    config->bytes[0x4e + (1 - channel) - VIA_CONFIG_BASE] = 0xff;
}

int VIADetect80WireCable(const viaConfig_t *config, viaChip_t chip,
                         unsigned char channel)
{
    (void)config;
    (void)chip;
    (void)channel;
    return 0;
}
