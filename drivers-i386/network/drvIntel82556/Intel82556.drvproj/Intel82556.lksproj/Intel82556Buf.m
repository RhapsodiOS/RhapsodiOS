/*
 * Intel82556Buf.m
 * Intel EtherExpress PRO/100 Network Driver - Buffer Management
 */

#import "Intel82556.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/* External symbols */
extern unsigned int _page_size;
extern unsigned int _page_mask;

/* Static function for getting network buffer from pool */
static void *_getNetBuffer(id pool);

@implementation Intel82556Buf

/*
 * Initialize with requested size
 *
 * Buffer pool structure (in self):
 *   +0x04: Initialization flag (1 if initialized)
 *   +0x05: Shutdown flag (1 if shutting down)
 *   +0x08: Head pointer (free list)
 *   +0x0C: Free count (number of free buffers)
 *   +0x10: Buffer entry size (buffer size + overhead)
 *   +0x14: Actual buffer size (aligned to 4 bytes)
 *   +0x18: Total count (total buffers allocated)
 *   +0x1C: Physical address
 *   +0x20: Virtual address
 *   +0x24: Lock object (NXSpinLock)
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
    id lockObj;
    unsigned int alignedSize;
    unsigned int entrySize;
    unsigned int buffersPerPage;
    unsigned int pagesNeeded;
    unsigned int totalSize;
    vm_address_t physAddr;
    vm_address_t virtAddr;
    unsigned char *bufferEntry;
    unsigned char *pageStart;
    unsigned char *pageEnd;
    int i;

    /* Check if already initialized */
    if (*(unsigned char *)(((char *)self) + 4) != 0) {
        return self;
    }

    /* Mark as initialized */
    *(unsigned char *)(((char *)self) + 4) = 1;

    /* Create lock object */
    lockObj = [[objc_getClass("NXSpinLock") alloc] init];
    *(id *)(((char *)self) + 0x24) = lockObj;

    /* Determine actual buffer size (minimum 0x5EA = 1514 bytes) */
    if (reqSize < 0x5EA) {
        alignedSize = 0x5EA;
    } else {
        alignedSize = reqSize;
    }

    /* Align to 4-byte boundary */
    if ((alignedSize & 3) != 0) {
        alignedSize = (alignedSize + 3) & ~3;
    }

    *(unsigned int *)(((char *)self) + 0x14) = alignedSize;
    *actSize = alignedSize;

    /* Calculate entry size (24-byte overhead + buffer size) */
    entrySize = alignedSize + 0x18;
    *(unsigned int *)(((char *)self) + 0x10) = entrySize;

    /* Verify entry size doesn't exceed page size */
    if (_page_size < entrySize) {
        IOPanic("Intel82556Buf: max buffer size exceeded");
    }

    /* Calculate how many buffers fit per page */
    buffersPerPage = _page_size / entrySize;

    /* Calculate pages needed */
    pagesNeeded = ((count + buffersPerPage - 1) / buffersPerPage);

    /* Calculate total size */
    totalSize = pagesNeeded * _page_size;

    /* Allocate non-cached memory */
    virtAddr = IOMallocNonCached(totalSize,
                                 (vm_address_t *)(((char *)self) + 0x1C),
                                 (vm_address_t *)(((char *)self) + 0x20));

    if (virtAddr == 0) {
        IOLog("Intel82556Buf: IOMallocNonCached failed\n");
        return nil;
    }

    /* Initialize pool state */
    *(unsigned char *)(((char *)self) + 5) = 0;     /* Not shutting down */
    *(unsigned int *)(((char *)self) + 8) = 0;      /* Free list head = NULL */
    *(unsigned int *)(((char *)self) + 0x18) = 0;   /* Total count = 0 */
    *(unsigned int *)(((char *)self) + 0x0C) = 0;   /* Free count = 0 */

    /* Initialize all buffer entries */
    bufferEntry = (unsigned char *)virtAddr;
    pageEnd = (unsigned char *)((_page_mask & *(unsigned int *)(((char *)self) + 0x1C)) +
                                 *(unsigned int *)(((char *)self) + 0x20));

    pageStart = (unsigned char *)virtAddr;

    while (1) {
        /* Check if we can fit another entry in current page */
        if (entrySize <= (_page_size - (bufferEntry - pageStart))) {
            /* Entry fits in current page */
        } else {
            /* Move to next page */
            pageStart = pageStart + _page_size;
            bufferEntry = pageStart;

            /* Check if we've reached the end */
            if (bufferEntry >= pageEnd) {
                break;
            }
        }

        /* Initialize buffer entry */
        /* +0x00: Pointer to pool */
        *(id *)bufferEntry = self;

        /* +0x04: Magic value 1 */
        *(unsigned int *)(bufferEntry + 4) = 0xCAFE2BAD;

        /* +0x08: User data (initially 0) */
        *(unsigned int *)(bufferEntry + 8) = 0;

        /* +0x10: Pointer to magic value 2 (at end of buffer) */
        *(unsigned int **)(bufferEntry + 0x10) =
            (unsigned int *)(bufferEntry + entrySize - 4);

        /* Write magic value 2 at end of buffer */
        *(unsigned int *)(bufferEntry + entrySize - 4) = 0xCAFE2BAD;

        /* Add entry to free list */
        [lockObj lock];

        /* +0x0C: Next pointer = current head */
        *(unsigned int *)(bufferEntry + 0x0C) = *(unsigned int *)(((char *)self) + 8);

        /* Update head to this entry */
        *(unsigned int *)(((char *)self) + 8) = (unsigned int)bufferEntry;

        /* Increment free count */
        *(unsigned int *)(((char *)self) + 0x0C) += 1;

        /* Increment total count */
        *(unsigned int *)(((char *)self) + 0x18) += 1;

        [lockObj unlock];

        /* Move to next entry */
        bufferEntry += entrySize;
    }

    return self;
}

