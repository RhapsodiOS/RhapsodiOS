#include <stdio.h>
#include <string.h>

#include "../KiwiATA.h"

static int failures;

#define CHECK(x) do { \
    if (!(x)) { \
        printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #x); \
        failures++; \
    } \
} while (0)

#define PROMISE(device)	(((unsigned int)(device) << 16) | KIWI_VENDOR_PROMISE)

static void
test_parts(void)
{
    static const unsigned int ultra133[] = {
        0x4d69, 0x6269, 0x1275, 0x5275, 0x7275
    };
    static const unsigned int ultra100[] = { 0x4d68, 0x6268 };
    unsigned int i;

    for (i = 0; i < sizeof(ultra133) / sizeof(ultra133[0]); i++)
        CHECK(KiwiUltraLimit(PROMISE(ultra133[i])) == 6);
    for (i = 0; i < sizeof(ultra100) / sizeof(ultra100[0]); i++)
        CHECK(KiwiUltraLimit(PROMISE(ultra100[i])) == 5);

    /* Older Promise parts, other vendors, and the halves swapped. */
    CHECK(KiwiUltraLimit(PROMISE(0x4d38)) == 0);
    CHECK(KiwiUltraLimit(PROMISE(0x0d38)) == 0);
    CHECK(KiwiUltraLimit((0x4d69U << 16) | 0x1095) == 0);
    CHECK(KiwiUltraLimit((KIWI_VENDOR_PROMISE << 16) | 0x4d69) == 0);
    CHECK(KiwiUltraLimit(0xffffffffU) == 0);

    CHECK(KiwiMaxUltraMode(6, 0x00) == 6);
    CHECK(KiwiMaxUltraMode(5, 0xfb) == 5);
    CHECK(KiwiMaxUltraMode(6, KIWI_CABLE_40_WIRE) == 2);
    CHECK(KiwiMaxUltraMode(5, 0xff) == 2);
}

static void
test_compatible(void)
{
    static const char alone[] = "kiwi-root";
    static const char listed[] = "pci105a,4d69\0kiwi-root";
    static const char prefix[] = "kiwi-root2\0kiwi";
    static const char other[] = "cmd646-ata";
    static const char cut[] = { 'k', 'i', 'w', 'i', '-', 'r', 'o', 'o', 't' };

    CHECK(KiwiIsCompatible(alone, sizeof(alone)));
    CHECK(KiwiIsCompatible(listed, sizeof(listed)));
    CHECK(KiwiIsCompatible(cut, sizeof(cut)));
    CHECK(!KiwiIsCompatible(prefix, sizeof(prefix)));
    CHECK(!KiwiIsCompatible(other, sizeof(other)));
    CHECK(!KiwiIsCompatible(alone, 8));
    CHECK(!KiwiIsCompatible(listed, 13));
    CHECK(!KiwiIsCompatible(0, 0));
}

/* phys.hi: space in bits 24-25 (1 = I/O, 2 = memory), register in 0-7. */
#define IO_BAR(bar)	(0x81000000U | (0x10U + 4U * (bar)))
#define MEM_BAR(bar)	(0x82000000U | (0x10U + 4U * (bar)))

static void
set_entry(unsigned int *cells, unsigned int n, unsigned int hi)
{
    cells[n * KIWI_ADDRESS_CELLS + 0] = hi;
    cells[n * KIWI_ADDRESS_CELLS + 1] = 0;
    cells[n * KIWI_ADDRESS_CELLS + 2] = 0x400 + 0x10 * n;
    cells[n * KIWI_ADDRESS_CELLS + 3] = 0;
    cells[n * KIWI_ADDRESS_CELLS + 4] = 8;
}

