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
 * dhcp.h
 * - definitions for DHCP (as specified in RFC2132)
 */
#import <sys/types.h>
#import <netinet/in.h>
#import <netinet/in_systm.h>
#import <netinet/ip.h>
#import <netinet/udp.h>

struct dhcp {
    u_char		dhp_op;		/* packet opcode type */
    u_char		dhp_htype;	/* hardware addr type */
    u_char		dhp_hlen;	/* hardware addr length */
    u_char		dhp_hops;	/* gateway hops */
    u_int32_t		dhp_xid;	/* transaction ID */
    u_int16_t		dhp_secs;	/* seconds since boot began */	
    u_int16_t		dhp_flags;	/* flags */
    struct in_addr	dhp_ciaddr;	/* client IP address */
    struct in_addr	dhp_yiaddr;	/* 'your' IP address */
    struct in_addr	dhp_siaddr;	/* server IP address */
    struct in_addr	dhp_giaddr;	/* gateway IP address */
    u_char		dhp_chaddr[16];/* client hardware address */
    u_char		dhp_sname[64];	/* server host name */
    u_char		dhp_file[128];	/* boot file name */
    u_char		dhp_options[0];/* variable-length options field */
};

struct dhcp_packet {
    struct ip 		ip;
    struct udphdr 	udp;
    struct dhcp 	dhcp;
};

#define DHCP_MIN_OPTIONS_SIZE	312

/* dhcp message types */
#define DHCPDISCOVER	1
#define DHCPOFFER	2
#define DHCPREQUEST	3
#define DHCPDECLINE	4
#define DHCPACK		5
#define DHCPNAK		6
#define DHCPRELEASE	7
#define DHCPINFORM	8

typedef enum {
    dhcp_msgtype_discover_e 	= DHCPDISCOVER,
    dhcp_msgtype_offer_e	= DHCPOFFER,
    dhcp_msgtype_request_e	= DHCPREQUEST,
    dhcp_msgtype_decline_e	= DHCPDECLINE,
    dhcp_msgtype_ack_e		= DHCPACK,
    dhcp_msgtype_nak_e		= DHCPNAK,
    dhcp_msgtype_release_e	= DHCPRELEASE,
    dhcp_msgtype_inform_e	= DHCPINFORM,
} dhcp_msgtype_t;

static __inline__ unsigned char *
dhcp_msgtype_names(dhcp_msgtype_t type)
{
    unsigned char * names[] = {
	"DISCOVER",
	"OFFER",
	"REQUEST",
	"DECLINE",
	"ACK",
	"NAK",
	"RELEASE",
	"INFORM",
    };
    if (type >= DHCPDISCOVER && type <= DHCPINFORM)
	return (names[type - 1]);
    return ("<unknown>");
}

#define DHCP_INFINITE_LEASE	((u_int32_t)0xffffffff)

#define DHCP_FLAGS_BROADCAST	((u_short)0x0001)
