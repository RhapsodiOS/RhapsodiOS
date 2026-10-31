/*
 * DECchip21140.m
 * Driver for DEC 21140 Ethernet Controller
 */

#import "DECchip21140.h"
#import "DECchip21140Private.h"
#import <driverkit/generalFuncs.h>

@implementation DECchip21140

/*
 * Probe for device
 */
+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    IOReturn result;
    unsigned char configSpace[256];
    unsigned char pciDevice, pciFunction, pciBus;
    IORange portRange[1];
    unsigned int irqLevel[2];
    unsigned int commandReg;
    id instance;

    /* Get PCI device/function/bus information */
    result = [deviceDescription getPCIdevice:&pciDevice function:&pciFunction bus:&pciBus];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: unsupported PCI hardware.\n", [self name]);
        return NO;
    }

    /* Log PCI device information */
    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", [self name], pciDevice, pciFunction, pciBus);

    /* Get PCI configuration space */
    result = [self getPCIConfigSpace:configSpace withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              [self name]);
        return NO;
    }

    /* Set up I/O port range (CSR base address is at config offset 0x10 / dword 4) */
    portRange[0].start = ((unsigned int *)configSpace)[4] & 0xFFFFFF80;
    portRange[0].size = 0x80;                          /* 128 bytes */
    portRange[0].flags = 0;

    result = [deviceDescription setPortRangeList:portRange num:1];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Unable to reserve port range 0x%x-0x%x - Aborting\n",
              [self name], portRange[0].start, portRange[0].start + 0x7f);
        return NO;
    }

    /* Validate and set up IRQ (at config offset 0x3c / byte 0x3c) */
    irqLevel[0] = configSpace[0x3c];

    /* IRQ must be in range 2-15 (not 0, 1, or > 15) */
    if (irqLevel[0] < 2 || irqLevel[0] > 15) {
        IOLog("%s: Invalid IRQ level (%d) assigned by PCI BIOS\n", [self name], irqLevel[0]);
        return NO;
    }

    irqLevel[1] = 0;
    result = [deviceDescription setInterruptList:irqLevel num:1];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Unable to reserve IRQ %d - Aborting\n", [self name], irqLevel[0]);
        return NO;
    }

    /* Read PCI command register (offset 4) */
    result = [self getPCIConfigData:&commandReg atRegister:4
                withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              [self name]);
        return NO;
    }

    /* Enable bus mastering (bit 2) and ensure memory access is disabled (clear bit 1) */
    commandReg = (commandReg & 0xFFFFFFFD) | 0x04;

    result = [self setPCIConfigData:commandReg atRegister:4
                withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Failed PCI configuration space access - aborting\n", [self name]);
        return NO;
    }

    /* Allocate and initialize instance */
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
 */
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    IOReturn result;
    unsigned char configSpace[256];
    unsigned short *configWords = (unsigned short *)configSpace;
    IORange *portRange;
    id configTable;
    const char *configString;
    const char *vendorNames[] = {"EM100", "EM110", "SMC9332", "DE500", "Custom"};
    const char *mediaNames[] = {"10BaseT", "10BaseT-FD", "10Base2", "10Base5", "100BaseTX", "100BaseTX-FD"};
    unsigned int i;
    int parsedValue;
    char *str;
    char ch;
    struct objc_super superInfo;

    /* Call superclass initialization */
    superInfo.receiver = self;
    superInfo.class = objc_getClass("IOEthernet");
    if (objc_msgSendSuper(&superInfo, @selector(initFromDeviceDescription:), deviceDescription) == nil) {
        return nil;
    }

    result = [self getPCIConfigSpace:configSpace withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              [self name]);
        return nil;
    }
    vendorDeviceID = configWords[0] | ((unsigned int)configWords[1] << 16);
    subVendorDeviceID = configWords[22] | ((unsigned int)configWords[23] << 16);

    /* Get I/O port base address */
    portRange = [deviceDescription portRangeList];
    ioBase = [portRange start];

    /* Get IRQ */
    irq = [deviceDescription interrupt];

    /* Get SROM address bits from config (default 6) */
    configTable = [deviceDescription configTable];
    configString = [configTable valueForStringKey:"SROM Address Bits"];
    if (configString != NULL && strcmp(configString, "8") == 0) {
        sromAddressBits = 8;
    } else {
        sromAddressBits = 6;
    }

    /* Get SROM address from config (default 0) - parse decimal */
    configString = [configTable valueForStringKey:"SROM Address"];
    if (configString == NULL) {
        enetAddressOffset = 0;
    } else {
        /* Parse decimal value */
        str = (char *)configString;
        ch = *str;
        while (ch != '\0' && (ch == ' ' || (unsigned char)(ch - 9) < 2)) {
            str++;
            ch = *str;
        }
        parsedValue = 0;
        if (*str != '\0') {
            while (*str != '\0') {
                if (*str == ' ' || (unsigned char)(*str - 9) < 2) break;
                if ((unsigned char)(*str - '0') < 10) {
                    parsedValue = (*str - '0') + parsedValue * 10;
                }
                str++;
            }
        }
        enetAddressOffset = parsedValue;
    }

    /* Get vendor type from config (default 5 = Custom) */
    hardwareVendorID = 5;
    configString = [configTable valueForStringKey:"Vendor Type"];
    if (configString != NULL) {
        for (i = 0; i < 5; i++) {
            if (strcmp(vendorNames[i], configString) == 0) {
                hardwareVendorID = i;
                break;
            }
        }
    }

    /* Get media type from config (default 0 = 10BaseT) */
    dataRateMode = 0;
    configString = [configTable valueForStringKey:"Media Type"];
    if (configString != NULL) {
        for (i = 0; i < 6; i++) {
            if (strcmp(mediaNames[i], configString) == 0) {
                dataRateMode = i;
                break;
            }
        }
    }

    /* Get station (MAC) address from SROM */
    [self _getStationAddress:&myAddress];

    /* Verify SROM checksum */
    if (![self _verifyCheckSum]) {
        IOLog("%s: SROM checksum verification failed\n", [self name]);
        [self free];
        return nil;
    }

    /* Allocate memory for descriptor rings */
    if (![self _allocateMemory]) {
        [self free];
        return nil;
    }

    /* Initialize state flags */
    isPromiscuous = NO;
    multicastEnabled = NO;

    /* Log adapter information based on vendor type */
    if ((subVendorDeviceID & 0xffff) == 0x10b8) {
        IOLog("SMC EtherPower 10/100 B at port 0x%0x irq %d\n", ioBase, irq);
        IOLog("%s: auto-detecting the interface port\n", [self name]);
    } else {
        IOLog("DECchip21140 based adapter at port 0x%0x irq %d\n", ioBase, irq);
        if (dataRateMode != 0) {
            IOLog("DECchip21140 using %s (MII/SYM) interface\n", mediaNames[dataRateMode]);
        } else {
            IOLog("DECchip21140 using 10BASE-T/BNC (SRL) interface\n");
        }
    }

    /* Allocate debug netbuf for polling mode */
    KDB_txBuf = [self allocateNetbuf];
    if (KDB_txBuf == NULL) {
        IOLog("%s: Failed to allocate debug netbuf\n", [self name]);
        [self free];
        return nil;
    }

    resetAndEnabled = NO;
    if (![self resetAndEnable:YES] || ![self resetAndEnable:NO]) {
        [self free];
        return nil;
    }

    /* Attach to network with MAC address */
    superInfo.receiver = self;
    superInfo.class = objc_getClass("IOEthernet");
    networkInterface = objc_msgSendSuper(&superInfo, @selector(attachToNetworkWithAddress:), &myAddress);

    return self;
}

