/*
 * DECchip21140Private.m
 * Private helper functions for DEC 21140 driver
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>
#import <mach/vm_param.h>
#import <objc/objc-runtime.h>
#import "DECchip21140Private.h"
#import "DECchip21140Shared.h"
#import "DECchip21140Inline.h"

extern vm_offset_t page_mask;

/*
 * IOUpdateDescriptorFromNetBuf
 *
 * Update a DMA descriptor from a network buffer.
 * This function maps the netbuf to physical memory and sets up the descriptor
 * for DMA transfer. Handles page boundary crossings.
 *
 * Parameters:
 *   netBuf        - Network buffer to map
 *   descriptor    - Pointer to DMA descriptor to update
 *   isSetupFrame  - TRUE if this is a setup frame, FALSE for normal packet
 *
 * Returns:
 *   TRUE (1) on success, FALSE (0) on failure
 */
BOOL
IOUpdateDescriptorFromNetBuf(netbuf_t netBuf,
                             DECchipDescriptor *descriptor,
                             BOOL isSetupFrame)
{
    int packetSize;
    unsigned int virtualAddr;
    unsigned int physAddr1;
    unsigned int physAddr2;
    int buffer1Size;
    int buffer2Size;
    unsigned int pageAlignedAddr;
    vm_task_t task;

    /* Determine packet size - setup frames are fixed size (0x5f0 = 1520 bytes) */
    if (isSetupFrame) {
        packetSize = 0x5f0;
    } else {
        packetSize = nb_size(netBuf);
    }

    /* Map the network buffer to get virtual address */
    virtualAddr = nb_map(netBuf);

    /* Clear buffer 2 physical address */
    descriptor->buffer2 = 0;

    /* Clear buffer sizes in control field */
    descriptor->control &= ~(DESC_CTRL_SIZE2_MASK | DESC_CTRL_SIZE1_MASK);

    /* Set buffer 1 size (lower 11 bits) */
    descriptor->control = (descriptor->control & 0xFFFFF800) | (packetSize & 0x7FF);

    /* Get physical address for buffer 1 */
    task = IOVmTaskSelf();
    physAddr1 = IOPhysicalFromVirtual(task, (vm_offset_t)virtualAddr);

    if (physAddr1 == 0) {
        /*
         * Physical address translation failed
         * Check if buffer crosses page boundary
         */
        if ((virtualAddr & ~page_mask) != ((virtualAddr + packetSize) & ~page_mask)) {
            /* Buffer crosses a page boundary - need to split into two buffers */

            /* Calculate the page-aligned address */
            pageAlignedAddr = (virtualAddr + page_mask) & ~page_mask;

            /* Calculate size of first buffer (up to page boundary) */
            buffer1Size = pageAlignedAddr - virtualAddr;

            /* Set buffer 1 size in descriptor */
            descriptor->control = (descriptor->control & 0xFFFFF800) |
                                 (buffer1Size & 0x7FF);

            /* Calculate buffer 2 size (remainder after page boundary) */
            buffer2Size = packetSize - buffer1Size;

            /* Set buffer 2 size in descriptor (bits 11-21) */
            descriptor->control = (descriptor->control & 0xFFC007FF) |
                                 ((buffer2Size & 0x7FF) << DESC_CTRL_SIZE2_SHIFT);

            /* Get physical addresses for both buffers */
            physAddr1 = IOPhysicalFromVirtual(task, (vm_offset_t)virtualAddr);
            physAddr2 = IOPhysicalFromVirtual(task, (vm_offset_t)pageAlignedAddr);

            if (physAddr2 != 0) {
                /* Second buffer address conversion also failed */
                return FALSE;
            }

            /* Store physical addresses in descriptor */
            descriptor->buffer1 = physAddr1;
            descriptor->buffer2 = physAddr2;
        }

        /* Return TRUE - buffer handled (matches decompiled) */
        return TRUE;
    } else {
        /* Store physical address for single buffer */
        descriptor->buffer1 = physAddr1;
        /* Return FALSE (matches decompiled LAB_00000f8c) */
        return FALSE;
    }
}

/* Import for category implementation */
#import "DECchip21140.h"

/*
 * Private category implementation
 */
@implementation DECchip21140(Private)

/*
 * Allocate memory for descriptor rings and buffers
 */
