/* Test-only process accounting boundary for production buffer traversal. */
extern struct proc *ext2_test_proc(void);
#define current_proc() ext2_test_proc()
