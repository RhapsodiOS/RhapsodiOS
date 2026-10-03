#include <stdio.h>
#include <string.h>
#include "../ATIData.h"
#include "mock_runtime.h"

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "data check failed at line %d: %s\n", __LINE__, #condition); \
    return 1; } } while (0)

int main(void)
{
    IODisplayInfo info;
    CHECK(AtiModeListCount == 54);
    CHECK(sizeof(gamma16) == 16 && sizeof(gamma8) == 256);
    CHECK(sizeof(crt_640x480_60.bytes) == 30);
    CHECK(AtiModeList[0].width == 640 && AtiModeList[0].height == 480);
    CHECK(AtiModeList[0].parameters == (void *)&crt_640x480_60);
    CHECK(AtiModeList[53].width == 1600 && AtiModeList[53].height == 1200);
    CHECK(AtiModeList[53].parameters == (void *)&crt_1600x1200_75);
    CHECK(ATI_modeToRefreshRatesTable[5].refreshRates == 0);
    CHECK(memSizeToBytes(0) == 0x80000);
    CHECK(memSizeToBytes(1) == 0x100000);
    CHECK(memSizeToBytes(2) == 0x200000);
    CHECK(memSizeToBytes(3) == 0x400000);
    CHECK(memSizeToBytes(4) == 0x600000);
    CHECK(memSizeToBytes(255) == 0x200000);
    memset(&info, 0, sizeof(info));
    info.bitsPerPixel = IO_15BitsPerPixel;
    CHECK(displayInfoToColorSpace(&info) == 2);
    CHECK(displayInfoToColorDepth(&info) == 3);
    CHECK(colorDepthToColorSpace(2) == 1);
    CHECK(colorDepthToColorSpace(4) == 2);
    CHECK(colorDepthToColorSpace(6) == 3);
    CHECK(colorDepthToColorSpace(1) == 0);
    ATI_mockReset();
    info.bitsPerPixel = IO_2BitsPerPixel;
    CHECK(displayInfoToColorSpace(&info) == 0);
    CHECK(displayInfoToColorDepth(&info) == 0);
    CHECK(ATI_mockLogCount() == 2 && ATI_mockPanicCount() == 2);
    return 0;
}
