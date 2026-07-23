/*
 * Intel82556.h
 * Intel EtherExpress PRO/100 Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODirectDevice.h>

/* Intel 82556 Register Offsets */
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
#define RU_LOAD_HDS         0x0005
#define RU_LOAD_RU_BASE     0x0006

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

/* Action Command Opcodes */
#define CB_CMD_NOP          0x0000
#define CB_CMD_IA_SETUP     0x0001
#define CB_CMD_CONFIG       0x0002
#define CB_CMD_MC_SETUP     0x0003
#define CB_CMD_TRANSMIT     0x0004
#define CB_CMD_LOAD_UCODE   0x0005
#define CB_CMD_DUMP         0x0006
#define CB_CMD_DIAGNOSE     0x0007

/* Buffer sizes */
#define RX_BUFFER_SIZE      2048
#define TX_BUFFER_SIZE      2048
#define NUM_RX_BUFFERS      32
#define NUM_TX_BUFFERS      16

/* Timeout values */
#define COMMAND_TIMEOUT     1000
#define RESET_TIMEOUT       10000

/* Forward declarations */
@class Intel82556Buf;

/* Main base class */
@interface Intel82556 : IOEthernetDriver
{
    /* Hardware configuration */
    unsigned int ioBase;
    unsigned int irq;
    void *memBase;
    enet_addr_t stationAddress;

    /* Instance state flags */
    BOOL isRunning;
    BOOL isPromiscuous;
    BOOL isMulticast;
    BOOL interruptDisabled;

    /* Network interface */
    id networkInterface;

    /* Statistics */
    unsigned int txErrors;
    unsigned int txCollisions;
    unsigned int txSuccess;
    unsigned int rxErrors;

    /* Buffer management */
    Intel82556Buf *netbufPool;

    /* Transmit/Receive state */
    unsigned int txIndex;
    unsigned int rxIndex;

    /* Power management */
    unsigned int powerState;
}

/* Class Methods */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/* Initialization Methods */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)free;
- (void)clearTimeout;

/* Hardware Initialization */
- (BOOL)hwInit;
- (BOOL)swInit;
- (BOOL)coldInit;

/* Configuration */
- (BOOL)config;
- (BOOL)iaSetup;
- (BOOL)mcSetup;

/* Promiscuous and Multicast Mode Control */
- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;
- (void)addMulticastAddress:(enet_addr_t *)addr;
- (void)removeMulticastAddress:(enet_addr_t *)addr;

/* Interrupt Management */
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)enableAdapterInterrupts;
- (void)disableAdapterInterrupts;
- (void)clearIrqLatch;
- (BOOL)acknowledgeInterrupts:(unsigned short)mask;

/* Interrupt Handlers */
- (BOOL)transmitInterruptOccurred;
- (BOOL)receiveInterruptOccurred:(unsigned int)arg;

/* Transmit Methods */
- (void)transmit:(netbuf_t)packet;
- (unsigned int)transmitQueueSize;
- (unsigned int)transmitQueueCount;
- (unsigned int)sendPacket:(void *)data length:(unsigned int)len;
- (void)serviceTransmitQueue;

/* Receive Methods */
- (unsigned int)receivePacket:(void *)data length:(unsigned int)maxlen timeout:(unsigned int)timeout;
- (netbuf_t)allocateNetbuf;

/* Power Management */
- (IOReturn)getPowerManagement:(void *)powerManagement;
- (IOReturn)getPowerState:(void *)powerState;
- (IOReturn)setPowerManagement:(unsigned int)powerLevel;
- (IOReturn)setPowerState:(unsigned int)powerState;

/* Hardware Control */
- (void)sendChannelAttention;
- (int)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg;
- (BOOL)getEthernetAddress;
- (BOOL)nop:(unsigned int)timeout;
- (BOOL)dump:(void *)buffer;
- (BOOL)setThrottleTimers;

/* Command/Status */
- (BOOL)lockDBRT;
- (void)initPLXchip;
- (void)resetPLXchip;

@end

/* Private Category - Internal Implementation */
@interface Intel82556(Intel82556Private)
- (BOOL)__hwInit;
- (BOOL)__selfTest;
- (void)__scheduleReset;
- (BOOL)__waitScb;
- (BOOL)__waitCu:(unsigned int)timeout;
- (void *)__memAlloc:(unsigned int)size;
- (BOOL)__initTcbList;
- (BOOL)__initRfdList;
- (BOOL)__startTransmit;
- (void)__transmitPacket:(netbuf_t)packet;
- (BOOL)__startReceiveUnit;
- (BOOL)__abortReceiveUnit;
- (netbuf_t)__recAllocateNetbuf;
@end

/* Buffer Management Class */
@interface Intel82556Buf : Object
{
    void *bufferBase;
    unsigned int bufferSize;
    unsigned int bufferCount;
    unsigned int freeCount;
    unsigned int requestedSize;
    unsigned int actualSize;
}

/* Initialization */
- initWithRequestedSize:(unsigned int)reqSize
             actualSize:(unsigned int *)actSize
                  count:(unsigned int)count;
- (void)free;

/* Buffer Operations */
- (void *)getNetBuffer;
- (unsigned int)numFree;

@end

/* EISA Bus Variant */
@interface IntelPRO100EISA : Intel82556
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/* EISA-specific methods */
- (void)clearIrqLatch;
- (void)enableAdapterInterrupts;
- (void)disableAdapterInterrupts;
- (void)sendChannelAttention;
- (int)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg;
- (BOOL)getEthernetAddress;
- (BOOL)lockDBRT;
- (void)initPLXchip;
- (void)resetPLXchip;
- (void)interruptOccurred;
@end

/* PCI Bus Variant */
@interface IntelPRO100PCI : Intel82556
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/* PCI-specific methods */
- (void)clearIrqLatch;
- (void)enableAdapterInterrupts;
- (void)disableAdapterInterrupts;
- (void)sendChannelAttention;
- (int)sendPortCommand:(unsigned int)cmd with:(unsigned int)arg;
- (BOOL)lockDBRT;
- (void)initPLXchip;
- (void)resetPLXchip;
- (void)interruptOccurred;
@end
