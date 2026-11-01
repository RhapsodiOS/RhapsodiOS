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
 * PExpert.h
 * i386 platform expert: the one "Bus Class" behind which the EISA, PCI
 * and PCMCIA buses live, and the table they read their settings from.
 */

#ifndef _PEXPERT_H_
#define _PEXPERT_H_

#import <objc/Object.h>

/*
 * The "Bus Class" of the config table the kernel links in for the
 * platform expert (driverkit/i386/autoconf_i386.m).  The buses read their
 * settings ("PnP", "PnP Read Port", "Verbose", "PCMCIA Memory Base", ...)
 * out of that table.
 */
#define PEXPERT_BUS_CLASS	"PExpert"

/*
 * The kernel sends probeBus: to the class named by the "Bus Class" key of
 * every "Family" = "Bus" table before it configures any driver.  This one
 * brings the buses up in order and claims the motherboard's own resources.
 */
@interface PExpert : Object

+ (BOOL)probeBus:configTable;

@end

/*
 * Value of `key` in the PExpert table whose "Instance" is `instance`
 * (a table without one is instance 0), copied into IOMalloc'd storage
 * the caller frees with IOFree(p, strlen(p) + 1); NULL when the table
 * or the key is absent.
 */
char *PExpertAttribute(int instance, const char *key);

#endif /* _PEXPERT_H_ */
