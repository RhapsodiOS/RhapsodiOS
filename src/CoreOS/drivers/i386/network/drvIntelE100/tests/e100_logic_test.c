/*
 * e100_logic_test.c - unit tests for E100Logic.c.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see ../LICENSE.
 *
 * Built and run on the build guest by `gnumake check`. The guest is
 * PowerPC, so these assert values, never little-endian byte images.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "E100Logic.h"

static int failures;

static void
check(int ok, const char *test, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL %s: %s\n", test, what);
        failures++;
    }
}

static void
blank(unsigned short *ee)
{
    int i;

    for (i = 0; i < E100_EEPROM_WORDS_KEPT; i++)
        ee[i] = 0;
}

static void
test_chip_lookup(void)
{
    static const char t[] = "chip lookup";
    const E100Chip *c;

    c = e100ChipLookup(0x1229, 0x02);
    check(c != 0 && strcmp(c->name, "82557") == 0, t, "1229 rev 2 is an 82557");
    c = e100ChipLookup(0x1229, 0x09);
    check(c != 0 && strcmp(c->name, "82559ER") == 0, t, "1229 rev 9 is an 82559ER");
    c = e100ChipLookup(0x1229, 0x10);
    check(c != 0 && strcmp(c->name, "82551") == 0, t, "1229 rev 0x10 is an 82551");
    c = e100ChipLookup(0x1229, 0x42);
    check(c != 0 && c->revision == -1, t, "other 1229 revisions take the catch-all");
    c = e100ChipLookup(0x2449, 0x03);
    check(c != 0 && c->ich == 2, t, "2449 is ICH2");
    c = e100ChipLookup(0x1039, 0x00);
    check(c != 0 && c->ich == 4, t, "1039 is ICH4");
    check(e100ChipLookup(0x1234, 0x01) == 0, t, "unknown device refused");
}

/* Default.table must list exactly the devices the chip table knows. */
static void
test_default_table(void)
{
    static const char t[] = "Default.table";
    char buf[4096], id[16], *p, *end, *q;
    const E100Chip *c;
    unsigned long v;
    size_t n;
    FILE *f;

    f = fopen("../IntelE100.drvproj/Default.table", "r");
    if (f == 0) {
        check(0, t, "cannot open ../IntelE100.drvproj/Default.table");
        return;
    }
    n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = 0;
    p = strstr(buf, "\"Auto Detect IDs\"");
    if (p == 0) {
        check(0, t, "no Auto Detect IDs key");
        return;
    }
    end = strchr(p, ';');
    if (end != 0)
        *end = 0;
    for (c = e100ChipTable(); c->name != 0; c++) {
        sprintf(id, "0x%04X8086", (unsigned int)c->device);
        check(strstr(p, id) != 0, t, id);
    }
    for (q = strstr(p, "0x"); q != 0; q = strstr(q, "0x")) {
        v = strtoul(q, &q, 16);
        check((v & 0xFFFFUL) == 0x8086UL
              && e100ChipLookup((unsigned short)(v >> 16), 0x42) != 0,
              t, "a listed ID has no chip table entry");
    }
}

static void
test_revision(void)
{
    static const char t[] = "effective revision";
    unsigned short ee[E100_EEPROM_WORDS_KEPT];

    blank(ee);
    check(e100EffectiveRevision(e100ChipLookup(0x2449, 3), 3, ee) == 8,
          t, "ICH parts count as revision 8");
    ee[E100_EEPROM_CONTROLLER] = 0x0100;
    check(e100EffectiveRevision(e100ChipLookup(0x1229, 2), 2, ee) == 1,
          t, "EEPROM word 5 high byte 1 means an 82557");
    ee[E100_EEPROM_CONTROLLER] = 0;
    check(e100EffectiveRevision(e100ChipLookup(0x1229, 2), 2, ee) == 2,
          t, "otherwise the PCI revision");
    check(e100EffectiveRevision(e100ChipLookup(0x1209, 9), 9, ee) == 9,
          t, "82559ER keeps its PCI revision");
}

