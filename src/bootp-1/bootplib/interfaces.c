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
 * interfaces.c
 * - get the list of interfaces in the system
 */

/*
 * Modification History
 * 02/23/98	Dieter Siegmund (dieter@apple.com)
 * - initial version
 */

#import <unistd.h>
#import <stdlib.h>
#import <stdio.h>
#import <sys/ioctl.h>
#import <strings.h>
#import <syslog.h>
#import <netdb.h>
#import "interfaces.h"
#import <arpa/inet.h>
#import <syslog.h>
#import <net/if_types.h>
#import "util.h"

extern char *  			ether_ntoa(struct ether_addr *e);
extern struct ether_addr *	ether_aton(char *);

static struct sockaddr_in init_sin = {sizeof(init_sin), AF_INET};

#define MAX_IF		16

boolean_t
S_get_ifreq_buf(int * sock_p, struct ifconf * ifconf_p)
{
    struct ifreq * 	ifreq = NULL;
    int			size = sizeof(struct ifreq) * MAX_IF;
    int			sockfd;

    size = sizeof(struct ifreq) * MAX_IF;
    if ((sockfd = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
	syslog(LOG_INFO, "socket call failed");
	return (FALSE);
    }

    while (1) {
	if (ifreq != NULL)
	    ifreq = (struct ifreq *)realloc(ifreq, size);
	else
	    ifreq = (struct ifreq *)malloc(size);
	ifconf_p->ifc_len = size;
	ifconf_p->ifc_req = ifreq;
	if (ioctl(sockfd, SIOCGIFCONF, (caddr_t)ifconf_p) < 0
	    || ifconf_p->ifc_len <= 0) {
	    syslog(LOG_INFO, "ioctl SIOCGIFCONF failed");
	    goto err;
	}
	if ((ifconf_p->ifc_len + sizeof(struct ifreq)) < size)
	    break;
	size *= 2;
    }
    *sock_p = sockfd;
    return (TRUE);
  err:
    close(sockfd);
    if (ifreq)
	free(ifreq);
    return (FALSE);
}

static boolean_t
S_build_interface_list(interface_list_t * interfaces)
{
    struct ifconf 	ifconf;
    struct ifreq *	ifrp;
    int			sockfd;

    if (S_get_ifreq_buf(&sockfd, &ifconf) == FALSE)
	return (FALSE);

    interfaces->list 
	= (interface_t *)malloc((ifconf.ifc_len / sizeof(struct ifreq))
				* sizeof(*(interfaces->list)));
    if (interfaces->list == NULL)
	goto err;

#define IFR_NEXT(ifr)	\
    ((struct ifreq *) ((char *) (ifr) + sizeof(*(ifr)) + \
      MAX(0, (int) (ifr)->ifr_addr.sa_len - (int) sizeof((ifr)->ifr_addr))))

    interfaces->count = 0;
    for (ifrp = (struct ifreq *) ifconf.ifc_buf;
	 (char *) ifrp < &ifconf.ifc_buf[ifconf.ifc_len];
	 ifrp = IFR_NEXT(ifrp)) {
	struct sockaddr_in * 	sin_p;

	switch (ifrp->ifr_addr.sa_family) {
	  case AF_INET: {
	      struct ifreq	ifr;
	      interface_t *	entry;
	      struct hostent *	h;
	      struct in_addr	broadcast;
	      struct in_addr	mask;
	      short		flags;
	      u_char 		name[IFNAMSIZ + 1];

	      strncpy(ifr.ifr_name, ifrp->ifr_name, sizeof(ifr.ifr_name));
	      if (ioctl(sockfd, SIOCGIFFLAGS, (caddr_t)&ifr) < 0) {
		  syslog(LOG_INFO, "ioctl(SIOGIFFLAGS)");
		  continue;
	      }
	      if (!(ifr.ifr_flags & IFF_UP))
		  continue;
	      flags = ifr.ifr_flags;
	      if (ioctl(sockfd, SIOCGIFNETMASK, (caddr_t)&ifr) < 0) {
		  syslog(LOG_INFO, "ioctl(SIOGIFNETMASK)");
		  continue;
	      }
	      mask = ((struct sockaddr_in *)&ifr.ifr_addr)->sin_addr;
	      if (flags & IFF_BROADCAST) {
		  if (ioctl(sockfd, SIOCGIFBRDADDR, (caddr_t)&ifr)< 0) {
		      syslog(LOG_INFO, "ioctl(SIOCGBRDADDR)");
		      continue;
		  }
		  broadcast = ((struct sockaddr_in *)&ifr.ifr_addr)->sin_addr;
	      }
	      strncpy(name, ifrp->ifr_name, sizeof(name));
	      entry = if_lookupbyname(interfaces, name);
	      if (entry == NULL) { /* new entry */
		  entry = interfaces->list + interfaces->count++;
		  bzero(entry, sizeof(*entry));
		  strcpy(entry->name, name);
	      }
	      /* fill in the entry */
	      entry->mask = mask;
	      entry->flags = flags;
	      if (flags & IFF_BROADCAST)
		  entry->broadcast = broadcast; 
	      sin_p = (struct sockaddr_in *)&ifrp->ifr_addr;
	      entry->addr = sin_p->sin_addr;
	      entry->netaddr.s_addr = htonl(iptohl(entry->addr)
					    & iptohl(entry->mask));
	      h = gethostbyaddr((char *)&entry->addr, 
				sizeof(struct in_addr), AF_INET);
	      if (!h) {
		  if (gethostname(entry->hostname, sizeof(entry->hostname))) {
		      syslog(LOG_INFO, 
			     "gethostbyaddr(%s) and gethostname() failed",
			   inet_ntoa(entry->addr));
		      entry->hostname[0] = '\0';
		  }
	      }
	      else 
		  strcpy(entry->hostname, h->h_name);
	      entry->inet_valid = TRUE;
	      break;
	  }
	  case AF_LINK: {
	      struct sockaddr_dl * dl_p;
	      interface_t *	entry;
	      u_char 		name[IFNAMSIZ + 1];

	      dl_p = (struct sockaddr_dl *)&ifrp->ifr_addr;
	      strncpy(name, ifrp->ifr_name, sizeof(name));
	      entry = if_lookupbyname(interfaces, name);
	      if (entry == NULL) { /* new entry */
		  entry = interfaces->list + interfaces->count++;
		  bzero(entry, sizeof(*entry));
		  strcpy(entry->name, name);
	      }
	      entry->link = *dl_p;
	      entry->link_valid = TRUE;
	      break;
	  }
	}
    }
    if (interfaces->count == 0) {
	syslog(LOG_INFO, "no interfaces available\n");
	goto err;
    }
    /* make it the "right" size */
    interfaces->list = (interface_t *)
	realloc(interfaces->list, 
		sizeof(*(interfaces->list)) * interfaces->count);
    if (ifconf.ifc_buf)
	free(ifconf.ifc_buf);
    close(sockfd);
    return (TRUE);
  err:
    if (interfaces->list)
	free(interfaces->list);
    interfaces->list = NULL;
    if (ifconf.ifc_buf)
	free(ifconf.ifc_buf);
    close(sockfd);
    return (FALSE);
}

/*
 * Function: if_first_broadcast_inet
 *
 * Purpose:
 *   Return the first non-loopback, broadcast capable interface.
 */
interface_t *
if_first_broadcast_inet(interface_list_t * intface)
{
    int i;
    for (i = 0; i < intface->count; i++) {
	if (intface->list[i].inet_valid 
	    && !(intface->list[i].flags & IFF_LOOPBACK)
	    && (intface->list[i].flags & IFF_BROADCAST))
	    return (intface->list + i);
    }
    return (NULL);
}

interface_t *
if_lookupbyip(interface_list_t * intface, struct in_addr iaddr)
{
    int 	i;

    for (i = 0; i < intface->count; i++) {
	if (intface->list[i].inet_valid
	    && intface->list[i].addr.s_addr == iaddr.s_addr)
	    return (intface->list + i);
    }
    return (NULL);
}
interface_t *
if_lookupbysubnet(interface_list_t * intface, struct in_addr iaddr)
{
    int 	i;
    u_long	addr_hl = iptohl(iaddr);

    for (i = 0; i < intface->count; i++) {
	u_long ifnetaddr_hl = iptohl(intface->list[i].netaddr);
	u_long ifmask_hl = iptohl(intface->list[i].mask);

	if (intface->list[i].inet_valid
	    && (addr_hl & ifmask_hl) == ifnetaddr_hl)
	    return (intface->list + i);
    }
    return (NULL);
}

interface_t *
if_lookupbyname(interface_list_t * intface, const char * name)
{
    int i;

    for (i = 0; i < intface->count; i++) {
	if (strcmp(intface->list[i].name, name) == 0)
	    return (intface->list + i);
    }
    return (NULL);
}

interface_t *
if_lookupbylinkindex(interface_list_t * intface, int index)
{
    int i;

    for (i = 0; i < intface->count; i++) {
	if (intface->list[i].link_valid
	    && intface->list[i].link.sdl_index == index)
	    return (intface->list + i);
    }
    return (NULL);
}

interface_list_t *
if_init()
{
    interface_list_t * intface = (interface_list_t *)malloc(sizeof(*intface));
    if (intface == NULL
	|| S_build_interface_list(intface) == FALSE
	|| intface->count == 0) {
	if (intface)
	    free(intface);
	return (NULL);
    }
    return (intface);
}

void
if_free(interface_list_t * * intface)
{
    if (intface != NULL && *intface != NULL) {
	if ((*intface)->list)
	    free((*intface)->list);
	free(*intface);
	*intface = NULL;
    }
    return;
}

#ifdef TESTING
void
link_if_print(struct sockaddr_dl * dl_p)
{
    printf("len %d index %d family %d type 0x%x nlen %d alen %d"
	   " slen %d", dl_p->sdl_len, 
	   dl_p->sdl_index,  dl_p->sdl_family, dl_p->sdl_type,
	   dl_p->sdl_nlen, dl_p->sdl_alen, dl_p->sdl_slen);
    if (dl_p->sdl_type == IFT_ETHER && dl_p->sdl_alen == 6)
	printf(" %s", ether_ntoa((struct ether_addr *)
				   (dl_p->sdl_data 
				    + dl_p->sdl_nlen)));
    
    printf("\n");
}

int
main()
{
    {
	interface_list_t * list_p = if_init();
	if (list_p != NULL) {
	    int i;
	    int count = 0;
	    
	    printf("inet interfaces:\n");
	    for (i = 0; i < list_p->count; i++) {
		char 		addr[32];
		interface_t * 	if_p = list_p->list + i;
		
		if (if_p->inet_valid) {
		    strcpy(addr, inet_ntoa(if_p->addr));
		    printf("interface %s: %s ip address %s mask %s\n", 
			   if_p->name, if_p->hostname, addr, 
			   inet_ntoa(if_p->mask));
		}
		if (if_p->link_valid)
		    link_if_print(&if_p->link);
		count++;
	    }
	    if (count == 0) {
		printf("no available interfaces");
		exit(2);
	    }
	}
    }
    exit(0);
}
#endif TESTING
#if 0
/*
 * Return the number of leading bytes matching in the
 * internet addresses supplied.
 */
int
nmatch(ca,cb)
	register char *ca, *cb;
{
	register n,m;

	for (m = n = 0 ; n < 4 ; n++) {
		if (*ca++ != *cb++)
			return(m);
		m++;
	}
	return(m);
}

/*
 * Function: pick_interface
 *
 * Purpose:
 *   Find the correct server address to use based on the given ip destination.
 *   If we are multi-homed, pick the 'best' interface ie. the one on the same
 *   net as the client.
 */
interface_t *
pick_interface(struct in_addr * dst_p)
{
    interface_t *	best_p;
    int 		maxmatch;
    int			i;

    maxmatch = 0;
    best_p = NULL;
    for (i = 0; i < interfaces.count; i++) {
	int 		m;

	m = nmatch((caddr_t)dst_p, (caddr_t)&(interfaces.list[i].addr));
	if (m > maxmatch) {
	    maxmatch = m;
	    best_p = interfaces.list + i;
	}
    }
    return ((maxmatch == 0) ? NULL : best_p);
}

#endif
