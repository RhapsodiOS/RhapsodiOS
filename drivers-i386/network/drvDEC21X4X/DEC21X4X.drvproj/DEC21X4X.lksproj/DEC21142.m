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
    // TODO: Store at offset 0x328
    // *(unsigned int *)(self + 0x328) = totalMemorySize;

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

    // TODO: Store allocated memory base at offset 0x324
    // *(void **)(self + 0x324) = allocatedMemory;

    // Calculate RX ring descriptor base (align to 16 bytes)
    rxRingVirt = allocatedMemory;
    if (((unsigned int)rxRingVirt & 0xf) != 0) {
        rxRingVirt = (void *)(((unsigned int)allocatedMemory + 0xf) & 0xfffffff0);
    }

    // TODO: Store RX ring base at offset 0x304
    // *(void **)(self + 0x304) = rxRingVirt;

    // Initialize 64 RX descriptors (0x40 descriptors, 0x10 bytes each)
    for (i = 0; i < 0x40; i++) {
        bzero((void *)((i * 0x10) + (unsigned int)rxRingVirt), 0x10);
        // TODO: Clear RX buffer pointer at offset 0x204 + (i * 4)
        // *(void **)(self + 0x204 + (i * 4)) = NULL;
    }

    // Calculate TX ring descriptor base (align to 16 bytes)
    // TX ring starts 0x400 bytes after RX ring
    txRingVirt = (void *)((unsigned int)rxRingVirt + 0x400);
    if (((unsigned int)txRingVirt & 0xf) != 0) {
        txRingVirt = (void *)(((unsigned int)rxRingVirt + 0x40f) & 0xfffffff0);
    }

    // TODO: Store TX ring base at offset 0x308
    // *(void **)(self + 0x308) = txRingVirt;

    // Initialize 32 TX descriptors (0x20 descriptors, 0x10 bytes each)
    for (i = 0; i < 0x20; i++) {
        bzero((void *)((i * 0x10) + (unsigned int)txRingVirt), 0x10);
        // TODO: Clear TX buffer pointer at offset 0x184 + (i * 4)
        // *(void **)(self + 0x184 + (i * 4)) = NULL;
    }

    // Calculate setup frame buffer base (align to 16 bytes)
    // Setup frame starts 0x200 bytes after TX ring
    setupFrameVirt = (void *)((unsigned int)txRingVirt + 0x200);
    if (((unsigned int)setupFrameVirt & 0xf) != 0) {
        setupFrameVirt = (void *)(((unsigned int)txRingVirt + 0x20f) & 0xfffffff0);
    }

    // TODO: Store setup frame base at offset 0x32c
    // *(void **)(self + 0x32c) = setupFrameVirt;

    // Get physical address for the setup frame
    // TODO: Get IOVmTaskSelf result
    // IOTask task = IOVmTaskSelf();
    // TODO: Store physical address at offset 0x330
    // ret = IOPhysicalFromVirtual(task, (vm_address_t)setupFrameVirt,
    //                             (IOPhysicalAddress *)(self + 0x330));

    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)setupFrameVirt,
                                (IOPhysicalAddress *)(self + 0x330));

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

    // TODO: Get base I/O port from offset 0x174
    basePort = 0;  // TODO: *(unsigned short *)(self + 0x174)

    // TODO: Get SROM address bits from offset 0x183
    sromAddressBits = 0;  // TODO: *(unsigned char *)(self + 0x183)

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

    // TODO: Get RX ring base from offset 0x304
    rxRingVirt = NULL;  // TODO: *(void **)(self + 0x304)

    // Initialize all 64 RX descriptors
    for (i = 0; i < 0x40; i++) {
        // Calculate descriptor address
        descriptor = (void *)((i * 0x10) + (unsigned int)rxRingVirt);

        // Zero the entire 16-byte descriptor
        bzero(descriptor, 0x10);

        // Clear ownership bit (bit 7 of byte 3)
        statusByte = (unsigned char *)((unsigned int)rxRingVirt + 3 + (i * 0x10));
        *statusByte = *statusByte & 0x7f;

        // Allocate netbuf if not already allocated
        // TODO: Check RX buffer array at offset 0x204 + (i * 4)
        netbuf = NULL;  // TODO: *(netbuf_t *)(self + 0x204 + (i * 4))

        if (netbuf == NULL) {
            netbuf = [self allocateNetbuf];
            if (netbuf == NULL) {
                IOPanic("allocateNetbuf returned NULL in _initRxRing");
            }
            // TODO: Store netbuf
            // *(netbuf_t *)(self + 0x204 + (i * 4)) = netbuf;
        }

        // Update descriptor from netbuf (set buffer addresses)
        // TODO: Get actual netbuf from array
        // netbuf = *(netbuf_t *)(self + 0x204 + (i * 4));
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
    // TODO: Set offset 0x31c to 0
    // *(unsigned int *)(self + 0x31c) = 0;

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

    // TODO: Get TX ring base from offset 0x308
    txRingVirt = NULL;  // TODO: *(void **)(self + 0x308)

    // Initialize all 32 TX descriptors
    for (i = 0; i < 0x20; i++) {
        // Calculate descriptor address
        descriptor = (void *)((i * 0x10) + (unsigned int)txRingVirt);

        // Zero the entire 16-byte descriptor
        bzero(descriptor, 0x10);

        // Clear ownership bit (bit 7 of byte 3)
        statusByte = (unsigned char *)((unsigned int)txRingVirt + 3 + (i * 0x10));
        *statusByte = *statusByte & 0x7f;

        // Free any existing netbuf in TX buffer array
        // TODO: Get netbuf from offset 0x184 + (i * 4)
        netbuf = NULL;  // TODO: *(netbuf_t *)(self + 0x184 + (i * 4))

        if (netbuf != NULL) {
            nb_free(netbuf);
            // TODO: Clear netbuf pointer
            // *(netbuf_t *)(self + 0x184 + (i * 4)) = NULL;
        }
    }

    // Set end-of-ring bit on last descriptor (bit 1 of byte at offset 0x1f7)
    // Last descriptor is at offset (0x1f * 0x10) + 7 = 0x1f7
    statusByte = (unsigned char *)((unsigned int)txRingVirt + 0x1f7);
    *statusByte = *statusByte | 0x02;

    // Reset TX ring indices
    // TODO: Set offset 0x30c to 0 (TX head index)
    // *(unsigned int *)(self + 0x30c) = 0;

    // TODO: Set offset 0x310 to 0 (TX tail index)
    // *(unsigned int *)(self + 0x310) = 0;

    // TODO: Set offset 0x314 to 0x20 (available TX descriptors = 32)
    // *(unsigned int *)(self + 0x314) = 0x20;

    // TODO: Set offset 0x318 to 0
    // *(unsigned int *)(self + 0x318) = 0;

    // Free existing TX queue if present
    // TODO: Get TX queue from offset 0x17c
    txQueue = nil;  // TODO: *(id *)(self + 0x17c)

    if (txQueue != nil) {
        [txQueue free];
    }

    // Allocate new IONetbufQueue with max count of 128 (0x80)
    txQueue = [[objc_getClass("IONetbufQueue") alloc] initWithMaxCount:0x80];
    // TODO: Store TX queue at offset 0x17c
    // *(id *)(self + 0x17c) = txQueue;

    if (txQueue == nil) {
        IOPanic("_initTxRing");
    }

    return YES;
}