static void
test_quirks(void)
{
    static const char t[] = "quirks";
    unsigned short ee[E100_EEPROM_WORDS_KEPT];
    const E100Chip *c557 = e100ChipLookup(0x1229, 2);
    const E100Chip *ich2 = e100ChipLookup(0x2449, 3);
    const E100Chip *ich4 = e100ChipLookup(0x1039, 0);

    blank(ee);
    check((e100Quirks(c557, 2, ee) & E100_Q_RXBUG) != 0, t, "82557 without the fix");
    ee[E100_EEPROM_COMPAT] = 0x0003;
    check((e100Quirks(c557, 2, ee) & E100_Q_RXBUG) == 0, t, "82557 with the fix");
    ee[E100_EEPROM_COMPAT] = 0;
    check((e100Quirks(c557, 4, ee) & E100_Q_RXBUG) == 0, t, "no lockup from rev 4");

    ee[E100_EEPROM_PHY] = 0x8300;
    check((e100Quirks(c557, 1, ee) & E100_Q_SERIAL) != 0, t, "82503 on rev 1");
    check((e100Quirks(c557, 2, ee) & E100_Q_SERIAL) == 0, t, "serial only on rev 1");
    ee[E100_EEPROM_PHY] = 0x0701;
    check((e100Quirks(c557, 1, ee) & E100_Q_SERIAL) == 0, t, "MII PHY is not serial");
    ee[E100_EEPROM_PHY] = 0;

    ee[E100_EEPROM_ID] = E100_ID_STANDBY;
    check((e100Quirks(ich2, 8, ee) & E100_Q_CU_RESUME) != 0, t, "ICH2 with standby");
    check((e100Quirks(ich4, 8, ee) & E100_Q_CU_RESUME) == 0, t, "not ICH4");
    check((e100Quirks(c557, 8, ee) & E100_Q_CU_RESUME) != 0, t, "discrete rev 8");
    check((e100Quirks(c557, 5, ee) & E100_Q_CU_RESUME) == 0, t, "not discrete rev 5");
    ee[E100_EEPROM_ID] = 0;
    check((e100Quirks(ich2, 8, ee) & E100_Q_CU_RESUME) == 0, t, "not without standby");
}

static void
test_generation(void)
{
    static const char t[] = "generation name";

    check(strcmp(e100GenerationName(1), "82557") == 0, t, "rev 1");
    check(strcmp(e100GenerationName(5), "82558") == 0, t, "rev 5");
    check(strcmp(e100GenerationName(8), "82559") == 0, t, "rev 8");
    check(strcmp(e100GenerationName(9), "82559") == 0, t, "rev 9");
    check(strcmp(e100GenerationName(13), "82550/82551") == 0, t, "rev 13");
}

static void
test_mac(void)
{
    static const char t[] = "MAC";
    unsigned short ee[E100_EEPROM_WORDS_KEPT];
    unsigned char mac[6];
    static const unsigned char want[6] = { 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 };
    static const unsigned char zero[6] = { 0, 0, 0, 0, 0, 0 };
    static const unsigned char ones[6] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
    static const unsigned char group[6] = { 0x01, 0x00, 0x5E, 0x00, 0x00, 0x01 };

    blank(ee);
    ee[0] = 0x5452;
    ee[1] = 0x1200;
    ee[2] = 0x5634;
    e100MacFromEeprom(ee, mac);
    check(memcmp(mac, want, 6) == 0, t, "low byte of each word first");
    check(e100MacValid(mac), t, "station address accepted");
    check(!e100MacValid(zero), t, "all zeros refused");
    check(!e100MacValid(ones), t, "all ones refused");
    check(!e100MacValid(group), t, "multicast refused");
}

static void
test_config(void)
{
    static const char t[] = "configure bytes";
    unsigned char b[E100_CONFIG_BYTES];

    e100BuildConfig(b, 1, 0, 0, 0);
    check(b[0] == 0x16 && b[1] == 0x08 && b[6] == 0x32 && b[7] == 0x03, t, "82557 bytes 0-7");
    check(b[8] == 0x01 && b[10] == 0x2E && b[12] == 0x60, t, "82557 bytes 8-12");
    check(b[15] == 0x48 && b[17] == 0x40 && b[18] == 0xF2, t, "82557 bytes 15-18");
    check(b[19] == 0x80 && b[20] == 0x3F && b[21] == 0x05, t, "82557 bytes 19-21");

    e100BuildConfig(b, 8, 0, 0, 0);
    check(b[12] == 0x61, t, "82558+ sets byte 12 bit 0");

    e100BuildConfig(b, 1, E100_Q_SERIAL, 0, 0);
    check(b[8] == 0x00 && b[15] == 0xC8, t, "82503 serial interface");

    e100BuildConfig(b, 8, 0, 1, 0);
    check(b[15] == 0x49 && b[6] == 0xB2 && b[7] == 0x02 && b[21] == 0x0D,
          t, "promiscuous");

    e100BuildConfig(b, 8, 0, 0, 1);
    check(b[21] == 0x0D && b[15] == 0x48 && b[6] == 0x32, t, "all multicast only");
}

