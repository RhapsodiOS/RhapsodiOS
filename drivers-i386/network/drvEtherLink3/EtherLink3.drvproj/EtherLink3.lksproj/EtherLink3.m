/*
 * EtherLink3.m
 * 3Com EtherLink III Network Driver - Main Implementation
 */

#import "EtherLink3.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <machkit/NXLock.h>

/* Forward declarations for utility functions */
static void __resetFunc(void *arg);
static void _intHandler(void *identity, void *state, unsigned int arg);
static netbuf_t _QDequeue(NetbufQueue *queue);
static void _QEnqueue(NetbufQueue *queue, netbuf_t netbuf);

@implementation EtherLink3

/*
 * Probe method - Called during driver discovery (ISA bus)
 * This performs ISA ID detection sequence for 3Com EtherLink III cards
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    EtherLink3 *driver;
    IORange *portRange;
    unsigned short ioBase;
    unsigned short vendorID, productID;
    unsigned int irq;
    int numInterrupts, numPorts;
    unsigned char idSeq;
    int i;
    BOOL carry;

    /* Allocate driver instance */
    driver = [[self alloc] init];
    if (driver == nil) {
        return NO;
    }

    /* Check if interrupt is configured */
    numInterrupts = [deviceDescription numInterrupts];
    if (numInterrupts == 0) {
        IOLog("EtherLinkIII: Interrupt level not configured - aborting\n");
        [driver free];
        return NO;
    }

    /* Check if I/O ports are configured */
    numPorts = [deviceDescription numPortRanges];
    if (numPorts == 0) {
        IOLog("EtherLinkIII: I/O ports not configured - aborting\n");
        [driver free];
        return NO;
    }

    /* Get port range */
    portRange = [deviceDescription portRangeList];
    if (portRange == NULL || portRange->size < 16) {
        [driver free];
        return NO;
    }

    /* Perform ISA ID sequence on ID port 0x110 */
    /* Send ID sequence to activate card */
    outb(EL3_ID_PORT, 0xC0);
    IOSleep(1);  /* Wait 1ms */
    outb(EL3_ID_PORT, 0x00);
    outb(EL3_ID_PORT, 0x00);

    /* Generate ID sequence (255 iterations of LFSR) */
    idSeq = 0xFF;
    for (i = 0; i < 255; i++) {
        outb(EL3_ID_PORT, idSeq);

        /* LFSR shift with polynomial 0xCF */
        carry = (idSeq & 0x80) != 0;
        idSeq <<= 1;
        if (carry) {
            idSeq ^= 0xCF;
        }
    }
    outb(EL3_ID_PORT, 0xFF);

    /* Read card ID from configured I/O base */
    ioBase = portRange->start;
    vendorID = inw(ioBase);
    productID = inw(ioBase + 2);

    /* Check for 3Com EtherLink III (vendor 0x6d50, product 0x90xx) */
    if (vendorID == EL3_VENDOR_ID && (productID & 0xF0FF) == EL3_PRODUCT_ID) {
        /* Found EtherLink III card */
        [driver setISA:YES];
        [driver setIOBase:ioBase];

        irq = [deviceDescription interrupt];
        [driver setIRQ:irq];

        [driver setDoAuto:NO];

        /* Initialize the driver */
        if ([driver initFromDeviceDescription:deviceDescription] != nil) {
            return YES;
        }
    } else {
        IOLog("EtherLinkIII: ISA adapter not found at address 0x%04x - aborting\n", ioBase);
    }

    [driver free];
    return NO;
}

/*
 * Initialize driver from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    id deviceTable;
    const char *connectorString;
    const char *connectorTypes[3] = {"AUI", "BNC", "RJ-45"};
    BOOL connectorFound = NO;
    unsigned short productID;
    unsigned short configReg;
    unsigned short statusReg;
    unsigned short addressData;
    int i;
    const char *modelName;
    unsigned int slotOrPort;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        [self free];
        return nil;
    }

    /* Get device table from device description */
    deviceTable = [deviceDescription deviceTable];

    /* Initialize current window to 0xFF (invalid) */
    currentWindow = 0xFF;

    /* Switch to window 0 */
    outw(ioBase + 0x0E, 0x0800);
    currentWindow = 0x00;

    /* Read product ID from window 0, offset 2 */
    productID = inw(ioBase + 0x02);

    /* Check for connector type in configuration */
    connectorString = [[deviceTable valueForStringKey:"Connector"] cString];
    if (connectorString != NULL) {
        /* Try to match connector string */
        for (i = 0; i < 3; i++) {
            if (strcmp(connectorString, connectorTypes[i]) == 0) {
                connectorType = i;
                connectorFound = YES;
                break;
            }
        }
        /* Free the string */
        IOFree((void *)connectorString, strlen(connectorString) + 1);
    }

    /* If no connector specified, try to detect from hardware */
    if (!connectorFound) {
        /* Switch to window 0 */
        if (currentWindow != 0x00) {
            outw(ioBase + 0x0E, 0x0800);
            currentWindow = 0x00;
        }

        /* Read configuration register at offset 6 */
        configReg = inw(ioBase + 0x06);

        /* Check if auto-select bit is set (bit 7) */
        if ((configReg & 0x0080) == 0) {
            /* No auto-select - read connector bits from config register */
            if (currentWindow != 0x00) {
                outw(ioBase + 0x0E, 0x0800);
                currentWindow = 0x00;
            }
            configReg = inw(ioBase + 0x06);

            /* Extract connector type from bits 14-15 */
            configReg >>= 14;
            if (configReg == 1) {
                connectorType = CONNECTOR_AUI;
            } else if (configReg < 2 || configReg != 3) {
                connectorType = CONNECTOR_RJ45;
            } else {
                connectorType = CONNECTOR_BNC;
            }
        } else {
            /* Auto-select enabled */
            doAutoDetect = YES;
        }
    }

    /* Set RX filter byte to 5 (station and broadcast) */
    rxFilterByte = 0x05;

    /* Read MAC address from EEPROM via window 0, register 10 */
    if (currentWindow != 0x00) {
        outw(ioBase + 0x0E, 0x0800);
        currentWindow = 0x00;
    }

    /* Wait for EEPROM busy flag to clear */
    do {
        statusReg = inw(ioBase + 0x0A);
    } while ((short)statusReg < 0);

    /* Read 3 words (6 bytes) of MAC address from EEPROM */
    for (i = 0; i < 3; i++) {
        /* Issue EEPROM read command (0x80 | address) */
        outw(ioBase + 0x0A, 0x0080 | (i & 0x3F));

        /* Wait for EEPROM busy flag to clear */
        do {
            statusReg = inw(ioBase + 0x0A);
        } while ((short)statusReg < 0);

        /* Read data from EEPROM data register at offset 0x0C */
        addressData = inw(ioBase + 0x0C);

        /* Store MAC address bytes (big endian) */
        stationAddress.ea_byte[i * 2] = (unsigned char)(addressData >> 8);
        stationAddress.ea_byte[i * 2 + 1] = (unsigned char)addressData;
    }

    /* Read product ID again and write to offset 0x0C */
    addressData = inw(ioBase + 0x02);
    outw(ioBase + 0x0C, addressData);

    /* Reset and enable the hardware */
    [self resetAndEnable:NO];

    /* Determine model name from product ID */
    switch (productID) {
        case 0x9050: modelName = "3C509-TP"; break;
        case 0x9058: modelName = "3C589"; break;
        case 0x9150: modelName = "3C509"; break;
        case 0x9250: modelName = "3C579-TP"; break;
        case 0x9350: modelName = "3C579"; break;
        case 0x9450: modelName = "3C509 Combo"; break;
        case 0x9550: modelName = "3C509-TPO"; break;
        default: modelName = ""; break;
    }

    /* Log device information - format depends on bus type */
    if (productID == 0x9350 || productID == 0x9250) {
        /* EISA card - log with slot number */
        slotOrPort = (ioBase >> 12);
        IOLog("3Com EtherLink III %s in slot %d irq %d using %s\n",
              modelName, slotOrPort, irq, connectorTypes[connectorType]);
    } else {
        /* ISA/PCMCIA - log with I/O port */
        slotOrPort = ioBase;
        IOLog("3Com EtherLink III %s at port 0x%x irq %d using %s\n",
              modelName, slotOrPort, irq, connectorTypes[connectorType]);
    }

    /* Attach to network with MAC address */
    networkInterface = [super attachToNetworkWithAddress:stationAddress];

    /* Initialize all queue structures */
    rxQueue.head = NULL;
    rxQueue.tail = NULL;
    rxQueue.count = 0;
    rxQueue.max = 0x80;  /* 128 packets */

    txQueue.head = NULL;
    txQueue.tail = NULL;
    txQueue.count = 0;
    txQueue.max = 0x10;  /* 16 packets */

    txPendingQueue.head = NULL;
    txPendingQueue.tail = NULL;
    txPendingQueue.count = 0;
    txPendingQueue.max = 0x40;  /* 64 packets */

    freeNetbufQueue.head = NULL;
    freeNetbufQueue.tail = NULL;
    freeNetbufQueue.count = 0;
    freeNetbufQueue.max = 0x20;  /* 32 packets */

    return self;
}

