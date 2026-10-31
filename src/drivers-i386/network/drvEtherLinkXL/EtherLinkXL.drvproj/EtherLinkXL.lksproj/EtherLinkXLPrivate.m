/*
 * EtherLinkXLPrivate.m
 * 3Com EtherLink XL Network Driver - Private Internal Methods
 */

#import "EtherLinkXL.h"
#import <driverkit/generalFuncs.h>
#import <kernserv/prototypes.h>
#import <strings.h>

/* External reference to page size */
extern unsigned int page_size;
extern unsigned int page_mask;

@implementation EtherLinkXL(EtherLinkXLPrivate)

/*
 * Internal initialization
 */
- (BOOL)_init
{
    vm_task_t task;
    unsigned int physicalAddr;
    unsigned short statusReg;
    int timeout;
    int i;
    const char *driverName;

    /* Get physical address of RX descriptor ring */
    task = IOVmTaskSelf();
    if (IOPhysicalFromVirtual(task, (vm_address_t)rxRing, &physicalAddr) != IO_R_SUCCESS) {
        driverName = [self name];
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
    if (window != 5) {
        outw(ioBase + REG_COMMAND, 0x0805);
        window = 5;
    }
    outw(ioBase + REG_COMMAND, 0x8FFC);

    /* Set bit 0x20 in register at port + 0x20 */
    physicalAddr = inl(ioBase + 0x20);
    outl(ioBase + 0x20, physicalAddr | 0x20);

    /* Switch to window 2 and write station address */
    if (window != 2) {
        outw(ioBase + REG_COMMAND, 0x0802);
        window = 2;
    }

    /* Write MAC address to window 2, offsets 0-5 */
    for (i = 0; i < 6; i++) {
        outb(ioBase + i, etherAddress.ea_byte[i]);
    }

    /* Write command with byte from offset 0x18A */
    outw(ioBase + REG_COMMAND, 0x8000 | rxFilterMode);

    /* Write command 0xB000 */
    outw(ioBase + REG_COMMAND, 0xB000);

    /* Switch to window 6 and read adapter capabilities */
    if (window != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        window = 6;
    }

    for (i = 0; i < 6; i++) {
        statStruct.rawCounters[i] = inb(ioBase + i);
    }
    statStruct.framesXmittedOk = inb(ioBase + 6);
    statStruct.framesRcvdOk = inb(ioBase + 7);
    physicalAddr = inb(ioBase + 9);
    statStruct.framesXmittedOk |= (physicalAddr & 0x30) << 4;
    statStruct.framesRcvdOk |= (physicalAddr & 0x03) << 8;
    statStruct.framesDeferred = inb(ioBase + 8);

    if (window != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        window = 6;
    }
    statStruct.bytesRcvdOk = inw(ioBase + 10);

    /* Read from window 4 offset 0x0D */
    if (window != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        window = 4;
    }
    statStruct.bytesRcvdOk |= (unsigned int)inb(ioBase + 0x0D) << 16;

    /* Read from window 6 offset 0x0C */
    if (window != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        window = 6;
    }
    statStruct.bytesXmittedOk = inw(ioBase + 0x0C);

    /* Read from window 4 offset 0x0D again */
    if (window != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        window = 4;
    }
    statStruct.bytesXmittedOk |= (unsigned int)inb(ioBase + 0x0D) << 16;

    /* Read media options from window 4 offset 0x0C */
    if (window != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        window = 4;
    }
    statStruct.badSSD = inb(ioBase + 0x0C);

    /* Write 0x40 to window 4 offset 6 */
    if (window != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        window = 4;
    }
    outw(ioBase + 6, 0x40);

    /* Write command 0xA800 */
    outw(ioBase + REG_COMMAND, 0xA800);

    return YES;
}

/*
 * Allocate DMA and descriptor memory
 */
- (BOOL)_allocateMemory
{
    const char *driverName;
    int i;

    /* Set descriptor memory size: 0x1020 = 4128 bytes
     * RX descriptors: 64 * 32 = 2048 bytes
     * TX descriptors: 32 * 32 * 2 (two queues) = 2048 bytes
     * Plus alignment padding
     */
    memorySize = 0x1020;

    /* Check if memory fits in one page */
    if (page_size < memorySize) {
        driverName = [self name];
        IOLog("%s: 1 page limit exceeded for descriptor memory\n", driverName);
        return NO;
    }

    /* Allocate low memory (DMA-able, < 16MB) for descriptors */
    memoryPtr = (void *)IOMallocLow(memorySize);
    if (memoryPtr == NULL) {
        driverName = [self name];
        IOLog("%s: Can't allocate %d bytes of memory\n", driverName, memorySize);
        return NO;
    }

    /* Set up RX descriptors (aligned to 16-byte boundary) */
    rxRing = (EtherLinkXLDescriptor *)memoryPtr;
    if (((unsigned int)rxRing & 0x0F) != 0) {
        /* Align to next 16-byte boundary */
        rxRing = (EtherLinkXLDescriptor *)(((unsigned int)memoryPtr + 0x0F) & 0xFFFFFFF0);
    }

    /* Initialize RX descriptors and netbuf array */
    for (i = 0; i < RX_RING_SIZE; i++) {
        bzero(&rxRing[i], sizeof(EtherLinkXLDescriptor));
        rxNetbuf[i] = NULL;
    }

    /* TX queues follow the receive ring in the same descriptor allocation. */
    txCurrentQueue = (EtherLinkXLDescriptor *)((unsigned int)rxRing + 0x800);
    if (((unsigned int)txCurrentQueue & 0x0F) != 0) {
        txCurrentQueue = (EtherLinkXLDescriptor *)(((unsigned int)txCurrentQueue + 0x0F) & 0xFFFFFFF0);
    }
    txPendingQueue = (EtherLinkXLDescriptor *)((unsigned int)txCurrentQueue + 0x400);

    /* Allocate TX netbuf arrays */
    xmitNetbufMemorySize = 0x80;  /* 128 bytes = 32 * 4 */
    txCurrentNetbuf = (netbuf_t *)IOMalloc(xmitNetbufMemorySize);
    txPendingNetbuf = (netbuf_t *)IOMalloc(xmitNetbufMemorySize);

    if (txCurrentNetbuf == NULL || txPendingNetbuf == NULL) {
        driverName = [self name];
        IOLog("%s: Can't allocate memory for netbuf array\n", driverName);
        return NO;
    }

    /* Initialize TX descriptors and netbuf arrays */
    for (i = 0; i < TX_RING_SIZE; i++) {
        /* Zero out both TX descriptor queues */
        bzero((void *)((unsigned int)txPendingQueue + i * sizeof(EtherLinkXLDescriptor)),
              sizeof(EtherLinkXLDescriptor));
        bzero(&txCurrentQueue[i], sizeof(EtherLinkXLDescriptor));

        /* Initialize netbuf arrays */
        txCurrentNetbuf[i] = NULL;
        txPendingNetbuf[i] = NULL;
    }

    return YES;
}

/*
 * Initialize receive ring
 */
- (BOOL)_initRxRing
{
    vm_task_t task;
    unsigned int physicalAddr;
    int i;
    EtherLinkXLDescriptor *descriptor;
    const char *driverName;

    task = IOVmTaskSelf();
    /* Initialize all RX descriptors */
    for (i = 0; i < RX_RING_SIZE; i++) {
        descriptor = &rxRing[i];

        /* Zero out descriptor */
        bzero(descriptor, sizeof(EtherLinkXLDescriptor));

        /* Get physical address of next descriptor (for linking) */
        if (IOPhysicalFromVirtual(task, (vm_address_t)&rxRing[i + 1],
                                  &physicalAddr) != IO_R_SUCCESS) {
            return NO;
        }
        descriptor->nextDescriptor = physicalAddr;

        /* Allocate netbuf if not already allocated */
        if (rxNetbuf[i] == NULL) {
            rxNetbuf[i] = [self allocateNetbuf];
            if (rxNetbuf[i] == NULL) {
                driverName = [self name];
                IOLog("%s: initRxRing: allocateNetbuf returned NULL\n", driverName);
                return NO;
            }
        }

        /* Update descriptor from netbuf */
        if (![self _updateDescriptor:descriptor fromNetBuf:rxNetbuf[i] receive:YES]) {
            driverName = [self name];
            IOLog("%s: initRxRing: updateDescriptor failed\n", driverName);
            return NO;
        }
    }

    if (IOPhysicalFromVirtual(task, (vm_address_t)rxRing, &physicalAddr) != IO_R_SUCCESS) {
        return NO;
    }
    rxRing[RX_RING_SIZE - 1].nextDescriptor = physicalAddr;
    rxCur = 0;

    return YES;
}

/*
 * Initialize transmit queue
 */
- (BOOL)_initTxQueue
{
    vm_task_t task;
    unsigned int physicalAddr;
    unsigned int i;
    EtherLinkXLDescriptor *descriptor;
    const char *driverName;

    task = IOVmTaskSelf();
    for (i = 0; i < TX_RING_SIZE; i++) {
        descriptor = &txCurrentQueue[i];
        bzero(descriptor, sizeof(*descriptor));
        if (i < TX_RING_SIZE - 1) {
            if (IOPhysicalFromVirtual(task, (vm_address_t)&txCurrentQueue[i + 1],
                                      &physicalAddr) != IO_R_SUCCESS) {
                return NO;
            }
            descriptor->ringLink = physicalAddr;
        }
        if (IOPhysicalFromVirtual(task, (vm_address_t)descriptor, &physicalAddr) != IO_R_SUCCESS) {
            return NO;
        }
        descriptor->physicalAddr = physicalAddr;

        /* Free any existing netbuf in first queue */
        if (txCurrentNetbuf[i] != NULL) {
            nb_free(txCurrentNetbuf[i]);
            txCurrentNetbuf[i] = NULL;
        }

        descriptor = &txPendingQueue[i];
        bzero(descriptor, sizeof(*descriptor));
        if (i < TX_RING_SIZE - 1) {
            if (IOPhysicalFromVirtual(task, (vm_address_t)&txPendingQueue[i + 1],
                                      &physicalAddr) != IO_R_SUCCESS) {
                return NO;
            }
            descriptor->ringLink = physicalAddr;
        }
        if (IOPhysicalFromVirtual(task, (vm_address_t)descriptor, &physicalAddr) != IO_R_SUCCESS) {
            return NO;
        }
        descriptor->physicalAddr = physicalAddr;

        /* Free any existing netbuf in second queue */
        if (txPendingNetbuf[i] != NULL) {
            nb_free(txPendingNetbuf[i]);
            txPendingNetbuf[i] = NULL;
        }
    }

    /* Initialize TX management variables */
    txIndex = 0;
    interruptExpected = NO;

    /* Free existing TX queue if present */
    if (transmitQueue != nil) {
        [transmitQueue free];
    }

    /* Create new IONetbufQueue with max count of 128 */
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:0x80];
    if (transmitQueue == nil) {
        driverName = [self name];
        IOLog("%s: initTxRing: IONetbufQueue is nil\n", driverName);
        return NO;
    }

    return YES;
}

