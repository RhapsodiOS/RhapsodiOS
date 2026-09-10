#include <stdio.h>
#include <string.h>
#include "ICHAC97Controller.h"

static int failures;

#define CHECK(expression) do { \
    if (!(expression)) { \
        fprintf(stderr, "%s:%d: CHECK failed: %s\n", \
                __FILE__, __LINE__, #expression); \
        failures++; \
    } \
} while (0)

static void test_bdl_wraps_unique_fragments_into_32_slots(void)
{
    ICHAC97Playback playback;
    ICHAC97BufferDescriptor bdl[32];
    unsigned int i;

    memset(&playback, 0, sizeof(playback));
    memset(bdl, 0xa5, sizeof(bdl));
    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0x2000U,
                            0x300000U, 32768U, 4096U) == kICHAC97Success);
    CHECK(playback.fragmentCount == 8U);
    CHECK(playback.serviceBytes == 4096U);
    for (i = 0; i < 32U; i++) {
        CHECK(bdl[i].bufferAddress == 0x300000U + (i % 8U) * 4096U);
        CHECK(bdl[i].controlLength == (ICHAC97_BD_IOC | 2048U));
    }
    CHECK(bdl[8].bufferAddress == 0x300000U);
    CHECK(bdl[31].bufferAddress == 0x300000U + (31U % 8U) * 4096U);
}

static void test_bdl_64k_8k_and_rejects(void)
{
    ICHAC97Playback playback;
    ICHAC97BufferDescriptor bdl[32];

    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0x2000U,
                            0x300000U, 65536U, 8192U) == kICHAC97Success);
    CHECK(playback.fragmentCount == 8U);
    CHECK(bdl[0].controlLength == (ICHAC97_BD_IOC | 4096U));
    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0U, 0U,
                            0U, 4096U) == kICHAC97InvalidArgument);
    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0U, 0U,
                            32768U, 4095U) == kICHAC97InvalidArgument);
    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0U, 0U,
                            32769U, 4096U) == kICHAC97InvalidArgument);
    CHECK(ICHAC97PrepareBDL(&playback, bdl, 0U, 0U,
                            67584U, 2048U) == kICHAC97InvalidArgument);
}

int main(void)
{
    test_bdl_wraps_unique_fragments_into_32_slots();
    test_bdl_64k_8k_and_rejects();
    if (failures != 0) {
        fprintf(stderr, "%d Intel AC97 checks failed\n", failures);
        return 1;
    }
    puts("Intel AC97 checks passed");
    return 0;
}
