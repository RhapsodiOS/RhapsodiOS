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
static void intHandler(void *identity, void *state, unsigned int arg);
static netbuf_t _QDequeue(EtherLink3Queue *queue);
static void _QEnqueue(EtherLink3Queue *queue, netbuf_t netbuf);

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
    const char *myConnectors[3] = {"AUI", "BNC", "RJ-45"};
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
    deviceTable = [deviceDescription configTable];

    /* Initialize current window to 0xFF (invalid) */
    currentWindow = 0xFF;

    /* Switch to window 0 */
    outw(ioBase + 0x0E, 0x0800);
    currentWindow = 0x00;

    /* Read product ID from window 0, offset 2 */
    productID = inw(ioBase + 0x02);

    /* Check for connector type in configuration */
    connectorString = [deviceTable valueForStringKey:"Connector"];
    if (connectorString != NULL) {
        /* Try to match connector string */
        for (i = 0; i < 3; i++) {
            if (strcmp(connectorString, myConnectors[i]) == 0) {
                myConnector = i;
                connectorFound = YES;
                break;
            }
        }
        /* Free the string */
        [deviceTable freeString:connectorString];
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
                myConnector = CONNECTOR_AUI;
            } else if (configReg < 2 || configReg != 3) {
                myConnector = CONNECTOR_RJ45;
            } else {
                myConnector = CONNECTOR_BNC;
            }
        } else {
            /* Auto-select enabled */
            autoConnector = YES;
        }
    }

    /* Set RX filter byte to 5 (station and broadcast) */
    rxModes = 0x05;

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
        myAddress.ea_byte[i * 2] = (unsigned char)(addressData >> 8);
        myAddress.ea_byte[i * 2 + 1] = (unsigned char)addressData;
    }

    /* Read product ID again and write to offset 0x0C */
    addressData = inw(ioBase + 0x02);
    outw(ioBase + 0x0C, addressData);

    /* Reset and enable the hardware */
    [self resetAndEnable:NO];

    reported_irq = [deviceDescription interrupt];

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
              modelName, slotOrPort, reported_irq, myConnectors[myConnector]);
    } else {
        /* ISA/PCMCIA - log with I/O port */
        slotOrPort = ioBase;
        IOLog("3Com EtherLink III %s at port 0x%x irq %d using %s\n",
              modelName, slotOrPort, reported_irq, myConnectors[myConnector]);
    }

    /* Attach to network with MAC address */
    networkInterface = [super attachToNetworkWithAddress:myAddress];

    /* Initialize all queue structures */
    rxQ.head = NULL;
    rxQ.tail = NULL;
    rxQ.count = 0;
    rxQ.max = 0x80;  /* 128 packets */

    txQ.head = NULL;
    txQ.tail = NULL;
    txQ.count = 0;
    txQ.max = 0x10;  /* 16 packets */

    txFreeQ.head = NULL;
    txFreeQ.tail = NULL;
    txFreeQ.count = 0;
    txFreeQ.max = 0x40;  /* 64 packets */

    rxPoolQ.head = NULL;
    rxPoolQ.tail = NULL;
    rxPoolQ.count = 0;
    rxPoolQ.max = 0x20;  /* 32 packets */

    return self;
}

/*
 * Reset and enable/disable the adapter
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    netbuf_t netbuf;

    resetInProgress = YES;
    interruptHappened = NO;
    [self QFill:&rxPoolQ];
    while ((netbuf = _QDequeue(&txQ)) != NULL)
        nb_free(netbuf);
    while ((netbuf = _QDequeue(&txFreeQ)) != NULL)
        nb_free(netbuf);
    while ((netbuf = _QDequeue(&rxQ)) != NULL)
        nb_free(netbuf);

    [self disableAllInterrupts];
    if (![self _hwInit]) {
        [self setRunning:NO];
        return NO;
    }
    if (enable) {
        if ([self enableAllInterrupts] != IO_R_SUCCESS) {
            [self setRunning:NO];
            return NO;
        }
        [self setRelativeTimeout:2000];
    }
    [self setRunning:enable];
    resetInProgress = NO;
    return YES;
}

/*
 * Free driver resources
 */
