/*
 * DECchip21140NetworkDriver.m
 * Main driver implementation for DECchip 21140 Network Driver
 */

#import "DECchip21140NetworkDriver.h"
#import "DECchip21140NetworkDriverKernelServerInstance.h"
#import "DECchip21140.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IODevice.h>
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
#define CSR9_SERIAL_ROM         9
#define CSR10_RESERVED          10
#define CSR11_GP_TIMER          11
#define CSR12_GP_PORT           12
#define CSR13_RESERVED_13       13
#define CSR14_RESERVED_14       14
#define CSR15_WATCHDOG          15

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
#define MEDIA_100BASETX         1
#define MEDIA_100BASEFX         2

/* Descriptor structure */
typedef struct {
    volatile unsigned int status;
    volatile unsigned int control;
    volatile unsigned int buffer1;
    volatile unsigned int buffer2;
} Descriptor;

@implementation DECchip21140NetworkDriver

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    unsigned int vendorID, deviceID;

    if (![deviceDescription respondsTo:@selector(getPCIVendorID:deviceID:)]) {
        return NO;
    }

    [deviceDescription getPCIVendorID:&vendorID deviceID:&deviceID];

    /* Check for DEC vendor ID (0x1011) and 21140 device ID (0x0009) */
    if (vendorID == 0x1011 && deviceID == 0x0009) {
        return YES;
    }

    return NO;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    unsigned int vendorID, deviceID;

    [super initFromDeviceDescription:deviceDescription];

    _deviceDescription = (IOPCIDeviceDescription *)deviceDescription;

    /* Get PCI device info */
    [_deviceDescription getPCIVendorID:&vendorID deviceID:&deviceID];
    _pciVendor = vendorID;
    _pciDevice = deviceID;

    /* Initialize state */
    _isInitialized = NO;
    _isEnabled = NO;
    _linkUp = NO;
    _fullDuplex = NO;
    _promiscuousMode = NO;
    _multicastCount = 0;

    /* Initialize statistics */
    _txPackets = 0;
    _rxPackets = 0;
    _txErrors = 0;
    _rxErrors = 0;
    _collisions = 0;
    _missedFrames = 0;

    /* Set ring sizes */
    _rxRingSize = 32;
    _txRingSize = 32;
    _rxHead = 0;
    _rxTail = 0;
    _txHead = 0;
    _txTail = 0;

    /* Identify chip type */
    _chipType = [self identifyChip];

    /* Create kernel server instance */
    _kernelServerInstance = [[DECchip21140NetworkDriverKernelServerInstance alloc] init];
    [_kernelServerInstance setDriver:self];

    /* Allocate memory for buffers and descriptors */
    if (![self allocateMemory]) {
        [self free];
        return nil;
    }

    /* Initialize chip */
    if (![self initChip]) {
        [self free];
        return nil;
    }

    _isInitialized = YES;

    return self;
}

- free
{
    [self freeMemory];

    if (_kernelServerInstance) {
        [_kernelServerInstance free];
        _kernelServerInstance = nil;
    }

    return [super free];
}

- (BOOL)resetAndEnable:(BOOL)enable
{
    [self resetChip];

    if (enable) {
        _isEnabled = YES;
        [self enableAllInterrupts];
        [self startReceive];
        [self startTransmit];
    } else {
        _isEnabled = NO;
        [self disableAllInterrupts];
        [self stopReceive];
        [self stopTransmit];
    }

    return YES;
}

- (BOOL)enableAllInterrupts
{
    /* Enable normal interrupts */
    [self writeCSR:7 value:0x0001FFFF];
    return YES;
}

- (BOOL)disableAllInterrupts
{
    /* Disable all interrupts */
    [self writeCSR:7 value:0x00000000];
    return YES;
}

- (void)transmitPacket:(void *)pkt length:(unsigned int)len
{
    [self _sendPacket:pkt length:len];
}

- (void)receivePacket
{
    [self _receiveInterruptOccurred];
}

- (unsigned int)transmitQueueSize
{
    return _txRingSize;
}

- (unsigned int)receiveQueueSize
{
    return _rxRingSize;
}

- (void)interruptOccurred
{
    unsigned int status;

    /* Read interrupt status */
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

- (void)timeoutOccurred
{
    /* Update statistics */
    [self updateStats];
}

- (BOOL)getHardwareAddress:(enet_addr_t *)addr
{
    if (!addr) {
        return NO;
    }

    bcopy(_stationAddress, addr->ea_byte, 6);
    return YES;
}

- (void)setStationAddress:(enet_addr_t *)addr
{
    if (!addr) {
        return;
    }

    bcopy(addr->ea_byte, _stationAddress, 6);

    /* Reload setup filter */
    [self _loadSetupFilter];
}

- (IOReturn)getPowerState
{
    return IO_R_SUCCESS;
}

- (IOReturn)setPowerState:(unsigned int)state
{
    return IO_R_SUCCESS;
}

- (void)resetStats
{
    _txPackets = 0;
    _rxPackets = 0;
    _txErrors = 0;
    _rxErrors = 0;
    _collisions = 0;
    _missedFrames = 0;
}

- (void)updateStats
{
    unsigned int missed;

    /* Read missed frames counter */
    missed = [self readCSR:CSR8_MISSED_FRAMES];
    _missedFrames += missed & 0xFFFF;
}

- (void)getStatistics
{
    [self updateStats];
}

- (BOOL)allocateMemory
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
    return [self initDescriptors];
}

