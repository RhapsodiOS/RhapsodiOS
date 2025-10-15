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
 * bscfgTest.c
 * - test harness for boot server configuration API
 */
#import "bscfg.h"
#import <arpa/inet.h>
#import <unistd.h>
#import <stdlib.h>
#import <stdio.h>
#import <sys/errno.h>
#import <string.h>

static char * progname = NULL;

#if 0
static void
print_ranges(ip_range_t * range, int count)
{
    int i;

    printf("%d ranges:\n", count);
    for (i = 0; i < count; i++) {
	printf(inet_ntoa(range[i].start));
	printf("..%s\n", inet_ntoa(range[i].end));
    }
    return;
}
#endif

void
usage()
{
    fprintf(stderr, "usage: %s filename\n", progname);
    exit(2);
}

static char buf[2048];

int
getFileList(char * filename, ip_range_t * * ranges_p, int * count_p)
{
    FILE * 		f;
    int			line_count;
    int			item_count = 0;
    int			array_size;
    ip_range_t *	ranges;
    int			ret = 0;

    f = fopen(filename, "r");
    if (f == NULL) {
	fprintf(stderr, "%s: couldn't open file '%s' for reading\n", progname, filename);
	return (-1);
    }
    array_size = 100;
    ranges = (ip_range_t *)malloc(array_size * sizeof(*ranges));
    if (ranges == 0) {
	fprintf(stderr, "%s: couldn't allocate memory", progname);
	return (-1);
    }
    line_count = 0;
    item_count = 0;
    while (1) {
	struct in_addr iaddr;

	if (fgets(buf, sizeof(buf), f) == NULL) {
	    if (line_count & 0x1) {
		fprintf(stderr, "%s: file contains odd number of lines\n", progname);
		ret = -1;
	    }
	    break;
	}
	line_count++;
	iaddr.s_addr = inet_addr(buf);
	if (iaddr.s_addr == -1) {
	    fprintf(stderr, "%s: bad ip address at line %d\n", progname, line_count);
	    ret = -1;
	    break;
	}
	if (item_count >= array_size) {
	    array_size *= 2;
	    ranges = (ip_range_t *)realloc(ranges, array_size * sizeof(*ranges));
	    if (ranges == 0) {
		fprintf(stderr, "%s: couldn't allocate memory", progname);
		ret = -1;
		break;
	    }
	}
	if (line_count & 0x1)
	    ranges[item_count].start = iaddr;
	else {
	    ranges[item_count].end = iaddr;
	    item_count++;
	}
    }
    *ranges_p = ranges;
    *count_p = item_count;
    fclose(f);
    return (ret);
}

int
main(int argc, char * argv[])
{
    bscfgRef_t ref;
    int count;
    ip_range_t * list;
    int ret;

    progname = argv[0];

    if (argc != 2)
	usage();
    if (getFileList(argv[1], &list, &count) != 0)
	exit(2);
//  print_ranges(list, count);

    ret = bscfgOpen(&ref);
    if (ret != BSCFG_SUCCESS) {
	printf("%s: couldn't open boot server configuration: %s\n", progname,
	       bscfgErrorString(ret));
	exit(1);
    }
    if ((ret = bscfgSetIPRanges(ref, list, count)) != BSCFG_SUCCESS) {
	printf("%s: couldn't set ipranges: %s\n", progname, 
	       bscfgErrorString(ret));
	exit(1);
    }
    free(list);
    bscfgClose(ref);
    exit(0);
}
