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
 * DEC21142.m
 * DEC 21142 chip-specific routines for DEC 21x4x Ethernet driver
 */

#import "DEC21X4X.h"
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>

// External system variable
extern unsigned int __page_size;

@implementation DEC21142

+ (BOOL)probe:(IOPCIDevice *)deviceDescription
{
    unsigned char device, function, bus;
    unsigned char configSpace[256];
    unsigned int portRange[4];
    unsigned int irqList[2];
    unsigned int commandReg;
    unsigned int cfddReg;
    IOReturn ret;
    id instance;

    // Get PCI device location
    ret = [deviceDescription getPCIdevice:&device function:&function bus:&bus];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: unsupported PCI hardware.\n", "DEC21X4X");
        return NO;
    }

    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", "DEC21X4X", device, function, bus);

    // Get PCI configuration space
    ret = [self getPCIConfigSpace:configSpace withDeviceDescription:deviceDescription];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n", "DEC21X4X");
        return NO;
    }

    // Setup I/O port range from BAR0 (base address register 0)
    // Offset 0x10 in config space is BAR0
    unsigned int *bar0 = (unsigned int *)&configSpace[0x10];
    portRange[0] = *bar0 & 0xFFFFFF80;  // Mask to get base address
    portRange[1] = 0x80;                 // Size is 128 bytes
    portRange[2] = 0;
    portRange[3] = 0;

    ret = [deviceDescription setPortRangeList:portRange num:1];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Unable to reserve port range 0x%x-0x%x - Aborting\n",
              "DEC21X4X", portRange[0], portRange[0] + 0x7F);
        return NO;
    }

    // Setup interrupt from PCI config space
    // Offset 0x3C is the interrupt line
    unsigned char irqLevel = configSpace[0x3C];

    if (irqLevel < 2 || irqLevel > 15) {
        IOLog("%s: Invalid IRQ level (%d) assigned by PCI BIOS\n", "DEC21X4X", irqLevel);
        return NO;
    }

    irqList[0] = irqLevel;
    irqList[1] = 0;

    ret = [deviceDescription setInterruptList:irqList num:1];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Unable to reserve IRQ %d - Aborting\n", "DEC21X4X", irqList[0]);
        return NO;
    }

    // Read PCI command register (offset 0x04)
    ret = [self getPCIConfigData:&commandReg atRegister:0x04 withDeviceDescription:deviceDescription];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n", "DEC21X4X");
        return NO;
    }

    // Enable I/O space (bit 0), Memory space (bit 1), Bus Master (bit 2),
    // Memory Write and Invalidate (bit 4)
    commandReg |= 0x17;
    // Disable parity error response (bit 6)
    commandReg &= ~0x02;

    ret = [self setPCIConfigData:commandReg atRegister:0x04 withDeviceDescription:deviceDescription];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Failed PCI configuration space access - aborting\n", "DEC21X4X");
        return NO;
    }

    // Read and modify CFDD register (offset 0x40)
    ret = [self getPCIConfigData:&cfddReg atRegister:0x40 withDeviceDescription:deviceDescription];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n", "DEC21X4X");
        return NO;
    }

    // Clear bits 30-31 (sleep mode bits)
    cfddReg &= 0x3FFFFFFF;

    ret = [self setPCIConfigData:cfddReg atRegister:0x40 withDeviceDescription:deviceDescription];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Failed PCI configuration space access - aborting\n", "DEC21X4X");
        return NO;
    }

    // Wait 20ms for chip to wake up
    IOSleep(20);

    // Allocate and initialize instance
    instance = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (instance == nil) {
        IOLog("%s: Failed to alloc instance\n", "DEC21X4X");
        return NO;
    }

    return YES;
}

- (BOOL)_allocateMemory
{
    void *allocatedMemory;
    unsigned int totalMemorySize;
    void *rxRingVirt;
    void *txRingVirt;
    void *setupFrameVirt;
    IOReturn ret;
    int i;

    // Calculate total memory needed (0x6f0 bytes)
    totalMemorySize = 0x6f0;
    self->memorySize = totalMemorySize;

    // Check if we exceed one page limit
    if (__page_size < totalMemorySize) {
        IOLog("%s: 1 page limit exceeded for descriptor memory\n", [self name]);
        return NO;
    }

    // Allocate low memory (must be in first 16MB for DMA)
    allocatedMemory = IOMallocLow(totalMemorySize);
    if (allocatedMemory == NULL) {
        IOLog("%s: can't allocate 0x%x bytes of memory\n", [self name], totalMemorySize);
        return NO;
    }

    self->memoryPtr = allocatedMemory;

    // Calculate RX ring descriptor base (align to 16 bytes)
    rxRingVirt = allocatedMemory;
    if (((unsigned int)rxRingVirt & 0xf) != 0) {
        rxRingVirt = (void *)(((unsigned int)allocatedMemory + 0xf) & 0xfffffff0);
    }

    self->rxRing = rxRingVirt;

    // Initialize 64 RX descriptors (0x40 descriptors, 0x10 bytes each)
    for (i = 0; i < 0x40; i++) {
        bzero((void *)((i * 0x10) + (unsigned int)rxRingVirt), 0x10);
        self->rxNetbuf[i] = NULL;
    }

    // Calculate TX ring descriptor base (align to 16 bytes)
    // TX ring starts 0x400 bytes after RX ring
    txRingVirt = (void *)((unsigned int)rxRingVirt + 0x400);
    if (((unsigned int)txRingVirt & 0xf) != 0) {
        txRingVirt = (void *)(((unsigned int)rxRingVirt + 0x40f) & 0xfffffff0);
    }

    self->txRing = txRingVirt;

    // Initialize 32 TX descriptors (0x20 descriptors, 0x10 bytes each)
    for (i = 0; i < 0x20; i++) {
        bzero((void *)((i * 0x10) + (unsigned int)txRingVirt), 0x10);
        self->txNetbuf[i] = NULL;
    }

    // Calculate setup frame buffer base (align to 16 bytes)
    // Setup frame starts 0x200 bytes after TX ring
    setupFrameVirt = (void *)((unsigned int)txRingVirt + 0x200);
    if (((unsigned int)setupFrameVirt & 0xf) != 0) {
        setupFrameVirt = (void *)(((unsigned int)txRingVirt + 0x20f) & 0xfffffff0);
    }

    self->setupBuffer = setupFrameVirt;

    // Get physical address for the setup frame
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)setupFrameVirt,
                                (IOPhysicalAddress *)&self->setupBufferPhysical);

    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Invalid shared memory address\n", [self name]);
        return NO;
    }

    return YES;
}