/*
 * Free resources
 */
- free
{
    int i;
    struct objc_super superInfo;

    /* Clear any pending timeout */
    [self clearTimeout];

    /* Reset chip to stop all DMA */
    [self _resetChip];

    /* Free network interface if allocated */
    if (networkInterface != nil) {
        [networkInterface free];
    }

    /* Free all RX netbufs (64 buffers) */
    for (i = 0; i < DECCHIP21140_RX_RING_SIZE; i++) {
        if (rxNetbuf[i] != NULL) {
            nb_free(rxNetbuf[i]);
        }
    }

    /* Free all TX netbufs (32 buffers) */
    for (i = 0; i < DECCHIP21140_TX_RING_SIZE; i++) {
        if (txNetbuf[i] != NULL) {
            nb_free(txNetbuf[i]);
        }
    }

    /* Free descriptor memory if allocated */
    if (memoryPtr != NULL) {
        IOFreeLow(memoryPtr, memorySize);
    }

    /* Re-enable system interrupts */
    [self enableAllInterrupts];

    /* Call superclass free */
    superInfo.receiver = self;
    superInfo.class = objc_getClass("IOEthernet");
    return objc_msgSendSuper(&superInfo, @selector(free));
}

/*
 * Reset and enable the adapter
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    resetAndEnabled = NO;
    [self clearTimeout];
    [self disableAdapterInterrupts];
    [self _resetChip];

    if (enable) {
        if (![self _initRxRing] || ![self _initTxRing]) {
            return NO;
        }
        if (![self _initChip]) {
            [self setRunning:NO];
            return NO;
        }
        [self _startTransmit];
        [self _startReceive];
        if ([self enableAllInterrupts] != IO_R_SUCCESS) {
            [self setRunning:NO];
            return NO;
        }
        [self enableAdapterInterrupts];
    }

    [self setRunning:enable];
    resetAndEnabled = YES;
    return YES;
}

/*
 * Enable adapter interrupts
 */
