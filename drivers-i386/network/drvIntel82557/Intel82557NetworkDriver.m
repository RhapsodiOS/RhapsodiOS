/*
 * Intel82557NetworkDriver.m
 * Intel EtherExpress PRO/100B PCI Network Driver
 */

#import "Intel82557NetworkDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/align.h>
#import <mach/mach_interface.h>
#import <string.h>

/* Intel 82557 Register Offsets */
#define CSR_STATUS          0x00
#define CSR_COMMAND         0x02
#define CSR_INTERRUPT       0x03
#define CSR_GENERAL_PTR     0x04
#define CSR_PORT            0x08
#define CSR_EEPROM_CTRL     0x0E
#define CSR_MDI_CTRL        0x10

/* Command Unit Commands */
#define CU_NOP              0x0000
#define CU_START            0x0010
#define CU_RESUME           0x0020
#define CU_LOAD_DUMP_ADDR   0x0040
#define CU_DUMP_STATS       0x0050
#define CU_LOAD_CU_BASE     0x0060
#define CU_DUMP_RESET       0x0070

/* Receive Unit Commands */
#define RU_NOP              0x0000
#define RU_START            0x0001
#define RU_RESUME           0x0002
#define RU_ABORT            0x0004
#define RU_LOAD_RU_BASE     0x0006
#define RU_LOAD_HDS         0x0005

/* Status Register Bits */
#define SCB_STATUS_CX       0x8000
#define SCB_STATUS_FR       0x4000
#define SCB_STATUS_CNA      0x2000
#define SCB_STATUS_RNR      0x1000
#define SCB_STATUS_MDI      0x0800
#define SCB_STATUS_SWI      0x0400
#define SCB_STATUS_FCP      0x0100

/* Command Register Bits */
#define SCB_CMD_CUC         0x00F0
#define SCB_CMD_RUC         0x0007

/* Interrupt Mask Bits */
#define SCB_INT_MASK        0x01
#define SCB_INT_CX          0x80
#define SCB_INT_FR          0x40
#define SCB_INT_CNA         0x20
#define SCB_INT_RNR         0x10
#define SCB_INT_ER          0x08
#define SCB_INT_FCP         0x04
#define SCB_INT_SI          0x02
#define SCB_INT_M           0x01

/* PORT commands */
#define PORT_SOFTWARE_RESET 0x00000000
#define PORT_SELFTEST       0x00000001
#define PORT_SELECTIVE_RESET 0x00000002
#define PORT_DUMP           0x00000003

/* Buffer sizes */
#define RX_BUFFER_SIZE      2048
#define TX_BUFFER_SIZE      2048
#define NUM_RX_BUFFERS      32
#define NUM_TX_BUFFERS      16

/* Command Block sizes */
#define CB_SIZE             128

/* Timeout values */
#define COMMAND_TIMEOUT     1000
#define RESET_TIMEOUT       10000

/* PCI IDs */
#define INTEL_VENDOR_ID     0x8086
#define INTEL_82557_DEVICE  0x1229

@implementation Intel82557NetworkDriver

