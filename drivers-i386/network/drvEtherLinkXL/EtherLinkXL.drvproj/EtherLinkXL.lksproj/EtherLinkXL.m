/*
 * EtherLinkXL.m
 * 3Com EtherLink XL Network Driver - Main Implementation
 */

#import "EtherLinkXL.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>

/* Adapter Table - Maps PCI Device IDs to adapter names */
static const AdapterEntry adapterTable[] = {
    { 0x9000, "3C900-TPO" },
    { 0x9001, "3C900-COMBO" },
    { 0x9050, "3C905-TX" },
    { 0x9051, "3C905-T4" },
    { 0, NULL }
};

/* Media Table - Defines available media types and their configuration */
static const MediaEntry mediaTable[] = {
    { "10Base-T",   0x00C0, 0x08, 0x03, 0x05DC, 0 },
    { "AUI",        0x0008, 0x20, 0x07, 0x012C, 0 },
    { "BNC",        0x0000, 0x00, 0x00, 0x0000, 0 },
    { "MII",        0x0000, 0x10, 0x01, 0x012C, 0 },
    { "100Base-TX", 0x0080, 0x02, 0x05, 0x012C, 0 },
    { "100Base-T4", 0x0080, 0x04, 0x06, 0x012C, 0 },
    { "100Base-FX", 0x0000, 0x40, 0x00, 0x012C, 0 },
    { "MII-External", 0x0000, 0xFF, 0x07, 0x0000, 0 },
    { NULL, 0, 0, 0, 0, 0 }
};

@implementation EtherLinkXL

/*
 * PCI Configuration Space Structure
 */
typedef struct {
    unsigned int bar0;          /* Base Address Register 0 (I/O base) */
    unsigned int bar1;
    unsigned int bar2;
    unsigned int bar3;
    unsigned int bar4;
    unsigned int bar5;
    unsigned int cardbusCIS;
    unsigned short subsysVendorID;
    unsigned short subsysID;
    unsigned int expansionROMBase;
    unsigned int reserved1;
    unsigned int reserved2;
    unsigned char irqLine;
} PCIConfigData;

/*
 * Probe method - Called during driver discovery
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    unsigned char pciDevice, pciFunction, pciBus;
    PCIConfigData pciConfig;
    unsigned int portRange[4];
    unsigned int irqList[2];
    unsigned int commandReg;
    IOReturn result;
    id instance;
    const char *driverName;

    /* Get PCI device location */
    result = [deviceDescription getPCIdevice:&pciDevice function:&pciFunction bus:&pciBus];
    if (result != IO_R_SUCCESS) {
        driverName = [[self name] cString];
        IOLog("%s: Unsupported PCI hardware\n", driverName);
        return NO;
    }

    /* Log device location */
    driverName = [[self name] cString];
    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", driverName, pciDevice, pciFunction, pciBus);

    /* Read PCI configuration space */
    result = [self getPCIConfigSpace:&pciConfig withDeviceDescriptor:deviceDescription];
    if (result != IO_R_SUCCESS) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid PCI configuration space - aborting\n", driverName);
        return NO;
    }

    /* Set up I/O port range (BAR0, 64 bytes) */
    portRange[0] = pciConfig.bar0 & 0xFFFFFFFC;  /* Mask off indicator bits */
    portRange[1] = 0x40;                          /* 64 bytes */
    portRange[2] = 0;
    portRange[3] = 0;

    result = [deviceDescription setPortRangeList:portRange num:1];
    if (result != IO_R_SUCCESS) {
        driverName = [[self name] cString];
        IOLog("%s: Unable to reserve port range 0x%x-0x%x - aborting\n",
              driverName, portRange[0], portRange[0] + 0x3F);
        return NO;
    }

    /* Validate and set up IRQ */
    irqList[0] = pciConfig.irqLine;
    if (irqList[0] < 2 || irqList[0] > 15) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid IRQ level (%d) assigned by PCI BIOS\n", driverName, irqList[0]);
        return NO;
    }

    irqList[1] = 0;
    result = [deviceDescription setInterruptList:irqList num:1];
    if (result != IO_R_SUCCESS) {
        driverName = [[self name] cString];
        IOLog("%s: Unable to reserve IRQ %d - aborting\n", driverName, irqList[0]);
        return NO;
    }

    /* Read PCI command register */
    result = [self getPCIConfigData:&commandReg atRegister:4 withDeviceDescriptor:deviceDescription];
    if (result != IO_R_SUCCESS) {
        driverName = [[self name] cString];
        IOLog("%s: Unable to read PCI Bus Master bit - aborting\n", driverName);
        return NO;
    }

    /* Enable I/O space (bit 0) and Bus Master (bit 2), disable Memory space (bit 1) */
    commandReg = (commandReg & 0xFFFFFFFD) | 0x05;

    result = [self setPCIConfigData:commandReg atRegister:4 withDeviceDescriptor:deviceDescription];
    if (result != IO_R_SUCCESS) {
        driverName = [[self name] cString];
        IOLog("%s: Unable to set PCI Bus Master bit - aborting\n", driverName);
        return NO;
    }

    /* Allocate and initialize driver instance */
    instance = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (instance == nil) {
        driverName = [[self name] cString];
        IOLog("%s: Failed to alloc instance\n", driverName);
        return NO;
    }

    return YES;
}