/*
 * Free resources
 */
- (void)free
{
    id lockObj;
    unsigned char shutdownFlag;
    int freeCount;
    int totalCount;
    vm_address_t virtAddr;
    vm_size_t size;

    lockObj = *(id *)(((char *)self) + 0x24);
    shutdownFlag = *(unsigned char *)(((char *)self) + 5);

    if (shutdownFlag == 0) {
        /* Not already shutting down */

        /* Set shutdown flag */
        [lockObj lock];
        *(unsigned char *)(((char *)self) + 5) = 1;
        [lockObj unlock];

        /* Check if all buffers are returned */
        freeCount = *(int *)(((char *)self) + 0x0C);
        totalCount = *(int *)(((char *)self) + 0x18);

        if (freeCount != totalCount) {
            /* Not all buffers returned yet - delayed free */
            return;
        }

        /* All buffers returned - free immediately */
        [lockObj free];

        virtAddr = *(vm_address_t *)(((char *)self) + 0x20);
        size = *(vm_size_t *)(((char *)self) + 0x1C);
        IOFree((void *)virtAddr, size);
    } else {
        /* Already shutting down */

        /* Check if all buffers are returned */
        freeCount = *(int *)(((char *)self) + 0x0C);
        totalCount = *(int *)(((char *)self) + 0x18);

        if (freeCount != totalCount) {
            /* Not all buffers returned yet */
            return;
        }

        /* All buffers returned - free now */
        [lockObj free];

        virtAddr = *(vm_address_t *)(((char *)self) + 0x20);
        size = *(vm_size_t *)(((char *)self) + 0x1C);
        IOFree((void *)virtAddr, size);

        IOLog("Intel82556Buf: delayed free accomplished\n");
    }

    /* Call superclass free */
    return [super free];
}

/*
 * Get a network buffer
 */
- (void *)getNetBuffer
{
    return _getNetBuffer(self);
}

/*
 * Get number of free buffers
 */
- (unsigned int)numFree
{
    return *(unsigned int *)(((char *)self) + 0x0C);
}

@end

/*
 * Static helper function to get a buffer from the pool
 *
 * Pool structure:
 *   +0x08: Head pointer (free list)
 *   +0x0C: Free count
 *   +0x14: Actual buffer size
 *   +0x24: Lock object
 *
 * Buffer entry:
 *   +0x0C: Next pointer
 *   +0x14: Start of actual buffer data
 */
static void *_getNetBuffer(id pool)
{
    id lockObj;
    unsigned int *entry;
    unsigned int next;
    void *buffer = NULL;

    lockObj = *(id *)(((char *)pool) + 0x24);

    [lockObj lock];

    /* Get head of free list */
    entry = *(unsigned int **)(((char *)pool) + 8);

    if (entry != NULL) {
        /* Get next pointer from entry */
        next = entry[3];  /* +0x0C offset / 4 = index 3 */

        /* Update head to next */
        *(unsigned int *)(((char *)pool) + 8) = next;

        /* Decrement free count */
        *(unsigned int *)(((char *)pool) + 0x0C) -= 1;

        /* Buffer data starts at offset +0x14 from entry */
        buffer = (void *)((unsigned char *)entry + 0x14);
    }

    [lockObj unlock];

    return buffer;
}
