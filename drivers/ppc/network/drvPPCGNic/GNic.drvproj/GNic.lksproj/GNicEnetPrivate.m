/* GNicEnetPrivate.m - PowerPC GNic Ethernet Driver Private Methods */

#import "GNicEnet.h"
#import <kernserv/prototypes.h>

// GNic register offsets (encoded with size in upper 16 bits)
// Format: (size << 16) | offset, where size: 1=byte, 2=word, 4=dword
// TODO: Define actual GNic register offsets
#define kGNicRegExample		0x40000		// Example register

// External function declarations
extern unsigned int _ReadGNicRegister(int base, unsigned int offset_and_size);
extern void _WriteGNicRegister(int base, unsigned int offset_and_size, unsigned int value);
extern void enforceInOrderExecutionIO(void);
extern int IOPhysicalFromVirtual(void *virtualAddr, void **physicalAddr);
extern void IOGetTimestamp(ns_time_t *time);

// DMA page size
#define PAGE_SIZE		4096

@implementation GNicEnet(Private)

//
// Initialize chip
//
- (BOOL)_initChip
{
    unsigned int i;

    // Clear multicast table and other registers (64 entries, 8 bytes each)
    i = 0;
    do {
        _WriteGNicRegister((int)memBase, i * 8 + 0x40100, 0);
        _WriteGNicRegister((int)memBase, i * 8 + 0x40104, 0);
        i = i + 1;
    } while (i < 0x40);

    // Configure chip registers
    _WriteGNicRegister((int)memBase, 0x400b8, 0x1e000c00);
    _WriteGNicRegister((int)memBase, 0x200a8, 0);
    _WriteGNicRegister((int)memBase, 0x200a0, 0x14e);
    _WriteGNicRegister((int)memBase, 0x200d0, 1);
    _WriteGNicRegister((int)memBase, 0x200a2, 0xc);
    _WriteGNicRegister((int)memBase, 0x400b0, 0x260500);
    _WriteGNicRegister((int)memBase, 0x200f8, 0x4c);
    _WriteGNicRegister((int)memBase, 0x400bc, 0x30ffff);
    _WriteGNicRegister((int)memBase, 0x200ce, 0x600);
    _WriteGNicRegister((int)memBase, 0x200e4, 0x400);
    _WriteGNicRegister((int)memBase, 0x40078, 0x400000);
    _WriteGNicRegister((int)memBase, 0x4007c, 0x50b00);
    _WriteGNicRegister((int)memBase, 0x20000, 0x15);
    _WriteGNicRegister((int)memBase, 0x20020, 0x15);

    // Set TX descriptor ring physical address
    _WriteGNicRegister((int)memBase, 0x40008, txDMACommandsPhys);

    // Set RX descriptor ring physical address
    _WriteGNicRegister((int)memBase, 0x40028, rxDMACommandsPhys);

    // Additional configuration
    _WriteGNicRegister((int)memBase, 0x200e4, 0x400);
    _WriteGNicRegister((int)memBase, 0x200e8, 0xa0);
    _WriteGNicRegister((int)memBase, 0x200e0, 0x1000);

    return YES;
}

//
// Reset chip
//
- (void)_resetChip
{
    unsigned int resetStatus;

    // Initiate software reset by writing 1 to reset register
    _WriteGNicRegister((int)memBase, 0x1006b, 1);

    // Poll until reset completes (bit 0 clears)
    do {
        resetStatus = _ReadGNicRegister((int)memBase, 0x1006b);
    } while ((resetStatus & 1) != 0);

    // Delay 10 microseconds
    IODelay(10);

    // Wait for chip to be ready (bit 0x40 clears in status register)
    do {
        resetStatus = _ReadGNicRegister((int)memBase, 0x100f0);
    } while ((resetStatus & 0x40) != 0);
}

//
// Start chip
//
- (void)_startChip
{
    unsigned int regValue;

    // Read current value from control register
    regValue = _ReadGNicRegister((int)memBase, 0x400b0);

    // Set bits 0x280 to enable transmitter and receiver
    _WriteGNicRegister((int)memBase, 0x400b0, regValue | 0x280);

    // Kick receive DMA
    _WriteGNicRegister((int)memBase, 0x20024, 1);

    // Kick transmit DMA
    _WriteGNicRegister((int)memBase, 0x20004, 1);
}

