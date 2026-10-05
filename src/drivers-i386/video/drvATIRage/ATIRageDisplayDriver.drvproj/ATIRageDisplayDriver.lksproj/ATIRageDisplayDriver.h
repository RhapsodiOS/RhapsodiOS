#ifndef __ATIRAGEDISPLAYDRIVER_H__
#define __ATIRAGEDISPLAYDRIVER_H__

#import <driverkit/IOFrameBufferDisplay.h>
#import <driverkit/IOFrameBufferShared.h>
#import <driverkit/displayDefs.h>
#import <driverkit/driverTypes.h>
#import "ATI_BIOS.h"

@class IOPCIDeviceDescription;

typedef struct _ATI_ModeRefreshMap {
    unsigned int mode;
    const int *rates;
} ATI_ModeRefreshMap;

@interface ATI : IOFrameBufferDisplay
{
@private
    char *redTransferTable;
    char *greenTransferTable;
    char *blueTransferTable;
    int transferTableCount;
    int brightnessLevel;
    int modeNumber;
    void *vram;
    unsigned int vramBytes;
    int currentState;
    id atiBios;
    void *queryData;
    unsigned int queryDataSize;
    char supportsGamma;
    char supportsGrey256;
    signed char relocatableIO;
    char engineStarted;
    char overrideStartBaseAddress;
    unsigned long baseAddress;
    int colorConfig;
    int fbMapStyle;
    int ramdacStyle;
}

- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- (char)fixDeviceDescriptionForPCI:(IOPCIDeviceDescription *)deviceDescription;
- (int)getQueryData;
- (int)parseModeString:(const char *)modeString;
- (void)updateModeList;
- (unsigned int)isModeValid:(int)mode;
- (char)verifyMemoryMap;
- free;
- (void)enterLinearMode;
- (void)revertToVGAMode;
- showCursor:(Point *)cursorLoc frame:(int)frame token:(int)token;
- moveCursor:(Point *)cursorLoc frame:(int)frame token:(int)token;
- hideCursor:(int)token;
- (void)initEngine;
- (void)resetEngine;
- (unsigned int)displayModeCount;
- (IODisplayInfo *)displayModes;
- (unsigned int)displayMemorySize;
- (char)setPendingDisplayMode:(int)mode;
- (int)setIntValues:(unsigned int *)parameterArray
       forParameter:(IOParameterName)parameterName
              count:(unsigned int)count;

/* ProgramDAC category methods are declared below the implementation. */
@end

#if defined(__i386__) || defined(i386)
typedef char _ATI_instance_must_be_624_bytes[(sizeof(ATI) == 624) ? 1 : -1];
#endif

@interface ATI (ProgramDAC)
- setGammaTable;
- setBrightness:(int)level token:(int)token;
- setTransferTable:(const unsigned int *)table count:(int)count;
@end

extern IONamedValue bitsPerPixelValues[6];
extern IONamedValue colorConfigValues[7];
extern ATI_ModeRefreshMap ATI_modeToRefreshRatesTable[6];
extern IONamedValue ABReturnValues[5];
extern IONamedValue ATI_AsicTypeValues[9];
extern IONamedValue ATI_AsicSubTypeValues[5];
extern IONamedValue ATI_memSizeValues[17];
extern IONamedValue ATI_dacTypeValues[22];
extern IONamedValue ATI_busTypeValues[6];
extern unsigned int ATI_Bios_Offset;
extern unsigned short ATI_Bios_Selector;
extern unsigned short ATI_Bios_StackOffset;
extern unsigned short ATI_Bios_StackSelector;

extern int displayInfoToColorSpace(const IODisplayInfo *displayInfo);
extern int colorDepthToColorSpace(int depth);
extern int displayInfoToColorDepth(const IODisplayInfo *displayInfo);
extern int memSizeToBytes(unsigned char memorySize);

#endif

extern IODisplayInfo AtiModeList[72];
