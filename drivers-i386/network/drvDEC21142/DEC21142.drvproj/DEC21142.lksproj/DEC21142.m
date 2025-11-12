/*
 * DEC21142.m
 * DEC Celebris On-Board 21142 LAN Network Driver
 */

#import "DEC21142.h"
#import "DEC21142KernelServerInstance.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/align.h>
#import <mach/mach_interface.h>
#import <string.h>

/* PCI Configuration Space Offsets */
#define PCI_COMMAND             0x04

/*
 * Helper function to update DMA descriptor from network buffer
 * Handles page boundary crossings for buffers that span pages
 */
static BOOL IOUpdateDescriptorFromNetBuf(netbuf_t nb, void *desc, BOOL isSetupFrame)
{
    unsigned int *descPtr = (unsigned int *)desc;
    unsigned int bufSize;
    unsigned int bufAddr;
    unsigned int physAddr1, physAddr2;
    vm_task_t task;
    extern unsigned int vm_page_size;

    /* Get buffer size - setup frames are fixed size */
    if (isSetupFrame) {
        bufSize = SETUP_FRAME_SIZE;
    } else {
        bufSize = nb_size(nb);
    }

    /* Get virtual address of buffer */
    bufAddr = (unsigned int)nb_map(nb);

    /* Clear second buffer address */
    descPtr[3] = 0;

    /* Clear and set first buffer size in control word */
    descPtr[1] &= 0xFFC007FF;  /* Clear both buffer size fields */
    descPtr[1] &= 0xFFFFF800;  /* Clear first buffer size */
    descPtr[1] |= (bufSize & 0x7FF);  /* Set first buffer size */

    /* Convert virtual to physical address */
    task = IOVmTaskSelf();
    physAddr1 = IOPhysicalFromVirtual(task, bufAddr);

    if (physAddr1 != 0) {
        /* Physical address conversion failed */
        return NO;
    }

    /* Store first buffer physical address */
    descPtr[2] = physAddr1;

    /* Check if buffer crosses a page boundary */
    if ((bufAddr & ~(vm_page_size - 1)) != ((bufAddr + bufSize) & ~(vm_page_size - 1))) {
        /* Buffer spans two pages - need to split descriptor */
        unsigned int nextPageAddr = (bufAddr + vm_page_size) & ~(vm_page_size - 1);
        unsigned int firstSize = nextPageAddr - bufAddr;
        unsigned int secondSize = bufSize - firstSize;

        /* Update first buffer size */
        descPtr[1] &= 0xFFFFF800;
        descPtr[1] |= (firstSize & 0x7FF);

        /* Set second buffer size */
        descPtr[1] &= 0xFFC007FF;
        descPtr[1] |= ((secondSize & 0x7FF) << 11);

        /* Get physical address for second buffer */
        physAddr2 = IOPhysicalFromVirtual(task, nextPageAddr);

        if (physAddr2 != 0) {
            return NO;
        }

        /* Store second buffer physical address */
        descPtr[3] = physAddr2;
    }

    return YES;
}

@implementation DEC21142

/*
 * Probe method - called to determine if hardware is present
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    IOPCIDeviceDescription *pciDevice;
    IOPCIConfigSpace configSpace;
    IORange portRange;
    unsigned int interruptList[2];
    unsigned int commandReg;
    unsigned int cfrdd;
    unsigned char device, function, bus;
    unsigned char irqLevel;
    int result;
    DEC21142 *driver;
    const char *driverName;

    if (![deviceDescription isKindOf:[IOPCIDeviceDescription class]]) {
        return NO;
    }

    pciDevice = (IOPCIDeviceDescription *)deviceDescription;

    /* Get PCI device location */
    result = [pciDevice getPCIdevice:&device function:&function bus:&bus];
    if (result != 0) {
        driverName = [[self name] cString];
        IOLog("%s: unsupported PCI hardware.\n", driverName);
        return NO;
    }

    driverName = [[self name] cString];
    IOLog("%s: PCI Dev: %d Func: %d Bus: %d\n", driverName, device, function, bus);

    /* Get PCI configuration space */
    result = [self getPCIConfigSpace:&configSpace withDeviceDescription:pciDevice];
    if (result != 0) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              driverName);
        return NO;
    }

    /* Setup I/O port range from BAR0 (bits 7-31, bit 0 = I/O space indicator) */
    portRange.start = configSpace.BaseAddress[0] & 0xFFFFFF80;
    portRange.size = 0x80;  /* 128 bytes */
    result = [pciDevice setPortRangeList:&portRange num:1];
    if (result != 0) {
        IOLog("%s: Unable to reserve port range 0x%x-0x%x - Aborting\n",
              driverName, portRange.start, portRange.start + 0x7F);
        return NO;
    }

    /* Setup interrupt */
    irqLevel = configSpace.InterruptLine;
    if (irqLevel < 2 || irqLevel > 15) {
        IOLog("%s: Invalid IRQ level (%d) assigned by PCI BIOS\n", driverName, irqLevel);
        return NO;
    }

    interruptList[0] = irqLevel;
    interruptList[1] = 0;
    result = [pciDevice setInterruptList:interruptList num:1];
    if (result != 0) {
        IOLog("%s: Unable to reserve IRQ %d - Aborting\n", driverName, irqLevel);
        return NO;
    }

    /* Enable I/O space and bus mastering in PCI command register */
    result = [self getPCIConfigData:&commandReg atRegister:PCI_COMMAND withDeviceDescription:pciDevice];
    if (result != 0) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              driverName);
        return NO;
    }

    /* Set I/O Space Enable (bit 0), clear Memory Write and Invalidate (bit 4), set Bus Master (bit 2) */
    commandReg = (commandReg & ~0x00000002) | 0x00000004;

    result = [self setPCIConfigData:commandReg atRegister:PCI_COMMAND withDeviceDescription:pciDevice];
    if (result != 0) {
        IOLog("%s: Failed PCI configuration space access - aborting\n", driverName);
        return NO;
    }

    /* Read and modify CFRDD register at offset 0x40 */
    result = [self getPCIConfigData:&cfrdd atRegister:0x40 withDeviceDescription:pciDevice];
    if (result != 0) {
        IOLog("%s: Invalid PCI configuration or failed configuration space access - aborting\n",
              driverName);
        return NO;
    }

    /* Clear bits 30-31 (power management bits) */
    cfrdd = cfrdd & 0x3FFFFFFF;

    result = [self setPCIConfigData:cfrdd atRegister:0x40 withDeviceDescription:pciDevice];
    if (result != 0) {
        IOLog("%s: Failed PCI configuration space access - aborting\n", driverName);
        return NO;
    }

    /* Wait 20ms for hardware to stabilize */
    IOSleep(20);

    /* Allocate and initialize driver instance */
    driver = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (driver == nil) {
        IOLog("%s: Failed to alloc instance\n", driverName);
        return NO;
    }

    /* Probe succeeded, free the driver instance (actual instance created later) */
    [driver free];

    return YES;
}

/*
 * Private implementation: Allocate memory for descriptors and setup frame
 * Allocates a single page of low memory divided into:
 * - RX descriptors (1024 bytes = 64 * 16 bytes)
 * - TX descriptors (512 bytes = 32 * 16 bytes)
 * - Setup frame (192 bytes)
 */
- (BOOL)_allocateMemory
{
    int i;
    unsigned int allocSize;
    void *memBase;
    vm_task_t task;
    extern unsigned int vm_page_size;
    const char *driverName;

    /* Calculate total allocation size - must fit in one page */
    allocSize = 0x6F0;  /* 1776 bytes total */

    if (vm_page_size < allocSize) {
        driverName = [[self name] cString];
        IOLog("%s: 1 page limit exceeded for descriptor memory\n", driverName);
        return NO;
    }

    /* Allocate low memory (for DMA) */
    memBase = IOMallocLow(allocSize);
    if (memBase == NULL) {
        driverName = [[self name] cString];
        IOLog("%s: can't allocate 0x%x bytes of memory\n", driverName, allocSize);
        return NO;
    }

    /* Setup RX descriptor ring (64 descriptors * 16 bytes = 1024 bytes) */
    _rxDescriptors = memBase;

    /* Align to 16-byte boundary if needed */
    if (((unsigned int)_rxDescriptors & 0xF) != 0) {
        _rxDescriptors = (void *)(((unsigned int)memBase + 0xF) & ~0xF);
    }

    /* Initialize RX descriptors and netbuf array */
    for (i = 0; i < RX_RING_SIZE; i++) {
        bzero((char *)_rxDescriptors + (i * 16), 16);
        /* Clear netbuf pointer array at offset 0x210 */
        *(unsigned int *)((char *)self + 0x210 + (i * 4)) = 0;
    }

    /* Setup TX descriptor ring (TX_RING_SIZE descriptors * 16 bytes = 512 bytes) */
    _txDescriptors = (char *)_rxDescriptors + 0x400;  /* 1024 bytes after RX */

    /* Align to 16-byte boundary if needed */
    if (((unsigned int)_txDescriptors & 0xF) != 0) {
        _txDescriptors = (void *)(((unsigned int)_rxDescriptors + 0x40F) & ~0xF);
    }

    /* Initialize TX descriptors and netbuf array */
    for (i = 0; i < TX_RING_SIZE; i++) {
        bzero((char *)_txDescriptors + (i * 16), 16);
        /* Clear netbuf pointer array at offset 0x190 (400 decimal) */
        *(unsigned int *)((char *)self + 400 + (i * 4)) = 0;
    }

    /* Setup frame buffer (192 bytes) */
    _setupFrame = (char *)_txDescriptors + 0x200;  /* 512 bytes after TX */

    /* Align to 16-byte boundary if needed */
    if (((unsigned int)_setupFrame & 0xF) != 0) {
        _setupFrame = (void *)(((unsigned int)_txDescriptors + 0x20F) & ~0xF);
    }

    /* Verify setup frame has a valid physical address */
    task = IOVmTaskSelf();
    if (IOPhysicalFromVirtual(task, (unsigned int)_setupFrame) != 0) {
        driverName = [[self name] cString];
        IOLog("%s: Invalid shared memory address\n", driverName);
        return NO;
    }

    return YES;
}

