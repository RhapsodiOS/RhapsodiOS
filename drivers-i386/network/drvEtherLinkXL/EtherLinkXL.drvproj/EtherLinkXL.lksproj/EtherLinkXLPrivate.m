/*
 * EtherLinkXLPrivate.m
 * 3Com EtherLink XL Network Driver - Private Internal Methods
 */

#import "EtherLinkXL.h"
#import <driverkit/generalFuncs.h>
#import <kernserv/prototypes.h>

/* External reference to page size */
extern unsigned int page_size;

@implementation EtherLinkXL(EtherLinkXLPrivate)

/*
 * Internal initialization
 */
- (BOOL)__init
{
    vm_task_t task;
    unsigned int physicalAddr;
    unsigned short statusReg;
    int timeout;
    int i;
    unsigned char byte;
    unsigned short word;
    const char *driverName;

    /* Get physical address of RX descriptor ring */
    task = IOVmTaskSelf();
    physicalAddr = IOPhysicalFromVirtual(task, (vm_address_t)rxDescriptors);

    if (physicalAddr == 0) {
        driverName = [[self name] cString];
        IOLog("%s: Virtual to physical mapping error\n", driverName);
        return NO;
    }

    /* Acknowledge all interrupts */
    outw(ioBase + REG_COMMAND, 0x3000);

    /* Wait for command to complete (bit 12 cleared in status register) */
    timeout = 999999;
    while (timeout > 0) {
        statusReg = inw(ioBase + REG_COMMAND);
        if ((statusReg & 0x1000) == 0) {
            break;
        }
        IODelay(1);
        timeout--;
    }

    /* Write RX descriptor base address (port + 0x38) */
    outl(ioBase + 0x38, physicalAddr);

    /* Acknowledge interrupt latch */
    outw(ioBase + REG_COMMAND, 0x3001);

    /* Reset TX status register */
    outw(ioBase + 0x24, 0);

    /* Write to port + 0x2F (value 6) */
    outb(ioBase + 0x2F, 6);

    /* Switch to window 5 and write command 0x8FFC */
    if (currentWindow != 5) {
        outw(ioBase + REG_COMMAND, 0x0805);
        currentWindow = 5;
    }
    outw(ioBase + REG_COMMAND, 0x8FFC);

    /* Set bit 0x20 in register at port + 0x20 */
    word = inl(ioBase + 0x20);
    outl(ioBase + 0x20, word | 0x20);

    /* Switch to window 2 and write station address */
    if (currentWindow != 2) {
        outw(ioBase + REG_COMMAND, 0x0802);
        currentWindow = 2;
    }

    /* Write MAC address to window 2, offsets 0-5 */
    for (i = 0; i < 6; i++) {
        outb(ioBase + i, stationAddress[i]);
    }

    /* Write command with byte from offset 0x18A */
    outw(ioBase + REG_COMMAND, 0x8000 | interruptMask);

    /* Write command 0xB000 */
    outw(ioBase + REG_COMMAND, 0xB000);

    /* Switch to window 6 and read adapter capabilities */
    if (currentWindow != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        currentWindow = 6;
    }

    /* Read 6 bytes of capabilities */
    for (i = 0; i < 6; i++) {
        adapterCapabilities[i] = inb(ioBase + i);
    }

    /* Read and build values from window 6 */
    byte = inb(ioBase + 6);
    rxFreeThresh = byte;

    byte = inb(ioBase + 7);
    txStartThresh = byte;

    byte = inb(ioBase + 9);
    rxFreeThresh |= (byte & 0x30) << 4;
    txStartThresh |= (byte & 0x03) << 8;

    softwareInfo = inb(ioBase + 8);

    /* Read from window 6 offset 10 */
    if (currentWindow != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        currentWindow = 6;
    }
    word = inw(ioBase + 10);
    txAvailable = word;

    /* Read from window 4 offset 0x0D */
    if (currentWindow != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        currentWindow = 4;
    }
    byte = inb(ioBase + 0x0D);
    txAvailable |= (unsigned int)byte << 16;

    /* Read from window 6 offset 0x0C */
    if (currentWindow != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        currentWindow = 6;
    }
    word = inw(ioBase + 0x0C);
    txSpaceThresh = word;

    /* Read from window 4 offset 0x0D again */
    if (currentWindow != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        currentWindow = 4;
    }
    byte = inb(ioBase + 0x0D);
    txSpaceThresh |= (unsigned int)byte << 16;

    /* Read media options from window 4 offset 0x0C */
    if (currentWindow != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        currentWindow = 4;
    }
    mediaOptions = inb(ioBase + 0x0C);

    /* Write 0x40 to window 4 offset 6 */
    if (currentWindow != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        currentWindow = 4;
    }
    outw(ioBase + 6, 0x40);

    /* Write command 0xA800 */
    outw(ioBase + REG_COMMAND, 0xA800);

    return YES;
}

/*
 * Allocate DMA and descriptor memory
 */