//
// Allocate memory for rings
//
- (BOOL)_allocateMemory
{
    unsigned int allocSize;
    unsigned int numPages;
    unsigned int i;
    void *physAddr;
    void *currentPage;
    int firstPagePhys;
    int result;

    // Calculate allocation size (PAGE_SIZE + 0x800, aligned to page boundary)
    allocSize = (PAGE_SIZE + 0x800) & ~PAGE_SIZE;

    // Allocate DMA command memory
    if (dmaCommands == NULL) {
        result = IOPhysicalFromVirtual((void *)PAGE_SIZE, &dmaCommands, allocSize);
        if (result != 0) {
            IOLog("Ethernet(GNic): Cant allocate channel dma commands\n\r");
            return NO;
        }

        // Calculate number of pages needed
        numPages = (allocSize - PAGE_SIZE) / PAGE_SIZE;

        // Get physical address of first page
        IOPhysicalFromVirtual((void *)PAGE_SIZE, (void **)&firstPagePhys, &dmaCommands);

        // Verify contiguous allocation
        currentPage = dmaCommands;
        i = 0;
        if (numPages != 0) {
            do {
                IOPhysicalFromVirtual((void *)PAGE_SIZE, (void **)&physAddr, currentPage);
                if ((int)physAddr != (i * PAGE_SIZE + firstPagePhys)) {
                    IOLog("Ethernet(GNic): Cant allocate contiguous memory for dma commands\n\r");
                    return NO;
                }
                i = i + 1;
                currentPage = (void *)((int)currentPage + PAGE_SIZE);
            } while (i < numPages);
        }

        // Set up TX and RX DMA command pointers (virtual addresses)
        txDMACommands = dmaCommands;
        txDMACommandsSize = 0x80;  // 128 bytes
        rxDMACommands = (void *)((int)dmaCommands + 0x400);  // Offset by 1024 bytes
        rxDMACommandsSize = 0x80;  // 128 bytes
    }

    return YES;
}

//
// Initialize transmit ring
//
- (BOOL)_initTxRing
{
    void *physAddr;
    int result;

    // Zero the TX ring descriptor memory
    // Note: rxDMACommands actually holds TX descriptors (naming is backwards)
    bzero(rxDMACommands, rxDMACommandsSize << 3);

    // Initialize TX ring pointers
    txHead = 0;
    txTail = 0;

    // Set bit 0x20 in last descriptor's byte at offset -5
    *(unsigned char *)(rxDMACommandsSize * 8 + (int)rxDMACommands + -5) = 0x20;

    // Free existing transmit queue if present
    if (transmitQueue != nil) {
        [transmitQueue free];
    }

    // Allocate new transmit queue with max 256 entries
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:0x100];
    if (transmitQueue == nil) {
        IOLog("Ethernet(GNic): Cant allocate transmit queue\n\r");
        return NO;
    }

    // Get physical address and verify it's valid
    result = IOPhysicalFromVirtual((void *)PAGE_SIZE, &physAddr, rxDMACommands);
    if (result != 0) {
        IOLog("Ethernet(GNic): Bad dma command buf - %08x\n\r", (unsigned int)rxDMACommands);
    }

    return YES;
}

