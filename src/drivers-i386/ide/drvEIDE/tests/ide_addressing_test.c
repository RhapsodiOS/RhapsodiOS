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

int main(void)
{
    test_capacity();

    if (failures != 0) {
        fprintf(stderr, "ide_addressing_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("ide_addressing_test: all tests passed\n");
    return EXIT_SUCCESS;
}
