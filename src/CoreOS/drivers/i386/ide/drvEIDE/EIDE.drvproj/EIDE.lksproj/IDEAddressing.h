#ifndef _IDE_ADDRESSING_H_
#define _IDE_ADDRESSING_H_

#define IDE_IDENTIFY_WORDS 256
#define IDE_IDENTIFY_CAPABILITIES 49
#define IDE_IDENTIFY_LBA28_LOW 60
#define IDE_IDENTIFY_LBA28_HIGH 61
#define IDE_IDENTIFY_COMMAND_SET_ENABLED_2 86

#define IDE_CAP_LBA 0x0200
#define IDE_CAP_LBA48 0x0400

#define IDE_LBA28_SECTORS 0x10000000UL
#define IDE_MAX_ADDRESSABLE_SECTORS 0xffffffffUL

#define IDE_ADDRESS_CHS 0
#define IDE_ADDRESS_LBA 1
#define IDE_ADDRESS_OK 0
#define IDE_ADDRESS_INVALID 1
#define IDE_ADDRESS_UNSUPPORTED 2

typedef struct {
    unsigned int sectors;
    unsigned int lba28Sectors;
    unsigned char lbaSupported;
    unsigned char lba48Supported;
    unsigned char clamped;
} ideCapacity_t;

typedef struct {
    unsigned char features, sectorCount, lbaLow, lbaMid, lbaHigh, deviceHead;
    unsigned char featuresHigh, sectorCountHigh;
    unsigned char lbaLowHigh, lbaMidHigh, lbaHighHigh, useLBA48;
} ideTaskfile_t;

typedef enum {
    IDE_TASK_DEVICE,
    IDE_TASK_FEATURES,
    IDE_TASK_COUNT,
    IDE_TASK_LBA_LOW,
    IDE_TASK_LBA_MID,
    IDE_TASK_LBA_HIGH
} ideTaskRegister_t;

typedef struct {
    ideTaskRegister_t reg;
    unsigned char value;
} ideTaskWrite_t;

void IDEParseIdentifyCapacity(
    const unsigned short identify[IDE_IDENTIFY_WORDS],
    ideCapacity_t *capacity);
int IDEBuildTaskfile(ideTaskfile_t *, unsigned char mode, unsigned char drive,
    unsigned int block, unsigned int count, unsigned int capacity,
    unsigned char lba48, unsigned int heads, unsigned int sectorsPerTrack);
unsigned int IDEExtendedCommand(unsigned int command);
unsigned int IDETaskfileWriteSequence(const ideTaskfile_t *,
    ideTaskWrite_t[11]);

#endif
