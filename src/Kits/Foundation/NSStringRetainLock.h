#ifndef FOUNDATION_NSSTRING_RETAIN_LOCK_H
#define FOUNDATION_NSSTRING_RETAIN_LOCK_H

#import <Foundation/NSLock.h>

#if defined(__ppc__) || defined(__POWERPC__)
#include <mach/cthreads.h>

extern volatile unsigned int __NSStringRetainLock;
extern int _NSIsMultiThreaded;

static BOOL NSStringRetainLockAcquire(void)
{
    if (!_NSIsMultiThreaded)
        return NO;
    for (;;) {
        unsigned oldValue;
        unsigned acquired;
        unsigned one = 1;

        __asm__ volatile(
            "1: lwarx %0,0,%2\n\t"
            "cmpwi %0,0\n\t"
            "bne- 2f\n\t"
            "stwcx. %3,0,%2\n\t"
            "bne- 1b\n\t"
            "isync\n\t"
            "li %1,1\n\t"
            "b 3f\n"
            "2: li %1,0\n"
            "3:"
            : "=&r" (oldValue), "=&r" (acquired)
            : "r" (&__NSStringRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return YES;
        cthread_yield();
    }
}

static void NSStringRetainLockRelease(BOOL locked)
{
    if (locked) {
        __asm__ volatile("sync" ::: "memory");
        __NSStringRetainLock = 0;
    }
}
#else
extern NSLock *_NSStringRetainLock;

static BOOL NSStringRetainLockAcquire(void)
{
    if (_NSStringRetainLock == nil)
        return NO;
    [_NSStringRetainLock lock];
    return YES;
}

static void NSStringRetainLockRelease(BOOL locked)
{
    if (locked)
        [_NSStringRetainLock unlock];
}
#endif

#endif
