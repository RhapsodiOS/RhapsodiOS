/*
 * DEC21X4X.m
 * DEC Generic 21X4X Network Driver
 * Supports DEC 21040, 21041, 21140, 21142, 21143 Ethernet Controllers
 */

#import "DEC21X4X.h"
#import "DEC21X4XKernelServerInstance.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/align.h>
#import <mach/mach_interface.h>
#import <string.h>

/* DEC 21X4X CSR (Control and Status Register) Offsets */
#define CSR0_BUS_MODE           0x00
#define CSR1_TRANSMIT_POLL      0x08
#define CSR2_RECEIVE_POLL       0x10
#define CSR3_RX_LIST_BASE       0x18
#define CSR4_TX_LIST_BASE       0x20
#define CSR5_STATUS             0x28
#define CSR6_NETWORK_ACCESS     0x30
#define CSR7_INTERRUPT_MASK     0x38
#define CSR8_MISSED_FRAMES      0x40
#define CSR9_SROM_MII           0x48
#define CSR10_DIAG_MODE         0x50
#define CSR11_TIMER             0x58
#define CSR12_SIA_STATUS        0x60
#define CSR13_SIA_CONNECTIVITY  0x68
#define CSR14_SIA_TX_RX         0x70
#define CSR15_SIA_GENERAL       0x78

/* CSR0 Bus Mode Register bits */
#define CSR0_RESET              0x00000001
#define CSR0_ARBITRATION        0x00000002
#define CSR0_DESCRIPTOR_SKIP_LEN 0x0000007C
#define CSR0_BIG_ENDIAN         0x00000080
#define CSR0_BURST_LEN_MASK     0x00003F00
#define CSR0_CACHE_ALIGN_MASK   0x0000C000
#define CSR0_READ_MULTIPLE      0x00020000
#define CSR0_WRITE_INVALIDATE   0x01000000

/* CSR5 Status Register bits */
#define CSR5_TRANSMIT_INT       0x00000001
#define CSR5_TRANSMIT_STOPPED   0x00000002
#define CSR5_TRANSMIT_UNAVAIL   0x00000004
#define CSR5_TRANSMIT_JABBER    0x00000008
#define CSR5_LINK_PASS          0x00000010
#define CSR5_TRANSMIT_UNDERFLOW 0x00000020
#define CSR5_RECEIVE_INT        0x00000040
#define CSR5_RECEIVE_UNAVAIL    0x00000080
#define CSR5_RECEIVE_STOPPED    0x00000100
#define CSR5_RECEIVE_WATCHDOG   0x00000200
#define CSR5_TIMER_EXPIRED      0x00000800
#define CSR5_LINK_CHANGE        0x00001000
#define CSR5_ABNORMAL_INT_SUM   0x00008000
#define CSR5_NORMAL_INT_SUM     0x00010000
#define CSR5_STATE_MASK         0x00700000
#define CSR5_ERROR_BITS         0x03800000

/* CSR6 Network Access Register bits */
#define CSR6_HP                 0x00000001
#define CSR6_SR                 0x00000002
#define CSR6_HO                 0x00000004
#define CSR6_PB                 0x00000008
#define CSR6_IF                 0x00000010
#define CSR6_SB                 0x00000020
#define CSR6_PR                 0x00000040
#define CSR6_PM                 0x00000080
#define CSR6_FKD                0x00000100
#define CSR6_FD                 0x00000200
#define CSR6_OM_MASK            0x00000C00
#define CSR6_FC                 0x00001000
#define CSR6_ST                 0x00002000
#define CSR6_TR_MASK            0x0000C000
#define CSR6_CA                 0x00020000
#define CSR6_RA                 0x00040000
#define CSR6_HBD                0x00080000
#define CSR6_PS                 0x08000000
#define CSR6_PCS                0x00800000
#define CSR6_SCR                0x01000000
#define CSR6_MBO                0x02000000

/* CSR7 Interrupt Enable Register bits */
#define CSR7_TRANSMIT_INT       0x00000001
#define CSR7_TRANSMIT_STOPPED   0x00000002
#define CSR7_TRANSMIT_UNAVAIL   0x00000004
#define CSR7_RECEIVE_INT        0x00000040
#define CSR7_RECEIVE_UNAVAIL    0x00000080
#define CSR7_RECEIVE_STOPPED    0x00000100
#define CSR7_TIMER_INT          0x00000800
#define CSR7_LINK_CHANGE        0x00001000
#define CSR7_NORMAL_INT         0x00010000
#define CSR7_ABNORMAL_INT       0x00008000

/* CSR9 SROM and MII Management Register bits */
#define CSR9_SROM_DATA_IN       0x00000001
#define CSR9_SROM_DATA_OUT      0x00000002
#define CSR9_SROM_CLOCK         0x00000004
#define CSR9_SROM_CHIP_SELECT   0x00000008
#define CSR9_MII_DATA_IN        0x00080000
#define CSR9_MII_DATA_OUT       0x00020000
#define CSR9_MII_CLOCK          0x00010000
#define CSR9_MII_DIRECTION      0x00040000

/* Buffer sizes */
#define RX_BUFFER_SIZE          2048
#define TX_BUFFER_SIZE          2048
#define NUM_RX_DESCRIPTORS      32
#define NUM_TX_DESCRIPTORS      16
#define SETUP_FRAME_SIZE        192

/* Descriptor sizes */
#define RX_DESC_SIZE            16
#define TX_DESC_SIZE            16

/* SROM size */
#define SROM_SIZE               128

/* Timeout values */
#define COMMAND_TIMEOUT         1000
#define RESET_TIMEOUT           10000
#define MII_TIMEOUT             1000
#define LINK_TIMEOUT            5000

/* PCI IDs */
#define DEC_VENDOR_ID           0x1011
#define DEC_21040_DEVICE        0x0002
#define DEC_21041_DEVICE        0x0014
#define DEC_21140_DEVICE        0x0009
#define DEC_21142_DEVICE        0x0019
#define DEC_21143_DEVICE        0x0019

