/* GemEnetPrivate.m - PowerPC Gem Ethernet Driver Private Methods */

#import "GemEnet.h"
#import <kernserv/prototypes.h>

// Gem registers, named as in the stock driver's register dump table.
// Format: (size << 16) | offset, where size: 1=byte, 2=word, 4=dword
#define kGemRegSEBState			0x10000
#define kGemRegConfig			0x20004
#define kGemRegInterruptStatus		0x4000c
#define kGemRegInterruptMask		0x40010
#define kGemRegInterruptAck		0x40014
#define kGemRegInterruptAltStatus	0x4001c
#define kGemRegPCIErrorStatus		0x11000
#define kGemRegPCIErrorMask		0x11004
#define kGemRegBIFConfig		0x11008
#define kGemRegBIFDiagnostic		0x4100c
#define kGemRegSoftwareReset		0x11010
#define kGemRegTxKick			0x22000
#define kGemRegTxConfig			0x42004
#define kGemRegTxDescBaseLo		0x42008
#define kGemRegTxDescBaseHi		0x4200c
#define kGemRegTxFIFOWritePtr		0x22014
#define kGemRegTxFIFOShadowWritePtr	0x22018
#define kGemRegTxFIFOReadPtr		0x2201c
#define kGemRegTxFIFOShadowReadPtr	0x22020
#define kGemRegTxFIFOPktCounter		0x22024
#define kGemRegTxStateMachine		0x42028
#define kGemRegTxDataPtrLo		0x42030
#define kGemRegTxDataPtrHi		0x42034
#define kGemRegTxCompletion		0x22100
#define kGemRegTxFIFOAddr		0x22104
#define kGemRegTxFIFOTag		0x12108
#define kGemRegTxFIFODataLo		0x4210c
#define kGemRegTxFIFODataHiTag1		0x42110
#define kGemRegTxFIFODataHiTag0		0x42114
#define kGemRegTxFIFOSize		0x22118
#define kGemRegRxConfig			0x44000
#define kGemRegRxDescBaseLo		0x44004
#define kGemRegRxDescBaseHi		0x44008
#define kGemRegRxFIFOWritePtr		0x2400c
#define kGemRegRxFIFOShadowWritePtr	0x24010
#define kGemRegRxFIFOReadPtr		0x24014
#define kGemRegRxFIFOPktCounter		0x24018
#define kGemRegRxStateMachine		0x4401c
#define kGemRegRxPauseThresholds	0x44020
#define kGemRegRxDataPtrLo		0x44024
#define kGemRegRxDataPtrHi		0x44028
#define kGemRegRxKick			0x24100
#define kGemRegRxCompletion		0x24104
#define kGemRegRxIntBlanking		0x44108
#define kGemRegRxFIFOAddr		0x2410c
#define kGemRegRxFIFOTag		0x14110
#define kGemRegRxDataLo			0x44114
#define kGemRegRxDataHiTag0		0x44118
#define kGemRegRxDataHiTag1		0x4411c
#define kGemRegRxFIFOSize		0x24120
#define kGemRegMacTxResetCmd		0x16000
#define kGemRegMacRxResetCmd		0x16004
#define kGemRegMacSendPauseCmd		0x46008
#define kGemRegMacTxStatus		0x26010
#define kGemRegMacRxStatus		0x26014
#define kGemRegMacControlStatus		0x46018
#define kGemRegMacTxMask		0x26020
#define kGemRegMacRxMask		0x26024
#define kGemRegMacControlMask		0x16028
#define kGemRegMacTxMacConfig		0x26030
#define kGemRegMacRxMacConfig		0x26034
#define kGemRegMacControlConfig		0x16038
#define kGemRegMacXIFConfig		0x1603c
#define kGemRegMacInterPktGap0		0x16040
#define kGemRegMacInterPktGap1		0x16044
#define kGemRegMacInterPktGap2		0x16048
#define kGemRegMacSlotTime		0x2604c
#define kGemRegMacMinFrameSize		0x26050
#define kGemRegMacMaxFrameSize		0x26054
#define kGemRegMacPASize		0x26058
#define kGemRegMacJamSize		0x1605c
#define kGemRegMacAttemptLimit		0x16060
#define kGemRegMacTypeControl		0x26064
#define kGemRegMacAddr			0x26080
#define kGemRegMacAddrFilter		0x260a4
#define kGemRegMacAddrFilterMask1	0x160b0
#define kGemRegMacAddrFilterMask0	0x260b4
#define kGemRegMacHashTable		0x260c0
#define kGemRegMacCollisions		0x26100
#define kGemRegMacSingleCollision	0x26104
#define kGemRegMacExcessCollisions	0x26108
#define kGemRegMacLateCollisions	0x2610c
#define kGemRegMacDeferTimer		0x26110
#define kGemRegMacPeakAttempts		0x26114
#define kGemRegMacRxFrameCounter	0x26118
#define kGemRegMacRxLengthErrors	0x2611c
#define kGemRegMacRxAlignErrors		0x26120
#define kGemRegMacRxFCSErrors		0x26124
#define kGemRegMacRxCodeErrors		0x26128
#define kGemRegMacRandomSeed		0x26130
#define kGemRegMacStateMachine		0x16134
#define kGemRegMIFCLock			0x16200
#define kGemRegMIFData			0x16204
#define kGemRegMIFOutputEnable		0x16208
#define kGemRegMIFFrame			0x4620c
#define kGemRegMIFConfig		0x26210
#define kGemRegMIFMask			0x26214
#define kGemRegMIFStatus		0x46218
#define kGemRegMIFStateMachine		0x1621c
#define kGemRegPCSControl		0x29000
#define kGemRegPCSStatus		0x29004
#define kGemRegPCSAdvert		0x29008
#define kGemRegPCSLPAbility		0x2900c
#define kGemRegPCSConfig		0x19010
#define kGemRegPCSStateMachine		0x49014
#define kGemRegPCSInterruptStatus	0x19018
#define kGemRegPCSDatapathMode		0x19050
#define kGemRegPCSSerdesControl		0x19054
#define kGemRegPCSSerdesOutputSelect	0x19058
#define kGemRegPCSSerdesState		0x1905c

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
    { kGemRegSEBState, "SEBState" },
    { kGemRegConfig, "Config" },
    { kGemRegInterruptStatus, "InterruptStatus" },
    { kGemRegInterruptMask, "InterruptMask" },
    { kGemRegInterruptAck, "InterruptAck" },
    { kGemRegInterruptAltStatus, "InterruptAltStatus" },
    { kGemRegPCIErrorStatus, "PCIErrorStatus" },
    { kGemRegPCIErrorMask, "PCIErrorMask" },
    { kGemRegBIFConfig, "BIFConfig" },
    { kGemRegBIFDiagnostic, "BIFDiagnostic" },
    { kGemRegSoftwareReset, "SoftwareReset" },
    { kGemRegTxKick, "TxKick" },
    { kGemRegTxConfig, "TxConfig" },
    { kGemRegTxDescBaseLo, "TxDescBaseLo" },
    { kGemRegTxDescBaseHi, "TxDescBaseHi" },
    { kGemRegTxFIFOWritePtr, "TxFIFOWritePtr" },
    { kGemRegTxFIFOShadowWritePtr, "TxFIFOShadowWritePtr" },
    { kGemRegTxFIFOReadPtr, "TxFIFOReadPtr" },
    { kGemRegTxFIFOShadowReadPtr, "TxFIFOShadowReadPtr" },
    { kGemRegTxFIFOPktCounter, "TxFIFOPktCounter" },
    { kGemRegTxStateMachine, "TxStateMachine" },
    { kGemRegTxDataPtrLo, "TxDataPtrLo" },
    { kGemRegTxDataPtrHi, "TxDataPtrHi" },
    { kGemRegTxCompletion, "TxCompletion" },
    { kGemRegTxFIFOAddr, "TxFIFOAddr" },
    { kGemRegTxFIFOTag, "TxFIFOTag" },
    { kGemRegTxFIFODataLo, "TxFIFODataLo" },
    { kGemRegTxFIFODataHiTag1, "TxFIFODataHiTag1" },
    { kGemRegTxFIFODataHiTag0, "TxFIFODataHiTag0" },
    { kGemRegTxFIFOSize, "TxFIFOSize" },
    { kGemRegRxConfig, "RxConfig" },
    { kGemRegRxDescBaseLo, "RxDescBaseLo" },
    { kGemRegRxDescBaseHi, "RxDescBaseHi" },
    { kGemRegRxFIFOWritePtr, "RxFIFOWritePtr" },
    { kGemRegRxFIFOShadowWritePtr, "RxFIFOShadowWritePtr" },
    { kGemRegRxFIFOReadPtr, "RxFIFOReadPtr" },
    { kGemRegRxFIFOPktCounter, "RxFIFOPktCounter" },
    { kGemRegRxStateMachine, "RxStateMachine" },
    { kGemRegRxPauseThresholds, "RxPauseThresholds" },
    { kGemRegRxDataPtrLo, "RxDataPtrLo" },
    { kGemRegRxDataPtrHi, "RxDataPtrHi" },
    { kGemRegRxKick, "RxKick" },
    { kGemRegRxCompletion, "RxCompletion" },
    { kGemRegRxIntBlanking, "RxIntBlanking" },
    { kGemRegRxFIFOAddr, "RxFIFOAddr" },
    { kGemRegRxFIFOTag, "RxFIFOTag" },
    { kGemRegRxDataLo, "RxDataLo" },
    { kGemRegRxDataHiTag0, "RxDataHiTag0" },
    { kGemRegRxDataHiTag1, "RxDataHiTag1" },
    { kGemRegRxFIFOSize, "RxFIFOSize" },
    { kGemRegMacTxResetCmd, "MacTxResetCmd" },
    { kGemRegMacRxResetCmd, "MacRxResetCmd" },
    { kGemRegMacSendPauseCmd, "MacSendPauseCmd" },
    { kGemRegMacTxStatus, "MacTxStatus" },
    { kGemRegMacRxStatus, "MacRxStatus" },
    { kGemRegMacControlStatus, "MacControlStatus" },
    { kGemRegMacTxMask, "MacTxMask" },
    { kGemRegMacRxMask, "MacRxMask" },
    { kGemRegMacControlMask, "MacControlMask" },
    { kGemRegMacTxMacConfig, "MacTxMacConfig" },
    { kGemRegMacRxMacConfig, "MacRxMacConfig" },
    { kGemRegMacControlConfig, "MacControlConfig" },
    { kGemRegMacXIFConfig, "MacXIFConfig" },
    { kGemRegMacInterPktGap0, "MacInterPktGap0" },
    { kGemRegMacInterPktGap1, "MacInterPktGap1" },
    { kGemRegMacInterPktGap2, "MacInterPktGap2" },
    { kGemRegMacSlotTime, "MacSlotTime" },
    { kGemRegMacMinFrameSize, "MacMinFrameSize" },
    { kGemRegMacMaxFrameSize, "MacMaxFrameSize" },
    { kGemRegMacPASize, "MacPASize" },
    { kGemRegMacJamSize, "MacJamSize" },
    { kGemRegMacAttemptLimit, "MacAttemptLimit" },
    { kGemRegMacTypeControl, "MacTypeControl" },
    { kGemRegMacAddr, "MacAddr" },
    { kGemRegMacAddrFilter, "MacAddrFilter" },
    { kGemRegMacAddrFilterMask1, "MacAddrFilterMask1" },
    { kGemRegMacAddrFilterMask0, "MacAddrFilterMask0" },
    { kGemRegMacHashTable, "MacHashTable" },
    { kGemRegMacCollisions, "MacCollisions" },
    { kGemRegMacSingleCollision, "MacSingleCollision" },
    { kGemRegMacExcessCollisions, "MacExcessCollisions" },
    { kGemRegMacLateCollisions, "MacLateCollisions" },
    { kGemRegMacDeferTimer, "MacDeferTimer" },
    { kGemRegMacPeakAttempts, "MacPeakAttempts" },
    { kGemRegMacRxFrameCounter, "MacRxFrameCounter" },
    { kGemRegMacRxLengthErrors, "MacRxLengthErrors" },
    { kGemRegMacRxAlignErrors, "MacRxAlignErrors" },
    { kGemRegMacRxFCSErrors, "MacRxFCSErrors" },
    { kGemRegMacRxCodeErrors, "MacRxCodeErrors" },
    { kGemRegMacRandomSeed, "MacRandomSeed" },
    { kGemRegMacStateMachine, "MacStateMachine" },
    { kGemRegMIFCLock, "MIFCLock" },
    { kGemRegMIFData, "MIFData" },
    { kGemRegMIFOutputEnable, "MIFOutputEnable" },
    { kGemRegMIFFrame, "MIFFrame" },
    { kGemRegMIFConfig, "MIFConfig" },
    { kGemRegMIFMask, "MIFMask" },
    { kGemRegMIFStatus, "MIFStatus" },
    { kGemRegMIFStateMachine, "MIFStateMachine" },
    { kGemRegPCSControl, "PCSControl" },
    { kGemRegPCSStatus, "PCSStatus" },
    { kGemRegPCSAdvert, "PCSAdvert" },
    { kGemRegPCSLPAbility, "PCSLPAbility" },
    { kGemRegPCSConfig, "PCSConfig" },
    { kGemRegPCSStateMachine, "PCSStateMachine" },
    { kGemRegPCSInterruptStatus, "PCSInterruptStatus" },
    { kGemRegPCSDatapathMode, "PCSDatapathMode" },
    { kGemRegPCSSerdesControl, "PCSSerdesControl" },
    { kGemRegPCSSerdesOutputSelect, "PCSSerdesOutputSelect" },
    { kGemRegPCSSerdesState, "PCSSerdesState" },
    { 0, NULL }  // End marker
};

