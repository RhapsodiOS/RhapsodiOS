#import "Intel82556.h"
#include <stddef.h>
#include <stdio.h>

struct MainLayout { @defs(Intel82556); };
struct PoolLayout { @defs(Intel82556Buf); };
static int failures;
#define CHECK_SIZE(type, bytes) check(sizeof(type) == bytes, #type " size")
#define CHECK_OFFSET(type, member, bytes) check(offsetof(type, member) == bytes, #type "." #member)
static void check(int ok, const char *name)
{
    if (!ok) { fprintf(stderr, "FAIL: %s\n", name); ++failures; }
}
int main(void)
{
    CHECK_SIZE(I556SCP, 12);
    CHECK_SIZE(I556ISCP, 8);
    CHECK_SIZE(I556SCB, 44);
    CHECK_SIZE(I556SelfTest, 8);
    CHECK_SIZE(I556TBD, 16);
    CHECK_SIZE(I556TCB, 68);
    CHECK_SIZE(I556RBD, 28);
    CHECK_SIZE(I556RFD, 72);
    CHECK_SIZE(I556Command, 68);
    CHECK_SIZE(struct MainLayout, 512);
    CHECK_OFFSET(struct MainLayout, ioBase, 372);
    CHECK_OFFSET(struct MainLayout, irq, 376);
    CHECK_OFFSET(struct MainLayout, myAddress, 380);
    CHECK_OFFSET(struct MainLayout, networkInterface, 388);
    CHECK_OFFSET(struct MainLayout, bufferPool, 392);
    CHECK_OFFSET(struct MainLayout, transmitQueue, 396);
    CHECK_OFFSET(struct MainLayout, promiscuousEnabled, 400);
    CHECK_OFFSET(struct MainLayout, multicastEnabled, 401);
    CHECK_OFFSET(struct MainLayout, allMulticastEnabled, 402);
    CHECK_OFFSET(struct MainLayout, multicastConfigured, 403);
    CHECK_OFFSET(struct MainLayout, sourceAddressInsertion, 404);
    CHECK_OFFSET(struct MainLayout, resetAndEnabled, 405);
    CHECK_OFFSET(struct MainLayout, sharedMemPtr, 408);
    CHECK_OFFSET(struct MainLayout, sharedMemSize, 412);
    CHECK_OFFSET(struct MainLayout, sharedMemAllocPtr, 416);
    CHECK_OFFSET(struct MainLayout, sharedMemAvail, 420);
    CHECK_OFFSET(struct MainLayout, sharedMem_actualPtr, 424);
    CHECK_OFFSET(struct MainLayout, sharedMem_actualSize, 428);
    CHECK_OFFSET(struct MainLayout, scp_p, 432);
    CHECK_OFFSET(struct MainLayout, iscp_p, 436);
    CHECK_OFFSET(struct MainLayout, scb_p, 440);
    CHECK_OFFSET(struct MainLayout, selfTest_p, 444);
    CHECK_OFFSET(struct MainLayout, cbl_p, 448);
    CHECK_OFFSET(struct MainLayout, cbl_paddr, 452);
    CHECK_OFFSET(struct MainLayout, tcbList_p, 456);
    CHECK_OFFSET(struct MainLayout, headFreeTcb, 460);
    CHECK_OFFSET(struct MainLayout, activeTcbHead, 464);
    CHECK_OFFSET(struct MainLayout, pendingTcbHead, 468);
    CHECK_OFFSET(struct MainLayout, pendingTcbTail, 472);
    CHECK_OFFSET(struct MainLayout, KDB_tcb_p, 476);
    CHECK_OFFSET(struct MainLayout, KDB_buf_p, 480);
    CHECK_OFFSET(struct MainLayout, KDB_buf_paddr, 484);
    CHECK_OFFSET(struct MainLayout, rfdList_p, 488);
    CHECK_OFFSET(struct MainLayout, headRfd, 492);
    CHECK_OFFSET(struct MainLayout, tailRfd, 496);
    CHECK_OFFSET(struct MainLayout, fullDuplexMode, 500);
    CHECK_OFFSET(struct MainLayout, dataRate, 504);
    CHECK_OFFSET(struct MainLayout, autoSpeedDetect, 508);
    CHECK_SIZE(struct PoolLayout, 40);
    CHECK_OFFSET(struct PoolLayout, initFlag, 4);
    CHECK_OFFSET(struct PoolLayout, freeInProgress, 5);
    CHECK_OFFSET(struct PoolLayout, freeList, 8);
    CHECK_OFFSET(struct PoolLayout, numFree, 12);
    CHECK_OFFSET(struct PoolLayout, bufSize, 16);
    CHECK_OFFSET(struct PoolLayout, bufSizeUser, 20);
    CHECK_OFFSET(struct PoolLayout, bufCount, 24);
    CHECK_OFFSET(struct PoolLayout, memPtr, 28);
    CHECK_OFFSET(struct PoolLayout, memSize, 32);
    CHECK_OFFSET(struct PoolLayout, freeListLock, 36);
    CHECK_OFFSET(I556TCB, next, 24);
    CHECK_OFFSET(I556TCB, physical, 28);
    CHECK_OFFSET(I556TCB, tbd, 32);
    CHECK_OFFSET(I556TCB, netbuf, 64);
    CHECK_OFFSET(I556TBD, link, 4);
    CHECK_OFFSET(I556TBD, buffer, 8);
    CHECK_OFFSET(I556TBD, physical, 12);
    CHECK_OFFSET(I556RFD, next, 32);
    CHECK_OFFSET(I556RFD, physical, 36);
    CHECK_OFFSET(I556RFD, rbd, 40);
    CHECK_OFFSET(I556RFD, netbuf, 68);
    CHECK_OFFSET(I556RBD, link, 4);
    CHECK_OFFSET(I556RBD, buffer, 8);
    CHECK_OFFSET(I556RBD, size, 12);
    CHECK_OFFSET(I556RBD, end, 14);
    CHECK_OFFSET(I556RBD, next, 20);
    CHECK_OFFSET(I556RBD, physical, 24);
    if (failures) return 1;
    puts("layout: reference ivar offsets and descriptor layouts passed");
    return 0;
}
