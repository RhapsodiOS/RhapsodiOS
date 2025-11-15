/*
 * Intel82557Buf.m
 * Intel EtherExpress PRO/100 Network Driver - Buffer Management
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <objc/Object.h>

/* External symbols */
extern unsigned int _page_size;
extern unsigned int _page_mask;

/* External function declarations */
extern Class objc_getClass(const char *name);
extern void *IOMallocNonCached(unsigned int size, vm_address_t *physAddr, vm_address_t *virtAddr);

@interface Intel82557Buf : Object
{
    BOOL initialized;
    BOOL shuttingDown;
    void *headPtr;
    unsigned int freeCount;
    unsigned int entrySize;
    unsigned int bufferSize;
    unsigned int totalCount;
    vm_address_t physAddr;
    vm_address_t virtAddr;
    id lockObj;
}

- initWithRequestedSize:(unsigned int)reqSize
             actualSize:(unsigned int *)actSize
                  count:(unsigned int)count;
- (void)free;
- (netbuf_t)getNetBuffer;
- (unsigned int)numFree;

@end

@implementation Intel82557Buf

/*
 * Initialize buffer pool with requested size and count
 *
 * Buffer pool structure:
 *   +0x00: Object header
 *   +0x04: Initialization flag (1 if initialized)
 *   +0x05: Shutdown flag (1 if shutting down)
 *   +0x08: Head pointer (free list)
 *   +0x0C: Free count (number of free buffers)
 *   +0x10: Buffer entry size (buffer size + overhead)
 *   +0x14: Actual buffer size (aligned to 4 bytes)
 *   +0x18: Total count (total buffers allocated)
 *   +0x1C: Physical address
 *   +0x20: Virtual address
 *   +0x24: Lock object
 *
 * Buffer entry structure:
 *   +0x00: Pointer to buffer pool (self)
 *   +0x04: Magic value 1 (0xCAFE2BAD)
 *   +0x08: User data
 *   +0x0C: Next pointer (for free list)
 *   +0x10: Pointer to magic value 2
 *   ... buffer data ...
 *   +size-4: Magic value 2 (0xCAFE2BAD)
 */
- initWithRequestedSize:(unsigned int)reqSize
             actualSize:(unsigned int *)actSize
                  count:(unsigned int)count
{
    unsigned int alignedSize;
    unsigned int calcEntrySize;
    unsigned int buffersPerPage;
    unsigned int pagesNeeded;
    unsigned int allocSize;
    void *memoryBase;
    void *currentPage;
    void *bufferEntry;
    void *endOfAllocation;

    [super init];

    /* Check if already initialized */
    if (initialized) {
        return self;
    }

    /* Mark as initialized */
    initialized = YES;

    /* Create lock object (NXSpinLock) */
    lockObj = [[objc_getClass("NXSpinLock") alloc] init];

    /* Determine actual buffer size (minimum 0x5EA = 1514 bytes for Ethernet) */
    if (reqSize < 0x5EA) {
        bufferSize = 0x5EA;
    } else {
        bufferSize = reqSize;
    }

    /* Align to 4-byte boundary */
    if ((bufferSize & 3) != 0) {
        bufferSize = (bufferSize + 3) & ~3;
    }

    /* Return actual size to caller */
    if (actSize != NULL) {
        *actSize = bufferSize;
    }

    /* Calculate entry size (24-byte overhead + buffer size) */
    entrySize = bufferSize + 0x18;

    /* Check if entry size exceeds page size */
    if (_page_size < entrySize) {
        IOPanic("Intel82557Buf: max buffer size exceeded");
    }

    /* Calculate number of buffers per page */
    buffersPerPage = _page_size / entrySize;

    /* Calculate number of pages needed */
    pagesNeeded = (count + buffersPerPage - 1) / buffersPerPage;
    allocSize = pagesNeeded * _page_size;

    /* Allocate DMA-capable non-cached memory */
    memoryBase = IOMallocNonCached(allocSize, &physAddr, &virtAddr);

    if (memoryBase == NULL) {
        IOLog("Intel82557Buf: IOMallocNonCached failed\n");
        return nil;
    }

    /* Initialize counters */
    shuttingDown = NO;
    headPtr = NULL;
    totalCount = 0;
    freeCount = 0;

    /* Calculate end of allocation */
    endOfAllocation = (void *)((~_page_mask & physAddr) + virtAddr);

    /* Initialize buffer entries */
    currentPage = memoryBase;
    bufferEntry = memoryBase;

    while (1) {
        /* Check if there's room in current page for another entry */
        if (entrySize <= (_page_size - ((unsigned int)bufferEntry - (unsigned int)currentPage))) {
            /* Room in current page - initialize this entry */

            /* Set up buffer entry structure */
            *(id *)bufferEntry = self;                    /* +0x00: Pool pointer */
            *(unsigned int *)((unsigned char *)bufferEntry + 0x04) = 0xCAFE2BAD;  /* +0x04: Magic 1 */
            *(unsigned int *)((unsigned char *)bufferEntry + 0x08) = 0;           /* +0x08: User data */

            /* Set pointer to magic value 2 at end of entry */
            *(void **)((unsigned char *)bufferEntry + 0x10) =
                (void *)((unsigned char *)bufferEntry + entrySize - 4);

            /* Write magic value 2 at end */
            *(unsigned int *)((unsigned char *)bufferEntry + entrySize - 4) = 0xCAFE2BAD;

            /* Add to free list (thread-safe) */
            [lockObj lock];

            /* Link into free list */
            *(void **)((unsigned char *)bufferEntry + 0x0C) = headPtr;  /* +0x0C: Next */
            headPtr = bufferEntry;

            /* Update counts */
            freeCount++;
            totalCount++;

            [lockObj unlock];

            /* Advance to next entry */
            bufferEntry = (void *)((unsigned char *)bufferEntry + entrySize);
        } else {
            /* No room in current page - move to next page */
            currentPage = (void *)((unsigned char *)currentPage + _page_size);
            bufferEntry = currentPage;

            /* Check if we've reached end of allocation */
            if (bufferEntry >= endOfAllocation) {
                break;
            }
        }
    }

    return self;
}