static void
test_bars(void)
{
    unsigned int cells[7 * KIWI_ADDRESS_CELLS];
    unsigned int entry[KIWI_BAR_COUNT];
    unsigned int i;

    /* In order, with BAR5 as memory space after them. */
    for (i = 0; i < KIWI_BAR_COUNT; i++)
        set_entry(cells, i, IO_BAR(i));
    set_entry(cells, 5, MEM_BAR(5));
    CHECK(KiwiFindBARs(cells, 6, entry));
    for (i = 0; i < KIWI_BAR_COUNT; i++)
        CHECK(entry[i] == i);

    /* Any order; BAR5 first. */
    set_entry(cells, 0, MEM_BAR(5));
    set_entry(cells, 1, IO_BAR(4));
    set_entry(cells, 2, IO_BAR(2));
    set_entry(cells, 3, IO_BAR(0));
    set_entry(cells, 4, IO_BAR(3));
    set_entry(cells, 5, IO_BAR(1));
    CHECK(KiwiFindBARs(cells, 6, entry));
    CHECK(entry[0] == 3 && entry[1] == 5 && entry[2] == 2 &&
        entry[3] == 4 && entry[4] == 1);

    /* Too few entries to hold BAR1. */
    CHECK(!KiwiFindBARs(cells, 5, entry));

    /* A BAR in memory space. */
    set_entry(cells, 2, MEM_BAR(2));
    CHECK(!KiwiFindBARs(cells, 6, entry));

    /* A missing BAR: the expansion ROM in its place. */
    set_entry(cells, 2, 0x82000030U);
    CHECK(!KiwiFindBARs(cells, 6, entry));

    CHECK(!KiwiFindBARs(0, 0, entry));
}

static void
test_counter(void)
{
    CHECK(KiwiCounter(0, 0, 0, 0) == 0);
    CHECK(KiwiCounter(0xff, 0x7f, 0xff, 0x7f) == 0x3fffffffUL);
    CHECK(KiwiCounter(0x34, 0x12, 0x78, 0x56) == 0x2b3c1234UL);
    /* The top bit of each high byte is not part of the count. */
    CHECK(KiwiCounter(0x34, 0x92, 0x78, 0xd6) == 0x2b3c1234UL);

    CHECK(KiwiCounterSettled(0x1000, 0x0ff0));
    CHECK(KiwiCounterSettled(0x1000, 0x1000));
    CHECK(!KiwiCounterSettled(0x1000, 0x1001));
    CHECK(!KiwiCounterSettled(0x00010000UL, 0x00008000UL));
    CHECK(!KiwiCounterSettled(0, 0x2b3c1234UL));
}

static void
test_pll_input(void)
{
    unsigned long hz;

    /* 16.949 MHz over 10 ms is 169490 counts. */
    hz = KiwiPLLInput(1000000UL, 1000000UL - 169490UL, 10000UL);
    CHECK(hz == 16949000UL);

    /* The counter wraps below zero. */
    hz = KiwiPLLInput(100000UL, (100000UL - 169490UL) & 0x3fffffffUL,
        10000UL);
    CHECK(hz == 16949000UL);

    /* A longer sleep than asked for still measures the same clock. */
    hz = KiwiPLLInput(900000UL, 900000UL - 338980UL, 20000UL);
    CHECK(hz == 16949000UL);
    hz = KiwiPLLInput(900000UL, 900000UL - 254235UL, 15000UL);
    CHECK(hz > 16900000UL && hz < 16960000UL);

    CHECK(KiwiPLLInput(1000UL, 0, 0) == 0);
    /* A result too large for 32 bits is not a clock. */
    CHECK(KiwiPLLInput(0x3fffffffUL, 0, 1) == 0);
}

static void
expect_pll(unsigned long input, unsigned int limit, unsigned int wantF,
    unsigned int wantR)
{
    unsigned int f;
    unsigned int r;

    f = r = 0xdead;
    if (!KiwiPLLControl(input, limit, &f, &r) || f != wantF || r != wantR) {
        printf("FAIL pll input=%lu limit=%u: got F=%u R=%u, want F=%u R=%u\n",
            input, limit, f, r, wantF, wantR);
        failures++;
    }
}

static void
test_pll_control(void)
{
    unsigned int f;
    unsigned int r;

    /* Half a 33 MHz PCI clock, as Linux expects to see. */
    expect_pll(16949000UL, 6, 115, 13);
    expect_pll(16949000UL, 5, 86, 13);
    /* The full 33 MHz clock. */
    expect_pll(33000000UL, 6, 58, 13);
    expect_pll(33000000UL, 5, 43, 13);
    /* Slow inputs reach the other R values. */
    expect_pll(10000000UL, 5, 98, 8);
    expect_pll(8000000UL, 5, 123, 8);
    expect_pll(7000000UL, 5, 112, 6);
    expect_pll(8000000UL, 6, 31, 0);
    expect_pll(5000000UL, 6, 51, 0);
    expect_pll(70000000UL, 6, 26, 13);
    /* Either side of each R threshold (ratios 8599/8600, 12899/12901,
       16097/16100); F stays in range at the top of each band. */
    expect_pll(11628000UL, 5, 126, 13);
    expect_pll(11627000UL, 5, 84, 8);
    expect_pll(7752000UL, 5, 126, 8);
    expect_pll(7751000UL, 5, 101, 6);
    expect_pll(6212000UL, 5, 126, 6);
    expect_pll(6211000UL, 5, 30, 0);

    f = r = 7;
    CHECK(!KiwiPLLControl(4999999UL, 6, &f, &r));
    CHECK(!KiwiPLLControl(70000001UL, 6, &f, &r));
    CHECK(!KiwiPLLControl(0, 6, &f, &r));
    CHECK(!KiwiPLLControl(16949000UL, 2, &f, &r));
    CHECK(f == 7 && r == 7);
    CHECK(!KiwiPLLControl(16949000UL, 6, 0, &r));
    CHECK(!KiwiPLLControl(16949000UL, 6, &f, 0));
}

