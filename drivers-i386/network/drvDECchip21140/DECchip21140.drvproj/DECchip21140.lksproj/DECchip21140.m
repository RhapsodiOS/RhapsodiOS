/*
 * DECchip21140.m
 * Driver for DEC 21140 Ethernet Controller
 */

#import "DECchip21140.h"
#import "DECchip21140Inline.h"
#import <driverkit/generalFuncs.h>

@implementation DECchip21140

/*
 * Probe for device
 */
+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    IOReturn result;
    unsigned char pciDevice, pciFunction, pciBus;
    unsigned char configSpace[256];
    unsigned int *configData = (unsigned int *)configSpace;
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
    portRange[0].start = configData[4] & 0xFFFFFF80;  /* Mask off lower bits */
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

    /* Get PCI device/vendor IDs */
    result = [deviceDescription getPCIdevice:&_pciDevice function:&_pciFunction bus:&_pciBus];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: Failed to get PCI device info\n", [self name]);
        return nil;
    }

    /* Store vendor and device IDs */
    _vendorID = ([deviceDescription vendorID] & 0xFFFF) | (([deviceDescription deviceID] & 0xFFFF) << 16);
    _deviceID = ([deviceDescription vendorID] & 0xFFFF) | (([deviceDescription subdeviceID] & 0xFFFF) << 16);

    /* Get I/O port base address */
    portRange = [deviceDescription portRangeList];
    _portBase = [portRange start];

    /* Get IRQ */
    _irqNumber = [deviceDescription interrupt];

    /* Get SROM address bits from config (default 6) */
    configTable = [deviceDescription configTable];
    configString = [[configTable valueForStringKey:"SROM Address Bits"] cString];
    if (configString != NULL && strcmp(configString, "8") == 0) {
        _sromAddressBits = 8;
    } else {
        _sromAddressBits = 6;
    }

    /* Get SROM address from config (default 0) - parse decimal */
    configString = [[configTable valueForStringKey:"SROM Address"] cString];
    if (configString == NULL) {
        _sromAddress = 0;
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
        _sromAddress = parsedValue;
    }

    /* Get vendor type from config (default 5 = Custom) */
    _vendorType = 5;
    configString = [[configTable valueForStringKey:"Vendor Type"] cString];
    if (configString != NULL) {
        for (i = 0; i < 5; i++) {
            if (strcmp(vendorNames[i], configString) == 0) {
                _vendorType = i;
                break;
            }
        }
    }

    /* Get media type from config (default 0 = 10BaseT) */
    _mediaType = 0;
    configString = [[configTable valueForStringKey:"Media Type"] cString];
    if (configString != NULL) {
        for (i = 0; i < 6; i++) {
            if (strcmp(mediaNames[i], configString) == 0) {
                _mediaType = i;
                break;
            }
        }
    }

    /* Get station (MAC) address from SROM */
    [self getStationAddress:&_stationAddress];

    /* Verify SROM checksum */
    if (![self verifyCheckSum]) {
        IOLog("%s: SROM checksum verification failed\n", [self name]);
        [self free];
        return nil;
    }

    /* Allocate memory for descriptor rings */
    if (![self allocateMemory]) {
        [self free];
        return nil;
    }

    /* Initialize state flags */
    _isEnabled = NO;
    _isAttached = NO;

    /* Log adapter information based on vendor type */
    if (_vendorID == 0x10b8) {
        IOLog("DECchip 21140 Cogent ANA-6911A/TX\n");
        IOLog("%s: auto-detecting the interface port\n", [self name]);
    } else {
        IOLog("DECchip 21140 based adapter\n");
        if (_mediaType == 0) {
            IOLog("Interface: 10 BaseT\n");
        } else {
            IOLog("Interface: %s\n", mediaNames[_mediaType]);
        }
    }

    /* Allocate debug netbuf for polling mode */
    _debugNetBuf = [self allocateNetbuf];
    if (_debugNetBuf == NULL) {
        IOLog("%s: Failed to allocate debug netbuf\n", [self name]);
        [self free];
        return nil;
    }

    /* Initialize polling mode flag */
    _isPollingMode = NO;

    /* Initialize chip hardware */
    if (![self initChip]) {
        [self free];
        return nil;
    }

    /* Initialize TX ring */
    if (![self initTxRing]) {
        [self free];
        return nil;
    }

    /* Attach to network with MAC address */
    superInfo.receiver = self;
    superInfo.class = objc_getClass("IOEthernet");
    _networkInterface = objc_msgSendSuper(&superInfo, @selector(attachToNetworkWithAddress:), &_stationAddress);

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
    [self resetChip];

    /* Free network interface if allocated */
    if (_networkInterface != nil) {
        [_networkInterface free];
    }

    /* Free all RX netbufs (64 buffers) */
    for (i = 0; i < DECCHIP21140_RX_RING_SIZE; i++) {
        if (_rxNetBufs[i] != NULL) {
            nb_free(_rxNetBufs[i]);
        }
    }

    /* Free all TX netbufs (32 buffers) */
    for (i = 0; i < DECCHIP21140_TX_RING_SIZE; i++) {
        if (_txNetBufs[i] != NULL) {
            nb_free(_txNetBufs[i]);
        }
    }

    /* Free descriptor memory if allocated */
    if (_descriptorMemory != NULL) {
        IOFreeLow(_descriptorMemory, _descriptorMemorySize);
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
- (IOReturn)resetAndEnable:(BOOL)enable
{
    return IO_R_SUCCESS;
}

/*
 * Enable adapter interrupts
 */
- (void)enableAdapterInterrupts
{
    /* Write interrupt mask to CSR7 (interrupt enable register) */
    outl(_portBase + 0x38, _linkStatus);
}

/*
 * Disable adapter interrupts
 */
- (void)disableAdapterInterrupts
{
    /* Write 0 to CSR7 (interrupt enable register) to disable all interrupts */
    outl(_portBase + 0x38, 0);
}

/*
 * Interrupt occurred
 */
- (void)interruptOccurred
{
}

/*
 * Timeout occurred
 */
- (void)timeoutOccurred
{
}

/*
 * Transmit a packet
 */
- (IOReturn)transmit:(netbuf_t)packet
{
    return IO_R_SUCCESS;
}

/*
 * Service transmit queue
 */
- (void)serviceTransmitQueue
{
}

/*
 * Get transmit queue count
 */
- (unsigned int)transmitQueueCount
{
    return 0;
}

/*
 * Get transmit queue size
 */
- (unsigned int)transmitQueueSize
{
    return 0;
}

/*
 * Get pending transmit count
 */
- (unsigned int)pendingTransmitCount
{
    return 0;
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
- (void)enablePromiscuousMode
{
    unsigned int csrValue;

    /* Set promiscuous mode flag */
    _isEnabled = YES;

    /* Reserve debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Read CSR6 command register */
    csrValue = inl(_portBase + 0x30);

    /* Set promiscuous mode bit (bit 6 = 0x40) */
    outl(_portBase + 0x30, csrValue | 0x40);

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    unsigned int csrValue;

    /* Clear promiscuous mode flag */
    _isEnabled = NO;

    /* Reserve debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Read CSR6 command register */
    csrValue = inl(_portBase + 0x30);

    /* Clear promiscuous mode bit (bit 6 = 0x40) */
    outl(_portBase + 0x30, csrValue & 0xFFFFFFBF);

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Enable multicast mode
 */
- (void)enableMulticastMode
{
    /* Mark as attached (multicast enabled) */
    _isAttached = YES;
}

/*
 * Disable multicast mode
 */
- (void)disableMulticastMode
{
    BOOL result;

    /* If attached (have multicast addresses), rebuild filter without them */
    if (_isAttached) {
        /* Reserve debugger lock for thread safety */
        [self reserveDebuggerLock];

        /* Rebuild address filtering */
        result = [self setAddressFiltering:NO];

        if (!result) {
            IOLog("%s: disable multicast mode failed\n", [self name]);
        }

        /* Release debugger lock */
        [self releaseDebuggerLock];
    }

    /* Mark as not attached (no multicast addresses) */
    _isAttached = NO;
}

/*
 * Add multicast address
 */
- (IOReturn)addMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;

    /* Mark that we're attached (have multicast addresses) */
    _isAttached = YES;

    /* Reserve debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Rebuild address filtering with new multicast address */
    result = [self setAddressFiltering:NO];

    if (!result) {
        IOLog("%s: add multicast address failed\n", [self name]);
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];

    return IO_R_SUCCESS;
}

/*
 * Remove multicast address
 */
- (IOReturn)removeMulticastAddress:(enet_addr_t *)addr
{
    return IO_R_SUCCESS;
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

/*
 * Get PCI configuration space
 */
+ (IOReturn)getPCIConfigSpace:(void *)configSpace
         withDeviceDescription:(IOPCIDeviceDescription *)deviceDesc
{
    IOReturn result;
    unsigned int reg;
    unsigned int *configData = (unsigned int *)configSpace;

    /* Read all 64 DWORDs (256 bytes) of PCI config space */
    for (reg = 0; reg < 64; reg++) {
        result = [deviceDesc getPCIConfigData:&configData[reg] atRegister:(reg * 4)];
        if (result != IO_R_SUCCESS) {
            return result;
        }
    }

    return IO_R_SUCCESS;
}

/*
 * Get PCI configuration data at specific register
 */
+ (IOReturn)getPCIConfigData:(unsigned int *)data
                  atRegister:(unsigned int)reg
       withDeviceDescription:(IOPCIDeviceDescription *)deviceDesc
{
    return [deviceDesc getPCIConfigData:data atRegister:reg];
}

/*
 * Set PCI configuration data at specific register
 */
+ (IOReturn)setPCIConfigData:(unsigned int)data
                  atRegister:(unsigned int)reg
       withDeviceDescription:(IOPCIDeviceDescription *)deviceDesc
{
    return [deviceDesc setPCIConfigData:data atRegister:reg];
}

@end