- (BOOL)_loadSetupFilter:(BOOL)perfect
{
    unsigned int availableDescriptors;
    unsigned int txHeadIndex;
    unsigned int txTailIndex;
    void *txRingVirt;
    unsigned int *descriptor;
    unsigned char *statusByte;
    unsigned int setupFramePhysAddr;
    unsigned short basePort;
    unsigned int csrValue;
    int timeout;

    // TODO: Get available TX descriptors from offset 0x314
    availableDescriptors = 0;  // TODO: *(unsigned int *)(self + 0x314)

    // Check if any TX descriptors are available
    if (availableDescriptors == 0) {
        return NO;
    }

    // TODO: Get TX ring base from offset 0x308
    txRingVirt = NULL;  // TODO: *(void **)(self + 0x308)

    // TODO: Get TX head index from offset 0x30c
    txHeadIndex = 0;  // TODO: *(unsigned int *)(self + 0x30c)

    // Get pointer to next TX descriptor
    descriptor = (unsigned int *)((txHeadIndex * 0x10) + (unsigned int)txRingVirt);

    // Increment TX head index (wrap at 32)
    txHeadIndex++;
    if (txHeadIndex == 0x20) {
        txHeadIndex = 0;
    }
    // TODO: Store updated TX head index
    // *(unsigned int *)(self + 0x30c) = txHeadIndex;

    // Decrement available descriptor count
    availableDescriptors--;
    // TODO: Store updated count
    // *(unsigned int *)(self + 0x314) = availableDescriptors;

    // Check if end-of-ring bit is set (bit 1 of byte 7)
    statusByte = (unsigned char *)((unsigned int)descriptor + 7);
    if ((*statusByte & 0x02) != 0) {
        // End of ring - clear buffer 2 address
        descriptor[1] = 0;
    }
    else {
        // Not end of ring - clear buffer 2 address and keep end-of-ring bit clear
        descriptor[1] = 0;
        *statusByte = *statusByte | 0x02;  // Set end-of-ring bit
    }

    // Set interrupt on completion (bit 3 of byte 7)
    *statusByte = *statusByte | 0x08;

    // Set ownership bit (bit 7 of byte 7)
    *statusByte = *statusByte | 0x80;

    // Clear buffer 1 size (bits 10-0 of DWORD 1)
    descriptor[1] = descriptor[1] & 0xfffff800;

    // Set filtering type (bits 7-6 of byte 4): 0xc0 = perfect filtering
    ((unsigned char *)&descriptor[1])[0] = ((unsigned char *)&descriptor[1])[0] | 0xc0;

    // Clear buffer 2 size (bits 21-11 of DWORD 1)
    descriptor[1] = descriptor[1] & 0xffc007ff;

    // Set buffer 1 address to setup frame physical address
    // TODO: Get setup frame physical address from offset 0x330
    setupFramePhysAddr = 0;  // TODO: *(unsigned int *)(self + 0x330)
    descriptor[2] = setupFramePhysAddr;

    // Clear buffer 2 address
    descriptor[3] = 0;

    // Clear status word
    descriptor[0] = 0;

    // Set ownership bit in byte 3 of status word
    statusByte = (unsigned char *)((unsigned int)descriptor + 3);
    *statusByte = *statusByte | 0x80;

    // Trigger transmit by writing to CSR1 (transmit poll demand)
    // TODO: Get base port from offset 0x174
    basePort = 0;  // TODO: *(unsigned short *)(self + 0x174)
    outw(basePort + 8, 1);  // CSR1 is at base + 8

    // If perfect filtering requested, wait for completion
    if (perfect) {
        timeout = 10000;  // 0x270f + 1 iterations

        do {
            IODelay(5);

            // Read CSR5 (status register at base + 0x28)
            csrValue = inw(basePort + 0x28);

            // Check for transmit interrupt (bit 2)
            if ((csrValue & 0x04) != 0) {
                // Clear the interrupt by writing back
                outw(basePort + 0x28, csrValue);
                break;
            }

            timeout--;
        } while (timeout >= 0);

        // Update TX tail index
        // TODO: Get TX tail index from offset 0x310
        txTailIndex = 0;  // TODO: *(unsigned int *)(self + 0x310)
        txTailIndex++;
        if (txTailIndex == 0x20) {
            txTailIndex = 0;
        }
        // TODO: Store updated TX tail index
        // *(unsigned int *)(self + 0x310) = txTailIndex;

        // Increment available descriptor count
        // TODO: Get current available count
        availableDescriptors = 0;  // TODO: *(unsigned int *)(self + 0x314)
        availableDescriptors++;
        // TODO: Store updated count
        // *(unsigned int *)(self + 0x314) = availableDescriptors;
    }

    return YES;
}

