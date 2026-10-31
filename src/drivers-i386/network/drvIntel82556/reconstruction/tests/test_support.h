#ifndef I556_TEST_SUPPORT_H
#define I556_TEST_SUPPORT_H

#include <setjmp.h>
#import "Intel82556.h"

typedef struct I556BufferNode {
    Intel82556Buf *owner;
    unsigned int startGuard;
    netbuf_t netbuf;
    struct I556BufferNode *next;
    unsigned int *endGuard;
} I556BufferNode;
#define I556_BUFFER_GUARD 0xcafe2badU
extern unsigned int page_size;
extern unsigned int page_mask;
extern unsigned int i556_test_iomalloc_fail;
extern unsigned int i556_test_nb_alloc_fail;
extern unsigned int i556_test_iofree_calls;
extern unsigned int i556_test_panic_calls;
extern unsigned int i556_test_lock_calls;
extern unsigned int i556_test_unlock_calls;
extern char i556_test_events[128];
extern unsigned int i556_test_event_count;
extern jmp_buf i556_test_panic_target;

void i556_test_free_netbuf(netbuf_t netbuf);
void i556_test_corrupt_guard(netbuf_t netbuf, int endGuard);
void i556_test_restore_guards(netbuf_t netbuf);
void i556_test_reset_counts(void);

#endif