- (BOOL)__allocateMemory
{
    const char *driverName;
    int i;
    void *alignedAddr;

    /* Set descriptor memory size: 0x1020 = 4128 bytes
     * RX descriptors: 64 * 32 = 2048 bytes
     * TX descriptors: 32 * 32 * 2 (two queues) = 2048 bytes
     * Plus alignment padding
     */
    descriptorMemSize = 0x1020;

    /* Check if memory fits in one page */
    if (page_size < descriptorMemSize) {
        driverName = [[self name] cString];
        IOLog("%s: 1 page limit exceeded for descriptor memory\n", driverName);
        return NO;
    }

    /* Allocate low memory (DMA-able, < 16MB) for descriptors */
    descriptorMemBase = (void *)IOMallocLow(descriptorMemSize);
    if (descriptorMemBase == NULL) {
        driverName = [[self name] cString];
        IOLog("%s: Can't allocate %d bytes of memory\n", driverName, descriptorMemSize);
        return NO;
    }

    /* Set up RX descriptors (aligned to 16-byte boundary) */
    rxDescriptors = (EtherLinkXLDescriptor *)descriptorMemBase;
    if (((unsigned int)rxDescriptors & 0x0F) != 0) {
        /* Align to next 16-byte boundary */
        rxDescriptors = (EtherLinkXLDescriptor *)(((unsigned int)descriptorMemBase + 0x0F) & 0xFFFFFFF0);
    }

    /* Initialize RX descriptors and netbuf array */
    for (i = 0; i < RX_RING_SIZE; i++) {
        bzero(&rxDescriptors[i], sizeof(EtherLinkXLDescriptor));
        rxNetbufArray[i] = NULL;
    }

    /* Set up TX descriptor base (offset 0x800 = 2048 from RX descriptors) */
    txDescriptorBase = (void *)((unsigned int)rxDescriptors + 0x800);
    if (((unsigned int)txDescriptorBase & 0x0F) != 0) {
        /* Align to next 16-byte boundary */
        txDescriptorBase = (void *)(((unsigned int)rxDescriptors + 0x80F) & 0xFFFFFFF0);
    }

    /* Set up first TX descriptor queue (offset 0x400 = 1024 from TX base) */
    txDescriptors = (EtherLinkXLDescriptor *)((unsigned int)txDescriptorBase + 0x400);

    /* Allocate TX netbuf arrays */
    txNetbufArraySize = 0x80;  /* 128 bytes = 32 * 4 */
    txNetbufArray = (netbuf_t *)IOMalloc(txNetbufArraySize);
    txNetbufArrayAlt = (netbuf_t *)IOMalloc(txNetbufArraySize);

    if (txNetbufArray == NULL || txNetbufArrayAlt == NULL) {
        driverName = [[self name] cString];
        IOLog("%s: Can't allocate memory for netbuf array\n", driverName);
        return NO;
    }

    /* Initialize TX descriptors and netbuf arrays */
    for (i = 0; i < TX_RING_SIZE; i++) {
        /* Zero out both TX descriptor queues */
        bzero((void *)((unsigned int)txDescriptorBase + i * sizeof(EtherLinkXLDescriptor)),
              sizeof(EtherLinkXLDescriptor));
        bzero(&txDescriptors[i], sizeof(EtherLinkXLDescriptor));

        /* Initialize netbuf arrays */
        txNetbufArray[i] = NULL;
        txNetbufArrayAlt[i] = NULL;
    }

    return YES;
}

/*
 * Initialize receive ring
 */
- (BOOL)__initRxRing
{
    vm_task_t task;
    unsigned int physicalAddr;
    int i;
    EtherLinkXLDescriptor *descriptor;
    const char *driverName;

    /* Initialize all RX descriptors */
    for (i = 0; i < RX_RING_SIZE; i++) {
        descriptor = &rxDescriptors[i];

        /* Zero out descriptor */
        bzero(descriptor, sizeof(EtherLinkXLDescriptor));

        /* Get physical address of next descriptor (for linking) */
        if (i < RX_RING_SIZE - 1) {
            task = IOVmTaskSelf();
            physicalAddr = IOPhysicalFromVirtual(task, (vm_address_t)&rxDescriptors[i + 1]);
            if (physicalAddr == 0) {
                return NO;
            }
            /* Store next descriptor physical address */
            descriptor->nextDescriptor = physicalAddr;
        }

        /* Allocate netbuf if not already allocated */
        if (rxNetbufArray[i] == NULL) {
            rxNetbufArray[i] = [self allocateNetbuf];
            if (rxNetbufArray[i] == NULL) {
                driverName = [[self name] cString];
                IOLog("%s: initRxRing: allocateNetbuf returned NULL\n", driverName);
                return NO;
            }
        }

        /* Update descriptor from netbuf */
        if (![self __updateDescriptor:descriptor fromNetBuf:rxNetbufArray[i] receive:YES]) {
            driverName = [[self name] cString];
            IOLog("%s: initRxRing: updateDescriptor failed\n", driverName);
            return NO;
        }
    }

    /* Link last descriptor back to first (create ring) */
    task = IOVmTaskSelf();
    physicalAddr = IOPhysicalFromVirtual(task, (vm_address_t)rxDescriptors);
    if (physicalAddr == 0) {
        return NO;
    }
    rxDescriptors[RX_RING_SIZE - 1].nextDescriptor = physicalAddr;

    /* Initialize RX index */
    rxIndex = 0;

    return YES;
}

