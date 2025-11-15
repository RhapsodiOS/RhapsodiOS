/*
 * Intel82595.m
 * Intel 82595 Ethernet Controller Base Driver
 */

#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IODirectDevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <objc/Object.h>

@interface Intel82595 : IOEthernetDriver
{
    unsigned int ioBase;
    unsigned int irqLevel;
    unsigned int memoryRegion;
    BOOL onboardMemory;
    void *rxBuffer;
    void *txBuffer;
    unsigned char chipVersion;
    unsigned char currentBank;
    unsigned short txMemoryStart;
    unsigned short txMemoryEnd;
    unsigned short rxMemoryStart;
    unsigned short rxMemoryEnd;
    unsigned short rxReadPtr;
    unsigned short rxStopPtr;
    BOOL multicastEnabled;
    BOOL mcSetupComplete;
    BOOL promiscuousMode;
    BOOL transmitActive;
    id netif;
    id transmitQueue;
    unsigned char romAddress[6];
}

+ (BOOL)probeIDRegisterAt:(unsigned int)address;

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)coldInit;
- (void)resetChip;
- (void)initializeChip;
- (BOOL)onboardMemoryPresent;
- (void)description;
- (void)busConfig;
- (void)connectorConfig;
- (BOOL)rxInit;
- (BOOL)txInit;

- (void)enableAllInterrupts;
- (void)disableAllInterrupts;
- (void)enablePromiscuousMode;
- (void)disablePromiscuousMode;

- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)transmit:(void *)packet;
- (void)sendPacket:(void *)pkt length:(unsigned int)len;
- (void)receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout;

- (void)addMulticastAddress:(void *)addr;
- (void)removeMulticastAddress:(void *)addr;

@end

// Private category
@interface Intel82595(Private)
- (unsigned int)_memoryRegion:(unsigned int)region;
- (BOOL)_onboardMemoryAvailable;
- (void *)_allocateOnboardMemory:(unsigned int)size;
- (void)_mcSetup;
- (void)_receiveInterruptOccurred;
- (void)_transmitInterruptOccurred;
@end

/* Chip stepping descriptions indexed by chipVersion (0-2) */
static const char *i82595SteppingDesc[3] = {
    "Intel 82595A-2 stepping",
    "Intel 82595TX stepping",
    "Intel 82595TX stepping"
};

@implementation Intel82595

/*
 * Probe ID register at specified address
 */
+ (BOOL)probeIDRegisterAt:(unsigned int)address
{
    unsigned char idReg1, idReg2;
    unsigned char expectedBank;
    int i;

    /* Write 0 to command register to reset bank */
    outb(address, 0);
    IODelay(100);

    /* Read ID register (port + 2) */
    idReg1 = inb(address + 2);

    /* Expected bank is bits 7-6 of ID register, incremented */
    expectedBank = ((idReg1 >> 6) + 1) & 0x03;

    /* Verify ID register stability and bank cycling */
    for (i = 0; i < 3; i++) {
        idReg2 = inb(address + 2);

        /* Check if chip ID (bits 5-2) matches */
        if (((idReg2 >> 2) & 0x0F) != ((idReg1 >> 2) & 0x0F)) {
            return NO;
        }

        /* Check if bank (bits 7-6) incremented correctly */
        if ((idReg2 >> 6) != expectedBank) {
            return NO;
        }

        /* Calculate next expected bank */
        expectedBank = (expectedBank + 1) & 0x03;
    }

    return YES;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IORange *portRange;
    unsigned char version;

    /* Call superclass */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Get I/O port range */
    portRange = [deviceDescription portRangeList:0];
    ioBase = portRange->start;

    /* Get IRQ */
    irqLevel = [deviceDescription interrupt];

    /* Initialize flags */
    promiscuousMode = NO;
    multicastEnabled = NO;
    mcSetupComplete = NO;
    transmitActive = NO;

    /* Reset chip */
    if (![self resetChip]) {
        [self free];
        return nil;
    }

    /* Read chip version from bank 2, register 10, bits 7-5 */
    if (currentBank != 0x02) {
        outb(ioBase, 0x80);
        IODelay(1);
        currentBank = 0x02;
    }
    version = inb(ioBase + 10);
    chipVersion = version >> 5;

    /* Validate version */
    if (chipVersion > 2) {
        IOLog("%s: i82595 version: %d.\n", [self name], chipVersion);
        chipVersion = 2;  /* Treat unknown versions as version 2 */
    }

    /* Perform cold initialization */
    if (![self coldInit]) {
        [self free];
        return nil;
    }

    /* Reset and enable hardware */
    if (![self resetAndEnable:YES]) {
        [self free];
        return nil;
    }

    /* Log initialization */
    IOLog("%s at port 0x%x irq %d\n", [self description], ioBase, irqLevel);

    /* Create transmit queue (max 32 packets) */
    transmitQueue = [[objc_getClass("IOQueue") alloc] initWithMaxCount:32];

    /* Attach to network stack */
    netif = [super attachToNetworkWithAddress:romAddress];

    return self;
}

/*
 * Free resources
 */
