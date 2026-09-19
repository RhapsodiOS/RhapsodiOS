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
 * bootpd.m
 * - BOOTP/DHCP server main
 * - see RFC951, RFC2131, RFC2132 for details on the BOOTP protocol, 
 *   BOOTP extensions/DHCP options, and the DHCP protocol
 */

/*
 * Modification History
 * 01/22/86	Croft	created.
 *
 * 03/19/86	Lougheed  Converted to run under 4.3 BSD inetd.
 *
 * 09/06/88	King	Added NeXT interrim support.
 *
 * 02/23/98	Dieter Siegmund (dieter@apple.com)
 *		- complete overhaul
 *		- added specialized Mac NC support
 *		- removed the NeXT "Sexy Net Init" code that performed
 *		  a proprietary form of dynamic BOOTP, since this
 *		  functionality is replaced by DHCP
 *		- added ability to respond to requests originating from 
 *		  a specific set of interfaces
 *		- added rfc2132 option handling
 *
 * June 5, 1998 	Dieter Siegmund (dieter@apple.com)
 * - do lookups using netinfo calls directly to be able to read/write
 *   entries and get subnet-specific bindings
 *
 * Oct 19, 1998		Dieter Siegmund (dieter@apple.com)
 * - provide domain name servers for this server if not explicitly 
 *   configured otherwise
 */

#import <unistd.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <sys/ioctl.h>
#import <sys/file.h>
#import <sys/time.h>
#import <sys/types.h>
#import <net/if.h>
#import <netinet/in.h>
#import <netinet/in_systm.h>
#import <netinet/ip.h>
#import <netinet/udp.h>
#import <netinet/bootp.h>
#import <netinet/if_ether.h>
#import <net/if_arp.h>
#import <mach/boolean.h>
#import <signal.h>
#import <stdio.h>
#import <string.h>
#import <errno.h>
#import <ctype.h>
#import <netdb.h>
#import <setjmp.h>
#import <syslog.h>
#import <varargs.h>
#import <arpa/inet.h>
#import <arpa/nameser.h>
#import <sys/uio.h>
#import <resolv.h>

#import "arp.h"
#import "netinfo.h"
#import "interfaces.h"
#import "inetroute.h"
#import "subnetDescr.h"
#import "dhcpOptions.h"
#import "dhcpOptionsPrivate.h"
#import "rfc_options.h"
#import "bootpd.h"
#import "hostlist.h"
#import "bootpdfile.h"
#import "macNC.h"
#import "NIHosts.h"
#import "host_identifier.h"
#import "dhcpd.h"

/* external functions */
extern int			useni();
extern char *  			ether_ntoa(struct ether_addr *e);
extern struct ether_addr *	ether_aton(char *);

/* local defines */
//#define SYSTEM_ARP  		1 /* see setarp() below */
#define	MAXIDLE			(5*60)	/* we hang around for five minutes */
#define	IGNORETIME		(2*60)	/* ignore host with no binding */
#define DOMAIN_HIERARCHY	"..."	/* ... means open the hierarchy */

/* global variables: */
int		debug = 0;
void *		ni_local = NULL; /* handle to local netinfo domain */
List *		niSearchDomains = nil;
int		niCreateDomain = -1; /* index into niSearchDomain */
int		quiet = 0;
unsigned char	rfc_magic[4] = RFC_OPTIONS_MAGIC;
id		subnets = nil;
boolean_t	use_en_address = TRUE;
int		verbose = 0;

/* local types */

/* local variables */
static boolean_t		S_bootfile_noexist_reply = TRUE;
static boolean_t		S_do_dhcp = FALSE;
static boolean_t		S_do_macNC = FALSE;
static id			S_domain_list = nil;
static struct in_addr *		S_dns_servers = NULL;
static int			S_dns_servers_count = 0;
static char *			S_domain_name = NULL;
static id			S_if_list = nil;
static struct hosts *		S_ignore_hosts = NULL;
static interface_list_t *	S_interfaces;
static inetroute_list_t *	S_inetroutes = NULL;
static u_short			S_ipport_client = IPPORT_BOOTPC;
static u_short			S_ipport_server = IPPORT_BOOTPS;
static struct timeval		S_lastmsgtime;
static u_char 			S_rxpkt[2048];/* receive packet buffer */
static boolean_t		S_sighup = TRUE; /* fake the 1st sighup */
#ifndef SYSTEM_ARP
static int			S_rtsockfd;
#endif SYSTEM_ARP
static int			S_sockfd;
static boolean_t		S_use_file = FALSE;

/* forward function declarations */
static int 		issock(int fd);
static void		on_alarm(int sigraised);
static void		on_sighup(int sigraised);
static void		bootp_request(interface_t *, void * bp, int len,
				      struct timeval *);
static void		reply(interface_t *);
static void		setarp(struct in_addr * ia, u_char * ha, int len);
static void		S_server_loop();

/*
 * Function: background
 *
 * Purpose:
 *   Daemon-ize ourselves.
 */
static void
background()
{
    if (fork())
	exit(0);
    { 
	int s;
	for (s = 0; s < 10; s++)
	    (void) close(s);
    }
    (void) open("/", O_RDONLY);
    (void) dup2(0, 1);
    (void) dup2(0, 2);
    {
	int tt = open("/dev/tty", O_RDWR);
	if (tt > 0) {
	    ioctl(tt, TIOCNOTTY, 0);
	    close(tt);
	}
    }
}

/*
 * Function: S_ni_in_list
 *
 * Purpose:
 *   Returns whether the given domain is in the list yet or not,
 *   using the host/tag pair as the key.
 */
static id
S_ni_in_list(id list, id domain)
{
    int i;
    for (i = 0; i < [list count]; i++) {
	id obj = [list objectAt:i];
	
	if (strcmp([obj tag], [domain tag]) == 0
	    && [obj ip].s_addr == [domain ip].s_addr)
	    return (obj);
    }
    return (nil);
}

/*
 * Function: S_ni_domains_init
 *
 * Purpose:
 *   Given the list of domain paths in S_domain_list,
 *   open a connection to it, and store the NIDomain object
 *   in the niSearchDomain list.
 *   The code makes sure it only opens each domain once by
 *   checking for uniqueness of the host/tag combination.
 *   The code also pays attention to the the special path "...",
 *   which means open the hierarchy starting from the local domain
 *   on up.
 */
