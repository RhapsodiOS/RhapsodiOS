#ifndef _INTEL82596_LAYOUT_H_
#define _INTEL82596_LAYOUT_H_

#ifdef __OBJC__
#import <net/etherdefs.h>
#import <net/netbuf.h>
@class IONetwork, Intel82596Buf, IONetbufQueue, NXSpinLock;
typedef IONetwork *I596IONetworkRef;
typedef Intel82596Buf *I596BufferPoolRef;
typedef IONetbufQueue *I596XmtQueueRef;
typedef NXSpinLock *I596SpinLockRef;
#else
typedef struct { unsigned char ether_addr_octet[6]; } enet_addr_t;
typedef struct { char opaque[1]; } *netbuf_t;
typedef void *I596IONetworkRef;
typedef void *I596BufferPoolRef;
typedef void *I596XmtQueueRef;
typedef void *I596SpinLockRef;
#endif

typedef struct { unsigned char bytes[12]; } I596SCP;
typedef struct { unsigned char bytes[8]; } I596ISCP;
typedef struct { unsigned char bytes[40]; } I596SCB;
typedef struct { unsigned char bytes[24]; } I596RBD;
typedef struct { unsigned char bytes[0x18]; } I596TBD;
typedef struct {
    unsigned char header[40];
    I596RBD rbd;
} I596RFD;
typedef struct {
    unsigned char header[32];
    I596TBD tbd[3];
    netbuf_t netbuf;
} I596TCB;

#define I596_BASE_IVARS \
    unsigned short ioBase; \
    int irq; \
    enet_addr_t myAddress; \
    int chipRev; \
    I596IONetworkRef networkInterface; \
    I596BufferPoolRef bufferPool; \
    I596XmtQueueRef xmtQueue; \
    unsigned char promiscuousEnabled; \
    unsigned char multicastEnabled; \
    unsigned char allMulticastEnabled; \
    unsigned char multicastConfigured; \
    unsigned char sourceAddressInsertion; \
    unsigned char resetAndEnabled; \
    unsigned char _pad_410_411[2]; \
    void *sharedMemPtr; \
    unsigned int sharedMemSize; \
    void *sharedMemAllocPtr; \
    unsigned int sharedMemAvail; \
    void *sharedMem_actualPtr; \
    unsigned int sharedMem_actualSize; \
    I596SCP *scp; \
    I596ISCP *iscp; \
    I596SCB *scb; \
    void *selfTestArea; \
    I596TCB *tcbList; \
    I596TCB *headFreeTcb; \
    I596TCB *activeTcbHead; \
    I596TCB *pendingTcbHead; \
    I596TCB *pendingTcbTail; \
    I596TCB *kdbTcb; \
    void *kdbPacketBuffer; \
    unsigned int kdbPacketPhysical; \
    I596RFD *rfdList; \
    I596RFD *headRfd; \
    I596RFD *tailRfd; \
    unsigned int rfdZeroSize; \
    unsigned int rbdZeroSize; \
    unsigned int tcbZeroSize; \
    unsigned char fullDuplexMode; \
    unsigned char _pad_509_511[3]

#define I596_BUF_IVARS \
    unsigned char initFlag; \
    unsigned char freeInProgress; \
    unsigned char _pad_6_7[2]; \
    void *freeList; \
    unsigned int numFree; \
    unsigned int bufSize; \
    unsigned int bufSizeUser; \
    unsigned int bufCount; \
    void *memPtr; \
    int memSize; \
    I596SpinLockRef freeListLock

typedef struct I596BufferNode I596BufferNode;
struct I596BufferNode {
    void *owner;
    unsigned int startGuard;
    netbuf_t netbuf;
    I596BufferNode *next;
    unsigned int *endGuard;
};

#define I596_BUFFER_DATA(node) ((char *)(node) + 20)
#define I596_BUFFER_GUARD 0xCAFE2BADU

typedef struct {
    unsigned char objectHeader[372];
    I596_BASE_IVARS;
} I596BaseLayout;

typedef struct {
    unsigned int isa;
    I596_BUF_IVARS;
} I596BufLayout;

#endif
