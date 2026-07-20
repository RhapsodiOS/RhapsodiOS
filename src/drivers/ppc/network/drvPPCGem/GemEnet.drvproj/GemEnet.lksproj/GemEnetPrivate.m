/* GemEnetPrivate.m - PowerPC Gem Ethernet Driver Private Methods */

#import "GemEnet.h"
#import <kernserv/prototypes.h>

// Gem register offsets (encoded with size in upper 16 bits)
// Format: (size << 16) | offset, where size: 1=byte, 2=word, 4=dword
#define kGemRegInterruptMask		0x40010		// Interrupt mask register
#define kGemRegInterruptStatus		0x40000		// Interrupt status register
#define kGemRegSoftwareReset		0x19050		// Software reset
#define kGemRegSoftwareResetControl	0x11010		// Software reset control
#define kGemRegConfigReg		0x1603c		// Configuration register
#define kGemRegPCSMIIStatus		0x19054		// PCS/MII status
#define kGemRegMIFFrameControl		0x29008		// MIF frame control
#define kGemRegMIFConfig		0x29000		// MIF configuration
#define kGemRegMIFStatus2		0x29004		// MIF status 2 (link)
#define kGemRegMIFMask			0x19010		// MIF mask
#define kGemRegPCSConfig		0x46008		// PCS configuration
#define kGemRegMIFStatus		0x16038		// MIF status
#define kGemRegPauseThreshold		0x26020		// Pause threshold
#define kGemRegNonPauseThreshold	0x26024		// Non-pause threshold
#define kGemRegRXPauseThreshold		0x16028		// RX pause threshold
#define kGemRegMACTXConfig		0x20004		// MAC TX configuration
#define kGemRegMACRXConfig		0x16040		// MAC RX configuration
#define kGemRegMACControlConfig		0x16044		// MAC control configuration
#define kGemRegMACXIFConfig		0x16048		// MAC XIF configuration
#define kGemRegInterPacketGap0		0x2604c		// Inter-packet gap 0
#define kGemRegInterPacketGap1		0x26050		// Inter-packet gap 1
#define kGemRegSlotTime			0x26054		// Slot time
#define kGemRegMinFrameSize		0x26058		// Minimum frame size
#define kGemRegMaxFrameSize		0x1605c		// Maximum frame size
#define kGemRegPreambleLength		0x16060		// Preamble length
#define kGemRegJamSize			0x26064		// JAM size
#define kGemRegMACAddress0		0x26080		// MAC address word 0
#define kGemRegMACAddress1		0x26084		// MAC address word 1
#define kGemRegMACAddress2		0x26088		// MAC address word 2
#define kGemRegMACAddress3		0x2608c		// MAC address word 3 (filter)
#define kGemRegMACAddress4		0x26090		// MAC address word 4 (filter)
#define kGemRegMACAddress5		0x26094		// MAC address word 5 (filter)
#define kGemRegAddressFilter0		0x260a4		// Address filter 0
#define kGemRegAddressFilter1		0x260a8		// Address filter 1
#define kGemRegAddressFilter2		0x260ac		// Address filter 2
#define kGemRegAddressFilterMask00	0x26098		// Address filter mask 0-0
#define kGemRegAddressFilterMask10	0x2609c		// Address filter mask 1-0
#define kGemRegAddressFilterMask20	0x260a0		// Address filter mask 2-0
#define kGemRegNormalCollisions		0x160b0		// Normal collision counter
#define kGemRegFirstAttemptSuccess	0x260b4		// First attempt success
#define kGemRegHashTable		0x260c0		// Hash table base
#define kGemRegRandomSeed		0x26130		// Random seed
#define kGemRegTXDescriptorBaseLow	0x42008		// TX descriptor base low
#define kGemRegTXDescriptorBaseHigh	0x4200c		// TX descriptor base high
#define kGemRegTXConfiguration		0x42004		// TX configuration
#define kGemRegTXKickWrite		0x22000		// TX kick write
#define kGemRegTXCompletion		0x22100		// TX completion index
#define kGemRegTXKick			0x26030		// TX kick
#define kGemRegRXDescriptorBaseLow	0x44004		// RX descriptor base low
#define kGemRegRXDescriptorBaseHigh	0x44008		// RX descriptor base high
#define kGemRegRXConfiguration		0x44000		// RX configuration
#define kGemRegRXKick			0x26034		// RX kick
#define kGemRegRXFIFOSize		0x24120		// RX FIFO size
#define kGemRegRXBlankingTime		0x44020		// RX blanking time
#define kGemRegRXPauseThresholdReg	0x24100		// RX pause threshold register
#define kGemRegBIFConfig		0x11008		// BIF configuration
#define kGemRegTXCompletionTimeout	0x44108		// TX completion timeout
#define kGemRegMACRXFrameCount		0x2611c		// MAC RX frame count
#define kGemRegMACRXLengthError		0x26124		// MAC RX length error count

// External function declarations
extern unsigned int _ReadGemRegister(int base, unsigned int offset_and_size);
extern void _WriteGemRegister(int base, unsigned int offset_and_size, unsigned int value);
extern void enforceInOrderExecutionIO(void);
extern int IOPhysicalFromVirtual(void *virtualAddr, void **physicalAddr);
extern void IOGetTimestamp(ns_time_t *time);

