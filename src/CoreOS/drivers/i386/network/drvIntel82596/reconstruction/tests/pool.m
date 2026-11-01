#import "test_support.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned int failures;
static unsigned int checks;
#define LAYOUT(pool) ((I596BufLayout *)(pool))

static void check(int ok, const char *name)
{
    ++checks;
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", name);
        ++failures;
    }
}

static Intel82596Buf *new_pool(unsigned int requested, unsigned int count,
                               unsigned int *actual)
{
    return [[Intel82596Buf alloc] initWithRequestedSize:requested
                                             actualSize:actual
                                                  count:count];
}

static void test_capacity_and_page_packing(void)
{
    unsigned int actual;
    unsigned int requested[] = {0, 1514, 1516, 1517};
    unsigned int expected[] = {1516, 1516, 1516, 1520};
    unsigned int i;
    Intel82596Buf *pool;

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
                I596BufferNode *node = (I596BufferNode *)LAYOUT(pool)->freeList;
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
    i596_test_iomalloc_fail = 1;
    check(new_pool(1514, 2, &actual) == nil,
          "noncached allocation failure returns nil");
    check(actual == 1516, "capacity is reported before allocation failure");
}

static void test_page_boundary_sizes(void)
{
    unsigned int actual;
    Intel82596Buf *pool;

    pool = new_pool(4072, 1, &actual);
    check(pool != nil && actual == 4072, "4072-byte payload fits one page slot");
    if (pool != nil) {
        check(LAYOUT(pool)->bufSize == 4096 && LAYOUT(pool)->bufCount == 1,
              "4072-byte payload has 4096-byte stride");
        [pool free];
    }

    if (setjmp(i596_test_panic_target) == 0) {
        (void)new_pool(4073, 1, &actual);
        check(0, "4073-byte payload panics above page stride");
    } else {
        check(i596_test_panic_calls == 1, "oversized buffer takes reference panic path");
    }
}

static void test_wrapper_failure_and_reinitialization(void)
{
    unsigned int actual;
    unsigned int oldAllocSize;
    Intel82596Buf *pool = new_pool(1514, 3, &actual);
    netbuf_t netbuf;

    check(pool != nil, "pool exists for wrapper failure test");
    if (pool == nil)
        return;
    oldAllocSize = (unsigned int)LAYOUT(pool)->memSize;
    (void)[pool initWithRequestedSize:2048 actualSize:&actual count:10];
    check(LAYOUT(pool)->bufSizeUser == 1516 && (unsigned int)LAYOUT(pool)->memSize == oldAllocSize,
          "repeat init returns existing pool unchanged");

    i596_test_nb_alloc_fail = 1;
    netbuf = [pool getNetBuffer];
    check(netbuf == 0 && LAYOUT(pool)->numFree == 4,
          "wrapper failure restores node to free list");
    netbuf = [pool getNetBuffer];
    check(netbuf != 0 && LAYOUT(pool)->numFree == 3,
          "successful wrapper removes one node");
    i596_test_free_netbuf(netbuf);
    check(LAYOUT(pool)->numFree == 4, "callback recycles ordinary outstanding node");
    [pool free];
}

static void test_guard_validation(void)
{
    unsigned int actual;
    Intel82596Buf *pool = new_pool(1514, 1, &actual);
    netbuf_t netbuf;
    int guard;

    check(pool != nil, "pool exists for guard test");
    if (pool == nil)
        return;
    i596_test_reset_counts();
    for (guard = 0; guard != 2; ++guard) {
        netbuf = [pool getNetBuffer];
        check(netbuf != 0, "guard test receives a wrapper");
        if (netbuf == 0)
            continue;
        i596_test_corrupt_guard(netbuf, guard);
        if (setjmp(i596_test_panic_target) == 0) {
            i596_test_free_netbuf(netbuf);
            check(0, guard ? "end guard corruption panics" : "start guard corruption panics");
        } else {
            check(i596_test_panic_calls == (unsigned int)(guard + 1),
                  "corrupt guard takes the reference panic path");
            i596_test_restore_guards(netbuf);
            i596_test_free_netbuf(netbuf);
        }
    }
    [pool free];
}

static void test_delayed_free_with_outstanding_wrapper(void)
{
    unsigned int actual;
    Intel82596Buf *pool = new_pool(1514, 3, &actual);
    netbuf_t netbuf;
    unsigned int freeCalls;
    unsigned int eventStart;

    check(pool != nil, "pool exists for deferred free test");
    if (pool == nil)
        return;
    netbuf = [pool getNetBuffer];
    check(netbuf != 0 && LAYOUT(pool)->numFree == 3, "wrapper is outstanding before shutdown");
    freeCalls = i596_test_iofree_calls;
    eventStart = i596_test_event_count;
    [pool free];
    check(i596_test_iofree_calls == freeCalls, "pool memory remains while wrapper is held");
    i596_test_free_netbuf(netbuf);
    check(i596_test_iofree_calls == freeCalls + 1,
          "last recycle releases the allocation exactly once");
    check(i596_test_event_count - eventStart == 6 &&
          i596_test_events[eventStart + 0] == 'L' &&
          i596_test_events[eventStart + 1] == 'U' &&
          i596_test_events[eventStart + 2] == 'L' &&
          i596_test_events[eventStart + 3] == 'U' &&
          i596_test_events[eventStart + 4] == 'F' &&
          i596_test_events[eventStart + 5] == 'I',
          "deferred release follows lock/unlock, lock free, allocation free");
}

int main(void)
{
    test_capacity_and_page_packing();
    test_page_boundary_sizes();
    test_wrapper_failure_and_reinitialization();
    test_allocation_failure();
    test_guard_validation();
    test_delayed_free_with_outstanding_wrapper();
    if (failures != 0) {
        fprintf(stderr, "%u pool checks failed\n", failures);
        return 1;
    }
    printf("pool: %u reference-derived checks passed\n", checks);
    return 0;
}