- (BOOL)_receiveInterruptOccurred
{
    unsigned int rxIndex;
    void *rxRingVirt;
    unsigned int *descriptor;
    unsigned char *statusByte;
    unsigned int statusWord;
    unsigned int packetLength;
    netbuf_t receivedNetbuf;
    netbuf_t newNetbuf;
    void *adapterInfo;
    unsigned int errorMask;
    BOOL promiscuousMode;
    id networkInterface;
    BOOL validPacket;
    BOOL success;
    void *packetData;
    int netbufSize;
    struct objc_super superClass;

    // Reserve debugger lock for safe RX ring access
    [self reserveDebuggerLock];

    // TODO: Get RX ring index from offset 0x31c
    rxIndex = 0;  // TODO: *(unsigned int *)(self + 0x31c)

    // TODO: Get RX ring base from offset 0x304
    rxRingVirt = NULL;  // TODO: *(void **)(self + 0x304)

    while (1) {
        // Check ownership bit (bit 7 of byte 3)
        statusByte = (unsigned char *)((unsigned int)rxRingVirt + 3 + (rxIndex * 0x10));

        if (*statusByte & 0x80) {
            // Hardware still owns this descriptor - no more packets
            [self releaseDebuggerLock];
            return YES;
        }

        validPacket = NO;

        // Get pointer to descriptor
        descriptor = (unsigned int *)((rxIndex * 0x10) + (unsigned int)rxRingVirt);

        // Get status word
        statusWord = descriptor[0];

        // Get packet length (bits 13-0 of word at offset 2, minus 4 for CRC)
        packetLength = ((*(unsigned short *)((unsigned int)descriptor + 2)) & 0x3fff) - 4;

        // TODO: Get adapter info from offset 0x334
        adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

        // TODO: Get error mask from offset 0x26c in adapter info
        errorMask = 0;  // TODO: *(unsigned int *)(adapterInfo + 0x26c)

        // Validate packet: no errors, first & last segment, minimum length
        if (((statusWord & errorMask) == 0) &&
            ((statusWord & 0x300) == 0x300) &&  // Both first and last segment
            (packetLength > 0x3b)) {  // > 60 bytes (0x3b = 59)

            // TODO: Get received netbuf from array at offset 0x204 + (rxIndex * 4)
            receivedNetbuf = NULL;  // TODO: *(netbuf_t *)(self + 0x204 + (rxIndex * 4))

            // TODO: Get promiscuous mode flag from offset 0x180
            promiscuousMode = NO;  // TODO: *(BOOL *)(self + 0x180)

            // Check multicast filtering if not in promiscuous mode
            if (!promiscuousMode && ((statusWord & 0x400) != 0)) {
                // Multicast packet - check if wanted
                packetData = nb_map(receivedNetbuf);

                superClass.receiver = self;
                superClass.class = objc_getClass("IOEthernet");

                success = (BOOL)objc_msgSendSuper(&superClass,
                                                   @selector(isUnwantedMulticastPacket:),
                                                   packetData);

                if (success) {
                    // Unwanted multicast - skip processing
                    goto give_back_to_hardware;
                }
            }

            // Allocate replacement netbuf
            newNetbuf = [self allocateNetbuf];

            if (newNetbuf != NULL) {
                // TODO: Store new netbuf in array
                // *(netbuf_t *)(self + 0x204 + (rxIndex * 4)) = newNetbuf;

                validPacket = YES;

                // Update descriptor with new netbuf
                // TODO: Get RX index
                // rxIndex = *(unsigned int *)(self + 0x31c)
                success = IOUpdateDescriptorFromNetBuf(newNetbuf,
                                                       (vm_address_t)descriptor,
                                                       YES);
                if (!success) {
                    IOPanic("DEC21142: IOUpdateDescriptorFromNetBuf\n");
                }

                // Shrink received netbuf to actual packet size
                netbufSize = nb_size(receivedNetbuf);
                nb_shrink_bot(receivedNetbuf, netbufSize - packetLength);
            }
        }
        else {
            // Invalid packet - increment error counter
            // TODO: Get network interface from offset 0x178
            networkInterface = nil;  // TODO: *(id *)(self + 0x178)

            [networkInterface incrementInputErrors];
        }

give_back_to_hardware:
        // Clear descriptor status
        descriptor[0] = 0;

        // Set ownership bit - give descriptor back to hardware
        statusByte = (unsigned char *)((unsigned int)descriptor + 3);
        *statusByte = *statusByte | 0x80;

        // Increment RX index (wrap at 64)
        // TODO: Get current RX index
        rxIndex = 0;  // TODO: *(unsigned int *)(self + 0x31c)
        rxIndex++;
        if (rxIndex == 0x40) {
            rxIndex = 0;
        }
        // TODO: Store updated RX index
        // *(unsigned int *)(self + 0x31c) = rxIndex;

        // If we received a valid packet, pass it to network stack
        if (validPacket) {
            [self releaseDebuggerLock];

            // TODO: Get network interface from offset 0x178
            networkInterface = nil;  // TODO: *(id *)(self + 0x178)

            // Pass packet to network stack
            [networkInterface handleInputPacket:receivedNetbuf extra:0];

            // Re-acquire lock for next iteration
            [self reserveDebuggerLock];
        }

        // Update local variables for next iteration
        // TODO: Get updated RX index and ring base
        rxIndex = 0;     // TODO: *(unsigned int *)(self + 0x31c)
        rxRingVirt = NULL;  // TODO: *(void **)(self + 0x304)
    }
}

- (BOOL)_setAddressFiltering:(BOOL)enabled
{
    void *adapterInfo;
    void *setupFrameVirt;
    unsigned short *macAddress;
    unsigned int entryIndex;
    BOOL multicastEnabled;
    id multicastQueue;
    void *queueHead;
    void *currentEntry;
    void *nextEntry;
    unsigned int *setupEntry;
    unsigned char *macBytes;
    unsigned int macWordValue;
    int byteIndex;
    BOOL success;
    struct objc_super superClass;

    // TODO: Get adapter info from offset 0x334
    adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

    // TODO: Get setup frame base from offset 0x32c
    setupFrameVirt = NULL;  // TODO: *(void **)(self + 0x32c)

    // TODO: Get MAC address from offset 0x4c in adapter info
    macAddress = NULL;  // TODO: (unsigned short *)(adapterInfo + 0x4c)

    // Copy our MAC address to first entry (3 words = 6 bytes)
    for (entryIndex = 0; entryIndex < 3; entryIndex++) {
        ((unsigned int *)setupFrameVirt)[entryIndex] = (unsigned int)macAddress[entryIndex];
    }

    // Fill second entry with broadcast address (0xFFFF for all 3 words)
    for (entryIndex = 0; entryIndex < 3; entryIndex++) {
        ((unsigned int *)setupFrameVirt)[3 + entryIndex] = 0xFFFF;
    }

    // Start with entry 2 for multicast addresses
    entryIndex = 2;

    // TODO: Get multicast enabled flag from offset 0x181
    multicastEnabled = NO;  // TODO: *(BOOL *)(self + 0x181)

    if (multicastEnabled) {
        // Get multicast queue from superclass
        superClass.receiver = self;
        superClass.class = objc_getClass("IOEthernet");

        multicastQueue = objc_msgSendSuper(&superClass, @selector(multicastQueue));

        // Get queue head
        queueHead = ((void **)multicastQueue)[0];

        // Check if queue is not empty (head->next != head)
        if (((void **)queueHead)[0] != queueHead) {
            // Iterate through multicast addresses
            currentEntry = ((void **)queueHead)[0];

            while (currentEntry != queueHead) {
                // Get next entry before processing
                nextEntry = ((void **)currentEntry)[2];

                // Copy MAC address (6 bytes as 3 words)
                // Each entry in setup frame is at offset (entryIndex * 0xc)
                setupEntry = (unsigned int *)((unsigned int)setupFrameVirt + (entryIndex * 0xc));
                macBytes = (unsigned char *)currentEntry;

                for (byteIndex = 0; byteIndex < 3; byteIndex++) {
                    // Build word from two bytes (little endian)
                    macWordValue = (unsigned int)macBytes[byteIndex * 2] |
                                  ((unsigned int)macBytes[byteIndex * 2 + 1] << 8);
                    setupEntry[byteIndex] = macWordValue;
                }

                entryIndex++;

                // Check if we exceeded 14 multicast address limit (entries 2-15)
                if (entryIndex > 0xf) {
                    IOLog("%s: %d multicast address limit exceeded\n", [self name], 14);
                    break;
                }

                currentEntry = nextEntry;
            }
        }
    }

    // Fill remaining entries with copy of first entry
    for (; entryIndex < 0x10; entryIndex++) {
        bcopy(setupFrameVirt,
              (void *)((entryIndex * 0xc) + (unsigned int)setupFrameVirt),
              0xc);
    }

    // Load the setup filter
    success = [self _loadSetupFilter:enabled];

    return success;
}

