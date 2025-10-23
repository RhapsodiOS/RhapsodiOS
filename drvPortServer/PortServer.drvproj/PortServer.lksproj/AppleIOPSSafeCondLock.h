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

@interface AppleIOPSSafeCondLock : Object
{
    /* Instance variables - actual lock state */
    int _condition;         /* Current condition value */
    BOOL _interruptible;    /* Whether lock can be interrupted */
    /* TODO: Add actual synchronization primitives:
     * - mutex/simple_lock for thread safety
     * - condition variable for waiting
     */
}

/* Class methods */

/* Called once when class is first used - caches method IMPs for performance */
+ (void)initialize;

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

/* Acquire lock (blocking) */
- (void)lock;

/* Try to acquire lock without blocking - returns YES if acquired */
- (BOOL)lockTry;

/* Acquire lock when condition equals specific value (blocking) */
- (void)lockWhen:(int)condition;

/* Unlock operations */

/* Release lock */
- (void)unlock;

/* Release lock and set new condition value */
- (void)unlockWith:(int)condition;

/* Condition operations */

/* Set condition value (may signal waiters) */
- (void)setCondition:(int)condition;

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
 */
void AIOPSSCL_lock(id lock);

/* Try to acquire lock without blocking
 * Calls: [lock lockTry]
 * Returns: Non-zero if lock was acquired, 0 if already locked
 */
int AIOPSSCL_lockTry(id lock);

/* Acquire lock when condition equals specified value
 * Calls: [lock lockWhen:condition]
 * Blocks until lock is available AND condition matches
 */
void AIOPSSCL_lockWhen(id lock, int condition);

/* Set/notify condition
 * Calls: [lock setCondition]
 * Note: No parameter - this may trigger condition notification
 */
void AIOPSSCL_setCondition(id lock);

/* Release lock
 * Calls: [lock unlock]
 * Unlocks the lock and may wake waiting threads
 */
void AIOPSSCL_unlock(id lock);

/* Release lock and set condition
 * Calls: [lock unlockWith:condition]
 * Atomically sets condition and unlocks
 */
void AIOPSSCL_unlockWith(id lock, int condition);

#endif /* _APPLEIOPSSAFECONDLOCK_H_ */
