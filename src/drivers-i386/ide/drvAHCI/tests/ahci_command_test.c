#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "AHCICommand.h"

static int failures;

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                    \
                    __FILE__, __LINE__, #expression);                         \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void check_fis(const unsigned char actual[20],
                      const unsigned char expected[20])
{
    CHECK(memcmp(actual, expected, 20) == 0);
}

static void test_command_layouts(void)
{
    CHECK(sizeof(AHCICommandHeader) == 32);
    CHECK(sizeof(AHCIPRDTEntry) == 16);
}

static void test_identify_fis(void)
{
    static const unsigned char expected[20] = {
        0x27, 0x80, 0xec, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    unsigned char fis[20];

    memset(fis, 0xff, sizeof(fis));
    AHCIBuildIdentifyFIS(fis, 0);

    CHECK(fis[0] == 0x27 && fis[1] == 0x80);
    CHECK(fis[2] == 0xec && fis[15] == 0x00);
    check_fis(fis, expected);
}

static void test_identify_packet_fis(void)
{
    static const unsigned char expected[20] = {
        0x27, 0x80, 0xa1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    unsigned char fis[20];

    memset(fis, 0xff, sizeof(fis));
    AHCIBuildIdentifyFIS(fis, 1);

    check_fis(fis, expected);
}

static void test_packet_fis(void)
{
    static const unsigned char expected[20] = {
        0x27, 0x80, 0xa0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    unsigned char fis[20];

    memset(fis, 0xff, sizeof(fis));
    AHCIBuildPacketFIS(fis);

    CHECK(fis[0] == 0x27 && fis[1] == 0x80);
    CHECK(fis[2] == 0xa0 && fis[15] == 0x00);
    check_fis(fis, expected);
}

static void test_lba28_read_dma_fis(void)
{
    static const unsigned char expected[20] = {
        0x27, 0x80, 0xc8, 0x00, 0x67, 0x45, 0x23, 0x41, 0x00, 0x00,
        0x00, 0x00, 0x23, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    unsigned char fis[20];

    CHECK(AHCIBuildDMAFIS(fis, 0x01234567, 0x23, 0, 0) == 0);
    check_fis(fis, expected);
}

static void test_lba48_write_dma_fis(void)
{
    static const unsigned char expected[20] = {
        0x27, 0x80, 0x35, 0x00, 0xef, 0xcd, 0xab, 0x40, 0x89, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    unsigned char fis[20];

    CHECK(AHCIBuildDMAFIS(fis, 0x89abcdef, 256, 1, 1) == 0);
    check_fis(fis, expected);
}

static void test_invalid_dma_fis(void)
{
    unsigned char fis[20];

    CHECK(AHCIBuildDMAFIS(fis, 0, 0, 0, 0) != 0);
    CHECK(AHCIBuildDMAFIS(fis, 0, 257, 0, 0) != 0);
    CHECK(AHCIBuildDMAFIS(fis, 0x0fffffff, 2, 0, 0) != 0);
    CHECK(AHCIBuildDMAFIS(fis, 0x10000000, 1, 0, 0) != 0);
    CHECK(AHCIBuildDMAFIS(fis, 0x0fffffff, 1, 0, 0) == 0);
}

static void test_flush_fis(void)
{
    static const unsigned char flush[20] = {
        0x27, 0x80, 0xe7, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    static const unsigned char flushExt[20] = {
        0x27, 0x80, 0xea, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    unsigned char fis[20];

    AHCIBuildFlushFIS(fis, 0);
    check_fis(fis, flush);
    AHCIBuildFlushFIS(fis, 1);
    check_fis(fis, flushExt);
}

int main(void)
{
    test_command_layouts();
    test_identify_fis();
    test_identify_packet_fis();
    test_packet_fis();
    test_lba28_read_dma_fis();
    test_lba48_write_dma_fis();
    test_invalid_dma_fis();
    test_flush_fis();

    if (failures != 0) {
        fprintf(stderr, "ahci_command_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("ahci_command_test: all tests passed\n");
    return EXIT_SUCCESS;
}
