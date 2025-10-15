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
	Syslog.h
	
	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
 */

#if NS_TARGET_MAJOR == 3
#import <foundation/NSObject.h>
#import <foundation/NSLock.h>
#else
#import <Foundation/NSObject.h>
#import <Foundation/NSLock.h>
#endif

#import <stdio.h>

@interface Syslog : NSObject
{
	char **messageQueue;
	char *priorityQueue;
	char *logIdent;
	int logOptions;
	int logFacility;
	int queueSize;
	NSConditionLock *qLock;
	FILE *fp;
}

- (Syslog *)initWithIdent:(char *)ident
	facility:(int)fac
	options:(int)opt;

- (Syslog *)initWithIdent:(char *)ident
	facility:(int)fac
	options:(int)opt
	logFile:(char *)logName;

- (void)setLogFile:(char *)fileName;
- (void)setLogFacility:(char *)facilityName;

- (void)log:(char *)message priority:(int)pri;

- (void)syslogEmergency:(char *)message;
- (void)syslogAlert:(char *)message;
- (void)syslogCritical:(char *)message;
- (void)syslogError:(char *)message;
- (void)syslogWarning:(char *)message;
- (void)syslogNotice:(char *)message;
- (void)syslogInfo:(char *)message;
- (void)syslogDebug:(char *)message;
- (void)logMessage:(char *)message;

@end
