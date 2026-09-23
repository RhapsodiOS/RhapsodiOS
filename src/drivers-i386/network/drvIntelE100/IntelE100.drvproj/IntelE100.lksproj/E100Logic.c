/*
 * E100Logic.c - pure logic for the 8255x driver.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * The chip table, the effective-revision rule and the quirk conditions
 * follow FreeBSD's if_fxp.c (fxp_ident_table, fxp_attach); the configure
 * bytes and statistics layouts follow the SDM. No code is taken from
 * either.
 */
#include "E100Logic.h"

/*
 * FreeBSD's ident list. 0x1229 is identified by revision first (SDM
 * Table 2); its catch-all entry must come after those.
 */
static const E100Chip chipTable[] = {
    { 0x1029, -1, 0, "82559 PCI/CardBus" },
    { 0x1030, -1, 0, "82559 InBusiness 10/100" },
    { 0x1031, -1, 3, "82801CAM (ICH3) PRO/100 VE" },
    { 0x1032, -1, 3, "82801CAM (ICH3) PRO/100 VE" },
    { 0x1033, -1, 3, "82801CAM (ICH3) PRO/100 VM" },
    { 0x1034, -1, 3, "82801CAM (ICH3) PRO/100 VM" },
    { 0x1035, -1, 3, "82801CAM (ICH3) PRO/100" },
    { 0x1036, -1, 3, "82801CAM (ICH3) PRO/100" },
    { 0x1037, -1, 3, "82801CAM (ICH3) PRO/100" },
    { 0x1038, -1, 3, "82801CAM (ICH3) PRO/100 VM" },
    { 0x1039, -1, 4, "82801DB (ICH4) PRO/100 VE" },
    { 0x103A, -1, 4, "82801DB (ICH4) PRO/100" },
    { 0x103B, -1, 4, "82801DB (ICH4) PRO/100 VM" },
    { 0x103C, -1, 4, "82801DB (ICH4) PRO/100" },
    { 0x103D, -1, 4, "82801DB (ICH4) PRO/100 VE" },
    { 0x103E, -1, 4, "82801DB (ICH4) PRO/100 VM" },
    { 0x1050, -1, 5, "82801BA (D865) PRO/100 VE" },
    { 0x1051, -1, 5, "82562ET (ICH5) PRO/100 VE" },
    { 0x1059, -1, 0, "82551QM" },
    { 0x1064, -1, 6, "82562EZ (ICH6)" },
    { 0x1065, -1, 6, "82562ET/EZ/GT/GZ PRO/100 VE" },
    { 0x1068, -1, 6, "82801FBM (ICH6-M) PRO/100 VE" },
    { 0x1069, -1, 6, "82562EM/EX/GX PRO/100" },
    { 0x1091, -1, 7, "82562GX PRO/100" },
    { 0x1092, -1, 7, "PRO/100 VE (ICH7)" },
    { 0x1093, -1, 7, "PRO/100 VM (ICH7)" },
    { 0x1094, -1, 7, "946GZ (ICH7) PRO/100" },
    { 0x1209, -1, 0, "82559ER" },
    { 0x1229, 0x01, 0, "82557" },
    { 0x1229, 0x02, 0, "82557" },
    { 0x1229, 0x03, 0, "82557" },
    { 0x1229, 0x04, 0, "82558" },
    { 0x1229, 0x05, 0, "82558" },
    { 0x1229, 0x06, 0, "82559" },
    { 0x1229, 0x07, 0, "82559" },
    { 0x1229, 0x08, 0, "82559" },
    { 0x1229, 0x09, 0, "82559ER" },
    { 0x1229, 0x0C, 0, "82550" },
    { 0x1229, 0x0D, 0, "82550" },
    { 0x1229, 0x0E, 0, "82550" },
    { 0x1229, 0x0F, 0, "82551" },
    { 0x1229, 0x10, 0, "82551" },
    { 0x1229, -1,   0, "82557/8/9" },
    { 0x2449, -1, 2, "82801BA/CAM (ICH2/3) PRO/100" },
    { 0x27DC, -1, 7, "82801GB (ICH7) PRO/100" },
    { 0, 0, 0, 0 }
};

