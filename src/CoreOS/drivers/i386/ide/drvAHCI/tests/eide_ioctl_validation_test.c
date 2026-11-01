#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

#include "EIDEIoctlValidation.h"

static int failures;

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                    \
                    __FILE__, __LINE__, #expression);                        \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void test_supported_command_semantics(void)
{
    unsigned int bytes;

    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_DIAGNOSE, 0, 0, 0, 0,
                                   &bytes) == 0);
    CHECK(bytes == 0);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_SET_MULTIPLE, 0, 0, 0, 0,
                                   &bytes) == 0);
    CHECK(EIDEIoctlPrepareTransfer(0xff, 0, 0, 0, 0, &bytes) != 0);
}

static void test_media_transfer_bounds(void)
{
    unsigned int bytes;

    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_READ, 10, 2, 512, 100,
                                   &bytes) == 0);
    CHECK(bytes == 1024);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_WRITE, 0, 0, 512, 100,
                                   &bytes) != 0);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_READ_DMA, 0,
                                   EIDE_IOCTL_MAX_BLOCKS + 1, 512, 1000,
                                   &bytes) != 0);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_WRITE_MULTIPLE, 0, 2, 0,
                                   100, &bytes) != 0);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_READ, 0, 2, INT_MAX, 100,
                                   &bytes) != 0);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_READ, 100, 1, 512, 100,
                                   &bytes) != 0);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_READ, 99, 2, 512, 100,
                                   &bytes) != 0);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_READ, UINT_MAX - 1, 2,
                                   512, UINT_MAX, &bytes) != 0);
}

static void test_nonbuffered_range_validation(void)
{
    unsigned int bytes;

    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_SEEK, 99, 0, 0, 100,
                                   &bytes) == 0);
    CHECK(bytes == 0);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_SEEK, 100, 0, 0, 100,
                                   &bytes) != 0);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_READ_VERIFY, 98, 2, 0,
                                   100, &bytes) == 0);
    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_READ_VERIFY, 99, 2, 0,
                                   100, &bytes) != 0);
}

static void test_identify_is_one_fixed_payload(void)
{
    unsigned int bytes;

    CHECK(EIDEIoctlPrepareTransfer(EIDE_IOCTL_CMD_IDENTIFY, UINT_MAX,
                                   UINT_MAX, 0, 0, &bytes) == 0);
    CHECK(bytes == EIDE_IOCTL_IDENTIFY_BYTES);
}

static void test_completion_bounds(void)
{
    unsigned int bytes;

    CHECK(EIDEIoctlValidateCompletion(EIDE_IOCTL_CMD_READ, 2, 2, 512,
                                      &bytes) == 0);
    CHECK(bytes == 1024);
    CHECK(EIDEIoctlValidateCompletion(EIDE_IOCTL_CMD_READ, 2, 3, 512,
                                      &bytes) != 0);
    CHECK(EIDEIoctlValidateCompletion(EIDE_IOCTL_CMD_READ, 2, 2, INT_MAX,
                                      &bytes) != 0);
    CHECK(EIDEIoctlValidateCompletion(EIDE_IOCTL_CMD_IDENTIFY, 99, 1, 0,
                                      &bytes) == 0);
    CHECK(bytes == EIDE_IOCTL_IDENTIFY_BYTES);
    CHECK(EIDEIoctlValidateCompletion(EIDE_IOCTL_CMD_IDENTIFY, 99, 2, 0,
                                      &bytes) != 0);
}

int main(void)
{
    test_supported_command_semantics();
    test_media_transfer_bounds();
    test_nonbuffered_range_validation();
    test_identify_is_one_fixed_payload();
    test_completion_bounds();

    if (failures != 0) {
        fprintf(stderr, "eide_ioctl_validation_test: %d failure(s)\n",
                failures);
        return EXIT_FAILURE;
    }

    printf("eide_ioctl_validation_test: all tests passed\n");
    return EXIT_SUCCESS;
}