/*
 * Initialize transmit queue
 */
- (BOOL)__initTxQueue
{
    vm_task_t task;
    unsigned int physicalAddr;
    unsigned int i;
    EtherLinkXLDescriptor *descriptor1, *descriptor2;
    const char *driverName;

    /* Initialize both TX descriptor queues */
    for (i = 0; i < TX_RING_SIZE; i++) {
        /* First TX queue (at txDescriptorBase) */
        descriptor1 = (EtherLinkXLDescriptor *)((unsigned int)txDescriptorBase + i * sizeof(EtherLinkXLDescriptor));
        bzero(descriptor1, sizeof(EtherLinkXLDescriptor));

        /* Get physical address of next descriptor (if not last) */
        if (i < TX_RING_SIZE - 1) {
            task = IOVmTaskSelf();
            physicalAddr = IOPhysicalFromVirtual(task,
                (vm_address_t)((unsigned int)txDescriptorBase + (i + 1) * sizeof(EtherLinkXLDescriptor)));
            if (physicalAddr == 0) {
                return NO;
            }
            /* Store at offset 0x18 (reserved[2]) */
            descriptor1->reserved[2] = physicalAddr;
        }

        /* Get physical address of current descriptor */
        task = IOVmTaskSelf();
        physicalAddr = IOPhysicalFromVirtual(task, (vm_address_t)descriptor1);
        if (physicalAddr == 0) {
            return NO;
        }
        /* Store at offset 0x1C (reserved[3]) */
        descriptor1->reserved[3] = physicalAddr;

        /* Free any existing netbuf in first queue */
        if (txNetbufArray[i] != NULL) {
            nb_free(txNetbufArray[i]);
            txNetbufArray[i] = NULL;
        }

        /* Second TX queue (at txDescriptors) */
        descriptor2 = &txDescriptors[i];
        bzero(descriptor2, sizeof(EtherLinkXLDescriptor));

        /* Get physical address of next descriptor (if not last) */
        if (i < TX_RING_SIZE - 1) {
            task = IOVmTaskSelf();
            physicalAddr = IOPhysicalFromVirtual(task, (vm_address_t)&txDescriptors[i + 1]);
            if (physicalAddr == 0) {
                return NO;
            }
            /* Store at offset 0x18 (reserved[2]) */
            descriptor2->reserved[2] = physicalAddr;
        }

        /* Get physical address of current descriptor */
        task = IOVmTaskSelf();
        physicalAddr = IOPhysicalFromVirtual(task, (vm_address_t)descriptor2);
        if (physicalAddr == 0) {
            return NO;
        }
        /* Store at offset 0x1C (reserved[3]) */
        descriptor2->reserved[3] = physicalAddr;

        /* Free any existing netbuf in second queue */
        if (txNetbufArrayAlt[i] != NULL) {
            nb_free(txNetbufArrayAlt[i]);
            txNetbufArrayAlt[i] = NULL;
        }
    }

    /* Initialize TX management variables */
    txHead = 0;
    txPending = NO;

    /* Free existing TX queue if present */
    if (txQueue != nil) {
        [txQueue free];
    }

    /* Create new IONetbufQueue with max count of 128 */
    txQueue = [[[objc_getClass("IONetbufQueue") alloc] initWithMaxCount:0x80] retain];
    if (txQueue == nil) {
        driverName = [[self name] cString];
        IOLog("%s: initTxRing: IONetbufQueue is nil\n", driverName);
        return NO;
    }

    return YES;
}

/*
 * Reset the chip
 */
- (void)__resetChip
{
    unsigned short statusReg;
    int timeout;

    /* Issue TX reset command (0x5800) */
    outw(ioBase + REG_COMMAND, 0x5800);

    /* Wait for TX reset to complete (bit 12 cleared in status) */
    timeout = 999999;
    while (timeout > 0) {
        statusReg = inw(ioBase + REG_COMMAND);
        if ((statusReg & 0x1000) == 0) {
            break;
        }
        IODelay(1);
        timeout--;
    }

    /* Issue RX reset command (0x2800) */
    outw(ioBase + REG_COMMAND, 0x2800);

    /* Wait for RX reset to complete (bit 12 cleared in status) */
    timeout = 999999;
    while (timeout > 0) {
        statusReg = inw(ioBase + REG_COMMAND);
        if ((statusReg & 0x1000) == 0) {
            break;
        }
        IODelay(1);
        timeout--;
    }
}

/*
 * Enable adapter interrupts
 */
- (void)__enableAdapterInterrupts
{
    /* Set interrupt mask:
     * 0x0685 = RX complete, TX complete, TX available, link events, statistics
     */
    interruptMask = 0x0685;

    /* Enable interrupts with command 0x7E85 (SetInterruptEnable + mask) */
    outw(ioBase + REG_COMMAND, 0x7E00 | interruptMask);

    /* Enable indication with command 0x6800 (SetIndicationEnable) */
    outw(ioBase + REG_COMMAND, 0x6800 | (interruptMask & 0x7FF));

    /* Enable acknowledge with command 0x7000 (SetReadZeroMask) */
    outw(ioBase + REG_COMMAND, 0x7000 | (interruptMask & 0x7FF));
}