/*
 * Reset and enable/disable the adapter
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    netbuf_t netbuf;
    IOReturn result;

    /* Disable interrupts during reset */
    interruptDisabled = YES;
    isRunning = NO;

    /* Fill receive buffer queue */
    [self QFill:&freeNetbufQueue];

    /* Flush TX queue */
    while ((netbuf = _QDequeue(&txQueue)) != NULL) {
        nb_free(netbuf);
    }

    /* Flush TX pending queue */
    while ((netbuf = _QDequeue(&txPendingQueue)) != NULL) {
        nb_free(netbuf);
    }

    /* Flush RX queue */
    while ((netbuf = _QDequeue(&rxQueue)) != NULL) {
        nb_free(netbuf);
    }

    /* Disable all interrupts */
    [self disableAllInterrupts];

    /* Initialize hardware */
    if (![self __hwInit]) {
        [self setRunning:NO];
        return NO;
    }

    /* If enable flag is set, enable interrupts and set timeout */
    if (enable) {
        result = [self enableAllInterrupts];
        if (result != IO_R_SUCCESS) {
            [self setRunning:NO];
            return NO;
        }

        /* Set 2 second timeout */
        [self setRelativeTimeout:2000];
    }

    /* Update running state */
    [self setRunning:enable];

    /* Re-enable interrupts */
    interruptDisabled = NO;

    return YES;
}

/*
 * Free driver resources
 */
- (void)free
{
    netbuf_t netbuf;

    /* Free all netbufs in free netbuf queue */
    while ((netbuf = _QDequeue(&freeNetbufQueue)) != NULL) {
        nb_free(netbuf);
    }

    /* Free all netbufs in TX pending queue */
    while ((netbuf = _QDequeue(&txPendingQueue)) != NULL) {
        nb_free(netbuf);
    }

    /* Free all netbufs in TX queue */
    while ((netbuf = _QDequeue(&txQueue)) != NULL) {
        nb_free(netbuf);
    }

    /* Free all netbufs in RX queue */
    while ((netbuf = _QDequeue(&rxQueue)) != NULL) {
        nb_free(netbuf);
    }

    /* Free network interface */
    if (networkInterface != nil) {
        [networkInterface free];
    }

    /* Call superclass free */
    [super free];
}

/*
 * Set I/O base address
 */
- (void)setIOBase:(unsigned short)base
{
    ioBase = base;
}

/*
 * Set IRQ
 */
- (void)setIRQ:(unsigned short)interrupt
{
    irq = interrupt;
}

/*
 * Set ISA flag
 */
- (void)setISA:(BOOL)flag
{
    isISA = flag;
}

/*
 * Set auto-detect flag
 */
- (void)setDoAuto:(BOOL)flag
{
    doAutoDetect = flag;
}

/*
 * Enable promiscuous mode
 * Sets bit 3 in RX filter to enable promiscuous mode
 */
- (BOOL)enablePromiscuousMode
{
    unsigned short filterCmd;

    /* Set promiscuous bit (bit 3 = 0x08) in RX filter byte */
    rxFilterByte |= 0x08;

    /* Send RX filter command (0x8000 | filter byte) */
    filterCmd = 0x8000 | (unsigned short)rxFilterByte;
    outw(ioBase + 0x0E, filterCmd);

    isPromiscuous = YES;
    return YES;
}

/*
 * Disable promiscuous mode
 * Clears bit 3 in RX filter to disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    unsigned short filterCmd;

    /* Clear promiscuous bit (bit 3 = 0x08) in RX filter byte */
    rxFilterByte &= 0xF7;  /* 0xF7 = ~0x08 */

    /* Send RX filter command (0x8000 | filter byte) */
    filterCmd = 0x8000 | (unsigned short)rxFilterByte;
    outw(ioBase + 0x0E, filterCmd);

    isPromiscuous = NO;
}