- (BOOL)allocateMemory
{
    int i;
    vm_task_t vmTask;

    /* Set memory size needed: RX ring (64) + TX ring (32) + setup frame */
    _descriptorMemorySize = 0x6f0;

    /* Check that one page is sufficient */
    if (page_size < _descriptorMemorySize) {
        IOLog("%s: 1 page limit exceeded for descriptor memory\n", [self name]);
        return NO;
    }

    /* Allocate physically contiguous memory (low memory for DMA) */
    _descriptorMemory = (void *)IOMallocLow(_descriptorMemorySize);
    if (_descriptorMemory == NULL) {
        IOLog("%s: can't allocate 0x%x bytes of memory\n", [self name], _descriptorMemorySize);
        return NO;
    }

    /* Set up RX ring pointer (align to 16-byte boundary) - 64 descriptors */
    _rxRing = (DECchipDescriptor *)_descriptorMemory;
    if (((unsigned int)_rxRing & 0x0F) != 0) {
        _rxRing = (DECchipDescriptor *)(((unsigned int)_descriptorMemory + 0x0F) & 0xFFFFFFF0);
    }

    /* Initialize RX descriptors and netbuf array */
    for (i = 0; i < DECCHIP21140_RX_RING_SIZE; i++) {
        bzero(&_rxRing[i], sizeof(DECchipDescriptor));
        _rxNetBufs[i] = NULL;
    }

    /* Set up TX ring pointer (RX ring + 0x400, align to 16-byte boundary) - 32 descriptors */
    _txRing = (DECchipDescriptor *)((unsigned int)_rxRing + 0x400);
    if (((unsigned int)_txRing & 0x0F) != 0) {
        _txRing = (DECchipDescriptor *)(((unsigned int)_rxRing + 0x40F) & 0xFFFFFFF0);
    }

    /* Initialize TX descriptors and netbuf array */
    for (i = 0; i < DECCHIP21140_TX_RING_SIZE; i++) {
        bzero(&_txRing[i], sizeof(DECchipDescriptor));
        _txNetBufs[i] = NULL;
    }

    /* Set up setup frame buffer (TX ring + 0x200, align to 16-byte boundary) */
    _setupFrame = (void *)((unsigned int)_txRing + 0x200);
    if (((unsigned int)_setupFrame & 0x0F) != 0) {
        _setupFrame = (void *)(((unsigned int)_txRing + 0x20F) & 0xFFFFFFF0);
    }

    /* Get physical address of setup frame */
    vmTask = IOVmTaskSelf();
    _setupFramePhys = IOPhysicalFromVirtual(vmTask, (vm_offset_t)_setupFrame);

    if (_setupFramePhys == 0) {
        IOLog("%s: Invalid shared memory address\n", [self name]);
        return NO;
    }

    return YES;
}

/*
 * Get station (MAC) address
 * Reads the Ethernet MAC address from the Serial ROM
 */
- (void)getStationAddress:(enet_addr_t *)addr
{
    unsigned short csrPort;
    unsigned int i, j;
    unsigned short readData;
    unsigned int bitCount;
    unsigned int romAddress;
    unsigned int dataBit;
    unsigned int regValue;

    /* Read 3 words (6 bytes) for MAC address */
    for (i = 0; i < 3; i++) {
        /* CSR9 (Serial ROM) port */
        csrPort = _portBase + 0x48;

        /* Send start sequence to serial ROM */
        outw(csrPort, 0x4800);
        IODelay(250);
        outw(csrPort, 0x4801);
        IODelay(250);
        outw(csrPort, 0x4803);
        IODelay(250);
        outw(csrPort, 0x4801);
        IODelay(250);
        outw(csrPort, 0x4805);
        IODelay(250);
        outw(csrPort, 0x4807);
        IODelay(250);
        outw(csrPort, 0x4805);
        IODelay(250);
        outw(csrPort, 0x4805);
        IODelay(250);
        outw(csrPort, 0x4807);
        IODelay(250);
        outw(csrPort, 0x4805);
        IODelay(250);
        outw(csrPort, 0x4801);
        IODelay(250);
        outw(csrPort, 0x4803);
        IODelay(250);
        outw(csrPort, 0x4801);
        IODelay(250);

        /* Clock out address bits */
        bitCount = _sromAddressBits;
        romAddress = _sromAddress;

        if (bitCount != 0) {
            for (j = 0; j < bitCount; j++) {
                /* Get bit value - shift right by (bitCount - j - 1) */
                dataBit = ((romAddress >> 1) + i) >> ((bitCount - j) - 1) & 1;

                if (dataBit < 2) {
                    /* Shift bit into position and clock it out */
                    dataBit = dataBit << 2;
                    outw(csrPort, dataBit | 0x4801);
                    IODelay(250);
                    outw(csrPort, dataBit | 0x4803);
                    IODelay(250);
                    outw(csrPort, dataBit | 0x4801);
                    IODelay(250);
                } else {
                    IOLog("bogus data in clock_in_bit\n");
                }
            }
        }

        /* Clock in 16 bits of data */
        readData = 0;
        for (j = 0; j < 16; j++) {
            /* Raise clock */
            outw(csrPort, 0x4803);
            IODelay(250);

            /* Read data bit (bit 3 of input) */
            regValue = inw(csrPort);
            IODelay(250);

            /* Extract bit 3 */
            dataBit = (regValue >> 3) & 1;

            /* Lower clock */
            outw(csrPort, 0x4801);
            IODelay(250);

            /* Shift data in */
            readData = (readData << 1) | (dataBit & 1);
        }

        /* Store the two bytes of MAC address */
        addr->ea_byte[i * 2] = (unsigned char)(readData & 0xFF);
        addr->ea_byte[i * 2 + 1] = (unsigned char)(readData >> 8);
    }
}

