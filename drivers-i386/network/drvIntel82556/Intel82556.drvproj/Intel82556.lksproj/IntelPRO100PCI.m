/*
 * IntelPRO100PCI.m
 * Intel EtherExpress PRO/100 Network Driver - PCI Bus Variant
 */

#import "Intel82556.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/IODevice.h>

/* PCI Vendor and Device IDs */
#define PCI_VENDOR_INTEL        0x8086
#define PCI_DEVICE_82556        0x1229

@implementation IntelPRO100PCI

/*
 * Probe method for PCI bus - Called during driver discovery
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    IntelPRO100PCI *driver;
    unsigned char device, function, bus;
    unsigned char configSpace[256];
    unsigned int commandReg;
    unsigned int baseAddressReg;
    unsigned char irqLine;
    unsigned short memCommand;
    unsigned int portRange[4];
    unsigned int irqLevel;
    int result;
    const char *driverName;

    /* Get PCI device location */
    result = [deviceDescription getPCIdevice:&device function:&function bus:&bus];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: unsupported PCI hardware.\n", driverName);
        return NO;
    }

    driverName = [[self name] cString];
    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", driverName, device, function, bus);

    /* Get PCI configuration space */
    result = [self getPCIConfigSpace:configSpace withDeviceDescription:deviceDescription];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              driverName);
        return NO;
    }

    /* Get config data at register 4 (command register) */
    result = [self getPCIConfigData:&commandReg atRegister:4 withDeviceDescription:deviceDescription];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              driverName);
        return NO;
    }

    /* Enable bus master (bit 2) */
    commandReg |= 0x04;
    result = [self setPCIConfigData:commandReg atRegister:4 withDeviceDescription:deviceDescription];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Failed PCI configuration space access - aborting\n", driverName);
        return NO;
    }

    /* Get Base Address Register (BAR) - at config offset 0x10 (but accessed via local_f0) */
    baseAddressReg = *(unsigned int *)&configSpace[0x10];

    /* Set port range - mask off lower bits to get base address */
    portRange[0] = baseAddressReg & 0xFFFFFFFC;
    portRange[1] = 0x40;  /* 64 bytes */

    result = [deviceDescription setPortRangeList:portRange num:1];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Unable to reserve port range 0x%x-0x%x - Aborting\n",
              driverName, portRange[0], portRange[0] + 0x3F);
        return NO;
    }

    /* Get IRQ line from config space offset 0x3C */
    irqLine = configSpace[0x3C];
    irqLevel = (unsigned int)irqLine;

    /* Validate IRQ level (must be between 2 and 14) */
    if ((irqLevel - 2) > 0xD) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid IRQ level (%d) assigned by PCI BIOS\n", driverName, irqLevel);
        return NO;
    }

    result = [deviceDescription setInterruptList:&irqLevel num:1];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Unable to reserve IRQ %d - Aborting\n", driverName, irqLevel);
        return NO;
    }

    /* Allocate driver instance */
    driver = [[self alloc] init];
    if (driver == nil) {
        driverName = [[self name] cString];
        IOLog("%s: Failed to alloc instance\n", driverName);
        return NO;
    }

    /* Store memory command and base address register values */
    /* Offset 0x17C = memCommand (from configSpace[0xC4]) */
    /* Offset 0x180 = baseAddressReg (from configSpace[0xC0]) */
    memCommand = *(unsigned short *)&configSpace[0xC4];
    driver->memBase = (void *)*(unsigned int *)&configSpace[0xC4];
    *(unsigned short *)((char *)driver + 0x180) = *(unsigned short *)&configSpace[0xC0];

    /* Initialize the driver */
    if ([driver initFromDeviceDescription:deviceDescription] != nil) {
        return YES;
    }

    [driver free];
    return NO;
}

/*
 * Initialize PCI variant from device description
 *
 * Instance variables:
 *   +0x174: I/O base address (ioBase)
 *   +0x178: IRQ number
 *   +0x17C: Station address (MAC address - 6 bytes)
 *   +0x184: Network interface object
 *   +0x190: Promiscuous mode flag (offset 400)
 *   +0x191-0x193: Multicast flags
 *   +0x1F4: Flag (offset 500)
 *   +0x1F8: Speed flag (0=10Mbps, 1=100Mbps)
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IORange *portRange;
    unsigned int irqValue;
    BOOL coldInitResult;
    BOOL resetResult;
    const char *speedStr;
    const char *driverName;
    id networkInterface;

    /* Get port range from device description */
    portRange = [deviceDescription portRangeList];
    if (portRange) {
        ioBase = portRange->start;
        *(unsigned short *)(((char *)self) + 0x174) = portRange->start;
    }

    /* Get IRQ from device description */
    irqValue = [deviceDescription interrupt];
    *(unsigned int *)(((char *)self) + 0x178) = irqValue;

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

    /* Log device information */
    driverName = [[self name] cString];
    IOLog("%s: Intel EtherExpress PRO/100 PCI port 0x%x irq %d at %sMbits/s\n",
          driverName, ioBase, irqValue, speedStr);

    /* Attach to network with station address */
    networkInterface = [super attachToNetworkWithAddress:
        *(enet_addr_t *)(((char *)self) + 0x17C)];

    /* Store network interface */
    *(id *)(((char *)self) + 0x184) = networkInterface;

    return self;
}

/*
 * Clear IRQ latch (PCI-specific)
 */
- (void)clearIrqLatch
{
    IOLog("IntelPRO100PCI: clearIrqLatch\n");
    /* PCI devices typically don't need IRQ latch clearing */
}

