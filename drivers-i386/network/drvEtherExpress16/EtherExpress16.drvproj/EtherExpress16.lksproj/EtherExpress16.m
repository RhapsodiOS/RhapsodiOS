/*
 * EtherExpress16.m
 * Intel EtherExpress 16 Network Driver - Main Implementation
 */

#import "EtherExpress16.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <driverkit/IOQueue.h>
#import <machkit/NXLock.h>

/* Forward declarations for utility functions */
static void _check_rbd(unsigned short *rbd, unsigned int lineNumber);
static void _check_rfd(unsigned short *rfd, unsigned int lineNumber);
static unsigned short _get_eeprom(unsigned short ioBase);
static void _get_etherAddress(enet_addr_t *addr, unsigned short ioBase);
static void _get_iscp_busy(unsigned short *buffer, unsigned short value, unsigned short ioBase);
static void _get_rbd(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _get_rfd(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _get_rfd_hdr(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _get_scb(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _get_scb_cmd(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _get_scb_stat(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _get_tcb_stat(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_eeprom(unsigned short value, unsigned char bitCount, unsigned short ioBase);
static void _put_iscp(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_rbd(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_rbd_magic(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_rbd_nxt(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_rfd(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_rfd_lnk(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_rfd_magic(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_scb(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_scb_cmd(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_scp(unsigned short *buffer, unsigned short ioBase);
static void _put_tbd(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_tbd_count(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static void _put_tcb(unsigned short *buffer, unsigned short offset, unsigned short ioBase);
static unsigned short _read_eeprom(unsigned short offset, unsigned short ioBase);
static unsigned short _setup_mem(unsigned short ioBase);
static void _wait_scb(unsigned short ioBase, unsigned short offset, int retries, unsigned int lineNumber);
static void _jump_label(unsigned int lineNumber);

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
    unsigned short ioBase;
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

    ioBase = portRange->start;

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
        readByte = inb(ioBase + 0x0F);

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
        IOLog("EtherExpress16: Adapter not found at address 0x%x\n", ioBase);
        [driver free];
        return NO;
    } else if (idValue != EE16_ID_VALUE) {
        IOLog("EtherExpress16: Unrecognized adapter found at address 0x%x (ID=0x%04x)\n",
              ioBase, idValue);
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
    void *instanceTable;
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
    ioBase = portRange->start;

    /* Read adapter ID value from port+0x300F (extended ID port)
     * This reads the same nibble sequence as probe, but from offset 0x300F
     * Used to differentiate between board revisions (0xBABA vs 0xBABB)
     */
    foundStart = NO;
    idValue = 0;
    nibbleIndex = 0;
    maxNibbles = 0x10;

    do {
        readByte = inb(ioBase + 0x300F);

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
    configFlag = idValue;

    /* Check if board version is supported (0xBABA or 0xBABB only) */
    if ((unsigned short)(configFlag + 0x4546) > 1) {
        IOLog("EtherExpress16: unsupported board version\n");
    }

    /* Initialize state flags */
    isRunning = NO;
    isPromiscuous = NO;
    isMulticast = NO;

    /* Reset hardware (disable, don't enable yet) */
    [self resetAndEnable:NO];

    /* Log board information */
    IOLog("EtherExpress16: %s at 0x%x IRQ %d\n",
          _boardDescription[boardType], ioBase, irq);

    /* Get instance table for configuration parameters */
    instanceTable = [deviceDescription deviceInstance];
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
                    connectorType = i;
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
        connectorType = CONNECTOR_BNC;
        break;
    default:
        connectorType = CONNECTOR_RJ45;
        break;
    }

    IOLog("EtherExpress16: defaulting to %s connector\n",
          _connectorType[connectorType]);

connector_configured:
    /* Validate connector type against board capabilities */
    if ((connectorType == CONNECTOR_BNC &&
         (boardType == 1 || boardType == 3)) ||
        (connectorType == CONNECTOR_RJ45 &&
         (boardType == 0 || boardType == 2))) {
        IOLog("EtherExpress16: configured connector (%s) is not present on board\n",
              _connectorType[connectorType]);

        /* Swap to alternate connector */
        if (connectorType == CONNECTOR_RJ45) {
            connectorType = CONNECTOR_BNC;
        } else {
            connectorType = CONNECTOR_RJ45;
        }

        /* Only log for second generation boards */
        if (boardType >= 2) {
            IOLog("EtherExpress16: defaulting to %s connector\n",
                  _connectorType[connectorType]);
        }
    }

    /* Free connector string */
    [instanceTable freeString:connectorString];

    /* Create transmit queue with max size of 32 packets */
    txQueue = [[[IOQueue alloc] initWithMaxCount:0x20] init];

    /* Attach to network with our MAC address */
    networkInterface = [super attachToNetworkWithAddress:&stationAddress];

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
    txInProgress = NO;

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
    [self __configureMulticastAddresses];

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
    if (txQueue != nil) {
        [txQueue free];
        txQueue = nil;
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
    mem_region_t region;
    int i;
    BOOL success;

    /* Clear command buffer */
    memset(configCmd, 0, 18);

    /* Allocate memory region for command */
    region = [self memRegion:18];
    cmdOffset = region.start;

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
    *((unsigned char *)&configCmd[7]) = (*((unsigned char *)&configCmd[7]) & 0xFE) | (isPromiscuous ? 1 : 0);

    /* Byte 16: Configuration byte 14 */
    *((unsigned char *)&configCmd[8]) = 0x40;

    /* Write command block to adapter memory */
    inb(ioBase + 0x0F);
    outb(ioBase + 2, cmdOffset);

    for (i = 0; i < 9; i++) {
        outw(ioBase, configCmd[i]);
    }

    /* Execute command */
    [self performCBL:cmdOffset];

    /* Read back command status */
    inb(ioBase + 0x0F);
    outb(ioBase + 4, cmdOffset);

    for (i = 0; i < 9; i++) {
        configCmd[i] = inw(ioBase);
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
{
    unsigned int maxCount = *count;

    /* Handle connector type parameter */
    if (strcmp(parameterName, "Connector") == 0) {
        /* Return available connector types based on board type */
        *count = 0;

        if (boardType == 1 || boardType == 3) {
            /* EtherExpress16TP variants - only RJ-45 */
            if (maxCount > 0) {
                parameterArray[0] = CONNECTOR_RJ45;
                *count = 1;
            }
        } else if (boardType == 4) {
            /* EtherExpress16C - combo card with all connectors */
            if (maxCount >= 3) {
                parameterArray[0] = CONNECTOR_AUI;
                parameterArray[1] = CONNECTOR_BNC;
                parameterArray[2] = CONNECTOR_RJ45;
                *count = 3;
            } else if (maxCount == 2) {
                parameterArray[0] = CONNECTOR_AUI;
                parameterArray[1] = CONNECTOR_BNC;
                *count = 2;
            } else if (maxCount == 1) {
                parameterArray[0] = CONNECTOR_AUI;
                *count = 1;
            }
        } else {
            /* EtherExpress16 (original) - AUI and BNC */
            if (maxCount >= 2) {
                parameterArray[0] = CONNECTOR_AUI;
                parameterArray[1] = CONNECTOR_BNC;
                *count = 2;
            } else if (maxCount == 1) {
                parameterArray[0] = CONNECTOR_AUI;
                *count = 1;
            }
        }

        return (*count > 0) ? YES : NO;
    }

    /* Call superclass for other parameters */
    return [super getIntValues:parameterArray
                  forParameter:parameterName
                         count:count];
}

/*
 * Hardware initialization
 */
- (BOOL)hwInit:(BOOL)reset
{
    unsigned short memBase;

    /* Reset hardware if requested */
    if (reset) {
        [self __resetEE16:YES];
    }

    /* Configure hardware (bus width and connector) */
    [self __configEE16:reset];

    /* Setup and detect memory configuration */
    memBase = _setup_mem(ioBase);

    /* Store memory base and size */
    if (memBase == 0x8000) {
        /* 32K memory */
        self->memBase = 0x8000;
        self->memSize = 0x8000;
    } else {
        /* 64K memory */
        self->memBase = 0;
        self->memSize = 0x10000;
    }

    return YES;
}

/*
 * Software initialization
 */
- (BOOL)swInit
{
    unsigned short scpBuffer[5];  /* SCP - 10 bytes */
    unsigned short iscpBuffer[3]; /* ISCP - 6 bytes */
    unsigned short scbBuffer[8];  /* SCB - 16 bytes */
    unsigned char *scbBytes = (unsigned char *)scbBuffer;
    unsigned short iscpOffset;
    unsigned short scbCheckAddr;

    /* Allocate fixed i82586 control structures in adapter memory
     * Must allocate from specific addresses:
     * - SCP is at fixed location 0xFFF6 (SCP_ADDRESS)
     * - We need ISCP at -10 from memory top
     * - SCB can be anywhere
     */

    /* Allocate ISCP at offset -10 (0xFFF6) */
    scbCheckAddr = [self memAlloc:10];
    if (scbCheckAddr != (unsigned short)-10) {
        IOPanic("EtherExpress16: onboard memory allocation failure.");
    }

    /* Allocate ISCP (6 bytes) */
    iscpOffset = [self memAlloc:6];

    /* Allocate SCB (16 bytes) */
    scbOffset = [self memAlloc:16];

    /* Build SCP (System Configuration Pointer)
     * Word 0-1: System bus (0 = 16-bit, 1 = 8-bit)
     * Word 2-3: Reserved (0)
     * Word 4:   ISCP base offset (low word)
     * Word 5:   ISCP base offset (high word)
     */
    scpBuffer[0] = 0;
    scpBuffer[1] = 0;
    scpBuffer[2] = 0;
    scpBuffer[3] = iscpOffset;
    scpBuffer[4] = 0;

    /* Write SCP to fixed location */
    _put_scp(scpBuffer, ioBase);

    /* Build ISCP (Intermediate System Configuration Pointer)
     * Word 0: Busy flag (1 = busy, cleared by i82586)
     * Word 1: SCB offset
     * Word 2: SCB base (high word, always 0)
     */
    iscpBuffer[0] = 1;     /* Busy flag */
    iscpBuffer[1] = scbOffset;
    iscpBuffer[2] = 0;     /* Base address high */

    /* Write ISCP */
    _put_iscp(iscpBuffer, iscpOffset, ioBase);

    /* Initialize SCB (System Control Block) */
    memset(scbBuffer, 0, 16);
    scbBuffer[0] = 0;  /* Status word */

    /* Write SCB */
    _put_scb(scbBuffer, scbOffset, ioBase);

    /* Issue Channel Attention to start i82586 initialization */
    outb(ioBase + 6, 1);

    /* Wait for ISCP busy flag to clear (i82586 sets it to 0) */
    if (iscpBuffer[0] != 0) {
        do {
            _get_iscp_busy(iscpBuffer, iscpOffset, ioBase);
        } while (iscpBuffer[0] != 0);
    }

    /* Wait for SCB status to show CX and CNA (0xA0 in high nibble of status high byte)
     * This indicates i82586 initialization is complete
     */
    if ((scbBytes[1] & 0xF0) != 0xA0) {
        do {
            _get_scb_stat(scbBuffer, scbOffset, ioBase);
        } while ((scbBytes[1] & 0xF0) != 0xA0);
    }

    /* Acknowledge the CX/CNA interrupts */
    scbBytes[2] = (scbBytes[2] & 0x0F) | (scbBytes[1] & 0xF0);

    /* Write acknowledgment */
    _put_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Send channel attention */
    outb(ioBase + 6, 1);

    /* Wait for SCB to be ready */
    _wait_scb(ioBase, scbOffset, 750000, __LINE__);

    return YES;
}

/*
 * Enable promiscuous mode
 */
- (BOOL)enablePromiscuousMode
{
    if (!isPromiscuous) {
        isPromiscuous = YES;
        [self resetAndEnable:YES];
    }
    return YES;
}

/*
 * Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    if (isPromiscuous) {
        isPromiscuous = NO;
        [self resetAndEnable:YES];
    }
}

/*
 * Enable multicast mode
 */
- (BOOL)enableMulticastMode
{
    isMulticast = YES;
    return YES;
}

/*
 * Disable multicast mode
 */
- (void)disableMulticastMode
{
    BOOL wasEnabled = isMulticast;

    isMulticast = NO;

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
    isMulticast = YES;
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
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;
    unsigned char statusByte, cmdByte;
    unsigned char irqMask, savedIRQMask;
    unsigned short statusWord;

    /* Disable interrupts at adapter */
    savedIRQMask = inb(ioBase + 7);
    irqMask = savedIRQMask & 0xF7;  /* Clear bit 3 (disable) */
    outb(ioBase + 7, irqMask);

    /* Re-enable interrupts at adapter */
    outb(ioBase + 7, savedIRQMask);

    /* Wait for SCB to be ready */
    _wait_scb(ioBase, scbOffset, 750000, 0);

    /* Read System Control Block */
    _get_scb(scbBuffer, scbOffset, ioBase);

    /* Extract status and command bytes
     * SCB format: [status word][command word][...]
     * Byte 0: Status low
     * Byte 1: Status high (interrupt status bits in upper nibble)
     * Byte 2: Command low
     * Byte 3: Command high
     */
    statusByte = scbBytes[1];  /* Status high byte */
    cmdByte = scbBytes[2];     /* Command low byte */

    /* Acknowledge interrupt by writing status bits back to command
     * Preserve CUS (bit 3) and status high nibble, clear command low nibble
     */
    scbBytes[3] = (scbBytes[3] & 0x08) | (statusByte & 0xF0);
    scbBytes[2] = cmdByte & 0x0F;

    /* Write SCB command to acknowledge interrupt */
    _put_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Send channel attention to execute command */
    outb(ioBase + 6, 1);

    /* Wait for command to complete */
    _wait_scb(ioBase, scbOffset, 750000, 0);

    /* Check interrupt status bits (upper nibble of status high byte)
     * Bit 4 (0x10): FR - Frame Received
     * Bit 6 (0x40): RNR - Receiver Not Ready
     * Bit 5 (0x20): CX - Command eXecuted
     * Bit 7 (0x80): CNA - Command unit Not Active
     */

    /* Handle frame received or receiver not ready (bits 4 or 6) */
    if ((statusByte >> 4) & 0x5) {  /* Check bits 4 and 6 (0x5 = 0101) */
        [self frIntr];
    }

    /* Handle command complete (bits 5 or 7) */
    if ((statusByte >> 4) & 0xA) {  /* Check bits 5 and 7 (0xA = 1010) */
        [self cxIntr];
    }

    /* Read SCB status to check RU (Receive Unit) state */
    _get_scb_stat(scbBuffer, scbOffset, ioBase);

    statusWord = scbBuffer[0];

    /* Check RU status (bits 4-6 of low byte)
     * 0x40 = RU ready
     * If not ready, restart receiver
     */
    if ((scbBytes[0] & 0x70) != 0x40) {
        [self recvRestart];
    }
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
            packet = [txQueue dequeue];
            if (packet != NULL) {
                [self transmit:packet];
            }
        }
    }

    /* Check if adapter stopped after timeout */
    if (![self isRunning]) {
        /* Adapter failed - flush transmit queue */
        if ([txQueue count] != 0) {
            txInProgress = NO;

            /* Free all queued packets */
            while (1) {
                packet = [txQueue dequeue];
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
    outb(ioBase + 7, irqMask);

    interruptDisabled = NO;

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
    outb(ioBase + 7, irqMask);

    interruptDisabled = YES;

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
    if (txInProgress) {
        /* Queue packet for later transmission */
        [txQueue enqueue:packet];
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
    tcbBuffer[3] = txTbdOffset;

    /* Set command to TRANSMIT (4) with EL and I bits */
    tcbBytes[3] |= 0xA0;  /* EL=1, I=1 */
    tcbBytes[2] = (tcbBytes[2] & 0xF8) | 0x04;  /* CMD=TRANSMIT */

    /* Write TCB to adapter */
    _put_tcb(tcbBuffer, txCmdOffset, ioBase);

    /* Copy payload data to transmit buffer */
    srcPtr = (unsigned short *)((char *)packetData + 14);

    /* Set write address to transmit buffer */
    inb(ioBase + 0x0F);
    outb(ioBase + 2, txBufferOffset);

    /* Write data in 16-bit words */
    for (i = 0; i < (payloadLen >> 1); i++) {
        outw(ioBase, srcPtr[i]);
    }

    /* Write odd byte if present */
    if (payloadLen & 1) {
        outb(ioBase, ((unsigned char *)srcPtr)[payloadLen - 1]);
    }

    /* Free the netbuf - data has been copied to adapter */
    nb_free(packet);

    /* Build TBD (Transmit Buffer Descriptor) */
    tbdBuffer[0] = 0;
    tbdBuffer[0] = (tbdBuffer[0] & 0xC000) | (payloadLen & 0x3FFF) | 0x8000;  /* EOF bit */
    tbdBuffer[1] = 0xFFFF;  /* Next TBD (none) */
    tbdBuffer[2] = txBufferOffset;  /* Buffer address */

    /* Write TBD count field */
    _put_tbd_count(tbdBuffer, txTbdOffset, ioBase);

    /* Wait for SCB to be ready */
    _wait_scb(ioBase, scbOffset, 750000, __LINE__);

    /* Read SCB command */
    _get_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Start transmit command */
    scbBuffer[2] = txCmdOffset;  /* CBL offset */
    scbBytes[2] = (scbBytes[2] & 0xF8) | 0x01;  /* CUC=START */

    /* Write SCB command */
    _put_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Send channel attention */
    outb(ioBase + 6, 1);

    /* Set timeout for transmit (3000 milliseconds) */
    [self setRelativeTimeout:3000];

    /* Mark transmit in progress */
    txInProgress = YES;
}

/*
 * Send packet data
 */
- (unsigned int)sendPacket:(void *)data length:(unsigned int)len
{
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;
    unsigned short tcbBuffer[8];  /* TCB - 16 bytes */
    unsigned char *tcbBytes = (unsigned char *)tcbBuffer;
    unsigned short tbdBuffer[4];  /* TBD - 8 bytes */
    unsigned short *srcPtr;
    unsigned int payloadLen;
    int i;

    /* Wait for SCB to be ready */
    _wait_scb(ioBase, scbOffset, 750000, 0);

    /* Read SCB status */
    _get_scb(scbBuffer, scbOffset, ioBase);

    /* If transmit is in progress, wait for CX/CNA interrupt status */
    if (txInProgress) {
        /* Wait for command complete (bits 5 or 7 in status high byte) */
        if (((scbBytes[1] >> 4) & 0x0A) == 0) {
            do {
                _get_scb_stat(scbBuffer, scbOffset, ioBase);
            } while (((scbBytes[1] >> 4) & 0x0A) == 0);
        }

        /* Acknowledge CX/CNA interrupt */
        scbBytes[2] = (scbBytes[2] & 0x0F) | (scbBytes[1] & 0xA0);
        _put_scb_cmd(scbBuffer, scbOffset, ioBase);
        outb(ioBase + 6, 1);  /* Channel attention */

        _wait_scb(ioBase, scbOffset, 750000, 0);
    }

    /* Build TCB (Transmit Command Block) */
    memset(tcbBuffer, 0, 16);

    /* Clear status bits */
    tcbBytes[0] &= 0xF0;

    /* Set TBD offset (word 3) */
    tcbBuffer[3] = txTbdOffset;

    /* Set command to TRANSMIT (4) with EL and I bits */
    tcbBytes[3] |= 0xA0;  /* EL=1, I=1 */
    tcbBytes[2] = (tcbBytes[2] & 0xF8) | 0x04;  /* CMD=TRANSMIT */

    /* Copy Ethernet header to TCB (bytes 8-21 contain dest+src+type) */
    tcbBuffer[4] = *((unsigned short *)data + 0);  /* Dest bytes 0-1 */
    tcbBuffer[5] = *((unsigned short *)data + 1);  /* Dest bytes 2-3 */
    tcbBuffer[6] = *((unsigned short *)data + 2);  /* Dest bytes 4-5 */
    tcbBuffer[7] = *((unsigned short *)data + 6);  /* Type field */

    /* Write TCB to adapter */
    _put_tcb(tcbBuffer, txCmdOffset, ioBase);

    /* Copy payload data to transmit buffer */
    payloadLen = len - 14;  /* Subtract Ethernet header */
    srcPtr = (unsigned short *)((char *)data + 14);

    /* Set write address to transmit buffer */
    inb(ioBase + 0x0F);
    outb(ioBase + 2, txBufferOffset);

    /* Write data in 16-bit words */
    for (i = 0; i < (payloadLen >> 1); i++) {
        outw(ioBase, srcPtr[i]);
    }

    /* Write odd byte if present */
    if (payloadLen & 1) {
        outb(ioBase, ((unsigned char *)srcPtr)[payloadLen - 1]);
    }

    /* Ensure minimum packet size (64 bytes = 14 header + 46 data minimum) */
    if (payloadLen < 0x40) {
        payloadLen = 0x40;
    }

    /* Build TBD (Transmit Buffer Descriptor) */
    tbdBuffer[0] = 0;
    tbdBuffer[0] = (tbdBuffer[0] & 0xC000) | (payloadLen & 0x3FFF) | 0x8000;  /* EOF bit */
    tbdBuffer[1] = 0xFFFF;  /* Next TBD (none) */
    tbdBuffer[2] = txBufferOffset;  /* Buffer address */

    /* Write TBD count field */
    _put_tbd_count(tbdBuffer, txTbdOffset, ioBase);

    /* Start transmit command */
    scbBuffer[2] = txCmdOffset;  /* CBL offset */
    scbBytes[2] = (scbBytes[2] & 0xF8) | 0x01;  /* CUC=START */

    _put_scb_cmd(scbBuffer, scbOffset, ioBase);
    outb(ioBase + 6, 1);  /* Channel attention */

    /* Mark transmit in progress */
    txInProgress = YES;

    /* If not in interrupt mode, wait for completion */
    if (!txInProgress) {
        /* Wait for command complete */
        if (((scbBytes[1] >> 4) & 0x0A) == 0) {
            do {
                _get_scb_stat(scbBuffer, scbOffset, ioBase);
            } while (((scbBytes[1] >> 4) & 0x0A) == 0);
        }

        /* Acknowledge interrupt */
        scbBytes[2] = (scbBytes[2] & 0x0F) | (scbBytes[1] & 0xA0);
        _put_scb_cmd(scbBuffer, scbOffset, ioBase);
        outb(ioBase + 6, 1);

        _wait_scb(ioBase, scbOffset, 750000, 0);
    }

    return len;
}

/*
 * Receive a packet
 */
- (unsigned int)receivePacket:(void *)data length:(unsigned int)maxlen timeout:(unsigned int)timeout
{
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;
    unsigned short rfdBuffer[32];
    unsigned char *rfdBytes = (unsigned char *)rfdBuffer;
    unsigned short rbdBuffer[6];
    unsigned char *rbdBytes = (unsigned char *)rbdBuffer;
    unsigned short currentRFD, savedRFD;
    unsigned short currentRBD, nextRBD;
    unsigned short rbdCount;
    unsigned int totalBytes;
    unsigned int frameLength;
    BOOL frameValid;
    BOOL frameOK;
    int timeoutUS;
    unsigned short *destPtr;
    int i;

    /* Convert timeout from milliseconds to microseconds */
    timeoutUS = timeout * 1000;

    /* Wait for SCB to be ready */
    _wait_scb(ioBase, scbOffset, 750000, 0);

    /* Get initial SCB and RFD status */
    _get_scb(scbBuffer, scbOffset, ioBase);
    _get_rfd(rfdBuffer, rxHeadOffset, ioBase);

    /* Poll for frame received */
    while (1) {
        /* Check if RU is ready (bit 6 of status high byte) and frame complete (bit 7 of RFD status) */
        if (((scbBytes[1] >> 4) & 0x04) != 0 && (rfdBytes[3] & 0x80) != 0) {
            /* Frame received - process it */
            savedRFD = rxHeadOffset;
            rxHeadOffset = rfdBuffer[2];  /* Update head to next RFD */
            rfdBuffer[2] = 0xFFFF;        /* Mark as end of list */

            /* Read RFD header (frame status and data) */
            _get_rfd_hdr(rfdBuffer, savedRFD, ioBase);

            /* Get RBD offset and check frame OK bit */
            currentRBD = rfdBuffer[11];  /* RBD offset at word 11 */
            frameOK = (rfdBytes[3] & 0x20) != 0;  /* OK bit */

            if (currentRBD != 0xFFFF && frameOK) {
                frameValid = YES;

                /* Copy Ethernet header from RFD (14 bytes at offset +8) */
                *((unsigned int *)data + 0) = rfdBuffer[4 + 0];  /* Dest addr bytes 0-1 */
                *((unsigned int *)data + 1) = rfdBuffer[4 + 2];  /* Dest addr bytes 2-3 */
                *((unsigned int *)data + 2) = rfdBuffer[4 + 4];  /* Dest addr bytes 4-5, src 0-1 */
                *((unsigned short *)data + 6) = rfdBuffer[4 + 6]; /* Type field */

                totalBytes = 14;  /* Ethernet header copied */
                frameLength = rfdBuffer[11];  /* Frame length from RFD */

                /* Walk RBD chain to copy packet data */
                while (1) {
                    _get_rbd(rbdBuffer, currentRBD, ioBase);

                    /* Check if count field is valid (bit 14 set) */
                    if ((rbdBuffer[0] & 0x4000) != 0) {
                        rbdCount = rbdBuffer[0] & 0x3FFF;  /* Extract byte count */

                        /* Check if data fits in buffer (1515 bytes max) */
                        if (frameValid && (totalBytes + rbdCount < 0x5EB)) {
                            /* Copy data from adapter memory */
                            destPtr = (unsigned short *)((char *)data + totalBytes);

                            /* Set read address */
                            inb(ioBase + 0x0F);
                            outb(ioBase + 4, rbdBuffer[2]);  /* Buffer address */

                            /* Read data in 16-bit words */
                            for (i = 0; i < (rbdCount >> 1); i++) {
                                destPtr[i] = inw(ioBase);
                            }

                            /* Read odd byte if present */
                            if (rbdCount & 1) {
                                ((unsigned char *)destPtr)[rbdCount - 1] = inb(ioBase);
                            }

                            totalBytes += rbdCount;
                        } else {
                            frameValid = NO;  /* Buffer overflow */
                        }
                    }

                    /* Clear count valid bit */
                    rbdBuffer[0] &= 0xBFFF;

                    /* Check EOF bit (bit 15) */
                    if ((short)rbdBuffer[0] < 0) {
                        break;  /* Last RBD in chain */
                    }

                    /* Write back RBD */
                    _put_rbd(rbdBuffer, currentRBD, ioBase);

                    /* Move to next RBD */
                    currentRBD = rbdBuffer[1];
                }

                /* Update RBD chain */
                rbdBuffer[0] &= 0x3FFF;  /* Clear all flags */
                nextRBD = rbdBuffer[1];

                if (nextRBD == 0xFFFF) {
                    /* End of RBD chain */
                    _put_rbd(rbdBuffer, currentRBD, ioBase);
                } else {
                    /* Link RBDs */
                    rbdHeadOffset = nextRBD;
                    rbdBuffer[1] = 0xFFFF;
                    rbdBytes[5] |= 0x80;  /* Set EL bit */
                    _put_rbd(rbdBuffer, currentRBD, ioBase);
                    rbdBytes[5] &= 0x7F;  /* Clear EL bit */
                    rbdBuffer[1] = rfdBuffer[11];  /* Restore link */
                    _put_rbd_nxt(rbdBuffer, rbdTailOffset, ioBase);
                    rbdTailOffset = currentRBD;
                }

                /* Return packet length if valid and minimum size met */
                if (frameValid && totalBytes > 60) {
                    /* Clear RFD status and update chain */
                    rfdBytes[3] &= 0x5F;  /* Clear C and OK bits */
                    rfdBuffer[11] = 0xFFFF;  /* Clear RBD offset */
                    rfdBytes[5] |= 0x80;  /* Set EL bit */
                    _put_rfd(rfdBuffer, savedRFD, ioBase);
                    rfdBytes[5] &= 0x7F;  /* Clear EL bit */
                    rfdBuffer[2] = savedRFD;  /* Link to self */
                    _put_rfd_lnk(rfdBuffer, rxTailOffset, ioBase);
                    rxTailOffset = savedRFD;

                    return totalBytes;
                }
            }

            /* Frame received but not valid - update RFD chain anyway */
            rfdBytes[3] &= 0x5F;
            rfdBuffer[11] = 0xFFFF;
            rfdBytes[5] |= 0x80;
            _put_rfd(rfdBuffer, savedRFD, ioBase);
            rfdBytes[5] &= 0x7F;
            rfdBuffer[2] = savedRFD;
            _put_rfd_lnk(rfdBuffer, rxTailOffset, ioBase);
            rxTailOffset = savedRFD;

            return 0;
        }

        /* Check timeout */
        if (timeoutUS < 1) {
            break;
        }

        /* Delay 50 microseconds */
        IODelay(50);
        timeoutUS -= 50;

        /* Re-read status */
        _get_scb_stat(scbBuffer, scbOffset, ioBase);
        _get_rfd(rfdBuffer, rxHeadOffset, ioBase);
    }

    /* Timeout expired - check if receiver needs restart */
    if ((scbBytes[0] & 0x70) != 0x40) {
        /* RU not ready - restart receiver */
        rfdBuffer[11] = rbdHeadOffset;
        _put_rfd(rfdBuffer, rxHeadOffset, ioBase);

        _wait_scb(ioBase, scbOffset, 750000, 0);
        _get_scb_cmd(scbBuffer, scbOffset, ioBase);

        /* Set RU command to START and preserve status bits */
        scbBytes[2] = (scbBytes[2] & 0x0F) | (scbBytes[1] & 0x50);
        scbBuffer[1] = rxHeadOffset;  /* RFA pointer */
        scbBytes[2] = (scbBytes[2] & 0x8F) | 0x10;  /* RUC = START */

        _put_scb_cmd(scbBuffer, scbOffset, ioBase);
        outb(ioBase + 6, 1);  /* Channel attention */

        _wait_scb(ioBase, scbOffset, 750000, 0);
    }

    IOLog("EtherExpress16: receivePacket failure (scb timeout)\n");
    return 0;
}

/*
 * Allocate memory on adapter
 */
- (unsigned short)memAlloc:(unsigned short)size
{
    mem_region_t region;

    /* Get memory region for requested size */
    region = [self memRegion:size];

    /* Update free memory pointer */
    memFree = memFree + size;

    return region.start;
}

/*
 * Get available memory
 */
- (unsigned short)memAvail
{
    unsigned int available;

    /* Calculate available memory: (total - used) - base offset
     * Total memory is always 0x10000 (64K)
     * memFree tracks how much has been allocated
     * memBase is the starting offset (0 for 64K, 0x8000 for 32K)
     */
    available = (0x10000 - memFree) - memBase;

    /* Return 0 if result is negative (no memory available) */
    if ((int)available < 0) {
        return 0;
    }

    return (unsigned short)available;
}

/*
 * Get memory region information
 */
- (mem_region_t)memRegion:(unsigned short)size
{
    mem_region_t region;
    unsigned int available;

    /* Check if enough memory is available */
    available = [self memAvail];
    if (available < size) {
        IOPanic("EtherExpress16: onboard memory exhausted");
    }

    /* Allocate from top of memory downward
     * Formula: -(size) - memFree
     * This effectively allocates from high addresses down
     */
    region.start = (unsigned short)(-(short)size - memFree);
    region.size = size;

    return region;
}

/*
 * Perform Command Block List operation
 */
- (BOOL)performCBL:(unsigned short)cmdOffset
{
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;
    int timeout;
    int retries;

    /* Timeout in 100us units (5000 * 100us = 500ms) */
    timeout = 5000;

    /* Read System Control Block */
    _get_scb(scbBuffer, scbOffset, ioBase);

    /* Set command block pointer (CBL offset) at word 2 */
    scbBuffer[2] = cmdOffset;

    /* Set CUC (Command Unit Command) to START (1) in command low byte
     * Command word is at bytes 2-3, low byte at index 2
     * CUC is in bits 0-2
     */
    scbBytes[2] = (scbBytes[2] & 0xF8) | 0x01;

    /* Write SCB command */
    _put_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Send channel attention to start command execution */
    outb(ioBase + 6, 1);

    /* Wait for CUC bits to clear (command accepted) */
    if ((scbBytes[2] & 0x07) != 0) {
        do {
            _get_scb_cmd(scbBuffer, scbOffset, ioBase);
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
            return NO;
        }

        /* Delay 100 microseconds */
        IODelay(100);

        /* Read SCB status */
        _get_scb_stat(scbBuffer, scbOffset, ioBase);
    }

    /* Acknowledge the CNA interrupt
     * Write status high nibble back to command high byte to acknowledge
     * Preserve lower nibble of command byte
     */
    scbBytes[2] = (scbBytes[2] & 0x0F) | (scbBytes[1] & 0xF0);

    /* Write acknowledgment */
    _put_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Send channel attention */
    outb(ioBase + 6, 1);

    /* Wait for SCB to be ready */
    _wait_scb(ioBase, scbOffset, 750000, __LINE__);

    return YES;
}

/*
 * Abort Command Block List
 */
- (void)abortCBL
{
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;

    /* Read current SCB */
    _get_scb(scbBuffer, scbOffset, ioBase);

    /* Set CUC (Command Unit Command) to ABORT (4) in command word */
    /* Command word low byte bits 0-2 */
    scbBytes[2] = (scbBytes[2] & 0xF8) | 0x04;

    /* Write SCB command back */
    _put_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Send Channel Attention signal */
    outb(ioBase + 6, 1);

    /* Wait for SCB to be ready (with timeout) */
    _wait_scb(ioBase, scbOffset, 750000, __LINE__);
}

/*
 * Initialize receive structures
 */
- (BOOL)recvInit
{
    unsigned short rfdBuffer[12];
    unsigned char *rfdBytes = (unsigned char *)rfdBuffer;
    unsigned short rbdBuffer[6];
    unsigned char *rbdBytes = (unsigned char *)rbdBuffer;
    unsigned short currentRFD, nextRFD;
    unsigned short currentRBD, nextRBD;
    unsigned short bufferAddr;
    int i;

    /* Initialize RFD buffer template */
    memset(rfdBuffer, 0, 24);
    rfdBuffer[0] = 0;  /* Status/command */
    rfdBuffer[11] = RFD_MAGIC;  /* Magic value at offset 0x16 */

    /* Initialize RBD buffer template */
    memset(rbdBuffer, 0, 12);
    rbdBuffer[0] = 0;  /* Count word */
    rbdBuffer[5] = RBD_MAGIC;  /* Magic value at offset 10 */

    /* Allocate first RFD (24 bytes) */
    currentRFD = [self memAlloc:0x18];
    rxHeadOffset = currentRFD;

    /* Allocate first RBD (12 bytes) */
    currentRBD = [self memAlloc:0x0C];
    rbdHeadOffset = currentRBD;

    /* Allocate first buffer (768 bytes) */
    bufferAddr = [self memAlloc:0x300];

    /* Clear EL bit in RFD byte 7 */
    rfdBytes[7] &= 0x7F;

    /* Setup first RBD */
    rbdBuffer[0] &= 0xC000;  /* Clear count */
    rbdBuffer[0] |= 0x300;   /* Set size to 768 bytes */
    rbdBuffer[2] = bufferAddr;  /* Buffer address */

    /* Create RFD and RBD chains (32 entries) */
    for (i = 1; i < 0x20; i++) {
        /* Allocate next RFD, RBD, and buffer */
        nextRFD = [self memAlloc:0x18];
        nextRBD = [self memAlloc:0x0C];
        bufferAddr = [self memAlloc:0x300];

        /* Link current RFD to next */
        rfdBuffer[2] = nextRFD;  /* Link field */
        rfdBuffer[11] = currentRBD;  /* RBD offset */

        /* Write current RFD */
        _put_rfd(rfdBuffer, currentRFD, ioBase);
        _put_rfd_magic(rfdBuffer, currentRFD, ioBase);

        /* Link current RBD to next */
        rbdBuffer[1] = nextRBD;  /* Next RBD */
        rbdBuffer[2] = bufferAddr;  /* Buffer address */

        /* Write current RBD */
        _put_rbd(rbdBuffer, currentRBD, ioBase);
        _put_rbd_magic(rbdBuffer, currentRBD, ioBase);

        /* Move to next descriptors */
        currentRFD = nextRFD;
        currentRBD = nextRBD;

        /* Clear EL bit for next RFD */
        rfdBytes[7] &= 0x7F;

        /* Setup next RBD */
        rfdBuffer[11] = 0xFFFF;  /* Clear RBD offset */
        rbdBuffer[0] = ((rbdBytes[3] & 0x7F) & 0xC0) << 8;
        rbdBuffer[0] |= 0x300;  /* Size */
    }

    /* Setup last RFD */
    rfdBuffer[2] = 0xFFFF;  /* End of list */
    rfdBytes[7] |= 0x80;    /* Set EL bit */

    /* Write last RFD */
    _put_rfd(rfdBuffer, currentRFD, ioBase);
    _put_rfd_magic(rfdBuffer, currentRFD, ioBase);

    /* Setup last RBD */
    rbdBuffer[1] = 0xFFFF;  /* End of list */
    rbdBuffer[0] = ((rbdBytes[3] & 0x7F) & 0xC0) << 8;
    rbdBuffer[0] |= 0x8300;  /* Size + EL bit */

    /* Write last RBD */
    _put_rbd(rbdBuffer, currentRBD, ioBase);
    _put_rbd_magic(rbdBuffer, currentRBD, ioBase);

    /* Save tail pointers */
    rxTailOffset = currentRFD;
    rbdTailOffset = currentRBD;

    return YES;
}

/*
 * Start receiver
 */
- (BOOL)recvStart
{
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;

    /* Wait for SCB to be ready */
    _wait_scb(ioBase, scbOffset, 750000, __LINE__);

    /* Read SCB command */
    _get_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Set RFA (Receive Frame Area) pointer to head of RFD list */
    scbBuffer[1] = rxHeadOffset;

    /* Set RUC (Receive Unit Command) to START (0x10 in bits 4-6) */
    scbBytes[2] = (scbBytes[2] & 0x8F) | 0x10;

    /* Write SCB command */
    _put_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Send channel attention */
    outb(ioBase + 6, 1);

    /* Wait for command to complete */
    _wait_scb(ioBase, scbOffset, 750000, __LINE__);

    return YES;
}

/*
 * Restart receiver
 */
- (BOOL)recvRestart
{
    unsigned short rfdBuffer[32];
    unsigned short scbBuffer[8];
    unsigned char *scbBytes = (unsigned char *)scbBuffer;

    /* Read current RFD at head */
    _get_rfd(rfdBuffer, rxHeadOffset, ioBase);

    /* Validate RFD magic */
    _check_rfd(rfdBuffer, __LINE__);

    /* Restore RBD pointer to RFD (word offset 11) */
    rfdBuffer[11] = rbdHeadOffset;

    /* Write RFD back */
    _put_rfd(rfdBuffer, rxHeadOffset, ioBase);

    /* Wait for SCB to be ready */
    _wait_scb(ioBase, scbOffset, 750000, __LINE__);

    /* Read SCB command */
    _get_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Set RFA pointer to head of RFD list */
    scbBuffer[1] = rxHeadOffset;

    /* Set RUC to START (0x10 in bits 4-6) */
    scbBytes[2] = (scbBytes[2] & 0x8F) | 0x10;

    /* Write SCB command */
    _put_scb_cmd(scbBuffer, scbOffset, ioBase);

    /* Send channel attention */
    outb(ioBase + 6, 1);

    /* Wait for command to complete */
    _wait_scb(ioBase, scbOffset, 750000, __LINE__);

    return YES;
}

/*
 * Process received frame
 */
- (void)recvFrame:(void *)frameData hdr:(recv_hdr_t *)hdr ok:(BOOL)frameOK
{
    netbuf_t packet = NULL;
    void *packetData;
    unsigned short rbdBuffer[6];
    unsigned char *rbdBytes = (unsigned char *)rbdBuffer;
    unsigned short currentRBD, nextRBD;
    unsigned short rbdCount;
    unsigned int totalBytes;
    BOOL validFrame;
    unsigned short *destPtr;
    int i;

    /* Release debugger lock while processing */
    [self releaseDebuggerLock];

    if (!frameOK) {
        /* Frame had errors - just increment error count */
        [networkInterface incrementInputErrors];
        packet = NULL;
        packetData = NULL;
        totalBytes = 0;
        goto update_rbd_chain;
    }

    /* Allocate netbuf for packet (1514 bytes max) */
    packet = nb_alloc(0x5EA);
    if (packet == NULL) {
        /* Allocation failed - treat as error */
        [networkInterface incrementInputErrors];
        frameOK = NO;
        packetData = NULL;
        totalBytes = 0;
        goto update_rbd_chain;
    }

    /* Map netbuf to get data pointer */
    packetData = nb_map(packet);

    /* Copy Ethernet header from hdr structure (14 bytes) */
    *((unsigned int *)packetData + 0) = *((unsigned int *)hdr + 0);
    *((unsigned int *)packetData + 1) = *((unsigned int *)hdr + 1);
    *((unsigned int *)packetData + 2) = *((unsigned int *)((char *)hdr + 6) + 0);
    *((unsigned short *)packetData + 6) = hdr->length;  /* Actually the type field */

    totalBytes = 14;  /* Header copied */
    validFrame = YES;

update_rbd_chain:
    /* Reserve debugger lock for hardware access */
    [self reserveDebuggerLock];

    /* Walk RBD chain to copy packet data */
    currentRBD = (unsigned short)frameData;  /* RBD offset passed in frameData */

    while (1) {
        /* Read RBD */
        _get_rbd(rbdBuffer, currentRBD, ioBase);

        /* Validate RBD magic */
        _check_rbd(rbdBuffer, __LINE__);

        /* Check if we should copy data */
        if (frameOK && (rbdBuffer[0] & 0x4000) != 0) {
            rbdCount = rbdBuffer[0] & 0x3FFF;

            /* Check buffer space (1514 bytes max) */
            if (totalBytes + rbdCount < 0x5EB) {
                /* Copy data from adapter memory */
                destPtr = (unsigned short *)((char *)packetData + totalBytes);

                /* Set read address */
                inb(ioBase + 0x0F);
                outb(ioBase + 4, rbdBuffer[2]);  /* Buffer address */

                /* Read data in 16-bit words */
                for (i = 0; i < (rbdCount >> 1); i++) {
                    destPtr[i] = inw(ioBase);
                }

                /* Read odd byte if present */
                if (rbdCount & 1) {
                    ((unsigned char *)destPtr)[rbdCount - 1] = inb(ioBase);
                }

                totalBytes += rbdCount;
            } else {
                /* Buffer overflow */
                frameOK = NO;
            }
        }

        /* Clear count valid bit */
        rbdBuffer[0] &= 0xBFFF;

        /* Check EOF bit (bit 15) */
        if ((short)rbdBuffer[0] < 0) {
            break;  /* Last RBD in chain */
        }

        /* Write back RBD */
        _put_rbd(rbdBuffer, currentRBD, ioBase);

        /* Move to next RBD */
        currentRBD = rbdBuffer[1];
    }

    /* Update RBD chain */
    rbdBuffer[0] &= 0x3FFF;  /* Clear all flags */
    nextRBD = rbdBuffer[1];

    if (nextRBD == 0xFFFF) {
        /* End of RBD chain */
        _put_rbd(rbdBuffer, currentRBD, ioBase);
    } else {
        /* Link RBDs back into free list */
        rbdHeadOffset = nextRBD;
        rbdBuffer[1] = 0xFFFF;
        rbdBytes[5] |= 0x80;  /* Set EL bit */
        _put_rbd(rbdBuffer, currentRBD, ioBase);
        rbdBytes[5] &= 0x7F;  /* Clear EL bit */
        rbdBuffer[1] = (unsigned short)frameData;  /* Original RBD offset */
        _put_rbd_nxt(rbdBuffer, rbdTailOffset, ioBase);
        rbdTailOffset = currentRBD;
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];

    /* Process packet if valid */
    if (packet == NULL) {
        /* No packet allocated - done */
        goto done;
    }

    if (!frameOK || totalBytes < 60) {
        /* Frame invalid or too short - free packet */
        nb_free(packet);
        goto done;
    }

    /* Check multicast filtering if not in promiscuous mode */
    if (!isPromiscuous) {
        void *mappedData = nb_map(packet);
        if ([super isUnwantedMulticastPacket:mappedData]) {
            /* Unwanted multicast - discard */
            nb_free(packet);
            goto done;
        }
    }

    /* Shrink packet to actual size */
    nb_shrink_bot(packet, 0x5EA - totalBytes);

    /* Pass packet to network stack */
    [networkInterface handleInputPacket:packet extra:0];

done:
    /* Reserve debugger lock before returning */
    [self reserveDebuggerLock];
}

/*
 * Handle command complete interrupt (transmit complete)
 */
- (void)cxIntr
{
    unsigned short tcbStatus[2];  /* Read TCB status */
    unsigned char *statusBytes = (unsigned char *)tcbStatus;
    unsigned char statusLow, statusHigh;
    int collisions;
    netbuf_t nextPacket;

    /* Only process if transmit is in progress */
    if (!txInProgress) {
        return;
    }

    /* Read transmit command block status */
    _get_tcb_stat(tcbStatus, txCmdOffset, ioBase);

    statusLow = statusBytes[0];
    statusHigh = statusBytes[1];

    /* Check if transmit OK (bit 5 of high byte) */
    if (statusHigh & 0x20) {
        /* Success - increment output packets */
        [networkInterface incrementOutputPackets];
    } else {
        /* Error - increment output errors */
        [networkInterface incrementOutputErrors];
    }

    /* Count collisions (bits 0-3 of low byte) */
    collisions = statusLow & 0x0F;
    while (collisions > 0) {
        [networkInterface incrementCollisions];
        collisions--;
    }

    /* Check for excessive collisions (bit 5 of low byte) */
    if (statusLow & 0x20) {
        /* 16 collisions */
        for (collisions = 0; collisions < 16; collisions++) {
            [networkInterface incrementCollisions];
        }
    }

    /* Clear transmit timeout */
    [self clearTimeout];

    /* Mark transmit as complete */
    txInProgress = NO;

    /* Check if more packets waiting in queue */
    nextPacket = [txQueue dequeue];
    if (nextPacket != NULL) {
        [self transmit:nextPacket];
    }
}

/*
 * Handle frame received interrupt
 */
- (void)frIntr
{
    unsigned short rfdBuffer[32];  /* RFD buffer (large enough for descriptor + header) */
    unsigned short *rfdStatus;
    unsigned char *statusBytes;
    recv_hdr_t frameHdr;
    unsigned short currentOffset;
    unsigned short nextOffset;
    BOOL frameOK;
    int processedCount = 0;
    int maxFrames = 64;  /* Limit processing to prevent infinite loop */

    /* Process all received frames in the RFD linked list */
    currentOffset = rxHeadOffset;

    while (processedCount < maxFrames) {
        /* Read RFD status and header */
        _get_rfd(rfdBuffer, currentOffset, ioBase);

        /* Check magic value */
        _check_rfd(rfdBuffer, __LINE__);

        rfdStatus = &rfdBuffer[0];
        statusBytes = (unsigned char *)rfdStatus;

        /* Check if frame is complete (C bit - bit 15 of status word) */
        if ((statusBytes[1] & 0x80) == 0) {
            /* Frame not complete - done processing */
            break;
        }

        /* Read frame header (status and length) */
        _get_rfd_hdr(rfdBuffer, currentOffset, ioBase);

        /* Extract frame status and length from RFD header */
        frameHdr.status = rfdBuffer[4];   /* RFD offset +8 */
        frameHdr.length = rfdBuffer[10];  /* RFD offset +20 */

        /* Check if frame received OK (bit 13 of RFD status) */
        frameOK = (statusBytes[1] & 0x20) ? YES : NO;

        /* Get next RFD offset from link field (word offset 2) */
        nextOffset = rfdBuffer[2];

        /* Process the frame */
        if (frameOK) {
            /* Frame received successfully - pass RBD offset as frameData */
            [self recvFrame:(void *)(unsigned int)currentRBD hdr:&frameHdr ok:YES];
        } else {
            /* Frame had errors */
            [networkInterface incrementInputErrors];
            [self recvFrame:NULL hdr:&frameHdr ok:NO];
        }

        /* Clear the RFD status (mark as processed) */
        rfdBuffer[0] = 0;
        inb(ioBase + 0x0F);
        outb(ioBase + 2, currentOffset);
        outw(ioBase, rfdBuffer[0]);

        /* Move to next RFD */
        rxHeadOffset = nextOffset;
        currentOffset = nextOffset;

        processedCount++;

        /* Check if we wrapped around to the tail (end of list) */
        if (currentOffset == rxTailOffset) {
            break;
        }
    }
}

@end

/* Private Category Implementation */
@implementation EtherExpress16(EtherExpress16Private)

/*
 * Configure EtherExpress 16 hardware for bus width and connector
 */
- (id)__configEE16:(BOOL)doConfig
{
    unsigned char ctrlReg;
    unsigned short ctrlPort;
    int retries;

    if (doConfig) {
        /* Read control register at port+0x0D */
        ctrlReg = inb(ioBase + 0x0D);

        /* Check if 16-bit slot (bit 2 set) */
        if ((ctrlReg & 0x04) == 0) {
            IOLog("EtherExpress16: 8-bit slot detected\n");
        } else {
            /* Try to configure 16-bit mode */
            ctrlReg |= 0x18;  /* Set bits 3 and 4 */
            ctrlPort = ioBase + 0x0D;

            /* First attempt: try up to 1000 times */
            for (retries = 0; retries < 1000; retries++) {
                /* Write with bit 5 set */
                outb(ctrlPort, ctrlReg | 0x20);
                inb(ctrlPort);

                /* Read back and clear bit 5 */
                ctrlReg = inb(ctrlPort);
                outb(ctrlPort, ctrlReg & 0xDF);

                /* Check if bit 6 is clear (success) */
                if ((ctrlReg & 0x40) == 0) {
                    goto config_connector;
                }

                IODelay(50);
            }

            /* Second attempt: clear bits 4-5, try up to 10 times */
            ctrlReg &= 0xCF;
            for (retries = 0; retries < 10; retries++) {
                outb(ctrlPort, ctrlReg | 0x20);
                inb(ctrlPort);

                ctrlReg = inb(ctrlPort);
                outb(ctrlPort, ctrlReg & 0xDF);

                if ((ctrlReg & 0x40) == 0) {
                    goto config_connector;
                }

                IODelay(50);
            }

            /* Failed to configure 16-bit mode */
            outb(ioBase + 0x0D, ctrlReg & 0xD7);
            IOLog("EtherExpress16: Unable to perform 16-bit transfers\n");
            IOLog("EtherExpress16: Defaulting to 8-bit mode\n");
        }
    }

config_connector:
    /* Configure connector type if configured */
    if (configFlag == 0xBABB) {
        unsigned char connReg;
        unsigned short connPort = ioBase + 0x300E;

        connReg = inb(connPort);

        /* Clear bits 1 and 7, then set based on connector type */
        connReg &= 0x7D;

        /* Set bit 7 if not AUI (type != 0) */
        if (connectorType != CONNECTOR_AUI) {
            connReg |= 0x80;
        }

        /* Set bit 1 if not BNC (type != 1) */
        if (connectorType != CONNECTOR_BNC) {
            connReg |= 0x02;
        }

        outb(connPort, connReg);
    }

    return self;
}

/*
 * Reset EtherExpress 16 hardware
 */
- (id)__resetEE16:(BOOL)enable
{
    unsigned int eepromConfig;
    unsigned int boardTypeValue;

    /* Assert reset (bit 7) */
    outb(ioBase + 0x0E, 0x80);
    IODelay(500);

    if (enable) {
        /* Pulse additional control bits */
        outb(ioBase + 0x0E, 0xC0);
        IODelay(500);

        /* Return to reset state */
        outb(ioBase + 0x0E, 0x80);
        IODelay(500);
    }

    /* Read Ethernet address from EEPROM */
    _get_etherAddress(&stationAddress, ioBase);

    /* Read configuration from EEPROM offset 5 to determine board type */
    eepromConfig = _read_eeprom(5, ioBase);

    /* Determine board type based on EEPROM bits */
    if (eepromConfig & 0x08) {
        /* Bit 3 set - EtherExpress16C */
        boardTypeValue = 4;
    } else if (eepromConfig & 0x01) {
        /* Bit 0 set - EtherExpress16TP */
        boardTypeValue = 1;
        if (configFlag == 0xBABB) {
            /* Second generation TP */
            boardTypeValue = 3;
        }
    } else {
        /* Neither bit set - EtherExpress16 */
        boardTypeValue = 0;
        if (configFlag == 0xBABB) {
            /* Second generation */
            boardTypeValue = 2;
        }
    }

    boardType = boardTypeValue;

    /* Clear reset */
    outb(ioBase + 0x0E, 0);

    return self;
}

/*
 * Configure multicast addresses on adapter
 */
- (void)__configureMulticastAddresses
{
    void *multicastQueue;
    void *entry;
    int count;
    int cmdSize;
    unsigned short cmdOffset;
    unsigned short *cmdBuffer;
    unsigned short *ptr;
    int i;
    mem_region_t region;

    /* Clear multicast configured flag */
    multicastConfigured = NO;

    /* Only configure if multicast mode is enabled */
    if (!isMulticast) {
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
    region = [self memRegion:cmdSize];
    cmdOffset = region.start;

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
    inb(ioBase + 0x0F);
    outb(ioBase + 2, cmdOffset);

    ptr = cmdBuffer;
    for (i = 0; i < (cmdSize >> 1); i++) {
        outw(ioBase, *ptr);
        ptr++;
    }

    /* Execute command */
    [self performCBL:cmdOffset];

    /* Read back command status */
    inb(ioBase + 0x0F);
    outb(ioBase + 4, cmdOffset);

    ptr = cmdBuffer;
    for (i = 0; i < 4; i++) {
        *ptr = inw(ioBase);
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
    mem_region_t region;
    int i;
    BOOL success;

    /* Clear command buffer */
    memset(iaCmd, 0, 14);

    /* Allocate memory region for command */
    region = [self memRegion:14];
    cmdOffset = region.start;

    /* Build IA-SETUP command block (i82586 format) */
    /* Byte 0-1: Command word */
    iaCmd[0] = (iaCmd[0] & 0xF8FF) | CMD_IA_SETUP;

    /* Byte 2-3: Status and flags */
    *((unsigned char *)&iaCmd[1] + 1) |= 0x20;  /* Set bit 5 (EL - end of list) */
    *((unsigned char *)&iaCmd[1] + 1) |= 0x80;  /* Set bit 7 (I - interrupt) */

    /* Bytes 8-13: MAC address */
    iaCmd[4] = *((unsigned short *)&stationAddress.ea_byte[0]);
    iaCmd[5] = *((unsigned short *)&stationAddress.ea_byte[2]);
    iaCmd[6] = *((unsigned short *)&stationAddress.ea_byte[4]);

    /* Write command block to adapter memory */
    inb(ioBase + 0x0F);
    outb(ioBase + 2, cmdOffset);

    for (i = 0; i < 7; i++) {
        outw(ioBase, iaCmd[i]);
    }

    /* Execute command */
    [self performCBL:cmdOffset];

    /* Read back command status */
    inb(ioBase + 0x0F);
    outb(ioBase + 4, cmdOffset);

    for (i = 0; i < 7; i++) {
        iaCmd[i] = inw(ioBase);
    }

    /* Check OK bit (bit 13 of status word) */
    success = (*((unsigned char *)&iaCmd[0] + 1) >> 5) & 1;

    return success;
}

/*
 * Initialize transmit structures
 */
- (BOOL)xmtInit
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
    txCmdOffset = [self memAlloc:0x10];

    /* Allocate transmit buffer descriptor (8 bytes) */
    txTbdOffset = [self memAlloc:0x08];

    /* Allocate transmit buffer (1514 bytes for max Ethernet frame) */
    txBufferOffset = [self memAlloc:0x5EA];

    /* Set TBD offset in TCB */
    tcbBuffer[3] = txTbdOffset;

    /* Write initial TCB to adapter */
    _put_tcb(tcbBuffer, txCmdOffset, ioBase);

    /* Set buffer address in TBD */
    tbdBuffer[2] = txBufferOffset;

    /* Write initial TBD to adapter */
    _put_tbd(tbdBuffer, txTbdOffset, ioBase);

    return YES;
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

/* Helper function for debug/error reporting */
static void _jump_label(unsigned int lineNumber)
{
    IOLog("EtherExpress16: Magic value check failed at line %u\n", lineNumber);
}

/* Check Receive Buffer Descriptor magic value */
static void _check_rbd(unsigned short *rbd, unsigned int lineNumber)
{
    /* Check magic value at offset 10 (word offset 5) */
    if (rbd[5] != RBD_MAGIC) {
        _jump_label(lineNumber);
    }
}

/* Check Receive Frame Descriptor magic value */
static void _check_rfd(unsigned short *rfd, unsigned int lineNumber)
{
    /* Check magic value at offset 0x16 (word offset 11) */
    if (rfd[11] != RFD_MAGIC) {
        _jump_label(lineNumber);
    }
}

/* Read EEPROM word via bit-banging */
static unsigned short _get_eeprom(unsigned short ioBase)
{
    unsigned short result = 0;
    unsigned int mask = 0x8000;
    unsigned short port = ioBase + 0x0E;
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
static void _get_etherAddress(enet_addr_t *addr, unsigned short ioBase)
{
    unsigned short word1, word2, word3;

    /* Read 3 words from EEPROM (locations 2, 3, 4) */
    word1 = _read_eeprom(2, ioBase);
    word2 = _read_eeprom(3, ioBase);
    word3 = _read_eeprom(4, ioBase);

    /* Byte swap and store (Intel byte order to network byte order) */
    addr->ea_byte[0] = (word3 >> 8) & 0xFF;
    addr->ea_byte[1] = word3 & 0xFF;
    addr->ea_byte[2] = (word2 >> 8) & 0xFF;
    addr->ea_byte[3] = word2 & 0xFF;
    addr->ea_byte[4] = (word1 >> 8) & 0xFF;
    addr->ea_byte[5] = word1 & 0xFF;
}

/* Read ISCP busy status and buffer data */
static void _get_iscp_busy(unsigned short *buffer, unsigned short value, unsigned short ioBase)
{
    int count = 0;

    /* Read from port 0x0F to clear status */
    inb(ioBase + 0x0F);

    /* Write value to port 4 */
    outb(ioBase + 4, value);

    /* Read words into buffer */
    do {
        buffer[count] = inw(ioBase);
        count++;
    } while (count != 0);  /* Loop until wrap-around */
}

/* Read Receive Buffer Descriptor from adapter */
static void _get_rbd(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set read address */
    outb(ioBase + 4, offset);

    /* Read 6 words */
    for (count = 5; count >= 0; count--) {
        *buffer = inw(ioBase);
        buffer++;
    }
}

/* Read Receive Frame Descriptor from adapter */
static void _get_rfd(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    unsigned short *ptr;
    int count;

    /* Read first 4 words */
    inb(ioBase + 0x0F);
    outb(ioBase + 4, offset);

    for (count = 3; count >= 0; count--) {
        *buffer = inw(ioBase);
        buffer++;
    }

    /* Move to word offset 11 (skip 11 words from current position) */
    ptr = buffer + 11;

    /* Read remaining data starting at offset+0x16 */
    inb(ioBase + 0x0F);
    outb(ioBase + 4, offset + 0x16);

    /* Read words until counter wraps */
    count = 0;
    do {
        *ptr = inw(ioBase);
        ptr++;
        count--;
    } while (count != 0);
}

/* Read Receive Frame Descriptor header */
static void _get_rfd_hdr(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    unsigned short *ptr;
    int count;

    /* Start at word offset 4 in buffer */
    ptr = buffer + 4;

    /* Clear status and set read address to offset+8 */
    inb(ioBase + 0x0F);
    outb(ioBase + 4, offset + 8);

    /* Read 7 words */
    for (count = 6; count >= 0; count--) {
        *ptr = inw(ioBase);
        ptr++;
    }
}

/* Read System Control Block from adapter */
static void _get_scb(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set read address */
    outb(ioBase + 4, offset);

    /* Read 8 words */
    for (count = 7; count >= 0; count--) {
        *buffer = inw(ioBase);
        buffer++;
    }
}

/* Read System Control Block command words */
static void _get_scb_cmd(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set read address to offset+2 */
    outb(ioBase + 4, offset + 2);

    /* Skip first word, then read 3 words */
    buffer++;
    for (count = 2; count >= 0; count--) {
        buffer++;
        *buffer = inw(ioBase);
    }
}

/* Read System Control Block status */
static void _get_scb_stat(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set read address */
    outb(ioBase + 4, offset);

    /* Read words until counter wraps */
    count = 0;
    do {
        *buffer = inw(ioBase);
        buffer++;
        count--;
    } while (count != 0);
}

/* Read Transmit Command Block status */
static void _get_tcb_stat(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set read address */
    outb(ioBase + 4, offset);

    /* Read words until counter wraps */
    count = 0;
    do {
        *buffer = inw(ioBase);
        buffer++;
        count--;
    } while (count != 0);
}

/* Write value to EEPROM via bit-banging */
static void _put_eeprom(unsigned short value, unsigned char bitCount, unsigned short ioBase)
{
    unsigned char ctrlByte = 0x82;
    unsigned int mask;
    unsigned short port = ioBase + 0x0E;

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
static void _put_iscp(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address */
    outb(ioBase + 2, offset);

    /* Write 3 words */
    for (count = 2; count >= 0; count--) {
        outw(ioBase, *buffer);
        buffer++;
    }
}

/* Write Receive Buffer Descriptor */
static void _put_rbd(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address */
    outb(ioBase + 2, offset);

    /* Write 5 words */
    for (count = 4; count >= 0; count--) {
        outw(ioBase, *buffer);
        buffer++;
    }
}

/* Write RBD magic value at offset+10 */
static void _put_rbd_magic(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    unsigned short *ptr;
    int count;

    /* Start at word offset 5 (byte offset 10) in buffer */
    ptr = buffer + 5;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address to offset+10 */
    outb(ioBase + 2, offset + 10);

    /* Write words until counter wraps */
    count = 0;
    do {
        outw(ioBase, *ptr);
        ptr++;
        count--;
    } while (count != 0);
}

/* Write RBD next pointer fields */
static void _put_rbd_nxt(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    unsigned short *ptr;
    int count;

    /* First write: buffer+1 to offset+2 */
    inb(ioBase + 0x0F);
    outb(ioBase + 2, offset + 2);

    count = 0;
    ptr = buffer;
    do {
        ptr++;
        outw(ioBase, *ptr);
        count--;
    } while (count != 0);

    /* Second write: buffer+4 to offset+8 */
    ptr = buffer + 4;
    inb(ioBase + 0x0F);
    outb(ioBase + 2, offset + 8);

    count = 0;
    do {
        outw(ioBase, *ptr);
        ptr++;
        count--;
    } while (count != 0);
}

/* Write Receive Frame Descriptor */
static void _put_rfd(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address */
    outb(ioBase + 2, offset);

    /* Write 4 words */
    for (count = 3; count >= 0; count--) {
        outw(ioBase, *buffer);
        buffer++;
    }
}

/* Write RFD link fields */
static void _put_rfd_lnk(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    unsigned short *ptr;
    int count;

    /* First write: buffer+2 to offset+4 */
    ptr = buffer + 2;
    inb(ioBase + 0x0F);
    outb(ioBase + 2, offset + 4);

    count = 0;
    do {
        outw(ioBase, *ptr);
        ptr++;
        count--;
    } while (count != 0);

    /* Second write: buffer+1 to offset+2 */
    inb(ioBase + 0x0F);
    outb(ioBase + 2, offset + 2);

    count = 0;
    do {
        buffer++;
        outw(ioBase, *buffer);
        count--;
    } while (count != 0);
}

/* Write RFD magic value at offset+0x16 */
static void _put_rfd_magic(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    unsigned short *ptr;
    int count;

    /* Start at word offset 11 (byte offset 0x16) in buffer */
    ptr = (unsigned short *)((unsigned char *)buffer + 0x16);

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address to offset+0x16 */
    outb(ioBase + 2, offset + 0x16);

    /* Write words until counter wraps */
    count = 0;
    do {
        outw(ioBase, *ptr);
        ptr++;
        count--;
    } while (count != 0);
}

/* Write System Control Block */
static void _put_scb(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address */
    outb(ioBase + 2, offset);

    /* Write 8 words */
    for (count = 7; count >= 0; count--) {
        outw(ioBase, *buffer);
        buffer++;
    }
}

/* Write System Control Block command words */
static void _put_scb_cmd(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address to offset+2 */
    outb(ioBase + 2, offset + 2);

    /* Skip first word, then write 3 words */
    for (count = 2; count >= 0; count--) {
        buffer++;
        outw(ioBase, *buffer);
    }
}

/* Write System Configuration Pointer (SCP) */
static void _put_scp(unsigned short *buffer, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address to fixed location (i82586 requirement) */
    outb(ioBase + 2, SCP_ADDRESS);

    /* Write 5 words */
    for (count = 4; count >= 0; count--) {
        outw(ioBase, *buffer);
        buffer++;
    }
}

/* Write Transmit Buffer Descriptor */
static void _put_tbd(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address */
    outb(ioBase + 2, offset);

    /* Write 4 words */
    for (count = 3; count >= 0; count--) {
        outw(ioBase, *buffer);
        buffer++;
    }
}

/* Write TBD count field */
static void _put_tbd_count(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address */
    outb(ioBase + 2, offset);

    /* Write words until counter wraps */
    count = 0;
    do {
        outw(ioBase, *buffer);
        buffer++;
        count--;
    } while (count != 0);
}

/* Write Transmit Command Block */
static void _put_tcb(unsigned short *buffer, unsigned short offset, unsigned short ioBase)
{
    int count;

    /* Clear status */
    inb(ioBase + 0x0F);

    /* Set write address */
    outb(ioBase + 2, offset);

    /* Write 8 words */
    for (count = 7; count >= 0; count--) {
        outw(ioBase, *buffer);
        buffer++;
    }
}

/* Read EEPROM word at given offset with proper command sequence */
static unsigned short _read_eeprom(unsigned short offset, unsigned short ioBase)
{
    unsigned short value;

    /* Send READ command (opcode 6, 3 bits) */
    _put_eeprom(6, 3, ioBase);

    /* Send address (offset, 6 bits) */
    _put_eeprom(offset, 6, ioBase);

    /* Read the data word */
    value = _get_eeprom(ioBase);

    /* Deselect EEPROM */
    outb(ioBase + 0x0E, 0);

    return value;
}

/* Setup and detect adapter memory configuration */
static unsigned short _setup_mem(unsigned short ioBase)
{
    int i;
    unsigned char readback;

    /* Clear/initialize memory - read 16 words from address 0 */
    for (i = 0; i < 0x10; i++) {
        inb(ioBase + 0x0F);
        outb(ioBase + 4, 0);
        inw(ioBase);
    }

    /* Test memory at address 0 */
    inb(ioBase + 0x0F);
    outb(ioBase + 2, 0);
    outw(ioBase, 0);

    /* Test memory at address 0x8000 */
    inb(ioBase + 0x0F);
    outb(ioBase + 2, 0x8000);
    outw(ioBase, 0);

    /* Write test pattern 0xAA to address 0 */
    inb(ioBase + 0x0F);
    outb(ioBase + 2, 0);
    outw(ioBase, 0xAA);

    /* Read back from address 0x8000 to test memory size */
    inb(ioBase + 0x0F);
    outb(ioBase + 4, 0x8000);
    readback = inb(ioBase);

    /* If readback is 0xAA, memory wraps - only 32K */
    /* If readback is NOT 0xAA, full 64K memory present */
    if (readback == 0xAA) {
        return 0x8000;  /* 32K memory */
    } else {
        return 0;       /* 64K memory (base 0) */
    }
}

/* Wait for System Control Block to become ready */
static void _wait_scb(unsigned short ioBase, unsigned short offset, int retries, unsigned int lineNumber)
{
    unsigned short scbCmd;
    int count;

    /* Retry loop */
    retries--;
    while (retries >= 0) {
        /* Read SCB command word at offset+2 */
        inb(ioBase + 0x0F);
        outb(ioBase + 4, offset + 2);

        /* Read words until wrap */
        count = 0;
        do {
            scbCmd = inw(ioBase);
            count--;
        } while (count != 0);

        /* Check if SCB is ready (command word is 0) */
        if (scbCmd == 0) {
            return;
        }

        retries--;
    }

    /* Timeout - report error if line number provided */
    if (lineNumber != 0) {
        _jump_label(lineNumber);
    }
}
