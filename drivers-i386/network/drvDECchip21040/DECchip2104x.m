/*
 * DECchip2104x.m
 * Base class implementation for DECchip 21040/21041 Network Driver
 */

#import "DECchip2104x.h"
#import "DECchip2104xKernelServerInstance.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <machkit/NXLock.h>
#import <net/etherdefs.h>
#import <net/netbuf.h>
#import <string.h>

/* CSR Register Definitions */
#define CSR0_BUS_MODE           0
#define CSR1_TX_POLL            1
#define CSR2_RX_POLL            2
#define CSR3_RX_LIST_BASE       3
#define CSR4_TX_LIST_BASE       4
#define CSR5_STATUS             5
#define CSR6_OPMODE             6
#define CSR7_INTERRUPT_ENABLE   7
#define CSR8_MISSED_FRAMES      8
#define CSR9_ENET_ROM           9
#define CSR10_RESERVED          10
#define CSR11_GP_TIMER          11
#define CSR12_SIA_STATUS        12
#define CSR13_SIA_CONNECTIVITY  13
#define CSR14_SIA_TX_RX         14
#define CSR15_SIA_GENERAL       15

/* CSR0 - Bus Mode Register */
#define CSR0_SOFTWARE_RESET     0x00000001
#define CSR0_BAR                0x00000002
#define CSR0_BLE                0x00000080
#define CSR0_PBL_MASK           0x00003F00
#define CSR0_CAL_MASK           0x0000C000
#define CSR0_TAP_MASK           0x000E0000

/* CSR5 - Status Register */
#define CSR5_TI                 0x00000001  /* Transmit Interrupt */
#define CSR5_TPS                0x00000002  /* Transmit Process Stopped */
#define CSR5_TU                 0x00000004  /* Transmit Buffer Unavailable */
#define CSR5_TJT                0x00000008  /* Transmit Jabber Timeout */
#define CSR5_UNF                0x00000020  /* Transmit Underflow */
#define CSR5_RI                 0x00000040  /* Receive Interrupt */
#define CSR5_RU                 0x00000080  /* Receive Buffer Unavailable */
#define CSR5_RPS                0x00000100  /* Receive Process Stopped */
#define CSR5_RWT                0x00000200  /* Receive Watchdog Timeout */
#define CSR5_ETI                0x00000400  /* Early Transmit Interrupt */
#define CSR5_GTE                0x00000800  /* General Purpose Timer Expired */
#define CSR5_FBE                0x00002000  /* Fatal Bus Error */
#define CSR5_ERI                0x00004000  /* Early Receive Interrupt */
#define CSR5_AIS                0x00008000  /* Abnormal Interrupt Summary */
#define CSR5_NIS                0x00010000  /* Normal Interrupt Summary */
#define CSR5_RS_MASK            0x000E0000  /* Receive Process State */
#define CSR5_TS_MASK            0x00700000  /* Transmit Process State */
#define CSR5_EB_MASK            0x03800000  /* Error Bits */

/* CSR6 - Operation Mode Register */
#define CSR6_HP                 0x00000001  /* Hash/Perfect Filter Mode */
#define CSR6_SR                 0x00000002  /* Start/Stop Receive */
#define CSR6_HO                 0x00000004  /* Hash Only Filtering Mode */
#define CSR6_PB                 0x00000008  /* Pass Bad Frames */
#define CSR6_IF                 0x00000010  /* Inverse Filtering */
#define CSR6_SB                 0x00000020  /* Start/Stop Backoff Counter */
#define CSR6_PR                 0x00000040  /* Promiscuous Mode */
#define CSR6_PM                 0x00000080  /* Pass All Multicast */
#define CSR6_FKD                0x00000100  /* Flaky Oscillator Disable */
#define CSR6_FD                 0x00000200  /* Full Duplex Mode */
#define CSR6_OM_MASK            0x00000C00  /* Operating Mode */
#define CSR6_FC                 0x00001000  /* Force Collision */
#define CSR6_ST                 0x00002000  /* Start/Stop Transmit */
#define CSR6_TR_MASK            0x0000C000  /* Threshold Control Bits */
#define CSR6_CA                 0x00020000  /* Capture Effect Enable */
#define CSR6_PS                 0x00040000  /* Port Select */
#define CSR6_HBD                0x00080000  /* Heartbeat Disable */
#define CSR6_PCS                0x00800000  /* PCS Function */
#define CSR6_SCR                0x01000000  /* Scrambler Mode */