/*
 * Initialize chip hardware
 */
- (BOOL)initChip
{
    BOOL result;

    /* Initialize CSR registers */
    [self initRegisters];

    /* Start transmit engine */
    [self startTransmit];

    /* Set up address filtering with blocking mode */
    result = [self setAddressFiltering:YES];

    return (result != NO);
}

/*
 * Initialize CSR registers
 */
- (void)initRegisters
{
    vm_task_t vmTask;
    vm_offset_t physAddr;
    unsigned int csrValue;
    unsigned int linkStatus;

    /* Reset chip first */
    [self resetChip];

    /* Write bus mode register (CSR0) - 0x6000 */
    outl(_portBase, 0x6000);

    /* Get physical address of RX ring and write to CSR3 */
    vmTask = IOVmTaskSelf();
    physAddr = IOPhysicalFromVirtual(vmTask, (vm_offset_t)_rxRing);

    if (physAddr != 0) {
        IOLog("%s: Invalid shared memory address\n", [self name]);
        return;
    }

    outl(_portBase + 0x18, physAddr);  /* CSR3 */

    /* Get physical address of TX ring and write to CSR4 */
    physAddr = IOPhysicalFromVirtual(vmTask, (vm_offset_t)_txRing);

    if (physAddr != 0) {
        IOLog("%s: Invalid shared memory address\n", [self name]);
        return;
    }

    outl(_portBase + 0x20, physAddr);  /* CSR4 */

    /* Set CSR6 (command register) based on media type */
    csrValue = 0;
    switch (_mediaType) {
        case 0:  /* 10Base-T */
            csrValue = 0x400000;
            break;
        case 1:  /* 10Base-T Full Duplex */
            csrValue = 0x4C0000;
            break;
        case 2:  /* 10Base2 (BNC) */
            csrValue = 0xC0000 | 0x4000;
            break;
        case 3:  /* 10Base5 (AUI) */
            csrValue = 0x2C0000;
            break;
        case 4:  /* 100BaseTX */
            csrValue = 0x8C0000 | 0x4000;
            break;
        case 5:  /* 100BaseTX Full Duplex */
            csrValue = 0x18C4000;
            break;
    }

    _cachedCSR6 = csrValue;
    outl(_portBase + 0x30, csrValue);  /* CSR6 */

    /* Initialize state variables */
    _linkStatus = 0x10049;

    /* For Cogent adapters (vendor subtype 0x10b8), check link status */
    if (_vendorID == 0x10b8) {
        /* Reset SIA */
        outl(_portBase + 0x60, 0x101);  /* CSR12 */
        outl(_portBase + 0x60, 0x100);
        IOSleep(100);
        outl(_portBase + 0x60, 0);
        IOSleep(1000);

        /* Check link status */
        linkStatus = inl(_portBase + 0x60);
        if ((linkStatus & 0x80) != 0) {
            IOLog("%s: no link detected, check network connection\n", [self name]);
        }
    }

    /* Call vendor-specific GP port initialization */
    switch (_vendorType) {
        case 1:  /* Cogent */
            if (_mediaType == 5) {
                [self initGPPortRegisterForCogent100Mb];
            } else if (_mediaType == 0) {
                [self initGPPortRegisterForCogent10Mb];
            }
            break;

        case 0:  /* DEC */
            if (_mediaType == 5) {
                [self initGPPortRegisterForCogent100Mb];
            }
            break;

        case 2:  /* DE500 */
            if (_mediaType == 5) {
                [self initGPPortRegisterForDE500100Mb];
            }
            break;

        case 4:  /* Custom */
            [self initGPPortRegisterForCustom];
            break;
    }
}

/*
 * Initialize receive descriptor ring
 */
