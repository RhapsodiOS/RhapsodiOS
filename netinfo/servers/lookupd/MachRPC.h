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
	MachRPC.h

	Custom RPC on top of Mach IPC for lookupd
	
	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
 */

#if NS_TARGET_MAJOR == 3
#import <foundation/NSObject.h>
#else
#import <Foundation/NSObject.h>
#endif

#import "LUDictionary.h"
#import "LUArray.h"
#import "Controller.h"
#import "XDRSerializer.h"

@interface MachRPC : NSObject
{
	XDRSerializer *xdr;
	SEL userSel;
	SEL userSel_A;
	SEL groupSel;
	SEL userShadowedSel;
	SEL userShadowedSel_A;
	SEL groupShadowedSel;
	SEL hostSel;
	SEL networkSel;
	SEL serviceSel;
	SEL protocolSel;
	SEL rpcSel;
	SEL mountSel;
	SEL printerSel;
	SEL bootparamsSel;
	SEL bootpSel;
	SEL aliasSel;
	SEL netgroupSel;
}

- (MachRPC *)init:(id)sender;

- (BOOL)process:(lookup_msg *)request;

- (BOOL)process:(int)procno
	inData:(char *)indata
	inLength:(unsigned int)inlen
	outData:(char **)outdata
	outLength:(unsigned int *)outlen
	privileged:(BOOL)privileged;

- (BOOL)xdrNetgroup:(LUDictionary *)item
	buffer:(char **)data
	length:(int *)len
	server:(LUServer *)server;

- (BOOL)xdrInt:(int)i buffer:(char **)data length:(int *)len;

- (BOOL)xdrList:(LUArray *)list
	method:(SEL)method
	buffer:(char **)data
	length:(int *)len
	server:(LUServer *)server;

- (BOOL)xdrItem:(LUDictionary *)item
	method:(SEL)method
	buffer:(char **)data
	length:(int *)len;

- (BOOL)xdrInitgroups:(LUArray *)list buffer:(char **)data length:(int *)len;

@end
