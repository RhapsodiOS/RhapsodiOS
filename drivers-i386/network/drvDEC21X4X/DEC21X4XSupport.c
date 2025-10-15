/*
 * DEC21X4XSupport.c
 * Supporting C functions for DEC21X4X Network Driver
 * Based on binary exports from DEC21X4XNetwork_reloc
 */

#include <sys/types.h>
#include <sys/param.h>
#include <mach/vm_param.h>
#include <net/netbuf.h>
#include <objc/objc-runtime.h>

/*
 * Page mask - returns the page alignment mask
 * Used for DMA buffer alignment
 */
unsigned int dec21x4x_page_mask(void)
{
    /* Returns page mask for memory alignment */
    /* PAGE_MASK is typically PAGE_SIZE - 1 */
    return PAGE_MASK;
}

/*
 * Page size - returns the system page size
 */
unsigned int dec21x4x_page_size(void)
{
    /* Returns system page size */
    /* Typically 4096 (i386) or 8192 (ppc) bytes */
    return PAGE_SIZE;
}

/*
 * Network buffer allocation wrapper
 * Allocates a network buffer of the specified size
 */
netbuf_t dec21x4x_nb_alloc(unsigned int size)
{
    /* Allocate network buffer using kernel API */
    return nb_alloc(size);
}

/*
 * Network buffer free wrapper
 * Frees a previously allocated network buffer
 */
void dec21x4x_nb_free(netbuf_t nb)
{
    /* Free network buffer using kernel API */
    if (nb) {
        nb_free(nb);
    }
}

/*
 * Network buffer allocation and free combined function
 * This is a utility function that handles both operations
 */
void dec21x4x_nb_alloc_np_free(void)
{
    /* This appears to be a placeholder or wrapper function */
    /* Actual allocation/free operations should use the individual functions */
}

/*
 * Network buffer grow bottom
 * Expands the network buffer from the bottom by adding space
 * Returns 0 on success, -1 on failure
 */
int dec21x4x_nb_grow_bot(netbuf_t nb, unsigned int size)
{
    /* Grow network buffer from bottom */
    /* Used to add header space at the beginning of the buffer */
    if (!nb) {
        return -1;
    }
    return nb_grow_bot(nb, size);
}

/*
 * Network buffer grow top
 * Expands the network buffer from the top by adding space
 * Returns 0 on success, -1 on failure
 */
int dec21x4x_nb_grow_top(netbuf_t nb, unsigned int size)
{
    /* Grow network buffer from top */
    /* Used to add trailer space at the end of the buffer */
    if (!nb) {
        return -1;
    }
    return nb_grow_top(nb, size);
}

/*
 * Network buffer map
 * Maps network buffer to return a pointer to the data
 * Returns pointer to buffer data
 */
void *dec21x4x_nb_map(netbuf_t nb)
{
    /* Map network buffer to get data pointer */
    /* Required for DMA operations and direct memory access */
    if (!nb) {
        return NULL;
    }
    return nb_map(nb);
}

/*
 * Network buffer shrink bottom
 * Reduces the network buffer from the bottom by removing space
 * Returns 0 on success, -1 on failure
 */
int dec21x4x_nb_shrink_bot(netbuf_t nb, unsigned int size)
{
    /* Shrink network buffer from bottom */
    /* Used to remove header space from the beginning */
    if (!nb) {
        return -1;
    }
    return nb_shrink_bot(nb, size);
}

/*
 * Network buffer shrink top
 * Reduces the network buffer from the top by removing space
 * Returns 0 on success, -1 on failure
 */
int dec21x4x_nb_shrink_top(netbuf_t nb, unsigned int size)
{
    /* Shrink network buffer from top */
    /* Used to remove trailer space from the end */
    if (!nb) {
        return -1;
    }
    return nb_shrink_top(nb, size);
}

/*
 * Network buffer size
 * Returns the current size of the network buffer
 */
unsigned int dec21x4x_nb_size(netbuf_t nb)
{
    /* Get network buffer size */
    if (!nb) {
        return 0;
    }
    return nb_size(nb);
}

/*
 * Message super with page mask
 * Sends message to superclass with page alignment parameter
 * This is used for calling superclass methods with proper alignment
 */
id dec21x4x_msgSuper_page_mask(struct objc_super *super, SEL selector, unsigned int page_mask)
{
    /* Send message to superclass */
    /* With page mask parameter for proper memory alignment */
    if (!super || !selector) {
        return nil;
    }

    /* Call superclass method using objc runtime */
    return objc_msgSendSuper(super, selector, page_mask);
}

/*
 * Utility: Get physical address from virtual address
 * Used for setting up DMA descriptors
 */
unsigned int dec21x4x_vtophys(void *vaddr)
{
    /* Convert virtual address to physical address */
    /* This is critical for DMA operations */
    if (!vaddr) {
        return 0;
    }

    /* On i386, we can often use the address directly in low memory */
    /* For more complex systems, this would use pmap functions */
    return (unsigned int)vaddr;
}

/*
 * Utility: Cache flush for DMA coherency
 * Ensures cache coherency before DMA operations
 */
void dec21x4x_cache_flush(void *addr, unsigned int size)
{
    /* Flush cache to ensure DMA coherency */
    /* On i386, this is typically a no-op due to cache coherency */
    /* On PowerPC, this would flush data cache */

    /* Implementation depends on architecture */
#ifdef __ppc__
    /* PowerPC requires explicit cache flushing */
    flush_dcache((vm_offset_t)addr, size, 1);
#endif
    /* i386 has hardware cache coherency, no action needed */
}

/*
 * Utility: Allocate aligned DMA buffer
 * Allocates memory suitable for DMA with proper alignment
 */
void *dec21x4x_alloc_dma_buffer(unsigned int size, unsigned int alignment)
{
    void *buffer;
    unsigned int alloc_size;
    void *orig_buffer;

    /* Allocate extra space to ensure alignment */
    alloc_size = size + alignment;

    /* Allocate buffer */
    orig_buffer = (void *)kalloc(alloc_size);
    if (!orig_buffer) {
        return NULL;
    }

    /* Align buffer to requested boundary */
    buffer = (void *)(((unsigned int)orig_buffer + alignment - 1) & ~(alignment - 1));

    return buffer;
}

/*
 * Utility: Free DMA buffer
 * Frees memory allocated for DMA
 */
void dec21x4x_free_dma_buffer(void *buffer, unsigned int size)
{
    if (buffer) {
        kfree(buffer, size);
    }
}

/*
 * Utility: Copy data to network buffer
 * Safely copies data into a network buffer
 */
int dec21x4x_nb_write_data(netbuf_t nb, unsigned int offset, void *data, unsigned int size)
{
    if (!nb || !data) {
        return -1;
    }

    /* Use kernel netbuf write function */
    return nb_write(nb, offset, size, data);
}

/*
 * Utility: Copy data from network buffer
 * Safely copies data from a network buffer
 */
int dec21x4x_nb_read_data(netbuf_t nb, unsigned int offset, void *data, unsigned int size)
{
    if (!nb || !data) {
        return -1;
    }

    /* Use kernel netbuf read function */
    return nb_read(nb, offset, size, data);
}
