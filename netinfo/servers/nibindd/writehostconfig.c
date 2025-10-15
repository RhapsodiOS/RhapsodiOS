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
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <rpcsvc/ypclnt.h>

#define HOSTCONFIG "/etc/hostconfig"
#define COPYHOSTCONFIG "/etc/copy_of_hostconfig"

enum config_type
{
	CONFIG_NOVALUE = 0,
	CONFIG_VALUE = 1,
	CONFIG_AUTOMATIC = 2,
	CONFIG_YES = 3,
	CONFIG_NO = 4,
	CONFIG_ROUTED = 5
};
typedef enum config_type config_type;

struct hostconfig
{
	config_type config_name;
	char *name;

	config_type config_router;
	struct in_addr router;

	config_type config_nisdomain;
	char *nisdomain;

	config_type config_configserver;
	config_type config_timesync;
};
typedef struct hostconfig hostconfig;

static void
init_hostconfig(hostconfig *h)
{
	h->config_name = CONFIG_NOVALUE;
	h->name = NULL;

	h->config_router = CONFIG_NOVALUE;
	h->router.s_addr = 0;

	h->config_nisdomain = CONFIG_NOVALUE;
	h->nisdomain = NULL;

	h->config_configserver = CONFIG_NOVALUE;
	h->config_timesync = CONFIG_NOVALUE;
}

static void
free_hostconfig(hostconfig *h)
{
	if (h->name != NULL) free(h->name);
	if (h->nisdomain != NULL) free (h->nisdomain);
}

static void
_setcharval(config_type *t, char **v, char *line)
{
	if (line == NULL) return;
	if (line[0] == '\0')
	{
		*t = CONFIG_NOVALUE;
		if (*v != NULL)
		{
			free(*v);
			*v = NULL;
		}
		return;
	}

	if (!strncmp(line, "-AUTOMATIC-", 11)) *t = CONFIG_AUTOMATIC;
	else if (!strncmp(line, "-YES-", 5)) *t = CONFIG_YES;
	else if (!strncmp(line, "-NO-", 4)) *t = CONFIG_NO;
	else if (!strncmp(line, "-ROUTED-", 8)) *t = CONFIG_ROUTED;
	else
	{
		*t = CONFIG_VALUE;
		*v = malloc(strlen(line) + 1);
		strcpy(*v, line);
	}
}

static void
_setaddrval(config_type *t, struct in_addr *v, char *line)
{
	if (line == NULL) return;
	if (line[0] == '\0')
	{
		*t = CONFIG_NOVALUE;
		v->s_addr = 0;
		return;
	}

	if (!strncmp(line, "-AUTOMATIC-", 11)) *t = CONFIG_AUTOMATIC;
	else if (!strncmp(line, "-YES-", 5)) *t = CONFIG_YES;
	else if (!strncmp(line, "-NO-", 4)) *t = CONFIG_NO;
	else if (!strncmp(line, "-ROUTED-", 8)) *t = CONFIG_ROUTED;
	else
	{
		*t = CONFIG_VALUE;
		v->s_addr = inet_addr(line);
	}
}

static void
_setval(config_type *t, char *line)
{
	if (line == NULL) return;
	if (line[0] == '\0') *t = CONFIG_NOVALUE;
	else if (!strncmp(line, "-AUTOMATIC-", 11)) *t = CONFIG_AUTOMATIC;
	else if (!strncmp(line, "-YES-", 5)) *t = CONFIG_YES;
	else if (!strncmp(line, "-NO-", 4)) *t = CONFIG_NO;
	else if (!strncmp(line, "-ROUTED-", 8)) *t = CONFIG_ROUTED;
}

