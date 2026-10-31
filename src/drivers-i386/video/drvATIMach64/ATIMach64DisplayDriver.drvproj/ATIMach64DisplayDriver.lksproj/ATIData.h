#ifndef __ATI_DATA_H__
#define __ATI_DATA_H__

#import <driverkit/displayDefs.h>
#import <driverkit/driverTypes.h>
#import "ATIBIOSTypes.h"

ATI_STATIC_ASSERT(sizeof(IODisplayInfo) == 136, ATI_IODisplayInfo_reference_size);

typedef struct {
    int selector;
    const int *refreshRates;
} ATI_ModeRefreshRates;

extern const unsigned char gamma16[16];
extern const unsigned char gamma8[256];
extern IONamedValue bitsPerPixelValues[];
extern IONamedValue colorConfigValues[];
extern int Refresh_60_72_75[4];
extern int Refresh_60_70_75[4];
extern ATI_ModeRefreshRates ATI_modeToRefreshRatesTable[6];
extern ATI_CRTCRecord crt_640x480_60, crt_640x480_72, crt_640x480_75;
extern ATI_CRTCRecord crt_800x600_60, crt_800x600_72, crt_800x600_75;
extern ATI_CRTCRecord crt_1024x768_60, crt_1024x768_70, crt_1024x768_75;
extern ATI_CRTCRecord crt_1280x1024_60, crt_1280x1024_70, crt_1280x1024_75;
extern ATI_CRTCRecord crt_1600x1200_75, crt_1600x1200_72, crt_1600x1200_60;
extern IODisplayInfo AtiModeList[54];
extern int AtiModeListCount;
extern IONamedValue ABReturnValues[];
extern IONamedValue ATI_AsicTypeValues[];
extern IONamedValue ATI_AsicSubTypeValues[];
extern IONamedValue ATI_memSizeValues[];
extern IONamedValue ATI_dacTypeValues[];
extern IONamedValue ATI_busTypeValues[];
extern unsigned int modeValidArray;

int displayInfoToColorSpace(const IODisplayInfo *info);
int colorDepthToColorSpace(int colorDepth);
int displayInfoToColorDepth(const IODisplayInfo *info);
unsigned int memSizeToBytes(unsigned char code);

#endif