- (BOOL)initRxRing
{
    int i;
    unsigned char *descByte;

    /* Initialize all RX descriptors (64 descriptors for 21140) */
    for (i = 0; i < DECCHIP21140_RX_RING_SIZE; i++) {
        /* Zero the descriptor */
        bzero(&_rxRing[i], sizeof(DECchipDescriptor));

        /* Clear ownership bit (bit 7 of status byte 3) */
        descByte = (unsigned char *)&_rxRing[i] + 3;
        *descByte &= 0x7F;

        /* Allocate network buffer if not already allocated */
        if (_rxNetBufs[i] == NULL) {
            _rxNetBufs[i] = [self allocateNetbuf];
            if (_rxNetBufs[i] == NULL) {
                IOPanic("allocateNetbuf returned NULL in _initRxRing");
            }
        }

        /* Update descriptor from network buffer (use setup frame size for RX) */
        if (!IOUpdateDescriptorFromNetBuf(_rxNetBufs[i], &_rxRing[i], TRUE)) {
            IOPanic("_initRxRing");
        }

        /* Set ownership bit to DMA (bit 7 of status byte 3) */
        descByte = (unsigned char *)&_rxRing[i] + 3;
        *descByte |= 0x80;
    }

    /* Set end of ring marker (bit 1 of last descriptor's control byte 3) */
    descByte = (unsigned char *)&_rxRing[DECCHIP21140_RX_RING_SIZE - 1] + 7;
    *descByte |= 0x02;

    /* Initialize RX ring head pointer */
    _rxHead = 0;

    return YES;
}

/*
 * Initialize transmit descriptor ring
 */
- (BOOL)initTxRing
{
    int i;
    unsigned char *descByte;
    id newQueue;

    /* Initialize all TX descriptors (32 descriptors for 21140) */
    for (i = 0; i < DECCHIP21140_TX_RING_SIZE; i++) {
        /* Zero the descriptor */
        bzero(&_txRing[i], sizeof(DECchipDescriptor));

        /* Clear ownership bit (bit 7 of status byte 3) */
        descByte = (unsigned char *)&_txRing[i] + 3;
        *descByte &= 0x7F;

        /* Free any existing network buffer */
        if (_txNetBufs[i] != NULL) {
            nb_free(_txNetBufs[i]);
            _txNetBufs[i] = NULL;
        }
    }

    /* Set end of ring marker (bit 1 of last descriptor's control byte 3) */
    descByte = (unsigned char *)&_txRing[DECCHIP21140_TX_RING_SIZE - 1] + 7;
    *descByte |= 0x02;

    /* Initialize TX ring pointers */
    _txHead = 0;
    _txCompletionIndex = 0;
    _txTail = DECCHIP21140_TX_RING_SIZE;  /* All 32 descriptors available */
    _txInterruptCounter = 0;

    /* Free existing transmit queue if present */
    if (_transmitQueue != nil) {
        [_transmitQueue free];
    }

    /* Allocate new IONetbufQueue with max count of 128 (0x80) */
    newQueue = [objc_getClass("IONetbufQueue") alloc];
    _transmitQueue = [newQueue initWithMaxCount:0x80];

    if (_transmitQueue == nil) {
        IOPanic("_initTxRing");
    }

    return YES;
}

/*
 * Load setup filter frame
 */
- (void)loadSetupFilter:(BOOL)perfect
{
    DECchipDescriptor *txDesc;
    unsigned char *descByte;
    unsigned int csr5;
    int timeout;

    /* Check if TX descriptor available */
    if (_txTail == 0) {
        return;
    }

    /* Get pointer to current TX descriptor */
    txDesc = &_txRing[_txHead];

    /* Advance TX head pointer */
    _txHead++;
    if (_txHead == DECCHIP21140_TX_RING_SIZE) {
        _txHead = 0;
    }

    /* Decrement available descriptor count */
    _txTail--;

    /* Clear control field, preserving end-of-ring marker if present */
    descByte = (unsigned char *)&txDesc->control + 3;
    if (*descByte & 0x02) {
        txDesc->control = 0;
        *descByte |= 0x02;  /* Preserve end-of-ring marker */
    } else {
        txDesc->control = 0;
    }

    /* Set setup frame flag (bit 3 of control byte 3) */
    *descByte |= 0x08;

    /* Set ownership bit (bit 7 of control byte 3) */
    *descByte |= 0x80;

    /* Set buffer size to 192 (0xC0) in control field */
    txDesc->control &= 0xFFFFF800;
    txDesc->control |= 0xC0;

    /* Clear buffer 2 size */
    txDesc->control &= 0xFFC007FF;

    /* Set buffer 1 physical address to setup frame */
    txDesc->buffer1 = _setupFramePhys;

    /* Clear buffer 2 address */
    txDesc->buffer2 = 0;

    /* Clear status */
    txDesc->status = 0;

    /* Set ownership bit in status */
    descByte = (unsigned char *)&txDesc->status + 3;
    *descByte |= 0x80;

    /* Write to CSR1 (TX poll demand) to start transmission */
    outl(_portBase + 8, 1);

    /* If blocking mode (perfect filtering), wait for completion */
    if (perfect) {
        timeout = 9999;
        while (timeout >= 0) {
            IODelay(5);
            csr5 = inl(_portBase + 0x28);  /* CSR5 */

            /* Check for transmit interrupt (bit 2) */
            if (csr5 & 0x04) {
                /* Clear the interrupt */
                outl(_portBase + 0x28, csr5);
                break;
            }
            timeout--;
        }

        /* Free the descriptor */
        _txCompletionIndex++;
        if (_txCompletionIndex == DECCHIP21140_TX_RING_SIZE) {
            _txCompletionIndex = 0;
        }

        /* Increment available count */
        _txTail++;
    }
}