/*
 * Disable adapter interrupts
 */
- (void)__disableAdapterInterrupts
{
    /* Disable all interrupts with command 0x7800 (SetInterruptEnable with 0) */
    outw(ioBase + REG_COMMAND, 0x7800);
}

/*
 * Start receive engine
 */
- (void)__startReceive
{
    /* Issue RX enable command (0x2000) */
    outw(ioBase + REG_COMMAND, 0x2000);
}

/*
 * Start transmit engine
 */
- (void)__startTransmit
{
    /* Issue TX enable command (0x4800) */
    outw(ioBase + REG_COMMAND, 0x4800);
}

/*
 * Handle receive interrupt
 */
- (void)__receiveInterruptOccurred
{
    unsigned int localIndex;
    EtherLinkXLDescriptor *descriptor;
    unsigned int descStatus;
    unsigned int packetLength;
    netbuf_t oldNetbuf;
    netbuf_t newNetbuf;
    int netbufSize;
    void *packetData;
    unsigned int packetCount;
    struct objc_super superStruct;

    packetCount = 0;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Get current RX index */
    localIndex = rxIndex & 0x3F;
    descriptor = &rxDescriptors[localIndex];
    descStatus = descriptor->status;

    /* Process all received packets */
    while (1) {
        /* Check if descriptor owned by software (bit 15 set in high byte) */
        if ((descStatus & 0x8000) == 0) {
            /* No more packets - release lock and return */
            [self releaseDebuggerLock];
            return;
        }

        oldNetbuf = rxNetbufArray[localIndex];
        packetCount++;

        /* Acknowledge interrupt every 8 packets (and if less than 128) */
        if ((packetCount & 7) == 0 && packetCount < 0x80) {
            outw(ioBase + REG_COMMAND, CMD_ACK_INTERRUPT_LATCH);
        }

        /* Check for errors (bit 14) and minimum size (> 59 bytes) */
        packetLength = descStatus & 0x1FFF;
        if ((descStatus & 0x4000) == 0 && packetLength > 59) {
            /* Good packet */

            /* Check if we should filter multicast packets */
            if (isPromiscuous || !isMulticast) {
                /* Process packet normally */
                goto processPacket;
            }

            /* Check if this is an unwanted multicast packet */
            packetData = (void *)nb_map(oldNetbuf);
            superStruct.receiver = self;
            superStruct.class = objc_getClass("IOEthernet");
            if (![super isUnwantedMulticastPacket:packetData]) {
                /* Wanted packet - process it */
processPacket:
                /* Allocate new netbuf for this descriptor */
                newNetbuf = [self allocateNetbuf];
                if (newNetbuf == NULL) {
                    /* Allocation failed - increment error counter */
                    [networkInterface incrementInputErrors];

                    /* Clear ownership bit and advance */
                    ((unsigned char *)descriptor)[5] &= 0x7F;
                    rxIndex++;
                } else {
                    /* Update descriptor with new netbuf */
                    rxNetbufArray[localIndex] = newNetbuf;

                    if (![self __updateDescriptor:descriptor fromNetBuf:newNetbuf receive:YES]) {
                        IOPanic("EtherLinkXL: updateDescriptor failed\n");
                    }

                    /* Adjust old netbuf size to packet length */
                    netbufSize = nb_size(oldNetbuf);
                    nb_shrink_bot(oldNetbuf, netbufSize - packetLength);

                    /* Clear ownership bit and advance */
                    ((unsigned char *)descriptor)[5] &= 0x7F;
                    rxIndex++;

                    /* Release lock before passing to network stack */
                    [self releaseDebuggerLock];

                    /* Pass packet to network interface */
                    [networkInterface handleInputPacket:oldNetbuf extra:0];

                    /* Re-acquire lock for next iteration */
                    [self reserveDebuggerLock];
                }
            } else {
                /* Unwanted multicast - drop it */
                ((unsigned char *)descriptor)[5] &= 0x7F;
                rxIndex++;
                localIndex = rxIndex;
            }
        } else {
            /* Bad packet - increment error counter */
            [networkInterface incrementInputErrors];

            /* Clear ownership bit and advance */
            ((unsigned char *)descriptor)[5] &= 0x7F;
            rxIndex++;
        }

        /* Get next descriptor */
        localIndex = rxIndex & 0x3F;
        descriptor = &rxDescriptors[localIndex];
        descStatus = descriptor->status;
    }
}

/*
 * Handle transmit interrupt
 */