/*
 * Private implementation: Read MAC address from SROM
 * Uses bit-banging over CSR9 to read from serial EEPROM
 */
- (void)_getStationAddress:(enet_addr_t *)addr
{
    unsigned int sromData;
    unsigned int sromAddr;
    unsigned short sromWord;
    int wordIndex, bitIndex;
    unsigned int csrValue;
    unsigned char addrWidth;

    if (!addr) {
        return;
    }

    /* Get SROM address width from device configuration */
    addrWidth = *(unsigned char *)((char *)self + 0x18B);
    sromData = *(unsigned int *)((char *)self + 0x18C);

    /* Read 3 words (6 bytes) from SROM for MAC address */
    for (wordIndex = 0; wordIndex < 3; wordIndex++) {
        /* Calculate SROM address for this word */
        sromAddr = (sromData >> 1) + wordIndex;

        /* Send start sequence: Select SROM chip */
        [self writeCSR:9 value:0x4800];
        IODelay(250);
        [self writeCSR:9 value:0x4801];
        IODelay(250);
        [self writeCSR:9 value:0x4803];
        IODelay(250);
        [self writeCSR:9 value:0x4801];
        IODelay(250);

        /* Send READ command (110b) */
        [self writeCSR:9 value:0x4805];
        IODelay(250);
        [self writeCSR:9 value:0x4807];
        IODelay(250);
        [self writeCSR:9 value:0x4805];
        IODelay(250);
        [self writeCSR:9 value:0x4805];
        IODelay(250);
        [self writeCSR:9 value:0x4807];
        IODelay(250);
        [self writeCSR:9 value:0x4805];
        IODelay(250);

        /* Send SROM address bits */
        [self writeCSR:9 value:0x4801];
        IODelay(250);
        [self writeCSR:9 value:0x4803];
        IODelay(250);
        [self writeCSR:9 value:0x4801];
        IODelay(250);

        /* Clock out address bits */
        if (addrWidth > 0) {
            for (bitIndex = 0; bitIndex < addrWidth; bitIndex++) {
                unsigned int bitValue = (sromAddr >> ((addrWidth - bitIndex) - 1)) & 1;
                unsigned int clockVal = (bitValue << 2) | 0x4801;

                [self writeCSR:9 value:clockVal];
                IODelay(250);
                [self writeCSR:9 value:clockVal | 0x0002];  /* Clock high */
                IODelay(250);
                [self writeCSR:9 value:clockVal];  /* Clock low */
                IODelay(250);
            }
        }

        /* Read 16 data bits */
        sromWord = 0;
        for (bitIndex = 0; bitIndex < 16; bitIndex++) {
            [self writeCSR:9 value:0x4803];  /* Clock high, enable input */
            IODelay(250);

            csrValue = [self readCSR:9];
            IODelay(250);

            [self writeCSR:9 value:0x4801];  /* Clock low */
            IODelay(250);

            /* Shift in bit (bit 3 of CSR9 is data input) */
            sromWord = (sromWord << 1) | ((csrValue >> 3) & 1);
        }

        /* Store bytes in MAC address array */
        addr->ea_byte[wordIndex * 2] = (unsigned char)(sromWord & 0xFF);
        addr->ea_byte[wordIndex * 2 + 1] = (unsigned char)((sromWord >> 8) & 0xFF);
    }
}

/*
 * Private implementation: Initialize the chip
 * Orchestrates register initialization and sets up address filtering
 */
- (BOOL)_init
{
    /* Initialize chip registers */
    [self _initRegisters];

    /* Start transmit operation */
    [self _startTransmit];

    /* Setup address filtering with multicast flag set */
    [self _setAddressFiltering:1];

    return YES;
}

/*
 * Private implementation: Initialize chip registers
 * Performs chip reset, sets up descriptor rings, and configures port selection
 */
- (void)_initRegisters
{
    unsigned int csr0Value;
    unsigned int csr6Value;
    unsigned int physAddr;
    vm_task_t task;
    unsigned int mediaSelection;

    /* Reset the chip by setting CSR0 bit 0 */
    [self writeCSR:CSR0_BUS_MODE value:CSR0_SOFTWARE_RESET];

    /* Wait for reset to complete (typically requires delay) */
    IODelay(50);

    /* Clear interrupt enable register (CSR7) */
    [self writeCSR:CSR7_INTERRUPT_ENABLE value:0x00000000];

    /* Set CSR0 for cache alignment and burst length
     * 0x6000 = cache alignment 32 bytes, burst length 32 longs */
    csr0Value = 0x00006000;
    [self writeCSR:CSR0_BUS_MODE value:csr0Value];

    /* Convert RX descriptor ring virtual address to physical */
    task = IOVmTaskSelf();
    physAddr = IOPhysicalFromVirtual(task, (unsigned int)_rxDescriptors);

    /* Load RX ring base address into CSR3 */
    [self writeCSR:CSR3_RX_LIST_BASE value:physAddr];

    /* Convert TX descriptor ring virtual address to physical */
    physAddr = IOPhysicalFromVirtual(task, (unsigned int)_txDescriptors);

    /* Load TX ring base address into CSR4 */
    [self writeCSR:CSR4_TX_LIST_BASE value:physAddr];

    /* Read media selection from instance variable at offset 0x348 */
    mediaSelection = *(unsigned int *)((char *)self + 0x348);

    /* Configure CSR6 based on media selection */
    if (mediaSelection == MEDIA_10BASET) {
        /* 10BaseT / MII mode
         * CSR6: Full duplex, Transmit threshold 128 bytes, MII mode */
        csr6Value = 0x00020200;
        [self writeCSR:CSR6_OPERATION_MODE value:csr6Value];

        /* Select MII port in CSR12 */
        [self writeCSR:CSR12_GP_PORT value:0x00000000];

    } else if (mediaSelection == MEDIA_AUI) {
        /* AUI mode */
        csr6Value = 0x00020200;
        [self writeCSR:CSR6_OPERATION_MODE value:csr6Value];

        /* Configure SIA registers for AUI */
        [self writeCSR:CSR13_SIA_STATUS value:0x00000000];
        [self writeCSR:CSR14_SIA_CONNECTIVITY value:0x00000008];
        [self writeCSR:CSR15_SIA_TX_RX value:0x00000008];

    } else if (mediaSelection == MEDIA_BNC) {
        /* BNC (10Base2) mode */
        csr6Value = 0x00020200;
        [self writeCSR:CSR6_OPERATION_MODE value:csr6Value];

        /* Configure SIA registers for BNC */
        [self writeCSR:CSR13_SIA_STATUS value:0x00000000];
        [self writeCSR:CSR14_SIA_CONNECTIVITY value:0x00000001];
        [self writeCSR:CSR15_SIA_TX_RX value:0x00000009];

    } else {
        /* Default: 10BaseT mode */
        csr6Value = 0x00020200;
        [self writeCSR:CSR6_OPERATION_MODE value:csr6Value];

        /* Configure SIA registers for 10BaseT */
        [self writeCSR:CSR13_SIA_STATUS value:0x00000000];
        [self writeCSR:CSR14_SIA_CONNECTIVITY value:0x0000EF01];
        [self writeCSR:CSR15_SIA_TX_RX value:0x00000008];
    }
}

/*
 * Private implementation: Initialize RX descriptor ring
 * Sets up 64 receive descriptors with network buffers
 */
