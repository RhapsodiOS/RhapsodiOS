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

/*
 * IODeviceMaster.m
 * Device Master Interface
 */

#import "IODeviceMaster.h"

/* External device_master functions */
extern port_t device_master_self(void);
extern int IOCreateMachPort(port_t master, unsigned int objNum, port_t *port);
extern int IOGetCharValues(port_t master, unsigned int objNum, const char *param, unsigned int maxCount, char **values, unsigned int *count);
extern int IOGetIntValues(port_t master, unsigned int objNum, const char *param, unsigned int maxCount, unsigned int *values, unsigned int *count);
extern int IOLookupByDeviceName(port_t master, const char *name, unsigned int *objNum, const char **kind);
extern int IOLookupByObjectNumber(port_t master, unsigned int objNum, const char **kind, const char **name);
extern int IOSetCharValues(port_t master, unsigned int objNum, const char *param, const char **values, unsigned int count);
extern int IOSetIntValues(port_t master, unsigned int objNum, const char *param, const unsigned int *values, unsigned int count);

/* Static singleton instance */
static id thisTasksId = nil;

@implementation IODeviceMaster

/*
 * Create or return singleton instance
 */
+ new
{
    if (thisTasksId == nil) {
        thisTasksId = [super alloc];
        ((IODeviceMaster *)thisTasksId)->deviceMasterPort = device_master_self();
    }
    return thisTasksId;
}

/*
 * Create Mach port for device communication
 */
- createMachPort:(port_t *)port objectNumber:(unsigned int)objNum
{
    IOCreateMachPort(deviceMasterPort, objNum, port);
    return self;
}

/*
 * Free the device master
 */
- free
{
    return self;
}

/*
 * Get character string values for a parameter
 */
- (int)getCharValues:(char **)values forParameter:(const char *)param objectNumber:(unsigned int)objNum count:(unsigned int *)count
{
    return IOGetCharValues(deviceMasterPort, objNum, param, *count, values, count);
}

/*
 * Get integer values for a parameter
 */
- (int)getIntValues:(unsigned int *)values forParameter:(const char *)param objectNumber:(unsigned int)objNum count:(unsigned int *)count
{
    return IOGetIntValues(deviceMasterPort, objNum, param, *count, values, count);
}

/*
 * Look up device by name
 */
- (int)lookUpByDeviceName:(const char *)name objectNumber:(unsigned int *)objNum deviceKind:(const char **)kind
{
    return IOLookupByDeviceName(deviceMasterPort, name, objNum, kind);
}

/*
 * Look up device by object number
 */
- (int)lookUpByObjectNumber:(unsigned int)objNum deviceKind:(const char **)kind deviceName:(const char **)name
{
    return IOLookupByObjectNumber(deviceMasterPort, objNum, kind, name);
}

/*
 * Set character string values for a parameter
 */
- (int)setCharValues:(const char **)values forParameter:(const char *)param objectNumber:(unsigned int)objNum count:(unsigned int)count
{
    return IOSetCharValues(deviceMasterPort, objNum, param, values, count);
}

/*
 * Set integer values for a parameter
 */
- (int)setIntValues:(const unsigned int *)values forParameter:(const char *)param objectNumber:(unsigned int)objNum count:(unsigned int)count
{
    return IOSetIntValues(deviceMasterPort, objNum, param, values, count);
}

@end
