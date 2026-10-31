#ifndef I596_TEST_SUPPORT_H
#define I596_TEST_SUPPORT_H

#include <setjmp.h>
#import "Intel82596Buf.h"

extern unsigned int page_size;
extern unsigned int page_mask;
extern unsigned int i596_test_iomalloc_fail;
extern unsigned int i596_test_nb_alloc_fail;
extern unsigned int i596_test_iofree_calls;
extern unsigned int i596_test_panic_calls;
extern unsigned int i596_test_lock_calls;
extern unsigned int i596_test_unlock_calls;
extern char i596_test_events[128];
extern unsigned int i596_test_event_count;
extern jmp_buf i596_test_panic_target;

void i596_test_free_netbuf(netbuf_t netbuf);
void i596_test_corrupt_guard(netbuf_t netbuf, int endGuard);
void i596_test_restore_guards(netbuf_t netbuf);
void i596_test_reset_counts(void);

#endif