/* CSR7 - Interrupt Enable Register */
#define CSR7_TI                 0x00000001
#define CSR7_TS                 0x00000002
#define CSR7_TU                 0x00000004
#define CSR7_TJ                 0x00000008
#define CSR7_UN                 0x00000020
#define CSR7_RI                 0x00000040
#define CSR7_RU                 0x00000080
#define CSR7_RS                 0x00000100
#define CSR7_RW                 0x00000200
#define CSR7_ET                 0x00000400
#define CSR7_GT                 0x00000800
#define CSR7_FB                 0x00002000
#define CSR7_ER                 0x00004000
#define CSR7_AI                 0x00008000
#define CSR7_NI                 0x00010000

/* Descriptor status bits */
#define RDES0_OWN               0x80000000
#define RDES0_FF                0x40000000
#define RDES0_FL_MASK           0x3FFF0000
#define RDES0_ES                0x00008000
#define RDES0_LE                0x00004000
#define RDES0_DT_MASK           0x00003000
#define RDES0_RF                0x00000800
#define RDES0_MF                0x00000400
#define RDES0_FS                0x00000200
#define RDES0_LS                0x00000100
#define RDES0_TL                0x00000080
#define RDES0_CS                0x00000040
#define RDES0_FT                0x00000020
#define RDES0_RE                0x00000008
#define RDES0_DB                0x00000004
#define RDES0_CE                0x00000002
#define RDES0_OF                0x00000001

#define RDES1_RER               0x02000000
#define RDES1_RCH               0x01000000
#define RDES1_RBS2_MASK         0x003FF800
#define RDES1_RBS1_MASK         0x000007FF

#define TDES0_OWN               0x80000000
#define TDES0_ES                0x00008000
#define TDES0_TO                0x00004000
#define TDES0_LO                0x00000800
#define TDES0_NC                0x00000400
#define TDES0_LC                0x00000200
#define TDES0_EC                0x00000100
#define TDES0_HF                0x00000080
#define TDES0_CC_MASK           0x00000078
#define TDES0_LF                0x00000004
#define TDES0_UF                0x00000002
#define TDES0_DE                0x00000001

#define TDES1_IC                0x80000000
#define TDES1_LS                0x40000000
#define TDES1_FS                0x20000000
#define TDES1_FT1               0x10000000
#define TDES1_SET               0x08000000
#define TDES1_AC                0x04000000
#define TDES1_TER               0x02000000
#define TDES1_TCH               0x01000000
#define TDES1_DPD               0x00800000
#define TDES1_FT0               0x00400000
#define TDES1_TBS2_MASK         0x003FF800
#define TDES1_TBS1_MASK         0x000007FF

/* Ring sizes */
#define RX_RING_SIZE            32
#define TX_RING_SIZE            16

/* Buffer sizes */
#define RX_BUFFER_SIZE          2048
#define TX_BUFFER_SIZE          2048
#define SETUP_FRAME_SIZE        192

/* Media types */
#define MEDIA_10BASET           0
#define MEDIA_10BASE2           1
#define MEDIA_10BASE5           2

/* Descriptor structure */
typedef struct {
    volatile unsigned int status;
    volatile unsigned int control;
    volatile unsigned int buffer1;
    volatile unsigned int buffer2;
} Descriptor;

@implementation DECchip2104x