/* Descriptor flags */
#define DESC_OWN                0x80000000
#define DESC_ES                 0x00008000

/* RX Descriptor flags */
#define RDESC_FL_MASK           0x3FFF0000
#define RDESC_FL_SHIFT          16
#define RDESC_FS                0x00000100
#define RDESC_LS                0x00000200
#define RDESC_RER               0x02000000

/* TX Descriptor flags */
#define TDESC_FS                0x20000000
#define TDESC_LS                0x40000000
#define TDESC_IC                0x80000000
#define TDESC_TER               0x02000000
#define TDESC_SETUP             0x08000000

/* MII PHY registers */
#define MII_BMCR                0x00
#define MII_BMSR                0x01
#define MII_PHYID1              0x02
#define MII_PHYID2              0x03
#define MII_ANAR                0x04
#define MII_ANLPAR              0x05

/* MII BMCR bits */
#define BMCR_RESET              0x8000
#define BMCR_LOOPBACK           0x4000
#define BMCR_SPEED100           0x2000
#define BMCR_ANENABLE           0x1000
#define BMCR_POWERDOWN          0x0800
#define BMCR_ISOLATE            0x0400
#define BMCR_ANRESTART          0x0200
#define BMCR_FULLDPLX           0x0100

/* MII BMSR bits */
#define BMSR_100FULL            0x4000
#define BMSR_100HALF            0x2000
#define BMSR_10FULL             0x1000
#define BMSR_10HALF             0x0800
#define BMSR_ANEGCOMPLETE       0x0020
#define BMSR_ANEGCAPABLE        0x0008
#define BMSR_LSTATUS            0x0004

@implementation DEC21X4X

/*
 * Probe method - called to determine if hardware is present
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    DEC21X4X *driver;
    BOOL result = NO;

    driver = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (driver != nil) {
        result = YES;
        [driver free];
    }

    return result;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    IOPCIDeviceDescription *pciDevice;
    int i;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    _deviceDescription = deviceDescription;
    _serverInstance = nil;
    _isInitialized = NO;
    _isEnabled = NO;
    _linkUp = NO;
    _rxIndex = 0;
    _txIndex = 0;
    _transmitTimeout = 0;
    _receiveBuffer = NULL;
    _transmitBuffer = NULL;
    _setupFrame = NULL;
    _rxDescriptors = NULL;
    _txDescriptors = NULL;
    _rxRingSize = NUM_RX_DESCRIPTORS;
    _txRingSize = NUM_TX_DESCRIPTORS;
    _multicastCount = 0;
    _promiscuousMode = NO;
    _multicastList = NULL;
    _txPackets = 0;
    _rxPackets = 0;
    _txErrors = 0;
    _rxErrors = 0;
    _missedFrames = 0;
    _sromData = NULL;
    _sromSize = SROM_SIZE;
    _sromValid = NO;
    _phyAddress = 1;
    _phyID = 0;
    _mediaType = MEDIA_AUTO;
    _fullDuplex = NO;
    _autoNegotiate = YES;
    _linkSpeed = 0;
    _reserved1 = NULL;
    _reserved2 = NULL;
    _reserved3 = NULL;

    /* Get PCI device information */
    if ([deviceDescription isKindOf:[IOPCIDeviceDescription class]]) {
        pciDevice = (IOPCIDeviceDescription *)deviceDescription;

        /* Get vendor and device ID */
        _pciVendor = [pciDevice vendorID];
        _pciDevice = [pciDevice deviceID];
        _pciRevision = [pciDevice revisionID];

        /* Identify chip type */
        _chipType = [self identifyChip];

        if (_chipType == CHIP_UNKNOWN) {
            IOLog("DEC21X4X: Unsupported device %04x:%04x\n",
                  _pciVendor, _pciDevice);
            [self free];
            return nil;
        }

        /* Get I/O base address and IRQ */
        _ioBase = [pciDevice portRangeList:0].start;
        _irqLevel = [pciDevice interrupt];
        _memBase = (void *)[pciDevice memoryRangeList:0].start;

        IOLog("DEC21X4X: Found %s at I/O base 0x%x, IRQ %d\n",
              [self chipName], _ioBase, _irqLevel);
    } else {
        IOLog("DEC21X4X: Invalid device description\n");
        [self free];
        return nil;
    }

    /* Allocate SROM buffer */
    _sromData = (unsigned char *)IOMalloc(SROM_SIZE);
    if (!_sromData) {
        IOLog("DEC21X4X: Failed to allocate SROM buffer\n");
        [self free];
        return nil;
    }

    /* Read SROM */
    for (i = 0; i < SROM_SIZE / 2; i++) {
        unsigned short word = [self sromRead:i];
        _sromData[i * 2] = word & 0xFF;
        _sromData[i * 2 + 1] = (word >> 8) & 0xFF;
    }

    /* Parse SROM for configuration */
    [self parseSROM];

    /* Read MAC address from SROM */
    if (![self getHardwareAddress:(enet_addr_t *)_romAddress]) {
        IOLog("DEC21X4X: Failed to read hardware address\n");
        [self free];
        return nil;
    }

    IOLog("DEC21X4X: MAC address %02x:%02x:%02x:%02x:%02x:%02x\n",
          _romAddress[0], _romAddress[1], _romAddress[2],
          _romAddress[3], _romAddress[4], _romAddress[5]);

    /* Allocate buffers */
    if (![self allocateBuffers]) {
        IOLog("DEC21X4X: Failed to allocate buffers\n");
        [self free];
        return nil;
    }

    /* Initialize descriptors */
    if (![self initDescriptors]) {
        IOLog("DEC21X4X: Failed to initialize descriptors\n");
        [self free];
        return nil;
    }

    /* Initialize the chip */
    if (![self initChip]) {
        IOLog("DEC21X4X: Failed to initialize chip\n");
        [self free];
        return nil;
    }

    /* Initialize PHY if present */
    if (_chipType >= CHIP_21140) {
        [self phyInit];
    }

    /* Setup media */
    [self setupPhy];

    /* Check link status */
    [self checkLink];

    /* Create server instance */
    _serverInstance = [[DEC21X4XKernelServerInstance alloc] initWithDriver:self];

    /* Enable interrupts */
    if ([self enableAllInterrupts]) {
        [self enableInterrupt:_irqLevel];
    }

    _isInitialized = YES;

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

    if (_irqLevel) {
        [self disableInterrupt:_irqLevel];
    }

    if (_serverInstance) {
        [_serverInstance free];
        _serverInstance = nil;
    }

    if (_sromData) {
        IOFree(_sromData, SROM_SIZE);
        _sromData = NULL;
    }

    if (_multicastList) {
        IOFree(_multicastList, 32 * 6);
        _multicastList = NULL;
    }

    [self freeDescriptors];
    [self freeBuffers];

    return [super free];
}