#define ENET_CRCPOLY 0x04c11db7

//
// Accumulate 16 bits of an address into the running CRC
//
static unsigned int crc416(unsigned int current, unsigned short nxtval)
{
    register unsigned int counter;
    register int highCRCBitSet, lowDataBitSet;

    // Swap bytes
    nxtval = ((nxtval & 0x00FF) << 8) | (nxtval >> 8);

    // Compute bit-by-bit
    for (counter = 0; counter != 16; ++counter) {
        // is high CRC bit set?
        if ((current & 0x80000000) == 0)
            highCRCBitSet = 0;
        else
            highCRCBitSet = 1;

        current = current << 1;

        if ((nxtval & 0x0001) == 0)
            lowDataBitSet = 0;
        else
            lowDataBitSet = 1;

        nxtval = nxtval >> 1;

        // do the XOR
        if (highCRCBitSet ^ lowDataBitSet)
            current = current ^ ENET_CRCPOLY;
    }

    return current;
}

//
// Calculate MACE-style CRC for multicast hash
//
static unsigned int mace_crc(unsigned short *address)
{
    register unsigned int newcrc;

    newcrc = crc416(0xffffffff, *address);	// address bits 47 - 32
    newcrc = crc416(newcrc, address[1]);	// address bits 31 - 16
    newcrc = crc416(newcrc, address[2]);	// address bits 15 - 0

    return newcrc;
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

    // PCS datapath mode
    _WriteGemRegister((int)ioBaseEnet, kGemRegPCSDatapathMode, 2);

    // MAC XIF configuration
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacXIFConfig, 0x49);

    // PCS serdes control
    _WriteGemRegister((int)ioBaseEnet, kGemRegPCSSerdesControl, 3);

    // PCS advertisement
    _WriteGemRegister((int)ioBaseEnet, kGemRegPCSAdvert, 0xa0);

    // PCS control
    _WriteGemRegister((int)ioBaseEnet, kGemRegPCSControl, 0x1200);

    // PCS configuration
    _WriteGemRegister((int)ioBaseEnet, kGemRegPCSConfig, 1);

    // MAC send pause command
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacSendPauseCmd, 0x1bf0);

    // MAC control configuration
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacControlConfig, 3);

    // Disable all interrupts
    _WriteGemRegister((int)ioBaseEnet, kGemRegInterruptMask, 0xffffffff);

    // Mask MAC TX and RX status interrupts
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacTxMask, 0xffff);
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacRxMask, 0xffff);

    // Mask MAC control interrupts
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacControlMask, 0xff);

    // Global configuration
    _WriteGemRegister((int)ioBaseEnet, kGemRegConfig, 0x42);

    // Inter-packet gaps
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacInterPktGap0, 0);
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacInterPktGap1, 8);
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacInterPktGap2, 4);

    // Slot time
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacSlotTime, 0x40);

    // Minimum frame size
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacMinFrameSize, 0x40);

    // Maximum frame size
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacMaxFrameSize, 0x5ee);

    // Preamble length
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacPASize, 7);

    // JAM size
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacJamSize, 4);

    // Attempt limit
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacAttemptLimit, 0x10);

    // MAC control type (802.3x)
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacTypeControl, 0x8808);

    // Write MAC address (3 words, reversed order)
    for (i = 0; i < 3; i++) {
        _WriteGemRegister((int)ioBaseEnet, kGemRegMacAddr + (i * 4),
                         *(unsigned short *)((int)&myAddress + (2 - i) * 2));
    }

    // Clear alternate MAC address words 3-5 and address filter words 0-2
    for (i = 0; i < 3; i++) {
        _WriteGemRegister((int)ioBaseEnet, kGemRegMacAddr + ((i + 3) * 4), 0);
        _WriteGemRegister((int)ioBaseEnet, kGemRegMacAddrFilter + (i * 4), 0);
    }

    // MAC address words 6-8: 802.3x flow control address 01:80:C2:00:00:01
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacAddr + (6 * 4), 1);
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacAddr + (7 * 4), 0xc200);
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacAddr + (8 * 4), 0x180);

    // Address filter masks
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacAddrFilterMask1, 0);
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacAddrFilterMask0, 0);

    // Clear hash table (16 entries)
    for (i = 0; i < 16; i++) {
        _WriteGemRegister((int)ioBaseEnet, kGemRegMacHashTable + (i * 4), 0);
    }

    // Clear the MAC statistics counters. The stock driver's loop body is
    // empty, so it only writes 0 to the unused offset 0x612c once; we clear
    // every counter as intended.
    for (i = kGemRegMacCollisions; i <= kGemRegMacRxCodeErrors; i += 4) {
        _WriteGemRegister((int)ioBaseEnet, i, 0);
    }

    // Get MAC address and write random seed
    [self _getStationAddress:&myAddress];
    randomSeed = *(unsigned short *)((int)&myAddress + 4);
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacRandomSeed, randomSeed);

    // TX descriptor base addresses (use physical address for hardware)
    _WriteGemRegister((int)ioBaseEnet, kGemRegTxDescBaseLo, txDMACommandsPhys);
    _WriteGemRegister((int)ioBaseEnet, kGemRegTxDescBaseHi, 0);

    // Calculate TX ring size (log2 of ring entries)
    txRingSize = 3;  // Assuming 3 entries for now
    txShift = 0;
    for (i = 0; i < 13; i++) {
        if (txRingSize == 0) break;
        txShift++;
        txRingSize >>= 1;
    }

    // TX configuration
    _WriteGemRegister((int)ioBaseEnet, kGemRegTxConfig, (txShift << 1) | 0x1ffc00);

    // MAC TX configuration
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacTxMacConfig, 6);

    // RX descriptor base addresses (use physical address for hardware)
    _WriteGemRegister((int)ioBaseEnet, kGemRegRxDescBaseLo, rxDMACommandsPhys);
    _WriteGemRegister((int)ioBaseEnet, kGemRegRxDescBaseHi, 0);

    // RX kick
    _WriteGemRegister((int)ioBaseEnet, kGemRegRxKick, 0x7c);

    // Calculate RX ring size (log2 of ring entries)
    rxRingSize = 3;  // Assuming 3 entries for now
    rxShift = 0;
    for (i = 0; i < 13; i++) {
        if (rxRingSize == 0) break;
        rxShift++;
        rxRingSize >>= 1;
    }

    // RX configuration
    _WriteGemRegister((int)ioBaseEnet, kGemRegRxConfig, (rxShift << 1) | 0x1000000);

    // MAC RX configuration
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacRxMacConfig, 0);

    // RX pause thresholds
    rxFIFOSize = _ReadGemRegister((int)ioBaseEnet, kGemRegRxFIFOSize);
    _WriteGemRegister((int)ioBaseEnet, kGemRegRxPauseThresholds, ((rxFIFOSize - 0x60) & 0xffff) | 0x60000);

    // RX interrupt blanking
    bifConfig = _ReadGemRegister((int)ioBaseEnet, kGemRegBIFConfig);
    timeoutDivisor = (bifConfig & 8) ? 0xf : 0x1e;
    _WriteGemRegister((int)ioBaseEnet, kGemRegRxIntBlanking,
                     ((250000 / (timeoutDivisor << 11)) << 12) | 5);

    return YES;
}

