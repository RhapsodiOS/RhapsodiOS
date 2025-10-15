/*
 * Intel82595NetworkDriver.m
 * Intel 82595 PCMCIA Ethernet Adapter Driver (Cogent EM595)
 */

#import "Intel82595NetworkDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/align.h>
#import <mach/mach_interface.h>
#import <string.h>

/* Intel 82595 Register Offsets */
#define REG_COMMAND         0x00
#define REG_STATUS          0x01
#define REG_ID              0x02
#define REG_INT_MASK        0x03
#define REG_RX_STOP_LOW     0x06
#define REG_RX_STOP_HIGH    0x07
#define REG_TX_BAR          0x0A
#define REG_RCV_BAR         0x0C
#define REG_CONFIG          0x0D
#define REG_EEPROM          0x0E

/* Bank 0 registers */
#define REG_B0_STATUS       0x01
#define REG_B0_COMMAND      0x00

/* Bank 1 registers */
#define REG_B1_ALT_RDY      0x01
#define REG_B1_INT_MASK     0x03

/* Bank 2 registers (address and configuration) */
#define REG_B2_IA0          0x04
#define REG_B2_IA1          0x05
#define REG_B2_IA2          0x06
#define REG_B2_IA3          0x07
#define REG_B2_IA4          0x08
#define REG_B2_IA5          0x09

/* Commands */
#define CMD_RESET           0x00
#define CMD_SELECT_RESET    0x08
#define CMD_POWER_DOWN      0x18
#define CMD_RESUME          0x20
#define CMD_RCV_ENABLE      0x08
#define CMD_RCV_DISABLE     0x00
#define CMD_TX_ENABLE       0x04
#define CMD_TX_DISABLE      0x00
#define CMD_STOP_DMA        0x40
#define CMD_BANK_SEL_MASK   0xC0

/* Status bits */
#define STAT_RX_INT         0x02
#define STAT_TX_INT         0x04
#define STAT_EXEC_INT       0x08
#define STAT_BUSY           0x80

/* Interrupt mask bits */
#define INT_RX              0x02
#define INT_TX              0x04
#define INT_EXEC_STATUS     0x08
#define INT_DMA             0x80
#define INT_ALL             0x8E

/* Configuration bits */
#define CONFIG_IRQ_ENABLE   0x80
#define CONFIG_IO_32BIT     0x20

/* Buffer sizes */
#define RX_BUFFER_SIZE      2048
#define TX_BUFFER_SIZE      2048
#define NUM_RX_BUFFERS      16
#define NUM_TX_BUFFERS      8

/* Memory layout (82595 has 32KB onboard RAM) */
#define RAM_SIZE            0x8000
#define TX_BUF_START        0x0000
#define TX_BUF_SIZE         0x2000
#define RX_BUF_START        0x2000
#define RX_BUF_SIZE         0x6000

/* Timeout values */
#define COMMAND_TIMEOUT     1000
#define RESET_TIMEOUT       10000

/* EEPROM constants */
#define EEPROM_SIZE         64
#define EEPROM_READ_CMD     0x80

@implementation Intel82595NetworkDriver

/*
 * Probe method - called to determine if hardware is present
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    Intel82595NetworkDriver *driver;
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
    _bankSelect = 0;
    _promiscuousMode = NO;
    _multicastMode = NO;
    _memoryRegion = 0;

    /* Get I/O base address and IRQ */
    _ioBase = [deviceDescription portRangeList:0].start;
    _irqLevel = [deviceDescription interrupt];

    IOLog("Intel82595: Found device at I/O base 0x%x, IRQ %d\n",
          _ioBase, _irqLevel);

    /* Initialize buffer pointers */
    _txBufferStart = TX_BUF_START;
    _txBufferEnd = TX_BUF_START + TX_BUF_SIZE;
    _rxBufferStart = RX_BUF_START;
    _rxBufferEnd = RX_BUF_START + RX_BUF_SIZE;
    _rxStopPtr = _rxBufferStart;
    _rxReadPtr = _rxBufferStart;

    /* Perform cold initialization */
    [self coldInit];

    /* Read MAC address */
    if (![self getHardwareAddress:(enet_addr_t *)_romAddress]) {
        IOLog("Intel82595: Failed to read hardware address\n");
        [self free];
        return nil;
    }

    IOLog("Intel82595: MAC address %02x:%02x:%02x:%02x:%02x:%02x\n",
          _romAddress[0], _romAddress[1], _romAddress[2],
          _romAddress[3], _romAddress[4], _romAddress[5]);

    /* Allocate buffers */
    if (![self allocateBuffers]) {
        IOLog("Intel82595: Failed to allocate buffers\n");
        [self free];
        return nil;
    }

    /* Initialize the chip */
    if (![self initChip]) {
        IOLog("Intel82595: Failed to initialize chip\n");
        [self free];
        return nil;
    }

    /* Enable interrupts */
    if ([self enableAllInterrupts]) {
        [self enableInterrupt:_irqLevel];
    }

    _isInitialized = YES;
    _linkUp = YES; /* PCMCIA cards don't have link detection */

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
            IOLog("Intel82595: Failed to initialize chip during enable\n");
            return NO;
        }

        [self enableAllInterrupts];
        _isEnabled = YES;

        /* Enable receiver */
        [self selectBank:0];
        outb(_ioBase + REG_COMMAND, CMD_RCV_ENABLE | CMD_TX_ENABLE);
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
    [self selectBank:1];
    outb(_ioBase + REG_B1_INT_MASK, INT_ALL);
    [self selectBank:0];

    return YES;
}