/*
 * Identify chip type from PCI device ID
 */
- (DEC21X4XChipType)identifyChip
{
    if (_pciVendor != DEC_VENDOR_ID) {
        return CHIP_UNKNOWN;
    }

    switch (_pciDevice) {
        case DEC_21040_DEVICE:
            return CHIP_21040;
        case DEC_21041_DEVICE:
            return CHIP_21041;
        case DEC_21140_DEVICE:
            return CHIP_21140;
        case DEC_21142_DEVICE:
        case DEC_21143_DEVICE:
            if (_pciRevision >= 0x20) {
                return CHIP_21143;
            }
            return CHIP_21142;
        default:
            return CHIP_UNKNOWN;
    }
}

/*
 * Get chip name string
 */
- (const char *)chipName
{
    switch (_chipType) {
        case CHIP_21040: return "21040";
        case CHIP_21041: return "21041";
        case CHIP_21140: return "21140";
        case CHIP_21142: return "21142";
        case CHIP_21143: return "21143";
        default: return "Unknown";
    }
}

/*
 * Check if chip is of a specific type
 */
- (BOOL)isChipType:(DEC21X4XChipType)type
{
    return _chipType == type;
}

/*
 * Reset and enable/disable the hardware
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    if (enable) {
        [self resetChip];

        if (![self initChip]) {
            IOLog("DEC21X4X: Failed to initialize chip during enable\n");
            return NO;
        }

        [self enableAllInterrupts];
        _isEnabled = YES;

        /* Start receive and transmit units */
        [self startReceive];
    } else {
        [self disableAllInterrupts];
        [self stopReceive];
        [self stopTransmit];
        [self resetChip];
        _isEnabled = NO;
    }

    return YES;
}

/*
 * Clear timeout counter
 */
- (void)clearTimeout
{
    _transmitTimeout = 0;
}

/*
 * Enable all interrupts
 */
- (BOOL)enableAllInterrupts
{
    unsigned int intMask;

    /* Enable normal and abnormal interrupts */
    intMask = CSR7_TRANSMIT_INT | CSR7_RECEIVE_INT |
              CSR7_TRANSMIT_UNAVAIL | CSR7_RECEIVE_UNAVAIL |
              CSR7_LINK_CHANGE |
              CSR7_NORMAL_INT | CSR7_ABNORMAL_INT;

    [self writeCSR:7 value:intMask];
    _csrInterruptMask = intMask;

    return YES;
}

/*
 * Disable all interrupts
 */
- (BOOL)disableAllInterrupts
{
    /* Write 0 to interrupt enable register */
    [self writeCSR:7 value:0];
    _csrInterruptMask = 0;

    return YES;
}

/*
 * Transmit a packet
 */
- (void)transmitPacket:(void *)pkt length:(unsigned int)len
{
    unsigned int *txDesc;
    unsigned char *txBuf;
    unsigned int control;

    if (!_isEnabled || len > TX_BUFFER_SIZE) {
        return;
    }

    txDesc = (unsigned int *)_txDescriptors + (_txIndex * 4);
    txBuf = (unsigned char *)_transmitBuffer + (_txIndex * TX_BUFFER_SIZE);

    /* Check if descriptor is available */
    if (txDesc[0] & DESC_OWN) {
        IOLog("DEC21X4X: TX descriptor not available\n");
        _txErrors++;
        return;
    }

    /* Copy packet to transmit buffer */
    bcopy(pkt, txBuf, len);

    /* Setup descriptor */
    txDesc[1] = len | TDESC_FS | TDESC_LS;
    txDesc[2] = (unsigned int)txBuf;
    txDesc[3] = 0;

    /* Add end of ring marker if last descriptor */
    if (_txIndex == (_txRingSize - 1)) {
        txDesc[1] |= TDESC_TER;
    }

    /* Give ownership to controller */
    txDesc[0] = DESC_OWN;

    _txPackets++;

    /* Start transmit */
    [self startTransmit];

    _txIndex = (_txIndex + 1) % _txRingSize;
}

/*
 * Receive a packet
 */
