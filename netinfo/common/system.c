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
 * System routines
 * Copyright (C) 1989 by NeXT, Inc.
 */
#include <stdio.h>
#include <unistd.h>
#include <rpc/rpc.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/param.h>
#include <sys/file.h>
#include <syslog.h>
#include <stdarg.h>
#include <mach/cthreads.h>
#include "system.h"
#include "socket_lock.h"

static volatile mutex_t log_mutex;
static char *msg_str = NULL;

void
sys_openlog(char * str, int flags, int facility)
{
	if (msg_str != NULL) free(msg_str);
	msg_str = NULL;
	if (str != NULL)
	{
		msg_str = malloc(strlen(str) + 1);
		strcpy(msg_str, str);
	}

	openlog(msg_str, flags, facility);
}
	
char *
sys_hostname(void)
{

	static char myhostname[MAXHOSTNAMELEN + 1];

	if (myhostname[0] == 0) {
		(void)gethostname(myhostname, sizeof(myhostname));
	}
	return (myhostname);
}

void
sys_msg(int debug, int priority, char *message, ...)
{
	va_list ap;
	int panic;

	if (log_mutex == NULL) log_mutex = mutex_alloc();

	mutex_lock(log_mutex);

	va_start(ap, message);
	if ((debug & DEBUG_SYSLOG) || (priority > LOG_DEBUG))
		vsyslog(priority, message, ap);
	if (debug & DEBUG_STDERR)
	{
		if (msg_str != NULL) fprintf(stderr, "%s: ", msg_str);
		vfprintf(stderr, message, ap);
		fprintf(stderr, "\n");
		fflush(stderr);
	}
	va_end(ap);

	panic = 0;
	if (priority <= LOG_ALERT)
	{
		syslog(priority, "aborting!");
		if (debug & DEBUG_STDERR)
		{
			fprintf(stderr, "aborting!\n");
			fflush(stderr);
		}
		panic = 1;
	}

	mutex_unlock(log_mutex);

	if (panic) abort();
}
	
int
sys_spawn(const char *fname, ...)
{
	va_list ap;
	char *args[10]; /* XXX */
	int i;
	int pid;
	
	va_start(ap, (char *)fname);
	args[0] = (char *)fname;
	for (i = 1; args[i] = va_arg(ap, char *); i++) {
	}
	va_end(ap);

	switch (pid = fork()) {
	case -1:
		return (-1);
	case 0:
		execv(args[0], args);
		_exit(-1);
	default:
		return (pid);
	}
}

unsigned long
sys_address(void)
{
	struct ifconf ifc;
	struct ifreq *ifr;
	char buf[1024]; /* XXX */
	int offset, addrlen;
	int sock;
	unsigned long addr;

	socket_lock();
	sock = socket(AF_INET, SOCK_DGRAM, 0);
	socket_unlock();

	if (sock < 0) return (htonl(INADDR_LOOPBACK));

	ifc.ifc_len = sizeof(buf);
	ifc.ifc_buf = buf;

	if (ioctl(sock, SIOCGIFCONF, (char *)&ifc) < 0)
	{
		socket_close(sock);
		return (htonl(INADDR_LOOPBACK));
	}

	addrlen = sizeof(struct ifreq) - IFNAMSIZ;
	offset = 0;

	while (offset <= ifc.ifc_len)
	{
		ifr = (struct ifreq *)(ifc.ifc_buf + offset);
		offset += IFNAMSIZ;
		if (ifr->ifr_addr.sa_len > addrlen) offset += ifr->ifr_addr.sa_len;
		else offset += addrlen;

		if (ifr->ifr_addr.sa_family != AF_INET) continue;
		if (ioctl(sock, SIOCGIFFLAGS, ifr) < 0) continue;

		addr = ((struct sockaddr_in *)&(ifr->ifr_addr))->sin_addr.s_addr;
		if
		(
			(ifr->ifr_flags & IFF_UP) &&
			(!(ifr->ifr_flags & IFF_LOOPBACK)) &&
			(addr != 0) &&
			(addr != -1)
		)
		{
			socket_close(sock);
			return addr;
		}
	}

	socket_close(sock);
	return (htonl(INADDR_LOOPBACK));
}