/*
 * Class method: probe
 * Checks if this driver can handle the specified device
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    unsigned int vendor, device;

    if (![deviceDescription isKindOf:[IOPCIDeviceDescription class]]) {
        return NO;
    }

    vendor = [(IOPCIDeviceDescription *)deviceDescription getVendor];
    device = [(IOPCIDeviceDescription *)deviceDescription getDevice];

    /* Check for DEC vendor ID */
    if (vendor != 0x1011) {
        return NO;
    }

    /* Check for 21040 or 21041 */
    if (device == 0x0002 || device == 0x0014) {
        return YES;
    }

    return NO;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IOPCIDeviceDescription *pciDesc;
    IORange *memRange;

    [super initFromDeviceDescription:deviceDescription];

    if (![deviceDescription isKindOf:[IOPCIDeviceDescription class]]) {
        [self free];
        return nil;
    }

    pciDesc = (IOPCIDeviceDescription *)deviceDescription;
    _deviceDescription = pciDesc;

    /* Get PCI device information */
    _pciVendor = [pciDesc getVendor];
    _pciDevice = [pciDesc getDevice];
    _pciRevision = [pciDesc getRevision];

    /* Identify chip type */
    _chipType = [self identifyChip];
    if (_chipType == CHIP_TYPE_UNKNOWN) {
        IOLog("%s: Unknown chip type\n", [self name]);
        [self free];
        return nil;
    }

    /* Get memory mapped I/O base */
    memRange = [pciDesc memoryRangeList];
    if (!memRange) {
        IOLog("%s: No memory range found\n", [self name]);
        [self free];
        return nil;
    }

    _memBase = (void *)memRange->start;
    _ioBase = (unsigned int)_memBase;

    /* Get IRQ level */
    _irqLevel = [pciDesc interrupt];

    /* Initialize state */
    _isInitialized = NO;
    _isEnabled = NO;
    _linkUp = NO;
    _fullDuplex = NO;
    _mediaType = MEDIA_10BASET;
    _multicastCount = 0;
    _promiscuousMode = NO;

    /* Ring sizes */
    _rxRingSize = RX_RING_SIZE;
    _txRingSize = TX_RING_SIZE;

    /* Initialize statistics */
    [self resetStats];

    /* Perform private initialization */
    if (![self _initFromDeviceDescription:deviceDescription]) {
        [self free];
        return nil;
    }

    /* Create kernel server instance */
    _kernelServerInstance = [[DECchip2104xKernelServerInstance alloc] init];
    if (!_kernelServerInstance) {
        IOLog("%s: Failed to create kernel server instance\n", [self name]);
        [self free];
        return nil;
    }

    IOLog("%s: %s initialized at 0x%x IRQ %d\n",
          [self name], [self chipName], _ioBase, _irqLevel);

    return self;
}

/*
 * Free resources
 */
- free
{
    if (_isEnabled) {
        [self resetAndEnable:NO];
    }

    [self _freeMemory];

    if (_kernelServerInstance) {
        [_kernelServerInstance free];
        _kernelServerInstance = nil;
    }

    return [super free];
}

/*
 * Reset and enable/disable the hardware
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    if (enable) {
        /* Reset chip */
        [self _resetChip];

        /* Allocate memory */
        if (![self _allocMemory]) {
            IOLog("%s: Failed to allocate memory\n", [self name]);
            return NO;
        }

        /* Initialize chip */
        if (![self _initChip]) {
            IOLog("%s: Failed to initialize chip\n", [self name]);
            [self _freeMemory];
            return NO;
        }

        /* Enable interrupts */
        [self enableAllInterrupts];

        /* Start receive and transmit */
        [self _startReceive];
        [self _startTransmit];

        _isEnabled = YES;
        _isInitialized = YES;
    } else {
        /* Disable interrupts */
        [self disableAllInterrupts];

        /* Stop receive and transmit */
        [self stopReceive];
        [self stopTransmit];

        /* Reset chip */
        [self _resetChip];

        _isEnabled = NO;
    }

    return YES;
}

/*
 * Enable all interrupts
 */
- (BOOL)enableAllInterrupts
{
    unsigned int mask;

    /* Enable normal and abnormal interrupts */
    mask = CSR7_TI | CSR7_RI | CSR7_TU | CSR7_RU |
           CSR7_UN | CSR7_FB | CSR7_AI | CSR7_NI;

    [self writeCSR:CSR7_INTERRUPT_ENABLE value:mask];

    return YES;
}

/*
 * Disable all interrupts
 */
- (BOOL)disableAllInterrupts
{
    [self writeCSR:CSR7_INTERRUPT_ENABLE value:0];
    return YES;
}

/*
 * Transmit a packet
 */
- (void)transmitPacket:(void *)pkt length:(unsigned int)len
{
    [self _sendPacket_length:pkt length:len];
}

