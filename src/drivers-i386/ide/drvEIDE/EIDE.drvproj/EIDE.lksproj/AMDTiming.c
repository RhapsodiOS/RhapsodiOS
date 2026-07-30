#include "AMDTiming.h"

typedef struct {
    unsigned short setup;
    unsigned short active8;
    unsigned short recover8;
    unsigned short cycle8;
    unsigned short active;
    unsigned short recover;
    unsigned short cycle;
} amdPIOTiming_t;

typedef struct {
    unsigned short setup;
    unsigned short active;
    unsigned short recover;
    unsigned short cycle;
} amdMWDMATiming_t;

typedef struct {
    unsigned char setup;
    unsigned char active8;
    unsigned char recover8;
    unsigned char active;
    unsigned char recover;
} amdClocks_t;

static const amdPIOTiming_t amdPIOTiming[] = {
    { 70, 290, 240, 600, 165, 150, 600 },
    { 50, 290,  93, 383, 125, 100, 383 },
    { 30, 290,  40, 330, 100,  90, 240 },
    { 30,  80,  70, 180,  80,  70, 180 },
    { 25,  70,  25, 120,  70,  25, 120 }
};

static const amdMWDMATiming_t amdMWDMATiming[] = {
    { 60, 215, 215, 480 },
    { 45,  80,  50, 150 },
    { 25,  70,  25, 120 }
};

static const amdChipInfo_t amd756Early = {
    AMD_CHIP_756, "AMD-756", 4, AMD_MODE_NONE, 4
};

static const amdChipInfo_t amd756Later = {
    AMD_CHIP_756, "AMD-756", 4, 2, 4
};

static const amdChipInfo_t amd766 = {
    AMD_CHIP_766, "AMD-766", 4, 2, 5
};

static unsigned char AMDClocks(unsigned short nanoseconds)
{
    return (unsigned char)((nanoseconds + 29) / 30);
}

static unsigned char AMDMaximum(unsigned char left, unsigned char right)
{
    return left > right ? left : right;
}

static unsigned char AMDClamp(unsigned char value, unsigned char low,
                              unsigned char high)
{
    if (value < low)
        return low;
    if (value > high)
        return high;
    return value;
}

static int AMDValidChip(amdChip_t chip)
{
    return chip == AMD_CHIP_756 || chip == AMD_CHIP_766;
}

static void AMDFitCycle(unsigned char *active, unsigned char *recover,
                        unsigned char cycle)
{
    unsigned char deficit;

    if ((unsigned int)*active + *recover >= cycle)
        return;

    deficit = (unsigned char)(cycle - *active - *recover);
    *active = (unsigned char)(*active + deficit / 2);
    *recover = (unsigned char)(cycle - *active);
}

static amdClocks_t AMDComputeClocks(const amdDriveTiming_t *drive)
{
    const amdPIOTiming_t *pio;
    const amdMWDMATiming_t *mwdma;
    amdClocks_t clocks;
    unsigned char cycle8;
    unsigned char cycle;

    pio = &amdPIOTiming[drive->pioMode];
    clocks.setup = AMDClocks(pio->setup);
    clocks.active8 = AMDClocks(pio->active8);
    clocks.recover8 = AMDClocks(pio->recover8);
    cycle8 = AMDClocks(pio->cycle8);
    clocks.active = AMDClocks(pio->active);
    clocks.recover = AMDClocks(pio->recover);
    cycle = AMDClocks(pio->cycle);

    if (drive->transferType == AMD_XFER_MWDMA) {
        mwdma = &amdMWDMATiming[drive->transferMode];
        clocks.setup = AMDMaximum(clocks.setup, AMDClocks(mwdma->setup));
        clocks.active = AMDMaximum(clocks.active, AMDClocks(mwdma->active));
        clocks.recover = AMDMaximum(clocks.recover,
                                    AMDClocks(mwdma->recover));
        cycle = AMDMaximum(cycle, AMDClocks(mwdma->cycle));
    }

    AMDFitCycle(&clocks.active8, &clocks.recover8, cycle8);
    AMDFitCycle(&clocks.active, &clocks.recover, cycle);
    clocks.setup = AMDClamp(clocks.setup, 1, 4);
    clocks.active8 = AMDClamp(clocks.active8, 1, 16);
    clocks.recover8 = AMDClamp(clocks.recover8, 1, 16);
    clocks.active = AMDClamp(clocks.active, 1, 16);
    clocks.recover = AMDClamp(clocks.recover, 1, 16);
    return clocks;
}

