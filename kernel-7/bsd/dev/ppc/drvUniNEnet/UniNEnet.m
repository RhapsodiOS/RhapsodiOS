/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * Copyright (c) 1998-1999 by Apple Computer, Inc., All rights reserved.
 *
 * Hardware independent (relatively) code for the UniN Ethernet Controller
 *
 * HISTORY
 *
 * dd-mmm-yy
 *	Created.
 *
 */

#import "UniNEnetPrivate.h"

/*
 * Utility functions for UniN register access
 */

static inline u_int32_t OSSwapInt32(u_int32_t data)
{
    return (data << 24) | ((data & 0xFF00) << 8) | ((data >> 8) & 0xFF00) | (data >> 24);
}

static inline u_int16_t OSSwapInt16(u_int16_t data)
{
    return (data << 8) | (data >> 8);
}

void WriteUniNRegister(IOPPCAddress ioBaseEnet, u_int32_t reg_offset, u_int32_t data)
{
    u_int32_t size;
    u_int32_t offset;

    size = reg_offset >> 16;
    offset = reg_offset & 0xFFFF;

    switch (size)
    {
        case 1:  // 8-bit register
            *(volatile u_int8_t *)((u_int32_t)ioBaseEnet + offset) = (u_int8_t)data;
            break;

        case 2:  // 16-bit register
            offset &= 0xFFFE;  // Align to 2-byte boundary
            *(volatile u_int16_t *)((u_int32_t)ioBaseEnet + offset) = OSSwapInt16((u_int16_t)data);
            break;

        case 4:  // 32-bit register
            offset &= 0xFFFC;  // Align to 4-byte boundary
            *(volatile u_int32_t *)((u_int32_t)ioBaseEnet + offset) = OSSwapInt32(data);
            break;
    }

    eieio();  // Enforce in-order execution of I/O operations
}

u_int32_t ReadUniNRegister(IOPPCAddress ioBaseEnet, u_int32_t reg_offset)
{
    u_int32_t size;
    u_int32_t offset;
    u_int32_t value = 0;

    size = reg_offset >> 16;
    offset = reg_offset & 0xFFFF;

    switch (size)
    {
        case 1:  // 8-bit register
            value = *(volatile u_int8_t *)((u_int32_t)ioBaseEnet + offset);
            break;

        case 2:  // 16-bit register
            offset &= 0xFFFE;  // Align to 2-byte boundary
            value = OSSwapInt16(*(volatile u_int16_t *)((u_int32_t)ioBaseEnet + offset));
            break;

        case 4:  // 32-bit register
            offset &= 0xFFFC;  // Align to 4-byte boundary
            value = OSSwapInt32(*(volatile u_int32_t *)((u_int32_t)ioBaseEnet + offset));
            break;
    }

    return value;
}

@implementation UniNEnet

/*
 * Public Factory Methods
 */

+ (BOOL)probe:(IOTreeDevice *)devDesc
{
    UniNEnet *uniNEnetInstance;

    uniNEnetInstance = [self alloc];
    return [uniNEnetInstance initFromDeviceDescription:devDesc] != nil;
}