- free
{
    /* Clear timeout */
    [self clearTimeout];

    /* Disable all interrupts */
    [self disableAllInterrupts];

    /* Reset chip */
    [self resetChip];

    /* Free transmit queue */
    if (transmitQueue != nil) {
        [transmitQueue free];
    }

    /* Unregister device */
    [self unregisterDevice];

    return [super free];
}

/*
 * Reset and enable/disable hardware
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    unsigned char status;

    /* Clear timeout */
    [self clearTimeout];

    /* Disable all interrupts */
    [self disableAllInterrupts];

    /* Reset chip */
    if (![self resetChip]) {
        return NO;
    }

    /* Clear transmit active flag */
    transmitActive = NO;

    /* Force bank selection to be re-initialized */
    currentBank = 0x03;
    outb(ioBase, 0x00);
    IODelay(1);
    currentBank = 0x00;

    /* Initialize chip */
    if (![self initializeChip]) {
        return NO;
    }

    /* Setup multicast filter */
    if (![self _mcSetup]) {
        return NO;
    }

    /* Initialize receive */
    if (![self rxInit]) {
        return NO;
    }

    /* Initialize transmit */
    if (![self txInit]) {
        return NO;
    }

    if (enable) {
        /* Enable interrupts */
        if (![self enableAllInterrupts]) {
            [self setRunning:NO];
            return NO;
        }

        /* Select bank 0 */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }

        /* Clear execution interrupt if set */
        status = inb(ioBase + 1);
        if (status & 0x08) {
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            outb(ioBase + 1, 0x08);
            IODelay(1);
            IOSleep(100);
        }

        /* Start receive (command 0x08) */
        status = inb(ioBase);
        outb(ioBase, (status & 0xE0) | 0x08);
        IODelay(1);
    }

    /* Set running state */
    [self setRunning:enable];

    return YES;
}

/*
 * Cold initialization
 */
- (BOOL)coldInit
{
    /* Base cold init - subclasses should override */
    return YES;
}

/*
 * Reset chip
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

    /* Clear execution interrupt if set */
    status = inb(ioBase + 1);
    if (status & 0x08) {
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

    /* Force bank selection to be re-initialized */
    currentBank = 0x03;
    outb(ioBase, 0x00);
    IODelay(1);
    currentBank = 0x00;

    return YES;
}

/*
 * Initialize chip
 */
- (BOOL)initializeChip
{
    unsigned char intMask, config, rxMode;
    int i, timeout;
    BOOL success;

    /* Select bank 0 and save interrupt mask */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    intMask = inb(ioBase + 3);

    /* Disable execution interrupt */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outb(ioBase + 3, (intMask & 0xD8) | 0x08);
    IODelay(1);

    /* Configure bank 1, register 2 */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }
    config = inb(ioBase + 2);
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }
    outb(ioBase + 2, (config & 0x8F) | 0x80);
    IODelay(1);

    /* Configure bus */
    if (![self busConfig]) {
        return NO;
    }

    /* Write MAC address to bank 2, registers 4-9 */
    for (i = 0; i < 6; i++) {
        if (currentBank != 0x02) {
            outb(ioBase, 0x80);
            IODelay(1);
            currentBank = 0x02;
        }
        outb(ioBase + 4 + i, romAddress[i]);
        IODelay(1);
    }

    /* Wait for chip ready */
    timeout = 0;
    success = NO;
    while (timeout < 100) {
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        config = inb(ioBase + 1);
        if ((config & 0x30) == 0) {
            success = YES;
            break;
        }
        IODelay(1000);
        timeout++;
    }

    if (!success) {
        return NO;
    }

    /* Configure receive mode in bank 2, register 2 */
    if (currentBank != 0x02) {
        outb(ioBase, 0x80);
        IODelay(1);
        currentBank = 0x02;
    }
    rxMode = inb(ioBase + 2);

    /* Set mode bits based on chip version */
    if (chipVersion == 2) {
        rxMode &= 0xF4;  /* Version 2 specific */
    } else {
        rxMode &= 0xFC;  /* Earlier versions */
    }

    /* Set receive mode with promiscuous bit */
    if (currentBank != 0x02) {
        outb(ioBase, 0x80);
        IODelay(1);
        currentBank = 0x02;
    }
    outb(ioBase + 2, (rxMode & 0x1F) | (promiscuousMode & 0x01) | 0x14);
    IODelay(1);

    /* Wait for chip ready */
    timeout = 0;
    success = NO;
    while (timeout < 100) {
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        config = inb(ioBase + 1);
        if ((config & 0x30) == 0) {
            success = YES;
            break;
        }
        IODelay(1000);
        timeout++;
    }

    if (!success) {
        return NO;
    }

    /* Configure connector */
    if (![self connectorConfig]) {
        return NO;
    }

    /* Wait for chip ready (longer timeout) */
    IODelay(10000);
    timeout = 0;
    success = NO;
    while (timeout < 1000) {
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        config = inb(ioBase + 1);
        if ((config & 0x30) == 0) {
            success = YES;
            break;
        }
        IODelay(1000);
        timeout++;
    }

    if (!success) {
        return NO;
    }

    /* Clear execution interrupt if set */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    config = inb(ioBase + 1);
    if (config & 0x08) {
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outb(ioBase + 1, 0x08);
        IODelay(1);
        IOSleep(100);
    }

    /* Start receive and transmit (command 0x1E) */
    config = inb(ioBase);
    outb(ioBase, (config & 0xE0) | 0x1E);
    IODelay(1);
    IOSleep(100);

    /* Reset memory allocation pointer */
    txMemoryEnd = 0;

    return YES;
}

