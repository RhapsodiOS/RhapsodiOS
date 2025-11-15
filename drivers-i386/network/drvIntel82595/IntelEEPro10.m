/*
 * IntelEEPro10.m
 * Intel EtherExpress PRO/10 ISA Adapter Driver
 */

#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/* Forward declaration of Intel82595 base class */
@interface Intel82595 : IOEthernetDriver
+ (BOOL)probeIDRegisterAt:(unsigned int)address;
@end

@interface IntelEEPro10 : IOEthernetDriver
{
    unsigned int ioBase;
    unsigned int irqLevel;
    unsigned char romAddress[6];
    unsigned char currentBank;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- (BOOL)coldInit;
- (void)intelEEPro10PnPInit;
- (BOOL)irqConfig;
- (const char *)description;

@end

/* ISA Plug and Play initiation key sequence */
static const unsigned char io_address_enable_str[32] = {
    0x6A, 0xB5, 0xDA, 0xED, 0xF6, 0xFB, 0x7D, 0xBE,
    0xDF, 0x6F, 0x37, 0x1B, 0x0D, 0x86, 0xC3, 0x61,
    0xB0, 0x58, 0x2C, 0x16, 0x8B, 0x45, 0xA2, 0xD1,
    0xE8, 0x74, 0x3A, 0x9D, 0xCE, 0xE7, 0x73, 0x39
};

/* IRQ mapping table: maps logical IRQ to hardware register value */
static const unsigned short irqMap[5] = {
    3, 5, 9, 10, 11
};

@implementation IntelEEPro10

/*
 * Probe for Intel EtherExpress PRO/10 hardware
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
        IOLog("IntelEEPro10: No I/O port range configured - aborting\n");
        return NO;
    }

    /* Get port range and validate it */
    portRange = [deviceDescription portRangeList:0];
    if ((portRange->start & 0x0F) != 0 || portRange->size <= 0x0F) {
        IOLog("IntelEEPro10: Invalid I/O port range configured - aborting\n");
        return NO;
    }

    /* Check if interrupt is configured */
    numInterrupts = [deviceDescription numInterrupts];
    if (numInterrupts == 0) {
        IOLog("IntelEEPro10: No interrupt configured - aborting\n");
        return NO;
    }

    ioBase = portRange->start;

    /* Probe the ID register */
    if (![Intel82595 probeIDRegisterAt:ioBase]) {
        IOLog("IntelEEPro10: Adapter not found at address 0x%x - aborting\n", ioBase);
        return NO;
    }

    /* Try to allocate and initialize an instance */
    instance = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (instance == nil) {
        IOLog("IntelEEPro10: Unable to allocate an instance - aborting\n");
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
    int wordOffset;

    /* Read 3 words (6 bytes) of MAC address from EEPROM addresses 2, 3, 4 */
    wordOffset = 4;  /* Start at offset 4, decrement to 0 */

    for (wordIndex = 0; wordIndex < 3; wordIndex++) {
        eepromWord = 0x8000;
        bitMask = 0;

        /* EEPROM read command: address offset + 2, OR with 0x80 */
        command = (wordIndex + 2) | 0x80;

        /* Select bank 2 for EEPROM access */
        if (currentBank != 0x02) {
            outb(ioBase, 0x80);
            IODelay(1);
            currentBank = 0x02;
        }

        /* Get current EEPROM control register value and clear lower bits */
        eepromCtrl = inb(ioBase + 10);
        eepromCtrl &= 0xF0;

        /* Reset EEPROM interface */
        if (currentBank != 0x02) {
            outb(ioBase, 0x80);
            IODelay(1);
            currentBank = 0x02;
        }
        outb(ioBase + 10, eepromCtrl);
        IODelay(1);
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

        /* Store word in MAC address buffer with byte swap */
        *(unsigned short *)&romAddress[wordOffset] = (bitMask << 8) | (bitMask >> 8);
        wordOffset -= 2;
    }

    return YES;
}

/*
 * Plug and Play initialization - Send ISA PnP initiation key
 */
- (void)intelEEPro10PnPInit
{
    int i;

    /* Write to ISA PnP address port (0x279) */
    /* First write 0 twice to reset */
    outb(0x279, 0);
    IODelay(1);
    outb(0x279, 0);
    IODelay(1);

    /* Write the 32-byte initiation key sequence */
    for (i = 0; i < 0x20; i++) {
        outb(0x279, io_address_enable_str[i]);
        IODelay(1);
    }
}

/*
 * Configure IRQ - Map IRQ level to hardware register value
 */
- (BOOL)irqConfig
{
    unsigned char irqIndex;
    unsigned char regValue;

    /* Find IRQ in mapping table */
    irqIndex = 0;
    while (irqIndex < 5) {
        if (irqLevel == irqMap[irqIndex]) {
            break;
        }
        irqIndex++;
    }

    /* Validate IRQ is supported */
    if (irqIndex == 5) {
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
 * Get description string
 */
- (const char *)description
{
    return "Intel EtherExpress PRO /10";
}

/*
 * Return amount of onboard memory present
 */
- (unsigned int)onboardMemoryPresent
{
    /* Intel EtherExpress PRO/10 has 32KB of onboard RAM */
    return 0x8000;
}

/*
 * Reset chip - EEPro10 variant
 */
- (BOOL)resetChip
{
    unsigned char status;

    /* Call PnP initialization first */
    [self intelEEPro10PnPInit];

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

    /* Issue reset command (0x1E) - EEPro10 specific */
    status = inb(ioBase);
    outb(ioBase, (status & 0xE0) | 0x1E);
    IODelay(1);
    IODelay(200);

    /* Force bank re-initialization */
    currentBank = 0x03;
    outb(ioBase, 0x00);
    IODelay(1);
    currentBank = 0x00;

    return YES;
}

@end