- (void)_dump_srom
{
    unsigned int wordIndex;
    int byteCount;
    unsigned short basePort;
    unsigned char sromAddressBits;
    unsigned int bitIndex;
    unsigned short csr9Port;
    unsigned int addressBit;
    unsigned short dataWord;
    int bitCount;
    unsigned int readValue;
    unsigned char lowByte, highByte;

    basePort = self->ioBase;

    sromAddressBits = self->sromAddressBits;

    byteCount = 0;

    // Read all 128 words (0-127) from SROM
    for (wordIndex = 0; wordIndex < 128; wordIndex++) {
        // Print address at start of each line
        if (byteCount == 0) {
            IOLog("%03d:", wordIndex);
        }

        // CSR9 is at base + 0x48
        csr9Port = basePort + 0x48;

        // Send START condition (EEPROM 93C46 protocol)
        outw(csr9Port, 0x4800);
        IODelay(250);  // 0xfa microseconds

        outw(csr9Port, 0x4801);
        IODelay(250);

        outw(csr9Port, 0x4803);
        IODelay(250);

        outw(csr9Port, 0x4801);
        IODelay(250);

        outw(csr9Port, 0x4805);
        IODelay(250);

        outw(csr9Port, 0x4807);
        IODelay(250);

        outw(csr9Port, 0x4805);
        IODelay(250);

        outw(csr9Port, 0x4805);
        IODelay(250);

        outw(csr9Port, 0x4807);
        IODelay(250);

        outw(csr9Port, 0x4805);
        IODelay(250);

        outw(csr9Port, 0x4801);
        IODelay(250);

        outw(csr9Port, 0x4803);
        IODelay(250);

        outw(csr9Port, 0x4801);
        IODelay(250);

        // Clock in address bits (MSB first)
        for (bitIndex = 0; bitIndex < sromAddressBits; bitIndex++) {
            // Extract bit from address (MSB first)
            addressBit = (wordIndex >> ((sromAddressBits - bitIndex) - 1)) & 1;

            if (addressBit < 2) {
                addressBit = addressBit << 2;  // Shift to bit 2 position

                outw(csr9Port, addressBit | 0x4801);
                IODelay(250);

                outw(csr9Port, addressBit | 0x4803);
                IODelay(250);

                outw(csr9Port, addressBit | 0x4801);
                IODelay(250);
            }
            else {
                IOLog("bogus data in clock_in_bit\n");
            }
        }

        // Clock out 16 data bits
        dataWord = 0;
        for (bitCount = 0; bitCount < 0x10; bitCount++) {
            outw(csr9Port, 0x4803);
            IODelay(250);

            readValue = inw(csr9Port);
            IODelay(250);

            lowByte = (readValue >> 3) & 1;

            outw(csr9Port, 0x4801);
            IODelay(250);

            // Shift in bit
            dataWord = (dataWord * 2) | lowByte;
        }

        // Print the two bytes from the word
        lowByte = (unsigned char)dataWord;
        highByte = (unsigned char)(dataWord >> 8);
        IOLog(" %02x %02x", lowByte, highByte);

        byteCount += 2;

        // Format output: 8 bytes, space, 8 bytes, newline
        if (byteCount == 8) {
            IOLog("  ");  // Double space separator
        }
        else if (byteCount == 16) {
            IOLog("\n");  // Newline after 16 bytes
            byteCount = 0;
        }
    }
}

- (BOOL)_initRxRing
{
    void *rxRingVirt;
    void *descriptor;
    unsigned char *statusByte;
    netbuf_t netbuf;
    BOOL success;
    int i;

    rxRingVirt = self->rxRing;

    // Initialize all 64 RX descriptors
    for (i = 0; i < 0x40; i++) {
        // Calculate descriptor address
        descriptor = (void *)((i * 0x10) + (unsigned int)rxRingVirt);

        // Zero the entire 16-byte descriptor
        bzero(descriptor, 0x10);

        // Clear ownership bit (bit 7 of byte 3)
        statusByte = (unsigned char *)((unsigned int)rxRingVirt + 3 + (i * 0x10));
        *statusByte = *statusByte & 0x7f;

        netbuf = self->rxNetbuf[i];

        if (netbuf == NULL) {
            netbuf = [self allocateNetbuf];
            if (netbuf == NULL) {
                IOPanic("allocateNetbuf returned NULL in _initRxRing");
            }
            self->rxNetbuf[i] = netbuf;
        }

        // Update descriptor from netbuf (set buffer addresses)
        success = IOUpdateDescriptorFromNetBuf(netbuf, (vm_address_t)descriptor, YES);
        if (!success) {
            IOPanic("_initRxRing");
        }

        // Set ownership bit (bit 7 of byte 3) - give descriptor to hardware
        statusByte = (unsigned char *)((unsigned int)rxRingVirt + 3 + (i * 0x10));
        *statusByte = *statusByte | 0x80;
    }

    // Set end-of-ring bit on last descriptor (bit 1 of byte at offset 0x3f7)
    // Last descriptor is at offset (0x3f * 0x10) + 7 = 0x3f7
    statusByte = (unsigned char *)((unsigned int)rxRingVirt + 0x3f7);
    *statusByte = *statusByte | 0x02;

    // Reset RX ring index to 0
    self->rxDoneIndex = 0;

    return YES;
}

