/*
 * KiwiATA.c - Kiwi (Promise PDC2027x) part table, PLL arithmetic and
 * 133 MHz timing tables.
 */

#include "KiwiATA.h"

static const struct {
    unsigned short	device;
    unsigned short	limit;
} kiwi_parts[] = {
    { 0x4d68, 5 },	/* PDC20268 */
    { 0x6268, 5 },	/* PDC20270 */
    { 0x4d69, 6 },	/* PDC20269 */
    { 0x6269, 6 },	/* PDC20271 */
    { 0x1275, 6 },	/* PDC20275 */
    { 0x5275, 6 },	/* PDC20276 */
    { 0x7275, 6 }	/* PDC20277 */
};

/* Indexed timing registers of the master; the slave's are 8 above. */
#define KIWI_TIMING_PIO_A	0x0c
#define KIWI_TIMING_PIO_B	0x0d
#define KIWI_TIMING_PIO_C	0x13
#define KIWI_TIMING_MW_A	0x0e
#define KIWI_TIMING_MW_B	0x0f
#define KIWI_TIMING_ULTRA_A	0x10
#define KIWI_TIMING_ULTRA_B	0x11
#define KIWI_TIMING_ULTRA_C	0x12
#define KIWI_TIMING_SLAVE	0x08
#define KIWI_ULTRA_THOLD	0x80	/* in KIWI_TIMING_ULTRA_A */

static const unsigned char kiwi_pio[5][3] = {
    { 0xfb, 0x2b, 0xac },	/* PIO 0 */
    { 0x46, 0x29, 0xa4 },	/* PIO 1 */
    { 0x23, 0x26, 0x64 },	/* PIO 2 */
    { 0x27, 0x0d, 0x35 },	/* PIO 3, IORDY */
    { 0x23, 0x09, 0x25 }	/* PIO 4, IORDY */
};

static const unsigned char kiwi_mwdma[3][2] = {
    { 0xdf, 0x5f },		/* multiword DMA 0 */
    { 0x6b, 0x27 },		/* multiword DMA 1 */
    { 0x69, 0x25 }		/* multiword DMA 2 */
};

static const unsigned char kiwi_ultra[7][3] = {
    { 0x4a, 0x0f, 0xd5 },	/* Ultra DMA 0 */
    { 0x3a, 0x0a, 0xd0 },	/* Ultra DMA 1 */
    { 0x2a, 0x07, 0xcd },	/* Ultra DMA 2 */
    { 0x1a, 0x05, 0xcd },	/* Ultra DMA 3 */
    { 0x1a, 0x03, 0xcd },	/* Ultra DMA 4 */
    { 0x1a, 0x02, 0xcb },	/* Ultra DMA 5 */
    { 0x1a, 0x01, 0xcb }	/* Ultra DMA 6 */
};

#define KIWI_COUNT(table)	(sizeof(table) / sizeof((table)[0]))

#define KIWI_COUNTER_MASK	0x3fffffffUL
#define KIWI_COUNTER_HIGH	0x3fff8000UL

unsigned int
KiwiUltraLimit(unsigned int pciID)
{
    unsigned int i;

    if ((pciID & 0xffff) != KIWI_VENDOR_PROMISE)
        return 0;
    for (i = 0; i < KIWI_COUNT(kiwi_parts); i++)
        if (kiwi_parts[i].device == (pciID >> 16))
            return kiwi_parts[i].limit;
    return 0;
}

unsigned int
KiwiMaxUltraMode(unsigned int limit, unsigned int cable)
{
    if (cable & KIWI_CABLE_40_WIRE)
        return KIWI_ULTRA_40_WIRE;
    return limit;
}

int
KiwiIsCompatible(const char *compatible, unsigned int length)
{
    static const char name[] = "kiwi-root";
    unsigned int start;
    unsigned int end;
    unsigned int i;

    if (compatible == 0)
        return 0;
    for (start = 0; start < length; start = end + 1) {
        for (end = start; end < length && compatible[end] != 0; end++)
            ;
        if (end - start != sizeof(name) - 1)
            continue;
        for (i = 0; i < sizeof(name) - 1; i++)
            if (compatible[start + i] != name[i])
                break;
        if (i == sizeof(name) - 1)
            return 1;
    }
    return 0;
}

int
KiwiFindBARs(const unsigned int *cells, unsigned int entries,
    unsigned int entry[KIWI_BAR_COUNT])
{
    unsigned int found[KIWI_BAR_COUNT];
    unsigned int seen;
    unsigned int hi;
    unsigned int reg;
    unsigned int bar;
    unsigned int i;

    if (cells == 0 || entry == 0)
        return 0;
    seen = 0;
    for (i = 0; i < entries; i++) {
        hi = cells[i * KIWI_ADDRESS_CELLS];
        reg = hi & 0xff;
        if (reg < 0x10 || (reg & 3) != 0)
            continue;
        bar = (reg - 0x10) / 4;
        if (bar >= KIWI_BAR_COUNT || (seen & (1U << bar)) != 0)
            continue;
        if (((hi >> 24) & 3) != 1)		/* I/O space */
            return 0;
        found[bar] = i;
        seen |= 1U << bar;
    }
    if (seen != (1U << KIWI_BAR_COUNT) - 1)
        return 0;
    for (i = 0; i < KIWI_BAR_COUNT; i++)
        entry[i] = found[i];
    return 1;
}

unsigned long
KiwiCounter(unsigned int primaryLow, unsigned int primaryHigh,
    unsigned int secondaryLow, unsigned int secondaryHigh)
{
    return ((unsigned long)(secondaryHigh & 0x7f) << 23) |
        ((unsigned long)(secondaryLow & 0xff) << 15) |
        ((unsigned long)(primaryHigh & 0x7f) << 8) |
        (unsigned long)(primaryLow & 0xff);
}

