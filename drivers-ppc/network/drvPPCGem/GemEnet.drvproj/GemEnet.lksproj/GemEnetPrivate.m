/* GemEnetPrivate.m - PowerPC Gem Ethernet Driver Private Methods */

#import "GemEnet.h"
#import <kernserv/prototypes.h>

// Gem register offsets (encoded with size in upper 16 bits)
// Format: (size << 16) | offset, where size: 1=byte, 2=word, 4=dword
#define kGemRegInterruptMask		0x40010		// Interrupt mask register
#define kGemRegInterruptStatus		0x40000		// Interrupt status register
#define kGemRegSoftwareReset		0x19050		// Software reset
#define kGemRegConfigReg		0x1603c		// Configuration register
#define kGemRegPCSMIIStatus		0x19054		// PCS/MII status
#define kGemRegMIFFrameControl		0x29008		// MIF frame control
#define kGemRegMIFConfig		0x29000		// MIF configuration
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

// External function declarations
extern unsigned int _ReadGemRegister(int base, unsigned int offset_and_size);
extern void _WriteGemRegister(int base, unsigned int offset_and_size, unsigned int value);
extern int IOPhysicalFromVirtual(void *virtualAddr, void **physicalAddr);

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
- (void)_initChip
{
    // TODO: Implement chip initialization
}

//
// Reset chip
//
- (void)_resetChip
{
    // TODO: Implement chip reset
}

//
// Start chip
//
- (void)_startChip
{
    // TODO: Implement chip start
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

        // Set up TX and RX DMA command pointers
        txDMACommands = dmaCommands;
        txDMACommandsSize = 0x80;  // 128 bytes
        rxDMACommands = (void *)((int)dmaCommands + 0x800);  // Offset by 2048 bytes
        rxDMACommandsSize = 0x80;  // 128 bytes
    }

    return YES;
}

//
// Initialize transmit ring
//
- (void)_initTxRing
{
    // TODO: Implement transmit ring initialization
}

//
// Initialize receive ring
//
- (void)_initRxRing
{
    // TODO: Implement receive ring initialization
}

//
// Enable adapter interrupts
//
- (void)_enableAdapterInterrupts
{
    // TODO: Implement enable interrupts
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
    // TODO: Implement transmit interrupt handling
}

//
// Handle receive interrupt
//
- (void)_receiveInterruptOccurred
{
    // TODO: Implement receive interrupt handling
}

//
// Transmit packet (internal)
//
- (void)_transmitPacket:(netbuf_t)packet
{
    // TODO: Implement transmit packet
}

//
// Send packet (internal)
//
- (void)_sendPacket:(void *)pkt length:(unsigned int)len
{
    // TODO: Implement send packet
}

//
// Send dummy packet
//
- (void)_sendDummyPacket
{
    // TODO: Implement send dummy packet
}

//
// Stop transmit DMA
//
- (void)_stopTransmitDMA
{
    // TODO: Implement stop transmit DMA
}

//
// Restart transmitter
//
- (void)_restartTransmitter
{
    // TODO: Implement restart transmitter
}

//
// Receive packet (internal)
//
- (void)_receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout
{
    // TODO: Implement receive packet
}

//
// Receive packets
//
- (void)_receivePackets:(BOOL)freeRun
{
    // TODO: Implement receive packets
}

//
// Stop receive DMA
//
- (void)_stopReceiveDMA
{
    // TODO: Implement stop receive DMA
}

//
// Restart receiver
//
- (void)_restartReceiver
{
    // TODO: Implement restart receiver
}

//
// Update Gem hash table mask
//
- (void)_updateGemHashTableMask
{
    // TODO: Implement update hash table mask
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
    // TODO: Implement remove from hash table mask
}

//
// Get station address
//
- (void)_getStationAddress:(enet_addr_t *)addr
{
    // TODO: Implement get station address
}

//
// Update descriptor from netbuf
//
- (void)_updateDescriptorFromNetBuf:(netbuf_t)nb Desc:(void *)desc ReceiveFlag:(BOOL)isReceive
{
    // TODO: Implement update descriptor from netbuf
}

//
// Monitor link status
//
- (void)_monitorLinkStatus
{
    // TODO: Implement monitor link status
}

//
// Dump registers for debugging
//
- (void)_dumpRegisters
{
    // TODO: Implement dump registers
}

//
// Send packet to debugger
//
- (void)_packetToDebugger:(void *)pkt
{
    // TODO: Implement packet to debugger
}

@end
