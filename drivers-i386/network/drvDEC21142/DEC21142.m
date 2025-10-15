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

/* DEC 21142 CSR (Control and Status Register) Offsets */
#define CSR0_BUS_MODE           0x00    /* Bus Mode Register */
#define CSR1_TRANSMIT_POLL      0x08    /* Transmit Poll Demand */
#define CSR2_RECEIVE_POLL       0x10    /* Receive Poll Demand */
#define CSR3_RX_LIST_BASE       0x18    /* Receive List Base Address */
#define CSR4_TX_LIST_BASE       0x20    /* Transmit List Base Address */
#define CSR5_STATUS             0x28    /* Status Register */
#define CSR6_NETWORK_ACCESS     0x30    /* Network Access (Opmode) Register */
#define CSR7_INTERRUPT_MASK     0x38    /* Interrupt Enable Register */
#define CSR8_MISSED_FRAMES      0x40    /* Missed Frames Counter */
#define CSR9_SROM_MII           0x48    /* SROM and MII Management */
#define CSR11_TIMER             0x58    /* General-Purpose Timer */
#define CSR12_SIA_STATUS        0x60    /* SIA Status Register */
#define CSR13_SIA_CONNECTIVITY  0x68    /* SIA Connectivity Register */
#define CSR14_SIA_TX_RX         0x70    /* SIA Transmit and Receive */
#define CSR15_SIA_GENERAL       0x78    /* SIA General Register */

/* CSR0 Bus Mode Register bits */
#define CSR0_RESET              0x00000001
#define CSR0_DESCRIPTOR_SKIP_LEN 0x0000007C
#define CSR0_BIG_ENDIAN         0x00000080
#define CSR0_BURST_LEN_MASK     0x00003F00
#define CSR0_CACHE_ALIGN_MASK   0x0000C000

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
#define CSR5_NORMAL_INT_SUM     0x00010000
#define CSR5_ABNORMAL_INT_SUM   0x00008000
#define CSR5_ERROR_BITS         0x03800000

/* CSR6 Network Access Register bits */
#define CSR6_HP                 0x00000001  /* Hash/Perfect filtering */
#define CSR6_SR                 0x00000002  /* Start/Stop Receive */
#define CSR6_HO                 0x00000004  /* Hash Only filtering */
#define CSR6_PB                 0x00000008  /* Pass Bad frames */
#define CSR6_IF                 0x00000010  /* Inverse Filtering */
#define CSR6_SB                 0x00000020  /* Start/Stop Backoff counter */
#define CSR6_PR                 0x00000040  /* Promiscuous Mode */
#define CSR6_PM                 0x00000080  /* Pass All Multicast */
#define CSR6_FKD                0x00000100  /* Flaky Oscillator Disable */
#define CSR6_FD                 0x00000200  /* Full Duplex mode */
#define CSR6_OM_MASK            0x00000C00  /* Operating Mode */
#define CSR6_FC                 0x00001000  /* Force Collision */
#define CSR6_ST                 0x00002000  /* Start/Stop Transmission */
#define CSR6_TR_MASK            0x0000C000  /* Threshold Control */
#define CSR6_CA                 0x00020000  /* Capture Effect Enable */
#define CSR6_PS                 0x08000000  /* Port Select */
#define CSR6_HBD                0x00080000  /* Heartbeat Disable */
#define CSR6_PCS                0x00800000  /* PCS function */
#define CSR6_SCR                0x01000000  /* Scrambler mode */

/* CSR7 Interrupt Enable Register bits */
#define CSR7_TRANSMIT_INT       0x00000001
#define CSR7_TRANSMIT_STOPPED   0x00000002
#define CSR7_TRANSMIT_UNAVAIL   0x00000004
#define CSR7_RECEIVE_INT        0x00000040
#define CSR7_RECEIVE_UNAVAIL    0x00000080
#define CSR7_RECEIVE_STOPPED    0x00000100
#define CSR7_TIMER_INT          0x00000800
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

/* Timeout values */
#define COMMAND_TIMEOUT         1000
#define RESET_TIMEOUT           10000
#define MII_TIMEOUT             1000
#define SROM_TIMEOUT            1000

/* PCI IDs */
#define DEC_VENDOR_ID           0x1011
#define DEC_21142_DEVICE        0x0019

/* Descriptor flags */
#define DESC_OWN                0x80000000  /* Owned by controller */
#define DESC_ES                 0x00008000  /* Error Summary */

/* RX Descriptor flags */
#define RDESC_FL_MASK           0x3FFF0000  /* Frame Length */
#define RDESC_FL_SHIFT          16
#define RDESC_FS                0x00000100  /* First Descriptor */
#define RDESC_LS                0x00000200  /* Last Descriptor */
#define RDESC_RER               0x02000000  /* Receive End of Ring */

