/*
 * AppleIOPSSafeCondLock.m
 * Safe condition lock implementation for PortServer driver
 *
 * Provides both Objective-C class implementation and C wrapper functions
 */

#import "AppleIOPSSafeCondLock.h"
#import <objc/objc-runtime.h>
#import <kern/lock.h>
#import <mach/machine/simple_lock.h>	/* the real inline simple_lock/simple_unlock */
#import <kern/thread.h>

/* ========================================================================
 * Global IMP Cache Variables
 * ======================================================================== */

/* Cached method implementations for performance optimization.
 * There is exactly one set; +initialize writes it and the C wrappers
 * below read it.
 */
static IMP IMP_interuptable;
static IMP IMP_condition;
static IMP IMP_setCondition;
static IMP IMP_unlock;
static IMP IMP_unlockWith;
static IMP IMP_lock;
static IMP IMP_lockTry;
static IMP IMP_lockWhen;

/* ========================================================================
 * Objective-C Class Implementation
 *
 * Each C wrapper is defined inside the @implementation block, immediately
 * ahead of the method it forwards to; that is the text order the shipped
 * driver has.
 * ======================================================================== */

@implementation AppleIOPSSafeCondLock

/*
 * initialize - Class initialization method
 * Called once when the class is first used
 * Caches IMP (function pointers) for all instance methods to improve performance
 */
+ (id)initialize
{
    /* Cache IMP for interuptable method */
    IMP_interuptable = objc_msgSend(self,
                                    @selector(instanceMethodFor:),
                                    @selector(interuptable));

    /* Cache IMP for condition method */
    IMP_condition = objc_msgSend(self,
                                 @selector(instanceMethodFor:),
                                 @selector(condition));

    /* Cache IMP for setCondition method.
     * The shipped driver asks for @selector(setCondition) - with no colon -
     * which this class does not implement, so the lookup yields the
     * forwarding IMP rather than -setCondition:. That is Apple's bug, not
     * ours; it is inert because nothing in the driver calls
     * AIOPSSCL_setCondition. Reproduced as shipped.
     */
    IMP_setCondition = objc_msgSend(self,
                                    @selector(instanceMethodFor:),
                                    @selector(setCondition));

    /* Cache IMP for unlock method */
    IMP_unlock = objc_msgSend(self,
                              @selector(instanceMethodFor:),
                              @selector(unlock));

    /* Cache IMP for unlockWith method */
    IMP_unlockWith = objc_msgSend(self,
                                  @selector(instanceMethodFor:),
                                  @selector(unlockWith:));

    /* Cache IMP for lock method */
    IMP_lock = objc_msgSend(self,
                            @selector(instanceMethodFor:),
                            @selector(lock));

    /* Cache IMP for lockTry method */
    IMP_lockTry = objc_msgSend(self,
                               @selector(instanceMethodFor:),
                               @selector(lockTry));

    /* Cache IMP for lockWhen method */
    IMP_lockWhen = objc_msgSend(self,
                                @selector(instanceMethodFor:),
                                @selector(lockWhen:));

    return self;
}

/*
 * init - Initialize with default values
 * Default condition: 0
 * Default interruptible: YES (1)
 * Calls initWith:intr: with condition=0, interruptible=YES
 */
- init
{
    return [self initWith:0 intr:YES];
}

/*
 * initWith: - Initialize with specific condition
 * Sets interruptible to YES (1) by default
 * Calls initWith:intr: with the given condition, interruptible=YES
 */
- initWith:(int)condition
{
    return [self initWith:condition intr:YES];
}

/*
 * initWith:intr: - Initialize with condition and interruptible flag
 * This is the designated initializer that does the actual initialization
 *
 * [super init]'s result is discarded; the method returns self.
 * interuptable is written last, after want_lock and waiting.
 */
- initWith:(int)condition intr:(BOOL)interruptible
{
    [super init];

    cond_interlock.locked = 0;
    conditionVar = condition;
    sleep_interlock.locked = 0;
    want_lock = 0;
    waiting = 0;
    interuptable = interruptible;

    return self;
}

/*
 * AIOPSSCL_interuptable - Check if lock is interruptible
 * Calls the -interuptable method on the lock object
 * Returns char cast to int
 */
int AIOPSSCL_interuptable(id lock)
{
    char result;

    /* Call Objective-C method: [lock interuptable] */
    result = (char)(*IMP_interuptable)(lock, @selector(interuptable));
    return (int)result;
}

