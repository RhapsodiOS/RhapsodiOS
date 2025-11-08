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
 * Implementation for hardware dependent (relatively) code
 * for the UniN Ethernet controller.
 *
 * HISTORY
 *
 */
#import "UniNEnetPrivate.h"
#import <mach/vm_param.h>			// page alignment macros

extern void 			*kernel_map;
extern kern_return_t		kmem_alloc_wired();
extern vm_size_t		page_mask;

/*
 * Byte swap utility functions (also defined in UniNEnet.m)
 */
static inline u_int32_t OSSwapInt32(u_int32_t data)
{
    return (data << 24) | ((data & 0xFF00) << 8) | ((data >> 8) & 0xFF00) | (data >> 24);
}

static inline u_int16_t OSSwapInt16(u_int16_t data)
{
    return (data << 8) | (data >> 8);
}

/*
 * CRC-32 polynomial for Ethernet multicast address hashing
 */
#define ENET_CRCPOLY 0x04c11db7

/*
 * Compute CRC-32 over a 16-bit value
 */
static u_int32_t crc416(u_int32_t current, u_int16_t nxtval)
{
    register unsigned int counter;
    register int highCRCBitSet, lowDataBitSet;

    /* Compute CRC-32 over each bit of the 16-bit value */
    for (counter = 0; counter < 16; counter++)
    {
        /* Check if high-order bit of CRC is set */
        highCRCBitSet = current & 0x80000000;

        /* Shift CRC left by 1 bit */
        current = current << 1;

        /* Check if current data bit is set */
        lowDataBitSet = nxtval & 1;
        nxtval = nxtval >> 1;

        /* XOR if high CRC bit differs from low data bit */
        if (highCRCBitSet ^ lowDataBitSet)
            current = current ^ ENET_CRCPOLY;
    }
    return current;
}

/*
 * Compute Ethernet CRC-32 over a MAC address
 */
static u_int32_t ether_crc(u_int16_t *address)
{
    register u_int32_t crc;

    crc = crc416(0xffffffff, address[0]);  /* Address bits 15-0 */
    crc = crc416(crc, address[1]);          /* Address bits 31-16 */
    crc = crc416(crc, address[2]);          /* Address bits 47-32 */

    return crc;
}

/*
 * Compute hash table index from MAC address
 * Takes the low 8 bits of CRC, reverses them, then inverts (0-255 range)
 */
static u_int32_t hashIndex(u_int8_t *addr)
{
    u_int32_t crc;
    u_int32_t index = 0;
    int i;

    /* Compute CRC-32 over MAC address */
    crc = ether_crc((u_int16_t *)addr);

    /* Take low 8 bits */
    crc = crc & 0xFF;

    /* Reverse the bits */
    for (i = 0; i < 8; i++)
    {
        index = index >> 1 | (crc & 0x80);
        crc = crc << 1;
    }

    /* Invert to get final index (0-255) */
    index = index ^ 0xFF;

    return index;
}

@implementation UniNEnet (Private)

