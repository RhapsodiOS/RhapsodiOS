#import "test_support.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned int failures;
static unsigned int checks;
#define LAYOUT(pool) (pool)

static void check(int ok, const char *name)
{
    ++checks;
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", name);
        ++failures;
    }
}

static Intel82556Buf *new_pool(unsigned int requested, unsigned int count,
                               unsigned int *actual)
{
    return [[Intel82556Buf alloc] initWithRequestedSize:requested
                                             actualSize:actual
                                                  count:count];
}

static void test_capacity_and_page_packing(void)
{
    unsigned int actual;
    unsigned int requested[] = {0, 1514, 1516, 1517};
    unsigned int expected[] = {1516, 1516, 1516, 1520};
    unsigned int i;
    Intel82556Buf *pool;

    for (i = 0; i < sizeof(requested) / sizeof(requested[0]); ++i) {
        actual = 0;
        pool = new_pool(requested[i], 3, &actual);
        check(pool != nil, "pool allocation succeeds");
        if (pool != nil) {
            check(actual == expected[i], "capacity minimum and four-byte rounding");
            check(LAYOUT(pool)->bufSizeUser == expected[i], "published capacity matches object");
            check(LAYOUT(pool)->bufSize == expected[i] + 24, "stride includes 24-byte prefix/guard");
            check(LAYOUT(pool)->bufCount == 4, "three requested standard buffers pack four slots");
            check(LAYOUT(pool)->numFree == 4, "all packed slots start on free list");
            {
                I556BufferNode *node = (I556BufferNode *)LAYOUT(pool)->freeList;
                unsigned int slots = 0;
                int pageSafe = 1;
                while (node != 0) {
                    unsigned int offset = (unsigned int)node & page_mask;
                    if (offset + LAYOUT(pool)->bufSize > page_size)
                        pageSafe = 0;
                    ++slots;
                    node = node->next;
                }
                check(slots == 4 && pageSafe, "no slot crosses a 4096-byte page");
            }
            [pool free];
        }
    }
}

static void test_allocation_failure(void)
{
    unsigned int actual = 0;
    i556_test_iomalloc_fail = 1;
    check(new_pool(1514, 2, &actual) == nil,
          "noncached allocation failure returns nil");
    check(actual == 1516, "capacity is reported before allocation failure");
}

static void test_page_boundary_sizes(void)
{
    unsigned int actual;
    Intel82556Buf *pool;

    pool = new_pool(4072, 1, &actual);
    check(pool != nil && actual == 4072, "4072-byte payload fits one page slot");
    if (pool != nil) {
        check(LAYOUT(pool)->bufSize == 4096 && LAYOUT(pool)->bufCount == 1,
              "4072-byte payload has 4096-byte stride");
        [pool free];
    }

    if (setjmp(i556_test_panic_target) == 0) {
        (void)new_pool(4073, 1, &actual);
        check(0, "4073-byte payload panics above page stride");
    } else {
        check(i556_test_panic_calls == 1, "oversized buffer takes reference panic path");
    }
}

static void test_wrapper_failure_and_reinitialization(void)
{
    unsigned int actual;
    unsigned int oldAllocSize;
    Intel82556Buf *pool = new_pool(1514, 3, &actual);
    netbuf_t netbuf;

    check(pool != nil, "pool exists for wrapper failure test");
    if (pool == nil)
        return;
    oldAllocSize = (unsigned int)LAYOUT(pool)->memSize;
    (void)[pool initWithRequestedSize:2048 actualSize:&actual count:10];
    check(LAYOUT(pool)->bufSizeUser == 1516 && (unsigned int)LAYOUT(pool)->memSize == oldAllocSize,
          "repeat init returns existing pool unchanged");

    i556_test_nb_alloc_fail = 1;
    netbuf = [pool getNetBuffer];
    check(netbuf == 0 && LAYOUT(pool)->numFree == 4,
          "wrapper failure restores node to free list");
    netbuf = [pool getNetBuffer];
    check(netbuf != 0 && LAYOUT(pool)->numFree == 3,
          "successful wrapper removes one node");
    i556_test_free_netbuf(netbuf);
    check(LAYOUT(pool)->numFree == 4, "callback recycles ordinary outstanding node");
    [pool free];
}

