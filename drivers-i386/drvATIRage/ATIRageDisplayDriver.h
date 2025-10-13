/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * ATIRageDisplayDriver.h - ATI Rage Display Driver
 *
 * HISTORY
 * 28 Mar 98    Created.
 */

#ifndef __ATIRAGEDISPLAYDRIVER_H__
#define __ATIRAGEDISPLAYDRIVER_H__

#import <driverkit/IOFrameBufferDisplay.h>
#import <driverkit/i386/IOPCIDevice.h>

@interface ATIRageDisplayDriver : IOFrameBufferDisplay
{
@private
    IOPCIDevice *_pciDevice;
    vm_address_t _mmioBase;
    vm_address_t _biosBase;
    unsigned int _memorySize;
    unsigned int _ramdacSpeed;

    /* ATI Rage registers */
    unsigned int _ATI_ASIC_ID;
    unsigned int _ATI_ASIC_TYPE;
    unsigned int _ATI_Bios_Offset;
    unsigned int _ATI_Bios_StackLength;
    unsigned int _ATI_memSizeValues;
    unsigned int _ATI_memSize60BitsPerPixel;
    unsigned int _ATI_memSize12BitsPerPixel;
    unsigned int _ATI_memSize15BitsPerPixel;
    unsigned int _ATI_memSize24BitsPerPixel;
    unsigned int _ATI_modeUseRefreshRate;
    unsigned int _ATI_modeListCount;
    void *_ATI_modeList;

    /* Reserved for future expansion */
    int _ATIRageDisplayDriver_reserved[8];
}

/* IODevice methods */
+ (BOOL)probe:deviceDescription;
- initFromDeviceDescription:deviceDescription;
- free;

/* IOFrameBufferDisplay methods */
- (void)enterLinearMode;
- (void)revertToVGAMode;

/* Display configuration */
- (unsigned int)displayMemorySize;
- (unsigned int)ramdacSpeed;

/* Hardware initialization */
- (BOOL)initializeHardware;
- (void)setupRegisters;
- (void)detectMemorySize;

/* ATI Rage specific methods */
- (void)parseModesString;
- (void)updateBiosMode;
- (BOOL)isNodeValid;
- (void)verifyMemoryMap;
- (int)interruptOccurred;
- (void)moveCursor:(void *)token;
- (void)resetCursor:(void *)token;
- (void)waitForRefresh:(unsigned long long)param;
- (void)setTransferTable:(unsigned int *)count refresh:(unsigned long long)param1
                   crtc:(unsigned long long)param2;
- (unsigned int)programAC;
- (unsigned int)setTransferTable_count;

/* ATI-specific BIOS and DAC functions */
- (void)ATI_ProgramDAC;
- (unsigned int)ATI_BIOS_ABReturnValues;
- (void)ATI_ASICSetupValues;
- (void)ATI_ASICTypeValues;
- (unsigned int)ATI_BIOS_Offset;
- (void)ATI_BIOS_StackLength;
- (void)ATI_ReadConfigM;
- (unsigned int)ATI_memSizeValues;
- (void)ATI_modeUseRefreshRate;
- (unsigned int)ATI_modeListCount_export;

@end

/* ATI BIOS return values structure */
typedef struct {
    unsigned int offset;
    unsigned int stackLength;
    unsigned int returnValue;
    unsigned int asicType;
} ATI_BIOS_ABReturnValues;

#endif /* __ATIRAGEDISPLAYDRIVER_H__ */