//
// Reset chip
//
- (void)_resetChip
{
    unsigned int resetStatus;

    // Write 3 to software reset register
    _WriteGemRegister((int)ioBaseEnet, kGemRegSoftwareReset, 3);

    // Poll until reset completes (bits 0 and 1 clear)
    do {
        resetStatus = _ReadGemRegister((int)ioBaseEnet, kGemRegSoftwareReset);
    } while ((resetStatus & 3) != 0);
}

//
// Start chip
//
- (void)_startChip
{
    unsigned int regValue;

    // Enable TX DMA - set bit 0 of TX configuration register
    regValue = _ReadGemRegister((int)ioBaseEnet, kGemRegTxConfig);
    regValue = regValue | 1;
    _WriteGemRegister((int)ioBaseEnet, kGemRegTxConfig, regValue);

    // Delay 20 microseconds
    IODelay(20);

    // Enable RX DMA - set bit 0 of RX configuration register
    regValue = _ReadGemRegister((int)ioBaseEnet, kGemRegRxConfig);
    regValue = regValue | 1;
    _WriteGemRegister((int)ioBaseEnet, kGemRegRxConfig, regValue);

    // Delay 20 microseconds
    IODelay(20);

    // Enable MAC transmitter - set bit 0 of MAC TX config
    regValue = _ReadGemRegister((int)ioBaseEnet, kGemRegMacTxMacConfig);
    regValue = regValue | 1;
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacTxMacConfig, regValue);

    // Delay 20 microseconds
    IODelay(20);

    // Enable MAC receiver - set bit 0 of MAC RX config
    regValue = _ReadGemRegister((int)ioBaseEnet, kGemRegMacRxMacConfig);
    regValue = regValue | 1;
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacRxMacConfig, regValue);
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
        rxDMACommands = dmaCommands;
        rxMaxCommand = 0x80;  // 128 bytes
        txDMACommands = (void *)((int)dmaCommands + 0x800);  // Offset by 2048 bytes
        txMaxCommand = 0x80;  // 128 bytes

        // Calculate physical addresses for hardware
        IOPhysicalFromVirtual(rxDMACommands, (void **)&txDMACommandsPhys);
        IOPhysicalFromVirtual(txDMACommands, (void **)&rxDMACommandsPhys);
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
    bzero(txDMACommands, txMaxCommand << 4);

    // Initialize TX ring pointers
    txCommandHead = 0;
    txCommandTail = 0;

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
    result = IOPhysicalFromVirtual(txDMACommands, &physAddr);
    if (result == 0) {
        IOLog("Ethernet(Gem): Bad dma command buf - %08x\n\r", (unsigned int)txDMACommands);
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
    bzero(rxDMACommands, rxMaxCommand << 4);

    // Get physical address and verify it's valid
    result = IOPhysicalFromVirtual(rxDMACommands, &physAddr);
    if (result != 0) {
        IOLog("Ethernet(Gem): Bad dma command buf - %08x\n\r", (unsigned int)rxDMACommands);
        return NO;
    }

    // Allocate netbufs for each RX ring entry
    for (i = 0; i < rxMaxCommand; i++) {
        // Allocate netbuf if not already allocated
        if (rxNetbuf[i] == NULL) {
            nb = [self allocateNetbuf];
            if (nb == NULL) {
                IOLog("Ethernet(Gem): allocateNetbuf returned NULL in _initRxRing\n\r");
                return NO;
            }
            rxNetbuf[i] = nb;
        }

        // Update descriptor from netbuf
        updateResult = [self _updateDescriptorFromNetBuf:rxNetbuf[i]
                                                     Desc:(void *)((int)rxDMACommands + (i * 0x10))
                                             ReceiveFlag:YES];
        if (!updateResult) {
            IOLog("Ethernet(Gem): cant map Netbuf to physical memory in _initRxRing\n\r");
            return NO;
        }
    }

    // Initialize RX ring pointers
    rxCommandHead = 0;
    rxCommandTail = i - 4;  // Tail is size minus 4

    return YES;
}

