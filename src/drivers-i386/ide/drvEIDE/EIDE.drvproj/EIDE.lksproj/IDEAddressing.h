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

typedef struct {
    unsigned int sectors;
    unsigned int lba28Sectors;
    unsigned char lbaSupported;
    unsigned char lba48Supported;
    unsigned char clamped;
} ideCapacity_t;

void IDEParseIdentifyCapacity(
    const unsigned short identify[IDE_IDENTIFY_WORDS],
    ideCapacity_t *capacity);

#endif
