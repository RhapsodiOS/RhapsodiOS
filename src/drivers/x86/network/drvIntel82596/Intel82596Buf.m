/*
 * Intel82596Buf.m
 * Buffer management for Intel 82596 Ethernet Controller
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IONetbufQueue.h>
#import <objc/Object.h>
#import <objc/NXLock.h>
#import <mach/mach_interface.h>
#import <machkit/NXLock.h>
#import <bsd/sys/types.h>
#import <bsd/string.h>

/* Guard value for buffer overflow/underflow detection */
#define BUFFER_GUARD_MAGIC  0xcafe2bad

/* Buffer node structure for free list management */
typedef struct BufferNode {
    unsigned int reserved;          /* Offset 0: reserved */
    unsigned int guardValue;        /* Offset 4: guard value for underrun */
    void *netbuf;                   /* Offset 8: network buffer pointer */
    struct BufferNode *next;        /* Offset 0xc: next in free list */
    unsigned int *endGuard;         /* Offset 0x10: pointer to end guard */
    char data[0];                   /* Offset 0x14: actual buffer data starts here */
} BufferNode;

@interface Intel82596Buf : Object
{
    void *bufferPool;               /* Offset 0: pointer to buffer pool memory */
    void *freeList;                 /* Offset 8: head of free list */
    unsigned int freeCount;         /* Offset 0xc: number of free buffers */
    unsigned int bufferSize;        /* Offset 0x14: size of each buffer */
    unsigned int bufferCount;       /* Buffer count */
    unsigned int actualSize;        /* Actual allocated size */
    id lock;                        /* Offset 0x24: lock for thread safety */
}

/* Initialization and cleanup */
- initWithRequestedSize:(unsigned int)reqSize
             actualSize:(unsigned int *)actSize
                  count:(unsigned int)count;
- free;

/* Buffer operations */
- (void *)getNetBuffer;
- (unsigned int)numFree;

@end

/* VM page size variables - from kernel */
extern unsigned int __page_size;
extern unsigned int __page_mask;

/* Network buffer API - from netbuf framework */
extern void *nb_alloc_wrapper(void *bufData, unsigned int size,
                               void (*recycleFunc)(void *, void *), void *recycleArg);
#define _nb_alloc_wrapper nb_alloc_wrapper

/* Network buffer free function */
extern void nb_free(void *netbuf);
#define _nb_free nb_free

/* Forward declarations for C functions */
void _recycleNetbuf(void *netbuf, void *userData, BufferNode *node);
void *_getNetBuffer(Intel82596Buf *pool);
unsigned int _IOIsPhysicallyContiguous(unsigned int addr, unsigned int size);
unsigned int _IOMallocNonCached(unsigned int size, void **actualAddr, unsigned int *actualSize);
unsigned int _IOMallocPage(unsigned int size, void **actualAddr, unsigned int *actualSize);

@implementation Intel82596Buf

/*
 * Initialize buffer pool with requested size and count
 * Creates a pool of network buffers with guard value protection
 */
