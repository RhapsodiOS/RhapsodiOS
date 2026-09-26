#include <stdio.h>
#include <string.h>

#include "../powermac/macrisc_discovery.h"

static int failures;

#define CHECK(x) do { \
    if (!(x)) { \
        printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #x); \
        failures++; \
    } \
} while (0)

static PEProperty
prop(const unsigned char *p, unsigned int n)
{
    PEProperty value;

    value.bytes = p;
    value.size = n;
    return value;
}

static void
platform(PEMacRISCPlatform *p)
{
    PEMacRISCPlatformInit(p);
    p->mpicSources = 64;
    p->interruptCells = 2;
}

static void
test_pairs(void)
{
    /* ata-3: device source 0x13 level, DMA source 0x0b edge. */
    static const unsigned char ata[] = {
        0, 0, 0, 0x13, 0, 0, 0, 1, 0, 0, 0, 0x0b, 0, 0, 0, 0
    };
    static const unsigned char last[] = { 0, 0, 0, 0x3f, 0, 0, 0, 3 };
    PEMacRISCPlatform p;
    unsigned int out[4];

    platform(&p);
    memset(out, 0xff, sizeof(out));
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(ata, sizeof(ata)), out, 4) == 2);
    CHECK(out[0] == 0x13 && out[1] == 0x0b);
    CHECK(out[2] == 0xffffffffU);
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(last, sizeof(last)), out, 1) == 1);
    CHECK(out[0] == 0x3f);
}

static void
test_rejects(void)
{
    static const unsigned char three[] = {
        0, 0, 0, 0x16, 0, 0, 0, 1, 0, 0, 0, 0x04, 0, 0, 0, 0,
        0, 0, 0, 0x05, 0, 0, 0, 0
    };
    static const unsigned char high[] = {
        0, 0, 0, 0x13, 0, 0, 0, 1, 0, 0, 0, 0x40, 0, 0, 0, 0
    };
    static const unsigned char huge[] = { 0x80, 0, 0, 0x13, 0, 0, 0, 1 };
    static const unsigned char sense[] = { 0, 0, 0, 0x13, 0, 0, 0, 4 };
    PEMacRISCPlatform p;
    unsigned int out[3];

    platform(&p);
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(three, sizeof(three)), out, 3)
        == 3);
    /* More pairs than the caller's slot holds. */
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(three, sizeof(three)), out, 2)
        == 0);
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(three, sizeof(three)), out, 0)
        == 0);
    /* Odd cell counts and partial cells are not two-cell specifiers. */
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(three, 4), out, 3) == 0);
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(three, 12), out, 3) == 0);
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(three, 7), out, 3) == 0);
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(three, 0), out, 3) == 0);
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(0, 0), out, 3) == 0);
    /* Sources at or above 64 and unknown senses. */
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(high, sizeof(high)), out, 3) == 0);
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(huge, sizeof(huge)), out, 3) == 0);
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(sense, sizeof(sense)), out, 3)
        == 0);
    /* A one-cell MPIC means the same bytes are four sources, not pairs. */
    p.interruptCells = 1;
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(high, sizeof(high)), out, 3) == 0);
    p.interruptCells = 2;
    CHECK(PEMacRISCAAPLInterrupts(0, prop(three, sizeof(three)), out, 3)
        == 0);
    CHECK(PEMacRISCAAPLInterrupts(&p, prop(three, sizeof(three)), 0, 3)
        == 0);
}

int
main(void)
{
    test_pairs();
    test_rejects();
    if (failures)
        return 1;
    printf("MacRISC interrupt tests passed\n");
    return 0;
}
