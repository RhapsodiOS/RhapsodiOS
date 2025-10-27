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
 * PnPDump
 * Plug and Play Device Dump Utility
 *
 * This tool enumerates and displays Plug and Play device configurations
 * for EISA and ISA PnP devices by communicating with the EISA driver.
 */

#import <objc/objc.h>
#import <objc/Object.h>
#import <driverkit/IODevice.h>
#import <driverkit/IODeviceMaster.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

/* Buffer sizes */
#define CMD_BUFFER_SIZE 512
#define VALUE_BUFFER_SIZE 512
#define MAX_CSN 255
#define MAX_LOGICAL_DEVICES 10

/* Global variables */
static const char *progname;
static char cmdBuffer[CMD_BUFFER_SIZE];
static char valueBuffer[VALUE_BUFFER_SIZE];

/*
 * Display usage information and exit
 */
static void usage(void)
{
    fprintf(stderr, "Usage: %s [-c] [-d]\n", progname);
    fprintf(stderr, "\n");
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -c    Show device configurations (resource descriptions)\n");
    fprintf(stderr, "  -d    Show device current settings (logical device configs)\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "If no options are specified, both -c and -d are assumed.\n");
    fprintf(stderr, "\n");
    exit(1);
}

/*
 * Display error message and exit
 */
static void bail(const char *message, IOReturn status)
{
    fprintf(stderr, "%s: %s", progname, message);
    if (status != 0) {
        fprintf(stderr, " (error code: 0x%x)", status);
    }
    fprintf(stderr, "\n");
    exit(1);
}

/*
 * Dump PnP device information for a specific CSN
 * Returns the number of logical devices found, or -1 if no device at this CSN
 */
static int dumpDeviceInfo(id deviceMaster, int objectNumber, int csn)
{
    IOReturn status;
    unsigned int bufferLength;
    id deviceResources;
    id deviceList;
    int deviceCount;

    /* Build command string to get PnP info */
    snprintf(cmdBuffer, CMD_BUFFER_SIZE, "GetPnPInfo( %d", csn);

    /* Get device resource description from driver */
    bufferLength = VALUE_BUFFER_SIZE;
    status = [deviceMaster getCharValues:valueBuffer
                            forParameter:cmdBuffer
                            objectNumber:objectNumber
                            count:&bufferLength];

    if (status != IO_R_SUCCESS) {
        return -1;  /* No device at this CSN */
    }

    /* Display device header */
    printf("\n");
    printf("=========================================================\n");
    printf("csn %d:\n", csn);
    printf("=====================\n");
    printf("Resource Description:\n");
    printf("=====================\n");

    /* Create PnPDeviceResources object from buffer */
    deviceResources = [[objc_getClass("PnPDeviceResources") alloc]
                       initFromBuffer:valueBuffer Length:bufferLength CSN:csn];

    /* Get device list */
    deviceList = [deviceResources deviceList];
    if (deviceList == nil) {
        fprintf(stderr, "Failed to get device list\n");
        exit(1);
    }

    /* Get device count and print resources */
    deviceCount = [deviceList count];
    [deviceResources print];

    /* Free device resources object */
    [deviceResources free];

    return deviceCount;
}

/*
 * Dump current configuration for logical devices
 */
static void dumpLogicalDeviceConfigs(id deviceMaster, int objectNumber, int csn, int deviceCount)
{
    IOReturn status;
    unsigned int bufferLength;
    id resources;
    int logicalDevice;

    /* Iterate through logical devices */
    for (logicalDevice = 0; logicalDevice < deviceCount; logicalDevice++) {
        /* Build command string to get device configuration */
        snprintf(cmdBuffer, CMD_BUFFER_SIZE, "GetPnPDeviceCfg( %d %d", csn, logicalDevice);

        /* Get current configuration from driver */
        bufferLength = VALUE_BUFFER_SIZE;
        status = [deviceMaster getCharValues:valueBuffer
                                forParameter:cmdBuffer
                                objectNumber:objectNumber
                                count:&bufferLength];

        if (status != IO_R_SUCCESS) {
            continue;  /* Skip if config unavailable */
        }

        /* Display configuration header */
        printf("\n");
        printf("============================================\n");
        printf("Current configuration for Logical Device %d:\n", logicalDevice);
        printf("============================================\n");

        /* Create PnPResources object from register values */
        resources = [[objc_getClass("PnPResources") alloc] initFromRegisters:valueBuffer];

        /* Print configuration if valid */
        if (resources == nil) {
            printf("config is nil - continuing\n");
        } else {
            [resources print];
            [resources free];
        }
    }
}

/*
 * Main program entry point
 */
int main(int argc, char *argv[])
{
    BOOL showConfigs = NO;
    BOOL showDevices = NO;
    id deviceMaster;
    IOReturn status;
    int objectNumber;
    int csn;
    char *arg;

    /* Save program name */
    progname = argv[0];

    /* Parse command line arguments */
    if (argc == 1) {
        /* No arguments - show both configs and devices */
        showConfigs = YES;
        showDevices = YES;
    } else {
        /* Process arguments */
        argc--;
        argv++;

        while (argc > 0) {
            arg = *argv;

            if (arg[0] == '-') {
                /* Process option flags */
                arg++;
                while (*arg != '\0') {
                    switch (*arg) {
                        case 'c':
                            showConfigs = YES;
                            break;
                        case 'd':
                            showDevices = YES;
                            break;
                        default:
                            bail("invalid option", 0);
                            break;
                    }
                    arg++;
                }
            }

            argc--;
            argv++;
        }
    }

    /* Get IODeviceMaster port */
    deviceMaster = [IODeviceMaster new];
    if (deviceMaster == nil) {
        bail("Failed to create IODeviceMaster", 0);
    }

    /* Look up EISA0 device */
    status = [deviceMaster lookUpByDeviceName:"EISA0"
                            objectNumber:&objectNumber];
    if (status != IO_R_SUCCESS) {
        bail("lookup EISA0 failed", status);
    }

    /* Enable verbose mode for PnPDeviceResources */
    [objc_getClass("PnPDeviceResources") setVerbose:YES];

    /* Enumerate all possible CSNs (Card Select Numbers) */
    for (csn = 1; csn <= MAX_CSN; csn++) {
        int deviceCount = MAX_LOGICAL_DEVICES;  /* Default device count */

        /* Dump device configuration if requested */
        if (showConfigs) {
            deviceCount = dumpDeviceInfo(deviceMaster, objectNumber, csn);
            if (deviceCount < 0) {
                /* No device at this CSN, skip to next */
                continue;
            }
        }

        /* Dump logical device configurations if requested */
        if (showDevices && deviceCount > 0) {
            dumpLogicalDeviceConfigs(deviceMaster, objectNumber, csn, deviceCount);
        }
    }

    /* Clean exit */
    exit(0);
}
