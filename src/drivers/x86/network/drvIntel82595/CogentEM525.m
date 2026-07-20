/*
 * CogentEM525.m
 * Cogent EM525 Ethernet Adapter Driver
 */

#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/* Forward declaration of Intel82595 base class */
@interface Intel82595 : IOEthernetDriver
+ (BOOL)probeIDRegisterAt:(unsigned int)address;
@end

@interface CogentEM525 : IOEthernetDriver
{
    unsigned int ioBase;
    unsigned int irqLevel;
    unsigned char romAddress[6];
    unsigned char currentBank;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- (BOOL)coldInit;
- (const char *)description;

@end

@implementation CogentEM525

/*
 * Probe for Cogent EM525 hardware
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
        IOLog("CogentEM525: No I/O port range configured - aborting\n");
        return NO;
    }

    /* Get port range and validate it */
    portRange = [deviceDescription portRangeList:0];
    if ((portRange->start & 0x0F) != 0 || portRange->size <= 0x0F) {
        IOLog("CogentEM525: Invalid I/O port range configured - aborting\n");
        return NO;
    }

    /* Check if interrupt is configured */
    numInterrupts = [deviceDescription numInterrupts];
    if (numInterrupts == 0) {
        IOLog("CogentEM525: No interrupt configured - aborting\n");
        return NO;
    }

    ioBase = portRange->start;

    /* Probe the ID register */
    if (![Intel82595 probeIDRegisterAt:ioBase]) {
        IOLog("CogentEM525: Adapter not found at address 0x%x - aborting\n", ioBase);
        return NO;
    }

    /* Try to allocate and initialize an instance */
    instance = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (instance == nil) {
        IOLog("CogentEM525: Unable to allocate an instance - aborting\n");
        return NO;
    }

    [instance free];
    return YES;
}

/*
 * Cold initialization - Read MAC address from EEPROM
 */
- (BOOL)coldInit
{
    int wordIndex;
    int bitIndex;
    unsigned short eepromWord;
    unsigned short bitMask;
    unsigned char command;
    unsigned char eepromCtrl;
    int timeout;

    /* Read 3 words (6 bytes) of MAC address from EEPROM */
    for (wordIndex = 0; wordIndex < 3; wordIndex++) {
        eepromWord = 0x8000;
        bitMask = 0;

        /* EEPROM read command: 110 (bits 7-5) + address (bits 4-0) */
        command = ((wordIndex + 2) | 0x80);  /* Read command with address offset */

        /* Select bank 2 for EEPROM access */
        if (currentBank != 0x02) {
            outb(ioBase, 0x80);
            IODelay(1);
            currentBank = 0x02;
        }

        /* Get current EEPROM control register value */
        eepromCtrl = inb(ioBase + 10);
        eepromCtrl &= 0xF0;  /* Clear lower bits */

        /* Set chip select and data in */
        if (currentBank != 0x02) {
            outb(ioBase, 0x80);
            IODelay(1);
            currentBank = 0x02;
        }
        outb(ioBase + 10, eepromCtrl);
        IODelay(20);

        /* Raise chip select */
        if (currentBank != 0x02) {
            outb(ioBase, 0x80);
            IODelay(1);
            currentBank = 0x02;
        }
        outb(ioBase + 10, eepromCtrl | 0x02);
        IODelay(1);

        eepromCtrl |= 0x06;  /* CS + DI */

        /* Send 9-bit command (start bit + opcode + address) */
        for (bitIndex = 0; bitIndex < 9; bitIndex++) {
            if (bitIndex != 0) {
                /* Set data bit based on command */
                if ((char)command < 0) {
                    eepromCtrl |= 0x04;  /* Set DI */
                } else {
                    eepromCtrl &= 0xFB;  /* Clear DI */
                }
                command <<= 1;
            }

            /* Clock low */
            if (currentBank != 0x02) {
                outb(ioBase, 0x80);
                IODelay(1);
                currentBank = 0x02;
            }
            outb(ioBase + 10, eepromCtrl);
            IODelay(1);

            /* Clock high */
            if (currentBank != 0x02) {
                outb(ioBase, 0x80);
                IODelay(1);
                currentBank = 0x02;
            }
            outb(ioBase + 10, eepromCtrl | 0x01);
            IODelay(1);

            /* Clock low */
            if (currentBank != 0x02) {
                outb(ioBase, 0x80);
                IODelay(1);
                currentBank = 0x02;
            }
            outb(ioBase + 10, eepromCtrl);
            IODelay(1);
        }

        /* Wait for data ready (DO goes low) */
        timeout = 0;
        while (timeout < 100) {
            if (currentBank != 0x02) {
                outb(ioBase, 0x80);
                IODelay(1);
                currentBank = 0x02;
            }
            eepromCtrl = inb(ioBase + 10);
            if ((eepromCtrl & 0x08) == 0) {
                break;
            }
            IODelay(1);
            timeout++;
        }

        if (timeout == 100) {
            IOLog("%s: unable to read Ethernet address from EEPROM\n", [self name]);
            return NO;
        }

        /* Read 16 bits of data */
        for (bitIndex = 0; bitIndex < 16; bitIndex++) {
            IODelay(1);

            /* Clock high */
            if (currentBank != 0x02) {
                outb(ioBase, 0x80);
                IODelay(1);
                currentBank = 0x02;
            }
            outb(ioBase + 10, eepromCtrl | 0x03);
            IODelay(1);

            /* Clock low */
            if (currentBank != 0x02) {
                outb(ioBase, 0x80);
                IODelay(1);
                currentBank = 0x02;
            }
            outb(ioBase + 10, (eepromCtrl | 0x03) & 0xFE);
            IODelay(1);

            /* Read data bit */
            if (currentBank != 0x02) {
                outb(ioBase, 0x80);
                IODelay(1);
                currentBank = 0x02;
            }
            eepromCtrl = inb(ioBase + 10);

            if (eepromCtrl & 0x08) {
                bitMask |= eepromWord;
            }
            eepromWord >>= 1;
        }

        /* Deselect EEPROM */
        if (currentBank != 0x02) {
            outb(ioBase, 0x80);
            IODelay(1);
            currentBank = 0x02;
        }
        eepromCtrl = inb(ioBase + 10);

        if (currentBank != 0x02) {
            outb(ioBase, 0x80);
            IODelay(1);
            currentBank = 0x02;
        }
        outb(ioBase + 10, eepromCtrl & 0xF0);
        IODelay(1);

        /* Store word in MAC address buffer (big-endian) */
        romAddress[4 - (wordIndex * 2)] = (bitMask >> 8) & 0xFF;
        romAddress[5 - (wordIndex * 2)] = bitMask & 0xFF;
    }

    /* Validate Cogent vendor ID (0x00 0x00 0x92) */
    if ((romAddress[0] == 0x00) && (romAddress[1] == 0x00) && (romAddress[2] == 0x92)) {
        return YES;
    } else {
        IOLog("%s: Found non-Cogent Ethernet address in EEPROM.\n", [self name]);
        return NO;
    }
}

/*
 * Get description
 */
- (const char *)description
{
    return "Cogent eMASTER+ EM525 AT";
}

@end
