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

#import <unistd.h>
#import <stdlib.h>
#import <stdio.h>
#import <netinet/in.h>
#import <sys/types.h>
#import <mach/boolean.h>
#import <string.h>

typedef struct {
	struct in_addr	start;
	struct in_addr	end;
} ip_range_t;

static __inline__
u_long iptohl(struct in_addr ip)
{
    return (ntohl(ip.s_addr));
}

static __inline__
struct in_addr hltoip(u_long l)
{
    struct in_addr ip;

    ip.s_addr = htonl(l);
    return (ip);
}

static __inline__ boolean_t
in_subnet(struct in_addr netaddr, struct in_addr netmask, struct in_addr ip)
{
    if ((iptohl(ip) & iptohl(netmask)) != iptohl(netaddr)) {
	return (FALSE);
    }
    return (TRUE);
}


static __inline__
int ipRangeCmp(ip_range_t * a_p, ip_range_t * b_p, boolean_t * overlap)
{
    u_long		b_start = iptohl(b_p->start);
    u_long		b_end = iptohl(b_p->end);
    u_long		a_start = iptohl(a_p->start);
    u_long		a_end = iptohl(a_p->end);
    int			result;
    
    result =  b_start - a_start;
    *overlap = FALSE;
    if (result == 0
	|| (result < 0 && b_end >= a_start)
	|| (result > 0 && a_end >= b_start))
	*overlap = TRUE;
    return (result);
}


/* nbits_host: number of bits of host address */
static __inline__ int
nbits_host(struct in_addr mask)
{
    u_long l = iptohl(mask);
    int i;

    for (i = 0; i < 32; i++) {
	if (l & (1 << i))
	    return (32 - i);
    }
    return (32);
}

static __inline__ u_char *
inet_nettoa(struct in_addr addr, struct in_addr mask)
{
    u_char *		addr_p;
    int 		nbits = nbits_host(mask);
    int 		nbytes;
    static u_char 	sbuf[32];
    u_char 		tmp[8];

#define NBITS_PER_BYTE	8    
    sbuf[0] = '\0';
    nbytes = (nbits + NBITS_PER_BYTE - 1) / NBITS_PER_BYTE;
//    printf("-- nbits %d, nbytes %d--", nbits, nbytes);
    for (addr_p = (u_char *)&addr.s_addr; nbytes > 0; addr_p++) {

	sprintf(tmp, "%d%s", *addr_p, nbytes > 1 ? "." : "");
	strcat(sbuf, tmp);
	nbytes--;
    }
    if (nbits % NBITS_PER_BYTE) {
	sprintf(tmp, "/%d", nbits);
	strcat(sbuf, tmp);
    }
    return (sbuf);
}

static __inline__ long
random_range(long bottom, long top)
{
    long number = top - bottom + 1;
    long range_size = LONG_MAX / number;
    return (random() / range_size + bottom);
}