static int
expect_writes(unsigned int limit, unsigned int drive, unsigned int pio,
    KiwiDMAType type, unsigned int mode, const unsigned char *want,
    int wantCount)
{
    KiwiRegisterWrite writes[KIWI_MAX_TIMING_WRITES];
    int count;
    int i;

    memset(writes, 0, sizeof(writes));
    count = KiwiTimingWrites(limit, drive, pio, type, mode, writes);
    if (count != wantCount) {
        printf("FAIL writes limit=%u drive=%u pio=%u type=%d mode=%u: "
            "count %d, want %d\n", limit, drive, pio, (int)type, mode,
            count, wantCount);
        failures++;
        return 0;
    }
    for (i = 0; i < count; i++) {
        if (writes[i].index != want[3 * i] ||
            writes[i].clear != want[3 * i + 1] ||
            writes[i].set != want[3 * i + 2]) {
            printf("FAIL writes limit=%u drive=%u pio=%u type=%d mode=%u: "
                "write %d is %02x/%02x/%02x, want %02x/%02x/%02x\n",
                limit, drive, pio, (int)type, mode, i, writes[i].index,
                writes[i].clear, writes[i].set, want[3 * i],
                want[3 * i + 1], want[3 * i + 2]);
            failures++;
            return 0;
        }
    }
    return 1;
}

static void
test_timing_133(void)
{
    static const unsigned char pio[5][9] = {
        { 0x0c, 0xff, 0xfb, 0x0d, 0xff, 0x2b, 0x13, 0xff, 0xac },
        { 0x0c, 0xff, 0x46, 0x0d, 0xff, 0x29, 0x13, 0xff, 0xa4 },
        { 0x0c, 0xff, 0x23, 0x0d, 0xff, 0x26, 0x13, 0xff, 0x64 },
        { 0x0c, 0xff, 0x27, 0x0d, 0xff, 0x0d, 0x13, 0xff, 0x35 },
        { 0x0c, 0xff, 0x23, 0x0d, 0xff, 0x09, 0x13, 0xff, 0x25 }
    };
    static const unsigned char mw[3][6] = {
        { 0x0e, 0xff, 0xdf, 0x0f, 0xff, 0x5f },
        { 0x0e, 0xff, 0x6b, 0x0f, 0xff, 0x27 },
        { 0x0e, 0xff, 0x69, 0x0f, 0xff, 0x25 }
    };
    static const unsigned char ultra[7][9] = {
        { 0x10, 0xff, 0x4a, 0x11, 0xff, 0x0f, 0x12, 0xff, 0xd5 },
        { 0x10, 0xff, 0x3a, 0x11, 0xff, 0x0a, 0x12, 0xff, 0xd0 },
        { 0x10, 0xff, 0x2a, 0x11, 0xff, 0x07, 0x12, 0xff, 0xcd },
        { 0x10, 0xff, 0x1a, 0x11, 0xff, 0x05, 0x12, 0xff, 0xcd },
        { 0x10, 0xff, 0x1a, 0x11, 0xff, 0x03, 0x12, 0xff, 0xcd },
        { 0x10, 0xff, 0x1a, 0x11, 0xff, 0x02, 0x12, 0xff, 0xcb },
        { 0x10, 0xff, 0x1a, 0x11, 0xff, 0x01, 0x12, 0xff, 0xcb }
    };
    static const unsigned char slave[18] = {
        0x14, 0xff, 0x23, 0x15, 0xff, 0x09, 0x1b, 0xff, 0x25,
        0x18, 0xff, 0x1a, 0x19, 0xff, 0x01, 0x1a, 0xff, 0xcb
    };
    unsigned char want[18];
    unsigned int m;

    for (m = 0; m < 5; m++)
        expect_writes(6, 0, m, kKiwiDMANone, 0, pio[m], 3);
    for (m = 0; m < 3; m++) {
        memcpy(want, pio[4], 9);
        memcpy(want + 9, mw[m], 6);
        expect_writes(6, 0, 4, kKiwiDMAMultiword, m, want, 5);
    }
    for (m = 0; m < 7; m++) {
        memcpy(want, pio[3], 9);
        memcpy(want + 9, ultra[m], 9);
        expect_writes(6, 0, 3, kKiwiDMAUltra, m, want, 6);
    }

    /* The slave's registers sit 8 above the master's. */
    expect_writes(6, 1, 4, kKiwiDMAUltra, 6, slave, 6);
}

