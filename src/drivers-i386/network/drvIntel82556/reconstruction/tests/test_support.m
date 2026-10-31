#import "test_support.h"
#import <driverkit/generalFuncs.h>
#import <mach/mach_interface.h>
#import <mach/vm_param.h>
#import <net/netbuf.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

unsigned int page_size = 4096;
unsigned int page_mask = 4095;
unsigned int i556_test_iomalloc_fail;
unsigned int i556_test_nb_alloc_fail;
unsigned int i556_test_iofree_calls;
unsigned int i556_test_panic_calls;
unsigned int i556_test_lock_calls;
unsigned int i556_test_unlock_calls;
char i556_test_events[128];
unsigned int i556_test_event_count;
jmp_buf i556_test_panic_target;

typedef struct {
    void *data;
    unsigned int size;
    void (*freeFunc)(void *);
    void *freeArg;
} TestNetbuf;

@implementation I556TestSpinLock
- (void)lock { ++i556_test_lock_calls; i556_test_events[i556_test_event_count++] = 'L'; }
- (void)unlock { ++i556_test_unlock_calls; i556_test_events[i556_test_event_count++] = 'U'; }
- free { i556_test_events[i556_test_event_count++] = 'F'; return [super free]; }
@end

void *IOMalloc(int size)
{
    if (i556_test_iomalloc_fail != 0) {
        --i556_test_iomalloc_fail;
        return 0;
    }
    return malloc((size_t)size);
}

void IOFree(void *address, int size)
{
    (void)size;
    ++i556_test_iofree_calls;
    i556_test_events[i556_test_event_count++] = 'I';
    free(address);
}

void IOPanic(const char *message)
{
    (void)message;
    ++i556_test_panic_calls;
    longjmp(i556_test_panic_target, 1);
}

void IOLog(const char *format, ...)
{
    (void)format;
}

vm_task_t IOVmTaskSelf(void) { return (vm_task_t)0; }

IOReturn IOPhysicalFromVirtual(vm_task_t task, vm_address_t virtualAddress,
                               vm_offset_t *physicalAddress)
{
    (void)task;
    *physicalAddress = virtualAddress + 0x01000000;
    return IO_R_SUCCESS;
}

netbuf_t nb_alloc_wrapper(void *data, unsigned int size,
                          void (*freeFunc)(void *), void *freeArg)
{
    TestNetbuf *netbuf;
    if (i556_test_nb_alloc_fail != 0) {
        --i556_test_nb_alloc_fail;
        return 0;
    }
    netbuf = (TestNetbuf *)malloc(sizeof(*netbuf));
    if (netbuf == 0)
        return 0;
    netbuf->data = data;
    netbuf->size = size;
    netbuf->freeFunc = freeFunc;
    netbuf->freeArg = freeArg;
    return (netbuf_t)netbuf;
}

void nb_free(netbuf_t opaque)
{
    TestNetbuf *netbuf = (TestNetbuf *)opaque;
    void (*freeFunc)(void *, unsigned int, void *);
    freeFunc = (void (*)(void *, unsigned int, void *))netbuf->freeFunc;
    freeFunc(netbuf->data, netbuf->size, netbuf->freeArg);
    free(netbuf);
}

void i556_test_free_netbuf(netbuf_t netbuf) { nb_free(netbuf); }

void i556_test_corrupt_guard(netbuf_t opaque, int endGuard)
{
    TestNetbuf *netbuf = (TestNetbuf *)opaque;
    I556BufferNode *node = (I556BufferNode *)((char *)netbuf->data - 20);
    if (endGuard)
        *node->endGuard = 0;
    else
        node->startGuard = 0;
}

void i556_test_restore_guards(netbuf_t opaque)
{
    TestNetbuf *netbuf = (TestNetbuf *)opaque;
    I556BufferNode *node = (I556BufferNode *)((char *)netbuf->data - 20);
    node->startGuard = I556_BUFFER_GUARD;
    *node->endGuard = I556_BUFFER_GUARD;
}

void i556_test_reset_counts(void)
{
    i556_test_iofree_calls = 0;
    i556_test_panic_calls = 0;
    i556_test_lock_calls = 0;
    i556_test_unlock_calls = 0;
    i556_test_event_count = 0;
}


/* Exercise the reference allocator's extra-page and alignment contract. */
void *IOMallocNonCached(int size, void **allocation, int *allocationSize)
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