// DMA page size
#define PAGE_SIZE		4096

//
// Register dump table structure
//
typedef struct {
    unsigned int	regOffset;	// Register offset with size encoded
    char		*regName;	// Register name
} GemRegisterDef;

//
// Table of all Gem registers for debugging
//
static GemRegisterDef gemRegisterTable[] = {
    { kGemRegInterruptStatus, "InterruptStatus" },
    { kGemRegInterruptMask, "InterruptMask" },
    { kGemRegSoftwareReset, "SoftwareReset" },
    { kGemRegConfigReg, "Config" },
    { kGemRegPCSMIIStatus, "PCS_MII_Status" },
    { kGemRegMIFFrameControl, "MIF_FrameCtrl" },
    { kGemRegMIFConfig, "MIF_Config" },
    { kGemRegMIFMask, "MIF_Mask" },
    { kGemRegPCSConfig, "PCS_Config" },
    { kGemRegMIFStatus, "MIF_Status" },
    { kGemRegPauseThreshold, "PauseThreshold" },
    { kGemRegNonPauseThreshold, "NonPauseThreshold" },
    { kGemRegRXPauseThreshold, "RX_PauseThreshold" },
    { kGemRegMACTXConfig, "MAC_TX_Config" },
    { kGemRegMACRXConfig, "MAC_RX_Config" },
    { kGemRegMACControlConfig, "MAC_CtrlConfig" },
    { kGemRegMACXIFConfig, "MAC_XIF_Config" },
    { kGemRegInterPacketGap0, "InterPacketGap0" },
    { kGemRegInterPacketGap1, "InterPacketGap1" },
    { kGemRegSlotTime, "SlotTime" },
    { kGemRegMinFrameSize, "MinFrameSize" },
    { kGemRegMaxFrameSize, "MaxFrameSize" },
    { kGemRegPreambleLength, "PreambleLength" },
    { kGemRegJamSize, "JamSize" },
    { kGemRegMACAddress0, "MAC_Addr0" },
    { kGemRegMACAddress1, "MAC_Addr1" },
    { kGemRegMACAddress2, "MAC_Addr2" },
    { kGemRegTXDescriptorBaseLow, "TX_DescBaseLow" },
    { kGemRegTXDescriptorBaseHigh, "TX_DescBaseHigh" },
    { kGemRegTXConfiguration, "TX_Config" },
    { kGemRegTXKick, "TX_Kick" },
    { kGemRegRXDescriptorBaseLow, "RX_DescBaseLow" },
    { kGemRegRXDescriptorBaseHigh, "RX_DescBaseHigh" },
    { kGemRegRXConfiguration, "RX_Config" },
    { kGemRegRXKick, "RX_Kick" },
    { kGemRegRXFIFOSize, "RX_FIFO_Size" },
    { kGemRegRXBlankingTime, "RX_BlankingTime" },
    { kGemRegBIFConfig, "BIF_Config" },
    { kGemRegTXCompletionTimeout, "TX_CompTimeout" },
    { 0, NULL }  // End marker
};

//
// Calculate MACE-style CRC for multicast hash
//
static unsigned int _mace_crc(unsigned char *address)
{
    unsigned int crc = 0xFFFFFFFF;
    int i, j;
    unsigned char byte;

    for (i = 0; i < 6; i++) {
        byte = address[i];
        for (j = 0; j < 8; j++) {
            if ((crc ^ byte) & 0x01) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc = crc >> 1;
            }
            byte >>= 1;
        }
    }

    return crc;
}

@implementation GemEnet(Private)