//
// Initialize receive ring
//
- (BOOL)_initRxRing
{
    void *physAddr;
    int result;
    unsigned int i;
    netbuf_t nb;
    BOOL updateResult;
    int descriptorAddr;

    // Zero the RX ring descriptor memory
    // Note: txDMACommands actually holds RX descriptors (naming is backwards)
    bzero(txDMACommands, txDMACommandsSize << 3);

    // Get physical address and verify it's valid
    result = IOPhysicalFromVirtual((void *)PAGE_SIZE, &physAddr, txDMACommands);
    if (result != 0) {
        IOLog("Ethernet(GNic): Bad dma command buf - %08x\n\r", (unsigned int)txDMACommands);
        return NO;
    }

    // Allocate netbufs for each RX ring entry
    i = 0;
    if (txDMACommandsSize != 0) {
        do {
            // Allocate netbuf if not already allocated
            if (rxNetbufs[i] == NULL) {
                nb = [self allocateNetbuf];
                if (nb == NULL) {
                    IOLog("Ethernet(GNic): allocateNetbuf returned NULL in _initRxRing\n\r");
                    return NO;
                }
                rxNetbufs[i] = nb;
            }

            // Update descriptor from netbuf
            updateResult = [self _updateDescriptorFromNetBuf:rxNetbufs[i]
                                                         Desc:(void *)((int)txDMACommands + (i * 8))
                                                 ReceiveFlag:YES];
            if (!updateResult) {
                IOLog("Ethernet(GNic): cant map Netbuf to physical memory in _initRxRing\n\r");
                return NO;
            }

            i = i + 1;
        } while (i < txDMACommandsSize);
    }

    // Initialize RX ring pointers
    rxHead = 0;
    rxTail = i - 1;

    // Set bit 0x20 in byte at offset +3 of last descriptor
    descriptorAddr = (i - 1) * 8 + (int)txDMACommands;
    *(unsigned char *)(descriptorAddr + 3) = *(unsigned char *)(descriptorAddr + 3) | 0x20;

    return YES;
}

//
// Enable adapter interrupts
//
- (void)_enableAdapterInterrupts
{
    // Enable interrupts by writing mask to interrupt enable register
    _WriteGNicRegister((int)memBase, 0x40080, 0x80838787);
}

//
// Disable adapter interrupts
//
- (void)_disableAdapterInterrupts
{
    // Disable all interrupts by writing 0 to interrupt enable register
    _WriteGNicRegister((int)memBase, 0x40080, 0);
}

//
// Handle transmit interrupt
//
- (void)_transmitInterruptOccurred
{
    unsigned char statusByte;
    unsigned int ownershipBit;
    unsigned int nextHead;

    // Only process if ring is not empty
    if (txHead != txTail) {
        do {
            // Read status byte at offset +3 of descriptor
            statusByte = *(unsigned char *)(txHead * 8 + (int)rxDMACommands + 3);
            ownershipBit = statusByte & 0x80;

            // If hardware still owns descriptor (bit 0x80 set), we're done
            if ((statusByte & 0x80) != 0) {
                return;
            }

            // Descriptor is complete - increment output packet counter
            [network incrementOutputPackets];

            // Free the transmitted netbuf
            nb_free(txNetbufs[txHead]);

            // Clear the netbuf pointer
            txNetbufs[txHead] = NULL;

            // Advance to next descriptor
            nextHead = txHead + 1;
            if (nextHead >= rxDMACommandsSize) {
                nextHead = 0;
            }
            txHead = nextHead;

        } while (txHead != txTail);
    }
}

//
// Handle receive interrupt
//
- (BOOL)_receiveInterruptOccurred
{
    // Process received packets (non-polling mode)
    [self _receivePackets:NO];
    return YES;
}

//
// Transmit packet (internal)
//
- (void)_transmitPacket:(netbuf_t)packet
{
    unsigned int nextTail;
    BOOL ringFull;

    // Calculate next tail position
    nextTail = txTail + 1;
    if (nextTail >= rxDMACommandsSize) {
        nextTail = 0;
    }

    // Check if ring is full
    ringFull = (nextTail == txHead);

    if (ringFull) {
        // Ring is full, can't transmit
        IOLog("Ethernet(GNic): Freeing transmit packet eh?\n\r");
        nb_free(packet);
    } else {
        // Update descriptor from netbuf (ReceiveFlag = NO for transmit)
        [self _updateDescriptorFromNetBuf:packet
                                     Desc:(void *)(txTail * 8 + (int)rxDMACommands)
                             ReceiveFlag:NO];

        // Store netbuf in TX array for later cleanup
        txNetbufs[txTail] = packet;

        // Update tail pointer
        txTail = nextTail;

        // Kick transmit DMA
        _WriteGNicRegister((int)memBase, 0x20004, 1);
    }
}

