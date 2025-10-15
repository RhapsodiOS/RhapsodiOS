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
	XDRSerializer.m

	XDR serializer for lookupd property lists

	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "XDRSerializer.h"
#import <netinfo/lookup_types.h>
#import "_lu_types.h"
#import "Syslog.h"
#import "LUGlobal.h"
#import <stdlib.h>
#import <string.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import "stringops.h"

extern struct ether_addr *ether_aton(char *);
extern void xdr_free();

@implementation XDRSerializer

- (void)encodeString:(char *)key
	from:(LUDictionary *)item
	intoXdr:(XDR *)xdrs
{
	char *value;

	value = [item valueForKey:key];
	if (value == NULL) [self encodeString:"" intoXdr:xdrs];
	else [self encodeString:value intoXdr:xdrs];
}

- (void)encodeInt:(char *)key
	from:(LUDictionary *)item
	intoXdr:(XDR *)xdrs
{
	char *value;
	int i;

	value = [item valueForKey:key];
	if (value == NULL)
	{
		i = 0;
		[self encodeInt:i intoXdr:xdrs];
		return;
	}

	i = atoi(value);
	if (!xdr_int(xdrs, &i))
	{
		[lookupLog syslogWarning:"xdr_int failed"];
	}
}

- (void)encodeIPAddr:(char *)key
	from:(LUDictionary *)item
	intoXdr:(XDR *)xdrs
{
	char *value;
	unsigned long i;

	value = [item valueForKey:key];
	if (value == NULL)
	{
		i = 0;
		[self encodeUnsignedLong:i intoXdr:xdrs];
		return;
	}

	i = inet_addr((char *)value);
	if (!xdr_u_long(xdrs, &i))
	{
		[lookupLog syslogWarning:"xdr_u_long failed"];
	}
}

- (void)encodeNetAddr:(char *)key
	from:(LUDictionary *)item
	intoXdr:(XDR *)xdrs
{
	char *value;
	unsigned long i;

	value = [item valueForKey:key];
	if (value == NULL)
	{
		i = 0;
		[self encodeUnsignedLong:i intoXdr:xdrs];
		return;
	}

	i = inet_network((char *)value);
	if (!xdr_u_long(xdrs, &i))
	{
		[lookupLog syslogWarning:"xdr_u_long failed"];
	}
}

- (void)encodeENAddr:(char *)key
	from:(LUDictionary *)item
	intoXdr:(XDR *)xdrs
{
	char *value;
	struct ether_addr *ether;

	value = [item valueForKey:key];
	if (value == NULL)
	{
		ether = ether_aton("0:0:0:0:0:0");
		if (!xdr_opaque(xdrs, (caddr_t)ether, 6))
		{
			[lookupLog syslogWarning:"xdr_opaque failed"];
		}
		return;
	}

	ether = ether_aton((char *)value);
	if (!xdr_opaque(xdrs, (caddr_t)ether, 6))
	{
		[lookupLog syslogWarning:"xdr_opaque failed"];
	}
}

- (void)encodeStrings:(char *)key
	from:(LUDictionary *)item
	intoXdr:(XDR *)xdrs
	max:(int)maxCount
{
	unsigned long i, len;
	char **values;
	char str[128];

	values = [item valuesForKey:key];
	len = [item countForKey:key];
	if (len == IndexNull) len = 0;

	if (len > maxCount)
	{
		sprintf(str, "truncating at %d values", maxCount);
		[lookupLog syslogError:str];
		len = maxCount;
	}

	[self encodeUnsignedLong:len intoXdr:xdrs];

	for (i = 0; i < len; i++)
	{
		[self encodeString:values[i] intoXdr:xdrs];
	}
}

- (void)encodeIPAddrs:(char *)key
	from:(LUDictionary *)item
	intoXdr:(XDR *)xdrs
	max:(int)maxCount
{
	unsigned long i, len;
	char **values;
	unsigned long ip;
	char str[128];

	values = [item valuesForKey:key];
	len = [item countForKey:key];
	if (len == IndexNull) 
	{
		/* No addresses - insert a 0 */
		len = 1;
		[self encodeUnsignedLong:len intoXdr:xdrs];
		ip = 0;
		[self encodeUnsignedLong:ip intoXdr:xdrs];
		return;
	}

	if (len > maxCount)
	{
		sprintf(str, "truncating at %d values", maxCount);
		[lookupLog syslogError:str];
		len = maxCount;
	}

	[self encodeUnsignedLong:len intoXdr:xdrs];

	for (i = 0; i < len; i++)
	{
		ip = inet_addr((char *)values[i]);
		[self encodeUnsignedLong:ip intoXdr:xdrs];
	}
}