/*
 * Enable multicast mode
 * Sets bit 1 in RX filter to enable multicast mode
 */
- (BOOL)enableMulticastMode
{
    unsigned short filterCmd;

    /* Set multicast bit (bit 1 = 0x02) in RX filter byte */
    rxFilterByte |= 0x02;

    /* Send RX filter command (0x8000 | filter byte) */
    filterCmd = 0x8000 | (unsigned short)rxFilterByte;
    outw(ioBase + 0x0E, filterCmd);

    isMulticast = YES;
    return YES;
}

/*
 * Disable multicast mode
 * Clears bit 1 in RX filter to disable multicast mode
 */
- (void)disableMulticastMode
{
    unsigned short filterCmd;

    /* Clear multicast bit (bit 1 = 0x02) in RX filter byte */
    rxFilterByte &= 0xFD;  /* 0xFD = ~0x02 */

    /* Send RX filter command (0x8000 | filter byte) */
    filterCmd = 0x8000 | (unsigned short)rxFilterByte;
    outw(ioBase + 0x0E, filterCmd);

    isMulticast = NO;
}

/*
 * Handle interrupt
 */
- (void)interruptOccurred
{
    netbuf_t netbuf;
    unsigned int packetData;
    unsigned int savedIPL;

    /* Mark that we're in interrupt occurred */
    isRunning = YES;

    /* Check if interrupts are disabled - if so, schedule a reset */
    if (interruptDisabled) {
        [self __scheduleReset];
        return;
    }

    /* Process all received packets from RX queue */
    while (1) {
        /* Raise IPL and dequeue packet */
        savedIPL = spldevice();
        netbuf = _QDequeue(&rxQueue);

        if (netbuf == NULL) {
            break;
        }

        /* Lower IPL before processing */
        splx(savedIPL);

        /* Get packet data pointer */
        packetData = (unsigned int)nb_map(netbuf);

        /* Check if this is an unwanted multicast packet */
        if ([super isUnwantedMulticastPacket:(void *)packetData] == NO) {
            /* Pass packet to network interface */
            [networkInterface handleInputPacket:netbuf extra:0];
        } else {
            /* Free unwanted packet */
            nb_free(netbuf);
        }
    }

    /* Process TX pending queue (free completed transmissions) */
    while (1) {
        savedIPL = spldevice();
        netbuf = _QDequeue(&txPendingQueue);

        if (netbuf == NULL) {
            break;
        }

        splx(savedIPL);
        nb_free(netbuf);
    }

    /* Update statistics if any errors occurred */
    if (rxErrors != 0) {
        [networkInterface incrementInputErrorsBy:rxErrors];
        rxErrors = 0;
    }

    if (txErrors != 0) {
        [networkInterface incrementOutputErrorsBy:txErrors];
        txErrors = 0;
    }

    if (txSuccess != 0) {
        [networkInterface incrementOutputPacketsBy:txSuccess];
        txSuccess = 0;
    }

    if (txCollisions != 0) {
        [networkInterface incrementCollisionsBy:txCollisions];
        txCollisions = 0;
    }

    splx(savedIPL);

    /* Refill receive buffers */
    [self QFill:&freeNetbufQueue];
}

/*
 * Handle timeout
 * Called periodically to check driver health
 */
- (void)timeoutOccurred
{
    /* Check if driver is running and interrupts enabled */
    if ([self isRunning] && !interruptDisabled) {
        /* Check if we've received interrupts or TX queue is empty */
        if (isRunning || txQueue.count == 0) {
            /* Activity detected - clear flag and reschedule */
            isRunning = NO;
            [self setRelativeTimeout:2000];
        } else {
            /* No activity - schedule a reset */
            [self __scheduleReset];
        }
    }
}

/*
 * Get interrupt handler
 */
- (void)getHandler:(IOInterruptHandler *)handler
            level:(unsigned int *)ipl
         argument:(void **)arg
     forInterrupt:(unsigned int)localInterrupt
{
    *handler = _intHandler;
    *ipl = 3;
    *arg = (void *)self;
}

/*
 * Transmit a packet
 */
