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
#import <objc/objc-runtime.h>
#import <stdio.h>
#import "Syslog.h"
#import "Controller.h"
#import "LookupDaemon.h"
#import "MemoryWatchdog.h"
#import <mach/cthreads.h>
#import <mach/mach.h>
#import <mach/message.h>
#import <mach/mig_errors.h>
#import <sys/file.h>
#import <sys/types.h>
#import <sys/ioctl.h>
#import <sys/resource.h>
#import <sys/signal.h>
#import <sys/wait.h>
#import <syslog.h>
#import <unistd.h>
#import <sys/time.h>
#import <sys/resource.h>
#import <signal.h>
#import <servers/netname.h>

#define forever for (;;)
#define PID_FILE "/var/run/lookupd.pid"

extern int getppid(void);
extern port_t _lookupd_port(port_t);
extern void interactive(FILE *, FILE*);

extern BOOL _NSIsMultiThreaded;

#if NS_TARGET_MAJOR == 3
extern const char VERS_NUM[];
#else
extern const char lookupd_VERS_NUM[];
#endif

BOOL debugMode;
struct
{
	msg_header_t head;
} restart_msg;

/*
 * GLOBALS - see LUGlobal.h
 */
id controller;
id lookupLog;
id machRPC;
id rover;
char *portName;
port_t server_port;
port_t server_port_unprivileged;
port_t server_port_privileged;
BOOL shadowPasswords;

static void
writepid(void)
{
	FILE *fp;

	fp = fopen(PID_FILE, "w");
	if (fp != NULL) {
		fprintf(fp, "%d\n", getpid());
		(void) fclose(fp);
	}
}

static void
detach(void)
{
	int i;

	signal(SIGINT, SIG_IGN);
	signal(SIGPIPE, SIG_IGN);

	for (i = getdtablesize() - 1; i <= 0; i--) close(i);

	open("/dev/null", O_RDWR, 0);
	dup(0);
	dup(0);

	if (setsid() < 0) syslog(LOG_ERR, "lookupd: setsid() failed: %m");
}

void
parentexit(int x)
{
	exit(0);
}

void
goodbye(int x)
{
	exit(1);
}

int
lookupd_running(const char *name)
{
	kern_return_t status;
	port_t aport;

	if (name == NULL)
	{
		aport = _lookupd_port(0);
		if (aport != MACH_PORT_NULL) return 1;
		return 0;
	}

	if (!strcmp(name, DefaultName))
	{
		aport = _lookupd_port(0);
		if (aport != MACH_PORT_NULL) return 1;
		return 0;
	}

	status = netname_look_up(name_server_port, "", (char *)name, &aport);
	if (status == KERN_SUCCESS) return 1;
	return 0;
}

void handleSIGHUP()
{
	restart_msg.head.msg_remote_port = restart_msg.head.msg_local_port;
	restart_msg.head.msg_local_port = MACH_PORT_NULL;
	msg_send((msg_header_t *)&restart_msg, MSG_OPTION_NONE, 0);
}

/*
 * Restart everything.
 */
void restart()
{
	char *Argv[7], pidstr[32], portstr1[32], portstr2[32];
	int pid;

	if (debugMode)
	{
		fprintf(stderr, "Caught SIGHUP - exiting\n");
		
		[controller release];
		[rover release];
		exit(0);
	}

	[lookupLog syslogNotice:"Restarting lookupd"];

	sprintf(pidstr,  "%d", getpid());
	sprintf(portstr1, "%d", server_port_unprivileged);
	sprintf(portstr2, "%d", server_port_privileged);

	Argv[0] = "lookupd";
	Argv[1] = "-r";
	Argv[2] = portstr1;
	Argv[3] = portstr2;
	Argv[4] = pidstr;
	Argv[5] = shadowPasswords ? NULL : "-u";
	Argv[6] = NULL;

	pid = fork();
	if (pid > 0)
	{
		signal(SIGTERM, parentexit);
		forever sleep(1);
	}

	execv("/usr/sbin/lookupd", Argv);
}