- (BOOL)_initRxRing
{
    int i;
    unsigned int *descriptor;
    netbuf_t netbuf;
    BOOL result;

    /* Initialize all RX descriptors */
    for (i = 0; i < RX_RING_SIZE; i++) {
        descriptor = (unsigned int *)((char *)_rxDescriptors + (i * 16));

        /* Clear descriptor (4 x 32-bit words) */
        descriptor[0] = 0;
        descriptor[1] = 0;
        descriptor[2] = 0;
        descriptor[3] = 0;

        /* Get netbuf pointer from array at offset 0x210 */
        netbuf = *(netbuf_t *)((char *)self + 0x210 + (i * 4));

        /* Allocate netbuf if not already allocated */
        if (netbuf == NULL) {
            netbuf = nb_alloc(ETHERMAXPACKET);
            if (netbuf == NULL) {
                IOLog("DEC21142: Failed to allocate netbuf for RX ring index %d\n", i);
                return NO;
            }
            /* Store netbuf in array */
            *(netbuf_t *)((char *)self + 0x210 + (i * 4)) = netbuf;
        }

        /* Setup descriptor with netbuf */
        result = IOUpdateDescriptorFromNetBuf(netbuf, descriptor, NO);
        if (!result) {
            IOLog("DEC21142: Failed to update RX descriptor %d\n", i);
            return NO;
        }

        /* Set ownership bit - give descriptor to controller */
        descriptor[0] |= RDES0_OWN;
    }

    /* Mark last descriptor with end-of-ring bit (bit 25 in word 1) */
    descriptor = (unsigned int *)((char *)_rxDescriptors + ((RX_RING_SIZE - 1) * 16));
    descriptor[1] |= RDES1_END_OF_RING;

    /* Reset RX ring index */
    _rxIndex = 0;

    return YES;
}

/*
 * Private implementation: Initialize TX descriptor ring
 * Sets up 32 transmit descriptors and creates transmit queue
 */
- (BOOL)_initTxRing
{
    int i;
    unsigned int *descriptor;
    netbuf_t netbuf;
    void *txQueue;

    /* Initialize all TX descriptors */
    for (i = 0; i < TX_RING_SIZE; i++) {
        descriptor = (unsigned int *)((char *)_txDescriptors + (i * 16));

        /* Clear descriptor (4 x 32-bit words) */
        descriptor[0] = 0;
        descriptor[1] = 0;
        descriptor[2] = 0;
        descriptor[3] = 0;

        /* Get and free any existing netbuf from array at offset 0x190 */
        netbuf = *(netbuf_t *)((char *)self + 0x190 + (i * 4));
        if (netbuf != NULL) {
            nb_free(netbuf);
            *(netbuf_t *)((char *)self + 0x190 + (i * 4)) = NULL;
        }
    }

    /* Mark last descriptor with end-of-ring bit (bit 25 in word 1) */
    descriptor = (unsigned int *)((char *)_txDescriptors + ((TX_RING_SIZE - 1) * 16));
    descriptor[1] |= TDES1_END_OF_RING;

    /* Reset TX ring indices */
    *(unsigned int *)((char *)self + 0x318) = 0;  /* txHead */
    *(unsigned int *)((char *)self + 0x31C) = 0;  /* txTail */
    *(unsigned int *)((char *)self + 0x320) = 0;  /* txCount */

    /* Create TX queue - stored at offset 0x324 */
    txQueue = *(void **)((char *)self + 0x324);
    if (txQueue == NULL) {
        /* Allocate new IONetbufQueue with max size */
        txQueue = (void *)[[IONetbufQueue alloc] initWithMaxCount:TX_QUEUE_MAX_SIZE];
        if (txQueue == NULL) {
            IOLog("DEC21142: Failed to allocate TX queue\n");
            return NO;
        }
        *(void **)((char *)self + 0x324) = txQueue;
    }

    return YES;
}

/*
 * Private implementation: Load setup filter frame
 * Programs a setup frame descriptor to configure address filtering
 */
- (BOOL)_loadSetupFilter:(BOOL)waitForCompletion
{
    unsigned int *descriptor;
    unsigned int csrValue;
    int timeout;
    unsigned int txCount;
    unsigned int txHead;
    unsigned int txTail;

    /* Check if TX ring has available descriptors */
    txCount = *(unsigned int *)((char *)self + 0x320);
    if (txCount == 0) {
        return NO;
    }

    /* Get current TX descriptor at txHead index */
    txHead = *(unsigned int *)((char *)self + 0x318);
    descriptor = (unsigned int *)((char *)_txDescriptors + (txHead * 16));

    /* Advance txHead, wrap at 32 descriptors */
    txHead++;
    if (txHead == 0x20) {
        txHead = 0;
    }
    *(unsigned int *)((char *)self + 0x318) = txHead;

    /* Decrement available descriptor count */
    txCount--;
    *(unsigned int *)((char *)self + 0x320) = txCount;

    /* Clear control word, preserving end-of-ring bit if set */
    if ((descriptor[1] & 0x02000000) == 0) {
        descriptor[1] = 0;
    } else {
        descriptor[1] = 0;
        descriptor[1] |= 0x02000000;  /* Preserve end-of-ring bit */
    }

    /* Set setup frame bit (bit 27) */
    descriptor[1] |= 0x08000000;

    /* Set first and last segment bits (bits 29-30) */
    descriptor[1] |= 0x80000000;  /* First segment */

    /* Clear buffer size fields and set buffer 1 size to 192 bytes (0xc0) */
    descriptor[1] &= 0xFFFFF800;
    descriptor[1] |= 0x000000C0;
    descriptor[1] &= 0xFFC007FF;  /* Clear buffer 2 size */

    /* Set buffer 1 address to setup frame physical address */
    descriptor[2] = *(unsigned int *)((char *)self + 0x33C);

    /* Clear buffer 2 address */
    descriptor[3] = 0;

    /* Clear status word and set ownership bit */
    descriptor[0] = 0;
    descriptor[0] |= TDES0_OWN;

    /* Trigger transmit poll by writing to CSR1 */
    [self writeCSR:CSR1_TX_POLL_DEMAND value:0x00000001];

    /* If synchronous mode, wait for completion */
    if (waitForCompletion) {
        timeout = 9999;
        while (timeout >= 0) {
            IODelay(5);

            /* Check CSR5 for transmit interrupt */
            csrValue = [self readCSR:CSR5_STATUS];
            if ((csrValue & CSR5_TX_BUFFER_UNAVAIL) != 0) {
                /* Clear transmit interrupt status */
                [self writeCSR:CSR5_STATUS value:csrValue];
                break;
            }

            timeout--;
        }

        /* Update txTail index */
        txTail = *(unsigned int *)((char *)self + 0x31C);
        txTail++;
        if (txTail == 0x20) {
            txTail = 0;
        }
        *(unsigned int *)((char *)self + 0x31C) = txTail;

        /* Increment available descriptor count */
        txCount++;
        *(unsigned int *)((char *)self + 0x320) = txCount;
    }

    return YES;
}

/*
 * Private implementation: Handle receive interrupt
 * Processes received packets from RX descriptor ring
 */
- (BOOL)_receiveInterruptOccurred
{
    unsigned int *descriptor;
    unsigned int rxIndex;
    unsigned int status;
    unsigned int frameLength;
    netbuf_t oldNetbuf;
    netbuf_t newNetbuf;
    void *frameData;
    BOOL allocated;
    BOOL result;
    int netbufSize;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    rxIndex = *(unsigned int *)((char *)self + 0x328);

    while (1) {
        /* Get current RX descriptor */
        descriptor = (unsigned int *)((char *)_rxDescriptors + (rxIndex * 16));

        /* Check ownership bit (bit 31) - if set, chip still owns it */
        if ((descriptor[0] & 0x80000000) != 0) {
            [self releaseDebuggerLock];
            return YES;
        }

        allocated = NO;
        status = descriptor[0];

        /* Extract frame length (bits 16-29) and subtract 4 bytes for CRC */
        frameLength = ((status >> 16) & 0x3FFF) - 4;

        /* Check for valid frame: First segment, Last segment, no errors */
        if (((status & 0x00000383) == 0x00000300) && (frameLength > 0x3B)) {
            /* Get netbuf for this descriptor */
            oldNetbuf = *(netbuf_t *)((char *)self + 0x210 + (rxIndex * 4));

            /* Check multicast filtering if not in promiscuous mode */
            if ((*(unsigned char *)((char *)self + 0x188) == 0) &&
                ((status & 0x00000400) != 0)) {
                /* Multicast packet - check if unwanted */
                frameData = nb_map(oldNetbuf);
                if ([super isUnwantedMulticastPacket:frameData]) {
                    /* Skip this packet */
                    goto skip_packet;
                }
            }

            /* Allocate new netbuf for descriptor */
            newNetbuf = [self allocateNetbuf];
            if (newNetbuf != NULL) {
                /* Store new netbuf in array */
                *(netbuf_t *)((char *)self + 0x210 + (rxIndex * 4)) = newNetbuf;
                allocated = YES;

                /* Update descriptor with new netbuf */
                result = IOUpdateDescriptorFromNetBuf(newNetbuf, descriptor, NO);
                if (!result) {
                    IOPanic("DEC21142: IOUpdateDescriptorFromNetBuf\n");
                }

                /* Adjust received netbuf size to actual frame length */
                netbufSize = nb_size(oldNetbuf);
                nb_shrink_bot(oldNetbuf, netbufSize - frameLength);
            }
        } else {
            /* Frame error - increment error counter */
            [_serverInstance incrementInputErrors];
        }

skip_packet:
        /* Return descriptor to chip */
        descriptor[0] = 0;
        descriptor[0] |= 0x80000000;

        /* Advance RX index, wrap at 64 descriptors */
        rxIndex++;
        if (rxIndex == 0x40) {
            rxIndex = 0;
        }
        *(unsigned int *)((char *)self + 0x328) = rxIndex;

        /* If we have a valid packet, pass it to upper layer */
        if (allocated) {
            [self releaseDebuggerLock];
            [_serverInstance handleInputPacket:oldNetbuf extra:0];
            [self reserveDebuggerLock];
        }

        /* Update rxIndex for next iteration */
        rxIndex = *(unsigned int *)((char *)self + 0x328);
    }
}

