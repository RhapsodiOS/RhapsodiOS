/*
 * IntelPRO100EISA.m
 * Intel EtherExpress PRO/100 Network Driver - EISA Bus Variant
 */

#import "Intel82556.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IOEISADeviceDescription.h>
#import <driverkit/i386/IOEISADirectDevice.h>

/* IRQ mapping tables for different card types */
static unsigned int _plxirq[] = {10, 11, 15, 9};
static unsigned int _fleairq[] = {5, 9, 10, 11};

/*
 * Get IRQ from EISA card configuration
 * Reads card type and IRQ configuration from EISA I/O ports
 *
 * Card types:
 *   - PLX-based: bit 7 clear at ioBase+0xc84
 *   - FLEA-based: bit 7 set at ioBase+0xc84
 *
 * Returns: IRQ number (5, 9, 10, 11, or 15)
 */
static unsigned int card_irq(unsigned short ioBase)
{
    unsigned char configByte;
    unsigned int irqIndex;

    /* Read configuration byte from ioBase + 0xc84 */
    configByte = inb(ioBase + 0xc84);

    /* Check bit 7 to determine card type */
    if ((configByte & 0x80) == 0) {
        /* PLX-based card - read from offset 0xc88 */
        configByte = inb(ioBase + 0xc88);
        irqIndex = (configByte >> 1) & 0x03;
        return _plxirq[irqIndex];
    } else {
        /* FLEA-based card - use direct config byte */
        irqIndex = (configByte >> 1) & 0x03;
        return _fleairq[irqIndex];
    }
}

@implementation IntelPRO100EISA

/*
 * Probe method for EISA bus - Called during driver discovery
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    IntelPRO100EISA *driver;
    unsigned short slotNumber;
    unsigned char eisaId[4];
    int result;

    /* Allocate driver instance */
    driver = [[self alloc] init];
    if (driver == nil) {
        return NO;
    }

    /* Get EISA slot number */
    result = [deviceDescription getEISASlotNumber:&slotNumber];
    if (result != 0) {
        IOLog("IntelPRO100EISA: couldn't get slot number\n");
        [driver free];
        return NO;
    }

    /* Get EISA slot ID */
    result = [deviceDescription getEISASlotID:eisaId];
    if (result != 0) {
        IOLog("IntelPRO100EISA: failed to retrieve eisa id\n");
        [driver free];
        return NO;
    }

    /* Calculate and store I/O base from slot number (slot << 12) */
    /* Offset 0x174 = ioBase instance variable */
    driver->ioBase = slotNumber << 12;

    /* Initialize the driver */
    if ([driver initFromDeviceDescription:deviceDescription] != nil) {
        return YES;
    }

    [driver free];
    return NO;
}

/*
 * Initialize EISA variant from device description
 *
 * Instance variables:
 *   +0x174: I/O base address (ioBase)
 *   +0x178: IRQ number
 *   +0x17C: Station address (MAC address - 6 bytes)
 *   +0x184: Network interface object
 *   +0x190: Promiscuous mode flag (offset 400)
 *   +0x191: Multicast configured flag
 *   +0x192: Flag
 *   +0x193: Multicast setup complete flag
 *   +0x1F4: Flag (offset 500)
 *   +0x1F8: Speed flag (0=10Mbps, 1=100Mbps)
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    unsigned int cardIrq;
    int result;
    BOOL coldInitResult;
    BOOL resetResult;
    const char *speedStr;
    const char *driverName;
    unsigned int slotNumber;
    id networkInterface;

    /* Get IRQ from card configuration */
    cardIrq = card_irq(ioBase);
    *(unsigned int *)(((char *)self) + 0x178) = cardIrq;

    /* Set interrupt list */
    result = [deviceDescription setInterruptList:(unsigned int *)(((char *)self) + 0x178) num:1];

    if (result != 0) {
        /* Failed to add IRQ */
        IOLog("IntelPRO100EISA: failed to add irq\n");
        [self free];
        return nil;
    }

    /* Initialize flags */
    *(unsigned char *)(((char *)self) + 400) = 0;   /* Promiscuous mode off */
    *(unsigned char *)(((char *)self) + 0x191) = 0; /* Multicast not configured */
    *(unsigned char *)(((char *)self) + 0x192) = 0;
    *(unsigned char *)(((char *)self) + 0x193) = 0; /* Multicast setup not complete */
    *(unsigned char *)(((char *)self) + 500) = 0;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Perform cold initialization */
    coldInitResult = [self coldInit];
    if (!coldInitResult) {
        return nil;
    }

    /* Reset and enable with enable=NO (just reset, don't enable interrupts yet) */
    resetResult = [self resetAndEnable:NO];
    if (!resetResult) {
        return nil;
    }

    /* Determine speed string */
    if (*(unsigned int *)(((char *)self) + 0x1F8) == 0) {
        speedStr = "10";
    } else {
        speedStr = "100";
    }

    /* Get slot number (ioBase >> 12) */
    slotNumber = ioBase >> 12;

    /* Log device information */
    driverName = [[self name] cString];
    IOLog("%s: Intel EtherExpress PRO/100 slot %d irq %d at %sMbits/s\n",
          driverName, slotNumber, cardIrq, speedStr);

    /* Attach to network with station address */
    networkInterface = [super attachToNetworkWithAddress:
        *(enet_addr_t *)(((char *)self) + 0x17C)];

    /* Store network interface */
    *(id *)(((char *)self) + 0x184) = networkInterface;

    return self;
}

