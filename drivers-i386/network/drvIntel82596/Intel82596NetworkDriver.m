/*
 * Intel82596NetworkDriver.m
 * Intel 82596 EISA Ethernet Adapter Driver (Cogent EM935)
 */

#import "Intel82596NetworkDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/align.h>
#import <mach/mach_interface.h>
#import <string.h>

/* Intel 82596 Command and Status Block offsets */
#define SCB_STATUS          0x00
#define SCB_COMMAND         0x02
#define SCB_CMD_LIST        0x04
#define SCB_RFD_LIST        0x08
#define SCB_CRC_ERRORS      0x0C
#define SCB_ALIGN_ERRORS    0x0E
#define SCB_RESOURCE_ERRORS 0x10
#define SCB_OVERRUN_ERRORS  0x12

/* SCB Command Unit Commands */
#define CUC_NOP             0x0000
#define CUC_START           0x0100
#define CUC_RESUME          0x0200
#define CUC_SUSPEND         0x0300
#define CUC_ABORT           0x0400

/* SCB Receive Unit Commands */
#define RUC_NOP             0x0000
#define RUC_START           0x0010
#define RUC_RESUME          0x0020
#define RUC_SUSPEND         0x0030
#define RUC_ABORT           0x0040

/* SCB Status Bits */
#define SCB_STAT_CX         0x8000  /* Command with I bit complete */
#define SCB_STAT_FR         0x4000  /* Frame received */
#define SCB_STAT_CNA        0x2000  /* Command unit not active */
#define SCB_STAT_RNR        0x1000  /* Receive unit not ready */

/* SCB Command Acknowledge Bits */
#define SCB_ACK_CX          0x8000
#define SCB_ACK_FR          0x4000
#define SCB_ACK_CNA         0x2000
#define SCB_ACK_RNR         0x1000

/* Action Commands */
#define CMD_NOP             0x0000
#define CMD_IA_SETUP        0x0001
#define CMD_CONFIGURE       0x0002
#define CMD_MC_SETUP        0x0003
#define CMD_TRANSMIT        0x0004
#define CMD_TDR             0x0005
#define CMD_DUMP            0x0006
#define CMD_DIAGNOSE        0x0007

/* Command Status Bits */
#define CMD_STAT_C          0x8000  /* Command complete */
#define CMD_STAT_B          0x4000  /* Command busy */
#define CMD_STAT_OK         0x2000  /* Command OK */
#define CMD_STAT_A          0x1000  /* Command aborted */

/* Command Control Bits */
#define CMD_EL              0x8000  /* End of list */
#define CMD_S               0x4000  /* Suspend */
#define CMD_I               0x2000  /* Interrupt */

/* System Configuration Pointer */
#define SCP_SYSBUS          0x00
#define SCP_ISCP_ADDR       0x08

/* Intermediate System Configuration Pointer */
#define ISCP_BUSY           0x00
#define ISCP_SCB_OFFSET     0x02
#define ISCP_SCB_BASE       0x04

/* Buffer sizes */
#define RX_BUFFER_SIZE      2048
#define TX_BUFFER_SIZE      2048
#define NUM_RX_BUFFERS      32
#define NUM_TX_BUFFERS      16
#define CMD_BLOCK_SIZE      128

/* 82596 structure sizes */
#define SCP_SIZE            16
#define ISCP_SIZE           16
#define SCB_SIZE            32
#define RFD_SIZE            64
#define RBD_SIZE            16
#define TBD_SIZE            16

/* Timeout values */
#define COMMAND_TIMEOUT     1000
#define RESET_TIMEOUT       10000

/* Channel Attention */
#define CHANNEL_ATTENTION   0x01

@implementation Intel82596NetworkDriver