const E100Chip *
e100ChipTable(void)
{
    return chipTable;
}

const E100Chip *
e100ChipLookup(unsigned short device, unsigned char revision)
{
    const E100Chip *c;

    for (c = chipTable; c->name != 0; c++) {
        if (c->device == device
            && (c->revision < 0 || c->revision == (short)revision))
            return c;
    }
    return 0;
}

/*
 * FreeBSD's rule (if_fxp.c, fxp_attach): every ICH part is treated as an
 * 82559 A0, and an EEPROM that calls the controller an 82557 wins over
 * the PCI revision.
 */
int
e100EffectiveRevision(const E100Chip *chip, unsigned char pciRevision,
                      const unsigned short *eeprom)
{
    if (chip->ich > 0)
        return E100_REV_82559;
    if ((eeprom[E100_EEPROM_CONTROLLER] >> 8) == 1)
        return E100_REV_82557;
    return pciRevision;
}

unsigned int
e100Quirks(const E100Chip *chip, int revision, const unsigned short *eeprom)
{
    unsigned int q = 0;
    unsigned short phy = eeprom[E100_EEPROM_PHY];

    /* 82557 receive lockup, unless EEPROM word 3 says it is fixed */
    if (revision < E100_REV_82558
        && (eeprom[E100_EEPROM_COMPAT] & E100_COMPAT_RXBUG_FIXED)
           != E100_COMPAT_RXBUG_FIXED)
        q |= E100_Q_RXBUG;

    /* 82503 serial interface: a device type is set and so is serial-only */
    if (revision == E100_REV_82557
        && (phy & E100_PHY_DEVICE_MASK) != 0
        && (phy & E100_PHY_SERIAL_ONLY) != 0)
        q |= E100_Q_SERIAL;

    /* Intel 82801BA erratum 30: Dynamic Standby left on in the EEPROM */
    if ((chip->ich == 2 || chip->ich == 3
         || (chip->ich == 0 && revision >= E100_REV_82559))
        && (eeprom[E100_EEPROM_ID] & E100_ID_STANDBY) != 0)
        q |= E100_Q_CU_RESUME;

    return q;
}

/* Generation names follow SDM Table 2's revision IDs. */
const char *
e100GenerationName(int revision)
{
    if (revision < 4)
        return "82557";
    if (revision < 6)
        return "82558";
    if (revision < E100_REV_82550)
        return "82559";
    return "82550/82551";
}

void
e100MacFromEeprom(const unsigned short *eeprom, unsigned char *mac)
{
    int i;

    for (i = 0; i < 3; i++) {
        mac[2 * i]     = (unsigned char)(eeprom[i] & 0xFF);
        mac[2 * i + 1] = (unsigned char)(eeprom[i] >> 8);
    }
}

int
e100MacValid(const unsigned char *mac)
{
    int i, zero = 1, ones = 1;

    for (i = 0; i < 6; i++) {
        if (mac[i] != 0x00)
            zero = 0;
        if (mac[i] != 0xFF)
            ones = 0;
    }
    return !zero && !ones && (mac[0] & 0x01) == 0;
}

/* The SDM's recommended configure bytes (SDM 6.4.2.3); see the spec. */
static const unsigned char configTemplate[E100_CONFIG_BYTES] = {
    0x16,       /*  0: 22 bytes                                       */
    0x08,       /*  1: receive FIFO limit 8, transmit 0               */
    0x00,       /*  2: adaptive IFS off                               */
    0x00,       /*  3: no MWI, no read or write alignment             */
    0x00,       /*  4: receive DMA byte count unused                  */
    0x00,       /*  5: transmit DMA byte count unused                 */
    0x32,       /*  6: CNA interrupts, standard TxCB and statistics   */
    0x03,       /*  7: underrun retry 1, discard short frames         */
    0x01,       /*  8: MII interface                                  */
    0x00,       /*  9                                                 */
    0x2E,       /* 10: 7-byte preamble, no source address insertion   */
    0x00,       /* 11                                                 */
    0x60,       /* 12: interframe spacing 6                           */
    0x00,       /* 13                                                 */
    0xF2,       /* 14                                                 */
    0x48,       /* 15                                                 */
    0x00,       /* 16                                                 */
    0x40,       /* 17                                                 */
    0xF2,       /* 18: pad short frames                               */
    0x80,       /* 19: duplex from the PHY's FDX pin                  */
    0x3F,       /* 20                                                 */
    0x05        /* 21                                                 */
};

