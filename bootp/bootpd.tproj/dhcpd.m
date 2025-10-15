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
 * dhcpd.m
 * - DHCP server
 */

/* 
 * Modification History
 * June 17, 1998 	Dieter Siegmund (dieter@apple.com)
 * - initial revision
 */
#import <unistd.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <sys/ioctl.h>
#import <sys/file.h>
#import <sys/time.h>
#import <net/if.h>
#import <netinet/in.h>
#import <netinet/in_systm.h>
#import <netinet/ip.h>
#import <netinet/udp.h>
#import <netinet/bootp.h>
#import <netinet/if_ether.h>
#import <syslog.h>
#import <arpa/inet.h>
#import <net/if_arp.h>
#import <mach/boolean.h>
#import "netinfo.h"
#import "dhcp.h"
#import "rfc_options.h"
#import "subnetDescr.h"
#import "dhcpOptions.h"
#import "dhcpOptionsPrivate.h"
#import "interfaces.h"
#import "bootpd.h"
#import "bootpdfile.h"
#import "dhcpd.h"

#define MAX_RETRY	5

#if DHCP
static void
S_remove_host(id domain, ni_id child)
{
    int		i;
    ni_id 	parent;
    ni_status	status;

    if ([domain handle] != ni_local) {
	syslog(LOG_INFO, "DHCP: can't remove non-local entry in %s",
	       [domain domain_name]);
	return;
    }
    status = ni_parent([domain handle], &child, &parent.nii_object);
    if (status != NI_OK) {
	syslog(LOG_ERR, "DHCP: can't get parent in %s\n", 
	       [domain domain_name]);
	return;
    }
    i = 0;
    do {
	ni_self([domain handle], &child);
	ni_self([domain handle], &parent);
	status = ni_destroy([domain handle], &parent, child);
	i++;
    } while (status == NI_STALE && i <= MAX_RETRY);
    if (status == NI_OK)
	return;
    syslog(LOG_ERR, "DHCP: failed to delete directory, %s",
	   ni_error(status));
}

static boolean_t
S_set_lease(id domain, ni_id * dir_p, ni_proplist * pl_p,
	    unsigned long lease_time)
{
    char 		buf[64];
    int			i;
    ni_namelist * 	nl_p;
    ni_status 		status;
    
    /* check that we're modifying the local domain */
    if ([domain handle] != ni_local) {
	syslog(LOG_ERR, 
	       "DHCP: entry for %s not the local domain",
	       inet_ntoa(iaddr));
	return (FALSE);
    }
    
    /* write the host entry with the new lease */
    nl_p = ni_nlforprop(pl_p, HOSTPROP__DHCP_LEASE);
    if (nl_p->ninl_len != 1)
	return (FALSE);

    ni_namelist_delete(nl_p, 0);
    sprintf(buf, "%ul", lease_time);
    ni_namelist_insert(nl_p, buf, 0);
    status = ni_write([domain handle], dir_p, *pl_p);
    i = 0;
    while (status == NI_STALE) { /* refresh and try again */
	if (++i == MAX_RETRY)
	    break;
	if (verbose)
	    syslog(LOG_INFO, 
		   "DHCP: lease update got stale handle, retrying %d", i);
	ni_self([domain handle], dir_p);
	status = ni_write([domain handle], dir_p, *pl_p);
    }
    if (status != NI_OK) {
	syslog(LOG_ERR, "DHCP: ni_write domain %s failed, %s",
	       [domain domain_name], ni_error(status));
	return (FALSE);
    }
    return (TRUE);
}

static unsigned long
S_lease_from_proplist(ni_proplist * pl_p)
{
    unsigned long	lease;
    ni_name 		lease_str;

    lease_str = ni_valforprop(pl_p, HOSTPROP__DHCP_LEASE);
    if (lease_str) {
	lease = strtoul(lease_str, NULL, NULL);
    }
    else
	/* if there is no lease, lease time is infinite */
	lease = DHCP_INFINITE_LEASE;
    return (lease);
}

#endif DHCP
/*
 * Function: is_dhcp_packet
 *
 * Purpose:
 *   Return whether packet is a DHCP packet.
 *   If the packet contains DHCP message ids, then its a DHCP packet.
 */
boolean_t
is_dhcp_packet(id options, dhcp_msgtype_t * msgtype)
{
    u_char * opt;
    int opt_len;

    if (options != nil) {
	opt = [options findOptionWithTag:dhcptag_dhcp_message_type_e
	       Length:&opt_len];
	if (opt != NULL) {
	    *msgtype = *opt;
	    return (TRUE);
	}
    }
    return (FALSE);
}