/*
 * Initialize driver from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IOReturn result;
    unsigned int deviceID;
    int adapterIndex;
    IORange *portRange;
    unsigned int internalConfig;
    unsigned int mediaType;
    const char *mediumString;
    const char *fullDuplexString;
    const char *driverName;
    int i;
    unsigned short eepromData;
    unsigned short statusReg;
    int phyAddr;
    BOOL found;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Read PCI device ID to identify the adapter */
    result = [[self class] getPCIConfigData:&deviceID atRegister:0x00 withDeviceDescriptor:deviceDescription];
    if (result != IO_R_SUCCESS) {
        driverName = [[self name] cString];
        IOLog("%s: Failed to read PCI device ID\n", driverName);
        [self free];
        return nil;
    }

    /* Search adapter table for matching device ID */
    deviceID = (deviceID >> 16) & 0xFFFF;  /* Extract device ID from combined value */
    adapterIndex = 0;
    while (adapterTable[adapterIndex].deviceID != 0) {
        if (adapterTable[adapterIndex].deviceID == deviceID) {
            break;
        }
        adapterIndex++;
    }

    if (adapterTable[adapterIndex].deviceID == 0) {
        driverName = [[self name] cString];
        IOLog("%s: Unsupported device ID 0x%04x\n", driverName, deviceID);
        [self free];
        return nil;
    }

    /* Get I/O port base address */
    portRange = [deviceDescription portRangeList];
    ioBase = portRange[0].start;

    /* Get IRQ */
    irq = [deviceDescription interrupt];

    /* Initialize instance variables */
    currentWindow = 0xFF;           /* No window selected yet */
    isRunning = NO;
    requestedMedium = 7;            /* Default to auto-select */
    isPromiscuous = NO;
    isMulticast = NO;
    rxFilterByte = RX_FILTER_INDIVIDUAL | RX_FILTER_BROADCAST;  /* 0x05 */
    mediaOptions = 0;
    isFullDuplex = NO;

    /* Verify EEPROM checksum */
    if (![self verifyEEPROMChecksum]) {
        driverName = [[self name] cString];
        IOLog("%s: EEPROM checksum verification failed\n", driverName);
        [self free];
        return nil;
    }

    /* Read MAC address from EEPROM (window 0, stations 0-2) */
    /* Switch to window 0 */
    if (currentWindow != 0) {
        outw(ioBase + REG_COMMAND, CMD_SELECT_WINDOW(0));
        currentWindow = 0;
    }

    /* Read 3 words (6 bytes) of MAC address */
    for (i = 0; i < 3; i++) {
        /* Write EEPROM address (with bit 7 set for read) */
        outw(ioBase + 0x0A, i | 0x80);

        /* Wait for EEPROM busy flag to clear (bit 15) */
        for (int timeout = 50; timeout > 0; timeout--) {
            IODelay(1);
            statusReg = inw(ioBase + 0x0A);
            if ((statusReg & 0x8000) == 0) {
                break;
            }
        }

        /* Read data from EEPROM data register */
        eepromData = inw(ioBase + 0x0C);
        stationAddress.ea_byte[i * 2] = (eepromData >> 8) & 0xFF;
        stationAddress.ea_byte[i * 2 + 1] = eepromData & 0xFF;
    }

    /* Read adapter capabilities from window 3 */
    if (currentWindow != 3) {
        outw(ioBase + REG_COMMAND, CMD_SELECT_WINDOW(3));
        currentWindow = 3;
    }

    /* Read available media bitmap (bits 0-6 of register at offset 8) */
    availableMedia = inw(ioBase + 0x08) & 0x7F;

    /* Read internal configuration to get default medium */
    internalConfig = inl(ioBase + 0x00);

    /* Extract default medium (bits 20-22) */
    mediaType = (internalConfig >> 20) & 0x07;
    defaultMedium = mediaType;
    currentMedium = mediaType;

    /* Extract software information byte (bit 24) */
    softwareInfo = (internalConfig >> 24) & 0x01;

    /* Check for user-specified medium in config table */
    mediumString = [[deviceDescription configTable] valueForStringKey:"Medium"];
    if (mediumString != NULL) {
        /* Search media table for matching name */
        for (i = 0; i < 7; i++) {
            if (strcmp(mediumString, mediaTable[i].name) == 0) {
                currentMedium = i;
                break;
            }
        }
    }

    /* Validate medium selection */
    if (currentMedium > 6) {
        currentMedium = defaultMedium;
        driverName = [[self name] cString];
        IOLog("%s: Invalid medium specified, using default\n", driverName);
    }

    /* Check for full duplex configuration */
    fullDuplexString = [[deviceDescription configTable] valueForStringKey:"Full Duplex"];
    if (fullDuplexString != NULL) {
        if ((fullDuplexString[0] == 'y') || (fullDuplexString[0] == 'Y')) {
            isFullDuplex = YES;
        }
    }

    /* For 3C905 adapters (index 2), scan for MII PHY */
    interruptMask = 0xFFFF;  /* No PHY found yet */
    if (adapterIndex == 2) {
        for (phyAddr = 0; phyAddr < 32; phyAddr++) {
            /* Try to read from PHY register 0 */
            found = [self _miiReadWord:NULL reg:0 phy:phyAddr];
            if (found) {
                interruptMask = phyAddr;  /* Store PHY address in interruptMask temporarily */
                break;
            }
        }
    }

    /* Initialize hardware */
    if (![self __init]) {
        driverName = [[self name] cString];
        IOLog("%s: Hardware initialization failed\n", driverName);
        [self free];
        return nil;
    }

    /* Log successful initialization */
    driverName = [[self name] cString];
    IOLog("%s: Using %s port at 0x%x IRQ %d\n",
          driverName, mediaTable[currentMedium].name, ioBase, irq);

    /* Allocate temporary netbuf for KDB/debugger mode */
    txTempNetbuf = [self allocateNetbuf];
    if (txTempNetbuf == NULL) {
        driverName = [[self name] cString];
        IOLog("%s: Failed to allocate debugger netbuf\n", driverName);
        [self free];
        return nil;
    }

    /* Attach to network stack with our MAC address */
    networkInterface = [super attachToNetworkWithAddress:&stationAddress];

    return self;
}

