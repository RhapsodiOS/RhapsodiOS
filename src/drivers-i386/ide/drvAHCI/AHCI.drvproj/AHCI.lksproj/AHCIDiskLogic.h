#ifndef RHAPSODIOS_AHCI_DISK_LOGIC_H
#define RHAPSODIOS_AHCI_DISK_LOGIC_H

#define AHCI_DISK_SECTOR_BYTES 512U
#define AHCI_DISK_MAX_SECTORS 256U
#define AHCI_DISK_MAX_BYTES (AHCI_DISK_SECTOR_BYTES * AHCI_DISK_MAX_SECTORS)
#define AHCI_DISK_LBA28_LIMIT 0x10000000U

#define AHCI_ATA_READ_DMA 0xc8U
#define AHCI_ATA_WRITE_DMA 0xcaU
#define AHCI_ATA_READ_DMA_EXT 0x25U
#define AHCI_ATA_WRITE_DMA_EXT 0x35U
#define AHCI_ATA_IDENTIFY_DEVICE 0xecU
#define AHCI_ATA_FLUSH_CACHE 0xe7U
#define AHCI_ATA_FLUSH_CACHE_EXT 0xeaU

typedef struct {
    unsigned int capacity;
    int lba48;
    char model[41];
    char serial[21];
    char firmware[9];
} AHCIDiskIdentify;

typedef struct {
    unsigned int blocks;
    unsigned int bytes;
    unsigned char command;
} AHCIDiskSegment;

int AHCIDiskParseIdentify(const unsigned short words[256],
                          AHCIDiskIdentify *result);
int AHCIDiskClipRequest(unsigned int capacity, unsigned int block,
                        unsigned int length, unsigned int *blocks);
int AHCIDiskPlanSegment(unsigned int block, unsigned int remaining,
                        int write, AHCIDiskSegment *segment);

#endif