/*
 * Probe method - called to determine if hardware is present
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    Intel82596NetworkDriver *driver;
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
    IOEISADeviceDescription *eisaDevice;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    _deviceDescription = deviceDescription;
    _isInitialized = NO;
    _isEnabled = NO;
    _linkUp = NO;
    _rxIndex = 0;
    _txIndex = 0;
    _cmdIndex = 0;
    _rfdIndex = 0;
    _transmitTimeout = 0;
    _receiveBuffer = NULL;
    _transmitBuffer = NULL;
    _scbBase = NULL;
    _iscp = NULL;
    _scp = NULL;
    _cmdList = NULL;
    _rfdList = NULL;
    _rbdList = NULL;
    _tbd = NULL;
    _promiscuousMode = NO;
    _multicastCount = 0;

    /* Get EISA device information */
    if ([deviceDescription isKindOf:[IOEISADeviceDescription class]]) {
        eisaDevice = (IOEISADeviceDescription *)deviceDescription;

        /* Get I/O base address and IRQ */
        _ioBase = [eisaDevice portRangeList:0].start;
        _irqLevel = [eisaDevice interrupt];
        _memBase = (void *)[eisaDevice memoryRangeList:0].start;

        IOLog("Intel82596: Found device at I/O base 0x%x, IRQ %d\n",
              _ioBase, _irqLevel);
    } else {
        IOLog("Intel82596: Invalid device description\n");
        [self free];
        return nil;
    }

    /* Perform cold initialization */
    [self coldInit];

    /* Read MAC address */
    if (![self getHardwareAddress:(enet_addr_t *)_romAddress]) {
        IOLog("Intel82596: Failed to read hardware address\n");
        [self free];
        return nil;
    }

    IOLog("Intel82596: MAC address %02x:%02x:%02x:%02x:%02x:%02x\n",
          _romAddress[0], _romAddress[1], _romAddress[2],
          _romAddress[3], _romAddress[4], _romAddress[5]);

    /* Allocate buffers */
    if (![self allocateBuffers]) {
        IOLog("Intel82596: Failed to allocate buffers\n");
        [self free];
        return nil;
    }

    /* Initialize the chip */
    if (![self initChip]) {
        IOLog("Intel82596: Failed to initialize chip\n");
        [self free];
        return nil;
    }

    /* Enable interrupts */
    if ([self enableAllInterrupts]) {
        [self enableInterrupt:_irqLevel];
    }

    _isInitialized = YES;
    _linkUp = YES;

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
            IOLog("Intel82596: Failed to initialize chip during enable\n");
            return NO;
        }

        [self enableAllInterrupts];
        _isEnabled = YES;

        /* Start receive unit */
        *(unsigned short *)(_scbBase + SCB_COMMAND) = RUC_START;
        [self cogentEMaster_sendChannelAttention];
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
    /* 82596 interrupts are always enabled, controlled by SCB */
    return YES;
}

/*
 * Disable all interrupts
 */
- (BOOL)disableAllInterrupts
{
    /* Mask interrupts by suspending command and receive units */
    *(unsigned short *)(_scbBase + SCB_COMMAND) = CUC_SUSPEND | RUC_SUSPEND;
    [self cogentEMaster_sendChannelAttention];

    return YES;
}

/*
 * Enable all interrupts (alternate)
 */
- (void)enableAllInterrupts2
{
    [self enableAllInterrupts];
}

/*
 * Disable all interrupts (alternate)
 */
- (void)disableAllInterrupts2
{
    [self disableAllInterrupts];
}

/*
 * Transmit a packet
 */
- (void)transmitPacket:(void *)pkt length:(unsigned int)len
{
    unsigned char *txBuf;
    void *tbd;
    void *cmd;

    if (!_isEnabled || len > TX_BUFFER_SIZE) {
        return;
    }

    txBuf = (unsigned char *)_transmitBuffer + (_txIndex * TX_BUFFER_SIZE);

    /* Copy packet to transmit buffer */
    bcopy(pkt, txBuf, len);

    /* Setup transmit buffer descriptor */
    tbd = (unsigned char *)_tbd + (_txIndex * TBD_SIZE);
    *(unsigned short *)(tbd + 0) = 0xFFFF;  /* Count and EOF */
    *(unsigned int *)(tbd + 4) = (unsigned int)txBuf;
    *(unsigned short *)(tbd + 8) = len | 0x8000;  /* Length with EOF */

    /* Setup transmit command */
    cmd = (unsigned char *)_cmdList + (_cmdIndex * CMD_BLOCK_SIZE);
    *(unsigned short *)(cmd + 0) = 0;  /* Status */
    *(unsigned short *)(cmd + 2) = CMD_TRANSMIT | CMD_EL | CMD_I;  /* Command */
    *(unsigned int *)(cmd + 4) = 0xFFFFFFFF;  /* Link (end of list) */
    *(unsigned int *)(cmd + 8) = (unsigned int)tbd;  /* TBD pointer */

    /* Start transmit */
    [self transmit];

    _txIndex = (_txIndex + 1) % NUM_TX_BUFFERS;
    _cmdIndex = (_cmdIndex + 1) % NUM_TX_BUFFERS;
}

/*
 * Transmit
 */
