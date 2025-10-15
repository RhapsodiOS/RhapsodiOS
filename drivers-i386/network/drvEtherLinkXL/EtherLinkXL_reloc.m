/*
 * Copyright (c) 1998 3Com Corporation. All rights reserved.
 *
 * EtherLink XL Kernel Server Interface
 *
 * This file provides the kernel server interface for the EtherLinkXL driver.
 * It implements the necessary functions for driver loading, initialization,
 * and communication with the kernel.
 */

#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDevice.h>
#import "EtherLinkXL.h"

/* Kernel server instance */
static id etherLinkXLInstance = nil;

/* Supported PCI device IDs */
static struct {
    unsigned short vendorID;
    unsigned short deviceID;
} supportedDevices[] = {
    { 0x10B7, 0x9000 },  /* 3C900 */
    { 0x10B7, 0x9001 },  /* 3C900B */
    { 0x10B7, 0x9050 },  /* 3C905 */
    { 0x10B7, 0x9051 },  /* 3C905B */
    { 0x10B7, 0x90B1 },  /* 3C90xB */
    { 0, 0 }
};

/*
 * Probe function - called during system boot to detect hardware
 */
static IOReturn EtherLinkXL_probe(IODeviceDescription *deviceDescription, id deviceObject)
{
    IOPCIDevice *pciDevice;
    unsigned int vendorID, deviceID;
    int i;

    if ([deviceDescription respondsTo:@selector(device)]) {
        pciDevice = [deviceDescription device];
    } else {
        return IO_R_NOTATTACHED;
    }

    /* Read PCI vendor and device ID */
    vendorID = [pciDevice configReadLong:PCI_VENDOR_ID];
    deviceID = (vendorID >> 16) & 0xFFFF;
    vendorID &= 0xFFFF;

    /* Check if this is a supported device */
    for (i = 0; supportedDevices[i].vendorID != 0; i++) {
        if (vendorID == supportedDevices[i].vendorID &&
            deviceID == supportedDevices[i].deviceID) {
            return IO_R_SUCCESS;
        }
    }

    return IO_R_NOTATTACHED;
}

/*
 * Initialize function - called to initialize the driver instance
 */
static IOReturn EtherLinkXL_initialize(IODeviceDescription *deviceDescription, id deviceObject)
{
    id driver;

    driver = [[EtherLinkXL alloc] initFromDeviceDescription:deviceDescription];
    if (driver == nil) {
        IOLog("EtherLinkXL: Failed to initialize driver\n");
        return IO_R_NO_MEMORY;
    }

    etherLinkXLInstance = driver;

    /* Register the driver */
    [driver registerDevice];

    IOLog("EtherLinkXL: Driver initialized successfully\n");
    return IO_R_SUCCESS;
}

/*
 * Interrupt handler - called when hardware generates an interrupt
 */
static void EtherLinkXL_interruptHandler(void *identity, void *state, unsigned int arg)
{
    id driver = (id)identity;

    if (driver != nil) {
        [driver handleInterrupt];
    }
}

/*
 * Kernel server main entry point
 */
int EtherLinkXL_loadable(int argc, char **argv)
{
    kern_server_t *instance;
    IOReturn ret;

    IOLog("EtherLinkXL: Loading driver\n");

    /* Create kernel server instance */
    instance = IOCreateKernelServer(NULL);
    if (instance == NULL) {
        IOLog("EtherLinkXL: Failed to create kernel server\n");
        return -1;
    }

    /* Register probe and initialize functions */
    ret = IORegisterDriver(instance, "EtherLinkXL",
                          EtherLinkXL_probe,
                          EtherLinkXL_initialize);
    if (ret != IO_R_SUCCESS) {
        IOLog("EtherLinkXL: Failed to register driver\n");
        IODestroyKernelServer(instance);
        return -1;
    }

    IOLog("EtherLinkXL: Driver loaded\n");
    return 0;
}

/*
 * Unload function - called when driver is unloaded
 */
int EtherLinkXL_unloadable(void)
{
    if (etherLinkXLInstance != nil) {
        [etherLinkXLInstance free];
        etherLinkXLInstance = nil;
    }

    IOLog("EtherLinkXL: Driver unloaded\n");
    return 0;
}

/*
 * Driver version information
 */
const char *EtherLinkXL_version = "5.01";
const char *EtherLinkXL_name = "EtherLinkXL";
const char *EtherLinkXL_description = "3Com EtherLink XL 3C90X Ethernet Driver";

/*
 * Exported symbols for kernel linking
 */
void *_EtherLinkXL_symbols[] = {
    (void *)EtherLinkXL_loadable,
    (void *)EtherLinkXL_unloadable,
    (void *)EtherLinkXL_version,
    (void *)EtherLinkXL_name,
    (void *)EtherLinkXL_description,
    NULL
};