static int
fread_hostconfig(FILE *f, hostconfig *h)
{
	char line[1024];

	if (f == NULL) return -1;

	while (NULL != fgets(line, 1024, f))
	{
		if (line[0] == '#') continue;
		line[strlen(line) - 1] = '\0';
		if (!strncmp(line, "HOSTNAME=", 9))
			_setcharval(&h->config_name, &h->name, line+9);
		else if (!strncmp(line, "ROUTER=", 7))
			_setaddrval(&h->config_router, &h->router, line+7);
		else if (!strncmp(line, "NISDOMAIN=", 10))
			_setcharval(&h->config_nisdomain, &h->nisdomain, line+10);
		else if (!strncmp(line, "CONFIGSERVER=", 13))
			_setval(&h->config_configserver, line+13);
		else if (!strncmp(line, "TIMESYNC=", 9))
			_setval(&h->config_timesync, line+9);
	}

	if (!((h->config_name == CONFIG_NOVALUE) ||
		(h->config_name == CONFIG_AUTOMATIC) ||
		(h->config_name == CONFIG_VALUE)))
	{
		_setcharval(&h->config_name, &h->name, "");	
	}

	if (!((h->config_router == CONFIG_NOVALUE) ||
		(h->config_router == CONFIG_NO) ||
		(h->config_router == CONFIG_ROUTED) ||
		(h->config_router == CONFIG_AUTOMATIC) ||
		(h->config_router == CONFIG_VALUE)))
	{
		_setaddrval(&h->config_router, &h->router, "");
	}

	if (!((h->config_nisdomain == CONFIG_NOVALUE) ||
		(h->config_nisdomain == CONFIG_NO) ||
		(h->config_nisdomain == CONFIG_VALUE)))
	{
		_setcharval(&h->config_nisdomain, &h->nisdomain, "");	
	}

	if (!((h->config_configserver == CONFIG_NOVALUE) ||
		(h->config_configserver == CONFIG_NO) ||
		(h->config_configserver == CONFIG_YES)))
	{
		h->config_configserver = CONFIG_NOVALUE;
	}

	if (!((h->config_timesync == CONFIG_NOVALUE) ||
		(h->config_timesync == CONFIG_AUTOMATIC) ||
		(h->config_timesync == CONFIG_NO)))
	{
		h->config_timesync = CONFIG_NOVALUE;
	}

	return 0;
}

static void
_fputcharval(FILE *f, config_type t, char *v)
{
	switch (t)
	{
		case CONFIG_AUTOMATIC: fprintf(f, "-AUTOMATIC-"); break;
		case CONFIG_YES: fprintf(f, "-YES-"); break;
		case CONFIG_NO: fprintf(f, "-NO-"); break;
		case CONFIG_ROUTED: fprintf(f, "-ROUTED-"); break;
		case CONFIG_VALUE: fprintf(f, "%s", v); break;
		case CONFIG_NOVALUE: break;
	}
}
	
static void
_fputaddrval(FILE *f, config_type t, struct in_addr v)
{
	switch (t)
	{
		case CONFIG_AUTOMATIC: fprintf(f, "-AUTOMATIC-"); break;
		case CONFIG_YES: fprintf(f, "-YES-"); break;
		case CONFIG_NO: fprintf(f, "-NO-"); break;
		case CONFIG_ROUTED: fprintf(f, "-ROUTED-"); break;
		case CONFIG_VALUE: fprintf(f, "%s", inet_ntoa(v)); break;
		case CONFIG_NOVALUE: break;
	}
}
	
static void
_fputval(FILE *f, config_type t)
{
	switch (t)
	{
		case CONFIG_AUTOMATIC: fprintf(f, "-AUTOMATIC-"); break;
		case CONFIG_YES: fprintf(f, "-YES-"); break;
		case CONFIG_NO: fprintf(f, "-NO-"); break;
		case CONFIG_ROUTED: fprintf(f, "-ROUTED-"); break;
		case CONFIG_NOVALUE: break;
		case CONFIG_VALUE: break;
	}
}
	
