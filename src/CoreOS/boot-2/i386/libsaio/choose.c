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
 * Copyright 1993 NeXT, Inc.
 * All rights reserved.
 */
 
#import "libsaio.h"
#import "drivers.h"


/*
 * Multiple-choice question, CDIS-style.
 * Localizable.
 */

static char *prompt = "\n---> ";

int chooseSimple( char **strings, int nstrings, int min, int max )
{
    char buf[80];
    register int num;
    
    for (num = 0; num < nstrings; num++) {
	localPrintf(strings[num]);
    }
    printf(prompt);
    gets(buf,sizeof(buf));
    num = atoi(buf);
    if (num < min || num > max) {
	return -1;
    }
    return num;
}

void clearScreen()
{
    register int i;
    for (i=0; i < 25; i++)
	putchar('\n');
}