- (void)receivePacket
{
    unsigned int *rxDesc;
    unsigned char *rxBuf;
    unsigned int status;
    unsigned int len;
    void *pkt;

    if (!_isEnabled) {
        return;
    }

    rxDesc = (unsigned int *)_rxDescriptors + (_rxIndex * 4);
    rxBuf = (unsigned char *)_receiveBuffer + (_rxIndex * RX_BUFFER_SIZE);

    /* Check if descriptor has been filled */
    if (rxDesc[0] & DESC_OWN) {
        /* Still owned by controller */
        return;
    }

    status = rxDesc[0];

    /* Check for errors */
    if (status & DESC_ES) {
        IOLog("DEC21X4X: RX error, status=0x%x\n", status);
        _rxErrors++;
        goto recycle;
    }

    /* Get frame length */
    len = (status & RDESC_FL_MASK) >> RDESC_FL_SHIFT;

    /* Subtract CRC */
    if (len > 4) {
        len -= 4;
    }

    if (len > 0 && len <= RX_BUFFER_SIZE) {
        /* Allocate packet buffer */
        pkt = IOMalloc(len);
        if (pkt) {
            bcopy(rxBuf, pkt, len);

            /* Pass packet to network stack */
            [self handleInputPacket:pkt length:len];

            IOFree(pkt, len);
            _rxPackets++;
        }
    }

recycle:
    /* Setup descriptor for reuse */
    [self setupRxDescriptor:_rxIndex];

    _rxIndex = (_rxIndex + 1) % _rxRingSize;
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
 * Interrupt handler
 */
- (void)interruptOccurred
{
    unsigned int status;
    unsigned int handled = 0;
    int count = 0;

    /* Read and acknowledge status */
    status = [self readCSR:5];

    /* Limit interrupt processing */
    while (status && count++ < 100) {
        /* Handle transmit interrupts */
        if (status & CSR5_TRANSMIT_INT) {
            handled |= CSR5_TRANSMIT_INT;
            [self clearTimeout];
        }

        if (status & CSR5_TRANSMIT_UNAVAIL) {
            handled |= CSR5_TRANSMIT_UNAVAIL;
        }

        if (status & CSR5_TRANSMIT_STOPPED) {
            handled |= CSR5_TRANSMIT_STOPPED;
            IOLog("DEC21X4X: Transmit stopped\n");
        }

        /* Handle receive interrupts */
        if (status & CSR5_RECEIVE_INT) {
            handled |= CSR5_RECEIVE_INT;
            [self receivePacket];
        }

        if (status & CSR5_RECEIVE_UNAVAIL) {
            handled |= CSR5_RECEIVE_UNAVAIL;
            [self startReceive];
        }

        if (status & CSR5_RECEIVE_STOPPED) {
            handled |= CSR5_RECEIVE_STOPPED;
            IOLog("DEC21X4X: Receive stopped\n");
            [self startReceive];
        }

        /* Handle link change */
        if (status & CSR5_LINK_CHANGE) {
            handled |= CSR5_LINK_CHANGE;
            [self checkLink];
        }

        /* Handle timer */
        if (status & CSR5_TIMER_EXPIRED) {
            handled |= CSR5_TIMER_EXPIRED;
        }

        /* Acknowledge interrupts */
        if (handled) {
            [self writeCSR:5 value:handled];
        }

        /* Read status again */
        status = [self readCSR:5];
        handled = 0;
    }
}

/*
 * Timeout handler
 */
- (void)timeoutOccurred
{
    _transmitTimeout++;

    if (_transmitTimeout > COMMAND_TIMEOUT) {
        IOLog("DEC21X4X: Transmit timeout, resetting\n");
        [self resetAndEnable:YES];
    }
}

/*
 * Get hardware MAC address from SROM
 */
- (BOOL)getHardwareAddress:(enet_addr_t *)addr
{
    int i;

    /* MAC address is at SROM offset 0 */
    if (_sromData && _sromValid) {
        for (i = 0; i < 6; i++) {
            _romAddress[i] = _sromData[i];
        }
    } else {
        /* Fallback: read from SROM directly */
        for (i = 0; i < 3; i++) {
            unsigned short word = [self sromRead:i];
            _romAddress[i * 2] = word & 0xFF;
            _romAddress[i * 2 + 1] = (word >> 8) & 0xFF;
        }
    }

    if (addr) {
        bcopy(_romAddress, addr->ea_byte, 6);
    }

    return YES;
}

/*
 * Perform a command (legacy compatibility)
 */
- (int)performCommand:(unsigned int)cmd
{
    /* DEC 21X4X uses CSR writes for commands */
    return 0;
}

/*
 * Send setup frame for address filtering
 */
- (void)sendSetupFrame
{
    unsigned int *setupData;
    unsigned int *txDesc;
    int i;

    if (!_setupFrame) {
        return;
    }

    setupData = (unsigned int *)_setupFrame;
    bzero(setupData, SETUP_FRAME_SIZE);

    /* Setup perfect filtering for our MAC address */
    /* Format: 16 entries of 6 bytes each in hash/perfect mode */
    for (i = 0; i < 16; i++) {
        setupData[i * 3 + 0] = (_romAddress[1] << 8) | _romAddress[0];
        setupData[i * 3 + 1] = (_romAddress[3] << 8) | _romAddress[2];
        setupData[i * 3 + 2] = (_romAddress[5] << 8) | _romAddress[4];
    }

    /* Use first available TX descriptor for setup frame */
    txDesc = (unsigned int *)_txDescriptors;

    /* Wait for descriptor to be available */
    while (txDesc[0] & DESC_OWN) {
        IODelay(10);
    }

    txDesc[1] = SETUP_FRAME_SIZE | TDESC_FS | TDESC_LS | TDESC_SETUP;
    txDesc[2] = (unsigned int)_setupFrame;
    txDesc[3] = 0;
    txDesc[0] = DESC_OWN;

    /* Trigger transmit poll */
    [self writeCSR:1 value:1];

    /* Wait for setup to complete */
    i = 1000;
    while ((txDesc[0] & DESC_OWN) && i-- > 0) {
        IODelay(10);
    }
}

/*
 * Get power state
 */
- (IOReturn)getPowerState
{
    return IO_R_SUCCESS;
}

/*
 * Set power state
 */
- (IOReturn)setPowerState:(unsigned int)state
{
    if (state == 0) {
        /* Power down */
        [self resetAndEnable:NO];
    } else {
        /* Power up */
        [self resetAndEnable:YES];
    }

    return IO_R_SUCCESS;
}

/*
 * Reset statistics
 */
- (void)resetStats
{
    _txPackets = 0;
    _rxPackets = 0;
    _txErrors = 0;
    _rxErrors = 0;
    _missedFrames = 0;

    /* Clear missed frames counter */
    [self readCSR:8];
}

/*
 * Update statistics
 */
- (void)updateStats
{
    [self getStatistics];
}

/*
 * Get statistics from hardware
 */
- (void)getStatistics
{
    unsigned int missedFrames;

    /* Read missed frames counter */
    missedFrames = [self readCSR:8];
    _missedFrames += (missedFrames & 0xFFFF);
}

/*
 * Setup PHY
 */
- (void)setupPhy
{
    if (_chipType >= CHIP_21140) {
        /* MII-based PHY */
        [self phyReset];

        if (_autoNegotiate) {
            [self phyAutoSense];
        }
    } else {
        /* SIA-based media (21040/21041) */
        [self selectMedia:MEDIA_10BASE_T];
    }
}

/*
 * Check link status
 */
- (void)checkLink
{
    int status;

    if (_chipType >= CHIP_21140) {
        /* Read PHY status register */
        status = [self miiRead:_phyAddress reg:MII_BMSR];

        if (status >= 0) {
            BOOL wasUp = _linkUp;
            _linkUp = (status & BMSR_LSTATUS) ? YES : NO;

            if (_linkUp && !wasUp) {
                IOLog("DEC21X4X: Link is up\n");

                /* Determine speed and duplex */
                if (status & (BMSR_100FULL | BMSR_100HALF)) {
                    _linkSpeed = 100;
                } else {
                    _linkSpeed = 10;
                }

                if (status & (BMSR_100FULL | BMSR_10FULL)) {
                    _fullDuplex = YES;
                } else {
                    _fullDuplex = NO;
                }

                IOLog("DEC21X4X: Speed %d Mbps, %s duplex\n",
                      _linkSpeed, _fullDuplex ? "full" : "half");
            } else if (!_linkUp && wasUp) {
                IOLog("DEC21X4X: Link is down\n");
            }
        }
    } else {
        /* Check SIA status for 21040/21041 */
        status = [self readCSR:12];
        _linkUp = (status & 0x02) ? YES : NO;
    }
}

/*
 * Allocate DMA buffers
 */
- (BOOL)allocateBuffers
{
    /* Allocate receive buffer */
    _receiveBuffer = IOMalloc(RX_BUFFER_SIZE * NUM_RX_DESCRIPTORS);
    if (!_receiveBuffer) {
        return NO;
    }

    /* Allocate transmit buffer */
    _transmitBuffer = IOMalloc(TX_BUFFER_SIZE * NUM_TX_DESCRIPTORS);
    if (!_transmitBuffer) {
        IOFree(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_DESCRIPTORS);
        _receiveBuffer = NULL;
        return NO;
    }

    /* Allocate setup frame buffer */
    _setupFrame = IOMalloc(SETUP_FRAME_SIZE);
    if (!_setupFrame) {
        IOFree(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_DESCRIPTORS);
        IOFree(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_DESCRIPTORS);
        _receiveBuffer = NULL;
        _transmitBuffer = NULL;
        return NO;
    }

    /* Allocate multicast list */
    _multicastList = IOMalloc(32 * 6);
    if (!_multicastList) {
        IOFree(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_DESCRIPTORS);
        IOFree(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_DESCRIPTORS);
        IOFree(_setupFrame, SETUP_FRAME_SIZE);
        _receiveBuffer = NULL;
        _transmitBuffer = NULL;
        _setupFrame = NULL;
        return NO;
    }

    /* Clear buffers */
    bzero(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_DESCRIPTORS);
    bzero(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_DESCRIPTORS);
    bzero(_setupFrame, SETUP_FRAME_SIZE);
    bzero(_multicastList, 32 * 6);

    return YES;
}

/*
 * Free DMA buffers
 */
- (void)freeBuffers
{
    if (_receiveBuffer) {
        IOFree(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_DESCRIPTORS);
        _receiveBuffer = NULL;
    }

    if (_transmitBuffer) {
        IOFree(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_DESCRIPTORS);
        _transmitBuffer = NULL;
    }

    if (_setupFrame) {
        IOFree(_setupFrame, SETUP_FRAME_SIZE);
        _setupFrame = NULL;
    }

    if (_multicastList) {
        IOFree(_multicastList, 32 * 6);
        _multicastList = NULL;
    }
}

/*
 * Initialize the chip
 */
- (BOOL)initChip
{
    unsigned int opmode;

    /* Reset the chip */
    [self resetChip];

    /* Wait for reset to complete */
    IODelay(10000);

    /* Configure bus mode (CSR0) */
    _csrBusMode = 0x00000000;  /* Default values */

    /* Set cache alignment for better performance */
    if (_chipType >= CHIP_21140) {
        _csrBusMode |= (32 << 8);  /* 32-word burst */
    }

    [self writeCSR:0 value:_csrBusMode];

    /* Load receive descriptor list base */
    [self writeCSR:3 value:(unsigned int)_rxDescriptors];

    /* Load transmit descriptor list base */
    [self writeCSR:4 value:(unsigned int)_txDescriptors];

    /* Setup DMA */
    if (![self setupDMA]) {
        return NO;
    }

    /* Send setup frame for address filtering */
    [self sendSetupFrame];

    /* Configure operating mode (CSR6) */
    opmode = CSR6_ST | CSR6_SR;  /* Start transmit and receive */

    if (_promiscuousMode) {
        opmode |= CSR6_PR;
    }

    if (_fullDuplex) {
        opmode |= CSR6_FD;
    }

    /* Set port select based on media type */
    if (_linkSpeed == 100 || _chipType >= CHIP_21140) {
        opmode |= CSR6_PS;  /* Port select for 100Mbps or MII */
    }

    [self writeCSR:6 value:opmode];
    _csrOpMode = opmode;

    return YES;
}

/*
 * Reset the chip
 */
- (void)resetChip
{
    int timeout = RESET_TIMEOUT;

    /* Issue software reset via CSR0 */
    [self writeCSR:0 value:CSR0_RESET];

    /* Wait for reset to complete */
    while (timeout-- > 0) {
        if (!([self readCSR:0] & CSR0_RESET)) {
            break;
        }
        IODelay(10);
    }

    if (timeout <= 0) {
        IOLog("DEC21X4X: Reset timeout\n");
    }

    /* Disable interrupts */
    [self disableAllInterrupts];
}

/*
 * Read from MII PHY register
 */
- (int)miiRead:(int)phyAddr reg:(int)regAddr
{
    unsigned int miiCmd;
    unsigned int miiData;
    int i;

    if (_chipType < CHIP_21140) {
        return -1;  /* No MII on 21040/21041 */
    }

    /* Build MII read command */
    miiCmd = (0x6 << 10) | (phyAddr << 5) | regAddr;

    /* Write command via CSR9 */
    for (i = 15; i >= 0; i--) {
        miiData = CSR9_MII_DIRECTION;
        if (miiCmd & (1 << i)) {
            miiData |= CSR9_MII_DATA_OUT;
        }

        [self writeCSR:9 value:miiData];
        IODelay(1);
        [self writeCSR:9 value:miiData | CSR9_MII_CLOCK];
        IODelay(1);
    }

    /* Read data */
    miiData = 0;
    for (i = 15; i >= 0; i--) {
        [self writeCSR:9 value:0];
        IODelay(1);
        [self writeCSR:9 value:CSR9_MII_CLOCK];
        IODelay(1);

        if ([self readCSR:9] & CSR9_MII_DATA_IN) {
            miiData |= (1 << i);
        }
    }

    return miiData;
}

/*
 * Write to MII PHY register
 */
- (void)miiWrite:(int)phyAddr reg:(int)regAddr value:(int)value
{
    unsigned int miiCmd;
    unsigned int miiData;
    int i;

    if (_chipType < CHIP_21140) {
        return;  /* No MII on 21040/21041 */
    }

    /* Build MII write command */
    miiCmd = (0x5 << 28) | (phyAddr << 23) | (regAddr << 18) | (0x2 << 16) | value;

    /* Write command and data via CSR9 */
    for (i = 31; i >= 0; i--) {
        miiData = CSR9_MII_DIRECTION;
        if (miiCmd & (1 << i)) {
            miiData |= CSR9_MII_DATA_OUT;
        }

        [self writeCSR:9 value:miiData];
        IODelay(1);
        [self writeCSR:9 value:miiData | CSR9_MII_CLOCK];
        IODelay(1);
    }

    /* Idle */
    [self writeCSR:9 value:0];
}

/*
 * Initialize PHY
 */
- (BOOL)phyInit
{
    int i;
    int phyid1, phyid2;

    /* Scan for PHY */
    for (i = 0; i < 32; i++) {
        phyid1 = [self miiRead:i reg:MII_PHYID1];
        if (phyid1 != 0 && phyid1 != 0xFFFF) {
            _phyAddress = i;
            phyid2 = [self miiRead:i reg:MII_PHYID2];
            _phyID = (phyid1 << 16) | phyid2;
            IOLog("DEC21X4X: Found PHY at address %d, ID 0x%08x\n", i, _phyID);
            return YES;
        }
    }

    IOLog("DEC21X4X: No PHY found\n");
    return NO;
}

/*
 * Reset PHY
 */
- (void)phyReset
{
    /* Reset PHY via MII */
    [self miiWrite:_phyAddress reg:MII_BMCR value:BMCR_RESET];

    /* Wait for reset to complete */
    IODelay(10000);

    /* Clear reset */
    [self miiWrite:_phyAddress reg:MII_BMCR value:0];
}

/*
 * Auto-sense PHY capabilities
 */
- (BOOL)phyAutoSense
{
    int bmcr;

    /* Enable auto-negotiation */
    bmcr = BMCR_ANENABLE | BMCR_ANRESTART;
    [self miiWrite:_phyAddress reg:MII_BMCR value:bmcr];

    /* Wait for auto-negotiation */
    IODelay(100000);

    return YES;
}

/*
 * Set PHY connection type
 */
- (void)setPhyConnection:(int)connectionType
{
    /* Implementation based on connection type */
}

/*
 * Get PHY control
 */
- (int)getPhyControl
{
    return [self miiRead:_phyAddress reg:MII_BMCR];
}

/*
 * Set PHY control
 */
- (void)setPhyControl:(int)control
{
    [self miiWrite:_phyAddress reg:MII_BMCR value:control];
}

/*
 * Read from SROM
 */
- (unsigned short)sromRead:(int)location
{
    unsigned int sromCmd;
    unsigned short retval = 0;
    int i;

    /* Select SROM */
    [self writeCSR:9 value:CSR9_SROM_CHIP_SELECT];
    IODelay(1);

    /* Build read command (110b + 6-bit address) */
    sromCmd = (0x6 << 6) | (location & 0x3F);

    /* Shift out command */
    for (i = 8; i >= 0; i--) {
        unsigned int bitval = (sromCmd & (1 << i)) ? CSR9_SROM_DATA_OUT : 0;
        [self writeCSR:9 value:CSR9_SROM_CHIP_SELECT | bitval];
        IODelay(1);
        [self writeCSR:9 value:CSR9_SROM_CHIP_SELECT | bitval | CSR9_SROM_CLOCK];
        IODelay(1);
    }

    /* Shift in data (16 bits) */
    for (i = 15; i >= 0; i--) {
        [self writeCSR:9 value:CSR9_SROM_CHIP_SELECT | CSR9_SROM_CLOCK];
        IODelay(1);

        if ([self readCSR:9] & CSR9_SROM_DATA_IN) {
            retval |= (1 << i);
        }

        [self writeCSR:9 value:CSR9_SROM_CHIP_SELECT];
        IODelay(1);
    }

    /* Deselect SROM */
    [self writeCSR:9 value:0];

    return retval;
}

/*
 * Write to SROM
 */
- (void)sromWrite:(int)location value:(unsigned short)value
{
    /* SROM write implementation */
    /* Note: Most SROMs are write-protected in production */
}

/*
 * Parse SROM for configuration data
 */
- (BOOL)parseSROM
{
    int i;
    unsigned char sum = 0;

    if (!_sromData) {
        return NO;
    }

    /* Calculate checksum */
    for (i = 0; i < SROM_SIZE - 1; i++) {
        sum += _sromData[i];
    }

    /* Verify checksum */
    if (sum == _sromData[SROM_SIZE - 1]) {
        _sromValid = YES;
        return YES;
    }

    IOLog("DEC21X4X: SROM checksum failed\n");
    _sromValid = NO;
    return NO;
}

/*
 * Load setup buffer
 */
- (void)loadSetupBuffer:(void *)buffer
{
    if (_setupFrame && buffer) {
        bcopy(buffer, _setupFrame, SETUP_FRAME_SIZE);
    }
}

/*
 * Setup DMA
 */
- (BOOL)setupDMA
{
    int i;

    /* Initialize all receive descriptors */
    for (i = 0; i < _rxRingSize; i++) {
        [self setupRxDescriptor:i];
    }

    /* Initialize all transmit descriptors */
    for (i = 0; i < _txRingSize; i++) {
        [self setupTxDescriptor:i];
    }

    return YES;
}

/*
 * Start transmit operation
 */
- (void)startTransmit
{
    /* Trigger transmit poll demand */
    [self writeCSR:1 value:1];
}

/*
 * Stop transmit operation
 */
- (void)stopTransmit
{
    unsigned int opmode;

    /* Clear ST bit in CSR6 */
    opmode = [self readCSR:6];
    opmode &= ~CSR6_ST;
    [self writeCSR:6 value:opmode];
    _csrOpMode = opmode;
}

/*
 * Start receive operation
 */
- (void)startReceive
{
    unsigned int opmode;

    /* Set SR bit in CSR6 and trigger receive poll */
    opmode = [self readCSR:6];
    opmode |= CSR6_SR;
    [self writeCSR:6 value:opmode];
    _csrOpMode = opmode;

    /* Trigger receive poll demand */
    [self writeCSR:2 value:1];
}

/*
 * Stop receive operation
 */
- (void)stopReceive
{
    unsigned int opmode;

    /* Clear SR bit in CSR6 */
    opmode = [self readCSR:6];
    opmode &= ~CSR6_SR;
    [self writeCSR:6 value:opmode];
    _csrOpMode = opmode;
}

/*
 * Initialize descriptor rings
 */
- (BOOL)initDescriptors
{
    /* Allocate receive descriptors */
    _rxDescriptors = IOMalloc(RX_DESC_SIZE * NUM_RX_DESCRIPTORS);
    if (!_rxDescriptors) {
        return NO;
    }

    /* Allocate transmit descriptors */
    _txDescriptors = IOMalloc(TX_DESC_SIZE * NUM_TX_DESCRIPTORS);
    if (!_txDescriptors) {
        IOFree(_rxDescriptors, RX_DESC_SIZE * NUM_RX_DESCRIPTORS);
        _rxDescriptors = NULL;
        return NO;
    }

    /* Clear descriptors */
    bzero(_rxDescriptors, RX_DESC_SIZE * NUM_RX_DESCRIPTORS);
    bzero(_txDescriptors, TX_DESC_SIZE * NUM_TX_DESCRIPTORS);

    return YES;
}

/*
 * Free descriptor rings
 */
- (void)freeDescriptors
{
    if (_rxDescriptors) {
        IOFree(_rxDescriptors, RX_DESC_SIZE * NUM_RX_DESCRIPTORS);
        _rxDescriptors = NULL;
    }

    if (_txDescriptors) {
        IOFree(_txDescriptors, TX_DESC_SIZE * NUM_TX_DESCRIPTORS);
        _txDescriptors = NULL;
    }
}

/*
 * Setup a receive descriptor
 */
- (void)setupRxDescriptor:(int)index
{
    unsigned int *rxDesc;
    unsigned char *rxBuf;

    rxDesc = (unsigned int *)_rxDescriptors + (index * 4);
    rxBuf = (unsigned char *)_receiveBuffer + (index * RX_BUFFER_SIZE);

    rxDesc[1] = RX_BUFFER_SIZE;
    rxDesc[2] = (unsigned int)rxBuf;
    rxDesc[3] = 0;

    /* Mark end of ring */
    if (index == (_rxRingSize - 1)) {
        rxDesc[1] |= RDESC_RER;
    }

    /* Give ownership to controller */
    rxDesc[0] = DESC_OWN;
}

/*
 * Setup a transmit descriptor
 */
- (void)setupTxDescriptor:(int)index
{
    unsigned int *txDesc;

    txDesc = (unsigned int *)_txDescriptors + (index * 4);

    /* Initialize descriptor */
    txDesc[0] = 0;
    txDesc[1] = 0;
    txDesc[2] = 0;
    txDesc[3] = 0;

    /* Mark end of ring */
    if (index == (_txRingSize - 1)) {
        txDesc[1] |= TDESC_TER;
    }
}

/*
 * Add multicast address
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    if (_multicastCount < 32 && _multicastList) {
        unsigned char *mcList = (unsigned char *)_multicastList;
        bcopy(addr->ea_byte, mcList + (_multicastCount * 6), 6);
        _multicastCount++;
        [self updateMulticastList];
    }
}

/*
 * Remove multicast address
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    if (_multicastCount > 0) {
        _multicastCount--;
        [self updateMulticastList];
    }
}

/*
 * Set multicast mode
 */
- (void)setMulticastMode:(BOOL)enable
{
    unsigned int opmode;

    opmode = [self readCSR:6];

    if (enable) {
        opmode |= CSR6_PM;
    } else {
        opmode &= ~CSR6_PM;
    }

    [self writeCSR:6 value:opmode];
    _csrOpMode = opmode;
}

/*
 * Update multicast address list
 */
- (void)updateMulticastList
{
    /* Send new setup frame with multicast list */
    [self sendSetupFrame];
}

/*
 * Set promiscuous mode
 */
- (void)setPromiscuousMode:(BOOL)enable
{
    unsigned int opmode;

    _promiscuousMode = enable;

    opmode = [self readCSR:6];

    if (enable) {
        opmode |= CSR6_PR;
    } else {
        opmode &= ~CSR6_PR;
    }

    [self writeCSR:6 value:opmode];
    _csrOpMode = opmode;
}

/*
 * Enable adapter interrupts
 */
- (BOOL)enableAdapterInterrupts
{
    return [self enableAllInterrupts];
}

/*
 * Disable adapter interrupts
 */
- (BOOL)disableAdapterInterrupts
{
    return [self disableAllInterrupts];
}

/*
 * Acknowledge interrupts
 */
- (void)acknowledgeInterrupts
{
    unsigned int status;

    status = [self readCSR:5];
    [self writeCSR:5 value:status];
}

/*
 * Allocate network buffer
 */
- (void)allocateNetbuf
{
    /* Network buffer allocation */
}

/*
 * Enable promiscuous mode (alternate entry)
 */
- (void)enablePromiscuousMode
{
    [self setPromiscuousMode:YES];
}

/*
 * Disable multicast mode
 */
- (void)disableMulticastMode
{
    [self setMulticastMode:NO];
}

/*
 * Get pending transmit count
 */
- (unsigned int)pendingTransmitCount
{
    return 0;
}

/*
 * Timeout occurred with timeout parameter
 */
- (unsigned int)timeoutOccurred_timeout
{
    [self timeoutOccurred];
    return _transmitTimeout;
}

/*
 * Select media type
 */
- (void)selectMedia:(DEC21X4XMediaType)media
{
    _mediaType = media;

    /* Configure chip for selected media */
    if (_chipType >= CHIP_21140) {
        /* MII-based media selection */
        switch (media) {
            case MEDIA_100BASE_TX:
                _linkSpeed = 100;
                break;
            case MEDIA_10BASE_T:
                _linkSpeed = 10;
                break;
            case MEDIA_AUTO:
                [self phyAutoSense];
                break;
            default:
                break;
        }
    } else {
        /* SIA-based media selection for 21040/21041 */
        switch (media) {
            case MEDIA_10BASE_T:
                [self writeCSR:13 value:0x00000001];
                [self writeCSR:14 value:0x0000007F];
                [self writeCSR:15 value:0x00000008];
                break;
            case MEDIA_10BASE_2:
                [self writeCSR:13 value:0x00000009];
                [self writeCSR:14 value:0x00000705];
                [self writeCSR:15 value:0x00000006];
                break;
            default:
                break;
        }
    }
}

/*
 * Detect media type
 */
- (DEC21X4XMediaType)detectMedia
{
    int bmsr;

    if (_chipType >= CHIP_21140) {
        /* Read PHY status */
        bmsr = [self miiRead:_phyAddress reg:MII_BMSR];

        if (bmsr & BMSR_100FULL) {
            return MEDIA_100BASE_TX;
        } else if (bmsr & BMSR_10FULL) {
            return MEDIA_10BASE_T;
        }
    }

    return MEDIA_10BASE_T;
}

/*
 * Set auto-sense timer
 */
- (void)setAutoSenseTimer
{
    /* Configure CSR11 timer */
    [self writeCSR:11 value:0xFFFF0000];
}

/*
 * Start auto-sense timer
 */
- (void)startAutoSenseTimer
{
    [self setAutoSenseTimer];
}

/*
 * Check connection support
 */
- (void)checkConnectionSupport
{
    /* Verify connection capabilities */
}

/*
 * Convert connection to control
 */
- (void)convertConnectionToControl
{
    /* Convert connection type to control register value */
}

/*
 * Handle link change interrupt
 */
- (void)handleLinkChangeInterrupt
{
    [self checkLink];
}

/*
 * Handle link fail interrupt
 */
- (void)handleLinkFailInterrupt
{
    _linkUp = NO;
    IOLog("DEC21X4X: Link failed\n");
}

/*
 * Handle link pass interrupt
 */
- (void)handleLinkPassInterrupt
{
    _linkUp = YES;
    IOLog("DEC21X4X: Link passed\n");
    [self checkLink];
}

/*
 * Read CSR register
 */
- (unsigned int)readCSR:(int)csr
{
    unsigned int offset = csr * 8;
    return inl(_ioBase + offset);
}

/*
 * Write CSR register
 */
- (void)writeCSR:(int)csr value:(unsigned int)value
{
    unsigned int offset = csr * 8;
    outl(_ioBase + offset, value);
}

/*
 * Write general register
 */
- (void)writeGenRegister:(int)reg value:(unsigned int)value
{
    [self writeCSR:reg value:value];
}

/*
 * Get driver name and media type occurred
 */
- (unsigned int)getDriverName_mediaTypeOccurred
{
    return 0;
}

/*
 * Schedule function, send packet, unschedule function
 */
- (void)scheduleFunc_sendPacket_unscheduleFunc
{
    /* Packet scheduling */
}

/*
 * Verify checksum, write Hi, get driver name
 */
- (void)verifyChecksum_writeHi_getDriverName
{
    /* Checksum verification */
}

/*
 * IODelay, IOFree, IOLog, IOPanic, IOReturn combined
 */
- (void)IODelay_IOFree_IOLog_IOPanic_IOReturn
{
    /* Utility functions wrapper */
}

/*
 * Get server instance
 */
- (DEC21X4XKernelServerInstance *)serverInstance
{
    return _serverInstance;
}

/*
 * Set server instance
 */
- (void)setServerInstance:(DEC21X4XKernelServerInstance *)instance
{
    if (_serverInstance != instance) {
        if (_serverInstance) {
            [_serverInstance free];
        }
        _serverInstance = instance;
    }
}

@end