- (void)enableAdapterInterrupts
{
    /* Write interrupt mask to CSR7 (interrupt enable register) */
    outl(ioBase + 0x38, interruptMask);
}

/*
 * Disable adapter interrupts
 */
- (void)disableAdapterInterrupts
{
    /* Write 0 to CSR7 (interrupt enable register) to disable all interrupts */
    outl(ioBase + 0x38, 0);
}

/*
 * Interrupt occurred
 */
- (void)interruptOccurred
{
    unsigned int csr5;

    do {
        [self reserveDebuggerLock];
        csr5 = inl(ioBase + 40);
        outl(ioBase + 40, csr5);
        [self releaseDebuggerLock];

        if (csr5 & 0x40) {
            [self _receiveInterruptOccurred];
        }
        if (csr5 & 1) {
            [self reserveDebuggerLock];
            [self _transmitInterruptOccurred];
            [self releaseDebuggerLock];
            [self serviceTransmitQueue];
        }
    } while (csr5 & 0x49);

    [self enableAllInterrupts];
}

/*
 * Timeout occurred
 */
- (void)timeoutOccurred
{
    if ([self isRunning]) {
        [self reserveDebuggerLock];
        [self _transmitInterruptOccurred];
        [self releaseDebuggerLock];
        [self serviceTransmitQueue];
    }
}

/*
 * Transmit a packet
 */
- (void)transmit:(netbuf_t)packet
{
    if (packet == NULL) {
        IOLog("%s: transmit: received NULL netbuf\n", [self name]);
    } else if ([self isRunning]) {
        [self reserveDebuggerLock];
        [self _transmitInterruptOccurred];
        [self releaseDebuggerLock];
        [self serviceTransmitQueue];
        if (txNumFree != 0 && [transmitQueue count] == 0) {
            [self _transmitPacket:packet];
        } else {
            [transmitQueue enqueue:packet];
        }
    } else {
        nb_free(packet);
    }
}

/*
 * Service transmit queue
 */
- (void)serviceTransmitQueue
{
    while (txNumFree != 0 && [transmitQueue count] != 0) {
        netbuf_t packet = [transmitQueue dequeue];
        if (packet == NULL) {
            break;
        }
        [self _transmitPacket:packet];
    }
}

/*
 * Get transmit queue count
 */
- (unsigned int)transmitQueueCount
{
    return [transmitQueue count];
}

