#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "IDEAddressing.h"

static int failures;

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                    \
                    __FILE__, __LINE__, #expression);                         \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void test_capacity(void)
{
    unsigned short identify[IDE_IDENTIFY_WORDS];
    ideCapacity_t capacity;

    memset(identify, 0, sizeof(identify));
    memset(&capacity, 0xff, sizeof(capacity));
    identify[IDE_IDENTIFY_CAPABILITIES] = IDE_CAP_LBA;
    identify[IDE_IDENTIFY_LBA28_LOW] = 0x5678;
    identify[IDE_IDENTIFY_LBA28_HIGH] = 0x0123;
    IDEParseIdentifyCapacity(identify, &capacity);
    CHECK(capacity.lbaSupported == 1);
    CHECK(capacity.lba48Supported == 0);
    CHECK(capacity.lba28Sectors == 0x01235678UL);
    CHECK(capacity.sectors == 0x01235678UL);
    CHECK(capacity.clamped == 0);

    memset(identify, 0, sizeof(identify));
    identify[IDE_IDENTIFY_CAPABILITIES] = IDE_CAP_LBA;
    identify[IDE_IDENTIFY_LBA28_LOW] = 0x0001;
    identify[IDE_IDENTIFY_LBA28_HIGH] = 0x1000;
    IDEParseIdentifyCapacity(identify, &capacity);
    CHECK(capacity.lba28Sectors == IDE_LBA28_SECTORS);
    CHECK(capacity.sectors == IDE_LBA28_SECTORS);

    memset(identify, 0, sizeof(identify));
    identify[IDE_IDENTIFY_LBA28_LOW] = 0x5678;
    identify[IDE_IDENTIFY_LBA28_HIGH] = 0x0123;
    IDEParseIdentifyCapacity(identify, &capacity);
    CHECK(capacity.lbaSupported == 0);
    CHECK(capacity.lba28Sectors == 0);
    CHECK(capacity.sectors == 0);

    memset(identify, 0, sizeof(identify));
    identify[IDE_IDENTIFY_COMMAND_SET_ENABLED_2] = IDE_CAP_LBA48;
    identify[100] = 0x5678;
    identify[101] = 0x1234;
    IDEParseIdentifyCapacity(identify, &capacity);
    CHECK(capacity.lba48Supported == 1);
    CHECK(capacity.sectors == 0x12345678UL);
    CHECK(capacity.clamped == 0);

    identify[102] = 1;
    IDEParseIdentifyCapacity(identify, &capacity);
    CHECK(capacity.lba48Supported == 1);
    CHECK(capacity.sectors == IDE_MAX_ADDRESSABLE_SECTORS);
    CHECK(capacity.clamped == 1);

    memset(identify, 0, sizeof(identify));
    identify[IDE_IDENTIFY_CAPABILITIES] = IDE_CAP_LBA;
    identify[IDE_IDENTIFY_LBA28_LOW] = 0x5678;
    identify[IDE_IDENTIFY_LBA28_HIGH] = 0x0123;
    identify[100] = 0x4321;
    identify[101] = 0x8765;
    IDEParseIdentifyCapacity(identify, &capacity);
    CHECK(capacity.lba48Supported == 0);
    CHECK(capacity.lba28Sectors == 0x01235678UL);
    CHECK(capacity.sectors == 0x01235678UL);

    memset(identify, 0, sizeof(identify));
    identify[IDE_IDENTIFY_COMMAND_SET_ENABLED_2] = IDE_CAP_LBA48;
    identify[102] = 1;
    IDEParseIdentifyCapacity(identify, &capacity);
    CHECK(capacity.lba48Supported == 1);
    CHECK(capacity.sectors == IDE_MAX_ADDRESSABLE_SECTORS);
    CHECK(capacity.clamped == 1);

    memset(identify, 0, sizeof(identify));
    identify[IDE_IDENTIFY_CAPABILITIES] = IDE_CAP_LBA;
    identify[IDE_IDENTIFY_LBA28_LOW] = 0x5678;
    identify[IDE_IDENTIFY_LBA28_HIGH] = 0x0123;
    identify[IDE_IDENTIFY_COMMAND_SET_ENABLED_2] = IDE_CAP_LBA48;
    IDEParseIdentifyCapacity(identify, &capacity);
    CHECK(capacity.lba48Supported == 0);
    CHECK(capacity.sectors == capacity.lba28Sectors);
    CHECK(capacity.sectors == 0x01235678UL);

    memset(identify, 0, sizeof(identify));
    IDEParseIdentifyCapacity(identify, &capacity);
    CHECK(capacity.sectors == 0);
    CHECK(capacity.lbaSupported == 0);
    CHECK(capacity.lba48Supported == 0);
    CHECK(capacity.clamped == 0);
}