/*
 * Reset the chip
 */
- (void)_resetChip
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
- (void)_enableAdapterInterrupts
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
- (void)_disableAdapterInterrupts
{
    /* Disable all interrupts with command 0x7800 (SetInterruptEnable with 0) */
    outw(ioBase + REG_COMMAND, 0x7800);
}

/*
 * Start receive engine
 */
- (void)_startReceive
{
    /* Issue RX enable command (0x2000) */
    outw(ioBase + REG_COMMAND, 0x2000);
}

/*
 * Start transmit engine
 */
- (void)_startTransmit
{
    /* Issue TX enable command (0x4800) */
    outw(ioBase + REG_COMMAND, 0x4800);
}

/*
 * Handle receive interrupt
 */
- (void)_receiveInterruptOccurred
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

    packetCount = 0;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Get current RX index */
    localIndex = rxCur & 0x3F;
    descriptor = &rxRing[localIndex];
    descStatus = descriptor->status;

    /* Process all received packets */
    while (1) {
        /* Check if descriptor owned by software (bit 15 set in high byte) */
        if ((descStatus & 0x8000) == 0) {
            /* No more packets - release lock and return */
            [self releaseDebuggerLock];
            return;
        }

        oldNetbuf = rxNetbuf[localIndex];
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
            if (isPromiscuous || !multicastEnabled) {
                /* Process packet normally */
                goto processPacket;
            }

            /* Check if this is an unwanted multicast packet */
            packetData = (void *)nb_map(oldNetbuf);
            if (![super isUnwantedMulticastPacket:(ether_header_t *)packetData]) {
                /* Wanted packet - process it */
processPacket:
                /* Allocate new netbuf for this descriptor */
                newNetbuf = [self allocateNetbuf];
                if (newNetbuf == NULL) {
                    /* Allocation failed - increment error counter */
                    [networkInterface incrementInputErrors];

                    /* Clear ownership bit and advance */
                    ((unsigned char *)descriptor)[5] &= 0x7F;
                    rxCur++;
                } else {
                    /* Update descriptor with new netbuf */
                    rxNetbuf[localIndex] = newNetbuf;

                    if (![self _updateDescriptor:descriptor fromNetBuf:newNetbuf receive:YES]) {
                        IOPanic("EtherLinkXL: updateDescriptor failed\n");
                    }

                    /* Adjust old netbuf size to packet length */
                    netbufSize = nb_size(oldNetbuf);
                    nb_shrink_bot(oldNetbuf, netbufSize - packetLength);

                    /* Clear ownership bit and advance */
                    ((unsigned char *)descriptor)[5] &= 0x7F;
                    rxCur++;

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
                rxCur++;
                localIndex = rxCur;
            }
        } else {
            /* Bad packet - increment error counter */
            [networkInterface incrementInputErrors];

            /* Clear ownership bit and advance */
            ((unsigned char *)descriptor)[5] &= 0x7F;
            rxCur++;
        }

        /* Get next descriptor */
        localIndex = rxCur & 0x3F;
        descriptor = &rxRing[localIndex];
        descStatus = descriptor->status;
    }
}

