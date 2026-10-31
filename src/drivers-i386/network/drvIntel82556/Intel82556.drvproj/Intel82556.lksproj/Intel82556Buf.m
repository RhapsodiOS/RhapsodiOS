/* Reconstructed from the i386 Intel82556NetworkDriver reference. */
#import "Intel82556.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

extern unsigned int page_size;
extern unsigned int page_mask;

#define BUFFER_GUARD 0xcafe2badU

typedef struct Intel82556BufferNode {
    Intel82556Buf *owner;
    unsigned int startGuard;
    netbuf_t netbuf;
    struct Intel82556BufferNode *next;
    unsigned int *endGuard;
} Intel82556BufferNode;

netbuf_t getNetBuffer(void *poolObject)
{
    Intel82556Buf *pool = (Intel82556Buf *)poolObject;
    Intel82556BufferNode *node = pool->freeList;

    [pool->freeListLock lock];
    if (node == 0) {
        [pool->freeListLock unlock];
        return 0;
    }
    pool->freeList = node->next;
    --pool->numFree;
    [pool->freeListLock unlock];

    if (node->startGuard != BUFFER_GUARD)
        IOPanic("getNetBuffer: buffer underrun");
    if (*node->endGuard != BUFFER_GUARD)
        IOPanic("getNetBuffer: buffer overrun");

    node->netbuf = nb_alloc_wrapper(node + 1, pool->bufSizeUser,
                                    (void (*)(void *))recycleNetbuf, node);
    if (node->netbuf == 0) {
        [pool->freeListLock lock];
        node->next = pool->freeList;
        pool->freeList = node;
        ++pool->numFree;
        [pool->freeListLock unlock];
    }
    return node->netbuf;
}

/* The original wrapper callback receives data, size, and its saved context. */
void recycleNetbuf(void *data, unsigned int size, void *context)
{
    Intel82556BufferNode *node = context;
    Intel82556Buf *pool = node->owner;

    (void)data;
    (void)size;
    if (node->startGuard != BUFFER_GUARD)
        IOPanic("recycleNetbuf: buffer underrun");
    if (*node->endGuard != BUFFER_GUARD)
        IOPanic("recycleNetbuf: buffer overrun");

    if (pool->freeInProgress != 0) {
        [pool->freeListLock lock];
        ++pool->numFree;
        [pool->freeListLock unlock];
        if (pool->bufCount == pool->numFree)
            [pool free];
    } else {
        [pool->freeListLock lock];
        node->next = pool->freeList;
        pool->freeList = node;
        ++pool->numFree;
        [pool->freeListLock unlock];
    }
}

@implementation Intel82556Buf

- initWithRequestedSize:(unsigned int)requested
             actualSize:(unsigned int *)actual
                  count:(unsigned int)count
{
    unsigned int slotsPerPage;
    unsigned int bytes;
    unsigned int pageStart;
    Intel82556BufferNode *node;

    if (initFlag != 0)
        return self;
    initFlag = 1;
    freeListLock = [NXSpinLock new];
    bufSizeUser = requested <= 1513 ? 1514 : requested;
    if ((bufSizeUser & 3) != 0)
        bufSizeUser = (bufSizeUser + 3) & ~3U;
    *actual = bufSizeUser;
    bufSize = bufSizeUser + 24;
    if (page_size < bufSize)
        IOPanic("Intel82556Buf: max buffer size exceeded");

    slotsPerPage = page_size / bufSize;
    bytes = page_size * ((slotsPerPage + count - 1) / slotsPerPage);
    pageStart = (unsigned int)IOMallocNonCached(bytes, &memPtr, &memSize);
    if (pageStart == 0) {
        IOLog("Intel82556Buf: IOMallocNonCached failed\n");
        return nil;
    }

    freeInProgress = 0;
    freeList = 0;
    bufCount = 0;
    numFree = 0;
    node = (Intel82556BufferNode *)pageStart;
    for (;;) {
        if (bufSize > page_size - ((unsigned int)node - pageStart)) {
            pageStart += page_size;
            if (pageStart == (((unsigned int)memPtr + memSize) & ~page_mask))
                return self;
            node = (Intel82556BufferNode *)pageStart;
        }
        node->owner = self;
        node->startGuard = BUFFER_GUARD;
        node->netbuf = 0;
        node->endGuard = (unsigned int *)((char *)node + bufSize - 4);
        *node->endGuard = BUFFER_GUARD;

        [freeListLock lock];
        node->next = freeList;
        freeList = node;
        ++numFree;
        ++bufCount;
        [freeListLock unlock];
        node = (Intel82556BufferNode *)((char *)node + bufSize);
    }
}

- free
{
    if (freeInProgress != 0) {
        if (bufCount != numFree)
            return self;
        [freeListLock free];
        IOFree(memPtr, memSize);
        IOLog("Intel82556Buf: delayed free accomplished\n");
    } else {
        [freeListLock lock];
        freeInProgress = 1;
        [freeListLock unlock];
        if (bufCount != numFree)
            return self;
        [freeListLock free];
        IOFree(memPtr, memSize);
    }
    return [super free];
}

- (netbuf_t)getNetBuffer
{
    return getNetBuffer(self);
}

- (unsigned int)numFree
{
    return numFree;
}

@end