static boolean_t
S_ni_domains_init()
{
    boolean_t	hierarchy_done = FALSE;
    int 	i;

    if (niSearchDomains != nil) {
	[[niSearchDomains freeObjects] free];
    }
    ni_local = NULL;
    niSearchDomains = [[List alloc] initCount:[S_domain_list count]];
    for (i = 0; i < [S_domain_list count]; i++) {
	NIDomain * domain;
	u_char *   dstr = (u_char *)[S_domain_list objectAt:i];

	if (strcmp(dstr, DOMAIN_HIERARCHY) == 0) {
	    id domain;

	    if (hierarchy_done)
		continue;
	    hierarchy_done = TRUE;
	    if (verbose)
		syslog(LOG_INFO, "opening hierarchy starting at .");
	    domain = [[NIDomain alloc] initWithDomain:NI_DOMAIN_LOCAL];
	    while (TRUE) {
		id obj;

		if (domain == nil)
		    break; /* we're done */
		obj = S_ni_in_list(niSearchDomains, domain);
		if (obj != nil) {
		    if (debug)
			printf("%s/%s already in the list: %s\n",
			       [obj tag], inet_ntoa([obj ip]),
			       [obj domain_name]);
		    [domain free];
		    domain = obj;
		}
		else {
		    if (verbose)
			syslog(LOG_INFO, "opened domain %s/%s", 
			       inet_ntoa([domain ip]),
			       [domain tag]);
		    [niSearchDomains addObject:domain];
		}
		domain = [[NIDomain alloc] initParentDomain:domain];
	    }
	}
	else {
	    if (verbose) {
		syslog(LOG_INFO, "opening domain %s", dstr);
	    }
	    domain = [[NIDomain alloc] initWithDomain:dstr];
	    if (domain != nil) {
		if (S_ni_in_list(niSearchDomains, domain) != nil) {
		    /* already in the list */
		    if (debug)
			printf("%s/%s already in the list\n",
			       [domain tag], inet_ntoa([domain ip]));
		    [domain free];
		    continue;
		}
		[niSearchDomains addObject:domain];
		if (verbose)
		    syslog(LOG_INFO, "opened domain %s/%s", 
			   inet_ntoa([domain ip]),
			   [domain tag]);
	    }
	    else {
		syslog(LOG_INFO, "unable to open domain '%s'", dstr);
	    }
	}
    }
    if ([niSearchDomains count] == 0) {
	[niSearchDomains free];
	niSearchDomains = nil;
	return (FALSE);
    }
    { /* find the "local" netinfo domain */
	id  domain;
	int i;

	for (i = 0; i < [niSearchDomains count]; i++) {
	    domain = [niSearchDomains objectAt:i];
	    if (if_lookupbyip(S_interfaces, [domain ip])
		&& strcmp([domain tag], "local") == 0) {
		ni_local = [domain handle];
	    }
	}
	if (ni_local == NULL && S_do_macNC) {
	    syslog(LOG_INFO, 
		   "macNC operation requires local netinfo domain, adding");
	    domain = [[NIDomain alloc] initWithDomain:NI_DOMAIN_LOCAL];
	    if (domain == nil)
		exit(1);
	    [niSearchDomains insertObject:domain at:0];
	    ni_local = [domain handle];
	}
    }		
    return (TRUE);
}

static void
S_init_dns()
{
    int i;

    res_init(); /* figure out the default dns servers */

    S_dns_servers_count = _res.nscount;
    if (S_dns_servers_count) {
	S_dns_servers = (struct in_addr *)malloc(sizeof(*S_dns_servers) 
						 * S_dns_servers_count);
	if (_res.defdname[0]) {
	    S_domain_name = _res.defdname;
	    if (debug)
		printf("%s\n", S_domain_name);
	}
	for (i = 0; i < S_dns_servers_count; i++) {
	    S_dns_servers[i] = _res.nsaddr_list[i].sin_addr;
	    if (debug)
		printf("%s\n", inet_ntoa(S_dns_servers[i]));
	}
    }
    return;
}

/*
 * Function: S_string_in_list
 *
 * Purpose:
 *   Given a List object, return boolean whether the C string is
 *   in the list.
 */
static boolean_t
S_string_in_list(id list, u_char * str)
{
    int i;
    for (i = 0; i < [list count]; i++) {
	u_char * lstr = (u_char *)[list objectAt:i];
	if (strcmp(str, lstr) == 0)
	    return (TRUE);
    }
    return (FALSE);
}

/*
 * Function: S_log_interfaces
 *
 * Purpose:
 *   Log which interfaces we will respond on.
 */
void
S_log_interfaces() 
{
    int i;
    int count = 0;
    
#ifndef SO_RCVIF
    /* 
     * if we have no way of knowing which interface received a packet
     * on a multi-homed machine, we can't do any allocations
     */
    if (S_interfaces->count > 1) {
	syslog(LOG_INFO, "SO_RCVIF unavailable on multi-homed machine");
	exit(2);
    }
#endif SO_RCVIF
    
    for (i = 0; i < S_interfaces->count; i++) {
	char 		addr[32];
	interface_t * 	if_p = S_interfaces->list + i;
	
	strcpy(addr, inet_ntoa(if_p->addr));
	if ((S_if_list == nil || S_string_in_list(S_if_list, if_p->name))
	    && if_p->inet_valid
	    && !(if_p->flags & IFF_LOOPBACK)) {
	    syslog(LOG_INFO, "interface %s: %s ip address %s mask %s", 
		   if_p->name, if_p->hostname, addr, 
		   inet_ntoa(if_p->mask));
	    count++;
	}
    }
    if (count == 0) {
	syslog(LOG_INFO, "no available interfaces");
	exit(2);
    }
}

/*
 * Function: S_get_interfaces
 * 
 * Purpose:
 *   Get the list of interfaces we will use.
 */
void
S_get_interfaces()
{
    interface_list_t *	new_list;
    
    new_list = if_init();
    if (new_list == NULL) {
	syslog(LOG_INFO, "interface list initialization failed");
	exit(1);
    }
    if_free(&S_interfaces);
    S_interfaces = new_list;
    S_log_interfaces();
    return;
}

/*
 * Function: S_get_network_routes
 *
 * Purpose:
 *   Get the list of network routes.
 */
void
S_get_network_routes()
{
    inetroute_list_t * new_list;
    
    new_list = inetroute_list_init();
    if (new_list == NULL) {
	syslog(LOG_INFO, "can't get inetroutes list");
	exit(1);
    }
    
    inetroute_list_free(&S_inetroutes);
    S_inetroutes = new_list;
    if (debug)
	inetroute_list_print(S_inetroutes);
}


int
useni()
{
	static int useit = -1;
	extern int _lu_running();

	if (useit == -1){
		useit = _lu_running();
	}
	return (useit);
}

