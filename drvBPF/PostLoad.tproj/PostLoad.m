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

#define PATH_NAME_SIZE 32
#define DEV_STRING "/dev/"
#define BPF_INIT_ERR_STRING "Error initializing BPF driver"

#define DEV_MOD_CHAR 020640
#define DEV_UMASK 0

/* Default number of BPF devices */
#define DEFAULT_BPF_DEVICES 16
#define MAX_BPF_DEVICES 256

static int makeNode(char *deviceName, int deviceNum, int major, unsigned short mode);

int main(int argc, char **argv)
{
    IOReturn ret;
    IOObjectNumber tag;
    IOString kind;
    unsigned int count;
    IODeviceMaster *devMaster;
    int characterMajor;
    int i, iRet;
    int numBPFDevices = DEFAULT_BPF_DEVICES;
    char path[PATH_NAME_SIZE];

    iRet = 0;

    devMaster = [IODeviceMaster new];

    /*
     * Look up the BPF kernel server to get configuration
     */
    bzero(path, PATH_NAME_SIZE);
    sprintf(path, "BPFKernelServer");

    ret = [devMaster lookUpByDeviceName:path
        objectNumber:&tag
        deviceKind:&kind];

    if (ret == IO_R_SUCCESS) {
        /*
         * Query the BPF kernel server for the number of devices
         */
        ret = [devMaster getIntValues:&numBPFDevices
               forParameter:"BPF Devices" objectNumber:tag
               count:&count];
        if (ret != IO_R_SUCCESS) {
            /* Use default if we can't get the parameter */
            numBPFDevices = DEFAULT_BPF_DEVICES;
        }

        /* Sanity check */
        if (numBPFDevices < 1) {
            numBPFDevices = 1;
        } else if (numBPFDevices > MAX_BPF_DEVICES) {
            numBPFDevices = MAX_BPF_DEVICES;
        }

        /*
         * Query the object for its character major device number
         */
        characterMajor = -1;
        ret = [devMaster getIntValues:&characterMajor
               forParameter:"CharacterMajor" objectNumber:tag
               count:&count];
        if (ret != IO_R_SUCCESS) {
            printf("%s: couldn't get char major number: Returned %d.\n",
                   BPF_INIT_ERR_STRING, ret);
            exit(-1);
        }

        /*
         * Create device nodes for all BPF devices
         */
        for (i = 0; i < numBPFDevices; i++) {
            iRet = makeNode("bpf", i, characterMajor, DEV_MOD_CHAR);
            if (iRet != 0) {
                printf("%s: Failed to create /dev/bpf%d\n",
                       BPF_INIT_ERR_STRING, i);
            }
        }

        printf("BPF PostLoad: Created %d BPF device node%s\n",
               numBPFDevices, (numBPFDevices == 1) ? "" : "s");
    } else {
        printf("%s: BPF kernel server not found (ret = %d)\n",
               BPF_INIT_ERR_STRING, ret);
        iRet = -1;
    }

    exit(iRet);
}

static int makeNode(char *deviceName, int deviceNum, int major, unsigned short mode)
{
    int iRet;
    char path[PATH_NAME_SIZE];

    iRet = 0;

    bzero(path, PATH_NAME_SIZE);
    sprintf(path, "%s%s%d", DEV_STRING, deviceName, deviceNum);

    if (unlink(path)) {
        if (errno != ENOENT) {
            printf("%s: could not delete old %s. Errno is %d\n",
                BPF_INIT_ERR_STRING, path, errno);
            /* Don't fail, try to create anyway */
        }
    }

    umask(DEV_UMASK);
    if (mknod(path, mode, (major << 8) | deviceNum)) {
        printf("%s: could not create %s. Errno is %d\n",
            BPF_INIT_ERR_STRING, path, errno);
        iRet = -1;
    }

    return iRet;
}
