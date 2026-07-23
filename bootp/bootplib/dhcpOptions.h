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
 * dhcpOptions.h
 */

/*
 * Modification History:
 *
 * December 15, 1997	Dieter Siegmund (dieter@apple)
 * - created
 */

#import <objc/Object.h>

#import <mach/boolean.h>

#import "dhcp.h"

@interface dhcpOptions : Object
{
    int			option_count;	/* number of options parsed */
    unsigned char * *	options;	/* option array */
    int			options_size;	/* current size of option array */
    void *		buffer;		/* buffer containing options */
    int			buffer_size;	/* buffer size */
    int			options_end;	/* position within buffer of next */
					/* option to write */
    unsigned char	errString[128];	/* error string */
    boolean_t		good_parse;	/* contents of options is valid */
    boolean_t		end_tag_present;/* end tag added */
}

- free;
- init;
- initWithBuffer:(void *)buffer Size:(int)size;
- (boolean_t)parse;
- (void *)findOptionWithTag:(int)tag Length:(int *)len_p;
- (unsigned char *) errString;
- setBuffer:(void *)buffer Size:(int)size;
- (boolean_t) dhcpMessage:(dhcp_msgtype_t)m;
- (boolean_t) addOption:(int)tag Length:(int)len Data:(void *)data;
- (boolean_t) addOption:(int)tag FromString:(unsigned char *)str;
- (int) freeSpace;
- (int) bufferUsed;
@end