- (void)_startReceive
{
    void *adapterInfo;
    unsigned int *csr6Register;
    unsigned short ioPortBase;

    // TODO: Get adapter info from offset 0x334
    adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

    // TODO: Get CSR6 register value from offset 0x68 in adapter info
    csr6Register = NULL;  // TODO: (unsigned int *)(adapterInfo + 0x68)

    // Set receive enable bit (bit 1)
    *csr6Register = *csr6Register | 0x02;

    // TODO: Get I/O port base from offset 0x24 in adapter info
    ioPortBase = 0;  // TODO: *(unsigned short *)(adapterInfo + 0x24)

    // Write CSR6 value to hardware
    outl(ioPortBase, *csr6Register);
}

- (void)_startTransmit
{
    void *adapterInfo;
    unsigned int *csr6Register;
    unsigned short ioPortBase;

    // TODO: Get adapter info from offset 0x334
    adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

    // TODO: Get CSR6 register value from offset 0x68 in adapter info
    csr6Register = NULL;  // TODO: (unsigned int *)(adapterInfo + 0x68)

    // Set transmit enable bit (bit 13)
    *csr6Register = *csr6Register | 0x2000;

    // TODO: Get I/O port base from offset 0x24 in adapter info
    ioPortBase = 0;  // TODO: *(unsigned short *)(adapterInfo + 0x24)

    // Write CSR6 value to hardware
    outl(ioPortBase, *csr6Register);
}

- (void)_transmitInterruptOccurred
{
}

- (BOOL)_transmitPacket:(netbuf_t)packet
{
    unsigned int availableDescriptors;
    unsigned int txHeadIndex;
    void *txRingVirt;
    unsigned char *descriptor;
    unsigned char *statusByte;
    netbuf_t *txNetbufArray;
    BOOL success;
    unsigned int txInterruptCounter;
    unsigned short basePort;

    // Perform loopback if needed
    [self performLoopback:packet];

    // Reserve debugger lock for safe TX ring access
    [self reserveDebuggerLock];

    // TODO: Get available TX descriptors from offset 0x314
    availableDescriptors = 0;  // TODO: *(unsigned int *)(self + 0x314)

    // Check if any TX descriptors are available
    if (availableDescriptors == 0) {
        [self releaseDebuggerLock];
        nb_free(packet);
        return NO;
    }

    // TODO: Get TX ring base from offset 0x308
    txRingVirt = NULL;  // TODO: *(void **)(self + 0x308)

    // TODO: Get TX head index from offset 0x30c
    txHeadIndex = 0;  // TODO: *(unsigned int *)(self + 0x30c)

    // Get pointer to next TX descriptor
    descriptor = (unsigned char *)((txHeadIndex * 0x10) + (unsigned int)txRingVirt);

    // Store netbuf in TX buffer array
    // TODO: Store at offset 0x184 + (txHeadIndex * 4)
    // *(netbuf_t *)(self + 0x184 + (txHeadIndex * 4)) = packet;

    // Check if end-of-ring bit is set (bit 1 of byte 7)
    statusByte = &descriptor[7];
    if ((*statusByte & 0x02) != 0) {
        // End of ring - clear control word and restore end-of-ring bit
        descriptor[4] = 0;
        descriptor[5] = 0;
        descriptor[6] = 0;
        descriptor[7] = 0;
        descriptor[7] = descriptor[7] | 0x02;
    }
    else {
        // Not end of ring - clear control word
        descriptor[4] = 0;
        descriptor[5] = 0;
        descriptor[6] = 0;
        descriptor[7] = 0;
    }

    // Update descriptor with netbuf buffer addresses
    success = IOUpdateDescriptorFromNetBuf(packet, (vm_address_t)descriptor, NO);

    if (!success) {
        [self releaseDebuggerLock];
        IOLog("%s: _transmitPacket: IOUpdateDescriptorFromNetBuf failed\n", [self name]);
        nb_free(packet);
        return NO;
    }

    // Set first segment bit (bit 5 of byte 7)
    descriptor[7] = descriptor[7] | 0x20;

    // Set last segment bit (bit 6 of byte 7)
    descriptor[7] = descriptor[7] | 0x40;

    // TODO: Get TX interrupt counter from offset 0x318
    txInterruptCounter = 0;  // TODO: *(unsigned int *)(self + 0x318)

    // Increment interrupt counter
    txInterruptCounter++;

    // Generate interrupt every 16 packets
    if (txInterruptCounter == 0x10) {
        // Set interrupt on completion bit (bit 7 of byte 7)
        descriptor[7] = descriptor[7] | 0x80;
        txInterruptCounter = 0;
    }
    else {
        // Clear interrupt on completion bit
        descriptor[7] = descriptor[7] & 0x7f;
    }

    // TODO: Store updated counter
    // *(unsigned int *)(self + 0x318) = txInterruptCounter;

    // Clear status word (bytes 0-3)
    descriptor[0] = 0;
    descriptor[1] = 0;
    descriptor[2] = 0;
    descriptor[3] = 0;

    // Set ownership bit in byte 3 of status word
    descriptor[3] = descriptor[3] | 0x80;

    // Increment TX head index (wrap at 32)
    txHeadIndex++;
    if (txHeadIndex == 0x20) {
        txHeadIndex = 0;
    }
    // TODO: Store updated TX head index
    // *(unsigned int *)(self + 0x30c) = txHeadIndex;

    // Decrement available descriptor count
    availableDescriptors--;
    // TODO: Store updated count
    // *(unsigned int *)(self + 0x314) = availableDescriptors;

    // Trigger transmit by writing to CSR1 (transmit poll demand)
    // TODO: Get base port from offset 0x174
    basePort = 0;  // TODO: *(unsigned short *)(self + 0x174)
    outw(basePort + 8, 1);  // CSR1 is at base + 8

    [self releaseDebuggerLock];

    return YES;
}