/*
 * Get size of onboard memory
 */
- (unsigned int)onboardMemoryPresent
{
    /* Intel 82595 has 64KB of onboard RAM */
    return 0x10000;
}

/*
 * Get description
 */
- (const char *)description
{
    return "Intel82595-based Ethernet Adapter";
}

/*
 * Get bus configuration
 */
- (BOOL)busConfig
{
    return YES;
}

/*
 * Get connector configuration
 */
- (BOOL)connectorConfig
{
    /* Select bank 2 */
    if (currentBank != 0x02) {
        outb(ioBase, 0x80);
        IODelay(1);
        currentBank = 0x02;
    }

    /* Set connector configuration */
    outb(ioBase + 3, 0x04);
    IODelay(1);

    return YES;
}

/*
 * Initialize receive subsystem
 */
- (BOOL)rxInit
{
    unsigned int memorySize;
    unsigned short rxSize;
    unsigned char config;

    /* Get onboard memory size */
    memorySize = [self onboardMemoryPresent];

    /* Determine RX buffer size based on memory */
    if (memorySize < 0x10000) {  /* Less than 64KB */
        if (memorySize < 0x8000) {  /* Less than 32KB */
            IOLog("%s: unsupported memory configuration\n", [self name]);
            return NO;
        }
        rxSize = 0x6400;  /* 25KB for 32KB memory */
    } else {
        rxSize = 0xE000;  /* 56KB for 64KB memory */
    }

    /* Select bank 2 */
    if (currentBank != 0x02) {
        outb(ioBase, 0x80);
        IODelay(1);
        currentBank = 0x02;
    }

    /* Read and set receive control register */
    config = inb(ioBase + 1);
    if (currentBank != 0x02) {
        outb(ioBase, 0x80);
        IODelay(1);
        currentBank = 0x02;
    }
    outb(ioBase + 1, config | 0x80);
    IODelay(1);

    /* Clear error counter */
    if (currentBank != 0x02) {
        outb(ioBase, 0x80);
        IODelay(1);
        currentBank = 0x02;
    }
    outb(ioBase + 0x0B, 0);
    IODelay(1);

    /* For chip version 2, clear additional registers */
    if (chipVersion == 2) {
        if (currentBank != 0x01) {
            outb(ioBase, 0x40);
            IODelay(1);
            currentBank = 0x01;
        }
        outb(ioBase + 7, 0);
        IODelay(1);

        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outb(ioBase + 8, 0);
        IODelay(1);
    }

    /* Allocate receive buffer memory */
    rxMemoryStart = [self _allocateOnboardMemory:rxSize];
    rxMemoryEnd = rxMemoryStart + rxSize;
    rxReadPtr = rxMemoryStart;

    /* Set RX start register (bank 1, register 8) */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }
    outb(ioBase + 8, rxMemoryStart >> 8);
    IODelay(1);

    /* Set RX stop register (bank 1, register 9) */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }
    outb(ioBase + 9, (rxMemoryEnd - 0x100) >> 8);
    IODelay(1);

    /* Set RX stop pointer (bank 0, register 6) */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outw(ioBase + 6, rxMemoryEnd - 1);
    IODelay(1);

    /* Set RX read pointer (bank 0, register 4) */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outw(ioBase + 4, rxMemoryStart);
    IODelay(1);

    return YES;
}

/*
 * Initialize transmit subsystem
 */
- (BOOL)txInit
{
    unsigned int memorySize;
    unsigned short txSize;
    unsigned char bankReg;

    /* Get total onboard memory */
    memorySize = [self onboardMemoryPresent];

    /* Determine TX buffer size based on memory */
    if (memorySize < 0x10000) {
        if (memorySize < 0x8000) {
            IOLog("%s: unsupported memory configuration\n", [self name]);
            return NO;
        }
        /* 32KB memory: allocate 5KB for TX */
        txSize = 0x1400;
    } else {
        /* 64KB memory: allocate 7KB for TX */
        txSize = 0x1C00;
    }

    /* Select bank 2 and read register 1 */
    if (currentBank != 0x02) {
        outb(ioBase, 0x80);
        IODelay(1);
        currentBank = 0x02;
    }
    bankReg = inb(ioBase + 1);

    /* If chip version is 2, clear bit 0 */
    if (chipVersion == 0x02) {
        bankReg &= 0xFE;
    }

    /* Clear bit 5 (TX chain disable) */
    if (currentBank != 0x02) {
        outb(ioBase, 0x80);
        IODelay(1);
        currentBank = 0x02;
    }
    outb(ioBase + 1, bankReg & 0xDF);
    IODelay(1);

    /* Allocate TX memory */
    txMemoryStart = [self _allocateOnboardMemory:txSize];
    txMemoryEnd = txMemoryStart + txSize;

    /* Select bank 1 and configure TX start register (high byte only) */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }
    outb(ioBase + 10, (unsigned char)(txMemoryStart >> 8));
    IODelay(1);

    /* Configure TX end register (high byte of end - 0x100) */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }
    outb(ioBase + 11, (unsigned char)((txMemoryEnd - 0x100) >> 8));
    IODelay(1);

    return YES;
}

