/*
 * IntelEEPro10+.m
 * Intel EtherExpress PRO/10+ ISA Adapter Driver
 */

#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/* Forward declaration of Intel82595 base class */
@interface Intel82595 : IOEthernetDriver
+ (BOOL)probeIDRegisterAt:(unsigned int)address;
@end

/* Forward declaration of i82595eeprom class */
@interface i82595eeprom : Object
- initWithBase:(unsigned short)base CurrentBank:(unsigned char *)bankPtr;
- (unsigned short *)getContents;
@end

@interface IntelEEPro10Plus : IOEthernetDriver
{
    unsigned int ioBase;
    unsigned int irqLevel;
    unsigned char romAddress[6];
    unsigned char currentBank;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- (BOOL)coldInit;
- (BOOL)busConfig;
- (BOOL)irqConfig;
- (unsigned int)onboardMemoryPresent;
- (BOOL)resetChip;
- (const char *)description;

@end

/* IRQ mapping table: EEPro10+ supports 8 IRQs */
static const unsigned short irqMap[8] = {
    3, 4, 5, 7, 9, 10, 11, 12
};

@implementation IntelEEPro10Plus

/*
 * Probe for Intel EtherExpress PRO/10+ hardware
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
        IOLog("IntelEEPro10+: No I/O port range configured - aborting\n");
        return NO;
    }

    /* Get port range and validate it */
    portRange = [deviceDescription portRangeList:0];
    if ((portRange->start & 0x0F) != 0 || portRange->size <= 0x0F) {
        IOLog("IntelEEPro10+: Invalid I/O port range configured - aborting\n");
        return NO;
    }

    /* Check if interrupt is configured */
    numInterrupts = [deviceDescription numInterrupts];
    if (numInterrupts == 0) {
        IOLog("IntelEEPro10+: No interrupt configured - aborting\n");
        return NO;
    }

    ioBase = portRange->start;

    /* Probe the ID register */
    if (![Intel82595 probeIDRegisterAt:ioBase]) {
        IOLog("IntelEEPro10+: Adapter not found at address 0x%x - aborting\n", ioBase);
        return NO;
    }

    /* Try to allocate and initialize an instance */
    instance = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (instance == nil) {
        IOLog("IntelEEPro10+: Unable to allocate an instance - aborting\n");
        return NO;
    }

    [instance free];
    return YES;
}

/*
 * Cold initialization - Read MAC address using i82595eeprom class
 */
- (BOOL)coldInit
{
    id eeprom;
    unsigned short *eepromContents;
    int i;

    /* Allocate and initialize i82595eeprom object */
    eeprom = [[objc_getClass("i82595eeprom") alloc]
              initWithBase:ioBase CurrentBank:&currentBank];

    if (eeprom == nil) {
        IOLog("82595eeprom returned nil\n");
        return NO;
    }

    /* Get EEPROM contents buffer */
    eepromContents = [eeprom getContents];

    /* Copy MAC address from EEPROM offset 9, in reverse byte order */
    for (i = 0; i < 6; i++) {
        romAddress[i] = ((unsigned char *)eepromContents)[9 - i];
    }

    /* Free the EEPROM object */
    [eeprom free];

    return YES;
}

/*
 * Configure bus - Simply calls irqConfig
 */
- (BOOL)busConfig
{
    [self irqConfig];
    return YES;
}

/*
 * Configure IRQ - EEPro10+ supports 8 IRQs
 */
- (BOOL)irqConfig
{
    unsigned char irqIndex;
    unsigned char regValue;

    /* Find IRQ in mapping table (8 IRQs supported) */
    irqIndex = 0;
    while (irqIndex < 8) {
        if (irqLevel == irqMap[irqIndex]) {
            break;
        }
        irqIndex++;
    }

    /* Validate IRQ is supported */
    if (irqIndex == 8) {
        IOLog("%s: Invalid IRQ Level (%d) configured.\n", [self name], irqLevel);
        return NO;
    }

    /* Select bank 1 */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }

    /* Read current value of register 2 */
    regValue = inb(ioBase + 2);

    /* Write IRQ index to bits 0-2 of register 2 */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }
    outb(ioBase + 2, (regValue & 0xF8) | (irqIndex & 0x07));
    IODelay(1);

    return YES;
}

/*
 * Return amount of onboard memory present
 */
- (unsigned int)onboardMemoryPresent
{
    /* Intel EtherExpress PRO/10+ has 32KB of onboard RAM */
    return 0x8000;
}

/*
 * Reset chip - EEPro10+ variant
 */
- (BOOL)resetChip
{
    unsigned char status;

    /* Select bank 0 */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }

    /* Read status register */
    status = inb(ioBase + 1);

    /* Check if execution interrupt is set (bit 3) */
    if ((status & 0x08) != 0) {
        /* Clear execution interrupt */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outb(ioBase + 1, 0x08);
        IODelay(1);
        IOSleep(100);
    }

    /* Issue reset command (0x1E) */
    status = inb(ioBase);
    outb(ioBase, (status & 0xE0) | 0x1E);
    IODelay(1);
    IODelay(200);
    IOSleep(1);  /* Additional 1ms sleep for EEPro10+ */

    /* Force bank re-initialization */
    currentBank = 0x03;
    outb(ioBase, 0x00);
    IODelay(1);
    currentBank = 0x00;

    return YES;
}

/*
 * Get description string
 */
- (const char *)description
{
    return "Intel EtherExpress PRO/10+ ISA";
}

@end
