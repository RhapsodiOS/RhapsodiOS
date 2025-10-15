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
 * dhcpOptionsPrivate.h
 */
#import "dhcpOptions.h"
#import "gen_dhcp_types.h"

/*
 * DHCP_OPTION_MAX
 * - the largest size that an option can be (limited to an 8-bit quantity)
 */
#define DHCP_OPTION_MAX	255

#define TAG_OFFSET	0
#define LEN_OFFSET	1
#define OPTION_OFFSET	2

@interface dhcpOptions(Private)
+ (tag_info_t *) tagInfo:(int)tag;
- (tag_info_t *) tagInfo:(int)tag;

+ (type_info_t *) typeInfo:(int)type;
- (type_info_t *) typeInfo:(int)type;

+ (boolean_t) str:(unsigned char *)str ToType:(int)type Buffer:(void *)buf
 Length:(int *)len_p ErrorString:(unsigned char *)err;
- (boolean_t) str:(unsigned char *)str ToType:(int)type Buffer:(void *)buf
 Length:(int *)len_p;

+ (boolean_t) str:(u_char *)tmp FromOption:(void *)opt Length:(int)len 
 Type:(int)type ErrorString:(u_char *)err;
+ (boolean_t) strList:(unsigned char * *)slist Number:(int)num
 Tag:(int)tag Buffer:(void *)buf Length:(int *)len_p 
 ErrorString:(unsigned char *)err;
- (boolean_t) strList:(unsigned char * *)slist Number:(int)num
 Tag:(int)tag Buffer:(void *)buf Length:(int *)len_p;

- (void) printType:(dhcptype_t)type Option:(void *)option Length:(int)opt_len;
- (boolean_t) printOption:(void *)opt;
- (void) print;
+ (void) printData:(void *) data_p Length:(int) n_bytes;
@end
