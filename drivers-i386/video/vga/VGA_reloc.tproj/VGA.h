/* CONFIDENTIAL
 * Copyright (c) 1996 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * VGA.h -- interface for VGA display driver.
 *
 * Created for RhapsodiOS VGA support
 */

#ifndef VGA_H__
#define VGA_H__

#import <driverkit/IOFrameBufferDisplay.h>
#import "VGAModes.h"

@interface VGA:IOFrameBufferDisplay
{
    /* The adapter type */
    VGAAdapterType adapter;

    /* The memory installed on this device. */
    vm_size_t availableMemory;

    /* The table of valid modes for this device. */
    const IODisplayInfo *modeTable;

    /* The count of valid modes for this device. */
    unsigned int modeTableCount;

    /* The physical address of framebuffer. */
    unsigned long videoRamAddress;

    /* The transfer tables for this mode. */
    unsigned char *redTransferTable;
    unsigned char *greenTransferTable;
    unsigned char *blueTransferTable;

    /* The number of entries in the transfer table. */
    int transferTableCount;

    /* The current screen brightness. */
    int brightnessLevel;

    /* Reserved for future expansion. */
    unsigned int _VGA_reserved[8];
}
- (void)enterLinearMode;
- (void)revertToVGAMode;
- initFromDeviceDescription: deviceDescription;
- setBrightness:(int)level token:(int)t;
@end

@interface VGA (SetMode)
- determineConfiguration;
- selectMode;
- initializeMode;
- enableLinearFrameBuffer;
- resetVGA;
@end

@interface VGA (ConfigTable)
- (const char *)valueForStringKey:(const char *)key;
- (int)parametersForMode:(const char *)modeName
	forStringKey:(const char *)key
	parameters:(char *)parameters
	count:(int)count;
- (BOOL)booleanForStringKey:(const char *)key withDefault:(BOOL)defaultValue;
@end

#endif	/* VGA_H__ */