/*
 * Free buffer pool and release all resources
 *
 * Buffer pool structure:
 *   +0x05: Shutdown flag
 *   +0x0C: Free count
 *   +0x18: Total count
 *   +0x1C: Physical address (used as size for IOFree)
 *   +0x20: Virtual address (memory base)
 *   +0x24: Lock object
 *
 * Operation:
 *   - If not already shutting down, lock and set shutdown flag
 *   - Check if all buffers returned (total count == free count)
 *   - If not, defer free until all buffers returned
 *   - Free lock object and allocated memory
 *   - Call superclass free
 */
- (void)free
{
    if (!shuttingDown) {
        /* Not shutting down yet - acquire lock and set flag */
        [lockObj lock];
        shuttingDown = YES;
        [lockObj unlock];

        /* Check if all buffers have been returned */
        if (totalCount != freeCount) {
            /* Can't free yet - some buffers still in use */
            return;
        }

        /* All buffers returned - proceed with free */
        [lockObj free];
        IOFree((void *)virtAddr, physAddr);
    } else {
        /* Already shutting down - check again if we can free */
        if (totalCount != freeCount) {
            /* Still waiting for buffers to be returned */
            return;
        }

        /* All buffers returned - delayed free can proceed */
        [lockObj free];
        IOFree((void *)virtAddr, physAddr);
        IOLog("Intel82557Buf: delayed free accomplished\n");
    }

    /* Call superclass free */
    [super free];
}

/*
 * Get network buffer from pool
 *
 * Buffer entry structure:
 *   +0x00: Pointer to buffer pool (self)
 *   +0x04: Magic value 1 (0xCAFE2BAD)
 *   +0x08: User data (this is the netbuf_t returned)
 *   +0x0C: Next pointer (for free list)
 *   +0x10: Pointer to magic value 2
 *
 * Returns: netbuf_t from free list, or NULL if pool is empty
 */
- (netbuf_t)getNetBuffer
{
    void *bufferEntry;
    netbuf_t nb;

    /* Check if shutting down or not initialized */
    if (shuttingDown || !initialized) {
        return NULL;
    }

    /* Acquire lock */
    [lockObj lock];

    /* Check if free list is empty */
    if (headPtr == NULL) {
        [lockObj unlock];
        return NULL;
    }

    /* Remove buffer from free list */
    bufferEntry = headPtr;
    headPtr = *(void **)((unsigned char *)bufferEntry + 0x0C);

    /* Decrement free count */
    freeCount--;

    /* Release lock */
    [lockObj unlock];

    /* Return pointer to netbuf (offset +0x08 in buffer entry) */
    nb = (netbuf_t)((unsigned char *)bufferEntry + 0x08);

    return nb;
}

/*
 * Get number of free buffers in pool
 *
 * Returns: Number of available buffers (no locking, atomic read)
 */
- (unsigned int)numFree
{
    /* Direct read of free count (atomic) */
    return freeCount;
}

@end
