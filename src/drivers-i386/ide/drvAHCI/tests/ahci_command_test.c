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

static void test_packet_command(void)
{
    static const unsigned char testUnitReady[12] = {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    static const unsigned char read10[12] = {
        0x28, 0x00, 0x00, 0x00, 0x12, 0x34,
        0x00, 0x00, 0x01, 0x00, 0x00, 0x00
    };
    static const unsigned char command16[16] = {
        0x88, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f
    };
    unsigned char fis[20];
    unsigned char acmd[16];

    memset(fis, 0xff, sizeof(fis));
    memset(acmd, 0xff, sizeof(acmd));
    CHECK(AHCIBuildPacketCommand(fis, acmd, testUnitReady, 12,
                                 0, 0, 1) == 0);
    CHECK(fis[2] == 0xa0 && fis[3] == 0x00);
    CHECK(fis[5] == 0x00 && fis[6] == 0x00);
    CHECK(memcmp(acmd, testUnitReady, 12) == 0);
    CHECK(acmd[12] == 0 && acmd[15] == 0);

    memset(acmd, 0xff, sizeof(acmd));
    CHECK(AHCIBuildPacketCommand(fis, acmd, read10, 12,
                                 2048, 0, 1) == 0);
    CHECK(fis[3] == 0x05);
    CHECK(fis[5] == 0x00 && fis[6] == 0x08);
    CHECK(memcmp(acmd, read10, 12) == 0);
    CHECK(acmd[12] == 0 && acmd[15] == 0);

    CHECK(AHCIBuildPacketCommand(fis, acmd, read10, 12,
                                 2048, 0, 0) == 0);
    CHECK(fis[3] == 0x01);

    CHECK(AHCIBuildPacketCommand(fis, acmd, command16, 16,
                                 4096, 1, 1) == 0);
    CHECK(fis[3] == 0x01);
    CHECK(fis[5] == 0x00 && fis[6] == 0x10);
    CHECK(memcmp(acmd, command16, 16) == 0);

    CHECK(AHCIBuildPacketCommand(fis, acmd, read10, 10,
                                 2048, 0, 1) != 0);
    CHECK(AHCIBuildPacketCommand(fis, acmd, read10, 12,
                                 131073, 0, 1) != 0);
}

static void test_atapi_autosense_decisions(void)
{
    CHECK(AHCIATAPIShouldRequestSense(0x28, 0) == 1);
    CHECK(AHCIATAPIShouldRequestSense(0x28, 1) == 0);
    CHECK(AHCIATAPIShouldRequestSense(0x03, 0) == 0);
    CHECK(AHCIATAPISenseDataValid(1, 14) == 1);
    CHECK(AHCIATAPISenseDataValid(1, 13) == 0);
    CHECK(AHCIATAPISenseDataValid(0, 14) == 0);
}

static void test_lba28_read_dma_fis(void)
{
    static const unsigned char expected[20] = {
        0x27, 0x80, 0xc8, 0x00, 0x67, 0x45, 0x23, 0x41, 0x00, 0x00,
        0x00, 0x00, 0x23, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    unsigned char fis[20];

    memset(fis, 0xff, sizeof(fis));
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

    memset(fis, 0xff, sizeof(fis));
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

    memset(fis, 0xff, sizeof(fis));
    AHCIBuildFlushFIS(fis, 0);
    check_fis(fis, flush);
    memset(fis, 0xff, sizeof(fis));
    AHCIBuildFlushFIS(fis, 1);
    check_fis(fis, flushExt);
}

static void test_identify_capacity(void)
{
    unsigned short id[256];
    AHCICapacity capacity;

    memset(id, 0, sizeof(id));
    id[49] = 0x0200;
    id[60] = 0xffff;
    id[61] = 0x0fff;
    CHECK(AHCIParseIdentify(id, &capacity) == 0);
    CHECK(capacity.sectors == 0x0fffffffU);
    CHECK(capacity.lba48 == 0 && capacity.clamped == 0);
    CHECK(capacity.logicalSectorIs512 == 1);

    id[86] = 0x0400;
    CHECK(AHCIParseIdentify(id, &capacity) == 0);
    CHECK(capacity.sectors == 0x0fffffffU && capacity.lba48 == 1);
    id[100] = 0x0001;
    id[101] = 0x0002;
    CHECK(AHCIParseIdentify(id, &capacity) == 0);
    CHECK(capacity.sectors == 0x00020001U);
    CHECK(capacity.lba48 == 1 && capacity.clamped == 0);

    id[102] = 1;
    CHECK(AHCIParseIdentify(id, &capacity) == 0);
    CHECK(capacity.sectors == 0xffffffffU && capacity.clamped == 1);

    id[102] = 0;
    id[106] = 0x5000;
    id[117] = 255;
    id[118] = 0;
    CHECK(AHCIParseIdentify(id, &capacity) != 0);
    id[117] = 256;
    CHECK(AHCIParseIdentify(id, &capacity) == 0);

    id[49] = 0;
    CHECK(AHCIParseIdentify(id, &capacity) != 0);
}

static void test_dma_command_selection(void)
{
    unsigned char command;
    unsigned char useLba48;

    CHECK(AHCISelectDMACommand(0x0fffffffU, 1, 0, 0,
                               &command, &useLba48) == 0);
    CHECK(command == 0xc8 && useLba48 == 0);
    CHECK(AHCISelectDMACommand(0, 256, 1, 0, &command, &useLba48) == 0);
    CHECK(command == 0xca && useLba48 == 0);
    CHECK(AHCISelectDMACommand(0x0fffffffU, 2, 0, 1,
                               &command, &useLba48) == 0);
    CHECK(command == 0x25 && useLba48 == 1);
    CHECK(AHCISelectDMACommand(0, 1, 1, 1, &command, &useLba48) == 0);
    CHECK(command == 0xca && useLba48 == 0);
    CHECK(AHCISelectDMACommand(0x0fffffffU, 2, 1, 1,
                               &command, &useLba48) == 0);
    CHECK(command == 0x35 && useLba48 == 1);
    CHECK(AHCISelectDMACommand(0x0fffffffU, 2, 0, 0,
                               &command, &useLba48) != 0);
    CHECK(AHCISelectDMACommand(0, 0, 0, 0, &command, &useLba48) != 0);
    CHECK(AHCISelectDMACommand(0, 257, 0, 1, &command, &useLba48) != 0);
    CHECK(AHCISelectDMACommand(0xffffffffU, 2, 0, 1,
                               &command, &useLba48) != 0);
}

static void test_prdt_builder(void)
{
    AHCIPRDTEntry prd[32];
    AHCISegment seg[33];
    unsigned int index;

    seg[0].address = 0x00100000;
    seg[0].length = 4096;
    seg[1].address = 0x00101000;
    seg[1].length = 4096;
    CHECK(AHCIBuildPRDT(prd, 32, seg, 2, 8192) == 1);
    CHECK(prd[0].dba == 0x00100000 && prd[0].dbau == 0);
    CHECK(prd[0].reserved == 0);
    CHECK((prd[0].dbc_ioc & 0x003fffffU) == 8191U);
    CHECK((prd[0].dbc_ioc & 0x80000000U) != 0);

    seg[1].address = 0x00200000;
    CHECK(AHCIBuildPRDT(prd, 32, seg, 2, 8192) == 2);
    CHECK((prd[0].dbc_ioc & 0x80000000U) == 0);
    CHECK((prd[1].dbc_ioc & 0x003fffffU) == 4095U);
    CHECK((prd[1].dbc_ioc & 0x80000000U) != 0);

    seg[0].address = 1;
    seg[0].length = 2;
    CHECK(AHCIBuildPRDT(prd, 32, seg, 1, 2) == -1);
    seg[0].address = 0;
    seg[0].length = 1;
    CHECK(AHCIBuildPRDT(prd, 32, seg, 1, 1) == -1);

    seg[0].address = 0x00400000;
    seg[0].length = 131072;
    CHECK(AHCIBuildPRDT(prd, 32, seg, 1, 131072) == 1);
    CHECK((prd[0].dbc_ioc & 0x003fffffU) == 131071U);
    seg[0].length = 131073;
    CHECK(AHCIBuildPRDT(prd, 32, seg, 1, 131073) != 0);

    CHECK(AHCIBuildPRDT(prd, 32, seg, 2, 0) != 0);
    seg[1].length = 0;
    CHECK(AHCIBuildPRDT(prd, 32, seg, 2, 4096) != 0);
    seg[1].length = 4096;
    seg[0].address = 0xfffff000U;
    seg[0].length = 8192;
    CHECK(AHCIBuildPRDT(prd, 32, seg, 1, 8192) != 0);
    seg[0].address = 0;
    seg[0].length = 0xfffff000U;
    CHECK(AHCIBuildPRDT(prd, 32, seg, 1, 8192) != 0);

    for (index = 0; index < 33; ++index) {
        seg[index].address = index * 1024;
        seg[index].length = 512;
    }
    CHECK(AHCIBuildPRDT(prd, 32, seg, 32, 32 * 512) == 32);
    CHECK((prd[0].dbc_ioc & 0x80000000U) == 0);
    CHECK((prd[31].dbc_ioc & 0x80000000U) != 0);
    CHECK(AHCIBuildPRDT(prd, 32, seg, 33, 33 * 512) != 0);
}

static void test_command_header(void)
{
    AHCICommandHeader header;

    memset(&header, 0xff, sizeof(header));
    AHCIInitCommandHeader(&header, 0x12345000, 2, 1, 1);
    CHECK(header.flags == 0x00000065U);
    CHECK(header.prdtl == 2 && header.prdbc == 0);
    CHECK(header.ctba == 0x12345000 && header.ctbau == 0);
    CHECK(header.reserved[0] == 0 && header.reserved[3] == 0);

    AHCIInitCommandHeader(&header, 0x12345000, 32, 0, 0);
    CHECK(header.flags == 5 && header.prdtl == 32);
    AHCIInitCommandHeader(&header, 0x12345000, 33, 1, 1);
    CHECK(header.flags == 0 && header.prdtl == 0 && header.ctba == 0);
}

int main(void)
{
    test_command_layouts();
    test_identify_fis();
    test_identify_packet_fis();
    test_packet_fis();
    test_packet_command();
    test_atapi_autosense_decisions();
    test_lba28_read_dma_fis();
    test_lba48_write_dma_fis();
    test_invalid_dma_fis();
    test_flush_fis();
    test_identify_capacity();
    test_dma_command_selection();
    test_prdt_builder();
    test_command_header();

    if (failures != 0) {
        fprintf(stderr, "ahci_command_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("ahci_command_test: all tests passed\n");
    return EXIT_SUCCESS;
}
