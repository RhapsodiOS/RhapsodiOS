/*
 * DECchip2104x.m
 * Base class for DEC 21040/21041 Ethernet Controllers
 */

#import "DECchip2104x.h"
#import "DECchip2104xInline.h"
#import "DECchip2104xPrivate.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IOPCIDeviceDescription.h>

@implementation DECchip2104x

/*
 * Probe for supported devices
 */
+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    unsigned char pciDevice, pciFunction, pciBus;
    unsigned char configSpace[256];
    IORange portRange;
    unsigned int irqLevel[2];
    unsigned int commandReg;
    id instance;
    IOReturn result;

    /* Get PCI device location */
    result = [deviceDescription getPCIdevice:&pciDevice function:&pciFunction bus:&pciBus];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: unsupported PCI hardware.\n", [self name]);
        return NO;
    }

    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", [self name], pciDevice, pciFunction, pciBus);

    /* Get PCI configuration space */
    result = [self getPCIConfigSpace:configSpace withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              [self name]);
        return NO;
    }

    /* Extract I/O base address from config space (BAR0 at offset 0x10) */
    /* configSpace[0x10-0x13] contains the base address register */
    unsigned int *bar0 = (unsigned int *)&configSpace[0x10];
    portRange.start = *bar0 & 0xFFFFFF80;  /* Mask off control bits */
    portRange.size = 0x80;
    portRange.protection = 0;
    portRange.reserved = 0;

    /* Reserve I/O port range */
    result = [deviceDescription setPortRangeList:&portRange num:1];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Unable to reserve port range 0x%x-0x%x - Aborting\n",
              [self name], portRange.start, portRange.start + 0x7F);
        return NO;
    }

    /* Get IRQ level from config space (at offset 0x3C) */
    irqLevel[0] = configSpace[0x3C];

    /* Validate IRQ level (must be 2-15) */
    if (irqLevel[0] < 2 || irqLevel[0] > 15) {
        IOLog("%s: Invalid IRQ level (%d) assigned by PCI BIOS\n",
              [self name], irqLevel[0]);
        return NO;
    }

    irqLevel[1] = 0;

    /* Reserve interrupt */
    result = [deviceDescription setInterruptList:irqLevel num:1];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Unable to reserve IRQ %d - Aborting\n", [self name], irqLevel[0]);
        return NO;
    }

    /* Read PCI command register (offset 4) */
    result = [self getPCIConfigData:&commandReg atRegister:4 withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              [self name]);
        return NO;
    }

    /* Enable bus mastering (bit 2) and disable memory space (bit 1) */
    commandReg = (commandReg & ~0x02) | 0x04;

    result = [self setPCIConfigData:commandReg atRegister:4 withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Failed PCI configuration space access - aborting\n", [self name]);
        return NO;
    }

    /* Allocate and initialize driver instance */
    instance = [self alloc];
    if (instance == nil) {
        IOLog("%s: Failed to alloc instance\n", [self name]);
        return NO;
    }

    instance = [instance initFromDeviceDescription:deviceDescription];
    if (instance == nil) {
        return NO;
    }

    return YES;
}

/*
 * Initialize from device description
 * This is the base class initialization - subclasses override this
 */
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Allocate debug netbuf for kernel debugger use */
    _debugNetBuf = [self allocateNetbuf];
    if (_debugNetBuf == NULL) {
        IOLog("%s: couldn't allocate KDB netbuf\n", [self name]);
        [self free];
        return nil;
    }

    /* Initialize polling mode flag to NO (normal interrupt-driven mode) */
    _isPollingMode = NO;

    return self;
}

/*
 * Free resources
 * Cleans up all allocated memory and resources
 */
- free
{
    int i;

    /* Clear any pending timeouts */
    [self clearTimeout];

    /* Reset the chip to stop all DMA activity */
    [self resetChip];

    /* Free network interface if allocated */
    if (_networkInterface != nil) {
        [_networkInterface free];
        _networkInterface = nil;
    }

    /* Free all RX network buffers (32 entries) */
    for (i = 0; i < DECCHIP_RX_RING_SIZE; i++) {
        if (_rxNetBufs[i] != NULL) {
            nb_free(_rxNetBufs[i]);
            _rxNetBufs[i] = NULL;
        }
    }

    /* Free all TX network buffers (16 entries) */
    for (i = 0; i < DECCHIP_TX_RING_SIZE; i++) {
        if (_txNetBufs[i] != NULL) {
            nb_free(_txNetBufs[i]);
            _txNetBufs[i] = NULL;
        }
    }

    /* Free debug netbuf */
    if (_debugNetBuf != NULL) {
        nb_free(_debugNetBuf);
        _debugNetBuf = NULL;
    }

    /* Free transmit queue */
    if (_transmitQueue != nil) {
        [_transmitQueue free];
        _transmitQueue = nil;
    }

    /* Free descriptor memory */
    if (_descriptorMemory != NULL) {
        IOFreeLow(_descriptorMemory, _descriptorMemorySize);
        _descriptorMemory = NULL;
    }

    /* Re-enable system interrupts */
    [self enableAllInterrupts];

    /* Call superclass free */
    return [super free];
}

