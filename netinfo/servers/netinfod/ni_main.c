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
 * NetInfo server main
 * Copyright (C) 1989 by NeXT, Inc.
 *
 * TODO: shutdown at time of signal if no write transaction is in progress
 */
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <rpc/rpc.h>
#include <sys/signal.h>
#include <sys/ioctl.h>
#include <sys/file.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <errno.h>
#include "ni_server.h"
#include <sys/time.h>
#include <sys/socket.h>
#include "system.h"
#include "ni_globals.h"
#include "checksum.h"
#include "getstuff.h"
#include "mm.h"
#include "notify.h"
#include "ni_dir.h"
#include "alert.h"
#include "socket_lock.h"
#include "sanitycheck.h"
#include "proxy_pids.h"

#define NIBIND_TIMEOUT 60
#define NIBIND_RETRIES 9

#define PID_FILE	"/var/run/netinfo_%s.pid"

#define FD_SLOPSIZE 15 /* # of fds for things other than connections */

extern void ni_prog_2();
extern void ni_svc_run(int);

static void sigterm(void);
static ni_status start_service(char *);
static ni_status ni_register(ni_name, unsigned, unsigned);
static ni_status ni_unregister(ni_name);
static void usage(char *);
void setproctitle(int, char **, char *, ...);
void writepid(ni_name tag);

extern void readall_catcher(void);
extern void dblock_catcher(void);

extern void waitforparent(void);

extern const char netinfod_VERS_NUM[];

static void
closeall(void)
{
	int i;

	for (i = getdtablesize() - 1; i >= 0; i--) close(i);

	/*
	 * We keep 0, 1 & 2 open to avoid using them. If we didn't, a
	 * library routine might do a printf to our descriptor and screw
	 * us up.
	 */
	open("/dev/null", O_RDWR, 0);
	dup(0);
	dup(0);
}

void main(int argc, char *argv[])
{
	char **Argv;
	int Argc;

	ni_status status;
	ni_name myname = argv[0];
	int create = 0;
	ni_name dbsource_name = NULL;
	ni_name dbsource_addr = NULL;
	ni_name dbsource_tag = NULL;
	struct rlimit rlim;
	char *str;

	debug = DEBUG_SYSLOG;
	forcedIsRoot = 0;

	Argv = argv;
	Argc = argc;

	argc--;
	argv++;
	while (argc > 0 && **argv == '-')
	{
		if (strcmp(*argv, "-d") == 0)
		{
			if (argc < 2) debug = DEBUG_STDERR;
			else {
				debug = atoi(argv[1]);
				argc -= 1;
				argv += 1;
			}
		}
		else if (strcmp(*argv, "-n") == 0) forcedIsRoot = 1;
		else if (strcmp(*argv, "-m") == 0) create++;
		else if (strcmp(*argv, "-c") == 0)
		{
			if (argc < 4) usage(myname);

			create++;
			dbsource_name = argv[1];
			dbsource_addr = argv[2];
			dbsource_tag = argv[3];
			argc -= 3;
			argv += 3;
		}
		else usage(myname);

		argc--;
		argv++;
	}

	if (argc != 1) usage(myname);

	if (!(debug & DEBUG_STDERR)) closeall();

	db_tag = malloc(strlen(argv[0]) + 1);
	strcpy(db_tag, argv[0]);

	str = malloc(strlen("netinfod ") + strlen(db_tag) + 1);
	sprintf(str, "netinfod %s", db_tag);
	sys_openlog(str, LOG_NDELAY | LOG_PID, LOG_NETINFO);
	free(str);

	sys_msg(debug, LOG_DEBUG, "version %s (pid %d) - starting\n",
		netinfod_VERS_NUM, getpid());

	rlim.rlim_cur = rlim.rlim_max = RLIM_INFINITY;
	setrlimit(RLIMIT_CORE, &rlim);
	umask(S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH);

	readall_mutex = mutex_alloc();
	lockup_mutex = mutex_alloc();
	cleanupwait = CLEANUPWAIT;
	auth_count[GOOD] = 0;
	auth_count[BAD] = 0;
	auth_count[WGOOD] = 0;
	auth_count[WBAD] = 0;

	if (create)
	{
		if (dbsource_addr == NULL)
		{
			sys_msg(debug, LOG_DEBUG, "creating master");
			status = dir_mastercreate(db_tag);
		}
		else
		{
			sys_msg(debug, LOG_DEBUG, "creating clone");
			status = dir_clonecreate(db_tag, dbsource_name,
				dbsource_addr, dbsource_tag);
		}

		if (status != NI_OK) exit(status);
	}
	
	signal(SIGTERM, (void *)sigterm);
	signal(SIGHUP, SIG_IGN);
	signal(SIGPIPE, SIG_IGN);
	signal(SIGCHLD, (void *)readall_catcher);
	signal(SIGINT, (void *)dblock_catcher);

	writepid(db_tag);

	status = start_service(db_tag);
	if (status != NI_OK)
	{
	    sys_msg(debug, LOG_ERR, "start_service(%s) failed - exiting", db_tag);
		exit(status);
	}

	setproctitle(Argc, Argv, "netinfod %s (%s)",
		db_tag, i_am_clone ? "clone" : "master");

	if (i_am_clone)
	{
		sys_msg(debug, LOG_DEBUG, "checking clone");
		cloneReadallResponseOK = get_clone_readall(db_ni);
		dir_clonecheck();
		if (get_sanitycheck(db_ni)) sanitycheck(db_tag);
		sys_msg(debug, LOG_DEBUG, "finished clone check");
	}
	else
	{
		sys_msg(debug, LOG_DEBUG, "setting up master server");
		get_readall_info(db_ni, &max_readall_proxies, &strict_proxies);
		max_subthreads = get_max_subthreads(db_ni);
		update_latency_secs = get_update_latency(db_ni);

		/* Tracking readall proxy pids uses ObjC, so isolate it */
		initialize_readall_proxies(-1 == max_readall_proxies ?
			MAX_READALL_PROXIES : max_readall_proxies);

		sys_msg(debug, LOG_DEBUG, "starting notify thread");
		(void) notify_start();
	}

	sys_msg(debug, LOG_DEBUG, "starting RPC service");

	ni_svc_run(FD_SETSIZE - (FD_SLOPSIZE + max_subthreads));

	sys_msg(debug, LOG_DEBUG, "shutting down");

	/*
	 * Tell the readall proxies to shut down
	 */
	if (readall_proxies > 0)
	{
		sys_msg(debug, LOG_INFO, "killing %d readall prox%s", readall_proxies,
			1 == readall_proxies ? "y" : "ies");
		if (!kill_proxies())
			sys_msg(debug, LOG_WARNING, "some readall proxies still running");
	}

	ni_shutdown(db_ni, db_checksum);
	sys_msg(debug, LOG_INFO, "exiting; checksum %u", db_checksum);
	status = ni_unregister(db_tag);
	exit(0);
}