//
// Initialize chip
//
- (BOOL)_initChip
{
    unsigned int i;
    unsigned int txRingSize, rxRingSize;
    unsigned int txShift, rxShift;
    unsigned int bifConfig;
    unsigned int rxFIFOSize;
    int timeoutDivisor;
    unsigned short randomSeed;

    // Software reset
    _WriteGemRegister((int)memBase, kGemRegSoftwareReset, 2);

    // Configuration register
    _WriteGemRegister((int)memBase, kGemRegConfigReg, 0x49);

    // PCS/MII status
    _WriteGemRegister((int)memBase, kGemRegPCSMIIStatus, 3);

    // MIF frame control - set to 0xa0
    _WriteGemRegister((int)memBase, kGemRegMIFFrameControl, 0xa0);

    // MIF configuration
    _WriteGemRegister((int)memBase, kGemRegMIFConfig, 0x1200);

    // MIF mask
    _WriteGemRegister((int)memBase, kGemRegMIFMask, 1);

    // PCS configuration
    _WriteGemRegister((int)memBase, kGemRegPCSConfig, 0x1bf0);

    // MIF status
    _WriteGemRegister((int)memBase, kGemRegMIFStatus, 3);

    // Disable all interrupts
    _WriteGemRegister((int)memBase, kGemRegInterruptMask, 0xffffffff);

    // Pause thresholds
    _WriteGemRegister((int)memBase, kGemRegPauseThreshold, 0xffff);
    _WriteGemRegister((int)memBase, kGemRegNonPauseThreshold, 0xffff);

    // RX pause threshold
    _WriteGemRegister((int)memBase, kGemRegRXPauseThreshold, 0xff);

    // MAC TX configuration
    _WriteGemRegister((int)memBase, kGemRegMACTXConfig, 0x42);

    // MAC RX configuration
    _WriteGemRegister((int)memBase, kGemRegMACRXConfig, 0);

    // MAC control configuration
    _WriteGemRegister((int)memBase, kGemRegMACControlConfig, 8);

    // MAC XIF configuration
    _WriteGemRegister((int)memBase, kGemRegMACXIFConfig, 4);

    // Inter-packet gaps
    _WriteGemRegister((int)memBase, kGemRegInterPacketGap0, 0x40);
    _WriteGemRegister((int)memBase, kGemRegInterPacketGap1, 0x40);

    // Slot time
    _WriteGemRegister((int)memBase, kGemRegSlotTime, 0x5ee);

    // Minimum frame size
    _WriteGemRegister((int)memBase, kGemRegMinFrameSize, 7);

    // Maximum frame size
    _WriteGemRegister((int)memBase, kGemRegMaxFrameSize, 4);

    // Preamble length
    _WriteGemRegister((int)memBase, kGemRegPreambleLength, 0x10);

    // JAM size
    _WriteGemRegister((int)memBase, kGemRegJamSize, 0x8808);

    // Write MAC address (3 words, reversed order)
    for (i = 0; i < 3; i++) {
        _WriteGemRegister((int)memBase, kGemRegMACAddress0 + (i * 4),
                         *(unsigned short *)((int)&myAddress + (2 - i) * 2));
    }

    // Clear MAC address filter words 3-5
    for (i = 0; i < 3; i++) {
        _WriteGemRegister((int)memBase, kGemRegMACAddress3 + (i * 4), 0);
        _WriteGemRegister((int)memBase, kGemRegAddressFilter0 + (i * 4), 0);
    }

    // Address filter masks
    _WriteGemRegister((int)memBase, kGemRegAddressFilterMask00, 1);
    _WriteGemRegister((int)memBase, kGemRegAddressFilterMask10, 0xc200);
    _WriteGemRegister((int)memBase, kGemRegAddressFilterMask20, 0x180);

    // Collision counters
    _WriteGemRegister((int)memBase, kGemRegNormalCollisions, 0);
    _WriteGemRegister((int)memBase, kGemRegFirstAttemptSuccess, 0);

    // Clear hash table (16 entries)
    for (i = 0; i < 16; i++) {
        _WriteGemRegister((int)memBase, kGemRegHashTable + (i * 4), 0);
    }

    // Clear additional registers (0x26100-0x26128)
    for (i = 0x26100; i <= 0x26128; i += 4) {
        _WriteGemRegister((int)memBase, (4 << 16) | i, 0);
    }

    // Get MAC address and write random seed
    [self _getStationAddress:&myAddress];
    randomSeed = *(unsigned short *)((int)&myAddress + 4);
    _WriteGemRegister((int)memBase, kGemRegRandomSeed, randomSeed);

    // TX descriptor base addresses (use physical address for hardware)
    _WriteGemRegister((int)memBase, kGemRegTXDescriptorBaseLow, txDMACommandsPhys);
    _WriteGemRegister((int)memBase, kGemRegTXDescriptorBaseHigh, 0);

    // Calculate TX ring size (log2 of ring entries)
    txRingSize = 3;  // Assuming 3 entries for now
    txShift = 0;
    for (i = 0; i < 13; i++) {
        if (txRingSize == 0) break;
        txShift++;
        txRingSize >>= 1;
    }

    // TX configuration
    _WriteGemRegister((int)memBase, kGemRegTXConfiguration, (txShift << 1) | 0x1ffc00);

    // TX kick
    _WriteGemRegister((int)memBase, kGemRegTXKick, 6);

    // RX descriptor base addresses (use physical address for hardware)
    _WriteGemRegister((int)memBase, kGemRegRXDescriptorBaseLow, rxDMACommandsPhys);
    _WriteGemRegister((int)memBase, kGemRegRXDescriptorBaseHigh, 0);

    // RX pause threshold register
    _WriteGemRegister((int)memBase, kGemRegRXPauseThresholdReg, 0x7c);

    // Calculate RX ring size (log2 of ring entries)
    rxRingSize = 3;  // Assuming 3 entries for now
    rxShift = 0;
    for (i = 0; i < 13; i++) {
        if (rxRingSize == 0) break;
        rxShift++;
        rxRingSize >>= 1;
    }

    // RX configuration
    _WriteGemRegister((int)memBase, kGemRegRXConfiguration, (rxShift << 1) | 0x1000000);

    // RX kick
    _WriteGemRegister((int)memBase, kGemRegRXKick, 0);

    // RX blanking time
    rxFIFOSize = _ReadGemRegister((int)memBase, kGemRegRXFIFOSize);
    _WriteGemRegister((int)memBase, kGemRegRXBlankingTime, ((rxFIFOSize - 0x60) & 0xffff) | 0x60000);

    // TX completion timeout
    bifConfig = _ReadGemRegister((int)memBase, kGemRegBIFConfig);
    timeoutDivisor = (bifConfig & 8) ? 0xf : 0x1e;
    _WriteGemRegister((int)memBase, kGemRegTXCompletionTimeout,
                     ((250000 / (timeoutDivisor << 11)) << 12) | 5);

    return YES;
}

