#ifndef _DECCHIP21140_H_
#define _DECCHIP21140_H_

#import <driverkit/IOEthernet.h>
#import <driverkit/IOPCIDeviceDescription.h>
#import <driverkit/IONetbufQueue.h>
#import <net/etherdefs.h>
#import <net/netbuf.h>
#import "DECchip21140Shared.h"

@interface DECchip21140 : IOEthernet
{
    /* The superclass occupies 0x000-0x173 in the reference instance. */
    unsigned short ioBase;                 /* 0x174 */
    unsigned short irq;                    /* 0x176 */
    enet_addr_t myAddress;                 /* 0x178 */
    IONetwork *networkInterface;            /* 0x180 */
    IONetbufQueue *transmitQueue;           /* 0x184 */
    BOOL isPromiscuous;                    /* 0x188 */
    BOOL multicastEnabled;                 /* 0x189 */
    BOOL resetAndEnabled;                  /* 0x18a */
    unsigned char sromAddressBits;          /* 0x18b */
    unsigned int enetAddressOffset;         /* 0x18c */
    int dataRateMode;                      /* 0x190 */
    int hardwareVendorID;                  /* 0x194 */
    netbuf_t txNetbuf[32];                 /* 0x198 */
    netbuf_t rxNetbuf[64];                 /* 0x218 */
    DECchipDescriptor *rxRing;              /* 0x318 */
    DECchipDescriptor *txRing;              /* 0x31c */
    unsigned int txPutIndex;               /* 0x320 */
    unsigned int txDoneIndex;              /* 0x324 */
    unsigned int txNumFree;                /* 0x328 */
    unsigned int txIntCount;               /* 0x32c */
    unsigned int rxDoneIndex;              /* 0x330 */
    netbuf_t KDB_txBuf;                    /* 0x334 */
    void *memoryPtr;                       /* 0x338 */
    unsigned int memorySize;               /* 0x33c */
    DECchipDescriptor *setupBuffer;         /* 0x340 */
    unsigned int setupBufferPhysical;       /* 0x344 */
    unsigned int interruptMask;            /* 0x348 */
    unsigned int operationMode;             /* 0x34c */
    unsigned int vendorDeviceID;            /* 0x350 */
    unsigned int subVendorDeviceID;         /* 0x354 */
}

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- free;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)enableAdapterInterrupts;
- (void)disableAdapterInterrupts;
- (void)interruptOccurred;
- (void)serviceTransmitQueue;
- (void)transmit:(netbuf_t)packet;
- (unsigned int)transmitQueueSize;
- (unsigned int)transmitQueueCount;
- (unsigned int)pendingTransmitCount;
- (void)timeoutOccurred;
- (netbuf_t)allocateNetbuf;
- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;
- (void)addMulticastAddress:(enet_addr_t *)address;
- (void)removeMulticastAddress:(enet_addr_t *)address;
- (IOReturn)getPowerState:(PMPowerState *)state;
- (IOReturn)setPowerState:(PMPowerState)state;
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state;
- (IOReturn)setPowerManagement:(PMPowerManagementState)state;
- (void)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout;
- (void)sendPacket:(void *)data length:(unsigned int)length;

/* These PCI configuration accessors are inherited from the DriverKit class. */
+ (IOReturn)getPCIConfigSpace:(void *)configSpace
    withDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
+ (IOReturn)getPCIConfigData:(unsigned int *)data
    atRegister:(unsigned int)reg
    withDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
+ (IOReturn)setPCIConfigData:(unsigned int)data
    atRegister:(unsigned int)reg
    withDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;

@end

#endif