static ni_status
register_it(ni_name tag)
{
	SVCXPRT *transp;
	ni_status status;
	unsigned udp_port;
	unsigned tcp_port;

	transp = svcudp_create(RPC_ANYSOCK);
	if (transp == NULL) return (NI_SYSTEMERR);

	if (!svc_register(transp, NI_PROG, NI_VERS, ni_prog_2, 0))
		return (NI_SYSTEMERR);

	udp_port = transp->xp_port;
	udp_sock = transp->xp_sock;

	transp = svctcp_create(RPC_ANYSOCK, NI_SENDSIZE, NI_RECVSIZE);
	if (transp == NULL) return (NI_SYSTEMERR);

	if (!svc_register(transp, NI_PROG, NI_VERS, ni_prog_2, 0))
		return (NI_SYSTEMERR);

	tcp_port = transp->xp_port;
	tcp_sock = transp->xp_sock;

	if ((forcedIsRoot == 0) && (ni_name_match(tag, "local")))
		waitforparent();

	sys_msg(debug, LOG_DEBUG, "registering %s udp %u tcp %u",
			tag, udp_port, tcp_port);
	status = ni_register(tag, udp_port, tcp_port);
	if (status != NI_OK)
	{
		sys_msg(debug, LOG_DEBUG, "ni_register: %s",
			tag, ni_error(status));
		return (status);
	}
	return (NI_OK);
}

static ni_status
start_service(ni_name tag)
{
	ni_name master;
	ni_status status;
	ni_name dbname;
	unsigned long addr;
	struct in_addr inaddr;

	sys_msg(debug, LOG_DEBUG, "directory cleanup");
	dir_cleanup(tag);
	dir_getnames(tag, &dbname, NULL, NULL);

	sys_msg(debug, LOG_DEBUG, "initializing server");
	status = ni_init(dbname, &db_ni);
	ni_name_free(&dbname);
	if (status != NI_OK) return (status);

	checksum_compute(&db_checksum, db_ni);
	sys_msg(debug, LOG_DEBUG, "checksum = %u", db_checksum);

	if (getmaster(db_ni, &master, NULL))
	{
		addr = getaddress(db_ni, master);
		inaddr.s_addr = addr;
		if (addr != 0)
		{
			if (!sys_ismyaddress(addr)) i_am_clone++;		    
		}
	}

	ni_name_free(&master);

	if (forcedIsRoot == 0)
		forcedIsRoot = get_forced_root(db_ni);

	sys_msg(debug, LOG_DEBUG, "registering tag %s", tag);
	status = register_it(tag);
	return (status);
}