//
// Reset chip
//
- (void)_resetChip
{
    unsigned int resetStatus;

    // Write 3 to software reset control register
    _WriteGemRegister((int)memBase, kGemRegSoftwareResetControl, 3);

    // Poll until reset completes (bits 0 and 1 clear)
    do {
        resetStatus = _ReadGemRegister((int)memBase, kGemRegSoftwareResetControl);
    } while ((resetStatus & 3) != 0);
}

//
// Start chip
//
- (void)_startChip
{
    unsigned int regValue;

    // Enable TX DMA - set bit 0 of TX configuration register
    regValue = _ReadGemRegister((int)memBase, kGemRegTXConfiguration);
    regValue = regValue | 1;
    _WriteGemRegister((int)memBase, kGemRegTXConfiguration, regValue);

    // Delay 20 microseconds
    IODelay(20);

    // Enable RX DMA - set bit 0 of RX configuration register
    regValue = _ReadGemRegister((int)memBase, kGemRegRXConfiguration);
    regValue = regValue | 1;
    _WriteGemRegister((int)memBase, kGemRegRXConfiguration, regValue);

    // Delay 20 microseconds
    IODelay(20);

    // Enable MAC transmitter - set bit 0 of MAC TX config
    regValue = _ReadGemRegister((int)memBase, kGemRegMACTXConfig);
    regValue = regValue | 1;
    _WriteGemRegister((int)memBase, kGemRegMACTXConfig, regValue);

    // Delay 20 microseconds
    IODelay(20);

    // Enable MAC receiver - set bit 0 of MAC RX config
    regValue = _ReadGemRegister((int)memBase, kGemRegMACRXConfig);
    regValue = regValue | 1;
    _WriteGemRegister((int)memBase, kGemRegMACRXConfig, regValue);
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

    // Calculate allocation size (aligned to page boundary)
    allocSize = (PAGE_SIZE + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);

    // Allocate DMA command memory
    if (dmaCommands == NULL) {
        result = IOPhysicalFromVirtual((void *)PAGE_SIZE, &dmaCommands);
        if (result != 0) {
            IOLog("Ethernet(Gem): Cant allocate channel dma commands\n\r");
            return NO;
        }

        // Calculate number of pages needed
        numPages = (allocSize - PAGE_SIZE) / PAGE_SIZE;

        // Get physical address of first page
        IOPhysicalFromVirtual(dmaCommands, (void **)&firstPagePhys);

        // Verify contiguous allocation
        currentPage = dmaCommands;
        for (i = 0; i < numPages; i++) {
            IOPhysicalFromVirtual(currentPage, (void **)&physAddr);
            if ((int)physAddr != (firstPagePhys + (i * PAGE_SIZE))) {
                IOLog("Ethernet(Gem): Cant allocate contiguous memory for dma commands\n\r");
                return NO;
            }
            currentPage = (void *)((int)currentPage + PAGE_SIZE);
        }

        // Set up TX and RX DMA command pointers (virtual addresses)
        txDMACommands = dmaCommands;
        txDMACommandsSize = 0x80;  // 128 bytes
        rxDMACommands = (void *)((int)dmaCommands + 0x800);  // Offset by 2048 bytes
        rxDMACommandsSize = 0x80;  // 128 bytes

        // Calculate physical addresses for hardware
        IOPhysicalFromVirtual(txDMACommands, (void **)&txDMACommandsPhys);
        IOPhysicalFromVirtual(rxDMACommands, (void **)&rxDMACommandsPhys);
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
    bzero(rxDMACommands, rxDMACommandsSize << 4);

    // Initialize TX ring pointers
    txHead = 0;
    txTail = 0;

    // Free existing transmit queue if present
    if (transmitQueue != nil) {
        [transmitQueue free];
    }

    // Allocate new transmit queue with max 256 entries
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:0x100];
    if (transmitQueue == nil) {
        IOLog("Ethernet(Gem): Cant allocate transmit queue\n\r");
        return NO;
    }

    // Get physical address and verify it's valid
    result = IOPhysicalFromVirtual(rxDMACommands, &physAddr);
    if (result == 0) {
        IOLog("Ethernet(Gem): Bad dma command buf - %08x\n\r", (unsigned int)rxDMACommands);
        return NO;
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

    // Zero the RX ring descriptor memory
    bzero(txDMACommands, txDMACommandsSize << 4);

    // Get physical address and verify it's valid
    result = IOPhysicalFromVirtual(txDMACommands, &physAddr);
    if (result != 0) {
        IOLog("Ethernet(Gem): Bad dma command buf - %08x\n\r", (unsigned int)txDMACommands);
        return NO;
    }

    // Allocate netbufs for each RX ring entry
    for (i = 0; i < txDMACommandsSize; i++) {
        // Allocate netbuf if not already allocated
        if (rxNetbufs[i] == NULL) {
            nb = [self allocateNetbuf];
            if (nb == NULL) {
                IOLog("Ethernet(Gem): allocateNetbuf returned NULL in _initRxRing\n\r");
                return NO;
            }
            rxNetbufs[i] = nb;
        }

        // Update descriptor from netbuf
        updateResult = [self _updateDescriptorFromNetBuf:rxNetbufs[i]
                                                     Desc:(void *)((int)txDMACommands + (i * 0x10))
                                             ReceiveFlag:YES];
        if (!updateResult) {
            IOLog("Ethernet(Gem): cant map Netbuf to physical memory in _initRxRing\n\r");
            return NO;
        }
    }

    // Initialize RX ring pointers
    rxHead = 0;
    rxTail = i - 4;  // Tail is size minus 4

    return YES;
}

//
// Enable adapter interrupts
//
- (void)_enableAdapterInterrupts
{
    unsigned int intMask;

    // Read current interrupt mask
    intMask = _ReadGemRegister((int)memBase, kGemRegInterruptMask);

    // Clear bits to enable interrupts (0x7fee enables specific interrupts)
    // Writing 0 to a bit enables that interrupt
    intMask &= 0xffff7fee;

    // Write back the modified mask
    _WriteGemRegister((int)memBase, kGemRegInterruptMask, intMask);
}

//
// Disable adapter interrupts
//
- (void)_disableAdapterInterrupts
{
    // Write all 1's to the interrupt mask register to disable all interrupts
    _WriteGemRegister((int)memBase, kGemRegInterruptMask, 0xFFFFFFFF);
}

//
// Handle transmit interrupt
//
- (void)_transmitInterruptOccurred
{
    unsigned int completionIndex;
    unsigned int descriptorIndex;
    void *descriptorAddr;
    unsigned int flags;
    netbuf_t nb;

    // Read TX completion index from hardware
    completionIndex = _ReadGemRegister((int)memBase, kGemRegTXCompletion);

    // Process all completed transmissions
    while (txHead != completionIndex) {
        descriptorIndex = txHead;

        // Get descriptor address (remember: rxDMACommands is used for TX descriptors)
        descriptorAddr = (void *)((int)rxDMACommands + (descriptorIndex * 0x10));

        // Read flags from descriptor (at offset +4)
        flags = *(unsigned int *)((int)descriptorAddr + 4);

        // Byte swap flags (big-endian)
        flags = (flags << 24) | ((flags >> 8) & 0xFF00) |
                ((flags << 8) & 0xFF0000) | (flags >> 24);

        // Get the netbuf from transmit queue
        nb = [transmitQueue dequeue];
        if (nb != NULL) {
            // Free the transmitted netbuf
            nb_free(nb);

            // Increment output packet counter
            [network incrementOutputPackets];
        }

        // Move to next descriptor
        txHead++;
        if (txHead >= txDMACommandsSize) {
            txHead = 0;
        }
    }

    // Service the transmit queue if there are pending packets
    [self serviceTransmitQueue];
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
    void *descriptorAddr;
    unsigned int flags;
    BOOL updateResult;

    // Calculate next tail position
    nextTail = txTail + 1;
    if (nextTail >= rxDMACommandsSize) {
        nextTail = 0;
    }

    // Check if ring is full
    if (nextTail == txHead) {
        // Ring is full, can't transmit
        IOLog("Ethernet(Gem): TX ring full\n\r");
        nb_free(packet);
        return;
    }

    // Get descriptor address (remember: rxDMACommands is used for TX descriptors)
    descriptorAddr = (void *)((int)rxDMACommands + (txTail * 0x10));

    // Update descriptor from netbuf
    updateResult = [self _updateDescriptorFromNetBuf:packet
                                                 Desc:descriptorAddr
                                         ReceiveFlag:NO];
    if (!updateResult) {
        IOLog("Ethernet(Gem): cant map TX netbuf to physical memory\n\r");
        nb_free(packet);
        return;
    }

    // Read flags from descriptor (at offset +4)
    flags = *(unsigned int *)((int)descriptorAddr + 4);

    // Byte swap flags to host order
    flags = (flags << 24) | ((flags >> 8) & 0xFF00) |
            ((flags << 8) & 0xFF0000) | (flags >> 24);

    // Set ownership bit (bit 31) - hardware now owns this descriptor
    flags = flags | 0x80000000;

    // Byte swap back to descriptor format
    flags = (flags << 24) | ((flags >> 8) & 0xFF00) |
            ((flags << 8) & 0xFF0000) | (flags >> 24);

    // Write flags back to descriptor
    *(unsigned int *)((int)descriptorAddr + 4) = flags;

    // Ensure write completes before updating tail
    enforceInOrderExecutionIO();

    // Add packet to transmit queue for later cleanup
    [transmitQueue enqueue:packet];

    // Update tail pointer
    txTail = nextTail;

    // Kick the hardware to start transmission
    _WriteGemRegister((int)memBase, kGemRegTXKickWrite, txTail);
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
            IOLog("Ethernet(Gem): Polled tranmit timeout - 1\n\r");
            [self enableAllInterrupts];
            return;
        }
    } while (1);

    // Allocate netbuf for the packet
    nb = [self allocateNetbuf];
    if (nb == NULL) {
        [self enableAllInterrupts];
        return;
    }

    // Store in debugger buffer pointer for tracking
    debuggerPktBuffer = (void *)nb;

    // Get data pointer and copy packet data
    data = nb_map(nb);
    bcopy(pkt, data, len);

    // Trim netbuf to actual packet size
    bufferSize = nb_size(nb);
    nb_shrink_bot(nb, bufferSize - len);

    // Transmit the packet
    [self _transmitPacket:nb];

    // Reset start time for transmission wait
    IOGetTimestamp(&startTime);

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
            IOLog("Ethernet(Gem): Polled tranmit timeout - 2\n\r");
            break;
        }
    } while (1);

    // Re-enable interrupts
    [self enableAllInterrupts];
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
    unsigned short statusWord;
    unsigned short packetLength;
    unsigned int flags;
    BOOL hasError;
    BOOL isUnwanted;
    BOOL allocated;
    netbuf_t oldNetbuf;
    netbuf_t newNetbuf;
    void *descriptorAddr;
    int oldLength;
    int frameErrors;
    int lengthErrors;
    id superclass;

    currentIndex = rxHead;
    previousIndex = 0xFFFFFFFF;

    // Process all received packets in the ring
    while (1) {
        allocated = NO;
        isUnwanted = NO;
        hasError = NO;

        // Get descriptor address
        descriptorAddr = (void *)((int)txDMACommands + (currentIndex * 0x10));

        // Read status word at offset +2 (big-endian, need to swap)
        statusWord = *(unsigned short *)((int)descriptorAddr + 2);
        statusWord = (statusWord >> 8) | (statusWord << 8);  // Byte swap

        // Check ownership bit (0x80)
        if ((statusWord & 0x80) != 0) {
            // Hardware owns this descriptor, we're done
            break;
        }

        // Extract packet length (bits 0-14)
        packetLength = statusWord & 0x7FFF;

        // Read flags at offset +4
        flags = *(unsigned int *)((int)descriptorAddr + 4);
        flags = (flags << 24) | ((flags >> 8) & 0xFF00) | ((flags << 8) & 0xFF0000) | (flags >> 24);

        // Check for errors: bad length or error flag
        if ((packetLength < 0x3C) || (packetLength > 0x5EE) || ((flags & 0x40000000) != 0)) {
            [network incrementInputErrors];
            hasError = YES;
        }

        // Get the netbuf for this slot
        oldNetbuf = rxNetbufs[currentIndex];

        if (!hasError) {
            // Check if unwanted multicast (only if not promiscuous)
            if (!promiscuousMode && ((flags & 0x10000000) != 0)) {
                // Multicast packet - check if we want it
                superclass = [IOEthernet self];
                if ([superclass isUnwantedMulticastPacket:[oldNetbuf data]]) {
                    isUnwanted = YES;
                }
            }

            if (!isUnwanted) {
                // Allocate new netbuf for this slot
                newNetbuf = [self allocateNetbuf];
                if (newNetbuf == NULL) {
                    [network incrementInputErrors];
                    hasError = YES;
                } else {
                    // Store new netbuf in slot
                    rxNetbufs[currentIndex] = newNetbuf;
                    allocated = YES;

                    // Update descriptor with new netbuf
                    if (![self _updateDescriptorFromNetBuf:newNetbuf
                                                      Desc:descriptorAddr
                                              ReceiveFlag:YES]) {
                        IOLog("Ethernet(Gem): _updateDescriptorFromNetBuf failed for receive\n");
                    }

                    // Trim old netbuf to actual packet length
                    oldLength = nb_size(oldNetbuf);
                    nb_shrink_bot(oldNetbuf, oldLength - packetLength);
                }
            }
        }

        // Reset descriptor if error or unwanted
        if (hasError || isUnwanted) {
            // Reset descriptor: status = 0xF085 (byte swapped = 0x85F0), flags = 0
            *(unsigned short *)((int)descriptorAddr + 2) = 0xF085;
            *(unsigned int *)((int)descriptorAddr + 4) = 0;
        }

        // Advance to next descriptor
        previousIndex = currentIndex;
        currentIndex++;
        if (currentIndex >= txDMACommandsSize) {
            currentIndex = 0;
        }

        // If we allocated a new buffer, process the old one
        if (allocated) {
            if (freeRun) {
                // Polling mode - send to debugger
                [self _packetToDebugger:oldNetbuf];
                break;  // Only process one packet in polling mode
            } else {
                // Normal mode - send to network stack
                [network handleInputPacket:oldNetbuf extra:0];
            }
        }
    }

    // Update ring pointers if we processed any packets
    if (previousIndex != 0xFFFFFFFF) {
        rxTail = previousIndex;
        rxHead = currentIndex;
    }

    // Update hardware RX kick register (aligned to 4-byte boundary)
    _WriteGemRegister((int)memBase, kGemRegRXPauseThresholdReg, rxTail & 0xFFFFFFFC);

    // Read and clear error counters
    frameErrors = _ReadGemRegister((int)memBase, kGemRegMACRXFrameCount);
    lengthErrors = _ReadGemRegister((int)memBase, kGemRegMACRXLengthError);
    _WriteGemRegister((int)memBase, kGemRegMACRXFrameCount, 0);
    _WriteGemRegister((int)memBase, kGemRegMACRXLengthError, 0);

    // Increment error counter
    [network incrementInputErrorsBy:(frameErrors + lengthErrors)];

    return YES;
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
// Update Gem hash table mask
//
- (void)_updateGemHashTableMask
{
    unsigned short rxKickValue;
    unsigned int statusValue;
    unsigned int i;

    // Read current RX kick register value
    rxKickValue = _ReadGemRegister((int)memBase, kGemRegRXKick);

    // Disable RX kick by clearing bits (AND with 0xffde)
    _WriteGemRegister((int)memBase, kGemRegRXKick, rxKickValue & 0xffde);

    // Wait for RX to stop (wait until bits 0x21 are clear)
    do {
        statusValue = _ReadGemRegister((int)memBase, kGemRegRXKick);
    } while ((statusValue & 0x21) != 0);

    // Write all 16 hash table entries to hardware
    // Note: hashTableMask array is written in reverse order to hardware registers
    for (i = 0; i < 0x10; i++) {
        _WriteGemRegister((int)memBase,
                         kGemRegHashTable + (i * 4),
                         hashTableMask[0xf - i]);
    }

    // Re-enable RX kick with bit 0x20 set
    _WriteGemRegister((int)memBase, kGemRegRXKick, rxKickValue | 0x20);
}

