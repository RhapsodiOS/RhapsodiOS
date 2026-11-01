/* Reconstructed from the i386 Intel82556NetworkDriver reference. */
#ifndef _INTEL82556_H_
#define _INTEL82556_H_

#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/IOPower.h>
#import <machkit/NXLock.h>
#import <net/netbuf.h>

@class Intel82556Buf;

/* Hardware layout and software bookkeeping, in the reference i386 ABI. */
typedef struct {
    unsigned short reserved0;
    volatile unsigned short sysbus;
    unsigned int reserved1;
    volatile unsigned int iscpAddress;
} I556SCP;

typedef struct {
    volatile unsigned char busy;
    unsigned char reserved[3];
    volatile unsigned int scbAddress;
} I556ISCP;

typedef struct {
    volatile unsigned short status;
    volatile unsigned short command;
    volatile unsigned int commandList;
    volatile unsigned int receiveFrameArea;
    volatile unsigned int counters[6];
    volatile unsigned short throttleOn;
    volatile unsigned short throttleOff;
    unsigned int reserved;
} I556SCB;

typedef struct {
    volatile unsigned int signature;
    volatile unsigned short result;
    unsigned short reserved;
} I556SelfTest;

typedef struct {
    volatile unsigned short count;
    unsigned short reserved;
    volatile unsigned int link;
    volatile unsigned int buffer;
    unsigned int physical;
} I556TBD;

typedef struct I556TCB {
    volatile unsigned short status;
    volatile unsigned short command;
    volatile unsigned int link;
    volatile unsigned int tbdAddress;
    volatile unsigned short count;
    volatile unsigned char threshold;
    volatile unsigned char tbdCount;
    unsigned char reserved[8];
    struct I556TCB *next;
    unsigned int physical;
    I556TBD tbd[2];
    netbuf_t netbuf;
} I556TCB;

typedef struct I556RBD {
    volatile unsigned short status;
    unsigned short reserved0;
    volatile unsigned int link;
    volatile unsigned int buffer;
    volatile unsigned short size;
    volatile unsigned short end;
    unsigned int reserved1;
    struct I556RBD *next;
    unsigned int physical;
} I556RBD;

typedef struct I556RFD {
    volatile unsigned short status;
    volatile unsigned short command;
    volatile unsigned int link;
    volatile unsigned int rbdAddress;
    volatile unsigned short count;
    volatile unsigned short size;
    unsigned char reserved[16];
    struct I556RFD *next;
    unsigned int physical;
    I556RBD rbd;
    netbuf_t netbuf;
} I556RFD;

typedef struct {
    volatile unsigned short status;
    volatile unsigned short command;
    volatile unsigned int link;
} I556CommandHeader;

typedef union {
    I556CommandHeader header;
    struct { I556CommandHeader header; unsigned char bytes[20]; } config;
    struct { I556CommandHeader header; enet_addr_t address; } ia;
    struct { I556CommandHeader header; unsigned int address; } dump;
    I556TCB transmit;
} I556Command;

typedef union { unsigned char bytes[88]; } I556Dump;

unsigned int IOIsPhysicallyContiguous(unsigned int address, int size);
void *IOMallocPage(int size, void **allocation, unsigned int *allocationSize);
void *IOMallocNonCached(int size, void **allocation, int *allocationSize);
netbuf_t getNetBuffer(void *pool);
void recycleNetbuf(void *data, unsigned int size, void *context);