/*
 * Reset and enable/disable the adapter
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    IOReturn result;

    /* Clear initialization complete flag */
    *(unsigned char *)(self + 0x18E) = 0;  /* Offset from decompiled code */

    /* Clear any pending timeouts */
    [self clearTimeout];

    /* Disable adapter interrupts */
    [self __disableAdapterInterrupts];

    /* If enabling, configure PHY and select medium */
    if (enable) {
        /* Configure PHY if present (interruptMask contains PHY address if != 0xFFFF) */
        if (interruptMask != 0xFFFF) {
            [self __configurePHY:interruptMask];
        }

        /* Auto-select best available medium */
        [self __autoSelectMedium];
    }

    /* Reset the chip */
    [self __resetChip];

    /* Initialize RX ring */
    if (![self __initRxRing]) {
        [self setRunning:NO];
        return NO;
    }

    /* Initialize TX queue */
    if (![self __initTxQueue]) {
        [self setRunning:NO];
        return NO;
    }

    /* Initialize hardware registers */
    if (![self __init]) {
        [self setRunning:NO];
        return NO;
    }

    /* Start transmit and receive engines */
    [self __startTransmit];
    [self __startReceive];

    /* If enabling, enable interrupts */
    if (enable) {
        result = [self enableAllInterrupts];
        if (result != IO_R_SUCCESS) {
            [self setRunning:NO];
            return NO;
        }

        /* Enable adapter interrupts */
        [self __enableAdapterInterrupts];
    }

    /* Update running state */
    [self setRunning:enable];

    /* Set initialization complete flag */
    *(unsigned char *)(self + 0x18E) = 1;

    return YES;
}

/*
 * Free driver resources
 */