#if DHCP
static struct dhcp * 
S_make_dhcp_reply(interface_t * intface, dhcp_msgtype_t msg, 
		  struct dhcp * request, id * options_p)
{
    struct dhcp * reply;
    id options = nil;

    /* formulate a dhcp_offer message */
    reply = (struct dhcp *)malloc(sizeof(*reply) + DHCP_MIN_OPTIONS_SIZE);
    if (reply == NULL)
	goto err;

    *reply = *request;
    reply->dhp_secs = 0;
    reply->dhp_op = BOOTREPLY;
    bcopy(rfc_magic, reply->dhp_options, sizeof(rfc_magic));
    options = [[dhcpOptions alloc] 
	       initWithBuffer:reply->dhp_options + sizeof(rfc_magic) 
	       Size:DHCP_MIN_OPTIONS_SIZE - sizeof(rfc_magic)];
    if (options == nil) {
	syslog(LOG_INFO, "S_make_dhcp_reply: init options failed");
	goto err;
    }
    /* make the reply a dhcp message */
    if ([options dhcpMessage:msg] == FALSE) {
	syslog(LOG_INFO, 
	       "S_make_dhcp_reply: couldn't add dhcp message tag %d: %s", msg,
	       [options errString]);
	goto err;
    }
    /* add our server identifier */
    if ([options addOption:dhcptag_server_identifier_e
         Length:sizeof(intface->addr) Data:&intface->addr] == FALSE) {
	syslog(LOG_INFO, 
	       "S_make_dhcp_reply: couldn't add server identifier tag: %s",
	       [options errString]);
	goto err;
    }
    *options_p = options;
    return (reply);
  err:
    if (reply)
	free(reply);
    if (options != nil)
	[options free];
    *options_p = nil;
    return (NULL);
}

static struct hosts *		S_pending_hosts = NULL;

static boolean_t
S_ipinuse(void * arg, struct in_addr ip)
{
    u_char * 		host;
    ni_proplist 	pl;
    struct timeval * 	time_in_p = (struct timeval *)arg;
    
    if (lookup_host_by_ip(ip, &host, NULL, &pl)) {
	ni_proplist_free(&pl);
	if (verbose)
	    syslog(LOG_INFO, "DHCP: %s is in use %s%s\n", inet_ntoa(ip),
		   host[0] ? "by " : "",
		   host[0] ? host : (u_char *) "");
	free(host);
	return (TRUE);
    }
    else {
	struct hosts * hp = hostbyip(S_pending_hosts, ip);
	if (hp) {
	    u_long pending_secs = time_in_p->tv_sec - hp->tv.tv_sec;

	    if (pending_secs < DHCP_DEFAULT_PENDING_SECS) {
		if (verbose)
		    syslog(LOG_INFO, "DHCP: %s will remain pending %d secs\n",
			   DHCP_DEFAULT_PENDING_SECS - pending_secs);
		return (TRUE);
	    }
	    hostfree(&S_pending_hosts, hp); /* remove it from the list */
	}
    }
    return (FALSE);
}
#endif DHCP