- (void)transmit:(netbuf_t)packet
{
    netbuf_t queuedPacket;
    unsigned int *dataPtr;
    unsigned int packetSize;
    unsigned int wordCount;
    unsigned int byteRemainder;
    unsigned int padBytes;
    unsigned short txFreeSpace;
    unsigned int savedIPL;
    unsigned int i;

    /* Check if adapter is running and interrupts enabled */
    if (![self isRunning] || interruptDisabled) {
        nb_free(packet);
        return;
    }

    /* Pad packet to minimum 60 bytes if needed */
    packetSize = nb_size(packet);
    if (packetSize < 60) {
        nb_grow_bot(packet, 60 - packetSize);
    }

    /* Perform loopback if needed */
    [self performLoopback:packet];

    /* Raise IPL */
    savedIPL = spldevice();

    /* Service TX queue - transmit queued packets if FIFO has space */
    while (txPendingQueue.count < txPendingQueue.max && txQueue.count > 0) {
        /* Check FIFO free space at window 3, offset 0x0C */
        if (currentWindow != 0x03) {
            outw(ioBase + 0x0E, 0x0803);
            currentWindow = 0x03;
        }
        txFreeSpace = inw(ioBase + 0x0C);

        /* Get size of packet at head of queue */
        packetSize = nb_size(txQueue.head);

        /* Check if FIFO has enough space (packet size + 50 bytes margin) */
        if (txFreeSpace - 50 < packetSize) {
            break;
        }

        /* Dequeue packet from TX queue */
        queuedPacket = _QDequeue(&txQueue);
        dataPtr = (unsigned int *)nb_map(queuedPacket);
        packetSize = nb_size(queuedPacket);

        /* Switch to window 1 for transmit */
        if (currentWindow != 0x01) {
            outw(ioBase + 0x0E, 0x0801);
            currentWindow = 0x01;
        }

        /* Write TX preamble (0x8000 | packet size) */
        outl(ioBase, 0x8000 | (packetSize & 0x7FF));

        /* Write packet data in 32-bit chunks */
        wordCount = packetSize >> 2;
        for (i = 0; i < wordCount; i++) {
            outl(ioBase, dataPtr[i]);
        }

        /* Write remaining bytes */
        byteRemainder = packetSize & 3;
        if (byteRemainder > 0) {
            unsigned char *bytePtr = (unsigned char *)&dataPtr[wordCount];
            for (i = 0; i < byteRemainder; i++) {
                outb(ioBase, bytePtr[i]);
            }

            /* Pad to 4-byte boundary */
            padBytes = 4 - byteRemainder;
            for (i = 0; i < padBytes; i++) {
                outb(ioBase, 0);
            }
        }

        /* Enqueue to TX pending queue */
        _QEnqueue(&txPendingQueue, queuedPacket);
    }

    /* Flush TX pending queue - free completed transmissions */
    while ((queuedPacket = _QDequeue(&txPendingQueue)) != NULL) {
        splx(savedIPL);
        nb_free(queuedPacket);
        savedIPL = spldevice();
    }

    /* Try to transmit new packet directly if TX queue is empty */
    if (txQueue.count == 0) {
        /* Check FIFO free space */
        if (currentWindow != 0x03) {
            outw(ioBase + 0x0E, 0x0803);
            currentWindow = 0x03;
        }
        txFreeSpace = inw(ioBase + 0x0C);

        packetSize = nb_size(packet);

        /* If FIFO has enough space, transmit immediately */
        if (txFreeSpace - 50 >= packetSize) {
            dataPtr = (unsigned int *)nb_map(packet);

            /* Switch to window 1 */
            if (currentWindow != 0x01) {
                outw(ioBase + 0x0E, 0x0801);
                currentWindow = 0x01;
            }

            /* Write TX preamble */
            outl(ioBase, 0x8000 | (packetSize & 0x7FF));

            /* Write data in dwords */
            wordCount = packetSize >> 2;
            for (i = 0; i < wordCount; i++) {
                outl(ioBase, dataPtr[i]);
            }

            /* Write remaining bytes */
            byteRemainder = packetSize & 3;
            if (byteRemainder > 0) {
                unsigned char *bytePtr = (unsigned char *)&dataPtr[wordCount];
                for (i = 0; i < byteRemainder; i++) {
                    outb(ioBase, bytePtr[i]);
                }

                /* Pad to 4-byte boundary */
                padBytes = 4 - byteRemainder;
                for (i = 0; i < padBytes; i++) {
                    outb(ioBase, 0);
                }
            }

            /* Packet transmitted - free it and lower IPL */
            splx(savedIPL);
            nb_free(packet);
            return;
        }
    }

    /* FIFO full or TX queue has packets - enqueue this packet */
    _QEnqueue(&txQueue, packet);

    splx(savedIPL);
}

/*
 * Get transmit queue size (max capacity)
 */
- (unsigned int)transmitQueueSize
{
    return txQueue.max;
}

/*
 * Get transmit queue count (current count)
 */
- (unsigned int)transmitQueueCount
{
    return txQueue.count;
}

/*
 * Allocate network buffer
 */
- (netbuf_t)allocateNetbuf
{
    netbuf_t netbuf;
    unsigned int dataPtr;
    unsigned int alignedPtr;
    unsigned int size;

    /* Allocate buffer of 1518 bytes (0x5ee) */
    netbuf = nb_alloc(0x5ee);

    /* Get data pointer and ensure 4-byte alignment */
    dataPtr = (unsigned int)nb_map(netbuf);
    if ((dataPtr & 3) != 0) {
        /* Not aligned - shrink top to align */
        alignedPtr = (dataPtr + 3) & 0xFFFFFFFC;
        nb_shrink_top(netbuf, alignedPtr - dataPtr);
    }

    /* Shrink bottom to make buffer exactly 1514 bytes (0x5ea) */
    size = nb_size(netbuf);
    nb_shrink_bot(netbuf, size - 0x5ea);

    return netbuf;
}

/*
 * Fill queue with pre-allocated netbuf buffers up to max capacity
 */
- (void)QFill:(NetbufQueue *)queue
{
    netbuf_t netbuf;
    unsigned int savedIPL;

    /* Allocate buffers until queue reaches its max capacity */
    while (queue->count < queue->max) {
        /* Allocate a netbuf */
        netbuf = [self allocateNetbuf];
        if (netbuf == NULL) {
            /* Allocation failed - stop filling */
            return;
        }

        /* Raise IPL before modifying queue */
        savedIPL = spldevice();

        /* Check again that queue is not full (race condition protection) */
        if (queue->count < queue->max) {
            /* Enqueue the netbuf */
            _QEnqueue(queue, netbuf);
        } else {
            /* Queue became full - free the netbuf */
            IOLog("EtherLink III: queue exceeded max %d - freeing netbuf\n", queue->max);
            nb_free(netbuf);
        }

        /* Lower IPL */
        splx(savedIPL);
    }
}

/*
 * Get power management capabilities
 */
- (IOReturn)getPowerManagement:(void *)powerManagement
{
    return IO_R_UNSUPPORTED;
}

/*
 * Get power state
 */
- (IOReturn)getPowerState:(void *)powerState
{
    return IO_R_UNSUPPORTED;
}

/*
 * Set power management level
 */
- (IOReturn)setPowerManagement:(unsigned int)powerLevel
{
    return IO_R_UNSUPPORTED;
}

/*
 * Set power state
 * If powerState == 3 (PM_OFF), perform hardware shutdown
 */
- (IOReturn)setPowerState:(unsigned int)powerState
{
    unsigned short reg4Value;

    /* Only handle powerState 3 (power off) */
    if (powerState != 3) {
        return IO_R_UNSUPPORTED;
    }

    /* Clear any pending timeout */
    [self clearTimeout];

    /* Disable interrupts at hardware level */
    /* Switch to window 0 */
    if (currentWindow != 0x00) {
        outw(ioBase + 0x0E, 0x0800);
        currentWindow = 0x00;
    }

    /* Read and clear interrupt enable bit in register at offset 4 */
    reg4Value = inw(ioBase + 0x04);

    if (currentWindow != 0x00) {
        outw(ioBase + 0x0E, 0x0800);
        currentWindow = 0x00;
    }

    /* Clear bit 0 to disable interrupts */
    reg4Value &= 0xFFFE;
    outw(ioBase + 0x04, reg4Value);

    /* Reset hardware */
    outw(ioBase + 0x0E, 0x2800);  /* RX reset */
    outw(ioBase + 0x0E, 0x5800);  /* TX reset */
    outw(ioBase + 0x0E, 0x1800);  /* RX disable */
    outw(ioBase + 0x0E, 0x5000);  /* TX disable */

    return IO_R_SUCCESS;
}