static void
test_timing_100(void)
{
    static const unsigned char thold[3] = { 0x10, 0x80, 0x00 };
    static const unsigned char tholdSlave[3] = { 0x18, 0x80, 0x00 };
    unsigned int m;

    /* The chip times itself at 100 MHz, bar Ultra DMA 2's hold time. */
    for (m = 0; m < 5; m++)
        expect_writes(5, 0, m, kKiwiDMANone, 0, 0, 0);
    for (m = 0; m < 3; m++)
        expect_writes(5, 0, 4, kKiwiDMAMultiword, m, 0, 0);
    for (m = 0; m < 6; m++) {
        if (m == 2)
            expect_writes(5, 0, 4, kKiwiDMAUltra, m, thold, 1);
        else
            expect_writes(5, 0, 4, kKiwiDMAUltra, m, 0, 0);
    }
    expect_writes(5, 1, 4, kKiwiDMAUltra, 2, tholdSlave, 1);
}

static void
test_timing_invalid(void)
{
    KiwiRegisterWrite writes[KIWI_MAX_TIMING_WRITES];

    CHECK(KiwiTimingWrites(6, 0, 5, kKiwiDMANone, 0, writes) == -1);
    CHECK(KiwiTimingWrites(6, 0, 4, kKiwiDMAMultiword, 3, writes) == -1);
    CHECK(KiwiTimingWrites(6, 0, 4, kKiwiDMAUltra, 7, writes) == -1);
    CHECK(KiwiTimingWrites(5, 0, 4, kKiwiDMAUltra, 6, writes) == -1);
    CHECK(KiwiTimingWrites(6, 2, 4, kKiwiDMANone, 0, writes) == -1);
    CHECK(KiwiTimingWrites(6, 0, 4, (KiwiDMAType)9, 0, writes) == -1);
    CHECK(KiwiTimingWrites(2, 0, 4, kKiwiDMANone, 0, writes) == -1);
    CHECK(KiwiTimingWrites(0, 0, 4, kKiwiDMANone, 0, writes) == -1);
    CHECK(KiwiTimingWrites(6, 0, 4, kKiwiDMANone, 0, 0) == -1);
}

static void
test_channel_path(void)
{
    static const char named0[] = "/ata-6@0/@0:9";
    static const char named1[] = "/ata-6@1/@0:9";
    static const char bare1[] = "/@1/@0";
    static const char disk[] = "/@0:9";
    static const char noUnit[] = "/ata-6/@0:9";
    static const char oddUnit[] = "/ata-6@0,1/@0";

    CHECK(KiwiSkipChannel(named0, 0) == named0 + 8);
    CHECK(KiwiSkipChannel(named0, 1) == 0);
    CHECK(KiwiSkipChannel(named1, 1) == named1 + 8);
    CHECK(KiwiSkipChannel(named1, 0) == 0);
    CHECK(KiwiSkipChannel(bare1, 1) == bare1 + 3);
    CHECK(KiwiSkipChannel(bare1, 0) == 0);

    /* Shapes that do not name a channel are left for the disk to parse. */
    CHECK(KiwiSkipChannel(disk, 0) == disk);
    CHECK(KiwiSkipChannel(disk, 1) == disk);
    CHECK(KiwiSkipChannel(noUnit, 1) == noUnit);
    CHECK(KiwiSkipChannel(oddUnit, 1) == oddUnit);
    CHECK(KiwiSkipChannel(":9", 0)[0] == ':');
    CHECK(KiwiSkipChannel("", 1)[0] == '\0');
    CHECK(KiwiSkipChannel(0, 0) == 0);
}

int
main(void)
{
    test_parts();
    test_compatible();
    test_bars();
    test_counter();
    test_pll_input();
    test_pll_control();
    test_timing_133();
    test_timing_100();
    test_timing_invalid();
    test_channel_path();

    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("kiwi_ata_test: all tests passed\n");
    return 0;
}
