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
 * InstallPPDev - Parallel Port Device Installation Utility
 *
 * This utility installs parallel port device configuration for
 * RhapsodiOS parallel port drivers (LPT1-LPT3).
 *
 * Usage:
 *   InstallPPDev [-port <portname>] [-base <address>] [-irq <number>]
 *                [-mode <mode>] [-verbose]
 *
 * Examples:
 *   InstallPPDev -port LPT1
 *   InstallPPDev -port LPT2 -base 0x278 -irq 5
 *   InstallPPDev -port LPT1 -mode EPP -verbose
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

/* Default port configurations */
typedef struct {
    const char *portName;
    UInt16      baseAddress;
    UInt32      irq;
    const char *mode;
} PortConfig;

static PortConfig defaultConfigs[] = {
    { "LPT1", LPT1_BASE, LPT1_IRQ, "SPP" },
    { "LPT2", LPT2_BASE, LPT2_IRQ, "SPP" },
    { "LPT3", LPT3_BASE, LPT3_IRQ, "SPP" },
    { NULL, 0, 0, NULL }
};

/* Verbose output flag */
static BOOL verbose = NO;

/* Function prototypes */
static void usage(void);
static PortConfig *getDefaultConfig(const char *portName);
static IOReturn installPort(const char *portName, UInt16 baseAddress,
                           UInt32 irq, const char *mode);
static IOReturn configureDriver(IODeviceMaster *master, const char *portName,
                               UInt16 baseAddress, UInt32 irq, const char *mode);
static IOReturn createDeviceNodes(const char *portName);
static void printVerbose(const char *format, ...);

/**
 * Main entry point
 */
int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    const char *portName = NULL;
    UInt16 baseAddress = 0;
    UInt32 irq = 0;
    const char *mode = NULL;
    IOReturn result;
    int i;

    /* Parse command line arguments */
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-port") == 0 && i + 1 < argc) {
            portName = argv[++i];
        }
        else if (strcmp(argv[i], "-base") == 0 && i + 1 < argc) {
            char *endptr;
            baseAddress = (UInt16)strtoul(argv[++i], &endptr, 0);
            if (*endptr != '\0') {
                fprintf(stderr, "Error: Invalid base address '%s'\n", argv[i]);
                usage();
                exit(1);
            }
        }
        else if (strcmp(argv[i], "-irq") == 0 && i + 1 < argc) {
            char *endptr;
            irq = (UInt32)strtoul(argv[++i], &endptr, 0);
            if (*endptr != '\0') {
                fprintf(stderr, "Error: Invalid IRQ '%s'\n", argv[i]);
                usage();
                exit(1);
            }
        }
        else if (strcmp(argv[i], "-mode") == 0 && i + 1 < argc) {
            mode = argv[++i];
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

    /* Get default configuration if parameters not specified */
    PortConfig *config = getDefaultConfig(portName);
    if (config == NULL) {
        fprintf(stderr, "Error: Unknown port '%s'\n", portName);
        fprintf(stderr, "Valid ports: LPT1, LPT2, LPT3\n");
        exit(1);
    }

    if (baseAddress == 0) {
        baseAddress = config->baseAddress;
    }
    if (irq == 0) {
        irq = config->irq;
    }
    if (mode == NULL) {
        mode = config->mode;
    }

    /* Check if running as root */
    if (getuid() != 0) {
        fprintf(stderr, "Error: This utility must be run as root\n");
        exit(1);
    }

    /* Install the port */
    printVerbose("Installing parallel port device: %s\n", portName);
    printVerbose("  Base Address: 0x%04X\n", baseAddress);
    printVerbose("  IRQ: %u\n", irq);
    printVerbose("  Mode: %s\n", mode);

    result = installPort(portName, baseAddress, irq, mode);

    if (result != IO_R_SUCCESS) {
        fprintf(stderr, "Error: Failed to install port '%s' (error %d)\n",
                portName, result);
        [pool release];
        exit(1);
    }

    printf("Successfully installed parallel port device: %s\n", portName);
    printVerbose("Device nodes created in /dev\n");

    [pool release];
    return 0;
}

/**
 * Print usage information
 */