/*
 * Enable adapter interrupts (PCI-specific)
 */
- (void)enableAdapterInterrupts
{
    IOLog("IntelPRO100PCI: enableAdapterInterrupts\n");

    /* Call base class method */
    [super enableAdapterInterrupts];

    /* PCI-specific interrupt enable code */
    if (ioBase) {
        outb(ioBase + CSR_INTERRUPT, 0);
    }
}

/*
 * Disable adapter interrupts (PCI-specific)
 */
- (void)disableAdapterInterrupts
{
    IOLog("IntelPRO100PCI: disableAdapterInterrupts\n");

    /* PCI-specific interrupt disable code */
    if (ioBase) {
        outb(ioBase + CSR_INTERRUPT, SCB_INT_M);
    }

    /* Call base class method */
    [super disableAdapterInterrupts];
}

/*
 * Send channel attention (PCI-specific)
 * Writes 0 to ioBase + 0x20
 */
- (void)sendChannelAttention
{
    if (!ioBase) {
        return;
    }

    /* Write 0 to ioBase + 0x20 to trigger channel attention */
    outb(ioBase + 0x20, 0);
}

/*
 * Send port command (PCI-specific)
 * Writes a port command to the 82556
 *
 * param cmd: Command (bits 0-3)
 * param arg: Argument (bits 4-31)
 *
 * PCI I/O ports:
 *   ioBase + 0x24: Port register
 */
- (int)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg
{
    unsigned int value;

    if (!ioBase) {
        return -1;
    }

    /* Combine command and argument: (arg & 0xFFFFFFF0) | (cmd & 0xF) */
    value = (arg & 0xFFFFFFF0) | (cmd & 0x0F);

    /* Write to port register at ioBase + 0x24 */
    outl(ioBase + 0x24, value);

    return 0;
}

/*
 * Lock DBRT (PCI-specific)
 * Dynamic Bus Release Throttle lock sequence
 *
 * PCI I/O ports:
 *   ioBase + 4: Control register
 */
- (BOOL)lockDBRT
{
    unsigned short port;
    unsigned char value;

    if (!ioBase) {
        return YES;
    }

    /* First sequence */
    port = ioBase + 4;
    value = inb(port);
    IOSleep(10);  /* Sleep 10ms */

    /* Clear bit 2, set bit 1 */
    value = (value & 0xFB) | 0x02;
    outb(port, value);

    IOSleep(50);  /* Sleep 50ms (0x32) */

    /* Second sequence */
    port = ioBase + 4;
    value = inb(port);
    IOSleep(10);  /* Sleep 10ms */

    /* Clear bit 1, set bit 2 */
    value = (value & 0xFD) | 0x04;
    outb(port, value);

    IOSleep(10);  /* Sleep 10ms */

    return YES;
}

/*
 * Initialize PLX chip (PCI-specific)
 * Configures control registers
 *
 * PCI I/O ports:
 *   ioBase: Base control register
 *   ioBase + 4: Secondary control register
 */
- (void)initPLXchip
{
    unsigned short port;
    unsigned char value;

    if (!ioBase) {
        return;
    }

    /* Configure base register at ioBase */
    value = inb(ioBase);

    /* Clear bit 8 (0xfffffeff) and set bits 3 and 5 (0x28) */
    /* Note: This is a byte operation, so we only care about lower byte */
    value = (value & 0xEF) | 0x28;
    outb(ioBase, value);

    /* Configure register at ioBase + 4 */
    port = ioBase + 4;
    value = inb(port);

    /* Set value to 0xF1 (bits 0, 4, 5, 6, 7) */
    outb(port, 0xF1);
}

/*
 * Reset PLX chip (PCI-specific)
 * Performs a hardware reset sequence
 *
 * PCI I/O ports:
 *   ioBase + 0x10: Reset control register
 */
- (void)resetPLXchip
{
    unsigned short port;
    unsigned char value;

    if (!ioBase) {
        return;
    }

    /* Set reset bit */
    port = ioBase + 0x10;
    value = inb(port);

    /* Set bit 12 (0x1000) - but this is a byte operation, so bit 4 of high byte */
    /* Since we're doing byte I/O, we need to set bit 4 in the byte at offset 0x11 */
    /* Wait, the decompiled code shows in/out on a short port, but applies a mask 0x1000 */
    /* Let me re-read: it's `in(sVar2)` where sVar2 is ioBase + 0x10, and the result is uint */
    /* Then `out(sVar2, uVar1 | 0x1000)` - so this is a word (16-bit) or dword operation */
    /* Let me use word operations */

    /* Read word from ioBase + 0x10 */
    unsigned short wordValue = inw(port);

    /* Set bit 12 (0x1000) */
    wordValue |= 0x1000;
    outw(port, wordValue);

    /* Wait 50ms for reset */
    IOSleep(50);  /* 0x32 */

    /* Clear reset bit */
    port = ioBase + 0x10;
    wordValue = inw(port);

    /* Clear bit 12 (& 0xFFFFEFFF) */
    wordValue &= 0xEFFF;
    outw(port, wordValue);
}

/*
 * Interrupt occurred (PCI-specific)
 * Handles interrupts with proper masking and acknowledgment
 *
 * Instance variables:
 *   +0x1B8: SCB base pointer
 */
- (void)interruptOccurred
{
    unsigned short status;
    unsigned short statusBits;
    BOOL result;

    if (!ioBase) {
        return;
    }

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

    /* Clear IRQ latch */
    [self clearIrqLatch];

    /* Re-enable interrupts */
    [self enableAllInterrupts];
}

@end
