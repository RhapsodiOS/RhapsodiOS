/* Reconstructed from the i386 Intel82596NetworkDriver reference. */
#import "Intel82596Buf.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <mach/mach_interface.h>
#import <machkit/NXLock.h>
#import <net/netbuf.h>

extern unsigned int page_size;
extern unsigned int page_mask;
extern void *IOMallocNonCached(unsigned int size, void **allocation,
                               unsigned int *allocationSize);
netbuf_t getNetBuffer(void *pool);
static void recycleNetbuf(void *data, unsigned int size, void *context);

@implementation Intel82596Buf

- initWithRequestedSize:(unsigned int)requested
             actualSize:(unsigned int *)actual
                  count:(unsigned int)count
{
    unsigned int slotsPerPage;
    unsigned int pages;
    unsigned int pageStart;
    unsigned int endPage;
    I596BufferNode *node;

    if (initFlag != 0)
        return self;
    initFlag = 1;
    freeListLock = [NXSpinLock new];

    if (requested <= 0x5e9)
        bufSizeUser = 1514;
    else
        bufSizeUser = requested;
    if ((bufSizeUser & 3) != 0)
        bufSizeUser = (bufSizeUser + 3) & 0xfffffffc;
    *actual = bufSizeUser;
    bufSize = bufSizeUser + 24;

    if (page_size < bufSize)
        IOPanic("Intel82596Buf: max buffer size exceeded");

    slotsPerPage = page_size / bufSize;
    pages = (slotsPerPage + count - 1) / slotsPerPage;
    pages *= page_size;
    pageStart = (unsigned int)IOMallocNonCached(
        pages, &memPtr, (unsigned int *)&memSize);
    if (pageStart == 0) {
        IOLog("Intel82596Buf: IOMallocNonCached failed\n");
        return nil;
    }

    freeInProgress = 0;
    freeList = 0;
    bufCount = 0;
    numFree = 0;
    endPage = ((unsigned int)memPtr + (unsigned int)memSize) & ~page_mask;
    node = (I596BufferNode *)pageStart;

    for (;;) {
        if (bufSize > page_size - ((unsigned int)node - pageStart)) {
            pageStart += page_size;
            if (pageStart == endPage)
                return self;
            node = (I596BufferNode *)pageStart;
        }

        node->owner = self;
        node->startGuard = I596_BUFFER_GUARD;
        node->netbuf = 0;
        node->endGuard = (unsigned int *)((char *)node + bufSize - 4);
        *node->endGuard = I596_BUFFER_GUARD;

        [freeListLock lock];
        node->next = freeList;
        freeList = node;
        ++numFree;
        ++bufCount;
        [freeListLock unlock];

        node = (I596BufferNode *)((char *)node + bufSize);
    }
}

- free
{
    BOOL delayed = (freeInProgress != 0);

    if (freeInProgress == 0) {
        [freeListLock lock];
        freeInProgress = 1;
        [freeListLock unlock];
        if (bufCount != numFree)
            return self;
    } else if (bufCount != numFree) {
        return self;
    }

    [freeListLock free];
    IOFree(memPtr, memSize);
    if (delayed)
        IOLog("Intel82596Buf: delayed free accomplished\n");
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

netbuf_t getNetBuffer(void *poolObject)
{
    Intel82596Buf *pool = (Intel82596Buf *)poolObject;
    I596BufLayout *state = (I596BufLayout *)pool;
    I596BufferNode *node;
    netbuf_t netbuf;

    node = (I596BufferNode *)state->freeList;
    [(NXSpinLock *)state->freeListLock lock];
    if (node == 0) {
        [(NXSpinLock *)state->freeListLock unlock];
        return 0;
    }

    state->freeList = node->next;
    --state->numFree;
    [(NXSpinLock *)state->freeListLock unlock];

    if (node->startGuard != I596_BUFFER_GUARD)
        IOPanic("getNetBuffer: buffer underrun");
    if (*node->endGuard != I596_BUFFER_GUARD)
        IOPanic("getNetBuffer: buffer overrun");

    netbuf = nb_alloc_wrapper(I596_BUFFER_DATA(node), state->bufSizeUser,
                              (void (*)(void *))recycleNetbuf, node);
    node->netbuf = netbuf;
    if (netbuf == 0) {
        [(NXSpinLock *)state->freeListLock lock];
        node->next = (I596BufferNode *)state->freeList;
        state->freeList = node;
        ++state->numFree;
        [(NXSpinLock *)state->freeListLock unlock];
    }
    return netbuf;
}

void recycleNetbuf(void *data, unsigned int size, void *context)
{
    I596BufferNode *node = (I596BufferNode *)context;
    Intel82596Buf *pool = (Intel82596Buf *)node->owner;
    I596BufLayout *state = (I596BufLayout *)pool;
    NXSpinLock *lock = (NXSpinLock *)state->freeListLock;

    (void)data;
    (void)size;
    if (node->startGuard != I596_BUFFER_GUARD)
        IOPanic("recycleNetbuf: buffer underrun");
    if (*node->endGuard != I596_BUFFER_GUARD)
        IOPanic("recycleNetbuf: buffer overrun");

    if (state->freeInProgress != 0) {
        [lock lock];
        ++state->numFree;
        [lock unlock];
        if (state->bufCount == state->numFree)
            [pool free];
    } else {
        [lock lock];
        node->next = (I596BufferNode *)state->freeList;
        state->freeList = node;
        ++state->numFree;
        [lock unlock];
    }
}

unsigned int IOIsPhysicallyContiguous(unsigned int address, unsigned int size)
{
    unsigned int last = address + size - 1;
    unsigned int boundary = page_size + (~page_mask & address);
    unsigned int physical;
    unsigned int previousPhysical;
    vm_task_t task;

    while (boundary <= last) {
        task = IOVmTaskSelf();
        if (IOPhysicalFromVirtual(task, boundary, &physical) != IO_R_SUCCESS)
            return 0;
        task = IOVmTaskSelf();
        if (IOPhysicalFromVirtual(task, boundary - 1, &previousPhysical) != IO_R_SUCCESS)
            return 0;
        if (physical != previousPhysical + 1)
            return boundary - 1;
        boundary += page_size;
    }
    return last;
}

void *IOMallocPage(unsigned int size, void **allocation, unsigned int *allocationSize)
{
    void *memory;

    *allocationSize = 2 * size;
    memory = IOMalloc(2 * size);
    if (memory == 0)
        return 0;
    *allocation = memory;
    return (void *)((page_mask + (unsigned int)memory) & ~page_mask);
}

void *IOMallocNonCached(unsigned int size, void **allocation,
                        unsigned int *allocationSize)
{
    unsigned int bytes = page_size + ((page_mask + size) & ~page_mask);
    void *memory;

    *allocationSize = bytes;
    memory = IOMalloc(bytes);
    *allocation = memory;
    if (memory == 0)
        return 0;
    return (void *)((page_mask + (unsigned int)memory) & ~page_mask);
}