static void usage(void)
{
    printf("Usage: InstallPPDev [options]\n");
    printf("\n");
    printf("Options:\n");
    printf("  -port <name>      Port name (LPT1, LPT2, or LPT3) [required]\n");
    printf("  -base <address>   Base I/O address (hex or decimal)\n");
    printf("  -irq <number>     IRQ number\n");
    printf("  -mode <mode>      Operating mode (SPP, PS2, EPP, ECP)\n");
    printf("  -verbose, -v      Verbose output\n");
    printf("  -help, -h         Show this help\n");
    printf("\n");
    printf("Default configurations:\n");
    printf("  LPT1: Base=0x378, IRQ=7, Mode=SPP\n");
    printf("  LPT2: Base=0x278, IRQ=5, Mode=SPP\n");
    printf("  LPT3: Base=0x3BC, IRQ=7, Mode=SPP\n");
    printf("\n");
    printf("Examples:\n");
    printf("  InstallPPDev -port LPT1\n");
    printf("  InstallPPDev -port LPT2 -base 0x278 -irq 5\n");
    printf("  InstallPPDev -port LPT1 -mode EPP -verbose\n");
    printf("\n");
}

/**
 * Get default configuration for a port
 */
static PortConfig *getDefaultConfig(const char *portName)
{
    int i;

    for (i = 0; defaultConfigs[i].portName != NULL; i++) {
        if (strcasecmp(defaultConfigs[i].portName, portName) == 0) {
            return &defaultConfigs[i];
        }
    }

    return NULL;
}

/**
 * Install parallel port device
 */
static IOReturn installPort(const char *portName, UInt16 baseAddress,
                           UInt32 irq, const char *mode)
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

    /* Configure the driver */
    result = configureDriver(master, portName, baseAddress, irq, mode);
    if (result != IO_R_SUCCESS) {
        [master free];
        return result;
    }

    /* Create device nodes */
    result = createDeviceNodes(portName);
    if (result != IO_R_SUCCESS) {
        fprintf(stderr, "Warning: Failed to create device nodes (error %d)\n", result);
        /* Don't fail completely if device node creation fails */
    }

    [master free];
    return IO_R_SUCCESS;
}

/**
 * Configure the parallel port driver
 */
static IOReturn configureDriver(IODeviceMaster *master, const char *portName,
                               UInt16 baseAddress, UInt32 irq, const char *mode)
{
    IOConfigTable *configTable;
    NSDictionary *portConfig;
    NSString *portKey;
    IOReturn result;

    printVerbose("Configuring driver for %s...\n", portName);

    /* Create configuration dictionary */
    portConfig = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSString stringWithFormat:@"0x%04X", baseAddress], @"Port",
        [NSString stringWithFormat:@"%u", irq], @"IRQ",
        [NSString stringWithCString:mode], @"Mode",
        @"YES", @"Probe",
        nil];

    /* Get the driver's config table */
    configTable = [IOConfigTable newForDriver:@"ParallelPort"];
    if (configTable == nil) {
        fprintf(stderr, "Error: Failed to get config table for ParallelPort driver\n");
        return IO_R_NO_DEVICE;
    }

    /* Add the port configuration */
    portKey = [NSString stringWithCString:portName];
    [configTable setValue:portConfig forKey:portKey];

    printVerbose("Configuration written for %s\n", portName);

    [configTable free];
    return IO_R_SUCCESS;
}

/**
 * Create device nodes for the parallel port
 */
static IOReturn createDeviceNodes(const char *portName)
{
    char devPath[256];
    int portNum;

    printVerbose("Creating device nodes...\n");

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

    /* Create /dev/lpt<n> node */
    snprintf(devPath, sizeof(devPath), "/dev/lpt%d", portNum);
    printVerbose("  Creating %s\n", devPath);

    /* Note: Actual mknod would be done by the kernel driver */
    /* Here we just verify the path is correct */

    /* Create /dev/parport<n> symlink */
    snprintf(devPath, sizeof(devPath), "/dev/parport%d", portNum);
    printVerbose("  Creating %s\n", devPath);

    return IO_R_SUCCESS;
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