//
// Add address to hash table mask
//
- (void)_addToHashTableMask:(enet_addr_t *)addr
{
    unsigned int crc;
    unsigned int hashIndex;
    unsigned int i;
    unsigned int bitIndex;
    unsigned int byteIndex;

    // Calculate CRC for the address
    crc = _mace_crc((unsigned char *)addr);

    // Take lower 8 bits of CRC
    crc = crc & 0xFF;

    // Reverse the bits in the byte
    hashIndex = 0;
    for (i = 0; i < 8; i++) {
        hashIndex = (hashIndex >> 1) | (crc & 0x80);
        crc = crc << 1;
    }

    // Invert the hash index
    hashIndex = hashIndex ^ 0xFF;

    // Increment usage counter for this hash
    hashTableUseCount[hashIndex]++;

    // If this is the first use of this hash, set the bit in the filter mask
    if (hashTableUseCount[hashIndex] == 1) {
        bitIndex = hashIndex & 0x0F;  // Which bit in the word
        byteIndex = (hashIndex >> 3) & 0x1E;  // Which word (aligned to 2-byte boundary)
        hashTableMask[byteIndex / 2] |= (1 << bitIndex);
    }
}

//
// Remove address from hash table mask
//
- (void)_removeFromHashTableMask:(enet_addr_t *)addr
{
    unsigned int crc;
    unsigned int hashIndex;
    unsigned int i;
    unsigned int bitIndex;
    unsigned int byteIndex;
    short count;

    // Calculate CRC for the address
    crc = _mace_crc((unsigned char *)addr);

    // Take lower 8 bits of CRC
    crc = crc & 0xFF;

    // Reverse the bits in the byte
    hashIndex = 0;
    for (i = 0; i < 8; i++) {
        hashIndex = (hashIndex >> 1) | (crc & 0x80);
        crc = crc << 1;
    }

    // Invert the hash index
    hashIndex = hashIndex ^ 0xFF;

    // Get current count
    count = hashTableUseCount[hashIndex];

    // Only decrement if count is non-zero
    if (count != 0) {
        count--;
        hashTableUseCount[hashIndex] = count;

        // If this was the last use of this hash, clear the bit in the filter mask
        if (count == 0) {
            bitIndex = hashIndex & 0x0F;  // Which bit in the word
            byteIndex = (hashIndex >> 3) & 0x1E;  // Which word (aligned to 2-byte boundary)
            hashTableMask[byteIndex / 2] &= ~(1 << bitIndex);
        }
    }
}