/*
 * Receive a packet
 */
- (void)receivePacket
{
    [self _receiveInterruptOccurred];
}

/*
 * Get transmit queue size
 */
- (unsigned int)transmitQueueSize
{
    return _txRingSize;
}

/*
 * Get receive queue size
 */
- (unsigned int)receiveQueueSize
{
    return _rxRingSize;
}

/*
 * Interrupt occurred
 */
- (void)interruptOccurred
{
    unsigned int status;

    /* Read status register */
    status = [self readCSR:CSR5_STATUS];

    /* Acknowledge interrupts */
    [self writeCSR:CSR5_STATUS value:status];

    /* Handle receive interrupt */
    if (status & CSR5_RI) {
        [self _receiveInterruptOccurred];
    }

    /* Handle transmit interrupt */
    if (status & CSR5_TI) {
        [self _transmitInterruptOccurred];
    }

    /* Handle error conditions */
    if (status & CSR5_AIS) {
        if (status & CSR5_RU) {
            _rxErrors++;
        }
        if (status & CSR5_TU) {
            _txErrors++;
        }
        if (status & CSR5_UNF) {
            _txErrors++;
        }
        if (status & CSR5_FBE) {
            IOLog("%s: Fatal bus error\n", [self name]);
        }
    }
}

/*
 * Timeout occurred
 */
- (void)timeoutOccurred
{
    /* Update statistics */
    [self updateStats];
}

/*
 * Get hardware address
 */
- (BOOL)getHardwareAddress:(enet_addr_t *)addr
{
    if (!addr) {
        return NO;
    }

    bcopy(_stationAddress, addr->ea_byte, 6);
    return YES;
}

/*
 * Set station address
 */
- (void)setStationAddress:(enet_addr_t *)addr
{
    if (!addr) {
        return;
    }

    bcopy(addr->ea_byte, _stationAddress, 6);

    /* Reload setup filter */
    [self _loadSetupFilter];
}

/*
 * Get power state
 */
- (IOReturn)getPowerState
{
    return [self _getPowerState];
}

/*
 * Set power state
 */
- (IOReturn)setPowerState:(unsigned int)state
{
    return [self _setPowerState:state];
}

/*
 * Reset statistics
 */
- (void)resetStats
{
    [self _resetStats];
}

/*
 * Update statistics
 */
- (void)updateStats
{
    unsigned int missed;

    /* Read missed frames counter */
    missed = [self readCSR:CSR8_MISSED_FRAMES];
    _missedFrames += missed & 0xFFFF;
}

/*
 * Get statistics
 */
- (void)getStatistics
{
    [self _getStatistics];
}

/*
 * Allocate memory (public wrapper)
 */
- (BOOL)allocateMemory
{
    return [self _allocMemory];
}

/*
 * Free memory (public wrapper)
 */
- (void)freeMemory
{
    [self _freeMemory];
}

/*
 * Initialize chip (public wrapper)
 */
- (BOOL)initChip
{
    return [self _initChip];
}

/*
 * Reset chip (public wrapper)
 */
- (void)resetChip
{
    [self _resetChip];
}

/*
 * Initialize descriptors
 */
- (BOOL)initDescriptors
{
    return [self _initDescriptors];
}

/*
 * Free descriptors
 */
- (void)freeDescriptors
{
    /* Descriptors are freed as part of _freeMemory */
}

/*
 * Setup RX descriptor
 */
- (void)setupRxDescriptor:(int)index
{
    [self _setupRxDescriptor:index];
}

/*
 * Setup TX descriptor
 */
- (void)setupTxDescriptor:(int)index
{
    [self _setupTxDescriptor:index];
}

/*
 * Start transmit
 */
- (void)startTransmit
{
    [self _startTransmit];
}

/*
 * Stop transmit
 */
- (void)stopTransmit
{
    unsigned int opmode;

    opmode = [self readCSR:CSR6_OPMODE];
    opmode &= ~CSR6_ST;
    [self writeCSR:CSR6_OPMODE value:opmode];
}

/*
 * Start receive
 */
- (void)startReceive
{
    [self _startReceive];
}

/*
 * Stop receive
 */
