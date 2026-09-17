/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */
/* 	Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved.
 *
 * IODeviceMaster.m
 *
 * Shaped like src/driverkit-3/libDriver/User/IODeviceMaster.m.
 * Reference InstallPPDev defines these methods locally and also defines
 * the MIG stubs (__IOGetCharValues and friends) in __TEXT,__text.
 */

#import "IODeviceMaster.h"
#import <driverkit/driverServer.h>
#import <mach/port.h>

static IODeviceMaster *thisTasksId = nil;

/*
 * Apple's InstallPPDev nlist names the mach-port MIG stub _IOCreateMachPort
 * (three arguments). Darwin driverServer.defs renamed that routine to
 * _IOServerConnect and added clientTask. Keep the Darwin stub and expose
 * Apple's symbol as a wrapper so the names pair without -lDriver.
 */
IOReturn
_IOCreateMachPort(port_t deviceMaster, IOObjectNumber objectNumber, port_t *machPort)
{
	return _IOServerConnect(deviceMaster, objectNumber, task_self(), machPort);
}

@implementation IODeviceMaster

+ new
{
	if(thisTasksId == nil) {
		thisTasksId = [self alloc];
		thisTasksId->_deviceMasterPort = device_master_self();
	}
	return thisTasksId;
}

- free
{
	return self;
}

- (IOReturn)lookUpByObjectNumber	: (IOObjectNumber)objectNumber
			     deviceKind : (IOString *)deviceKind
			     deviceName : (IOString *)deviceName
{
	return _IOLookupByObjectNumber(_deviceMasterPort,
		objectNumber,
		deviceKind,
		deviceName);
}

- (IOReturn)lookUpByDeviceName		: (IOString)deviceName
			   objectNumber : (IOObjectNumber *)objectNumber
			     deviceKind : (IOString *)deviceKind
{
	return _IOLookupByDeviceName(_deviceMasterPort,
		deviceName,
		objectNumber,
		deviceKind);
}

- (IOReturn)getIntValues		: (unsigned *)parameterArray
			   forParameter : (IOParameterName)parameterName
			   objectNumber : (IOObjectNumber)objectNumber
			          count : (unsigned *)count
{
	return _IOGetIntValues(_deviceMasterPort,
		objectNumber,
		parameterName,
		*count,
		parameterArray,
		count);
}

- (IOReturn)getCharValues		: (unsigned char *)parameterArray
			   forParameter : (IOParameterName)parameterName
			   objectNumber : (IOObjectNumber)objectNumber
			          count : (unsigned *)count
{
	return _IOGetCharValues(_deviceMasterPort,
		objectNumber,
		parameterName,
		*count,
		parameterArray,
		count);
}

- (IOReturn)setIntValues		: (unsigned *)parameterArray
			   forParameter : (IOParameterName)parameterName
			   objectNumber : (IOObjectNumber)objectNumber
			          count : (unsigned)count;
{
	return _IOSetIntValues(_deviceMasterPort,
		objectNumber,
		parameterName,
		parameterArray,
		count);
}

- (IOReturn)setCharValues		: (unsigned char *)parameterArray
			   forParameter : (IOParameterName)parameterName
			   objectNumber : (IOObjectNumber)objectNumber
			          count : (unsigned)count;
{
	return _IOSetCharValues(_deviceMasterPort,
		objectNumber,
		parameterName,
		parameterArray,
		count);
}

- (IOReturn)createMachPort:(port_t *)machPort
	      objectNumber:(IOObjectNumber)objectNumber
{
	return _IOCreateMachPort(_deviceMasterPort, objectNumber, machPort);
}

@end
