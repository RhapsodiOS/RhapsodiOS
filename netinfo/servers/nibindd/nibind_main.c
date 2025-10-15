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
 * nibindd - NetInfo binder
 * Copyright 1989-94, NeXT Computer Inc.
 */
#include <rpc/rpc.h>
#include <rpc/pmap_clnt.h>
#include <stdio.h>
#include <libc.h>
#include <stdlib.h>
#include <string.h>
#include <netinfo/ni.h>
#include <sys/dir.h>
#include <sys/ioctl.h>
#include <sys/param.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <syslog.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/resource.h>
#include <errno.h>
#include "mm.h"
#include "system.h"

extern int debug;

/* getppid() should be in libc.h, but it isn't */
extern int getppid(void);

const char NETINFO_PROG[] = "/usr/sbin/netinfod";
const char NIBINDD_PROG[] = "/usr/sbin/nibindd";
const char NETINFO_DIR[] = "/etc/netinfo";
const char PID_FILE[] = "/var/run/nibindd.pid";

extern const char nibindd_VERS_NUM[];

void nibind_svc_run(void);
extern void nibind_prog_1();

int isnidir(char *, ni_name *);

extern void catchchild(int);
extern void killchildren(int);
extern void respawn(void);
extern void storepid(int, ni_name);

static void parentexit(int);
static void closeall(void);
static void writepid(void);
static void killparent(void);
static void catchhup(int);

extern int waitreg;
static int restart;

void
main(int argc, char *argv[])
{
	SVCXPRT *transp;
	DIR *dp;
	struct direct *d;
	ni_name tag = NULL;
	ni_namelist nl;
	ni_index i;
	int pid, ni_debug;
	struct rlimit rlim;
	char *netinfod_argv[16]; /* XXX */
	int netinfod_argc, x;

	netinfod_argc = 0;
	netinfod_argv[netinfod_argc++] = (char *)NETINFO_PROG;

	debug = DEBUG_SYSLOG;
	ni_debug = DEBUG_NONE;

	for (i = 1; i < argc; i++)
	{
		if (!strcmp(argv[i], "-n"))
		{
			netinfod_argv[netinfod_argc++] = argv[i];
		}

		if (!strcmp(argv[i], "-d"))
		{
			debug = DEBUG_STDERR;
			if ((argc > (i+1)) && (argv[i+1][0] != '-'))
				debug = atoi(argv[++i]);
		}

		if (!strcmp(argv[i], "-D"))
		{
			netinfod_argv[netinfod_argc++] = "-d";

			if ((argc > (i+1)) && (argv[i+1][0] != '-'))
			{
				ni_debug = atoi(argv[++i]);
				netinfod_argv[netinfod_argc++] = argv[i];
			}
			else
			{
				ni_debug = DEBUG_STDERR;
			}
		}
	}

	sys_openlog("nibindd", LOG_NDELAY | LOG_PID, LOG_NETINFO);

	if (debug & DEBUG_STDERR)
	{
		sys_msg(debug, LOG_DEBUG, "version %s - debug mode\n",
			nibindd_VERS_NUM);
	}
	else
	{
		sys_msg(debug, LOG_DEBUG, "version %s - starting\n",
			nibindd_VERS_NUM);

		closeall();

		if (fork())
		{
			sys_msg(debug, LOG_DEBUG, "parent waiting for child to start");
			signal(SIGTERM, parentexit);
			for (;;) pause();
		}
	}

	writepid();

	rlim.rlim_cur = rlim.rlim_max = RLIM_INFINITY;
	setrlimit(RLIMIT_CORE, &rlim);
	signal(SIGCHLD, catchchild);
	signal(SIGTERM, killchildren);
	signal(SIGHUP, catchhup);
	signal(SIGINT, SIG_IGN);

	/*
	 * cd to netinfo directory, find out which databases should
	 * be served and lock the directory before registering service.
	 */
	if (chdir(NETINFO_DIR) < 0)
	{
		killparent();
		sys_msg(debug, LOG_ALERT, "cannot chdir to netinfo directory");
	}

	dp = opendir(NETINFO_DIR);
	if (dp == NULL)
	{
		killparent();
		sys_msg(debug, LOG_ALERT, "cannot open netinfo directory");
	}

	MM_ZERO(&nl);
	while ((d = readdir(dp)))
	{
		if (isnidir(d->d_name, &tag))
		{
			if (ni_namelist_match(nl, tag) == NI_INDEX_NULL)
			{
				sys_msg(debug, LOG_DEBUG, "found database: %s", tag);
				ni_namelist_insert(&nl, tag, NI_INDEX_NULL);
			} 
			ni_name_free(&tag);
		}
	}

#ifdef _NETINFO_FLOCK_
	/*
	 * Do not close the directory: keep it locked so another nibindd
	 * won't run.
	 */
	if (flock(dp->dd_fd, LOCK_EX|LOCK_NB) < 0)
	{
		killparent();
		sys_msg(debug, LOG_ALERT, "nibindd already running");
	}
	fcntl(dp->dd_fd, F_SETFD, 1);
#else
	closedir(dp);
#endif

	/*
	 * Register as a SUNRPC service
	 */
	pmap_unset(NIBIND_PROG, NIBIND_VERS);
	transp = svcudp_create(RPC_ANYSOCK);
	if (transp == NULL)
	{
		killparent();
		sys_msg(debug, LOG_ALERT, "cannot start udp service");
	}

	if (!svc_register(transp, NIBIND_PROG, NIBIND_VERS, nibind_prog_1,
			  IPPROTO_UDP))
	{
		killparent();
		sys_msg(debug, LOG_ALERT, "cannot register udp service");
	}

	transp = svctcp_create(RPC_ANYSOCK, 0, 0);
	if (transp == NULL)
	{
		killparent();
		sys_msg(debug, LOG_ALERT, "cannot start tcp service");
	}

	if (!svc_register(transp, NIBIND_PROG, NIBIND_VERS, nibind_prog_1,
			  IPPROTO_TCP))
	{
		killparent();
		sys_msg(debug, LOG_ALERT, "cannot register tcp service");
	}

	waitreg = 0;
	for (i = 0; i < nl.ninl_len; i++)
	{
		netinfod_argv[netinfod_argc] = nl.ninl_val[i];
		netinfod_argv[netinfod_argc + 1] = NULL;

		sys_msg(debug, LOG_DEBUG, "starting netinfod %s", nl.ninl_val[i]);
		sys_msg(debug, LOG_DEBUG, "execv debug 0: %s", NETINFO_PROG);
		for (x = 0; netinfod_argv[x] != NULL; x++)
			sys_msg(debug, LOG_DEBUG, "execv debug %d: %s",
				x, netinfod_argv[x]);

		pid = fork();
		if (pid == 0)
		{
			/* child */
			execv(NETINFO_PROG, netinfod_argv);
			exit(-1);
		}

#ifdef DEBUG
		sys_msg(debug, LOG_DEBUG, "netinfod %s pid = %d", nl.ninl_val[i], pid);
#endif

		if (pid > 0)
		{
			waitreg++;
			storepid(pid, nl.ninl_val[i]);
		}
		else
		{
			sys_msg(debug, LOG_ERR,
				"server for tag %s failed to start", nl.ninl_val[i]);
		}
	}

	ni_namelist_free(&nl);

	/*
	 * Detach from controlling tty.
	 * Do this AFTER starting netinfod so "type c to continue..." works.
	 */
	setsid();

	restart = 0;

	sys_msg(debug, LOG_DEBUG, "starting RPC service");

	nibind_svc_run();
	sys_msg(debug, LOG_ALERT, "svc_run returned");
	exit(1);
}

