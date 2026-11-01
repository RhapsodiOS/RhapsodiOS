/*	NSDebug.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDebug.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSException.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSProxy.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <objc/Object.h>
#import <objc/objc-runtime.h>
#import <objc/zone.h>
#import <streams/streams.h>
#import <mach/mach.h>
#import <mach/message.h>

#include <signal.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach/cthreads.h>

extern NSPort *__NSMachNMServerPort;
extern NSZone *__NSDefaultMallocZone;
extern int _NSIsMultiThreaded;
#import "NSProcessInfoPrivate.h"
extern unsigned NSAutoreleasePoolCountForObject(id object);

#if defined(__ppc__) || defined(__POWERPC__)
extern unsigned int _NSCStringToUnsignedLong(char *string, char **endPointer);
extern volatile unsigned int __NSDebugRecordLock;
#define NS_ALLOCATION_EVENT_PACKET_SIZE 3512
#else
extern mutex_t __NSDebugRecordLock;
#define NS_ALLOCATION_EVENT_PACKET_SIZE 7608
#endif

static unsigned long NSDebugParseUnsignedLong(char *string, int base)
{
#if defined(__ppc__) || defined(__POWERPC__)
    (void)base;
    return (unsigned long)_NSCStringToUnsignedLong(string, NULL);
#else
    return strtoul(string, NULL, base);
#endif
}

BOOL NSDebugEnabled = NO;
BOOL NSZombieEnabled = NO;
BOOL NSDeallocateZombies = NO;
BOOL NSHangOnMallocError = NO;
BOOL NSNegativeRetainCheckEnabled = NO;
BOOL NSKeepAllocationStatistics = NO;
unsigned int NSAllocationStatisticsOutputMask = 0xffffffffU;
static int sending_event_port;
static NSString *NSDebuggerDescriptionForDebugger;

void NSDebugRecordObjectAndStack(void)
{
}

void _NSNegativeRetain(void *object, int virtualRetains)
{
    Class classObject = *(Class *)object;

    NSLog(@"*** _NSNegativeRetain(): object (0x%x) of class %s has less than zero (%d) virtual retains\n",
          (unsigned)object, classObject->name, virtualRetains);
}

#if !defined(__ppc__) && !defined(__POWERPC__)
int _NSDoubleToBinaryString(unsigned int firstWord, unsigned int secondWord,
                            char *buffer)
{
    char *cursor = buffer;

    sprintf(cursor, "%u %u%u%u%u%u%u%u",
            (secondWord >> 31) & 1, (secondWord >> 30) & 1,
            (secondWord >> 29) & 1, (secondWord >> 28) & 1,
            (secondWord >> 27) & 1, (secondWord >> 26) & 1,
            (secondWord >> 25) & 1, (secondWord >> 24) & 1);
    cursor += strlen(cursor);
    sprintf(cursor, "%u%u%u%u %u%u%u%u",
            (secondWord >> 23) & 1, (secondWord >> 22) & 1,
            (secondWord >> 21) & 1, (secondWord >> 20) & 1,
            (secondWord >> 19) & 1, (secondWord >> 18) & 1,
            (secondWord >> 17) & 1, (secondWord >> 16) & 1);
    cursor += strlen(cursor);
    sprintf(cursor, "%u%u%u%u%u%u%u%u",
            (secondWord >> 15) & 1, (secondWord >> 14) & 1,
            (secondWord >> 13) & 1, (secondWord >> 12) & 1,
            (secondWord >> 11) & 1, (secondWord >> 10) & 1,
            (secondWord >> 9) & 1, (secondWord >> 8) & 1);
    cursor += strlen(cursor);
    sprintf(cursor, "%u%u%u%u%u%u%u%u",
            (secondWord >> 7) & 1, (secondWord >> 6) & 1,
            (secondWord >> 5) & 1, (secondWord >> 4) & 1,
            (secondWord >> 3) & 1, (secondWord >> 2) & 1,
            (secondWord >> 1) & 1, secondWord & 1);
    cursor += strlen(cursor);
    sprintf(cursor, "%u%u%u%u%u%u%u%u",
            (firstWord >> 31) & 1, (firstWord >> 30) & 1,
            (firstWord >> 29) & 1, (firstWord >> 28) & 1,
            (firstWord >> 27) & 1, (firstWord >> 26) & 1,
            (firstWord >> 25) & 1, (firstWord >> 24) & 1);
    cursor += strlen(cursor);
    sprintf(cursor, "%u%u%u%u%u%u%u%u",
            (firstWord >> 23) & 1, (firstWord >> 22) & 1,
            (firstWord >> 21) & 1, (firstWord >> 20) & 1,
            (firstWord >> 19) & 1, (firstWord >> 18) & 1,
            (firstWord >> 17) & 1, (firstWord >> 16) & 1);
    cursor += strlen(cursor);
    sprintf(cursor, "%u%u%u%u%u%u%u%u",
            (firstWord >> 15) & 1, (firstWord >> 14) & 1,
            (firstWord >> 13) & 1, (firstWord >> 12) & 1,
            (firstWord >> 11) & 1, (firstWord >> 10) & 1,
            (firstWord >> 9) & 1, (firstWord >> 8) & 1);
    cursor += strlen(cursor);
    return sprintf(cursor, "%u%u%u%u%u%u%u%u",
                   (firstWord >> 7) & 1, (firstWord >> 6) & 1,
                   (firstWord >> 5) & 1, (firstWord >> 4) & 1,
                   (firstWord >> 3) & 1, (firstWord >> 2) & 1,
                   (firstWord >> 1) & 1, firstWord & 1);
}
#endif

extern char *_NSGetEnvironmentVariable(const char *name);
extern char *_NSProcessName(void);
extern char *_NSProcessPath(void);
extern NSPort *_NSToDoAtProcessStart(void);
extern int malloc_debug(int level);
extern void (*malloc_error(void (*handler)(int)))(int);
extern void instrumentObjcMessageSends(BOOL flag);
extern ssize_t _NSWriteToFileDescriptor(int descriptor, const void *buffer,
                                        size_t length);

@interface NSException (NSDebugLogging)
+ (void)_enableLogging:(BOOL)flag;
@end

@interface NSConnection (NSDebugPrivate)
+ (void)_toggleLogging;
@end

@interface NSString (NSDebuggerExtras)
- (NSString *)displayableString;
@end

static BOOL NSDebugEnvironmentFlag(const char *name, int yes, int no)
{
    const char *value = _NSGetEnvironmentVariable(name);

    return value != NULL && (*value == yes || *value == no);
}

static BOOL NSDebugIsReadableAddress(const void *pointer, unsigned length)
{
    vm_address_t address = (vm_address_t)pointer;
    vm_address_t regionAddress = address;
    vm_size_t regionSize;
    vm_prot_t protection;
    vm_prot_t maxProtection;
    vm_inherit_t inheritance;
    boolean_t isShared;
    memory_object_name_t objectName;
    vm_offset_t offset;

    if ((address >> NSLogPageSize()) == 0)
        return NO;
    if (vm_region(task_self(), &regionAddress, &regionSize, &protection,
                  &maxProtection, &inheritance, &isShared, &objectName,
                  &offset) != KERN_SUCCESS)
        return NO;
    if ((protection & VM_PROT_READ) == 0 || regionAddress > address)
        return NO;
    return address + length <= regionAddress + regionSize;
}

static BOOL NSDebugIsClass(Class candidate)
{
    NXHashTable *classes = objc_getClasses();
    NXHashState state = NXInitHashState(classes);
    void *classObject;

    while (NXNextHashState(classes, &state, &classObject))
        if (classObject == candidate)
            return YES;
    return NO;
}

char *_NSPrintForDebugger(id object)
{
    NSHandler2 handler;

    if (object == nil)
        return "<nil>";
    if (NSDebuggerDescriptionForDebugger != nil) {
        [NSDebuggerDescriptionForDebugger release];
        NSDebuggerDescriptionForDebugger = nil;
    }
    if (!NSDebugIsReadableAddress(object, sizeof(Class))
        || (!NSDebugIsClass(*(Class *)object) && !NSDebugIsClass((Class)object)))
        return "<not an object>";
    if (![object respondsToSelector:@selector(debugDescription)])
        return "<object does not respond to PrintObject method>";

    _NSAddHandler2(&handler);
    if (_setjmp(handler._state) != 0) {
        (void)_NSExceptionObjectFromHandler2(&handler);
        return "<object raised exception generating description>";
    }
    NSDebuggerDescriptionForDebugger = [object debugDescription];
    _NSRemoveHandler2(&handler);
    if (NSDebuggerDescriptionForDebugger == nil)
        return "<object returns empty description>";
    if ([NSDebuggerDescriptionForDebugger isEqualToString:@""]) {
        NSDebuggerDescriptionForDebugger = nil;
        return "<object returns empty description>";
    }
    [NSDebuggerDescriptionForDebugger retain];
    return (char *)[NSDebuggerDescriptionForDebugger lossyCString];
}

BOOL NSIsFreedObject(id anObject)
{
    static Class freedObjectClass;
    static Class zombieClass;
    Class objectClass;

    if (anObject == nil || !NSDebugIsReadableAddress(anObject, sizeof(Class)))
        return NO;

    objectClass = *(Class *)anObject;
    if (freedObjectClass == Nil) {
        Object *probe = [(id)objc_lookUpClass("Object") allocWithZone:NULL];

        [probe free];
        freedObjectClass = *(Class *)probe;
        zombieClass = [(id)objc_lookUpClass("_NSZombie") class];
    }
    if (objectClass == freedObjectClass)
        return YES;
    while (objectClass != Nil) {
        if (objectClass == zombieClass)
            return YES;
        objectClass = objectClass->super_class;
    }
    return NO;
}

static void _NSHandleMallocError(int code)
{
    char message[1024];
    char *processName = _NSProcessName();
    char *cursor = message;
    const char *suffix = ": Malloc-related error detected with code ";

    while ((*cursor++ = *processName++) != '\0')
        ;
    cursor--;
    while ((*cursor++ = *suffix++) != '\0')
        ;
    cursor--;
    *cursor++ = (char)code + '0';
    *cursor++ = '\n';
    *cursor = '\0';
    _NSWriteToFileDescriptor(2, message, (size_t)(cursor - message) + 1);
    if (NSHangOnMallocError) {
        sigset_t emptySignalSet;
        sigemptyset(&emptySignalSet);
        sigsuspend(&emptySignalSet);
    }
}

void _NSInitializePlatform(void)
{
    static BOOL initialized;
    NSZone *defaultZone;
    char *value;

    if (initialized)
        return;
    initialized = YES;

    if (__NSDefaultMallocZone == 0)
        __NSDefaultMallocZone = (NSZone *)NXDefaultMallocZone();
    defaultZone = __NSDefaultMallocZone;
    malloc_error(_NSHandleMallocError);
    NXNameZone((NXZone *)defaultZone, "NSDefaultZone");

    if (NSDebugEnvironmentFlag("NSDebugEnabled", 'Y', 'y'))
        NSDebugEnabled = YES;
    if (NSDebugEnvironmentFlag("NSZombieEnabled", 'Y', 'y'))
        NSZombieEnabled = YES;
    if (NSDebugEnvironmentFlag("NSDeallocateZombies", 'Y', 'y'))
        NSDeallocateZombies = YES;
    if (NSDebugEnvironmentFlag("NSHangOnMallocError", 'Y', 'y'))
        NSHangOnMallocError = YES;
    if (NSDebugEnvironmentFlag("NSHangOnUncaughtException", 'Y', 'y'))
        NSHangOnUncaughtException = YES;
    if (NSDebugEnvironmentFlag("NSNegativeRetainCheckEnabled", 'Y', 'y'))
        NSNegativeRetainCheckEnabled = YES;

    value = _NSGetEnvironmentVariable("NSMallocDebugMask");
    if (value != NULL)
        malloc_debug((int)NSDebugParseUnsignedLong(value, 0));
    if (NSDebugEnvironmentFlag("NSObjCMessageLoggingEnabled", 'Y', 'y'))
        instrumentObjcMessageSends(YES);

    _NSProcessPath();
    _NSToDoAtProcessStart();

    value = _NSGetEnvironmentVariable("NSEnableAutoreleasePool");
    if (value != NULL && (*value == 'N' || *value == 'n'))
        [NSAutoreleasePool enableRelease:NO];
    value = _NSGetEnvironmentVariable("NSAutoreleaseHighWaterMark");
    if (value != NULL)
        [NSAutoreleasePool setPoolCountHighWaterMark:
            (unsigned)NSDebugParseUnsignedLong(value, 10)];
    value = _NSGetEnvironmentVariable("NSAutoreleaseHighWaterResolution");
    if (value != NULL)
        [NSAutoreleasePool setPoolCountHighWaterResolution:
            (unsigned)NSDebugParseUnsignedLong(value, 10)];
    if (NSDebugEnvironmentFlag("NSAutoreleaseFreedObjectCheckEnabled", 'Y', 'y'))
        [NSAutoreleasePool enableFreedObjectCheck:YES];
    if (NSDebugEnvironmentFlag("NSExceptionLoggingEnabled", 'Y', 'y'))
        [NSException _enableLogging:YES];
    if (NSDebugEnvironmentFlag("NSDOLoggingEnabled", 'Y', 'y'))
        [NSConnection _toggleLogging];
    if (NSDebugEnvironmentFlag("NSUnbufferedIO", 'Y', 'y')) {
        setvbuf(stdout, NULL, _IONBF, 0);
        setvbuf(stderr, NULL, _IONBF, 0);
    }
    if (NSDebugEnvironmentFlag("NSKeepAllocationStatistics", 'Y', 'y'))
        NSKeepAllocationStatistics = YES;
    value = _NSGetEnvironmentVariable("NSAllocationStatisticsOutputMask");
    if (value != NULL)
        NSAllocationStatisticsOutputMask =
            (unsigned)NSDebugParseUnsignedLong(value, 0);
}

NSPort *
NSGetAllocationStatisticsOutputPort(void)
{
    return [NSPort portWithMachPort:sending_event_port];
}

void
NSSetAllocationStatisticsOutputPort(NSPort *port)
{
    sending_event_port = port == nil ? 0 : [port machPort];
}

static unsigned NSAllocationEventSequence;
static unsigned NSAllocationEventRequestedVersion;

static BOOL
NSDebugLockAllocationRecord(void)
{
#if defined(__ppc__) || defined(__POWERPC__)
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
            : "r" (&__NSDebugRecordLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return YES;
        cthread_yield();
    }
#else
    if (__NSDebugRecordLock == NULL)
        return NO;
    if (mutex_try_lock(__NSDebugRecordLock) == 0)
        mutex_wait_lock(__NSDebugRecordLock);
    return YES;
#endif
}

static void
NSDebugUnlockAllocationRecord(void)
{
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned zero = 0;

    __asm__ volatile("sync\n\tstw %1,0(%0)"
                     : : "r" (&__NSDebugRecordLock), "r" (zero) : "memory");
#else
    *(__volatile__ unsigned *)__NSDebugRecordLock = 0;
#endif
}

static void
NSDebugInitializeAllocationPacket(unsigned char *packet)
{
    memset(packet, 0, NS_ALLOCATION_EVENT_PACKET_SIZE);
    packet[3] = 1;
    packet[24] = 0x09;
    packet[25] = 0x08;
    packet[164] = 0x02;
#if defined(__ppc__) || defined(__POWERPC__)
    packet[26] = 0x08;
    packet[27] = 0x88;
    packet[165] = 0x20;
    packet[166] = 0x00;
    packet[167] = 0x78;
    packet[196] = 0x0a;
    packet[197] = 0x40;
    packet[198] = 0x19;
    packet[199] = 0xe8;
#else
    packet[26] = 0x88;
    packet[27] = 0x10;
    packet[165] = 0x20;
    packet[166] = 0x07;
    packet[167] = 0x10;
    packet[196] = 0x0a;
    packet[197] = 0x40;
    packet[198] = 0x9e;
    packet[199] = 0x13;
#endif
}

static void
NSDebugSetAllocationTraceCount(unsigned char *packet, unsigned count)
{
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned countField = (16 * (count + 6)) & 0xfff0;

    packet[198] = (unsigned char)(countField >> 8);
    packet[199] = (unsigned char)(countField | 0x08);
#else
    unsigned countField = (16 * (count + 6)) & 0xfff0;

    packet[198] = (unsigned char)countField;
    packet[199] = (unsigned char)(countField >> 8);
#endif
}

static void
NSDebugRecordAllocationEvent(int eventType, va_list arguments)
{
    unsigned packetWords[NS_ALLOCATION_EVENT_PACKET_SIZE / sizeof(unsigned)];
    unsigned char *packet = (unsigned char *)packetWords;
    unsigned *words = packetWords;
    id object = nil;
    id copiedObject = nil;
    NSZone *zone = NULL;
    void *pointer = NULL;
    void *data = NULL;
    const char *className = NULL;
    unsigned size = 0;
    unsigned extraBytes = 0;
    unsigned traceCount = 0;
    unsigned traceLimit = (NS_ALLOCATION_EVENT_PACKET_SIZE - 248) / 8;
    unsigned index;
    void *frame;
    void *nextFrame;
    BOOL locked;
    BOOL negativeRetainObjectRead = NO;
    char *portName;
    char *hostName = NULL;
    const char *host = "";
    char ppcHostBuffer[260];
    port_t outputPort = 0;
    kern_return_t sendResult;

    if (eventType <= 15 && NSNegativeRetainCheckEnabled
        && (eventType == NSObjectAutoreleasedEvent
            || eventType == NSObjectExtraRefDecrementedEvent
            || eventType == NSObjectInternalRefDecrementedEvent)) {
        object = va_arg(arguments, id);
        negativeRetainObjectRead = YES;
        if (object != nil) {
            int virtualRetains = (int)[object retainCount]
                - (int)NSAutoreleasePoolCountForObject(object) - 1;
            if (virtualRetains < 0)
                _NSNegativeRetain(object, virtualRetains);
        }
    }

    if ((NSAllocationStatisticsOutputMask
         & (1U << ((unsigned)eventType & 31U))) == 0)
        return;

    locked = NSDebugLockAllocationRecord();
    if (sending_event_port == 0) {
        portName = _NSGetEnvironmentVariable("NSAllocationStatisticsOutputPortName");
        if (portName != NULL) {
            if (strncmp(portName, "mach-port://", 12) == 0) {
                char *slash = portName + 12;
                unsigned hostLength;

                while (*slash != '\0' && *slash != '/')
                    ++slash;
                hostLength = (unsigned)(slash - portName - 11);
#if defined(__ppc__) || defined(__POWERPC__)
                if (hostLength > 259)
                    hostLength = 259;
                hostName = ppcHostBuffer;
                memset(hostName, 0, 260);
                memmove(hostName, portName + 12, hostLength);
                hostName[hostLength - 1] = '\0';
#else
                hostName = (char *)NSZoneMalloc(NULL, hostLength);
                memmove(hostName, portName + 12, hostLength);
                hostName[hostLength - 1] = '\0';
#endif
                host = hostName;
                portName = slash + 1;
            }
            sendResult = netname_look_up((mach_port_t)[__NSMachNMServerPort machPort],
                                         (char *)host, portName, &outputPort);
#if !defined(__ppc__) && !defined(__POWERPC__)
            if (hostName != NULL)
                NSZoneFree(NULL, hostName);
#endif
            sending_event_port = sendResult == KERN_SUCCESS ? outputPort : 0;
        }
    }

    if (sending_event_port != 0 && eventType >= 0
        && eventType <= NSZoneRecycledEvent
        && (eventType < 12 || eventType > 15)) {
        switch (eventType) {
            case NSObjectAllocatedEvent:
                object = va_arg(arguments, id);
                extraBytes = va_arg(arguments, unsigned);
                pointer = object;
                if (object != nil) {
                    zone = NSZoneFromPointer(object);
                    size = object->isa->instance_size + extraBytes;
                }
                break;
            case NSObjectDeallocatedEvent:
            case NSObjectAutoreleasedEvent:
            case NSObjectExtraRefIncrementedEvent:
            case NSObjectExtraRefDecrementedEvent:
            case NSObjectInternalRefIncrementedEvent:
            case NSObjectInternalRefDecrementedEvent:
                if (!negativeRetainObjectRead)
                    object = va_arg(arguments, id);
                pointer = object;
                break;
            case NSObjectCopiedEvent:
                object = va_arg(arguments, id);
                extraBytes = va_arg(arguments, unsigned);
                copiedObject = va_arg(arguments, id);
                pointer = object;
                data = copiedObject;
                if (object != nil)
                    size = object->isa->instance_size + extraBytes;
                if (copiedObject != nil)
                    zone = NSZoneFromPointer(copiedObject);
                break;
            case NSJavaObjectAllocatedEvent:
                object = va_arg(arguments, id);
                size = va_arg(arguments, unsigned);
                className = va_arg(arguments, const char *);
                pointer = object;
                break;
            case NSJavaObjectFinalizedEvent:
                object = va_arg(arguments, id);
                (void)va_arg(arguments, const char *);
                className = va_arg(arguments, const char *);
                pointer = object;
                break;
            case NSZoneMallocEvent:
            case NSZoneCallocEvent:
                pointer = va_arg(arguments, void *);
                zone = va_arg(arguments, NSZone *);
                size = va_arg(arguments, unsigned);
                break;
            case NSZoneReallocEvent:
                pointer = va_arg(arguments, void *);
                zone = va_arg(arguments, NSZone *);
                size = va_arg(arguments, unsigned);
                data = va_arg(arguments, void *);
                break;
            case NSZoneFreeEvent:
                pointer = va_arg(arguments, void *);
                break;
            case NSVMAllocateEvent:
            case NSVMDeallocateEvent:
                pointer = va_arg(arguments, void *);
                size = va_arg(arguments, unsigned);
                break;
            case NSVMCopyEvent:
                pointer = va_arg(arguments, void *);
                size = va_arg(arguments, unsigned);
                data = va_arg(arguments, void *);
                break;
            case NSZoneCreatedEvent:
                zone = va_arg(arguments, NSZone *);
                pointer = zone;
                size = va_arg(arguments, unsigned);
                data = (void *)(unsigned long)va_arg(arguments, unsigned);
                break;
            case NSZoneRecycledEvent:
                zone = va_arg(arguments, NSZone *);
                pointer = zone;
                break;
            case NSObjectPoolDeallocStartedEvent:
            case NSObjectPoolDeallocFinishedEvent:
                pointer = va_arg(arguments, void *);
                break;
            default:
                break;
        }

        unsigned char *classField = packet + 28;
        unsigned classLength;
        double eventTime;

        NSDebugInitializeAllocationPacket(packet);
        words[1] = 0;
        words[4] = sending_event_port;
        words[5] = NSAllocationEventRequestedVersion;
        eventTime = (double)_NSCurrentTime();
        memcpy(packet + 156, &eventTime, sizeof(eventTime));

        if (eventType <= NSJavaObjectFinalizedEvent
            && eventType != NSObjectPoolDeallocStartedEvent
            && eventType != NSObjectPoolDeallocFinishedEvent) {
            if (eventType == NSJavaObjectAllocatedEvent
                || eventType == NSJavaObjectFinalizedEvent) {
                if (className != NULL) {
                    classLength = (unsigned)strlen(className);
                    if (classLength > 127)
                        classLength = 127;
                    memmove(classField, className, classLength);
                    classField[classLength] = '\0';
                }
            } else if (object != nil && object->isa != Nil) {
                className = object->isa->name;
                classLength = (unsigned)strlen(className);
                if (classLength > 127)
                    classLength = 127;
                memmove(classField, className, classLength);
                classField[classLength] = '\0';
            }
        }

        if (eventType >= NSObjectExtraRefIncrementedEvent
            && eventType <= NSObjectInternalRefDecrementedEvent)
            data = (void *)(unsigned long)[object retainCount];

        words[42] = NSAllocationEventSequence++;
        words[43] = eventType;
        words[44] = size;
        words[45] = 0;
        words[50] = 0;
        words[51] = (unsigned)cthread_thread(cthread_self());
        words[52] = 0;
        words[53] = (unsigned)zone;
        words[54] = 0;
        words[55] = (unsigned)pointer;
        words[56] = 0;
        words[57] = (unsigned)data;

        frame = _NSFirstFrameAddress();
#if defined(__ppc__) || defined(__POWERPC__)
        frame = _NSNextFrameAddress(frame);
#endif
        nextFrame = _NSNextFrameAddress(frame);
        for (index = 0; index < traceLimit; ++index) {
            if ((unsigned long)nextFrame <= 0x7ff)
                break;
            frame = _NSReturnAddressFromFrameAddress(frame);
            words[62 + 2 * index] = 0;
            words[63 + 2 * index] = (unsigned)frame;
            frame = nextFrame;
            nextFrame = _NSNextFrameAddress(frame);
            ++traceCount;
        }
        words[45] = traceCount;
        words[1] = 248 + 8 * traceCount;
        NSDebugSetAllocationTraceCount(packet, traceCount);

        sendResult = msg_send((msg_header_t *)packet, SEND_TIMEOUT, 0);
        if (sendResult == -103)
            (void)msg_send((msg_header_t *)packet, 0x20, 0);
    }

    if (locked)
        NSDebugUnlockAllocationRecord();
}

void
NSRecordAllocationEvent(int eventType, ...)
{
    va_list arguments;

    va_start(arguments, eventType);
    NSDebugRecordAllocationEvent(eventType, arguments);
    va_end(arguments);
}

BOOL
NSWaitForAllocationEvent(NSPort *eventPort, void **message,
                         NSTimeInterval timeout)
{
    unsigned char storage[NS_ALLOCATION_EVENT_PACKET_SIZE];
    msg_header_t *header = (msg_header_t *)storage;
    msg_timeout_t receiveTimeout;
    double timeoutMilliseconds = 1000.0 * timeout;

    header->msg_local_port = (port_t)[eventPort machPort];
    header->msg_size = sizeof(storage);
#if defined(__ppc__) || defined(__POWERPC__)
    if (timeoutMilliseconds >= 2147483648.0)
        receiveTimeout = (msg_timeout_t)(int)(timeoutMilliseconds - 2147483648.0)
            ^ 0x80000000U;
    else
        receiveTimeout = (msg_timeout_t)(int)timeoutMilliseconds;
#else
    receiveTimeout = (msg_timeout_t)timeoutMilliseconds;
#endif
    if (msg_receive(header, RCV_TIMEOUT,
                    receiveTimeout) != RCV_SUCCESS)
        return NO;

    if (message != NULL) {
        *message = NSZoneRealloc(NSZoneFromPointer(*message), *message,
                                 sizeof(storage));
        memmove(*message, storage, sizeof(storage));
    }
    return YES;
}

#if !defined(__ppc__) && !defined(__POWERPC__)
static unsigned
NSDebugByteSwap32(unsigned value)
{
    return ((value & 0x000000ffU) << 24)
        | ((value & 0x0000ff00U) << 8)
        | ((value & 0x00ff0000U) >> 8)
        | ((value & 0xff000000U) >> 24);
}
#endif

void
NSParseAllocationEvent(void *message, void *allocEvent,
                       unsigned long long **backtrace,
                       unsigned long *numBacktrace)
{
    const unsigned *words = (const unsigned *)message;

    if (allocEvent != NULL) {
        unsigned *eventWords = (unsigned *)allocEvent;

#if defined(__ppc__) || defined(__POWERPC__)
        memmove(eventWords + 3, words + 39, 8);
#else
        eventWords[3] = NSDebugByteSwap32(words[40]);
        eventWords[4] = NSDebugByteSwap32(words[39]);
#endif
        eventWords[1] = words[42];
        eventWords[2] = words[43];
        eventWords[5] = words[50];
        eventWords[6] = words[51];
        eventWords[7] = words[52];
        eventWords[8] = words[53];
        eventWords[9] = words[54];
        eventWords[10] = words[55];
        eventWords[11] = words[56];
        eventWords[12] = words[57];
        eventWords[13] = words[44];
        memmove(eventWords + 14, words + 7, 128);
    }

    if (numBacktrace != NULL)
        *numBacktrace = words[45];

    if (backtrace != NULL) {
        unsigned *traceWords;
        unsigned index;

        *backtrace = (unsigned long long *)NSZoneRealloc(
            NSZoneFromPointer(*backtrace), *backtrace, 8 * words[45]);
        traceWords = (unsigned *)*backtrace;
        for (index = 0; index < words[45]; ++index) {
            traceWords[2 * index] = words[2 * index + 62];
            traceWords[2 * index + 1] = words[2 * index + 63];
        }
    }
}

#if !defined(__ppc__) && !defined(__POWERPC__)
@implementation NSProxy (NSDebuggerExtras)

- (void)printForDebugger:(NXStream *)stream
{
    const char *string = [[[self description] displayableString] cString];

    NXPrintf(stream, "%s", string);
    NXFlush(stream);
}

@end

@implementation NSObject (NSDebuggerExtras)

- (void)printForDebugger:(NXStream *)stream
{
    const char *string = [[[self description] displayableString] cString];

    NXPrintf(stream, "%s", string);
    NXFlush(stream);
}

@end
#endif

/*  NSDebug.h declares the (NSAutoreleasePoolDebugging) category on
    NSAutoreleasePool, which is why the stub generator originally placed
    an @implementation here.  The reference binary's own __OBJC,
    __module_info places these 11 methods in the SAME module as the rest
    of NSAutoreleasePool's class methods, not in a module of their own
    (confirmed by stage 2a's committed abi/NSAutoreleasePool.json, which
    lists all 15 class methods -- including these 11 -- directly under
    the class, with no separate category entry) -- so the real
    implementation belongs, and now lives, in NSAutoreleasePool.m, not
    here.  Removed to avoid two translation units defining the same
    @implementation NSAutoreleasePool selectors (this file's stub bodies
    were a real duplicate-definition hazard once NSAutoreleasePool.m
    implemented them for real; see divergences.md).  */