- (BOOL)_initTxRing
{
    void *txRingVirt;
    void *descriptor;
    unsigned char *statusByte;
    netbuf_t netbuf;
    id txQueue;
    unsigned int i;

    txRingVirt = self->txRing;

    // Initialize all 32 TX descriptors
    for (i = 0; i < 0x20; i++) {
        // Calculate descriptor address
        descriptor = (void *)((i * 0x10) + (unsigned int)txRingVirt);

        // Zero the entire 16-byte descriptor
        bzero(descriptor, 0x10);

        // Clear ownership bit (bit 7 of byte 3)
        statusByte = (unsigned char *)((unsigned int)txRingVirt + 3 + (i * 0x10));
        *statusByte = *statusByte & 0x7f;

        netbuf = self->txNetbuf[i];

        if (netbuf != NULL) {
            nb_free(netbuf);
            self->txNetbuf[i] = NULL;
        }
    }

    // Set end-of-ring bit on last descriptor (bit 1 of byte at offset 0x1f7)
    // Last descriptor is at offset (0x1f * 0x10) + 7 = 0x1f7
    statusByte = (unsigned char *)((unsigned int)txRingVirt + 0x1f7);
    *statusByte = *statusByte | 0x02;

    // Reset TX ring indices
    self->txPutIndex = 0;
    self->txDoneIndex = 0;
    self->txNumFree = 0x20;
    self->txIntCount = 0;

    // Free existing TX queue if present
    txQueue = self->transmitQueue;

    if (txQueue != nil) {
        [txQueue free];
        self->transmitQueue = nil;
    }

    // Allocate new IONetbufQueue with max count of 128 (0x80)
    txQueue = [[objc_getClass("IONetbufQueue") alloc] initWithMaxCount:0x80];

    if (txQueue == nil) {
        IOPanic("_initTxRing");
    }
    self->transmitQueue = txQueue;

    return YES;
}

- (BOOL)_loadSetupFilter:(BOOL)perfect
{
    unsigned char *descriptor;
    unsigned char endOfRing;
    unsigned int csrValue;
    int timeout;

    if (self->txNumFree == 0) return NO;

    descriptor = (unsigned char *)self->txRing + 16 * self->txPutIndex++;
    if (self->txPutIndex == 32) self->txPutIndex = 0;
    --self->txNumFree;

    endOfRing = descriptor[7] & 2;
    ((unsigned int *)descriptor)[1] = 0;
    descriptor[7] |= endOfRing;
    descriptor[7] |= 0x88;
    ((unsigned short *)descriptor)[2] &= 0xf800;
    descriptor[4] |= 0xc0;
    ((unsigned int *)descriptor)[1] &= 0xffc007ff;
    ((unsigned int *)descriptor)[2] = self->setupBufferPhysical;
    ((unsigned int *)descriptor)[3] = 0;
    *(unsigned int *)descriptor = 0;
    descriptor[3] |= 0x80;
    outl(self->ioBase + CSR1_TX_POLL_DEMAND, 1);

    if (perfect) {
        timeout = 9999;
        do {
            IODelay(5);
            csrValue = inl(self->ioBase + CSR5_STATUS);
            if (csrValue & 4) {
                outl(self->ioBase + CSR5_STATUS, csrValue);
                break;
            }
        } while (--timeout != -1);

        if (++self->txDoneIndex == 32) self->txDoneIndex = 0;
        ++self->txNumFree;
    }
    return YES;
}

- (BOOL)_receiveInterruptOccurred
{
    unsigned int *descriptor;
    unsigned char *descriptorBytes;
    unsigned int packetLength;
    netbuf_t receivedNetbuf;
    netbuf_t newNetbuf;
    unsigned int statusWord;
    unsigned int errorMask;
    BOOL deliverPacket;
    int netbufSize;

    [self reserveDebuggerLock];
    for (;;) {
        descriptorBytes = (unsigned char *)self->rxRing + 16 * self->rxDoneIndex;
        if ((signed char)descriptorBytes[3] < 0) break;

        deliverPacket = NO;
        descriptor = (unsigned int *)descriptorBytes;
        statusWord = descriptor[0];
        packetLength = (*((unsigned short *)descriptor + 1) & 0x3fff) - 4;
        errorMask = *((unsigned int *)self->Adapter + 155);
        if ((statusWord & errorMask) == 0 &&
            (descriptorBytes[1] & 3) == 3 && packetLength > 0x3b) {
            receivedNetbuf = self->rxNetbuf[self->rxDoneIndex];
            if (self->isPromiscuous || (descriptorBytes[1] & 4) == 0 ||
                ![super isUnwantedMulticastPacket:
                    (ether_header_t *)nb_map(receivedNetbuf)]) {
                newNetbuf = [self allocateNetbuf];
                if (newNetbuf != NULL) {
                    self->rxNetbuf[self->rxDoneIndex] = newNetbuf;
                    deliverPacket = YES;
                    if (!IOUpdateDescriptorFromNetBuf(newNetbuf,
                                                      (vm_address_t)descriptor,
                                                      YES))
                        IOPanic("DEC21142: IOUpdateDescriptorFromNetBuf\n");
                    netbufSize = nb_size(receivedNetbuf);
                    nb_shrink_bot(receivedNetbuf, netbufSize - packetLength);
                }
            }
        } else {
            [self->networkInterface incrementInputErrors];
        }

        *descriptor = 0;
        descriptorBytes[3] |= 0x80;
        if (++self->rxDoneIndex == 64) self->rxDoneIndex = 0;
        if (deliverPacket) {
            [self releaseDebuggerLock];
            [self->networkInterface handleInputPacket:receivedNetbuf extra:0];
            [self reserveDebuggerLock];
        }
    }

    [self releaseDebuggerLock];
    return YES;
}