/*
 * Probe method - called to determine if hardware is present
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    Intel82557NetworkDriver *driver;
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
    _isInitialized = NO;
    _isEnabled = NO;
    _linkUp = NO;
    _rxIndex = 0;
    _txIndex = 0;
    _transmitTimeout = 0;
    _receiveBuffer = NULL;
    _transmitBuffer = NULL;
    _commandBlock = NULL;
    _rxRingBase = NULL;
    _txRingBase = NULL;
    _rxRingSize = NUM_RX_BUFFERS;
    _txRingSize = NUM_TX_BUFFERS;
    _multicastCount = 0;
    _promiscuousMode = NO;

    /* Get PCI device information */
    if ([deviceDescription isKindOf:[IOPCIDeviceDescription class]]) {
        pciDevice = (IOPCIDeviceDescription *)deviceDescription;

        /* Get vendor and device ID */
        _pciVendor = [pciDevice vendorID];
        _pciDevice = [pciDevice deviceID];

        /* Verify this is an Intel 82557 */
        if (_pciVendor != INTEL_VENDOR_ID || _pciDevice != INTEL_82557_DEVICE) {
            IOLog("Intel82557: Unsupported device %04x:%04x\n",
                  _pciVendor, _pciDevice);
            [self free];
            return nil;
        }

        /* Get I/O base address and IRQ */
        _ioBase = [pciDevice portRangeList:0].start;
        _irqLevel = [pciDevice interrupt];
        _memBase = (void *)[pciDevice memoryRangeList:0].start;

        IOLog("Intel82557: Found device at I/O base 0x%x, IRQ %d\n",
              _ioBase, _irqLevel);
    } else {
        IOLog("Intel82557: Invalid device description\n");
        [self free];
        return nil;
    }

    /* Read MAC address from EEPROM */
    if (![self getHardwareAddress:(enet_addr_t *)_romAddress]) {
        IOLog("Intel82557: Failed to read hardware address\n");
        [self free];
        return nil;
    }

    IOLog("Intel82557: MAC address %02x:%02x:%02x:%02x:%02x:%02x\n",
          _romAddress[0], _romAddress[1], _romAddress[2],
          _romAddress[3], _romAddress[4], _romAddress[5]);

    /* Allocate buffers */
    if (![self allocateBuffers]) {
        IOLog("Intel82557: Failed to allocate buffers\n");
        [self free];
        return nil;
    }

    /* Initialize the chip */
    if (![self initChip]) {
        IOLog("Intel82557: Failed to initialize chip\n");
        [self free];
        return nil;
    }

    /* Setup PHY */
    [self setupPhy];

    /* Check link status */
    [self checkLink];

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
            IOLog("Intel82557: Failed to initialize chip during enable\n");
            return NO;
        }

        [self enableAllInterrupts];
        _isEnabled = YES;

        /* Start receive unit */
        [self performCommand:RU_START];
    } else {
        [self disableAllInterrupts];
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
    unsigned char intMask = 0;

    /* Write interrupt mask to enable interrupts */
    outb(_ioBase + CSR_INTERRUPT, intMask);

    return YES;
}

/*
 * Disable all interrupts
 */
- (BOOL)disableAllInterrupts
{
    unsigned char intMask = SCB_INT_M;

    /* Write interrupt mask to disable all interrupts */
    outb(_ioBase + CSR_INTERRUPT, intMask);

    return YES;
}

/*
 * Transmit a packet
 */
- (void)transmitPacket:(void *)pkt length:(unsigned int)len
{
    unsigned char *txBuf;

    if (!_isEnabled || len > TX_BUFFER_SIZE) {
        return;
    }

    txBuf = (unsigned char *)_transmitBuffer + (_txIndex * TX_BUFFER_SIZE);

    /* Copy packet to transmit buffer */
    bcopy(pkt, txBuf, len);

    /* Store length in buffer header */
    *(unsigned short *)txBuf = len;

    /* Start transmit */
    [self startTransmit];

    _txIndex = (_txIndex + 1) % NUM_TX_BUFFERS;
}

/*
 * Receive a packet
 */
- (void)receivePacket
{
    unsigned char *rxBuf;
    unsigned int len;
    void *pkt;

    if (!_isEnabled) {
        return;
    }

    rxBuf = (unsigned char *)_receiveBuffer + (_rxIndex * RX_BUFFER_SIZE);

    /* Get packet length from buffer (first 2 bytes) */
    len = *(unsigned short *)rxBuf;

    if (len > 0 && len <= RX_BUFFER_SIZE - 2) {
        /* Allocate packet buffer */
        pkt = IOMalloc(len);
        if (pkt) {
            bcopy(rxBuf + 2, pkt, len);

            /* Pass packet to network stack */
            [self handleInputPacket:pkt length:len];

            IOFree(pkt, len);
        }
    }

    _rxIndex = (_rxIndex + 1) % NUM_RX_BUFFERS;
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
    unsigned short status;
    unsigned char ack = 0;

    /* Read status register */
    status = inw(_ioBase + CSR_STATUS);

    /* Handle command unit interrupts */
    if (status & SCB_STATUS_CX) {
        ack |= SCB_INT_CX;
        [self clearTimeout];
    }

    if (status & SCB_STATUS_CNA) {
        ack |= SCB_INT_CNA;
    }

    /* Handle receive unit interrupts */
    if (status & SCB_STATUS_FR) {
        ack |= SCB_INT_FR;
        [self receivePacket];
    }

    if (status & SCB_STATUS_RNR) {
        ack |= SCB_INT_RNR;
        /* Restart receive unit */
        [self performCommand:RU_START];
    }

    /* Handle flow control pause */
    if (status & SCB_STATUS_FCP) {
        ack |= SCB_INT_FCP;
    }

    /* Acknowledge interrupts */
    if (ack) {
        outb(_ioBase + CSR_INTERRUPT, ack);
    }
}

