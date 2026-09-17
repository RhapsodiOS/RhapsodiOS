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

static void 
S_set_fail_test(bscfgRef_t * ref, ip_range_t * ranges, int count,
		u_char * testname)
{
    static int testnum = 0;
    int ret;

    testnum++;
    printf("test %d (%s): ", testnum, testname);
    print_ranges(ranges, count);
    if ((ret = bscfgSetIPRanges(ref, ranges, count)) != BSCFG_SUCCESS) {
	printf("SUCCESS: bscfgSetIPRanges failed as expected: %s\n-----\n", 
	       bscfgErrorString(ret));
	    
    }
    else
	printf("ERROR: test '%s' succeeded unexpectedly\n-------\n", testname);
    return;
}

int
main()
{
    bscfgRef_t ref;
    int count;
    ip_range_t * list;
    int ret;

    ret = bscfgOpen(&ref);
    if (ret != BSCFG_SUCCESS) {
	printf("open failed: %s\n", bscfgErrorString(ret));
	exit(1);
    }
    {
	ip_range_t ranges[1] = { 
	    { { inet_addr("14.3.3.100") }, { inet_addr("14.3.3.1") } },
	};
	S_set_fail_test(ref, ranges, 1, "range invalid");
    }
    {
	ip_range_t ranges[1] = {
	    { { inet_addr("15.3.3.1") }, { inet_addr("15.3.3.100") } },
	};
	S_set_fail_test(ref, ranges, 1, "no interface for range");
    }
    {
	ip_range_t ranges[1] = {
	    { { inet_addr("14.3.3.1") }, { inet_addr("15.3.3.100") } },
	};
	S_set_fail_test(ref, ranges, 1, "range spans subnets");
    }
    {
	ip_range_t ranges[3] = {
	    { { inet_addr("14.3.3.1") }, { inet_addr("14.3.3.100") } },
	    { { inet_addr("17.202.40.1") }, { inet_addr("17.202.43.254") } },
	    { { inet_addr("17.202.42.1") }, { inet_addr("17.202.42.100") } },
	};
	S_set_fail_test(ref, ranges, 3, "ranges overlap");
    }

    if (bscfgGetIPRanges(ref, &list, &count) != BSCFG_SUCCESS) {
	printf("get ipranges failed\n");
	exit(1);
    }
    print_ranges(list, count);
    if ((ret = bscfgSetIPRanges(ref, list, count)) != BSCFG_SUCCESS) {
	printf("set ipranges failed: %s\n", bscfgErrorString(ret));
	exit(1);
    }

    bscfgFreeIPRanges(&list);
    bscfgClose(ref);
#if 0
    {
	ip_range_t ranges[2] = {
	    { { inet_addr("14.3.3.1") }, { inet_addr("14.3.3.100") } },
	    { { inet_addr("17.202.40.10") }, { inet_addr("17.202.43.254") } },
	};
	if ((ret = bscfgSetIPRanges(ref, ranges, 2)) != BSCFG_SUCCESS) {
	    printf("set ipranges failed: %s\n", bscfgErrorString(ret));
	    exit(1);
	}
    }
#endif

    exit(0);
}
