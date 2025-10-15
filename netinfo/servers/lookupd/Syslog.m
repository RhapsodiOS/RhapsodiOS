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
	Syslog.m
	
	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
 */

#import "Syslog.h"
#import <mach/cthreads.h>
#import <syslog.h>
#import <stdio.h>
#import "stringops.h"

#define QEMPTY 0
#define QDATA 1

#define forever for (;;)

@implementation Syslog

- (int)facilityForName:(char *)name
{
	if (name == NULL) return LOG_DAEMON;

	else if (!strcmp(name, "LOG_KERN")) return LOG_KERN;
	else if (!strcmp(name, "KERN")) return LOG_KERN;
	else if (!strcmp(name, "log_kern")) return LOG_KERN;
	else if (!strcmp(name, "kern")) return LOG_KERN;

	else if (!strcmp(name, "LOG_USER")) return LOG_USER;
	else if (!strcmp(name, "USER")) return LOG_USER;
	else if (!strcmp(name, "log_user")) return LOG_USER;
	else if (!strcmp(name, "user")) return LOG_USER;

	else if (!strcmp(name, "LOG_MAIL")) return LOG_MAIL;
	else if (!strcmp(name, "MAIL")) return LOG_MAIL;
	else if (!strcmp(name, "log_mail")) return LOG_MAIL;
	else if (!strcmp(name, "mail")) return LOG_MAIL;

	else if (!strcmp(name, "LOG_DAEMON")) return LOG_DAEMON;
	else if (!strcmp(name, "DAEMON")) return LOG_DAEMON;
	else if (!strcmp(name, "log_daemon")) return LOG_DAEMON;
	else if (!strcmp(name, "daemon")) return LOG_DAEMON;

	else if (!strcmp(name, "LOG_AUTH")) return LOG_AUTH;
	else if (!strcmp(name, "AUTH")) return LOG_AUTH;
	else if (!strcmp(name, "log_auth")) return LOG_AUTH;
	else if (!strcmp(name, "auth")) return LOG_AUTH;

	else if (!strcmp(name, "LOG_SYSLOG")) return LOG_SYSLOG;
	else if (!strcmp(name, "SYSLOG")) return LOG_SYSLOG;
	else if (!strcmp(name, "log_syslog")) return LOG_SYSLOG;
	else if (!strcmp(name, "syslog")) return LOG_SYSLOG;

	else if (!strcmp(name, "LOG_LPR")) return LOG_LPR;
	else if (!strcmp(name, "LPR")) return LOG_LPR;
	else if (!strcmp(name, "log_lpr")) return LOG_LPR;
	else if (!strcmp(name, "lpr")) return LOG_LPR;

	else if (!strcmp(name, "LOG_NEWS")) return LOG_NEWS;
	else if (!strcmp(name, "NEWS")) return LOG_NEWS;
	else if (!strcmp(name, "log_news")) return LOG_NEWS;
	else if (!strcmp(name, "news")) return LOG_NEWS;

	else if (!strcmp(name, "LOG_UUCP")) return LOG_UUCP;
	else if (!strcmp(name, "UUCP")) return LOG_UUCP;
	else if (!strcmp(name, "log_uucp")) return LOG_UUCP;
	else if (!strcmp(name, "uucp")) return LOG_UUCP;

	else if (!strcmp(name, "LOG_CRON")) return LOG_CRON;
	else if (!strcmp(name, "CRON")) return LOG_CRON;
	else if (!strcmp(name, "log_cron")) return LOG_CRON;
	else if (!strcmp(name, "cron")) return LOG_CRON;

	else if (!strcmp(name, "LOG_AUTHPRIV")) return LOG_AUTHPRIV;
	else if (!strcmp(name, "AUTHPRIV")) return LOG_AUTHPRIV;
	else if (!strcmp(name, "log_authpriv")) return LOG_AUTHPRIV;
	else if (!strcmp(name, "authpriv")) return LOG_AUTHPRIV;

	else if (!strcmp(name, "LOG_FTP")) return LOG_FTP;
	else if (!strcmp(name, "FTP")) return LOG_FTP;
	else if (!strcmp(name, "log_ftp")) return LOG_FTP;
	else if (!strcmp(name, "ftp")) return LOG_FTP;

	else if (!strcmp(name, "LOG_NETINFO")) return LOG_NETINFO;
	else if (!strcmp(name, "NETINFO")) return LOG_NETINFO;
	else if (!strcmp(name, "log_netinfo")) return LOG_NETINFO;
	else if (!strcmp(name, "netinfo")) return LOG_NETINFO;
	else if (!strcmp(name, "NetInfo")) return LOG_NETINFO;

	else if (!strcmp(name, "LOG_LOCAL0")) return LOG_LOCAL0;
	else if (!strcmp(name, "LOCAL0")) return LOG_LOCAL0;
	else if (!strcmp(name, "log_local0")) return LOG_LOCAL0;
	else if (!strcmp(name, "local0")) return LOG_LOCAL0;

	else if (!strcmp(name, "LOG_LOCAL1")) return LOG_LOCAL1;
	else if (!strcmp(name, "LOCAL1")) return LOG_LOCAL1;
	else if (!strcmp(name, "log_local1")) return LOG_LOCAL1;
	else if (!strcmp(name, "local1")) return LOG_LOCAL1;

	else if (!strcmp(name, "LOG_LOCAL2")) return LOG_LOCAL2;
	else if (!strcmp(name, "LOCAL2")) return LOG_LOCAL2;
	else if (!strcmp(name, "log_local2")) return LOG_LOCAL2;
	else if (!strcmp(name, "local2")) return LOG_LOCAL2;

	else if (!strcmp(name, "LOG_LOCAL3")) return LOG_LOCAL3;
	else if (!strcmp(name, "LOCAL3")) return LOG_LOCAL3;
	else if (!strcmp(name, "log_local3")) return LOG_LOCAL3;
	else if (!strcmp(name, "local3")) return LOG_LOCAL3;

	else if (!strcmp(name, "LOG_LOCAL4")) return LOG_LOCAL4;
	else if (!strcmp(name, "LOCAL4")) return LOG_LOCAL4;
	else if (!strcmp(name, "log_local4")) return LOG_LOCAL4;
	else if (!strcmp(name, "local4")) return LOG_LOCAL4;

	else if (!strcmp(name, "LOG_LOCAL5")) return LOG_LOCAL5;
	else if (!strcmp(name, "LOCAL5")) return LOG_LOCAL5;
	else if (!strcmp(name, "log_local5")) return LOG_LOCAL5;
	else if (!strcmp(name, "local5")) return LOG_LOCAL5;

	else if (!strcmp(name, "LOG_LOCAL6")) return LOG_LOCAL6;
	else if (!strcmp(name, "LOCAL6")) return LOG_LOCAL6;
	else if (!strcmp(name, "log_local6")) return LOG_LOCAL6;
	else if (!strcmp(name, "local6")) return LOG_LOCAL6;

	else if (!strcmp(name, "LOG_LOCAL7")) return LOG_LOCAL7;
	else if (!strcmp(name, "LOCAL7")) return LOG_LOCAL7;
	else if (!strcmp(name, "log_local7")) return LOG_LOCAL7;
	else if (!strcmp(name, "local7")) return LOG_LOCAL7;

	return LOG_DAEMON;
}

