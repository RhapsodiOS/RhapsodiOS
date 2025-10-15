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

/**
 * RemovePPDev - Parallel Port Device Removal Utility
 *
 * This utility removes parallel port device configuration from
 * RhapsodiOS parallel port drivers (LPT1-LPT3).
 *
 * Usage:
 *   RemovePPDev [-port <portname>] [-force] [-verbose]
 *
 * Examples:
 *   RemovePPDev -port LPT1
 *   RemovePPDev -port LPT2 -force
 *   RemovePPDev -port LPT1 -verbose
 */

#import <Foundation/Foundation.h>
#import <driverkit/IODeviceMaster.h>
#import <driverkit/IODevice.h>
#import <driverkit/IOConfigTable.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#import <mach/mach.h>
#import <libc.h>
#import "ParallelPortDriver.h"
#import "ParallelPortTypes.h"

/* Command line flags */
static BOOL verbose = NO;
static BOOL force = NO;

/* Function prototypes */
static void usage(void);
static IOReturn removePort(const char *portName);
static IOReturn unconfigureDriver(IODeviceMaster *master, const char *portName);
static IOReturn removeDeviceNodes(const char *portName);
static BOOL confirmRemoval(const char *portName);
static void printVerbose(const char *format, ...);

/**
 * Main entry point
 */
int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    const char *portName = NULL;
    IOReturn result;
    int i;

    /* Parse command line arguments */
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-port") == 0 && i + 1 < argc) {
            portName = argv[++i];
        }
        else if (strcmp(argv[i], "-force") == 0 || strcmp(argv[i], "-f") == 0) {
            force = YES;
        }
        else if (strcmp(argv[i], "-verbose") == 0 || strcmp(argv[i], "-v") == 0) {
            verbose = YES;
        }
        else if (strcmp(argv[i], "-help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage();
            exit(0);
        }
        else {
            fprintf(stderr, "Error: Unknown option '%s'\n", argv[i]);
            usage();
            exit(1);
        }
    }

    /* Validate port name */
    if (portName == NULL) {
        fprintf(stderr, "Error: Port name is required\n");
        usage();
        exit(1);
    }

    /* Validate port name is one of LPT1-3 */
    if (strcasecmp(portName, "LPT1") != 0 &&
        strcasecmp(portName, "LPT2") != 0 &&
        strcasecmp(portName, "LPT3") != 0) {
        fprintf(stderr, "Error: Invalid port '%s'\n", portName);
        fprintf(stderr, "Valid ports: LPT1, LPT2, LPT3\n");
        exit(1);
    }

    /* Check if running as root */
    if (getuid() != 0) {
        fprintf(stderr, "Error: This utility must be run as root\n");
        exit(1);
    }

    /* Confirm removal unless -force specified */
    if (!force) {
        if (!confirmRemoval(portName)) {
            printf("Removal cancelled.\n");
            [pool release];
            return 0;
        }
    }

    /* Remove the port */
    printVerbose("Removing parallel port device: %s\n", portName);

    result = removePort(portName);

    if (result != IO_R_SUCCESS) {
        fprintf(stderr, "Error: Failed to remove port '%s' (error %d)\n",
                portName, result);
        [pool release];
        exit(1);
    }

    printf("Successfully removed parallel port device: %s\n", portName);

    [pool release];
    return 0;
}

/**
 * Print usage information
 */
static void usage(void)
{
    printf("Usage: RemovePPDev [options]\n");
    printf("\n");
    printf("Options:\n");
    printf("  -port <name>      Port name (LPT1, LPT2, or LPT3) [required]\n");
    printf("  -force, -f        Force removal without confirmation\n");
    printf("  -verbose, -v      Verbose output\n");
    printf("  -help, -h         Show this help\n");
    printf("\n");
    printf("Examples:\n");
    printf("  RemovePPDev -port LPT1\n");
    printf("  RemovePPDev -port LPT2 -force\n");
    printf("  RemovePPDev -port LPT1 -verbose\n");
    printf("\n");
}

