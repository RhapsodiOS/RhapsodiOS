/*
 * EtherExpress16.m
 * Intel EtherExpress 16 Network Driver - Main Implementation
 */

#import "EtherExpress16.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/IOEthernetPrivate.h>
#import <machine/label_t.h>
#import <machkit/NXLock.h>

/* Forward declarations for utility functions */
static void _check_rbd(unsigned short *rbd, label_t *label);
static void _check_rfd(unsigned short *rfd, label_t *label);
static unsigned short _get_eeprom(unsigned short base);
static void _get_etherAddress(enet_addr_t *addr, unsigned short base);
static void _get_iscp_busy(unsigned short *buffer, unsigned short value, unsigned short base);
static void _get_rbd(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _get_rfd(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _get_rfd_hdr(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _get_scb(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _get_scb_cmd(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _get_scb_stat(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _get_tcb_stat(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_eeprom(unsigned short value, unsigned char bitCount, unsigned short base);
static void _put_iscp(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_rbd(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_rbd_magic(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_rbd_nxt(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_rfd(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_rfd_lnk(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_rfd_magic(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_scb(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_scb_cmd(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_scp(unsigned short *buffer, unsigned short base);
static void _put_tbd(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_tbd_count(unsigned short *buffer, unsigned short offset, unsigned short base);
static void _put_tcb(unsigned short *buffer, unsigned short offset, unsigned short base);
static unsigned short _read_eeprom(unsigned short offset, unsigned short base);
static unsigned short _setup_mem(unsigned short base);
static void _wait_scb(unsigned short base, unsigned short offset, int retries, label_t *label);
extern int set_label(label_t *label);
extern void jump_label(label_t *label);

static inline void _disable(void)
{
    __asm__ volatile("cli" ::: "memory");
}

static inline void _enable(void)
{
    __asm__ volatile("sti" ::: "memory");
}

/* Connector type strings */
static const char *_connectorType[] = {
    "AUI",
    "BNC",
    "RJ-45"
};

/* IRQ mapping table */
static const unsigned char _irq_map[] = {
    0, 0, 0, 2, 3, 4, 0, 0, 0, 1, 5, 6, 0, 0, 0, 0
};

/* Board description strings */
static const char *_boardDescription[] = {
    "EtherExpress16",
    "EtherExpress16TP",
    "EtherExpress16 (Second Generation)",
    "EtherExpress16TP (Second Generation)",
    "EtherExpress16C"
};

@implementation EtherExpress16

/*
 * Probe method - Called during driver discovery
 * Detects EtherExpress 16 adapter by reading ID pattern from port+0x0F
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    EtherExpress16 *driver;
    IORange *portRange;
    unsigned short base;
    unsigned short idValue;
    unsigned char readByte;
    unsigned int nibbleIndex;
    unsigned int maxNibbles;
    BOOL foundStart;
    int numInterrupts, numPorts;

    /* Allocate driver instance */
    driver = [[self alloc] init];
    if (driver == nil) {
        return NO;
    }

    /* Check if I/O ports are configured */
    numPorts = [deviceDescription numPortRanges];
    if (numPorts == 0) {
        [driver free];
        return NO;
    }

    /* Check if interrupt is configured */
    numInterrupts = [deviceDescription numInterrupts];
    if (numInterrupts == 0) {
        [driver free];
        return NO;
    }

    /* Get port range */
    portRange = [deviceDescription portRangeList];
    if (portRange == NULL || portRange->size < 0x10) {
        [driver free];
        return NO;
    }

    base = portRange->start;

    /* Read ID pattern from adapter
     * The adapter presents a nibble sequence at port+0x0F where:
     * - Low nibble increments: 0, 1, 2, 3, 0, 1, 2, 3...
     * - High nibble contains ID bits
     * We read until we see low nibble = 0, then read 4 more nibbles
     * to build the 16-bit ID value (0xBABA for EtherExpress 16)
     */
    foundStart = NO;
    idValue = 0;
    nibbleIndex = 0;
    maxNibbles = 0x10;  /* Maximum attempts to find start */

    do {
        readByte = inb(base + 0x0F);

        if (foundStart) {
            /* We found the start sequence - verify nibble sequence */
            if ((readByte & 0x0F) != nibbleIndex) {
                /* Sequence broken - not a valid adapter */
                idValue = 0;
                break;
            }
            /* Extract high nibble and build ID value */
            idValue |= (unsigned short)(readByte >> 4) << (nibbleIndex * 4);
        } else {
            /* Looking for start of sequence (low nibble = 0) */
            if ((readByte & 0x0F) == 0) {
                foundStart = YES;
                nibbleIndex = 0;
                maxNibbles = 4;  /* Read 4 nibbles for 16-bit ID */
                /* Process this first nibble */
                idValue |= (unsigned short)(readByte >> 4) << (nibbleIndex * 4);
            }
        }

        nibbleIndex++;
    } while (nibbleIndex < maxNibbles);

    /* Check ID value */
    if (idValue == 0) {
        IOLog("EtherExpress16: Adapter not found at address 0x%x\n", base);
        [driver free];
        return NO;
    } else if (idValue != EE16_ID_VALUE) {
        IOLog("EtherExpress16: Unrecognized adapter found at address 0x%x (ID=0x%04x)\n",
              base, idValue);
        [driver free];
        return NO;
    }

    /* Valid EtherExpress 16 adapter found - initialize it */
    if ([driver initFromDeviceDescription:deviceDescription] != nil) {
        return YES;
    }

    [driver free];
    return NO;
}

/*
 * Initialize driver from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IORange *portRange;
    unsigned char readByte;
    unsigned int nibbleIndex;
    unsigned int maxNibbles;
    BOOL foundStart;
    unsigned short idValue;
    IOConfigTable *instanceTable;
    const char *connectorString;
    int i;
    BOOL isDefault;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Get IRQ and I/O port configuration */
    irq = [deviceDescription interrupt];
    portRange = [deviceDescription portRangeList];
    base = portRange->start;

    /* Read adapter ID value from port+0x300F (extended ID port)
     * This reads the same nibble sequence as probe, but from offset 0x300F
     * Used to differentiate between board revisions (0xBABA vs 0xBABB)
     */
    foundStart = NO;
    idValue = 0;
    nibbleIndex = 0;
    maxNibbles = 0x10;

    do {
        readByte = inb(base + 0x300F);

        if (foundStart) {
            if ((readByte & 0x0F) != nibbleIndex) {
                idValue = 0;
                break;
            }
            idValue |= (unsigned short)(readByte >> 4) << (nibbleIndex * 4);
        } else {
            if ((readByte & 0x0F) == 0) {
                foundStart = YES;
                nibbleIndex = 0;
                maxNibbles = 4;
                idValue |= (unsigned short)(readByte >> 4) << (nibbleIndex * 4);
            }
        }

        nibbleIndex++;
    } while (nibbleIndex < maxNibbles);

    /* Store configuration flag (0xBABA or 0xBABB) */
    boardID = idValue;

    /* Check if board version is supported (0xBABA or 0xBABB only) */
    if ((unsigned short)(boardID + 0x4546) > 1) {
        IOLog("EtherExpress16: unsupported board version\n");
    }

    /* Initialize state flags */
    promiscuousEnabled = NO;
    multicastEnabled = NO;

    /* Reset hardware (disable, don't enable yet) */
    [self resetAndEnable:NO];

    /* Log board information */
    IOLog("EtherExpress16: %s at 0x%x IRQ %d\n",
          _boardDescription[boardType], base, irq);

    /* Get instance table for configuration parameters */
    instanceTable = [deviceDescription configTable];
    if (instanceTable == NULL) {
        IOLog("EtherExpress16: couldn't get Instance table\n");
        [self free];
        return nil;
    }

    /* Get configured connector type from instance table */
    connectorString = [instanceTable valueForStringKey:"Connector"];

    if (connectorString != NULL) {
        /* Check if set to "Default" */
        isDefault = (strcmp(connectorString, "Default") == 0);

        if (!isDefault) {
            /* Try to match against known connector types */
            for (i = 0; i < 3; i++) {
                if (strcmp(connectorString, _connectorType[i]) == 0) {
                    interfaceConnector = i;
                    goto connector_configured;
                }
            }
        }
    }

    /* If we get here, either "Default" or unrecognized connector */
    if (connectorString != NULL && strcmp(connectorString, "Default") != 0) {
        IOLog("EtherExpress16: Unrecognized connector configured - %s\n",
              (connectorString != NULL) ? connectorString : "<none set>");
    }

    /* Set default connector based on board type */
    switch (boardType) {
    case 0:  /* EtherExpress16 */
    case 2:  /* EtherExpress16 (Second Generation) */
        interfaceConnector = CONNECTOR_BNC;
        break;
    default:
        interfaceConnector = CONNECTOR_RJ45;
        break;
    }

    IOLog("EtherExpress16: defaulting to %s connector\n",
          _connectorType[interfaceConnector]);

connector_configured:
    /* Validate connector type against board capabilities */
    if ((interfaceConnector == CONNECTOR_BNC &&
         (boardType == 1 || boardType == 3)) ||
        (interfaceConnector == CONNECTOR_RJ45 &&
         (boardType == 0 || boardType == 2))) {
        IOLog("EtherExpress16: configured connector (%s) is not present on board\n",
              _connectorType[interfaceConnector]);

        /* Swap to alternate connector */
        if (interfaceConnector == CONNECTOR_RJ45) {
            interfaceConnector = CONNECTOR_BNC;
        } else {
            interfaceConnector = CONNECTOR_RJ45;
        }

        /* Only log for second generation boards */
        if (boardType >= 2) {
            IOLog("EtherExpress16: defaulting to %s connector\n",
                  _connectorType[interfaceConnector]);
        }
    }

    /* Free connector string */
    [instanceTable freeString:connectorString];

    /* Create transmit queue with max size of 32 packets */
    xmtQueue = [[IONetbufQueue alloc] initWithMaxCount:0x20];

    /* Attach to network with our MAC address */
    network = [super attachToNetworkWithAddress:myAddress];

    return self;
}

/*
 * Reset and enable/disable the hardware
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    BOOL success;

    /* Disable interrupts during reset */
    [self disableAllInterrupts];

    /* Clear transmit in progress flag */
    xmtActive = NO;

    /* Initialize hardware (reset if not enable) */
    [self hwInit:!enable];

    /* Initialize software structures */
    [self swInit];

    /* Configure i82586 */
    success = [self config];
    if (!success) {
        [self setRunning:NO];
        return NO;
    }

    /* Setup individual address (MAC) */
    success = [self ia_setup];
    if (!success) {
        [self setRunning:NO];
        return NO;
    }

    /* Initialize transmit structures */
    [self xmtInit];

    /* Initialize receive structures */
    [self recvInit];

    /* Configure multicast addresses if needed */
    [self _configureMulticastAddresses];

    /* Start receiver */
    [self recvStart];

    /* Enable interrupts and set running state if requested */
    if (enable) {
        if ([self enableAllInterrupts] != IO_R_SUCCESS) {
            [self setRunning:NO];
            return NO;
        }
    }

    /* Delay to allow adapter to stabilize */
    IODelay(500);

    /* Update running state */
    [self setRunning:enable];

    return YES;
}

/*
 * Free driver resources
 */
- (void)free
{
    /* Free transmit queue if allocated */
    if (xmtQueue != nil) {
        [(IONetbufQueue *)xmtQueue free];
        xmtQueue = nil;
    }

    /* Call superclass free */
    [super free];
}

/*
 * Configure the i82586 adapter
 */
- (BOOL)config
{
    unsigned short configCmd[9];  /* 18 bytes */
    unsigned short cmdOffset;
    int i;
    BOOL success;

    /* Clear command buffer */
    memset(configCmd, 0, 18);

    /* Allocate memory region for command */
    cmdOffset = [self memRegion:18];

    /* Build CONFIGURE command block (i82586 format) */
    /* Byte 0-1: Command word */
    *((unsigned char *)&configCmd[0] + 1) &= 0xEF;  /* Clear bit 4 */
    configCmd[0] = (configCmd[0] & 0xF8FF) | CMD_CONFIGURE;

    /* Byte 2: Configuration byte 0 */
    *((unsigned char *)&configCmd[1]) = (*((unsigned char *)&configCmd[1]) & 0xF8) | 0x02;

    /* Byte 3: Configuration byte 1 - EL (end of list) and I (interrupt) */
    *((unsigned char *)&configCmd[1] + 1) |= 0xA0;

    /* Byte 6: Configuration byte 4 - FIFO limit */
    *((unsigned char *)&configCmd[3]) = (*((unsigned char *)&configCmd[3]) & 0xF0) | 0x0C;

    /* Byte 7: Configuration byte 5 */
    *((unsigned char *)&configCmd[3] + 1) = (*((unsigned char *)&configCmd[3] + 1) & 0xF0) | 0x08;

    /* Byte 9: Configuration byte 7 - Slot time and retry */
    *((unsigned char *)&configCmd[4] + 1) = (*((unsigned char *)&configCmd[4] + 1) & 0xC0) | 0x26;

    /* Byte 11: Configuration byte 9 */
    *((unsigned char *)&configCmd[5] + 1) = 0x60;

    /* Byte 12: Configuration byte 10 */
    *((unsigned char *)&configCmd[6]) = 0x02;

    /* Byte 13: Configuration byte 11 - Linear priority */
    *((unsigned char *)&configCmd[6] + 1) |= 0xF0;

    /* Byte 14: Configuration byte 12 - Interframe spacing and promiscuous mode */
    *((unsigned char *)&configCmd[7]) = (*((unsigned char *)&configCmd[7]) & 0xFE) | (promiscuousEnabled ? 1 : 0);

    /* Byte 16: Configuration byte 14 */
    *((unsigned char *)&configCmd[8]) = 0x40;

    /* Write command block to adapter memory */
    inb(base + 0x0F);
    outw(base + 2, cmdOffset);

    for (i = 0; i < 9; i++) {
        outw(base, configCmd[i]);
    }

    /* Execute command */
    [self performCBL:cmdOffset];

    /* Read back command status */
    inb(base + 0x0F);
    outw(base + 4, cmdOffset);

    for (i = 0; i < 9; i++) {
        configCmd[i] = inw(base);
    }

    /* Check OK bit (bit 13 of status word) */
    success = (*((unsigned char *)&configCmd[0] + 1) >> 5) & 1;

    return success;
}

/*
 * Get integer parameter values
 */
- (BOOL)getIntValues:(unsigned int *)parameterArray
        forParameter:(IOParameterName)parameterName
               count:(unsigned int *)count
{    unsigned int capacity = *count;

    if (strcmp(parameterName, "Valid Connectors") == 0) {
        if (capacity > 0) parameterArray[0] = 1;
        if (capacity > 1) parameterArray[1] =
            boardType == 0 || boardType == 2 || boardType == 4;
        if (capacity > 2) parameterArray[2] =
            boardType == 1 || boardType == 3 || boardType == 4;
        if (capacity > 2) *count = 3;
        return 0;
    }
    return [super getIntValues:parameterArray forParameter:parameterName count:count];
}

/*
 * Hardware initialization
 */
- (void)hwInit:(BOOL)reset
{    [self _resetEE16:reset];
    [self _configEE16:reset];
    membase = _setup_mem(base);
    memused = 0;
}

/*
 * Software initialization
 */
- (void)swInit
{    unsigned short iscp[3];
    unsigned short scb[8];
    unsigned short iscpOffset;
    unsigned char *scbBytes = (unsigned char *)scb;
    label_t waitLabel;

    if (set_label(&waitLabel) != 0) {
        IOLog("EtherExpress16: swInit failed (scb timeout)\n");
        return;
    }
    if ([self memAlloc:10] != (unsigned short)-10)
        IOPanic("EtherExpress16: onboard memory allocation failure.");
    iscpOffset = [self memAlloc:6];
    scb_off = [self memAlloc:16];
    _put_scp((unsigned short[5]){0, 0, 0, iscpOffset, 0}, base);
    iscp[0] = 1; iscp[1] = scb_off; iscp[2] = 0;
    _put_iscp(iscp, iscpOffset, base);
    memset(scb, 0, sizeof(scb));
    _put_scb(scb, scb_off, base);
    outb(base + 6, 1);
    while (iscp[0] != 0) _get_iscp_busy(iscp, iscpOffset, base);
    while ((scbBytes[1] & 0xF0) != 0xA0) _get_scb_stat(scb, scb_off, base);
    scbBytes[2] = (scbBytes[2] & 0x0F) | (scbBytes[1] & 0xF0);
    _put_scb_cmd(scb, scb_off, base);
    outb(base + 6, 1);
    _wait_scb(base, scb_off, 750000, &waitLabel);
}

/*
 * Enable promiscuous mode
 */
- (BOOL)enablePromiscuousMode
{
    if (!promiscuousEnabled) {
        promiscuousEnabled = YES;
        [self resetAndEnable:YES];
    }
    return YES;
}

/*
 * Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    if (promiscuousEnabled) {
        promiscuousEnabled = NO;
        [self resetAndEnable:YES];
    }
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
    BOOL wasEnabled = multicastEnabled;

    multicastEnabled = NO;

    if (wasEnabled) {
        [self resetAndEnable:YES];
    }
}

/*
 * Add a multicast address
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    /* Enable multicast mode and reset adapter to apply changes */
    multicastEnabled = YES;
    [self resetAndEnable:YES];
}

/*
 * Remove a multicast address
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    /* Reset and re-enable adapter to apply multicast changes */
    [self resetAndEnable:YES];
}

/*
 * Handle interrupt
 */
- (void)interruptOccurred
{
    unsigned short scb[8];
    unsigned char *bytes = (unsigned char *)scb;
    unsigned char irqMask;

    if (set_label((label_t *)&resetLabel) != 0) {
        [self timeoutOccurred];
        return;
    }

    irqMask = inb(base + 7) & 0xF7;
    outb(base + 7, irqMask);
    outb(base + 7, irqMask | 0x08);

    _wait_scb(base, scb_off, 750000, (label_t *)&resetLabel);
    _get_scb(scb, scb_off, base);
    bytes[2] = (bytes[2] & 0x0F) | (bytes[1] & 0xF0);
    bytes[2] &= 0xF8;
    bytes[3] &= 0x8F;
    bytes[3] &= 0x7F;
    _put_scb_cmd(scb, scb_off, base);
    outb(base + 6, 1);
    _wait_scb(base, scb_off, 750000, (label_t *)&resetLabel);

    if (((bytes[1] >> 4) & 0x05) != 0)
        [self frIntr];
    if (((bytes[1] >> 4) & 0x0A) != 0)
        [self cxIntr];
    _get_scb_stat(scb, scb_off, base);
    if ((scb[0] & 0x70) != 0x40)
        [self recvRestart];
}

/*
 * Handle timeout
 */
- (void)timeoutOccurred
{
    netbuf_t packet;

    /* Check if adapter is still running */
    if ([self isRunning]) {
        /* Timeout during normal operation - try to recover */
        if ([self resetAndEnable:YES]) {
            /* Reset successful - try to restart transmission */
            packet = [xmtQueue dequeue];
            if (packet != NULL) {
                [self transmit:packet];
            }
        }
    }

    /* Check if adapter stopped after timeout */
    if (![self isRunning]) {
        /* Adapter failed - flush transmit queue */
        if ([xmtQueue count] != 0) {
            xmtActive = NO;

            /* Free all queued packets */
            while (1) {
                packet = [xmtQueue dequeue];
                if (packet == NULL) {
                    break;
                }
                nb_free(packet);
            }
        }
    }
}

/*
 * Enable all interrupts
 */
- (IOReturn)enableAllInterrupts
{
    unsigned char irqMask;

    /* Get IRQ mask from mapping table and set bit 3 (enable) */
    irqMask = (_irq_map[irq] & 0x07) | 0x08;

    /* Write to interrupt control register at port+7 */
    outb(base + 7, irqMask);

    /* Call superclass */
    return [super enableAllInterrupts];
}

/*
 * Disable all interrupts
 */
- (void)disableAllInterrupts
{
    unsigned char irqMask;

    /* Get IRQ mask from mapping table (bit 3 clear = disable) */
    irqMask = _irq_map[irq] & 0x07;

    /* Write to interrupt control register at port+7 */
    outb(base + 7, irqMask);

    /* Call superclass */
    [super disableAllInterrupts];
}

/*
 * Transmit a packet
 */
- (void)transmit:(netbuf_t)packet
{
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;
    unsigned short tcbBuffer[8];  /* TCB - 16 bytes */
    unsigned char *tcbBytes = (unsigned char *)tcbBuffer;
    unsigned short tbdBuffer[4];  /* TBD - 8 bytes */
    void *packetData;
    unsigned int packetSize;
    unsigned int payloadLen;
    unsigned short *srcPtr;
    int i;

    /* Check if adapter is running */
    if (![self isRunning]) {
        /* Not running - discard packet */
        nb_free(packet);
        return;
    }

    /* Ensure minimum packet size (60 bytes) */
    packetSize = nb_size(packet);
    if (packetSize < 60) {
        nb_grow_bot(packet, 60 - packetSize);
        packetSize = 60;
    }

    /* Check if transmit is already in progress */
    if (xmtActive) {
        /* Queue packet for later transmission */
        [xmtQueue enqueue:packet];
        return;
    }

    /* Transmit immediately */

    /* Perform loopback check for local packets */
    [self performLoopback:packet];

    /* Map packet to get data pointer */
    packetData = nb_map(packet);

    /* Calculate payload length (packet size - 14 byte header) */
    payloadLen = packetSize - 14;

    /* Build TCB (Transmit Command Block) */
    memset(tcbBuffer, 0, 16);

    /* Clear status bits */
    tcbBytes[0] &= 0xF0;

    /* Copy Ethernet header to TCB (bytes 8-21) */
    tcbBuffer[4] = *((unsigned short *)packetData + 0);  /* Dest bytes 0-1 */
    tcbBuffer[5] = *((unsigned short *)packetData + 1);  /* Dest bytes 2-3 */
    tcbBuffer[6] = *((unsigned short *)packetData + 2);  /* Dest bytes 4-5 */
    tcbBuffer[7] = *((unsigned short *)packetData + 6);  /* Type field */

    /* Set TBD offset (word 3) */
    tcbBuffer[3] = tbd_off;

    /* Set command to TRANSMIT (4) with EL and I bits */
    tcbBytes[3] |= 0xA0;  /* EL=1, I=1 */
    tcbBytes[2] = (tcbBytes[2] & 0xF8) | 0x04;  /* CMD=TRANSMIT */

    /* Write TCB to adapter */
    _put_tcb(tcbBuffer, tcb_off, base);

    /* Copy payload data to transmit buffer */
    srcPtr = (unsigned short *)((char *)packetData + 14);

    /* Set write address to transmit buffer */
    inb(base + 0x0F);
    outw(base + 2, tbuf_off);

    /* Write data in 16-bit words */
    for (i = 0; i < (payloadLen >> 1); i++) {
        outw(base, srcPtr[i]);
    }

    /* Write odd byte if present */
    if (payloadLen & 1) {
        outb(base, ((unsigned char *)srcPtr)[payloadLen - 1]);
    }

    /* Free the netbuf - data has been copied to adapter */
    nb_free(packet);

    /* Build TBD (Transmit Buffer Descriptor) */
    tbdBuffer[0] = 0;
    tbdBuffer[0] = (tbdBuffer[0] & 0xC000) | (payloadLen & 0x3FFF) | 0x8000;  /* EOF bit */
    tbdBuffer[1] = 0xFFFF;  /* Next TBD (none) */
    tbdBuffer[2] = tbuf_off;  /* Buffer address */

    /* Write TBD count field */
    _put_tbd_count(tbdBuffer, tbd_off, base);

    /* Wait for SCB to be ready */
    _wait_scb(base, scb_off, 750000, (label_t *)&resetLabel);

    /* Read SCB command */
    _get_scb_cmd(scbBuffer, scb_off, base);

    /* Start transmit command */
    scbBuffer[2] = tcb_off;  /* CBL offset */
    scbBytes[2] = (scbBytes[2] & 0xF8) | 0x01;  /* CUC=START */

    /* Write SCB command */
    _put_scb_cmd(scbBuffer, scb_off, base);

    /* Send channel attention */
    outb(base + 6, 1);

    /* Set timeout for transmit (3000 milliseconds) */
    [self setRelativeTimeout:3000];

    /* Mark transmit in progress */
    xmtActive = YES;
}

/*
 * Send packet data
 */
- (void)sendPacket:(void *)data length:(unsigned int)len
{
    unsigned int payloadLength;
    unsigned int words;
    unsigned short scb[8];
    unsigned char *scbBytes = (unsigned char *)scb;
    unsigned short tcb[8];
    unsigned short tbd[4];
    unsigned char *tcbBytes = (unsigned char *)tcb;
    label_t waitLabel;
    unsigned int i;

    if (set_label(&waitLabel) != 0) {
        IOLog("EtherExpress16: sendPacket failure (scb timeout)\n");
        return;
    }
    _wait_scb(base, scb_off, 750000, &waitLabel);
    _get_scb(scb, scb_off, base);
    if (xmtActive) {
        while (((scbBytes[1] >> 4) & 0x0A) == 0)
            _get_scb_stat(scb, scb_off, base);
        scbBytes[2] = (scbBytes[2] & 0x0F) | (scbBytes[1] & 0xA0);
        _put_scb_cmd(scb, scb_off, base);
        outb(base + 6, 1);
        _wait_scb(base, scb_off, 750000, &waitLabel);
    }

    memset(tcb, 0, sizeof(tcb));
    tcbBytes[0] &= 0xF0;
    payloadLength = len - 14;
    tcb[4] = ((unsigned short *)data)[0];
    tcb[5] = ((unsigned short *)data)[1];
    tcb[6] = ((unsigned short *)data)[2];
    tcb[7] = ((unsigned short *)data)[6];
    tcb[3] = tbd_off;
    tcbBytes[1] |= 0x20;
    tcbBytes[1] |= 0x80;
    tcbBytes[2] = (tcbBytes[2] & 0xF8) | 4;
    _put_tcb(tcb, tcb_off, base);

    inb(base + 0x0F);
    outw(base + 2, tbuf_off);
    words = payloadLength >> 1;
    for (i = 0; i < words; ++i)
        outw(base, ((unsigned short *)((unsigned char *)data + 14))[i]);
    if (payloadLength & 1)
        outb(base, *((unsigned char *)data + 14 + payloadLength - 1));

    if (payloadLength <= 0x3F)
        payloadLength = 64;
    memset(tbd, 0, sizeof(tbd));
    tbd[0] = (payloadLength & 0x3FFF) | 0x8000;
    tbd[1] = 0xFFFF;
    tbd[2] = tbuf_off;
    _put_tbd_count(tbd, tbd_off, base);

    scb[2] = tcb_off;
    scbBytes[2] = (scbBytes[2] & 0xF8) | 1;
    _put_scb_cmd(scb, scb_off, base);
    outb(base + 6, 1);
    if (!xmtActive) {
        while (((scbBytes[1] >> 4) & 0x0A) == 0)
            _get_scb_stat(scb, scb_off, base);
        scbBytes[2] = (scbBytes[2] & 0x0F) | (scbBytes[1] & 0xA0);
        _put_scb_cmd(scb, scb_off, base);
        outb(base + 6, 1);
        _wait_scb(base, scb_off, 750000, &waitLabel);
    }
}

/*
 * Receive a packet
 */
- (void)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout
{
    unsigned short scb[8];
    unsigned char *scbBytes = (unsigned char *)scb;
    unsigned short rfd[12];
    unsigned char *rfdBytes = (unsigned char *)rfd;
    unsigned short rbd[6];
    unsigned char *rbdBytes = (unsigned char *)rbd;
    unsigned short frameOffset, rbdOffset, nextRBD;
    unsigned int remainingUS = timeout * 1000;
    unsigned int received = 14;
    unsigned int count, words, i;
    unsigned char *destination = (unsigned char *)data;
    BOOL copyFrame = YES;
    label_t waitLabel;

    if (set_label(&waitLabel) != 0) {
        IOLog("EtherExpress16: receivePacket failure (scb timeout)\n");
        return;
    }
    _wait_scb(base, scb_off, 750000, &waitLabel);
    _get_scb(scb, scb_off, base);
    _get_rfd(rfd, frf_off, base);

    if (((scbBytes[1] >> 4) & 0x04) == 0 || (short)rfd[0] >= 0) {
        while (remainingUS > 0) {
            IODelay(50);
            remainingUS -= 50;
            _get_scb_stat(scb, scb_off, base);
            _get_rfd(rfd, frf_off, base);
            if (((scbBytes[1] >> 4) & 0x04) != 0 && (short)rfd[0] < 0)
                break;
        }
        if (((scbBytes[1] >> 4) & 0x04) == 0 || (short)rfd[0] >= 0) {
            if ((scb[0] & 0x70) != 0x40) {
                rfd[3] = frb_off;
                _put_rfd(rfd, frf_off, base);
                _wait_scb(base, scb_off, 750000, &waitLabel);
                _get_scb_cmd(scb, scb_off, base);
                scbBytes[2] = (scbBytes[2] & 0x0F) | (scbBytes[1] & 0x50);
                scb[1] = frf_off;
                scbBytes[2] = (scbBytes[2] & 0x8F) | 0x10;
                _put_scb_cmd(scb, scb_off, base);
                outb(base + 6, 1);
                _wait_scb(base, scb_off, 750000, &waitLabel);
            }
            return;
        }
    }

    frameOffset = frf_off;
    frf_off = rfd[2];
    rfd[2] = 0xFFFF;
    _get_rfd_hdr(rfd, frameOffset, base);
    rbdOffset = rfd[3];
    if (rbdOffset != 0xFFFF && (rfd[0] & 0x2000) != 0) {
        for (i = 0; i < 7; ++i)
            ((unsigned short *)data)[i] = rfd[4 + i];
        _get_rbd(rbd, rbdOffset, base);
        while (1) {
            count = rbd[0] & 0x3FFF;
            if (copyFrame && (rbd[0] & 0x4000) != 0) {
                if (received + count <= 1514) {
                    inb(base + 0x0F);
                    outw(base + 4, rbd[2]);
                    words = count >> 1;
                    for (i = 0; i < words; ++i)
                        ((unsigned short *)(destination + received))[i] = inw(base);
                    if (count & 1)
                        destination[received + count - 1] = inb(base);
                    received += count;
                } else {
                    copyFrame = NO;
                }
            }
            if ((short)rbd[0] < 0)
                break;
            rbdBytes[1] &= 0xBF;
            _put_rbd(rbd, rbdOffset, base);
            rbdOffset = rbd[1];
            _get_rbd(rbd, rbdOffset, base);
        }
        rbdBytes[1] &= 0x7F;
        nextRBD = rbd[1];
        if (nextRBD == 0xFFFF) {
            _put_rbd(rbd, rbdOffset, base);
        } else {
            frb_off = nextRBD;
            rbd[1] = 0xFFFF;
            rbdBytes[3] |= 0x80;
            _put_rbd(rbd, rbdOffset, base);
            rbdBytes[3] &= 0x7F;
            rbd[1] = rbdOffset;
            _put_rbd_nxt(rbd, lrb_off, base);
            lrb_off = rbdOffset;
        }
        if (copyFrame && received > 59)
            *length = received;
    }

    rfdBytes[1] &= 0x5F;
    rfd[3] = 0xFFFF;
    rfdBytes[3] |= 0x80;
    _put_rfd(rfd, frameOffset, base);
    rfdBytes[3] &= 0x7F;
    rfd[2] = frameOffset;
    _put_rfd_lnk(rfd, lrf_off, base);
    lrf_off = frameOffset;
}

/*
 * Allocate memory on adapter
 */
- (unsigned short)memAlloc:(unsigned int)size
{    unsigned short address = [self memRegion:size];
    memused += size;
    return address;
}

/*
 * Get available memory
 */
- (unsigned int)memAvail
{    int available = 0x10000 - memused - membase;
    return available >= 0 ? (unsigned int)available : 0;
}

/*
 * Get memory region information
 */
- (unsigned short)memRegion:(unsigned int)size
{    if ([self memAvail] < size)
        IOPanic("EtherExpress16: onboard memory exhausted");
    return (unsigned short)(-memused - size);
}

/*
 * Perform Command Block List operation
 */
- (void)performCBL:(unsigned short)cmdOffset
{
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;
    int timeout;
    label_t waitLabel;

    if (set_label(&waitLabel) != 0) {
        IOLog("EtherExpress16: performCBL failed (scb timeout)\n");
        return;
    }

    /* Timeout in 100us units (5000 * 100us = 500ms) */
    timeout = 5000;

    /* Read System Control Block */
    _get_scb(scbBuffer, scb_off, base);

    /* Set command block pointer (CBL offset) at word 2 */
    scbBuffer[2] = cmdOffset;

    /* Set CUC (Command Unit Command) to START (1) in command low byte
     * Command word is at bytes 2-3, low byte at index 2
     * CUC is in bits 0-2
     */
    scbBytes[2] = (scbBytes[2] & 0xF8) | 0x01;

    /* Write SCB command */
    _put_scb_cmd(scbBuffer, scb_off, base);

    /* Send channel attention to start command execution */
    outb(base + 6, 1);

    /* Wait for CUC bits to clear (command accepted) */
    if ((scbBytes[2] & 0x07) != 0) {
        do {
            _get_scb_cmd(scbBuffer, scb_off, base);
        } while ((scbBytes[2] & 0x07) != 0);
    }

    /* Poll for command completion (CNA bit set in status high byte)
     * CNA (Command unit Not Active) is bit 7 of status high byte (byte 1)
     * Status high byte upper nibble contains interrupt status bits
     */
    while (((scbBytes[1] >> 4) & 0x08) == 0) {
        /* Decrement timeout */
        timeout -= 100;
        if (timeout < 1) {
            /* Timeout - abort the command */
            IOLog("EtherExpress16: performCBL failed (scb timeout)\n");
            [self abortCBL];
            return;
        }

        /* Delay 100 microseconds */
        IODelay(100);

        /* Read SCB status */
        _get_scb_stat(scbBuffer, scb_off, base);
    }

    /* Acknowledge the CNA interrupt
     * Write status high nibble back to command high byte to acknowledge
     * Preserve lower nibble of command byte
     */
    scbBytes[2] = (scbBytes[2] & 0x0F) | (scbBytes[1] & 0xF0);

    /* Write acknowledgment */
    _put_scb_cmd(scbBuffer, scb_off, base);

    /* Send channel attention */
    outb(base + 6, 1);

    /* Wait for SCB to be ready */
    _wait_scb(base, scb_off, 750000, &waitLabel);

    return;
}

/*
 * Abort Command Block List
 */
- (void)abortCBL
{
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;
    label_t waitLabel;

    if (set_label(&waitLabel) != 0) {
        IOLog("EtherExpress16: abortCBL failed (scb timeout)\n");
        return;
    }

    /* Read current SCB */
    _get_scb(scbBuffer, scb_off, base);

    /* Set CUC (Command Unit Command) to ABORT (4) in command word */
    /* Command word low byte bits 0-2 */
    scbBytes[2] = (scbBytes[2] & 0xF8) | 0x04;

    /* Write SCB command back */
    _put_scb_cmd(scbBuffer, scb_off, base);

    /* Send Channel Attention signal */
    outb(base + 6, 1);

    /* Wait for SCB to be ready (with timeout) */
    _wait_scb(base, scb_off, 750000, &waitLabel);
}

/*
 * Initialize receive structures
 */
- (void)recvInit
{
    unsigned short rfdBuffer[12];
    unsigned short rbdBuffer[6];
    unsigned short currentRFD, nextRFD;
    unsigned short currentRBD, nextRBD;
    unsigned short bufferAddress;
    int i;

    memset(rfdBuffer, 0, sizeof(rfdBuffer));
    memset(rbdBuffer, 0, sizeof(rbdBuffer));
    rfdBuffer[11] = RFD_MAGIC;
    rbdBuffer[0] &= 0xC000;
    rbdBuffer[4] = 0x0300;
    rbdBuffer[5] = RBD_MAGIC;

    currentRFD = [self memAlloc:24];
    frf_off = currentRFD;
    currentRBD = [self memAlloc:12];
    frb_off = currentRBD;
    bufferAddress = [self memAlloc:768];
    rfdBuffer[1] &= 0x7FFF;
    rfdBuffer[3] = currentRBD;
    rbdBuffer[2] = bufferAddress;

    for (i = 1; i <= 31; ++i) {
        nextRFD = [self memAlloc:24];
        nextRBD = [self memAlloc:12];
        bufferAddress = [self memAlloc:768];

        rfdBuffer[2] = nextRFD;
        rfdBuffer[3] = currentRBD;
        rbdBuffer[1] = nextRBD;
        rbdBuffer[2] = bufferAddress;
        rfdBuffer[1] &= 0x7FFF;
        rbdBuffer[5] &= 0x7FFF;
        _put_rfd(rfdBuffer, currentRFD, base);
        _put_rfd_magic(rfdBuffer, currentRFD, base);
        _put_rbd(rbdBuffer, currentRBD, base);
        _put_rbd_magic(rbdBuffer, currentRBD, base);

        currentRFD = nextRFD;
        currentRBD = nextRBD;
        rfdBuffer[3] = 0xFFFF;
        rbdBuffer[1] = 0xFFFF;
    }

    rfdBuffer[2] = 0xFFFF;
    rfdBuffer[1] |= 0x8000;
    rfdBuffer[3] = 0xFFFF;
    rbdBuffer[1] = 0xFFFF;
    rbdBuffer[5] |= 0x8000;
    _put_rfd(rfdBuffer, currentRFD, base);
    _put_rfd_magic(rfdBuffer, currentRFD, base);
    _put_rbd(rbdBuffer, currentRBD, base);
    _put_rbd_magic(rbdBuffer, currentRBD, base);
    lrf_off = currentRFD;
    lrb_off = currentRBD;
}

/*
 * Start receiver
 */
- (void)recvStart
{
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;

    /* Wait for SCB to be ready */
    _wait_scb(base, scb_off, 750000, (label_t *)&resetLabel);

    /* Read SCB command */
    _get_scb_cmd(scbBuffer, scb_off, base);

    /* Set RFA (Receive Frame Area) pointer to head of RFD list */
    scbBuffer[1] = frf_off;

    /* Set RUC (Receive Unit Command) to START (0x10 in bits 4-6) */
    scbBytes[2] = (scbBytes[2] & 0x8F) | 0x10;

    /* Write SCB command */
    _put_scb_cmd(scbBuffer, scb_off, base);

    /* Send channel attention */
    outb(base + 6, 1);

    /* Wait for command to complete */
    _wait_scb(base, scb_off, 750000, (label_t *)&resetLabel);

    return;
}

/*
 * Restart receiver
 */
- (void)recvRestart
{
    unsigned short rfdBuffer[32];
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;

    /* Read current RFD at head */
    _get_rfd(rfdBuffer, frf_off, base);

    /* Validate RFD magic */
    _check_rfd(rfdBuffer, (label_t *)&resetLabel);

    /* Restore RBD pointer to RFD (word offset 11) */
    rfdBuffer[3] = frb_off;

    /* Write RFD back */
    _put_rfd(rfdBuffer, frf_off, base);

    /* Wait for SCB to be ready */
    _wait_scb(base, scb_off, 750000, (label_t *)&resetLabel);

    /* Read SCB command */
    _get_scb_cmd(scbBuffer, scb_off, base);

    /* Set RFA pointer to head of RFD list */
    scbBuffer[1] = frf_off;

    /* Set RUC to START (0x10 in bits 4-6) */
    scbBytes[2] = (scbBytes[2] & 0x8F) | 0x10;

    /* Write SCB command */
    _put_scb_cmd(scbBuffer, scb_off, base);

    /* Send channel attention */
    outb(base + 6, 1);

    /* Wait for command to complete */
    _wait_scb(base, scb_off, 750000, (label_t *)&resetLabel);

    return;
}

/*
 * Process received frame
 */
- (void)recvFrame:(unsigned short)frameOffset hdr:(recv_hdr_t *)hdr ok:(BOOL)frameOK
{
    netbuf_t packet = NULL;
    unsigned char *packetData = NULL;
    unsigned char *destination;
    unsigned short rbd[6];
    unsigned char *rbdBytes = (unsigned char *)rbd;
    unsigned short currentRBD = frameOffset;
    unsigned short nextRBD;
    unsigned int totalBytes = 14;
    unsigned int count, words, i;
    BOOL copyFrame = frameOK;

    [self releaseDebuggerLock];
    if (frameOK) {
        packet = nb_alloc(1514);
        if (packet != NULL) {
            packetData = nb_map(packet);
            memcpy(packetData, hdr, 14);
        } else {
            copyFrame = NO;
            [network incrementInputErrors];
        }
    } else {
        [network incrementInputErrors];
    }

    [self reserveDebuggerLock];
    _get_rbd(rbd, currentRBD, base);
    while (1) {
        _check_rbd(rbd, (label_t *)&resetLabel);
        count = rbd[0] & 0x3FFF;
        if (copyFrame && (rbd[0] & 0x4000) != 0) {
            if (totalBytes + count <= 1514) {
                destination = packetData + totalBytes;
                inb(base + 0x0F);
                outw(base + 4, rbd[2]);
                words = count >> 1;
                for (i = 0; i < words; ++i)
                    ((unsigned short *)destination)[i] = inw(base);
                if (count & 1)
                    destination[count - 1] = inb(base);
                totalBytes += count;
            } else {
                copyFrame = NO;
            }
        }
        if ((short)rbd[0] < 0)
            break;
        rbdBytes[1] &= 0xBF;
        _put_rbd(rbd, currentRBD, base);
        currentRBD = rbd[1];
        _get_rbd(rbd, currentRBD, base);
    }

    rbdBytes[1] &= 0x7F;
    nextRBD = rbd[1];
    if (nextRBD == 0xFFFF) {
        _put_rbd(rbd, currentRBD, base);
    } else {
        frb_off = nextRBD;
        rbd[1] = 0xFFFF;
        rbdBytes[3] |= 0x80;
        _put_rbd(rbd, currentRBD, base);
        rbdBytes[3] &= 0x7F;
        rbd[1] = frameOffset;
        _put_rbd_nxt(rbd, lrb_off, base);
        lrb_off = currentRBD;
    }
    [self releaseDebuggerLock];

    if (packet != NULL) {
        if (copyFrame && totalBytes > 59 &&
            (promiscuousEnabled ||
             ![super isUnwantedMulticastPacket:(ether_header_t *)packetData])) {
            nb_shrink_bot(packet, 1514 - totalBytes);
            [network handleInputPacket:packet extra:0];
        } else {
            nb_free(packet);
        }
    }
    [self reserveDebuggerLock];
}

/*
 * Handle command complete interrupt (transmit complete)
 */
- (void)cxIntr
{
    unsigned short status;
    int collisions;
    netbuf_t nextPacket;

    if (xmtActive) {
        _get_tcb_stat(&status, tcb_off, base);
        if (status & 0x2000)
            [network incrementOutputPackets];
        else
            [network incrementOutputErrors];

        for (collisions = 0; collisions < (status & 0x0F); ++collisions)
            [network incrementCollisions];
        if (status & 0x20) {
            for (collisions = 0; collisions <= 15; ++collisions)
                [network incrementCollisions];
        }
        [self clearTimeout];
        xmtActive = NO;
    }

    nextPacket = [xmtQueue dequeue];
    if (nextPacket != (netbuf_t)0)
        [self transmit:nextPacket];
}

/*
 * Handle frame received interrupt
 */
- (void)frIntr
{
    unsigned short rfd[12];
    unsigned short frameOffset;
    unsigned short rbdOffset;
    unsigned char *bytes = (unsigned char *)rfd;
    [self reserveDebuggerLock];
    frameOffset = frf_off;
    _get_rfd(rfd, frameOffset, base);
    _check_rfd(rfd, (label_t *)&resetLabel);
    while ((short)rfd[0] < 0) {
        frf_off = rfd[2];
        rbdOffset = 0xFFFF;
        _get_rfd_hdr(rfd, frameOffset, base);
        rbdOffset = rfd[3];
        if (rbdOffset != 0xFFFF)
            [self recvFrame:rbdOffset
                        hdr:(recv_hdr_t *)&rfd[4] ok:(rfd[0] & 0x2000) != 0];

        bytes[1] &= 0x5F;
        rbdOffset = 0xFFFF;
        bytes[3] |= 0x80;
        _put_rfd(rfd, frameOffset, base);
        bytes[3] &= 0x7F;
        rfd[2] = frameOffset;
        _put_rfd_lnk(rfd, lrf_off, base);
        lrf_off = frameOffset;
        frameOffset = frf_off;
        _get_rfd(rfd, frameOffset, base);
        _check_rfd(rfd, (label_t *)&resetLabel);
    }
    [self releaseDebuggerLock];
}

@end

/* Private Category Implementation */
@implementation EtherExpress16(EtherExpress16Private)

/*
 * Configure EtherExpress 16 hardware for bus width and connector
 */
- (id)_configEE16:(BOOL)doConfig
{
    unsigned char ctrlReg;
    unsigned short ctrlPort;
    int retries;

    if (doConfig) {
        /* Read control register at port+0x0D */
        ctrlReg = inb(base + 0x0D);

        /* Check if 16-bit slot (bit 2 set) */
        if ((ctrlReg & 0x04) == 0) {
            IOLog("EtherExpress16: 8-bit slot detected\n");
        } else {
            /* Try to configure 16-bit mode */
            ctrlReg |= 0x18;  /* Set bits 3 and 4 */
            ctrlPort = base + 0x0D;

            /* First attempt: try up to 1000 times */
            for (retries = 0; retries < 1000; retries++) {
                /* Write with bit 5 set */
                _disable();
                outb(ctrlPort, ctrlReg | 0x20);
                inw(ctrlPort);

                /* Read back and clear bit 5 */
                ctrlReg = inb(ctrlPort);
                ctrlReg &= 0xDF;
                outb(ctrlPort, ctrlReg);
                _enable();

                /* Check if bit 6 is clear (success) */
                if ((ctrlReg & 0x40) == 0) {
                    goto config_connector;
                }

                IODelay(50);
            }

            /* Second attempt: clear bits 4-5, try up to 10 times */
            ctrlReg &= 0xEF;
            for (retries = 0; retries < 10; retries++) {
                _disable();
                outb(ctrlPort, ctrlReg | 0x20);
                inw(ctrlPort);

                ctrlReg = inb(ctrlPort);
                ctrlReg &= 0xDF;
                outb(ctrlPort, ctrlReg);
                _enable();

                if ((ctrlReg & 0x40) == 0) {
                    goto config_connector;
                }

                IODelay(50);
            }

            /* Failed to configure 16-bit mode */
            outb(base + 0x0D, ctrlReg & 0xF7);
            IOLog("EtherExpress16: Unable to perform 16-bit transfers\n");
            IOLog("EtherExpress16: Defaulting to 8-bit mode\n");
        }
    }

config_connector:
    /* Configure connector type if configured */
    if (boardID == 0xBABB) {
        unsigned char connReg;
        unsigned short connPort = base + 0x300E;

        connReg = inb(connPort);

        /* Clear bits 1 and 7, then set based on connector type */
        connReg &= 0x7D;

        /* Set bit 7 if not AUI (type != 0) */
        if (interfaceConnector != CONNECTOR_AUI) {
            connReg |= 0x80;
        }

        /* Set bit 1 if not BNC (type != 1) */
        if (interfaceConnector != CONNECTOR_BNC) {
            connReg |= 0x02;
        }

        outb(connPort, connReg);
    }

    return self;
}

/*
 * Reset EtherExpress 16 hardware
 */
- (id)_resetEE16:(BOOL)enable
{
    unsigned int eepromConfig;
    unsigned int boardTypeValue;

    /* Assert reset (bit 7) */
    outb(base + 0x0E, 0x80);
    IODelay(500);

    if (enable) {
        /* Pulse additional control bits */
        outb(base + 0x0E, 0xC0);
        IODelay(500);

        /* Return to reset state */
        outb(base + 0x0E, 0x80);
        IODelay(500);
    }

    /* Read Ethernet address from EEPROM */
    _get_etherAddress(&myAddress, base);

    /* Read configuration from EEPROM offset 5 to determine board type */
    eepromConfig = _read_eeprom(5, base);

    /* Determine board type based on EEPROM bits */
    if (eepromConfig & 0x08) {
        /* Bit 3 set - EtherExpress16C */
        boardTypeValue = 4;
    } else if (eepromConfig & 0x01) {
        /* Bit 0 set - EtherExpress16TP */
        boardTypeValue = 1;
        if (boardID == 0xBABB) {
            /* Second generation TP */
            boardTypeValue = 3;
        }
    } else {
        /* Neither bit set - EtherExpress16 */
        boardTypeValue = 0;
        if (boardID == 0xBABB) {
            /* Second generation */
            boardTypeValue = 2;
        }
    }

    boardType = boardTypeValue;

    /* Clear reset */
    outb(base + 0x0E, 0);

    return self;
}

/*
 * Configure multicast addresses on adapter
 */
- (void)_configureMulticastAddresses
{
    void *multicastQueue;
    void *entry;
    int count;
    int cmdSize;
    unsigned short cmdOffset;
    unsigned short *cmdBuffer;
    unsigned short *ptr;
    int i;

    /* Clear multicast configured flag */
    multicastConfigured = NO;

    /* Only configure if multicast mode is enabled */
    if (!multicastEnabled) {
        return;
    }

    /* Get multicast address queue from superclass */
    multicastQueue = [super multicastQueue];
    if (multicastQueue == NULL) {
        return;
    }

    /* Count multicast addresses in queue */
    count = 0;
    for (entry = *(void **)multicastQueue;
         entry != multicastQueue;
         entry = *((void **)entry + 2)) {
        count++;
    }

    if (count == 0) {
        return;
    }

    /* Calculate command buffer size (8 byte header + 6 bytes per address) */
    cmdSize = (count * 6) + 8;

    /* Allocate memory region on adapter */
    cmdOffset = [self memRegion:cmdSize];

    /* Allocate temporary buffer */
    cmdBuffer = (unsigned short *)IOMalloc(cmdSize);
    if (cmdBuffer == NULL) {
        return;
    }

    /* Build multicast command block */
    /* Word 0: command and status */
    cmdBuffer[0] = (cmdBuffer[0] & 0xF8FF) | CMD_MC_SETUP;

    /* Word 1: flags */
    *((unsigned char *)cmdBuffer + 3) |= 0x20;  /* Set bit 5 (EL - end of list) */
    *((unsigned char *)cmdBuffer + 3) |= 0x80;  /* Set bit 7 (I - interrupt) */

    /* Word 3: byte count */
    cmdBuffer[3] = (cmdBuffer[3] & 0xC000) | ((count * 6) & 0x3FFF);

    /* Copy multicast addresses */
    i = 0;
    for (entry = *(void **)multicastQueue;
         entry != multicastQueue;
         entry = *((void **)entry + 2)) {
        /* Copy 6-byte address */
        *((unsigned int *)(cmdBuffer + (i * 3) + 4)) = *(unsigned int *)entry;
        cmdBuffer[(i * 3) + 6] = *((unsigned short *)((unsigned int *)entry + 1));
        i++;
    }

    /* Write command block to adapter memory */
    inb(base + 0x0F);
    outw(base + 2, cmdOffset);

    ptr = cmdBuffer;
    for (i = 0; i < (cmdSize >> 1); i++) {
        outw(base, *ptr);
        ptr++;
    }

    /* Execute command */
    [self performCBL:cmdOffset];

    /* Read back command status */
    inb(base + 0x0F);
    outw(base + 4, cmdOffset);

    ptr = cmdBuffer;
    for (i = 0; i < 4; i++) {
        *ptr = inw(base);
        ptr++;
    }

    /* Free buffer */
    IOFree(cmdBuffer, cmdSize);

    /* Mark multicast as configured */
    multicastConfigured = YES;
}

/*
 * Setup individual address (MAC address)
 */
- (BOOL)ia_setup
{
    unsigned short iaCmd[7];  /* 14 bytes: 8 byte header + 6 byte address */
    unsigned short cmdOffset;
    int i;
    BOOL success;

    /* Clear command buffer */
    memset(iaCmd, 0, 14);

    /* Allocate memory region for command */
    cmdOffset = [self memRegion:14];

    /* Build IA-SETUP command block (i82586 format) */
    /* Byte 0-1: Command word */
    iaCmd[0] = (iaCmd[0] & 0xF8FF) | CMD_IA_SETUP;

    /* Byte 2-3: Status and flags */
    *((unsigned char *)&iaCmd[1] + 1) |= 0x20;  /* Set bit 5 (EL - end of list) */
    *((unsigned char *)&iaCmd[1] + 1) |= 0x80;  /* Set bit 7 (I - interrupt) */

    /* Bytes 8-13: MAC address */
    iaCmd[4] = *((unsigned short *)&myAddress.ether_addr_octet[0]);
    iaCmd[5] = *((unsigned short *)&myAddress.ether_addr_octet[2]);
    iaCmd[6] = *((unsigned short *)&myAddress.ether_addr_octet[4]);

    /* Write command block to adapter memory */
    inb(base + 0x0F);
    outw(base + 2, cmdOffset);

    for (i = 0; i < 7; i++) {
        outw(base, iaCmd[i]);
    }

    /* Execute command */
    [self performCBL:cmdOffset];

    /* Read back command status */
    inb(base + 0x0F);
    outw(base + 4, cmdOffset);

    for (i = 0; i < 7; i++) {
        iaCmd[i] = inw(base);
    }

    /* Check OK bit (bit 13 of status word) */
    success = (*((unsigned char *)&iaCmd[0] + 1) >> 5) & 1;

    return success;
}

/*
 * Initialize transmit structures
 */
- (void)xmtInit
{
    unsigned short tcbBuffer[8];   /* TCB - 16 bytes */
    unsigned char *tcbBytes = (unsigned char *)tcbBuffer;
    unsigned short tbdBuffer[4];   /* TBD - 8 bytes */

    /* Initialize TCB buffer */
    memset(tcbBuffer, 0, 16);
    tcbBytes[0] &= 0xF0;  /* Clear status */

    /* Initialize TBD buffer */
    memset(tbdBuffer, 0, 8);
    tbdBuffer[0] = 0;  /* Clear count */

    /* Allocate transmit command block (16 bytes) */
    tcb_off = [self memAlloc:0x10];

    /* Allocate transmit buffer descriptor (8 bytes) */
    tbd_off = [self memAlloc:0x08];

    /* Allocate transmit buffer (1514 bytes for max Ethernet frame) */
    tbuf_off = [self memAlloc:0x5EA];

    /* Set TBD offset in TCB */
    tcbBuffer[3] = tbd_off;

    /* Write initial TCB to adapter */
    _put_tcb(tcbBuffer, tcb_off, base);

    /* Set buffer address in TBD */
    tbdBuffer[2] = tbuf_off;

    /* Write initial TBD to adapter */
    _put_tbd(tbdBuffer, tbd_off, base);

    return;
}

@end

/* Kernel Server Instance Implementation */
@implementation EtherExpress16KernelServerInstance

+ (id)kernelServerInstance
{
    return [[self alloc] init];
}

@end

/* Version Information Implementation */
@implementation EtherExpress16Version

+ (const char *)driverKitVersionForEtherExpress16
{
    return "1.0.0";
}

@end

/*
 * Utility Functions
 *
 * EtherExpress 16 I/O Port Protocol:
 * - Port+0x00: Data port for windowed reads/writes
 * - Port+0x02: Write address/offset register
 * - Port+0x04: Read address/offset register
 * - Port+0x0E: EEPROM control port (bit-banging)
 * - Port+0x0F: Status/clear register
 *
 * The adapter uses a windowed I/O scheme:
 * - For reads:  1) inb(port+0x0F) to clear status
 *               2) outb(port+4, offset) to set address
 *               3) inw(port+0) to read data
 * - For writes: 1) inb(port+0x0F) to clear status
 *               2) outb(port+2, offset) to set address
 *               3) outw(port+0, data) to write data
 *
 * EEPROM bit-banging protocol (port+0x0E):
 * - Bit 0: Clock signal
 * - Bit 2: Data bit
 * - Control byte base: 0x82 (read) or 0x83 (write strobe)
 */


/* Check Receive Buffer Descriptor magic value */
static void _check_rbd(unsigned short *rbd, label_t *label)
{
    /* Check magic value at offset 10 (word offset 5) */
    if (rbd[5] != RBD_MAGIC) {
        jump_label(label);
    }
}

/* Check Receive Frame Descriptor magic value */
static void _check_rfd(unsigned short *rfd, label_t *label)
{
    /* Check magic value at offset 0x16 (word offset 11) */
    if (rfd[11] != RFD_MAGIC) {
        jump_label(label);
    }
}

/* Read EEPROM word via bit-banging */
static unsigned short _get_eeprom(unsigned short base)
{
    unsigned short result = 0;
    unsigned int mask = 0x8000;
    unsigned short port = base + 0x0E;
    unsigned char value;

    /* Read 16 bits */
    while (mask != 0) {
        /* Set read strobe high */
        outb(port, 0x83);
        IODelay(10);

        /* Read bit */
        value = inb(port);
        if (value & 0x08) {
            result |= mask;
        }

        /* Set read strobe low */
        outb(port, 0x82);
        IODelay(10);

        mask >>= 1;
    }

    return result;
}

/* Read Ethernet address from EEPROM */
static void _get_etherAddress(enet_addr_t *addr, unsigned short base)
{
    unsigned short word1, word2, word3;

    /* Read 3 words from EEPROM (locations 2, 3, 4) */
    word1 = _read_eeprom(2, base);
    word2 = _read_eeprom(3, base);
    word3 = _read_eeprom(4, base);

    /* Byte swap and store (Intel byte order to network byte order) */
    addr->ether_addr_octet[0] = (word3 >> 8) & 0xFF;
    addr->ether_addr_octet[1] = word3 & 0xFF;
    addr->ether_addr_octet[2] = (word2 >> 8) & 0xFF;
    addr->ether_addr_octet[3] = word2 & 0xFF;
    addr->ether_addr_octet[4] = (word1 >> 8) & 0xFF;
    addr->ether_addr_octet[5] = word1 & 0xFF;
}

/* Read ISCP busy status and buffer data */
static void _get_iscp_busy(unsigned short *buffer, unsigned short value, unsigned short base)
{
    inb(base + 0x0F);
    outw(base + 4, value);
    *buffer = inw(base);
}

/* Read Receive Buffer Descriptor from adapter */
static void _get_rbd(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set read address */
    outw(base + 4, offset);

    /* Read 6 words */
    for (count = 5; count >= 0; count--) {
        *buffer = inw(base);
        buffer++;
    }
}

/* Read Receive Frame Descriptor from adapter */
static void _get_rfd(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    inb(base + 0x0F);
    outw(base + 4, offset);
    for (count = 3; count >= 0; count--)
        *buffer++ = inw(base);

    inb(base + 0x0F);
    outw(base + 4, offset + 22);
    buffer[7] = inw(base);
}

/* Read Receive Frame Descriptor header */
static void _get_rfd_hdr(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    unsigned short *ptr;
    int count;

    /* Start at word offset 4 in buffer */
    ptr = buffer + 4;

    /* Clear status and set read address to offset+8 */
    inb(base + 0x0F);
    outw(base + 4, offset + 8);

    /* Read 7 words */
    for (count = 6; count >= 0; count--) {
        *ptr = inw(base);
        ptr++;
    }
}

/* Read System Control Block from adapter */
static void _get_scb(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set read address */
    outw(base + 4, offset);

    /* Read 8 words */
    for (count = 7; count >= 0; count--) {
        *buffer = inw(base);
        buffer++;
    }
}

/* Read System Control Block command words */
static void _get_scb_cmd(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set read address to offset+2 */
    outw(base + 4, offset + 2);

    /* Skip first word, then read 3 words */
    buffer++;
    for (count = 2; count >= 0; count--) {
        buffer++;
        *buffer = inw(base);
    }
}

/* Read System Control Block status */
static void _get_scb_stat(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    inb(base + 0x0F);
    outw(base + 4, offset);
    *buffer = inw(base);
}

/* Read Transmit Command Block status */
static void _get_tcb_stat(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    inb(base + 0x0F);
    outw(base + 4, offset);
    *buffer = inw(base);
}

/* Write value to EEPROM via bit-banging */
static void _put_eeprom(unsigned short value, unsigned char bitCount, unsigned short base)
{
    unsigned char ctrlByte = 0x82;
    unsigned int mask;
    unsigned short port = base + 0x0E;

    /* Calculate starting bit mask */
    mask = 1 << ((bitCount - 1) & 0x1F);

    /* Write bits MSB first */
    while (mask != 0) {
        /* Set or clear data bit */
        if (value & mask) {
            ctrlByte |= 0x04;  /* Set bit 2 */
        } else {
            ctrlByte &= 0xFB;  /* Clear bit 2 */
        }

        /* Write data bit */
        outb(port, ctrlByte);
        IODelay(10);

        /* Pulse clock high */
        outb(port, ctrlByte | 0x01);
        IODelay(10);

        /* Clock low */
        outb(port, ctrlByte);
        IODelay(10);

        mask >>= 1;
    }
}

/* Write ISCP (Intermediate System Configuration Pointer) */
static void _put_iscp(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set write address */
    outw(base + 2, offset);

    /* Write 3 words */
    for (count = 2; count >= 0; count--) {
        outw(base, *buffer);
        buffer++;
    }
}

/* Write Receive Buffer Descriptor */
static void _put_rbd(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set write address */
    outw(base + 2, offset);

    /* Write 5 words */
    for (count = 4; count >= 0; count--) {
        outw(base, *buffer);
        buffer++;
    }
}

/* Write RBD magic value at offset+10 */
static void _put_rbd_magic(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    inb(base + 0x0F);
    outw(base + 2, offset + 10);
    outw(base, buffer[5]);
}

/* Write RBD next pointer fields */
static void _put_rbd_nxt(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    inb(base + 0x0F);
    outw(base + 2, offset + 2);
    outw(base, buffer[1]);
    inb(base + 0x0F);
    outw(base + 2, offset + 8);
    outw(base, buffer[4]);
}

/* Write Receive Frame Descriptor */
static void _put_rfd(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set write address */
    outw(base + 2, offset);

    /* Write 4 words */
    for (count = 3; count >= 0; count--) {
        outw(base, *buffer);
        buffer++;
    }
}

/* Write RFD link fields */
static void _put_rfd_lnk(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    inb(base + 0x0F);
    outw(base + 2, offset + 4);
    outw(base, buffer[2]);
    inb(base + 0x0F);
    outw(base + 2, offset + 2);
    outw(base, buffer[1]);
}

/* Write RFD magic value at offset+0x16 */
static void _put_rfd_magic(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    inb(base + 0x0F);
    outw(base + 2, offset + 0x16);
    outw(base, buffer[11]);
}

/* Write System Control Block */
static void _put_scb(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set write address */
    outw(base + 2, offset);

    /* Write 8 words */
    for (count = 7; count >= 0; count--) {
        outw(base, *buffer);
        buffer++;
    }
}

/* Write System Control Block command words */
static void _put_scb_cmd(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set write address to offset+2 */
    outw(base + 2, offset + 2);

    /* Skip first word, then write 3 words */
    for (count = 2; count >= 0; count--) {
        buffer++;
        outw(base, *buffer);
    }
}

/* Write System Configuration Pointer (SCP) */
static void _put_scp(unsigned short *buffer, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set write address to fixed location (i82586 requirement) */
    outw(base + 2, SCP_ADDRESS);

    /* Write 5 words */
    for (count = 4; count >= 0; count--) {
        outw(base, *buffer);
        buffer++;
    }
}

/* Write Transmit Buffer Descriptor */
static void _put_tbd(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set write address */
    outw(base + 2, offset);

    /* Write 4 words */
    for (count = 3; count >= 0; count--) {
        outw(base, *buffer);
        buffer++;
    }
}

/* Write TBD count field */
static void _put_tbd_count(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    inb(base + 0x0F);
    outw(base + 2, offset);
    outw(base, buffer[0]);
}

/* Write Transmit Command Block */
static void _put_tcb(unsigned short *buffer, unsigned short offset, unsigned short base)
{
    int count;

    /* Clear status */
    inb(base + 0x0F);

    /* Set write address */
    outw(base + 2, offset);

    /* Write 8 words */
    for (count = 7; count >= 0; count--) {
        outw(base, *buffer);
        buffer++;
    }
}

/* Read EEPROM word at given offset with proper command sequence */
static unsigned short _read_eeprom(unsigned short offset, unsigned short base)
{
    unsigned short value;

    /* Send READ command (opcode 6, 3 bits) */
    _put_eeprom(6, 3, base);

    /* Send address (offset, 6 bits) */
    _put_eeprom(offset, 6, base);

    /* Read the data word */
    value = _get_eeprom(base);

    /* Deselect EEPROM */
    outb(base + 0x0E, 0);

    return value;
}

/* Setup and detect adapter memory configuration */
static unsigned short _setup_mem(unsigned short base)
{
    int i;
    unsigned char readback;

    /* Clear/initialize memory - read 16 words from address 0 */
    for (i = 0; i < 0x10; i++) {
        inb(base + 0x0F);
        outw(base + 4, 0);
        inb(base);
    }

    /* Test memory at address 0 */
    inb(base + 0x0F);
    outw(base + 2, 0);
    outb(base, 0);

    /* Test memory at address 0x8000 */
    inb(base + 0x0F);
    outw(base + 2, 0x8000);
    outb(base, 0);

    /* Write test pattern 0xAA to address 0 */
    inb(base + 0x0F);
    outw(base + 2, 0);
    outb(base, 0xAA);

    /* Read back from address 0x8000 to test memory size */
    inb(base + 0x0F);
    outw(base + 4, 0x8000);
    readback = inb(base);

    /* If readback is 0xAA, memory wraps - only 32K */
    /* If readback is NOT 0xAA, full 64K memory present */
    if (readback == 0xAA) {
        return 0x8000;  /* 32K memory */
    } else {
        return 0;       /* 64K memory (base 0) */
    }
}

/* Wait for System Control Block to become ready */
static void _wait_scb(unsigned short base, unsigned short offset, int retries, label_t *label)
{
    unsigned short scbCmd;

    while (retries != 0) {
        inb(base + 0x0F);
        outw(base + 4, offset + 2);
        scbCmd = inw(base);
        if (scbCmd == 0)
            return;
        retries--;
    }
    if (label != 0)
        jump_label(label);
}