- (void)free
{
    int i;

    /* Clear any pending timeouts */
    [self clearTimeout];

    /* Reset chip if it's running */
    if (isRunning) {
        [self __resetChip];
    }

    /* Free transmit queue */
    if (txQueue != nil) {
        [txQueue free];
    }

    /* Free all RX netbufs (64 entries) */
    for (i = 0; i < RX_RING_SIZE; i++) {
        if (rxNetbufArray[i] != NULL) {
            nb_free(rxNetbufArray[i]);
        }
    }

    /* Free all TX netbufs from both arrays (32 entries each) */
    for (i = 0; i < TX_RING_SIZE; i++) {
        /* Free netbufs from primary TX array */
        if ((txNetbufArray != NULL) && (txNetbufArray[i] != NULL)) {
            nb_free(txNetbufArray[i]);
        }
        /* Free netbufs from alternate TX array */
        if ((txNetbufArrayAlt != NULL) && (txNetbufArrayAlt[i] != NULL)) {
            nb_free(txNetbufArrayAlt[i]);
        }
    }

    /* Free descriptor memory (allocated with IOMallocLow) */
    if (descriptorMemBase != NULL) {
        IOFreeLow(descriptorMemBase, descriptorMemSize);
    }

    /* Free TX netbuf array (primary) */
    if (txNetbufArray != NULL) {
        IOFree(txNetbufArray, txNetbufArraySize);
    }

    /* Free TX netbuf array (alternate) */
    if (txNetbufArrayAlt != NULL) {
        IOFree(txNetbufArrayAlt, txNetbufArraySize);
    }

    /* Re-enable all system interrupts */
    [self enableAllInterrupts];

    /* Call superclass free */
    [super free];
}

/*
 * Verify EEPROM checksum
 */
- (BOOL)verifyEEPROMChecksum
{
    unsigned int checksumXOR = 0;
    unsigned short eepromData[24];
    int i;
    unsigned short statusReg;
    int timeout;

    /* Read all 24 words from EEPROM and calculate checksum */
    for (i = 0; i < 24; i++) {
        /* Switch to window 0 for EEPROM access */
        if (currentWindow != 0) {
            outw(ioBase + REG_COMMAND, CMD_SELECT_WINDOW(0));
            currentWindow = 0;
        }

        /* Wait for EEPROM ready (busy flag bit 15 clear) */
        timeout = 50;
        while (timeout > 0) {
            IODelay(200);
            statusReg = inw(ioBase + 0x0A);
            if ((statusReg & 0x8000) == 0) {
                break;  /* EEPROM ready */
            }
            timeout--;
        }

        /* Write EEPROM address with read command (bit 7 set) */
        outw(ioBase + 0x0A, (i & 0x3F) | 0x80);

        /* Wait for EEPROM busy flag to clear */
        timeout = 50;
        while (timeout > 0) {
            IODelay(200);
            statusReg = inw(ioBase + 0x0A);
            if ((statusReg & 0x8000) == 0) {
                break;
            }
            timeout--;
        }

        /* Read data from EEPROM data register */
        eepromData[i] = inw(ioBase + 0x0C);

        /* XOR into running checksum */
        checksumXOR ^= eepromData[i];
    }

    /* Valid checksum: low byte equals high byte of XOR result */
    return ((checksumXOR & 0xFF) == ((checksumXOR >> 8) & 0xFF));
}

/*
 * Enable promiscuous mode
 */
- (void)enablePromiscuousMode
{
    /* Set promiscuous bit (bit 3) in RX filter byte */
    rxFilterByte |= RX_FILTER_PROMISCUOUS;

    /* Acquire debugger lock before hardware access */
    [self reserveDebuggerLock];

    /* Send Set RX Filter command to hardware */
    outw(ioBase + REG_COMMAND, CMD_SET_RX_FILTER(rxFilterByte));

    /* Release debugger lock */
    [self releaseDebuggerLock];

    /* Update state flag */
    isPromiscuous = YES;
}

/*
 * Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    /* Clear promiscuous bit (bit 3) in RX filter byte */
    rxFilterByte &= ~RX_FILTER_PROMISCUOUS;

    /* Acquire debugger lock before hardware access */
    [self reserveDebuggerLock];

    /* Send Set RX Filter command to hardware */
    outw(ioBase + REG_COMMAND, CMD_SET_RX_FILTER(rxFilterByte));

    /* Release debugger lock */
    [self releaseDebuggerLock];

    /* Update state flag */
    isPromiscuous = NO;
}

/*
 * Enable multicast mode
 */