static void test_guard_validation(void)
{
    unsigned int actual;
    Intel82556Buf *pool = new_pool(1514, 1, &actual);
    netbuf_t netbuf;
    int guard;

    check(pool != nil, "pool exists for guard test");
    if (pool == nil)
        return;
    i556_test_reset_counts();
    for (guard = 0; guard != 2; ++guard) {
        netbuf = [pool getNetBuffer];
        check(netbuf != 0, "guard test receives a wrapper");
        if (netbuf == 0)
            continue;
        i556_test_corrupt_guard(netbuf, guard);
        if (setjmp(i556_test_panic_target) == 0) {
            i556_test_free_netbuf(netbuf);
            check(0, guard ? "end guard corruption panics" : "start guard corruption panics");
        } else {
            check(i556_test_panic_calls == (unsigned int)(guard + 1),
                  "corrupt guard takes the reference panic path");
            i556_test_restore_guards(netbuf);
            i556_test_free_netbuf(netbuf);
        }
    }
    [pool free];
}

static void test_delayed_free_with_outstanding_wrapper(void)
{
    unsigned int actual;
    Intel82556Buf *pool = new_pool(1514, 3, &actual);
    netbuf_t netbuf;
    netbuf_t second;
    void *oldHead;
    unsigned int freeCalls;
    unsigned int eventStart;

    check(pool != nil, "pool exists for deferred free test");
    if (pool == nil)
        return;
    netbuf = [pool getNetBuffer];
    check(netbuf != 0 && LAYOUT(pool)->numFree == 3, "wrapper is outstanding before shutdown");
    second = [pool getNetBuffer];
    oldHead = pool->freeList;
    freeCalls = i556_test_iofree_calls;
    eventStart = i556_test_event_count;
    check([pool free] == pool, "outstanding wrappers retain the pool object");
    check([pool free] == pool, "repeated free during shutdown retains the pool");
    check(i556_test_iofree_calls == freeCalls, "pool memory remains while wrappers are held");
    i556_test_free_netbuf(second);
    check(i556_test_iofree_calls == freeCalls && pool->freeList == oldHead,
          "shutdown callback counts a returned node without relinking or premature free");
    i556_test_free_netbuf(netbuf);
    check(i556_test_iofree_calls == freeCalls + 1,
          "last recycle releases the allocation exactly once");
    check(i556_test_event_count - eventStart == 8 &&
          i556_test_events[eventStart + 0] == 'L' &&
          i556_test_events[eventStart + 1] == 'U' &&
          i556_test_events[eventStart + 2] == 'L' &&
          i556_test_events[eventStart + 3] == 'U' &&
          i556_test_events[eventStart + 4] == 'L' &&
          i556_test_events[eventStart + 5] == 'U' &&
          i556_test_events[eventStart + 6] == 'F' &&
          i556_test_events[eventStart + 7] == 'I',
          "deferred release follows lock/unlock, lock free, allocation free");
}

static void test_exhaustion(void)
{
    unsigned int actual;
    Intel82556Buf *pool = new_pool(1514, 3, &actual);
    netbuf_t held[4];
    unsigned int i;
    check(pool != nil, "pool exists for exhaustion test");
    if (pool == nil) return;
    for (i = 0; i != 4; ++i) held[i] = [pool getNetBuffer];
    check([pool numFree] == 0 && [pool getNetBuffer] == 0,
          "empty pool returns null without decrementing free count");
    for (i = 0; i != 4; ++i) i556_test_free_netbuf(held[i]);
    check([pool numFree] == 4, "exhausted pool recovers all returned wrappers");
    [pool free];
}

static void test_native_page_size(void)
{
    unsigned int actual;
    Intel82556Buf *pool;
    page_size = 8192;
    page_mask = 8191;
    pool = new_pool(1518, 6, &actual);
    check(pool != nil && actual == 1520, "native 8192-byte page capacity");
    if (pool != nil) {
        I556BufferNode *node = pool->freeList;
        unsigned int slots = 0;
        int pageSafe = 1;
        while (node != 0) {
            if (((unsigned int)node & page_mask) + pool->bufSize > page_size)
                pageSafe = 0;
            ++slots;
            node = node->next;
        }
        check(slots == 10 && pool->numFree == 10 && pageSafe,
              "six requested buffers pack ten slots on two native pages");
        [pool free];
    }
    page_size = 4096;
    page_mask = 4095;
}

int main(void)
{
    check(sizeof(I556BufferNode) == 20, "buffer prefix is twenty bytes");
    test_capacity_and_page_packing();
    test_page_boundary_sizes();
    test_wrapper_failure_and_reinitialization();
    test_allocation_failure();
    test_guard_validation();
    test_delayed_free_with_outstanding_wrapper();
    test_exhaustion();
    test_native_page_size();
    if (failures != 0) {
        fprintf(stderr, "%u pool checks failed\n", failures);
        return 1;
    }
    printf("pool: %u reference-derived checks passed\n", checks);
    return 0;
}
