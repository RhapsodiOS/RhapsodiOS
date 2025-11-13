/*
 * EtherLink3PCMCIA.m
 * 3Com EtherLink III Network Driver - PCMCIA Bus Variant
 */

#import "EtherLink3.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation EtherLink3PCMCIA

/*
 * Probe method for PCMCIA bus - Called during driver discovery
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    EtherLink3PCMCIA *driver;
    IORange *portRange;
    unsigned short ioBase;
    unsigned short configReg;
    unsigned short statusReg;
    unsigned short productID;
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

    /* Get I/O base address */
    ioBase = portRange->start & 0xFFFF;

    /* Configure driver */
    [driver setISA:NO];
    [driver setIOBase:ioBase];
    [driver setIRQ:3];  /* PCMCIA typically uses IRQ 3 */
    [driver setDoAuto:YES];

    /* Configure PCMCIA card registers */
    /* Select window 0 */
    outw(ioBase + 0x0E, 0x0800);

    /* Read configuration register at offset 6 */
    configReg = inw(ioBase + 0x06);
    /* Modify: keep bits 15-14, 6-5 (mask 0xC0E0), set bit 7 (0x80) */
    outw(ioBase + 0x06, (configReg & 0xC0E0) | 0x0080);

    /* Wait for status register bit 15 to clear (busy flag) */
    do {
        statusReg = inw(ioBase + 0x0A);
    } while ((short)statusReg < 0);

    /* Write configuration command 0x83 to status register */
    outw(ioBase + 0x0A, 0x0083);

    /* Wait for busy flag to clear again */
    do {
        statusReg = inw(ioBase + 0x0A);
    } while ((short)statusReg < 0);

    /* Read product ID from offset 0x0C and write to offset 2 */
    productID = inw(ioBase + 0x0C);
    outw(ioBase + 0x02, productID);

    /* Initialize the driver */
    if ([driver initFromDeviceDescription:deviceDescription] != nil) {
        return YES;
    }

    [driver free];
    return NO;
}

/*
 * Initialize PCMCIA variant from device description
 * Overrides base class method to add PCMCIA-specific initialization
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    const char *driverName;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    driverName = [[self name] cString];
    IOLog("%s: PCMCIA initFromDeviceDescription called\n", driverName);

    /* Set ISA flag to NO for PCMCIA bus */
    [self setISA:NO];

    /* PCMCIA-specific initialization would go here */
    /* This might include:
     * - Configuring card I/O windows
     * - Setting up card power management
     * - Configuring interrupt routing
     */

    return self;
}

@end