- (void)freeMemory
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

- (BOOL)initChip
{
    unsigned int busMode;
    unsigned int i;
    unsigned short eeprom;

    /* Reset the chip */
    [self resetChip];

    /* Configure bus mode */
    busMode = (32 << 8);  /* PBL = 32 */
    busMode |= (3 << 14); /* CAL = 3 (16 longwords) */
    [self writeCSR:CSR0_BUS_MODE value:busMode];

    /* Read MAC address from EEPROM */
    for (i = 0; i < 3; i++) {
        eeprom = [self _readEEPROM:i];
        _stationAddress[i * 2] = eeprom & 0xFF;
        _stationAddress[i * 2 + 1] = (eeprom >> 8) & 0xFF;
    }

    /* Set descriptor list base addresses */
    [self writeCSR:CSR3_RX_LIST_BASE value:(unsigned int)_rxDescriptors];
    [self writeCSR:CSR4_TX_LIST_BASE value:(unsigned int)_txDescriptors];

    /* Initialize MII */
    [self _initMII];

    /* Configure operation mode */
    [self _setInterface];

    /* Load setup filter */
    [self _loadSetupFilter];

    return YES;
}

- (void)resetChip
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

- (BOOL)initDescriptors
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

- (void)freeDescriptors
{
    /* Descriptors are freed in freeMemory */
}

- (void)setupRxDescriptor:(int)index
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

- (void)setupTxDescriptor:(int)index
{
    Descriptor *desc;

    if (index >= _txRingSize) {
        return;
    }

    desc = (Descriptor *)_txDescriptors + index;
    desc->status = 0;
}

- (void)startTransmit
{
    unsigned int csr6;

    /* Enable transmitter */
    csr6 = [self readCSR:6];
    csr6 |= 0x00002000;  /* ST bit */
    [self writeCSR:6 value:csr6];
}

- (void)stopTransmit
{
    unsigned int csr6;

    /* Disable transmitter */
    csr6 = [self readCSR:6];
    csr6 &= ~0x00002000;  /* ST bit */
    [self writeCSR:6 value:csr6];
}

- (void)startReceive
{
    unsigned int csr6;

    /* Enable receiver */
    csr6 = [self readCSR:6];
    csr6 |= 0x00000002;  /* SR bit */
    [self writeCSR:6 value:csr6];
}

- (void)stopReceive
{
    unsigned int csr6;

    /* Disable receiver */
    csr6 = [self readCSR:6];
    csr6 &= ~0x00000002;  /* SR bit */
    [self writeCSR:6 value:csr6];
}

- (void)loadSetupFilter
{
    [self _loadSetupFilter];
}

- (void)sendSetupFrame
{
    /* Setup frame is sent as part of _loadSetupFilter */
    [self _loadSetupFilter];
}

- (void)addMulticastAddress:(enet_addr_t *)addr
{
    if (_multicastCount < 16) {
        _multicastCount++;
        [self _loadSetupFilter];
    }
}

- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    if (_multicastCount > 0) {
        _multicastCount--;
        [self _loadSetupFilter];
    }
}

- (void)setPromiscuousMode:(BOOL)enable
{
    unsigned int csr6;

    _promiscuousMode = enable;

    csr6 = [self readCSR:6];

    if (enable) {
        csr6 |= 0x00000040;  /* PR bit */
    } else {
        csr6 &= ~0x00000040;  /* PR bit */
    }

    [self writeCSR:6 value:csr6];
}

- (unsigned int)readCSR:(int)csr
{
    volatile unsigned int *base = (volatile unsigned int *)_memBase;
    return base[csr];
}

- (void)writeCSR:(int)csr value:(unsigned int)value
{
    volatile unsigned int *base = (volatile unsigned int *)_memBase;
    base[csr] = value;
}

- (DECchip21140Type)identifyChip
{
    if (_pciDevice == 0x0009) {
        return CHIP_TYPE_21140;
    } else if (_pciDevice == 0x0019) {
        return CHIP_TYPE_21142;
    } else if (_pciDevice == 0x0029) {
        return CHIP_TYPE_21143;
    }

    return CHIP_TYPE_UNKNOWN;
}

- (const char *)chipName
{
    switch (_chipType) {
        case CHIP_TYPE_21140:
            return "DECchip 21140";
        case CHIP_TYPE_21142:
            return "DECchip 21142";
        case CHIP_TYPE_21143:
            return "DECchip 21143";
        default:
            return "Unknown DECchip";
    }
}

- (DECchip21140NetworkDriverKernelServerInstance *)kernelServerInstance
{
    return _kernelServerInstance;
}

@end