void *
_NSFirstFrameAddress(void)
{
    return __builtin_frame_address(1);
}

void *
_NSNextFrameAddress(void *frame)
{
    return *(void **)frame;
}

void *
_NSReturnAddressFromFrameAddress(void *frame)
{
#if defined(__ppc__) || defined(__POWERPC__)
    return *(void **)((char *)frame + 8);
#else
    return *(void **)((char *)frame + 4);
#endif
}

NSString *
NSStringFromStack(NSString *format, NSString *separator)
{
    NSMutableString *string;
    void *frame;
    BOOL first = YES;

    if (format == nil)
        format = @"0x%x";
    if (separator == nil)
        separator = @" ";
    string = [[[NSMutableString allocWithZone:NULL] initWithCapacity:1024]
        autorelease];
    frame = _NSFirstFrameAddress();
    for (;;) {
        unsigned length;
        void *nextFrame;

        if (!first) {
            length = [string length];
            [string replaceCharactersInRange:NSMakeRange(length, 0)
                                  withString:separator];
        }
        first = NO;
        nextFrame = _NSNextFrameAddress(frame);
        if ((unsigned)nextFrame <= 0x7ff)
            break;
        [string appendFormat:format, _NSReturnAddressFromFrameAddress(frame)];
        frame = nextFrame;
    }
    return string;
}

void *
NSFrameAddress(unsigned frame)
{
    void *address = _NSFirstFrameAddress();

    if (frame != (unsigned)-1) {
        for (;;) {
            address = _NSNextFrameAddress(address);
            if ((unsigned)address <= 0x7ff)
                return NULL;
            if (--frame == (unsigned)-1)
                return address;
        }
    }
    return address;
}

void *
NSReturnAddress(unsigned frame)
{
    void *address = NSFrameAddress(frame);

    return address == NULL ? NULL : _NSReturnAddressFromFrameAddress(address);
}

unsigned
NSCountFrames(void)
{
    unsigned count = 0;
    void *address = _NSFirstFrameAddress();

    for (;;) {
        address = _NSNextFrameAddress(address);
        if ((unsigned)address <= 0x7ff)
            return count;
        count++;
    }
}
