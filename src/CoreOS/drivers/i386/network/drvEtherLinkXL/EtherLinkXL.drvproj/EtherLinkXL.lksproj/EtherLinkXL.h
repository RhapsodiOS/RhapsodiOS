/*
 * EtherLinkXL.h
 * 3Com EtherLink XL Network Driver
 */

#import <sys/types.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/IOEthernetPrivate.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/i386/kernelDriver.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IONetbufQueue.h>

/* Register offsets */
#define REG_COMMAND             0x0E
#define REG_STATUS              0x0E
#define REG_TX_STATUS           0x24

/* Command register commands */
#define CMD_SELECT_WINDOW(n)    (0x0800 | ((n) & 0x07))
#define CMD_ACK_INTERRUPT       0x3000
#define CMD_ACK_INTERRUPT_LATCH 0x3001
#define CMD_SET_INDICATION      0x6800
#define CMD_SET_RX_FILTER(f)    (0x8000 | ((f) & 0xFF))
#define CMD_RX_ENABLE           0xA800
#define CMD_STATS_DISABLE       0xB000

/* RX filter bits */
#define RX_FILTER_INDIVIDUAL    0x01
#define RX_FILTER_MULTICAST     0x02
#define RX_FILTER_BROADCAST     0x04
#define RX_FILTER_PROMISCUOUS   0x08

#define RX_RING_SIZE            64
#define TX_RING_SIZE            32

/* The 3C90x descriptor has two buffer fragments. */
typedef struct {
    unsigned int nextDescriptor;
    unsigned int status;
    unsigned int bufferAddr;
    unsigned int bufferStatus;
    unsigned int bufferAddr2;
    unsigned int bufferStatus2;
    unsigned int ringLink;
    unsigned int physicalAddr;
} EtherLinkXLDescriptor;

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

typedef struct {
    unsigned char rawCounters[6];
    unsigned short framesXmittedOk;
    unsigned short framesRcvdOk;
    unsigned char framesDeferred;
    unsigned char badSSD;
    unsigned int bytesRcvdOk;
    unsigned int bytesXmittedOk;
    unsigned int reserved;
} EtherLinkXLStats;


@interface EtherLinkXL : IOEthernet
{
    unsigned short ioBase;                    /* +0x174 */
    unsigned short irq;                       /* +0x176 */
    enet_addr_t etherAddress;                 /* +0x178 */
    id networkInterface;                      /* +0x180 */
    IONetbufQueue *transmitQueue;              /* +0x184 */
    BOOL isPromiscuous;                       /* +0x188 */
    BOOL multicastEnabled;                    /* +0x189 */
    unsigned char rxFilterMode;                /* +0x18A */
    BOOL isRunning;                           /* +0x18B */
    unsigned short interruptMask;              /* +0x18C */
    BOOL resetAndEnabled;                     /* +0x18E */
    netbuf_t *txCurrentNetbuf;                 /* +0x190 */
    netbuf_t *txPendingNetbuf;                 /* +0x194 */
    unsigned int xmitNetbufMemorySize;         /* +0x198 */
    netbuf_t rxNetbuf[RX_RING_SIZE];           /* +0x19C */
    EtherLinkXLDescriptor *rxRing;             /* +0x29C */
    EtherLinkXLDescriptor *txCurrentQueue;     /* +0x2A0 */
    EtherLinkXLDescriptor *txPendingQueue;     /* +0x2A4 */
    unsigned int txIndex;                      /* +0x2A8 */
    BOOL interruptExpected;                    /* +0x2AC */
    unsigned int rxCur;                        /* +0x2B0 */
    unsigned char window;                      /* +0x2B4 */
    int defaultMedium;                         /* +0x2B8 */
    int selectedMedium;                        /* +0x2BC */
    int currentMedium;                         /* +0x2C0 */
    unsigned int mediaCapableFlag;              /* +0x2C4 */
    BOOL autoSelect;                           /* +0x2C8 */
    BOOL fullDuplex;                           /* +0x2C9 */
    BOOL phyFullDuplex;                        /* +0x2CA */
    BOOL waitForTimeout;                       /* +0x2CB */
    short phynum;                              /* +0x2CC */
    void *memoryPtr;                           /* +0x2D0 */
    unsigned int memorySize;                   /* +0x2D4 */
    netbuf_t KDB_txBuf;                        /* +0x2D8 */
    EtherLinkXLStats statStruct;                /* +0x2DC, 24 bytes */
}

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- (BOOL)resetAndEnable:(BOOL)enable;
- (id)free;
- (BOOL)verifyEEPROMChecksum;
- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)transmit:(netbuf_t)packet;
- (void)serviceTransmitQueue;
- (netbuf_t)allocateNetbuf;
- (void)setRunning:(BOOL)running;
@end

@interface EtherLinkXL(EtherLinkXLKDB)
- (void)sendPacket:(void *)data length:(unsigned int)length;
- (void)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout;
@end

@interface EtherLinkXL(EtherLinkXLMII)
- (int)miiReadBit;
- (BOOL)miiReadWord:(unsigned short *)value reg:(unsigned short)reg phy:(unsigned short)phy;
- (void)miiWrite:(unsigned int)value size:(unsigned int)size;
- (void)miiWriteWord:(unsigned short)value reg:(unsigned short)reg phy:(unsigned short)phy;
- (BOOL)resetMIIDevice:(unsigned short)phy;
- (BOOL)waitMIIAutoNegotiation:(unsigned short)phy;
- (BOOL)waitMIILink:(unsigned short)phy;
@end

@interface EtherLinkXL(EtherLinkXLPrivate)
- (BOOL)_init;
- (BOOL)_allocateMemory;
- (BOOL)_initRxRing;
- (BOOL)_initTxQueue;
- (void)_resetChip;
- (void)_enableAdapterInterrupts;
- (void)_disableAdapterInterrupts;
- (void)_startReceive;
- (void)_startTransmit;
- (void)_receiveInterruptOccurred;
- (void)_transmitInterruptOccurred;
- (void)_transmitErrorInterruptOccurred;
- (void)_updateStatsInterruptOccurred;
- (void)_transmitPacket:(netbuf_t)packet flush:(BOOL)flush;
- (BOOL)_updateDescriptor:(void *)descriptor fromNetBuf:(netbuf_t)netbuf receive:(BOOL)receive;
- (void)_switchQueuesAndTransmitWithTimeout:(BOOL)startTimer;
- (void)_autoSelectMedium;
- (void)_setCurrentMedium;
- (void)_configurePHY:(unsigned short)phy;
- (BOOL)_linkUp;
@end