void
dhcp_request(dhcp_msgtype_t dhcp_msgtype, interface_t * intface,
	     u_char * rxpkt, int n, id rq_options, struct timeval * time_in_p)
{
#if DHCP
    u_char *		bootfile = NULL;
    boolean_t		bound = FALSE;
    id			domain;
    ni_id		dir;
    u_char *		hostname = NULL;
    struct hosts *	hp;
    struct in_addr	iaddr;
    unsigned long	lease_delta;
    unsigned long	lease_time;
    boolean_t		lookup_error;
    id			options = nil;
    int		  	optlen;
    ni_proplist		pl;
    struct dhcp * 	reply = NULL;
    struct dhcp *	rq = (struct dhcp *)rxpkt;
    int			size;
    id			subnet = nil;

#endif DHCP

    if (debug) {
	printf("DHCP %s message\n", dhcp_msgtype_names(dhcp_msgtype));
	[rq_options print];
    }
#if DHCP
    NI_INIT(&pl);
    hp = hostbyaddr(S_pending_hosts, rq->dhp_htype, rq->dhp_chaddr, 
		    rq->dhp_hlen);
    bound = lookup_host_by_identifier(rq->dhp_htype, rq->dhp_chaddr, rq->dhp_hlen,
				      rq->dhp_giaddr, intface,
				      &iaddr, &hostname, &bootfile, 
				      &domain, &dir, &pl, &lookup_error);
    if (bound == FALSE && lookup_error)
	goto no_reply;
    if (bound) {
	subnet = [subnets entry:iaddr];
	if (subnet == nil) {
	    syslog(LOG_INFO, "can't locate subnet for '%s'", 
		   inet_ntoa(iaddr));
	    goto no_reply;
	}
	/* maybe check that subnet entry includes DHCP_CLIENT_TYPE? XXX */

	lease_time = S_lease_from_proplist(&pl);
    }
    else if (hp)
	iaddr = hp->iaddr;

    switch (dhcp_msgtype) {
      case dhcp_msgtype_discover_e: {
	  if (hp) { /* clear any existing temporary binding */
	      hostfree(&S_pending_hosts, hp);
	      hp = NULL;
	  }
	  if (bound) { /* client has a host entry */
	      if (lease_time == DHCP_INFINITE_LEASE)
		  ;
	      else if (time_in_p->tv_sec >= lease_time) {
		  /* expired, extend it for now */
		  /* XXX - should check if not in use */
		  lease_time = time_in_p->tv_secs + DHCP_LEASE_SECS;
		  if (S_set_lease(domain, &dir, &pl, lease_time) == FALSE)
		      goto no_reply;
	      }
	  }
	  else { /* find an ip address */
	      struct hosts * hp;

	      /* allocate a new ip address */
	      if (rq->dhp_giaddr.s_addr)
		  iaddr = rq->dhp_giaddr;
	      else
		  iaddr = intface->netaddr;
	      
	      if ([subnets acquireIpSupernet:&iaddr 
		   ClientType:DHCP_CLIENT_TYPE Func:S_ipinuse 
		   Arg:time_in_p] == FALSE) {
		  goto no_reply; /* out of ip addresses */
	      }
	      hp = hostadd(&S_pending_hosts, time_in_p, rq->dhp_htype, 
			   rq->dhp_chaddr, rq->dhp_hlen, &iaddr, NULL, NULL);
	      if (hp == NULL)
		  goto no_reply;

	      /* store the lease time */
	      lease_time = hp->lease = time_in_p->tv_secs + DHCP_LEASE_SECS;

	      if (verbose) {
		  syslog(LOG_INFO, "DHCP: pending host (%d seconds):",
			 DHCP_PENDING_SECS);
		  hostprint(hp);
	      }
	  }
	      
	  if (lease_time == DHCP_INFINITE_LEASE)
	      lease_delta = htonl(DHCP_INFINITE_LEASE);
	  else
	      lease_delta 
		  = htonl(lease_pro_rate(lease_time - time_in_p->tv_secs));
	  
	  /* form a reply */
	  reply = S_make_dhcp_reply(intface, dhcp_msgtype_offer_e, rq, 
				    &options);
	  if (reply == NULL)
	      goto no_reply;
	  reply->ciaddr.s_addr = 0;
	  reply->yiaddr = iaddr;
	  if (bootp_add_bootfile(rq->dhp_file, hostname, boot_home_dir,
				 bootfile, boot_default_file, 
				 boot_tftp_dir, reply->file) == FALSE)
	      goto no_reply;
	  if ([options addOption:dhcptag_ip_address_lease_time_e
	       Length:sizeof(lease_delta) Data:&lease_delta] == FALSE) {
	      syslog(LOG_INFO, "couldn't add lease time tag: %s",
		     [options errString]);
	      goto no_reply;
	  }
	  { /* add the client-specified parameters */
	      u_char *	 	params;
	      int		num_params;
	      params = (char *)
		  [rq_options 
		   findOptionWithTag:dhcptag_parameter_request_list_e
	           Length:&num_params];
	      add_subnet_options(iaddr, intface, options, params, num_params);
	  }
	  if ([options addOption:dhcptag_end_e Length:0 Data:NULL] == FALSE) {
	      syslog(LOG_INFO, "couldn't add end tag: %s",
		     [options errString]);
	      goto no_reply;
	  }
	  if (debug) {
	      printf("Sending the following to the client\n");
	      [options parse];
	      [options print];
	  }
	  size = sizeof(struct dhcp) + sizeof(rfc_magic) 
	      + [options bufferUsed];
	  sendreply(intface, (struct bootp *)reply, size, 0);
	  break;
      }
      case dhcp_msgtype_request_e: {
	  struct in_addr * 	req_ip;
	  struct in_addr *	server_ip;
	  dhcp_cstate_t		state;
	    
	  server_ip = (struct in_addr *)
	      [rq_options findOptionWithTag:dhcptag_server_identifier_e
	       Length:&optlen];
	  req_ip = (struct in_addr *)
	      [rq_options findOptionWithTag:dhcptag_requested_ip_address_e
	       Length:&optlen];
	  if (server_ip) {
	      if (req_ip == NULL)
		  goto no_reply;
	      state = dhcp_cstate_selecting_e;
	  }
	  else {
	      if (req_ip)
		  state = dhcp_cstate_init_reboot_e;
	      else {
		  if (/* client message was a broadcast */)
		      state = dhcp_cstate_rebind_e;
		  else
		      state = dhcp_cstate_renew_e;
	      }
	  }
	  if (debug) {
	      printf("DHCP_REQUEST: %s", dhcp_cstate_str(state));
	      if (req_ip)
		  printf(" requested ip %s", inet_ntoa(*req_ip));
	      printf("\n");
	  }
	  switch (state) {
	    case dhcp_cstate_selecting_e:
	      if (server_ip->s_addr != intface->addr.s_addr) {
		  /* not for us */
		  if (verbose)
		      syslog(LOG_INFO, "DHCP: client %s has chosen %s over us",
			     hostname, inet_ntoa(*server_ip));
		  /* clean up */
		  if (hp)
		      hostfree(&S_pending_hosts, hp);
		  if (bound) {
		      unsigned long l = S_lease_from_proplist(&pl);
		      if (l == DHCP_INFINITE_LEASE)
			  ; /* leave it alone if infinite */
		      else /* remove the host entry */
			  S_remove_host(domain, &dir);
		  }
		  goto no_reply;
	      }
	      break;

	    case dhcp_cstate_init_reboot_e:
	      /* if requested ip is on the wrong network, send nak */
	      goto no_reply;
	      break;

	    case dhcp_cstate_renew_rebind_e:
	      /* check that ciaddr is correct */
	      
	      break;

	    default:
	      break;
	  }

	  /* form a reply */
	  reply = S_make_dhcp_reply(intface, dhcp_msgtype_ack_e, rq, &options);
	  if (reply == NULL)
	      goto no_reply;
	  reply->yiaddr = iaddr;
	  if (bootp_add_bootfile(rq->dhp_file, hostname, boot_home_dir,
				 bootfile, boot_default_file, 
				 boot_tftp_dir, reply->file) == FALSE)
	      goto no_reply;
	  if ([options addOption:dhcptag_ip_address_lease_time_e
	       Length:sizeof(lease_time) Data:&lease_time] == FALSE) {
	      syslog(LOG_INFO, "couldn't add lease time tag: %s",
		     [options errString]);
	      goto no_reply;
	  }
	  { /* add the client-specified parameters */
	      u_char *	 	params;
	      int		num_params;
	      params = (char *)
		  [rq_options 
		   findOptionWithTag:dhcptag_parameter_request_list_e
	           Length:&num_params];
	      add_subnet_options(iaddr, intface, options, params, num_params);
	  }
	  if ([options addOption:dhcptag_end_e Length:0 Data:NULL] == FALSE) {
	      syslog(LOG_INFO, "couldn't add end tag: %s",
		     [options errString]);
	      goto no_reply;
	  }
	  if (debug) {
	      printf("Sending the following to the client\n");
	      [options parse];
	      [options print];
	  }
	  size = sizeof(struct dhcp) + sizeof(rfc_magic)
	      + [options bufferUsed];
	  if (sendreply(intface, (struct bootp *)reply, size, 0))
	      syslog(LOG_INFO, "reply sent %s %s pktsize %d",
		     hostname, inet_ntoa(iaddr), size);
	  break;
      }
      case dhcp_msgtype_decline_e:
	printf("decline ignored\n");
	break;
      case dhcp_msgtype_release_e:
	printf("release ignored\n");
	break;
      case dhcp_msgtype_inform_e:
	printf("inform ignored\n");
	break;
      default:
	printf("unknown message ignored\n");
	break;
    }
  no_reply:
    if (hostname)
	free(hostname);
    if (bootfile)
	free(bootfile);
    if (reply)
	free(reply);
    if (options != nil)
	[options free];
    ni_proplist_free(&pl);
#endif DHCP
    return;
}