//
// Send packet (internal) - Polled transmit for debugger
//
- (void)_sendPacket:(void *)pkt length:(unsigned int)len
{
    ns_time_t startTime, currentTime;
    unsigned int elapsedMicroseconds;
    netbuf_t nb;
    void *data;
    int bufferSize;

    // Only proceed if driver is ready
    if (!ready) {
        return;
    }

    // Disable interrupts during polling
    [self disableAllInterrupts];

    // Get start time
    IOGetTimestamp(&startTime);

    // Wait for TX ring to have space (head == tail means empty)
    do {
        // Process any pending transmit completions
        [self _transmitInterruptOccurred];

        // Get current time
        IOGetTimestamp(&currentTime);

        // Calculate elapsed time in microseconds
        elapsedMicroseconds = (unsigned int)((currentTime - startTime) / 1000);

        // Check if ring has space
        if (txHead == txTail) {
            break;  // Ring is empty, we can transmit
        }

        // Timeout after 1000 microseconds
        if (elapsedMicroseconds >= 1000) {
            IOLog("Ethernet(GNic): Polled tranmit timeout - 1\n\r");
            [self enableAllInterrupts];
            return;
        }
    } while (1);

    // Only proceed if ring is empty
    if (txHead == txTail) {
        // Allocate netbuf for the packet
        nb = [self allocateNetbuf];
        debuggerPktBuffer = (void *)nb;

        // Get data pointer and copy packet data
        data = nb_map(nb);
        bcopy(pkt, data, len);

        // Trim netbuf to actual packet size
        bufferSize = nb_size(nb);
        nb_shrink_bot(nb, bufferSize - len);

        // Transmit the packet
        [self _transmitPacket:nb];

        // Wait for transmission to complete
        do {
            // Process any pending transmit completions
            [self _transmitInterruptOccurred];

            // Get current time
            IOGetTimestamp(&currentTime);

            // Calculate elapsed time in microseconds
            elapsedMicroseconds = (unsigned int)((currentTime - startTime) / 1000);

            // Check if transmission completed (head == tail again)
            if (txHead == txTail) {
                break;  // Transmission complete
            }

            // Timeout after 1000 microseconds
            if (elapsedMicroseconds >= 1000) {
                IOLog("Ethernet(GNic): Polled tranmit timeout - 2\n\r");
                break;
            }
        } while (1);

        // Re-enable interrupts
        [self enableAllInterrupts];
    }
}

//
// Send dummy packet
//
- (void)_sendDummyPacket
{
    unsigned char dummyPacket[64];

    // Zero the packet
    bzero(dummyPacket, 0x40);

    // Set destination MAC address (bytes 0-5) to our own address
    dummyPacket[0] = myAddress.ea_byte[0];
    dummyPacket[1] = myAddress.ea_byte[1];
    dummyPacket[2] = myAddress.ea_byte[2];
    dummyPacket[3] = myAddress.ea_byte[3];
    dummyPacket[4] = myAddress.ea_byte[4];
    dummyPacket[5] = myAddress.ea_byte[5];

    // Set source MAC address (bytes 6-11) to our own address
    dummyPacket[6] = myAddress.ea_byte[0];
    dummyPacket[7] = myAddress.ea_byte[1];
    dummyPacket[8] = myAddress.ea_byte[2];
    dummyPacket[9] = myAddress.ea_byte[3];
    dummyPacket[10] = myAddress.ea_byte[4];
    dummyPacket[11] = myAddress.ea_byte[5];

    // Send the dummy packet
    [self _sendPacket:dummyPacket length:0x40];
}

//
// Stop transmit DMA
//
- (void)_stopTransmitDMA
{
    // No-op: Hardware handles TX DMA stopping automatically
}

//
// Restart transmitter
//
- (void)_restartTransmitter
{
    // No-op in this implementation
}

//
// Receive packet (internal) - Polling mode with timeout
//
- (void)_receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout
{
    ns_time_t startTime, currentTime;
    unsigned int elapsedMicroseconds;

    // Initialize output length
    *len = 0;

    // Only proceed if driver is ready
    if (!ready) {
        return;
    }

    // Disable interrupts during polling
    [self disableAllInterrupts];

    // Set up debugger packet buffer
    debuggerPktBuffer = pkt;
    debuggerPktLength = 0;

    // Get start time
    IOGetTimestamp(&startTime);

    // Poll for packets until timeout or packet received
    do {
        // Process received packets in polling mode
        [self _receivePackets:YES];

        // Get current time
        IOGetTimestamp(&currentTime);

        // Calculate elapsed time in microseconds
        elapsedMicroseconds = (unsigned int)((currentTime - startTime) / 1000);

        // Break if we received a packet
        if (debuggerPktLength != 0) {
            break;
        }

        // Continue polling if timeout not reached
    } while (elapsedMicroseconds < timeout);

    // Return the received length
    *len = debuggerPktLength;

    // Re-enable interrupts
    [self enableAllInterrupts];
}