static void
test_mcast(void)
{
    static const char t[] = "multicast CB";
    static const unsigned char addrs[12] = {
        0x01, 0x00, 0x5E, 0x00, 0x00, 0x01, 0x01, 0x00, 0x5E, 0x00, 0x00, 0x02
    };
    unsigned char many[40 * 6];
    E100McastCB cb;

    e100FillMcast(&cb, addrs, 2);
    check(cb.byteCount == 12, t, "count is in bytes");
    check(cb.addr[5] == 0x01 && cb.addr[11] == 0x02, t, "addresses copied");
    memset(many, 0x01, sizeof(many));
    e100FillMcast(&cb, many, 40);
    check(cb.byteCount == E100_MAX_MCAST * 6, t, "capped at E100_MAX_MCAST");
    e100FillMcast(&cb, addrs, 0);
    check(cb.byteCount == 0, t, "empty list");
}

static void
test_stats(void)
{
    static const char t[] = "statistics completion";
    unsigned long s[E100_STATS_DWORDS];

    memset(s, 0, sizeof(s));
    check(!e100StatsComplete(s), t, "zeroed block is not complete");
    s[16] = E100_DUMP_RESET_DONE;
    check(e100StatsComplete(s), t, "82557 layout, dword 16");
    s[16] = 0;
    s[19] = E100_DUMP_RESET_DONE;
    check(e100StatsComplete(s), t, "82558 layout, dword 19");
    s[19] = 0;
    s[20] = E100_DUMP_RESET_DONE;
    check(e100StatsComplete(s), t, "82559 layout, dword 20");
    s[20] = 0;
    s[16] = 0x0000A005UL;
    check(!e100StatsComplete(s), t, "dump-without-reset code is not ours");
}

static void
test_threshold(void)
{
    static const char t[] = "transmit threshold";

    check(e100NextThreshold(64, 0) == 64, t, "no underruns, no change");
    check(e100NextThreshold(64, 3) == 128, t, "underruns raise it one step");
    check(e100NextThreshold(128, 1) == 192, t, "up to the maximum");
    check(e100NextThreshold(192, 9) == 192, t, "never past the maximum");
}

static void
test_link(void)
{
    static const char t[] = "link decode";
    E100Link l;

    e100DecodeLink(0x0000, 0x01E1, 0x01E1, -1, &l);
    check(!l.up && !l.known, t, "down");
    e100DecodeLink(0x0024, 0x01E1, 0x01E1, -1, &l);
    check(l.up && l.known && l.speed100 && l.fullDuplex, t, "100 full");
    e100DecodeLink(0x0024, 0x01E1, 0x0081, -1, &l);
    check(l.up && l.known && l.speed100 && !l.fullDuplex, t, "100 half");
    e100DecodeLink(0x0024, 0x01E1, 0x0041, -1, &l);
    check(l.up && l.known && !l.speed100 && l.fullDuplex, t, "10 full");
    e100DecodeLink(0x0004, 0x01E1, 0x0000, 0x0003, &l);
    check(l.up && l.known && l.speed100 && l.fullDuplex, t, "Intel register 16");
    e100DecodeLink(0x0004, -1, -1, -1, &l);
    check(l.up && !l.known, t, "up, nothing to say how");
}

int
main(void)
{
    test_chip_lookup();
    test_default_table();
    test_revision();
    test_quirks();
    test_generation();
    test_mac();
    test_config();
    test_mcast();
    test_stats();
    test_threshold();
    test_link();
    if (failures == 0)
        printf("e100_logic_test: all passed\n");
    return failures != 0;
}
