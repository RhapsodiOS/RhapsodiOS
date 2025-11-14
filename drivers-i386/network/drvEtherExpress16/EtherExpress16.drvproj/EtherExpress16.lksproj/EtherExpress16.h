/*
 * EtherExpress16.h
 * Intel EtherExpress 16 Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODirectDevice.h>

/* Connector types */
#define CONNECTOR_AUI          0         /* AUI (Attachment Unit Interface) */
#define CONNECTOR_BNC          1         /* BNC (10Base2 coaxial) */
#define CONNECTOR_RJ45         2         /* RJ-45 (10Base-T twisted pair) */

/* Magic values for descriptor validation */
#define RBD_MAGIC              0xBD42    /* Receive Buffer Descriptor magic */
#define RFD_MAGIC              0x0D02    /* Receive Frame Descriptor magic */

/* i82586 System Configuration Pointer address */
#define SCP_ADDRESS            0xFFF6    /* Fixed SCP location in adapter memory */

/* EtherExpress 16 ID value */
#define EE16_ID_VALUE          0xBABA    /* Adapter ID read from port+0x0F */

/* i82586 Command codes */
#define CMD_NOP                0x0000    /* No operation */
#define CMD_IA_SETUP           0x0001    /* Individual Address Setup */
#define CMD_CONFIGURE          0x0002    /* Configure */
#define CMD_MC_SETUP           0x0003    /* Multicast Setup */
#define CMD_TRANSMIT           0x0004    /* Transmit */
#define CMD_TDR                0x0005    /* Time Domain Reflectometry */
#define CMD_DUMP               0x0006    /* Dump */
#define CMD_DIAGNOSE           0x0007    /* Diagnose */

/* Memory region structure */
typedef struct {
    unsigned short start;
    unsigned short size;
} mem_region_t;

/* Receive frame header structure */
typedef struct {
    unsigned short status;
    unsigned short length;
} recv_hdr_t;

@interface EtherExpress16 : IOEthernetDriver
{
    /* Hardware configuration */
    unsigned short ioBase;                    /* I/O port base address */
    unsigned short irq;                       /* IRQ number */
    unsigned short memBase;                   /* Shared memory base address */
    unsigned short memSize;                   /* Shared memory size */
    enet_addr_t stationAddress;               /* MAC address */

    /* Instance state flags */
    BOOL isRunning;                           /* Adapter running state */
    BOOL isPromiscuous;                       /* Promiscuous mode enabled */
    BOOL isMulticast;                         /* Multicast mode enabled */
    BOOL interruptDisabled;                   /* Interrupt disabled flag */

    /* Network interface */
    id networkInterface;                      /* Network interface instance */

    /* Hardware configuration registers */
    unsigned int connectorType;               /* Connector type (0=AUI, 1=BNC, 2=RJ-45) */
    unsigned int boardType;                   /* Board type index */
    unsigned short configFlag;                /* Configuration flag (0xBABB when configured) */
    BOOL multicastConfigured;                 /* Multicast addresses configured */

    /* Statistics */
    unsigned int txErrors;                    /* TX error count */
    unsigned int txCollisions;                /* TX collision count */
    unsigned int txSuccess;                   /* TX success count */
    unsigned int rxErrors;                    /* RX error count */

    /* Memory management */
    unsigned short memFree;                   /* Free memory pointer */
    unsigned short memAvailSize;              /* Available memory size */
    unsigned short scbOffset;                 /* System Control Block offset in adapter memory */

    /* Transmit state */
    BOOL txInProgress;                        /* Transmit operation in progress */
    unsigned short txCmdOffset;               /* Transmit command block offset */
    unsigned short txTbdOffset;               /* Transmit buffer descriptor offset */
    unsigned short txBufferOffset;            /* Transmit buffer offset */

    /* Queue pointers */
    id txQueue;                               /* Transmit queue */

    /* Receive state */
    unsigned short rxHeadOffset;              /* Receive frame head offset */
    unsigned short rxTailOffset;              /* Receive frame tail offset */
    unsigned short rbdHeadOffset;             /* Receive buffer head offset */
    unsigned short rbdTailOffset;             /* Receive buffer tail offset */
}

/* Class Methods */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/* Instance Methods - Initialization */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)free;

/* Configuration Methods */
- (BOOL)config;
- (BOOL)getIntValues:(unsigned int *)parameterArray
        forParameter:(IOParameterName)parameterName
               count:(unsigned int *)count;

/* Hardware Initialization */
- (BOOL)hwInit:(BOOL)reset;
- (BOOL)swInit;

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
- (void)clearTimeout;

/* Interrupt Control */
- (void)enableAllInterrupts;
- (void)disableAllInterrupts;

/* Transmit Methods */
- (void)transmit:(netbuf_t)packet;
- (unsigned int)sendPacket:(void *)data length:(unsigned int)len;

/* Receive Methods */
- (unsigned int)receivePacket:(void *)data length:(unsigned int)maxlen timeout:(unsigned int)timeout;

/* Memory Management */
- (unsigned short)memAlloc:(unsigned short)size;
- (unsigned short)memAvail;
- (mem_region_t)memRegion:(unsigned short)addr;

/* Command Block List Operations */
- (BOOL)performCBL:(unsigned short)addr;
- (void)abortCBL;

/* Receive Operations */
- (BOOL)recvInit;
- (BOOL)recvStart;
- (BOOL)recvRestart;
- (void)recvFrame:(void *)frame hdr:(recv_hdr_t *)hdr ok:(BOOL)status;

/* Interrupt Handlers */
- (void)cxIntr;
- (void)frIntr;

@end

/* Private Category - Internal Implementation */
@interface EtherExpress16(EtherExpress16Private)
- (BOOL)__configEE16:(IODeviceDescription *)deviceDescription;
- (BOOL)__resetEE16:(BOOL)enable;
- (void)__configureMulticastAddresses;
- (BOOL)ia_setup;
- (BOOL)xmtInit;
@end

/* Kernel Server Instance */
@interface EtherExpress16KernelServerInstance : Object
+ (id)kernelServerInstance;
@end

/* Version Information */
@interface EtherExpress16Version : Object
+ (const char *)driverKitVersionForEtherExpress16;
@end