/*
 * Public Instance Methods
 */

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- initFromDeviceDescription:(IOTreeDevice *)devDesc
{
    u_int32_t macAddrHigh;
    u_int32_t macAddrLow;
    volatile u_int32_t *uniNorthReg;
    struct ifnet *ifp;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:devDesc] == nil) {
        IOLog("Ethernet(UniN): [super initFromDeviceDescription] failed\n");
        return nil;
    }

    /* Verify device has memory ranges defined */
    if ([devDesc numMemoryRanges] == 0) {
        IOLog("Ethernet(UniN): Incorrect deviceDescription - 1\n\r");
        return nil;
    }

    /* Enable UniNorth Ethernet clock via system controller register */
    /* UniNorth system controller at 0xf8000000, offset 0x20 is clock control */
    uniNorthReg = (volatile u_int32_t *)0xf8000020;
    *uniNorthReg |= 0x02;  /* Set bit 1 to enable Ethernet clock */
    eieio();  /* Enforce in-order I/O execution */

    /* Configure PCI registers */
    /* Write 0x16 to PCI command register (offset 4): enable bus master + memory space */
    [devDesc configWriteLong:4 value:0x16];

    /* Write 0x608 to PCI latency/cache line register (offset 0xc) */
    [devDesc configWriteLong:0xc value:0x608];

    /* Map Ethernet controller registers to kernel virtual address space */
    [self mapMemoryRange:0 to:&ioBaseEnet findSpace:YES cache:IO_CacheOff];

    /* Initialize PHY ID to "not found" */
    phyId = 0xFF;

    /* Reset hardware without enabling it */
    if (![self resetAndEnable:NO]) {
        [self free];
        return nil;
    }

    /* Read station (MAC) address from device tree */
    [self _getStationAddress:&myAddress];

    /* Allocate DMA memory for transmit and receive rings */
    if (![self _allocateMemory]) {
        [self free];
        return nil;
    }

    /* Reset and enable hardware */
    if (![self resetAndEnable:YES]) {
        [self free];
        return nil;
    }

    /* Initialize mode flags */
    isPromiscuous = NO;
    multicastEnabled = NO;

    /* Attach to network stack with our MAC address */
    /* Split 6-byte MAC address into two u_int32_t values for the call */
    macAddrHigh = *(u_int32_t *)&myAddress.ea_byte[0];  /* First 4 bytes */
    macAddrLow = (myAddress.ea_byte[4] << 8) | myAddress.ea_byte[5];  /* Last 2 bytes */

    networkInterface = [super attachToNetworkWithAddress:macAddrHigh :macAddrLow];

    /* Get the BSD ifnet structure and set IFF_SIMPLEX flag */
    ifp = (struct ifnet *)[networkInterface getIONetworkIfnet];
    ifp->if_flags |= 0x20;  /* IFF_SIMPLEX - can't hear own transmissions */

    return self;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- free
{
    u_int32_t i;

    /* Clear any pending timeout */
    [self clearTimeout];

    /* Reset the chip to stop all activity */
    [self _resetChip];

    /* Free the network interface object if attached */
    if (networkInterface != nil) {
        [networkInterface free];
    }

    /* Free all receive netbufs */
    for (i = 0; i < rxMaxCommand; i++) {
        if (rxNetbuf[i] != NULL) {
            nb_free(rxNetbuf[i]);
            rxNetbuf[i] = NULL;
        }
    }

    /* Free all transmit netbufs */
    for (i = 0; i < txMaxCommand; i++) {
        if (txNetbuf[i] != NULL) {
            nb_free(txNetbuf[i]);
            txNetbuf[i] = NULL;
        }
    }

    /* Call superclass cleanup */
    return [super free];
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)transmit:(netbuf_t)pkt
{
    u_int32_t queueCount;
    u_int32_t queueMax;
    u_int32_t nextTail;

    /* Acquire debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Validate packet buffer */
    if (pkt == NULL) {
        IOLog("EtherNet(UniN): transmit received NULL netbuf\n");
        [self releaseDebuggerLock];
        return;
    }

    /* Check if interface is running */
    if (![self isRunning]) {
        /* Interface is down - discard packet */
        nb_free(pkt);
        [self releaseDebuggerLock];
        return;
    }

    /* Service any pending packets from queue first */
    [self serviceTransmitQueue];

    /* Get current queue count */
    queueCount = [transmitQueue count];

    /* Try direct transmission if queue is empty */
    if (queueCount == 0) {
        /* Calculate next tail position */
        nextTail = txCommandTail + 1;
        if (nextTail >= txMaxCommand) {
            nextTail = 0;  /* Wrap around */
        }

        /* Check if ring has space (tail hasn't caught up to head) */
        if (nextTail != txCommandHead) {
            /* Ring has space - transmit directly */
            [self _transmitPacket:pkt];
            [self releaseDebuggerLock];
            return;
        }
    }

    /* Queue is not empty OR ring is full - check queue limits */
    queueMax = [transmitQueue maxCount];
    if (queueCount >= queueMax) {
        /* Queue is full - increment error counter */
        [networkInterface incrementOutputErrors];
    }

    /* Add packet to queue */
    [transmitQueue enqueue:pkt];

    [self releaseDebuggerLock];
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)serviceTransmitQueue
{
    netbuf_t packet;
    u_int32_t nextTail;

    /* Process all queued packets that can fit in the TX ring */
    while ([transmitQueue count] > 0) {
        /* Calculate next tail position */
        nextTail = txCommandTail + 1;
        if (nextTail >= txMaxCommand) {
            nextTail = 0;  /* Wrap around */
        }

        /* Check if ring has space (tail hasn't caught up to head) */
        if (nextTail == txCommandHead) {
            /* TX ring is full - cannot send more packets now */
            break;
        }

        /* Dequeue packet from the queue */
        packet = [transmitQueue dequeue];
        if (packet == NULL) {
            break;  /* Queue became empty */
        }

        /* Transmit the packet to hardware */
        [self _transmitPacket:packet];
    }
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (BOOL)resetAndEnable:(BOOL)enable
{
    /* Clear chip ID verification flag */
    chipIdVerified = NO;

    /* Clear any pending timeout */
    [self clearTimeout];

    /* Disable all interrupts */
    [self disableAllInterrupts];

    /* Reset the chip */
    [self _resetChip];

    if (!enable) {
        /* Disable mode - just mark interface as not running */
        [self setRunning:NO];
        return YES;
    }

    /* Enable mode - initialize and start the hardware */

    /* Initialize receive ring */
    if (![self _initRxRing]) {
        [self setRunning:NO];
        return NO;
    }

    /* Initialize transmit ring */
    if (![self _initTxRing]) {
        [self setRunning:NO];
        return NO;
    }

    /* Initialize PHY if one was found (phyId != 0xFF) */
    if (phyId != 0xFF) {
        [self miiInitializePHY:phyId];
    }

    /* Initialize chip registers */
    if (![self _initChip]) {
        [self setRunning:NO];
        return NO;
    }

    /* Enable IODevice interrupts */
    [self enableAllInterrupts];

    /* Enable adapter-specific interrupts */
    [self _enableAdapterInterrupts];

    /* Start watchdog timer (300ms interval) */
    [self setRelativeTimeout:300];

    /* Mark chip as verified and initialized */
    chipIdVerified = YES;

    /* Mark interface as running */
    [self setRunning:YES];

    return YES;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)interruptOccurred
{
    u_int32_t interruptStatus;
    u_int32_t *txWatchdogCounter;

    /* Interrupt status register (offset 0x000c) */
    #define kInterruptStatus    0x4000C

    /* Interrupt status bits */
    #define kIntrStatus_TxComplete      0x00000001  /* Transmit completed */
    #define kIntrStatus_RxComplete      0x00000010  /* Receive completed */
    #define kIntrStatus_TxRxMask        0x00000011  /* TX or RX interrupt */

    /* Acquire debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Process interrupts in a loop until all are serviced */
    do {
        /* Read interrupt status register */
        interruptStatus = ReadUniNRegister(ioBaseEnet, kInterruptStatus);

        /* Check for transmit completion interrupt */
        if ((interruptStatus & kIntrStatus_TxComplete) != 0) {
            /* Increment transmit watchdog counter (used by timeoutOccurred) */
            /* This counter tracks transmit activity for hang detection */
            txWatchdogCounter = (u_int32_t *)((u_int8_t *)self + 0x5c4);
            (*txWatchdogCounter)++;

            /* Process completed transmit packets */
            [self _transmitInterruptOccurred];

            /* Service any queued packets waiting to be transmitted */
            [self serviceTransmitQueue];
        }

        /* Check for receive completion interrupt */
        if ((interruptStatus & kIntrStatus_RxComplete) != 0) {
            /* Process received packets */
            [self _receiveInterruptOccurred];
        }

        /* Continue looping while TX or RX interrupts are pending */
    } while ((interruptStatus & kIntrStatus_TxRxMask) != 0);

    /* Re-enable all interrupts */
    [self enableAllInterrupts];

    /* Release debugger lock */
    [self releaseDebuggerLock];

    #undef kInterruptStatus
    #undef kIntrStatus_TxComplete
    #undef kIntrStatus_RxComplete
    #undef kIntrStatus_TxRxMask
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)timeoutOccurred
{
    /* Check if interface is running */
    if (![self isRunning]) {
        return;
    }

    /* Acquire debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Monitor PHY link status periodically */
    [self _monitorLinkStatus];

    /* Check for transmit timeout/watchdog */
    if (txCommandHead != txCommandTail) {
        /* There are packets in the TX ring - check for hang */

        /* Force transmit interrupt processing to clean up completed packets */
        if ([self _transmitInterruptOccurred]) {
            /* Packets were successfully processed */
        } else {
            /* No progress detected - possible transmit hang */
            /* Restart the transmitter to recover */
            [self _restartTransmitter];
        }
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];

    /* Schedule next timeout for 300ms (watchdog interval) */
    [self relativeTimeout:300];
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)enableMulticastMode
{
    /* Set multicast enabled flag */
    multicastEnabled = YES;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)disableMulticastMode
{
    /* Clear multicast enabled flag */
    multicastEnabled = NO;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)enablePromiscuousMode
{
    u_int16_t rxConfig;

    /* RX Configuration register (offset 0x6034) */
    #define kRxConfig           0x26034
    #define kRxConfig_Promisc   0x0008  /* Promiscuous mode bit */

    /* Set promiscuous mode flag */
    isPromiscuous = YES;

    /* Acquire debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Read current RX configuration register */
    rxConfig = (u_int16_t)ReadUniNRegister(ioBaseEnet, kRxConfig);

    /* Set promiscuous mode bit */
    rxConfig |= kRxConfig_Promisc;

    /* Write updated configuration back to hardware */
    WriteUniNRegister(ioBaseEnet, kRxConfig, rxConfig);

    /* Release debugger lock */
    [self releaseDebuggerLock];

    #undef kRxConfig
    #undef kRxConfig_Promisc
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)disablePromiscuousMode
{
    u_int32_t rxConfig;

    /* RX Configuration register (offset 0x6034) */
    #define kRxConfig           0x26034
    #define kRxConfig_Promisc   0x0008  /* Promiscuous mode bit */

    /* Clear promiscuous mode flag */
    isPromiscuous = NO;

    /* Acquire debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Read current RX configuration register */
    rxConfig = ReadUniNRegister(ioBaseEnet, kRxConfig);

    /* Clear promiscuous mode bit (mask 0xfff7 = ~0x0008) */
    rxConfig &= 0xFFF7;

    /* Write updated configuration back to hardware */
    WriteUniNRegister(ioBaseEnet, kRxConfig, rxConfig);

    /* Release debugger lock */
    [self releaseDebuggerLock];

    #undef kRxConfig
    #undef kRxConfig_Promisc
}

/*-------------------------------------------------------------------------
 *
 * Multicast support
 *
 *-------------------------------------------------------------------------*/

- (void)addMulticastAddress:(enet_addr_t *)addr
{
    /* Enable multicast mode when first address is added */
    multicastEnabled = YES;

    /* Acquire debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Add address to hash table */
    [self _addToHashTableMask:(u_int8_t *)addr];

    /* Update hardware hash table registers */
    [self _updateUniNHashTableMask];

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    /* Acquire debugger lock for thread safety */
    [self reserveDebuggerLock];

    /* Remove address from hash table */
    [self _removeFromHashTableMask:(u_int8_t *)addr];

    /* Update hardware hash table registers */
    [self _updateUniNHashTableMask];

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*-------------------------------------------------------------------------
 *
 * Kernel debugger support
 *
 *-------------------------------------------------------------------------*/

- (void)sendPacket:(void *)pkt length:(unsigned int)pkt_len
{
    /* Public wrapper for kernel debugger packet transmission */
    [self _sendPacket:pkt length:pkt_len];
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)receivePacket:(void *)pkt length:(unsigned int *)pkt_len timeout:(unsigned int)timeout
{
    /* Public wrapper for kernel debugger packet reception */
    [self _receivePacket:pkt length:pkt_len timeout:timeout];
}

/*-------------------------------------------------------------------------
 *
 * Power management support
 *
 *-------------------------------------------------------------------------*/

- (IOReturn)getPowerState:(PMPowerState *)state_p
{
    /* Power state query is not supported */
    return IO_R_UNSUPPORTED;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (IOReturn)getPowerManagement:(PMPowerManagementState *)state_p
{
    /* Power management state query is not supported */
    return IO_R_UNSUPPORTED;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (IOReturn)setPowerState:(PMPowerState)state
{
    /* Handle power state transitions */
    if (state == 3) {
        /* Power state 3 requires chip reset */
        /* Clear chip ID verification flag before reset */
        chipIdVerified = NO;

        /* Perform chip reset */
        [self _resetChip];

        return IO_R_SUCCESS;
    }

    /* Other power states are not supported */
    return IO_R_UNSUPPORTED;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{
    /* Power management state changes are not supported */
    return IO_R_UNSUPPORTED;
}

/*-------------------------------------------------------------------------
 *
 * Transmit queue support
 *
 *-------------------------------------------------------------------------*/

- (int)transmitQueueSize
{
    /* Return maximum transmit queue size (256 packets) */
    return 0x100;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (int)transmitQueueCount
{
    /* Return current number of packets in transmit queue */
    return [transmitQueue count];
}

@end