static void
sigterm(void)
{
	shutdown_server++;
}

static ni_status
ni_register(ni_name tag, unsigned udp_port, unsigned tcp_port)
{
	nibind_registration reg;
	ni_status status;
	CLIENT *cl;
	int sock;
	struct sockaddr_in sin;
	struct timeval tv;

	sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	sin.sin_port = 0;
	sin.sin_family = AF_INET;
	bzero(sin.sin_zero, sizeof(sin.sin_zero));
	sock = socket_open(&sin, NIBIND_PROG, NIBIND_VERS);
	if (sock < 0) return (NI_SYSTEMERR);

	tv.tv_sec = NIBIND_TIMEOUT / (NIBIND_RETRIES + 1);
	tv.tv_usec = 0;
	cl = clntudp_create(&sin, NIBIND_PROG, NIBIND_VERS, tv, &sock);
	if (cl == NULL)
	{
		socket_close(sock);
		return (NI_SYSTEMERR);
	}

	reg.tag = tag;
	reg.addrs.udp_port = udp_port;
	reg.addrs.tcp_port = tcp_port;
	tv.tv_sec = NIBIND_TIMEOUT;
	if (clnt_call(cl, NIBIND_REGISTER, xdr_nibind_registration,
		  &reg, xdr_ni_status, &status, tv) != RPC_SUCCESS)
	{
		clnt_destroy(cl);
		socket_close(sock);
		return (NI_SYSTEMERR);
	}
	clnt_destroy(cl);
	socket_close(sock);
	return (status);
}

static ni_status
ni_unregister(ni_name tag)
{
	ni_status status;
	CLIENT *cl;
	int sock;
	struct sockaddr_in sin;
	struct timeval tv;

	sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	sin.sin_port = 0;
	sin.sin_family = AF_INET;
	bzero(sin.sin_zero, sizeof(sin.sin_zero));
	sock = socket_open(&sin, NIBIND_PROG, NIBIND_VERS);
	if (sock < 0) return (NI_SYSTEMERR);

	tv.tv_sec = NIBIND_TIMEOUT / (NIBIND_RETRIES + 1);
	tv.tv_usec = 0;
	cl = clntudp_create(&sin, NIBIND_PROG, NIBIND_VERS, tv, &sock);
	if (cl == NULL)
	{
		socket_close(sock);
		return (NI_SYSTEMERR);
	}

	tv.tv_sec = NIBIND_TIMEOUT;

	if (clnt_call(cl, NIBIND_UNREGISTER, xdr_ni_name,
		  &tag, xdr_ni_status, &status, tv) != RPC_SUCCESS)
	{
		clnt_destroy(cl);
		socket_close(sock);
		return (NI_SYSTEMERR);
	}

	clnt_destroy(cl);
	socket_close(sock);
	return (status);
}

static void 
usage(char *myname)
{
	fprintf(stderr, "usage: netinfod [-m] [-c name addr tag] tag\n");
	exit(1);
}

#ifdef MALLOC_DEBUG
void  catch_malloc_problems(int problem)
{
	abort();
}
#endif

void writepid(ni_name tag)
{
	FILE *fp;
	char *fname;

	fname = (char *)malloc(strlen(tag) + strlen(PID_FILE) + 1);
    sprintf(fname, PID_FILE, tag);

	fp = fopen(fname, "w");
    if (fp == NULL)
	{
		sys_msg(debug, LOG_ERR, "Cannot open PID file %s", fname);
		free(fname);
		return;
	}

	fprintf(fp, "%d\n", getpid());
	if (fclose(fp) != 0)
	sys_msg(debug, LOG_ERR, "error closing PID file '%s': %m", fname);
}

/*VARARGS1*/
void setproctitle(int argc, char **argv, char *fmt, ...)
{
	va_list ap;
	char *last, *p;
	int i, len, arglen;
	char buf[NI_NAME_MAXLEN + BUFSIZ];	/* Message buffer */

	va_start(ap, fmt);
    vsprintf(buf, fmt, ap);
	va_end(ap);

 	last = argv[argc - 1] + strlen(argv[argc - 1]);
	p = argv[0];
	arglen = last - p;

	len = strlen(buf);
	if (len > arglen) return;

	sprintf(p, buf);
	p += len;
	for (i = len; i < arglen; i++) *p++ = ' ';
}