- (BOOL)_setAddressFiltering:(BOOL)enabled
{
    unsigned short *macAddress;
    unsigned int entryIndex;
    void *queueHead;
    void *currentEntry;
    unsigned int *setupEntry;
    unsigned char *macBytes;
    unsigned int macWordValue;
    int byteIndex;

    macAddress = (unsigned short *)((unsigned char *)self->Adapter + 76);
    for (entryIndex = 0; entryIndex < 3; entryIndex++) {
        ((unsigned int *)self->setupBuffer)[entryIndex] = macAddress[entryIndex];
    }

    for (entryIndex = 0; entryIndex < 3; entryIndex++) {
        ((unsigned int *)self->setupBuffer)[3 + entryIndex] = 0xffff;
    }

    entryIndex = 2;
    if (self->multicastEnabled) {
        queueHead = [super multicastQueue];
        currentEntry = *(void **)queueHead;
        while (currentEntry != queueHead && entryIndex <= 15) {
            setupEntry = (unsigned int *)((unsigned char *)self->setupBuffer +
                                          entryIndex * 12);
            macBytes = (unsigned char *)currentEntry;
            for (byteIndex = 0; byteIndex < 3; byteIndex++) {
                macWordValue = (unsigned int)macBytes[byteIndex * 2] |
                    ((unsigned int)macBytes[byteIndex * 2 + 1] << 8);
                setupEntry[byteIndex] = macWordValue;
            }
            if (++entryIndex > 15) {
                IOLog("%s: %d multicast address limit exceeded\n", [self name], 14);
                break;
            }
            currentEntry = ((void **)currentEntry)[2];
        }
    }

    while (entryIndex <= 15) {
        bcopy(self->setupBuffer,
              (unsigned char *)self->setupBuffer + entryIndex * 12, 12);
        ++entryIndex;
    }

    return [self _loadSetupFilter:enabled];
}

- (void)_startReceive
{
    unsigned char *adapter = (unsigned char *)self->Adapter;
    unsigned int *word = (unsigned int *)adapter;

    adapter[104] |= 2;
    outl(*(unsigned short *)(adapter + 36), word[26]);
}

- (void)_startTransmit
{
    unsigned char *adapter = (unsigned char *)self->Adapter;
    unsigned int *word = (unsigned int *)adapter;

    word[26] |= 0x2000;
    outl(*(unsigned short *)(adapter + 36), word[26]);
}

- (void)_transmitInterruptOccurred
{
    unsigned char *descriptor;
    unsigned int index;

    while (self->txNumFree <= 31) {
        descriptor = (unsigned char *)self->txRing + 16 * self->txDoneIndex;
        if ((signed char)descriptor[3] < 0) break;

        if ((descriptor[7] & 8) == 0) {
            if ((*((unsigned int *)self->Adapter + 154) &
                 *(unsigned int *)descriptor) != 0) {
                [self->networkInterface incrementOutputErrors];
            } else {
                [self->networkInterface incrementOutputPackets];
            }

            if (descriptor[1] & 1) {
                [self->networkInterface incrementCollisionsBy:16];
            } else if (*(unsigned int *)descriptor & 0x78) {
                [self->networkInterface incrementCollisionsBy:
                    (descriptor[0] >> 3) & 0x0f];
            }
            if ((*(unsigned short *)descriptor & 0x202) == 0x200)
                [self->networkInterface incrementCollisions];

            index = self->txDoneIndex;
            if (self->txNetbuf[index] != NULL) {
                nb_free(self->txNetbuf[index]);
                self->txNetbuf[index] = NULL;
            }
        }

        if (++self->txDoneIndex == 32) self->txDoneIndex = 0;
        ++self->txNumFree;
    }
}

- (void)_transmitPacket:(netbuf_t)packet
{
    unsigned char *descriptor;
    unsigned char control;

    // Perform loopback if needed
    [self performLoopback:packet];

    // Reserve debugger lock for safe TX ring access
    [self reserveDebuggerLock];

    if (self->txNumFree == 0) {
        [self releaseDebuggerLock];
        nb_free(packet);
        return;
    }

    descriptor = (unsigned char *)self->txRing + 16 * self->txPutIndex;
    self->txNetbuf[self->txPutIndex] = packet;
    control = descriptor[7] & 2;
    ((unsigned int *)descriptor)[1] = 0;
    descriptor[7] |= control;

    if (!IOUpdateDescriptorFromNetBuf(packet, (vm_address_t)descriptor, NO)) {
        [self releaseDebuggerLock];
        IOLog("%s: _transmitPacket: IOUpdateDescriptorFromNetBuf failed\n", [self name]);
        nb_free(packet);
        return;
    }

    descriptor[7] |= 0x60;
    if (++self->txIntCount == 16) {
        descriptor[7] |= 0x80;
        self->txIntCount = 0;
    } else {
        descriptor[7] &= ~0x80;
    }
    *(unsigned int *)descriptor = 0;
    descriptor[3] |= 0x80;
    if (++self->txPutIndex == 32) self->txPutIndex = 0;
    --self->txNumFree;
    outl(self->ioBase + CSR1_TX_POLL_DEMAND, 1);

    [self releaseDebuggerLock];
}

