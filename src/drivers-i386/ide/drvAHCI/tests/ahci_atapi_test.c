#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "AHCICommand.h"
#include "AHCIATAPILogic.h"

static int failures;

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                    \
                    __FILE__, __LINE__, #expression);                         \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void test_cdb_length_validation(void)
{
    CHECK(AHCIATAPIValidateCDBLength(0x12, 0, 12) == 6);
    CHECK(AHCIATAPIValidateCDBLength(0x28, 0, 12) == 10);
    CHECK(AHCIATAPIValidateCDBLength(0x28, 6, 12) == 0);
    CHECK(AHCIATAPIValidateCDBLength(0x28, 10, 12) == 10);
    CHECK(AHCIATAPIValidateCDBLength(0x88, 13, 16) == 0);
    CHECK(AHCIATAPIValidateCDBLength(0x88, 14, 16) == 0);
    CHECK(AHCIATAPIValidateCDBLength(0x88, 15, 16) == 0);
    CHECK(AHCIATAPIValidateCDBLength(0x88, 16, 12) == 0);
    CHECK(AHCIATAPIValidateCDBLength(0x88, 16, 16) == 16);
    CHECK(AHCIATAPIValidateCDBLength(0xff, 0, 16) == 0);
}

static void test_packet_timeout_selection(void)
{
    CHECK(AHCIATAPIPacketTimeout(0) == 30U);
    CHECK(AHCIATAPIPacketTimeout(1) == 30U);
    CHECK(AHCIATAPIPacketTimeout(30) == 30U);
    CHECK(AHCIATAPIPacketTimeout(31) == 31U);
    CHECK(AHCIATAPIPacketTimeout(120) == 120U);
}

static void test_odd_read_transport_padding(void)
{
    unsigned char cdb6[6];
    unsigned char cdb[12];
    unsigned char cdb10[12];
    unsigned char fis[20];
    unsigned char acmd[16];
    unsigned char guarded[37];
    AHCIPRDTEntry prd;
    AHCISegment segment;
    unsigned int requested;
    unsigned int transport;
    unsigned int clipped;

    memset(cdb6, 0, sizeof(cdb6));
    cdb6[0] = 0x1a;
    cdb6[4] = 255;
    CHECK(AHCIATAPITranslateModeSense6(cdb6, 255, cdb10,
                                       &requested) == 1);
    CHECK(requested == 259U);
    CHECK(AHCIATAPITransportLength(requested, 0, 131072U,
                                   &transport) == 1);
    CHECK(transport == 260U && cdb10[7] == 1 && cdb10[8] == 3);
    CHECK(AHCIBuildPacketCommand(fis, acmd, cdb10, 12, transport,
                                 0, 1) == 0);
    segment.address = 0x1000U;
    segment.length = transport;
    CHECK(AHCIBuildPRDT(&prd, 1, &segment, 1, transport) == 1);

    memset(cdb, 0, sizeof(cdb));
    cdb[0] = 0x12;
    cdb[4] = 35;
    CHECK(AHCIATAPITransportLength(35U, 0, 131072U, &transport) == 1);
    CHECK(transport == 36U && cdb[4] == 35);
    CHECK(AHCIBuildPacketCommand(fis, acmd, cdb, 12, transport,
                                 0, 1) == 0);
    segment.length = transport;
    CHECK(AHCIBuildPRDT(&prd, 1, &segment, 1, transport) == 1);
    memset(guarded, 0x5a, sizeof(guarded));
    clipped = AHCIATAPIClipTransfer(36U, 35U);
    memset(guarded, 0xa5, clipped);
    CHECK(clipped == 35U && guarded[35] == 0x5a && guarded[36] == 0x5a);
    CHECK(AHCIATAPIClipTransfer(34U, 35U) == 34U);

    CHECK(AHCIATAPITransportLength(0U, 0, 131072U, &transport) == 1);
    CHECK(transport == 0U);
    CHECK(AHCIBuildPacketCommand(fis, acmd, cdb, 12, transport,
                                 0, 1) == 0);
    CHECK(AHCIATAPITransportLength(36U, 0, 131072U, &transport) == 1);
    CHECK(transport == 36U);
    CHECK(AHCIATAPITransportLength(35U, 1, 131072U, &transport) == 0);
}