- (void)addMulticastAddress:(enet_addr_t *)address
{
    BOOL success;

    // Enable multicast mode
    // TODO: Set multicast enabled flag at offset 0x181
    // *(BOOL *)(self + 0x181) = YES;

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
    void *adapterInfo;

    // TODO: Get adapter info from offset 0x334
    adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

    // Call utility function to disable interrupts
    DC21X4DisableInterrupt(adapterInfo);
}

- (void)disableMulticastMode
{
    BOOL multicastEnabled;
    BOOL success;

    // TODO: Get multicast enabled flag from offset 0x181
    multicastEnabled = NO;  // TODO: *(BOOL *)(self + 0x181)

    if (multicastEnabled) {
        // Reserve debugger lock
        [self reserveDebuggerLock];

        // Update address filtering to remove multicast addresses
        success = [self _setAddressFiltering:NO];

        if (!success) {
            IOLog("%s: disable multicast mode failed\n", [self name]);
        }

        [self releaseDebuggerLock];
    }

    // Disable multicast mode
    // TODO: Clear multicast enabled flag at offset 0x181
    // *(BOOL *)(self + 0x181) = NO;
}

- (void)disablePromiscuousMode
{
    unsigned short basePort;
    unsigned short csr6Port;
    unsigned int csr6Value;

    // Clear promiscuous mode flag
    // TODO: Clear flag at offset 0x180
    // *(BOOL *)(self + 0x180) = NO;

    // Reserve debugger lock
    [self reserveDebuggerLock];

    // TODO: Get base I/O port from offset 0x174
    basePort = 0;  // TODO: *(unsigned short *)(self + 0x174)

    // CSR6 is at base + 0x30
    csr6Port = basePort + 0x30;

    // Read current CSR6 value
    csr6Value = inl(csr6Port);

    // Clear promiscuous mode bit (bit 6 = 0x40)
    csr6Value = csr6Value & 0xffffffbf;

    // Write updated value back
    outl(csr6Port, csr6Value);

    [self releaseDebuggerLock];
}

- (void)enableAdapterInterrupts
{
    void *adapterInfo;

    // TODO: Get adapter info from offset 0x334
    adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

    // Call utility function to enable interrupts
    DC21X4EnableInterrupt(adapterInfo);
}

- (BOOL)enableMulticastMode
{
    // Enable multicast mode
    // TODO: Set multicast enabled flag at offset 0x181
    // *(BOOL *)(self + 0x181) = YES;

    return YES;
}

- (BOOL)enablePromiscuousMode
{
    unsigned short basePort;
    unsigned short csr6Port;
    unsigned int csr6Value;

    // Set promiscuous mode flag
    // TODO: Set flag at offset 0x180
    // *(BOOL *)(self + 0x180) = YES;

    // Reserve debugger lock
    [self reserveDebuggerLock];

    // TODO: Get base I/O port from offset 0x174
    basePort = 0;  // TODO: *(unsigned short *)(self + 0x174)

    // CSR6 is at base + 0x30
    csr6Port = basePort + 0x30;

    // Read current CSR6 value
    csr6Value = inl(csr6Port);

    // Set promiscuous mode bit (bit 6 = 0x40)
    csr6Value = csr6Value | 0x40;

    // Write updated value back
    outl(csr6Port, csr6Value);

    [self releaseDebuggerLock];

    return YES;
}

- (void)free
{
    void *adapterInfo;
    int timerHandle;
    id networkInterface;
    netbuf_t netbuf;
    void *descriptorMemory;
    unsigned int descriptorMemorySize;
    int i;
    struct objc_super superClass;

    // TODO: Get adapter info from offset 0x334
    adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

    // Stop autosense timer if running
    // TODO: Check timer handle at offset 0x220 in adapter info
    timerHandle = 0;  // TODO: *(int *)(adapterInfo + 0x220)

    if (timerHandle != 0) {
        DC21X4StopAutoSenseTimer(adapterInfo);
    }

    // Clear any pending timeouts
    [self clearTimeout];

    // Stop the adapter
    DC21X4StopAdapter(adapterInfo);

    // Free network interface
    // TODO: Get network interface from offset 0x178
    networkInterface = nil;  // TODO: *(id *)(self + 0x178)

    if (networkInterface != nil) {
        [networkInterface free];
    }

    // Free all RX netbufs (64 descriptors)
    for (i = 0; i < 0x40; i++) {
        // TODO: Get netbuf from offset 0x204 + (i * 4)
        netbuf = NULL;  // TODO: *(netbuf_t *)(self + 0x204 + (i * 4))

        if (netbuf != NULL) {
            nb_free(netbuf);
        }
    }

    // Free all TX netbufs (32 descriptors)
    for (i = 0; i < 0x20; i++) {
        // TODO: Get netbuf from offset 0x184 + (i * 4)
        netbuf = NULL;  // TODO: *(netbuf_t *)(self + 0x184 + (i * 4))

        if (netbuf != NULL) {
            nb_free(netbuf);
        }
    }

    // Free descriptor memory
    // TODO: Get descriptor memory base from offset 0x324
    descriptorMemory = NULL;  // TODO: *(void **)(self + 0x324)

    if (descriptorMemory != NULL) {
        // TODO: Get descriptor memory size from offset 0x328
        descriptorMemorySize = 0;  // TODO: *(unsigned int *)(self + 0x328)

        IOFreeLow(descriptorMemory, descriptorMemorySize);
    }

    // Free adapter info structure
    if (adapterInfo != NULL) {
        IOFree(adapterInfo, 0x27c);  // Size: 636 bytes
    }

    // Enable all interrupts before freeing
    [self enableAllInterrupts];

    // Call superclass free
    superClass.receiver = self;
    superClass.class = objc_getClass("IOEthernet");
    objc_msgSendSuper(&superClass, @selector(free));
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
    id networkController;
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

    // Zero adapter info and store pointer
    bzero(adapterInfo, 0x27c);
    // TODO: Store adapter info pointer at offset 0x334
    // *(void **)(self + 0x334) = adapterInfo;

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
    // TODO: Store base port at offset 0x174
    // *(unsigned short *)(self + 0x174) = portList[0];
    basePort = portList[0];

    // Store base port at offset 0 in adapter info
    *(unsigned int *)adapterInfo = (unsigned int)basePort;

    // Get IRQ level
    irqLevel = [deviceDescription interrupt];
    // TODO: Store IRQ at offset 0x176
    // *(unsigned short *)(self + 0x176) = irqLevel;

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
        // TODO: Store at offset 0x183
        // *(unsigned char *)(self + 0x183) = 6;
    }
    else {
        // Use 8 bits
        // TODO: Store at offset 0x183
        // *(unsigned char *)(self + 0x183) = 8;
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

    // Reset and enable adapter
    success = [self _resetAndEnable:NO];
    if (!success) {
        IOLog("%s: _resetAndEnable failed\n", [self name]);
        [self free];
        return nil;
    }

    // Initialize flags
    // TODO: Set promiscuous mode flag at offset 0x180
    // *(BOOL *)(self + 0x180) = NO;

    // TODO: Set multicast mode flag at offset 0x181
    // *(BOOL *)(self + 0x181) = NO;

    // Get network controller class
    networkController = objc_msgSend(objc_getClass("IONetworkController"), @selector(alloc));

    // TODO: Store at offset 800 (0x320)
    // *(id *)(self + 800) = networkController;

    if (networkController == nil) {
        IOLog("%s: Failed to allocate network controller\n", [self name]);
        [self free];
        return nil;
    }

    // TODO: Set flag at offset 0x182
    // *(BOOL *)(self + 0x182) = NO;

    // Initialize registers
    success = [self _initRegisters];
    if (!success) {
        IOLog("%s: _initRegisters failed\n", [self name]);
        [self free];
        return nil;
    }

    // Copy MAC address from adapter info offset 0x4c
    bcopy((void *)((unsigned int)adapterInfo + 0x4c), macAddress, 6);

    // Attach to network with MAC address
    superClass.receiver = self;
    superClass.class = objc_getClass("IOEthernet");

    networkInterface = objc_msgSendSuper(&superClass,
                                        @selector(attachToNetworkWithAddress:),
                                        macAddress);

    // TODO: Store network interface at offset 0x178
    // *(id *)(self + 0x178) = networkInterface;

    return self;
}

