#ifndef __ATI_PRIVATE_H__
#define __ATI_PRIVATE_H__

#import <driverkit/IOFrameBufferDisplay.h>
#import "ATI_BIOS.h"

@interface ATI : IOFrameBufferDisplay
{
@private
    unsigned int *redTransferTable;
    unsigned int *greenTransferTable;
    unsigned int *blueTransferTable;
    int transferTableCount;
    int brightnessLevel;
    int modeNumber;
    void *vram;
    unsigned int vramBytes;
    int currentState;
    char isPCI;
    ATI_BIOS *atiBios;
    void *queryData;
    unsigned int queryDataSize;
    char supportsGamma;
    char supportsGrey256;
    int colorConfig;
    int fbMapStyle;
    int ramdacStyle;
}
+ (BOOL)probe:deviceDescription;
- initFromDeviceDescription:deviceDescription;
- free;
- (void)enterLinearMode;
- (void)revertToVGAMode;
- (char)setPendingDisplayMode:(int)mode;
- (int)getQueryData;
- (int)parseModeString:(const char *)modeString;
- (void)updateModeList;
- (unsigned int)isModeValid:(int)mode;
- (char)verifyMemoryMap;
- (int)changeHardwareMapping:(unsigned int)mode;
- (int)changeTableMapping:(unsigned int)mode;
- (id)setGammaTable;
- (id)setBrightness:(int)level token:(int)token;
- (id)setTransferTable:(const unsigned int *)table count:(int)count;
- (unsigned int)displayModeCount;
- (IODisplayInfo *)displayModes;
- (unsigned int)displayMemorySize;
- (unsigned int)ramdacSpeed;
@end

#endif