static void set_identify_string(unsigned short *words, unsigned int count,
                                const char *text)
{
    unsigned int index;

    for (index = 0; index < count; ++index) {
        unsigned char first;
        unsigned char second;

        first = *text == '\0' ? ' ' : (unsigned char)*text++;
        second = *text == '\0' ? ' ' : (unsigned char)*text++;
        words[index] = (unsigned short)(((unsigned short)first << 8) |
                                        second);
    }
}

static void test_identify_identity_matching(void)
{
    unsigned short words[256];
    AHCIATAPIIdentity first;
    AHCIATAPIIdentity second;

    memset(words, 0, sizeof(words));
    words[0] = (unsigned short)(5U << 8);
    words[62] = 0x8000U;
    set_identify_string(words + 10, 10, "SERIAL-A");
    set_identify_string(words + 23, 4, "FW1");
    set_identify_string(words + 27, 20, "OPTICAL MODEL");
    CHECK(AHCIATAPIParseIdentity(words, &first) == 1);
    CHECK(first.peripheralType == 5U);
    CHECK(first.packetLength == 12U);
    CHECK(first.dmaDirSupported == 1);
    CHECK(strcmp(first.serial, "SERIAL-A") == 0);
    CHECK(strcmp(first.model, "OPTICAL MODEL") == 0);

    second = first;
    CHECK(AHCIATAPIIdentityMatches(&first, &second) == 1);
    second.dmaDirSupported = 0;
    CHECK(AHCIATAPIIdentityMatches(&first, &second) == 0);
    second = first;
    strcpy(second.serial, "SERIAL-B");
    CHECK(AHCIATAPIIdentityMatches(&first, &second) == 0);
    second = first;
    strcpy(second.firmware, "FW2");
    CHECK(AHCIATAPIIdentityMatches(&first, &second) == 1);

    words[0] = (unsigned short)((5U << 8) | 1U);
    CHECK(AHCIATAPIParseIdentity(words, &second) == 1);
    CHECK(second.packetLength == 16U);
    CHECK(AHCIATAPIIdentityMatches(&first, &second) == 0);
}