- initWithRequestedSize:(unsigned int)reqSize
             actualSize:(unsigned int *)actSize
                  count:(unsigned int)count
{
    unsigned int minBufferSize = 0x5ea;  /* 1514 bytes - Ethernet max frame */
    unsigned int nodeSize;
    unsigned int totalSize;
    unsigned int allocatedSize;
    void *allocatedAddr;
    unsigned int poolAddr;
    BufferNode *node;
    unsigned int *endGuard;
    unsigned int i;

    self = [super init];
    if (self == nil) {
        return nil;
    }

    /* Initialize instance variables */
    bufferPool = NULL;
    freeList = NULL;
    freeCount = 0;
    bufferCount = count;

    /* Create lock for thread-safe buffer management */
    lock = [[NXLock alloc] init];
    if (lock == nil) {
        [self free];
        return nil;
    }

    /* Ensure minimum buffer size (Ethernet MTU) */
    if (reqSize < minBufferSize) {
        reqSize = minBufferSize;
    }

    /* Round buffer size up to 4-byte boundary */
    bufferSize = (reqSize + 3) & ~3;

    /* Calculate size of each buffer node:
     * - BufferNode structure (0x14 bytes)
     * - Buffer data (bufferSize bytes)
     * - End guard value (4 bytes)
     */
    nodeSize = sizeof(BufferNode) + bufferSize + sizeof(unsigned int);

    /* Round node size up to 4-byte boundary */
    nodeSize = (nodeSize + 3) & ~3;

    /* Calculate total size needed for all buffers */
    totalSize = nodeSize * count;

    /* Allocate non-cached memory for buffer pool */
    poolAddr = _IOMallocNonCached(totalSize, &allocatedAddr, &allocatedSize);
    if (poolAddr == 0) {
        [self free];
        return nil;
    }

    /* Save allocation info */
    bufferPool = allocatedAddr;
    actualSize = allocatedSize;

    /* Initialize buffer nodes and link them into free list */
    for (i = 0; i < count; i++) {
        /* Get pointer to this buffer node */
        node = (BufferNode *)(poolAddr + (i * nodeSize));

        /* Set reserved field to point back to pool object */
        node->reserved = (unsigned int)self;

        /* Set start guard value */
        node->guardValue = BUFFER_GUARD_MAGIC;

        /* Initialize netbuf pointer */
        node->netbuf = NULL;

        /* Calculate and set end guard pointer */
        endGuard = (unsigned int *)(&node->data[bufferSize]);
        node->endGuard = endGuard;
        *endGuard = BUFFER_GUARD_MAGIC;

        /* Link this node into the free list */
        node->next = (BufferNode *)freeList;
        freeList = node;
        freeCount++;
    }

    /* Return actual buffer size to caller if requested */
    if (actSize != NULL) {
        *actSize = bufferSize;
    }

    return self;
}

/*
 * Free buffer pool
 * Implements delayed free when buffers are still in use
 */
- free
{
    BOOL hasBuffersInUse;

    /* Lock and check if buffers are in use */
    if (lock != nil) {
        [lock lock];
        hasBuffersInUse = (freeCount != bufferCount);

        if (hasBuffersInUse) {
            /* Buffers still in use - set delayed free flag at offset 5 */
            *((char *)self + 5) = 1;
            [lock unlock];
            /* Return without freeing - _recycleNetbuf will free when all buffers returned */
            return self;
        }

        [lock unlock];
        [lock free];
        lock = nil;
    }

    /* Free buffer pool memory */
    if (bufferPool != NULL) {
        IOFree(bufferPool, actualSize);
        bufferPool = NULL;
    }

    freeList = NULL;

    return [super free];
}

/*
 * Get a network buffer from the pool
 * Simple wrapper around _getNetBuffer C function
 */
- (void *)getNetBuffer
{
    return _getNetBuffer(self);
}

/*
 * Return number of free buffers
 * Thread-safe accessor
 */
- (unsigned int)numFree
{
    unsigned int count;

    [lock lock];
    count = freeCount;
    [lock unlock];

    return count;
}

@end

/*
 * C function implementations for buffer management
 */

/*
 * Get network buffer from buffer pool
 * This function implements thread-safe buffer allocation with guard value checking
 */
void *_getNetBuffer(Intel82596Buf *pool)
{
    BufferNode *node;
    void *netbuf;

    /* Lock the buffer pool for thread safety */
    [pool->lock lock];

    /* Get head of free list */
    node = (BufferNode *)pool->freeList;

    if (node == NULL) {
        /* No free buffers available */
        [pool->lock unlock];
        return NULL;
    }

    /* Remove node from free list */
    pool->freeList = node->next;
    pool->freeCount--;

    /* Unlock early since we have our buffer */
    [pool->lock unlock];

    /* Check for buffer underrun */
    if (node->guardValue != BUFFER_GUARD_MAGIC) {
        IOPanic("getNetBuffer: buffer underrun");
    }

    /* Check for buffer overrun */
    if (*(node->endGuard) != BUFFER_GUARD_MAGIC) {
        IOPanic("getNetBuffer: buffer overrun");
    }

    /* Allocate network buffer wrapper */
    netbuf = _nb_alloc_wrapper(&node->data, pool->bufferSize, _recycleNetbuf, node);
    node->netbuf = netbuf;

    if (netbuf == NULL) {
        /* Failed to allocate wrapper, return node to free list */
        [pool->lock lock];
        node->next = (BufferNode *)pool->freeList;
        pool->freeList = node;
        pool->freeCount++;
        [pool->lock unlock];
    }

    return netbuf;
}

