/*
 * IdeBMIDE.h - Generic SFF-8038i bus-master IDE core and chipset back-end
 * interface. Shared definitions between the generic core (IdeBMIDE.m) and
 * the per-chipset back-ends (IdePIIX.m Intel, IdeVIA.m VIA, IdeAMD.m AMD,
 * IdeGeneric.m fallback).
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
    unsigned int  privateData;  /* selected back-end's per-controller value */
} ideChipCaps_t;

#define CHIP_FLAG_BUSMASTER      0x01   /* controller is bus-master capable */
#define CHIP_FLAG_HAS_IDECONFIG  0x02   /* ICH IDE_CONFIG (0x54) present */

/* Thin, swappable chipset back-end. Selected once at probe time. */
typedef struct {
    const char *name;
    /* Claim the device by PCI id / prog-if; fill *out on success. */
    BOOL (*match)(id deviceDescription, unsigned long pciID,
        unsigned char revision, unsigned char progIf, ideChipCaps_t *out);
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

/*
 * BMIDE IO space register offsets. Base address is set in BMIDE_BMIBA.
 * Register size (bits) in parenthesis.
 *
 * Note:
 * For the primary channel, the base address is stored in BMIDE_BMIBA.
 * For the secondary channel, the base address is equal to
 * (BMIDE_BMIBA + BMIDE_BM_OFFSET).
 */
#define BMIDE_BMIBA		0x20	// (32) Bus-Master interface base address
#define BMIDE_BMICX		0x00	// (8) Bus master IDE command register
#define BMIDE_BMISX		0x02	// (8) Bus master IDE status register
#define BMIDE_BMIDTPX	0x04	// (32) Descriptor table pointer register
#define BMIDE_BM_OFFSET	0x08	// offset to secondary channel registers
#define BMIDE_BM_SIZE	0x08	// size of the BM registers for each channel
#define BMIDE_BM_MASK	0xfff0	// mask BMIBA to get register base address

/*
 * BMIDE IO space register definition.
 *
 * BMICX - Bus master IDE command register
 */
typedef union {
	struct {
		u_char
			ssbm	:1,		// start/stop bus master
			rsvd1	:2,		// RESERVED
			rwcon	:1,		// Bus master read/write control
			rsvd2	:4;		// RESERVED
	} bits;
	u_char byte;
} bmide_bmicx_u;

/*
 * BMIDE IO space register definition.
 *
 * BMIDE_BMISX - Bus master IDE status register
 */
typedef union {
	struct {
		u_char
			bmidea	:1,		// Bus master IDE active
			err		:1,		// IDE DMA error
			ideints	:1,		// IDE interrupt status
			rsvd1	:2,		// RESERVED
			dma0cap	:1,		// drive 0 DMA capable
			dma1cap	:1,		// drive 1 DMA capable
			rsvd2	:1;		// RESERVED (hardwired to 0)
	} bits;
	u_char byte;
} bmide_bmisx_u;

#define BMIDE_STATUS_MASK	0x07
#define BMIDE_STATUS_OK		0x04
#define BMIDE_STATUS_ERROR	0x02
#define BMIDE_STATUS_ACTIVE	0x01

/*
 * BMIDE Bus Master alignment/boundary requirements.
 *
 * Intel nomemclature:
 * WORD  - 16-bit
 * DWord - 32-bit
 *
 * NOTE:
 * Boundary limit implies that the entire region is physically
 * contiguous.
 *
 * There is an error in the manual regarding DT alignment and boundary
 * restrictions. The "Intel 82371AB (PIIX4) Specification Update" has a
 * clarification to this issue.
 */
#define BMIDE_DT_ALIGN	4			// descriptor table must be DWord aligned.
#define BMIDE_DT_BOUND	(4 * 1024)	// cannot cross 4K boundary. (or 64K ?)

#define BMIDE_BUF_ALIGN	4			// memory buffer must be DWord aligned.
#define BMIDE_BUF_BOUND	(64 * 1024)	// cannot cross 64K boundary.
#define BMIDE_BUF_LIMIT	(64 * 1024) // limited to 64K in size

/*
 * BMIDE Bus Master Physical Region Descriptor (PRD) format.
 *
 */
typedef struct {
	u_int	base;				// base address
	u_int	count	:16,		// byte count
			rsvd	:15,
			eot		:1;			// final PRD indication bit
} bmide_prd_t;

/*
 * bmStopDMA needs external linkage: IdePIIX.m's PIIXInit calls it
 * directly (as a plain C function, not an Objective-C method) to
 * quiesce the bus master on reset. Defined in IdeBMIDE.m.
 */
extern void bmStopDMA(u_short bm_base);

#endif /* _IDE_BMIDE_H_ */