- (void)transmit
{
    [self waitScb];

    /* Start command unit */
    *(unsigned short *)(_scbBase + SCB_COMMAND) = CUC_START;
    *(unsigned int *)(_scbBase + SCB_CMD_LIST) = (unsigned int)_cmdList;

    [self cogentEMaster_sendChannelAttention];

    _transmitTimeout = 0;
}

/*
 * Receive a packet
 */
- (void)receivePacket
{
    unsigned char *rxBuf;
    void *rfd;
    unsigned short status;
    unsigned short count;
    void *pkt;

    if (!_isEnabled) {
        return;
    }

    rfd = (unsigned char *)_rfdList + (_rfdIndex * RFD_SIZE);

    /* Check status */
    status = *(unsigned short *)(rfd + 0);

    if (status & CMD_STAT_C) {
        /* Frame received */
        count = *(unsigned short *)(rfd + 12);
        count &= 0x3FFF;  /* Mask off control bits */

        if (count > 0 && count <= RX_BUFFER_SIZE) {
            rxBuf = (unsigned char *)_receiveBuffer + (_rfdIndex * RX_BUFFER_SIZE);

            /* Allocate packet buffer */
            pkt = IOMalloc(count);
            if (pkt) {
                bcopy(rxBuf, pkt, count);

                /* Pass packet to network stack */
                [self handleInputPacket:pkt length:count];

                IOFree(pkt, count);
            }
        }

        /* Reset RFD */
        *(unsigned short *)(rfd + 0) = 0;
        *(unsigned short *)(rfd + 2) = 0;

        _rfdIndex = (_rfdIndex + 1) % NUM_RX_BUFFERS;
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
 * Interrupt handler
 */
- (void)interruptOccurred
{
    unsigned short status;

    /* Clear IRQ latch */
    [self cogentEMaster_clearIrqLatch];

    /* Read SCB status */
    status = *(unsigned short *)(_scbBase + SCB_STATUS);

    /* Handle command complete */
    if (status & SCB_STAT_CX) {
        [self processCmdInterrupt];
    }

    /* Handle frame received */
    if (status & SCB_STAT_FR) {
        [self processRecInterrupt];
    }

    /* Handle command unit not active */
    if (status & SCB_STAT_CNA) {
        [self clearTimeout];
    }

    /* Handle receive unit not ready */
    if (status & SCB_STAT_RNR) {
        /* Restart receive unit */
        [self waitScb];
        *(unsigned short *)(_scbBase + SCB_COMMAND) = RUC_START;
        [self cogentEMaster_sendChannelAttention];
    }

    /* Acknowledge interrupts */
    [self acknowledgeInterrupts];
}

/*
 * Process receive interrupt
 */
- (void)processRecInterrupt
{
    [self receivePacket];
}

/*
 * Process command interrupt
 */
- (void)processCmdInterrupt
{
    [self clearTimeout];
}

/*
 * Acknowledge interrupts
 */
- (void)acknowledgeInterrupts
{
    unsigned short status;

    status = *(unsigned short *)(_scbBase + SCB_STATUS);

    /* Acknowledge by writing status bits back */
    *(unsigned short *)(_scbBase + SCB_COMMAND) = status & 0xF000;

    [self cogentEMaster_sendChannelAttention];
}

/*
 * Timeout handler
 */
- (void)timeoutOccurred
{
    _transmitTimeout++;

    if (_transmitTimeout > COMMAND_TIMEOUT) {
        IOLog("Intel82596: Transmit timeout, resetting\n");
        [self scheduleReset];
    }
}

/*
 * Timeout handler (alternate)
 */
- (void)timeoutOccurred2
{
    [self timeoutOccurred];
}

/*
 * Get hardware MAC address
 */
- (BOOL)getHardwareAddress:(enet_addr_t *)addr
{
    unsigned char *romBase;
    int i;

    /* Read MAC address from ROM at memory base */
    if (_memBase) {
        romBase = (unsigned char *)_memBase;

        for (i = 0; i < 6; i++) {
            _romAddress[i] = romBase[i * 2];
        }
    } else {
        /* Default MAC address if ROM not accessible */
        _romAddress[0] = 0x00;
        _romAddress[1] = 0x00;
        _romAddress[2] = 0xC0;
        _romAddress[3] = 0x00;
        _romAddress[4] = 0x00;
        _romAddress[5] = 0x01;
    }

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
    /* Reset internal statistics counters */
}

/*
 * Update statistics
 */
- (void)updateStats
{
    /* Read statistics from SCB */
}

/*
 * Allocate DMA buffers and 82596 structures
 */
- (BOOL)allocateBuffers
{
    /* Allocate System Configuration Pointer */
    _scp = IOMalloc(SCP_SIZE);
    if (!_scp) {
        return NO;
    }

    /* Allocate Intermediate System Configuration Pointer */
    _iscp = IOMalloc(ISCP_SIZE);
    if (!_iscp) {
        IOFree(_scp, SCP_SIZE);
        _scp = NULL;
        return NO;
    }

    /* Allocate System Configuration Block */
    _scbBase = IOMalloc(SCB_SIZE);
    if (!_scbBase) {
        IOFree(_scp, SCP_SIZE);
        IOFree(_iscp, ISCP_SIZE);
        _scp = NULL;
        _iscp = NULL;
        return NO;
    }

    /* Allocate command list */
    _cmdList = IOMalloc(CMD_BLOCK_SIZE * NUM_TX_BUFFERS);
    if (!_cmdList) {
        IOFree(_scp, SCP_SIZE);
        IOFree(_iscp, ISCP_SIZE);
        IOFree(_scbBase, SCB_SIZE);
        _scp = NULL;
        _iscp = NULL;
        _scbBase = NULL;
        return NO;
    }

    /* Allocate RFD list */
    _rfdList = IOMalloc(RFD_SIZE * NUM_RX_BUFFERS);
    if (!_rfdList) {
        IOFree(_scp, SCP_SIZE);
        IOFree(_iscp, ISCP_SIZE);
        IOFree(_scbBase, SCB_SIZE);
        IOFree(_cmdList, CMD_BLOCK_SIZE * NUM_TX_BUFFERS);
        _scp = NULL;
        _iscp = NULL;
        _scbBase = NULL;
        _cmdList = NULL;
        return NO;
    }

    /* Allocate RBD list */
    _rbdList = IOMalloc(RBD_SIZE * NUM_RX_BUFFERS);
    if (!_rbdList) {
        IOFree(_scp, SCP_SIZE);
        IOFree(_iscp, ISCP_SIZE);
        IOFree(_scbBase, SCB_SIZE);
        IOFree(_cmdList, CMD_BLOCK_SIZE * NUM_TX_BUFFERS);
        IOFree(_rfdList, RFD_SIZE * NUM_RX_BUFFERS);
        _scp = NULL;
        _iscp = NULL;
        _scbBase = NULL;
        _cmdList = NULL;
        _rfdList = NULL;
        return NO;
    }

    /* Allocate TBD */
    _tbd = IOMalloc(TBD_SIZE * NUM_TX_BUFFERS);
    if (!_tbd) {
        IOFree(_scp, SCP_SIZE);
        IOFree(_iscp, ISCP_SIZE);
        IOFree(_scbBase, SCB_SIZE);
        IOFree(_cmdList, CMD_BLOCK_SIZE * NUM_TX_BUFFERS);
        IOFree(_rfdList, RFD_SIZE * NUM_RX_BUFFERS);
        IOFree(_rbdList, RBD_SIZE * NUM_RX_BUFFERS);
        _scp = NULL;
        _iscp = NULL;
        _scbBase = NULL;
        _cmdList = NULL;
        _rfdList = NULL;
        _rbdList = NULL;
        return NO;
    }

    /* Allocate receive buffer */
    _receiveBuffer = IOMalloc(RX_BUFFER_SIZE * NUM_RX_BUFFERS);
    if (!_receiveBuffer) {
        [self freeBuffers];
        return NO;
    }

    /* Allocate transmit buffer */
    _transmitBuffer = IOMalloc(TX_BUFFER_SIZE * NUM_TX_BUFFERS);
    if (!_transmitBuffer) {
        [self freeBuffers];
        return NO;
    }

    /* Clear all buffers */
    bzero(_scp, SCP_SIZE);
    bzero(_iscp, ISCP_SIZE);
    bzero(_scbBase, SCB_SIZE);
    bzero(_cmdList, CMD_BLOCK_SIZE * NUM_TX_BUFFERS);
    bzero(_rfdList, RFD_SIZE * NUM_RX_BUFFERS);
    bzero(_rbdList, RBD_SIZE * NUM_RX_BUFFERS);
    bzero(_tbd, TBD_SIZE * NUM_TX_BUFFERS);
    bzero(_receiveBuffer, RX_BUFFER_SIZE * NUM_RX_BUFFERS);
    bzero(_transmitBuffer, TX_BUFFER_SIZE * NUM_TX_BUFFERS);

    return YES;
}

/*
 * Free DMA buffers
 */
- (void)freeBuffers
{
    if (_scp) {
        IOFree(_scp, SCP_SIZE);
        _scp = NULL;
    }

    if (_iscp) {
        IOFree(_iscp, ISCP_SIZE);
        _iscp = NULL;
    }

    if (_scbBase) {
        IOFree(_scbBase, SCB_SIZE);
        _scbBase = NULL;
    }

    if (_cmdList) {
        IOFree(_cmdList, CMD_BLOCK_SIZE * NUM_TX_BUFFERS);
        _cmdList = NULL;
    }

    if (_rfdList) {
        IOFree(_rfdList, RFD_SIZE * NUM_RX_BUFFERS);
        _rfdList = NULL;
    }

    if (_rbdList) {
        IOFree(_rbdList, RBD_SIZE * NUM_RX_BUFFERS);
        _rbdList = NULL;
    }

    if (_tbd) {
        IOFree(_tbd, TBD_SIZE * NUM_TX_BUFFERS);
        _tbd = NULL;
    }

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
    int i;
    void *rfd, *rbd;

    /* Reset the chip */
    [self resetChip];

    /* Wait for reset to complete */
    IODelay(10000);

    /* Setup System Configuration Pointer */
    *(unsigned int *)(_scp + SCP_SYSBUS) = 0x00440000;  /* 32-bit mode */
    *(unsigned int *)(_scp + SCP_ISCP_ADDR) = (unsigned int)_iscp;

    /* Setup Intermediate System Configuration Pointer */
    *(unsigned short *)(_iscp + ISCP_BUSY) = 1;
    *(unsigned short *)(_iscp + ISCP_SCB_OFFSET) = 0;
    *(unsigned int *)(_iscp + ISCP_SCB_BASE) = (unsigned int)_scbBase;

    /* Write SCP address to chip */
    outl(_ioBase + 0, (unsigned int)_scp);

    /* Issue channel attention */
    [self cogentEMaster_sendChannelAttention];

    /* Wait for initialization */
    IODelay(10000);

    /* Initialize receive frame descriptors */
    [self initRxRd];

    /* Initialize transmit descriptors */
    [self initTxRd];

    /* Configure the chip */
    [self polledCommand:_cmdList];

    return YES;
}

/*
 * Reset the chip
 */
- (void)resetChip
{
    /* Issue reset to port */
    outl(_ioBase + 0, 0);

    /* Wait for reset to complete */
    IODelay(20000);
}

/*
 * Cold initialization
 */
- (void)coldInit
{
    /* Perform initial hardware setup */
}

/*
 * Wait for SCB to be ready
 */
- (void)waitScb
{
    int timeout = COMMAND_TIMEOUT;
    unsigned short cmd;

    while (timeout-- > 0) {
        cmd = *(unsigned short *)(_scbBase + SCB_COMMAND);
        if (cmd == 0) {
            return;
        }
        IODelay(10);
    }
}

/*
 * Execute a polled command
 */
- (int)polledCommand:(void *)cmd
{
    int timeout = COMMAND_TIMEOUT;

    [self waitScb];

    /* Start command */
    *(unsigned short *)(_scbBase + SCB_COMMAND) = CUC_START;
    *(unsigned int *)(_scbBase + SCB_CMD_LIST) = (unsigned int)cmd;

    [self cogentEMaster_sendChannelAttention];

    /* Wait for completion */
    while (timeout-- > 0) {
        if (*(unsigned short *)cmd & CMD_STAT_C) {
            return 0;
        }
        IODelay(10);
    }

    return -1;
}

/*
 * Start command unit
 */
- (void)startCommandUnit
{
    [self waitScb];

    *(unsigned short *)(_scbBase + SCB_COMMAND) = CUC_START;
    [self cogentEMaster_sendChannelAttention];
}

/*
 * Schedule reset
 */
- (void)scheduleReset
{
    [self resetAndEnable:YES];
}

/*
 * Initialize receive ring descriptors
 */
- (void)initRxRd
{
    int i;
    void *rfd, *rbd;
    unsigned char *rxBuf;

    for (i = 0; i < NUM_RX_BUFFERS; i++) {
        rfd = (unsigned char *)_rfdList + (i * RFD_SIZE);
        rbd = (unsigned char *)_rbdList + (i * RBD_SIZE);
        rxBuf = (unsigned char *)_receiveBuffer + (i * RX_BUFFER_SIZE);

        /* Setup RFD */
        *(unsigned short *)(rfd + 0) = 0;  /* Status */
        *(unsigned short *)(rfd + 2) = 0;  /* Command */

        if (i == NUM_RX_BUFFERS - 1) {
            *(unsigned int *)(rfd + 4) = (unsigned int)_rfdList;  /* Link to first */
            *(unsigned short *)(rfd + 2) = CMD_EL;  /* End of list */
        } else {
            *(unsigned int *)(rfd + 4) = (unsigned int)((unsigned char *)_rfdList + ((i + 1) * RFD_SIZE));
        }

        *(unsigned int *)(rfd + 8) = (unsigned int)rbd;  /* RBD pointer */

        /* Setup RBD */
        *(unsigned short *)(rbd + 0) = 0;  /* Count */
        *(unsigned int *)(rbd + 4) = (unsigned int)rxBuf;
        *(unsigned short *)(rbd + 8) = RX_BUFFER_SIZE | 0x8000;  /* Size with EOF */

        if (i == NUM_RX_BUFFERS - 1) {
            *(unsigned int *)(rbd + 12) = 0xFFFFFFFF;  /* End of list */
        } else {
            *(unsigned int *)(rbd + 12) = (unsigned int)((unsigned char *)_rbdList + ((i + 1) * RBD_SIZE));
        }
    }

    /* Set RFD list pointer in SCB */
    *(unsigned int *)(_scbBase + SCB_RFD_LIST) = (unsigned int)_rfdList;
}

/*
 * Initialize transmit ring descriptors
 */
- (void)initTxRd
{
    _txIndex = 0;
    _cmdIndex = 0;
}

/*
 * Service receive interrupt
 */
- (void)serviceRxInt
{
    [self receivePacket];
}

/*
 * Bottom half receive interrupt
 */
- (void)botRxReceiveInt
{
    [self serviceRxInt];
}

/*
 * Service transmit queue
 */
- (void)serviceTransmitQueue
{
    /* Service pending transmit requests */
}

/*
 * Enable promiscuous mode
 */
- (void)enablePromiscuousMode
{
    _promiscuousMode = YES;
}

/*
 * Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    _promiscuousMode = NO;
}

/*
 * Network buffer wrapper functions
 */
- (void)nb_alloc_wrapper { }
- (void)nb_free { }
- (void)nb_map { }
- (void)nb_shrink_bot { }
- (void)nb_size { }
- (void)nb_timeout { }
- (void)nb_msgSend { }
- (void)msgSendSuper_page_mask_page_size { }

/*
 * CogentEMaster clear IRQ latch
 */
- (void)cogentEMaster_clearIrqLatch
{
    /* Clear interrupt latch on Cogent board */
    if (_ioBase) {
        inb(_ioBase + 4);
    }
}

/*
 * CogentEMaster send channel attention
 */
- (void)cogentEMaster_sendChannelAttention
{
    /* Send channel attention signal */
    if (_ioBase) {
        outb(_ioBase + 0, CHANNEL_ATTENTION);
    }
}

/*
 * IntelEEFlash32 methods
 */
- (void)intelEEFlash32_probe { }
- (void)intelEEFlash32_initFromDeviceDescription { }
- (void)intelEEFlash32_clearIrqLatch { [self cogentEMaster_clearIrqLatch]; }
- (void)intelEEFlash32_sendChannelAttention { [self cogentEMaster_sendChannelAttention]; }
- (void)intelEEFlash32_interruptOccurred { [self interruptOccurred]; }

/*
 * IntelPRO10PCI methods
 */
- (void)intelPRO10PCI_probe { }
- (void)intelPRO10PCI_setConnectorType { }
- (void)intelPRO10PCI_getConnectorType { }
- (void)intelPRO10PCI_initFromDeviceDescription { }
- (void)intelPRO10PCI_clearIrqLatch { [self cogentEMaster_clearIrqLatch]; }
- (void)intelPRO10PCI_initChip { [self initChip]; }
- (void)intelPRO10PCI_resetChip { [self resetChip]; }
- (void)intelPRO10PCI_enableAdapterInterrupts { [self enableAllInterrupts]; }
- (void)intelPRO10PCI_disableAdapterInterrupts { [self disableAllInterrupts]; }
- (void)intelPRO10PCI_resetEnable { [self resetAndEnable:YES]; }

/*
 * Description
 */
- (void)description
{
    /* Return driver description */
}

@end