- (void)interruptOccurred
{
    void *adapterInfo;
    unsigned int savedInterruptMask;
    unsigned short csr5Port;
    unsigned short csr7Port;
    unsigned int csr5Status;
    unsigned int maskedStatus;
    unsigned int timerHandle;
    id txQueue;
    int queueCount;

    // TODO: Get adapter info from offset 0x334
    adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

    // Save current interrupt mask at offset 0x1fc
    savedInterruptMask = 0;  // TODO: *(unsigned int *)(adapterInfo + 0x1fc)

    while (1) {
        // Reserve debugger lock
        [self reserveDebuggerLock];

        // TODO: Get CSR5 port (status register at offset 0x20 in adapter info)
        csr5Port = 0;  // TODO: *(unsigned short *)(adapterInfo + 0x20)

        // Read CSR5 status register
        csr5Status = inl(csr5Port);

        // Write back to CSR5 to clear interrupts
        outl(csr5Port, csr5Status);

        [self releaseDebuggerLock];

        // TODO: Get interrupt mask from offset 0x200 in adapter info
        maskedStatus = csr5Status & 0;  // TODO: csr5Status & *(unsigned int *)(adapterInfo + 0x200)

        // Check if any interrupts are pending
        if (maskedStatus == 0) {
            // No more interrupts - restore interrupt mask if changed
            // TODO: Check if mask changed
            if (0 /* TODO: *(unsigned int *)(adapterInfo + 0x1fc) */ != savedInterruptMask) {
                [self reserveDebuggerLock];

                // TODO: Get CSR7 port (interrupt enable at offset 0x28)
                csr7Port = 0;  // TODO: *(unsigned short *)(adapterInfo + 0x28)

                // TODO: Write saved mask to CSR7
                // outl(csr7Port, *(unsigned int *)(adapterInfo + 0x1fc));

                [self releaseDebuggerLock];
            }

            // Enable all interrupts before returning
            [self enableAllInterrupts];
            return;
        }

        // Handle link status interrupts (GEP, link fail/pass/change)
        if ((maskedStatus & 0x0C001010) != 0) {
            [self reserveDebuggerLock];

            // Handle GEP interrupt (bit 26)
            if ((maskedStatus & 0x04000000) != 0) {
                HandleGepInterrupt(adapterInfo);
            }

            // Check timer handle state (if 4 or 5, skip other link interrupts)
            // TODO: Get timer handle from offset 0x220
            timerHandle = 0;  // TODO: *(unsigned int *)(adapterInfo + 0x220)

            if (timerHandle - 4 < 2) {  // If timerHandle is 4 or 5
                [self releaseDebuggerLock];
                continue;  // Skip to next interrupt check
            }

            // Handle link fail interrupt (bit 12)
            if ((maskedStatus & 0x1000) != 0) {
                HandleLinkFailInterrupt(adapterInfo, &maskedStatus);
            }

            // Handle link pass interrupt (bit 4)
            if ((maskedStatus & 0x10) != 0) {
                HandleLinkPassInterrupt(adapterInfo, &maskedStatus);
            }

            // Handle link change interrupt (bit 27)
            if ((maskedStatus & 0x08000000) != 0) {
                HandleLinkChangeInterrupt(adapterInfo);
            }

            [self releaseDebuggerLock];
        }

        // Handle receive interrupt (bit 6)
        if ((maskedStatus & 0x40) != 0) {
            [self _receiveInterruptOccurred];
        }

        // Handle transmit interrupt (bit 0)
        if ((maskedStatus & 0x01) != 0) {
            [self reserveDebuggerLock];
            [self _transmitInterruptOccurred];
            [self releaseDebuggerLock];

            // Service transmit queue
            [self serviceTransmitQueue];
        }
    }
}

- (unsigned int)pendingTransmitCount
{
    id txQueue;
    int queueCount;
    unsigned int availableDescriptors;

    // TODO: Get TX queue from offset 0x17c
    txQueue = nil;  // TODO: *(id *)(self + 0x17c)

    // Get count of packets in TX queue
    queueCount = [txQueue count];

    // TODO: Get available TX descriptors from offset 0x314
    availableDescriptors = 0;  // TODO: *(unsigned int *)(self + 0x314)

    // Return (queue_count + 32) - available_descriptors
    // This gives total pending = queued packets + descriptors in use
    return (queueCount + 0x20) - availableDescriptors;
}

