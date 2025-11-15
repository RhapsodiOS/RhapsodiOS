/*
 * Intel82595ISA.m
 * Intel 82595 ISA Bus Variant Driver
 */

#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@interface Intel82595ISA : IOEthernetDriver
{
    unsigned int ioBase;
    unsigned int irqLevel;
    unsigned char currentBank;
}

- (BOOL)busConfig;
- (BOOL)irqConfig;
- (BOOL)resetChip;
- (const char *)description;

@end

/* IRQ mapping table: maps logical IRQ to hardware register value */
static const unsigned short irqMap[5] = {
    3, 5, 9, 10, 11
};

@implementation Intel82595ISA

/*
 * Configure ISA bus - Detect and enable 16-bit mode if supported
 */
- (BOOL)busConfig
{
    unsigned char reg1, reg13;

    /* Select bank 1 */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }

    /* Read bank 1 register 1 */
    reg1 = inb(ioBase + 1);

    /* Check bit 1 - if clear, it's an 8-bit slot */
    if ((reg1 & 0x02) == 0) {
        IOLog("%s: 8-bit slot detected\n", [self name]);
    } else {
        /* 16-bit capable slot detected */

        /* Clear bit 6 of register 1 */
        if (currentBank != 0x01) {
            outb(ioBase, 0x40);
            IODelay(1);
            currentBank = 0x01;
        }
        outb(ioBase + 1, reg1 & 0xBF);
        IODelay(1);

        /* Read register 13 */
        if (currentBank != 0x01) {
            outb(ioBase, 0x40);
            IODelay(1);
            currentBank = 0x01;
        }
        reg13 = inb(ioBase + 0x0D);

        /* Set bit 1 of register 13 */
        if (currentBank != 0x01) {
            outb(ioBase, 0x40);
            IODelay(1);
            currentBank = 0x01;
        }
        outb(ioBase + 0x0D, reg13 | 0x02);
        IODelay(1);

        /* Perform dummy read from base register */
        if (currentBank != 0x01) {
            outb(ioBase, 0x40);
            IODelay(1);
            currentBank = 0x01;
        }
        inb(ioBase);

        /* Read register 13 again */
        if (currentBank != 0x01) {
            outb(ioBase, 0x40);
            IODelay(1);
            currentBank = 0x01;
        }
        reg13 = inb(ioBase + 0x0D);

        /* Clear bit 1 of register 13 */
        if (currentBank != 0x01) {
            outb(ioBase, 0x40);
            IODelay(1);
            currentBank = 0x01;
        }
        outb(ioBase + 0x0D, reg13 & 0xFD);
        IODelay(1);

        /* Check if bit 0 is clear (16-bit test failed) */
        if ((reg13 & 0x01) == 0) {
            /* First test failed, try with bit 6 set */
            if (currentBank != 0x01) {
                outb(ioBase, 0x40);
                IODelay(1);
                currentBank = 0x01;
            }
            outb(ioBase + 1, (reg1 & 0xFD) | 0x40);
            IODelay(1);

            /* Read register 13 */
            if (currentBank != 0x01) {
                outb(ioBase, 0x40);
                IODelay(1);
                currentBank = 0x01;
            }
            reg13 = inb(ioBase + 0x0D);

            /* Set bit 1 of register 13 */
            if (currentBank != 0x01) {
                outb(ioBase, 0x40);
                IODelay(1);
                currentBank = 0x01;
            }
            outb(ioBase + 0x0D, reg13 | 0x02);
            IODelay(1);

            /* Perform dummy read */
            if (currentBank != 0x01) {
                outb(ioBase, 0x40);
                IODelay(1);
                currentBank = 0x01;
            }
            inb(ioBase);

            /* Read register 13 again */
            if (currentBank != 0x01) {
                outb(ioBase, 0x40);
                IODelay(1);
                currentBank = 0x01;
            }
            reg13 = inb(ioBase + 0x0D);

            /* Clear bit 1 */
            if (currentBank != 0x01) {
                outb(ioBase, 0x40);
                IODelay(1);
                currentBank = 0x01;
            }
            outb(ioBase + 0x0D, reg13 & 0xFD);
            IODelay(1);

            /* Check if still failed */
            if ((reg13 & 0x01) == 0) {
                /* Unable to perform 16-bit transfers */
                if (currentBank != 0x01) {
                    outb(ioBase, 0x40);
                    IODelay(1);
                    currentBank = 0x01;
                }
                outb(ioBase + 1, reg13 & 0xBD);
                IODelay(1);

                IOLog("%s: Unable to perform 16-bit transfers\n", [self name]);
                IOLog("%s: Defaulting to 8-bit mode\n", [self name]);
            }
        }
    }

    /* Call irqConfig to complete configuration */
    return [self irqConfig];
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
 * Reset chip - ISA variant with timeout
 */
- (BOOL)resetChip
{
    unsigned char status;
    unsigned int timeout;

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

    /* Issue reset command (0x0E) */
    status = inb(ioBase);
    outb(ioBase, (status & 0xE0) | 0x0E);
    IODelay(1);
    IODelay(250);

    /* Wait for execution interrupt (bit 3) with timeout */
    timeout = 0;
    while (timeout < 500000) {
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        status = inb(ioBase + 1);

        if ((status & 0x08) != 0) {
            /* Execution interrupt received - reset complete */
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            outb(ioBase + 1, 0x08);
            IODelay(1);

            /* Force bank re-initialization */
            currentBank = 0x03;
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;

            return YES;
        }
        timeout++;
    }

    /* Timeout - reset failed */
    currentBank = 0x03;
    outb(ioBase, 0x00);
    IODelay(1);
    currentBank = 0x00;

    return NO;
}

/*
 * Get description string
 */
- (const char *)description
{
    return "Intel82595-based ISA Ethernet Adapter";
}

@end