static void test_taskfile_construction(void)
{
    ideTaskfile_t taskfile;

    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_LBA, 0,
        0x0fffffffUL, 1, 0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_OK);
    CHECK(taskfile.useLBA48 == 0);
    CHECK(taskfile.deviceHead == 0xef);

    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_LBA, 1,
        0x0fffffffUL, 2, 0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_OK);
    CHECK(taskfile.useLBA48 == 1);
    CHECK(taskfile.deviceHead == 0xf0);
    CHECK(taskfile.lbaLowHigh == 0x0f);

    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_LBA, 0,
        0x10000000UL, 256, 0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_OK);
    CHECK(taskfile.sectorCount == 0);
    CHECK(taskfile.sectorCountHigh == 1);

    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_LBA, 0,
        1, 256, 0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_OK);
    CHECK(taskfile.useLBA48 == 0);
    CHECK(taskfile.sectorCount == 0);

    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_CHS, 0,
        63, 1, 100000, 0, 16, 63) == IDE_ADDRESS_OK);
    CHECK(taskfile.lbaLow == 1);
    CHECK(taskfile.deviceHead == 0xa1);

    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_LBA, 0,
        0x10000000UL, 1, 0xffffffffUL, 0, 0, 0) ==
        IDE_ADDRESS_UNSUPPORTED);
    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_LBA, 0,
        0, 0, 100, 0, 0, 0) == IDE_ADDRESS_INVALID);
    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_LBA, 0,
        99, 2, 100, 0, 0, 0) == IDE_ADDRESS_INVALID);
    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_LBA, 0,
        0xfffffffeUL, 2, 0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_INVALID);
}

static void test_extended_commands(void)
{
    CHECK(IDEExtendedCommand(0x20) == 0x24);
    CHECK(IDEExtendedCommand(0x30) == 0x34);
    CHECK(IDEExtendedCommand(0xc4) == 0x29);
    CHECK(IDEExtendedCommand(0xc5) == 0x39);
    CHECK(IDEExtendedCommand(0xc8) == 0x25);
    CHECK(IDEExtendedCommand(0xca) == 0x35);
    CHECK(IDEExtendedCommand(0x40) == 0x42);
    CHECK(IDEExtendedCommand(0x70) == 0);
}

static void test_taskfile_write_sequence(void)
{
    ideTaskfile_t taskfile;
    ideTaskWrite_t writes[11];
    unsigned int count;

    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_LBA, 0,
        0x12345678UL, 256, 0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_OK);
    count = IDETaskfileWriteSequence(&taskfile, writes);
    CHECK(count == 11);
    CHECK(writes[0].reg == IDE_TASK_DEVICE);
    CHECK(writes[0].value == taskfile.deviceHead);
    CHECK(writes[1].reg == IDE_TASK_FEATURES);
    CHECK(writes[1].value == 0);
    CHECK(writes[2].reg == IDE_TASK_COUNT);
    CHECK(writes[2].value == 1);
    CHECK(writes[3].reg == IDE_TASK_LBA_LOW);
    CHECK(writes[3].value == 0x12);
    CHECK(writes[4].reg == IDE_TASK_LBA_MID);
    CHECK(writes[4].value == 0);
    CHECK(writes[5].reg == IDE_TASK_LBA_HIGH);
    CHECK(writes[5].value == 0);
    CHECK(writes[6].reg == IDE_TASK_FEATURES);
    CHECK(writes[6].value == 0);
    CHECK(writes[7].reg == IDE_TASK_COUNT);
    CHECK(writes[7].value == 0);
    CHECK(writes[8].reg == IDE_TASK_LBA_LOW);
    CHECK(writes[8].value == 0x78);
    CHECK(writes[9].reg == IDE_TASK_LBA_MID);
    CHECK(writes[9].value == 0x56);
    CHECK(writes[10].reg == IDE_TASK_LBA_HIGH);
    CHECK(writes[10].value == 0x34);

    CHECK(IDEBuildTaskfile(&taskfile, IDE_ADDRESS_LBA, 0,
        1, 1, 100, 0, 0, 0) == IDE_ADDRESS_OK);
    count = IDETaskfileWriteSequence(&taskfile, writes);
    CHECK(count == 5);
    CHECK(writes[0].reg == IDE_TASK_DEVICE);
    CHECK(writes[1].reg == IDE_TASK_LBA_LOW);
    CHECK(writes[2].reg == IDE_TASK_COUNT);
    CHECK(writes[3].reg == IDE_TASK_LBA_MID);
    CHECK(writes[4].reg == IDE_TASK_LBA_HIGH);
}

int main(void)
{
    test_capacity();
    test_taskfile_construction();
    test_extended_commands();
    test_taskfile_write_sequence();

    if (failures != 0) {
        fprintf(stderr, "ide_addressing_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("ide_addressing_test: all tests passed\n");
    return EXIT_SUCCESS;
}