- (netbuf_t)receivePacket:(void *)buffer
                   length:(unsigned int *)length
                  timeout:(ns_time_t)timeout
{
    void *rxRingVirt;
    unsigned int rxIndex;
    unsigned int *descriptor;
    unsigned char *statusByte;
    unsigned int statusWord;
    unsigned int packetLength;
    void *adapterInfo;
    unsigned int errorMask;
    netbuf_t rxNetbuf;
    void *packetData;
    BOOL pollingMode;
    int timeoutMicros;

    // Initialize length to 0
    *length = 0;

    // Convert timeout from nanoseconds to microseconds
    timeoutMicros = timeout / 1000;

    // TODO: Get polling mode flag from offset 0x182
    pollingMode = NO;  // TODO: *(BOOL *)(self + 0x182)

    // Only work in polling mode (used by kernel debugger)
    if (!pollingMode) {
        return NULL;
    }

    while (1) {
        // TODO: Get RX index from offset 0x31c
        rxIndex = 0;  // TODO: *(unsigned int *)(self + 0x31c)

        // TODO: Get RX ring base from offset 0x304
        rxRingVirt = NULL;  // TODO: *(void **)(self + 0x304)

        // Check ownership bit (bit 7 of byte 3)
        statusByte = (unsigned char *)((unsigned int)rxRingVirt + 3 + (rxIndex * 0x10));

        // Wait for hardware to give us ownership
        while (*statusByte & 0x80) {
            // Still owned by hardware - check timeout
            if (timeoutMicros < 1) {
                return NULL;  // Timeout
            }

            // Delay 50 microseconds (0x32)
            IODelay(50);
            timeoutMicros -= 50;
        }

        // We own the descriptor - validate packet
        descriptor = (unsigned int *)((rxIndex * 0x10) + (unsigned int)rxRingVirt);
        statusWord = descriptor[0];

        // TODO: Get adapter info from offset 0x334
        adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

        // TODO: Get error mask from offset 0x26c in adapter info
        errorMask = 0;  // TODO: *(unsigned int *)(adapterInfo + 0x26c)

        // Check if packet is valid: no errors, first & last segment, min length
        if (((statusWord & errorMask) == 0) &&
            ((statusWord & 0x300) == 0x300) &&  // Both first and last segment
            ((*(unsigned short *)((unsigned int)descriptor + 2) & 0x3fff) > 0x3f)) {  // > 63 bytes

            // Valid packet - extract data
            packetLength = ((*(unsigned short *)((unsigned int)descriptor + 2)) & 0x3fff) - 4;
            *length = packetLength;

            // TODO: Get RX netbuf from array at offset 0x204 + (rxIndex * 4)
            rxNetbuf = NULL;  // TODO: *(netbuf_t *)(self + 0x204 + (rxIndex * 4))

            // Map netbuf to get packet data
            packetData = nb_map(rxNetbuf);

            // Copy packet data to buffer
            bcopy(packetData, buffer, packetLength);

            // Clear status and give descriptor back to hardware
            descriptor[0] = 0;
            statusByte = (unsigned char *)((unsigned int)descriptor + 3);
            *statusByte = *statusByte | 0x80;

            // Increment RX index (wrap at 64)
            rxIndex++;
            if (rxIndex == 0x40) {
                rxIndex = 0;
            }
            // TODO: Store updated RX index
            // *(unsigned int *)(self + 0x31c) = rxIndex;

            return NULL;  // Success - data copied to buffer
        }

        // Invalid packet - give descriptor back to hardware
        statusByte = (unsigned char *)((unsigned int)rxRingVirt + 3 + (rxIndex * 0x10));
        *statusByte = *statusByte | 0x80;

        // Increment RX index (wrap at 64)
        rxIndex++;
        if (rxIndex == 0x40) {
            rxIndex = 0;
        }
        // TODO: Store updated RX index
        // *(unsigned int *)(self + 0x31c) = rxIndex;
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
    BOOL pollingMode;
    BOOL interruptMode;
    unsigned int availableDescriptors;
    unsigned int txHeadIndex;
    void *txRingVirt;
    unsigned int *descriptor;
    unsigned char *statusByte;
    id debugNetbuf;
    void *netbufData;
    int netbufSize;
    BOOL success;
    unsigned short basePort;
    int pollCount;

    // TODO: Get polling mode flag from offset 0x182
    pollingMode = NO;  // TODO: *(BOOL *)(self + 0x182)

    // TODO: Get adapter info from offset 0x334
    adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

    // TODO: Get interrupt mode flag from offset 499 in adapter info
    interruptMode = NO;  // TODO: *(BOOL *)(adapterInfo + 499)

    // Only work in polling or interrupt mode (debugger use)
    if (!pollingMode && !interruptMode) {
        return NO;
    }

    // Reclaim completed TX descriptors
    [self _transmitInterruptOccurred];

    // TODO: Get available descriptors from offset 0x314
    availableDescriptors = 0;  // TODO: *(unsigned int *)(self + 0x314)

    if (availableDescriptors == 0) {
        IOLog("%s: _sendPacket: no free tx descriptors\n", [self name]);
        return NO;
    }

    // TODO: Get TX head index from offset 0x30c
    txHeadIndex = 0;  // TODO: *(unsigned int *)(self + 0x30c)

    // TODO: Get TX ring base from offset 0x308
    txRingVirt = NULL;  // TODO: *(void **)(self + 0x308)

    // Get pointer to next TX descriptor
    descriptor = (unsigned int *)((txHeadIndex * 0x10) + (unsigned int)txRingVirt);

    // Clear netbuf pointer for this descriptor
    // TODO: Clear at offset 0x184 + (txHeadIndex * 4)
    // *(netbuf_t *)(self + 0x184 + (txHeadIndex * 4)) = NULL;

    // TODO: Get debug netbuf from offset 800
    debugNetbuf = nil;  // TODO: *(id *)(self + 800)

    // Map netbuf and copy packet data
    netbufData = nb_map(debugNetbuf);
    bcopy(packet, netbufData, length);

    // Shrink netbuf to packet size
    netbufSize = nb_size(debugNetbuf);
    nb_shrink_bot(debugNetbuf, netbufSize - length);

    // Check if end-of-ring bit is set (bit 1 of byte 7)
    statusByte = (unsigned char *)((unsigned int)descriptor + 7);
    if ((*statusByte & 0x02) != 0) {
        // End of ring - clear control word and restore end-of-ring bit
        descriptor[1] = 0;
        *statusByte = *statusByte | 0x02;
    }
    else {
        // Not end of ring - clear control word
        descriptor[1] = 0;
    }

    // Update descriptor with netbuf buffer addresses
    success = IOUpdateDescriptorFromNetBuf(debugNetbuf, (vm_address_t)descriptor, NO);

    if (!success) {
        IOLog("%s: _sendPacket: IOUpdateDescriptorFromNetBuf failed\n", [self name]);
        return NO;
    }

    // Set first segment bit (bit 5 of byte 7)
    *statusByte = *statusByte | 0x20;

    // Set last segment bit (bit 6 of byte 7)
    *statusByte = *statusByte | 0x40;

    // Clear interrupt on completion bit (polling mode)
    *statusByte = *statusByte & 0x7f;

    // Clear status word (bytes 0-3)
    descriptor[0] = 0;

    // Set ownership bit in byte 3
    statusByte = (unsigned char *)((unsigned int)descriptor + 3);
    *statusByte = *statusByte | 0x80;

    // Set additional flag if in interrupt mode
    if (interruptMode) {
        statusByte = (unsigned char *)((unsigned int)descriptor + 7);
        *statusByte = *statusByte | 0x04;
    }

    // Increment TX head index (wrap at 32)
    txHeadIndex++;
    if (txHeadIndex == 0x20) {
        txHeadIndex = 0;
    }
    // TODO: Store updated TX head index
    // *(unsigned int *)(self + 0x30c) = txHeadIndex;

    // Decrement available descriptor count
    availableDescriptors--;
    // TODO: Store updated count
    // *(unsigned int *)(self + 0x314) = availableDescriptors;

    // Trigger transmit by writing to CSR1
    // TODO: Get base port from offset 0x174
    basePort = 0;  // TODO: *(unsigned short *)(self + 0x174)
    outw(basePort + 8, 1);

    // Poll for completion (up to 10000 iterations, 500μs delays)
    statusByte = (unsigned char *)((unsigned int)descriptor + 3);
    for (pollCount = 0; pollCount < 10000; pollCount++) {
        if ((*statusByte & 0x80) == 0) {
            // Hardware cleared ownership - transmission complete
            break;
        }
        IODelay(500);
    }

    // Record timing statistics
    // TODO: Store completion time at offset 0x270 in adapter info
    // *(int *)(adapterInfo + 0x270) = 10000 - pollCount;

    // TODO: Store final status at offset 0x274
    // *(unsigned int *)(adapterInfo + 0x274) = descriptor[0];

    // Check for timeout (only in non-interrupt mode)
    if ((*statusByte & 0x80) && !interruptMode) {
        IOLog("%s: _sendPacket: polling timed out\n", [self name]);
    }

    // Restore netbuf size
    nb_grow_bot(debugNetbuf, netbufSize - length);

    // Clear interrupt mode flag if set
    if (interruptMode) {
        // TODO: Clear flag at offset 499 in adapter info
        // *(BOOL *)(adapterInfo + 499) = NO;
    }

    return YES;
}

- (void)serviceTransmitQueue
{
    id txQueue;
    int checkValue;
    netbuf_t packet;

    // TODO: Get TX queue from offset 0x17c
    txQueue = nil;  // TODO: *(id *)(self + 0x17c)

    // TODO: Get available TX descriptors from offset 0x314
    checkValue = 0;  // TODO: *(int *)(self + 0x314)

    // Loop while descriptors available, queue has packets, and dequeue succeeds
    while ((checkValue != 0) &&
           ((checkValue = [txQueue count]) != 0) &&
           ((packet = (netbuf_t)[txQueue dequeue]) != NULL)) {

        // Transmit the packet
        [self _transmitPacket:packet];

        // Re-read available descriptors for next iteration
        // TODO: checkValue = *(int *)(self + 0x314);
        checkValue = 0;  // TODO
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
        // Call _verifyMediaSupport: with first value and store in global
        mediaSupported = [self _verifyMediaSupport:values[0]];
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
    void *adapterInfo;
    unsigned int timerHandle;

    // Check if power state is PM_OFF (3)
    if (state == 3) {
        // Clear polling mode flag at offset 0x182
        // TODO: *(BOOL *)(self + 0x182) = NO;

        // TODO: Get adapter info from offset 0x334
        adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

        // TODO: Get timer handle from offset 0x220 in adapter info
        timerHandle = 0;  // TODO: *(unsigned int *)(adapterInfo + 0x220)

        // If auto-sense timer is running, stop it
        if (timerHandle != 0) {
            DC21X4StopAutoSenseTimer(adapterInfo);
        }

        // Stop the adapter
        DC21X4StopAdapter(adapterInfo);

        return IO_R_SUCCESS;
    }
    else {
        // Other power states not supported
        return IO_R_UNSUPPORTED;
    }
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
    BOOL running;
    unsigned int availableDescriptors;
    id txQueue;
    int queueCount;

    // Check for NULL packet
    if (packet == NULL) {
        IOLog("%s: transmit: received NULL netbuf\n", [self name]);
        return;
    }

    // Check if adapter is running
    running = [self isRunning];

    if (!running) {
        // Not running - free the netbuf
        nb_free(packet);
        return;
    }

    // Adapter is running - try to transmit
    // First reclaim any completed TX descriptors
    [self reserveDebuggerLock];
    [self _transmitInterruptOccurred];
    [self releaseDebuggerLock];

    // Service any queued packets
    [self serviceTransmitQueue];

    // TODO: Get available TX descriptors from offset 0x314
    availableDescriptors = 0;  // TODO: *(unsigned int *)(self + 0x314)

    // TODO: Get TX queue from offset 0x17c
    txQueue = nil;  // TODO: *(id *)(self + 0x17c)

    // Decide whether to enqueue or directly transmit
    if (availableDescriptors == 0) {
        // No descriptors available - enqueue packet
        [txQueue enqueue:packet];
    }
    else {
        // Check if queue has packets
        queueCount = [txQueue count];

        if (queueCount != 0) {
            // Queue is not empty - enqueue to maintain order
            [txQueue enqueue:packet];
        }
        else {
            // Queue is empty and descriptors available - transmit directly
            [self _transmitPacket:packet];
        }
    }
}

- (unsigned int)transmitQueueCount
{
    id txQueue;
    int queueCount;

    // TODO: Get TX queue from offset 0x17c
    txQueue = nil;  // TODO: *(id *)(self + 0x17c)

    // Get count of packets in TX queue
    queueCount = [txQueue count];

    return queueCount;
}

- (unsigned int)transmitQueueSize
{
    // Maximum TX queue size is 128 (0x80)
    return 0x80;
}

@end