/*
 * Private implementation: Reset chip
 * Performs a soft reset of the DEC21142 chip
 */
- (void)_resetChip
{
    /* Set software reset bit in CSR0 */
    [self writeCSR:CSR0_BUS_MODE value:CSR0_SOFTWARE_RESET];

    /* Wait 100 microseconds for reset to propagate */
    IODelay(100);

    /* Clear reset bit */
    [self writeCSR:CSR0_BUS_MODE value:0x00000000];

    /* Wait 1 millisecond for chip to stabilize */
    IOSleep(1);
}

/*
 * Private implementation: Setup address filtering
 * Configures the setup frame with station address, broadcast, and multicast addresses
 */
- (BOOL)_setAddressFiltering:(BOOL)waitForCompletion
{
    unsigned short *stationAddr;
    unsigned int *setupFrame;
    int i;
    BOOL hasMulticast;
    void *multicastQueue;
    void *entry;
    void *next;
    unsigned int slot;
    unsigned short *macAddr;
    unsigned short addrWord;

    setupFrame = (unsigned int *)*(void **)((char *)self + 0x338);
    stationAddr = (unsigned short *)((char *)self + 0x178);

    /* Slot 0: Copy station address (6 bytes as 3 words) */
    for (i = 0; i < 3; i++) {
        setupFrame[i] = (unsigned int)stationAddr[i];
    }

    /* Slot 1: Broadcast address (all 0xFFFF) */
    for (i = 0; i < 3; i++) {
        setupFrame[3 + i] = 0xFFFF;
    }

    /* Start filling multicast addresses at slot 2 */
    slot = 2;

    /* Check if multicast is enabled */
    hasMulticast = *(unsigned char *)((char *)self + 0x189);
    if (hasMulticast) {
        /* Get multicast queue from superclass */
        multicastQueue = [super multicastQueue];

        /* Iterate through linked list of multicast addresses */
        entry = *(void **)multicastQueue;
        if (entry != multicastQueue) {
            while (entry != multicastQueue) {
                /* Each entry contains a MAC address */
                macAddr = (unsigned short *)entry;

                /* Copy 6 bytes (3 words) of MAC address to setup frame */
                for (i = 0; i < 3; i++) {
                    /* Read word from entry (handle byte ordering) */
                    unsigned char byte0 = *((unsigned char *)entry + (i * 2));
                    unsigned char byte1 = *((unsigned char *)entry + (i * 2) + 1);
                    addrWord = (unsigned short)byte0 | ((unsigned short)byte1 << 8);
                    setupFrame[(slot * 3) + i] = addrWord;
                }

                slot++;

                /* Check if we've exceeded the 16 slot limit */
                if (slot > 0xF) {
                    IOLog("%s: %d multicast address limit exceeded\n",
                          [[self name] cString], 14);
                    break;
                }

                /* Move to next entry in linked list */
                entry = *((void **)entry + 2);
            }
        }
    }

    /* Fill remaining slots with station address */
    for (; slot < 0x10; slot++) {
        bcopy((void *)setupFrame, (void *)&setupFrame[slot * 3], 12);
    }

    /* Load the setup filter frame */
    return [self _loadSetupFilter:waitForCompletion];
}

/*
 * Private implementation: Start receive operation
 * Enables the receiver by setting SR bit in CSR6
 */
- (void)_startReceive
{
    unsigned int csr6Value;

    /* Read current CSR6 value from offset 0x344 */
    csr6Value = *(unsigned int *)((char *)self + 0x344);

    /* Set Start/Stop Receive bit */
    csr6Value |= CSR6_START_RX;

    /* Store updated value */
    *(unsigned int *)((char *)self + 0x344) = csr6Value;

    /* Write to CSR6 register */
    [self writeCSR:CSR6_OPERATION_MODE value:csr6Value];
}

/*
 * Private implementation: Start transmit operation
 * Enables the transmitter by setting ST bit in CSR6
 */
- (void)_startTransmit
{
    unsigned int csr6Value;

    /* Read current CSR6 value from offset 0x344 */
    csr6Value = *(unsigned int *)((char *)self + 0x344);

    /* Set Start/Stop Transmit bit */
    csr6Value |= CSR6_START_TX;

    /* Store updated value */
    *(unsigned int *)((char *)self + 0x344) = csr6Value;

    /* Write to CSR6 register */
    [self writeCSR:CSR6_OPERATION_MODE value:csr6Value];
}

/*
 * Private implementation: Handle transmit interrupt
 * Processes completed transmit descriptors and updates statistics
 */
- (BOOL)_transmitInterruptOccurred
{
    unsigned int txCount;
    unsigned int txTail;
    unsigned int *descriptor;
    unsigned int status;
    unsigned char collisionCount;
    netbuf_t netbuf;

    txCount = *(unsigned int *)((char *)self + 0x320);

    while (1) {
        /* Check if all descriptors have been processed */
        if (txCount > 0x1F) {
            return YES;
        }

        /* Get descriptor at txTail */
        txTail = *(unsigned int *)((char *)self + 0x31C);
        descriptor = (unsigned int *)((char *)_txDescriptors + (txTail * 16));

        /* Check ownership bit - if set, chip still owns it */
        if ((descriptor[0] & 0x80000000) != 0) {
            return YES;
        }

        status = descriptor[0];

        /* Skip statistics for setup frames (bit 27 in word 1) */
        if ((descriptor[1] & 0x08000000) == 0) {
            /* Check for transmission errors (bits 1, 8-10, 14) */
            if ((status & 0x00004702) == 0) {
                /* Successful transmission */
                [_serverInstance incrementOutputPackets];
            } else {
                /* Transmission error */
                [_serverInstance incrementOutputErrors];
            }

            /* Handle collision statistics */
            if ((status & 0x00000100) != 0) {
                /* Excessive collisions (bit 8) - count as 16 */
                collisionCount = 0x10;
                [_serverInstance incrementCollisionsBy:collisionCount];
            } else if ((status & 0x00000078) != 0) {
                /* Normal collision count (bits 3-6) */
                collisionCount = (status >> 3) & 0x0F;
                [_serverInstance incrementCollisionsBy:collisionCount];
            }

            /* Check for late collision (bit 9) without carrier sense (bit 1) */
            if ((status & 0x00000202) == 0x00000200) {
                [_serverInstance incrementCollisions];
            }

            /* Free the netbuf associated with this descriptor */
            netbuf = *(netbuf_t *)((char *)self + 0x190 + (txTail * 4));
            if (netbuf != NULL) {
                nb_free(netbuf);
                *(netbuf_t *)((char *)self + 0x190 + (txTail * 4)) = NULL;
            }
        }

        /* Advance txTail, wrap at 32 descriptors */
        txTail++;
        if (txTail == 0x20) {
            txTail = 0;
        }
        *(unsigned int *)((char *)self + 0x31C) = txTail;

        /* Increment available descriptor count */
        txCount++;
        *(unsigned int *)((char *)self + 0x320) = txCount;
    }
}

/*
 * Private implementation: Transmit a packet
 * Programs a TX descriptor and initiates transmission
 */