/* TX Descriptor flags */
#define TDESC_FS                0x20000000  /* First Segment */
#define TDESC_LS                0x40000000  /* Last Segment */
#define TDESC_IC                0x80000000  /* Interrupt on Completion */
#define TDESC_TER               0x02000000  /* Transmit End of Ring */

@implementation DEC21142

/*
 * Probe method - called to determine if hardware is present
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    DEC21142 *driver;
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
    unsigned int vendorID, deviceID;
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

    /* Get PCI device information */
    if ([deviceDescription isKindOf:[IOPCIDeviceDescription class]]) {
        pciDevice = (IOPCIDeviceDescription *)deviceDescription;

        /* Get vendor and device ID */
        _pciVendor = [pciDevice vendorID];
        _pciDevice = [pciDevice deviceID];

        /* Verify this is a DEC 21142 */
        if (_pciVendor != DEC_VENDOR_ID || _pciDevice != DEC_21142_DEVICE) {
            IOLog("DEC21142: Unsupported device %04x:%04x\n",
                  _pciVendor, _pciDevice);
            [self free];
            return nil;
        }

        /* Get I/O base address and IRQ */
        _ioBase = [pciDevice portRangeList:0].start;
        _irqLevel = [pciDevice interrupt];
        _memBase = (void *)[pciDevice memoryRangeList:0].start;

        IOLog("DEC21142: Found device at I/O base 0x%x, IRQ %d\n",
              _ioBase, _irqLevel);
    } else {
        IOLog("DEC21142: Invalid device description\n");
        [self free];
        return nil;
    }

    /* Read MAC address from SROM */
    if (![self getHardwareAddress:(enet_addr_t *)_romAddress]) {
        IOLog("DEC21142: Failed to read hardware address\n");
        [self free];
        return nil;
    }

    IOLog("DEC21142: MAC address %02x:%02x:%02x:%02x:%02x:%02x\n",
          _romAddress[0], _romAddress[1], _romAddress[2],
          _romAddress[3], _romAddress[4], _romAddress[5]);

    /* Allocate buffers */
    if (![self allocateBuffers]) {
        IOLog("DEC21142: Failed to allocate buffers\n");
        [self free];
        return nil;
    }

    /* Initialize descriptors */
    if (![self initDescriptors]) {
        IOLog("DEC21142: Failed to initialize descriptors\n");
        [self free];
        return nil;
    }

    /* Initialize the chip */
    if (![self initChip]) {
        IOLog("DEC21142: Failed to initialize chip\n");
        [self free];
        return nil;
    }

    /* Setup PHY */
    [self setupPhy];

    /* Check link status */
    [self checkLink];

    /* Create server instance */
    _serverInstance = [[DEC21142KernelServerInstance alloc] initWithDriver:self];

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

    [self freeDescriptors];
    [self freeBuffers];

    return [super free];
}

/*
 * Reset and enable/disable the hardware
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    if (enable) {
        [self resetChip];

        if (![self initChip]) {
            IOLog("DEC21142: Failed to initialize chip during enable\n");
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
              CSR7_NORMAL_INT | CSR7_ABNORMAL_INT;

    [self writeCSR:7 value:intMask];

    return YES;
}

/*
 * Disable all interrupts
 */
- (BOOL)disableAllInterrupts
{
    /* Write 0 to interrupt enable register */
    [self writeCSR:7 value:0];

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
        IOLog("DEC21142: TX descriptor not available\n");
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
        IOLog("DEC21142: RX error, status=0x%x\n", status);
        goto recycle;
    }

    /* Get frame length */
    len = (status & RDESC_FL_MASK) >> RDESC_FL_SHIFT;

    if (len > 0 && len <= RX_BUFFER_SIZE) {
        /* Allocate packet buffer */
        pkt = IOMalloc(len);
        if (pkt) {
            bcopy(rxBuf, pkt, len);

            /* Pass packet to network stack */
            [self handleInputPacket:pkt length:len];

            IOFree(pkt, len);
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

    /* Read status register */
    status = [self readCSR:5];

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
        IOLog("DEC21142: Transmit stopped\n");
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
        IOLog("DEC21142: Receive stopped\n");
        [self startReceive];
    }

    /* Handle link change */
    if (status & CSR5_LINK_CHANGE) {
        handled |= CSR5_LINK_CHANGE;
        [self checkLink];
    }

    /* Acknowledge interrupts */
    if (handled) {
        [self writeCSR:5 value:handled];
    }
}

/*
 * Timeout handler
 */