- (void)stopReceive
{
    unsigned int opmode;

    opmode = [self readCSR:CSR6_OPMODE];
    opmode &= ~CSR6_SR;
    [self writeCSR:CSR6_OPMODE value:opmode];
}

/*
 * Load setup filter
 */
- (void)loadSetupFilter
{
    [self _loadSetupFilter];
}

/*
 * Send setup frame
 */
- (void)sendSetupFrame
{
    /* Setup frame is sent as part of _loadSetupFilter */
    [self _loadSetupFilter];
}

/*
 * Add multicast address
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    if (_multicastCount < 16) {
        _multicastCount++;
        [self _loadSetupFilter];
    }
}

/*
 * Remove multicast address
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    if (_multicastCount > 0) {
        _multicastCount--;
        [self _loadSetupFilter];
    }
}

/*
 * Set promiscuous mode
 */
- (void)setPromiscuousMode:(BOOL)enable
{
    unsigned int opmode;

    _promiscuousMode = enable;

    opmode = [self readCSR:CSR6_OPMODE];
    if (enable) {
        opmode |= CSR6_PR;
    } else {
        opmode &= ~CSR6_PR;
    }
    [self writeCSR:CSR6_OPMODE value:opmode];
}

/*
 * Read CSR register
 */
- (unsigned int)readCSR:(int)csr
{
    volatile unsigned int *base = (volatile unsigned int *)_memBase;
    return base[csr];
}

/*
 * Write CSR register
 */
- (void)writeCSR:(int)csr value:(unsigned int)value
{
    volatile unsigned int *base = (volatile unsigned int *)_memBase;
    base[csr] = value;
}

/*
 * Identify chip type
 */
- (DECchip2104xType)identifyChip
{
    if (_pciDevice == 0x0002) {
        return CHIP_TYPE_21040;
    } else if (_pciDevice == 0x0014) {
        return CHIP_TYPE_21041;
    }
    return CHIP_TYPE_UNKNOWN;
}

/*
 * Get chip name
 */
- (const char *)chipName
{
    switch (_chipType) {
        case CHIP_TYPE_21040:
            return "DECchip 21040";
        case CHIP_TYPE_21041:
            return "DECchip 21041";
        default:
            return "Unknown";
    }
}

/*
 * Get kernel server instance
 */
- (DECchip2104xKernelServerInstance *)kernelServerInstance
{
    return _kernelServerInstance;
}

@end

/*
 * Private category implementation
 */
@implementation DECchip2104x(Private)

/*
 * Private: Allocate memory for descriptors and buffers
 */
- (BOOL)_allocMemory
{
    unsigned int totalSize;
    unsigned int rxDescSize, txDescSize;
    unsigned int rxBufSize, txBufSize;

    /* Calculate sizes */
    rxDescSize = _rxRingSize * sizeof(Descriptor);
    txDescSize = _txRingSize * sizeof(Descriptor);
    rxBufSize = _rxRingSize * RX_BUFFER_SIZE;
    txBufSize = _txRingSize * TX_BUFFER_SIZE;

    totalSize = rxDescSize + txDescSize + rxBufSize + txBufSize + SETUP_FRAME_SIZE;

    /* Allocate memory using kernel malloc */
    _rxDescriptors = IOMalloc(totalSize);
    if (!_rxDescriptors) {
        return NO;
    }

    bzero(_rxDescriptors, totalSize);

    /* Set up pointers */
    _txDescriptors = (void *)((unsigned int)_rxDescriptors + rxDescSize);
    _receiveBuffers = (void *)((unsigned int)_txDescriptors + txDescSize);
    _transmitBuffers = (void *)((unsigned int)_receiveBuffers + rxBufSize);
    _setupFrame = (void *)((unsigned int)_transmitBuffers + txBufSize);

    /* Initialize indices */
    _rxHead = 0;
    _rxTail = 0;
    _txHead = 0;
    _txTail = 0;

    /* Initialize descriptors */
    return [self _initDescriptors];
}

/*
 * Private: Free memory
 */