int main(int argc, char *argv[])
{
	int i, len, pid;
	BOOL restarting;
	BOOL customName;
	BOOL printFinalStats;
	char *configDir;
	struct rlimit rlim;
	LUArray *sList;
	LUDictionary *stats;
	port_t old_port_unprivileged;
	port_t old_port_privileged;
	task_t old_lu;

	/* Clean up and re-initialize state on SIGHUP */
	signal(SIGHUP, handleSIGHUP);

	objc_setMultithreaded(YES);
	_NSIsMultiThreaded = YES;

	old_port_unprivileged = MACH_PORT_NULL;
	old_port_privileged = MACH_PORT_NULL;
	pid = -1;
	restarting = NO;
	debugMode = NO;
	customName = NO;
	printFinalStats = NO;
	configDir = NULL;
	portName = DefaultName;
	server_port = MACH_PORT_NULL;
	server_port_unprivileged = MACH_PORT_NULL;
	server_port_privileged = MACH_PORT_NULL;
	shadowPasswords = YES;

	for (i = 1; i < argc; i++)
	{
		if (!strcmp(argv[i], "-r"))
		{
			if (((argc - i) - 1) < 2) 
			{
				fprintf(stderr,"usage: lookupd -r unprivport privport pid\n");
				exit(1);
			}

			restarting = YES;
			old_port_unprivileged = (port_t)atoi(argv[++i]);
			old_port_privileged = (port_t)atoi(argv[++i]);
			pid = atoi(argv[++i]);
		}

		else if (!strcmp(argv[i], "-d"))
		{
			debugMode = YES;
			portName = DebugName;
		}

		else if (!strcmp(argv[i], "-D"))
		{
			debugMode = YES;
			customName = YES;
			if (((argc - i) - 1) < 1) 
			{
				fprintf(stderr,"usage: lookupd -D name\n");
				exit(1);
			}
			portName = argv[++i];
		}

		else if (!strcmp(argv[i], "-s")) printFinalStats = YES;

		else if (!strcmp(argv[i], "-u")) shadowPasswords = NO;

		else
		{
			fprintf(stderr, "Unknown option: %s\n", argv[i]);
			exit(1);
		}
	}

	if (restarting && debugMode)
	{
		fprintf(stderr, "Can't restart in debug mode\n");
		exit(1);
	}

	if ((!restarting) && lookupd_running(portName))
	{
		if (debugMode)
		{
			if (customName)
			{
				fprintf(stderr, "lookupd -D %s is already running!\n",
					portName);
			}
			else
			{
				fprintf(stderr, "lookupd -d is already running!\n");
			}
		}
		else
		{
			fprintf(stderr, "lookupd is already running!\n");
			syslog(LOG_ERR, "lookupd is already running!\n");
		}
		exit(1);
	}

	rover = [[MemoryWatchdog alloc] init];

	if (debugMode)
	{
		controller = [[Controller alloc] initWithName:portName];
		if (controller == nil)
		{
			fprintf(stderr, "controller didn't init!\n");
			exit(1);
		}

#if NS_TARGET_MAJOR == 3
		printf("lookupd version %s\n", VERS_NUM);
#else
		printf("lookupd version %s\n", lookupd_VERS_NUM);
#endif
		printf("Debug mode\n");
		interactive(stdin, stdout);

		if (printFinalStats)
		{
			sList = [controller allStatistics];
			len = [sList count];
			for (i = 0; i < len; i++)
			{
				stats = [sList objectAtIndex:i];
				if (stats != nil) [stats print:stdout];
			}
			[sList release];
		}

		[controller release];
		[rover release];
		exit(0);
	}

	if (restarting)
	{
		if (task_by_unix_pid(task_self(), pid, &old_lu) != KERN_SUCCESS)
		{
			syslog(LOG_EMERG, "Can't get port for PID %d", pid);
			exit(1);
		}

		if (port_extract_receive(old_lu, old_port_unprivileged, &server_port_unprivileged)
			!= KERN_SUCCESS || 
		    port_extract_receive(old_lu, old_port_privileged, &server_port_privileged)
			!= KERN_SUCCESS || 
		    port_set_allocate(task_self(), &server_port)
			!= KERN_SUCCESS || 
		    port_set_add(task_self(), server_port, server_port_unprivileged)
			!= KERN_SUCCESS || 
		    port_set_add(task_self(), server_port, server_port_privileged)
			!= KERN_SUCCESS)
		{
			syslog(LOG_EMERG, "Can't grab port rights");
			kill(pid, SIGKILL);
			exit(1);
		}
	}
	else
	{
		pid = fork();
		if (pid > 0)
		{
			signal(SIGTERM, parentexit);
			forever sleep(1);
		}

		detach();
	}

	if (!debugMode) writepid();

	rlim.rlim_cur = rlim.rlim_max = RLIM_INFINITY;
	setrlimit(RLIMIT_CORE, &rlim);
	signal(SIGTERM, goodbye);

	controller = [[Controller alloc] initWithName:portName];
	if (controller == nil)
	{
		[lookupLog syslogEmergency:"controller didn't init!"];
		kill(getppid(), SIGTERM);
		exit(1);
	}

	port_allocate(task_self(), &restart_msg.head.msg_local_port);
	restart_msg.head.msg_size = sizeof(restart_msg);

	kill(getppid(), SIGTERM);

	(void)msg_receive((msg_header_t *)&restart_msg, MSG_OPTION_NONE, 0);

	/*
	 * We only get here if the sighup handler sends a message
	 * to the restart_msg port.  We need to restart this way because
	 * restarting in the signal handler's context blocks that
	 * signal from ever getting recieved again.
	 */
	restart();

	[controller release];
	[rover release];
	exit(0);
}