//
// Receive packets from RX ring
//
- (BOOL)_receivePackets:(BOOL)freeRun
{
    unsigned int currentIndex;
    unsigned int previousIndex;
    unsigned int packetLength;
    unsigned int flags;
    unsigned int statusWord;
    BOOL hasError;
    BOOL isAllocated;
    netbuf_t oldNetbuf;
    netbuf_t newNetbuf;
    int descriptorAddr;
    void *packetData;
    int actualSize;
    int errorCount1, errorCount2, errorCount3, errorCount4, errorCount5;
    id superclass;
    BOOL isUnwanted;
    unsigned short lengthField;
    unsigned char byte_lo, byte_hi;

    currentIndex = rxHead;
    previousIndex = 0xFFFFFFFF;

    // Process all received packets in the ring
    do {
        do {
            currentIndex = currentIndex;
            isAllocated = NO;
            hasError = NO;

            // Get descriptor address
            descriptorAddr = currentIndex * 8 + (int)txDMACommands;

            // Check ownership bit (bit 0x80 in byte at offset +3)
            if ((*(unsigned char *)(descriptorAddr + 3) & 0x80) != 0) {
                // Hardware still owns this descriptor, we're done
                if (previousIndex != 0xFFFFFFFF) {
                    rxTail = previousIndex;
                    rxHead = currentIndex;
                }

                // Read and clear error counters
                errorCount1 = _ReadGNicRegister((int)memBase, 0x40350);
                errorCount2 = _ReadGNicRegister((int)memBase, 0x40354);
                errorCount3 = _ReadGNicRegister((int)memBase, 0x40360);
                errorCount4 = _ReadGNicRegister((int)memBase, 0x40368);
                errorCount5 = _ReadGNicRegister((int)memBase, 0x4036c);
                _WriteGNicRegister((int)memBase, 0x40350, 0);
                _WriteGNicRegister((int)memBase, 0x40354, 0);
                _WriteGNicRegister((int)memBase, 0x40360, 0);
                _WriteGNicRegister((int)memBase, 0x40368, 0);
                _WriteGNicRegister((int)memBase, 0x4036c, 0);

                // Increment error counter
                [network incrementInputErrorsBy:(errorCount1 + errorCount2 + errorCount3 +
                                                  errorCount4 + errorCount5)];

                // Kick receive register
                _WriteGNicRegister((int)memBase, 0x20024, 1);
                return YES;
            }

            // Read length field from descriptor (bytes 0-1, swap bytes)
            lengthField = *(unsigned short *)(descriptorAddr);
            byte_hi = (unsigned char)lengthField;
            byte_lo = (unsigned char)(lengthField >> 8);
            statusWord = (unsigned int)((byte_hi << 8) | byte_lo);

            // For packets > 4 bytes, read flags from end of packet
            if (statusWord > 3) {
                packetData = nb_map(rxNetbufs[currentIndex]);
                flags = *(unsigned int *)((int)packetData + statusWord - 4);
                // Byte swap flags
                flags = (flags << 0x18) | ((flags >> 8 & 0xFF) << 0x10) |
                        ((flags >> 0x10 & 0xFF) << 8) | (flags >> 0x18);
            }

            packetLength = statusWord;

            // Check for errors: bad length or error flags
            if (((packetLength - 0x3c) > 0x5b2) || ((flags & 0x380000) != 0)) {
                [network incrementInputErrors];
                hasError = YES;
            }

            // Get the netbuf for this slot
            oldNetbuf = rxNetbufs[currentIndex];

            // Check if unwanted multicast (only if not promiscuous)
            if (!promiscuousMode && !hasError) {
                superclass = [IOEthernet self];
                packetData = nb_map(oldNetbuf);
                if ([superclass isUnwantedMulticastPacket:packetData]) {
                    hasError = YES;
                }
            }

            // Reset descriptor if error
            if (hasError) {
                // Reset descriptor: length = 0x5f8, clear bit 0x40 in byte +3, set bit 0x80
                *(unsigned short *)(descriptorAddr) = 0xf805;
                descriptorAddr = descriptorAddr;
                *(unsigned char *)(descriptorAddr + 3) =
                    *(unsigned char *)(descriptorAddr + 3) & 0xbf;
                descriptorAddr = descriptorAddr;
                *(unsigned char *)(descriptorAddr + 3) =
                    *(unsigned char *)(descriptorAddr + 3) | 0x80;
            } else {
                // Allocate new netbuf for this slot
                newNetbuf = [self allocateNetbuf];
                if (newNetbuf == NULL) {
                    hasError = YES;
                    [network incrementInputErrors];
                }

                if (hasError) {
                    // Reset descriptor
                    *(unsigned short *)(descriptorAddr) = 0xf805;
                    descriptorAddr = descriptorAddr;
                    *(unsigned char *)(descriptorAddr + 3) =
                        *(unsigned char *)(descriptorAddr + 3) & 0xbf;
                    descriptorAddr = descriptorAddr;
                    *(unsigned char *)(descriptorAddr + 3) =
                        *(unsigned char *)(descriptorAddr + 3) | 0x80;
                } else {
                    // Store new netbuf in slot
                    rxNetbufs[currentIndex] = newNetbuf;
                    isAllocated = YES;

                    // Update descriptor with new netbuf
                    if (![self _updateDescriptorFromNetBuf:newNetbuf
                                                      Desc:(void *)(currentIndex * 8 + (int)txDMACommands)
                                              ReceiveFlag:YES]) {
                        IOLog("Ethernet(GNic): _updateDescriptorFromNetBuf failed for receive\n");
                    }

                    // Trim old netbuf to actual packet length
                    actualSize = nb_size(oldNetbuf);
                    nb_shrink_bot(oldNetbuf, actualSize - packetLength);
                }
            }

            // Advance to next descriptor
            currentIndex = currentIndex + 1;
            if (currentIndex >= txDMACommandsSize) {
                currentIndex = 0;
            }
            previousIndex = currentIndex - 1;
            if ((int)previousIndex < 0) {
                previousIndex = txDMACommandsSize - 1;
            }

        } while (!isAllocated);

        // Process the packet
        if (freeRun) {
            // Polling mode - send to debugger
            [self _packetToDebugger:oldNetbuf];
            // Update ring pointers and return
            if (previousIndex != 0xFFFFFFFF) {
                rxTail = previousIndex;
                rxHead = currentIndex;
            }
            // Read and clear error counters
            errorCount1 = _ReadGNicRegister((int)memBase, 0x40350);
            errorCount2 = _ReadGNicRegister((int)memBase, 0x40354);
            errorCount3 = _ReadGNicRegister((int)memBase, 0x40360);
            errorCount4 = _ReadGNicRegister((int)memBase, 0x40368);
            errorCount5 = _ReadGNicRegister((int)memBase, 0x4036c);
            _WriteGNicRegister((int)memBase, 0x40350, 0);
            _WriteGNicRegister((int)memBase, 0x40354, 0);
            _WriteGNicRegister((int)memBase, 0x40360, 0);
            _WriteGNicRegister((int)memBase, 0x40368, 0);
            _WriteGNicRegister((int)memBase, 0x4036c, 0);
            [network incrementInputErrorsBy:(errorCount1 + errorCount2 + errorCount3 +
                                              errorCount4 + errorCount5)];
            _WriteGNicRegister((int)memBase, 0x20024, 1);
            return YES;
        } else {
            // Normal mode - send to network stack
            [network handleInputPacket:oldNetbuf extra:0];
        }
    } while (1);
}

