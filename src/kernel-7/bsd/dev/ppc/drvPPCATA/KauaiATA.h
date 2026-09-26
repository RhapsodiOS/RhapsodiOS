/*
 * KauaiATA.h - Kauai UltraATA/100 cell ("kauai-ata" on UniNorth 2's
 * internal PCI bus).  Pure C, no kernel headers, so the host tests build it.
 *
 * Offsets are from PCI BAR0 unless noted.  Every register is little-endian.
 * Values follow Linux drivers/ata/pata_macio.c, used as a hardware
 * reference.
 */

#ifndef _BSD_DEV_PPC_KAUAIATA_H_
#define _BSD_DEV_PPC_KAUAIATA_H_

#define KAUAI_FCR_OFFSET		0x0000
#define KAUAI_DBDMA_OFFSET		0x1000
#define KAUAI_TASKFILE_OFFSET		0x2000

/* Timing registers, from the task file base. */
#define KAUAI_PIO_CONFIG_OFFSET		0x200	/* PIO and multiword DMA */
#define KAUAI_ULTRA_CONFIG_OFFSET	0x210	/* Ultra DMA, bit 0 enables */

/* BAR0 must reach the Ultra DMA timing register. */
#define KAUAI_REGISTER_SPAN \
	(KAUAI_TASKFILE_OFFSET + KAUAI_ULTRA_CONFIG_OFFSET + 4)

/* Feature control: magic bit, reset negated, cell enabled. */
#define KAUAI_FCR_ENABLE		0x00000007

#define KAUAI_MAX_ULTRA_MODE		5
#define KAUAI_MAX_ULTRA_40_WIRE		2

typedef enum {
    kKauaiDMANone, kKauaiDMAMultiword, kKauaiDMAUltra
} KauaiDMAType;

/*
 * Timing words for one drive, in host order.  Without DMA the first word
 * carries multiword DMA 0 timing, as Linux does.  Returns 0, leaving the
 * outputs alone, for a mode the cell has no timing for.
 */
int KauaiTimingWords(unsigned int pioMode, KauaiDMAType dmaType,
    unsigned int dmaMode, unsigned int *pioConfig,
    unsigned int *ultraConfig);

/* Highest Ultra DMA mode for the node's "cable-type" (may be absent). */
unsigned int KauaiMaxUltraMode(const char *cableType, unsigned int length);

#endif /* _BSD_DEV_PPC_KAUAIATA_H_ */