/*
 * Enable all interrupts
 */
- (BOOL)enableAllInterrupts
{
    unsigned char status;

    /* Select bank 1 */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }

    /* Read interrupt mask register */
    status = inb(ioBase + 1);

    /* Enable interrupts by setting bit 7 */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }
    outb(ioBase + 1, status | 0x80);
    IODelay(1);

    /* Call superclass */
    return [super enableAllInterrupts];
}

/*
 * Disable all interrupts
 */
- (void)disableAllInterrupts
{
    unsigned char status;

    /* Call superclass */
    [super disableAllInterrupts];

    /* Select bank 1 */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }

    /* Read interrupt mask register */
    status = inb(ioBase + 1);

    /* Disable interrupts by clearing bit 7 */
    if (currentBank != 0x01) {
        outb(ioBase, 0x40);
        IODelay(1);
        currentBank = 0x01;
    }
    outb(ioBase + 1, status & 0x7F);
    IODelay(1);
}

/*
 * Enable promiscuous mode
 */
- (BOOL)enablePromiscuousMode
{
    BOOL wasRunning;

    if (promiscuousMode) {
        /* Already enabled */
        return YES;
    }

    promiscuousMode = YES;

    /* Reset and re-enable if running */
    wasRunning = [self isRunning];
    return [self resetAndEnable:wasRunning];
}

/*
 * Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    BOOL wasRunning;

    if (promiscuousMode) {
        promiscuousMode = NO;

        /* Reset and re-enable if running */
        wasRunning = [self isRunning];
        [self resetAndEnable:wasRunning];
    }
}

/*
 * Handle interrupt
 */
- (void)interruptOccurred
{
    unsigned char status;
    unsigned char errorCount;

    /* Select bank 0 */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }

    /* Read status register */
    status = inb(ioBase + 1);

    /* Loop while there are pending interrupts (bits 0-3) */
    while ((status & 0x0F) != 0) {
        /* Clear interrupt status by writing back */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outb(ioBase + 1, status);
        IODelay(1);

        /* Handle receive interrupt (bit 1) */
        if ((status & 0x02) != 0) {
            if (![self _receiveInterruptOccurred]) {
                return;
            }
        }

        /* Handle transmit interrupt (bit 2) */
        if ((status & 0x04) != 0) {
            if (![self _transmitInterruptOccurred]) {
                return;
            }
        }

        /* Handle frame error interrupt (bit 0) */
        if ((status & 0x01) != 0) {
            /* Select bank 2 to read error counter */
            if (currentBank != 0x02) {
                outb(ioBase, 0x80);
                IODelay(1);
                currentBank = 0x02;
            }

            /* Read error count from register 11 */
            errorCount = inb(ioBase + 0x0B);

            /* Increment network errors */
            [netif incrementInputErrorsBy:errorCount];

            /* Clear error counter */
            if (currentBank != 0x02) {
                outb(ioBase, 0x80);
                IODelay(1);
                currentBank = 0x02;
            }
            outb(ioBase + 0x0B, 0);
            IODelay(1);
        }

        /* Read status again */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        status = inb(ioBase + 1);
    }
}

/*
 * Handle timeout - Called when watchdog timer expires
 */
- (void)timeoutOccurred
{
    void *packet;

    /* If driver is running, try to reset and recover */
    if ([self isRunning]) {
        if ([self resetAndEnable:YES]) {
            /* Dequeue next packet and try to transmit */
            packet = [transmitQueue dequeue];
            if (packet != NULL) {
                [self transmit:packet];
            }
        }
    }

    /* If driver is not running, flush transmit queue */
    if (![self isRunning]) {
        if ([transmitQueue count] != 0) {
            transmitActive = NO;
            while ((packet = [transmitQueue dequeue]) != NULL) {
                nb_free(packet);
            }
        }
    }
}

/*
 * Transmit packet (high-level netbuf transmission)
 */