/*
 * Timeout handler
 */
- (void)timeoutOccurred
{
    _transmitTimeout++;

    if (_transmitTimeout > COMMAND_TIMEOUT) {
        IOLog("Intel82557: Transmit timeout, resetting\n");
        [self resetAndEnable:YES];
    }
}

/*
 * Get hardware MAC address
 */
- (BOOL)getHardwareAddress:(enet_addr_t *)addr
{
    int i;
    unsigned short word;

    /* Read MAC address from EEPROM (first 3 words) */
    for (i = 0; i < 3; i++) {
        word = [self eepromRead:i];
        _romAddress[i * 2] = word & 0xFF;
        _romAddress[i * 2 + 1] = (word >> 8) & 0xFF;
    }

    if (addr) {
        bcopy(_romAddress, addr->ea_byte, 6);
    }

    return YES;
}

/*
 * Perform a command
 */
- (int)performCommand:(unsigned int)cmd
{
    int timeout = COMMAND_TIMEOUT;
    unsigned short status;

    /* Wait for previous command to complete */
    while (timeout-- > 0) {
        status = inw(_ioBase + CSR_STATUS);
        if ((status & 0x00FF) == 0) {
            break;
        }
        IODelay(10);
    }

    if (timeout <= 0) {
        IOLog("Intel82557: Command timeout\n");
        return -1;
    }

    /* Issue command */
    outw(_ioBase + CSR_COMMAND, cmd);

    return 0;
}

/*
 * Send channel attention signal
 */
- (void)sendChannelAttention
{
    outb(_ioBase + CSR_COMMAND, 0x01);
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
    /* Issue dump and reset statistics command */
    outl(_ioBase + CSR_GENERAL_PTR, 0);
    [self performCommand:CU_DUMP_RESET];
}

/*
 * Update statistics
 */
- (void)updateStats
{
    /* Read statistics from chip */
    [self getStatistics];
}

/*
 * Get statistics from hardware
 */
- (void)getStatistics
{
    /* Trigger statistics dump */
    outl(_ioBase + CSR_GENERAL_PTR, 0);
    [self performCommand:CU_DUMP_STATS];
}

/*
 * Setup PHY
 */
- (void)setupPhy
{
    int phyStatus;

    /* Reset PHY */
    [self miiWrite:1 reg:0 value:0x8000];

    /* Wait for reset to complete */
    IODelay(10000);

    /* Enable auto-negotiation */
    [self miiWrite:1 reg:0 value:0x1200];
}

/*
 * Check link status
 */
- (void)checkLink
{
    int status;

    /* Read PHY status register (register 1) */
    status = [self miiRead:1 reg:1];

    if (status >= 0) {
        /* Bit 2 indicates link status */
        _linkUp = (status & 0x04) ? YES : NO;

        if (_linkUp) {
            IOLog("Intel82557: Link is up\n");
        } else {
            IOLog("Intel82557: Link is down\n");
        }
    }
}

/*
 * Allocate DMA buffers
 */
- (BOOL)allocateBuffers
{
    /* Allocate receive buffer */
    _receiveBuffer = IOMalloc(RX_BUFFER_SIZE * NUM_RX_BUFFERS);
    if (!_receiveBuffer) {
        return NO;
    }

    /* Allocate transmit buffer */
    _transmitBuffer = IOMalloc(TX_BUFFER_SIZE * NUM_TX_BUFFERS);
    if (!_transmitBuffer) {
        IOFree(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_BUFFERS);
        _receiveBuffer = NULL;
        return NO;
    }

    /* Allocate command block */
    _commandBlock = IOMalloc(CB_SIZE);
    if (!_commandBlock) {
        IOFree(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_BUFFERS);
        IOFree(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_BUFFERS);
        _receiveBuffer = NULL;
        _transmitBuffer = NULL;
        return NO;
    }

    /* Clear buffers */
    bzero(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_BUFFERS);
    bzero(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_BUFFERS);
    bzero(_commandBlock, CB_SIZE);

    _rxRingBase = _receiveBuffer;
    _txRingBase = _transmitBuffer;

    return YES;
}