/*
 * Reset and optionally enable the controller
 * If enable is NO, resets and disables the controller
 * If enable is YES, resets and fully initializes the controller
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    BOOL result;
    int interruptResult;

    /* Clear polling mode flag during reset */
    _isPollingMode = NO;

    /* Clear any pending timeouts */
    [self clearTimeout];

    /* Disable adapter interrupts */
    [self disableAdapterInterrupts];

    /* Reset the chip hardware */
    [self resetChip];

    if (!enable) {
        /* Just resetting, not enabling */
        [self setRunning:NO];
        _isPollingMode = YES;
        return YES;
    }

    /* Enable path - initialize rings and chip */
    result = [self initRxRing];
    if (!result) {
        [self setRunning:NO];
        return NO;
    }

    result = [self initTxRing];
    if (!result) {
        [self setRunning:NO];
        return NO;
    }

    result = [self initChip];
    if (!result) {
        [self setRunning:NO];
        return NO;
    }

    /* Start transmit and receive engines */
    [self startTransmit];
    [self startReceive];

    /* Enable system interrupts */
    interruptResult = [self enableAllInterrupts];
    if (interruptResult == 0) {
        /* Success - enable adapter interrupts */
        [self enableAdapterInterrupts];
        [self setRunning:enable];
        _isPollingMode = YES;
        return YES;
    }

    /* Failed to enable interrupts */
    [self setRunning:NO];
    return NO;
}

/*
 * Interrupt handler
 * Processes interrupts in a loop until no more pending interrupts
 */
- (void)interruptOccurred
{
    unsigned int status;

    /* Process interrupts in a loop */
    while (1) {
        /* Reserve debugger lock for register access */
        [self reserveDebuggerLock];

        /* Read CSR5 status register */
        status = DECchip_ReadCSR(_ioBase, CSR5_STATUS);

        /* Write back to acknowledge/clear interrupts */
        DECchip_WriteCSR(_ioBase, CSR5_STATUS, status);

        /* Release debugger lock */
        [self releaseDebuggerLock];

        /* Check if any TX or RX interrupts pending (bits 0x49 = 0x40|0x08|0x01) */
        if ((status & 0x49) == 0) {
            /* No more interrupts to process */
            break;
        }

        /* Handle receive interrupt (bit 0x40 = CSR5_RI) */
        if (status & 0x40) {
            [self receiveInterruptOccurred];
        }

        /* Handle transmit interrupt (bit 0x01 = CSR5_TI) */
        if (status & 0x01) {
            [self reserveDebuggerLock];
            [self transmitInterruptOccurred];
            [self releaseDebuggerLock];

            /* Service the transmit queue to send any pending packets */
            [self serviceTransmitQueue];
        }
    }

    /* Re-enable system interrupts after handling */
    [self enableAllInterrupts];
}

/*
 * Transmit a packet
 * Main transmit entry point from network stack
 */
- (int)transmit:(netbuf_t)pkt
{
    int queueCount;

    /* Validate netbuf parameter */
    if (pkt == NULL) {
        IOLog("%s: transmit: received NULL netbuf\n", [self name]);
        return 0;
    }

    /* Check if adapter is running */
    if (![self isRunning]) {
        /* Not running - discard packet */
        nb_free(pkt);
        return 0;
    }

    /* Process any completed transmissions first */
    [self reserveDebuggerLock];
    [self transmitInterruptOccurred];
    [self releaseDebuggerLock];

    /* Service the transmit queue */
    [self serviceTransmitQueue];

    /* Decide whether to queue or transmit directly */
    if (_txTail == 0) {
        /* No descriptors available - must queue */
        [_transmitQueue enqueue:pkt];
    } else {
        /* Check if queue has packets */
        queueCount = [_transmitQueue count];
        if (queueCount != 0) {
            /* Queue has packets - enqueue to maintain order */
            [_transmitQueue enqueue:pkt];
        } else {
            /* Queue is empty and descriptors available - transmit directly */
            [self transmitPacket:pkt];
        }
    }

    return 0;
}

/*
 * Receive packets
 */
- (void)receivePackets
{
    /* TODO: Implement packet reception */
}

/*
 * Get Ethernet MAC address
 */
- (void)getEthernetAddress:(enet_addr_t *)addr
{
    /* TODO: Read MAC address from SROM */
    memset(addr, 0, sizeof(enet_addr_t));
}

/*
 * Set full duplex mode
 */