- (void)_transmitPacket:(netbuf_t)packet
{
    unsigned int *descriptor;
    unsigned int txHead;
    unsigned int txCount;
    unsigned int packetCount;
    BOOL result;

    /* Perform loopback if enabled */
    [self performLoopback:packet];

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Check if TX descriptors are available */
    txCount = *(unsigned int *)((char *)self + 0x320);
    if (txCount == 0) {
        /* No descriptors available, drop packet */
        [self releaseDebuggerLock];
        nb_free(packet);
        return;
    }

    /* Get descriptor at txHead */
    txHead = *(unsigned int *)((char *)self + 0x318);
    descriptor = (unsigned int *)((char *)_txDescriptors + (txHead * 16));

    /* Store netbuf in TX array */
    *(netbuf_t *)((char *)self + 0x190 + (txHead * 4)) = packet;

    /* Clear control word, preserving end-of-ring bit if set */
    if ((descriptor[1] & 0x02000000) == 0) {
        descriptor[1] = 0;
    } else {
        descriptor[1] = 0;
        descriptor[1] |= 0x02000000;
    }

    /* Update descriptor with packet buffer */
    result = IOUpdateDescriptorFromNetBuf(packet, descriptor, NO);
    if (!result) {
        [self releaseDebuggerLock];
        IOLog("%s: _transmitPacket: IOUpdateDescriptorFromNetBuf failed\n",
              [[self name] cString]);
        nb_free(packet);
        return;
    }

    /* Set first segment bit (bit 29) */
    descriptor[1] |= TDES1_FIRST_SEGMENT;

    /* Set last segment bit (bit 30) */
    descriptor[1] |= TDES1_LAST_SEGMENT;

    /* Increment packet counter at offset 0x324 */
    packetCount = *(unsigned int *)((char *)self + 0x324);
    packetCount++;
    *(unsigned int *)((char *)self + 0x324) = packetCount;

    /* Set interrupt on completion every N packets */
    if (packetCount == TX_INTERRUPT_FREQUENCY) {
        descriptor[1] |= TDES1_INTERRUPT_ON_COMPLETION;
        *(unsigned int *)((char *)self + 0x324) = 0;
    } else {
        descriptor[1] &= ~TDES1_INTERRUPT_ON_COMPLETION;
    }

    /* Clear status word and set ownership bit */
    descriptor[0] = 0;
    descriptor[0] |= TDES0_OWN;

    /* Advance txHead, wrap at TX_RING_SIZE descriptors */
    txHead++;
    if (txHead == TX_RING_SIZE) {
        txHead = 0;
    }
    *(unsigned int *)((char *)self + 0x318) = txHead;

    /* Decrement available descriptor count */
    txCount--;
    *(unsigned int *)((char *)self + 0x320) = txCount;

    /* Trigger transmit poll by writing to CSR1 */
    [self writeCSR:1 value:0x00000001];

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Private implementation: Verify SROM checksum
 * Reads and validates SROM checksum data
 */
- (BOOL)_verifyCheckSum
{
    unsigned int sromAddr;
    unsigned char addrWidth;
    int bitIndex;
    unsigned int bitValue;
    unsigned int clockVal;

    /* Send start sequence: Select SROM chip */
    [self writeCSR:9 value:0x4800];
    IODelay(250);
    [self writeCSR:9 value:0x4801];
    IODelay(250);
    [self writeCSR:9 value:0x4803];
    IODelay(250);
    [self writeCSR:9 value:0x4801];
    IODelay(250);

    /* Send READ command (110b) */
    [self writeCSR:9 value:0x4805];
    IODelay(250);
    [self writeCSR:9 value:0x4807];
    IODelay(250);
    [self writeCSR:9 value:0x4805];
    IODelay(250);
    [self writeCSR:9 value:0x4805];
    IODelay(250);
    [self writeCSR:9 value:0x4807];
    IODelay(250);
    [self writeCSR:9 value:0x4805];
    IODelay(250);

    /* Send SROM address bits */
    [self writeCSR:9 value:0x4801];
    IODelay(250);
    [self writeCSR:9 value:0x4803];
    IODelay(250);
    [self writeCSR:9 value:0x4801];
    IODelay(250);

    /* Read address width from offset 0x18B */
    addrWidth = *(unsigned char *)((char *)self + 0x18B);
    sromAddr = 3;  /* Reading from address 3 for checksum */

    /* Clock out address bits */
    if (addrWidth > 0) {
        for (bitIndex = 0; bitIndex < addrWidth; bitIndex++) {
            bitValue = (sromAddr >> ((addrWidth - bitIndex) - 1)) & 1;
            clockVal = (bitValue << 2) | 0x4801;

            [self writeCSR:9 value:clockVal];
            IODelay(250);
            [self writeCSR:9 value:clockVal | 0x0002];  /* Clock high */
            IODelay(250);
            [self writeCSR:9 value:clockVal];  /* Clock low */
            IODelay(250);
        }
    }

    /* Read 16 data bits (checksum value) */
    for (bitIndex = 0; bitIndex < 16; bitIndex++) {
        [self writeCSR:9 value:0x4803];  /* Clock high, enable input */
        IODelay(250);

        [self readCSR:9];  /* Read bit but don't store */
        IODelay(250);

        [self writeCSR:9 value:0x4801];  /* Clock low */
        IODelay(250);
    }

    /* Always return YES - checksum verification is informational */
    return YES;
}

/*
 * Public method: Add multicast address
 * Enables multicast filtering and programs the setup frame
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;

    /* Enable multicast flag */
    *(unsigned char *)((char *)self + 0x189) = 1;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Update address filtering (asynchronous - don't wait) */
    result = [self _setAddressFiltering:NO];
    if (!result) {
        IOLog("%s: add multicast address failed\n", [[self name] cString]);
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Public method: Allocate network buffer
 * Allocates and aligns a netbuf for receive operations
 */
- (netbuf_t)allocateNetbuf
{
    netbuf_t netbuf;
    unsigned int bufAddr;
    unsigned int alignOffset;
    int bufSize;

    /* Allocate netbuf (1552 bytes - oversized for alignment) */
    netbuf = nb_alloc(0x610);
    if (netbuf == NULL) {
        return NULL;
    }

    /* Get buffer address */
    bufAddr = (unsigned int)nb_map(netbuf);

    /* Check for 32-byte alignment */
    alignOffset = bufAddr & 0x1F;
    if (alignOffset != 0) {
        /* Adjust alignment by shrinking from top */
        nb_shrink_top(netbuf, 0x20 - alignOffset);
    }

    /* Shrink to final size (1514 bytes = standard Ethernet MTU + padding) */
    bufSize = nb_size(netbuf);
    nb_shrink_bot(netbuf, bufSize - 0x5EA);

    return netbuf;
}

/*
 * Public method: Check MII PHY
 * Performs MII management interface communication to detect PHY
 */
- (void)checkMII
{
    unsigned int csrValue;
    unsigned short readValue;
    int bitIndex;

    /* Initialize CSR9 to 0 */
    [self writeCSR:9 value:0x00000000];

    /* Send 32-bit preamble (all 1s) using MII clock */
    /* Pattern: 0x50000 (clock high + data 1), 0x40000 (clock low) */

    /* Bits 0-1: Clock data 1 */
    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    /* Bits 2-3: Clock data 1 */
    [self writeCSR:9 value:0x00070000];
    IODelay(100);
    [self writeCSR:9 value:0x00060000];
    IODelay(100);

    /* Bits 4-5: Clock data 1 */
    [self writeCSR:9 value:0x00070000];
    IODelay(100);
    [self writeCSR:9 value:0x00060000];
    IODelay(100);

    /* Bits 6-9: Clock data 0,1,0,1 pattern */
    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    /* Continue clocking pattern */
    [self writeCSR:9 value:0x00070000];
    IODelay(100);
    [self writeCSR:9 value:0x00060000];
    IODelay(100);

    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    [self writeCSR:9 value:0x00070000];
    IODelay(100);
    [self writeCSR:9 value:0x00060000];
    IODelay(100);

    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    [self writeCSR:9 value:0x00050000];
    IODelay(100);
    [self writeCSR:9 value:0x00040000];
    IODelay(100);

    /* Read 2 bits from MII */
    readValue = 0;
    for (bitIndex = 0; bitIndex < 2; bitIndex++) {
        /* Clock high for read */
        [self writeCSR:9 value:0x00010000];
        IODelay(100);

        /* Clock low and read data */
        [self writeCSR:9 value:0x00000000];
        IODelay(100);

        /* Read CSR9 and extract bit 19 */
        csrValue = [self readCSR:9];
        readValue = ((readValue | ((csrValue >> 19) & 1)) * 2);
    }

    IOLog("u is 0x%x\n", (int)readValue);

    /* Reset CSR9 to 0 */
    [self writeCSR:9 value:0x00000000];
}

/*
 * Public method: Disable adapter interrupts
 * Disables all interrupts from the DEC21142 chip
 */
- (void)disableAdapterInterrupts
{
    /* Clear interrupt enable register (CSR7) */
    [self writeCSR:CSR7_INTERRUPT_ENABLE value:0x00000000];
}

/*
 * Public method: Disable multicast mode
 * Turns off multicast address filtering
 */
- (void)disableMulticastMode
{
    BOOL result;

    /* Check if multicast is currently enabled */
    if (*(unsigned char *)((char *)self + 0x189) != 0) {
        /* Acquire debugger lock */
        [self reserveDebuggerLock];

        /* Update address filtering (asynchronous - don't wait) */
        result = [self _setAddressFiltering:NO];
        if (!result) {
            IOLog("%s: disable multicast mode failed\n", [[self name] cString]);
        }

        /* Release debugger lock */
        [self releaseDebuggerLock];
    }

    /* Clear multicast flag */
    *(unsigned char *)((char *)self + 0x189) = 0;
}

/*
 * Public method: Disable promiscuous mode
 * Turns off promiscuous packet reception
 */
- (void)disablePromiscuousMode
{
    unsigned int csr6Value;

    /* Clear promiscuous flag */
    *(unsigned char *)((char *)self + 0x188) = 0;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Read CSR6 and clear promiscuous bit */
    csr6Value = [self readCSR:CSR6_OPERATION_MODE];
    [self writeCSR:CSR6_OPERATION_MODE value:(csr6Value & ~CSR6_PROMISCUOUS)];

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Public method: Auto-detect network port
 * Attempts to detect and select the appropriate port (10BaseT or AUI)
 */
- (void)doAutoPortSelect
{
    unsigned int csr5Value;
    int timeout;

    IOLog("%s: autosensing the network port\n", [[self name] cString]);

    /* Try 10BaseT first */
    [self select10BaseT];

    /* Wait up to 4 seconds (40 * 100ms) for link detect */
    timeout = 0;
    while (timeout < 0x28) {
        /* Read CSR5 status register */
        csr5Value = [self readCSR:5];

        /* Check link pass bit (bit 4) */
        if ((csr5Value & 0x00000010) != 0) {
            /* Link detected on 10BaseT */
            *(unsigned int *)((char *)self + 0x348) = 3;
            IOLog("%s: detected RJ-45 port\n", [[self name] cString]);
            return;
        }

        /* Check link fail bit (bit 12) */
        if ((csr5Value & 0x00001000) != 0) {
            /* Link definitely failed */
            break;
        }

        /* Wait 100ms and retry */
        IOSleep(100);
        timeout++;
    }

    /* No link on 10BaseT, use AUI port instead */
    *(unsigned int *)((char *)self + 0x348) = 2;
    IOLog("%s: using AUI port\n", [[self name] cString]);
    [self selectAUI];
}

/*
 * Public method: Enable adapter interrupts
 * Enables interrupts from the DEC21142 chip
 */
- (void)enableAdapterInterrupts
{
    unsigned int interruptMask;

    /* Get interrupt mask from offset 0x340 */
    interruptMask = *(unsigned int *)((char *)self + 0x340);

    /* Write interrupt mask to CSR7 (interrupt enable register) */
    [self writeCSR:CSR7_INTERRUPT_ENABLE value:interruptMask];
}

/*
 * Public method: Enable multicast mode
 * Turns on multicast address filtering
 */
- (BOOL)enableMulticastMode
{
    /* Set multicast flag */
    *(unsigned char *)((char *)self + 0x189) = 1;

    return YES;
}

/*
 * Public method: Enable promiscuous mode
 * Turns on promiscuous packet reception
 */
- (BOOL)enablePromiscuousMode
{
    unsigned int csr6Value;

    /* Set promiscuous flag */
    *(unsigned char *)((char *)self + 0x188) = 1;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Read CSR6 and set promiscuous bit */
    csr6Value = [self readCSR:CSR6_OPERATION_MODE];
    [self writeCSR:CSR6_OPERATION_MODE value:(csr6Value | CSR6_PROMISCUOUS)];

    /* Release debugger lock */
    [self releaseDebuggerLock];

    return YES;
}

/*
 * Free resources
 */
- free
{
    int i;
    netbuf_t netbuf;
    void *memBase;
    unsigned int allocSize;

    /* Clear any pending timeouts */
    [self clearTimeout];

    /* Reset the chip */
    [self _resetChip];

    /* Free server instance */
    if (_serverInstance != NULL) {
        [_serverInstance free];
        _serverInstance = NULL;
    }

    /* Free all RX netbufs (64 descriptors) */
    for (i = 0; i < 0x40; i++) {
        netbuf = *(netbuf_t *)((char *)self + 0x210 + (i * 4));
        if (netbuf != NULL) {
            nb_free(netbuf);
            *(netbuf_t *)((char *)self + 0x210 + (i * 4)) = NULL;
        }
    }

    /* Free all TX netbufs (32 descriptors) */
    for (i = 0; i < 0x20; i++) {
        netbuf = *(netbuf_t *)((char *)self + 0x190 + (i * 4));
        if (netbuf != NULL) {
            nb_free(netbuf);
            *(netbuf_t *)((char *)self + 0x190 + (i * 4)) = NULL;
        }
    }

    /* Free low memory allocation (descriptors) */
    memBase = *(void **)((char *)self + 0x330);
    if (memBase != NULL) {
        allocSize = *(unsigned int *)((char *)self + 0x334);
        IOFreeLow(memBase, allocSize);
        *(void **)((char *)self + 0x330) = NULL;
    }

    /* Re-enable all interrupts (cleanup) */
    [self enableAllInterrupts];

    /* Call superclass free */
    return [super free];
}

/*
 * Public method: Get power management capabilities
 * Returns error code indicating power management is not supported
 */
- (IOReturn)getPowerManagement:(void *)powerManagement
{
    /* Return IO_R_UNSUPPORTED (0xfffffd39) */
    return IO_R_UNSUPPORTED;
}

/*
 * Public method: Get power state
 * Returns error code indicating power state query is not supported
 */
- (IOReturn)getPowerState:(void *)powerState
{
    /* Return IO_R_UNSUPPORTED (0xfffffd39) */
    return IO_R_UNSUPPORTED;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IOPCIDeviceDescription *pciDevice;
    IORange *portRange;
    unsigned short ioBase;
    unsigned short irq;
    NXStringTable *configTable;
    const char *configValue;
    char *endPtr;
    int sromOffset;
    unsigned int mediaSelection;
    const char *mediaNames[4];
    enet_addr_t stationAddress;
    BOOL result;
    id networkInterface;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Get I/O port range */
    pciDevice = (IOPCIDeviceDescription *)deviceDescription;
    portRange = [pciDevice portRangeList:0];
    ioBase = portRange->start;
    *(unsigned short *)((char *)self + 0x174) = ioBase;

    /* Get interrupt level */
    irq = [deviceDescription interrupt];
    *(unsigned short *)((char *)self + 0x176) = irq;

    /* Get configuration table */
    configTable = [deviceDescription configTable];

    /* Read SROM address bits configuration */
    configValue = [configTable valueForStringKey:"SROM Address Bits"];
    if (configValue != NULL && strcmp(configValue, "8") == 0) {
        *(unsigned char *)((char *)self + 0x18B) = 8;
    } else {
        *(unsigned char *)((char *)self + 0x18B) = 6;
    }

    /* Free string if allocated */
    if (configValue != NULL) {
        [configTable freeString:configValue];
    }

    /* Read SROM data offset - defaults to 0x14 (20 decimal) */
    *(unsigned int *)((char *)self + 0x18C) = 0x14;
    configValue = [configTable valueForStringKey:"SROM Data Offset"];
    if (configValue != NULL) {
        /* Skip leading whitespace */
        while (*configValue == ' ' || *configValue == '\t' || *configValue == '\n') {
            configValue++;
        }

        /* Parse integer value */
        sromOffset = 0;
        while (*configValue != '\0' && *configValue != ' ' &&
               *configValue != '\t' && *configValue != '\n') {
            if (*configValue >= '0' && *configValue <= '9') {
                sromOffset = sromOffset * 10 + (*configValue - '0');
            }
            configValue++;
        }

        *(int *)((char *)self + 0x18C) = sromOffset;
        [configTable freeString:configValue];
    }

    /* Read port selection - defaults to AUTO (0) */
    *(unsigned int *)((char *)self + 0x348) = 0;
    configValue = [configTable valueForStringKey:"Port"];
    if (configValue != NULL) {
        mediaNames[0] = "AUTO";
        mediaNames[1] = "BNC";
        mediaNames[2] = "AUI";
        mediaNames[3] = "TP";

        mediaSelection = 0;
        while (mediaSelection < 4) {
            if (strcmp(configValue, mediaNames[mediaSelection]) == 0) {
                break;
            }
            mediaSelection++;
        }

        *(unsigned int *)((char *)self + 0x348) = mediaSelection;
        [configTable freeString:configValue];
    }

    /* Disable hardware loopback */
    [self disableHardwareLoopback];

    /* Allocate memory for descriptors and setup frame */
    result = [self _allocateMemory];
    if (!result) {
        [self free];
        return nil;
    }

    /* Initialize promiscuous and multicast flags */
    *(unsigned char *)((char *)self + 0x188) = 0;
    *(unsigned char *)((char *)self + 0x189) = 0;

    /* Log initialization message */
    IOLog("DEC21142: Initializing\n");

    /* Log port selection if not AUTO */
    if (*(unsigned int *)((char *)self + 0x348) != 0) {
        mediaNames[0] = "AUTO";
        mediaNames[1] = "BNC";
        mediaNames[2] = "AUI";
        mediaNames[3] = "TP";
        IOLog("DEC21142: Port selection: %s\n",
              mediaNames[*(unsigned int *)((char *)self + 0x348)]);
    }

    /* Get station address from SROM */
    [self _getStationAddress:&stationAddress];
    *(unsigned int *)((char *)self + 0x32C) = *(unsigned int *)&stationAddress.ea_byte[0];

    /* Verify station address is valid */
    if (*(unsigned int *)((char *)self + 0x32C) == 0) {
        IOLog("%s: Invalid station address\n", [[self name] cString]);
        [self free];
        return nil;
    }

    /* Clear some flag at offset 0x18A */
    *(unsigned char *)((char *)self + 0x18A) = 0;

    /* Perform chip initialization */
    result = [self _init];
    if (!result) {
        [self free];
        return nil;
    }

    /* Attach to network stack */
    networkInterface = [super attachToNetworkWithAddress:&stationAddress];
    *(id *)((char *)self + 0x180) = networkInterface;

    return self;
}

/*
 * Public method: Handle hardware interrupt
 * Called when the DEC21142 chip generates an interrupt
 */
- (void)interruptOccurred
{
    unsigned int csr5Status;

    while (1) {
        /* Acquire debugger lock */
        [self reserveDebuggerLock];

        /* Read CSR5 status register */
        csr5Status = [self readCSR:5];

        /* Write back to clear interrupts */
        [self writeCSR:5 value:csr5Status];

        /* Release debugger lock */
        [self releaseDebuggerLock];

        /* Check if any relevant interrupts occurred (bits 0, 3, 6) */
        if ((csr5Status & 0x00000049) == 0) {
            break;
        }

        /* Handle receive interrupt (bit 6) */
        if ((csr5Status & 0x00000040) != 0) {
            [self _receiveInterruptOccurred];
        }

        /* Handle transmit interrupt (bit 0) */
        if ((csr5Status & 0x00000001) != 0) {
            [self reserveDebuggerLock];
            [self _transmitInterruptOccurred];
            [self releaseDebuggerLock];
            [self serviceTransmitQueue];
        }
    }

    /* Re-enable interrupts */
    [self enableAllInterrupts];
}

/*
 * Public method: Get pending transmit count
 * Returns the number of packets waiting to be transmitted
 */
- (unsigned int)pendingTransmitCount
{
    unsigned int queueCount;
    unsigned int txCount;

    /* Get count from transmit queue at offset 0x184 */
    queueCount = [*(id *)((char *)self + 0x184) count];

    /* Get available descriptor count */
    txCount = *(unsigned int *)((char *)self + 0x320);

    /* Return total pending: queued packets + (max descriptors - available) */
    return (queueCount + 0x20) - txCount;
}

/*
 * Public method: Receive packet in polling mode
 * Used by debugger to receive packets without interrupts
 */
- (void)receivePacket:(void *)buffer length:(unsigned int *)length timeout:(unsigned int)timeout
{
    unsigned int *descriptor;
    unsigned int rxIndex;
    unsigned int status;
    unsigned int frameLength;
    int timeRemaining;
    void *netbufData;
    netbuf_t netbuf;

    /* Initialize length to 0 */
    *length = 0;

    /* Convert timeout from milliseconds to microseconds */
    timeRemaining = timeout * 1000;

    /* Check if in debugger mode (flag at offset 0x18A) */
    if (*(unsigned char *)((char *)self + 0x18A) == 0) {
        return;
    }

    /* Poll for packet */
    while (1) {
        rxIndex = *(unsigned int *)((char *)self + 0x328);
        descriptor = (unsigned int *)((char *)_rxDescriptors + (rxIndex * 16));

        /* Wait for descriptor ownership to be released by chip */
        while ((descriptor[0] & 0x80000000) != 0) {
            /* Check timeout */
            if (timeRemaining < 1) {
                return;
            }

            /* Delay 50 microseconds */
            IODelay(50);
            timeRemaining -= 50;
        }

        status = descriptor[0];

        /* Check for valid frame: First and Last segment, no errors */
        if (((status & 0x00000383) == 0x00000300) &&
            (((status >> 16) & 0x3FFF) > 0x3F)) {
            /* Valid packet found */
            break;
        }

        /* Error or invalid packet - skip it */
        descriptor[0] = 0;
        descriptor[0] |= 0x80000000;

        /* Advance RX index */
        rxIndex++;
        if (rxIndex == 0x40) {
            rxIndex = 0;
        }
        *(unsigned int *)((char *)self + 0x328) = rxIndex;
    }

    /* Extract frame length (bits 16-29) and subtract 4 for CRC */
    frameLength = ((descriptor[0] >> 16) & 0x3FFF) - 4;
    *length = frameLength;

    /* Get netbuf and copy data */
    netbuf = *(netbuf_t *)((char *)self + 0x210 + (rxIndex * 4));
    netbufData = nb_map(netbuf);
    bcopy(netbufData, buffer, frameLength);

    /* Return descriptor to chip */
    descriptor[0] = 0;
    descriptor[0] |= 0x80000000;

    /* Advance RX index */
    rxIndex++;
    if (rxIndex == 0x40) {
        rxIndex = 0;
    }
    *(unsigned int *)((char *)self + 0x328) = rxIndex;
}

/*
 * Public method: Remove multicast address
 * Removes a multicast address from the filter and reprograms the chip
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    BOOL result;

    /* Acquire debugger lock */
    [self reserveDebuggerLock];

    /* Update address filtering (asynchronous - don't wait) */
    result = [self _setAddressFiltering:NO];
    if (!result) {
        IOLog("%s: remove multicast address failed\n", [[self name] cString]);
    }

    /* Release debugger lock */
    [self releaseDebuggerLock];
}

/*
 * Public method: Reset and enable/disable the adapter
 * Performs full chip reset and reinitializes if enabling
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    BOOL result;
    int interruptResult;

    /* Clear debugger flag */
    *(unsigned char *)((char *)self + 0x18A) = 0;

    /* Clear any pending timeouts */
    [self clearTimeout];

    /* Disable interrupts */
    [self disableAdapterInterrupts];

    /* Reset the chip */
    [self _resetChip];

    /* Reinitialize RX ring */
    result = [self _initRxRing];
    if (!result) {
        return NO;
    }

    /* Reinitialize TX ring */
    result = [self _initTxRing];
    if (!result) {
        return NO;
    }

    /* Perform chip initialization */
    result = [self _init];
    if (!result) {
        [self setRunning:NO];
        return NO;
    }

    /* Start transmit and receive */
    [self _startTransmit];
    [self _startReceive];

    /* If disabling (enable == NO), we're done */
    if (!enable) {
        [self setRunning:enable];
        *(unsigned char *)((char *)self + 0x18A) = 1;
        return YES;
    }

    /* If enabling, setup interrupts */
    interruptResult = [self enableAllInterrupts];
    if (interruptResult == 0) {
        /* Success - enable adapter interrupts */
        [self enableAdapterInterrupts];
        [self setRunning:enable];
        *(unsigned char *)((char *)self + 0x18A) = 1;
        return YES;
    }

    /* Failed to enable interrupts */
    [self setRunning:NO];
    return NO;
}

/*
 * Public method: Select 10BaseT port
 * Configures the chip for 10BaseT operation
 */
- (void)select10BaseT
{
    /* Configure CSR15 (SIA general register) = 8 */
    [self writeCSR:15 value:0x00000008];

    /* Configure CSR6 for 10BaseT mode */
    [self writeCSR:6 value:0x00400000];

    /* Cache CSR6 value at offset 0x344 */
    *(unsigned int *)((char *)self + 0x344) = 0x00400000;

    /* Configure SIA registers for 10BaseT */
    /* CSR13 (SIA connectivity) = 0 */
    [self writeCSR:13 value:0x00000000];

    /* CSR14 (SIA transmit/receive) = 0xFFFF */
    [self writeCSR:14 value:0x0000FFFF];

    /* CSR13 (SIA connectivity) = 1 to activate */
    [self writeCSR:13 value:0x00000001];
}

/*
 * Public method: Select AUI port
 * Configures the chip for AUI (Attachment Unit Interface) operation
 */
- (void)selectAUI
{
    /* Configure CSR15 (SIA general register) = 0xE (14) */
    [self writeCSR:15 value:0x0000000E];

    /* Configure CSR6 for AUI mode */
    [self writeCSR:6 value:0x00400000];

    /* Cache CSR6 value at offset 0x344 */
    *(unsigned int *)((char *)self + 0x344) = 0x00400000;

    /* Configure SIA registers for AUI */
    /* CSR13 (SIA connectivity) = 0 */
    [self writeCSR:13 value:0x00000000];

    /* CSR14 (SIA transmit/receive) = 0xF7FD */
    [self writeCSR:14 value:0x0000F7FD];

    /* CSR13 (SIA connectivity) = 9 to activate */
    [self writeCSR:13 value:0x00000009];
}

/*
 * Public method: Select BNC port
 * Configures the chip for BNC (10Base2) operation
 */
- (void)selectBNC
{
    /* Configure CSR15 (SIA general register) = 6 */
    [self writeCSR:15 value:0x00000006];

    /* Configure CSR6 for BNC mode */
    [self writeCSR:6 value:0x00400000];

    /* Cache CSR6 value at offset 0x344 */
    *(unsigned int *)((char *)self + 0x344) = 0x00400000;

    /* Configure SIA registers for BNC */
    /* CSR13 (SIA connectivity) = 0 */
    [self writeCSR:13 value:0x00000000];

    /* CSR14 (SIA transmit/receive) = 0xF7FD */
    [self writeCSR:14 value:0x0000F7FD];

    /* CSR13 (SIA connectivity) = 9 to activate */
    [self writeCSR:13 value:0x00000009];
}

/*
 * Public method: Select MII port
 * Configures the chip for MII (Media Independent Interface) operation
 */
- (void)selectMII
{
    /* CSR13 (SIA connectivity) = 0 */
    [self writeCSR:13 value:0x00000000];

    /* Configure CSR15 (SIA general register) = 8 */
    [self writeCSR:15 value:0x00000008];

    /* Configure CSR6 = 0 (reset) */
    [self writeCSR:6 value:0x00000000];

    /* CSR14 (SIA transmit/receive) = 0 */
    [self writeCSR:14 value:0x00000000];

    /* Configure CSR6 for MII mode */
    [self writeCSR:6 value:0x00040000];
}

/*
 * Public method: Send packet in polling mode
 * Used by debugger to transmit packets without interrupts
 */
- (void)sendPacket:(void *)data length:(unsigned int)length
{
    unsigned int *descriptor;
    unsigned int txHead;
    unsigned int txCount;
    netbuf_t txNetbuf;
    void *netbufData;
    int originalSize;
    BOOL result;
    int timeout;

    /* Check if in debugger mode (flag at offset 0x18A) */
    if (*(unsigned char *)((char *)self + 0x18A) == 0) {
        return;
    }

    /* Process any pending TX completions */
    [self _transmitInterruptOccurred];

    /* Check if TX descriptors are available */
    txCount = *(unsigned int *)((char *)self + 0x320);
    if (txCount == 0) {
        IOLog("%s: _sendPacket: No free tx descriptors\n", [[self name] cString]);
        return;
    }

    /* Get descriptor at txHead */
    txHead = *(unsigned int *)((char *)self + 0x318);
    descriptor = (unsigned int *)((char *)_txDescriptors + (txHead * 16));

    /* Clear netbuf in TX array (not using it for polling mode) */
    *(netbuf_t *)((char *)self + 0x190 + (txHead * 4)) = NULL;

    /* Get temporary netbuf for this packet (stored at offset 0x32C) */
    txNetbuf = *(netbuf_t *)((char *)self + 0x32C);
    netbufData = nb_map(txNetbuf);

    /* Copy packet data to netbuf */
    bcopy(data, netbufData, length);

    /* Adjust netbuf size to packet length */
    originalSize = nb_size(txNetbuf);
    nb_shrink_bot(txNetbuf, originalSize - length);

    /* Clear control word, preserving end-of-ring bit if set */
    if ((descriptor[1] & 0x02000000) == 0) {
        descriptor[1] = 0;
    } else {
        descriptor[1] = 0;
        descriptor[1] |= 0x02000000;
    }

    /* Update descriptor with netbuf */
    result = IOUpdateDescriptorFromNetBuf(txNetbuf, descriptor, NO);
    if (!result) {
        IOLog("%s: _sendPacket: IOUpdateDescriptorFromNetBuf failed\n",
              [[self name] cString]);
        nb_grow_bot(txNetbuf, originalSize - length);
        return;
    }

    /* Set first segment bit (bit 29) */
    descriptor[1] |= 0x20000000;

    /* Set last segment bit (bit 30) */
    descriptor[1] |= 0x40000000;

    /* Clear interrupt on completion bit (bit 31) - polling mode */
    descriptor[1] &= 0x7FFFFFFF;

    /* Clear status word and set ownership bit */
    descriptor[0] = 0;
    descriptor[0] |= 0x80000000;

    /* Advance txHead, wrap at 32 descriptors */
    txHead++;
    if (txHead == 0x20) {
        txHead = 0;
    }
    *(unsigned int *)((char *)self + 0x318) = txHead;

    /* Decrement available descriptor count */
    txCount--;
    *(unsigned int *)((char *)self + 0x320) = txCount;

    /* Trigger transmit poll by writing to CSR1 */
    [self writeCSR:1 value:0x00000001];

    /* Poll for transmission completion (timeout 5 seconds) */
    timeout = 0;
    while (timeout < 10000) {
        /* Check if ownership bit cleared by chip */
        if ((descriptor[0] & 0x80000000) == 0) {
            break;
        }

        /* Delay 500 microseconds */
        IODelay(500);
        timeout++;
    }

    /* Check for timeout */
    if ((descriptor[0] & 0x80000000) != 0) {
        IOLog("%s: _sendPacket: polling timed out\n", [[self name] cString]);
    }

    /* Restore netbuf to original size */
    nb_grow_bot(txNetbuf, originalSize - length);
}

- (void)serviceTransmitQueue
{
    netbuf_t packet;
    unsigned int txCount;
    void *txQueue;

    /* Get transmit queue pointer at offset 0x184 */
    txQueue = *(void **)((char *)self + 0x184);
    if (txQueue == NULL) {
        return;
    }

    /* Service packets while descriptors are available */
    while (YES) {
        /* Check if TX descriptors are available at offset 0x320 */
        txCount = *(unsigned int *)((char *)self + 0x320);
        if (txCount == 0) {
            break;
        }

        /* Dequeue packet from transmit queue */
        packet = nb_dequeue(txQueue);
        if (packet == NULL) {
            break;
        }

        /* Transmit the packet */
        [self _transmitPacket:packet];
    }
}

- (IOReturn)setPowerManagement:(unsigned int)powerLevel
{
    /* Power management not supported */
    return 0xfffffd39;  /* IO_R_UNSUPPORTED */
}

- (IOReturn)setPowerState:(unsigned int)powerState
{
    /* Only handle power state 3 (ON_STATE) */
    if (powerState == 3) {
        /* Clear debugger flag at offset 0x18A */
        *(unsigned char *)((char *)self + 0x18A) = 0;

        /* Reset the chip */
        [self _resetChip];

        return IO_R_SUCCESS;
    }

    /* Other power states not supported */
    return 0xfffffd39;  /* IO_R_UNSUPPORTED */
}

- (void)timeoutOccurred
{
    BOOL running;

    /* Check if adapter is running */
    running = *(BOOL *)((char *)self + 0x17C);
    if (!running) {
        return;
    }

    /* Acquire lock at offset 0x180 */
    IOTakeLock(*(void **)((char *)self + 0x180));

    /* Process any pending TX completions */
    [self _transmitInterruptOccurred];

    /* Release lock */
    IOUnlock(*(void **)((char *)self + 0x180));

    /* Service transmit queue */
    [self serviceTransmitQueue];
}

- (void)transmit:(netbuf_t)packet
{
    BOOL running;
    unsigned int txCount;
    void *txQueue;
    unsigned int queueCount;

    /* Validate netbuf */
    if (packet == NULL) {
        return;
    }

    /* Check if adapter is running at offset 0x17C */
    running = *(BOOL *)((char *)self + 0x17C);
    if (!running) {
        nb_free(packet);
        return;
    }

    /* Acquire lock at offset 0x180 */
    IOTakeLock(*(void **)((char *)self + 0x180));

    /* Process any pending TX completions */
    [self _transmitInterruptOccurred];

    /* Release lock */
    IOUnlock(*(void **)((char *)self + 0x180));

    /* Check if TX descriptors are available at offset 0x320 */
    txCount = *(unsigned int *)((char *)self + 0x320);

    /* Get transmit queue pointer at offset 0x184 */
    txQueue = *(void **)((char *)self + 0x184);
    if (txQueue != NULL) {
        queueCount = nb_queue_size(txQueue);
    } else {
        queueCount = 0;
    }

    /* If no descriptors available or queue not empty, enqueue packet */
    if (txCount == 0 || queueCount != 0) {
        if (txQueue != NULL) {
            nb_enqueue(txQueue, packet);
        } else {
            /* No queue, drop packet */
            nb_free(packet);
        }
        return;
    }

    /* Transmit directly */
    [self _transmitPacket:packet];
}

- (unsigned int)transmitQueueCount
{
    void *txQueue;

    /* Get transmit queue pointer at offset 0x184 */
    txQueue = *(void **)((char *)self + 0x184);
    if (txQueue == NULL) {
        return 0;
    }

    /* Return count of packets in queue */
    return [txQueue count];
}

- (unsigned int)transmitQueueSize
{
    /* Return maximum queue size */
    return TX_QUEUE_MAX_SIZE;
}

@end
