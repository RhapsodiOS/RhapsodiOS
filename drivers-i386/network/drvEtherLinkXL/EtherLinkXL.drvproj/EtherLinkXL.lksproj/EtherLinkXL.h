/*
 * EtherLinkXL.h
 * 3Com EtherLink XL Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOPCIDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

/* Register offsets */
#define REG_COMMAND             0x0E
#define REG_STATUS              0x0E
#define REG_WINDOW              0x0E
#define REG_TX_STATUS           0x24
#define REG_RX_DESC_BASE        0x38

/* Command Register Commands */
#define CMD_SELECT_WINDOW(n)    (0x0800 | ((n) & 0x07))
#define CMD_ACK_INTERRUPT       0x3000
#define CMD_ACK_INTERRUPT_LATCH 0x3001
#define CMD_SET_INDICATION      0x6800
#define CMD_SET_READ_ZERO       0x7000
#define CMD_SET_INTERRUPT       0x7E00
#define CMD_DISABLE_INTERRUPT   0x7800
#define CMD_SET_RX_FILTER(f)    (0x8000 | ((f) & 0xFF))
#define CMD_STATS_DISABLE       0xB000
#define CMD_RX_ENABLE           0xA800

/* RX Filter Bits */
#define RX_FILTER_INDIVIDUAL    0x01
#define RX_FILTER_MULTICAST     0x02
#define RX_FILTER_BROADCAST     0x04
#define RX_FILTER_PROMISCUOUS   0x08

/* Adapter and Media Tables */
typedef struct {
    unsigned int deviceID;
    const char *name;
} AdapterEntry;

typedef struct {
    const char *name;
    unsigned short flags;
    unsigned char type;
    unsigned char param;
    unsigned short delay;
    unsigned short pad;
} MediaEntry;

/* Ring Sizes */
#define RX_RING_SIZE            64
#define TX_RING_SIZE            32

/* Descriptor structure (32 bytes each) */
typedef struct {
    unsigned int nextDescriptor;      /* +0x00: Next descriptor pointer */
    unsigned int status;              /* +0x04: Status word */
    unsigned int bufferAddr;          /* +0x08: Buffer address */
    unsigned int reserved[5];         /* +0x0C-0x1F: Reserved */
} EtherLinkXLDescriptor;

@interface EtherLinkXL : IOEthernetDriver
{
    /* Hardware configuration */
    unsigned short ioBase;            /* I/O port base address */
    unsigned short irq;               /* IRQ number */
    enet_addr_t stationAddress;       /* MAC address */

    /* Instance state flags */
    BOOL isRunning;                   /* Adapter running state */
    BOOL isPromiscuous;               /* Promiscuous mode enabled */
    BOOL isMulticast;                 /* Multicast mode enabled */
    unsigned char rxFilterByte;       /* Receive filter register value */

    /* Network interface */
    id networkInterface;              /* Network interface instance */

    /* Transmit management */
    id txQueue;                              /* Transmit queue (IONetbufQueue) */
    netbuf_t *txNetbufArray;                 /* TX netbuf array pointer */
    unsigned int txNetbufArraySize;          /* TX netbuf array size */

    /* Receive management */
    netbuf_t rxNetbufArray[RX_RING_SIZE];   /* RX netbuf pointers */

    /* Descriptor rings */
    void *descriptorMemBase;                 /* Base of allocated descriptor memory */
    unsigned int descriptorMemSize;          /* Size of descriptor memory */
    EtherLinkXLDescriptor *rxDescriptors;    /* RX descriptor ring */
    void *txDescriptorBase;                  /* TX descriptor base (two queues) */
    EtherLinkXLDescriptor *txDescriptors;    /* TX descriptor ring (current) */
    unsigned int txHead;                     /* TX ring head index */
    BOOL txPending;                          /* TX operation pending flag */
    unsigned int rxIndex;                    /* Current RX descriptor index */
    netbuf_t *txNetbufArrayAlt;              /* Alternate TX netbuf array */

    /* Temporary netbuf for polling mode */
    netbuf_t txTempNetbuf;                   /* Temporary TX netbuf for KDB */

    /* Hardware state */
    unsigned int requestedMedium;            /* User-requested media type */
    unsigned int defaultMedium;              /* Default media type */
    unsigned int currentMedium;              /* Currently selected media type */
    unsigned int availableMedia;             /* Bitmap of available media */
    unsigned char currentWindow;             /* Currently selected register window */
    BOOL isFullDuplex;                       /* Full duplex mode flag */
    unsigned short interruptMask;            /* Interrupt enable mask */

    /* Adapter capabilities and statistics */
    unsigned char adapterCapabilities[6];    /* Adapter capabilities from EEPROM */
    unsigned char softwareInfo;              /* Software information byte */
    unsigned char mediaOptions;              /* Media options byte */
    unsigned int rxFreeThresh;               /* RX free threshold */
    unsigned int txStartThresh;              /* TX start threshold */
    unsigned int txAvailable;                /* TX available space */
    unsigned int txSpaceThresh;              /* TX space threshold */
}

/* Class Methods */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/* Instance Methods - Initialization */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)free;

/* EEPROM Methods */
- (BOOL)verifyEEPROMChecksum;

/* Promiscuous and Multicast Mode Control */
- (void)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (void)enableMulticastMode;
- (void)disableMulticastMode;

/* Interrupt Management */
- (void)interruptOccurred;
- (void)timeoutOccurred;

/* Transmit Methods */
- (void)transmit:(netbuf_t)packet;
- (void)serviceTransmitQueue;

/* Receive Methods */
- (netbuf_t)allocateNetbuf;

/* Running State */
- (void)setRunning:(BOOL)running;

@end

/* KDB Category - Debugger Support */
@interface EtherLinkXL(EtherLinkXLKDB)
- (void)sendPacket:(void *)data length:(unsigned int)length;
- (BOOL)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout;
@end

/* MII Category - Media Independent Interface */
@interface EtherLinkXL(EtherLinkXLMII)
- (int)_miiReadBit;
- (BOOL)_miiReadWord:(unsigned short *)value reg:(unsigned short)reg phy:(unsigned short)phy;
- (void)_miiWrite:(unsigned int)value size:(unsigned int)size;
- (void)_miiWriteWord:(unsigned int)value reg:(unsigned int)reg phy:(unsigned int)phy;
- (BOOL)_resetMIIDevice:(unsigned int)phy;
- (BOOL)_waitMIIAutoNegotiation:(unsigned int)phy;
- (BOOL)_waitMIILink:(unsigned int)phy;
@end

/* Private Category - Internal Implementation */
@interface EtherLinkXL(EtherLinkXLPrivate)
- (BOOL)__init;
- (BOOL)__allocateMemory;
- (void)__initRxRing;
- (void)__initTxQueue;
- (void)__resetChip;
- (void)__enableAdapterInterrupts;
- (void)__disableAdapterInterrupts;
- (void)__startReceive;
- (void)__startTransmit;
- (void)__receiveInterruptOccurred;
- (void)__transmitInterruptOccurred;
- (void)__transmitErrorInterruptOccurred;
- (void)__updateStatsInterruptOccurred;
- (BOOL)__transmitPacket:(netbuf_t)packet flush:(BOOL)flush;
- (void)__updateDescriptor:(void *)descriptor fromNetBuf:(netbuf_t)netbuf receive:(BOOL)receive;
- (BOOL)__switchQueuesAndTransmitWithTimeout:(unsigned int)timeout;
- (void)__autoSelectMedium;
- (void)__setCurrentMedium;
- (BOOL)__configurePHY:(unsigned int)phy;
- (BOOL)__linkUp;
@end