/*
 * Clear IRQ latch (EISA-specific)
 * Clears the interrupt latch on EISA cards
 *
 * EISA I/O ports:
 *   ioBase + 0x430: Control register
 *   ioBase + 0xc88: PLX chip register
 */
- (void)clearIrqLatch
{
    unsigned short port;
    unsigned char value;

    if (!ioBase) {
        return;
    }

    /* Read from control register at ioBase + 0x430 */
    port = ioBase + 0x430;
    value = inb(port);

    /* Set bit 4 (0x10) */
    value |= 0x10;
    outb(port, value);

    /* Read from PLX register at ioBase + 0xc88 */
    port = ioBase + 0xc88;
    value = inb(port);

    /* Clear bit 4 (0xef = ~0x10) */
    value &= 0xEF;
    outb(port, value);
}

/*
 * Enable adapter interrupts (EISA-specific)
 * Clears bit 5 in the control register to enable interrupts
 *
 * EISA I/O ports:
 *   ioBase + 0x430: Control register
 */
- (void)enableAdapterInterrupts
{
    unsigned short port;
    unsigned char value;

    if (!ioBase) {
        return;
    }

    /* Read from control register at ioBase + 0x430 */
    port = ioBase + 0x430;
    value = inb(port);

    /* Clear bit 5 (0xdf = ~0x20) to enable interrupts */
    value &= 0xDF;
    outb(port, value);
}

/*
 * Disable adapter interrupts (EISA-specific)
 * Sets bit 5 in the control register to disable interrupts
 *
 * EISA I/O ports:
 *   ioBase + 0x430: Control register
 */
- (void)disableAdapterInterrupts
{
    unsigned short port;
    unsigned char value;

    if (!ioBase) {
        return;
    }

    /* Read from control register at ioBase + 0x430 */
    port = ioBase + 0x430;
    value = inb(port);

    /* Set bit 5 (0x20) to disable interrupts */
    value |= 0x20;
    outb(port, value);
}

/*
 * Send channel attention (EISA-specific)
 * Writes 0 to the I/O base to trigger channel attention
 */
- (void)sendChannelAttention
{
    if (!ioBase) {
        return;
    }

    /* Write 0 to ioBase to trigger channel attention */
    outb(ioBase, 0);
}

/*
 * Send port command (EISA-specific)
 * Writes a port command to the 82556
 *
 * param cmd: Command (bits 0-3)
 * param arg: Argument (bits 4-31)
 *
 * EISA I/O ports:
 *   ioBase + 8: Port register
 */
- (int)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg
{
    unsigned int value;

    if (!ioBase) {
        return -1;
    }

    /* Combine command and argument: (arg & 0xFFFFFFF0) | (cmd & 0xF) */
    value = (arg & 0xFFFFFFF0) | (cmd & 0x0F);

    /* Write to port register at ioBase + 8 */
    outl(ioBase + 8, value);

    return 0;
}

/*
 * Get Ethernet address (EISA-specific)
 * Reads the MAC address from EISA card ROM
 *
 * EISA I/O ports:
 *   ioBase + 0xc90 to ioBase + 0xc95: MAC address bytes
 *
 * Instance variables:
 *   +0x17C: Station address (6 bytes)
 */
- (BOOL)getEthernetAddress
{
    int i;
    unsigned short port;
    unsigned char byte;

    if (!ioBase) {
        return NO;
    }

    /* Read 6 bytes of MAC address from ioBase + 0xc90 */
    for (i = 0; i < 6; i++) {
        port = ioBase + 0xc90 + i;
        byte = inb(port);

        /* Store at offset 0x17C + i */
        *(unsigned char *)(((char *)self) + 0x17C + i) = byte;
    }

    return YES;
}

/*
 * Lock DBRT (EISA-specific)
 * Dynamic Bus Release Throttle lock sequence
 *
 * EISA I/O ports:
 *   ioBase + 0xc89: PLX control register
 */
- (BOOL)lockDBRT
{
    unsigned short port;
    unsigned char value;

    if (!ioBase) {
        return YES;
    }

    /* First sequence */
    port = ioBase + 0xc89;
    value = inb(port);
    IOSleep(10);  /* Sleep 10ms */

    /* Clear bit 2, set bit 1 */
    value = (value & 0xFB) | 0x02;
    outb(port, value);

    IOSleep(50);  /* Sleep 50ms (0x32) */

    /* Second sequence */
    port = ioBase + 0xc89;
    value = inb(port);
    IOSleep(10);  /* Sleep 10ms */

    /* Clear bit 1, set bit 2 */
    value = (value & 0xFD) | 0x04;
    outb(port, value);

    IOSleep(10);  /* Sleep 10ms */

    return YES;
}