- (void)transmit:(void *)packet
{
    unsigned char txHeader[8];
    unsigned short *txHeaderPtr;
    unsigned short *packetData;
    unsigned short packetSize;
    unsigned char status;
    unsigned int timeout;
    int i;

    /* If transmit is not active, transmit immediately */
    if (!transmitActive) {
        /* Mark transmit as active */
        transmitActive = YES;

        /* Perform loopback if enabled */
        [self performLoopback:packet];

        /* Build 8-byte TX header */
        bzero(txHeader, 8);
        txHeader[0] = 0x04;  /* TX command */
        packetSize = nb_size(packet);
        *(unsigned short *)&txHeader[6] = packetSize & 0x7FFF;

        /* Select bank 0 */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }

        /* Clear bit 4 of register 3 (disable TX chain) */
        status = inb(ioBase + 3);
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outb(ioBase + 3, status & 0xEF);
        IODelay(1);

        /* Set I/O pointer to TX memory start */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outw(ioBase + 0x0C, txMemoryStart);
        IODelay(1);

        /* Write 8-byte TX header as 4 words */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        txHeaderPtr = (unsigned short *)txHeader;
        for (i = 0; i < 4; i++) {
            outw(ioBase + 0x0E, txHeaderPtr[i]);
            IODelay(1);
        }

        /* Map netbuf to get packet data */
        packetData = (unsigned short *)nb_map(packet);
        packetSize = nb_size(packet);

        /* Write packet data in 16-bit words */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        for (i = 0; i < (int)(packetSize >> 1); i++) {
            outw(ioBase + 0x0E, packetData[i]);
            IODelay(1);
        }

        /* Write final odd byte if length is odd */
        if ((packetSize & 1) != 0) {
            outw(ioBase + 0x0E, packetData[packetSize >> 1]);
            IODelay(1);
        }

        /* Free the netbuf */
        nb_free(packet);

        /* Wait for status bits 0x30 to clear (up to 100ms) */
        timeout = 0;
        do {
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            status = inb(ioBase + 1);
            if ((status & 0x30) == 0) {
                break;
            }
            IODelay(1000);
            timeout++;
        } while (timeout < 100);

        /* Write TX memory start to register 10 */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outw(ioBase + 10, txMemoryStart);
        IODelay(1);

        /* Check for and clear execution interrupt (bit 3) */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        status = inb(ioBase + 1);
        if ((status & 0x08) != 0) {
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            outb(ioBase + 1, 0x08);
            IODelay(1);
            IOSleep(100);
        }

        /* Issue transmit command (0x04) */
        status = inb(ioBase);
        outb(ioBase, (status & 0xE0) | 0x04);
        IODelay(1);

        /* Set watchdog timeout to 3000ms (0xbb8) */
        [self setRelativeTimeout:3000];
    } else {
        /* Transmit is active, queue the packet */
        [transmitQueue enqueue:packet];
    }
}

/*
 * Send packet to hardware
 */
- (void)sendPacket:(void *)pkt length:(unsigned int)len
{
    unsigned char txHeader[8];
    unsigned short *txHeaderPtr;
    unsigned short *packetPtr;
    unsigned char status;
    unsigned int timeout;
    int i;

    /* If transmit is active, wait for TX complete interrupt */
    if (transmitActive) {
        /* Wait for TX interrupt (bit 2) */
        do {
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            status = inb(ioBase + 1);
        } while ((status & 0x04) == 0);

        /* Clear TX interrupt */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outb(ioBase + 1, 0x04);
        IODelay(1);
    }

    /* Ensure minimum packet size of 64 bytes */
    if (len < 0x40) {
        len = 0x40;
    }

    /* Build 8-byte TX header */
    bzero(txHeader, 8);
    txHeader[0] = 0x04;  /* TX command */
    *(unsigned short *)&txHeader[6] = len & 0x7FFF;  /* Length field */

    /* Select bank 0 */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }

    /* Clear bit 4 of register 3 (disable TX chain) */
    status = inb(ioBase + 3);
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outb(ioBase + 3, status & 0xEF);
    IODelay(1);

    /* Set I/O pointer to TX memory start (register 0x0C) */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outw(ioBase + 0x0C, txMemoryStart);
    IODelay(1);

    /* Write 8-byte TX header as 4 words to I/O data port */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    txHeaderPtr = (unsigned short *)txHeader;
    for (i = 0; i < 4; i++) {
        outw(ioBase + 0x0E, txHeaderPtr[i]);
        IODelay(1);
    }

    /* Write packet data in 16-bit words */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    packetPtr = (unsigned short *)pkt;
    for (i = 0; i < (int)(len >> 1); i++) {
        outw(ioBase + 0x0E, packetPtr[i]);
        IODelay(1);
    }

    /* Write final odd byte if length is odd */
    if ((len & 1) != 0) {
        outw(ioBase + 0x0E, ((unsigned char *)pkt)[len - 1]);
        IODelay(1);
    }

    /* Wait for status bits 0x30 to clear (up to 100ms) */
    timeout = 0;
    do {
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        status = inb(ioBase + 1);
        if ((status & 0x30) == 0) {
            break;
        }
        IODelay(1000);  /* 1ms delay */
        timeout++;
    } while (timeout < 100);

    /* Write TX memory start to register 10 */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outw(ioBase + 10, txMemoryStart);
    IODelay(1);

    /* Check for and clear execution interrupt (bit 3) */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    status = inb(ioBase + 1);
    if ((status & 0x08) != 0) {
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outb(ioBase + 1, 0x08);
        IODelay(1);
        IOSleep(100);
    }

    /* Issue transmit command (0x04) */
    status = inb(ioBase);
    outb(ioBase, (status & 0xE0) | 0x04);
    IODelay(1);

    /* If not transmitActive, wait for TX complete */
    if (!transmitActive) {
        /* Wait for TX interrupt (bit 2) */
        do {
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            status = inb(ioBase + 1);
        } while ((status & 0x04) == 0);

        /* Clear TX interrupt */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outb(ioBase + 1, 0x04);
        IODelay(1);
    }
}