//
// Get station address from device tree
//
- (void)_getStationAddress:(enet_addr_t *)addr
{
    IODeviceDescription *deviceDesc;
    id propertyTable;
    void *macAddressData = NULL;
    int macAddressLength[4];
    int result;
    unsigned int i;

    // Get device description
    deviceDesc = [self deviceDescription];
    if (!deviceDesc) {
        return;
    }

    // Get property table
    propertyTable = [deviceDesc propertyTable];
    if (!propertyTable) {
        return;
    }

    // Get "local-mac-address" property
    macAddressLength[0] = 0;
    result = [propertyTable getProperty:"local-mac-address"
                                  flags:0x10000
                                  value:&macAddressData
                                 length:macAddressLength];

    // If we got the MAC address and it's the right length (6 bytes)
    // Note: getProperty returns 0 on failure, non-zero on success
    if ((result == 0) && (macAddressLength[0] == 6)) {
        // Copy the 6 bytes
        for (i = 0; i < 6; i++) {
            addr->ea_byte[i] = ((unsigned char *)macAddressData)[i];
        }
    }
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
    unsigned int flags;
    unsigned short length;
    static unsigned int txCnt = 0;

    // Determine buffer size
    if (isReceive) {
        bufferSize = 0x5f0;  // 1520 bytes for receive
    } else {
        bufferSize = nb_size(nb);  // Actual packet size for transmit
    }

    // Get data pointer from netbuf
    dataPtr = nb_map(nb);

    // Get physical address
    result = IOPhysicalFromVirtual(dataPtr, (void **)&physicalAddr);
    if (result == 0) {
        // Failed to get physical address
        return NO;
    }

    // Check if buffer is contiguous (within same page boundary)
    pageMask = ~(PAGE_SIZE - 1);  // 0xFFFFF000 for 4KB pages
    if (((unsigned int)dataPtr & pageMask) !=
        (((unsigned int)dataPtr + bufferSize - 1) & pageMask)) {
        IOLog("Ethernet(Gem): Network buffer not contiguous\n\r");
        return NO;
    }

    // Fill in descriptor based on direction
    if (isReceive) {
        // Receive descriptor format:
        // +0: length (2 bytes) with ownership bit 0x80 in high byte
        // +2: length low byte
        // +4: flags (4 bytes) - cleared
        // +8: physical address (4 bytes) - byte swapped

        // Write physical address at offset +8 (byte swapped to little-endian)
        *(unsigned int *)((int)desc + 8) =
            (physicalAddr << 24) | ((physicalAddr >> 8) & 0xFF00) |
            ((physicalAddr << 8) & 0xFF0000) | (physicalAddr >> 24);

        // Write length at offset +2 with ownership bit (0x80) set in high byte
        length = (unsigned short)bufferSize;
        *(unsigned short *)((int)desc + 2) = ((length >> 8) | (length << 8)) | 0x80;

        // Clear flags at offset +4
        *(unsigned int *)((int)desc + 4) = 0;

    } else {
        // Transmit descriptor format:
        // +0: length and flags (4 bytes) - includes 0xc0000000 flags
        // +4: special flags (4 bytes) - 0x01000000 every 64 packets
        // +8: physical address (4 bytes) - byte swapped

        // Write physical address at offset +8 (byte swapped to little-endian)
        *(unsigned int *)((int)desc + 8) =
            (physicalAddr << 24) | ((physicalAddr >> 8) & 0xFF00) |
            ((physicalAddr << 8) & 0xFF0000) | (physicalAddr >> 24);

        // Prepare length with flags (0xc0000000 for start/end of packet)
        flags = bufferSize | 0xc0000000;

        // Write length and flags at offset +0 (byte swapped)
        *(unsigned int *)desc =
            (flags << 24) | ((flags >> 8) & 0xFF00) |
            ((flags << 8) & 0xFF0000) | (flags >> 24);

        // Set special flag every 64th packet (for interrupt coalescing)
        if ((txCnt & 0x3f) == 0) {
            *(unsigned int *)((int)desc + 4) = 0x01000000;
        } else {
            *(unsigned int *)((int)desc + 4) = 0;
        }

        txCnt++;
    }

    return YES;
}