/*
 * Enable all interrupts
 * Enables adapter interrupts by setting bit 0 in register at window 0, offset 4
 * Also configures IRQ level in high 4 bits of register at offset 8
 */
- (IOReturn)enableAllInterrupts
{
    unsigned short reg4Value;
    unsigned short reg8Value;

    /* Switch to window 0 if needed */
    if (currentWindow != 0x00) {
        outw(ioBase + 0x0E, 0x0800);
        currentWindow = 0x00;
    }

    /* Read current value of register at offset 4 */
    reg4Value = inw(ioBase + 0x04);

    /* Switch to window 0 again if needed */
    if (currentWindow != 0x00) {
        outw(ioBase + 0x0E, 0x0800);
        currentWindow = 0x00;
    }

    /* Read current value of register at offset 8 */
    reg8Value = inw(ioBase + 0x08);

    /* Switch to window 0 again if needed */
    if (currentWindow != 0x00) {
        outw(ioBase + 0x0E, 0x0800);
        currentWindow = 0x00;
    }

    /* Configure IRQ in high 4 bits (bits 12-15), preserve low 12 bits */
    reg8Value = (reg8Value & 0x0FFF) | ((unsigned short)irq << 12);
    outw(ioBase + 0x08, reg8Value);

    /* Switch to window 0 again if needed */
    if (currentWindow != 0x00) {
        outw(ioBase + 0x0E, 0x0800);
        currentWindow = 0x00;
    }

    /* Enable interrupts by setting bit 0 */
    reg4Value |= 0x0001;
    outw(ioBase + 0x04, reg4Value);

    /* Call superclass */
    return [super enableAllInterrupts];
}

/*
 * Disable all interrupts
 * Disables adapter interrupts by clearing bit 0 in register at window 0, offset 4
 */
- (void)disableAllInterrupts
{
    unsigned short reg4Value;

    /* Switch to window 0 if needed */
    if (currentWindow != 0x00) {
        outw(ioBase + 0x0E, 0x0800);
        currentWindow = 0x00;
    }

    /* Read current value of register at offset 4 */
    reg4Value = inw(ioBase + 0x04);

    /* Switch to window 0 again if needed */
    if (currentWindow != 0x00) {
        outw(ioBase + 0x0E, 0x0800);
        currentWindow = 0x00;
    }

    /* Disable interrupts by clearing bit 0 */
    reg4Value &= 0xFFFE;  /* Clear bit 0 */
    outw(ioBase + 0x04, reg4Value);

    /* Call superclass */
    [super disableAllInterrupts];
}

@end

/* Private Category Implementation */
@implementation EtherLink3(EtherLink3Private)

/*
 * Hardware initialization
 */
- (BOOL)__hwInit
{
    const char *driverName;
    unsigned char idSeq;
    unsigned char carry;
    int i;
    unsigned short configReg;
    unsigned short mediaControlReg;
    enet_addr_t localMAC;

    driverName = [[self name] cString];

    /* Check if ISA card - if so, need to send ID sequence again */
    if (!isISA) {
        /* Non-ISA card - send simple activate command */
        outw(ioBase + 0x0E, 0x0030);
    } else {
        /* ISA card - send full activation sequence */
        outb(EL3_ID_PORT, 0xC0);
        IOSleep(1);
        outb(EL3_ID_PORT, 0x00);
        outb(EL3_ID_PORT, 0x00);

        /* Generate 255-byte LFSR ID sequence */
        idSeq = 0xFF;
        for (i = 0; i < 255; i++) {
            outb(EL3_ID_PORT, idSeq);
            carry = (idSeq & 0x80) ? 1 : 0;
            idSeq <<= 1;
            if (carry) {
                idSeq ^= 0xCF;
            }
        }
        outb(EL3_ID_PORT, 0xFF);
    }

    /* Reset and disable TX and RX */
    outw(ioBase + 0x0E, 0x2800);  /* RX reset */
    outw(ioBase + 0x0E, 0x5800);  /* TX reset */
    outw(ioBase + 0x0E, 0x1800);  /* RX disable */
    outw(ioBase + 0x0E, 0x5000);  /* TX disable */

    /* Copy MAC address to local variable */
    bcopy(&stationAddress, &localMAC, sizeof(enet_addr_t));

    /* Switch to window 2 to program station address */
    if (currentWindow != 0x02) {
        outw(ioBase + 0x0E, 0x0802);
        currentWindow = 0x02;
    }

    /* Write MAC address to station address registers (window 2, offsets 0-5) */
    for (i = 0; i < 6; i++) {
        outb(ioBase + i, localMAC.ea_byte[i]);
    }

    /* Check if auto-detect is needed */
    if (!doAutoDetect) {
        /* No auto-detect - configure connector directly */

        /* Switch to window 0 to access configuration register */
        if (currentWindow != 0x00) {
            outw(ioBase + 0x0E, 0x0800);
            currentWindow = 0x00;
        }

        /* Read configuration register at window 0, offset 6 */
        configReg = inw(ioBase + 0x06);
        configReg &= 0xC0FF;  /* Keep bits 15-14 and 7-0 */

        /* Configure based on connector type */
        if (connectorType == CONNECTOR_BNC) {
            /* BNC - set bits 15-14 */
            configReg |= 0xC000;
        } else if (connectorType == CONNECTOR_AUI) {
            /* AUI - set bit 14 only, clear high byte except bit 14 */
            configReg = (configReg & 0x00FF) | 0x4000;
        } else if (connectorType == CONNECTOR_RJ45) {
            /* RJ-45 - clear high byte */
            configReg &= 0x00FF;
        }

        /* Write configuration register */
        if (currentWindow != 0x00) {
            outw(ioBase + 0x0E, 0x0800);
            currentWindow = 0x00;
        }
        outw(ioBase + 0x06, configReg);

        /* Additional configuration based on connector type */
        if (connectorType == CONNECTOR_BNC) {
            /* Enable adapter for BNC */
            outw(ioBase + 0x0E, 0x1000);
            IOSleep(1);
        } else if (connectorType == CONNECTOR_RJ45) {
            /* Configure link beat detection for RJ-45 */
            if (currentWindow != 0x04) {
                outw(ioBase + 0x0E, 0x0804);
                currentWindow = 0x04;
            }
            mediaControlReg = 0x00C0;  /* Enable link beat */
            outw(ioBase + 0x0A, mediaControlReg);
        } else {
            /* AUI - configure SQE */
            if (currentWindow != 0x04) {
                outw(ioBase + 0x0E, 0x0804);
                currentWindow = 0x04;
            }
            mediaControlReg = 0x0008;  /* Enable SQE */
            outw(ioBase + 0x0A, mediaControlReg);
        }

        /* Enable interrupts and adapter */
        outw(ioBase + 0x0E, 0x7097);  /* Set interrupt enable */
        outw(ioBase + 0x0E, 0x7897);  /* Set indication enable */
        outw(ioBase + 0x0E, 0x68FF);  /* Acknowledge all interrupts */
        outw(ioBase + 0x0E, rxFilterByte | 0x8000);  /* Set RX filter */
        outw(ioBase + 0x0E, 0x4800);  /* Enable TX */
        outw(ioBase + 0x0E, 0x2000);  /* Enable RX */

        return YES;
    } else {
        /* Auto-detect mode - call auto-detect and recurse */
        [self __doAutoConnectorDetect];
        doAutoDetect = NO;  /* Clear flag to prevent infinite recursion */
        return [self __hwInit];  /* Recursive call */
    }
}

