/*	NSThread.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSThread.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSArchiver.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSProxy.h>
#import <Foundation/NSRecursiveLock.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>

#import <objc/objc-runtime.h>

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <mach/cthreads.h>
#include <mach/mach_traps.h>
#include <mach/thread_switch.h>

static NSThread *threadCache;
static unsigned sequenceNumber;
#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSSequenceLock;
#else
mutex_t __NSSequenceLock;
#endif
#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSDebugRecordLock;
volatile unsigned int __NSStringRetainLock;
#else
mutex_t __NSDebugRecordLock;
#endif
#if !defined(__ppc__) && !defined(__POWERPC__)
mutex_t __NSAllocatorLock;
mutex_t __NSRefCountLock;
#endif
int _NSIsMultiThreaded;
NSLock *_NSGlobalRetainLock;
#if !defined(__ppc__) && !defined(__POWERPC__)
NSLock *_NSSimpleHashingLock;
#endif
NSLock *_NSHostTableLock;
NSLock *_NSTempFileCounterLock;
NSLock *_NSUniqueStringCounterLock;
NSLock *_NSUniqueCStringLock;
NSLock *_NSDistantObjectSelectorsTableLock;
NSRecursiveLock *_NSLogLock;
NSLock *_NSConnectionHashTableLock;
NSLock *_NSConnectionTableLock;
NSRecursiveLock *_NSConnectionModesLock;
NSLock *_NSPortTableLock;
#if !defined(__ppc__) && !defined(__POWERPC__)
NSLock *_NSStringRetainLock;
NSLock *_NSURLFormatterRegistrarLock;
NSLock *_NSURLHandlerRegistrarLock;
NSLock *_NSPlaceholderValueLock;
#endif
#if !defined(__ppc__) && !defined(__POWERPC__)
static NSRecursiveLock *_NSUserDefaultsLock;
#endif
NSString * const NSWillBecomeMultiThreadedNotification = @"NSWillBecomeMultiThreadedNotification";
NSString * const NSDidBecomeSingleThreadedNotification = @"NSDidBecomeSingleThreadedNotification";
NSString * const NSThreadWillExitNotification = @"NSThreadWillExitNotification";

extern void set_malloc_singlethreaded(int singleThreaded);
extern NSRecursiveLock *__NSLanguageContextLock;
extern NSLock *_NSPerformTimerCacheLock;
extern NSLock *_NSPortCoderCacheLock;
extern NSLock *_NSConnectionWorkQueueLock;
extern NSLock *_NSConnectionLock;
extern NSLock *_NSConnectionReplyTableLock;
extern NSLock *_NSConnectionConversationTableLock;
extern NSLock *_NSNotificationCenterLock;
extern NSLock *_NSMethodSignatureTableLock;
extern NSLock *_NSCharacterSetLock;
extern NSRecursiveLock *_NSTimeZoneLock;
extern NSLock *_NSNaturalLanguageCacheLock;
#if !defined(__ppc__) && !defined(__POWERPC__)
extern NSLock *_NSPlaceholderDecimalNumberLock;
#endif
#if defined(__ppc__) || defined(__POWERPC__)
extern NSLock *_NSUserDefaultsLock;
#endif
extern void NSConnectionRegisterConversation(id conversation, NSThread *thread);
extern void NSConnectionUnregisterConversation(id conversation);
extern NSThread *NSConnectionThreadForConversation(id conversation);

kern_return_t _NSMilliSleep(mach_msg_timeout_t timeout) {
    return thread_switch(0, SWITCH_OPTION_WAIT, timeout);
}

extern unsigned NSPushAutoreleasePool(void);
extern void _NSClearExceptionStack(void **handlerStack);
extern NSRecursiveLock *_NSBundleDataLock;
#if !defined(__ppc__) && !defined(__POWERPC__)
extern NSLock *_NSPlaceholderStringLock;
#endif

@interface NSRunLoop (NSThreadPrivate)
+ (void)_taskNowSingleThreaded;
+ (void)_taskNowMultiThreaded;
@end

@interface NSObject (NSThreadBootstrap)
+ (id)self;
@end

@interface NSProxy (NSThreadBootstrap)
+ (id)self;
@end

@class NSFault;
@interface NSFault
+ (id)self;
@end

void _NSToDoAtFirstThreadStart(void) {
#if !defined(__ppc__) && !defined(__POWERPC__)
    __NSDebugRecordLock = (mutex_t)calloc(1, sizeof(struct mutex));
    __NSAllocatorLock = (mutex_t)calloc(1, sizeof(struct mutex));
    __NSRefCountLock = (mutex_t)calloc(1, sizeof(struct mutex));
    __NSSequenceLock = (mutex_t)calloc(1, sizeof(struct mutex));
#endif
    (void)[NSObject self];
    (void)[NSProxy self];
    (void)[NSFault self];
    (void)[NSRunLoop self];
    (void)[NSConnection self];
    (void)[NSUnarchiver self];
    (void)[NSBundle self];
    (void)[NSFileManager self];
    if (_NSGlobalRetainLock == nil)
        _NSGlobalRetainLock = [[NSLock allocWithZone:NULL] init];
#if !defined(__ppc__) && !defined(__POWERPC__)
    if (_NSSimpleHashingLock == nil)
        _NSSimpleHashingLock = [[NSLock allocWithZone:NULL] init];
#endif
    if (__NSLanguageContextLock == nil)
        __NSLanguageContextLock = [[NSRecursiveLock allocWithZone:NULL] init];
    if (_NSPortCoderCacheLock == nil)
        _NSPortCoderCacheLock = [[NSLock allocWithZone:NULL] init];
    if (_NSConnectionLock == nil)
        _NSConnectionLock = [[NSLock allocWithZone:NULL] init];
    if (_NSConnectionTableLock == nil)
        _NSConnectionTableLock = [[NSLock allocWithZone:NULL] init];
    if (_NSConnectionHashTableLock == nil)
        _NSConnectionHashTableLock = [[NSLock allocWithZone:NULL] init];
    if (_NSConnectionReplyTableLock == nil)
        _NSConnectionReplyTableLock = [[NSLock allocWithZone:NULL] init];
    if (_NSConnectionWorkQueueLock == nil)
        _NSConnectionWorkQueueLock = [[NSLock allocWithZone:NULL] init];
    if (_NSConnectionModesLock == nil)
        _NSConnectionModesLock = [[NSRecursiveLock allocWithZone:NULL] init];
    if (_NSConnectionConversationTableLock == nil)
        _NSConnectionConversationTableLock = [[NSLock allocWithZone:NULL] init];
    if (_NSDistantObjectSelectorsTableLock == nil)
        _NSDistantObjectSelectorsTableLock = [[NSLock allocWithZone:NULL] init];
    if (_NSNotificationCenterLock == nil)
        _NSNotificationCenterLock = [[NSLock allocWithZone:NULL] init];
    if (_NSMethodSignatureTableLock == nil)
        _NSMethodSignatureTableLock = [[NSLock allocWithZone:NULL] init];
    if (_NSHostTableLock == nil)
        _NSHostTableLock = [[NSLock allocWithZone:NULL] init];
    if (_NSPortTableLock == nil)
        _NSPortTableLock = [[NSLock allocWithZone:NULL] init];
    if (_NSCharacterSetLock == nil)
        _NSCharacterSetLock = [[NSLock allocWithZone:NULL] init];
    if (_NSTimeZoneLock == nil)
        _NSTimeZoneLock = [[NSRecursiveLock allocWithZone:NULL] init];
    if (_NSLogLock == nil)
        _NSLogLock = [[NSRecursiveLock allocWithZone:NULL] init];
    if (_NSPerformTimerCacheLock == nil)
        _NSPerformTimerCacheLock = [[NSLock allocWithZone:NULL] init];
    if (_NSBundleDataLock == nil)
        _NSBundleDataLock = [[NSRecursiveLock allocWithZone:NULL] init];
    if (_NSUniqueCStringLock == nil)
        _NSUniqueCStringLock = [[NSLock allocWithZone:NULL] init];
#if !defined(__ppc__) && !defined(__POWERPC__)
    if (_NSStringRetainLock == nil)
        _NSStringRetainLock = [[NSLock allocWithZone:NULL] init];
    if (_NSURLFormatterRegistrarLock == nil)
        _NSURLFormatterRegistrarLock = [[NSLock allocWithZone:NULL] init];
    if (_NSURLHandlerRegistrarLock == nil)
        _NSURLHandlerRegistrarLock = [[NSLock allocWithZone:NULL] init];
#endif
    if (_NSNaturalLanguageCacheLock == nil)
        _NSNaturalLanguageCacheLock = [[NSLock allocWithZone:NULL] init];
#if !defined(__ppc__) && !defined(__POWERPC__)
    if (_NSPlaceholderStringLock == nil)
        _NSPlaceholderStringLock = [[NSLock allocWithZone:NULL] init];
    if (_NSPlaceholderDecimalNumberLock == nil)
        _NSPlaceholderDecimalNumberLock = [[NSLock allocWithZone:NULL] init];
    if (_NSPlaceholderValueLock == nil)
        _NSPlaceholderValueLock = [[NSLock allocWithZone:NULL] init];
#endif
#if defined(__ppc__) || defined(__POWERPC__)
    if (_NSUserDefaultsLock == nil)
        _NSUserDefaultsLock = [[NSRecursiveLock allocWithZone:NULL] init];
#else
    if (_NSUserDefaultsLock == nil)
        _NSUserDefaultsLock = [[NSRecursiveLock allocWithZone:NULL] init];
#endif
    if (_NSTempFileCounterLock == nil)
        _NSTempFileCounterLock = [[NSLock allocWithZone:NULL] init];
    if (_NSUniqueStringCounterLock == nil)
        _NSUniqueStringCounterLock = [[NSLock allocWithZone:NULL] init];
    [NSRunLoop _taskNowMultiThreaded];
}

#define NS_RELEASE_THREAD_LOCK(lock) do { \
    if ((lock) != nil) { \
        [(lock) release]; \
        (lock) = nil; \
    } \
} while (0)

#if defined(__ppc__) || defined(__POWERPC__)
id _NSToDoAtLastThreadExit(void) {
    id result;
#else
void _NSToDoAtLastThreadExit(void) {
#endif
    [NSRunLoop _taskNowSingleThreaded];
    NS_RELEASE_THREAD_LOCK(_NSGlobalRetainLock);
#if !defined(__ppc__) && !defined(__POWERPC__)
    NS_RELEASE_THREAD_LOCK(_NSSimpleHashingLock);
#endif
    NS_RELEASE_THREAD_LOCK(__NSLanguageContextLock);
    NS_RELEASE_THREAD_LOCK(_NSPortCoderCacheLock);
    NS_RELEASE_THREAD_LOCK(_NSConnectionLock);
    NS_RELEASE_THREAD_LOCK(_NSConnectionTableLock);
    NS_RELEASE_THREAD_LOCK(_NSConnectionHashTableLock);
    NS_RELEASE_THREAD_LOCK(_NSConnectionReplyTableLock);
    NS_RELEASE_THREAD_LOCK(_NSConnectionWorkQueueLock);
    NS_RELEASE_THREAD_LOCK(_NSConnectionModesLock);
    NS_RELEASE_THREAD_LOCK(_NSConnectionConversationTableLock);
    NS_RELEASE_THREAD_LOCK(_NSDistantObjectSelectorsTableLock);
    NS_RELEASE_THREAD_LOCK(_NSNotificationCenterLock);
    NS_RELEASE_THREAD_LOCK(_NSMethodSignatureTableLock);
    NS_RELEASE_THREAD_LOCK(_NSHostTableLock);
    NS_RELEASE_THREAD_LOCK(_NSPortTableLock);
    NS_RELEASE_THREAD_LOCK(_NSCharacterSetLock);
    NS_RELEASE_THREAD_LOCK(_NSTimeZoneLock);
    NS_RELEASE_THREAD_LOCK(_NSLogLock);
    NS_RELEASE_THREAD_LOCK(_NSPerformTimerCacheLock);
    NS_RELEASE_THREAD_LOCK(_NSBundleDataLock);
    NS_RELEASE_THREAD_LOCK(_NSUniqueCStringLock);
#if !defined(__ppc__) && !defined(__POWERPC__)
    NS_RELEASE_THREAD_LOCK(_NSStringRetainLock);
    NS_RELEASE_THREAD_LOCK(_NSURLFormatterRegistrarLock);
    NS_RELEASE_THREAD_LOCK(_NSURLHandlerRegistrarLock);
#endif
    NS_RELEASE_THREAD_LOCK(_NSNaturalLanguageCacheLock);
#if !defined(__ppc__) && !defined(__POWERPC__)
    NS_RELEASE_THREAD_LOCK(_NSPlaceholderStringLock);
    NS_RELEASE_THREAD_LOCK(_NSPlaceholderDecimalNumberLock);
    NS_RELEASE_THREAD_LOCK(_NSPlaceholderValueLock);
#endif
#if defined(__ppc__) || defined(__POWERPC__)
    NS_RELEASE_THREAD_LOCK(_NSUserDefaultsLock);
#else
    NS_RELEASE_THREAD_LOCK(_NSUserDefaultsLock);
#endif
    NS_RELEASE_THREAD_LOCK(_NSTempFileCounterLock);
#if defined(__ppc__) || defined(__POWERPC__)
    result = _NSUniqueStringCounterLock;
    if (_NSUniqueStringCounterLock != nil) {
        result = ((id (*)(id, SEL))objc_msgSend)(
            _NSUniqueStringCounterLock, @selector(release));
        _NSUniqueStringCounterLock = nil;
    }
    return result;
#else
    NS_RELEASE_THREAD_LOCK(_NSUniqueStringCounterLock);
    if (__NSDebugRecordLock != NULL) {
        free(__NSDebugRecordLock);
        __NSDebugRecordLock = NULL;
    }
    if (__NSAllocatorLock != NULL) {
        free(__NSAllocatorLock);
        __NSAllocatorLock = NULL;
    }
    if (__NSRefCountLock != NULL) {
        free(__NSRefCountLock);
        __NSRefCountLock = NULL;
    }
    if (__NSSequenceLock != NULL) {
        free(__NSSequenceLock);
        __NSSequenceLock = NULL;
    }
#endif
}

@interface NSAutoreleasePool (NSThreadPrivate)
+ (void)releaseAllPools;
@end

NSThread *_NSCurrentThread(void) {
    unsigned stackPage = 0;
    unsigned stackMarker;
    NSThread *thread = threadCache;

    if (thread == nil || (_NSIsMultiThreaded
        && (stackPage = (unsigned)&stackMarker & ~(NSPageSize() - 1),
            ((unsigned *)thread)[2] != stackPage))) {
        if (stackPage == 0)
            stackPage = (unsigned)&stackMarker & ~(NSPageSize() - 1);
        thread = (NSThread *)cthread_data(cthread_self());
        if (thread == nil) {
            thread = [[NSThread allocWithZone:NULL] init];
            cthread_set_data(cthread_self(), thread);
        }
        ((unsigned *)thread)[2] = stackPage;
        threadCache = thread;
    }
    return thread;
}

@interface NSThread (NSThreadPrivate)
- (void)_exit;
- (void)_setThreadName:(NSString *)name;
- (NSString *)_threadName;
@end

typedef struct {
    id target;
    SEL selector;
    id argument;
} NSThreadInvocation;

static any_t NSThreadStartFunction(any_t value) {
    NSThreadInvocation *invocation = (NSThreadInvocation *)value;

#if defined(__ppc__) || defined(__POWERPC__)
    NSThread *thread = _NSCurrentThread();

    [[NSPort allocWithZone:NULL]
        initWithMachPort:cthread_self()->real_thread];
    [thread _setThreadName:@"Foundation-created thread"];
    ((void **)thread)[11] = invocation;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"_NSThreadDidStartNotification"
                      object:nil
                    userInfo:nil];
    [invocation->target performSelector:invocation->selector
                             withObject:invocation->argument];
    [thread _exit];
#else
    [[NSPort allocWithZone:NULL]
        initWithMachPort:cthread_self()->real_thread];
    [_NSCurrentThread() _setThreadName:@"Foundation-created thread"];
    [invocation->target performSelector:invocation->selector
                             withObject:invocation->argument];
    [invocation->target release];
    [invocation->argument release];
    NSZoneFree(NULL, invocation);
    [NSThread exit];
#endif
    return NULL;
}

@implementation NSThread

+ (NSThread *)currentThread {
    return _NSCurrentThread();
}

+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument {
    NSThreadInvocation *invocation = (NSThreadInvocation *)NSZoneMalloc(NULL,
        sizeof(NSThreadInvocation));
    cthread_t thread;

    invocation->target = [target retain];
    invocation->selector = selector;
    invocation->argument = [argument retain];

    objc_setMultithreaded(YES);
    if (!_NSIsMultiThreaded) {
        _NSIsMultiThreaded = 1;
        _NSToDoAtFirstThreadStart();
        [[NSNotificationCenter defaultCenter]
            postNotificationName:NSWillBecomeMultiThreadedNotification
                          object:nil
                        userInfo:nil];
    }
    set_malloc_singlethreaded(0);
    thread = cthread_fork(NSThreadStartFunction, invocation);
    cthread_detach(thread);
}

+ (BOOL)isMultiThreaded {
    return _NSIsMultiThreaded;
}

- (NSMutableDictionary *)threadDictionary {
    if (threadDictionary == nil) {
#if defined(__ppc__) || defined(__POWERPC__)
        threadDictionary = [[NSMutableDictionary allocWithZone:[self zone]]
            initWithCapacity:21];
#else
        threadDictionary = [[NSMutableDictionary allocWithZone:[self zone]]
            initWithCapacity:3];
#endif
    }
    return threadDictionary;
}

- (id)runLoop {
    return runLoop;
}

- (void)setRunLoop:(id)newRunLoop {
    [newRunLoop retain];
    [runLoop release];
    runLoop = newRunLoop;
}

- (id)init {
#if defined(__ppc__) || defined(__POWERPC__)
    if (_NSIsMultiThreaded) {
        for (;;) {
            unsigned oldValue;
            unsigned one = 1;

            __asm__ volatile(
                "1: lwarx %0,0,%1\n\t"
                "stwcx. %2,0,%1\n\t"
                "bne- 1b"
                : "=&r" (oldValue)
                : "r" (&__NSSequenceLock), "r" (one)
                : "cr0", "memory");
            if (oldValue == 0)
                break;
            cthread_yield();
        }
        __asm__ volatile("isync" ::: "memory");
    }
    seqNum = sequenceNumber++;
    if (_NSIsMultiThreaded) {
        __asm__ volatile("sync" ::: "memory");
        __NSSequenceLock = 0;
    }
#else
    if (__NSSequenceLock != NULL &&
        mutex_try_lock(__NSSequenceLock) == 0)
        mutex_wait_lock(__NSSequenceLock);
    seqNum = sequenceNumber++;
    if (__NSSequenceLock != NULL)
        *(__volatile unsigned *)__NSSequenceLock = 0;
#endif
    return self;
}

+ (void)sleepUntilDate:(NSDate *)date {
    NSTimeInterval milliseconds = [date timeIntervalSinceNow] * 1000.0;

    if (milliseconds <= 0.0)
        return;
    if (milliseconds >= (double)UINT_MAX)
        _NSMilliSleep((mach_msg_timeout_t)-1);
    else
        _NSMilliSleep((mach_msg_timeout_t)milliseconds);
}

+ (void)sleepForTimeInterval:(NSTimeInterval)seconds {
    NSTimeInterval milliseconds = seconds * 1000.0;

    if (milliseconds <= 0.0)
        return;
    if (milliseconds > (double)UINT_MAX)
        _NSMilliSleep((mach_msg_timeout_t)-1);
    else
        _NSMilliSleep((mach_msg_timeout_t)milliseconds);
}

+ (void)exit {
    [_NSCurrentThread() _exit];
}

- (void)_exit {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSThreadWillExitNotification
                      object:self
                    userInfo:nil];
    [self release];
    threadCache = nil;
    cthread_exit(NULL);
}

- (void)_setThreadName:(NSString *)name {
    const char *oldName = cthread_name(cthread_self());

    cthread_set_name(cthread_self(), NULL);
    if (oldName != NULL && (oldName[0] != '?' || oldName[1] != '\0'))
        NSZoneFree(NULL, (void *)oldName);

    if (name != nil) {
        const char *newName = [name cString];
        size_t length = strlen(newName);
        char *copy = (char *)NSZoneMalloc(NULL, (unsigned)(length + 1));

        memmove(copy, newName, length);
        copy[length] = '\0';
        cthread_set_name(cthread_self(), copy);
    }
}

- (NSString *)_threadName {
#if defined(__ppc__) || defined(__POWERPC__)
    const char *name = cthread_name(cthread_self());
    const char *lengthName = cthread_name(cthread_self());

    return [NSString stringWithCString:name length:(unsigned)strlen(lengthName)];
#else
    const char *lengthName = cthread_name(cthread_self());
    unsigned length = (unsigned)strlen(lengthName);
    const char *name = cthread_name(cthread_self());

    return [NSString stringWithCString:name length:length];
#endif
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Thread %d", (int)cthread_self()];
}

- (void)dealloc {
    NSPushAutoreleasePool();
#if defined(__ppc__) || defined(__POWERPC__)
    if (reserved1 != NULL) {
        id *reservedObjects = (id *)reserved1;

        [reservedObjects[0] release];
        [reservedObjects[2] release];
        NSZoneFree(NULL, reserved1);
    }
#endif
    [runLoop release];
    runLoop = nil;
    [doConversation release];
    doConversation = nil;
    [doConversationRequest release];
    doConversationRequest = nil;
    [doQueue release];
    doQueue = nil;
    [threadDictionary release];
    threadDictionary = nil;
    [self _setThreadName:nil];
    [NSAutoreleasePool releaseAllPools];
    _NSClearExceptionStack(&excHandlers);
    cthread_set_data(cthread_self(), NULL);
    [super dealloc];
}

@end

@implementation NSThread (NSConnectionWorkQueue)

- (id)lastConversation {
    return doConversation;
}

- (void)addConversation:(id)conversation {
    if (doConversation == nil) {
        if (doConversationCount != 0) {
            NSLog(@"Warning: Adding new conversation to %@, but count is not 0",
                  [NSThread currentThread]);
            doConversationCount = 0;
        }
        doConversation = [conversation retain];
        NSConnectionRegisterConversation(conversation, _NSCurrentThread());
    }
    ++doConversationCount;
}

- (void)removeConversation {
    if (doConversation == nil || doConversationCount == 0) {
        NSLog(@"Warning: attempting to remove bad conversation from %@, conversation %x, conversationCount %u",
              [NSThread currentThread], (unsigned int)doConversation,
              doConversationCount);
        doConversationCount = 1;
    }
    --doConversationCount;
    if (doConversationCount == 0) {
        NSConnectionUnregisterConversation(doConversation);
        [doConversation release];
        doConversation = nil;
    }
}

- (void)clearConversationRequest {
    [doConversationRequest release];
    doConversationRequest = nil;
}

- (id)conversationRequest {
    return doConversationRequest;
}

- (void)setConversationRequest:(id)request {
    if (doConversationRequest != nil) {
        NSLog(@"Warning: Overwriting queued conversation request %@",
              doConversationRequest);
        [doConversationRequest release];
    }
    [request retain];
    doConversationRequest = request;
}

+ (NSThread *)mapConversationToThread:(id)conversation {
    NSThread *thread = NSConnectionThreadForConversation(conversation);

    if (thread == _NSCurrentThread())
        NSLog(@"Warning: Mapped conversation (%x) to current thread (%@), this should never happen",
              (unsigned)conversation, thread);
    return thread;
}

- (NSMutableArray *)workQueue {
    if (doQueue == nil)
        doQueue = [[NSMutableArray allocWithZone:NULL] init];
    return (NSMutableArray *)doQueue;
}

@end
