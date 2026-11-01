/* CONFIDENTIAL
 * Copyright (c) 1993-1996 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * S3Generic.h -- interface for S3 Generic display driver.
 *
 * Modified to support S3 Trio and Virge chipsets
 * Created by Peter Graffagnino 1/31/93
 * Modified by Derek B Clegg	21 May 1993
 */

#ifndef S3GENERIC_H__
#define S3GENERIC_H__

#import <driverkit/IOFrameBufferDisplay.h>
#import "S3GenericModes.h"

@interface S3Generic:IOFrameBufferDisplay
{
    /* The adapter type (805, 928, Trio32, Trio64, Virge, etc.) */
    S3AdapterType adapter;

    /* The memory installed on this device. */
    vm_size_t availableMemory;

    /* The type of DAC this device has. */
    DACtype dac;

    /* The bus configuration. */
    int busConfiguration;

    /* The table of valid modes for this device. */
    const IODisplayInfo *modeTable;

    /* The count of valid modes for this device. */
    unsigned int modeTableCount;

    /* The physical address of framebuffer. */
    unsigned long videoRamAddress;

    /* YES if the fast write buffer is enabled; NO otherwise. */
    BOOL writePostingEnabled;

    /* YES if the read-ahead cache is enabled; NO otherwise. */
    BOOL readAheadCacheEnabled;

    /* The transfer tables for this mode. */
    unsigned char *redTransferTable;
    unsigned char *greenTransferTable;
    unsigned char *blueTransferTable;

    /* The number of entries in the transfer table. */
    int transferTableCount;

    /* The current screen brightness. */
    int brightnessLevel;

    /* Reserved for future expansion. */
    unsigned int _S3Generic_reserved[8];
}
- (void)enterLinearMode;
- (void)revertToVGAMode;
- initFromDeviceDescription: deviceDescription;
- setBrightness:(int)level token:(int)t;
@end

@interface S3Generic (SetMode)
- determineConfiguration;
- selectMode;
- initializeMode;
- enableLinearFrameBuffer;
- resetVGA;
@end

@interface S3Generic (ProgramDAC)
- determineDACType;
- (BOOL)hasTransferTable;
- (BOOL)needsSoftwareGammaCorrection;
- resetDAC;
- programDAC;
- setGammaTable;
@end

@interface S3Generic (ConfigTable)
- (const char *)valueForStringKey:(const char *)key;
- (int)parametersForMode:(const char *)modeName
	forStringKey:(const char *)key
	parameters:(char *)parameters
	count:(int)count;
- (BOOL)booleanForStringKey:(const char *)key withDefault:(BOOL)defaultValue;
@end

#endif	/* S3GENERIC_H__ */