//
// Stop receive DMA
//
- (void)_stopReceiveDMA
{
    // No-op: Hardware handles RX DMA stopping automatically
}

//
// Restart receiver
//
- (void)_restartReceiver
{
    // No-op in this implementation
}

//
// Add multicast address (internal)
//
- (void)_addMulticastAddress:(enet_addr_t *)address
{
    BOOL found;
    unsigned int index;
    unsigned int regOffset;
    unsigned int regValue;
    unsigned int i;

    // Check if address already exists
    found = [self _findMulticastAddress:address Index:&index];
    if (found) {
        // Address already in list, nothing to do
        return;
    }

    // Find an empty slot in hardware multicast table (64 slots, 8 bytes each)
    regOffset = 0x10100;
    index = 0;

    do {
        // Read status register for this slot (offset +6)
        regValue = _ReadGNicRegister((int)memBase, regOffset + 6);

        // Check if bit 2 is clear (slot is available)
        if ((regValue & 2) == 0) {
            // Found empty slot - write MAC address (6 bytes)
            i = 0;
            do {
                _WriteGNicRegister((int)memBase, regOffset + i, address->ea_byte[i]);
                i = i + 1;
            } while (i < 6);

            // Mark slot as valid by setting bit 2
            _WriteGNicRegister((int)memBase, regOffset + i, 2);
            return;
        }

        // Move to next slot (8 bytes per slot)
        index = index + 1;
        regOffset = regOffset + 8;
    } while (index < 0x40);  // 64 slots total
}