/*
 * Recycle network buffer - return buffer to pool
 * Called when network buffer is no longer needed
 */
void _recycleNetbuf(void *netbuf, void *userData, BufferNode *node)
{
    Intel82596Buf *pool;
    BOOL shouldFree = NO;

    pool = (Intel82596Buf *)node->reserved;

    /* Check for buffer underrun */
    if (node->guardValue != BUFFER_GUARD_MAGIC) {
        IOPanic("recycleNetbuf: buffer underrun");
    }

    /* Check for buffer overrun */
    if (*(node->endGuard) != BUFFER_GUARD_MAGIC) {
        IOPanic("recycleNetbuf: buffer overrun");
    }

    /* Lock the pool */
    [pool->lock lock];

    /* Check if pool is being freed (flag at offset 5) */
    if (*((char *)pool + 5) == 0) {
        /* Normal recycling - return buffer to free list */
        node->next = (BufferNode *)pool->freeList;
        pool->freeList = node;
        pool->freeCount++;
        [pool->lock unlock];
    } else {
        /* Pool is being freed - increment counter and check if all buffers returned */
        pool->freeCount++;
        [pool->lock unlock];

        /* If all buffers are returned, free the pool */
        if (pool->bufferCount == pool->freeCount) {
            shouldFree = YES;
        }
    }

    /* Free pool if all buffers have been returned during cleanup */
    if (shouldFree) {
        [pool free];
    }
}

/*
 * Check if memory region is physically contiguous
 * Returns the end address if contiguous, or the address where contiguity breaks
 */
unsigned int _IOIsPhysicallyContiguous(unsigned int addr, unsigned int size)
{
    extern unsigned int __page_mask;
    extern unsigned int __page_size;
    unsigned int endAddr;
    unsigned int currentPage;
    unsigned int physAddr1, physAddr2;
    IOReturn result;
    vm_task_t task;

    endAddr = (addr + size) - 1;
    currentPage = (addr & ~__page_mask) + __page_size;

    while (currentPage <= endAddr) {
        /* Get physical address for current page boundary */
        task = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(task, currentPage, &physAddr1);
        if (result != IO_R_SUCCESS) {
            return 0;
        }

        /* Get physical address for previous byte */
        task = IOVmTaskSelf();
        result = IOPhysicalFromVirtual(task, currentPage - 1, &physAddr2);
        if (result != IO_R_SUCCESS) {
            return 0;
        }

        /* Check if physically contiguous */
        if (physAddr1 != physAddr2 + 1) {
            return currentPage - 1;
        }

        currentPage += __page_size;
    }

    return endAddr;
}

/*
 * Allocate non-cached memory
 * Returns page-aligned address
 */
unsigned int _IOMallocNonCached(unsigned int size, void **actualAddr, unsigned int *actualSize)
{
    extern unsigned int __page_mask;
    extern unsigned int __page_size;
    unsigned int allocSize;
    void *allocated;
    unsigned int aligned;

    /* Round up to page boundary and add one extra page */
    allocSize = ((size + __page_mask) & ~__page_mask) + __page_size;
    *actualSize = allocSize;

    /* Allocate memory */
    allocated = IOMalloc(allocSize);
    *actualAddr = allocated;

    if (allocated == NULL) {
        return 0;
    }

    /* Return page-aligned address */
    aligned = ((unsigned int)allocated + __page_mask) & ~__page_mask;
    return aligned;
}

/*
 * Allocate page-aligned memory
 * Allocates 2x requested size to ensure page alignment
 */
unsigned int _IOMallocPage(unsigned int size, void **actualAddr, unsigned int *actualSize)
{
    extern unsigned int __page_mask;
    void *allocated;
    unsigned int aligned;

    /* Allocate 2x the requested size */
    *actualSize = size * 2;
    allocated = IOMalloc(size * 2);

    if (allocated == NULL) {
        return 0;
    }

    *actualAddr = allocated;

    /* Return page-aligned address */
    aligned = ((unsigned int)allocated + __page_mask) & ~__page_mask;
    return aligned;
}