- (void)enableMulticastMode
{
    /* Set multicast bit (bit 1) in RX filter byte */
    rxFilterByte |= RX_FILTER_MULTICAST;

    /* Acquire debugger lock before hardware access */
    [self reserveDebuggerLock];

    /* Send Set RX Filter command to hardware */
    outw(ioBase + REG_COMMAND, CMD_SET_RX_FILTER(rxFilterByte));

    /* Release debugger lock */
    [self releaseDebuggerLock];

    /* Update state flag */
    isMulticast = YES;
}

/*
 * Disable multicast mode
 */
- (void)disableMulticastMode
{
    /* Clear multicast bit (bit 1) in RX filter byte */
    rxFilterByte &= ~RX_FILTER_MULTICAST;

    /* Acquire debugger lock before hardware access */
    [self reserveDebuggerLock];

    /* Send Set RX Filter command to hardware */
    outw(ioBase + REG_COMMAND, CMD_SET_RX_FILTER(rxFilterByte));

    /* Release debugger lock */
    [self releaseDebuggerLock];

    /* Update state flag */
    isMulticast = NO;
}

/*
 * Handle interrupt
 */
- (void)interruptOccurred
{
    unsigned short statusReg;
    BOOL txCompleted = NO;
    BOOL needAck;

    /* Loop while there are active interrupts */
    while (1) {
        /* Read status register */
        [self reserveDebuggerLock];
        statusReg = inw(ioBase + REG_STATUS);
        [self releaseDebuggerLock];

        /* Check if any enabled interrupts are active */
        if ((interruptMask & statusReg) == 0) {
            break;  /* No more interrupts to handle */
        }

        needAck = NO;

        /* Handle RX complete interrupt (bit 10 = 0x0400) */
        if ((statusReg & 0x0400) != 0) {
            [self __receiveInterruptOccurred];

            /* Acknowledge RX interrupt with special sequence */
            [self reserveDebuggerLock];
            outw(ioBase + REG_COMMAND, 0x6C01);  /* Set indication enable with RX complete */
            outw(ioBase + REG_COMMAND, 0x3001);  /* Acknowledge interrupt latch */
            [self releaseDebuggerLock];
        }

        /* Handle TX complete interrupt (bit 9 = 0x0200) */
        if ((statusReg & 0x0200) != 0) {
            [self clearTimeout];
            [self __transmitInterruptOccurred];
            txCompleted = YES;
            needAck = YES;
        }

        /* Handle statistics interrupt (bit 15 = 0x8000) */
        if ((statusReg & 0x8000) != 0) {
            [self __updateStatsInterruptOccurred];
            needAck = YES;
        }

        /* Handle TX error interrupt (bit 2 = 0x0004) */
        if ((statusReg & 0x0004) != 0) {
            [self __transmitErrorInterruptOccurred];
            needAck = YES;
        }

        /* Acknowledge interrupt if needed */
        if (needAck) {
            [self reserveDebuggerLock];
            /* Set indication enable, preserving bits except RX/TX complete (mask 0x6BFF) */
            outw(ioBase + REG_COMMAND, (statusReg & 0x6BFF) | 0x6801);
            [self releaseDebuggerLock];
        }
    }

    /* If TX completed, check if there are more packets to send */
    if (txCompleted) {
        [self reserveDebuggerLock];

        /* If TX queue has packets and no transmission pending */
        if ((txHead != 0) && !txPending) {
            unsigned int queueDepth = txHead;

            /* Flush the current TX queue */
            [self __switchQueuesAndTransmitWithTimeout:1];

            /* If queue was nearly full, service the transmit queue */
            if (queueDepth >= 32) {
                [self serviceTransmitQueue];
            }
        }

        [self releaseDebuggerLock];
    }

    /* Re-enable system interrupts */
    [self enableAllInterrupts];
}

/*
 * Handle timeout
 */