//
// Enable adapter interrupts
//
- (void)_enableAdapterInterrupts
{
    unsigned int intMask;

    // Read current interrupt mask
    intMask = _ReadGemRegister((int)ioBaseEnet, kGemRegInterruptMask);

    // Clear bits to enable interrupts (0x7fee enables specific interrupts)
    // Writing 0 to a bit enables that interrupt
    intMask &= 0xffff7fee;

    // Write back the modified mask
    _WriteGemRegister((int)ioBaseEnet, kGemRegInterruptMask, intMask);
}

//
// Disable adapter interrupts
//
- (void)_disableAdapterInterrupts
{
    // Write all 1's to the interrupt mask register to disable all interrupts
    _WriteGemRegister((int)ioBaseEnet, kGemRegInterruptMask, 0xFFFFFFFF);
}

//
// Handle transmit interrupt
//
- (BOOL)_transmitInterruptOccurred
{
    // Free each netbuf the hardware has finished sending
    while (_ReadGemRegister((int)ioBaseEnet, kGemRegTxCompletion) != txCommandHead) {
        [networkInterface incrementOutputPackets];
        nb_free(txNetbuf[txCommandHead]);
        txNetbuf[txCommandHead] = NULL;

        txCommandHead++;
        if (txCommandHead >= txMaxCommand) {
            txCommandHead = 0;
        }
    }

    return YES;
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
    nextTail = txCommandTail + 1;
    if (nextTail >= txMaxCommand) {
        nextTail = 0;
    }

    // Check if ring is full
    if (nextTail == txCommandHead) {
        // Ring is full, can't transmit
        IOLog("Ethernet(Gem): TX ring full\n\r");
        nb_free(packet);
        return;
    }

    // Get descriptor address
    descriptorAddr = (void *)((int)txDMACommands + (txCommandTail * 0x10));

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

    // Keep the netbuf until the transmit completes
    txNetbuf[txCommandTail] = packet;

    // Update tail pointer
    txCommandTail = nextTail;

    // Kick the hardware to start transmission
    _WriteGemRegister((int)ioBaseEnet, kGemRegTxKick, txCommandTail);
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
    if (!resetAndEnabled) {
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
        if (txCommandHead == txCommandTail) {
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
    debuggerPkt = (void *)nb;

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
        if (txCommandHead == txCommandTail) {
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
    if (!resetAndEnabled) {
        return;
    }

    // Disable interrupts during polling
    [self disableAllInterrupts];

    // Set up debugger packet buffer
    debuggerPkt = pkt;
    debuggerPktSize = 0;

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
        if (debuggerPktSize != 0) {
            break;
        }

        // Continue polling if timeout not reached
    } while (elapsedMicroseconds < timeout);

    // Return the received length
    *len = debuggerPktSize;

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

    currentIndex = rxCommandHead;
    previousIndex = 0xFFFFFFFF;

    // Process all received packets in the ring
    while (1) {
        allocated = NO;
        isUnwanted = NO;
        hasError = NO;

        // Get descriptor address
        descriptorAddr = (void *)((int)rxDMACommands + (currentIndex * 0x10));

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
            [networkInterface incrementInputErrors];
            hasError = YES;
        }

        // Get the netbuf for this slot
        oldNetbuf = rxNetbuf[currentIndex];

        if (!hasError) {
            // Check if unwanted multicast (only if not promiscuous)
            if (!isPromiscuous && ((flags & 0x10000000) != 0)) {
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
                    [networkInterface incrementInputErrors];
                    hasError = YES;
                } else {
                    // Store new netbuf in slot
                    rxNetbuf[currentIndex] = newNetbuf;
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
        if (currentIndex >= rxMaxCommand) {
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
                [networkInterface handleInputPacket:oldNetbuf extra:0];
            }
        }
    }

    // Update ring pointers if we processed any packets
    if (previousIndex != 0xFFFFFFFF) {
        rxCommandTail = previousIndex;
        rxCommandHead = currentIndex;
    }

    // Update hardware RX kick register (aligned to 4-byte boundary)
    _WriteGemRegister((int)ioBaseEnet, kGemRegRxKick, rxCommandTail & 0xFFFFFFFC);

    // Read and clear error counters
    frameErrors = _ReadGemRegister((int)ioBaseEnet, kGemRegMacRxLengthErrors);
    lengthErrors = _ReadGemRegister((int)ioBaseEnet, kGemRegMacRxFCSErrors);
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacRxLengthErrors, 0);
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacRxFCSErrors, 0);

    // Increment error counter
    [networkInterface incrementInputErrorsBy:(frameErrors + lengthErrors)];

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

    // Read current MAC RX configuration
    rxKickValue = _ReadGemRegister((int)ioBaseEnet, kGemRegMacRxMacConfig);

    // Disable the receiver and hash filter (AND with 0xffde)
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacRxMacConfig, rxKickValue & 0xffde);

    // Wait for RX to stop (wait until bits 0x21 are clear)
    do {
        statusValue = _ReadGemRegister((int)ioBaseEnet, kGemRegMacRxMacConfig);
    } while ((statusValue & 0x21) != 0);

    // Write all 16 hash table entries to hardware
    // Note: hashTableMask array is written in reverse order to hardware registers
    for (i = 0; i < 0x10; i++) {
        _WriteGemRegister((int)ioBaseEnet,
                         kGemRegMacHashTable + (i * 4),
                         hashTableMask[0xf - i]);
    }

    // Re-enable with the hash filter bit 0x20 set
    _WriteGemRegister((int)ioBaseEnet, kGemRegMacRxMacConfig, rxKickValue | 0x20);
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
    crc = mace_crc((unsigned short *)addr);

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
    crc = mace_crc((unsigned short *)addr);

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

    // Read current PCS status
    currentStatus = _ReadGemRegister((int)ioBaseEnet, kGemRegPCSStatus);

    // Check if link status bit (bit 2 = 0x04) has changed
    if (((currentStatus ^ phyStatusPrev) & 0x04) != 0) {
        // Read current MAC XIF configuration
        configReg = _ReadGemRegister((int)ioBaseEnet, kGemRegMacXIFConfig);

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

        // Write back the modified XIF configuration
        _WriteGemRegister((int)ioBaseEnet, kGemRegMacXIFConfig, configReg);
    }

    // Store current status for next comparison
    phyStatusPrev = currentStatus;
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

    IOLog("\nEthernet(Gem): IO Address = %08x\n\r", (unsigned int)ioBaseEnet);

    // Iterate through register table
    for (i = 0; gemRegisterTable[i].regName != NULL; i++) {
        regOffset = gemRegisterTable[i].regOffset;
        regSize = (unsigned short)(regOffset >> 16);

        // Read the register value
        regValue = _ReadGemRegister((int)ioBaseEnet, regOffset);

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
    debuggerPktSize = length;

    // Get the packet data pointer
    data = nb_map(nb);

    // Copy packet data to debugger buffer
    if (debuggerPkt != NULL && data != NULL) {
        bcopy(data, debuggerPkt, debuggerPktSize);
    }

    // Free the netbuf
    nb_free(nb);
}

@end