- (void)encodeString:(char *)aString intoXdr:(XDR *)xdrs
{
	if (!xdr_string(xdrs, &aString, _LU_MAXLUSTRLEN))
	{
		[lookupLog syslogWarning:"xdr_string failed"];
	}
}

- (void)encodeInt:(int)i intoXdr:(XDR *)xdrs
{
	if (!xdr_int(xdrs, &i))
	{
		[lookupLog syslogWarning:"xdr_int failed"];
	}
}

- (void)encodeBool:(BOOL)i intoXdr:(XDR *)xdrs
{
	bool_t b;

	b = i;
	if (!xdr_bool(xdrs, &b))
	{
		[lookupLog syslogWarning:"xdr_bool failed"];
	}
}

- (void)encodeUnsignedLong:(unsigned long)i intoXdr:(XDR *)xdrs
{
	if (!xdr_u_long(xdrs, &i))
	{
		[lookupLog syslogWarning:"xdr_u_long failed"];
	}
}

/* 
 * decode routines
 */
- (char *)stringFromBuffer:(char *)buf length:(int)len;
{
	char *str;
	XDR inxdr;

	xdrmem_create(&inxdr, buf, len, XDR_DECODE);
	str = NULL;
	if (!xdr__lu_string(&inxdr, &str)) return NULL;
	xdr_destroy(&inxdr);
	
	return str;
}

- (int)intFromBuffer:(char *)buf length:(int)len
{
	int i;
	XDR inxdr;

	xdrmem_create(&inxdr, buf, len, XDR_DECODE);
	if (!xdr_int(&inxdr, &i)) return 0;
	xdr_destroy(&inxdr);
	
	return i;
}

- (struct ether_addr)ethernetAddressFromBuffer:(char *)buf length:(int)len
{
	struct ether_addr en;
	XDR inxdr;

	bzero((char *)&en, sizeof(struct ether_addr));
	xdrmem_create(&inxdr, buf, len, XDR_DECODE);
	if (!xdr_opaque(&inxdr, (caddr_t)&en, sizeof(struct ether_addr)))
	{
		return en;
	}
	xdr_destroy(&inxdr);
	
	return en;
}

- (char **)twoStringsFromBuffer:(char *)buf length:(int)len
{
	char *str1, *str2;
	char **l = NULL;
	XDR inxdr;

	xdrmem_create(&inxdr, buf, len, XDR_DECODE);
	str1 = NULL;
	str2 = NULL;
	if (!xdr__lu_string(&inxdr, &str1) ||
	    !xdr__lu_string(&inxdr, &str2))
	{
		return NULL;
	}
	xdr_destroy(&inxdr);

	l = appendString(str1, l);
	l = appendString(str2, l);

	free(str1);
	free(str2);

	return l;
}

- (char **)intAndStringFromBuffer:(char *)buf length:(int)len
{
	int i;
	char *str;
	char **l = NULL;
	XDR inxdr;
	char num[64];

	xdrmem_create(&inxdr, buf, len, XDR_DECODE);
	str = NULL;
	if (!xdr_int(&inxdr, &i) ||
	    !xdr__lu_string(&inxdr, &str))
	{
		return NULL;
	}
	xdr_destroy(&inxdr);

	sprintf(num, "%d", i);
	l = appendString(num, l);
	l = appendString(str, l);
	free(str);
	return l;
}

- (char **)inNetgroupArgsFromBuffer:(char *)buf length:(int)len
{
	_lu_innetgr_args args;
	XDR inxdr;
	char **l = NULL;

	bzero(&args, sizeof(args));
	xdrmem_create(&inxdr, buf, len, XDR_DECODE);
	if (!xdr__lu_innetgr_args(&inxdr, &args))
	{
		return NULL;
	}
	xdr_destroy(&inxdr);

	l = appendString(args.group, l);

	if (args.host != NULL) l = appendString(*args.host, l);
	else l = appendString("", l);
	if (args.user != NULL) l = appendString(*args.user, l);
	else l = appendString("", l);
	if (args.domain != NULL) l = appendString(*args.domain, l);
	else l = appendString("", l);

	xdr_free(xdr__lu_innetgr_args, (void *)&args);

	return l;
}

@end