@interface Intel82556 : IOEthernet <IOPower>
{
    unsigned short ioBase;
    int irq;
    enet_addr_t myAddress;
    IONetwork *networkInterface;
    Intel82556Buf *bufferPool;
    IONetbufQueue *transmitQueue;
    BOOL promiscuousEnabled;
    BOOL multicastEnabled;
    BOOL allMulticastEnabled;
    BOOL multicastConfigured;
    BOOL sourceAddressInsertion;
    BOOL resetAndEnabled;
    void *sharedMemPtr;
    unsigned int sharedMemSize;
    void *sharedMemAllocPtr;
    unsigned int sharedMemAvail;
    void *sharedMem_actualPtr;
    unsigned int sharedMem_actualSize;
    I556SCP *scp_p;
    I556ISCP *iscp_p;
    I556SCB *scb_p;
    I556SelfTest *selfTest_p;
    I556Command *cbl_p;
    unsigned int cbl_paddr;
    I556TCB *tcbList_p;
    I556TCB *headFreeTcb;
    I556TCB *activeTcbHead;
    I556TCB *pendingTcbHead;
    I556TCB *pendingTcbTail;
    I556TCB *KDB_tcb_p;
    void *KDB_buf_p;
    unsigned int KDB_buf_paddr;
    I556RFD *rfdList_p;
    I556RFD *headRfd;
    I556RFD *tailRfd;
    BOOL fullDuplexMode;
    int dataRate;
    BOOL autoSpeedDetect;
}
- initFromDeviceDescription:(IODeviceDescription *)description;
- free;
- (BOOL)resetAndEnable:(BOOL)enable;
- (BOOL)hwInit;
- (BOOL)swInit;
- (BOOL)coldInit;
- (BOOL)config;
- (BOOL)iaSetup;
- (BOOL)mcSetup;
- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;
- (void)addMulticastAddress:(enet_addr_t *)address;
- (void)removeMulticastAddress:(enet_addr_t *)address;
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)enableAdapterInterrupts;
- (void)disableAdapterInterrupts;
- (void)clearIrqLatch;
- (BOOL)acknowledgeInterrupts:(unsigned short)status;
- (BOOL)transmitInterruptOccurred;
- (BOOL)receiveInterruptOccurred:(BOOL)restart;
- (void)transmit:(netbuf_t)packet;
- (int)transmitQueueSize;
- (int)transmitQueueCount;
- (void)sendPacket:(void *)data length:(unsigned int)length;
- (void)serviceTransmitQueue;
- (void)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout;
- (netbuf_t)allocateNetbuf;
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state;
- (IOReturn)getPowerState:(PMPowerState *)state;
- (IOReturn)setPowerManagement:(PMPowerManagementState)state;
- (IOReturn)setPowerState:(PMPowerState)state;
- (void)sendChannelAttention;
- (void)sendPortCommand:(int)command with:(unsigned int)argument;
- (void)getEthernetAddress;
- (BOOL)nop:(BOOL)interrupt;
- (BOOL)dump:(I556Dump *)area;
- (BOOL)setThrottleTimers;
- (void)lockDBRT;
- (void)initPLXchip;
- (void)resetPLXchip;
- (BOOL)_hwInit;
- (BOOL)_selfTest;
- (void)_scheduleReset;
- (BOOL)_waitScb;
- (BOOL)_waitCu:(unsigned int)timeout;
- (void *)_memAlloc:(unsigned int)size;
- (BOOL)_initTcbList;
- (BOOL)_initRfdList;
- (BOOL)_startTransmit;
- (void)_transmitPacket:(netbuf_t)packet;
- (BOOL)_startReceiveUnit;
- (BOOL)_abortReceiveUnit;
- (netbuf_t)_recAllocateNetbuf;
@end

/* Public so the two C netbuf callbacks access the recovered named state. */
@interface Intel82556Buf : Object
{
@public
    BOOL initFlag;
    BOOL freeInProgress;
    void *freeList;
    unsigned int numFree;
    unsigned int bufSize;
    unsigned int bufSizeUser;
    unsigned int bufCount;
    void *memPtr;
    int memSize;
    NXSpinLock *freeListLock;
}
- initWithRequestedSize:(unsigned int)requested
             actualSize:(unsigned int *)actual
                  count:(unsigned int)count;
- free;
- (netbuf_t)getNetBuffer;
- (unsigned int)numFree;
@end

@interface IntelPRO100EISA : Intel82556
+ (BOOL)probe:(IODeviceDescription *)description;
- initFromDeviceDescription:(IODeviceDescription *)description;
- (void)clearIrqLatch;
- (void)enableAdapterInterrupts;
- (void)disableAdapterInterrupts;
- (void)sendChannelAttention;
- (void)sendPortCommand:(int)command with:(unsigned int)argument;
- (void)getEthernetAddress;
- (void)lockDBRT;
- (void)initPLXchip;
- (void)resetPLXchip;
- (void)interruptOccurred;
@end

@interface IntelPRO100PCI : Intel82556
+ (BOOL)probe:(IODeviceDescription *)description;
- initFromDeviceDescription:(IODeviceDescription *)description;
- (void)clearIrqLatch;
- (void)enableAdapterInterrupts;
- (void)disableAdapterInterrupts;
- (void)sendChannelAttention;
- (void)sendPortCommand:(int)command with:(unsigned int)argument;
- (void)lockDBRT;
- (void)initPLXchip;
- (void)resetPLXchip;
- (void)interruptOccurred;
@end

#endif