- (void)addMulticastAddress:(enet_addr_t *)address
{
    BOOL success;

    self->multicastEnabled = YES;

    // Reserve debugger lock
    [self reserveDebuggerLock];

    // Update address filtering to include multicast addresses
    success = [self _setAddressFiltering:NO];

    if (!success) {
        IOLog("%s: add multicast address failed\n", [self name]);
    }

    [self releaseDebuggerLock];
}

- (netbuf_t)allocateNetbuf
{
    netbuf_t netbuf;
    unsigned int bufferAddress;
    unsigned int misalignment;
    int bufferSize;

    // Allocate network buffer (1552 bytes = 0x610)
    netbuf = nb_alloc(0x610);

    if (netbuf != NULL) {
        // Map buffer to get virtual address
        bufferAddress = nb_map(netbuf);

        // Check 32-byte alignment (mask 0x1f)
        misalignment = bufferAddress & 0x1f;

        if (misalignment != 0) {
            // Not aligned - shrink top to align to 32-byte boundary
            nb_shrink_top(netbuf, 0x20 - misalignment);
        }

        // Get buffer size and shrink to final size (1514 bytes = 0x5ea)
        bufferSize = nb_size(netbuf);
        nb_shrink_bot(netbuf, bufferSize - 0x5ea);
    }

    return netbuf;
}

- (void)disableAdapterInterrupts
{
    DC21X4DisableInterrupt(self->Adapter);
}

- (void)disableMulticastMode
{
    BOOL success;

    if (self->multicastEnabled) {
        [self reserveDebuggerLock];
        success = [self _setAddressFiltering:NO];
        if (!success) {
            IOLog("%s: disable multicast mode failed\n", [self name]);
        }
        [self releaseDebuggerLock];
    }
    self->multicastEnabled = NO;
}

- (void)disablePromiscuousMode
{
    unsigned int csr6Value;

    self->isPromiscuous = NO;
    [self reserveDebuggerLock];
    csr6Value = inl(self->ioBase + CSR6_OPMODE);
    outl(self->ioBase + CSR6_OPMODE, csr6Value & ~0x40);
    [self releaseDebuggerLock];
}

- (void)enableAdapterInterrupts
{
    DC21X4EnableInterrupt(self->Adapter);
}

- (BOOL)enableMulticastMode
{
    self->multicastEnabled = YES;
    return YES;
}

- (BOOL)enablePromiscuousMode
{
    unsigned int csr6Value;

    self->isPromiscuous = YES;
    [self reserveDebuggerLock];
    csr6Value = inl(self->ioBase + CSR6_OPMODE);
    outl(self->ioBase + CSR6_OPMODE, csr6Value | 0x40);
    [self releaseDebuggerLock];
    return YES;
}

- (id)free
{
    void *adapterInfo;
    id networkInterface;
    unsigned int i;
    struct objc_super superClass;

    adapterInfo = self->Adapter;
    if (*((unsigned int *)adapterInfo + 136) != 0)
        DC21X4StopAutoSenseTimer(adapterInfo);
    [self clearTimeout];
    DC21X4StopAdapter(adapterInfo);
    networkInterface = self->networkInterface;
    if (networkInterface != NULL) [networkInterface free];
    for (i = 0; i < 64; i++)
        if (self->rxNetbuf[i] != NULL) nb_free(self->rxNetbuf[i]);
    for (i = 0; i < 32; i++)
        if (self->txNetbuf[i] != NULL) nb_free(self->txNetbuf[i]);
    if (self->memoryPtr != NULL)
        IOFreeLow(self->memoryPtr, self->memorySize);
    if (adapterInfo != NULL) IOFree(adapterInfo, 636);
    [self enableAllInterrupts];
    superClass.receiver = self;
    superClass.class = objc_getClass("IOEthernet");
    return (id)objc_msgSendSuper(&superClass, @selector(free));
}

- (IOReturn)getIntValues:(unsigned int *)values
            forParameter:(IOParameterName)parameter
                   count:(unsigned int *)count
{
    id deviceDescription;
    IOReturn ret;
    unsigned char device, function, bus;
    struct objc_super superClass;

    // Check for custom parameter: DEC21X4X_VERIFYMEDIA
    if (strcmp(parameter, "DEC21X4X_VERIFYMEDIA") == 0 && *count != 0) {
        // Return media supported flag
        *values = (unsigned int)mediaSupported;
        *count = 1;
        return IO_R_SUCCESS;
    }

    // Check for custom parameter: DEC21X4X_GETLOCATION
    if (strcmp(parameter, "DEC21X4X_GETLOCATION") == 0 && *count != 0) {
        // Get device description
        deviceDescription = [self deviceDescription];

        // Get PCI device location
        ret = [deviceDescription getPCIdevice:&device function:&function bus:&bus];

        if (ret == IO_R_SUCCESS) {
            // Pack device, function, bus into single value
            // Format: (device << 16) | (function << 8) | bus
            *values = ((unsigned int)device << 16) |
                     ((unsigned int)function << 8) |
                     (unsigned int)bus;
            *count = 1;
            return IO_R_SUCCESS;
        }
    }

    // Not a custom parameter - call superclass
    superClass.receiver = self;
    superClass.class = objc_getClass("IOEthernet");

    return (IOReturn)objc_msgSendSuper(&superClass,
                                       @selector(getIntValues:forParameter:count:),
                                       values, parameter, count);
}