- (void)_freeMemory
{
    unsigned int totalSize;
    unsigned int rxDescSize, txDescSize;
    unsigned int rxBufSize, txBufSize;

    if (_rxDescriptors) {
        rxDescSize = _rxRingSize * sizeof(Descriptor);
        txDescSize = _txRingSize * sizeof(Descriptor);
        rxBufSize = _rxRingSize * RX_BUFFER_SIZE;
        txBufSize = _txRingSize * TX_BUFFER_SIZE;

        totalSize = rxDescSize + txDescSize + rxBufSize + txBufSize + SETUP_FRAME_SIZE;

        IOFree(_rxDescriptors, totalSize);
        _rxDescriptors = NULL;
        _txDescriptors = NULL;
        _receiveBuffers = NULL;
        _transmitBuffers = NULL;
        _setupFrame = NULL;
    }
}

/*
 * Private: Initialize from device description
 */
- (BOOL)_initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    /* Read station address from SROM/EEPROM */
    unsigned int i;
    unsigned int rom;

    for (i = 0; i < 6; i += 2) {
        rom = [self readCSR:CSR9_ENET_ROM];
        IODelay(10000); /* 10ms delay */
        rom = [self readCSR:CSR9_ENET_ROM];
        _stationAddress[i] = rom & 0xFF;
        _stationAddress[i + 1] = (rom >> 8) & 0xFF;
    }

    return YES;
}

/*
 * Private: Reset chip
 */
- (void)_resetChip
{
    int timeout;

    /* Write software reset bit */
    [self writeCSR:CSR0_BUS_MODE value:CSR0_SOFTWARE_RESET];

    /* Wait for reset to complete */
    for (timeout = 0; timeout < 1000; timeout++) {
        IODelay(10);
        if (!([self readCSR:CSR0_BUS_MODE] & CSR0_SOFTWARE_RESET)) {
            break;
        }
    }

    if (timeout >= 1000) {
        IOLog("%s: Reset timeout\n", [self name]);
    }
}

/*
 * Private: Initialize chip
 */
- (BOOL)_initChip
{
    unsigned int busMode;

    /* Configure bus mode */
    busMode = (32 << 8);  /* PBL = 32 */
    busMode |= (3 << 14); /* CAL = 3 (16 longwords) */
    [self writeCSR:CSR0_BUS_MODE value:busMode];

    /* Set descriptor list base addresses */
    [self writeCSR:CSR3_RX_LIST_BASE value:(unsigned int)_rxDescriptors];
    [self writeCSR:CSR4_TX_LIST_BASE value:(unsigned int)_txDescriptors];

    /* Configure operation mode */
    [self _setInterface];

    /* Load setup filter */
    [self _loadSetupFilter];

    return YES;
}

/*
 * Private: Select interface
 */
- (void)_selectInterface:(int)interface
{
    _mediaType = interface;
    [self _setInterface];
}

/*
 * Private: Set interface based on media type
 */
- (void)_setInterface
{
    /* Configure SIA registers based on media type */
    switch (_mediaType) {
        case MEDIA_10BASET:
            /* 10BaseT configuration */
            [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000001];
            [self writeCSR:CSR14_SIA_TX_RX value:0x0000007F];
            [self writeCSR:CSR15_SIA_GENERAL value:0x00000008];
            break;

        case MEDIA_10BASE2:
            /* 10Base2 (BNC) configuration */
            [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000009];
            [self writeCSR:CSR14_SIA_TX_RX value:0x00000705];
            [self writeCSR:CSR15_SIA_GENERAL value:0x00000006];
            break;

        case MEDIA_10BASE5:
            /* 10Base5 (AUI) configuration */
            [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000009];
            [self writeCSR:CSR14_SIA_TX_RX value:0x00000705];
            [self writeCSR:CSR15_SIA_GENERAL value:0x00000006];
            break;
    }

    /* Set operation mode */
    unsigned int opmode = CSR6_HBD;  /* Heartbeat disable */
    if (_fullDuplex) {
        opmode |= CSR6_FD;
    }
    [self writeCSR:CSR6_OPMODE value:opmode];
}

/*
 * Private: Start transmit
 */
- (void)_startTransmit
{
    unsigned int opmode;

    opmode = [self readCSR:CSR6_OPMODE];
    opmode |= CSR6_ST;
    [self writeCSR:CSR6_OPMODE value:opmode];
}