/*
 * Auto-detect connector type (AUI, BNC, or RJ-45)
 * Tests available media ports and selects the best one
 */
- (void)__doAutoConnectorDetect
{
    const char *driverName;
    unsigned short mediaAvail;
    unsigned short configReg;
    unsigned short statusReg;
    unsigned short txStatusByte;
    netbuf_t testPacket;
    unsigned int *dataPtr;
    unsigned char *bytePtr;
    const char *testString = "EtherLink3 AutoConnectorDetect";
    unsigned int testStringLen;
    unsigned int i;

    driverName = [[self name] cString];
    IOLog("%s: auto detecting the network interface\n", driverName);

    /* Switch to window 0 if needed */
    if (currentWindow != 0) {
        outw(ioBase + 0x0E, 0x0800);
        currentWindow = 0;
    }

    /* Read media availability from window 0, offset 4 */
    mediaAvail = inw(ioBase + 0x04);

    /* Test RJ-45 (10Base-T) if available */
    if (mediaAvail & MEDIA_AVAIL_RJ45) {
        connectorType = CONNECTOR_RJ45;

        /* Read and modify configuration register at offset 6 */
        configReg = inw(ioBase + 0x06);
        configReg &= 0x00FF;  /* Keep only low byte */
        outw(ioBase + 0x06, configReg);

        /* Switch to window 4 */
        if (currentWindow != 4) {
            outw(ioBase + 0x0E, 0x0804);
            currentWindow = 4;
        }

        /* Enable link beat detection - write 0xC0 to offset 10 */
        outw(ioBase + 0x0A, 0x00C0);

        /* Wait 1 second for link to come up */
        IOSleep(1000);

        /* Read link status from window 4, offset 10 */
        if (currentWindow != 4) {
            outw(ioBase + 0x0E, 0x0804);
            currentWindow = 4;
        }
        statusReg = inw(ioBase + 0x0A);

        /* Check if link is valid (bit 11 = 0x0800) */
        if (statusReg & 0x0800) {
            IOLog("%s: valid link detected\n", driverName);
            return;  /* RJ-45 link detected, done */
        }

        /* No RJ-45 link - reset TX/RX */
        outw(ioBase + 0x0E, 0x2800);  /* RX reset */
        outw(ioBase + 0x0E, 0x5800);  /* TX reset */
        outw(ioBase + 0x0E, 0x1800);  /* RX disable */
        outw(ioBase + 0x0E, 0x5000);  /* TX disable */
    }

    /* Test BNC (10Base2) if available */
    if (mediaAvail & MEDIA_AVAIL_BNC) {
        connectorType = CONNECTOR_BNC;

        /* Configure for BNC in window 0, register 6 */
        if (currentWindow != 0) {
            outw(ioBase + 0x0E, 0x0800);
            currentWindow = 0;
        }

        configReg = inw(ioBase + 0x06);
        configReg = (configReg & 0xC0FF) | 0xC000;  /* Set BNC bits */
        outw(ioBase + 0x06, configReg);

        /* Enable interrupts and TX */
        outw(ioBase + 0x0E, 0x1000);  /* Enable adapter */
        IOSleep(1);

        /* Setup interrupt and indication masks */
        outw(ioBase + 0x0E, 0x7097);  /* Set interrupt enable */
        outw(ioBase + 0x0E, 0x7897);  /* Set indication enable */
        outw(ioBase + 0x0E, 0x68FF);  /* Set RX filter */

        /* Set RX filter byte */
        outw(ioBase + 0x0E, rxFilterByte | 0x8000);

        /* Enable TX */
        outw(ioBase + 0x0E, 0x4800);

        /* Enable RX */
        outw(ioBase + 0x0E, 0x2000);

        /* Wait for hardware to stabilize */
        IOSleep(300);

        /* Send test packet to check BNC */
        testPacket = [self allocateNetbuf];
        if (testPacket != NULL) {
            /* Build test packet */
            dataPtr = (unsigned int *)nb_map(testPacket);
            bzero(dataPtr, 64);

            /* Set destination to our own MAC (loopback test) */
            dataPtr[0] = *(unsigned int *)&stationAddress.ea_byte[0];
            *(unsigned short *)((char *)dataPtr + 4) = *(unsigned short *)&stationAddress.ea_byte[4];

            /* Set source to our MAC */
            *(unsigned int *)((char *)dataPtr + 6) = *(unsigned int *)&stationAddress.ea_byte[0];
            *(unsigned short *)((char *)dataPtr + 10) = *(unsigned short *)&stationAddress.ea_byte[4];

            /* Set EtherType to 0x4444 */
            *(unsigned short *)((char *)dataPtr + 12) = 0x4444;

            /* Copy test string */
            testStringLen = strlen(testString);
            bcopy(testString, (char *)dataPtr + 14, testStringLen);

            /* Transmit test packet */
            if (currentWindow != 1) {
                outw(ioBase + 0x0E, 0x0801);
                currentWindow = 1;
            }

            /* Write TX preamble (0x8040 = 64 bytes) */
            outl(ioBase, 0x8040);

            /* Write packet data (16 dwords = 64 bytes) */
            for (i = 0; i < 16; i++) {
                outl(ioBase, dataPtr[i]);
            }

            nb_free(testPacket);

            /* Wait for transmission */
            IOSleep(500);

            /* Check TX status */
            if (currentWindow != 1) {
                outw(ioBase + 0x0E, 0x0801);
                currentWindow = 1;
            }

            txStatusByte = inb(ioBase + 0x0B);
            outb(ioBase + 0x0B, 0);  /* Clear status */

            /* Check if transmission successful (bits 6-7 set, no errors in bits 2-5) */
            if ((txStatusByte & 0xC0) != 0 && (txStatusByte & 0x3C) == 0) {
                IOLog("%s: BNC port detected\n", driverName);
                return;  /* BNC working, done */
            }
        }

        /* BNC test failed - disable TX */
        outw(ioBase + 0x0E, 0xB800);  /* Stats disable */
        IOSleep(1);
    }

    /* Test AUI if available */
    if (mediaAvail & MEDIA_AVAIL_AUI) {
        IOLog("%s: AUI port selected\n", driverName);
        connectorType = CONNECTOR_AUI;
        return;
    }

    /* Default based on availability */
    if (mediaAvail & MEDIA_AVAIL_RJ45) {
        connectorType = CONNECTOR_RJ45;
        IOLog("%s: defaulting to RJ-45\n", driverName);
    } else {
        connectorType = CONNECTOR_BNC;
        IOLog("%s: defaulting to BNC\n", driverName);
    }
}