- (IOReturn)getPowerManagement:(PMPowerManagementState *)state
{
    return IO_R_UNSUPPORTED;
}

- (IOReturn)getPowerState:(PMPowerState *)state
{
    return IO_R_UNSUPPORTED;
}

- initFromDeviceDescription:(IOPCIDevice *)deviceDescription
{
    void *adapterInfo;
    IOReturn ret;
    unsigned int deviceVendorID;
    unsigned int chipRevision;
    unsigned char chipStep;
    const unsigned short *portList;
    unsigned short basePort;
    unsigned char irqLevel;
    const char *chipName;
    id configTable;
    const char *sromBitsStr;
    const char *connectorStr;
    int connectorIndex;
    unsigned int mediaType;
    unsigned char macAddress[6];
    BOOL success;
    id networkInterface;
    struct objc_super superClass;

    // Call superclass init
    superClass.receiver = self;
    superClass.class = objc_getClass("IOEthernet");

    if (!objc_msgSendSuper(&superClass, @selector(initFromDeviceDescription:), deviceDescription)) {
        return nil;
    }

    // Allocate adapter info structure (636 bytes = 0x27c)
    adapterInfo = IOMalloc(0x27c);
    if (adapterInfo == NULL) {
        IOLog("%s: Unable to allocate memory for adapter info\n", [self name]);
        [self free];
        return nil;
    }

    // Zero adapter info and retain it in the instance.
    bzero(adapterInfo, 0x27c);
    self->Adapter = adapterInfo;

    // Store back pointer to self at offset 0x278 in adapter info
    ((id *)adapterInfo)[0x278 / sizeof(id)] = self;

    // Initialize timer handle to 0 at offset 0x220
    *(unsigned int *)((unsigned int)adapterInfo + 0x220) = 0;

    // Get device/vendor ID from PCI config space
    ret = [[self class] getPCIConfigData:&deviceVendorID
                              atRegister:0
                    withDeviceDescription:deviceDescription];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Failed to read PCI configuration\n", [self name]);
        [self free];
        return nil;
    }

    // Store chip revision at offset 0x54
    *(unsigned int *)((unsigned int)adapterInfo + 0x54) = deviceVendorID;

    // Get chip step/revision from PCI config space offset 8
    ret = [[self class] getPCIConfigData:&chipStep
                              atRegister:8
                    withDeviceDescription:deviceDescription];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Failed to read chip revision\n", [self name]);
        [self free];
        return nil;
    }

    // Store chip step at offset 0x08
    *(unsigned char *)((unsigned int)adapterInfo + 8) = chipStep;

    // Get I/O port base
    portList = [deviceDescription portRangeList];
    basePort = portList[0];
    self->ioBase = basePort;

    // Store base port at offset 0 in adapter info
    *(unsigned int *)adapterInfo = (unsigned int)basePort;

    // Get IRQ level
    irqLevel = [deviceDescription interrupt];
    self->irq = irqLevel;

    // Handle DC21140 revision detection
    chipRevision = *(unsigned int *)((unsigned int)adapterInfo + 0x54);
    if (chipRevision == 0x191011) {
        chipStep = *(unsigned char *)((unsigned int)adapterInfo + 8);
        if ((chipStep & 0xF0) != 0x10) {
            // Not true DC21143 - mark as variant
            *(unsigned int *)((unsigned int)adapterInfo + 0x54) = 0xFF1011;
            chipRevision = 0xFF1011;
        }
    }

    // Determine chip name based on revision
    switch (chipRevision) {
        case 0x21011:
            chipName = "DC21040";
            break;
        case 0x141011:
            chipName = "DC21041";
            break;
        case 0x91011:
            chipName = "DC21140";
            break;
        case 0x191011:
            chipName = "DC21143";
            break;
        case 0xFF1011:
            chipName = "DC21140 (variant)";
            break;
        default:
            IOLog("%s: Unknown chip revision 0x%x\n", [self name], chipRevision);
            [self free];
            return nil;
    }

    // Log device information
    IOLog("%s: %s (Rev:0x%02x) at port 0x%x irq %d\n",
          [self name], chipName, chipStep, basePort, irqLevel);

    // Get SROM address bits from config table
    configTable = [deviceDescription configTable];
    sromBitsStr = [[configTable valueForStringKey:"SROM Address Bits"] cString];

    if (sromBitsStr == NULL || strcmp(sromBitsStr, "8") != 0) {
        // Default to 6 bits
        self->sromAddressBits = 6;
    }
    else {
        // Use 8 bits
        self->sromAddressBits = 8;
    }

    // Free SROM bits string if allocated
    if (sromBitsStr != NULL) {
        [[configTable valueForStringKey:"SROM Address Bits"] free];
    }

    // Set default media type to 0x900
    *(unsigned int *)((unsigned int)adapterInfo + 0x78) = 0x900;

    // Get connector type from config table
    connectorStr = [[configTable valueForStringKey:"Connector"] cString];

    connectorIndex = 0;
    if (connectorStr != NULL) {
        // Search connector table
        for (int i = 0; i < CONNECTOR_TABLE_COUNT; i++) {
            if (strcmp(connectorStr, connectorTable[i]) == 0) {
                connectorIndex = i;
                break;
            }
        }

        // Free connector string
        [[configTable valueForStringKey:"Connector"] free];
    }

    // Set media type based on connector
    mediaType = connectorMediaMap[connectorIndex];
    *(unsigned int *)((unsigned int)adapterInfo + 0x78) = mediaType;

    // Log media type
    IOLog("%s: Media type: 0x%x\n", [self name], mediaType);

    success = [self _allocateMemory];
    if (!success) {
        IOLog("%s: Memory allocation error\n", [self name]);
        [self free];
        return nil;
    }

    self->isPromiscuous = NO;
    self->multicastEnabled = NO;
    self->KDB_txBuf = [self allocateNetbuf];
    if (self->KDB_txBuf == NULL) {
        IOLog("%s: Couldn't allocate KDB netbuf\n", [self name]);
        [self free];
        return nil;
    }

    self->resetAndEnabled = NO;
    success = [self resetAndEnable:YES];
    if (!success) {
        [self free];
        return nil;
    }

    bcopy((char *)self->Adapter + 76, macAddress, sizeof(macAddress));
    superClass.receiver = self;
    superClass.class = objc_getClass("IOEthernet");
    networkInterface = objc_msgSendSuper(&superClass,
                                        @selector(attachToNetworkWithAddress:),
                                        macAddress);
    self->networkInterface = networkInterface;

    return self;
}