/*
 * Private: Start receive
 */
- (void)_startReceive
{
    unsigned int opmode;

    opmode = [self readCSR:CSR6_OPMODE];
    opmode |= CSR6_SR;
    [self writeCSR:CSR6_OPMODE value:opmode];
}

/*
 * Private: Transmit interrupt occurred
 */
- (void)_transmitInterruptOccurred
{
    Descriptor *desc;
    unsigned int status;

    while (_txTail != _txHead) {
        desc = (Descriptor *)_txDescriptors + _txTail;
        status = desc->status;

        /* Check if still owned by chip */
        if (status & TDES0_OWN) {
            break;
        }

        /* Update statistics */
        if (status & TDES0_ES) {
            _txErrors++;
        } else {
            _txPackets++;
        }

        /* Get collision count */
        _collisions += (status & TDES0_CC_MASK) >> 3;

        /* Move to next descriptor */
        _txTail = (_txTail + 1) % _txRingSize;
    }
}

/*
 * Private: Receive interrupt occurred
 */
- (void)_receiveInterruptOccurred
{
    Descriptor *desc;
    unsigned int status, length;
    void *buffer;

    while (1) {
        desc = (Descriptor *)_rxDescriptors + _rxHead;
        status = desc->status;

        /* Check if still owned by chip */
        if (status & RDES0_OWN) {
            break;
        }

        /* Check for errors */
        if (status & RDES0_ES) {
            _rxErrors++;
        } else {
            /* Get frame length */
            length = (status & RDES0_FL_MASK) >> 16;
            length -= 4; /* Remove CRC */

            /* Get buffer pointer */
            buffer = (void *)((unsigned int)_receiveBuffers + (_rxHead * RX_BUFFER_SIZE));

            /* Pass packet up to network stack */
            [self _receivePacket_length:buffer];

            _rxPackets++;
        }

        /* Reset descriptor for reuse */
        desc->status = RDES0_OWN;

        /* Move to next descriptor */
        _rxHead = (_rxHead + 1) % _rxRingSize;
    }

    /* Kick receive poll demand */
    [self writeCSR:CSR2_RX_POLL value:1];
}

/*
 * Private: Send packet
 */
- (void)_sendPacket_length:(void *)packet length:(unsigned int)len
{
    Descriptor *desc;
    void *buffer;

    desc = (Descriptor *)_txDescriptors + _txHead;

    /* Wait if descriptor still owned by chip */
    if (desc->status & TDES0_OWN) {
        return;
    }

    /* Copy packet to transmit buffer */
    buffer = (void *)((unsigned int)_transmitBuffers + (_txHead * TX_BUFFER_SIZE));
    bcopy(packet, buffer, len);

    /* Setup descriptor */
    desc->buffer1 = (unsigned int)buffer;
    desc->control = TDES1_LS | TDES1_FS | TDES1_IC | (len & TDES1_TBS1_MASK);
    desc->status = TDES0_OWN;

    /* Move to next descriptor */
    _txHead = (_txHead + 1) % _txRingSize;

    /* Kick transmit poll demand */
    [self writeCSR:CSR1_TX_POLL value:1];
}

/*
 * Private: Receive packet
 */
- (void)_receivePacket_length:(void *)packet
{
    /* This would pass the packet up to the network stack */
    /* Implementation depends on IOEthernetDriver interface */
}

/*
 * Private: Initialize descriptors
 */
- (BOOL)_initDescriptors
{
    unsigned int i;
    Descriptor *desc;
    void *buffer;

    /* Initialize RX descriptors */
    for (i = 0; i < _rxRingSize; i++) {
        desc = (Descriptor *)_rxDescriptors + i;
        buffer = (void *)((unsigned int)_receiveBuffers + (i * RX_BUFFER_SIZE));

        desc->status = RDES0_OWN;
        desc->control = RDES1_RCH | (RX_BUFFER_SIZE & RDES1_RBS1_MASK);
        desc->buffer1 = (unsigned int)buffer;

        /* Link to next descriptor */
        if (i < _rxRingSize - 1) {
            desc->buffer2 = (unsigned int)(desc + 1);
        } else {
            desc->buffer2 = (unsigned int)_rxDescriptors;
            desc->control |= RDES1_RER;
        }
    }

    /* Initialize TX descriptors */
    for (i = 0; i < _txRingSize; i++) {
        desc = (Descriptor *)_txDescriptors + i;

        desc->status = 0;
        desc->control = TDES1_TCH;
        desc->buffer1 = 0;

        /* Link to next descriptor */
        if (i < _txRingSize - 1) {
            desc->buffer2 = (unsigned int)(desc + 1);
        } else {
            desc->buffer2 = (unsigned int)_txDescriptors;
            desc->control |= TDES1_TER;
        }
    }

    return YES;
}