/*
 * interuptable - Check if lock is interruptible
 * Returns YES if lock can be interrupted by signals
 */
- (BOOL)interuptable
{
    return interuptable;
}

/*
 * AIOPSSCL_condition - Get current condition value
 * Calls the -condition method on the lock object
 */
int AIOPSSCL_condition(id lock)
{
    /* Call Objective-C method: [lock condition] */
    return (int)(*IMP_condition)(lock, @selector(condition));
}

/*
 * condition - Get current condition value
 * Returns the current condition as an integer
 */
- (int)condition
{
    int value;

    value = conditionVar;

    return value;
}

/*
 * AIOPSSCL_setCondition - Set condition value
 * Calls the -setCondition method (no parameter) on the lock object
 * Note: This appears to be a getter-style method, not a setter
 */
void AIOPSSCL_setCondition(id lock)
{
    /* Call Objective-C method: [lock setCondition] */
    (*IMP_setCondition)(lock, @selector(setCondition));
}

/*
 * setCondition: - Set condition value
 * Updates the condition and wakes one waiter
 * Note: takes no interlock - the caller is expected to hold the lock
 */
- setCondition:(int)condition
{
    conditionVar = condition;

    /* Wake one thread waiting on the condition variable
     * thread_wakeup_prim(event, one_thread, result)
     * - event: pointer to the condition variable
     * - one_thread: 1 = wake one thread, 0 = wake all threads
     * - result: wake result code (0)
     */
    thread_wakeup_prim((char *)&conditionVar, 1, 0);

    return self;
}

/*
 * free - Cleanup and deallocate
 */
- free
{
    return [super free];
}

/*
 * AIOPSSCL_unlock - Release lock
 * Calls the -unlock method on the lock object
 * Unlocks the lock and may wake waiting threads
 */
id AIOPSSCL_unlock(id lock)
{
    /* Call Objective-C method: [lock unlock] */
    return (id)(*IMP_unlock)(lock, @selector(unlock));
}

/*
 * unlock - Release lock
 * Unlocks the lock and signals waiting threads
 *
 * Wakes threads waiting on condition variable and threads waiting on the lock
 */
- unlock
{
    char waiters;

    /* Acquire the sleep interlock */
    simple_lock((simple_lock_t)&sleep_interlock);

    /* Wake one thread waiting on the condition variable */
    thread_wakeup_prim((char *)&conditionVar, 1, 0);

    /* Clear the lock held flag */
    want_lock = 0;

    /* If there are waiters, wake them.  The reference loads the flag into a
     * register and tests it (mov al, [ebx+0x12] / test al, al) rather than
     * comparing it in place, so it is read into a local here.
     */
    waiters = waiting;
    if (waiters != '\0') {
        /* Clear the waiter flag */
        waiting = 0;

        /* Wake all threads waiting on the lock object itself
         * thread_wakeup_prim(event, one_thread, result)
         * - event: self (the lock object)
         * - one_thread: 0 = wake all threads
         * - result: 0
         */
        thread_wakeup_prim(self, 0, 0);
    }

    /* Release the sleep interlock */
    simple_unlock((simple_lock_t)&sleep_interlock);

    return self;
}

/*
 * AIOPSSCL_unlockWith - Release lock and set condition
 * Calls the -unlockWith: method on the lock object
 * Atomically sets condition and unlocks
 */
id AIOPSSCL_unlockWith(id lock, int condition)
{
    /* Call Objective-C method: [lock unlockWith:condition] */
    return (id)(*IMP_unlockWith)(lock, @selector(unlockWith:), condition);
}

/*
 * unlockWith: - Release lock and set new condition
 * Atomically sets condition and unlocks
 * This is the typical way to change condition values
 *
 * Acquires both interlocks, updates the condition, then calls unlock
 */
- unlockWith:(int)condition
{

    /* Acquire the sleep interlock */
    simple_lock((simple_lock_t)&sleep_interlock);

    /* Acquire the condition interlock */
    simple_lock((simple_lock_t)&cond_interlock);

    /* Update the condition value */
    conditionVar = condition;

    /* Release the condition interlock */
    simple_unlock((simple_lock_t)&cond_interlock);

    /* Release the sleep interlock */
    simple_unlock((simple_lock_t)&sleep_interlock);

    /* Call unlock to wake waiting threads and clear the lock held flag */
    return AIOPSSCL_unlock(self);
}