- (void)free
{
    netbuf_t netbuf;

    /* Free all netbufs in free netbuf queue */
    while ((netbuf = _QDequeue(&rxPoolQ)) != NULL) {
        nb_free(netbuf);
    }

    /* Free all netbufs in TX pending queue */
    while ((netbuf = _QDequeue(&txFreeQ)) != NULL) {
        nb_free(netbuf);
    }

    /* Free all netbufs in TX queue */
    while ((netbuf = _QDequeue(&txQ)) != NULL) {
        nb_free(netbuf);
    }

    /* Free all netbufs in RX queue */
    while ((netbuf = _QDequeue(&rxQ)) != NULL) {
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
- (void)setIRQ:(unsigned int)interrupt
{
    real_irq = interrupt;
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
    autoConnector = flag;
}

/*
 * Enable promiscuous mode
 * Sets bit 3 in RX filter to enable promiscuous mode
 */
- (BOOL)enablePromiscuousMode
{
    unsigned short filterCmd;

    /* Set promiscuous bit (bit 3 = 0x08) in RX filter byte */
    rxModes |= 0x08;

    /* Send RX filter command (0x8000 | filter byte) */
    filterCmd = 0x8000 | (unsigned short)rxModes;
    outw(ioBase + 0x0E, filterCmd);

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
    rxModes &= 0xF7;  /* 0xF7 = ~0x08 */

    /* Send RX filter command (0x8000 | filter byte) */
    filterCmd = 0x8000 | (unsigned short)rxModes;
    outw(ioBase + 0x0E, filterCmd);

}

/*
 * Enable multicast mode
 * Sets bit 1 in RX filter to enable multicast mode
 */
- (BOOL)enableMulticastMode
{
    unsigned short filterCmd;

    /* Set multicast bit (bit 1 = 0x02) in RX filter byte */
    rxModes |= 0x02;

    /* Send RX filter command (0x8000 | filter byte) */
    filterCmd = 0x8000 | (unsigned short)rxModes;
    outw(ioBase + 0x0E, filterCmd);

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
    rxModes &= 0xFD;  /* 0xFD = ~0x02 */

    /* Send RX filter command (0x8000 | filter byte) */
    filterCmd = 0x8000 | (unsigned short)rxModes;
    outw(ioBase + 0x0E, filterCmd);

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
    interruptHappened = YES;

    /* Check if interrupts are disabled - if so, schedule a reset */
    if (resetInProgress) {
        [self _scheduleReset];
        return;
    }

    /* Process all received packets from RX queue */
    while (1) {
        /* Raise IPL and dequeue packet */
        savedIPL = spldevice();
        netbuf = _QDequeue(&rxQ);

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
        netbuf = _QDequeue(&txFreeQ);

        if (netbuf == NULL) {
            break;
        }

        splx(savedIPL);
        nb_free(netbuf);
    }

    /* Update statistics if any errors occurred */
    if (inputErrors != 0) {
        [networkInterface incrementInputErrorsBy:inputErrors];
        inputErrors = 0;
    }

    if (outputErrors != 0) {
        [networkInterface incrementOutputErrorsBy:outputErrors];
        outputErrors = 0;
    }

    if (outputPackets != 0) {
        [networkInterface incrementOutputPacketsBy:outputPackets];
        outputPackets = 0;
    }

    if (collisions != 0) {
        [networkInterface incrementCollisionsBy:collisions];
        collisions = 0;
    }

    splx(savedIPL);

    /* Refill receive buffers */
    [self QFill:&rxPoolQ];
}

/*
 * Handle timeout
 * Called periodically to check driver health
 */
- (void)timeoutOccurred
{
    /* Check if driver is running and interrupts enabled */
    if ([self isRunning] && !resetInProgress) {
        /* Check if we've received interrupts or TX queue is empty */
        if (interruptHappened || txQ.count == 0) {
            /* Activity detected - clear flag and reschedule */
            interruptHappened = NO;
            [self setRelativeTimeout:2000];
        } else {
            /* No activity - schedule a reset */
            [self _scheduleReset];
        }
    }
}

/*
 * Get interrupt handler
 */
- (BOOL)getHandler:(IOInterruptHandler *)handler
            level:(unsigned int *)ipl
         argument:(void **)arg
     forInterrupt:(unsigned int)localInterrupt
{
    *handler = intHandler;
    *ipl = 3;
    *arg = (void *)self;
    return YES;
}

/*
 * Transmit a packet
 */
- (void)transmit:(netbuf_t)packet
{
    netbuf_t queuedPacket;
    unsigned int *data;
    unsigned char *bytes;
    unsigned int packetSize;
    unsigned int remainder;
    unsigned int i;
    unsigned short txFreeSpace;
    unsigned int savedIPL;

    if (![self isRunning] || resetInProgress) {
        nb_free(packet);
        return;
    }
    packetSize = nb_size(packet);
    if (packetSize <= 59)
        nb_grow_bot(packet, 60 - packetSize);
    [self performLoopback:packet];

    savedIPL = spldevice();
    while (txFreeQ.max > txFreeQ.count && txQ.head != NULL) {
        packetSize = nb_size(txQ.head);
        if (currentWindow != 3) {
            outw(ioBase + 14, 0x0803);
            currentWindow = 3;
        }
        txFreeSpace = inw(ioBase + 12);
        if (packetSize > (unsigned int)txFreeSpace - 50)
            break;

        queuedPacket = _QDequeue(&txQ);
        data = (unsigned int *)nb_map(queuedPacket);
        packetSize = nb_size(queuedPacket);
        remainder = packetSize & 3;
        if (currentWindow != 1) {
            outw(ioBase + 14, 0x0801);
            currentWindow = 1;
        }
        outl(ioBase, (packetSize & 0x7ff) | 0x8000);
        for (i = 0; i < packetSize >> 2; i++)
            outl(ioBase, data[i]);
        if (remainder != 0) {
            bytes = (unsigned char *)&data[packetSize >> 2];
            for (i = 0; i < remainder; i++)
                outb(ioBase, bytes[i]);
            for (; i < 4; i++)
                outb(ioBase, 0);
        }
        _QEnqueue(&txFreeQ, queuedPacket);
    }

    while ((queuedPacket = _QDequeue(&txFreeQ)) != NULL) {
        splx(savedIPL);
        nb_free(queuedPacket);
        savedIPL = spldevice();
    }

    if (txQ.head == NULL) {
        packetSize = nb_size(packet);
        if (currentWindow != 3) {
            outw(ioBase + 14, 0x0803);
            currentWindow = 3;
        }
        txFreeSpace = inw(ioBase + 12);
        if (packetSize <= (unsigned int)txFreeSpace - 50) {
            data = (unsigned int *)nb_map(packet);
            if (currentWindow != 1) {
                outw(ioBase + 14, 0x0801);
                currentWindow = 1;
            }
            outl(ioBase, (packetSize & 0x7ff) | 0x8000);
            for (i = 0; i < packetSize >> 2; i++)
                outl(ioBase, data[i]);
            remainder = packetSize & 3;
            if (remainder != 0) {
                bytes = (unsigned char *)&data[packetSize >> 2];
                for (i = 0; i < remainder; i++)
                    outb(ioBase, bytes[i]);
                for (; i < 4; i++)
                    outb(ioBase, 0);
            }
            splx(savedIPL);
            nb_free(packet);
            return;
        }
    }

    if (txQ.max <= txQ.count) {
        splx(savedIPL);
        nb_free(packet);
        return;
    }
    _QEnqueue(&txQ, packet);
    splx(savedIPL);
}

/*
 * Get transmit queue size (max capacity)
 */
- (unsigned int)transmitQueueSize
{
    return txQ.max;
}

/*
 * Get transmit queue count (current count)
 */
- (unsigned int)transmitQueueCount
{
    return txQ.count;
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
- (void)QFill:(EtherLink3Queue *)queue
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
    reg8Value = (reg8Value & 0x0FFF) | ((unsigned short)real_irq << 12);
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


/*
 * Hardware initialization
 */
- (BOOL)_hwInit
{
    unsigned char idSequence;
    unsigned char previous;
    unsigned short configReg;
    int i;

    if (isISA) {
        outb(0x110, 0xc0);
        IOSleep(1);
        outb(0x110, 0);
        outb(0x110, 0);
        idSequence = 0xff;
        for (i = 0; i < 255; i++) {
            outb(0x110, idSequence);
            previous = idSequence;
            idSequence <<= 1;
            if (previous & 0x80)
                idSequence ^= 0xcf;
        }
        outb(0x110, 0xff);
    } else {
        outw(ioBase + 14, 0x0030);
    }

    outw(ioBase + 14, 0x2800);
    outw(ioBase + 14, 0x5800);
    outw(ioBase + 14, 0x1800);
    outw(ioBase + 14, 0x5000);

    if (currentWindow != 2) {
        outw(ioBase + 14, 0x0802);
        currentWindow = 2;
    }
    for (i = 0; i < 6; i++)
        outb(ioBase + i, myAddress.ea_byte[i]);

    if (autoConnector) {
        [self _doAutoConnectorDetect];
        autoConnector = NO;
        return [self _hwInit];
    }

    if (currentWindow != 0) {
        outw(ioBase + 14, 0x0800);
        currentWindow = 0;
    }
    configReg = inw(ioBase + 6) & 0xc0ff;
    if (myConnector == 1)
        configReg |= 0xc000;
    else if (myConnector == 0)
        configReg = (configReg & 0x3fff) | 0x4000;
    else
        configReg &= 0x3fff;
    if (currentWindow != 0) {
        outw(ioBase + 14, 0x0800);
        currentWindow = 0;
    }
    outw(ioBase + 6, configReg);

    if (myConnector == 1) {
        outw(ioBase + 14, 0x1000);
        IOSleep(1);
    } else {
        if (currentWindow != 4) {
            outw(ioBase + 14, 0x0804);
            currentWindow = 4;
        }
        outw(ioBase + 10, myConnector == 2 ? 0x00c0 : 0x0008);
    }

    outw(ioBase + 14, 0x7097);
    outw(ioBase + 14, 0x7897);
    outw(ioBase + 14, 0x68ff);
    outw(ioBase + 14, rxModes | 0x8000);
    outw(ioBase + 14, 0x4800);
    outw(ioBase + 14, 0x2000);
    return YES;
}

/*
 * Auto-detect connector type (AUI, BNC, or RJ-45)
 * Tests available media ports and selects the best one
 */
- (void)_doAutoConnectorDetect
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
        myConnector = CONNECTOR_RJ45;

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
        myConnector = CONNECTOR_BNC;

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
        outw(ioBase + 0x0E, rxModes | 0x8000);

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
            dataPtr[0] = *(unsigned int *)&myAddress.ea_byte[0];
            *(unsigned short *)((char *)dataPtr + 4) = *(unsigned short *)&myAddress.ea_byte[4];

            /* Set source to our MAC */
            *(unsigned int *)((char *)dataPtr + 6) = *(unsigned int *)&myAddress.ea_byte[0];
            *(unsigned short *)((char *)dataPtr + 10) = *(unsigned short *)&myAddress.ea_byte[4];

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
        myConnector = CONNECTOR_AUI;
        return;
    }

    /* Default based on availability */
    if (mediaAvail & MEDIA_AVAIL_RJ45) {
        myConnector = CONNECTOR_RJ45;
        IOLog("%s: defaulting to RJ-45\n", driverName);
    } else {
        myConnector = CONNECTOR_BNC;
        IOLog("%s: defaulting to BNC\n", driverName);
    }
}

/*
 * Schedule reset
 * Schedules a delayed reset after 200ms using timeout mechanism
 */
- (void)_scheduleReset
{
    /* Clear any existing timeout */
    [self clearTimeout];

    /* Schedule reset function to be called after 200ms */
    ns_timeout((func)__resetFunc, self, 0, 0, 4);
}

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
static void intHandler(void *identity, void *state, unsigned int arg)
{
    EtherLink3 *driver = (EtherLink3 *)arg;
    unsigned short ioBase = driver->ioBase;
    unsigned short status = inw(ioBase + 14);
    unsigned short rxStatus;
    unsigned short txFreeSpace;
    unsigned char txStatus;
    unsigned int packetSize;
    unsigned int wordCount;
    unsigned int remainder;
    unsigned int *data;
    unsigned char *bytes;
    netbuf_t packet;
    unsigned int i;
    BOOL hadReceive = NO;

    if (driver->resetInProgress)
        return;

    while (status & 0xff) {
        outw(ioBase + 14, (status & 0xff) | 0x6800);
        if (status & 0x02) {
            driver->resetInProgress = YES;
            break;
        }

        if (status & 0x10) {
            if (driver->currentWindow != 1) {
                outw(ioBase + 14, 0x0801);
                driver->currentWindow = 1;
            }
            rxStatus = inw(ioBase + 8);
            if (rxStatus & 0x4000) {
                outw(ioBase + 14, 0x4000);
                while (inw(ioBase + 14) & 0x1000) {}
                driver->inputErrors++;
            } else if (!(rxStatus & 0x8000)) {
                packetSize = rxStatus & 0x7ff;
                if (packetSize > 1514 ||
                    driver->rxQ.count >= driver->rxQ.max) {
                    outw(ioBase + 14, 0x4000);
                    while (inw(ioBase + 14) & 0x1000) {}
                    driver->inputErrors++;
                } else {
                    packet = _QDequeue(&driver->rxPoolQ);
                    if (packet == NULL) {
                        outw(ioBase + 14, 0x4000);
                        while (inw(ioBase + 14) & 0x1000) {}
                        driver->inputErrors++;
                    } else {
                        data = (unsigned int *)nb_map(packet);
                        wordCount = packetSize >> 2;
                        for (i = 0; i < wordCount; i++)
                            data[i] = inl(ioBase);
                        remainder = packetSize & 3;
                        if (remainder != 0) {
                            bytes = (unsigned char *)&data[wordCount];
                            for (i = 0; i < remainder; i++)
                                bytes[i] = inb(ioBase);
                        }
                        if (packetSize < nb_size(packet))
                            nb_shrink_bot(packet, nb_size(packet) - packetSize);
                        _QEnqueue(&driver->rxQ, packet);
                        outw(ioBase + 14, 0x4000);
                        while (inw(ioBase + 14) & 0x1000) {}
                    }
                }
            }
            hadReceive = YES;
        }

        if (status & 0x04) {
            if (driver->currentWindow != 1) {
                outw(ioBase + 14, 0x0801);
                driver->currentWindow = 1;
            }
            txStatus = inb(ioBase + 11);
            outb(ioBase + 11, 0);
            if (txStatus & 0x3c) {
                if (txStatus & 0x30)
                    outw(ioBase + 14, 0x5800);
                outw(ioBase + 14, 0x4800);
                driver->outputErrors++;
                if (txStatus & 0x08)
                    driver->collisions++;
            } else {
                driver->outputPackets++;
            }

            while (driver->txFreeQ.count < driver->txFreeQ.max &&
                   driver->txQ.head != NULL) {
                packetSize = nb_size(driver->txQ.head);
                if (driver->currentWindow != 3) {
                    outw(ioBase + 14, 0x0803);
                    driver->currentWindow = 3;
                }
                txFreeSpace = inw(ioBase + 12);
                if (packetSize > (unsigned int)txFreeSpace - 50)
                    break;

                packet = _QDequeue(&driver->txQ);
                data = (unsigned int *)nb_map(packet);
                packetSize = nb_size(packet);
                remainder = packetSize & 3;
                if (driver->currentWindow != 1) {
                    outw(ioBase + 14, 0x0801);
                    driver->currentWindow = 1;
                }
                outl(ioBase, (packetSize & 0x7ff) | 0x8000);
                wordCount = packetSize >> 2;
                for (i = 0; i < wordCount; i++)
                    outl(ioBase, data[i]);
                if (remainder != 0) {
                    bytes = (unsigned char *)&data[wordCount];
                    for (i = 0; i < remainder; i++)
                        outb(ioBase, bytes[i]);
                    for (; i < 4; i++)
                        outb(ioBase, 0);
                }
                _QEnqueue(&driver->txFreeQ, packet);
            }
        }
        status = inw(ioBase + 14);
    }

    if (hadReceive || driver->resetInProgress)
        IOSendInterrupt(identity, state, 0x232325);
}

/*
 * Dequeue from netbuf queue
 * This is a simple linked-list dequeue operation
 * The netbuf structure uses its first word as a next pointer
 *
 * param_1 is a pointer to a EtherLink3Queue structure containing:
 *   - head pointer (offset 0)
 *   - tail pointer (offset 4)
 *   - count (offset 8)
 */
static netbuf_t _QDequeue(EtherLink3Queue *queue)
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
static void _QEnqueue(EtherLink3Queue *queue, netbuf_t netbuf)
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
