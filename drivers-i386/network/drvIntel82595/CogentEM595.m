/*
 * CogentEM595.m
 * Cogent EM595 Ethernet Adapter Driver
 */

#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/* Forward declaration of Intel82595 base class */
@interface Intel82595 : IOEthernetDriver
+ (BOOL)probeIDRegisterAt:(unsigned int)address;
@end

@interface CogentEM595 : IOEthernetDriver
{
    unsigned int ioBase;
    unsigned int irqLevel;
    unsigned char romAddress[6];
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- (BOOL)coldInit;
- (const char *)description;

@end

@implementation CogentEM595

/*
 * Probe for Cogent EM595 hardware
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    IORange *portRange;
    unsigned int ioBase;
    int numPorts, numInterrupts;
    id instance;

    /* Check if I/O port range is configured */
    numPorts = [deviceDescription numPortRanges];
    if (numPorts == 0) {
        IOLog("CogentEM595: No I/O port range configured - aborting\n");
        return NO;
    }

    /* Get port range and validate it */
    portRange = [deviceDescription portRangeList:0];
    if ((portRange->start & 0x0F) != 0 || portRange->size <= 0x0F) {
        IOLog("CogentEM595: Invalid I/O port range configured - aborting\n");
        return NO;
    }

    /* Check if interrupt is configured */
    numInterrupts = [deviceDescription numInterrupts];
    if (numInterrupts == 0) {
        IOLog("CogentEM595: No interrupt configured - aborting\n");
        return NO;
    }

    ioBase = portRange->start;

    /* Probe the ID register */
    if (![Intel82595 probeIDRegisterAt:ioBase]) {
        IOLog("CogentEM595: Adapter not found at address 0x%x - aborting\n", ioBase);
        return NO;
    }

    /* Try to allocate and initialize an instance */
    instance = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (instance == nil) {
        IOLog("CogentEM595: Unable to allocate an instance - aborting\n");
        return NO;
    }

    [instance free];
    return YES;
}

/*
 * Cold initialization - Read MAC address from PCMCIA CIS tuples
 */
- (BOOL)coldInit
{
    id deviceDesc;
    unsigned int numTuples;
    id *tupleList;
    unsigned int i;
    unsigned char tupleCode;
    unsigned char *tupleData;
    int j;

    /* Get device description */
    deviceDesc = [self deviceDescription];
    if (deviceDesc == nil) {
        IOLog("%s: cannot access device description\n", [self name]);
        return NO;
    }

    /* Get number of CIS tuples */
    numTuples = [deviceDesc numTuples];
    if (numTuples == 0) {
        IOLog("%s: cannot access CIS tuples\n", [self name]);
        return NO;
    }

    /* Get tuple list */
    tupleList = [deviceDesc tupleList];
    if (tupleList == NULL) {
        IOLog("%s: cannot access CIS tuples list\n", [self name]);
        return NO;
    }

    /* Search for CISTPL_FUNCE tuple (0x22) containing MAC address */
    for (i = 0; i < numTuples; i++) {
        tupleCode = [tupleList[i] code];
        if (tupleCode == 0x22) {  /* CISTPL_FUNCE - Function Extension tuple */
            tupleData = [tupleList[i] data];
            [tupleList[i] length];

            /* MAC address is at offset 9 in the tuple data */
            for (j = 0; j < 6; j++) {
                romAddress[j] = tupleData[9 + j];
            }
            return YES;
        }
    }

    return NO;
}

/*
 * Get description
 */
- (const char *)description
{
    return "Cogent eMASTER+ EM595 PCMCIA";
}

@end
