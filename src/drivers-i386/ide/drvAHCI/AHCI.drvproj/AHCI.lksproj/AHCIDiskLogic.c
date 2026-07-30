#include "AHCIDiskLogic.h"
#include <limits.h>

static void AHCIDiskCopyIdentifyString(char *destination,
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

int AHCIDiskParseIdentify(const unsigned short words[256],
                          AHCIDiskIdentify *result)
{
    unsigned int capacity;
    unsigned int logicalWords;

    if (words == 0 || result == 0 || (words[49] & (1U << 9)) == 0)
        return 0;
    if ((words[106] & (1U << 14)) != 0 &&
        (words[106] & (1U << 15)) == 0 &&
        (words[106] & (1U << 12)) != 0) {
        logicalWords = (unsigned int)words[117] |
                       ((unsigned int)words[118] << 16);
        if (logicalWords != 256U)
            return 0;
    }
    result->lba48 = (words[83] & (1U << 10)) != 0;
    if (result->lba48) {
        if (words[102] != 0 || words[103] != 0)
            capacity = UINT_MAX;
        else
            capacity = (unsigned int)words[100] |
                       ((unsigned int)words[101] << 16);
    } else {
        capacity = (unsigned int)words[60] |
                   ((unsigned int)words[61] << 16);
    }
    if (capacity == 0)
        return 0;
    result->capacity = capacity;
    AHCIDiskCopyIdentifyString(result->serial, sizeof(result->serial),
                               words + 10, 10U);
    AHCIDiskCopyIdentifyString(result->firmware,
                               sizeof(result->firmware), words + 23, 4U);
    AHCIDiskCopyIdentifyString(result->model, sizeof(result->model),
                               words + 27, 20U);
    return 1;
}

int AHCIDiskClipRequest(unsigned int capacity, unsigned int block,
                        unsigned int length, unsigned int *blocks)
{
    unsigned int requested;
    unsigned int available;

    if (blocks == 0 || length == 0 ||
        (length % AHCI_DISK_SECTOR_BYTES) != 0 || block >= capacity)
        return 0;
    requested = length / AHCI_DISK_SECTOR_BYTES;
    available = capacity - block;
    *blocks = requested > available ? available : requested;
    return *blocks != 0;
}

int AHCIDiskPlanSegment(unsigned int block, unsigned int remaining,
                        int write, AHCIDiskSegment *segment)
{
    int extended;

    if (remaining == 0 || segment == 0)
        return 0;
    segment->blocks = remaining > AHCI_DISK_MAX_SECTORS ?
                      AHCI_DISK_MAX_SECTORS : remaining;
    segment->bytes = segment->blocks * AHCI_DISK_SECTOR_BYTES;
    extended = block >= AHCI_DISK_LBA28_LIMIT ||
               segment->blocks > AHCI_DISK_LBA28_LIMIT - block;
    if (write)
        segment->command = extended ? AHCI_ATA_WRITE_DMA_EXT :
                                      AHCI_ATA_WRITE_DMA;
    else
        segment->command = extended ? AHCI_ATA_READ_DMA_EXT :
                                      AHCI_ATA_READ_DMA;
    return 1;
}