/*
 * Get transmit queue size
 */
- (unsigned int)transmitQueueSize
{
    return 128;
}

/*
 * Get pending transmit count
 */
- (unsigned int)pendingTransmitCount
{
    return [transmitQueue count] - txNumFree + DECCHIP21140_TX_RING_SIZE;
}

/*
 * Allocate network buffer
 */
- (netbuf_t)allocateNetbuf
{
    netbuf_t netBuf;
    unsigned int virtualAddr;
    int bufferSize;

    /* Allocate buffer (0x610 = 1552 bytes) */
    netBuf = nb_alloc(0x610);
    if (netBuf == NULL) {
        return NULL;
    }

    /* Map buffer to get virtual address */
    virtualAddr = nb_map(netBuf);

    /* Align to 32-byte boundary */
    if ((virtualAddr & 0x1F) != 0) {
        /* Shrink top to align */
        nb_shrink_top(netBuf, 0x20 - (virtualAddr & 0x1F));
    }

    /* Set final buffer size to 0x5ea (1514 bytes - max ethernet frame) */
    bufferSize = nb_size(netBuf);
    nb_shrink_bot(netBuf, bufferSize - 0x5ea);

    return netBuf;
}

/*
 * Enable promiscuous mode
 */
- (BOOL)enablePromiscuousMode
{
    unsigned int csrValue;

    /* Set promiscuous mode flag */
    isPromiscuous = YES;

    /* Reserve debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Read CSR6 command register */
    csrValue = inl(ioBase + 0x30);

    /* Set promiscuous mode bit (bit 6 = 0x40) */
    outl(ioBase + 0x30, csrValue | 0x40);

    /* Release debugger lock */
    [self releaseDebuggerLock];
    return YES;
}

/*
 * Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    unsigned int csrValue;

    /* Clear promiscuous mode flag */
    isPromiscuous = NO;

    /* Reserve debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Read CSR6 command register */
    csrValue = inl(ioBase + 0x30);

    /* Clear promiscuous mode bit (bit 6 = 0x40) */
    outl(ioBase + 0x30, csrValue & 0xFFFFFFBF);

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Enable multicast mode
 */
- (BOOL)enableMulticastMode
{
    multicastEnabled = YES;
    return YES;
}

/*
 * Disable multicast mode
 */
- (void)disableMulticastMode
{
    BOOL result;

    /* If attached (have multicast addresses), rebuild filter without them */
    if (multicastEnabled) {
        /* Reserve debugger lock for thread safety */
        [self reserveDebuggerLock];

        /* Rebuild address filtering */
        result = [self _setAddressFiltering:NO];

        if (!result) {
            IOLog("%s: disable multicast mode failed\n", [self name]);
        }

        /* Release debugger lock */
        [self releaseDebuggerLock];
    }

    /* Mark as not attached (no multicast addresses) */
    multicastEnabled = NO;
}

/*
 * Add multicast address
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;

    /* Mark that we're attached (have multicast addresses) */
    multicastEnabled = YES;

    /* Reserve debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Rebuild address filtering with new multicast address */
    result = [self _setAddressFiltering:NO];

    if (!result) {
        IOLog("%s: add multicast address failed\n", [self name]);
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];

}

/*
 * Remove multicast address
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;

    [self reserveDebuggerLock];
    result = [self _setAddressFiltering:NO];
    if (!result) {
        IOLog("%s: remove multicast address failed\n", [self name]);
    }
    [self releaseDebuggerLock];
}

/*
 * Get power management state
 */
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state
{
    /* Power management not supported */
    return IO_R_UNSUPPORTED;
}

/*
 * Set power management state
 */
- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{
    return IO_R_SUCCESS;
}

/*
 * Get power state
 */
- (IOReturn)getPowerState:(PMPowerState *)state
{
    /* Power management not supported */
    return IO_R_UNSUPPORTED;
}

/*
 * Set power state
 */
- (IOReturn)setPowerState:(PMPowerState)state
{
    return IO_R_SUCCESS;
}

@end