static unsigned char AMDEncode(unsigned char active, unsigned char recover)
{
    return (unsigned char)(((active - 1) << 4) | (recover - 1));
}

static unsigned char AMDDataOffset(unsigned char channel, unsigned char unit)
{
    unsigned char dn;

    dn = (unsigned char)(channel * 2 + unit);
    return (unsigned char)(0x48 + (3 - dn) - AMD_CONFIG_BASE);
}

static unsigned char AMDSetupShift(unsigned char channel, unsigned char unit)
{
    unsigned char dn;

    dn = (unsigned char)(channel * 2 + unit);
    return (unsigned char)((3 - dn) * 2);
}

static unsigned char AMDCommandOffset(unsigned char channel)
{
    return (unsigned char)(0x4e + (1 - channel) - AMD_CONFIG_BASE);
}

const amdChipInfo_t *AMDFindChip(unsigned long pciID, unsigned char revision)
{
    if (pciID == AMD_IDE_756) {
        if (revision <= 3)
            return &amd756Early;
        return &amd756Later;
    }

    if (pciID == AMD_IDE_766)
        return &amd766;

    return 0;
}

void AMDComputeConfig(amdConfig_t *config, amdChip_t chip,
                      unsigned char channel,
                      const amdDriveTiming_t drives[2])
{
    amdClocks_t clocks;
    unsigned char commandActive;
    unsigned char commandRecover;
    unsigned char commandPresent;
    unsigned char dataOffset;
    unsigned char setupOffset;
    unsigned char setupShift;
    unsigned char setupMask;
    unsigned char unit;

    if (config == 0 || drives == 0 || !AMDValidChip(chip) ||
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

    setupOffset = 0x4c - AMD_CONFIG_BASE;
    for (unit = 0; unit < 2; ++unit) {
        dataOffset = AMDDataOffset(channel, unit);
        setupShift = AMDSetupShift(channel, unit);
        setupMask = (unsigned char)(0x03 << setupShift);
        config->bytes[dataOffset] = 0xa8;
        config->bytes[setupOffset] =
            (unsigned char)((config->bytes[setupOffset] & ~setupMask) |
                            (0x03 << setupShift));
    }

    commandActive = 0;
    commandRecover = 0;
    commandPresent = 0;
    for (unit = 0; unit < 2; ++unit) {
        if (!drives[unit].present)
            continue;

        clocks = AMDComputeClocks(&drives[unit]);
        dataOffset = AMDDataOffset(channel, unit);
        setupShift = AMDSetupShift(channel, unit);
        setupMask = (unsigned char)(0x03 << setupShift);
        config->bytes[dataOffset] = AMDEncode(clocks.active, clocks.recover);
        config->bytes[setupOffset] =
            (unsigned char)((config->bytes[setupOffset] & ~setupMask) |
                            ((clocks.setup - 1) << setupShift));
        commandActive = AMDMaximum(commandActive, clocks.active8);
        commandRecover = AMDMaximum(commandRecover, clocks.recover8);
        commandPresent = 1;
    }

    if (commandPresent)
        config->bytes[AMDCommandOffset(channel)] =
            AMDEncode(commandActive, commandRecover);
    else
        config->bytes[AMDCommandOffset(channel)] = 0xff;
}

void AMDResetConfig(amdConfig_t *config, amdChip_t chip,
                    unsigned char channel)
{
    unsigned char dataOffset;
    unsigned char setupOffset;
    unsigned char setupShift;
    unsigned char setupMask;
    unsigned char unit;

    if (config == 0 || !AMDValidChip(chip) ||
        channel > AMD_CHANNEL_SECONDARY)
        return;

    setupOffset = 0x4c - AMD_CONFIG_BASE;
    for (unit = 0; unit < 2; ++unit) {
        dataOffset = AMDDataOffset(channel, unit);
        setupShift = AMDSetupShift(channel, unit);
        setupMask = (unsigned char)(0x03 << setupShift);
        config->bytes[dataOffset] = 0xa8;
        config->bytes[setupOffset] =
            (unsigned char)((config->bytes[setupOffset] & ~setupMask) |
                            (0x03 << setupShift));
    }

    config->bytes[AMDCommandOffset(channel)] = 0xff;
}