static void test_mode_sense_translation(void)
{
    unsigned char cdb6[6];
    unsigned char cdb10[12];
    unsigned char atapiData[16];
    unsigned char scsiData[12];
    unsigned int transfer;
    unsigned int actual;

    memset(cdb6, 0, sizeof(cdb6));
    cdb6[0] = 0x1a;
    cdb6[2] = 0x3f;
    cdb6[4] = 12;
    CHECK(AHCIATAPITranslateModeSense6(cdb6, 12, cdb10,
                                       &transfer) == 1);
    CHECK(cdb10[0] == 0x5a && cdb10[2] == 0x3f);
    CHECK(cdb10[7] == 0 && cdb10[8] == 16);
    CHECK(transfer == 16U);
    CHECK(AHCIATAPITranslateModeSense6(cdb6, 11, cdb10,
                                       &transfer) == 0);
    cdb6[4] = 255;
    CHECK(AHCIATAPITranslateModeSense6(cdb6, 255, cdb10,
                                       &transfer) == 1);
    CHECK(cdb10[7] == 1 && cdb10[8] == 3 && transfer == 259U);

    memset(atapiData, 0, sizeof(atapiData));
    atapiData[1] = 10;
    atapiData[2] = 1;
    atapiData[8] = 0x2a;
    atapiData[9] = 2;
    atapiData[10] = 0xaa;
    atapiData[11] = 0xbb;
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 12, scsiData,
                                    sizeof(scsiData), &actual) == 1);
    CHECK(actual == 8U);
    CHECK(scsiData[0] == 7 && scsiData[1] == 1);
    CHECK(scsiData[2] == 0 && scsiData[3] == 0);
    CHECK(scsiData[4] == 0x2a && scsiData[7] == 0xbb);
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 7, scsiData,
                                    sizeof(scsiData), &actual) == 0);

    memset(atapiData, 0, sizeof(atapiData));
    atapiData[1] = 14;
    atapiData[6] = 0;
    atapiData[7] = 4;
    atapiData[8] = 0xde;
    atapiData[9] = 0xad;
    atapiData[10] = 0xbe;
    atapiData[11] = 0xef;
    atapiData[12] = 0x2a;
    atapiData[13] = 2;
    atapiData[14] = 0xaa;
    atapiData[15] = 0xbb;
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 16, scsiData,
                                    sizeof(scsiData), &actual) == 1);
    CHECK(actual == 12U && scsiData[0] == 11 && scsiData[3] == 4);
    CHECK(scsiData[4] == 0xde && scsiData[7] == 0xef);
    CHECK(scsiData[8] == 0x2a && scsiData[11] == 0xbb);
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 12, scsiData,
                                    sizeof(scsiData), &actual) == 1);
    CHECK(actual == 8U && scsiData[0] == 11 && scsiData[3] == 4);
    atapiData[1] = 10;
    atapiData[7] = 5;
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 12, scsiData,
                                    sizeof(scsiData), &actual) == 0);
    atapiData[1] = 14;
    atapiData[7] = 4;
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 16, scsiData,
                                    6, &actual) == 1);
    CHECK(actual == 6U && scsiData[0] == 11 && scsiData[3] == 4);
    CHECK(scsiData[4] == 0xde && scsiData[5] == 0xad);

    atapiData[0] = 1;
    atapiData[1] = 0xff;
    atapiData[7] = 0;
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 12, scsiData,
                                    sizeof(scsiData), &actual) == 1);
    CHECK(actual == 8U && scsiData[0] == 0xff);

    atapiData[0] = 0;
    atapiData[1] = 14;
    atapiData[7] = 4;
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 10, scsiData,
                                    sizeof(scsiData), &actual) == 1);
    CHECK(actual == 6U && scsiData[3] == 4);
    CHECK(scsiData[4] == 0xde && scsiData[5] == 0xad);

    memset(atapiData, 0, sizeof(atapiData));
    atapiData[1] = 14;
    atapiData[2] = 0x12;
    atapiData[3] = 0x34;
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 2, scsiData,
                                    1, &actual) == 1);
    CHECK(actual == 1U && scsiData[0] == 11);
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 3, scsiData,
                                    2, &actual) == 1);
    CHECK(actual == 2U && scsiData[1] == 0x12);
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 4, scsiData,
                                    3, &actual) == 1);
    CHECK(actual == 3U && scsiData[2] == 0x34);

    atapiData[1] = 10;
    atapiData[7] = 5;
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 12, scsiData,
                                    sizeof(scsiData), &actual) == 0);
    CHECK(AHCIATAPIRemapModeSense10(atapiData, 12, scsiData,
                                    1, &actual) == 0);
}

static void test_mode_sense_page_two_emulation(void)
{
    unsigned char cdb6[6];
    unsigned char data[16];
    unsigned int actual;

    memset(cdb6, 0, sizeof(cdb6));
    cdb6[0] = 0x1a;
    cdb6[2] = 2;
    cdb6[4] = sizeof(data);
    memset(data, 0xff, sizeof(data));
    CHECK(AHCIATAPIEmulateModeSensePage2(cdb6, data, sizeof(data),
                                         &actual) == 1);
    CHECK(actual == 3U);
    CHECK(data[0] == 2 && data[1] == sizeof(data) && data[2] == 1);
    CHECK(data[3] == 0xff && data[15] == 0xff);
    cdb6[2] = 3;
    CHECK(AHCIATAPIEmulateModeSensePage2(cdb6, data, sizeof(data),
                                         &actual) == 0);
}

int main(void)
{
    test_cdb_length_validation();
    test_packet_timeout_selection();
    test_odd_read_transport_padding();
    test_identify_identity_matching();
    test_mode_sense_translation();
    test_mode_sense_page_two_emulation();
    if (failures != 0) {
        fprintf(stderr, "ahci_atapi_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }
    puts("ahci_atapi_test: all tests passed");
    return EXIT_SUCCESS;
}
