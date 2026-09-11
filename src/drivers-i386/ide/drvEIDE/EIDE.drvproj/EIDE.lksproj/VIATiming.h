#ifndef VIA_TIMING_H
#define VIA_TIMING_H

#define VIA_IDE_586     0x15711106UL
#define VIA_IDE_LATER   0x05711106UL
#define VIA_BRIDGE_586  0x05861106UL
#define VIA_BRIDGE_596  0x05961106UL
#define VIA_BRIDGE_686  0x06861106UL

#define VIA_MODE_NONE 0xff

#define VIA_CONFIG_BASE 0x40
#define VIA_CONFIG_SIZE 0x14

#define VIA_CHANNEL_PRIMARY 0
#define VIA_CHANNEL_SECONDARY 1

#define VIA_XFER_PIO 0
#define VIA_XFER_MWDMA 2
#define VIA_XFER_UDMA 3

typedef enum {
    VIA_CHIP_NONE,
    VIA_CHIP_586,
    VIA_CHIP_586A,
    VIA_CHIP_596A,
    VIA_CHIP_686A
} viaChip_t;

typedef struct {
    viaChip_t chip;
    const char *name;
    unsigned char maxPIO;
    unsigned char maxMWDMA;
    unsigned char maxUDMA;
} viaChipInfo_t;

typedef struct {
    unsigned char bytes[VIA_CONFIG_SIZE];
} viaConfig_t;

typedef struct {
    unsigned char present;
    unsigned char pioMode;
    unsigned char transferType;
    unsigned char transferMode;
} viaDriveTiming_t;

const viaChipInfo_t *VIAFindChip(unsigned long ideID,
                                 unsigned long bridgeID,
                                 unsigned char revision);
void VIAComputeConfig(viaConfig_t *config, viaChip_t chip,
                      unsigned char channel,
                      const viaDriveTiming_t drives[2]);
void VIAResetConfig(viaConfig_t *config, viaChip_t chip,
                    unsigned char channel);
int VIADetect80WireCable(const viaConfig_t *config, viaChip_t chip,
                         unsigned char channel);

#endif /* VIA_TIMING_H */
