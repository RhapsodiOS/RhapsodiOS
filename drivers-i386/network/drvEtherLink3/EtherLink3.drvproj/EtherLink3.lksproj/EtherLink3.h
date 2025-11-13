/*
 * EtherLink3.h
 * 3Com EtherLink III Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODirectDevice.h>

/* Register offsets for EtherLink III */
#define EL3_COMMAND            0x0E
#define EL3_STATUS             0x0E
#define EL3_WINDOW             0x0E

/* Ring sizes */
#define RX_RING_SIZE           32
#define TX_RING_SIZE           16

/* Queue size */
#define TX_QUEUE_MAX_SIZE      128

/* EtherLink III ID values */
#define EL3_VENDOR_ID          0x6d50    /* 3Com vendor ID */
#define EL3_PRODUCT_ID         0x9050    /* EtherLink III product ID mask */
#define EL3_ID_PORT            0x110     /* ISA ID port */

/* Connector types */
#define CONNECTOR_AUI          0         /* AUI (Attachment Unit Interface) */
#define CONNECTOR_BNC          1         /* BNC (10Base2 coaxial) */
#define CONNECTOR_RJ45         2         /* RJ-45 (10Base-T twisted pair) */

/* Media availability bits (from offset 4 in window 0) */
#define MEDIA_AVAIL_RJ45       0x0200    /* RJ-45/10Base-T available */
#define MEDIA_AVAIL_BNC        0x1000    /* BNC/10Base2 available */
#define MEDIA_AVAIL_AUI        0x2000    /* AUI available */

/* Queue structure for linked-list management */
typedef struct {
    netbuf_t head;
    netbuf_t tail;
    unsigned int count;
    unsigned int max;
} NetbufQueue;

@interface EtherLink3 : IOEthernetDriver
{
    /* Hardware configuration */
    unsigned short ioBase;                    /* +0x174: I/O port base address */
    unsigned short irq;                       /* IRQ number */
    enet_addr_t stationAddress;               /* MAC address */

    /* Instance state flags */
    BOOL isRunning;                           /* Adapter running state */
    BOOL isPromiscuous;                       /* Promiscuous mode enabled */
    BOOL isMulticast;                         /* Multicast mode enabled */
    BOOL isISA;                               /* ISA bus flag */
    BOOL doAutoDetect;                        /* Auto-detect connector */
    BOOL interruptDisabled;                   /* +0x198: Interrupt disabled flag */

    /* Network interface */
    id networkInterface;                      /* Network interface instance */

    /* Hardware configuration registers */
    unsigned int connectorType;               /* +0x188: Connector type (0=AUI, 1=BNC, 2=RJ-45) */
    unsigned char rxFilterByte;               /* +0x19c: RX filter configuration byte */
    unsigned char currentWindow;              /* +0x19d: Currently selected register window */

    /* Transmit queue (software queue of packets waiting to be sent) */
    NetbufQueue txQueue;                      /* +0x1a0: TX queue structure (16 bytes) */

    /* Transmit pending queue (packets currently being transmitted) */
    NetbufQueue txPendingQueue;               /* +0x1b0: TX pending queue structure (16 bytes, max at 0x1bc) */

    /* Receive queue (received packets waiting to be processed) */
    NetbufQueue rxQueue;                      /* +0x1c0: RX queue structure (16 bytes, max at 0x1cc) */

    /* Free netbuf list (pre-allocated buffers for RX) */
    NetbufQueue freeNetbufQueue;              /* +0x1d0: Free netbuf queue structure (16 bytes, max at 0x1dc) */

    /* Statistics */
    unsigned int txErrors;                    /* +0x1e4: TX error count */
    unsigned int txCollisions;                /* +0x1e8: TX collision count */
    unsigned int txSuccess;                   /* +0x1ec: TX success count */
    unsigned int rxErrors;                    /* +0x1f0: RX error count */

    /* Descriptor rings */
    void *descriptorMemBase;                  /* Base of allocated descriptor memory */
    unsigned int descriptorMemSize;           /* Size of descriptor memory */
}

/* Class Methods */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/* Instance Methods - Initialization */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)free;

/* Configuration Methods */
- (void)setIOBase:(unsigned short)base;
- (void)setIRQ:(unsigned short)interrupt;
- (void)setISA:(BOOL)flag;
- (void)setDoAuto:(BOOL)flag;

/* Promiscuous and Multicast Mode Control */
- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;

/* Interrupt Management */
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)getHandler:(IOInterruptHandler *)handler
            level:(unsigned int *)ipl
         argument:(void **)arg
     forInterrupt:(unsigned int)localInterrupt;

/* Transmit Methods */
- (void)transmit:(netbuf_t)packet;
- (unsigned int)transmitQueueSize;
- (unsigned int)transmitQueueCount;

/* Receive Methods */
- (netbuf_t)allocateNetbuf;
- (void)QFill:(NetbufQueue *)queue;

/* Power Management */
- (IOReturn)getPowerManagement:(void *)powerManagement;
- (IOReturn)getPowerState:(void *)powerState;
- (IOReturn)setPowerManagement:(unsigned int)powerLevel;
- (IOReturn)setPowerState:(unsigned int)powerState;

/* Interrupt Control */
- (IOReturn)enableAllInterrupts;
- (void)disableAllInterrupts;

@end

/* Private Category - Internal Implementation */
@interface EtherLink3(EtherLink3Private)
- (BOOL)__hwInit;
- (void)__doAutoConnectorDetect;
- (void)__scheduleReset;
@end

/* EISA Bus Variant */
@interface EtherLink3EISA : EtherLink3
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
@end

/* PCMCIA Bus Variant */
@interface EtherLink3PCMCIA : EtherLink3
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
@end

/* PnP Bus Variant */
@interface EtherLink3PnP : EtherLink3
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
@end

/* Kernel Server Instance */
@interface EtherLink3KernelServerInstance : Object
+ (id)kernelServerInstance;
@end

/* Version Information */
@interface EtherLink3Version : Object
+ (const char *)driverKitVersionForEtherLink3;
@end
