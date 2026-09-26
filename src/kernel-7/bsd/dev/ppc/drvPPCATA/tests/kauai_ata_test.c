#include <stdio.h>
#include <string.h>

#include "../KauaiATA.h"

static int failures;

#define CHECK(x) do { \
    if (!(x)) { \
        printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #x); \
        failures++; \
    } \
} while (0)

static void
expect_words(unsigned int pio, KauaiDMAType type, unsigned int mode,
    unsigned int wantPio, unsigned int wantUltra)
{
    unsigned int pioConfig;
    unsigned int ultraConfig;

    pioConfig = ultraConfig = 0xdeadbeefU;
    if (!KauaiTimingWords(pio, type, mode, &pioConfig, &ultraConfig) ||
        pioConfig != wantPio || ultraConfig != wantUltra) {
        printf("FAIL words pio=%u type=%d mode=%u: got %08x %08x, "
            "want %08x %08x\n", pio, (int)type, mode, pioConfig,
            ultraConfig, wantPio, wantUltra);
        failures++;
    }
}

static void
test_timing_words(void)
{
    unsigned int pioConfig;
    unsigned int ultraConfig;

    /* PIO alone is timed with multiword DMA 0, as Linux's default. */
    expect_words(0, kKauaiDMANone, 0, 0x08618a92U, 0);
    expect_words(1, kKauaiDMANone, 0, 0x0861860fU, 0);
    expect_words(2, kKauaiDMANone, 0, 0x0861838bU, 0);
    expect_words(3, kKauaiDMANone, 0, 0x05618249U, 0);
    expect_words(4, kKauaiDMANone, 0, 0x04618148U, 0);

    expect_words(4, kKauaiDMAMultiword, 0, 0x04618148U, 0);
    expect_words(4, kKauaiDMAMultiword, 1, 0x04209148U, 0);
    expect_words(3, kKauaiDMAMultiword, 2, 0x05148249U, 0);

    /* Ultra DMA leaves the first register to PIO. */
    expect_words(4, kKauaiDMAUltra, 0, 0x04000148U, 0x000070c1U);
    expect_words(4, kKauaiDMAUltra, 1, 0x04000148U, 0x00005d81U);
    expect_words(4, kKauaiDMAUltra, 2, 0x04000148U, 0x00004a61U);
    expect_words(4, kKauaiDMAUltra, 3, 0x04000148U, 0x00003a51U);
    expect_words(4, kKauaiDMAUltra, 4, 0x04000148U, 0x00002a31U);
    expect_words(4, kKauaiDMAUltra, 5, 0x04000148U, 0x00002921U);

    pioConfig = ultraConfig = 7;
    CHECK(!KauaiTimingWords(5, kKauaiDMANone, 0, &pioConfig, &ultraConfig));
    CHECK(!KauaiTimingWords(4, kKauaiDMAMultiword, 3, &pioConfig,
        &ultraConfig));
    CHECK(!KauaiTimingWords(4, kKauaiDMAUltra, 6, &pioConfig, &ultraConfig));
    CHECK(!KauaiTimingWords(4, (KauaiDMAType)9, 0, &pioConfig,
        &ultraConfig));
    CHECK(pioConfig == 7 && ultraConfig == 7);
    CHECK(!KauaiTimingWords(0, kKauaiDMANone, 0, 0, &ultraConfig));
    CHECK(!KauaiTimingWords(0, kKauaiDMANone, 0, &pioConfig, 0));
}

static void
test_cable(void)
{
    static const char eighty[] = "80-conductor";
    static const char forty[] = "40-conductor";
    static const char cut[] = { '8', '0' };

    CHECK(KauaiMaxUltraMode(eighty, sizeof(eighty)) == 5);
    CHECK(KauaiMaxUltraMode(forty, sizeof(forty)) == 2);
    CHECK(KauaiMaxUltraMode(cut, sizeof(cut)) == 2);
    CHECK(KauaiMaxUltraMode(eighty, 2) == 2);
    CHECK(KauaiMaxUltraMode(0, 0) == 2);
}

static void
test_layout(void)
{
    /* Every register the driver touches lies inside the span it checks. */
    CHECK(KAUAI_DBDMA_OFFSET + 0x100 <= KAUAI_TASKFILE_OFFSET);
    CHECK(KAUAI_TASKFILE_OFFSET + 0x160 < KAUAI_REGISTER_SPAN);
    CHECK(KAUAI_TASKFILE_OFFSET + KAUAI_PIO_CONFIG_OFFSET + 4 <=
        KAUAI_REGISTER_SPAN);
    CHECK(KAUAI_REGISTER_SPAN == 0x2214);
}

int
main(void)
{
    test_timing_words();
    test_cable();
    test_layout();
    if (failures)
        return 1;
    printf("Kauai ATA tests passed\n");
    return 0;
}