//
// Remove multicast address (internal)
//
- (void)_removeMulticastAddress:(enet_addr_t *)address
{
    BOOL found;
    unsigned int index;

    // Find the address in the multicast table
    found = [self _findMulticastAddress:address Index:&index];

    if (found) {
        // Calculate register offset for this slot
        index = index * 8;

        // Clear the multicast entry (write 0 to both registers)
        _WriteGNicRegister((int)memBase, (index + 0x104) | 0x40000, 0);
        _WriteGNicRegister((int)memBase, (index + 0x100) | 0x40000, 0);
    }
}

//
// Find multicast address in list
//
- (BOOL)_findMulticastAddress:(enet_addr_t *)address Index:(unsigned int *)index
{
    unsigned int slotIndex;
    unsigned int regOffset;
    unsigned int regValue;
    unsigned int byteIndex;
    unsigned int addrByte;

    // Search through all 64 multicast table entries
    regOffset = 0x10100;
    slotIndex = 0;

    do {
        // Read status register for this slot (offset +6)
        regValue = _ReadGNicRegister((int)memBase, regOffset + 6);

        // Check if bit 2 is set (slot is valid/in use)
        if ((regValue & 2) != 0) {
            // Slot is valid, compare MAC address
            byteIndex = 0;
            while (1) {
                // Read byte from hardware register
                addrByte = _ReadGNicRegister((int)memBase, regOffset + byteIndex);

                // Compare with input address byte
                if (addrByte != (unsigned char)address->ea_byte[byteIndex]) {
                    // Mismatch, break out of comparison loop
                    break;
                }

                // Move to next byte
                byteIndex = byteIndex + 1;

                // If we've compared all 6 bytes successfully, we found it
                if (byteIndex > 5) {
                    *index = slotIndex;
                    return YES;
                }
            }
        }

        // Move to next slot (8 bytes per slot)
        slotIndex = slotIndex + 1;
        regOffset = regOffset + 8;
    } while (slotIndex < 0x40);  // 64 slots total

    // Address not found
    return NO;
}

//
// Get station address from hardware registers
//
- (void)_getStationAddress:(enet_addr_t *)addr
{
    unsigned int wordIndex;
    unsigned int byteOffset;
    unsigned int regValue;

    // Read MAC address from hardware (3 words, 2 bytes each)
    wordIndex = 0;
    do {
        // Calculate byte offset for this word
        byteOffset = wordIndex * 2;

        // Read 16-bit word from MAC address register
        // Registers start at 0x200d2 and are 2 bytes apart
        regValue = _ReadGNicRegister((int)memBase, byteOffset + 0x200d2);

        // Extract and store low byte
        addr->ea_byte[byteOffset] = (unsigned char)(regValue & 0xFFFF);

        // Extract and store high byte
        addr->ea_byte[byteOffset + 1] = (unsigned char)((regValue & 0xFFFF) >> 8);

        wordIndex = wordIndex + 1;
    } while (wordIndex < 3);
}