/*
 * Initialize PLX chip (EISA-specific)
 * Configures the PLX PCI-to-EISA bridge chip
 *
 * EISA I/O ports:
 *   ioBase + 0xc88: PLX control register 1
 *   ioBase + 0xc89: PLX control register 2
 *   ioBase + 0xc8a: PLX status register
 *   ioBase + 0xc8f: PLX reset/control register
 */
- (void)initPLXchip
{
    unsigned short port;
    unsigned char value;

    if (!ioBase) {
        return;
    }

    /* Configure register at 0xc88 */
    port = ioBase + 0xc88;
    value = inb(port);

    /* Clear bit 3 if set */
    if (value & 0x08) {
        value &= 0xF7;
    }

    /* Set bit 6 if clear */
    if ((value & 0x40) == 0) {
        value |= 0x40;
    }

    /* Set bit 7 if clear */
    if ((char)value >= 0) {  /* Check sign bit */
        value |= 0x80;
    }

    /* Clear bit 5 if set */
    if (value & 0x20) {
        value &= 0xDF;
    }

    outb(port, value);

    /* Configure register at 0xc89 */
    port = ioBase + 0xc89;
    value = inb(port);

    /* Set bit 0 if clear */
    if ((value & 0x01) == 0) {
        value |= 0x01;
    }

    /* Clear bit 3 */
    value &= 0xF7;

    /* Clear bit 4 if set */
    if (value & 0x10) {
        value &= 0xE7;
    }

    /* Set bit 2 */
    value |= 0x04;

    outb(port, value);

    /* Check and handle status at 0xc8a */
    port = ioBase + 0xc8a;
    value = inb(port);

    /* If bit 1 is set, write back */
    if (value & 0x02) {
        outb(port, value);
    }

    /* Configure register at 0xc8f */
    port = ioBase + 0xc8f;
    value = inb(port);

    /* Set bit 7 if clear */
    if ((char)value >= 0) {  /* Check sign bit */
        value |= 0x80;
    }

    /* Clear bits 6 and 2 (0xbb = ~0x44) */
    value &= 0xBB;

    outb(port, value);
}

/*
 * Reset PLX chip (EISA-specific)
 * Performs a hardware reset of the PLX bridge chip
 *
 * EISA I/O ports:
 *   ioBase + 0xc8f: PLX reset/control register
 */
- (void)resetPLXchip
{
    unsigned short port;
    unsigned char value;

    if (!ioBase) {
        return;
    }

    /* Set reset bit */
    port = ioBase + 0xc8f;
    value = inb(port);

    /* Set bit 1 (reset) */
    value |= 0x02;
    outb(port, value);

    /* Wait 50ms for reset */
    IOSleep(50);  /* 0x32 */

    /* Clear reset bit */
    port = ioBase + 0xc8f;
    value = inb(port);

    /* Clear bit 1 (release reset) */
    value &= 0xFD;
    outb(port, value);
}

/*
 * Interrupt occurred (EISA-specific)
 * Handles interrupts for EISA cards with proper masking and acknowledgment
 *
 * EISA I/O ports:
 *   ioBase + 0x430: Control register (interrupt enable/disable)
 *
 * Instance variables:
 *   +0x1B8: SCB base pointer
 */
- (void)interruptOccurred
{
    unsigned short port;
    unsigned char value;
    unsigned short status;
    unsigned short statusBits;
    BOOL result;

    if (!ioBase) {
        return;
    }

    /* Disable interrupts at EISA level (set bit 5) */
    port = ioBase + 0x430;
    value = inb(port);
    value |= 0x20;
    outb(port, value);

    /* Read status from SCB */
    status = *(unsigned short *)*(void **)(((char *)self) + 0x1B8);

    /* Acknowledge all interrupts */
    [self acknowledgeInterrupts:status];

    /* Extract status bits 12-15 (upper nibble shifted right 12) */
    statusBits = (status >> 12) & 0x0F;

    /* Check for receive interrupts (bits 12 and 14 = 0x5) */
    if ((statusBits & 0x05) != 0) {
        /* Call receive interrupt handler with bit 12 status */
        result = [self receiveInterruptOccurred:(statusBits & 0x01)];
        if (!result) {
            return;
        }
    }

    /* Check for transmit interrupts (bits 13 and 15 = 0xA) */
    if ((statusBits & 0x0A) != 0) {
        /* Call transmit interrupt handler */
        result = [self transmitInterruptOccurred];
        if (!result) {
            return;
        }
    }

    /* Clear EISA IRQ latch */
    [self clearIrqLatch];

    /* Re-enable interrupts at EISA level (clear bit 5) */
    port = ioBase + 0x430;
    value = inb(port);
    value &= 0xDF;
    outb(port, value);
}

@end