static void
merge_hostconfig(FILE *src, FILE *dst, hostconfig *h)
{
	char line[1024];
	int p_name = 0;
	int p_router = 0;
	int p_nisdomain = 0;
	int p_configserver = 0;
	int p_timesync = 0;

	if (src == NULL) return;
	if (dst == NULL) return;

	while (NULL != fgets(line, 1024, src))
	{
		line[strlen(line) - 1] = '\0';

		if (!strncmp(line, "HOSTNAME=", 9))
		{
			if (p_name == 1) continue;
			fprintf(dst, "HOSTNAME=");
			_fputcharval(dst, h->config_name, h->name);
			fprintf(dst, "\n");
			p_name = 1;
		}
		else if (!strncmp(line, "ROUTER=", 7))
		{
			if (p_router == 1) continue;
			fprintf(dst, "ROUTER=");
			_fputaddrval(dst, h->config_router, h->router);
			fprintf(dst, "\n");
			p_router = 1;
		}
		else if (!strncmp(line, "NISDOMAIN=", 9))
		{
			if (p_nisdomain == 1) continue;
			fprintf(dst, "NISDOMAIN=");
			_fputcharval(dst, h->config_nisdomain, h->nisdomain);
			fprintf(dst, "\n");
			p_nisdomain = 1;
		}
		else if (!strncmp(line, "CONFIGSERVER=", 10))
		{
			if (p_configserver == 1) continue;
			fprintf(dst, "CONFIGSERVER=");
			_fputval(dst, h->config_configserver);
			fprintf(dst, "\n");
			p_configserver = 1;
		}
		else if (!strncmp(line, "TIMESYNC=", 5))
		{
			if (p_timesync == 1) continue;
			fprintf(dst, "TIMESYNC=");
			_fputval(dst, h->config_timesync);
			fprintf(dst, "\n");
			p_timesync = 1;
		}
		else fprintf(dst, "%s\n", line);
	}

	if (p_name == 0) 
	{
		fprintf(dst, "HOSTNAME=");
		_fputcharval(dst, h->config_name, h->name);
		fprintf(dst, "\n");
	}

	if (p_router == 0)
	{
		fprintf(dst, "ROUTER=");
		_fputaddrval(dst, h->config_router, h->router);
		fprintf(dst, "\n");
	}

	if (p_nisdomain == 0)
	{
		fprintf(dst, "NISDOMAIN=");
		_fputcharval(dst, h->config_nisdomain, h->nisdomain);
		fprintf(dst, "\n");
	}

	if (p_configserver == 0)
	{
		fprintf(dst, "CONFIGSERVER=");
		_fputval(dst, h->config_configserver);
		fprintf(dst, "\n");
	}

	if (p_timesync == 0)
	{
		fprintf(dst, "TIMESYNC=");
		_fputval(dst, h->config_timesync);
		fprintf(dst, "\n");
	}
}

void
writehostconfig(void)
{
	FILE *fp, *cp;
	char str[1024], copyname[64], *domain;
	hostconfig h;

	fp = fopen(HOSTCONFIG, "r+");
	if (fp == NULL) return;

	sprintf(copyname, "%s.%d", COPYHOSTCONFIG, getpid());
	cp = fopen(copyname, "w");
	if (cp == NULL) return;

	init_hostconfig(&h);
	fread_hostconfig(fp, &h);

	gethostname(str, 1024);
	h.config_name = CONFIG_VALUE;
	if (h.name != NULL) free(h.name);
	if (!strcmp(str, "localhost")) strcpy(str, "-AUTOMATIC-");
	h.name = malloc(strlen(str) + 1);
	strcpy(h.name, str);

	if ((h.config_router == CONFIG_NOVALUE) ||
		(h.config_router == CONFIG_NO) ||
		(h.config_router == CONFIG_YES) ||
		(h.config_router == CONFIG_ROUTED))
	{
		h.config_router = CONFIG_ROUTED;
	}

//	yp_get_default_domain(&domain);
	domain = NULL;
	if (domain != NULL)
	{
		h.config_nisdomain = CONFIG_VALUE;
		if (h.nisdomain != NULL) free(h.nisdomain);
		h.nisdomain = malloc(strlen(domain) + 1);
		strcpy(h.nisdomain, domain);
	}

	if (h.config_nisdomain != CONFIG_VALUE)
	{
		h.config_nisdomain = CONFIG_NO;
		if (h.nisdomain != NULL) free(h.nisdomain);
	}

	if ((h.config_configserver == CONFIG_NOVALUE) ||
		(h.config_configserver == CONFIG_NO) ||
		(h.config_configserver == CONFIG_VALUE) ||
		(h.config_configserver == CONFIG_ROUTED) ||
		(h.config_configserver == CONFIG_AUTOMATIC))
	{
		h.config_configserver = CONFIG_NO;
	}
	else h.config_configserver = CONFIG_YES;

	if ((h.config_timesync == CONFIG_NOVALUE) ||
		(h.config_timesync == CONFIG_NO) ||
		(h.config_timesync == CONFIG_VALUE) ||
		(h.config_timesync == CONFIG_ROUTED))
	{
		h.config_timesync = CONFIG_NO;
	}
	else h.config_timesync = CONFIG_YES;

	fseek(fp, 0, SEEK_SET);
	merge_hostconfig(fp, cp, &h);

	free_hostconfig(&h);
	fclose(fp);
	fclose(cp);

	rename(copyname, HOSTCONFIG);
}