/*
 * Handle receive interrupt
 */
- (void)receiveInterruptOccurred
{
    DECchipDescriptor *rxDesc;
    unsigned char *descByte;
    netbuf_t oldNetBuf, newNetBuf;
    unsigned int packetLength;
    unsigned char errorStatus;
    BOOL isGoodPacket;
    BOOL shouldDeliver;
    int bufSize;
    struct objc_super superInfo;

    /* Reserve debugger lock */
    [self reserveDebuggerLock];

    /* Process all received packets */
    while (1) {
        rxDesc = &_rxRing[_rxHead];

        /* Check ownership bit - if set, DMA still owns it */
        descByte = (unsigned char *)&rxDesc->status + 3;
        if (*descByte & 0x80) {
            /* No more packets to process */
            [self releaseDebuggerLock];
            return;
        }

        shouldDeliver = NO;

        /* Extract packet length (lower 15 bits of status word at offset 2, minus 4 for CRC) */
        packetLength = (rxDesc->status & 0x7FFF0000) >> 16;
        packetLength -= 4;

        /* Check error status (byte 1 of status) */
        errorStatus = *((unsigned char *)&rxDesc->status + 1);

        /* Check if packet is good: bits 0,1,7 should be set (0x83), and length > 59 */
        isGoodPacket = ((errorStatus & 0x83) == 0x03) && (packetLength > 59);

        if (isGoodPacket) {
            oldNetBuf = _rxNetBufs[_rxHead];

            /* Filter multicast packets if not in promiscuous mode */
            if (!_isEnabled && (errorStatus & 0x04)) {
                /* Multicast packet - check if unwanted */
                superInfo.receiver = self;
                superInfo.class = objc_getClass("IOEthernet");

                if ([self isUnwantedMulticastPacket:(void *)nb_map(oldNetBuf)]) {
                    /* Unwanted multicast - don't deliver */
                } else {
                    shouldDeliver = YES;
                }
            } else {
                shouldDeliver = YES;
            }

            if (shouldDeliver) {
                /* Allocate new buffer for this descriptor */
                newNetBuf = [self allocateNetbuf];

                if (newNetBuf != NULL) {
                    /* Replace buffer in array */
                    _rxNetBufs[_rxHead] = newNetBuf;
                    shouldDeliver = YES;

                    /* Update descriptor with new buffer */
                    if (!IOUpdateDescriptorFromNetBuf(_rxNetBufs[_rxHead], &_rxRing[_rxHead], TRUE)) {
                        IOPanic("DECchip21040: IOUpdateDescriptorFromNetBuf\n");
                    }

                    /* Adjust old buffer size to actual packet length */
                    bufSize = nb_size(oldNetBuf);
                    nb_shrink_bot(oldNetBuf, bufSize - packetLength);
                }
            }
        } else {
            /* Packet had errors */
            [_networkInterface incrementInputErrors];
        }

        /* Reset descriptor status and return ownership to DMA */
        rxDesc->status = 0;
        descByte = (unsigned char *)&rxDesc->status + 3;
        *descByte |= 0x80;

        /* Advance RX head pointer */
        _rxHead++;
        if (_rxHead == DECCHIP21140_RX_RING_SIZE) {
            _rxHead = 0;
        }

        /* If we have a good packet to deliver, pass it to network stack */
        if (shouldDeliver) {
            [self releaseDebuggerLock];
            [_networkInterface handleInputPacket:oldNetBuf extra:0];
            [self reserveDebuggerLock];
        }
    }
}

/*
 * Reset chip hardware
 */
- (void)resetChip
{
    /* Write 1 to CSR0 to initiate software reset */
    outl(_portBase, 1);

    /* Wait 100 microseconds for reset to start */
    IODelay(100);

    /* Write 0 to CSR0 to complete reset */
    outl(_portBase, 0);

    /* Sleep 1 millisecond for reset to stabilize */
    IOSleep(1);
}

/*
 * Set address filtering mode
 * Builds the setup frame with station address, broadcast, and multicast addresses
 */