/*
 * Receive packet with timeout (polling mode)
 */
- (void)receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout
{
    unsigned short rxStatus[1];
    unsigned short rxHeader[3];
    unsigned char status1, status2;
    unsigned short nextPtr, length;
    unsigned short *packetData;
    unsigned char oldIntMask;
    int timeoutMicros;
    int i;

    /* Convert timeout to microseconds */
    timeoutMicros = timeout * 1000;

    /* Default to 0 length */
    *len = 0;

    /* Select bank 0 and disable execution interrupt */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    oldIntMask = inb(ioBase + 3);
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outb(ioBase + 3, oldIntMask & 0xEF);
    IODelay(1);

    /* Poll for packet with timeout */
    while (1) {
        /* Set receive read pointer */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outw(ioBase + 0x0C, rxReadPtr);
        IODelay(1);

        /* Read receive status word */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        rxStatus[0] = inw(ioBase + 0x0E);

        /* Check if packet available (bit 3) */
        if ((rxStatus[0] & 0x0800) != 0) {
            /* Read packet header */
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            for (i = 0; i < 3; i++) {
                rxHeader[i] = inw(ioBase + 0x0E);
            }

            status1 = rxHeader[0] & 0xFF;
            status2 = (rxHeader[0] >> 8) & 0xFF;
            nextPtr = rxHeader[1];
            length = rxHeader[2];

            /* Check if packet is good and within size limit */
            if ((status2 & 0x20) != 0 && length < 0x5EB) {
                /* Set length */
                *len = length;

                /* Read packet data */
                if (currentBank != 0x00) {
                    outb(ioBase, 0x00);
                    IODelay(1);
                    currentBank = 0x00;
                }

                packetData = (unsigned short *)pkt;
                for (i = 0; i < (length + 1) / 2; i++) {
                    packetData[i] = inw(ioBase + 0x0E);
                }

                /* Read odd byte if needed */
                if (length & 1) {
                    ((unsigned char *)pkt)[length - 1] = inb(ioBase + 0x0E);
                }
            }

            /* Update receive read pointer */
            rxReadPtr = nextPtr;

            /* Update RX stop register */
            if (rxMemoryStart == rxReadPtr) {
                rxStopPtr = rxMemoryEnd;
            } else {
                rxStopPtr = rxReadPtr;
            }

            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            outw(ioBase + 6, rxStopPtr - 1);
            IODelay(1);

            return;
        }

        /* Check timeout */
        if (timeoutMicros < 1) {
            /* Timeout expired */
            *len = 0;
            return;
        }

        /* Delay and decrement timeout */
        IODelay(50);
        timeoutMicros -= 50;
    }
}

/*
 * Add multicast address
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;

    /* Enable multicast mode */
    multicastEnabled = YES;

    /* Setup multicast filter */
    result = [self _mcSetup];
    if (!result) {
        IOLog("%s: add multicast address failed\n", [self name]);
    }
}

/*
 * Remove multicast address
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;

    /* Note: Multicast remains enabled, just reconfigure filter */

    /* Setup multicast filter */
    result = [self _mcSetup];
    if (!result) {
        IOLog("%s: remove multicast address failed\n", [self name]);
    }
}

@end

@implementation Intel82595(Private)

/*
 * Get memory region offset and verify space is available
 */
- (unsigned short)_memoryRegion:(unsigned int)size
{
    unsigned int available;

    /* Check if enough memory is available */
    available = [self _onboardMemoryAvailable];
    if (available < size) {
        IOPanic("Intel82595: onboard memory exhausted");
    }

    return txMemoryEnd;
}

/*
 * Get available onboard memory
 */
- (unsigned int)_onboardMemoryAvailable
{
    int totalMemory;
    unsigned int available;

    /* Get total onboard memory size */
    totalMemory = [self onboardMemoryPresent];

    /* Calculate available memory (total - used) */
    available = totalMemory - txMemoryEnd;

    /* Return 0 if negative (shouldn't happen) */
    if ((int)available < 0) {
        return 0;
    }

    return available;
}

/*
 * Allocate onboard memory - returns offset and updates pointer
 */
- (unsigned short)_allocateOnboardMemory:(unsigned int)size
{
    unsigned short result;

    /* Get current memory region offset */
    result = [self _memoryRegion:size];

    /* Update memory allocation pointer */
    txMemoryEnd += size;

    return result;
}

/*
 * Setup multicast filter
 */
