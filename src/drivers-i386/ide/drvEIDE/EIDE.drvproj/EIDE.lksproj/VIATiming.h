#ifndef _VIA_TIMING_H_
#define _VIA_TIMING_H_

#define VIA_IDE_586     0x15711106UL
#define VIA_IDE_LATER   0x05711106UL
#define VIA_BRIDGE_586  0x05861106UL
#define VIA_BRIDGE_596  0x05961106UL
#define VIA_BRIDGE_686  0x06861106UL

#define VIA_MODE_NONE 0xff

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

const viaChipInfo_t *VIAFindChip(unsigned long ideID,
                                 unsigned long bridgeID,
                                 unsigned char revision);

#endif /* _VIA_TIMING_H_ */