- (BOOL)setAddressFiltering:(BOOL)enable
{
    unsigned short *macAddr;
    unsigned int *setupFrame;
    int i;
    unsigned int entryIndex;
    struct objc_super superInfo;
    id multicastQueue;
    void *queueHead;
    void *currentEntry;
    void *nextEntry;
    unsigned char *addrBytes;
    unsigned int word;
    BOOL result;

    setupFrame = (unsigned int *)_setupFrame;
    macAddr = (unsigned short *)&_stationAddress;

    /* Copy station (MAC) address as first entry (3 16-bit words = 12 bytes) */
    for (i = 0; i < 3; i++) {
        setupFrame[i] = (unsigned int)macAddr[i];
    }

    /* Fill second entry with broadcast address (0xFFFF) */
    for (i = 0; i < 3; i++) {
        setupFrame[3 + i] = 0xFFFF;
    }

    /* Start filling additional entries at index 2 */
    entryIndex = 2;

    /* If attached to network, add multicast addresses */
    if (_isAttached) {
        /* Get multicast queue from superclass IOEthernet */
        superInfo.receiver = self;
        superInfo.class = objc_getClass("IOEthernet");

        multicastQueue = objc_msgSendSuper(&superInfo, @selector(multicastQueue));

        /* The queue is a linked list structure */
        queueHead = (void *)multicastQueue;
        currentEntry = *(void **)multicastQueue;  /* Get first entry */

        /* Iterate through multicast addresses */
        while (currentEntry != queueHead) {
            /* Each multicast address entry contains 6 bytes */
            addrBytes = (unsigned char *)currentEntry;

            /* Copy address as 3 16-bit words to setup frame */
            for (i = 0; i < 3; i++) {
                /* Combine two bytes into one word (little-endian) */
                word = addrBytes[i * 2] | (addrBytes[i * 2 + 1] << 8);
                setupFrame[entryIndex * 3 + i] = word;
            }

            entryIndex++;

            /* Check if we've reached the limit (16 entries total) */
            if (entryIndex > 15) {
                IOLog("%s: %d multicast address limit exceeded\n", [self name], 14);
                break;
            }

            /* Get next entry (linked list pointer at offset 8 / index 2) */
            nextEntry = ((void **)currentEntry)[2];
            currentEntry = nextEntry;
        }
    }

    /* Fill remaining entries by copying the first entry (station address) */
    for (; entryIndex < 16; entryIndex++) {
        bcopy(_setupFrame, (char *)_setupFrame + (entryIndex * 12), 12);
    }

    /* Load the setup frame to the chip */
    result = [self loadSetupFilter:enable];
    return (result != NO);
}

/*
 * Start receive engine
 */
- (void)startReceive
{
    /* Set Start Receive bit (bit 1) in cached CSR6 */
    ((unsigned char *)&_cachedCSR6)[0] |= 0x02;

    /* Write cached value to CSR6 command register */
    outl(_portBase + 0x30, _cachedCSR6);
}

/*
 * Start transmit engine
 */
- (void)startTransmit
{
    /* Set Start Transmit bit (bit 13 = 0x20 in byte 1) in cached CSR6 */
    ((unsigned char *)&_cachedCSR6)[1] |= 0x20;

    /* Write cached value to CSR6 command register */
    outl(_portBase + 0x30, _cachedCSR6);
}

/*
 * Handle transmit interrupt
 */
- (void)transmitInterruptOccurred
{
    DECchipDescriptor *txDesc;
    unsigned short *status;
    unsigned char *descByte;
    unsigned char collisionCount;

    /* Process completed TX descriptors */
    while (1) {
        /* Check if there are descriptors to process (tail > 31 means all available) */
        if (_txTail > 31) {
            return;
        }

        /* Get descriptor at TX completion index */
        txDesc = &_txRing[_txCompletionIndex];

        /* Check ownership bit - if DMA still owns it, we're done */
        descByte = (unsigned char *)&txDesc->status + 3;
        if (*descByte & 0x80) {
            return;
        }

        /* Check if this is a setup frame (bit 3 of control byte 3) */
        descByte = (unsigned char *)&txDesc->control + 3;
        if ((*descByte & 0x08) == 0) {
            /* Regular data packet - process status */
            status = (unsigned short *)&txDesc->status;

            /* Check for errors (bits in 0x4702) */
            if (*status & 0x4702) {
                /* Error occurred */
                [_networkInterface incrementOutputErrors];
            } else {
                /* Successful transmission */
                [_networkInterface incrementOutputPackets];
            }

            /* Process collision statistics */
            if (*status & 0x0100) {
                /* Excessive collisions (bit 8) */
                collisionCount = 16;
                [_networkInterface incrementCollisionsBy:collisionCount];
            } else if (*status & 0x0078) {
                /* Normal collisions (bits 3-6) */
                collisionCount = (*status >> 3) & 0x0F;
                [_networkInterface incrementCollisionsBy:collisionCount];
            }

            /* Check for deferred transmission with collision (bits 1 and 9) */
            if ((*status & 0x0202) == 0x0200) {
                [_networkInterface incrementCollisions];
            }

            /* Free the transmitted netbuf */
            if (_txNetBufs[_txCompletionIndex] != NULL) {
                nb_free(_txNetBufs[_txCompletionIndex]);
                _txNetBufs[_txCompletionIndex] = NULL;
            }
        }

        /* Advance TX completion pointer */
        _txCompletionIndex++;
        if (_txCompletionIndex == DECCHIP21140_TX_RING_SIZE) {
            _txCompletionIndex = 0;
        }

        /* Increment available descriptor count */
        _txTail++;
    }
}