/*
 * Private functions
 */

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (BOOL)_allocateMemory
{
    kern_return_t result;
    u_int32_t allocSize;
    u_int32_t numPages;
    u_int32_t i;
    u_int32_t physAddr;
    u_int32_t physAddrCheck;
    u_int32_t vAddr;

    /* Calculate allocation size: round 0x1000 (4KB) to page boundary */
    allocSize = (page_mask + 0x1000) & ~page_mask;

    /* Allocate wired kernel memory if not already allocated */
    if (dmaCommands == NULL) {
        result = kmem_alloc_wired(kernel_map, (vm_offset_t *)&dmaCommands, allocSize);
        if (result != KERN_SUCCESS) {
            IOLog("Ethernet(UniN): Cant allocate channel dma commands\n");
            return NO;
        }
    }

    /* Verify allocated memory is physically contiguous */
    numPages = (allocSize - page_size) / page_size;

    /* Get physical address of first page */
    IOPhysicalFromVirtual(kernel_map, (vm_address_t)dmaCommands, &physAddr);

    /* Check each subsequent page for physical contiguity */
    vAddr = (u_int32_t)dmaCommands;
    for (i = 0; i < numPages; i++) {
        IOPhysicalFromVirtual(kernel_map, (vm_address_t)vAddr, &physAddrCheck);

        /* Verify physical address is contiguous */
        if (physAddrCheck != (physAddr + (i * page_size))) {
            IOLog("Ethernet(UniN): Cant allocate contiguous memory for dma commands\n");
            return NO;
        }

        vAddr += page_size;
    }

    /* Set up ring sizes (128 entries each) */
    rxMaxCommand = 0x80;  /* 128 RX descriptors */
    txMaxCommand = 0x80;  /* 128 TX descriptors */

    /* Partition DMA buffer between RX and TX rings */
    rxDMACommands = (enet_dma_cmd_t *)dmaCommands;           /* RX at start */
    txDMACommands = (enet_txdma_cmd_t *)((u_int32_t)dmaCommands + 0x800);  /* TX at +2KB offset */

    return YES;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (BOOL)_initTxRing
{
    IOReturn result;

    /* Zero out the entire TX DMA command buffer */
    bzero(txDMACommands, txMaxCommand * sizeof(enet_txdma_cmd_t));

    /* Initialize ring head and tail pointers */
    txCommandHead = 0;
    txCommandTail = 0;

    /* Free existing transmit queue if present */
    if (transmitQueue != nil) {
        [transmitQueue free];
    }

    /* Allocate new transmit queue with max count of 256 packets */
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:0x100];
    if (transmitQueue == nil) {
        IOLog("Ethernet(UniN): Cant allocate transmit queue\n");
        return NO;
    }

    /* Get physical address of TX DMA command buffer */
    result = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)txDMACommands,
                                    (u_int32_t *)&txDMACommandsPhys);
    if (result != IO_R_SUCCESS) {
        IOLog("Ethernet(UniN): Bad dma command buf - %08x\n", (u_int32_t)txDMACommands);
        return NO;
    }

    return YES;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (BOOL)_initRxRing
{
    IOReturn result;
    u_int32_t i;
    netbuf_t packet;
    enet_dma_cmd_t *desc;

    /* Zero out the entire RX DMA command buffer */
    bzero(rxDMACommands, rxMaxCommand * sizeof(enet_dma_cmd_t));

    /* Get physical address of RX DMA command buffer */
    result = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)rxDMACommands,
                                    (u_int32_t *)&rxDMACommandsPhys);
    if (result != IO_R_SUCCESS) {
        IOLog("Ethernet(UniN): Bad dma command buf - %08x\n", (u_int32_t)rxDMACommands);
        return NO;
    }

    /* Allocate netbufs for all RX descriptors and update descriptors */
    for (i = 0; i < rxMaxCommand; i++) {
        /* Allocate netbuf if not already present */
        if (rxNetbuf[i] == NULL) {
            packet = [self allocateNetbuf];
            if (packet == NULL) {
                IOLog("Ethernet(UniN): allocateNetbuf returned NULL in _initRxRing\n");
                return NO;
            }
            rxNetbuf[i] = packet;
        }

        /* Get descriptor pointer */
        desc = &rxDMACommands[i];

        /* Update descriptor with netbuf physical address */
        if (![self _updateDescriptorFromNetBuf:rxNetbuf[i] Desc:desc ReceiveFlag:YES]) {
            IOLog("Ethernet(UniN): cant map Netbuf to physical memory in _initRxRing\n");
            return NO;
        }
    }

    /* Initialize ring head and tail pointers */
    rxCommandHead = 0;
    rxCommandTail = i - 4;  /* Tail is count - 4 */

    return YES;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (BOOL)_initChip
{
    u_int32_t regValue;
    u_int32_t ringSize;
    u_int32_t i;
    u_int16_t randomSeed;
    ns_time_t timestamp;

    /* Perform chip reset sequence */
    WriteUniNRegister(ioBaseEnet, kSoftwareReset1, 4);  /* Reset TX */
    WriteUniNRegister(ioBaseEnet, kPCSMIIControl, 0x41);  /* PCS config */
    WriteUniNRegister(ioBaseEnet, kSoftwareReset2, 3);  /* Reset RX */

    /* Configure MAC control */
    WriteUniNRegister(ioBaseEnet, kMacControl, 0x1BF0);

    /* Configure PCS/SerDes */
    WriteUniNRegister(ioBaseEnet, kPCSMIIControl, 2);

    /* Clear/set interrupt masks */
    WriteUniNRegister(ioBaseEnet, kMacStatus, 0xFFFFFFFF);  /* Clear status */
    WriteUniNRegister(ioBaseEnet, kTxMask, 0xFFFF);  /* Mask all TX interrupts */
    WriteUniNRegister(ioBaseEnet, kRxMask, 0xFFFF);  /* Mask all RX interrupts */
    WriteUniNRegister(ioBaseEnet, kMacControlMask, 0xFF);  /* Mask MAC interrupts */

    /* Configure PCS MII status */
    WriteUniNRegister(ioBaseEnet, kPCSMIIStatus, 0x42);

    /* Configure TX/RX parameters */
    WriteUniNRegister(ioBaseEnet, kTxPauseQuanta, 0);  /* TX pause quanta */
    WriteUniNRegister(ioBaseEnet, kMinFrameSize, 8);  /* Min frame size */
    WriteUniNRegister(ioBaseEnet, kMaxBurst, 4);  /* Max burst */
    WriteUniNRegister(ioBaseEnet, kTxFIFOThresh, 0x40);  /* TX FIFO threshold */
    WriteUniNRegister(ioBaseEnet, kRxFIFOThresh, 0x40);  /* RX FIFO threshold */
    WriteUniNRegister(ioBaseEnet, kRxPauseThresh, 0x5EE);  /* RX pause threshold */
    WriteUniNRegister(ioBaseEnet, kRxFIFOSize, 7);  /* RX FIFO size */
    WriteUniNRegister(ioBaseEnet, kAttemptLimit, 4);  /* TX attempt limit */
    WriteUniNRegister(ioBaseEnet, kSlotTime, 0x10);  /* Slot time */
    WriteUniNRegister(ioBaseEnet, kMinInterFrameGap, 0x8808);  /* Min IFG */

    /* Program MAC address (written in reverse order: bytes 4,5 then 2,3 then 0,1) */
    WriteUniNRegister(ioBaseEnet, kMacAddr0, *(u_int16_t *)&myAddress.ea_byte[4]);
    WriteUniNRegister(ioBaseEnet, kMacAddr1, *(u_int16_t *)&myAddress.ea_byte[2]);
    WriteUniNRegister(ioBaseEnet, kMacAddr2, *(u_int16_t *)&myAddress.ea_byte[0]);

    /* Clear address filters */
    WriteUniNRegister(ioBaseEnet, kAddrFilter0_0, 0);
    WriteUniNRegister(ioBaseEnet, kAddrFilter0_1, 0);
    WriteUniNRegister(ioBaseEnet, kAddrFilter1_0, 0);
    WriteUniNRegister(ioBaseEnet, kAddrFilter1_1, 0);
    WriteUniNRegister(ioBaseEnet, kAddrFilter2_0, 0);
    WriteUniNRegister(ioBaseEnet, kAddrFilter2_1, 0);

    /* Configure address filter 2/2 mask and collision counters */
    WriteUniNRegister(ioBaseEnet, kAddrFilter2_2Mask, 1);
    WriteUniNRegister(ioBaseEnet, kNormalCollCnt, 0xC200);  /* Normal collision */
    WriteUniNRegister(ioBaseEnet, kFirstCollCnt, 0x180);  /* First collision */
    WriteUniNRegister(ioBaseEnet, kExcessCollCnt, 0);  /* Excess collision */
    WriteUniNRegister(ioBaseEnet, kLateCollCnt, 0);  /* Late collision */

    /* Clear hash table (16 words = 64 bytes = 512 bits) */
    for (i = 0; i < 16; i++) {
        WriteUniNRegister(ioBaseEnet, kHashTable0 + (i * 4), 0);
    }

    /* Clear additional interrupt registers (0x26100 to 0x26128) */
    for (i = 0x26100; i <= 0x26128; i += 4) {
        WriteUniNRegister(ioBaseEnet, i, 0);
    }

    /* Get timestamp and use low 16 bits as random seed */
    IOGetTimestamp(&timestamp);
    randomSeed = (u_int16_t)(timestamp & 0xFFFF);
    WriteUniNRegister(ioBaseEnet, kRandomSeed, randomSeed);

    /* Configure TX DMA */
    WriteUniNRegister(ioBaseEnet, kTxDescBase, txDMACommandsPhys);
    WriteUniNRegister(ioBaseEnet, kTxDescBaseHi, 0);  /* Upper 32 bits (always 0 on 32-bit) */

    /* Calculate TX ring size encoding (log2 of ring size) */
    ringSize = 0;
    regValue = txMaxCommand;
    while ((regValue > 1) && (ringSize < 13)) {
        ringSize++;
        regValue >>= 1;
    }
    WriteUniNRegister(ioBaseEnet, kTxConfig, (ringSize << 1) | 0x1FFC00);

    /* Initialize TX DMA configuration and set half duplex mode */
    WriteUniNRegister(ioBaseEnet, kTxDmaConfig, 0);
    [self _setDuplexMode:NO];  /* Start in half duplex */

    /* Configure RX DMA */
    WriteUniNRegister(ioBaseEnet, kRxDescBase, rxDMACommandsPhys);
    WriteUniNRegister(ioBaseEnet, kRxDescBaseHi, 0);  /* Upper 32 bits (always 0) */
    WriteUniNRegister(ioBaseEnet, kRxKick, 0x7C);  /* Initial kick value (124) */

    /* Calculate RX ring size encoding */
    ringSize = 0;
    regValue = rxMaxCommand;
    while ((regValue > 1) && (ringSize < 13)) {
        ringSize++;
        regValue >>= 1;
    }
    WriteUniNRegister(ioBaseEnet, kRxConfig, (ringSize << 1) | 0x1000000);

    /* Initialize RX DMA configuration */
    WriteUniNRegister(ioBaseEnet, kRxDmaConfig, 0);

    /* Configure RX interrupt blanking */
    regValue = ReadUniNRegister(ioBaseEnet, kRxBlankTime);
    WriteUniNRegister(ioBaseEnet, kRxBlankConfig,
                      ((regValue - 0x47) << 12) | (regValue - 0x2F));

    /* Configure RX pause time based on system clock */
    regValue = ReadUniNRegister(ioBaseEnet, kSystemClock);
    if ((regValue & 8) != 0) {
        /* 66 MHz clock */
        regValue = 0xF;
    } else {
        /* 33 MHz clock */
        regValue = 0x1E;
    }
    /* Calculate: (250000 / (regValue * 2048)) << 12 | 5 */
    WriteUniNRegister(ioBaseEnet, kRxPauseTime,
                      ((250000 / (regValue << 11)) << 12) | 5);

    return YES;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_resetChip
{
    u_int32_t regValue;
    u_int16_t phyReg;
    BOOL phyFound;

    // Perform software reset by writing 3 to reset register
    WriteUniNRegister(ioBaseEnet, kSoftwareReset, 3);

    // Poll until reset completes (bits 0-1 clear)
    do {
        regValue = ReadUniNRegister(ioBaseEnet, kSoftwareReset);
    } while ((regValue & 3) != 0);

    // If PHY hasn't been found yet (phyId == 0xFF)
    if (phyId == 0xFF) {
        // Try to locate PHY on MII bus
        phyFound = [self miiFindPHY:&phyId];

        if (phyFound) {
            // Reset the PHY
            [self miiResetPHY:phyId];

            // Read PHY manufacturer/model ID from MII registers 2 and 3
            [self miiReadWord:(u_int16_t *)&phyMfgID reg:MII_ID0 phy:phyId];
            [self miiReadWord:(u_int16_t *)((u_int32_t)&phyMfgID + 2) reg:MII_ID1 phy:phyId];

            // Check if this is a Broadcom BCM5400 PHY (ID 0x0020604x)
            if ((phyMfgID & 0xFFFFFFF0) == 0x00206040) {
                // BCM5400-specific initialization sequence

                // Read register 0x18, set bit 2, write back
                [self miiReadWord:&phyReg reg:0x18 phy:phyId];
                phyReg |= 0x0004;
                [self miiWriteWord:phyReg reg:0x18 phy:phyId];

                // Read register 9, set bit 0x200, write back
                [self miiReadWord:&phyReg reg:9 phy:phyId];
                phyReg |= 0x0200;
                [self miiWriteWord:phyReg reg:9 phy:phyId];

                // Small delay for PHY reconfiguration
                IODelay(100);

                // Reset secondary PHY at address 0x1F (BCM5400 has dual PHY)
                [self miiResetPHY:0x1F];

                // Read register 0x1E from secondary PHY, set bit 1, write back
                [self miiReadWord:&phyReg reg:0x1E phy:0x1F];
                phyReg |= 0x0002;
                [self miiWriteWord:phyReg reg:0x1E phy:0x1F];

                // Read register 0x18 from main PHY, clear bit 2, write back
                [self miiReadWord:&phyReg reg:0x18 phy:phyId];
                phyReg &= 0xFFFB;
                [self miiWriteWord:phyReg reg:0x18 phy:phyId];
            }
        }
    }
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_disableAdapterInterrupts
{
    /* Mask all interrupts by writing all 1's to interrupt mask register */
    WriteUniNRegister(ioBaseEnet, kMacIntMask, 0xFFFFFFFF);
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_enableAdapterInterrupts
{
    u_int32_t intMask;

    /* Read current interrupt mask */
    intMask = ReadUniNRegister(ioBaseEnet, kMacIntMask);

    /* Clear specific interrupt mask bits to enable interrupts */
    /* Keeps bits 0x00008011 masked, unmasks all others */
    intMask &= 0xFFFF7FEE;

    /* Write back the modified mask */
    WriteUniNRegister(ioBaseEnet, kMacIntMask, intMask);
}

/*-------------------------------------------------------------------------
 *
 * Set full/half duplex mode
 *
 *-------------------------------------------------------------------------*/

- (void)_setDuplexMode:(BOOL)duplexMode
{
    u_int16_t txDmaConfig;
    u_int16_t macConfig;
    u_int32_t status;

    // Store duplex mode
    isFullDuplex = duplexMode;

    // Read current TX DMA configuration
    txDmaConfig = (u_int16_t)ReadUniNRegister(ioBaseEnet, kTxDmaConfig);

    // Disable TX DMA temporarily
    WriteUniNRegister(ioBaseEnet, kTxDmaConfig, txDmaConfig & 0xFFFE);

    // Wait for TX DMA to stop (bit 0 to clear)
    do {
        status = ReadUniNRegister(ioBaseEnet, kTxDmaConfig);
    } while ((status & 1) != 0);

    // Read MAC configuration
    macConfig = (u_int16_t)ReadUniNRegister(ioBaseEnet, kMacConfig);

    if (duplexMode == NO) {
        // Half duplex mode
        txDmaConfig &= 0xFFF9;  // Clear bits 1 and 2
        macConfig |= 0x0004;    // Set bit 2
    } else {
        // Full duplex mode
        txDmaConfig |= 0x0006;  // Set bits 1 and 2
        macConfig &= 0xFFFB;    // Clear bit 2
    }

    // Write back configurations
    WriteUniNRegister(ioBaseEnet, kTxDmaConfig, txDmaConfig);
    WriteUniNRegister(ioBaseEnet, kMacConfig, macConfig);
}

/*-------------------------------------------------------------------------
 *
 * Start the chip by enabling all major components
 *
 *-------------------------------------------------------------------------*/

- (void)_startChip
{
    u_int32_t regValue;

    // Enable MAC transmitter
    regValue = ReadUniNRegister(ioBaseEnet, kTxConfig);
    WriteUniNRegister(ioBaseEnet, kTxConfig, regValue | kEnableBit);
    IOSleep(20);  // Allow time for transmitter to start

    // Enable MAC receiver
    regValue = ReadUniNRegister(ioBaseEnet, kRxConfig);
    WriteUniNRegister(ioBaseEnet, kRxConfig, regValue | kEnableBit);
    IOSleep(20);  // Allow time for receiver to start

    // Enable transmit DMA
    regValue = ReadUniNRegister(ioBaseEnet, kTxDmaConfig);
    WriteUniNRegister(ioBaseEnet, kTxDmaConfig, regValue | kEnableBit);
    IOSleep(20);  // Allow time for DMA to start

    // Enable receive DMA
    regValue = ReadUniNRegister(ioBaseEnet, kRxDmaConfig);
    WriteUniNRegister(ioBaseEnet, kRxDmaConfig, regValue | kEnableBit);
}

/*-------------------------------------------------------------------------
 *
 * Stop the chip by disabling all major components
 *
 *-------------------------------------------------------------------------*/

- (void)_stopChip
{
    u_int32_t regValue;

    // Disable MAC transmitter
    regValue = ReadUniNRegister(ioBaseEnet, kTxConfig);
    WriteUniNRegister(ioBaseEnet, kTxConfig, regValue & kDisableBit);
    IOSleep(20);  // Allow time for transmitter to stop

    // Disable MAC receiver
    regValue = ReadUniNRegister(ioBaseEnet, kRxConfig);
    WriteUniNRegister(ioBaseEnet, kRxConfig, regValue & kDisableBit);
    IOSleep(20);  // Allow time for receiver to stop

    // Disable transmit DMA
    regValue = ReadUniNRegister(ioBaseEnet, kTxDmaConfig);
    WriteUniNRegister(ioBaseEnet, kTxDmaConfig, regValue & kDisableBit);
    IOSleep(20);  // Allow time for DMA to stop

    // Disable receive DMA
    regValue = ReadUniNRegister(ioBaseEnet, kRxDmaConfig);
    WriteUniNRegister(ioBaseEnet, kRxDmaConfig, regValue & kDisableBit);
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_restartTransmitter
{
    // No implementation needed for UniN Ethernet
    // Hardware automatically restarts transmitter as needed
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_restartReceiver
{
    // No implementation needed for UniN Ethernet
    // Hardware automatically restarts receiver as needed
}

/*-------------------------------------------------------------------------
 *
 * Stop transmit DMA (currently no-op for UniN)
 *
 *-------------------------------------------------------------------------*/

- (void)_stopTransmitDMA
{
    // UniN Ethernet controller doesn't require explicit transmit DMA stop
    // Hardware handles this automatically
}

/*-------------------------------------------------------------------------
 *
 * Stop receive DMA (currently no-op for UniN)
 *
 *-------------------------------------------------------------------------*/

- (void)_stopReceiveDMA
{
    // UniN Ethernet controller doesn't require explicit receive DMA stop
    // Hardware handles this automatically
}

/*-------------------------------------------------------------------------
 *
 * Transmit a packet
 *
 *-------------------------------------------------------------------------*/

- (BOOL)_transmitPacket:(netbuf_t)packet
{
    u_int32_t next;

    // Calculate next transmit ring index
    next = txCommandTail + 1;
    if (next >= txMaxCommand) {
        next = 0;
    }

    // Check if transmit ring is full
    if (next == txCommandHead) {
        IOLog("Ethernet(UniN): Freeing transmit packet eh?\n\r");
        nb_free(packet);
        return NO;
    }

    // Update the descriptor for this packet
    [self _updateDescriptorFromNetBuf:packet
          Desc:&txDMACommands[txCommandTail]
          ReceiveFlag:NO];

    // Store the netbuf pointer for later cleanup
    txNetbuf[txCommandTail] = packet;

    // Update tail pointer to next position
    txCommandTail = next;

    // Kick the transmit DMA engine
    WriteUniNRegister(ioBaseEnet, kTxKick, 0);

    return YES;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (BOOL)_receiveInterruptOccurred
{
    /* Call main receive packet processing routine */
    [self _receivePackets:NO];
    return YES;
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (BOOL)_receivePackets:(BOOL)fDebugger
{
    enet_dma_cmd_t *desc;
    netbuf_t packet;
    netbuf_t newPacket;
    u_int32_t currentIndex;
    u_int32_t nextIndex;
    u_int32_t lastIndex = 0xFFFFFFFF;
    u_int16_t status;
    u_int16_t packetLength;
    u_int32_t statusWord;
    BOOL packetProcessed;
    BOOL packetError;
    void *pktData;
    u_int32_t actualSize;
    u_int32_t rxErrors, rxCRCErrors;

    currentIndex = rxCommandHead;

    /* Process receive descriptors until we find one still owned by hardware */
    do {
        do {
            packetError = NO;
            packetProcessed = NO;

            /* Get pointer to current descriptor */
            desc = &rxDMACommands[currentIndex];

            /* Read descriptor status word (offset +2) */
            status = OSSwapInt16(desc->desc_seg[0].address);

            /* Check ownership bit (bit 7 of high byte) */
            if ((status & 0x80) != 0) {
                /* Hardware still owns this descriptor - we're done */
                goto receiveComplete;
            }

            /* Extract packet length (lower 15 bits) */
            packetLength = status & 0x7FFF;

            /* Read status flags from descriptor (offset +4, shifted left 24 bits in original code) */
            statusWord = OSSwapInt32(desc->desc_seg[0].cmdDep);

            /* Validate packet length (60-1514 bytes) and check error bit */
            if ((packetLength < 60) || (packetLength > 1514) || ((statusWord & 0x40000000) != 0)) {
                packetError = YES;
                [networkInterface incrementInputErrors];
            }

            /* Get current receive buffer */
            packet = rxNetbuf[currentIndex];

            if (packetError) {
resetDescriptor:
                /* Reset descriptor for reuse - set ownership bit and clear status */
                desc->desc_seg[0].address = OSSwapInt16(0xF085);  /* 0x85F0 swapped */
                desc->desc_seg[0].cmdDep = 0;
            }
            else {
                /* Check for unwanted multicast packet (if not in promiscuous mode) */
                if ((isPromiscuous == NO) && ((statusWord & 0x10000000) != 0)) {
                    /* Multicast bit is set - check if we want this packet */
                    pktData = nb_map(packet);
                    if ([super isUnwantedMulticastPacket:pktData]) {
                        packetError = YES;
                    }
                }

                if (packetError)
                    goto resetDescriptor;

                /* Allocate new netbuf for the descriptor ring */
                newPacket = [self allocateNetbuf];
                if (newPacket == NULL) {
                    packetError = YES;
                    [networkInterface incrementInputErrors];
                    goto resetDescriptor;
                }

                /* Replace the current netbuf with new one */
                rxNetbuf[currentIndex] = newPacket;

                /* Update descriptor with new netbuf */
                if (![self _updateDescriptorFromNetBuf:newPacket Desc:desc ReceiveFlag:YES]) {
                    IOLog("Ethernet(UniN): _updateDescriptorFromNetBuf failed for receive\n");
                }

                /* Adjust received packet size to actual length */
                actualSize = nb_size(packet);
                nb_shrink_bot(packet, actualSize - packetLength);

                packetProcessed = YES;
            }

            /* Advance to next descriptor */
            nextIndex = currentIndex + 1;
            if (nextIndex >= rxMaxCommand) {
                nextIndex = 0;
            }

            lastIndex = currentIndex;
            currentIndex = nextIndex;

        } while (!packetProcessed);

        /* Pass packet to debugger or network stack */
        if (fDebugger) {
            [self _packetToDebugger:packet];
            goto receiveComplete;
        }

        /* Pass packet to network stack */
        [networkInterface handleInputPacket:packet extra:0];

    } while (1);

receiveComplete:
    /* Update head/tail pointers if we processed any packets */
    if (lastIndex != 0xFFFFFFFF) {
        rxCommandTail = lastIndex;
        rxCommandHead = currentIndex;
    }

    /* Kick the RX DMA with the tail pointer (aligned to 4-byte boundary) */
    WriteUniNRegister(ioBaseEnet, kRxKick, rxCommandTail & 0xFFFFFFFC);

    /* Read and clear error counters */
    rxCRCErrors = ReadUniNRegister(ioBaseEnet, kRxMacCRCErrors);
    rxErrors = ReadUniNRegister(ioBaseEnet, kRxMacCodeErrors);
    WriteUniNRegister(ioBaseEnet, kRxMacCRCErrors, 0);
    WriteUniNRegister(ioBaseEnet, kRxMacCodeErrors, 0);

    /* Update error statistics */
    [networkInterface incrementInputErrorsBy:(rxCRCErrors + rxErrors)];

    return YES;
}

/*-------------------------------------------------------------------------
 *
 * Handle transmit completion interrupts
 *
 *-------------------------------------------------------------------------*/

- (BOOL)_transmitInterruptOccurred
{
    u_int32_t completionIndex;

    // Read hardware's transmit completion index
    completionIndex = ReadUniNRegister(ioBaseEnet, kTxCompletion);

    // Process all completed transmit descriptors
    while (completionIndex != txCommandHead)
    {
        // Increment output packet statistics
        [networkInterface incrementOutputPackets];

        // Free the transmitted netbuf
        if (txNetbuf[txCommandHead] != NULL)
        {
            nb_free(txNetbuf[txCommandHead]);
            txNetbuf[txCommandHead] = NULL;
        }

        // Move to next descriptor
        txCommandHead++;
        if (txCommandHead >= txMaxCommand)
        {
            txCommandHead = 0;  // Wrap around
        }

        // Re-read completion index in case more completed
        completionIndex = ReadUniNRegister(ioBaseEnet, kTxCompletion);
    }

    return YES;
}

/*-------------------------------------------------------------------------
 *
 * Update DMA descriptor from network buffer
 *
 *-------------------------------------------------------------------------*/

- (BOOL)_updateDescriptorFromNetBuf:(netbuf_t)nb Desc:(enet_dma_cmd_t *)desc ReceiveFlag:(BOOL)isReceive
{
    IOReturn result;
    u_int32_t size;
    u_int32_t vaddr;
    u_int32_t paddr;
    static u_int32_t txInterruptCounter = 0;

    // Determine buffer size
    if (isReceive) {
        size = 0x5F0;  // Fixed receive buffer size (1520 bytes)
    } else {
        size = nb_size(nb);  // Transmit uses actual packet size
    }

    // Get virtual address of network buffer
    vaddr = (u_int32_t)nb_map(nb);

    // Convert to physical address
    result = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)vaddr, &paddr);
    if (result != IO_R_SUCCESS) {
        return NO;
    }

    // Check if buffer crosses page boundary
    if ((vaddr & ~page_mask) != ((vaddr + size - 1) & ~page_mask)) {
        IOLog("Ethernet(UniN): Network buffer not contiguous\n\r");
        return NO;
    }

    // Build descriptor based on transmit or receive
    if (isReceive) {
        // Receive descriptor format
        // Word 0 (command): [size:16][flags:16] - flags include 0x80 for receive
        // Word 1: reserved (0)
        // Word 2: physical address
        desc->desc_seg[0].operation = OSSwapInt16((u_int16_t)size) | 0x0080;
        desc->desc_seg[0].address = 0;
        desc->desc_seg[0].cmdDep = OSSwapInt32(paddr);
    } else {
        // Transmit descriptor format
        // Word 0 (command): [flags:16][size:16] - flags include 0xC000 for transmit
        // Word 1: interrupt control (0x01000000 every 64 packets)
        // Word 2: physical address
        u_int32_t command = (size & 0xFFFF) | 0xC0000000;
        desc->desc_seg[0].operation = OSSwapInt32(command);

        // Generate interrupt every 64 packets
        txInterruptCounter = (txInterruptCounter + 1) & 0x3F;
        if (txInterruptCounter == 0) {
            desc->desc_seg[0].address = 0x01000000;
        } else {
            desc->desc_seg[0].address = 0;
        }

        desc->desc_seg[0].cmdDep = OSSwapInt32(paddr);
    }

    return YES;
}

/*-------------------------------------------------------------------------
 *
 * Kernel Debugger - Send packet in polled mode
 *
 *-------------------------------------------------------------------------*/

- (void)_sendPacket:(void *)pkt length:(unsigned int)pkt_len
{
    void *bufPtr;
    int bufSize;
    int timeout;

    // Only send if chip is running
    if (!resetAndEnabled) {
        return;
    }

    // Disable interrupts for polled operation
    [self disableAllInterrupts];

    // Wait for transmit ring to be empty (poll for completions)
    timeout = 1000;  // 1 second timeout
    while (txCommandHead != txCommandTail && timeout > 0)
    {
        [self _transmitInterruptOccurred];
        IOSleep(1);
        timeout--;
    }

    if (timeout <= 0) {
        IOLog("Ethernet(UniN): Polled transmit timeout - 1\n\r");
        [self enableAllInterrupts];
        return;
    }

    // Allocate netbuf for debugger packet
    debuggerPkt = [self allocateNetbuf];
    if (debuggerPkt == NULL) {
        [self enableAllInterrupts];
        return;
    }

    // Get buffer pointer and copy packet data
    bufPtr = nb_map(debuggerPkt);
    bcopy(pkt, bufPtr, pkt_len);

    // Adjust netbuf size to match packet length
    bufSize = nb_size(debuggerPkt);
    nb_shrink_bot(debuggerPkt, bufSize - pkt_len);

    // Transmit the packet
    [self _transmitPacket:debuggerPkt];

    // Poll for transmission complete
    timeout = 1000;  // 1 second timeout
    while (txCommandHead != txCommandTail && timeout > 0)
    {
        [self _transmitInterruptOccurred];
        IOSleep(1);
        timeout--;
    }

    if (timeout <= 0) {
        IOLog("Ethernet(UniN): Polled transmit timeout - 2\n\r");
    }

    // Re-enable interrupts
    [self enableAllInterrupts];
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_receivePacket:(void *)pkt length:(unsigned int *)pkt_len timeout:(unsigned int)timeout
{
    ns_time_t startTime, currentTime;
    u_int64_t elapsedTime;
    u_int32_t elapsedMs;

    /* Initialize return value */
    *pkt_len = 0;

    /* Only receive if adapter is enabled */
    if (!resetAndEnabled)
        return;

    /* Disable interrupts for polled mode */
    [self disableAllInterrupts];

    /* Set up debugger receive buffer */
    debuggerBuf = pkt;
    rxDebuggerBytes = 0;

    /* Get start time */
    IOGetTimestamp(&startTime);

    /* Poll for packets until timeout or packet received */
    do {
        /* Process receive packets in debugger mode */
        [self _receivePackets:YES];

        /* Get current time */
        IOGetTimestamp(&currentTime);

        /* Calculate elapsed time in microseconds */
        elapsedTime = currentTime - startTime;

        /* Convert to milliseconds */
        elapsedMs = (u_int32_t)(elapsedTime / 1000000);

        /* Check if packet was received */
        if (rxDebuggerBytes != 0)
            break;

    } while (elapsedMs < timeout);

    /* Return received packet length */
    *pkt_len = rxDebuggerBytes;

    /* Re-enable interrupts */
    [self enableAllInterrupts];
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_packetToDebugger:(netbuf_t)packet
{
    void *packetData;

    /* Get packet size */
    rxDebuggerBytes = nb_size(packet);

    /* Get pointer to packet data */
    packetData = nb_map(packet);

    /* Copy packet to debugger buffer */
    bcopy(packetData, debuggerBuf, rxDebuggerBytes);

    /* Free the netbuf */
    nb_free(packet);
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_sendDummyPacket
{
    u_int8_t dummyPacket[64];

    // Zero the entire packet buffer
    bzero(dummyPacket, sizeof(dummyPacket));

    // Set destination MAC address (first 6 bytes) to our own address
    dummyPacket[0] = myAddress.ea_byte[0];
    dummyPacket[1] = myAddress.ea_byte[1];
    dummyPacket[2] = myAddress.ea_byte[2];
    dummyPacket[3] = myAddress.ea_byte[3];
    dummyPacket[4] = myAddress.ea_byte[4];
    dummyPacket[5] = myAddress.ea_byte[5];

    // Set source MAC address (next 6 bytes) to our own address
    dummyPacket[6] = myAddress.ea_byte[0];
    dummyPacket[7] = myAddress.ea_byte[1];
    dummyPacket[8] = myAddress.ea_byte[2];
    dummyPacket[9] = myAddress.ea_byte[3];
    dummyPacket[10] = myAddress.ea_byte[4];
    dummyPacket[11] = myAddress.ea_byte[5];

    // Send the dummy packet using polled mode
    [self _sendPacket:dummyPacket length:sizeof(dummyPacket)];
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_getStationAddress:(enet_addr_t *)ea
{
    id deviceDesc;
    id propTable;
    IOReturn result;
    void *propertyData;
    int propertyLength[1];
    int i;

    /* Get device description from IOTreeDevice */
    deviceDesc = [self deviceDescription];

    /* Get property table */
    propTable = [deviceDesc propertyTable];

    /* Read "local-mac-address" property from device tree */
    result = [propTable getProperty:"local-mac-address"
                             flags:0x10000  /* kReferenceProperty */
                             value:&propertyData
                             length:propertyLength];

    /* If property found and length is 6 bytes (valid MAC address) */
    if ((result == IO_R_SUCCESS) && (propertyLength[0] == 6)) {
        /* Copy MAC address bytes */
        for (i = 0; i < 6; i++) {
            ea->ea_byte[i] = ((u_int8_t *)propertyData)[i];
        }
    }
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_addToHashTableMask:(u_int8_t *)addr
{
    u_int32_t index;
    u_int32_t bit;
    u_int32_t arrayIndex;

    /* Compute hash index (0-255) from MAC address */
    index = hashIndex(addr);

    /* Increment use count for this hash index */
    if (hashTableUseCount[index]++)
        return;  /* Bit was already set */

    /* Compute which bit to set in the hash table mask */
    bit = index & 0xF;  /* Which bit within the 16-bit word (0-15) */
    arrayIndex = index >> 4;  /* Which 16-bit word (0-15) */

    /* Set the bit in the hash table mask */
    hashTableMask[arrayIndex] |= (1 << bit);
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_removeFromHashTableMask:(u_int8_t *)addr
{
    u_int32_t index;
    u_int32_t bit;
    u_int32_t arrayIndex;

    /* Compute hash index (0-255) from MAC address */
    index = hashIndex(addr);

    /* Check if this hash index is in use */
    if (hashTableUseCount[index] == 0)
        return;  /* Bit wasn't in use */

    /* Decrement use count */
    if (--hashTableUseCount[index])
        return;  /* Bit is still in use by other addresses */

    /* Compute which bit to clear in the hash table mask */
    bit = index & 0xF;  /* Which bit within the 16-bit word (0-15) */
    arrayIndex = index >> 4;  /* Which 16-bit word (0-15) */

    /* Clear the bit in the hash table mask */
    hashTableMask[arrayIndex] &= ~(1 << bit);
}

/*-------------------------------------------------------------------------
 *
 * Update the hardware hash table mask for multicast filtering.
 *
 *-------------------------------------------------------------------------*/

- (void)_updateUniNHashTableMask
{
    u_int16_t savedControl;
    u_int32_t status;
    int i;

    // Read current receive configuration register value
    savedControl = (u_int16_t)ReadUniNRegister(ioBaseEnet, kRxDmaConfig);

    // Disable hash table by clearing the register
    WriteUniNRegister(ioBaseEnet, kRxDmaConfig, 0);

    // Wait for hardware to be ready (busy bits should clear)
    do {
        status = ReadUniNRegister(ioBaseEnet, kRxDmaConfig);
    } while ((status & kRxConfig_Busy) != 0);

    // Write 16 hash table entries to hardware registers
    // Note: Hardware expects hash table in reverse order
    for (i = 0; i < 16; i++)
    {
        WriteUniNRegister(ioBaseEnet, kHashTable0 + (i * 4), hashTableMask[15 - i]);
    }

    // Restore control register with hash enable bit set
    WriteUniNRegister(ioBaseEnet, kRxDmaConfig, savedControl | kRxConfig_HashEnable);
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_dumpRegisters
{
    /* Static register map table for debugging */
    static struct {
        u_int32_t regOffset;  /* Register offset with size encoding */
        char *regName;         /* Register name string */
    } regMap[] = {
        /* System/Control Registers */
        { 0x00011008, "SYS_CLK" },
        { 0x00011010, "SW_RESET" },
        { 0x00019050, "SW_RST1" },
        { 0x00019054, "SW_RST2" },

        /* PCS/SerDes Registers */
        { 0x00016038, "PCS_MII_CTRL" },
        { 0x00020004, "PCS_MII_STAT" },

        /* MAC Control Registers */
        { 0x00046008, "MAC_CTRL" },
        { 0x00040010, "MAC_STAT" },
        { 0x00042004, "MAC_TX_CFG" },
        { 0x00044000, "MAC_RX_CFG" },
        { 0x00042008, "MAC_CTRL_CFG" },
        { 0x00016028, "MAC_CTRL_MASK" },
        { 0x0004048C, "MAC_XIF_CFG" },

        /* TX Configuration */
        { 0x00026020, "TX_INT_MASK" },
        { 0x00026030, "TX_DMA_CFG" },
        { 0x0002604C, "TX_FIFO_THR" },
        { 0x00016040, "TX_PAUSE_Q" },
        { 0x0001605C, "TX_ATT_LIM" },
        { 0x00042008, "TX_DESC_BASE" },
        { 0x0004200C, "TX_DESC_HI" },

        /* RX Configuration */
        { 0x00026024, "RX_INT_MASK" },
        { 0x00026034, "RX_DMA_CFG" },
        { 0x00026050, "RX_FIFO_THR" },
        { 0x00026054, "RX_PAUSE_THR" },
        { 0x00026058, "RX_FIFO_SIZE" },
        { 0x00044004, "RX_DESC_BASE" },
        { 0x00044008, "RX_DESC_HI" },
        { 0x00024100, "RX_KICK" },
        { 0x00024104, "RX_COMP" },
        { 0x00024120, "RX_BLANK_TIME" },
        { 0x00044020, "RX_BLANK_CFG" },
        { 0x00044108, "RX_PAUSE_TIME" },

        /* Frame Parameters */
        { 0x00016044, "MIN_FRAME" },
        { 0x00016048, "MAX_BURST" },
        { 0x00016060, "SLOT_TIME" },
        { 0x00026064, "MIN_IFG" },

        /* MAC Address */
        { 0x00026080, "MAC_ADDR0" },
        { 0x00026084, "MAC_ADDR1" },
        { 0x00026088, "MAC_ADDR2" },

        /* Address Filters */
        { 0x0002608C, "ADDR_FILT0_0" },
        { 0x00026090, "ADDR_FILT1_0" },
        { 0x00026094, "ADDR_FILT2_0" },
        { 0x00026098, "ADDR_FILT2_2" },
        { 0x000260A4, "ADDR_FILT0_1" },
        { 0x000260A8, "ADDR_FILT1_1" },
        { 0x000260AC, "ADDR_FILT2_1" },

        /* Collision Counters */
        { 0x0002609C, "NORM_COLL_CNT" },
        { 0x000260A0, "FIRST_COLL_CNT" },
        { 0x000160B0, "EXCESS_COLL" },
        { 0x000260B4, "LATE_COLL" },

        /* Hash Table */
        { 0x000260C0, "HASH_TBL0" },
        { 0x000260C4, "HASH_TBL1" },
        { 0x000260C8, "HASH_TBL2" },
        { 0x000260CC, "HASH_TBL3" },
        { 0x000260D0, "HASH_TBL4" },
        { 0x000260D4, "HASH_TBL5" },
        { 0x000260D8, "HASH_TBL6" },
        { 0x000260DC, "HASH_TBL7" },
        { 0x000260E0, "HASH_TBL8" },
        { 0x000260E4, "HASH_TBL9" },
        { 0x000260E8, "HASH_TBL10" },
        { 0x000260EC, "HASH_TBL11" },
        { 0x000260F0, "HASH_TBL12" },
        { 0x000260F4, "HASH_TBL13" },
        { 0x000260F8, "HASH_TBL14" },
        { 0x000260FC, "HASH_TBL15" },

        /* Interrupt Status */
        { 0x00026100, "INT_STAT0" },
        { 0x00026104, "INT_STAT1" },
        { 0x00026108, "INT_STAT2" },
        { 0x0002610C, "INT_STAT3" },
        { 0x00026110, "INT_STAT4" },
        { 0x00026114, "INT_STAT5" },
        { 0x00026118, "INT_STAT6" },
        { 0x0002611C, "RX_MAC_CRC_ERR" },
        { 0x00026120, "RX_MAC_CODE_ERR" },
        { 0x00026124, "RX_LEN_ERR" },
        { 0x00026128, "RX_ALIGN_ERR" },

        /* Random Seed */
        { 0x00026130, "RAND_SEED" },

        /* MII Management */
        { 0x0004620C, "MII_MGMT" },
    };

    u_int32_t regValue;
    u_int32_t regSize;
    u_int16_t regOffset;
    int i;
    int numRegs = sizeof(regMap) / sizeof(regMap[0]);

    IOLog("\nEthernet(UniN): IO Address = %08x\n", (u_int32_t)ioBaseEnet);

    /* Iterate through register map and dump each register */
    for (i = 0; i < numRegs; i++) {
        regSize = regMap[i].regOffset >> 16;
        regOffset = regMap[i].regOffset & 0xFFFF;

        /* Read register value */
        regValue = ReadUniNRegister(ioBaseEnet, regMap[i].regOffset);

        /* Print based on register size */
        switch (regSize) {
            case 1:  /* 8-bit register */
                IOLog("Ethernet(UniN): %04x: %s = %02x\n",
                      regOffset, regMap[i].regName, regValue);
                break;

            case 2:  /* 16-bit register */
                IOLog("Ethernet(UniN): %04x: %s = %04x\n",
                      regOffset, regMap[i].regName, regValue);
                break;

            case 4:  /* 32-bit register */
                IOLog("Ethernet(UniN): %04x: %s = %08x\n",
                      regOffset, regMap[i].regName, regValue);
                break;
        }
    }
}

/*-------------------------------------------------------------------------
 *
 *
 *
 *-------------------------------------------------------------------------*/

- (void)_monitorLinkStatus
{
    u_int16_t miiStatus;
    u_int16_t miiANLPA;      /* Auto-negotiation Link Partner Ability */
    u_int16_t phyAuxStatus;
    u_int32_t phyMode;
    u_int16_t xifConfig;
    BOOL linkUp = NO;
    BOOL fullDuplex = NO;
    char *speedStr;
    char *duplexStr;

    /* Check if PHY has been detected */
    if (phyId == 0xFF)
        return;

    /* Read MII status register */
    if (![self miiReadWord:&miiStatus reg:MII_STATUS phy:phyId])
        return;

    /* Check if link status changed (bits 0x24 = link status + auto-negotiation complete) */
    if (((phyStatusPrev ^ miiStatus) & 0x24) == 0)
        return;  /* No change in link status */

    /* Check if link is up and auto-negotiation complete */
    if ((miiStatus & 0x24) != 0x24) {
        /* Link is down */
        if (phyType == YES) {
            [self _stopChip];
            IOLog("Ethernet(UniN): Link is down.\n");
        }
        linkUp = NO;
        goto updateStatus;
    }

    /* Link is up - read auto-negotiation link partner ability */
    [self miiReadWord:&miiANLPA reg:MII_ADVERTISEMENT+1 phy:phyId];  /* Register 5 */

    /* Configure XIF register based on 1000Base-T capability */
    xifConfig = (u_int16_t)ReadUniNRegister(ioBaseEnet, kPCSMIIControl);
    if ((miiANLPA & 0x400) == 0) {
        xifConfig &= 0xFFFE;  /* Clear bit 0 - disable gigabit mode */
    } else {
        xifConfig |= 0x0001;  /* Set bit 0 - enable gigabit mode */
    }
    WriteUniNRegister(ioBaseEnet, kPCSMIIControl, xifConfig);

    /* Determine link speed and duplex based on PHY manufacturer */
    phyMode = phyMfgID & 0xFFFFFFF0;

    if (phyMode == 0x00406210) {
        /* Marvell 88E1000 PHY */
        [self miiReadWord:&phyAuxStatus reg:0x18 phy:phyId];

        fullDuplex = (phyAuxStatus & 1) ? YES : NO;

        if ((phyAuxStatus & 2) == 0) {
            speedStr = "10";
        } else {
            speedStr = "100";
        }

        duplexStr = fullDuplex ? "Full" : "Half";
        IOLog("Ethernet(UniN): Link is up at %sMb - %s Duplex\n", speedStr, duplexStr);
    }
    else if (phyMode == 0x00206040) {
        /* Broadcom BCM5400 PHY */
        [self miiReadWord:&phyAuxStatus reg:0x19 phy:phyId];

        /* Extract speed/duplex from bits 8-10 */
        u_int16_t linkMode = (phyAuxStatus >> 8) & 7;

        /* Configure MII mode based on link speed */
        xifConfig = (u_int16_t)ReadUniNRegister(ioBaseEnet, kPCSMIIControl);
        if (linkMode < 6) {
            xifConfig &= 0xFFF7;  /* Clear bit 3 - MII mode for 10/100 */
        } else {
            xifConfig |= 0x0008;  /* Set bit 3 - GMII mode for 1000 */
        }
        WriteUniNRegister(ioBaseEnet, kPCSMIIControl, xifConfig);

        /* Decode link mode */
        switch (linkMode) {
            case 0:
                /* No link - shouldn't happen here */
                IOLog("Ethernet(UniN): Link is up\n");
                fullDuplex = NO;
                break;

            case 1:  /* 10Base-T half duplex */
                speedStr = "10Base-T";
                fullDuplex = NO;
                duplexStr = "Half";
                IOLog("Ethernet(UniN): Link is up at %s - %s Duplex\n", speedStr, duplexStr);
                break;

            case 2:  /* 10Base-T full duplex */
                speedStr = "10Base-T";
                fullDuplex = YES;
                duplexStr = "Full";
                IOLog("Ethernet(UniN): Link is up at %s - %s Duplex\n", speedStr, duplexStr);
                break;

            case 3:  /* 100Base-TX half duplex */
                speedStr = "100Base-TX";
                fullDuplex = NO;
                duplexStr = "Half";
                IOLog("Ethernet(UniN): Link is up at %s - %s Duplex\n", speedStr, duplexStr);
                break;

            case 4:  /* 100Base-TX full duplex */
                speedStr = "100Base-TX";
                fullDuplex = YES;
                duplexStr = "Full";
                IOLog("Ethernet(UniN): Link is up at %s - %s Duplex\n", speedStr, duplexStr);
                break;

            case 5:  /* 100Base-T4 */
                speedStr = "100Base-T4";
                fullDuplex = NO;
                duplexStr = "Half";
                IOLog("Ethernet(UniN): Link is up at %s - %s Duplex\n", speedStr, duplexStr);
                break;

            case 6:  /* 1000Base-T half duplex */
                speedStr = "1000Base-T";
                fullDuplex = NO;
                duplexStr = "Half";
                IOLog("Ethernet(UniN): Link is up at %s - %s Duplex\n", speedStr, duplexStr);
                break;

            case 7:  /* 1000Base-T full duplex */
                speedStr = "1000Base-T";
                fullDuplex = YES;
                duplexStr = "Full";
                IOLog("Ethernet(UniN): Link is up at %s - %s Duplex\n", speedStr, duplexStr);
                break;
        }
    }
    else if (phyMode == 0x001378E0) {
        /* National Semiconductor DP83843 or similar PHY */
        [self miiReadWord:&phyAuxStatus reg:0x11 phy:phyId];

        fullDuplex = ((phyAuxStatus >> 9) & 1) ? YES : NO;

        if ((phyAuxStatus & 0x4000) == 0) {
            speedStr = "10";
        } else {
            speedStr = "100";
        }

        duplexStr = fullDuplex ? "Full" : "Half";
        IOLog("Ethernet(UniN): Link is up at %sMb - %s Duplex\n", speedStr, duplexStr);
    }
    else {
        /* Unknown PHY - just report link up */
        IOLog("Ethernet(UniN): Link is up\n");
        fullDuplex = NO;
    }

    /* Update duplex mode if changed */
    if (fullDuplex != isFullDuplex) {
        [self _setDuplexMode:fullDuplex];
    }

    /* Start chip if it was enabled */
    if (resetAndEnabled) {
        [self _startChip];
    }

    linkUp = YES;

updateStatus:
    /* Update saved status */
    phyType = linkUp;
    phyStatusPrev = miiStatus;
}

@end