int
KiwiCounterSettled(unsigned long previous, unsigned long current)
{
    /* The counter runs down; its high bytes must not move between reads. */
    return ((previous ^ current) & KIWI_COUNTER_HIGH) == 0 &&
        current <= previous;
}

unsigned long
KiwiPLLInput(unsigned long start, unsigned long end,
    unsigned long elapsedMicroseconds)
{
    unsigned long counts;
    unsigned long scale;

    if (elapsedMicroseconds == 0)
        return 0;
    /* Linux's arithmetic: stays in 32 bits for any sane clock. */
    counts = ((start - end) & KIWI_COUNTER_MASK) / 10;
    scale = 10000000UL / elapsedMicroseconds;
    if (scale != 0 && counts > 0xffffffffUL / scale)
        return 0;
    return counts * scale;
}

int
KiwiPLLControl(unsigned long input, unsigned int limit, unsigned int *f,
    unsigned int *r)
{
    unsigned long output;
    unsigned long ratio;
    unsigned long product;
    unsigned int divider;

    if (f == 0 || r == 0 || input < 5000000UL || input > 70000000UL)
        return 0;
    if (limit == 6)
        output = 133333333UL;
    else if (limit == 5)
        output = 100000000UL;
    else
        return 0;

    /* output = input * (F + 2) / (R + 2); ratio is output / input * 1000. */
    ratio = output / (input / 1000);
    if (ratio < 8600)
        divider = 13;
    else if (ratio < 12900)
        divider = 8;
    else if (ratio < 16100)
        divider = 6;
    else if (ratio < 64000)
        divider = 0;
    else
        return 0;

    product = ratio * (divider + 2) / 1000;
    if (product < 2 || product - 2 > 127)
        return 0;
    *f = (unsigned int)(product - 2);
    *r = divider;
    return 1;
}

static void
kiwi_write(KiwiRegisterWrite *write, unsigned int index, unsigned int clear,
    unsigned int set)
{
    write->index = (unsigned char)index;
    write->clear = (unsigned char)clear;
    write->set = (unsigned char)set;
}

int
KiwiTimingWrites(unsigned int limit, unsigned int drive,
    unsigned int pioMode, KiwiDMAType dmaType, unsigned int dmaMode,
    KiwiRegisterWrite writes[KIWI_MAX_TIMING_WRITES])
{
    unsigned int base;
    int count;

    if (writes == 0 || drive > 1 || (limit != 5 && limit != 6) ||
        pioMode >= KIWI_COUNT(kiwi_pio))
        return -1;
    switch (dmaType) {
    case kKiwiDMANone:
        break;
    case kKiwiDMAMultiword:
        if (dmaMode >= KIWI_COUNT(kiwi_mwdma))
            return -1;
        break;
    case kKiwiDMAUltra:
        if (dmaMode > limit)
            return -1;
        break;
    default:
        return -1;
    }

    base = drive ? KIWI_TIMING_SLAVE : 0;
    count = 0;

    /* At 100 MHz the chip times itself from SET FEATURES. */
    if (limit == 5) {
        if (dmaType == kKiwiDMAUltra && dmaMode == 2)
            kiwi_write(&writes[count++], base + KIWI_TIMING_ULTRA_A,
                KIWI_ULTRA_THOLD, 0);
        return count;
    }

    kiwi_write(&writes[count++], base + KIWI_TIMING_PIO_A, 0xff,
        kiwi_pio[pioMode][0]);
    kiwi_write(&writes[count++], base + KIWI_TIMING_PIO_B, 0xff,
        kiwi_pio[pioMode][1]);
    kiwi_write(&writes[count++], base + KIWI_TIMING_PIO_C, 0xff,
        kiwi_pio[pioMode][2]);
    if (dmaType == kKiwiDMAMultiword) {
        kiwi_write(&writes[count++], base + KIWI_TIMING_MW_A, 0xff,
            kiwi_mwdma[dmaMode][0]);
        kiwi_write(&writes[count++], base + KIWI_TIMING_MW_B, 0xff,
            kiwi_mwdma[dmaMode][1]);
    } else if (dmaType == kKiwiDMAUltra) {
        kiwi_write(&writes[count++], base + KIWI_TIMING_ULTRA_A, 0xff,
            kiwi_ultra[dmaMode][0]);
        kiwi_write(&writes[count++], base + KIWI_TIMING_ULTRA_B, 0xff,
            kiwi_ultra[dmaMode][1]);
        kiwi_write(&writes[count++], base + KIWI_TIMING_ULTRA_C, 0xff,
            kiwi_ultra[dmaMode][2]);
    }
    return count;
}

const char *
KiwiSkipChannel(const char *tail, unsigned int channel)
{
    const char *end;
    const char *p;
    unsigned int unit;
    unsigned int digit;

    if (tail == 0 || tail[0] != '/')
        return tail;
    for (end = tail + 1; *end != 0 && *end != '/'; end++)
        ;
    if (*end != '/')
        return tail;			/* the disk's own component */
    for (p = tail + 1; p < end && *p != '@'; p++)
        ;
    if (p == end || p + 1 == end)
        return tail;
    unit = 0;
    for (p++; p < end; p++) {
        if (*p >= '0' && *p <= '9')
            digit = *p - '0';
        else if (*p >= 'a' && *p <= 'f')
            digit = *p - 'a' + 10;
        else if (*p >= 'A' && *p <= 'F')
            digit = *p - 'A' + 10;
        else
            return tail;
        if (unit > 0xfffffffU)
            return tail;
        unit = unit * 16 + digit;
    }
    return unit == channel ? end : 0;
}
