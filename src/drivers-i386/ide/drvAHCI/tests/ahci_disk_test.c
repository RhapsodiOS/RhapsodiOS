#include <limits.h>
#include <stdio.h>
#include <string.h>

#include "AHCIDiskLogic.h"

static int failures;

#define CHECK(expression) do {                                             \
    if (!(expression)) {                                                   \
        fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #expression); \
        ++failures;                                                        \
    }                                                                      \
} while (0)

static void put_string(unsigned short *words, unsigned int first,
                       unsigned int count, const char *text)
{
    unsigned int index;
    unsigned int length;
    unsigned char high;
    unsigned char low;

    length = (unsigned int)strlen(text);
    for (index = 0; index < count; ++index) {
        high = 2U * index < length ?
               (unsigned char)text[2U * index] : (unsigned char)' ';
        low = 2U * index + 1U < length ?
              (unsigned char)text[2U * index + 1U] : (unsigned char)' ';
        words[first + index] = (unsigned short)((high << 8) | low);
    }
}

static void base_identify(unsigned short words[256])
{
    memset(words, 0, 512U);
    words[49] = 1U << 9;
    words[60] = 0x5678U;
    words[61] = 0x0234U;
    put_string(words, 10U, 10U, "SN123");
    put_string(words, 23U, 4U, "FW1");
    put_string(words, 27U, 20U, "RhapsodiOS SATA Disk");
}

static void test_lba28_identify(void)
{
    unsigned short words[256];
    AHCIDiskIdentify result;

    base_identify(words);
    CHECK(AHCIDiskParseIdentify(words, &result));
    CHECK(result.capacity == 0x02345678U);
    CHECK(result.lba48 == 0);
    CHECK(strcmp(result.model, "RhapsodiOS SATA Disk") == 0);
    CHECK(strcmp(result.serial, "SN123") == 0);
    CHECK(strcmp(result.firmware, "FW1") == 0);
}

static void test_lba28_capacity_is_capped(void)
{
    unsigned short words[256];
    AHCIDiskIdentify result;

    base_identify(words);
    words[60] = 0xffffU;
    words[61] = 0xffffU;
    CHECK(AHCIDiskParseIdentify(words, &result));
    CHECK(result.capacity == AHCI_DISK_LBA28_LIMIT);
    CHECK(result.lba48 == 0);
}

static void test_lba48_capacity_is_capped(void)
{
    unsigned short words[256];
    AHCIDiskIdentify result;

    base_identify(words);
    words[83] = 1U << 10;
    words[100] = 1U;
    words[101] = 0U;
    words[102] = 1U;
    words[103] = 0U;
    CHECK(AHCIDiskParseIdentify(words, &result));
    CHECK(result.capacity == UINT_MAX);
    CHECK(result.lba48 == 1);
}

static void test_unsupported_sector_sizes_and_empty_media(void)
{
    unsigned short words[256];
    AHCIDiskIdentify result;

    base_identify(words);
    words[106] = (1U << 14) | (1U << 12);
    words[117] = 2048U;
    CHECK(!AHCIDiskParseIdentify(words, &result));

    base_identify(words);
    words[60] = 0U;
    words[61] = 0U;
    CHECK(!AHCIDiskParseIdentify(words, &result));
}

static void test_request_boundaries(void)
{
    unsigned int blocks;

    CHECK(!AHCIDiskClipRequest(100U, 0U, 0U, &blocks));
    CHECK(!AHCIDiskClipRequest(100U, 100U, 512U, &blocks));
    CHECK(!AHCIDiskClipRequest(100U, UINT_MAX, 1024U, &blocks));
    CHECK(!AHCIDiskClipRequest(100U, 0U, 513U, &blocks));
    CHECK(AHCIDiskClipRequest(UINT_MAX, UINT_MAX - 1U, 4096U,
                              &blocks));
    CHECK(blocks == 1U);
    CHECK(AHCIDiskClipRequest(AHCI_DISK_LBA28_LIMIT,
                              AHCI_DISK_LBA28_LIMIT - 1U,
                              1024U, &blocks));
    CHECK(blocks == 1U);
}

static void test_segment_and_command_selection(void)
{
    AHCIDiskSegment segment;

    CHECK(AHCIDiskPlanSegment(1U, 300U, 0, 0, 0U, 4096U,
                              &segment));
    CHECK(segment.blocks == 256U);
    CHECK(segment.bytes == 128U * 1024U);
    CHECK(segment.command == AHCI_ATA_READ_DMA);

    CHECK(!AHCIDiskPlanSegment(0x0fffffffU, 2U, 1, 0, 0U, 4096U,
                               &segment));
    CHECK(AHCIDiskPlanSegment(0x0fffffffU, 2U, 1, 1, 0U, 4096U,
                              &segment));
    CHECK(segment.blocks == 2U);
    CHECK(segment.command == AHCI_ATA_WRITE_DMA_EXT);

    CHECK(AHCIDiskPlanSegment(0x10000000U, 1U, 0, 1, 0U, 4096U,
                              &segment));
    CHECK(segment.command == AHCI_ATA_READ_DMA_EXT);

    CHECK(AHCIDiskPlanSegment(1U, 256U, 0, 0, 4095U, 4096U,
                              &segment));
    CHECK(segment.blocks == 248U);
    CHECK(segment.bytes == 248U * 512U);
}

static void test_reidentify_requires_same_media(void)
{
    unsigned short words[256];
    AHCIDiskIdentify first;
    AHCIDiskIdentify second;

    base_identify(words);
    CHECK(AHCIDiskParseIdentify(words, &first));
    CHECK(AHCIDiskParseIdentify(words, &second));
    CHECK(AHCIDiskIdentifyMatches(&first, &second));
    put_string(words, 10U, 10U, "DIFFERENT");
    CHECK(AHCIDiskParseIdentify(words, &second));
    CHECK(!AHCIDiskIdentifyMatches(&first, &second));
}

int main(void)
{
    test_lba28_identify();
    test_lba28_capacity_is_capped();
    test_lba48_capacity_is_capped();
    test_unsupported_sector_sizes_and_empty_media();
    test_request_boundaries();
    test_segment_and_command_selection();
    test_reidentify_requires_same_media();
    if (failures != 0)
        return 1;
    puts("ahci disk tests passed");
    return 0;
}