- (void)timeoutOccurred
{
    unsigned short statusReg;
    int timeout;
    IOReturn result;
    const char *driverName;

    /* Stop DMA by issuing command 0 */
    outw(ioBase + REG_COMMAND, 0x0000);

    /* Wait for DMA in-progress bit (bit 12 = 0x1000) to clear */
    timeout = 1000000;  /* 1 second in microseconds */
    while (timeout > 0) {
        statusReg = inw(ioBase + REG_STATUS);
        if ((statusReg & 0x1000) == 0) {
            break;  /* DMA stopped */
        }
        IODelay(1);
        timeout--;
    }

    /* Disable adapter interrupts */
    [self __disableAdapterInterrupts];

    /* Reconfigure current medium */
    [self __setCurrentMedium];

    /* Reinitialize RX ring */
    if (![self __initRxRing]) {
        [self setRunning:NO];
        driverName = [[self name] cString];
        IOLog("%s: timeout: initRxRing / initTxQueue failed\n", driverName);
        return;
    }

    /* Reinitialize TX queue */
    if (![self __initTxQueue]) {
        [self setRunning:NO];
        driverName = [[self name] cString];
        IOLog("%s: timeout: initRxRing / initTxQueue failed\n", driverName);
        return;
    }

    /* Reinitialize hardware */
    if (![self __init]) {
        [self setRunning:NO];
        driverName = [[self name] cString];
        IOLog("%s: timeout: init failed\n", driverName);
        return;
    }

    /* Restart transmit and receive engines */
    [self __startTransmit];
    [self __startReceive];

    /* Re-enable system interrupts */
    result = [self enableAllInterrupts];
    if (result != IO_R_SUCCESS) {
        [self setRunning:NO];
        driverName = [[self name] cString];
        IOLog("%s: timeout: enableAllInterrupts failed\n", driverName);
        return;
    }

    /* Re-enable adapter interrupts */
    [self __enableAdapterInterrupts];
}

/*
 * Transmit a packet
 */
- (void)transmit:(netbuf_t)packet
{
    int queueCount;
    const char *driverName;

    /* Check for NULL netbuf */
    if (packet == NULL) {
        driverName = [[self name] cString];
        IOLog("%s: transmit: received NULL netbuf\n", driverName);
        return;
    }

    /* Check if adapter is running */
    if (!isRunning) {
        /* Not running - free the packet */
        nb_free(packet);
        return;
    }

    /* Acquire debugger lock for thread-safe operation */
    [self reserveDebuggerLock];

    /* Service any pending transmit queue entries */
    [self serviceTransmitQueue];

    /* Check if we can transmit immediately */
    if (txHead < TX_RING_SIZE) {
        /* Check if software queue is empty */
        queueCount = [txQueue count];
        if (queueCount == 0) {
            /* TX ring has space and queue is empty - transmit immediately with flush */
            [self __transmitPacket:packet flush:YES];
        } else {
            /* Queue has packets - enqueue this one too */
            [txQueue enqueue:packet];
        }
    } else {
        /* TX ring is full - enqueue to software queue */
        [txQueue enqueue:packet];
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Service transmit queue
 */
- (void)serviceTransmitQueue
{
    unsigned int queueDepth;
    int queueCount;
    netbuf_t packet;

    /* Get current TX queue depth */
    queueDepth = txHead;

    /* While TX queue has space and packets are waiting */
    while (queueDepth < TX_RING_SIZE) {
        /* Check if there are packets in the queue */
        queueCount = [txQueue count];
        if (queueCount == 0) {
            break;  /* No more packets */
        }

        /* Dequeue next packet */
        packet = [txQueue dequeue];
        if (packet == NULL) {
            break;  /* Queue empty */
        }

        /* Transmit the packet (no flush yet) */
        [self __transmitPacket:packet flush:NO];

        /* Update queue depth */
        queueDepth = txHead;
    }
}

/*
 * Allocate network buffer
 * Allocates a 1514-byte buffer with 32-byte alignment for DMA
 */
- (netbuf_t)allocateNetbuf
{
    netbuf_t netbuf;
    unsigned int bufferAddr;
    unsigned int alignmentOffset;
    unsigned int finalSize;

    /* Allocate buffer with extra space for alignment (1546 bytes = 0x60A) */
    netbuf = nb_alloc(0x60A);
    if (netbuf == NULL) {
        return NULL;
    }

    /* Map buffer to get virtual address */
    bufferAddr = (unsigned int)nb_map(netbuf);

    /* Check 32-byte alignment (address & 0x1F should be 0) */
    alignmentOffset = bufferAddr & 0x1F;
    if (alignmentOffset != 0) {
        /* Shrink from top to make buffer 32-byte aligned */
        nb_shrink_top(netbuf, 0x20 - alignmentOffset);
    }

    /* Get current buffer size and shrink to exactly 1514 bytes (0x5EA) */
    finalSize = nb_size(netbuf);
    nb_shrink_bot(netbuf, finalSize - 0x5EA);

    return netbuf;
}

/*
 * Set running state
 */
- (void)setRunning:(BOOL)running
{
    /* Call superclass to update network interface state */
    [super setRunning:running];

    /* Update our running flag */
    isRunning = running;
}

@end