/*
 * Private: Setup RX descriptor
 */
- (void)_setupRxDescriptor:(int)index
{
    Descriptor *desc;
    void *buffer;

    if (index >= _rxRingSize) {
        return;
    }

    desc = (Descriptor *)_rxDescriptors + index;
    buffer = (void *)((unsigned int)_receiveBuffers + (index * RX_BUFFER_SIZE));

    desc->status = RDES0_OWN;
    desc->buffer1 = (unsigned int)buffer;
}

/*
 * Private: Setup TX descriptor
 */
- (void)_setupTxDescriptor:(int)index
{
    Descriptor *desc;

    if (index >= _txRingSize) {
        return;
    }

    desc = (Descriptor *)_txDescriptors + index;
    desc->status = 0;
}

/*
 * Private: Load setup filter
 */
- (void)_loadSetupFilter
{
    unsigned short *setup;
    Descriptor *desc;
    int i;

    setup = (unsigned short *)_setupFrame;
    bzero(setup, SETUP_FRAME_SIZE);

    /* Create perfect filter for our station address */
    for (i = 0; i < 6; i++) {
        setup[i] = _stationAddress[i] | (_stationAddress[i] << 8);
    }

    /* Broadcast address */
    for (i = 6; i < 12; i++) {
        setup[i] = 0xFFFF;
    }

    /* Use first TX descriptor for setup frame */
    desc = (Descriptor *)_txDescriptors;
    desc->buffer1 = (unsigned int)_setupFrame;
    desc->control = TDES1_SET | TDES1_FS | TDES1_LS | TDES1_IC |
                    (SETUP_FRAME_SIZE & TDES1_TBS1_MASK);
    desc->status = TDES0_OWN;

    /* Kick transmit poll */
    [self writeCSR:CSR1_TX_POLL value:1];

    /* Wait for completion */
    for (i = 0; i < 1000; i++) {
        if (!(desc->status & TDES0_OWN)) {
            break;
        }
        IODelay(10);
    }
}

/*
 * Private: Update descriptor from netbuf
 */
- (void)_updateDescriptorFromNetbuf:(void *)descriptor
{
    /* Placeholder for netbuf integration */
}

/*
 * Private: Allocate netbuf
 */
- (void)_allocateNetbuf
{
    /* Placeholder for netbuf allocation */
}

/*
 * Private: Get statistics
 */
- (void)_getStatistics
{
    IOLog("%s: Statistics\n", [self name]);
    IOLog("  TX packets: %u\n", _txPackets);
    IOLog("  RX packets: %u\n", _rxPackets);
    IOLog("  TX errors: %u\n", _txErrors);
    IOLog("  RX errors: %u\n", _rxErrors);
    IOLog("  Collisions: %u\n", _collisions);
    IOLog("  Missed frames: %u\n", _missedFrames);
}

/*
 * Private: Reset statistics
 */
- (void)_resetStats
{
    _txPackets = 0;
    _rxPackets = 0;
    _txErrors = 0;
    _rxErrors = 0;
    _collisions = 0;
    _missedFrames = 0;
}

/*
 * Private: Get power state
 */
- (IOReturn)_getPowerState
{
    /* Power management not implemented for 21040/21041 */
    return IO_R_SUCCESS;
}

/*
 * Private: Set power state
 */
- (IOReturn)_setPowerState:(unsigned int)state
{
    /* Power management not implemented for 21040/21041 */
    return IO_R_SUCCESS;
}

/*
 * Private: Set power management
 */
- (void)_setPowerManagement
{
    /* Power management not implemented for 21040/21041 */
}

@end