- (BOOL)_mcSetup
{
    id multicastQueue;
    id currentEntry;
    int numAddresses;
    int packetSize;
    unsigned char *packet;
    int i;
    unsigned short *wordPtr;
    unsigned char oldIntMask;
    unsigned char status;
    unsigned char command;
    BOOL wasReceiving;
    BOOL success;
    int timeout;

    numAddresses = 0;
    wasReceiving = NO;
    mcSetupComplete = NO;

    /* Get multicast queue from superclass */
    multicastQueue = [super multicastQueue];

    /* If multicast is disabled or queue is empty, return success */
    if (!multicastEnabled || [multicastQueue isEmpty]) {
        return YES;
    }

    /* Count multicast addresses */
    currentEntry = [multicastQueue firstElement];
    while (currentEntry != nil) {
        numAddresses++;
        currentEntry = [multicastQueue nextElement];
    }

    /* Allocate packet buffer (8 byte header + 6 bytes per address) */
    packetSize = 8 + (numAddresses * 6);
    packet = (unsigned char *)IOMalloc(packetSize);
    if (packet == NULL) {
        return NO;
    }

    /* Build multicast command packet */
    bzero(packet, 8);
    packet[0] = (packet[0] & 0xF0) | 0x03;  /* Command: Setup multicast */
    *(unsigned short *)(packet + 6) = numAddresses * 6;  /* Byte count */

    /* Copy multicast addresses into packet */
    i = 0;
    currentEntry = [multicastQueue firstElement];
    while (currentEntry != nil) {
        unsigned char *addr = (unsigned char *)[currentEntry data];
        bcopy(addr, packet + 8 + (i * 6), 6);
        i++;
        currentEntry = [multicastQueue nextElement];
    }

    /* Select bank 0 */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }

    /* Save and disable interrupts */
    oldIntMask = inb(ioBase + 3);
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outb(ioBase + 3, oldIntMask & 0xEF);
    IODelay(1);

    /* Set transmit pointer to MC setup area */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outw(ioBase + 0x0C, txMemoryStart + 0x1000);
    IODelay(1);

    /* Write packet to chip memory (word at a time) */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }

    wordPtr = (unsigned short *)packet;
    for (i = 0; i < (packetSize + 1) / 2; i++) {
        outw(ioBase + 0x0E, wordPtr[i]);
        IODelay(1);
    }

    /* Check if receive is active and stop it */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    status = inb(ioBase + 1);

    if (status & 0xC0) {  /* RX busy or executing */
        /* Clear execution interrupt if set */
        if (status & 0x08) {
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            outb(ioBase + 1, 0x08);
            IODelay(1);
            IOSleep(100);
        }

        /* Stop receive */
        command = inb(ioBase);
        outb(ioBase, (command & 0xE0) | 0x0A);  /* Stop RX */
        IODelay(1);
        wasReceiving = YES;
    }

    /* Enable MC setup command execution interrupt */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outb(ioBase + 3, oldIntMask | 0x0F);
    IODelay(1);

    /* Wait for previous command to complete */
    timeout = 0;
    success = NO;
    while (timeout < 100) {
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        status = inb(ioBase + 1);
        if ((status & 0x30) == 0) {  /* Not busy */
            success = YES;
            break;
        }
        IODelay(1000);
        timeout++;
    }

    if (success) {
        /* Execute MC setup command */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outw(ioBase + 10, txMemoryStart + 0x1000);
        IODelay(1);

        /* Clear execution interrupt if set */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        status = inb(ioBase + 1);
        if (status & 0x08) {
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            outb(ioBase + 1, 0x08);
            IODelay(1);
            IOSleep(100);
        }

        /* Start MC setup execution */
        command = inb(ioBase);
        outb(ioBase, (command & 0xE0) | 0x03);  /* Execute command */
        IODelay(1);
        IOSleep(100);

        /* Wait for execution interrupt */
        timeout = 0;
        success = NO;
        while (timeout < 100) {
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            status = inb(ioBase + 1);
            if (status & 0x08) {  /* Execution complete */
                success = YES;
                break;
            }
            IODelay(1000);
            timeout++;
        }

        if (success) {
            /* Check command completion status */
            command = inb(ioBase);
            success = ((command & 0x3F) == 0x03);

            /* Clear execution interrupt */
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            outb(ioBase + 1, 0x08);
            IODelay(1);
        }
    }

    /* Free packet buffer */
    IOFree(packet, packetSize);

    /* Store result */
    mcSetupComplete = success;

    /* Restore interrupt mask */
    if (currentBank != 0x00) {
        outb(ioBase, 0x00);
        IODelay(1);
        currentBank = 0x00;
    }
    outb(ioBase + 3, oldIntMask);
    IODelay(1);

    /* Restart receive if it was running */
    if (wasReceiving) {
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }

        /* Clear execution interrupt if set */
        status = inb(ioBase + 1);
        if (status & 0x08) {
            if (currentBank != 0x00) {
                outb(ioBase, 0x00);
                IODelay(1);
                currentBank = 0x00;
            }
            outb(ioBase + 1, 0x08);
            IODelay(1);
            IOSleep(100);
        }

        /* Start receive */
        command = inb(ioBase);
        outb(ioBase, (command & 0xE0) | 0x08);  /* Start RX */
        IODelay(1);
    }

    return success;
}

/*
 * Handle receive interrupt
 */
