/*	NSLock.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSLock.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSObjCRuntime.h>
#import <mach/cthreads.h>

#include <limits.h>
#include <objc/objc-class.h>
#include "../../Libc-1/threads.subproj/cthread_internals.h"

#import "NSProcessInfoPrivate.h"

@interface NSMultiReadUniWriteLock : NSObject {
@public
    void *_priv;
}
- (void)lockForReading;
- (void)lockForWriting;
- (BOOL)tryLockForReading;
- (BOOL)tryLockForWriting;
@end

#if defined(__ppc__) || defined(__POWERPC__)
#define NS_CONDITION_WAIT_ERROR @"*** condition_wait_timeout_(): msg_receive failure with exit code %d"
#define NS_CONDITION_SEND_ERROR @"*** condition_signal_timeout_(): msg_end failure with exit code %d"
#else
#define NS_CONDITION_WAIT_ERROR @"*** condition_wait_timeout(): msg_receive failure with exit code %d"
#define NS_CONDITION_SEND_ERROR @"*** condition_signal_timeout(): msg_end failure with exit code %d"
#endif

static int
NSConditionWaitTimeout(condition_t condition, mutex_t mutex, double seconds)
{
    cproc_t proc = cproc_self();
    msg_header_t message;
#if defined(__ppc__) || defined(__POWERPC__)
    double milliseconds = seconds * 1000.0;
#else
    long double milliseconds = (long double)seconds * 1000.0L;
#endif
    unsigned timeout;
    int messaged = NO;

#if defined(__ppc__) || defined(__POWERPC__)
    if (!(milliseconds <= (double)UINT_MAX))
        timeout = UINT_MAX;
    else
        timeout = (unsigned)(long long)milliseconds;
#else
    if (milliseconds >= (long double)UINT_MAX)
        timeout = UINT_MAX;
    else
        timeout = (unsigned)(long long)milliseconds;
#endif

    spin_lock(&condition->lock);
    cthread_queue_enq(&condition->queue, proc);
    proc->state = CPROC_BLOCKED;
    spin_unlock(&condition->lock);
    mutex_unlock(mutex);

    for (;;) {
        kern_return_t result;

        do {
            message.msg_size = sizeof(message);
            message.msg_local_port = proc->wait_port;
            result = msg_receive(&message, RCV_TIMEOUT, timeout);
        } while (result == -21);

        if (result == RCV_TIMED_OUT) {
            struct cthread_queue queue;
            cproc_t item;

            if (proc->state == CPROC_EATING)
                continue;
            spin_lock(&condition->lock);
            if (proc->state == CPROC_EATING) {
                spin_unlock(&condition->lock);
                continue;
            }
            queue = condition->queue;
            cthread_queue_init(&condition->queue);
            for (;;) {
                cthread_queue_deq(&queue, cproc_t, item);
                if (item == NO_CPROC)
                    break;
                if (item != proc)
                    cthread_queue_enq(&condition->queue, item);
            }
            proc->state = CPROC_RUNNING;
            spin_unlock(&condition->lock);
            messaged = NO;
        } else if (result == RCV_SUCCESS) {
            proc->state = CPROC_RUNNING;
            messaged = YES;
        } else {
#if defined(__ppc__) || defined(__POWERPC__)
            [NSException raise:NSInternalInconsistencyException
                        format:NS_CONDITION_WAIT_ERROR];
#else
            [NSException raise:NSInternalInconsistencyException
                        format:NS_CONDITION_WAIT_ERROR, (int)result];
#endif
        }
        break;
    }

    mutex_lock(mutex);
    return messaged;
}

static void
NSConditionSendWakeup(cproc_t proc)
{
    msg_header_t message;
    kern_return_t result;

    message.msg_simple = TRUE;
    message.msg_size = sizeof(message);
    message.msg_type = MSG_TYPE_NORMAL;
    message.msg_local_port = PORT_NULL;
    message.msg_remote_port = proc->wait_port;
    message.msg_id = 0;
    result = msg_send(&message, SEND_TIMEOUT, 0);
    if (result != SEND_SUCCESS && result != SEND_TIMED_OUT)
        [NSException raise:NSInternalInconsistencyException
                    format:NS_CONDITION_SEND_ERROR, (int)result];
}

static void
NSConditionSignalTimeout(condition_t condition)
{
    cproc_t proc;

    if (condition->queue.head == 0)
        return;
    spin_lock(&condition->lock);
    cthread_queue_deq(&condition->queue, cproc_t, proc);
    if (proc != NO_CPROC) {
        proc->state = CPROC_EATING;
        spin_unlock(&condition->lock);
        NSConditionSendWakeup(proc);
    } else {
        spin_unlock(&condition->lock);
    }
}

static void NSConditionDrainWaiters(condition_t condition);

static void
NSConditionDrainWaiters(condition_t condition)
{
    cproc_t proc;

    cthread_queue_deq(&condition->queue, cproc_t, proc);
    if (proc != NO_CPROC) {
        proc->state = CPROC_EATING;
        NSConditionDrainWaiters(condition);
        NSConditionSendWakeup(proc);
    } else {
        spin_unlock(&condition->lock);
    }
}

static void
NSConditionBroadcastTimeout(condition_t condition)
{
    if (condition->queue.head == 0)
        return;
    spin_lock(&condition->lock);
    NSConditionDrainWaiters(condition);
}

@implementation NSLock

+ (id)allocWithZone:(NSZone *)zone {
    return NSAllocateObject(self, 0x1c, zone);
}

- (id)init {
    char *state = (char *)self + self->isa->instance_size;

    _priv = state;
    *((int *)state) = 0;
    *((int *)(state + 8)) = 0;
    *((int *)(state + 16)) = 0;
    *((int *)(state + 12)) = 0;
    state[24] = 0;
    return self;
}

- (void)lock {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    condition_t condition = (condition_t)(state + 8);

    mutex_lock(mutex);
    while (state[24])
        NSConditionWaitTimeout(condition, mutex, 1.0e20);
    state[24] = 1;
    mutex_unlock(mutex);
}

- (void)unlock {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    condition_t condition = (condition_t)(state + 8);

    mutex_lock(mutex);
    state[24] = 0;
    NSConditionSignalTimeout(condition);
    mutex_unlock(mutex);
}

- (BOOL)tryLock {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    BOOL acquired;

    mutex_lock(mutex);
    acquired = !state[24];
    if (acquired)
        state[24] = 1;
    mutex_unlock(mutex);
    return acquired;
}

- (BOOL)lockBeforeDate:(NSDate *)limit {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    condition_t condition = (condition_t)(state + 8);
    NSTimeInterval deadline = [limit timeIntervalSinceReferenceDate];
    BOOL acquired = YES;

    mutex_lock(mutex);
    while (state[24]) {
        NSTimeInterval remaining = deadline - (NSTimeInterval)_NSCurrentTime();

        if (remaining < 0.0) {
            acquired = NO;
            break;
        }
        if (!NSConditionWaitTimeout(condition, mutex, remaining)) {
            acquired = NO;
            break;
        }
    }
    if (acquired)
        state[24] = 1;
    mutex_unlock(mutex);
    return acquired;
}

- (void)dealloc {
    char *state = (char *)_priv;
    condition_t condition = (condition_t)(state + 8);

    NSConditionBroadcastTimeout(condition);
    spin_lock(&condition->lock);
    [super dealloc];
}

- (NSString *)description {
    char *state = (char *)_priv;

    return [NSString stringWithFormat:@"%s(0x%x) locked: %s",
            self->isa->name, (unsigned)self, state[24] ? "YES" : "NO"];
}

@end

@implementation NSCondition

+ (id)allocWithZone:(NSZone *)zone {
    return NSAllocateObject(self, 24, zone);
}

- (id)init {
    int *state = (int *)((char *)self + self->isa->instance_size);

    _priv = state;
    state[0] = 0;
    state[2] = 0;
    state[4] = 0;
    state[3] = 0;
    return self;
}

- (void)lock {
    mutex_t mutex = (mutex_t)_priv;

    if (!mutex_try_lock(mutex))
        mutex_wait_lock(mutex);
}

- (void)unlock {
    *((int *)_priv) = 0;
}

- (void)broadcast {
    NSConditionBroadcastTimeout((condition_t)((char *)_priv + 8));
}

- (void)signal {
    NSConditionSignalTimeout((condition_t)((char *)_priv + 8));
}

- (void)wait {
    NSConditionWaitTimeout((condition_t)((char *)_priv + 8),
                           (mutex_t)_priv, 1.0e20);
}

- (BOOL)waitUntilDate:(NSDate *)limit {
    NSTimeInterval remaining = [limit timeIntervalSinceNow];

    if (remaining < 0.0)
        return NO;
    return NSConditionWaitTimeout((condition_t)((char *)_priv + 8),
                                  (mutex_t)_priv, remaining);
}

- (void)dealloc {
    int *state = (int *)_priv;
    condition_t condition = (condition_t)(state + 2);

    if (state[3] != 0)
        cond_broadcast(condition);
    spin_lock(&condition->lock);
    [super dealloc];
}

@end

@implementation NSConditionLock

+ (id)allocWithZone:(NSZone *)zone {
    return NSAllocateObject(self, 0x20, zone);
}

- (id)init {
    char *state = (char *)self + self->isa->instance_size;

    _priv = state;
    *((int *)state) = 0;
    *((int *)(state + 8)) = 0;
    *((int *)(state + 16)) = 0;
    *((int *)(state + 12)) = 0;
    *((int *)(state + 24)) = 0;
    *((int *)(state + 28)) = 0;
    return self;
}

- (id)initWithCondition:(int)condition {
    [self init];
    *((int *)_priv + 7) = condition;
    return self;
}

- (int)condition {
    return *((int *)_priv + 7);
}

- (void)lock {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    condition_t condition = (condition_t)(state + 8);

    mutex_lock(mutex);
    while (state[24])
        NSConditionWaitTimeout(condition, mutex, 1.0e20);
    state[24] = 1;
    mutex_unlock(mutex);
}

- (void)lockWhenCondition:(int)condition {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    condition_t conditionVariable = (condition_t)(state + 8);

    mutex_lock(mutex);
    while (state[24] || *((int *)(state + 28)) != condition)
        NSConditionWaitTimeout(conditionVariable, mutex, 1.0e20);
    state[24] = 1;
    mutex_unlock(mutex);
}

- (BOOL)tryLock {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    BOOL acquired;

    mutex_lock(mutex);
    acquired = !state[24];
    if (acquired)
        state[24] = 1;
    mutex_unlock(mutex);
    return acquired;
}

- (BOOL)tryLockWhenCondition:(int)condition {
    return [self lockWhenCondition:condition beforeDate:[NSDate date]];
}

- (void)unlockWithCondition:(int)condition {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;

    mutex_lock(mutex);
    *((int *)(state + 28)) = condition;
    state[24] = 0;
    mutex_unlock(mutex);
    NSConditionBroadcastTimeout((condition_t)(state + 8));
}

- (BOOL)lockBeforeDate:(NSDate *)limit {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    condition_t condition = (condition_t)(state + 8);
    NSTimeInterval deadline = [limit timeIntervalSinceReferenceDate];
    BOOL acquired = YES;

    mutex_lock(mutex);
    while (state[24]) {
        NSTimeInterval remaining = deadline - (NSTimeInterval)_NSCurrentTime();
        if (remaining < 0.0) {
            acquired = NO;
            break;
        }
        if (!NSConditionWaitTimeout(condition, mutex, remaining)) {
            acquired = NO;
            break;
        }
    }
    if (acquired)
        state[24] = 1;
    mutex_unlock(mutex);
    return acquired;
}

- (BOOL)lockWhenCondition:(int)condition beforeDate:(NSDate *)limit {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    condition_t conditionVariable = (condition_t)(state + 8);
    NSTimeInterval deadline = [limit timeIntervalSinceReferenceDate];
    BOOL acquired = YES;

    mutex_lock(mutex);
    while (state[24] || *((int *)(state + 28)) != condition) {
        NSTimeInterval remaining = deadline - (NSTimeInterval)_NSCurrentTime();

        if (remaining < 0.0) {
            acquired = NO;
            break;
        }
        if (!NSConditionWaitTimeout(conditionVariable, mutex, remaining)) {
            acquired = NO;
            break;
        }
    }
    if (acquired)
        state[24] = 1;
    mutex_unlock(mutex);
    return acquired;
}

- (void)unlock {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;

    mutex_lock(mutex);
    state[24] = 0;
    mutex_unlock(mutex);
    NSConditionBroadcastTimeout((condition_t)(state + 8));
}

- (void)dealloc {
    condition_t condition = (condition_t)((char *)_priv + 8);

    condition_broadcast(condition);
    spin_lock(&condition->lock);
    [super dealloc];
}

- (NSString *)description {
    int *state = (int *)_priv;

    return [NSString stringWithFormat:@"%s(0x%x) locked: %s  condition: %d",
            self->isa->name, (unsigned)self, state[6] == 1 ? "YES" : "NO", state[7]];
}

@end

@implementation NSRecursiveLock

+ (id)allocWithZone:(NSZone *)zone {
    return NSAllocateObject(self, 0x20, zone);
}

- (id)init {
    char *state = (char *)self + self->isa->instance_size;

    _priv = state;
    *((int *)state) = 0;
    *((int *)(state + 8)) = 0;
    *((int *)(state + 16)) = 0;
    *((int *)(state + 12)) = 0;
    *((int *)(state + 24)) = 0;
    *((int *)(state + 28)) = 0;
    return self;
}

- (void)lock {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    condition_t condition = (condition_t)(state + 8);
    int owner = (int)cthread_self();

    mutex_lock(mutex);
    while (*((int *)(state + 28)) != 0 && *((int *)(state + 28)) != owner)
        NSConditionWaitTimeout(condition, mutex, 1.0e20);
    ++*((int *)(state + 24));
    *((int *)(state + 28)) = owner;
    mutex_unlock(mutex);
}

- (void)unlock {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    condition_t condition = (condition_t)(state + 8);
    int *count = (int *)(state + 24);

    mutex_lock(mutex);
    if ((*count)-- == 1) {
        *((int *)(state + 28)) = 0;
        NSConditionSignalTimeout(condition);
    }
    if (*count < 0)
        *count = 0;
    mutex_unlock(mutex);
}

- (BOOL)tryLock {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    int owner = (int)cthread_self();
    BOOL acquired;

    mutex_lock(mutex);
    acquired = *((int *)(state + 28)) == 0 || *((int *)(state + 28)) == owner;
    if (acquired) {
        ++*((int *)(state + 24));
        *((int *)(state + 28)) = owner;
    }
    mutex_unlock(mutex);
    return acquired;
}

- (BOOL)lockBeforeDate:(NSDate *)limit {
    char *state = (char *)_priv;
    mutex_t mutex = (mutex_t)state;
    condition_t condition = (condition_t)(state + 8);
    int owner = (int)cthread_self();
    NSTimeInterval deadline = [limit timeIntervalSinceReferenceDate];
    BOOL acquired = YES;

    mutex_lock(mutex);
    while (*((int *)(state + 28)) != 0 && *((int *)(state + 28)) != owner) {
        NSTimeInterval remaining = deadline - (NSTimeInterval)_NSCurrentTime();

        if (remaining < 0.0) {
            acquired = NO;
            break;
        }
        if (!NSConditionWaitTimeout(condition, mutex, remaining)) {
            acquired = NO;
            break;
        }
    }
    if (acquired) {
        ++*((int *)(state + 24));
        *((int *)(state + 28)) = owner;
    }
    mutex_unlock(mutex);
    return acquired;
}

- (void)dealloc {
    condition_t condition = (condition_t)((char *)_priv + 8);

    NSConditionBroadcastTimeout(condition);
    spin_lock(&condition->lock);
    [super dealloc];
}

- (NSString *)description {
    int *state = (int *)_priv;

    return [NSString stringWithFormat:@"%s(0x%x) locked: %s  recursion count: %d",
            self->isa->name, (unsigned)self, state[7] ? "YES" : "NO", state[6]];
}

@end

@implementation NSMultiReadUniWriteLock

+ (id)allocWithZone:(NSZone *)zone {
    return NSAllocateObject(self, 0x34, zone);
}

- (id)init {
    int *state = (int *)((char *)self + self->isa->instance_size);

    _priv = state;
    state[0] = 0;
    state[2] = 0;
    state[4] = 0;
    state[3] = 0;
    state[6] = 0;
    state[8] = 0;
    state[7] = 0;
    state[11] = 0;
    state[10] = 0;
#if defined(__ppc__) || defined(__POWERPC__)
    state[12] = 0;
#else
    ((unsigned char *)state)[51] &= ~0x80u;
    state[12] &= 0x80000000u;
#endif
    return self;
}

- (void)dealloc {
    int *state = (int *)_priv;
    condition_t readers = (condition_t)(state + 2);
    condition_t writers = (condition_t)(state + 6);

    if (state[3] != 0)
        cond_broadcast(readers);
    spin_lock(&readers->lock);
    if (state[7] != 0)
        cond_broadcast(writers);
    spin_lock(&writers->lock);
    [super dealloc];
}

- (NSString *)description {
    int *state = (int *)_priv;

    return [NSString stringWithFormat:
        @"%@(0x%x) {\n  readers: %u\n  waiting readers: %u\n  writers: %u\n  waiting writers: %u\n}",
        NSStringFromClass(self->isa), (unsigned)self,
#if defined(__ppc__) || defined(__POWERPC__)
        (unsigned)state[12] >> 1, (unsigned)state[10],
        (unsigned)state[12] & 1u, (unsigned)state[11]];
#else
        (unsigned)(state[12] & 0x7fffffff), (unsigned)state[10],
        (unsigned)(((unsigned char *)state)[51] >> 7), (unsigned)state[11]];
#endif
}

- (void)lockForReading {
    int *state = (int *)_priv;
    mutex_t mutex = (mutex_t)state;
#if !defined(__ppc__) && !defined(__POWERPC__)
    unsigned readers;
#endif

    if (!mutex_try_lock(mutex))
        mutex_wait_lock(mutex);
    ++state[10];
#if defined(__ppc__) || defined(__POWERPC__)
    while (((unsigned)state[12] & 1u) != 0 || state[11] != 0)
#else
    while (((char *)state)[51] < 0 || state[11] != 0)
#endif
        condition_wait((condition_t)(state + 2), mutex);
    --state[10];
#if defined(__ppc__) || defined(__POWERPC__)
    state[12] = (int)(((((unsigned)state[12] >> 1) + 1) << 1)
                      | ((unsigned)state[12] & 1u));
#else
    readers = (((unsigned)state[12] & 0x7fffffffU) + 1) & 0x7fffffffU;
    state[12] &= 0x80000000u;
    state[12] |= (int)readers;
#endif
    state[0] = 0;
}

- (void)lockForWriting {
    int *state = (int *)_priv;
    mutex_t mutex = (mutex_t)state;

    if (!mutex_try_lock(mutex))
        mutex_wait_lock(mutex);
    ++state[11];
#if defined(__ppc__) || defined(__POWERPC__)
    while (((unsigned)state[12] & 1u) != 0
           || ((unsigned)state[12] >> 1) != 0)
#else
    while (((char *)state)[51] < 0
           || ((unsigned)state[12] & 0x7fffffffU) != 0)
#endif
        condition_wait((condition_t)(state + 6), mutex);
    --state[11];
#if defined(__ppc__) || defined(__POWERPC__)
    state[12] |= 1;
#else
    ((char *)state)[51] |= (char)0x80;
#endif
    state[0] = 0;
}

- (void)lock {
    [self lockForWriting];
}

- (BOOL)tryLockForReading {
    int *state = (int *)_priv;
    mutex_t mutex = (mutex_t)state;
    BOOL acquired = NO;

    if (!mutex_try_lock(mutex))
        mutex_wait_lock(mutex);
#if defined(__ppc__) || defined(__POWERPC__)
    if (((unsigned)state[12] & 1u) == 0 && state[11] == 0) {
        state[12] = (int)(((((unsigned)state[12] >> 1) + 1) << 1)
                          | ((unsigned)state[12] & 1u));
        acquired = YES;
    }
#else
    if (((char *)state)[51] >= 0 && state[11] == 0) {
        unsigned readers = (((unsigned)state[12] & 0x7fffffffU) + 1)
                           & 0x7fffffffU;

        state[12] &= 0x80000000u;
        state[12] |= (int)readers;
        acquired = YES;
    }
#endif
    state[0] = 0;
    return acquired;
}

- (BOOL)tryLockForWriting {
    int *state = (int *)_priv;
    mutex_t mutex = (mutex_t)state;
    BOOL acquired = NO;

    if (!mutex_try_lock(mutex))
        mutex_wait_lock(mutex);
#if defined(__ppc__) || defined(__POWERPC__)
    if (((unsigned)state[12] & 1u) == 0
        && ((unsigned)state[12] >> 1) == 0) {
        state[12] |= 1;
        acquired = YES;
    }
#else
    if (((char *)state)[51] >= 0
        && ((unsigned)state[12] & 0x7fffffffU) == 0) {
        ((char *)state)[51] |= (char)0x80;
        acquired = YES;
    }
#endif
    state[0] = 0;
    return acquired;
}

- (void)unlock {
    int *state = (int *)_priv;
    mutex_t mutex = (mutex_t)state;
    BOOL wakeReaders = NO;
    BOOL wakeWriters = NO;
    unsigned readers;

    if (!mutex_try_lock(mutex))
        mutex_wait_lock(mutex);
#if defined(__ppc__) || defined(__POWERPC__)
    if (((unsigned)state[12] & 1u) != 0) {
        state[12] &= ~1;
        wakeReaders = state[10] != 0;
        if (!wakeReaders)
            wakeWriters = state[11] != 0;
    } else {
        readers = (unsigned)state[12] >> 1;
        if (readers == 0) {
            wakeReaders = state[10] != 0;
            wakeWriters = state[11] != 0;
        } else {
            state[12] = (int)((((readers - 1) << 1)
                               | ((unsigned)state[12] & 1u)));
            if (((unsigned)state[12] & 0xfffffffeu) == 0) {
                wakeWriters = state[11] != 0;
                if (!wakeWriters)
                    wakeReaders = state[10] != 0;
            }
        }
    }
#else
    if (((char *)state)[51] >= 0) {
        readers = (unsigned)state[12] & 0x7fffffffU;
        if (readers == 0) {
            wakeReaders = state[10] != 0;
            wakeWriters = state[11] != 0;
        } else {
            state[12] &= 0x80000000u;
            state[12] |= (int)((readers - 1) & 0x7fffffffU);
            if (((unsigned)state[12] & 0x7fffffffU) == 0) {
                wakeWriters = state[11] != 0;
                if (!wakeWriters)
                    wakeReaders = state[10] != 0;
            }
        }
    } else {
        ((char *)state)[51] &= (char)~0x80;
        wakeReaders = state[10] != 0;
        if (!wakeReaders)
            wakeWriters = state[11] != 0;
    }
#endif
    state[0] = 0;
    if (wakeReaders && state[3] != 0)
        cond_broadcast((condition_t)(state + 2));
    if (wakeWriters && state[7] != 0)
        cond_signal((condition_t)(state + 6));
}

@end
