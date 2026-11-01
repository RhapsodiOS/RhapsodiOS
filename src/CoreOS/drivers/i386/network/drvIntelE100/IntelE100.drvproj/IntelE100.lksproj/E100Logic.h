/*
 * E100Logic.h - the parts of the 8255x driver that are pure functions:
 * chip identification, quirk flags, configure bytes, statistics and link
 * decoding. No I/O and no kernel calls, so tests/ runs them anywhere.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 */
#ifndef E100LOGIC_H
#define E100LOGIC_H

#include "E100Regs.h"

typedef struct {
    unsigned short      device;
    short               revision;       /* PCI revision ID, or -1 for any */
    unsigned char       ich;            /* ICH generation; 0 = discrete   */
    const char         *name;
} E100Chip;

/* Effective revisions (FreeBSD if_fxpreg.h FXP_REV_*) */
#define E100_REV_82557          1
#define E100_REV_82558          4
#define E100_REV_82559          8       /* every ICH part counts as this  */
#define E100_REV_82550          12

/* Quirk flags */
#define E100_Q_RXBUG            0x01    /* 82557 receive lockup not fixed */
#define E100_Q_SERIAL           0x02    /* 82503 serial interface, no MII */
#define E100_Q_CU_RESUME        0x04    /* CU NOP before each CU Resume   */

/* Transmit threshold in the TxCB's units of 8 bytes (FreeBSD if_fxp.c) */
#define E100_TX_THRESHOLD_START 64
#define E100_TX_THRESHOLD_STEP  64
#define E100_TX_THRESHOLD_MAX   192

typedef struct {
    int up;
    int known;          /* speed100 and fullDuplex are meaningful */
    int speed100;
    int fullDuplex;
} E100Link;

const E100Chip *e100ChipTable(void);
const E100Chip *e100ChipLookup(unsigned short device, unsigned char revision);
int e100EffectiveRevision(const E100Chip *chip, unsigned char pciRevision,
                          const unsigned short *eeprom);
unsigned int e100Quirks(const E100Chip *chip, int revision,
                        const unsigned short *eeprom);
const char *e100GenerationName(int revision);

void e100MacFromEeprom(const unsigned short *eeprom, unsigned char *mac);
int e100MacValid(const unsigned char *mac);

void e100BuildConfig(unsigned char *bytes, int revision, unsigned int quirks,
                     int promiscuous, int allMulticast);
void e100FillMcast(E100McastCB *cb, const unsigned char *addrs, int count);

int e100StatsComplete(const volatile unsigned long *stats);
unsigned int e100NextThreshold(unsigned int threshold, unsigned long underruns);

void e100DecodeLink(int bmsr, int anar, int anlpar, int intelStatus,
                    E100Link *link);

#endif