/**
 * Remove parallel port device
 */
static IOReturn removePort(const char *portName)
{
    IODeviceMaster *master;
    IOReturn result;

    printVerbose("Connecting to IODeviceMaster...\n");

    /* Get IODeviceMaster instance */
    master = [IODeviceMaster new];
    if (master == nil) {
        fprintf(stderr, "Error: Failed to create IODeviceMaster\n");
        return IO_R_NO_DEVICE;
    }

    /* Unconfigure the driver */
    result = unconfigureDriver(master, portName);
    if (result != IO_R_SUCCESS) {
        [master free];
        return result;
    }

    /* Remove device nodes */
    result = removeDeviceNodes(portName);
    if (result != IO_R_SUCCESS) {
        fprintf(stderr, "Warning: Failed to remove device nodes (error %d)\n", result);
        /* Don't fail completely if device node removal fails */
    }

    [master free];
    return IO_R_SUCCESS;
}

/**
 * Unconfigure the parallel port driver
 */
static IOReturn unconfigureDriver(IODeviceMaster *master, const char *portName)
{
    IOConfigTable *configTable;
    NSString *portKey;
    IOReturn result;

    printVerbose("Unconfiguring driver for %s...\n", portName);

    /* Get the driver's config table */
    configTable = [IOConfigTable newForDriver:@"ParallelPort"];
    if (configTable == nil) {
        fprintf(stderr, "Error: Failed to get config table for ParallelPort driver\n");
        return IO_R_NO_DEVICE;
    }

    /* Remove the port configuration */
    portKey = [NSString stringWithCString:portName];
    [configTable removeValueForKey:portKey];

    printVerbose("Configuration removed for %s\n", portName);

    [configTable free];
    return IO_R_SUCCESS;
}

/**
 * Remove device nodes for the parallel port
 */
static IOReturn removeDeviceNodes(const char *portName)
{
    char devPath[256];
    int portNum;
    int ret;

    printVerbose("Removing device nodes...\n");

    /* Determine port number */
    if (strcasecmp(portName, "LPT1") == 0) {
        portNum = 0;
    } else if (strcasecmp(portName, "LPT2") == 0) {
        portNum = 1;
    } else if (strcasecmp(portName, "LPT3") == 0) {
        portNum = 2;
    } else {
        return IO_R_INVALID_ARG;
    }

    /* Remove /dev/lpt<n> node */
    snprintf(devPath, sizeof(devPath), "/dev/lpt%d", portNum);
    printVerbose("  Removing %s\n", devPath);

    ret = unlink(devPath);
    if (ret != 0 && errno != ENOENT) {
        printVerbose("  Warning: Failed to remove %s: %s\n", devPath, strerror(errno));
    }

    /* Remove /dev/parport<n> symlink */
    snprintf(devPath, sizeof(devPath), "/dev/parport%d", portNum);
    printVerbose("  Removing %s\n", devPath);

    ret = unlink(devPath);
    if (ret != 0 && errno != ENOENT) {
        printVerbose("  Warning: Failed to remove %s: %s\n", devPath, strerror(errno));
    }

    return IO_R_SUCCESS;
}

/**
 * Confirm removal with user
 */
static BOOL confirmRemoval(const char *portName)
{
    char response[256];

    printf("Are you sure you want to remove parallel port device '%s'? [y/N]: ",
           portName);
    fflush(stdout);

    if (fgets(response, sizeof(response), stdin) == NULL) {
        return NO;
    }

    /* Trim newline */
    size_t len = strlen(response);
    if (len > 0 && response[len - 1] == '\n') {
        response[len - 1] = '\0';
    }

    /* Check response */
    if (strcasecmp(response, "y") == 0 || strcasecmp(response, "yes") == 0) {
        return YES;
    }

    return NO;
}

/**
 * Print verbose message
 */
static void printVerbose(const char *format, ...)
{
    va_list args;

    if (!verbose) {
        return;
    }

    va_start(args, format);
    vprintf(format, args);
    va_end(args);
}