- (void)interruptOccurred
{
    unsigned char *adapterInfo;
    unsigned int *adapterWords;
    unsigned int savedInterruptMask;
    unsigned int csr5Status;
    unsigned int maskedStatus;
    unsigned int timerHandle;

    adapterInfo = (unsigned char *)self->Adapter;
    adapterWords = (unsigned int *)adapterInfo;
    savedInterruptMask = adapterWords[127];

    while (1) {
        [self reserveDebuggerLock];
        csr5Status = inl(*(unsigned short *)(adapterInfo + 32));
        outl(*(unsigned short *)(adapterInfo + 32), csr5Status);
        [self releaseDebuggerLock];

        maskedStatus = csr5Status & adapterWords[128];
        if (maskedStatus == 0) {
            break;
        }

        if ((maskedStatus & 0x0c001010) != 0) {
            [self reserveDebuggerLock];
            if (maskedStatus & 0x04000000) HandleGepInterrupt(adapterInfo);
            timerHandle = adapterWords[136];
            if (timerHandle - 4 <= 1) {
                [self releaseDebuggerLock];
                break;
            }
            if (maskedStatus & 0x1000)
                HandleLinkFailInterrupt(adapterInfo, &maskedStatus);
            if (maskedStatus & 0x10)
                HandleLinkPassInterrupt(adapterInfo, &maskedStatus);
            if (maskedStatus & 0x08000000)
                HandleLinkChangeInterrupt(adapterInfo);
            [self releaseDebuggerLock];
        }

        if (maskedStatus & 0x40)
            [self _receiveInterruptOccurred];
        if (maskedStatus & 1) {
            [self reserveDebuggerLock];
            [self _transmitInterruptOccurred];
            [self releaseDebuggerLock];
            [self serviceTransmitQueue];
        }
    }

    if (adapterWords[127] != savedInterruptMask) {
        [self reserveDebuggerLock];
        outl(*(unsigned short *)(adapterInfo + 40), adapterWords[127]);
        [self releaseDebuggerLock];
    }
    [self enableAllInterrupts];
}


- (unsigned int)pendingTransmitCount
{
    return [self->transmitQueue count] - self->txNumFree + 32;
}

- (void)receivePacket:(void *)buffer
                   length:(unsigned int *)length
                  timeout:(unsigned int)timeout
{
    unsigned char *descriptorBytes;
    unsigned int *descriptor;
    unsigned int packetLength;
    unsigned int errorMask;
    netbuf_t rxNetbuf;
    void *packetData;
    int timeoutMicros;

    *length = 0;
    timeoutMicros = timeout * 1000;
    if (!self->resetAndEnabled) return;

    for (;;) {
        descriptorBytes = (unsigned char *)self->rxRing +
                          16 * self->rxDoneIndex;
        while ((signed char)descriptorBytes[3] < 0) {
            if (timeoutMicros <= 0) return;
            IODelay(50);
            timeoutMicros -= 50;
            descriptorBytes = (unsigned char *)self->rxRing +
                              16 * self->rxDoneIndex;
        }

        descriptor = (unsigned int *)descriptorBytes;
        errorMask = *((unsigned int *)self->Adapter + 155);
        if ((errorMask & descriptor[0]) == 0 &&
            (descriptorBytes[1] & 3) == 3 &&
            (*((unsigned short *)descriptor + 1) & 0x3fff) > 0x3f) {
            packetLength = (*((unsigned short *)descriptor + 1) & 0x3fff) - 4;
            *length = packetLength;
            rxNetbuf = self->rxNetbuf[self->rxDoneIndex];
            packetData = nb_map(rxNetbuf);
            bcopy(packetData, buffer, packetLength);
            *descriptor = 0;
            descriptorBytes[3] |= 0x80;
            if (++self->rxDoneIndex == 64) self->rxDoneIndex = 0;
            return;
        }

        descriptorBytes[3] |= 0x80;
        if (++self->rxDoneIndex == 64) self->rxDoneIndex = 0;
    }
}

- (void)removeMulticastAddress:(enet_addr_t *)address
{
    BOOL success;

    // Reserve debugger lock
    [self reserveDebuggerLock];

    // Update address filtering to remove multicast addresses
    success = [self _setAddressFiltering:NO];

    if (!success) {
        IOLog("%s: remove multicast address failed\n", [self name]);
    }

    [self releaseDebuggerLock];
}