//
// Monitor link status
//
- (void)_monitorLinkStatus
{
    unsigned short currentStatus;
    unsigned char configReg;

    // Read current MIF status
    currentStatus = _ReadGemRegister((int)memBase, kGemRegMIFStatus2);

    // Check if link status bit (bit 2 = 0x04) has changed
    if (((currentStatus ^ linkStatus) & 0x04) != 0) {
        // Read current configuration register
        configReg = _ReadGemRegister((int)memBase, kGemRegConfigReg);

        if ((currentStatus & 0x04) == 0) {
            // Link is down
            IOLog("Ethernet(Gem): Link is down.\n\r");
            // Clear bit 0x20 (Full duplex bit)
            configReg &= 0xdf;
        } else {
            // Link is up
            IOLog("Ethernet(Gem): Link is up at 1Gb - Full Duplex\n\r");
            // Set bit 0x20 (Full duplex bit)
            configReg |= 0x20;
        }

        // Write back the modified configuration
        _WriteGemRegister((int)memBase, kGemRegConfigReg, configReg);
    }

    // Store current status for next comparison
    linkStatus = currentStatus;
}

//
// Dump registers for debugging
//
- (void)_dumpRegisters
{
    int i;
    unsigned int regValue;
    unsigned int regOffset;
    unsigned short regSize;
    char *formatStr;

    IOLog("\nEthernet(Gem): IO Address = %08x\n\r", (unsigned int)memBase);

    // Iterate through register table
    for (i = 0; gemRegisterTable[i].regName != NULL; i++) {
        regOffset = gemRegisterTable[i].regOffset;
        regSize = (unsigned short)(regOffset >> 16);

        // Read the register value
        regValue = _ReadGemRegister((int)memBase, regOffset);

        // Select format string based on register size
        switch (regSize) {
            case 1:
                formatStr = "Ethernet(Gem): %04x: %s = %02x\n\r";
                break;
            case 2:
                formatStr = "Ethernet(Gem): %04x: %s = %04x\n\r";
                break;
            case 4:
                formatStr = "Ethernet(Gem): %04x: %s = %08x\n\r";
                break;
            default:
                continue;
        }

        // Print the register
        IOLog(formatStr, regOffset & 0xffff, gemRegisterTable[i].regName, regValue);
    }
}

//
// Send packet to debugger
//
- (void)_packetToDebugger:(void *)pkt
{
    netbuf_t nb = (netbuf_t)pkt;
    void *data;
    unsigned int length;

    // Get the packet length
    length = nb_size(nb);
    debuggerPktLength = length;

    // Get the packet data pointer
    data = nb_map(nb);

    // Copy packet data to debugger buffer
    if (debuggerPktBuffer != NULL && data != NULL) {
        bcopy(data, debuggerPktBuffer, debuggerPktLength);
    }

    // Free the netbuf
    nb_free(nb);
}

@end
