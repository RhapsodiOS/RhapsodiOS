#include "AHCIATAPILogic.h"
#include <string.h>

static void AHCIATAPICopyIdentifyString(char *destination,
                                        unsigned int destinationBytes,
                                        const unsigned short *words,
                                        unsigned int wordCount)
{
    unsigned int index;
    unsigned int bytes;

    bytes = wordCount * 2U;
    if (bytes >= destinationBytes)
        bytes = destinationBytes - 1U;
    for (index = 0; index < bytes; ++index) {
        unsigned short word;

        word = words[index / 2U];
        destination[index] = (char)((index & 1U) == 0 ?
                             word >> 8 : word & 0xffU);
    }
    while (bytes != 0 && destination[bytes - 1U] == ' ')
        --bytes;
    destination[bytes] = '\0';
}

static unsigned int AHCIATAPISupportedCDBLength(unsigned char opcode)
{
    switch (opcode) {
    case 0x00:
    case 0x03:
    case 0x12:
    case 0x1a:
    case 0x1b:
    case 0x1e:
        return 6U;
    case 0x25:
    case 0x28:
        return 10U;
    case AHCI_ATAPI_READ_16:
        return 16U;
    default:
        return 0;
    }
}

unsigned int AHCIATAPIValidateCDBLength(unsigned char opcode,
                                         unsigned int suppliedLength,
                                         unsigned int cdbCapacity)
{
    unsigned int expected;

    expected = AHCIATAPISupportedCDBLength(opcode);
    if (expected == 0 || expected > cdbCapacity)
        return 0;
    if (suppliedLength != 0 && suppliedLength != expected)
        return 0;
    return expected;
}

unsigned int AHCIATAPIPacketTimeout(int requestedSeconds)
{
    return requestedSeconds > 30 ? (unsigned int)requestedSeconds : 30U;
}

int AHCIATAPIParseIdentity(const unsigned short words[256],
                           AHCIATAPIIdentity *identity)
{
    unsigned int packetCode;

    if (words == 0 || identity == 0)
        return 0;
    identity->peripheralType = (unsigned char)((words[0] >> 8) & 0x1fU);
    packetCode = words[0] & 3U;
    if ((identity->peripheralType != 5U &&
         identity->peripheralType != 7U) || packetCode > 1U)
        return 0;
    identity->packetLength = packetCode == 1U ? 16U : 12U;
    identity->dmaDirSupported = (words[62] & 0x8000U) != 0;
    AHCIATAPICopyIdentifyString(identity->serial,
                                sizeof(identity->serial), words + 10, 10U);
    AHCIATAPICopyIdentifyString(identity->firmware,
                                sizeof(identity->firmware), words + 23, 4U);
    AHCIATAPICopyIdentifyString(identity->model,
                                sizeof(identity->model), words + 27, 20U);
    return 1;
}

int AHCIATAPIIdentityMatches(const AHCIATAPIIdentity *first,
                             const AHCIATAPIIdentity *second)
{
    if (first == 0 || second == 0)
        return 0;
    return first->peripheralType == second->peripheralType &&
           first->packetLength == second->packetLength &&
           first->dmaDirSupported == second->dmaDirSupported &&
           strcmp(first->model, second->model) == 0 &&
           strcmp(first->serial, second->serial) == 0;
}

int AHCIATAPITranslateModeSense6(const unsigned char cdb6[6],
                                  unsigned int maxTransfer,
                                  unsigned char cdb10[12],
                                  unsigned int *translatedTransfer)
{
    unsigned int allocation;

    if (cdb6 == 0 || cdb10 == 0 || translatedTransfer == 0 ||
        cdb6[0] != 0x1a)
        return 0;
    allocation = cdb6[4];
    if (allocation == 0 || allocation > maxTransfer || allocation > 255U)
        return 0;
    memset(cdb10, 0, 12);
    cdb10[0] = 0x5a;
    cdb10[1] = cdb6[1];
    cdb10[2] = cdb6[2];
    cdb10[3] = cdb6[3];
    cdb10[7] = (unsigned char)((allocation + 4U) >> 8);
    cdb10[8] = (unsigned char)(allocation + 4U);
    cdb10[9] = cdb6[5];
    *translatedTransfer = allocation + 4U;
    return 1;
}

int AHCIATAPIRemapModeSense10(const unsigned char *atapiData,
                               unsigned int atapiBytes,
                               unsigned char *scsiData,
                               unsigned int scsiCapacity,
                               unsigned int *scsiBytes)
{
    unsigned int descriptorBytes;
    unsigned int pageOffset;
    unsigned int pageBytes;
    unsigned int resultBytes;

    if (atapiData == 0 || scsiData == 0 || scsiBytes == 0 ||
        atapiBytes < 8U)
        return 0;
    descriptorBytes = ((unsigned int)atapiData[6] << 8) |
                      atapiData[7];
    if (descriptorBytes > atapiBytes - 8U)
        return 0;
    pageOffset = 8U + descriptorBytes;
    pageBytes = atapiBytes - pageOffset;
    resultBytes = 4U + pageBytes;
    if (resultBytes > scsiCapacity || resultBytes > 256U)
        return 0;
    scsiData[0] = (unsigned char)(resultBytes - 1U);
    scsiData[1] = atapiData[2];
    scsiData[2] = atapiData[3];
    scsiData[3] = 0;
    if (pageBytes != 0)
        memcpy(scsiData + 4, atapiData + pageOffset, pageBytes);
    *scsiBytes = resultBytes;
    return 1;
}

int AHCIATAPIEmulateModeSensePage2(const unsigned char cdb6[6],
                                    unsigned char *data,
                                    unsigned int capacity,
                                    unsigned int *actual)
{
    unsigned int allocation;

    if (cdb6 == 0 || data == 0 || actual == 0 || cdb6[0] != 0x1a ||
        (cdb6[2] & 0x3fU) != 2U)
        return 0;
    allocation = cdb6[4];
    if (allocation < 3U || allocation > capacity)
        return 0;
    memset(data, 0, allocation);
    data[0] = 2;
    data[1] = (unsigned char)allocation;
    data[2] = 1;
    *actual = allocation;
    return 1;
}
