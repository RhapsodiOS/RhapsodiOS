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
 * bootpd.h
 */
void
add_subnet_options(struct in_addr iaddr, interface_t * intface,
		   id options, u_char * tags, int n);
boolean_t
bootp_add_bootfile(char * request_file, char * hostname, 
		   char * homedir, char * bootfile,
		   char * default_bootfile, 
		   char * tftp_homedir, char * reply_file);
boolean_t	
get_dhcp_option(id subnet, int tag, void * buf, int * len_p);

boolean_t
lookup_host_by_ip(struct in_addr ip, u_char * * name, u_char * * bootfile,
		  ni_proplist * pl_p);
boolean_t
lookup_host_by_identifier(u_char hwtype, void * hwaddr, int hwlen, 
			  struct in_addr giaddr, interface_t * intface, 
			  struct in_addr * ip, u_char * * name,
			  u_char * * bootfile, id * domain_p,
			  ni_id * dir_p, ni_proplist * pl_p,
			  boolean_t * error);
boolean_t
subnetAddressAndMask(struct in_addr giaddr, interface_t * intface,
		     struct in_addr * addr, struct in_addr * mask);
int
prop_index_subnet(ni_name prop, ni_name value, 
		  struct in_addr giaddr, interface_t * intface,
		  ni_proplist * proplist, boolean_t * error);
boolean_t	
sendreply(interface_t * intf, struct bootp * bp, int n,
	  int forward);
boolean_t
ip_address_reachable(struct in_addr ip, struct in_addr giaddr, 
		     interface_t * intface);
void
timestamp_syslog(char * msg);


extern unsigned char	rfc_magic[4];
extern int		debug;
extern void *		ni_local;
extern List *		niSearchDomains;
extern int 		niCreateDomain;
extern int		quiet;
extern u_char		rfc_magic[4];
extern id		subnets;
extern boolean_t	use_en_address;
extern int		verbose;

static __inline__ void
timeval_subtract(struct timeval * tv1, struct timeval * tv2, 
		 struct timeval * result)
{
#define USECS_PER_SEC	1000000
    result->tv_sec = tv1->tv_sec - tv2->tv_sec;
    result->tv_usec = tv1->tv_usec - tv2->tv_usec;
    if (result->tv_usec < 0) {
	result->tv_usec += USECS_PER_SEC;
	result->tv_usec -= 1;
    }
    return;
}

#define DHCP_OPTION_PREFIX	"dhcp_"
