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

const amdChipInfo_t *AMDFindChip(unsigned long pciID, unsigned char revision);
void AMDComputeConfig(amdConfig_t *config, amdChip_t chip,
                      unsigned char channel,
                      const amdDriveTiming_t drives[2]);
void AMDResetConfig(amdConfig_t *config, amdChip_t chip,
                    unsigned char channel);
int AMDDetect80WireCable(const amdConfig_t *config, amdChip_t chip,
                         unsigned char channel);

#endif /* AMD_TIMING_H */