/*
 * Free DMA buffers
 */
- (void)freeBuffers
{
    if (_receiveBuffer) {
        IOFree(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_BUFFERS);
        _receiveBuffer = NULL;
        _rxRingBase = NULL;
    }

    if (_transmitBuffer) {
        IOFree(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_BUFFERS);
        _transmitBuffer = NULL;
        _txRingBase = NULL;
    }

    if (_commandBlock) {
        IOFree(_commandBlock, CB_SIZE);
        _commandBlock = NULL;
    }
}

/*
 * Initialize the chip
 */
- (BOOL)initChip
{
    int i;

    /* Reset the chip */
    [self resetChip];

    /* Wait for reset to complete */
    IODelay(10000);

    /* Load CU base address */
    outl(_ioBase + CSR_GENERAL_PTR, 0);
    [self performCommand:CU_LOAD_CU_BASE];

    /* Load RU base address */
    outl(_ioBase + CSR_GENERAL_PTR, 0);
    [self performCommand:RU_LOAD_RU_BASE];

    /* Setup DMA */
    if (![self setupDMA]) {
        return NO;
    }

    return YES;
}

/*
 * Reset the chip
 */
- (void)resetChip
{
    /* Issue software reset via PORT register */
    outl(_ioBase + CSR_PORT, PORT_SOFTWARE_RESET);

    /* Wait for reset to complete */
    IODelay(20000);

    /* Disable interrupts */
    [self disableAllInterrupts];
}

/*
 * Read from MII PHY register
 */
- (int)miiRead:(int)phyAddr reg:(int)regAddr
{
    unsigned int mdiCtrl;
    int timeout = 1000;

    /* Build MDI control word: read operation */
    mdiCtrl = (2 << 26) | (phyAddr << 21) | (regAddr << 16);

    /* Write to MDI control register */
    outl(_ioBase + CSR_MDI_CTRL, mdiCtrl);

    /* Wait for operation to complete */
    while (timeout-- > 0) {
        mdiCtrl = inl(_ioBase + CSR_MDI_CTRL);
        if (mdiCtrl & (1 << 28)) {
            /* Operation complete */
            return mdiCtrl & 0xFFFF;
        }
        IODelay(10);
    }

    return -1;
}

/*
 * Write to MII PHY register
 */
- (void)miiWrite:(int)phyAddr reg:(int)regAddr value:(int)value
{
    unsigned int mdiCtrl;
    int timeout = 1000;

    /* Build MDI control word: write operation */
    mdiCtrl = (1 << 26) | (phyAddr << 21) | (regAddr << 16) | (value & 0xFFFF);

    /* Write to MDI control register */
    outl(_ioBase + CSR_MDI_CTRL, mdiCtrl);

    /* Wait for operation to complete */
    while (timeout-- > 0) {
        mdiCtrl = inl(_ioBase + CSR_MDI_CTRL);
        if (mdiCtrl & (1 << 28)) {
            /* Operation complete */
            return;
        }
        IODelay(10);
    }
}

/*
 * Read from EEPROM
 */
- (unsigned short)eepromRead:(int)location
{
    unsigned short eeCtrl;
    unsigned short retval = 0;
    int i;

    /* Select EEPROM, chip select high */
    eeCtrl = 0x04;
    outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl);

    /* Shift out read command (110b) and address */
    for (i = 10; i >= 0; i--) {
        unsigned short dataval = ((6 << 8) | location) & (1 << i) ? 0x02 : 0;
        outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl | dataval);
        IODelay(1);
        outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl | dataval | 0x01);
        IODelay(1);
    }

    /* Shift in data */
    for (i = 15; i >= 0; i--) {
        outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl | 0x01);
        IODelay(1);
        if (inw(_ioBase + CSR_EEPROM_CTRL) & 0x08) {
            retval |= (1 << i);
        }
        outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl);
        IODelay(1);
    }

    /* Deselect EEPROM */
    outw(_ioBase + CSR_EEPROM_CTRL, 0);

    return retval;
}

/*
 * Write to EEPROM
 */