static char *suffixes[] = {
	".nidb",
	".move",
	".temp",
	NULL
};

int
isnidir(char *dir, ni_name *tag)
{
	char *s;
	int i;
	
	s = rindex(dir, '.');
	if (s == NULL) {
		return (0);
	}
	for (i = 0; suffixes[i] != NULL; i++) {
		if (ni_name_match(s, suffixes[i])) {
			*tag = ni_name_dup(dir);
			s = rindex(*tag, '.');
			*s = 0;
			return (1);
		}
	}
	return (0);
}

static void
closeall(void)
{
	int i;

	for (i = getdtablesize() - 1; i <= 0; i--) close(i);

	open("/dev/null", O_RDWR, 0);
	dup(0);
	dup(0);
}

static void
killparent(void)
{
	kill(getppid(), SIGTERM);
}

void
nibind_svc_run(void)
{
	fd_set readfds;
	int maxfds;

	maxfds = getdtablesize();
	for (;;)
	{
		readfds = svc_fdset;
		switch (select(maxfds, &readfds, NULL, NULL, NULL))
		{
			case -1:
				if (errno != EINTR)
				{
					sys_msg(debug, LOG_ALERT,
						"unexpected errno: %m, aborting");
				}
			break;

			case 0:
				break;
			default:
				svc_getreqset(&readfds);
				break;
		}

		if (waitreg == 0)
		{
			waitreg = -1;
			if (debug & DEBUG_STDERR)
			{
				sys_msg(debug, LOG_DEBUG, "all servers registered");
			}
			else 
			{
				sys_msg(debug, LOG_DEBUG,
					"all servers registered - signalling parent");
				killparent();
			}
		}

		if (restart == 1)
		{
			svc_unregister(NIBIND_PROG, NIBIND_VERS);
			pmap_unset(NIBIND_PROG, NIBIND_VERS);
			respawn();
		}
	}
}
	 
static void
parentexit(int x)
{
	sys_msg(debug, LOG_DEBUG, "parent exiting");
	exit(0);
}

static void
catchhup(int sig)
{
	restart = 1;
}

static void
writepid(void)
{
	FILE *fp;

	fp = fopen(PID_FILE, "w");
	if (fp != NULL)
	{
		fprintf(fp, "%d\n", getpid());
		fclose(fp);
	}
}