unsigned long
sys_netmask(void)
{
	struct ifconf ifc;
	struct ifreq *ifr;
	char buf[1024]; /* XXX */
	int offset, addrlen;
	int sock;
	unsigned long addr;

	socket_lock();
	sock = socket(AF_INET, SOCK_DGRAM, 0);
	socket_unlock();

	if (sock < 0) return (htonl(IN_CLASSA_NET));

	ifc.ifc_len = sizeof(buf);
	ifc.ifc_buf = buf;

	if (ioctl(sock, SIOCGIFCONF, (char *)&ifc) < 0)
	{
		socket_close(sock);
		return (htonl(IN_CLASSA_NET));
	}

	addrlen = sizeof(struct ifreq) - IFNAMSIZ;
	offset = 0;

	while (offset <= ifc.ifc_len)
	{
		ifr = (struct ifreq *)(ifc.ifc_buf + offset);
		offset += IFNAMSIZ;
		if (ifr->ifr_addr.sa_len > addrlen) offset += ifr->ifr_addr.sa_len;
		else offset += addrlen;

		if (ifr->ifr_addr.sa_family != AF_INET) continue;
		if (ioctl(sock, SIOCGIFFLAGS, (char *)ifr) < 0) continue;

		addr = ((struct sockaddr_in *)&(ifr->ifr_addr))->sin_addr.s_addr;
		if
		(
			(ifr->ifr_flags & IFF_UP) &&
			(!(ifr->ifr_flags & IFF_LOOPBACK)) &&
			(addr != 0) &&
			(addr != -1)
		)
		{
			ioctl(sock, SIOCGIFNETMASK, (char *)ifr);
			addr = ((struct sockaddr_in *)&(ifr->ifr_addr))->sin_addr.s_addr;
			socket_close(sock);
			return (addr);
		}
	}

	socket_close(sock);
	return (htonl(IN_CLASSA_NET));
}

int
sys_ismyaddress(unsigned long addr)
{
	struct ifconf ifc;
	struct ifreq *ifr;
	char buf[1024]; /* XXX */
	int offset, addrlen;
	int sock;
	struct sockaddr_in *sin;

	if (addr == htonl(INADDR_LOOPBACK)) return 1;

	socket_lock();
	sock = socket(AF_INET, SOCK_DGRAM, 0);
	socket_unlock();

	if (sock < 0) return 0;

	ifc.ifc_len = sizeof(buf);
	ifc.ifc_buf = buf;

	if (ioctl(sock, SIOCGIFCONF, (char *)&ifc) < 0)
	{
		socket_close(sock);
		return 0;
	}

	addrlen = sizeof(struct ifreq) - IFNAMSIZ;
	offset = 0;

	while (offset <= ifc.ifc_len)
	{
		ifr = (struct ifreq *)(ifc.ifc_buf + offset);
		offset += IFNAMSIZ;
		if (ifr->ifr_addr.sa_len > addrlen) offset += ifr->ifr_addr.sa_len;
		else offset += addrlen;

		if (ifr->ifr_addr.sa_family != AF_INET) continue;
		if (ioctl(sock, SIOCGIFFLAGS, ifr) < 0) continue;

		sin = (struct sockaddr_in *)&ifr->ifr_addr;
		if ((ifr->ifr_flags & IFF_UP) &&
			(!(ifr->ifr_flags & IFF_LOOPBACK)) &&
			(sin->sin_addr.s_addr == addr))
		{
			socket_close(sock);
			return 1;
		}
	}

	socket_close(sock);
	return 0;
}

int
sys_standalone(void)
{
	return (sys_address() == htonl(INADDR_LOOPBACK));
}


long
sys_time(void)
{
	struct timeval tv;

	(void)gettimeofday(&tv, NULL);
	return (tv.tv_sec);
}
