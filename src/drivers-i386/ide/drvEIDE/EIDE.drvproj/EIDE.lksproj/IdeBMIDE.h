/*
 * IdeBMIDE.h - Generic SFF-8038i bus-master IDE core and chipset back-end
 * interface. Shared definitions between the generic core (IdeBMIDE.m) and
 * the per-chipset back-ends (IdePIIX.m Intel, IdeGeneric.m fallback).
 */
#ifndef _IDE_BMIDE_H_
#define _IDE_BMIDE_H_

#import "ata_extern.h"          /* ata_mode_t, transfer types */

/* An ATA mode number (0-based). 0xff means "this transfer type unsupported". */
#define ATA_MODE_NUM_NONE   0xff

/* PCI class-code fields (config dword at 0x08). */
#define PCI_CLASS_MASS_STORAGE  0x01
#define PCI_SUBCLASS_IDE        0x01
/* Programming-interface byte bits (SFF-8038i / PCI IDE). */
#define PCI_IDE_PRIMARY_NATIVE   0x01
#define PCI_IDE_SECONDARY_NATIVE 0x04
#define PCI_IDE_BUSMASTER        0x80

/* Chipset capability descriptor filled in by a back-end's match(). */
typedef struct {
    unsigned char maxPIO;       /* highest PIO mode number */
    unsigned char maxMWDMA;     /* highest multiword DMA mode, or ATA_MODE_NUM_NONE */
    unsigned char maxUDMA;      /* highest ultra DMA mode, or ATA_MODE_NUM_NONE */
    unsigned int  flags;
} ideChipCaps_t;

#define CHIP_FLAG_BUSMASTER      0x01   /* controller is bus-master capable */
#define CHIP_FLAG_HAS_IDECONFIG  0x02   /* ICH IDE_CONFIG (0x54) present */

/* Thin, swappable chipset back-end. Selected once at probe time. */
typedef struct {
    const char *name;
    /* Claim the device by PCI id / prog-if; fill *out on success. */
    BOOL (*match)(unsigned long pciID, unsigned char progIf, ideChipCaps_t *out);
    /* Program the chip's timing registers for the negotiated drive modes. */
    void (*setTiming)(id self, void *drives);      /* driveInfo_t * */
    /* Revert the chip to compatible/default timing. */
    void (*resetTiming)(id self);
    /* Detect an 80-conductor cable (gates UDMA > mode 2). */
    BOOL (*detectCable)(id self);
} ideChipsetOps_t;

/* Back-end op tables, defined in their respective .m files. */
extern const ideChipsetOps_t ideIntelOps;      /* IdePIIX.m */
extern const ideChipsetOps_t ideGenericOps;    /* IdeGeneric.m */

#endif /* _IDE_BMIDE_H_ */
