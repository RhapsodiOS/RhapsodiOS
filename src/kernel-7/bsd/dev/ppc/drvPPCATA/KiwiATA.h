/*
 * KiwiATA.h - Kiwi, Apple's name for the Promise PDC2027x ATA controller
 * ("kiwi-root") on the Xserve G4.  Pure C, no kernel headers, so the host
 * tests build it.
 *
 * Registers are SFF-8038i style in PCI I/O space.  Values follow Linux
 * drivers/ide/pdc202xx_new.c and drivers/ata/pata_pdc2027x.c, used as
 * hardware references.
 */

#ifndef _BSD_DEV_PPC_KIWIATA_H_
#define _BSD_DEV_PPC_KIWIATA_H_

#define KIWI_VENDOR_PROMISE		0x105a

/* BARs 0-3 are task file and control for each channel; BAR4 is bus master. */
#define KIWI_BAR_COUNT			5
#define KIWI_BUS_MASTER_BAR		4
#define KIWI_CONTROL_OFFSET		2	/* device control in its BAR */
#define KIWI_ADDRESS_CELLS		5	/* one "assigned-addresses" entry */

/* Bus-master block, one per channel. */
#define KIWI_BM_CHANNEL_STRIDE		8
#define KIWI_BM_COMMAND			0
#define KIWI_BM_INDEX			1
#define KIWI_BM_STATUS			2
#define KIWI_BM_DATA			3
#define KIWI_BM_PRD			4	/* 32 bits, little-endian */

#define KIWI_BM_COMMAND_START		0x01
#define KIWI_BM_COMMAND_READ		0x08	/* device to memory */
#define KIWI_BM_STATUS_ERROR		0x02
#define KIWI_BM_STATUS_INTERRUPT	0x04
#define KIWI_BM_STATUS_DRIVES		0x60	/* drive DMA capable bits */

/* Indexed registers, reached through a channel's index and data ports. */
#define KIWI_INDEX_TEST_MODE		0x01	/* primary channel */
#define KIWI_TEST_MODE_ENABLE		0x40
#define KIWI_INDEX_PLL_F		0x02	/* secondary channel */
#define KIWI_INDEX_PLL_R		0x03	/* secondary channel */
#define KIWI_INDEX_CABLE		0x0b
#define KIWI_CABLE_40_WIRE		0x04
#define KIWI_INDEX_COUNTER_LOW		0x20
#define KIWI_INDEX_COUNTER_HIGH		0x21

/* Apple's setup: set bit 0 of configuration byte 0x40 on revision 3 on. */
#define KIWI_CONFIG_APPLE		0x40
#define KIWI_CONFIG_APPLE_ENABLE	0x01
#define KIWI_CONFIG_APPLE_REVISION	3

#define KIWI_PLL_SETTLE_MS		30
#define KIWI_ULTRA_40_WIRE		2
#define KIWI_MAX_TIMING_WRITES		6

typedef enum {
    kKiwiDMANone, kKiwiDMAMultiword, kKiwiDMAUltra
} KiwiDMAType;

/* New value = (old & ~clear) | set.  A clear of 0xff needs no read. */
typedef struct {
    unsigned char	index;
    unsigned char	clear;
    unsigned char	set;
} KiwiRegisterWrite;

/*
 * Highest Ultra DMA mode of the part named by PCI configuration word 0
 * (device << 16 | vendor): 6 or 5, or 0 for anything else.
 */
unsigned int KiwiUltraLimit(unsigned int pciID);

/* Highest Ultra DMA mode for the part's limit and cable register. */
unsigned int KiwiMaxUltraMode(unsigned int limit, unsigned int cable);

/* Whether a "compatible" property (may be unterminated) lists kiwi-root. */
int KiwiIsCompatible(const char *compatible, unsigned int length);

/*
 * Find BAR0-BAR4 among "assigned-addresses" entries; each must be in I/O
 * space.  On success entry[bar] is the entry's position.
 */
int KiwiFindBARs(const unsigned int *cells, unsigned int entries,
    unsigned int entry[KIWI_BAR_COUNT]);

/* The 30-bit clock counter from its four indexed bytes. */
unsigned long KiwiCounter(unsigned int primaryLow, unsigned int primaryHigh,
    unsigned int secondaryLow, unsigned int secondaryHigh);

/* Whether a re-read counter agrees with the previous read. */
int KiwiCounterSettled(unsigned long previous, unsigned long current);

/* PLL input in Hz from the down-counter over an elapsed time; 0 if unknown. */
unsigned long KiwiPLLInput(unsigned long start, unsigned long end,
    unsigned long elapsedMicroseconds);

/*
 * PLL F and R for the part's limit.  Returns 0, leaving the outputs alone,
 * when the input or the result is out of range.
 */
int KiwiPLLControl(unsigned long input, unsigned int limit,
    unsigned int *f, unsigned int *r);

/*
 * Indexed writes that set one drive's timing after SET FEATURES.  Returns the
 * number of writes, or -1 for a mode or part the tables do not cover.
 */
int KiwiTimingWrites(unsigned int limit, unsigned int drive,
    unsigned int pioMode, KiwiDMAType dmaType, unsigned int dmaMode,
    KiwiRegisterWrite writes[KIWI_MAX_TIMING_WRITES]);

/*
 * Skip a firmware path component naming this channel ("/name@1" before the
 * disk's own component).  Returns the rest of the path, the path unchanged
 * when there is no such component, or 0 when it names the other channel.
 */
const char *KiwiSkipChannel(const char *tail, unsigned int channel);

#endif /* _BSD_DEV_PPC_KIWIATA_H_ */
