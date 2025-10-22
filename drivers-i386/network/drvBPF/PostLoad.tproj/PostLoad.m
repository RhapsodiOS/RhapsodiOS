/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * PostLoad.m
 * Berkeley Packet Filter (BPF) PostLoad utility
 *
 * Creates device nodes for BPF devices (/dev/bpf0, /dev/bpf1, etc.)
 */

#import <streams/streams.h>
#import <driverkit/IODeviceMaster.h>
#import <driverkit/IODevice.h>
#import <errno.h>
#import <libc.h>
#import <sys/stat.h>

#define DEV_STRING "/dev/"
#define BPF_INIT_ERR_STRING "Error initializing BPF driver"

int main(int argc, char **argv)
{
    IOReturn ret;
    IOObjectNumber tag;
    IOString kind;
    IODeviceMaster *devMaster;
    int bpfValues[2];  /* [0] = major number, [1] = number of devices */
    unsigned int count;
    unsigned int i;
    int iRet;
    char path[10];

    iRet = 0;
    count = 2;  /* Expect 2 values: major number and device count */

    devMaster = [IODeviceMaster new];

    /*
     * Look up the BPF driver
     */
    ret = [devMaster lookUpByDeviceName:"bpf"
        objectNumber:&tag
        deviceKind:&kind];

    if (ret != IO_R_SUCCESS) {
        printf("%s: couldn't find driver. Returned %d\n",
               BPF_INIT_ERR_STRING, ret);
        return -1;
    }

    /*
     * Query the BPF driver for major number and device count
     */
    ret = [devMaster getIntValues:bpfValues
           forParameter:"BpfMajorMinor"
           objectNumber:tag
           count:&count];

    if (ret != IO_R_SUCCESS) {
        printf("%s: couldn't get major number:  Returned %d.\n",
               BPF_INIT_ERR_STRING, ret);
        return -1;
    }

    /*
     * Create device nodes for all BPF devices
     */
    for (i = 0; i < bpfValues[1]; i++) {
        bzero(path, sizeof(path));
        sprintf(path, "%s%s%d", DEV_STRING, "bpf", i);

        if (unlink(path) != 0) {
            if (errno != ENOENT) {
                printf("%s: could not delete old %s.  Errno is %d\n",
                       BPF_INIT_ERR_STRING, path, errno);
                iRet = -1;
            }
        }

        if (ret == IO_R_SUCCESS) {
            umask(0);
            if (mknod(path, 0x2180, (bpfValues[0] << 8) | i) != 0) {
                printf("%s: could not create %s.  Errno is %d\n",
                       BPF_INIT_ERR_STRING, path, errno);
                iRet = -1;
            }
        }
    }

    return iRet;
}