- (const char *)level:(int)n
{
	int i;

	i = priorityQueue[n];

	switch (i)
	{
		case LOG_EMERG: return("Emergency");
		case LOG_ALERT: return("Alert");
		case LOG_CRIT: return("Critical");
		case LOG_ERR: return("Error");
		case LOG_WARNING: return("Warning");
		case LOG_NOTICE: return("Notice");
		case LOG_INFO: return("Info");
		case LOG_DEBUG: return("Debug");
		default: return("Unknown");
	}
	return("Unknown");
}

- (NSConditionLock *)qLock
{
	return qLock;
}

- (FILE *)fp
{
	return fp;
}

- (char *)message:(int)n
{
	return messageQueue[n];
}

- (int)priority:(int)n
{
	return (int)priorityQueue[n];
}

- (int)queueSize
{
	return queueSize;
}

- (void)flushQueue
{
	freeList(messageQueue);
	messageQueue = NULL;
	freeString(priorityQueue);
	priorityQueue = NULL;
	queueSize = 0;
}

void logger(id sender)
{
	NSConditionLock *qLock;
	FILE *fp;
	int i, size, p;

	qLock = [sender qLock];

	forever
	{
		[qLock lockWhenCondition:QDATA];
		size = [sender queueSize];

		if (size < 0)
		{
			[qLock unlock];
			cthread_exit(0);
		}
		for (i = 0; i < size; i++)
		{
			p = [sender priority:i];
			syslog(p, [sender message:i]);

			fp = [sender fp];
			if (fp != NULL)
			{
				if (p < 0)
					fprintf(fp,"(Log) %s\n", [sender message:i]);
				else
					fprintf(fp,"(%s) %s\n",
						[sender level:i], [sender message:i]);

				fflush(fp);
			}
		}
		[sender flushQueue];
		[qLock unlockWithCondition:QEMPTY];
	}
}

