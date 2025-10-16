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
#import <mach/mach.h>


typedef void (*_NSSKPortProc)( msg_header_t *msg, void *userData );
  /* Callback proc for ports registered by _NSSKAddPort. */

typedef struct __DPSTimedEntry *_NSSKTimedEntry;

typedef void (*_NSSKTimedEntryProc)(
    _NSSKTimedEntry te,
    double now,
    void *userData );
/* Callback proc for timed entries registered by DPSAddTimedEntry. */


/*
 * Prototypes for obsolete functions.
 */
void _NSSKAddPort(port_t newPort, _NSSKPortProc handler, int maxSize, void *userData, int priority);

void _NSSKRemovePort(port_t machPort);

_NSSKTimedEntry _NSSKAddTimedEntry(double period, _NSSKTimedEntryProc handler, void *userData, int priority);

void _NSSKRemoveTimedEntry(_NSSKTimedEntry te);