/*
 * Transmit a packet using the descriptor ring
 */
- (BOOL)transmitPacket:(netbuf_t)pkt
{
    DECchipDescriptor *txDesc;
    unsigned char *descByte;

    /* Perform loopback if enabled */
    [self performLoopback:pkt];

    /* Reserve debugger lock */
    [self reserveDebuggerLock];

    /* Check if TX descriptors available */
    if (_txTail == 0) {
        /* No descriptors available */
        [self releaseDebuggerLock];
        nb_free(pkt);
        return NO;
    }

    /* Get descriptor at TX head */
    txDesc = &_txRing[_txHead];

    /* Store netbuf in array */
    _txNetBufs[_txHead] = pkt;

    /* Clear control field, preserving end-of-ring marker if present */
    descByte = (unsigned char *)&txDesc->control + 3;
    if (*descByte & 0x02) {
        /* End of ring - clear but preserve marker */
        txDesc->control = 0;
        *descByte |= 0x02;
    } else {
        /* Not end of ring - just clear */
        txDesc->control = 0;
    }

    /* Update descriptor from network buffer */
    if (!IOUpdateDescriptorFromNetBuf(pkt, txDesc, NO)) {
        [self releaseDebuggerLock];
        IOLog("%s: _transmitPacket: IOUpdateDescriptorFromNetBuf failed\n", [self name]);
        nb_free(pkt);
        return NO;
    }

    /* Set first packet bit (bit 5 of control byte 3) */
    descByte = (unsigned char *)&txDesc->control + 3;
    *descByte |= 0x20;

    /* Set last packet bit (bit 6 of control byte 3) */
    *descByte |= 0x40;

    /* Set interrupt on completion every 16 packets */
    _txInterruptCounter++;
    if (_txInterruptCounter == 16) {
        *descByte |= 0x80;  /* Set interrupt bit */
        _txInterruptCounter = 0;
    } else {
        *descByte &= 0x7F;  /* Clear interrupt bit */
    }

    /* Clear status field */
    txDesc->status = 0;

    /* Set ownership bit (bit 7 of status byte 3) to give to DMA */
    descByte = (unsigned char *)&txDesc->status + 3;
    *descByte |= 0x80;

    /* Advance TX head pointer */
    _txHead++;
    if (_txHead == DECCHIP21140_TX_RING_SIZE) {
        _txHead = 0;
    }

    /* Decrement available descriptor count */
    _txTail--;

    /* Write to CSR1 (TX poll demand) to trigger transmission */
    outl(_portBase + 8, 1);

    /* Release debugger lock */
    [self releaseDebuggerLock];

    return YES;
}

/*
 * Verify checksum
 * Verifies serial ROM is responding by reading checksum address
 */
- (BOOL)verifyCheckSum
{
    unsigned short csrPort;
    unsigned int i;
    unsigned int bitCount;
    unsigned int dataBit;

    /* CSR9 (Serial ROM) port */
    csrPort = _portBase + 0x48;

    /* Send start sequence to serial ROM */
    outw(csrPort, 0x4800);
    IODelay(250);
    outw(csrPort, 0x4801);
    IODelay(250);
    outw(csrPort, 0x4803);
    IODelay(250);
    outw(csrPort, 0x4801);
    IODelay(250);
    outw(csrPort, 0x4805);
    IODelay(250);
    outw(csrPort, 0x4807);
    IODelay(250);
    outw(csrPort, 0x4805);
    IODelay(250);
    outw(csrPort, 0x4805);
    IODelay(250);
    outw(csrPort, 0x4807);
    IODelay(250);
    outw(csrPort, 0x4805);
    IODelay(250);
    outw(csrPort, 0x4801);
    IODelay(250);
    outw(csrPort, 0x4803);
    IODelay(250);
    outw(csrPort, 0x4801);
    IODelay(250);

    /* Clock out address bits for address 3 (checksum location) */
    bitCount = _sromAddressBits;

    if (bitCount != 0) {
        for (i = 0; i < bitCount; i++) {
            /* Get bit value from address 3, shifted right by (bitCount - i - 1) */
            dataBit = 3U >> ((bitCount - i) - 1) & 1;

            if (dataBit < 2) {
                /* Shift bit into position and clock it out */
                dataBit = dataBit << 2;
                outw(csrPort, dataBit | 0x4801);
                IODelay(250);
                outw(csrPort, dataBit | 0x4803);
                IODelay(250);
                outw(csrPort, dataBit | 0x4801);
                IODelay(250);
            } else {
                IOLog("bogus data in clock_in_bit\n");
            }
        }
    }

    /* Clock in 16 bits of data (but don't use result) */
    for (i = 0; i < 16; i++) {
        /* Raise clock */
        outw(csrPort, 0x4803);
        IODelay(250);

        /* Read data (result ignored) */
        inw(csrPort);
        IODelay(250);

        /* Lower clock */
        outw(csrPort, 0x4801);
        IODelay(250);
    }

    /* Always return success - just checking ROM responds */
    return YES;
}