- (BOOL)_receiveInterruptOccurred
{
    unsigned short rxStatus[1];
    unsigned short rxHeader[3];  /* status1, status2, nextPtr, length */
    unsigned short *packetData;
    unsigned char status1, status2;
    unsigned short nextPtr, length;
    unsigned char oldIntMask;
    id packet;
    BOOL skipPacket;
    int i;

    [self reserveDebuggerLock];

    while (1) {
        skipPacket = NO;

        /* Select bank 0 and disable execution interrupt */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        oldIntMask = inb(ioBase + 3);
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outb(ioBase + 3, oldIntMask & 0xEF);
        IODelay(1);

        /* Set receive read pointer */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outw(ioBase + 0x0C, rxReadPtr);
        IODelay(1);

        /* Read receive status word */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        rxStatus[0] = inw(ioBase + 0x0E);

        /* Check if packet available (bit 3) */
        if ((rxStatus[0] & 0x0800) == 0) {
            [self releaseDebuggerLock];
            return YES;
        }

        /* Read packet header (3 words: status, next pointer, length) */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        for (i = 0; i < 3; i++) {
            rxHeader[i] = inw(ioBase + 0x0E);
        }

        status1 = rxHeader[0] & 0xFF;
        status2 = (rxHeader[0] >> 8) & 0xFF;
        nextPtr = rxHeader[1];
        length = rxHeader[2];

        /* Check if packet is good (bit 5 of status2) */
        if ((status2 & 0x20) == 0) {
            [netif incrementInputErrors];
            skipPacket = YES;
        } else if (length > 0x5EA) {  /* 1514 bytes max */
            [netif incrementInputErrors];
            skipPacket = YES;
        } else {
            /* Allocate network buffer */
            packet = nb_alloc(length);
            if (packet == nil) {
                IOLog("%s: unable to allocate a netbuf\n", [self name]);
                [netif incrementInputErrors];
                skipPacket = YES;
            } else {
                /* Map buffer and read packet data */
                packetData = (unsigned short *)nb_map(packet);

                if (currentBank != 0x00) {
                    outb(ioBase, 0x00);
                    IODelay(1);
                    currentBank = 0x00;
                }

                /* Read data words */
                for (i = 0; i < (length + 1) / 2; i++) {
                    packetData[i] = inw(ioBase + 0x0E);
                }

                /* Read odd byte if needed */
                if (length & 1) {
                    ((unsigned char *)packetData)[length - 1] = inb(ioBase + 0x0E);
                }
            }
        }

        /* Update receive read pointer */
        rxReadPtr = nextPtr;

        /* Update RX stop register */
        if (rxMemoryStart == rxReadPtr) {
            rxStopPtr = rxMemoryEnd;
        } else {
            rxStopPtr = rxReadPtr;
        }

        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outw(ioBase + 6, rxStopPtr - 1);
        IODelay(1);

        if (skipPacket) {
            continue;
        }

        /* Check if this is an unwanted multicast packet */
        if (!promiscuousMode && (status1 & 0x02)) {
            unsigned char *packetBytes = (unsigned char *)nb_map(packet);
            if ([super isUnwantedMulticastPacket:packetBytes]) {
                nb_free(packet);
                continue;
            }
        }

        /* Pass packet to network stack */
        [self releaseDebuggerLock];
        [netif handleInputPacket:packet extra:0];
        [self reserveDebuggerLock];
    }

    return YES;
}

/*
 * Handle transmit interrupt
 */
- (BOOL)_transmitInterruptOccurred
{
    unsigned short txStatus[1];
    unsigned char status1, status2;
    unsigned char oldIntMask;
    id nextPacket;

    if (transmitActive) {
        [self clearTimeout];

        /* Select bank 0 and disable execution interrupt */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        oldIntMask = inb(ioBase + 3);
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outb(ioBase + 3, oldIntMask & 0xEF);
        IODelay(1);

        /* Set read pointer to TX status area */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        outw(ioBase + 0x0C, txMemoryStart + 2);
        IODelay(1);

        /* Read transmit status */
        if (currentBank != 0x00) {
            outb(ioBase, 0x00);
            IODelay(1);
            currentBank = 0x00;
        }
        txStatus[0] = inw(ioBase + 0x0E);

        status1 = txStatus[0] & 0xFF;
        status2 = (txStatus[0] >> 8) & 0xFF;

        /* Update statistics based on status */
        if ((status2 & 0x20) == 0) {
            /* Transmit error */
            [netif incrementOutputErrors];
        } else {
            /* Transmit success */
            [netif incrementOutputPackets];
        }

        /* Check for excessive collisions (bit 5 of status1) */
        if (status1 & 0x20) {
            [netif incrementCollisionsBy:0x10];
        }

        /* Add collision count (bits 0-3 of status1) */
        if (status1 & 0x0F) {
            [netif incrementCollisionsBy:(status1 & 0x0F)];
        }

        /* Check for underrun (bit 3 of status2) */
        if (status2 & 0x08) {
            [netif incrementCollisions];
        }

        transmitActive = NO;
    }

    /* Dequeue next packet for transmission */
    nextPacket = [transmitQueue dequeue];
    if (nextPacket != nil) {
        [self transmit:nextPacket];
    }

    return YES;
}

@end