- (void)eepromWrite:(int)location value:(unsigned short)value
{
    unsigned short eeCtrl;
    int i;

    /* Select EEPROM, chip select high */
    eeCtrl = 0x04;
    outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl);

    /* Write enable command */
    for (i = 10; i >= 0; i--) {
        unsigned short dataval = (0x4C0 & (1 << i)) ? 0x02 : 0;
        outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl | dataval);
        IODelay(1);
        outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl | dataval | 0x01);
        IODelay(1);
    }

    /* Deselect */
    outw(_ioBase + CSR_EEPROM_CTRL, 0);
    IODelay(1);

    /* Select again for write */
    outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl);

    /* Shift out write command (101b) and address */
    for (i = 10; i >= 0; i--) {
        unsigned short dataval = ((5 << 8) | location) & (1 << i) ? 0x02 : 0;
        outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl | dataval);
        IODelay(1);
        outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl | dataval | 0x01);
        IODelay(1);
    }

    /* Shift out data */
    for (i = 15; i >= 0; i--) {
        unsigned short dataval = (value & (1 << i)) ? 0x02 : 0;
        outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl | dataval);
        IODelay(1);
        outw(_ioBase + CSR_EEPROM_CTRL, eeCtrl | dataval | 0x01);
        IODelay(1);
    }

    /* Deselect EEPROM */
    outw(_ioBase + CSR_EEPROM_CTRL, 0);

    /* Wait for write to complete */
    IODelay(10000);
}

/*
 * Setup DMA for receive and transmit
 */
- (BOOL)setupDMA
{
    /* Configure receive frame area */
    outl(_ioBase + CSR_GENERAL_PTR, (unsigned int)_receiveBuffer);

    return YES;
}

/*
 * Start transmit operation
 */
- (void)startTransmit
{
    unsigned char *txBuf;

    txBuf = (unsigned char *)_transmitBuffer + (_txIndex * TX_BUFFER_SIZE);

    /* Load transmit buffer address */
    outl(_ioBase + CSR_GENERAL_PTR, (unsigned int)txBuf);

    /* Issue transmit command */
    [self performCommand:CU_START];

    _transmitTimeout = 0;
}

/*
 * Stop transmit operation
 */
- (void)stopTransmit
{
    /* Abort command unit */
    outw(_ioBase + CSR_COMMAND, 0x0040);
}

/*
 * Execute a polled command
 */
- (int)polledCommand:(void *)cmd
{
    int timeout = COMMAND_TIMEOUT;

    /* Wait for command to complete */
    if (![self waitForCommand]) {
        return -1;
    }

    /* Load command block address */
    outl(_ioBase + CSR_GENERAL_PTR, (unsigned int)cmd);

    /* Start command */
    [self performCommand:CU_START];

    /* Wait for completion */
    while (timeout-- > 0) {
        if (*(unsigned short *)cmd & 0x8000) {
            /* Command complete */
            return 0;
        }
        IODelay(10);
    }

    return -1;
}

/*
 * Wait for command to complete
 */
- (BOOL)waitForCommand
{
    int timeout = COMMAND_TIMEOUT;
    unsigned short status;

    while (timeout-- > 0) {
        status = inw(_ioBase + CSR_STATUS);
        if ((status & 0x00C0) != 0x00C0) {
            /* Command unit idle */
            return YES;
        }
        IODelay(10);
    }

    return NO;
}

/*
 * Add multicast address
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    if (_multicastCount < 32) {
        _multicastCount++;
    }
}

/*
 * Remove multicast address
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    if (_multicastCount > 0) {
        _multicastCount--;
    }
}

/*
 * Set multicast mode
 */
- (void)setMulticastMode:(BOOL)enable
{
    /* Configure multicast filtering */
}

/*
 * Set promiscuous mode
 */
- (void)setPromiscuousMode:(BOOL)enable
{
    _promiscuousMode = enable;

    /* Reconfigure chip for promiscuous mode */
    if (_isEnabled) {
        [self initChip];
    }
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
    unsigned short status;

    status = inw(_ioBase + CSR_STATUS);
    outw(_ioBase + CSR_STATUS, status);
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
- (void)transmitQueueSize:(unsigned int)size
{
    if (size > 0 && size <= 64) {
        _txRingSize = size;
    }
}

/*
 * Get transmit queue count
 */
- (void)transmitQueueCount
{
    /* Return number of queued transmit packets */
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
 * Get contents (statistics)
 */
- (void)getContents
{
    [self getStatistics];
}

@end