/*
 * Schedule reset
 * Schedules a delayed reset after 200ms using timeout mechanism
 */
- (void)__scheduleReset
{
    /* Clear any existing timeout */
    [self clearTimeout];

    /* Schedule reset function to be called after 200ms */
    ns_timeout((func)__resetFunc, self, 0, CALLOUT_PRI_SOFTINT0, 200);
}

@end

/* Utility Functions */

/*
 * Reset function - called to reset the adapter
 */
static void __resetFunc(void *arg)
{
    EtherLink3 *driver = (EtherLink3 *)arg;
    BOOL result;
    const char *driverName;

    if (driver == nil) {
        return;
    }

    /* Attempt to reset and enable the adapter */
    result = [driver resetAndEnable:YES];

    if (!result) {
        driverName = [[driver name] cString];
        IOLog("%s: Reset attempt unsuccessful\n", driverName);
    }
}

/*
 * Interrupt handler - main ISR for EtherLink III
 */
static void _intHandler(void *identity, void *state, unsigned int arg)
{
    EtherLink3 *driver = (EtherLink3 *)arg;
    unsigned short ioBase;
    unsigned short statusReg;
    unsigned short rxStatus;
    unsigned short txStatus;
    unsigned short txFreeSpace;
    unsigned char txStatusByte;
    unsigned int packetSize;
    unsigned int wordCount;
    unsigned int byteRemainder;
    netbuf_t netbuf;
    netbuf_t *nextPtr;
    unsigned int *dataPtr;
    unsigned char *bytePtr;
    unsigned int actualSize;
    unsigned int i;
    BOOL hadInterrupt = NO;

    if (driver == nil) {
        return;
    }

    /* Check if interrupts are disabled */
    if (driver->interruptDisabled) {
        return;
    }

    ioBase = driver->ioBase;

    /* Read status register and process interrupts */
    statusReg = inw(ioBase + 0x0E);

    /* Main interrupt processing loop */
    while ((statusReg & 0xFF) != 0) {
        /* Acknowledge interrupt with indication enable */
        outw(ioBase + 0x0E, (statusReg & 0xFF) | 0x6800);

        /* Check for adapter failure (bit 1) */
        if (statusReg & 0x02) {
            driver->interruptDisabled = YES;
            break;
        }

        /* Handle RX complete interrupt (bit 4 = 0x10) */
        if (statusReg & 0x10) {
            /* Switch to window 1 if not already there */
            if (driver->currentWindow != 0x01) {
                outw(ioBase + 0x0E, 0x0801);  /* Select window 1 */
                driver->currentWindow = 0x01;
            }

            /* Read RX status register at window 1, offset 8 */
            rxStatus = inw(ioBase + 0x08);

            /* Check for RX errors (bit 14 = incomplete, bit 15 = error) */
            if ((rxStatus & 0xC000) == 0 && (short)rxStatus >= 0) {
                /* Extract packet size (bits 0-10) */
                packetSize = rxStatus & 0x7FF;

                /* Validate packet size (must be at least 60 bytes, less than 1515) */
                if (packetSize >= 60 && packetSize < 1515) {
                    /* Check if we can receive (RX queue not full and free netbuf available) */
                    if (driver->rxQueueCount < driver->rxQueueMax && driver->freeNetbufCount > 0) {
                        /* Dequeue a free netbuf from free list */
                        netbuf = driver->freeNetbufHead;
                        if (netbuf != NULL) {
                            driver->freeNetbufHead = *(netbuf_t *)netbuf;
                            driver->freeNetbufCount--;
                            if (driver->freeNetbufCount == 0) {
                                driver->freeNetbufTail = NULL;
                                driver->freeNetbufHead = NULL;
                            }
                            *(netbuf_t *)netbuf = NULL;

                            /* Map netbuf to get data pointer */
                            dataPtr = (unsigned int *)nb_map(netbuf);

                            /* Read packet data in 32-bit chunks from I/O port 0 */
                            wordCount = packetSize >> 2;
                            for (i = 0; i < wordCount; i++) {
                                dataPtr[i] = inl(ioBase);
                            }

                            /* Read remaining bytes */
                            byteRemainder = packetSize & 3;
                            if (byteRemainder > 0) {
                                bytePtr = (unsigned char *)&dataPtr[wordCount];
                                for (i = 0; i < byteRemainder; i++) {
                                    bytePtr[i] = inb(ioBase);
                                }
                            }

                            /* Shrink netbuf to actual packet size */
                            actualSize = nb_size(netbuf);
                            if (packetSize < actualSize) {
                                nb_shrink_bot(netbuf, actualSize - packetSize);
                            }

                            /* Enqueue to RX queue */
                            if (driver->rxQueueCount < driver->rxQueueMax) {
                                if (driver->rxQueueCount == 0) {
                                    driver->rxQueueTail = netbuf;
                                    driver->rxQueueHead = netbuf;
                                } else {
                                    *(netbuf_t *)driver->rxQueueTail = netbuf;
                                    driver->rxQueueTail = netbuf;
                                }
                                *(netbuf_t *)netbuf = NULL;
                                driver->rxQueueCount++;
                            } else {
                                IOLog("EtherLink III: queue exceeded max %d - freeing netbuf\n",
                                      driver->rxQueueMax);
                                nb_free(netbuf);
                            }

                            /* Issue RX discard command */
                            outw(ioBase + 0x0E, 0x4000);

                            /* Wait for command to complete (bit 12 = 0x1000) */
                            do {
                                rxStatus = inw(ioBase + 0x0E);
                            } while (rxStatus & 0x1000);

                            hadInterrupt = YES;
                        }
                    }
                }
            }

            /* Discard packet if we couldn't receive it */
            if (!hadInterrupt) {
                outw(ioBase + 0x0E, 0x4000);  /* RX discard */
                do {
                    rxStatus = inw(ioBase + 0x0E);
                } while (rxStatus & 0x1000);
                driver->rxErrors++;
            }
        }

        /* Handle TX complete interrupt (bit 2 = 0x04) */
        if (statusReg & 0x04) {
            /* Switch to window 1 if not already there */
            if (driver->currentWindow != 0x01) {
                outw(ioBase + 0x0E, 0x0801);  /* Select window 1 */
                driver->currentWindow = 0x01;
            }

            /* Read TX status byte at window 1, offset 0xB */
            txStatusByte = inb(ioBase + 0x0B);

            /* Clear TX status */
            outb(ioBase + 0x0B, 0);

            /* Check for TX errors (bits 2-5 = 0x3C) */
            if ((txStatusByte & 0x3C) == 0) {
                /* Successful transmission */
                driver->txSuccess++;
            } else {
                /* TX error occurred */
                /* Check for underrun or jabber (bits 4-5 = 0x30) */
                if (txStatusByte & 0x30) {
                    /* Issue TX reset command */
                    outw(ioBase + 0x0E, 0x5800);
                }

                /* Issue TX enable command */
                outw(ioBase + 0x0E, 0x4800);

                driver->txErrors++;

                /* Check for max collisions (bit 3) */
                if (txStatusByte & 0x08) {
                    driver->txCollisions++;
                }
            }

            /* Try to transmit more packets from TX queue */
            while (driver->txPendingCount < driver->txPendingMax && driver->txQueueCount > 0) {
                /* Switch to window 3 to check TX free space */
                if (driver->currentWindow != 0x03) {
                    outw(ioBase + 0x0E, 0x0803);  /* Select window 3 */
                    driver->currentWindow = 0x03;
                }

                /* Get packet size */
                netbuf = driver->txQueueHead;
                packetSize = nb_size(netbuf);

                /* Read TX free space at window 3, offset 0xC */
                txFreeSpace = inw(ioBase + 0x0C);

                /* Check if enough space (need size + 50 bytes overhead) */
                if (txFreeSpace < packetSize + 50) {
                    break;
                }

                /* Dequeue packet from TX queue */
                driver->txQueueHead = *(netbuf_t *)netbuf;
                driver->txQueueCount--;
                if (driver->txQueueCount == 0) {
                    driver->txQueueTail = NULL;
                    driver->txQueueHead = NULL;
                }
                *(netbuf_t *)netbuf = NULL;

                /* Get packet data */
                dataPtr = (unsigned int *)nb_map(netbuf);
                byteRemainder = packetSize & 3;

                /* Switch to window 1 for TX */
                if (driver->currentWindow != 0x01) {
                    outw(ioBase + 0x0E, 0x0801);  /* Select window 1 */
                    driver->currentWindow = 0x01;
                }

                /* Write TX preamble with length */
                outl(ioBase, (packetSize & 0x7FF) | 0x8000);

                /* Write packet data in 32-bit chunks */
                wordCount = packetSize >> 2;
                for (i = 0; i < wordCount; i++) {
                    outl(ioBase, dataPtr[i]);
                }

                /* Write remaining bytes */
                if (byteRemainder > 0) {
                    bytePtr = (unsigned char *)&dataPtr[wordCount];
                    for (i = 0; i < byteRemainder; i++) {
                        outb(ioBase, bytePtr[i]);
                    }

                    /* Pad to 32-bit boundary */
                    for (i = byteRemainder; i < 4; i++) {
                        outb(ioBase, 0);
                    }
                }

                /* Enqueue to TX pending queue */
                if (driver->txPendingCount < driver->txPendingMax) {
                    if (driver->txPendingCount == 0) {
                        driver->txPendingTail = netbuf;
                        driver->txPendingHead = netbuf;
                    } else {
                        *(netbuf_t *)driver->txPendingTail = netbuf;
                        driver->txPendingTail = netbuf;
                    }
                    *(netbuf_t *)netbuf = NULL;
                    driver->txPendingCount++;
                } else {
                    IOLog("EtherLink III: queue exceeded max %d - freeing netbuf\n",
                          driver->txPendingMax);
                    nb_free(netbuf);
                }
            }
        }

        /* Read status register again */
        statusReg = inw(ioBase + 0x0E);
    }

    /* If we had interrupts or adapter failed, send interrupt notification */
    if (hadInterrupt || driver->interruptDisabled) {
        IOSendInterrupt(identity, state, 0x232325);
    }
}