/*
 * AIOPSSCL_lock - Acquire lock
 * Calls the -lock method on the lock object
 * Blocks until lock is available
 */
int AIOPSSCL_lock(id lock)
{
    /* Call Objective-C method: [lock lock] */
    return (int)(*IMP_lock)(lock, @selector(lock));
}

/*
 * lock - Acquire lock
 * Blocks until lock is available
 * Returns 0 on success, or the thread_wait_result if the wait was interrupted
 *
 * Uses sleep_interlock and want_lock to track lock state;
 * sleeps on self, interruptibly when interuptable is set
 */
- (int)lock
{
    int result;

    result = 0;

    /* Acquire spinlock using test-and-set pattern */
    simple_lock((simple_lock_t)&sleep_interlock);

    /* If lock is already held, we need to wait */
    if (want_lock != '\0') {
        do {
            /* Mark that we're waiting */
            waiting = 1;

            /* Sleep on the lock object */
            thread_sleep(self, (simple_lock_t)&sleep_interlock, interuptable);

            /* Re-acquire spinlock after waking */
            simple_lock((simple_lock_t)&sleep_interlock);

            /* Check if we were interrupted */
            result = thread_wait_result();

        } while ((want_lock != '\0') && (result == 0));
    }

    /* If we successfully acquired the lock (result == 0), mark it as held */
    if (result == 0) {
        want_lock = 1;
    }

    /* Release spinlock */
    simple_unlock((simple_lock_t)&sleep_interlock);

    /* If result != 0, lock acquisition failed (interrupted) */
    return result;
}

/*
 * AIOPSSCL_lockTry - Try to acquire lock without blocking
 * Calls the -lockTry method on the lock object
 * Returns char cast to int (YES/NO)
 */
int AIOPSSCL_lockTry(id lock)
{
    char result;

    /* Call Objective-C method: [lock lockTry] */
    result = (char)(*IMP_lockTry)(lock, @selector(lockTry));
    return (int)result;
}

/*
 * lockTry - Try to acquire lock without blocking
 * Returns YES if lock was acquired, NO if already held
 *
 * Uses sleep_interlock and checks want_lock
 */
- (BOOL)lockTry
{
    BOOL acquired;

    /* Acquire spinlock using test-and-set pattern */
    simple_lock((simple_lock_t)&sleep_interlock);

    /* Check if lock is free */
    acquired = (want_lock == '\0');

    /* If lock is free, mark it as held */
    if (acquired) {
        want_lock = 1;
    }

    /* Release spinlock */
    simple_unlock((simple_lock_t)&sleep_interlock);

    return acquired;
}

/*
 * AIOPSSCL_lockWhen - Acquire lock when condition equals specified value
 * Calls the -lockWhen: method on the lock object
 * Blocks until lock is available AND condition matches
 */
int AIOPSSCL_lockWhen(id lock, int condition)
{
    /* Call Objective-C method: [lock lockWhen:condition] */
    return (int)(*IMP_lockWhen)(lock, @selector(lockWhen:), condition);
}

/*
 * lockWhen: - Acquire lock when condition equals specific value
 * Blocks until lock is available AND condition matches
 * Returns 0 on success, or the thread_wait_result if the wait was interrupted
 *
 * Uses AIOPSSCL_lock/unlock wrappers and thread_sleep to wait for condition
 * Sleeps on conditionVar protected by cond_interlock
 */
- (int)lockWhen:(int)condition
{
    int result;

    while (1) {
        /* Try to acquire the lock */
        result = AIOPSSCL_lock(self);
        if (result != 0) {
            /* Lock acquisition failed (interrupted) */
            return result;
        }

        /* Check if condition matches */
        if (condition == conditionVar) {
            /* Condition matches, we have the lock and can return */
            break;
        }

        /* Condition doesn't match, need to wait */
        /* Acquire the condition interlock */
        simple_lock((simple_lock_t)&cond_interlock);

        /* Release the main lock before sleeping */
        AIOPSSCL_unlock(self);

        /* Sleep on the condition variable, protected by cond_interlock */
        thread_sleep((char *)&conditionVar, (simple_lock_t)&cond_interlock, interuptable);

        /* Check if we were interrupted */
        result = thread_wait_result();
        if (result != 0) {
            /* Sleep was interrupted */
            return result;
        }

        /* Loop back to re-acquire lock and check condition again */
    }

    /* Successfully acquired lock with matching condition */
    return 0;
}

@end
