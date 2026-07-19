/*
 * AppleIOPSSafeCondLock.m
 * Safe condition lock implementation for PortServer driver
 *
 * Provides both Objective-C class implementation and C wrapper functions
 */

#import "AppleIOPSSafeCondLock.h"
#import <objc/objc-runtime.h>
#import <kern/lock.h>
#import <kern/thread.h>

/* ========================================================================
 * Global IMP Cache Variables
 * ======================================================================== */

/* Cached method implementations for performance optimization */
static IMP _IMP_interuptable = NULL;
static IMP _IMP_condition = NULL;
static IMP _IMP_setCondition = NULL;
static IMP _IMP_unlock = NULL;
static IMP _IMP_unlockWith = NULL;
static IMP _IMP_lock = NULL;
static IMP _IMP_lockTry = NULL;
static IMP _IMP_lockWhen = NULL;

/* ========================================================================
 * Objective-C Class Implementation
 * ======================================================================== */

@implementation AppleIOPSSafeCondLock

/*
 * initialize - Class initialization method
 * Called once when the class is first used
 * Caches IMP (function pointers) for all instance methods to improve performance
 */
+ (void)initialize
{
    /* Cache IMP for interuptable method */
    _IMP_interuptable = objc_msgSend(self,
                                     @selector(instanceMethodFor:),
                                     @selector(interuptable));

    /* Cache IMP for condition method */
    _IMP_condition = objc_msgSend(self,
                                  @selector(instanceMethodFor:),
                                  @selector(condition));

    /* Cache IMP for setCondition method */
    _IMP_setCondition = objc_msgSend(self,
                                     @selector(instanceMethodFor:),
                                     @selector(setCondition:));

    /* Cache IMP for unlock method */
    _IMP_unlock = objc_msgSend(self,
                               @selector(instanceMethodFor:),
                               @selector(unlock));

    /* Cache IMP for unlockWith method */
    _IMP_unlockWith = objc_msgSend(self,
                                   @selector(instanceMethodFor:),
                                   @selector(unlockWith:));

    /* Cache IMP for lock method */
    _IMP_lock = objc_msgSend(self,
                            @selector(instanceMethodFor:),
                            @selector(lock));

    /* Cache IMP for lockTry method */
    _IMP_lockTry = objc_msgSend(self,
                                @selector(instanceMethodFor:),
                                @selector(lockTry));

    /* Cache IMP for lockWhen method */
    _IMP_lockWhen = objc_msgSend(self,
                                 @selector(instanceMethodFor:),
                                 @selector(lockWhen:));
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
 * Instance variable layout (from decompiled code):
 *   offset +4: initialized to 0
 *   offset +8: _condition (condition parameter)
 *   offset +c: initialized to 0
 *   offset +10: _interruptible (interruptible parameter)
 *   offset +11: initialized to 0
 *   offset +12: initialized to 0
 */
- initWith:(int)condition intr:(BOOL)interruptible
{
    [super init];
    
    /* Initialize instance variables based on decompiled offsets */
    *(int *)((char *)self + 4) = 0;
    *(int *)((char *)self + 8) = condition;     /* _condition */
    *(int *)((char *)self + 0xc) = 0;
    *(char *)((char *)self + 0x10) = interruptible;  /* _interruptible */
    *(char *)((char *)self + 0x11) = 0;
    *(char *)((char *)self + 0x12) = 0;
    
    /* Note: The named ivars _condition and _interruptible are actually
     * at offsets +8 and +10 respectively. The code above initializes
     * additional fields that may be used for synchronization primitives.
     */
    
    return self;
}

/*
 * free - Cleanup and deallocate
 * Must release any held locks and free resources
 */
- free
{
    /* TODO: Cleanup synchronization primitives:
     * - Ensure lock is not held
     * - Wake any waiting threads
     * - Free lock structures
     */

    return [super free];
}

/*
 * condition - Get current condition value
 * Returns the current condition as an integer
 */
- (int)condition
{
    int value;

    /* Read from offset +8 where _condition is stored */
    value = *(int *)((char *)self + 8);

    return value;
}

/*
 * interuptable - Check if lock is interruptible
 * Returns YES if lock can be interrupted by signals
 */
- (BOOL)interuptable
{
    /* Read from offset +10 where _interruptible is stored */
    return *(char *)((char *)self + 0x10);
}

/*
 * lock - Acquire lock
 * Blocks until lock is available
 * 
 * Uses a spinlock at offset +c and a flag at offset +11 to track lock state
 * If offset +10 (_interruptible) is true, uses thread_sleep for waiting
 */
- (void)lock
{
    int *spinlock_ptr;
    int spinlock_value;
    int result;
    
    result = 0;
    spinlock_ptr = (int *)((char *)self + 0xc);
    
    /* Acquire spinlock using test-and-set pattern */
    do {
        /* Spin while spinlock is held */
        while (*spinlock_ptr != 0) {
            /* Busy wait */
        }
        
        /* Try to acquire spinlock atomically */
        LOCK();
        spinlock_value = *spinlock_ptr;
        *spinlock_ptr = 1;
        UNLOCK();
    } while (spinlock_value == 1);
    
    /* If lock is already held (offset +11 != 0), we need to wait */
    if (*(char *)((char *)self + 0x11) != '\0') {
        spinlock_ptr = (int *)((char *)self + 0xc);
        
        do {
            /* Mark that we're waiting (offset +12) */
            *(char *)((char *)self + 0x12) = 1;
            
            /* Sleep on the lock object, interruptible flag from offset +10 */
            thread_sleep(self, spinlock_ptr, *(char *)((char *)self + 0x10));
            
            /* Re-acquire spinlock after waking */
            do {
                while (*spinlock_ptr != 0) {
                    /* Busy wait */
                }
                
                LOCK();
                spinlock_value = *spinlock_ptr;
                *spinlock_ptr = 1;
                UNLOCK();
            } while (spinlock_value == 1);
            
            /* Check if we were interrupted */
            result = thread_wait_result();
            
        } while ((*(char *)((char *)self + 0x11) != '\0') && (result == 0));
    }
    
    /* If we successfully acquired the lock (result == 0), mark it as held */
    if (result == 0) {
        *(char *)((char *)self + 0x11) = 1;
    }
    
    /* Release spinlock */
    LOCK();
    *(int *)((char *)self + 0xc) = 0;
    UNLOCK();
    
    /* Note: Original returns result, but method signature is void */
    /* If result != 0, lock acquisition failed (interrupted) */
}

/*
 * lockTry - Try to acquire lock without blocking
 * Returns YES if lock was acquired, NO if already held
 * 
 * Uses a spinlock at offset +c and checks flag at offset +11
 */
- (BOOL)lockTry
{
    int *spinlock_ptr;
    int spinlock_value;
    BOOL acquired;
    
    spinlock_ptr = (int *)((char *)self + 0xc);
    
    /* Acquire spinlock using test-and-set pattern */
    do {
        /* Spin while spinlock is held */
        while (*spinlock_ptr != 0) {
            /* Busy wait */
        }
        
        /* Try to acquire spinlock atomically */
        LOCK();
        spinlock_value = *spinlock_ptr;
        *spinlock_ptr = 1;
        UNLOCK();
    } while (spinlock_value == 1);
    
    /* Check if lock is free (offset +11 == 0) */
    acquired = (*(char *)((char *)self + 0x11) == '\0');
    
    /* If lock is free, mark it as held */
    if (acquired) {
        *(char *)((char *)self + 0x11) = 1;
    }
    
    /* Release spinlock */
    LOCK();
    *(int *)((char *)self + 0xc) = 0;
    UNLOCK();
    
    return acquired;
}

/*
 * lockWhen: - Acquire lock when condition equals specific value
 * Blocks until lock is available AND condition matches
 * 
 * Uses AIOPSSCL_lock/unlock wrappers and thread_sleep to wait for condition
 * Sleeps on the condition variable (offset +8) protected by spinlock at offset +4
 */
- (void)lockWhen:(int)condition
{
    int *spinlock_ptr;
    int spinlock_value;
    int result;
    
    while (1) {
        /* Try to acquire the lock */
        result = AIOPSSCL_lock(self);
        if (result != 0) {
            /* Lock acquisition failed (interrupted) */
            return;  /* Note: should return result, but signature is void */
        }
        
        /* Check if condition matches */
        if (condition == *(int *)((char *)self + 8)) {
            /* Condition matches, we have the lock and can return */
            break;
        }
        
        /* Condition doesn't match, need to wait */
        /* Acquire the condition variable spinlock at offset +4 */
        spinlock_ptr = (int *)((char *)self + 4);
        do {
            /* Spin while spinlock is held */
            while (*spinlock_ptr != 0) {
                /* Busy wait */
            }
            
            /* Try to acquire spinlock atomically */
            LOCK();
            spinlock_value = *spinlock_ptr;
            *spinlock_ptr = 1;
            UNLOCK();
        } while (spinlock_value == 1);
        
        /* Release the main lock before sleeping */
        AIOPSSCL_unlock(self);
        
        /* Sleep on the condition variable (offset +8), protected by spinlock at +4 */
        /* Uses interruptible flag from offset +10 */
        thread_sleep((char *)self + 8, (char *)self + 4, *(char *)((char *)self + 0x10));
        
        /* Check if we were interrupted */
        result = thread_wait_result();
        if (result != 0) {
            /* Sleep was interrupted */
            return;  /* Note: should return result, but signature is void */
        }
        
        /* Loop back to re-acquire lock and check condition again */
    }
    
    /* Successfully acquired lock with matching condition */
    return;  /* Note: original returns 0 */
}

/*
 * setCondition: - Set condition value
 * Updates condition and wakes all waiters
 * Note: Should be called with lock held
 * 
 * Sets the condition at offset +8 and wakes threads sleeping on it
 */
- (void)setCondition:(int)condition
{
    /* Update the condition value at offset +8 */
    *(int *)((char *)self + 8) = condition;
    
    /* Wake all threads waiting on the condition variable
     * thread_wakeup_prim(event, one_thread, result)
     * - event: pointer to condition variable (offset +8)
     * - one_thread: 1 = wake one thread, 0 = wake all threads (using 1 here)
     * - result: wake result code (0)
     */
    thread_wakeup_prim((char *)self + 8, 1, 0);
/*
 * unlock - Release lock
 * Unlocks the lock and signals waiting threads
 * 
 * Wakes threads waiting on condition variable and threads waiting on the lock
 */
- (void)unlock
{
    int *spinlock_ptr;
    int spinlock_value;
    
    /* Acquire the main lock spinlock at offset +c */
    spinlock_ptr = (int *)((char *)self + 0xc);
    do {
        /* Spin while spinlock is held */
        while (*spinlock_ptr != 0) {
            /* Busy wait */
        }
        
        /* Try to acquire spinlock atomically */
        LOCK();
        spinlock_value = *spinlock_ptr;
        *spinlock_ptr = 1;
        UNLOCK();
    } while (spinlock_value == 1);
    
    /* Wake one thread waiting on the condition variable (offset +8) */
    thread_wakeup_prim((char *)self + 8, 1, 0);
    
    /* Clear the lock held flag at offset +11 */
    *(char *)((char *)self + 0x11) = 0;
    
    /* If there are waiters (offset +12), wake them */
    if (*(char *)((char *)self + 0x12) != '\0') {
        /* Clear the waiter flag */
        *(char *)((char *)self + 0x12) = 0;
        
        /* Wake all threads waiting on the lock object itself
         * thread_wakeup_prim(event, one_thread, result)
         * - event: self (the lock object)
         * - one_thread: 0 = wake all threads
         * - result: 0
         */
        thread_wakeup_prim(self, 0, 0);
    }
    
    /* Release the spinlock */
    LOCK();
    *(int *)((char *)self + 0xc) = 0;
    UNLOCK();
    
    /* Note: Original returns self, but our signature is void */
}

/*
 * unlockWith: - Release lock and set new condition
 * Atomically sets condition and unlocks
 * This is the typical way to change condition values
 * 
 * Acquires both spinlocks, updates condition, then calls unlock
 */
- (void)unlockWith:(int)condition
{
    int *spinlock_ptr;
    int spinlock_value;
    
    /* Acquire the main lock spinlock at offset +c */
    spinlock_ptr = (int *)((char *)self + 0xc);
    do {
        /* Spin while spinlock is held */
        while (*spinlock_ptr != 0) {
            /* Busy wait */
        }
        
        /* Try to acquire spinlock atomically */
        LOCK();
        spinlock_value = *spinlock_ptr;
        *spinlock_ptr = 1;
        UNLOCK();
    } while (spinlock_value == 1);
    
    /* Acquire the condition variable spinlock at offset +4 */
    spinlock_ptr = (int *)((char *)self + 4);
    do {
        /* Spin while spinlock is held */
        while (*spinlock_ptr != 0) {
            /* Busy wait */
        }
        
        /* Try to acquire spinlock atomically */
        LOCK();
        spinlock_value = *spinlock_ptr;
        *spinlock_ptr = 1;
        UNLOCK();
    } while (spinlock_value == 1);
    
    /* Update the condition value at offset +8 */
    *(int *)((char *)self + 8) = condition;
    
    /* Release the condition variable spinlock */
    LOCK();
    *(int *)((char *)self + 4) = 0;
    UNLOCK();
    
    /* Release the main lock spinlock */
    LOCK();
    *(int *)((char *)self + 0xc) = 0;
    UNLOCK();
    
    /* Call unlock to wake waiting threads and clear lock held flag */
    AIOPSSCL_unlock(self);
    
    /* Note: Original returns result of AIOPSSCL_unlock, but our signature is void */
}
 * This is the typical way to change condition values
 */
- (void)unlockWith:(int)condition
{
    /* TODO: Implement atomic unlock with condition update:
     * - Update _condition = condition
     * - Release mutex/simple_lock
     * - Broadcast to all waiting threads (condition changed)
     * - Wake all threads waiting in lockWhen:
     */

    *(int *)((char *)self + 8) = condition;  /* Update _condition at offset +8 */
}

/*
 * setCondition: - Set condition value
 * Updates condition and signals waiters
 * Note: Should be called with lock held
 */
- (void)setCondition:(int)condition
{
    /* TODO: Implement condition update:
     * - Should verify lock is held by caller
     * - Update _condition = condition
     * - Broadcast condition variable
     * - Wake threads waiting for this condition
     */

    *(int *)((char *)self + 8) = condition;  /* Update _condition at offset +8 */
}

@end


/* ========================================================================
 * C Wrapper Functions
 * ======================================================================== */

/*
 * IMP function pointers - these are cached method implementations
 * for performance. They are initialized when first needed.
 */
static IMP IMP_condition = NULL;
static IMP IMP_interuptable = NULL;
static IMP IMP_lock = NULL;
static IMP IMP_lockTry = NULL;
static IMP IMP_lockWhen = NULL;
static IMP IMP_setCondition = NULL;
static IMP IMP_unlock = NULL;
static IMP IMP_unlockWith = NULL;

/* Selector references - these are string constants in the binary */
/* The actual selector strings like "condition", "lock:", etc. */

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
 * AIOPSSCL_lock - Acquire lock
 * Calls the -lock method on the lock object
 * Blocks until lock is available
 */
void AIOPSSCL_lock(id lock)
{
    /* Call Objective-C method: [lock lock] */
    (*IMP_lock)(lock, @selector(lock));
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
 * AIOPSSCL_lockWhen - Acquire lock when condition equals specified value
 * Calls the -lockWhen: method on the lock object
 * Blocks until lock is available AND condition matches
 */
void AIOPSSCL_lockWhen(id lock, int condition)
{
    /* Call Objective-C method: [lock lockWhen:condition] */
    (*IMP_lockWhen)(lock, @selector(lockWhen:), condition);
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
 * AIOPSSCL_unlock - Release lock
 * Calls the -unlock method on the lock object
 * Unlocks the lock and may wake waiting threads
 */
void AIOPSSCL_unlock(id lock)
{
    /* Call Objective-C method: [lock unlock] */
    (*IMP_unlock)(lock, @selector(unlock));
}

/*
 * AIOPSSCL_unlockWith - Release lock and set condition
 * Calls the -unlockWith: method on the lock object
 * Atomically sets condition and unlocks
 */
void AIOPSSCL_unlockWith(id lock, int condition)
{
    /* Call Objective-C method: [lock unlockWith:condition] */
    (*IMP_unlockWith)(lock, @selector(unlockWith:), condition);
}