- (BOOL)setFullDuplex:(BOOL)fullDuplex
{
    unsigned int csr6;

    csr6 = DECchip_ReadCSR(_ioBase, CSR6_COMMAND);

    if (fullDuplex) {
        csr6 |= CSR6_FD;
    } else {
        csr6 &= ~CSR6_FD;
    }

    DECchip_WriteCSR(_ioBase, CSR6_COMMAND, csr6);
    _isFullDuplex = fullDuplex;

    return YES;
}

/*
 * Get station (MAC) address - base implementation
 * This is overridden by subclasses (21040, 21041) to read from hardware
 */
- (void)getStationAddress:(enet_addr_t *)addr
{
    /* Base class does nothing - subclasses must override */
    return;
}

/*
 * Select network interface
 * Base class does nothing - subclasses (21040, 21041) override this
 */
- (IOReturn)selectInterface
{
    /* Base implementation does nothing */
    return;
}

/*
 * Allocate a network buffer
 * Allocates buffer with proper size and alignment for DMA
 */
- (netbuf_t)allocateNetbuf
{
    netbuf_t netBuf;
    unsigned int bufferAddr;
    int bufferSize;

    /* Allocate 0x610 bytes (1552 bytes) */
    netBuf = nb_alloc(0x610);

    if (netBuf != NULL) {
        /* Get buffer address */
        bufferAddr = nb_map(netBuf);

        /* Check if buffer is 32-byte aligned */
        if ((bufferAddr & 0x1F) != 0) {
            /* Not aligned - shrink from top to align */
            nb_shrink_top(netBuf, 0x20 - (bufferAddr & 0x1F));
        }

        /* Get current size and shrink to final size of 0x5ea (1514 bytes) */
        bufferSize = nb_size(netBuf);
        nb_shrink_bot(netBuf, bufferSize - 0x5EA);
    }

    return netBuf;
}

/*
 * Enable adapter interrupts
 * Writes the interrupt mask to CSR7
 */
- (void)enableAdapterInterrupts
{
    /* Write interrupt mask to CSR7 (interrupt enable register) */
    DECchip_WriteCSR(_ioBase, CSR7_INTERRUPT_MASK, _interruptMask);
}

/*
 * Disable adapter interrupts
 * Writes 0 to CSR7 to mask all interrupts
 */
- (void)disableAdapterInterrupts
{
    /* Write 0 to CSR7 (interrupt enable register) */
    DECchip_WriteCSR(_ioBase, CSR7_INTERRUPT_MASK, 0);
}

/*
 * Enable promiscuous mode
 * Sets promiscuous bit in CSR6 and updates state flag
 */