- (Syslog *)initWithIdent:(char *)ident
	facility:(int)fac
	options:(int)opt
{
	return [self initWithIdent:ident facility:fac options:opt logFile:NULL];
}

- (Syslog *)initWithIdent:(char *)ident
	facility:(int)fac
	options:(int)opt
	logFile:(char *)fileName
{
	char str[256];

	messageQueue = NULL;
	priorityQueue = NULL;
	queueSize = 0;

	if (ident == NULL) logIdent = copyString("lookupd");
	else logIdent = copyString(ident);
	logOptions = opt;
	logFacility = fac;

	qLock = [[NSConditionLock alloc] init];
	if (fileName == NULL) fp = NULL;
	else fp = fopen(fileName, "a");
	openlog(logIdent, logOptions, logFacility);
	cthread_detach(cthread_fork((cthread_fn_t)logger, (any_t)self));

	if ((fileName != NULL) && (fp == NULL))
	{
		sprintf(str, "Can't write to file %s", fileName);
		[self syslogWarning:str];
	}

	return self;
}

- (void)setLogFile:(char *)fileName
{
	char str[256];

	[qLock lock];

	if (fp != NULL) fclose(fp);
	if (fileName == NULL) fp = NULL;
	else fp = fopen(fileName, "a");

	[qLock unlockWithCondition:QDATA];

	if ((fileName != NULL) && (fp == NULL))
	{
		sprintf(str, "Can't write to file %s", fileName);
		[self syslogWarning:str];
	}
}

- (void)setLogFacility:(char *)facilityName
{
	[qLock lock];

	if (logIdent == NULL) return;

	closelog();
	logFacility = [self facilityForName:facilityName];
	openlog(logIdent, logOptions, logFacility);

	[qLock unlockWithCondition:QDATA];
}

- (void)dealloc
{
	[qLock lock];
	freeList(messageQueue);
	messageQueue = NULL;
	freeString(priorityQueue);
	priorityQueue = NULL;
	queueSize = -1;
	[qLock unlockWithCondition:QDATA];
	cthread_yield();
	[qLock release];
	closelog();
	if (logIdent != NULL) freeString(logIdent);
	[super dealloc];
}

- (void)log:(char *)message priority:(int)pri
{
	[qLock lock];

	if (queueSize == 0)
	{
		priorityQueue = malloc(2);
	}
	else	
	{
		priorityQueue = realloc(priorityQueue, queueSize+2);
	}

	messageQueue = appendString(message, messageQueue);
	priorityQueue[queueSize] = (char)pri;

	queueSize++;
	priorityQueue[queueSize] = '\0';

	[qLock unlockWithCondition:QDATA];
}

- (void)syslogEmergency:(char *)message
{
	[self log:message priority:LOG_EMERG];
}

- (void)syslogAlert:(char *)message
{
	[self log:message priority:LOG_ALERT];
}

- (void)syslogCritical:(char *)message
{
	[self log:message priority:LOG_CRIT];
}

- (void)syslogError:(char *)message
{
	[self log:message priority:LOG_ERR];
}

- (void)syslogWarning:(char *)message
{
	[self log:message priority:LOG_WARNING];
}

- (void)syslogNotice:(char *)message
{
	[self log:message priority:LOG_NOTICE];
}

- (void)syslogInfo:(char *)message
{
	[self log:message priority:LOG_INFO];
}

- (void)syslogDebug:(char *)message
{
	[self log:message priority:LOG_DEBUG];
}

- (void)logMessage:(char *)message
{
	[self log:message priority:-1];
}

@end
