/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * ATIMach64DisplayDriver.h - ATI Mach64 Display Driver
 *
 * HISTORY
 * 28 Mar 98    Created.
 */

#ifndef __ATIMACH64DISPLAYDRIVER_H__
#define __ATIMACH64DISPLAYDRIVER_H__

#import <driverkit/IOFrameBufferDisplay.h>
#import <driverkit/i386/IOPCIDevice.h>

@interface ATIMach64DisplayDriver : IOFrameBufferDisplay
{
@private
    IOPCIDevice *_pciDevice;
    vm_address_t _mmioBase;
    vm_address_t _biosBase;
    unsigned int _memorySize;
    unsigned int _ramdacSpeed;

    /* ATI registers */
    unsigned int _ATI_ASIC_ID;
    unsigned int _ATI_ASIC_TYPE;
    unsigned int _ATI_memSize;

    /* Reserved for future expansion */
    int _ATIMach64DisplayDriver_reserved[8];
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
- (unsigned int)ATI_modeListCount;

@end

/* ATI BIOS return values structure */
typedef struct {
    unsigned int offset;
    unsigned int stackLength;
    unsigned int returnValue;
    unsigned int asicType;
} ATI_BIOS_ABReturnValues;

#endif /* __ATIMACH64DISPLAYDRIVER_H__ */
