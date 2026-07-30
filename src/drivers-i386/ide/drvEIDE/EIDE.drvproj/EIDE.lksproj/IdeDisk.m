/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * Copyright 1997-1998 by Apple Computer, Inc., All rights reserved.
 * Copyright 1994-1997 NeXT Software, Inc., All rights reserved.
 *
 * IdeDisk.m - Exported methods for IDE Disk device class. 
 *
 * HISTORY 
 * 07-Jul-1994	 Rakesh Dubey at NeXT
 *	Created from original driver written by David Somayajulu.
 */
 
#import <driverkit/return.h>
#import <driverkit/driverTypes.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDiskMethods.h>
#import <driverkit/IODevice.h>
#import <machkit/NXLock.h>
#import <sys/systm.h>
#import <bsd/dev/ata_hd_registry.h>

#import "IdeCnt.h"
#import "IdeDisk.h"
#import "IdeDiskInternal.h"
#import "IdeCntPublic.h"
#import "IdeKernel.h"

//#define DEBUG

/*
 * List of controllers that have been already probed. We need this since each
 * Instance table lists IdeDisk as well as IdeController classes. And we need
 * to create instances of disks attached to each controller only once. 
 */
static int probedControllerCount = 0;
static id probedControllers[MAX_IDE_CONTROLLERS];

@implementation IdeDisk

static Protocol *protocols[] = {
    @protocol(IdeControllerPublic),
    nil
};

+ (Protocol **)requiredProtocols
{
    return protocols;
}

+ (IODeviceStyle)deviceStyle
{
    return IO_IndirectDevice;
}

/*
 * IDE drives come with a built in controller on each drive. Hence we can
 * have just one object per controller-disk pair. Probe is invoked at load
 * time. It determines what drives are on the bus and alloc's and init:'s an
 * instance of this class for each one. 
 *
 */

+ (BOOL)probe : deviceDescription
{
    id diskId;
    IODevAndIdInfo *idMap;
    int globalUnit;
    int unit, i;
    id controllerId = [deviceDescription directDevice];

#ifdef DEBUG
    IOLog("IdeDisk probed with controller id %x\n", controllerId);
#endif DEBUG

    if (ata_hd_devsw_init(self, deviceDescription) == NO) {
	IOLog("IDEDisk: failed to initialize shared hd devsw tables.\n");
	return NO;
    }
    
    for (i = 0; i < probedControllerCount; i++)	{
    	if (probedControllers[i] == controllerId)	{
	    //IOLog("IdeDisk already probed for controller %x\n", controllerId);
	    return YES;
	}
    }
    probedControllers[probedControllerCount++] = controllerId;
//  IOLog("IdeDisk probing for controller %x\n", controllerId);
	
    for (unit = 0; unit < MAX_IDE_DRIVES; unit++) {
    
	diskId = [[IdeDisk alloc] initFromDeviceDescription:deviceDescription];
	[diskId initResources:controllerId];

	globalUnit = ata_hd_register(diskId, IdeDiskTransportIoctl, &idMap);
	if (globalUnit < 0) {
	    [diskId free];
	    IOLog("IDEDisk: failed to allocate shared hd unit.\n");
	    return NO;
	}
	[diskId setDevAndIdInfo:idMap];

	if ([diskId ideDiskInit:(unsigned int)globalUnit target:unit] == NO) {
	    if (ata_hd_unregister(globalUnit) != IO_R_SUCCESS)
		IOLog("IDEDisk: failed to release shared hd unit %d.\n",
		      globalUnit);
	    [diskId free];
	    continue;
	}

	/*
	 * Success; we initialized a drive. Have DiskObject superclass take
	 * care of the rest.
	 */
	[diskId setDeviceKind:"IDEDisk"];
	[diskId setIsPhysical:YES];
	if ([diskId registerDevice] == nil) {
	    if (ata_hd_unregister(globalUnit) != IO_R_SUCCESS)
		IOLog("IDEDisk: failed to release shared hd unit %d.\n",
		      globalUnit);
	    [diskId free];
	    IOLog("IDEDisk: failed to publish shared hd unit %d.\n",
		  globalUnit);
	    return NO;
	}
    }
    
    return YES;
}

/*
 * Common read/write methods. These are used directly in the kernel; user-level
 * methods using remote objects as defined in IODevice.h in turn call these.
 */
