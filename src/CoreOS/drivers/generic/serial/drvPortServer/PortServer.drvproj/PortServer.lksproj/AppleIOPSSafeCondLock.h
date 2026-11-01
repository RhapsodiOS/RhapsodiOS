/*
 * AppleIOPSSafeCondLock.h
 * Safe condition lock interface for PortServer driver
 * 
 * Provides both Objective-C class and C wrapper functions
 */

#ifndef _APPLEIOPSSAFECONDLOCK_H_
#define _APPLEIOPSSAFECONDLOCK_H_

#import <objc/Object.h>

/* ========================================================================
 * Objective-C Class Definition
 * ======================================================================== */

/* The interlock shape carried by the shipped class metadata, whose @encode
 * is {?="locked"I} - a 4-byte anonymous struct with one unsigned int member
 * named "locked" (the NeXT simple_lock layout).
 */
typedef struct {
    unsigned int locked;
} AIOPSSCLInterlock;

@interface AppleIOPSSafeCondLock : Object
{
    /* Instance variables - actual lock state */
    AIOPSSCLInterlock cond_interlock;   /* +4:  guards conditionVar */
    int conditionVar;                   /* +8:  current condition value */
    AIOPSSCLInterlock sleep_interlock;  /* +c:  guards want_lock/waiting */
    char interuptable;                  /* +10: sleeps may be interrupted */
    char want_lock;                     /* +11: lock is held */
    char waiting;                       /* +12: a thread waits on the lock */
}

/* Class methods */

/* Called once when class is first used - caches method IMPs for performance */
+ (id)initialize;

/* Initialization methods */

/* Initialize with default condition (0) and non-interruptible */
- init;

/* Initialize with specific condition value */
- initWith:(int)condition;

/* Initialize with condition and interruptible flag */
- initWith:(int)condition intr:(BOOL)interruptible;

/* Cleanup */
- free;

/* Lock query methods */

/* Get current condition value */
- (int)condition;

/* Check if lock is interruptible */
- (BOOL)interuptable;

/* Lock operations */

/* Acquire lock (blocking) - returns 0 on success, non-zero if interrupted */
- (int)lock;

/* Try to acquire lock without blocking - returns YES if acquired */
- (BOOL)lockTry;

/* Acquire lock when condition equals specific value (blocking)
 * Returns 0 on success, non-zero if interrupted
 */
- (int)lockWhen:(int)condition;

/* Unlock operations */

/* Release lock - returns self */
- unlock;

/* Release lock and set new condition value - returns self */
- unlockWith:(int)condition;

/* Condition operations */

/* Set condition value (may signal waiters) - returns self */
- setCondition:(int)condition;

@end


/* ========================================================================
 * C Wrapper Functions
 * ======================================================================== */

/* Get current condition value
 * Calls: [lock condition]
 * Returns: Integer condition value
 */
int AIOPSSCL_condition(id lock);

/* Check if lock is interruptible
 * Calls: [lock interuptable]
 * Returns: Non-zero if interruptible, 0 otherwise
 */
int AIOPSSCL_interuptable(id lock);

/* Acquire lock
 * Calls: [lock lock]
 * Blocks until lock is available
 * Returns: 0 on success, non-zero if the wait was interrupted
 */
int AIOPSSCL_lock(id lock);

/* Try to acquire lock without blocking
 * Calls: [lock lockTry]
 * Returns: Non-zero if lock was acquired, 0 if already locked
 */
int AIOPSSCL_lockTry(id lock);

/* Acquire lock when condition equals specified value
 * Calls: [lock lockWhen:condition]
 * Blocks until lock is available AND condition matches
 * Returns: 0 on success, non-zero if the wait was interrupted
 */
int AIOPSSCL_lockWhen(id lock, int condition);

/* Set/notify condition
 * Calls: [lock setCondition]
 * Note: No parameter - this may trigger condition notification
 */
void AIOPSSCL_setCondition(id lock);

/* Release lock
 * Calls: [lock unlock]
 * Unlocks the lock and may wake waiting threads
 * Returns: the lock object
 */
id AIOPSSCL_unlock(id lock);

/* Release lock and set condition
 * Calls: [lock unlockWith:condition]
 * Atomically sets condition and unlocks
 * Returns: the lock object
 */
id AIOPSSCL_unlockWith(id lock, int condition);

#endif /* _APPLEIOPSSAFECONDLOCK_H_ */
