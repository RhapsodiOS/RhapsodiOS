#include <stddef.h>
#include <stdio.h>

#include "Intel82596Layout.h"

#define CHECK_LAYOUT(name, expression) \
    typedef char name[(expression) ? 1 : -1]

CHECK_LAYOUT(pointer_must_be_i386, sizeof(void *) == 4);
CHECK_LAYOUT(scp_size, sizeof(I596SCP) == 12);
CHECK_LAYOUT(iscp_size, sizeof(I596ISCP) == 8);
CHECK_LAYOUT(scb_size, sizeof(I596SCB) == 40);
CHECK_LAYOUT(rfd_size, sizeof(I596RFD) == 64);
CHECK_LAYOUT(rbd_in_rfd, offsetof(I596RFD, rbd) == 40);
CHECK_LAYOUT(rbd_size, sizeof(I596RBD) == 24);
CHECK_LAYOUT(tcb_size, sizeof(I596TCB) == 0x6c);
CHECK_LAYOUT(tcb_tbd, offsetof(I596TCB, tbd) == 32);
CHECK_LAYOUT(tcb_netbuf, offsetof(I596TCB, netbuf) == 104);
CHECK_LAYOUT(tbd_size, sizeof(I596TBD) == 0x18);
CHECK_LAYOUT(node_owner, offsetof(I596BufferNode, owner) == 0);
CHECK_LAYOUT(node_guard, offsetof(I596BufferNode, startGuard) == 4);
CHECK_LAYOUT(node_netbuf, offsetof(I596BufferNode, netbuf) == 8);
CHECK_LAYOUT(node_link, offsetof(I596BufferNode, next) == 12);
CHECK_LAYOUT(node_end_guard, offsetof(I596BufferNode, endGuard) == 16);
CHECK_LAYOUT(node_data, sizeof(I596BufferNode) == 20);
CHECK_LAYOUT(base_io, offsetof(I596BaseLayout, ioBase) == 372);
CHECK_LAYOUT(base_irq, offsetof(I596BaseLayout, irq) == 376);
CHECK_LAYOUT(base_mac, offsetof(I596BaseLayout, myAddress) == 380);
CHECK_LAYOUT(base_scp, offsetof(I596BaseLayout, scp) == 436);
CHECK_LAYOUT(base_full_duplex, offsetof(I596BaseLayout, fullDuplexMode) == 508);
CHECK_LAYOUT(base_size, sizeof(I596BaseLayout) == 512);
CHECK_LAYOUT(pool_init, offsetof(I596BufLayout, initFlag) == 4);
CHECK_LAYOUT(pool_shutdown, offsetof(I596BufLayout, freeInProgress) == 5);
CHECK_LAYOUT(pool_list, offsetof(I596BufLayout, freeList) == 8);
CHECK_LAYOUT(pool_free_count, offsetof(I596BufLayout, numFree) == 12);
CHECK_LAYOUT(pool_stride, offsetof(I596BufLayout, bufSize) == 16);
CHECK_LAYOUT(pool_capacity, offsetof(I596BufLayout, bufSizeUser) == 20);
CHECK_LAYOUT(pool_count, offsetof(I596BufLayout, bufCount) == 24);
CHECK_LAYOUT(pool_allocation, offsetof(I596BufLayout, memPtr) == 28);
CHECK_LAYOUT(pool_allocation_size, offsetof(I596BufLayout, memSize) == 32);
CHECK_LAYOUT(pool_lock, offsetof(I596BufLayout, freeListLock) == 36);
CHECK_LAYOUT(pool_size, sizeof(I596BufLayout) == 40);

int main(void)
{
    puts("layout: 33 i386 ABI assertions passed");
    return 0;
}