- (IOReturn) readAt		: (unsigned)offset 
				    length : (unsigned)length 
				    buffer : (unsigned char *)buffer
				    actualLength : (unsigned *)actualLength 
				    client : (vm_task_t)client
{
    IOReturn rtn;
	
    rtn = [self deviceRwCommon : IDEC_READ
	    block : offset
	    length : length 
	    buffer : buffer
	    client: client
	    pending : NULL
	    actualLength : actualLength];
    return(rtn);
}				  

- (IOReturn) readAsyncAt	: (unsigned)offset 
				    length : (unsigned)length 
				    buffer : (unsigned char *)buffer
				    pending : (void *)pending
				    client : (vm_task_t)client
{
    IOReturn rtn;
	
    rtn = [self deviceRwCommon : IDEC_READ
	    block : offset
	    length : length 
	    buffer : buffer
	    client : client
	    pending : (void *)pending
	    actualLength : NULL];
    return(rtn);
}				  
		
- (IOReturn) writeAt		: (unsigned)offset 
				  length : (unsigned)length 
				  buffer : (unsigned char *)buffer
				  actualLength : (unsigned *)actualLength 
				  client : (vm_task_t)client
{
    IOReturn rtn;
    
    rtn = [self deviceRwCommon : IDEC_WRITE
	    block : offset
	    length : length 
	    buffer : buffer
	    client: client
	    pending : NULL
	    actualLength : actualLength];

    return(rtn);
}				  
		  
- (IOReturn) writeAsyncAt	: (unsigned)offset 
				  length : (unsigned)length 
				  buffer : (unsigned char *)buffer
				  pending : (void *)pending
				  client : (vm_task_t)client
{
    IOReturn rtn;
    
    rtn = [self deviceRwCommon : IDEC_WRITE
	    block : offset
	    length : length 
	    buffer : buffer
	    client : client
	    pending : (void *)pending
	    actualLength : NULL];
    return(rtn);
}				  

- (IOReturn)updatePhysicalParameters
{
    // we have got everything we need during initialization

    return(IO_R_SUCCESS);
}

- (void)abortRequest
{
    ideBuf_t *ideBuf;
    IOReturn rtn;
    
    ideBuf = [self allocIdeBuf:NULL];
    ideBuf->command = IDEC_ABORT;
    ideBuf->buf = NULL;
    ideBuf->needsDisk =  0;
    ideBuf->oneWay = 0;
    rtn = [self enqueueIdeBuf:ideBuf];
    [self freeIdeBuf:ideBuf];
}

- (void)diskBecameReady
{
    [_ioQLock lock];
    [_ioQLock unlockWith:WORK_AVAILABLE];
}

- (IOReturn)isDiskReady	: (BOOL)prompt
{
    return(IO_R_SUCCESS);
}

- (IODiskReadyState)updateReadyState
{
    return([self lastReadyState]);
}

- (IOReturn) ejectPhysical
{
    return(IO_R_UNSUPPORTED);
}

- (int)deviceOpen:(u_int)intentions
{
    return(0);
}

- (void)deviceClose
{
    return;
}

- (ideDriveInfo_t)ideGetDriveInfo
{
    return(_ideInfo);
}

- (id)cntrlr
{
    return _cntrlr;
}

- (unsigned)driveNum
{
    return _driveNum;
}

- (IOReturn)getIntValues:(unsigned int *)values
	    forParameter:(IOParameterName)parameter
	    count:(unsigned int *)count
{
    int maxCount = *count;

    if (maxCount == 0) {
	maxCount = IO_MAX_PARAMETER_ARRAY_LENGTH;
    }
    
    if (strcmp(parameter, "BlockMajor") == 0) {
	values[0] = [[self class] blockMajor];
	*count = 1;
	return IO_R_SUCCESS;
    }
    if (strcmp(parameter, "CharacterMajor") == 0) {
	values[0] = [[self class] characterMajor];
	*count = 1;
	return IO_R_SUCCESS;
    }
    
    /*
     * Pass to superclass what we can't handle. 
     */
    return [super getIntValues:values forParameter:parameter
		count:&maxCount];
}

- property_IOUnit:(char *)result length:(unsigned int *)maxLen
{
    sprintf( result, "%d", [self driveNum]);
}

@end
