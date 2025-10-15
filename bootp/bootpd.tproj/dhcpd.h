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
 * dhcpd.h
 * - DHCP server definitions
 */
boolean_t
is_dhcp_packet(id options, dhcp_msgtype_t * msgtype);

void
dhcp_request(dhcp_msgtype_t dhcp_msgtype, interface_t * intface,
	     u_char * rxpkt, int n, id rq_options, struct timeval * time_in_p);

#define DHCP_CLIENT_TYPE		"dhcp"

#define SECS_PER_MIN			60
#define MIN_PER_HOUR			60

/* default time to leave an ip address pending before re-using it */
#define DHCP_PENDING_SECS		SECS_PER_MIN

/* default time to lease an ip address is one hour */
//#define DHCP_LEASE_SECS		(1 * MIN_PER_HOUR * SECS_PER_MIN)


/* for testing, 5 min. */
#define DHCP_LEASE_SECS			(5 * SECS_PER_MIN)

#define HOSTPROP__DHCP_LEASE		"_dhcp_lease"

typedef enum {
    dhcp_cstate_selecting_e 	= 0,
    dhcp_cstate_init_reboot_e	= 1,
    dhcp_cstate_renew_e		= 2,
    dhcp_cstate_rebind_e	= 3,
    dhcp_cstate_last_e		= dhcp_cstate_rebind_e,
} dhcp_cstate_t;


static __inline__ const u_char *
dhcp_cstate_str(dhcp_cstate_t state)
{
    static const char * list[] = {"SELECTING", "INIT-REBOOT", "RENEW/REBIND"};
    if (state <= dhcp_cstate_last_e)
	return list[state];
    return ("<undefined>");
}

static __inline__ unsigned long
lease_pro_rate(unsigned long l)
{
    unsigned long t = l * 900 / 1000; /* 90% of the lease */
    return (t ? t : l); /* 90% of the lease, unless that's zero, the lease */
}
