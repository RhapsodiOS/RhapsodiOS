/*
 * EtherLink3EISA.m
 * 3Com EtherLink III Network Driver - EISA Bus Variant
 */

#import "EtherLink3.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation EtherLink3EISA

/*
 * Probe method for EISA bus - Called during driver discovery
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    EtherLink3EISA *driver;
    int slotNumber;
    unsigned short ioBase;
    unsigned short configReg;
    unsigned int irqLevel;
    unsigned int irqList[2];
    int result;

    /* Allocate driver instance */
    driver = [[self alloc] init];
    if (driver == nil) {
        return NO;
    }

    /* Get EISA slot number */
    result = [deviceDescription getEISASlotNumber:&slotNumber];
    if (result != 0) {
        IOLog("EtherLinkIII: couldn't get slot number\n");
        [driver free];
        return NO;
    }

    /* Calculate I/O base from slot number (slot << 12) */
    ioBase = (slotNumber << 12) & 0xFFFF;

    /* Select window 0 */
    outw(ioBase + 0x0E, 0x0800);

    /* Read IRQ configuration from window 0, offset 8 */
    configReg = inw(ioBase + 0x08);

    /* Extract IRQ level from bits 12-15 */
    irqLevel = (configReg >> 12) & 0x0F;

    /* Setup interrupt list */
    irqList[0] = irqLevel;
    irqList[1] = 0;

    /* Register interrupt with device description */
    result = [deviceDescription setInterruptList:irqList num:1];
    if (result != 0) {
        IOLog("EtherLink III EISA: failed to add irq\n");
        [driver free];
        return NO;
    }

    /* Configure driver */
    [driver setISA:NO];
    [driver setIOBase:ioBase];
    [driver setIRQ:irqLevel];

    /* Initialize the driver */
    if ([driver initFromDeviceDescription:deviceDescription] != nil) {
        return YES;
    }

    [driver free];
    return NO;
}

/*
 * Initialize EISA variant from device description
 * Overrides base class method to add EISA-specific initialization
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    const char *driverName;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    driverName = [[self name] cString];
    IOLog("%s: EISA initFromDeviceDescription called\n", driverName);

    /* Set ISA flag to NO for EISA bus */
    [self setISA:NO];

    /* EISA-specific initialization would go here */

    return self;
}

@end