int
main(int argc, char * argv[])
{
    char *		cp;

    debug = 0;			/* no debugging ie. go into the background */
    verbose = 0;		/* don't print extra information */

    argc--, argv++;
    while (argc > 0 && *argv[0] == '-') {
	for (cp = &argv[0][1]; *cp; cp++) {
	    switch (*cp) {
	      case 'b':
		S_bootfile_noexist_reply = FALSE; 
		/* reply only if bootfile exists */
		break;
	      case 'c':		/* specify the client ip port */
		if (argc > 1) {
		    S_ipport_client = atoi(argv[1]);
		    argc--; argv++;
		}
		break;
	      case 'D':		/* act as a DHCP server */
		S_do_dhcp = TRUE;
		break;
	      case 'd':		/* stay in the foreground, extra printf's */
		debug++;
		break;
	      case 'e':
		/* don't use en_address to lookup/store ethernet hosts */
		use_en_address = FALSE;
		break;
	      case 'F':
		S_use_file = TRUE;
		break;
	      case 'i':		/* user specified interface(s) to use */
		if (argc > 1 && argv[1][0] != '-') {
		    if (S_if_list == nil)
			S_if_list = [[List alloc] init];
		    if (S_string_in_list(S_if_list, argv[1]) == FALSE) {
			[S_if_list addObject:(id)argv[1]];
		    }
		    else {
			syslog(LOG_INFO, "interface %s already specified",
			       argv[1]);
		    }
		    argc--; argv++;
		}
		break;
	      case 'm':		/* act as an NC Boot Server */
		S_do_macNC = TRUE;
		break;
	      case 'n':		/* specify netinfo domain search hierarchy */
		if (argc > 1 && argv[1][0] != '-') {
		    if (S_domain_list == nil)
			S_domain_list = [[List alloc] init];
		    if (S_string_in_list(S_domain_list, argv[1]) == FALSE)
			[S_domain_list addObject:(id)argv[1]];
		    argc--; argv++;
		}
		break;
	      case 'q':
		quiet = 1;
		break;
	      case 's':		/* specify the server ip port */
		if (argc > 1) {
		    S_ipport_server = atoi(argv[1]);
		    argc--; argv++;
		}
		break;
	      case 'v':		/* extra info to syslog */
		verbose++;
		break;
	      default:
		fprintf(stderr,"bootpd: unknown flag -%c ignored",*cp);
		break;
	    }
	}
	argc--, argv++;
    }
    if (debug)
	quiet = 0;
    else if (quiet)
	verbose = 0;
    if (!issock(0)) { /* started by user */
	struct sockaddr_in Sin = { sizeof(Sin), AF_INET };
	int i;
	
	if (!debug)
	    background();
	
	if ((S_sockfd = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
	    syslog(LOG_INFO, "socket call failed");
	    exit(1);
	}
	Sin.sin_port = htons(S_ipport_server);
	Sin.sin_addr.s_addr = htonl(INADDR_ANY);
	i = 0;
	while (bind(S_sockfd, (struct sockaddr *)&Sin, sizeof(Sin)) < 0) {
	    syslog(LOG_INFO, "bind call failed: %s", strerror(errno));
	    if (errno != EADDRINUSE)
		exit(1);
	    i++;
	    if (i == 10) {
		syslog(LOG_INFO, "exiting");
		exit(1);
	    }
	    sleep(10);
	}
    } 
    else { /* started by inetd */
	S_sockfd = 0;
	signal(SIGALRM, on_alarm);
	gettimeofday(&S_lastmsgtime, 0);
	alarm(15);
    }
    (void) openlog("bootpd", LOG_CONS | LOG_PID, LOG_DAEMON);
    syslog(LOG_DEBUG, "server starting");
    
    { 
	int opt = 1;
	
#ifdef SO_RCVIF
	/* indicate that we want receive interface information as well */
	if (setsockopt(S_sockfd, SOL_SOCKET, SO_RCVIF, (caddr_t)&opt,
		       sizeof(opt)) < 0) {
	    syslog(LOG_INFO, "setsockopt(SO_RCVIF) failed: %s", 
		   strerror(errno));
	    if (S_interfaces->count > 1) {
		syslog(LOG_INFO, 
		       "SO_RCVIF unavailable on multi-homed machine");
		exit(2);
	    }
	}
#endif SO_RCVIF
	
	if (setsockopt(S_sockfd, SOL_SOCKET, SO_BROADCAST, (caddr_t)&opt,
		       sizeof(opt)) < 0) {
	    syslog(LOG_INFO, "setsockopt(SO_BROADCAST) failed");
	    exit(1);
	}
	if (setsockopt(S_sockfd, SOL_SOCKET, SO_REUSEADDR, (caddr_t)&opt,
		       sizeof(opt)) < 0) {
	    syslog(LOG_INFO, "setsockopt(SO_REUSEADDR) failed");
	    exit(1);
	}
#if 0
	if (setsockopt(S_sockfd, IPPROTO_IP, IP_RECVDSTADDR, (caddr_t)&opt,
		       sizeof(opt)) < 0) {
	    syslog(LOG_INFO, "setsockopt(IPPROTO_IP, IP_RECVDSTADDR) failed");
	    exit(1);
	}
#endif 0
    }
    
    S_get_interfaces();
    S_get_network_routes();

    /* install our sighup handler */
    signal(SIGHUP, on_sighup);

    if (useni() == FALSE)
	S_use_file = TRUE;
    if (S_use_file) {
	if (S_do_macNC) {
	    syslog(LOG_INFO, "file-based NC operation not supported");
	    S_do_macNC = FALSE;
	}
	if (S_do_dhcp) {
	    syslog(LOG_INFO, "file-based DHCP operation not supported");
	    S_do_dhcp = FALSE;
	}
    }
    else {
	/* initialize our netinfo search domains */
	if (S_domain_list == nil) {
	    S_domain_list = [[List alloc] init];
	    [S_domain_list addObject:(id)DOMAIN_HIERARCHY];
	}
	if (S_ni_domains_init() == FALSE) {
	    syslog(LOG_INFO, "domain initialization failed");
	    exit (1);
	}
    }

#ifndef SYSTEM_ARP
    S_rtsockfd = arp_get_routing_socket();
    if (S_rtsockfd < 0) {
	syslog(LOG_INFO, "couldn't get routing socket: %s",
	       strerror(errno));
	exit(1);
    }
#endif SYSTEM_ARP

    S_init_dns();

    S_server_loop();
    exit (0);
}

/* 
 * Function: timestamp_syslog
 *
 * Purpose:
 *   Log a timestamped event message to the syslog.
 */
void
timestamp_syslog(char * msg)
{
    static struct timeval	tvp = {0,0};
    struct timeval		tv;

    if (verbose) {
	gettimeofday(&tv, 0);
	if (tvp.tv_sec) {
	    struct timeval result;

	    timeval_subtract(&tv, &tvp, &result);
	    syslog(LOG_INFO, "%d.%06d (%d.%06d): %s", 
		   tv.tv_sec, tv.tv_usec, result.tv_sec, result.tv_usec, msg);
	}
	else 
	    syslog(LOG_INFO, "%d.%06d (%d.%06d): %s", 
		   tv.tv_sec, tv.tv_usec, 0, 0, msg);
	tvp = tv;
    }
}

/*
 * Function: subnetAddressAndMask
 *
 * Purpose:
 *   Given the gateway address field from the request and the 
 *   interface the packet was received on, determine the subnet
 *   address and mask.
 * Note:
 *   This currently does not support "super-netting", in which
 *   more than one proper subnet shares the same physical subnet.
 */
boolean_t
subnetAddressAndMask(struct in_addr giaddr, interface_t * intface,
		     struct in_addr * addr, struct in_addr * mask)
{
    /* gateway specified, find a subnet description on the same subnet */
    if (giaddr.s_addr) {
	id subnet;
	/* find a subnet entry on the same subnet as the gateway */
	if (subnets == nil 
	    || (subnet = [subnets entrySameSubnet:giaddr]) == nil)
	    return (FALSE);
	*addr = giaddr;
	*mask = [subnet mask];
    }
    else {
	*addr = intface->netaddr;
	*mask = intface->mask;
    }
    return (TRUE);
}

/*
 * Function: issock
 *
 * Purpose:
 *   Determine if a descriptor belongs to a socket or not
 */
static int
issock(fd)
     int fd;
{
    struct stat st;
    
    if (fstat(fd, &st) < 0) {
	return (0);
    } 
    /*	
     * SunOS returns S_IFIFO for sockets, while 4.3 returns 0 and
     * does not even have an S_IFIFO mode.  Since there is confusion 
     * about what the mode is, we check for what it is not instead of 
     * what it is.
     */
    switch (st.st_mode & S_IFMT) {
      case S_IFCHR:
      case S_IFREG:
      case S_IFLNK:
      case S_IFDIR:
      case S_IFBLK:
	return (0);
      default:	
	return (1);
    }
}


/*
 * Function: on_sighup
 *
 * Purpose:
 *   If we get a sighup, re-read the subnet descriptions.
 */
static void
on_sighup(int sigraised)
{
    if (sigraised == SIGHUP)
	S_sighup = TRUE;
    return;
}

/*
 * Function: on_alarm
 *
 * Purpose:
 *   If we were started by inetd, we kill ourselves during periods of
 *   inactivity.  If we've been idle for MAXIDLE, exit.
 */
static void
on_alarm(int sigraised)
{
    struct timeval tv;
    
    gettimeofday(&tv, 0);
    
    if ((tv.tv_sec - S_lastmsgtime.tv_sec) >= MAXIDLE)
	exit(0);
    alarm(15);
    return;
}

/*
 * Function: bootp_add_bootfile
 *
 * Purpose:
 *   Verify that the specified bootfile exists, and add it to the given
 *   packet.  Handle <bootfile>.<hostname> to allow a specific host to
 *   get its own version of the bootfile.
 */
boolean_t
bootp_add_bootfile(char * request_file, char * hostname, char * homedir, 
		   char * bootfile, char * default_bootfile, 
		   char * tftp_homedir, char * reply_file)
{
    boolean_t 	dothost = FALSE;	/* file.host was found */
    char 	file[PATH_MAX];
    char 	path[PATH_MAX];
    boolean_t	specific_file = FALSE;

    strcpy(path, homedir);
    strcat(path, "/");
    if (request_file && request_file[0]) {
	/* client did specify file */
	strcpy(file, request_file);
	specific_file = TRUE;
    }
    else if (bootfile && bootfile[0]) {
	if (S_bootfile_noexist_reply == FALSE)
	    specific_file = TRUE;
	strcpy(file, bootfile);
    }
    else
	strcpy(file, default_bootfile);

    if (file[0] == '/')	/* if absolute pathname */
	strcpy(path, file);
    else
	strcat(path, file);

    /* try first to find the file with a ".host" suffix */
    if (hostname) {
	int 	n;

	n = strlen(path);
	strcat(path, ".");
	strcat(path, hostname);
	if (access(path, R_OK) >= 0)
	    dothost = TRUE;
	else
	    path[n] = 0;	/* try it without the suffix */
    }
    
    if (dothost == FALSE) {
	if (access(path, R_OK) < 0) {
	    if (specific_file) { /* wanted specific file */
		syslog(LOG_INFO, 
		       "boot file %s* missing - not replying", path);
		return (FALSE);
	    }
	    if (verbose)
		syslog(LOG_INFO, "boot file %s* missing", path);
	}
    }

    if (tftp_homedir != NULL && tftp_homedir[0] != 0) {
	/* Rebuild the path with tftp_homedir at the front */
	strcpy(path, tftp_homedir);
	if (tftp_homedir[strlen(tftp_homedir) - 1] != '/') {
	    strcat(path, "/");
	}
	if (file[0] == '/') /* might not work in secure case */
	    strcpy(path, file);
	else
	    strcat(path, file);
	if (dothost) {
	    strcat(path, ".");
	    strcat(path, hostname);
	}
    }
    if (verbose)
	syslog(LOG_INFO,"replyfile %s", path);
    strcpy(reply_file, path);
    return (TRUE);
}

/*
 * Function: lookup_host_by_ip
 *
 * Purpose:
 *   Search netinfo for an entry that contains the given ip address.
 *   Retrieve the hostname, and bootfile if the corresponding
 *   argument pointer is not NULL.
 */
boolean_t
lookup_host_by_ip(struct in_addr ip, u_char * * name, u_char * * bootfile,
		  ni_proplist * pl_p)
{
    char 	ipstr[32];
    ni_id	dir;
    id		domain;
    ni_proplist	pl;

    NI_INIT(&pl);
    strcpy(ipstr, inet_ntoa(ip));
    domain = [NIHosts lookupKey:NIPROP_IP_ADDRESS Value:ipstr
	      DomainList:niSearchDomains
	      PropList:pl_p Dir:&dir];
    if (domain == nil)
	return (FALSE);
    
    /* retrieve the host name */
    if (name) {
	ni_name str;
	
	*name = NULL;
	str = ni_valforprop(pl_p, NIPROP_NAME);
	if (str)
	    *name = ni_name_dup(str);
    }
    
    /* retrieve the bootfile */
    if (bootfile) {
	ni_name str;
	
	*bootfile = NULL;
	str = ni_valforprop(pl_p, NIPROP_BOOTFILE);
	if (str)
	    *bootfile = ni_name_dup(str);
    }
    
    return (TRUE);
}

/*
 * Function: ip_address_reachable
 *
 * Purpose:
 *   Determine whether the given ip address is directly reachable from
 *   the given interface and/or gateway.
 *
 *   Directly reachable means without using a router ie. share the same wire.
 */
boolean_t
ip_address_reachable(struct in_addr ip, struct in_addr giaddr, 
		     interface_t * intface)
{
    int i;

    if (giaddr.s_addr) { /* gateway'd */
	/* find a subnet entry on the same subnet as the gateway */
	if (subnets == nil 
	    || [subnets ip:ip SameSupernet:giaddr])
	    return (FALSE);
	return (TRUE);
    }

    for (i = 0; i < S_inetroutes->count; i++) {
	inetroute_t * inr_p = S_inetroutes->list + i;

	if (inr_p->gateway.link.sdl_family == AF_LINK
	    && (if_lookupbylinkindex(S_interfaces, 
				     inr_p->gateway.link.sdl_index) 
		== intface)) {
	    /* reachable? */
	    if (in_subnet(inr_p->dest, inr_p->mask, ip))
		return (TRUE);
	}
    }
    return (FALSE);
}

/*
 * Function: prop_index_subnet
 *
 * Purpose:
 *   Given a property name and value, find the property value index 
 *   that has an IP_ADDRESS value reachable through the given
 *   interface or gateway.
 * Returns:
 *   -1 if not found, index if found.
 * Note:
 *   If a host entry has multiple hardware and ip addresses, the
 *   namelists for certain properties are treated as parallel arrays.
 *   This is to allow a host to have a single hardware address
 *   bound to more than one ip address, and to have multiple hardware
 *   addresses bound to multiple ip addresses.
 *   eg.
 *
 *   1. identifier = { "1/0:1:2:3:4:5", "1/0:1:2:3:4:5" };
 *      ip_address = { "17.202.40.191", "17.201.16.20" };
 *      - host has single interface, that will have ip address 17.202.40.191
 *        on subnet 17.202.40.0 and ip address 17.201.16 on subnet 17.202.16.0.
 *
 *   2. identifier = { "1/0:1:2:3:4:5", "1/0:5:5:5:5:5" };
 *      ip_address = { "17.202.40.191", "17.201.16.40" };
 *      - host has multiple interfaces:
 *        interface 0:1:2:3:4:5 has ip 17.202.40.191
 *        interface 0:5:5:5:5:5 has ip 17.201.16.40
 */

int
prop_index_subnet(ni_name prop, ni_name value, struct in_addr giaddr,
		  interface_t * intface, ni_proplist * proplist, 
		  boolean_t * error)
{
    ni_namelist * 	ip_nl_p;
    int			p;
    ni_namelist *	prop_nl_p;

    prop_nl_p = ni_nlforprop(proplist, prop);
    if (prop_nl_p == NULL) {
	*error = TRUE;
	if (verbose)
	    syslog(LOG_INFO, "bad host entry, missing %s = %s",
		   prop, value);
	return (-1);
    }
    ip_nl_p = ni_nlforprop(proplist, NIPROP_IP_ADDRESS);
    if (ip_nl_p == NULL) {
	*error = TRUE;
	if (verbose)
	    syslog(LOG_INFO, "bad host entry (%s=%s), missing %s",
		   prop, value, NIPROP_IP_ADDRESS);
	return -1;
    }
    for (p = 0; p < prop_nl_p->ninl_len; p++) {
	if (p >= ip_nl_p->ninl_len) { /* parallel array */
	    *error = TRUE;
	    if (verbose)
		syslog(LOG_INFO, "bad host entry (%s=%s): too few %s values",
		       prop, value, NIPROP_IP_ADDRESS);
	    return -1;
	}
	if (strcmp(prop_nl_p->ninl_val[p], value) == 0) {
	    struct in_addr ip;
	    ip.s_addr = inet_addr(ip_nl_p->ninl_val[p]);
	    if (ip.s_addr != -1) {
		if (ip_address_reachable(ip, giaddr, intface))
		    return (p);
	    }
	    else if (verbose)
		syslog(LOG_INFO, "bad host entry (%s=%s): %s=%s",
		       prop, value, NIPROP_IP_ADDRESS, ip_nl_p->ninl_val[p]);
	}
    }
    return (-1);
}

typedef struct subnetMatchArgs {
    ni_name		key;
    ni_name		value;
    struct in_addr	giaddr;
    interface_t *	intface;
    int			index;
} subnetMatchArgs_t;

static boolean_t 
S_subnet_match(void * arg, ni_proplist * pl_p)
{
    boolean_t			error = FALSE;
    subnetMatchArgs_t * 	s = (subnetMatchArgs_t *)arg;

    s->index = prop_index_subnet(s->key, s->value, s->giaddr,
				 s->intface, pl_p, &error);
    if (s->index == -1)
	return (FALSE);
    return (TRUE);
}

/*
 * Function: lookup_host_by_identifier
 *
 * Purpose:
 *   Retrieve the hardware address -> ip address binding by looking 
 *   up the given host's hardware address.
 */
boolean_t
lookup_host_by_identifier(u_char hwtype, void * hwaddr, int hwlen, 
			  struct in_addr giaddr, interface_t * intface,
			  struct in_addr * ip, u_char * * name,
			  u_char * * bootfile, id * domain_p, ni_id * dir_p,
			  ni_proplist * pl_p,
			  boolean_t * error)
{
    ni_id		dir;
    id			domain;
    u_char		enstr[32];
    ni_name 		ipstr;
    u_char *		idstr = NULL;
    int			key_matches = 0;
    int			matches = 0;
    subnetMatchArgs_t	s;

    NI_INIT(pl_p);

    *error = FALSE;
    s.giaddr = giaddr;
    s.intface = intface;
    s.index = -1;

    if (use_en_address  /* lookup using en_address property */
	&& hwtype == ARPHRD_ETHER) {
	strcpy(enstr, ether_ntoa((struct ether_addr *)hwaddr));
	s.key = NIPROP_EN_ADDRESS;
	s.value = enstr;
    }
    else { /* lookup using identifier property */
	idstr = identifierToString(hwtype, hwaddr, hwlen); /* malloc'd */
	if (idstr == NULL) {
	    *error = TRUE;
	    return (FALSE);
	}
	s.key = NIPROP_IDENTIFIER;
	s.value = idstr;
    }
    domain = [NIHosts lookupKey:s.key Value:s.value
	      Func:S_subnet_match Arg:(void *)&s
	      DomainList:niSearchDomains
	      KeyMatches:&key_matches
	      Matches:&matches
	      PropList:pl_p Dir:&dir];

    if (domain != nil && verbose)
	syslog(LOG_INFO, "%s = %s: matches %d, exact matches %d\n",
	       s.key, s.value, key_matches, matches);

    if (idstr) {
	free(idstr);
	idstr = NULL;
    }

    if (domain == nil) /* binding does not exist */
	return (FALSE);

    if (matches == 0 || s.index == -1) { /* binding on other subnet */
	ni_proplist_free(pl_p);
	return (FALSE);
    }

    /* retrieve the ip address */
    ipstr = (ni_nlforprop(pl_p, NIPROP_IP_ADDRESS))->ninl_val[s.index];
    if (ip) /* return the ip address */
	ip->s_addr = inet_addr(ipstr);

    /* retrieve the host name */
    if (name) {
	ni_name 	str;
	
	*name = NULL;
	str = ni_valforprop(pl_p, NIPROP_NAME);
	if (str)
	    *name = ni_name_dup(str);
    }
    
    /* retrieve the bootfile */
    if (bootfile) {
	ni_name str;
	
	*bootfile = NULL;
	str = ni_valforprop(pl_p, NIPROP_BOOTFILE);
	if (str)
	    *bootfile = ni_name_dup(str);
    }
    if (dir_p)
	*dir_p = dir;
    if (domain_p)
	*domain_p = domain;

    return (TRUE);
}

void
print_packet(struct bootp *bp, int bp_len)
{
	int i, j, len;

	printf("bp_op = ");
	if (bp->bp_op == BOOTREQUEST) printf("BOOTREQUEST\n");
	else if (bp->bp_op == BOOTREPLY) printf("BOOTREPLY\n");
	else
	{
		i = bp->bp_op;
		printf("%d\n", i);
	}

	i = bp->bp_htype;
	printf("bp_htype = %d\n", i);

	len = bp->bp_hlen;
	printf("bp_hlen = %d\n", len);

	i = bp->bp_hops;
	printf("bp_hops = %d\n", i);

	printf("bp_xid = %lu\n", bp->bp_xid);

	printf("bp_secs = %hu\n", bp->bp_secs);

	printf("bp_ciaddr = %s\n", inet_ntoa(bp->bp_ciaddr));
	printf("bp_yiaddr = %s\n", inet_ntoa(bp->bp_yiaddr));
	printf("bp_siaddr = %s\n", inet_ntoa(bp->bp_siaddr));
	printf("bp_giaddr = %s\n", inet_ntoa(bp->bp_giaddr));

	printf("bp_chaddr = ");
	for (j = 0; j < len; j++)
	{
		i = bp->bp_chaddr[j];
		printf("%0x", i);
		if (j < (len - 1)) printf(":");
	}
	printf("\n");

	printf("bp_sname = %s\n", bp->bp_sname);
	printf("bp_file = %s\n", bp->bp_file);

	if (bcmp(bp->bp_vend, rfc_magic, sizeof(rfc_magic)) == 0) {
	    id			options;

	    options = [[dhcpOptions alloc] 
		        initWithBuffer:bp->bp_vend + sizeof(rfc_magic) 
		        Size:bp_len - sizeof(struct dhcp) - sizeof(rfc_magic)];
	    if ([options parse] == TRUE) {
		printf("options: packet size %d\n", bp_len);
		[options print];
	    }
	    else if (bcmp(bp->bp_vend, VM_NEXT, 4) == 0) {
		struct nextvend *nv;
		
		printf("nv_opcode = ");
		nv = (struct nextvend *)&bp->bp_vend;
		switch (nv->nv_opcode) {
		  case BPOP_OK: printf("BPOP_OK\n"); break;
		  case BPOP_QUERY: printf("BPOP_QUERY\n"); break;
		  case BPOP_QUERY_NE: printf("BPOP_QUERY_NE\n"); break;
		  case BPOP_ERROR: printf("BPOP_ERROR\n"); break;
		  default:
		    i = nv->nv_opcode;
		    printf("%d\n", i);
		    break;
		}
		i = nv->nv_xid;
		printf("nv_xid = %d\n", i);
		printf("nv_text = \"%s\"\n", nv->nv_text);
		
	    }
	    [options free];
	}
}

/*
 * Function: bootp_request
 *
 * Purpose:
 *   Process BOOTREQUEST packet.
 *
 * Note:
 *   This version of the bootp.c server never forwards 
 *   the request to another server.  In our environment the 
 *   stand-alone gateways perform that function.
 *
 *   Also this version does not interpret the hostname field of
 *   the request packet;  it COULD do a name->address lookup and
 *   forward the request there.
 */
static void
bootp_request(interface_t * intface, void * rxpkt, int rxpkt_len,
	      struct timeval * time_in_p)
{
    u_char *		bootfile = NULL;
    boolean_t		error;
    u_char *		hostname = NULL;
    struct in_addr	iaddr;
    struct bootp 	rp;
    struct bootp *	rq = (struct bootp *)rxpkt;

    rp = *rq;	/* copy request into reply */
    rp.bp_op = BOOTREPLY;

    if (rq->bp_ciaddr.s_addr == 0) { /* client doesn't specify ip */
	if (S_use_file) {
	    if (bootp_getbyhw_file(rq->bp_htype, rq->bp_chaddr, rq->bp_hlen,
				   &iaddr, &hostname, &bootfile) == FALSE)
		return;
	}
	else {
	    struct hosts * 	hp;
	    ni_proplist 	pl;
    
	    /* check for host entry in the ignore queue */
	    hp = hostbyaddr(S_ignore_hosts, rq->bp_htype, rq->bp_chaddr,
			    rq->bp_hlen);
	    if (hp) {
		if ((time_in_p->tv_sec - hp->tv.tv_sec) <= IGNORETIME)
		    return;
		hostfree(&S_ignore_hosts, hp);
		hp = NULL;
	    }
	    if (lookup_host_by_identifier(rq->bp_htype, rq->bp_chaddr, 
					  rq->bp_hlen, rq->bp_giaddr,
					  intface, &iaddr,
					  &hostname, &bootfile, NULL, NULL, 
					  &pl, &error) == FALSE) {
		/* remember that we didn't reply before */
		struct hosts * hp;
		hp = hostadd(&S_ignore_hosts, time_in_p, rq->bp_htype, 
			     rq->bp_chaddr, rq->bp_hlen, NULL, NULL, NULL);
		if (verbose && hp) {
		    syslog(LOG_INFO, 
			   "ignoring the following host for %d seconds",
			   IGNORETIME);
		    hostprint(hp);
		}
		return;
	    }
	    ni_proplist_free(&pl);
	}
	rp.bp_yiaddr = iaddr;
    }
    else { /* client specified ip address */
	if (S_use_file) {
	    if (bootp_getbyip_file(rq->bp_ciaddr, &hostname, &bootfile) 
		== FALSE)
		return;
	}
	else {
	    ni_proplist pl;
	    
	    if (lookup_host_by_ip(iaddr, &hostname, &bootfile, &pl) == FALSE)
		return; /* unknown ip address */
	    ni_proplist_free(&pl);
	}
    }
    if (!quiet)
	syslog(LOG_INFO,"BOOTP request [%s]: %s requested file '%s'",
	       intface->name, hostname ? hostname : (u_char *)inet_ntoa(iaddr),
	       rq->bp_file);
    if (bootp_add_bootfile(rq->bp_file, hostname, boot_home_dir,
			   bootfile, boot_default_file, boot_tftp_dir,
			   rp.bp_file) == FALSE)
	/* client specified a bootfile but it did not exist */
	goto no_reply;
    
    if (bcmp(rq->bp_vend, rfc_magic, sizeof(rfc_magic)) == 0) {
	/* insert the usual set of options/extensions if possible */
	id options;
		
	options = [[dhcpOptions alloc] 
		   initWithBuffer:rp.bp_vend + sizeof(rfc_magic)
		   Size:sizeof(rp.bp_vend) - sizeof(rfc_magic)];
	if (options == nil)
	    syslog(LOG_INFO, "init options failed");
	else {
	    if ([options addOption:dhcptag_host_name_e 
	         FromString:hostname] == FALSE) {
		syslog(LOG_INFO, "couldn't add hostname: %s",
		       [options errString]);
	    }
	    /* figure out which subnet to use */
	    add_subnet_options(iaddr, intface, options, NULL, 0);
	    if (verbose) 
		syslog(LOG_INFO, "added rfc options");
	    if ([options addOption:dhcptag_end_e Length:0 
	         Data:NULL] == FALSE) {
		syslog(LOG_INFO, "couldn't add end tag: %s",
		       [options errString]);
	    }
	    else
		bcopy(rfc_magic, rp.bp_vend, sizeof(rfc_magic));
	    if (options != nil)
		[options free];
	}
    } /* if RFC magic number */
    else if (bcmp(rq->bp_vend, VM_NEXT, sizeof(VM_NEXT)) == 0) {
	struct nextvend *nv_rq = (struct nextvend *)&rq->bp_vend;
	struct nextvend *nv_rp = (struct nextvend *)&rp.bp_vend;
	if (nv_rq->nv_version == 1) {
	    nv_rp->nv_opcode = BPOP_OK;
	    nv_rp->nv_xid = 0;
	}
    }
    if (sendreply(intface, &rp, sizeof(rp), 0))
	if (!quiet)
	    syslog(LOG_INFO, "reply sent %s %s pktsize %d",
		   hostname, inet_ntoa(iaddr), sizeof(rp));

  no_reply:
    if (hostname)
	free(hostname);
    if (bootfile)
	free(bootfile);
    return;
}


/*
 * Process BOOTREPLY packet (something is using us as a gateway).
 */
void
reply(interface_t * intface)
{
	struct bootp *bp = (struct bootp *)S_rxpkt;

	sendreply(intface, bp, sizeof(struct bootp), 1);
}

/*
 * Send a reply packet to the client.  'forward' flag is set if we are
 * not the originator of this reply packet.
 */
boolean_t
sendreply(interface_t * intface, struct bootp * bp, int n, int forward)
{
    struct in_addr 		dst;
    struct sockaddr_in 		to = { sizeof(to), AF_INET };

    to.sin_port = htons(S_ipport_client);
    /*
     * If the client IP address is specified, use that
     * else if gateway IP address is specified, use that
     * else make a temporary arp cache entry for the client's NEW 
     * IP/hardware address and use that.
     */
    if (bp->bp_ciaddr.s_addr) {
	dst = bp->bp_ciaddr;
	if (verbose) 
	    syslog(LOG_DEBUG, "reply ciaddr %s", inet_ntoa(dst));
    }
    else if (bp->bp_giaddr.s_addr && forward == 0) {
	dst = bp->bp_giaddr;
	to.sin_port = htons(S_ipport_server);
	if (verbose) 
	    syslog(LOG_INFO, "reply giaddr %s", inet_ntoa(dst));
    } 
    else { /* local net request */
	dst = bp->bp_yiaddr;

	/* 
	 * This code is not correct: we should be using 255.255.255.255,
	 * not the subnet-specific broadcast.  However, to get an all ff's
	 * broadcast sent out a specific interface (rather than the one
	 * corresponding to the default) would require additional kernel 
	 * support (similar to SO_RCVIF).
	 */
	if (ntohs(bp->bp_unused) & DHCP_FLAGS_BROADCAST) {
	    if (verbose)
		syslog(LOG_INFO, "client requested broadcast");
	    dst = intface->broadcast;
	}
	if (verbose) 
	    syslog(LOG_INFO, "reply yiaddr %s", inet_ntoa(dst));
	
	if (dst.s_addr == 0) {
	    if (!quiet)
		syslog(LOG_INFO, "ignoring %s", inet_ntoa(dst));
	    return (FALSE);
	}
	setarp(&dst, bp->bp_chaddr, bp->bp_hlen);
    }
    to.sin_addr = dst;
    if (forward == 0) {
	if (bp->bp_giaddr.s_addr == 0)
	    bp->bp_giaddr = intface->addr;

	bp->bp_siaddr = intface->addr;
	strcpy(bp->bp_sname, intface->hostname);
	if (sendto(S_sockfd, (caddr_t)bp, n, 0, (struct sockaddr *)&to, 
		   sizeof to) < 0) {
	    syslog(LOG_INFO, "send failed");
	    return (FALSE);
	}
    }
    else if (sendto(S_sockfd, (caddr_t)bp, n, 0, 
		    (struct sockaddr *)&to, sizeof to) < 0) {
	syslog(LOG_INFO, "send failed");
	return (FALSE);
    }
    return (TRUE);
}

/*
 * Function: get_dhcp_option
 *
 * Purpose:
 *   Get a dhcp option from subnet description.
 */
boolean_t
get_dhcp_option(id subnet, int tag, void * buf, int * len_p)
{
    unsigned char	err[256];
    unsigned char	propname[128];
    ni_namelist	*	nl_p;
    tag_info_t * 	tag_info = [dhcpOptions tagInfo:tag];

    if (dhcptag_subnet_mask_e == tag)
	strcpy(propname, NIPROP_NET_MASK);
    else
	sprintf(propname, "%s%s", DHCP_OPTION_PREFIX, tag_info->name);
    nl_p = [subnet lookup:propname];
    if (nl_p == NULL) {
	if (verbose)
	    syslog(LOG_INFO, "subnet entry %s is missing option %s",
		   [subnet name:err], propname);
	return (FALSE);
    }
    
    if ([dhcpOptions strList:(unsigned char * *)nl_p->ninl_val 
         Number:nl_p->ninl_len Tag:tag Buffer:buf Length:len_p
         ErrorString:err] == FALSE) {
	if (verbose)
	    syslog(LOG_INFO, "couldn't add option '%s': %s",
		   propname, err);
	return (FALSE);
    }
    return (TRUE);
}
/*
 * Function: add_subnet_options
 *
 * Purpose:
 *   Given a list of tags, retrieve them from the subnet entry and
 *   insert them into the message options.
 */
void
add_subnet_options(struct in_addr iaddr, interface_t * intface,
		   id options, u_char * tags, int n)
{
    char		buf[DHCP_OPTION_MAX];
    int			len;
    static u_char 	default_tags[] = { 
	dhcptag_subnet_mask_e, 
	dhcptag_router_e, 
	dhcptag_domain_name_server_e,
	dhcptag_domain_name_e,
#if 0
	dhcptag_netinfo_server_address_e,
	dhcptag_netinfo_server_tag_e,
#endif
    };
    int			i;
    id			subnet = [subnets entry:iaddr];

    if (tags == NULL) {
	tags = default_tags;
	n = sizeof(default_tags) / sizeof(default_tags[0]);
    }
			
    for (i = 0; i < n; i++ ) {
	len = [options freeSpace];
	if (len > sizeof(buf))
	    len = sizeof(buf);
	if (subnet != nil 
	    && get_dhcp_option(subnet, tags[i], buf, &len)) {
	    if ([options addOption:tags[i] Length:len Data:buf] == FALSE) {
		if (!quiet)
		    syslog(LOG_INFO, "couldn't add option %d: %s",
			   tags[i], [options errString]);
	    }
	}
	else { /* try to use defaults if no explicit configuration */
	    struct in_addr * def_route;

	    switch (tags[i]) {
	      case dhcptag_subnet_mask_e:
		if (if_lookupbysubnet(S_interfaces, iaddr) != intface)
		    continue;
		if ([options addOption:dhcptag_subnet_mask_e 
		     Length:sizeof(intface->mask) 
		     Data:&intface->mask] == FALSE) {
		    if (!quiet)
			syslog(LOG_INFO, "couldn't add subnet_mask: %s",
			       [options errString]);
		    continue;
		}
		if (verbose)
		    syslog(LOG_INFO, 
			   "subnet mask %s derived from %s",
			   inet_ntoa(intface->mask), intface->name);
		break;
	      case dhcptag_router_e:
		def_route = inetroute_default(S_inetroutes);
		if (def_route == NULL
		    || in_subnet(intface->netaddr, intface->mask,
				   *def_route) == FALSE)
		    continue;
		if ([options addOption:dhcptag_router_e
		     Length:sizeof(*def_route) Data:def_route] == FALSE) {
		    if (!quiet)
			syslog(LOG_INFO, "couldn't add router: %s",
			       [options errString]);
		    continue;
		}
		if (verbose)
		    syslog(LOG_INFO, "default route added as router");
		break;
	      case dhcptag_domain_name_server_e:
		if (S_dns_servers_count == 0)
		    continue;
		if ([options addOption:dhcptag_domain_name_server_e
		     Length:S_dns_servers_count * sizeof(*S_dns_servers)
		     Data:S_dns_servers] == FALSE) {
		    if (!quiet)
			syslog(LOG_INFO, "couldn't add dns servers: %s",
			       [options errString]);
		    continue;
		}
		if (verbose)
		    syslog(LOG_INFO, "default dns servers added");
		break;
	      case dhcptag_domain_name_e:
		if (S_domain_name) {
		    if ([options addOption:dhcptag_domain_name_e 
		         FromString:S_domain_name] == FALSE) {
			if (!quiet)
			    syslog(LOG_INFO, "couldn't add domain name: %s",
				   [options errString]);
			continue;
		    }
		    if (verbose)
			syslog(LOG_INFO, "default domain name added");
		}
		break;
	      default:
		break;
	    }
	}
    }
    return;
}


#ifndef SYSTEM_ARP
/*
 * Function: setarp
 *
 * Purpose:
 *   Temporarily bind IP address 'ia'  to hardware address 'ha' of 
 *   length 'len'.  Uses the arp_set/arp_delete routines.
 */
void
setarp(struct in_addr * ia, u_char * ha, int len)
{
    int arp_ret;

    arp_ret = arp_delete(S_rtsockfd, ia, FALSE);
    if (arp_ret != 0 && verbose)
	syslog(LOG_INFO, "arp_delete(%s) failed, %d", inet_ntoa(*ia), arp_ret);
    arp_ret = arp_set(S_rtsockfd, ia, (void *)ha, len, TRUE, FALSE);
    if (verbose) {
	if (arp_ret == 0)
	    syslog(LOG_INFO, "arp_set(%s, %s) succeeded", inet_ntoa(*ia), 
		   ether_ntoa((struct ether_addr *)ha));
	else
	    syslog(LOG_INFO, "arp_set(%s, %s) failed: %s", inet_ntoa(*ia), 
		   ether_ntoa((struct ether_addr *)ha),
		   arp_strerror(arp_ret));
    }
    return;
}
#else SYSTEM_ARP
/* 
 * SYSTEM_ARP: use system("arp") to set the arp entry
 */
/*
 * Setup the arp cache so that IP address 'ia' will be temporarily
 * bound to hardware address 'ha' of length 'len'.
 */
static void
setarp(struct in_addr * ia, u_char * ha, int len)
{
    char buf[256];
    int status;
    
    sprintf(buf, "/usr/sbin/arp -d %s", inet_ntoa(*ia));
    if (verbose) 
	syslog(LOG_INFO, buf);
    status = system(buf);
    if (status && verbose)
	syslog(LOG_INFO, "arp -d failed, exit code=0x%x", status);
    sprintf(buf, "/usr/sbin/arp -s %s %s temp",
	    inet_ntoa(*ia), ether_ntoa((struct ether_addr *)ha));;
    if (verbose) syslog(LOG_INFO, buf);
    status = system(buf);
    if (status && verbose)
	syslog(LOG_INFO, "arp failed, exit code=0x%x", status);
    return;
}
#endif SYSTEM_ARP

/**
 ** Server Main Loop
 **/
static char 		control[1024];
static struct iovec  	iov;
static struct msghdr 	msg;

static void
S_init_msg()
{
    msg.msg_name = 0;
    msg.msg_namelen = 0;
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = control;
    msg.msg_controllen = sizeof(control);
    msg.msg_flags = 0;
    iov.iov_base = (caddr_t)S_rxpkt;
    iov.iov_len = sizeof(S_rxpkt);
    return;
}

static void
S_dispatch_packet(struct bootp * bp, int n, interface_t * ifa)
{
    id 			options = nil;
    boolean_t		dhcp_pkt = FALSE;
    dhcp_msgtype_t	dhcp_msgtype = 0;
    
    /* get the packet options, check for dhcp */
    if (bcmp(bp->bp_vend, rfc_magic, sizeof(rfc_magic)) == 0) {
	options = [[dhcpOptions alloc] 
		   initWithBuffer:bp->bp_vend + sizeof(rfc_magic)
		   Size:n - sizeof(struct dhcp) - sizeof(rfc_magic)];
	if ([options parse]) {
	    dhcp_pkt = is_dhcp_packet(options, &dhcp_msgtype);
	}
	else {
	    [options free];
	    options = nil;
	}
	    
    }
    switch (bp->bp_op) {
      case BOOTREQUEST:
	if (bp->bp_sname[0] != '\0' 
	    && strcmp(bp->bp_sname, ifa->hostname) != 0)
	    break;
	if (bp->bp_siaddr.s_addr != 0
	    && ntohl(bp->bp_siaddr.s_addr) != ntohl(ifa->addr.s_addr))
	    break;
	if (dhcp_pkt) { /* this is a DHCP packet */
	    if (S_do_dhcp)
		dhcp_request(dhcp_msgtype, ifa, S_rxpkt, n, options, 
			     &S_lastmsgtime);
	}
	else if (S_do_macNC && options != nil
		 && NC_request(ifa, S_rxpkt, n, options, &S_lastmsgtime))
	    break;
	else
	    bootp_request(ifa, S_rxpkt, n, &S_lastmsgtime);
	break;
      case BOOTREPLY:
	reply(ifa);
	break;
      default:
	break;
    }
    if (options != nil)
	[options free];
    if (verbose) {
	struct timeval now;
	struct timeval result;

	gettimeofday(&now, 0);
	timeval_subtract(&now, &S_lastmsgtime, &result);
	if (!quiet)
	    syslog(LOG_INFO, "service time %d.%06d seconds",
		   result.tv_sec, result.tv_usec);
    }
    return;
}

static __inline__ void *
S_parse_control(int level, int type, int * len)
{
    struct cmsghdr *	cmsg;

    *len = 0;
    for (cmsg = CMSG_FIRSTHDR(&msg); cmsg; cmsg = CMSG_NXTHDR(&msg, cmsg)) {
	if (cmsg->cmsg_level == level 
	    && cmsg->cmsg_type == type) {
	    if (cmsg->cmsg_len < sizeof(*cmsg))
		return (NULL);
	    *len = cmsg->cmsg_len - sizeof(*cmsg);
	    return (CMSG_DATA(cmsg));
	}
    }
    return (NULL);
}

#ifdef SO_RCVIF
static __inline__ interface_t *
S_which_interface()
{
    void *		data;
    interface_t *	if_p = NULL;
    char 		ifname[32]; 
    int 		len = 0;

    data = S_parse_control(SOL_SOCKET, SO_RCVIF, &len);
    if (data == NULL || len == 0 || len >= sizeof(ifname))
	return (NULL);
    bcopy(data, ifname, len);
    ifname[len] = '\0';
    if_p = if_lookupbyname(S_interfaces, ifname);
    if (if_p == NULL) {
	if (verbose)
	    syslog(LOG_INFO, "unknown interface %s\n", ifname);
	return (NULL);
    }
    if (if_p->inet_valid == FALSE)
	return (NULL);
    if (if_p->hostname[0] == '\0') {
	if (verbose)
	    syslog(LOG_INFO, 
		   "ignoring request on %s - hostname not defined", 
		   ifname);
	return (NULL);
    }
    if (S_if_list != nil 
	&& S_string_in_list(S_if_list, ifname) == FALSE) {
	if (verbose)
	    syslog(LOG_INFO, "ignoring request on %s", ifname);
	return (NULL);
    }
    return (if_p);
}
#endif SO_RCVIF

#if 0
static __inline__ struct in_addr *
S_which_dstaddr()
{
    void *	data;
    int		len = 0;
    
    data = S_parse_control(IPPROTO_IP, IP_RECVDSTADDR, &len);
    if (data && len == sizeof(struct in_addr))
	return ((struct in_addr *)data);
    return (NULL);
}
#endif

/*
 * Function: S_server_loop
 *
 * Purpose:
 *   This is the main "wait for packets and reply" loop.
 */
static void
S_server_loop()
{
#if 0
    struct in_addr * 	dstaddr_p = NULL;
#endif
    struct sockaddr_in 	from = { sizeof(from), AF_INET };
    interface_t *	ifa;
    int 		mask;
    int			n;

    for (;;) {
	S_init_msg();
	msg.msg_name = (caddr_t)&from;
	msg.msg_namelen = sizeof(from);
	n = recvmsg(S_sockfd, &msg, 0);
	if (n < 0) {
	    if (errno != EINTR)
		sleep(1);
	    if (verbose)
		syslog(LOG_DEBUG, "recvmsg failed %d (%d)", n, errno);
	    errno = 0;
	    continue;
	}
	if (n < sizeof(struct bootp))
	    continue;

	bootp_readtab();	/* (re)read the bootptab */

	if (S_sighup) {
	    static boolean_t first = TRUE;

	    hostlistfree(&S_ignore_hosts); /* clean-up ignore queue */
	    if (first == FALSE) {
		S_get_interfaces();
		S_get_network_routes();
	    }
	    first = FALSE;
	    { /* get the new subnet descriptions */
		u_char		err[256];
		subnetListNI *	new_subnets;

		err[0] = '\0';
		new_subnets = [[subnetListNI alloc] init:err];
		if (new_subnets != nil) {
		    [subnets free];
		    subnets = new_subnets;
		}
		else {
		    if (verbose)
			syslog(LOG_INFO, "subnets init failed: %s", err);
		}
	    }
	    /* re-read the NC configuration */
	    if (S_do_macNC) {
		if (NC_cfg_init() == FALSE)
		    S_do_macNC = FALSE; /* shut off NC operation */
	    }
	    S_sighup = FALSE;
	}

#ifdef SO_RCVIF
	ifa = S_which_interface();
	if (ifa == NULL)
	    continue;
#else SO_RCVIF
	ifa = if_first_broadcast_inet(S_interfaces);
#endif SO_RCVIF

#if 0
	dstaddr_p = S_which_dstaddr();
	if (dstaddr_p == NULL)
	    continue;
#endif

	gettimeofday(&S_lastmsgtime, 0);

        mask = sigblock(sigmask(SIGALRM));
	S_dispatch_packet((struct bootp *)S_rxpkt, n, ifa);
	sigsetmask(mask);
    }
    exit (0); /* not reached */
}
