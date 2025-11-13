/*
 * EtherLink3PnP.m
 * 3Com EtherLink III Network Driver - Plug and Play (ISA PnP) Bus Variant
 */

#import "EtherLink3.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation EtherLink3PnP

/*
 * Probe method for ISA PnP bus - Called during driver discovery
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    EtherLink3PnP *driver;
    IORange *portRange;
    unsigned short ioBase;
    unsigned short vendorID, productID;
    unsigned int irq;
    int numInterrupts, numPorts;

    /* Allocate driver instance */
    driver = [[self alloc] init];
    if (driver == nil) {
        return NO;
    }

    /* Check if interrupt is configured */
    numInterrupts = [deviceDescription numInterrupts];
    if (numInterrupts == 0) {
        IOLog("EtherLinkIII: Interrupt level not configured - aborting\n");
        [driver free];
        return NO;
    }

    /* Check if I/O ports are configured */
    numPorts = [deviceDescription numPortRanges];
    if (numPorts == 0) {
        IOLog("EtherLinkIII: I/O ports not configured - aborting\n");
        [driver free];
        return NO;
    }

    /* Get port range */
    portRange = [deviceDescription portRangeList];
    if (portRange == NULL || portRange->size < 16) {
        [driver free];
        return NO;
    }

    /* Read card ID from I/O base (PnP devices are already activated) */
    ioBase = portRange->start;
    vendorID = inw(ioBase);
    productID = inw(ioBase + 2);

    /* Check for 3Com EtherLink III (vendor 0x6d50, product 0x90xx) */
    if (vendorID == EL3_VENDOR_ID && (productID & 0xF0FF) == EL3_PRODUCT_ID) {
        /* Found EtherLink III PnP card */
        [driver setISA:NO];  /* PnP is not regular ISA */
        [driver setIOBase:ioBase];

        irq = [deviceDescription interrupt];
        [driver setIRQ:irq];

        /* Note: setDoAuto is not called for PnP - auto-detect is not needed */

        /* Initialize the driver */
        if ([driver initFromDeviceDescription:deviceDescription] != nil) {
            return YES;
        }
    } else {
        IOLog("EtherLinkIII: ISA/PnP adapter not found at address 0x%04x - aborting\n", ioBase);
    }

    [driver free];
    return NO;
}

/*
 * Initialize PnP variant from device description
 * Overrides base class method to add PnP-specific initialization
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    const char *driverName;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    driverName = [[self name] cString];
    IOLog("%s: PnP initFromDeviceDescription called\n", driverName);

    /* Set ISA flag to YES for ISA PnP bus (it's still ISA-based) */
    [self setISA:YES];

    /* PnP-specific initialization would go here */
    /* This might include:
     * - Activating the PnP device
     * - Reading PnP resource allocation
     * - Configuring device with allocated resources
     */

    return self;
}

@end