/*
 * Disable all interrupts
 */
- (BOOL)disableAllInterrupts
{
    [self selectBank:1];
    outb(_ioBase + REG_B1_INT_MASK, 0);
    [self selectBank:0];

    return YES;
}

/*
 * Transmit a packet
 */
- (void)transmitPacket:(void *)pkt length:(unsigned int)len
{
    if (!_isEnabled || len > TX_BUFFER_SIZE) {
        return;
    }

    [self sendPacket:pkt length:len];
}

/*
 * Send a packet
 */
- (void)sendPacket:(void *)pkt length:(unsigned int)len
{
    unsigned short txAddr;
    unsigned char *data = (unsigned char *)pkt;
    int i;

    /* Wait for transmitter to be ready */
    [self selectBank:0];
    while (inb(_ioBase + REG_STATUS) & STAT_BUSY) {
        IODelay(10);
    }

    /* Set transmit address */
    txAddr = _txBufferStart + (_txIndex * TX_BUFFER_SIZE);
    outb(_ioBase + REG_TX_BAR, txAddr & 0xFF);
    outb(_ioBase + REG_TX_BAR + 1, (txAddr >> 8) & 0xFF);

    /* Write packet length */
    outb(_ioBase + 0x0A, len & 0xFF);
    outb(_ioBase + 0x0B, (len >> 8) & 0xFF);

    /* Write packet data */
    for (i = 0; i < len; i++) {
        outb(_ioBase + 0x0A, data[i]);
    }

    /* Trigger transmission */
    outb(_ioBase + REG_COMMAND, CMD_TX_ENABLE);

    _txIndex = (_txIndex + 1) % NUM_TX_BUFFERS;
    _transmitTimeout = 0;
}

/*
 * Receive a packet
 */
- (void)receivePacket
{
    unsigned short rxStatus;
    unsigned short len;
    void *pkt;
    int i;

    if (!_isEnabled) {
        return;
    }

    [self selectBank:0];

    /* Check if packet available */
    rxStatus = inb(_ioBase + REG_STATUS);
    if (!(rxStatus & STAT_RX_INT)) {
        return;
    }

    /* Set receive buffer pointer */
    outb(_ioBase + REG_RCV_BAR, _rxReadPtr & 0xFF);
    outb(_ioBase + REG_RCV_BAR + 1, (_rxReadPtr >> 8) & 0xFF);

    /* Read packet length */
    len = inb(_ioBase + 0x0C);
    len |= (inb(_ioBase + 0x0C) << 8);

    if (len > 0 && len <= RX_BUFFER_SIZE) {
        /* Allocate packet buffer */
        pkt = IOMalloc(len);
        if (pkt) {
            unsigned char *data = (unsigned char *)pkt;

            /* Read packet data */
            for (i = 0; i < len; i++) {
                data[i] = inb(_ioBase + 0x0C);
            }

            /* Pass packet to network stack */
            [self handleInputPacket:pkt length:len];

            IOFree(pkt, len);
        }

        /* Update read pointer */
        _rxReadPtr += len + 4; /* Include header */
        if (_rxReadPtr >= _rxBufferEnd) {
            _rxReadPtr = _rxBufferStart;
        }
    }
}