//
// Update descriptor from netbuf
//
- (BOOL)_updateDescriptorFromNetBuf:(netbuf_t)nb Desc:(void *)desc ReceiveFlag:(BOOL)isReceive
{
    unsigned int bufferSize;
    void *dataPtr;
    unsigned int physicalAddr;
    int result;
    unsigned int pageMask;
    unsigned char controlByte;
    unsigned short length;
    unsigned char byte_lo, byte_hi;

    // Determine buffer size
    if (isReceive) {
        bufferSize = 0x5f8;  // 1528 bytes for receive
    } else {
        bufferSize = nb_size(nb);  // Actual packet size for transmit
    }

    // Get data pointer from netbuf
    dataPtr = nb_map(nb);

    // Get physical address
    result = IOPhysicalFromVirtual((void *)PAGE_SIZE, (void **)&physicalAddr, dataPtr);
    if (result == 0) {
        // Failed to get physical address
        return NO;
    }

    // Check if buffer is contiguous (within same page boundary)
    pageMask = ~(PAGE_SIZE - 1);  // 0xFFFFF000 for 4KB pages
    if (((unsigned int)dataPtr & pageMask) !=
        (((unsigned int)dataPtr + bufferSize - 1) & pageMask)) {
        IOLog("Ethernet(GNic): Network buffer not contiguous\n\r");
        return NO;
    }

    // Fill in descriptor based on direction
    // Descriptor format (8 bytes):
    // +0: length (2 bytes, byte swapped)
    // +2: unused
    // +3: control byte
    // +4: physical address (4 bytes, byte swapped)

    // Write physical address at offset +4 (byte swapped)
    *(unsigned int *)((int)desc + 4) =
        (physicalAddr << 0x18) | ((physicalAddr >> 8 & 0xFF) << 0x10) |
        ((physicalAddr >> 0x10 & 0xFF) << 8) | (physicalAddr >> 0x18);

    // Write length at offset +0 (byte swapped)
    byte_hi = (unsigned char)(bufferSize & 0xFFFF);
    byte_lo = (unsigned char)((bufferSize & 0xFFFF) >> 8);
    *(unsigned short *)desc = (unsigned short)((byte_hi << 8) | byte_lo);

    // Set control byte at offset +3
    if (isReceive) {
        // Receive: clear bit 0x40, set bit 0x90
        controlByte = *(unsigned char *)((int)desc + 3);
        controlByte = (controlByte & 0xbf) | 0x90;
    } else {
        // Transmit: set bit 0xd0
        controlByte = *(unsigned char *)((int)desc + 3);
        controlByte = controlByte | 0xd0;
    }
    *(unsigned char *)((int)desc + 3) = controlByte;

    return YES;
}

//
// Monitor link status
//
- (void)_monitorLinkStatus
{
    unsigned short currentStatus;
    unsigned int regValue;

    // Read current link status from register 0x200e2
    currentStatus = _ReadGNicRegister((int)memBase, 0x200e2);

    // Check if link status bit 0x80 has changed
    if (((currentStatus ^ linkStatus) & 0x80) != 0) {
        if ((currentStatus & 0x80) == 0) {
            // Link is down
            IOLog("Ethernet(GNic): Link is down.\n\r");
            regValue = _ReadGNicRegister((int)memBase, 0x1006c);
            regValue = (regValue & 0xfc) | 3;
        } else {
            // Link is up
            IOLog("Ethernet(GNic): Link is up at 1Gb - Full Duplex\n\r");
            regValue = _ReadGNicRegister((int)memBase, 0x1006c);
            regValue = (regValue & 0xfc) | 1;
        }
        _WriteGNicRegister((int)memBase, 0x1006c, regValue);
    }

    // Store current status for next comparison
    linkStatus = currentStatus;
}

//
// Send packet to debugger
//
- (void)_packetToDebugger:(netbuf_t)pkt
{
    void *data;
    unsigned int length;

    // Get the packet length
    length = nb_size(pkt);
    debuggerPktLength = length;

    // Get the packet data pointer
    data = nb_map(pkt);

    // Copy packet data to debugger buffer
    bcopy(data, debuggerPktBuffer, debuggerPktLength);

    // Free the netbuf
    nb_free(pkt);
}

@end