/*
 * Handle transmit interrupt
 */
- (void)_transmitInterruptOccurred
{
    int i;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Check if transmission was pending */
    if (interruptExpected) {
        /* Free all transmitted netbufs */
        for (i = 0; i < TX_RING_SIZE; i++) {
            if (txCurrentNetbuf[i] == NULL) {
                break;
            }
            nb_free(txCurrentNetbuf[i]);
            txCurrentNetbuf[i] = NULL;
        }

        /* Clear pending flag */
        interruptExpected = NO;
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Handle transmit error interrupt
 */
- (void)_transmitErrorInterruptOccurred
{
    unsigned char txStatusByte;
    unsigned int savedTxStatus;
    unsigned short statusReg;
    unsigned int regValue;
    int timeout;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Switch to window 1 to read TX status */
    if (window != 1) {
        outw(ioBase + REG_COMMAND, 0x0801);
        window = 1;
    }

    /* Read TX status byte at offset 0x0B */
    txStatusByte = inb(ioBase + 0x0B);

    /* Read command register (dummy read) */
    inw(ioBase + REG_COMMAND);

    /* Save TX status register value */
    savedTxStatus = inw(ioBase + REG_TX_STATUS);

    /* Write back TX status byte to clear it */
    if (window != 1) {
        outw(ioBase + REG_COMMAND, 0x0801);
        window = 1;
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
            if (window != 4) {
                outw(ioBase + REG_COMMAND, 0x0804);
                window = 4;
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
- (void)_updateStatsInterruptOccurred
{
    unsigned char stats[6];
    unsigned char byte1, byte3;
    unsigned int txPackets;
    unsigned short word;
    unsigned char highByte;
    int i;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Switch to window 6 to read statistics */
    if (window != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        window = 6;
    }

    /* Read 6 bytes of statistics */
    for (i = 0; i < 6; i++) {
        stats[i] = inb(ioBase + i);
    }

    /* Read additional bytes */
    byte1 = inb(ioBase + 6);
    inb(ioBase + 7);
    byte3 = inb(ioBase + 9);

    /* Build TX packets counter (12-bit value) */
    txPackets = byte1 | ((byte3 & 0x30) << 4);

    /* Read byte at offset 8 (not used but read anyway) */
    inb(ioBase + 8);

    /* Read from window 6 offset 10 */
    if (window != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        window = 6;
    }
    word = inw(ioBase + 10);

    /* Read from window 4 offset 0x0D and combine */
    if (window != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        window = 4;
    }
    highByte = inb(ioBase + 0x0D);
    /* Not used - just read for clearing */

    /* Read from window 6 offset 0x0C */
    if (window != 6) {
        outw(ioBase + REG_COMMAND, 0x0806);
        window = 6;
    }
    word = inw(ioBase + 0x0C);

    /* Read from window 4 offset 0x0D and combine */
    if (window != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        window = 4;
    }
    highByte = inb(ioBase + 0x0D);
    /* Not used - just read for clearing */

    /* Read from window 4 offset 0x0C */
    if (window != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        window = 4;
    }
    inb(ioBase + 0x0C);

    (void)word;
    (void)highByte;

    /* Release debugger lock */
    [self releaseDebuggerLock];

    /* Update network interface statistics */
    [networkInterface incrementOutputPacketsBy:txPackets];
    [networkInterface incrementCollisionsBy:(stats[3] + stats[2] + stats[4])];
}

/*
 * Transmit a packet
 */
- (void)_transmitPacket:(netbuf_t)packet flush:(BOOL)flush
{
    EtherLinkXLDescriptor *descriptor;
    EtherLinkXLDescriptor *prevDescriptor;
    const char *driverName;

    /* Perform loopback check */
    [self performLoopback:packet];

    /* Check if TX queue has space */
    if (txIndex >= TX_RING_SIZE) {
        nb_free(packet);
        return;  /* Queue full */
    }

    /* Get current TX descriptor */
    descriptor = &txPendingQueue[txIndex];

    /* Free any existing netbuf in this slot */
    if (txPendingNetbuf[txIndex] != NULL) {
        nb_free(txPendingNetbuf[txIndex]);
        txPendingNetbuf[txIndex] = NULL;
    }

    /* Update descriptor from netbuf */
    if (![self _updateDescriptor:descriptor fromNetBuf:packet receive:NO]) {
        driverName = [self name];
        IOLog("%s: transmitPacket: updateDescriptor failed\n", driverName);
        nb_free(packet);
        return;
    }
    txPendingNetbuf[txIndex] = packet;
    descriptor->nextDescriptor = 0;

    /* Set ownership bit (bit 7 of byte 7 - indicating software ownership during setup) */
    ((unsigned char *)descriptor)[7] |= 0x80;

    /* Link previous descriptor if not first */
    if (txIndex != 0) {
        prevDescriptor = &txPendingQueue[txIndex - 1];
        prevDescriptor->nextDescriptor = prevDescriptor->ringLink;
        /* Clear ownership bit on previous descriptor (transfer to hardware) */
        ((unsigned char *)prevDescriptor)[7] &= 0x7F;
    }

    /* Increment TX head */
    txIndex++;

    /* If flush requested or queue full, initiate transmission */
    if (!interruptExpected && (flush || txIndex > 0x1F)) {
        [self _switchQueuesAndTransmitWithTimeout:YES];
    }

}

/*
 * Update descriptor from netbuf
 * This method handles both TX and RX descriptors and deals with page boundary crossing
 */
- (BOOL)_updateDescriptor:(void *)descriptor fromNetBuf:(netbuf_t)netbuf receive:(BOOL)receive
{
    EtherLinkXLDescriptor *desc;
    unsigned int netbufSize;
    vm_address_t bufferAddr;
    vm_address_t secondBuffer;
    unsigned int physicalAddr;
    unsigned int firstChunkSize;
    unsigned int secondChunkSize;
    vm_task_t task;

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
    bufferAddr = (vm_address_t)nb_map(netbuf);

    /* Get current IOTask */
    task = IOVmTaskSelf();

    if (!receive) {
        ((unsigned short *)desc)[2] = (((unsigned short *)desc)[2] & 0xE000) |
                                      (netbufSize & 0x1FFF);
    }
    ((unsigned short *)desc)[6] = (((unsigned short *)desc)[6] & 0xE000) |
                                  (netbufSize & 0x1FFF);
    ((unsigned char *)desc)[15] |= 0x80;
    if (IOPhysicalFromVirtual(task, bufferAddr, &physicalAddr) != IO_R_SUCCESS) {
        return NO;
    }
    desc->bufferAddr = physicalAddr;

    if ((bufferAddr & ~page_mask) == ((bufferAddr + netbufSize) & ~page_mask)) {
        return YES;
    }

    firstChunkSize = (~page_mask & (page_mask + bufferAddr)) - bufferAddr;
    secondChunkSize = netbufSize - firstChunkSize;
    ((unsigned char *)desc)[15] &= ~0x80;
    ((unsigned char *)desc)[23] |= 0x80;
    ((unsigned short *)desc)[6] = (((unsigned short *)desc)[6] & 0xE000) |
                                  (firstChunkSize & 0x1FFF);
    ((unsigned short *)desc)[10] = (((unsigned short *)desc)[10] & 0xE000) |
                                   (secondChunkSize & 0x1FFF);
    secondBuffer = bufferAddr + firstChunkSize;
    if (IOPhysicalFromVirtual(task, secondBuffer, &physicalAddr) != IO_R_SUCCESS) {
        return NO;
    }
    desc->bufferAddr2 = physicalAddr;
    return YES;
}

/*
 * Switch queues and transmit with timeout
 */
- (void)_switchQueuesAndTransmitWithTimeout:(BOOL)startTimer
{
    unsigned int txStatus;
    EtherLinkXLDescriptor *tempQueue;
    netbuf_t *tempNetbuf;

    /* Wait for TX status register to clear (previous transmission complete) */
    do {
        txStatus = inw(ioBase + REG_TX_STATUS);
    } while (txStatus != 0);

    /* Get current TX descriptor queue */
    outl(ioBase + REG_TX_STATUS, txPendingQueue[0].physicalAddr);

    /* Swap the two TX descriptor queue pointers */
    tempQueue = txPendingQueue;
    txPendingQueue = txCurrentQueue;
    txCurrentQueue = tempQueue;

    /* Reset TX head counter */
    txIndex = 0;

    /* Swap the two TX netbuf array pointers */
    tempNetbuf = txPendingNetbuf;
    txPendingNetbuf = txCurrentNetbuf;
    txCurrentNetbuf = tempNetbuf;

    /* Set a 1500 ms timeout when requested. */
    if (startTimer) {
        [self setRelativeTimeout:1500];
    }

    /* Mark transmission as pending */
    interruptExpected = YES;

}

/*
 * Auto-select best medium
 */
- (void)_autoSelectMedium
{
    extern const MediaEntry mediaTable[];
    const char *driverName;
    const char *mediaName;
    unsigned int nextMedium;

    /* Validate requested medium index */
    if (selectedMedium > 6) {
        /* Invalid medium - use default */
        selectedMedium = defaultMedium;
        driverName = [self name];
        mediaName = mediaTable[currentMedium].name;
        IOLog("%s: Invalid network port. Using default (%s).\n", driverName, mediaName);
    }

    /* Check if auto-select requested (medium index 2) */
    if (selectedMedium == 2) {
        /* Auto-select mode - try each available medium */
        currentMedium = 4;  /* Start with medium 4 */

        while (1) {
            /* Check if current medium is available in hardware */
            while ((mediaCapableFlag & mediaTable[currentMedium].type) == 0) {
                /* Not available - try next medium */
                nextMedium = mediaTable[currentMedium].param;
                currentMedium = nextMedium;
            }

            /* Check if we've tried all media */
            if (currentMedium == 7) {
                /* No working medium found - use default */
                currentMedium = defaultMedium;
                driverName = [self name];
                mediaName = mediaTable[currentMedium].name;
                IOLog("%s: Auto-selected %s port\n", driverName, mediaName);
                break;
            }

            /* Try this medium */
            [self _setCurrentMedium];

            /* Wait for medium to stabilize */
            IOSleep(mediaTable[currentMedium].delay);

            /* Check if link is up */
            if ([self _linkUp]) {
                /* Link established - use this medium */
                driverName = [self name];
                mediaName = mediaTable[currentMedium].name;
                IOLog("%s: Auto-selected %s port\n", driverName, mediaName);
                break;
            }

            /* Link failed - try next medium */
            currentMedium = mediaTable[currentMedium].param;
        }

        /* Configure the selected medium */
        [self _setCurrentMedium];
    } else {
        /* Specific medium requested */
        currentMedium = selectedMedium;

        /* Check if requested medium is available */
        if ((mediaCapableFlag & mediaTable[currentMedium].type) == 0) {
            /* Not available - fall back to default */
            driverName = [self name];
            IOLog("%s: %s port rejected by adapter. Switching to %s port.\n",
                  driverName,
                  mediaTable[selectedMedium].name,
                  mediaTable[defaultMedium].name);
            currentMedium = defaultMedium;
        }

        /* Configure the selected medium */
        [self _setCurrentMedium];
    }
}

/*
 * Set current medium
 */
- (void)_setCurrentMedium
{
    extern const MediaEntry mediaTable[];
    unsigned short mediaFlags;
    unsigned int internalConfig;
    unsigned short statusReg;

    /* The adjacent media flags enable the full-duplex adapter option. */
    mediaFlags = 0;
    if ((*((unsigned int *)&autoSelect) & 0xFFFF00) != 0) {
        mediaFlags = 0x20;  /* Enable full duplex */
    }

    /* Switch to window 3 and write media flags */
    if (window != 3) {
        outw(ioBase + REG_COMMAND, 0x0803);
        window = 3;
    }
    outw(ioBase + 6, mediaFlags);

    /* Read internal config register */
    if (window != 3) {
        outw(ioBase + REG_COMMAND, 0x0803);
        window = 3;
    }
    internalConfig = inl(ioBase + 0);

    /* Modify xcvr type field (bits 20-22) */
    if (window != 3) {
        outw(ioBase + REG_COMMAND, 0x0803);
        window = 3;
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
    if (window != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        window = 4;
    }

    /* Read current media status */
    statusReg = inw(ioBase + 10);

    /* Get media-specific flags from media table */
    mediaFlags = mediaTable[currentMedium].flags;

    /* Write back with media flags (preserve bits not in 0xFF37 mask) */
    if (window != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        window = 4;
    }
    outw(ioBase + 10, (statusReg & 0xFF37) | mediaFlags);
}

/*
 * Configure PHY
 */
- (void)_configurePHY:(unsigned short)phy
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
        return;
    }

    /* Reset the PHY */
    if (![self resetMIIDevice:phy]) {
        driverName = [self name];
        IOLog("%s: PHY reset failed\n", driverName);
        return;
    }

    /* Read PHY ID registers to identify the PHY */
    if (![self miiReadWord:&phyID1 reg:2 phy:phy]) {
        driverName = [self name];
        IOLog("%s: MII/PHY read error\n", driverName);
        return;
    }

    if (![self miiReadWord:&phyID2 reg:3 phy:phy]) {
        driverName = [self name];
        IOLog("%s: MII/PHY read error\n", driverName);
        return;
    }

    /* Combine ID registers into 32-bit PHY ID */
    phyID = (phyID1 << 16) | phyID2;

    /* Identify PHY type */
    if (phyID == 0x20005C00) {
        driverName = [self name];
        IOLog("%s: Found DP83840 PHY\n", driverName);
    } else if (phyID == 0x20005C01) {
        driverName = [self name];
        IOLog("%s: Found DP83840A PHY\n", driverName);
    } else {
        driverName = [self name];
        IOLog("%s: Unknown PHY ID: 0x%08x\n", driverName, phyID);
        return;
    }

    /* Read control register */
    if (![self miiReadWord:&controlReg reg:0 phy:phy]) {
        driverName = [self name];
        IOLog("%s: MII/PHY read error\n", driverName);
        return;
    }

    /* Enable auto-negotiation and 100Mbps:
     * Bit 12 (0x1000) = Auto-negotiation enable
     * Bit 13 (0x2000) = Speed selection (100Mbps)
     * 0x1200 = both bits
     */
    controlReg |= 0x1200;
    [self miiWriteWord:controlReg reg:0 phy:phy];

    /* Wait for auto-negotiation to complete */
    if (![self waitMIIAutoNegotiation:phy]) {
        driverName = [self name];
        IOLog("%s: MII/PHY Auto-negotiation failed\n", driverName);
        return;
    }

    /* Read PHY-specific status register (register 0x19 = 25) */
    if (![self miiReadWord:&statusReg reg:0x19 phy:phy]) {
        driverName = [self name];
        IOLog("%s: MII/PHY read error\n", driverName);
        return;
    }

    /* Determine duplex mode from bit 7 (0x80) */
    if ((statusReg & 0x80) != 0) {
        duplexStr = "Full";
        phyFullDuplex = YES;
    } else {
        duplexStr = "Half";
        phyFullDuplex = NO;
    }

    /* Determine speed from bit 6 (0x40) */
    if ((statusReg & 0x40) != 0) {
        speedStr = "10";
    } else {
        speedStr = "100";
    }

    /* Log configuration */
    driverName = [self name];
    IOLog("%s: MII port configured for %s Mbps %s Duplex\n",
          driverName, speedStr, duplexStr);

}

/*
 * Check if link is up
 */
- (BOOL)_linkUp
{
    unsigned short statusReg;

    /* Acquire debugger lock for safe register access */
    [self reserveDebuggerLock];

    /* Switch to window 4 to read media status */
    if (window != 4) {
        outw(ioBase + REG_COMMAND, 0x0804);
        window = 4;
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