- (BOOL)sendPacket:(netbuf_t)packet length:(unsigned int)length
{
    void *adapterInfo;
    BOOL interruptMode;
    unsigned int *descriptor;
    unsigned char *statusByte;
    unsigned char endOfRing;
    void *netbufData;
    int netbufSize;
    int pollCount;

    adapterInfo = self->Adapter;
    interruptMode = *((unsigned char *)adapterInfo + 499);

    if (!self->resetAndEnabled && !interruptMode) {
        return NO;
    }

    [self _transmitInterruptOccurred];
    if (self->txNumFree == 0) {
        IOLog("%s: _sendPacket: no free tx descriptors\n", [self name]);
        return NO;
    }

    descriptor = (unsigned int *)((unsigned char *)self->txRing +
                                  16 * self->txPutIndex);
    self->txNetbuf[self->txPutIndex] = NULL;
    netbufData = nb_map(self->KDB_txBuf);
    bcopy(packet, netbufData, length);
    netbufSize = nb_size(self->KDB_txBuf);
    nb_shrink_bot(self->KDB_txBuf, netbufSize - length);

    statusByte = (unsigned char *)descriptor + 7;
    endOfRing = *statusByte & 2;
    descriptor[1] = 0;
    *statusByte |= endOfRing;

    if (!IOUpdateDescriptorFromNetBuf(self->KDB_txBuf,
                                      (vm_address_t)descriptor, NO)) {
        IOLog("%s: _sendPacket: IOUpdateDescriptorFromNetBuf failed\n", [self name]);
        return NO;
    }

    *statusByte |= 0x60;
    *statusByte &= ~0x80;
    descriptor[0] = 0;
    ((unsigned char *)descriptor)[3] |= 0x80;
    if (interruptMode) ((unsigned char *)descriptor)[7] |= 4;
    if (++self->txPutIndex == 32) self->txPutIndex = 0;
    --self->txNumFree;
    outl(self->ioBase + CSR1_TX_POLL_DEMAND, 1);

    statusByte = (unsigned char *)descriptor + 3;
    for (pollCount = 0; pollCount < 10000; pollCount++) {
        if ((*statusByte & 0x80) == 0) break;
        IODelay(500);
    }

    *((unsigned int *)adapterInfo + 156) = 10000 - pollCount;
    *((unsigned int *)adapterInfo + 157) = descriptor[0];

    if ((*statusByte & 0x80) && !interruptMode) {
        IOLog("%s: _sendPacket: polling timed out\n", [self name]);
    }

    nb_grow_bot(self->KDB_txBuf, netbufSize - length);
    if (interruptMode) *((unsigned char *)adapterInfo + 499) = NO;

    return YES;
}

- (void)serviceTransmitQueue
{
    netbuf_t packet;

    while (self->txNumFree != 0 && [self->transmitQueue count] != 0) {
        packet = (netbuf_t)[self->transmitQueue dequeue];
        if (packet == NULL) break;
        [self _transmitPacket:packet];
    }
}

- (IOReturn)setIntValues:(unsigned int *)values
            forParameter:(IOParameterName)parameter
                   count:(unsigned int)count
{
    int compareLength;
    const char *paramStr;
    const char *targetStr;
    BOOL match;
    struct objc_super superClass;

    // Check if parameter matches "DEC21X4X_VERIFYMEDIA" (21 characters)
    compareLength = 0x15;  // 21 bytes
    match = YES;
    paramStr = parameter;
    targetStr = "DEC21X4X_VERIFYMEDIA";

    // Manual character-by-character comparison
    do {
        if (compareLength == 0) {
            break;
        }
        compareLength--;
        match = (*paramStr == *targetStr);
        paramStr++;
        targetStr++;
    } while (match);

    // If parameter matches and count is not zero
    if (match && (count != 0)) {
        // Call verifyMediaSupport: with first value and store in global
        mediaSupported = [self verifyMediaSupport:values[0]];
        return IO_R_SUCCESS;
    }
    else {
        // Pass to superclass
        superClass.receiver = self;
        superClass.class = objc_getClass("IOEthernet");
        return objc_msgSendSuper(&superClass,
                                 @selector(setIntValues:forParameter:count:),
                                 values, parameter, count);
    }
}

- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{
    // Power management not supported - return 0xfffffd39
    return IO_R_UNSUPPORTED;
}

- (IOReturn)setPowerState:(PMPowerState)state
{
    unsigned int *adapterWords;

    if (state != 3) return IO_R_UNSUPPORTED;
    self->resetAndEnabled = NO;
    adapterWords = (unsigned int *)self->Adapter;
    if (adapterWords[136] != 0)
        DC21X4StopAutoSenseTimer(self->Adapter);
    DC21X4StopAdapter(self->Adapter);
    return IO_R_SUCCESS;
}

- (void)timeoutOccurred
{
    BOOL running;

    // Check if adapter is running
    running = [self isRunning];

    if (running) {
        // Reclaim any completed TX descriptors
        [self reserveDebuggerLock];
        [self _transmitInterruptOccurred];
        [self releaseDebuggerLock];

        // Service the transmit queue
        [self serviceTransmitQueue];
    }
}

- (void)transmit:(netbuf_t)packet
{
    if (packet == NULL) {
        IOLog("%s: transmit: received NULL netbuf\n", [self name]);
        return;
    }

    if (![self isRunning]) {
        nb_free(packet);
        return;
    }

    [self reserveDebuggerLock];
    [self _transmitInterruptOccurred];
    [self releaseDebuggerLock];
    [self serviceTransmitQueue];

    if (self->txNumFree != 0 && [self->transmitQueue count] == 0)
        [self _transmitPacket:packet];
    else
        [self->transmitQueue enqueue:packet];
}

- (unsigned int)transmitQueueCount
{
    return [self->transmitQueue count];
}

- (unsigned int)transmitQueueSize
{
    // Maximum TX queue size is 128 (0x80)
    return 0x80;
}

@end