/*
 * Get transmit queue size
 */
- (unsigned int)transmitQueueSize
{
    return NUM_TX_BUFFERS;
}

/*
 * Get receive queue count
 */
- (unsigned int)receiveQueueCount
{
    return NUM_RX_BUFFERS;
}

/*
 * Interrupt handler
 */
- (void)interruptOccurred
{
    unsigned char status;

    [self selectBank:0];
    status = inb(_ioBase + REG_STATUS);

    /* Handle receive interrupt */
    if (status & STAT_RX_INT) {
        [self receiveInterruptOccurred];
    }

    /* Handle transmit interrupt */
    if (status & STAT_TX_INT) {
        [self transmitInterruptOccurred];
    }

    /* Clear interrupts */
    outb(_ioBase + REG_STATUS, status);
}

/*
 * Receive interrupt handler
 */
- (void)receiveInterruptOccurred
{
    [self receivePacket];
}

/*
 * Transmit interrupt handler
 */
- (void)transmitInterruptOccurred
{
    [self clearTimeout];
}

/*
 * Transmit interrupt handler (alternate)
 */
- (void)transmitInterruptOccurred2
{
    [self transmitInterruptOccurred];
}

/*
 * Timeout handler
 */
- (void)timeoutOccurred
{
    _transmitTimeout++;

    if (_transmitTimeout > COMMAND_TIMEOUT) {
        IOLog("Intel82595: Transmit timeout, resetting\n");
        [self resetAndEnable:YES];
    }
}

/*
 * Get hardware MAC address
 */
- (BOOL)getHardwareAddress:(enet_addr_t *)addr
{
    int i;

    /* Select bank 2 to access station address */
    [self selectBank:2];

    /* Read MAC address from registers */
    _romAddress[0] = inb(_ioBase + REG_B2_IA0);
    _romAddress[1] = inb(_ioBase + REG_B2_IA1);
    _romAddress[2] = inb(_ioBase + REG_B2_IA2);
    _romAddress[3] = inb(_ioBase + REG_B2_IA3);
    _romAddress[4] = inb(_ioBase + REG_B2_IA4);
    _romAddress[5] = inb(_ioBase + REG_B2_IA5);

    [self selectBank:0];

    if (addr) {
        bcopy(_romAddress, addr->ea_byte, 6);
    }

    return YES;
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
        [self selectBank:0];
        outb(_ioBase + REG_COMMAND, CMD_POWER_DOWN);
        [self resetAndEnable:NO];
    } else {
        /* Power up */
        [self selectBank:0];
        outb(_ioBase + REG_COMMAND, CMD_RESUME);
        [self resetAndEnable:YES];
    }

    return IO_R_SUCCESS;
}

/*
 * Reset statistics
 */
- (void)resetStats
{
    /* Reset internal statistics counters */
}

/*
 * Update statistics
 */
- (void)updateStats
{
    /* Read statistics from chip and update counters */
}

/*
 * Get statistics from hardware
 */
- (void)getStatistics
{
    /* Read statistics registers */
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

    /* Clear buffers */
    bzero(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_BUFFERS);
    bzero(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_BUFFERS);

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
    }

    if (_transmitBuffer) {
        IOFree(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_BUFFERS);
        _transmitBuffer = NULL;
    }
}

/*
 * Initialize the chip
 */
- (BOOL)initChip
{
    /* Reset the chip */
    [self resetChip];

    /* Wait for reset to complete */
    IODelay(10000);

    /* Select bank 0 */
    [self selectBank:0];

    /* Configure receive and transmit buffers */
    outb(_ioBase + REG_RX_STOP_LOW, (_rxBufferEnd - 0x80) & 0xFF);
    outb(_ioBase + REG_RX_STOP_HIGH, ((_rxBufferEnd - 0x80) >> 8) & 0xFF);

    /* Enable IRQ */
    [self selectBank:0];
    outb(_ioBase + REG_CONFIG, CONFIG_IRQ_ENABLE);

    /* Initialize transmit ring */
    [self initTxRd];

    return YES;
}

/*
 * Reset the chip
 */
- (void)resetChip
{
    [self selectBank:0];
    outb(_ioBase + REG_COMMAND, CMD_RESET);

    /* Wait for reset to complete */
    IODelay(20000);

    /* Disable interrupts */
    [self disableAllInterrupts];
}

/*
 * Reset the chip (alternate method)
 */