void
e100BuildConfig(unsigned char *bytes, int revision, unsigned int quirks,
                int promiscuous, int allMulticast)
{
    int i;

    for (i = 0; i < E100_CONFIG_BYTES; i++)
        bytes[i] = configTemplate[i];

    /* Byte 12 bit 0 is reserved on the 82558 and 82559 and "should be set
     * to 1" (SDM 6.4.2.3); on the 82557 it selects linear priority. */
    if (revision >= E100_REV_82558)
        bytes[12] |= 0x01;

    if (quirks & E100_Q_SERIAL) {
        bytes[8] = 0x00;                /* 82503 serial, not MII        */
        bytes[15] |= 0x80;              /* CRS and CDT                  */
    }
    if (promiscuous) {
        bytes[6] |= 0x80;               /* save bad frames              */
        bytes[7] &= (unsigned char)~0x01; /* keep short frames          */
        bytes[15] |= 0x01;              /* promiscuous                  */
    }
    if (promiscuous || allMulticast)
        bytes[21] |= 0x08;              /* all multicast                */
}

void
e100FillMcast(E100McastCB *cb, const unsigned char *addrs, int count)
{
    int i;

    if (count > E100_MAX_MCAST)
        count = E100_MAX_MCAST;
    cb->byteCount = (unsigned short)(count * 6);
    for (i = 0; i < count * 6; i++)
        cb->addr[i] = addrs[i];
}

/*
 * The completion code lands after the last counter, and where that is
 * depends on the layout: 82557 format (16 counters), 82558 extended (19)
 * or 82559 TCO (dword 20, FreeBSD's offset). Configure byte 6 asks for the
 * 82557 format everywhere; accepting all three keeps a part that ignores
 * it readable.
 */
int
e100StatsComplete(const volatile unsigned long *stats)
{
    return stats[16] == E100_DUMP_RESET_DONE
        || stats[19] == E100_DUMP_RESET_DONE
        || stats[20] == E100_DUMP_RESET_DONE;
}

/* FreeBSD's policy (if_fxp.c, fxp_update_stats): any underrun since the
 * last dump raises the threshold one step, up to 192 (1536 bytes). */
unsigned int
e100NextThreshold(unsigned int threshold, unsigned long underruns)
{
    if (underruns != 0 && threshold < E100_TX_THRESHOLD_MAX)
        return threshold + E100_TX_THRESHOLD_STEP;
    return threshold;
}

void
e100DecodeLink(int bmsr, int anar, int anlpar, int intelStatus, E100Link *link)
{
    int common = 0;

    link->up = (bmsr & BMSR_LINK) != 0;
    link->known = 0;
    link->speed100 = 0;
    link->fullDuplex = 0;
    if (!link->up)
        return;

    if (anar >= 0 && anlpar >= 0 && (bmsr & BMSR_AUTONEG_DONE))
        common = anar & anlpar;

    if (common & ANLPAR_100FD) {
        link->speed100 = 1;
        link->fullDuplex = 1;
        link->known = 1;
    } else if (common & ANLPAR_100TX) {
        link->speed100 = 1;
        link->known = 1;
    } else if (common & ANLPAR_10FD) {
        link->fullDuplex = 1;
        link->known = 1;
    } else if (common & ANLPAR_10) {
        link->known = 1;
    } else if (intelStatus >= 0) {
        /* Not negotiated (parallel detection, or forced): Intel PHYs
         * report the result in register 16 (SDM 7.5). */
        link->speed100 = (intelStatus & INTEL_STATUS_100) != 0;
        link->fullDuplex = (intelStatus & INTEL_STATUS_FD) != 0;
        link->known = 1;
    }
}