/*
 * Receive a packet (blocking)
 * Used for debugging/polling mode only
 */
- (BOOL)receivePacket:(void *)data
               length:(unsigned int *)length
              timeout:(unsigned int)timeout
{
    return NO;
}

/*
 * Send a packet (blocking)
 * Used for debugging/polling mode only
 */
- (BOOL)sendPacket:(void *)data length:(unsigned int)length
{
    DECchipDescriptor *txDesc;
    unsigned char *descByte;
    void *bufferData;
    int originalBufferSize;
    int pollCount;

    /* Only work in polling mode */
    if (!_isPollingMode) {
        return NO;
    }

    /* Process any completed transmissions first */
    [self transmitInterruptOccurred];

    /* Check if TX descriptors available */
    if (_txTail == 0) {
        IOLog("%s: _sendPacket: No free tx descriptors\n", [self name]);
        return NO;
    }

    /* Get descriptor at TX head */
    txDesc = &_txRing[_txHead];

    /* Clear netbuf entry for this descriptor */
    _txNetBufs[_txHead] = NULL;

    /* Copy data to debug netbuf */
    bufferData = (void *)nb_map(_debugNetBuf);
    bcopy(data, bufferData, length);

    /* Adjust netbuf size to packet length */
    originalBufferSize = nb_size(_debugNetBuf);
    nb_shrink_bot(_debugNetBuf, originalBufferSize - length);

    /* Clear control field, preserving end-of-ring marker if present */
    descByte = (unsigned char *)&txDesc->control + 3;
    if (*descByte & 0x02) {
        /* End of ring - clear but preserve marker */
        txDesc->control = 0;
        *descByte |= 0x02;
    } else {
        /* Not end of ring - just clear */
        txDesc->control = 0;
    }

    /* Update descriptor from debug netbuf */
    if (!IOUpdateDescriptorFromNetBuf(_debugNetBuf, txDesc, NO)) {
        IOLog("%s: _sendPacket: IOUpdateDescriptorFromNetBuf failed\n", [self name]);
        nb_grow_bot(_debugNetBuf, originalBufferSize - length);
        return NO;
    }

    /* Set first packet bit (bit 5 of control byte 3) */
    descByte = (unsigned char *)&txDesc->control + 3;
    *descByte |= 0x20;

    /* Set last packet bit (bit 6 of control byte 3) */
    *descByte |= 0x40;

    /* Clear interrupt bit (bit 7) for polling mode */
    *descByte &= 0x7F;

    /* Clear status field */
    txDesc->status = 0;

    /* Set ownership bit (bit 7 of status byte 3) to give to DMA */
    descByte = (unsigned char *)&txDesc->status + 3;
    *descByte |= 0x80;

    /* Advance TX head pointer */
    _txHead++;
    if (_txHead == DECCHIP21140_TX_RING_SIZE) {
        _txHead = 0;
    }

    /* Decrement available descriptor count */
    _txTail--;

    /* Write to CSR1 (TX poll demand) to trigger transmission */
    outl(_portBase + 8, 1);

    /* Poll for completion (up to 10000 iterations = 5 seconds) */
    pollCount = 0;
    descByte = (unsigned char *)&txDesc->status + 3;
    while (*descByte & 0x80) {
        /* Still owned by DMA */
        if (pollCount >= 10000) {
            IOLog("%s: _sendPacket: polling timed out\n", [self name]);
            nb_grow_bot(_debugNetBuf, originalBufferSize - length);
            return NO;
        }
        IODelay(500);
        pollCount++;
    }

    /* Restore original buffer size */
    nb_grow_bot(_debugNetBuf, originalBufferSize - length);

    return YES;
}

@end
