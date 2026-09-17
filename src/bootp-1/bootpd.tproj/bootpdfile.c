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
 * bootpdfile.c
 * - read bootptab to get the default boot file and path
 * - parse the list of hardware address to ip bindings
 * - lookup host entries in the file-based host list
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
#import <mach/boolean.h>
#import <signal.h>
#import <stdio.h>
#import <string.h>
#import <errno.h>
#import <ctype.h>
#import <netdb.h>
#import <setjmp.h>
#import <syslog.h>
#import <arpa/inet.h>
#import <sys/uio.h>
#import <unistd.h>
#import <stdlib.h>
#import <sys/types.h>
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
#import <stdio.h>
#import <mach/boolean.h>
#import <syslog.h>
#import <string.h>
#import <arpa/inet.h>
#import <sys/uio.h>

#import "bootpdfile.h"
#import "hostlist.h"

#define HTYPE_ETHER		1
#define NUM_EN_ADDR_BYTES	6

#define HOSTNAME_MAX		64
#define BOOTFILE_MAX		128

/* globals: */
char		boot_home_dir[128];/* bootfile directory */
char		boot_tftp_dir[128];/* bootfile directory given to tftpd */
char		boot_default_file[64];/* default file to boot */

static FILE *	fp = NULL;
static char *	bootptab = "/etc/bootptab";
static long	modtime = 0;	/* last modification time of bootptab */
static char	line[256];	/* line buffer for reading bootptab */
static char *	linep;		/* pointer to 'line' */
static int	linenum;	/* current line number in bootptab */

static 
struct hosts * 	S_file_hosts = NULL; /* list of host entries from the file */

/*
 * Get next field from 'line' buffer into 'str'.  'linep' is the 
 * pointer to current position.
 */
static void
S_getfield(str, len)
	char *str;
{
	register char *cp = str;

	for ( ; *linep && (*linep == ' ' || *linep == '\t') ; linep++)
		;	/* skip spaces/tabs */
	if (*linep == 0) {
		*cp = 0;
		return;
	}
	len--;	/* save a spot for a null */
	for ( ; *linep && *linep != ' ' & *linep != '\t' ; linep++) {
		*cp++ = *linep;
		if (--len <= 0) {
			*cp = 0;
			syslog(LOG_INFO, "string truncated: %s,"
			       " on line %d of bootptab", str, linenum);
			return;
		}
	}
	*cp = 0;
}

/*
 * Read bootptab database file.  Avoid rereading the file if the
 * write date hasnt changed since the last time we read it.
 */
void
bootp_readtab()
{
    struct stat st;
    register char *cp;
    register i;
    char temp[64], tempcpy[64];
    register struct hosts *hp, *thp;
    int skiptopercent;
    
    if (fp == NULL) {
	if ((fp = fopen(bootptab, "r")) == NULL) {
	    syslog(LOG_INFO, "can't open %s", bootptab);
	    exit(1);
	}
    }
    if (fstat(fileno(fp), &st) == 0 
	&& st.st_mtime == modtime 
	&& st.st_nlink)
	return;	/* hasnt been modified or deleted yet */

    fclose(fp);

    if ((fp = fopen(bootptab, "r")) == NULL) {
	syslog(LOG_INFO, "can't open %s", bootptab);
	exit(1);
    }
    fstat(fileno(fp), &st);
    syslog(LOG_INFO, "re-reading %s", bootptab);
    modtime = st.st_mtime;
    boot_tftp_dir[0] = boot_home_dir[0] = boot_default_file[0] = 0;
    linenum = 0;
    skiptopercent = 1;
    
    /*
     * Free old file entries.
     */
    hp = S_file_hosts;
    while (hp) {
	thp = hp->next;
	hostfree(&S_file_hosts, hp);
	hp = thp;
    }
    
    /*
     * read and parse each line in the file.
     */
    for (;;) {
	char hostname[HOSTNAME_MAX];
	char bootfile[BOOTFILE_MAX];
	struct in_addr iaddr;
	int htype;
	int hlen;
	char haddr[32];
	
	if (fgets(line, sizeof line, fp) == NULL)
	    break;	/* done */

	if ((i = strlen(line)))
	    line[i-1] = 0;	/* remove trailing newline */

	linep = line;
	linenum++;
	if (line[0] == '#' || line[0] == 0 || line[0] == ' ')
	    continue;	/* skip comment lines */

	/* fill in fixed leading fields */
	if (boot_home_dir[0] == 0) {
	    S_getfield(boot_home_dir, sizeof boot_home_dir);
	    if (cp = (char *) index(boot_home_dir, ':')) {
		*cp++ = '\0';
		strcpy(boot_tftp_dir, cp);
	    }
	    continue;
	}
	if (boot_default_file[0] == 0) {
	    S_getfield(boot_default_file, sizeof boot_default_file);
	    continue;
	}
	if (skiptopercent) {	/* allow for future leading fields */
	    if (line[0] != '%')
		continue;
	    skiptopercent = 0;
	    continue;
	}
	/* fill in host table */
	S_getfield(hostname, sizeof(hostname) - 1);
	S_getfield(temp, sizeof temp);
	sscanf(temp, "%d", &htype);
	S_getfield(temp, sizeof temp);
	strcpy(tempcpy, temp);
	cp = tempcpy;
	/* parse hardware address */
	for (hlen = 0; hlen < sizeof(haddr);) {
	    char *cpold;
	    char c;
	    int v;

	    cpold = cp;
	    while (*cp != '.' && *cp != ':' && *cp != 0)
		cp++;
	    c = *cp;	/* save original terminator */
	    *cp = 0;
	    cp++;
	    if (sscanf(cpold, "%x", &v) != 1)
		goto badhex;
	    haddr[hlen++] = v;
	    if (c == 0)
		break;
	}
	if (htype == HTYPE_ETHER && hlen != NUM_EN_ADDR_BYTES) {
	  badhex:	
	    syslog(LOG_INFO, "bad hex address: %s,"
		   " at line %d of bootptab", temp, linenum);
	    continue;
	}
	S_getfield(temp, sizeof(temp));
	iaddr.s_addr = inet_addr(temp);
	if (iaddr.s_addr == -1 || iaddr.s_addr == 0) {
	    syslog(LOG_INFO, "bad internet address: %s,"
		   " at line %d of bootptab", temp, linenum);
	    continue;
	}
	S_getfield(bootfile, sizeof(bootfile) - 1);
	(void)hostadd(&S_file_hosts, NULL, htype, haddr, hlen, &iaddr,
		      hostname, bootfile);
    }
}

boolean_t
bootp_getbyhw_file(u_char hwtype, void * hwaddr, int hwlen, 
		   struct in_addr * iaddr_p, 
		   u_char * * hostname_p, u_char * * bootfile_p)
{
    struct hosts * hp;

    hp = hostbyaddr(S_file_hosts, hwtype, hwaddr, hwlen);
    if (hp == NULL)
	return (FALSE);
    if (hostname_p)
	*hostname_p = strdup(hp->host);
    if (bootfile_p)
	*bootfile_p = strdup(hp->bootfile);
    *iaddr_p = hp->iaddr;
    return (TRUE);
}

boolean_t
bootp_getbyip_file(struct in_addr ciaddr, u_char * * hostname_p, 
		   u_char * * bootfile_p)
{
    struct hosts * hp;

    hp = hostbyip(S_file_hosts, ciaddr);
    if (hp == NULL)
	return (FALSE);

    if (hostname_p)
	*hostname_p = strdup(hp->host);
    if (bootfile_p)
	*bootfile_p = strdup(hp->bootfile);
    return (TRUE);
}