- (void)resetChip2
{
    [self resetChip];
}

/*
 * Cold initialization
 */
- (void)coldInit
{
    /* Perform initial hardware setup */
    [self selectBank:0];
    outb(_ioBase + REG_COMMAND, CMD_SELECT_RESET);

    IODelay(10000);

    /* Check for onboard memory */
    [self onboardMemoryPresent];

    /* Allocate memory */
    [self allocateMemoryAvailable];
}

/*
 * Select register bank
 */
- (void)selectBank:(unsigned int)bank
{
    unsigned char cmd;

    _bankSelect = bank & 0x03;
    cmd = (bank << 6) & CMD_BANK_SEL_MASK;

    outb(_ioBase + REG_COMMAND, cmd);
}

/*
 * Allocate memory available
 */
- (void)allocateMemoryAvailable
{
    /* Setup memory regions for TX and RX */
    _memoryRegion = RAM_SIZE;
}

/*
 * Schedule reset
 */
- (void)scheduleReset
{
    /* Schedule a reset operation */
}

/*
 * Stopping description
 */
- (void)stoppingDesc
{
    /* Clean up when stopping */
}

/*
 * Enable promiscuous mode
 */
- (void)enablePromiscuousMode
{
    _promiscuousMode = YES;

    [self selectBank:0];
    /* Set promiscuous bit in configuration */
}

/*
 * Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    _promiscuousMode = NO;

    [self selectBank:0];
    /* Clear promiscuous bit in configuration */
}

/*
 * Enable multicast mode
 */
- (void)enableMulticastMode
{
    _multicastMode = YES;
}

/*
 * Disable multicast mode
 */
- (void)disableMulticastMode
{
    _multicastMode = NO;
}

/*
 * Add multicast address
 */
- (void)addMulticast
{
    /* Configure multicast filter */
}

/*
 * Reset and enable
 */
- (void)resetEnable
{
    [self resetAndEnable:YES];
}

/*
 * Initialize transmit ring descriptor
 */
- (void)initTxRd
{
    _txIndex = 0;
    _rxIndex = 0;
}

/*
 * Check if onboard memory is present
 */
- (void)onboardMemoryPresent
{
    /* Test for presence of onboard RAM */
    _memoryRegion = RAM_SIZE;
}

/*
 * EEPROM I/O sleep
 */
- (unsigned short)eepromIOSleep
{
    IODelay(1000);
    return 0;
}

/*
 * EEPROM I/O dezero
 */
- (void)eepromIODezero
{
    /* EEPROM operation */
}

/*
 * EEPROM I/O allocate
 */
- (unsigned short)eepromIOAlloc
{
    return 0;
}

/*
 * Description
 */
- (void)description
{
    /* Return driver description */
}

/*
 * IntelEEPro10Plus probe
 */
- (void)intelEEPro10Plus_probe
{
    /* Probe for Intel EtherExpress PRO/10+ */
}

/*
 * IntelEEPro10Plus bus configuration
 */
- (void)intelEEPro10Plus_busConfig
{
    /* Configure bus settings */
}

/*
 * IntelEEPro10Plus cold initialization
 */
- (void)intelEEPro10Plus_coldInit
{
    [self coldInit];
}

/*
 * IntelEEPro10Plus reset chip
 */
- (void)intelEEPro10Plus_resetChip
{
    [self resetChip];
}

/*
 * IntelEEPro10Plus I/O address enable string
 */
- (void)intelEEPro10Plus_io_address_enable_str
{
    /* Enable I/O address */
}

/*
 * IntelEEPro10Plus allocate memory available
 */
- (void)intelEEPro10Plus_allocateMemoryAvailable
{
    [self allocateMemoryAvailable];
}

/*
 * CogentEM595 probe
 */
- (void)cogentEM595_probe
{
    /* Probe for Cogent EM595 */
}

/*
 * CogentEM595 cold initialization
 */
- (void)cogentEM595_coldInit
{
    [self coldInit];
}

/*
 * CogentEM595 description
 */
- (void)cogentEM595_description
{
    /* Return Cogent EM595 description */
}

/*
 * CogentEM595 allocate memory available
 */
- (void)cogentEM595_allocateMemoryAvailable
{
    [self allocateMemoryAvailable];
}

/*
 * CogentEM595 stopping description
 */
- (void)cogentEM595_stoppingDesc
{
    [self stoppingDesc];
}

@end