- (void)enablePromiscuousMode
{
    unsigned int csr6;

    /* Set promiscuous mode flag */
    _isEnabled = YES;

    /* Reserve debugger lock for register access */
    [self reserveDebuggerLock];

    /* Read CSR6, set promiscuous bit (bit 6 = 0x40), and write back */
    csr6 = DECchip_ReadCSR(_ioBase, CSR6_COMMAND);
    csr6 |= 0x40;  /* Set bit 6 (promiscuous mode) */
    DECchip_WriteCSR(_ioBase, CSR6_COMMAND, csr6);

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Disable promiscuous mode
 * Clears promiscuous bit in CSR6 and updates state flag
 */
- (void)disablePromiscuousMode
{
    unsigned int csr6;

    /* Clear promiscuous mode flag */
    _isEnabled = NO;

    /* Reserve debugger lock for register access */
    [self reserveDebuggerLock];

    /* Read CSR6, clear promiscuous bit (bit 6 = 0x40), and write back */
    csr6 = DECchip_ReadCSR(_ioBase, CSR6_COMMAND);
    csr6 &= ~0x40;  /* Clear bit 6 (promiscuous mode) */
    DECchip_WriteCSR(_ioBase, CSR6_COMMAND, csr6);

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Enable multicast mode
 * Sets the multicast mode flag
 */
- (void)enableMulticastMode
{
    /* Set multicast mode flag */
    _isAttached = YES;
}

/*
 * Disable multicast mode
 * Rebuilds setup filter without multicast addresses
 */
- (void)disableMulticastMode
{
    BOOL result;

    /* Check if multicast mode is currently active */
    if (_isAttached) {
        /* Reserve debugger lock */
        [self reserveDebuggerLock];

        /* Rebuild setup filter without multicast addresses */
        result = [self setAddressFiltering:NO];
        if (!result) {
            IOLog("%s: disable multicast mode failed\n", [self name]);
        }

        /* Release debugger lock */
        [self releaseDebuggerLock];
    }

    /* Clear multicast mode flag */
    _isAttached = NO;
}

/*
 * Add multicast address
 * Rebuilds the setup filter to include the new multicast address
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;

    /* Set multicast mode flag */
    _isAttached = YES;

    /* Reserve debugger lock */
    [self reserveDebuggerLock];

    /* Rebuild setup filter with multicast addresses */
    result = [self setAddressFiltering:NO];
    if (!result) {
        IOLog("%s: add multicast address failed\n", [self name]);
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Remove multicast address
 * Rebuilds the setup filter without the removed multicast address
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;

    /* Reserve debugger lock */
    [self reserveDebuggerLock];

    /* Rebuild setup filter (which will exclude removed addresses) */
    result = [self setAddressFiltering:NO];
    if (!result) {
        IOLog("%s: remove multicast address failed\n", [self name]);
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Service transmit queue
 * Dequeues packets from transmit queue and sends them while descriptors available
 */
- (void)serviceTransmitQueue
{
    netbuf_t packet;
    int queueCount;

    /* Loop while descriptors are available */
    while (_txTail != 0) {
        /* Check if queue has packets */
        queueCount = [_transmitQueue count];
        if (queueCount == 0) {
            break;
        }

        /* Dequeue a packet */
        packet = [_transmitQueue dequeue];
        if (packet == NULL) {
            break;
        }

        /* Transmit the packet */
        [self transmitPacket:packet];
    }
}

/*
 * Get pending transmit count
 * Returns the number of packets that are queued or in-flight
 */
- (unsigned int)pendingTransmitCount
{
    int queueCount;

    /* Get count of packets in transmit queue */
    queueCount = [_transmitQueue count];

    /* Add descriptors in use: (queue + 16 total) - available */
    return (queueCount + 0x10) - _txTail;
}

/*
 * Get transmit queue count
 * Returns the number of packets currently in the transmit queue
 */
- (unsigned int)transmitQueueCount
{
    /* Return count of packets in queue */
    return [_transmitQueue count];
}

/*
 * Get transmit queue size
 * Returns the maximum number of packets the transmit queue can hold
 */
- (unsigned int)transmitQueueSize
{
    /* Return maximum queue size (64 packets) */
    return 0x40;
}

/*
 * Timeout occurred
 * Watchdog timeout handler - processes transmit completions if running
 */
- (void)timeoutOccurred
{
    /* Check if the adapter is running */
    if ([self isRunning]) {
        /* Process any completed transmissions */
        [self reserveDebuggerLock];
        [self transmitInterruptOccurred];
        [self releaseDebuggerLock];

        /* Service the transmit queue to send any pending packets */
        [self serviceTransmitQueue];
    }
}

/*
 * Reserve debugger lock
 */
- (void)reserveDebuggerLock
{
    /* TODO: Implement debugger lock reservation */
}

/*
 * Release debugger lock
 */
- (void)releaseDebuggerLock
{
    /* TODO: Implement debugger lock release */
}

/*
 * Check if multicast packet should be filtered
 */
- (BOOL)isUnwantedMulticastPacket:(void *)packet
{
    /* Call superclass implementation */
    struct objc_super superInfo;
    superInfo.receiver = self;
    superInfo.class = objc_getClass("IOEthernet");

    return (BOOL)objc_msgSendSuper(&superInfo, @selector(isUnwantedMulticastPacket:), packet);
}

/*
 * Perform loopback of packet if needed
 */
- (void)performLoopback:(netbuf_t)packet
{
    /* Call superclass implementation */
    struct objc_super superInfo;
    superInfo.receiver = self;
    superInfo.class = objc_getClass("IOEthernet");

    objc_msgSendSuper(&superInfo, @selector(performLoopback:), packet);
}

/*
 * Get power management capabilities
 * Power management is not supported by this driver
 */
- (IOReturn)getPowerManagement:(IOPMPowerManagementState *)state
{
    /* Return 0xfffffd39 (-711 decimal) = IO_R_UNSUPPORTED */
    return 0xfffffd39;
}

/*
 * Set power management
 * Power management is not supported by this driver
 */
- (IOReturn)setPowerManagement:(IOPMPowerManagementState)state
{
    /* Return 0xfffffd39 = IO_R_UNSUPPORTED */
    return 0xfffffd39;
}

/*
 * Get power state
 * Power management is not supported by this driver
 */
- (IOReturn)getPowerState:(IOPMPowerState *)state
{
    /* Return 0xfffffd39 (-711 decimal) = IO_R_UNSUPPORTED */
    return 0xfffffd39;
}

/*
 * Set power state
 * Only supports state 3 (reset)
 */
- (IOReturn)setPowerState:(IOPMPowerState)state
{
    /* Check if state is 3 (reset/wake) */
    if (state != 3) {
        /* Other states not supported */
        return 0xfffffd39;
    }

    /* State 3: Clear polling mode and reset chip */
    _isPollingMode = NO;
    [self resetChip];

    return 0;  /* Success */
}

@end