/*
 * Dequeue from netbuf queue
 * This is a simple linked-list dequeue operation
 * The netbuf structure uses its first word as a next pointer
 *
 * param_1 is a pointer to a NetbufQueue structure containing:
 *   - head pointer (offset 0)
 *   - tail pointer (offset 4)
 *   - count (offset 8)
 */
static netbuf_t _QDequeue(NetbufQueue *queue)
{
    netbuf_t netbuf;

    /* Check if queue is empty (count == 0) */
    if (queue->count == 0) {
        return NULL;
    }

    /* Dequeue from head */
    netbuf = queue->head;
    queue->head = *(netbuf_t *)netbuf;
    queue->count--;

    /* If queue is now empty, clear tail and head pointers */
    if (queue->count == 0) {
        queue->tail = NULL;
        queue->head = NULL;
    }

    /* Clear the next pointer in the dequeued netbuf */
    *(netbuf_t *)netbuf = NULL;

    return netbuf;
}

/*
 * Enqueue netbuf to queue
 */
static void _QEnqueue(NetbufQueue *queue, netbuf_t netbuf)
{
    /* Enqueue to tail */
    if (queue->count == 0) {
        queue->head = netbuf;
        queue->tail = netbuf;
    } else {
        *(netbuf_t *)queue->tail = netbuf;
        queue->tail = netbuf;
    }
    *(netbuf_t *)netbuf = NULL;
    queue->count++;
}