- (void)timeoutOccurred
{
    _transmitTimeout++;

    if (_transmitTimeout > COMMAND_TIMEOUT) {
        IOLog("DEC21142: Transmit timeout, resetting\n");
        [self resetAndEnable:YES];
    }
}

/*
 * Get hardware MAC address from SROM
 */
- (BOOL)getHardwareAddress:(enet_addr_t *)addr
{
    int i;
    unsigned short word;

    /* Read MAC address from SROM (first 3 words at offset 0) */
    for (i = 0; i < 3; i++) {
        word = [self sromRead:i];
        _romAddress[i * 2] = word & 0xFF;
        _romAddress[i * 2 + 1] = (word >> 8) & 0xFF;
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
    /* DEC 21142 uses CSR writes for commands */
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
    /* Format: 16 entries of 6 bytes each */
    for (i = 0; i < 16; i++) {
        setupData[i * 3 + 0] = (_romAddress[1] << 8) | _romAddress[0];
        setupData[i * 3 + 1] = (_romAddress[3] << 8) | _romAddress[2];
        setupData[i * 3 + 2] = (_romAddress[5] << 8) | _romAddress[4];
    }

    /* Use descriptor 0 for setup frame */
    txDesc = (unsigned int *)_txDescriptors;

    txDesc[1] = SETUP_FRAME_SIZE | TDESC_FS | TDESC_LS | 0x08000000; /* Setup frame bit */
    txDesc[2] = (unsigned int)_setupFrame;
    txDesc[3] = 0;
    txDesc[0] = DESC_OWN;

    /* Trigger transmit poll */
    [self writeCSR:1 value:1];
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
}

/*
 * Setup PHY
 */
- (void)setupPhy
{
    int phyStatus;

    /* Reset PHY via MII */
    [self miiWrite:1 reg:0 value:0x8000];

    /* Wait for reset to complete */
    IODelay(10000);

    /* Enable auto-negotiation */
    [self miiWrite:1 reg:0 value:0x1200];

    /* Wait for auto-negotiation */
    IODelay(100000);
}

/*
 * Check link status
 */
- (void)checkLink
{
    int status;

    /* Read PHY status register */
    status = [self miiRead:1 reg:1];

    if (status >= 0) {
        /* Bit 2 indicates link status */
        _linkUp = (status & 0x04) ? YES : NO;

        if (_linkUp) {
            IOLog("DEC21142: Link is up\n");
        } else {
            IOLog("DEC21142: Link is down\n");
        }
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

    /* Clear buffers */
    bzero(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_DESCRIPTORS);
    bzero(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_DESCRIPTORS);
    bzero(_setupFrame, SETUP_FRAME_SIZE);

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
    /* Set cache alignment, burst length */
    [self writeCSR:0 value:0x00000000];

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

    [self writeCSR:6 value:opmode];

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
        IOLog("DEC21142: Reset timeout\n");
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
    int timeout = MII_TIMEOUT;
    int i;

    /* Build MII read command */
    /* Frame: 01 (start) + 10 (read) + 5-bit PHY addr + 5-bit reg addr */
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

    /* Build MII write command */
    /* Frame: 01 (start) + 01 (write) + 5-bit PHY addr + 5-bit reg addr + 10 (turnaround) + 16-bit data */
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

    /* Descriptor format:
     * [0] = status/control (owned by DMA)
     * [1] = control/buffer size
     * [2] = buffer address 1
     * [3] = buffer address 2 (or next descriptor)
     */

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
    if (_multicastCount < 32) {
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
 * Recycle network buffer
 */
- (void)recycleNetbuf
{
    /* Return buffer to pool */
}

/*
 * Shrink queue
 */
- (void)shrinkQueue
{
    /* Reduce queue size if needed */
}

/*
 * Set transmit queue size
 */
- (void)setTransmitQueueSize:(unsigned int)size
{
    if (size > 0 && size <= 64) {
        _txRingSize = size;
    }
}

/*
 * Get transmit queue count
 */
- (unsigned int)getTransmitQueueCount
{
    return _txRingSize;
}

/*
 * Get model ID
 */
- (void)getModelId
{
    /* Read model ID from hardware */
}

/*
 * Set model ID
 */
- (void)setModelId:(int)modelId
{
    /* Store model ID */
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
 * Get server instance
 */
- (DEC21142KernelServerInstance *)serverInstance
{
    return _serverInstance;
}

/*
 * Set server instance
 */
- (void)setServerInstance:(DEC21142KernelServerInstance *)instance
{
    if (_serverInstance != instance) {
        if (_serverInstance) {
            [_serverInstance free];
        }
        _serverInstance = instance;
    }
}

@end