- (void)__transmitInterruptOccurred
{
    int i;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Check if transmission was pending */
    if (txPending) {
        /* Free all transmitted netbufs */
        for (i = 0; i < TX_RING_SIZE; i++) {
            if (txNetbufArray[i] == NULL) {
                break;
            }
            nb_free(txNetbufArray[i]);
            txNetbufArray[i] = NULL;
        }

        /* Clear pending flag */
        txPending = NO;
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Handle transmit error interrupt
 */
- (void)__transmitErrorInterruptOccurred
{
    unsigned char txStatusByte;
    unsigned int savedTxStatus;
    unsigned short statusReg;
    unsigned int regValue;
    int timeout;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Switch to window 1 to read TX status */
    if (currentWindow != 1) {
        outw(ioBase + REG_COMMAND, 0x0801);
        currentWindow = 1;
    }

    /* Read TX status byte at offset 0x0B */
    txStatusByte = inb(ioBase + 0x0B);

    /* Read command register (dummy read) */
    inw(ioBase + REG_COMMAND);

    /* Save TX status register value */
    savedTxStatus = inw(ioBase + REG_TX_STATUS);

    /* Write back TX status byte to clear it */
    if (currentWindow != 1) {
        outw(ioBase + REG_COMMAND, 0x0801);
        currentWindow = 1;
    }
    outb(ioBase + 0x0B, txStatusByte);

    /* Handle specific error conditions */
    if ((txStatusByte & 0x08) != 0) {
        /* Max collisions (bit 3) - increment collision counter by 16 */
        [networkInterface incrementCollisionsBy:16];
    } else if ((txStatusByte & 0x10) != 0) {
        /* Jabber error (bit 4) */

        /* Wait for bit 7 clear in register at offset 0x20 */
        do {
            regValue = inl(ioBase + 0x20);
        } while ((regValue & 0x80) != 0);

        /* Poll window 4 offset 10 for bit 12 clear */
        do {
            if (currentWindow != 4) {
                outw(ioBase + REG_COMMAND, 0x0804);
                currentWindow = 4;
            }
            statusReg = inw(ioBase + 10);
        } while ((statusReg & 0x1000) != 0);

        /* Reset TX with command 0x5840 */
        outw(ioBase + REG_COMMAND, 0x5840);

        /* Wait for reset to complete */
        timeout = 999999;
        while (timeout > 0) {
            statusReg = inw(ioBase + REG_COMMAND);
            if ((statusReg & 0x1000) == 0) {
                break;
            }
            IODelay(1);
            timeout--;
        }

        /* Increment output errors */
        [networkInterface incrementOutputErrors];
    } else if ((txStatusByte & 0x20) != 0) {
        /* Underrun error (bit 5) */

        /* Reset TX with command 0x5840 */
        outw(ioBase + REG_COMMAND, 0x5840);

        /* Wait for reset to complete */
        timeout = 999999;
        while (timeout > 0) {
            statusReg = inw(ioBase + REG_COMMAND);
            if ((statusReg & 0x1000) == 0) {
                break;
            }
            IODelay(1);
            timeout--;
        }

        /* Increment output errors */
        [networkInterface incrementOutputErrors];
    }

    /* Re-enable transmit (command 0x4800) */
    outw(ioBase + REG_COMMAND, 0x4800);

    /* Write to offset 0x2F */
    outb(ioBase + 0x2F, 6);

    /* Restore TX status register */
    outl(ioBase + REG_TX_STATUS, savedTxStatus);

    /* Acknowledge TX complete interrupt (0x3003) */
    outw(ioBase + REG_COMMAND, 0x3003);

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Handle statistics update interrupt
 */
- (void)__updateStatsInterruptOccurred
{
    unsigned char stats[6];
    unsigned char byte1, byte2, byte3;
    unsigned int txPackets;
    unsigned int collisions;
    unsigned short word;
    unsigned char highByte;
    int i;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Switch to window 6 to read statistics */
    if (currentWindow != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        currentWindow = 6;
    }

    /* Read 6 bytes of statistics */
    for (i = 0; i < 6; i++) {
        stats[i] = inb(ioBase + i);
    }

    /* Read additional bytes */
    byte1 = inb(ioBase + 6);
    byte2 = inb(ioBase + 7);
    byte3 = inb(ioBase + 9);

    /* Build TX packets counter (12-bit value) */
    txPackets = byte1 | ((byte3 & 0x30) << 4);

    /* Build collisions counter (10-bit value) */
    collisions = byte2 | ((byte3 & 0x03) << 8);

    /* Read byte at offset 8 (not used but read anyway) */
    inb(ioBase + 8);

    /* Read from window 6 offset 10 */
    if (currentWindow != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        currentWindow = 6;
    }
    word = inw(ioBase + 10);

    /* Read from window 4 offset 0x0D and combine */
    if (currentWindow != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        currentWindow = 4;
    }
    highByte = inb(ioBase + 0x0D);
    /* Not used - just read for clearing */

    /* Read from window 6 offset 0x0C */
    if (currentWindow != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        currentWindow = 6;
    }
    word = inw(ioBase + 0x0C);

    /* Read from window 4 offset 0x0D and combine */
    if (currentWindow != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        currentWindow = 4;
    }
    highByte = inb(ioBase + 0x0D);
    /* Not used - just read for clearing */

    /* Read from window 4 offset 0x0C */
    if (currentWindow != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        currentWindow = 4;
    }
    inb(ioBase + 0x0C);

    /* Release debugger lock */
    [self releaseDebuggerLock];

    /* Update network interface statistics */
    [networkInterface incrementOutputPacketsBy:txPackets];
    [networkInterface incrementCollisionsBy:(stats[2] + stats[3] + stats[0])];
}

/*
 * Transmit a packet
 */
- (BOOL)__transmitPacket:(netbuf_t)packet flush:(BOOL)flush
{
    EtherLinkXLDescriptor *descriptor;
    EtherLinkXLDescriptor *prevDescriptor;
    IOTask task;
    unsigned int physicalAddr;

    /* Perform loopback check */
    [self performLoopback:packet];

    /* Check if TX queue has space */
    if (txHead >= TX_RING_SIZE) {
        return NO;  /* Queue full */
    }

    /* Get current TX descriptor */
    descriptor = &txDescriptors[txHead];

    /* Free any existing netbuf in this slot */
    if (txNetbufArray[txHead] != NULL) {
        nb_free(txNetbufArray[txHead]);
        txNetbufArray[txHead] = NULL;
    }

    /* Store the new netbuf */
    txNetbufArray[txHead] = packet;

    /* Update descriptor from netbuf */
    [self __updateDescriptor:descriptor fromNetBuf:packet receive:NO];

    /* Get IOTask for physical address operations */
    task = IOVmTaskSelf();

    /* Calculate and cache physical address of this descriptor */
    physicalAddr = IOPhysicalFromVirtual(task, (vm_address_t)descriptor);
    descriptor->reserved[2] = physicalAddr;

    /* Set ownership bit (bit 7 of byte 7 - indicating software ownership during setup) */
    ((unsigned char *)descriptor)[7] |= 0x80;

    /* Link previous descriptor if not first */
    if (txHead != 0) {
        prevDescriptor = &txDescriptors[txHead - 1];
        /* Link previous descriptor to this one using cached physical address */
        prevDescriptor->nextDescriptor = descriptor->reserved[2];
        /* Clear ownership bit on previous descriptor (transfer to hardware) */
        ((unsigned char *)prevDescriptor)[7] &= 0x7F;
    }

    /* Increment TX head */
    txHead++;

    /* If flush requested or queue full, initiate transmission */
    if (flush || (txHead >= TX_RING_SIZE)) {
        /* Clear ownership bit on last descriptor (transfer to hardware) */
        ((unsigned char *)descriptor)[7] &= 0x7F;

        /* Switch queues and transmit with 1500ms timeout */
        return [self __switchQueuesAndTransmitWithTimeout:0x5DC];
    }

    return YES;
}

/*
 * Update descriptor from netbuf
 * This method handles both TX and RX descriptors and deals with page boundary crossing
 */
- (void)__updateDescriptor:(void *)descriptor fromNetBuf:(netbuf_t)netbuf receive:(BOOL)receive
{
    EtherLinkXLDescriptor *desc;
    unsigned int netbufSize;
    void *bufferAddr;
    unsigned int physicalAddr;
    unsigned int pageOffset;
    unsigned int firstChunkSize;
    unsigned int secondChunkSize;
    kern_return_t result;
    IOTask task;

    desc = (EtherLinkXLDescriptor *)descriptor;

    /* Get buffer size (different for RX and TX) */
    if (receive) {
        /* RX: Use fixed buffer size of 1514 bytes (0x5EA) */
        netbufSize = 0x5EA;
    } else {
        /* TX: Use actual netbuf size */
        netbufSize = nb_size(netbuf);
    }

    /* Map netbuf to get virtual address */
    bufferAddr = (void *)nb_map(netbuf);

    /* Get current IOTask */
    task = IOVmTaskSelf();

    /* Convert virtual address to physical address */
    physicalAddr = IOPhysicalFromVirtual(task, (vm_address_t)bufferAddr);

    /* Check for page boundary crossing */
    pageOffset = physicalAddr & 0xFFF;  /* Offset within 4KB page */

    if ((pageOffset + netbufSize) <= 0x1000) {
        /* No page crossing - simple case */
        desc->bufferAddr = physicalAddr;
        desc->status = netbufSize & 0x1FFF;  /* Store size in bits 0-12 */

        /* For RX, set descriptor to be owned by hardware (bit 15) */
        if (receive) {
            desc->status |= 0x8000;
        }
    } else {
        /* Page boundary crossing - split into two fragments */
        firstChunkSize = 0x1000 - pageOffset;  /* Bytes until end of first page */
        secondChunkSize = netbufSize - firstChunkSize;

        /* First descriptor contains first chunk */
        desc->bufferAddr = physicalAddr;
        desc->status = firstChunkSize & 0x1FFF;

        /* For RX, set owned by hardware */
        if (receive) {
            desc->status |= 0x8000;
        }

        /* Get physical address of second chunk (on next page) */
        physicalAddr = IOPhysicalFromVirtual(task, (vm_address_t)bufferAddr + firstChunkSize);

        /* Set up continuation in reserved field (acts as second descriptor) */
        desc->reserved[0] = physicalAddr;  /* Address of second chunk */
        desc->reserved[1] = secondChunkSize & 0x1FFF;  /* Size of second chunk */

        if (receive) {
            desc->reserved[1] |= 0x8000;  /* Owned by hardware */
        }
    }
}

/*
 * Switch queues and transmit with timeout
 */
- (BOOL)__switchQueuesAndTransmitWithTimeout:(unsigned int)timeout
{
    int txStatus;
    void *tempPtr;
    EtherLinkXLDescriptor *currentDescriptors;

    /* Wait for TX status register to clear (previous transmission complete) */
    do {
        txStatus = inw(ioBase + REG_TX_STATUS);
    } while (txStatus != 0);

    /* Get current TX descriptor queue */
    currentDescriptors = txDescriptors;

    /* Write physical address of first descriptor to TX status register
     * This starts the DMA transmission
     * Physical address is stored at offset 0x1C (reserved[3])
     */
    outl(ioBase + REG_TX_STATUS, currentDescriptors[0].reserved[3]);

    /* Swap the two TX descriptor queue pointers */
    tempPtr = txDescriptors;
    txDescriptors = (EtherLinkXLDescriptor *)txDescriptorBase;
    txDescriptorBase = tempPtr;

    /* Reset TX head counter */
    txHead = 0;

    /* Swap the two TX netbuf array pointers */
    tempPtr = txNetbufArrayAlt;
    txNetbufArrayAlt = txNetbufArray;
    txNetbufArray = (netbuf_t *)tempPtr;

    /* Set timeout if requested */
    if (timeout != 0) {
        [self setRelativeTimeout:timeout];
    }

    /* Mark transmission as pending */
    txPending = YES;

    return YES;
}

/*
 * Auto-select best medium
 */
- (void)__autoSelectMedium
{
    extern const MediaEntry mediaTable[];
    const char *driverName;
    const char *mediaName;
    unsigned int nextMedium;

    /* Validate requested medium index */
    if (requestedMedium > 6) {
        /* Invalid medium - use default */
        currentMedium = defaultMedium;
        driverName = [[self name] cString];
        mediaName = mediaTable[currentMedium].name;
        IOLog("%s: Invalid network port. Using default (%s).\n", driverName, mediaName);
    }

    /* Check if auto-select requested (medium index 2) */
    if (requestedMedium == 2) {
        /* Auto-select mode - try each available medium */
        currentMedium = 4;  /* Start with medium 4 */

        while (1) {
            /* Check if current medium is available in hardware */
            while ((availableMedia & mediaTable[currentMedium].type) == 0) {
                /* Not available - try next medium */
                nextMedium = mediaTable[currentMedium].param;
                currentMedium = nextMedium;
            }

            /* Check if we've tried all media */
            if (currentMedium == 7) {
                /* No working medium found - use default */
                currentMedium = defaultMedium;
                driverName = [[self name] cString];
                mediaName = mediaTable[currentMedium].name;
                IOLog("%s: Auto-selected %s port\n", driverName, mediaName);
                break;
            }

            /* Try this medium */
            [self __setCurrentMedium];

            /* Wait for medium to stabilize */
            IOSleep(mediaTable[currentMedium].delay);

            /* Check if link is up */
            if ([self __linkUp]) {
                /* Link established - use this medium */
                driverName = [[self name] cString];
                mediaName = mediaTable[currentMedium].name;
                IOLog("%s: Auto-selected %s port\n", driverName, mediaName);
                break;
            }

            /* Link failed - try next medium */
            currentMedium = mediaTable[currentMedium].param;
        }

        /* Configure the selected medium */
        [self __setCurrentMedium];
    } else {
        /* Specific medium requested */
        currentMedium = requestedMedium;

        /* Check if requested medium is available */
        if ((availableMedia & mediaTable[currentMedium].type) == 0) {
            /* Not available - fall back to default */
            driverName = [[self name] cString];
            IOLog("%s: %s port rejected by adapter. Switching to %s port.\n",
                  driverName,
                  mediaTable[requestedMedium].name,
                  mediaTable[defaultMedium].name);
            currentMedium = defaultMedium;
        }

        /* Configure the selected medium */
        [self __setCurrentMedium];
    }
}

/*
 * Set current medium
 */
- (void)__setCurrentMedium
{
    extern const MediaEntry mediaTable[];
    unsigned short mediaFlags;
    unsigned int internalConfig;
    unsigned short statusReg;

    /* Check if full duplex capable (upper 16 bits of availableMedia) */
    mediaFlags = 0;
    if ((availableMedia & 0xFFFF00) != 0) {
        mediaFlags = 0x20;  /* Enable full duplex */
    }

    /* Switch to window 3 and write media flags */
    if (currentWindow != 3) {
        outw(ioBase + REG_COMMAND, 0x0803);
        currentWindow = 3;
    }
    outw(ioBase + 6, mediaFlags);

    /* Read internal config register */
    if (currentWindow != 3) {
        outw(ioBase + REG_COMMAND, 0x0803);
        currentWindow = 3;
    }
    internalConfig = inl(ioBase + 0);

    /* Modify xcvr type field (bits 20-22) */
    if (currentWindow != 3) {
        outw(ioBase + REG_COMMAND, 0x0803);
        currentWindow = 3;
    }
    outl(ioBase + 0, (internalConfig & 0xFF8FFFFF) | ((currentMedium & 0x07) << 20));

    /* Issue appropriate command based on medium */
    if (currentMedium == 3) {
        /* MII medium - enable MII (0x1000) */
        outw(ioBase + REG_COMMAND, 0x1000);
        IODelay(1000);
    } else {
        /* Other media - disable MII (0xB800) */
        outw(ioBase + REG_COMMAND, 0xB800);
    }

    /* Switch to window 4 and configure media options */
    if (currentWindow != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        currentWindow = 4;
    }

    /* Read current media status */
    statusReg = inw(ioBase + 10);

    /* Get media-specific flags from media table */
    mediaFlags = mediaTable[currentMedium].flags;

    /* Write back with media flags (preserve bits not in 0xFF37 mask) */
    if (currentWindow != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        currentWindow = 4;
    }
    outw(ioBase + 10, (statusReg & 0xFF37) | mediaFlags);
}

/*
 * Configure PHY
 */
- (BOOL)__configurePHY:(unsigned int)phy
{
    unsigned short controlReg;
    unsigned short phyID1, phyID2;
    unsigned int phyID;
    unsigned short statusReg;
    const char *driverName;
    const char *speedStr;
    const char *duplexStr;

    /* Only configure valid PHY addresses (0-31) */
    if (phy >= 0x20) {
        return NO;
    }

    /* Reset the PHY */
    if (![self _resetMIIDevice:phy]) {
        driverName = [[self name] cString];
        IOLog("%s: PHY reset failed\n", driverName);
        return NO;
    }

    /* Read PHY ID registers to identify the PHY */
    if (![self _miiReadWord:&phyID1 reg:2 phy:phy]) {
        driverName = [[self name] cString];
        IOLog("%s: MII/PHY read error\n", driverName);
        return NO;
    }

    if (![self _miiReadWord:&phyID2 reg:3 phy:phy]) {
        driverName = [[self name] cString];
        IOLog("%s: MII/PHY read error\n", driverName);
        return NO;
    }

    /* Combine ID registers into 32-bit PHY ID */
    phyID = (phyID1 << 16) | phyID2;

    /* Identify PHY type */
    if (phyID == 0x20005C00) {
        driverName = [[self name] cString];
        IOLog("%s: Found DP83840 PHY\n", driverName);
    } else if (phyID == 0x20005C01) {
        driverName = [[self name] cString];
        IOLog("%s: Found DP83840A PHY\n", driverName);
    } else {
        driverName = [[self name] cString];
        IOLog("%s: Unknown PHY ID: 0x%08x\n", driverName, phyID);
        return NO;
    }

    /* Read control register */
    if (![self _miiReadWord:&controlReg reg:0 phy:phy]) {
        driverName = [[self name] cString];
        IOLog("%s: MII/PHY read error\n", driverName);
        return NO;
    }

    /* Enable auto-negotiation and 100Mbps:
     * Bit 12 (0x1000) = Auto-negotiation enable
     * Bit 13 (0x2000) = Speed selection (100Mbps)
     * 0x1200 = both bits
     */
    controlReg |= 0x1200;
    [self _miiWriteWord:controlReg reg:0 phy:phy];

    /* Wait for auto-negotiation to complete */
    if (![self _waitMIIAutoNegotiation:phy]) {
        driverName = [[self name] cString];
        IOLog("%s: MII/PHY Auto-negotiation failed\n", driverName);
        return NO;
    }

    /* Read PHY-specific status register (register 0x19 = 25) */
    if (![self _miiReadWord:&statusReg reg:0x19 phy:phy]) {
        driverName = [[self name] cString];
        IOLog("%s: MII/PHY read error\n", driverName);
        return NO;
    }

    /* Determine duplex mode from bit 7 (0x80) */
    if ((statusReg & 0x80) != 0) {
        duplexStr = "Full";
        isFullDuplex = YES;
    } else {
        duplexStr = "Half";
        isFullDuplex = NO;
    }

    /* Determine speed from bit 6 (0x40) */
    if ((statusReg & 0x40) != 0) {
        speedStr = "10";
    } else {
        speedStr = "100";
    }

    /* Log configuration */
    driverName = [[self name] cString];
    IOLog("%s: MII port configured for %s Mbps %s Duplex\n",
          driverName, speedStr, duplexStr);

    return YES;
}

/*
 * Check if link is up
 */
- (BOOL)__linkUp
{
    unsigned short statusReg;

    /* Acquire debugger lock for safe register access */
    [self reserveDebuggerLock];

    /* Switch to window 4 to read media status */
    if (currentWindow != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        currentWindow = 4;
    }

    /* Read media status register at offset 10 */
    statusReg = inw(ioBase + 10);

    /* Release debugger lock */
    [self releaseDebuggerLock];

    /* Check link status based on current medium */
    switch (currentMedium) {
        case 0:  /* 10Base-T */
        case 4:  /* 100Base-TX */
        case 5:  /* 100Base-T4 */
            /* Check link beat detect (bit 11 when right-shifted by 8 = bit 3) */
            if ((statusReg & 0x0800) == 0) {
                return NO;
            }
            break;

        case 1:  /* AUI */
        case 6:  /* 100Base-FX */
            /* AUI and FX always considered up */
            break;

        case 3:  /* MII */
            /* Check MII link fail (bit 4) - inverted logic */
            if ((statusReg & 0x10) != 0) {
                return NO;
            }
            break;

        default:
            /* Unknown medium */
            return NO;
    }

    return YES;
}

@end
