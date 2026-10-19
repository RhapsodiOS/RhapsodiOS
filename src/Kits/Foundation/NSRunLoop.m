/*	NSRunLoop.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSRunLoop.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSException.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSPortMessage.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import "NSPerformTimerPrivate.h"

#include <mach/mach.h>
#include <mach/message.h>
#include <mach/cthreads.h>
#include <string.h>

extern unsigned NSPushAutoreleasePool(void);
extern void NSPopAutoreleasePool(unsigned token);
extern NSDate *__NSDistantFutureDate;
extern id __NSEmptyArray;
extern Class __NSMachPortClass, __NSConstantStringClass, __NSInlineCStringClass;

NSString * const NSDefaultRunLoopMode = @"NSDefaultRunLoopMode";

@interface NSMachPort : NSPort
@end

typedef struct {
    unsigned count;
    unsigned capacity;
    unsigned references;
    id objects[1];
} NSRunLoopPortVector;

typedef struct {
    NSRunLoopPortVector *ports;
    unsigned portSet;
} NSRunLoopModePortSet;

typedef struct NSRunLoopModeInfo {
    struct NSRunLoopModeInfo *next;
    NSString *mode;
    NSTimeInterval nextFireTime;
    unsigned char flag16;
    unsigned char reserved[3];
    void *delegates;
    NSRunLoopModePortSet *portSet;
} NSRunLoopModeInfo;

typedef struct {
    NSPort *port;
    union {
        msg_header_t header;
        char bytes[256];
    } message;
} NSRunLoopInputBuffer;

typedef struct {
    unsigned head;
    unsigned count;
    unsigned capacity;
    NSRunLoopInputBuffer **buffers;
} NSRunLoopMessageQueue;

typedef struct {
    Class isa;
    void *modes;
    id currentMode;
    id callout;
    void *callouts;
    void *timers;
    id condition;
    void *currentSet;
    char *msg;
} NSRunLoopWorkerFields;

typedef struct NSRunLoopPerformer {
    Class isa;
    struct NSRunLoopPerformer *next;
    id target;
    SEL selector;
    id argument;
    unsigned order;
    NSArray *modes;
    unsigned short firing : 1;
    unsigned short invalid : 1;
    unsigned short filler : 14;
    unsigned short refCount : 16;
} NSRunLoopPerformer;

NSRunLoopModePortSet *_NSRunLoopAllPorts;
NSRunLoopPortVector *_NSRunLoopAllRunLoops;
NSRunLoop *_NSNotifyRunLoop;
NSPort *_NSMachNotifyPort;
NSLock *_NSRunLoopLock;
NSLock *_NSRunLoopAllPortsLock;
NSLock *MsgBufferGate;
NSLock *ModePortsGate;
static cthread_t WorkerThread;
static NSRunLoopInputBuffer *MsgBuffers;
static unsigned MsgBufferCacheCount;
static NSRunLoopMessageQueue *NSRunLoopMessages;

#import "NSProcessInfoPrivate.h"

static NSRunLoopPortVector *NSRunLoopCreatePortVector(unsigned capacity) {
    NSRunLoopPortVector *vector = (NSRunLoopPortVector *)NSZoneMalloc(
        NULL, (unsigned)(sizeof(NSRunLoopPortVector) + (capacity - 1) * sizeof(id)));

    vector->count = 0;
    vector->capacity = capacity;
    vector->references = 1;
    return vector;
}

static NSRunLoopPortVector *NSRunLoopAppendObject(NSRunLoopPortVector *vector,
                                                  id object) {
    if (vector->capacity < vector->count + 1) {
        vector->capacity = 2 * vector->capacity + 1;
        vector = (NSRunLoopPortVector *)NSZoneRealloc(
            NULL, vector,
            (unsigned)(12 + vector->capacity * sizeof(id)));
    }
    vector->objects[vector->count++] = [object retain];
    return vector;
}

static void NSRunLoopRemoveObjectAtIndex(NSRunLoopPortVector *vector,
                                         unsigned index) {
    [vector->objects[index] release];
    vector->count--;
    if (index < vector->count)
        memmove(&vector->objects[index], &vector->objects[index + 1],
                (vector->count - index) * sizeof(id));
}

static int NSRunLoopFindObject(NSRunLoopPortVector *vector, id object) {
    unsigned index;

    if (vector != NULL) {
        for (index = 0; index < vector->count; index++) {
            if (vector->objects[index] == object)
                return (int)index;
        }
    }
    return -1;
}

static int NSRunLoopFindLastObject(NSRunLoopPortVector *vector, id object) {
    unsigned index;

    if (vector != NULL) {
        index = vector->count;
        while (index != 0) {
            index--;
            if (vector->objects[index] == object)
                return (int)index;
        }
    }
    return -1;
}

static unsigned NSRunLoopCountObject(NSRunLoopPortVector *vector, id object) {
    unsigned count = 0;
    unsigned index;

    if (vector != NULL) {
        for (index = 0; index < vector->count; index++) {
            if (vector->objects[index] == object)
                count++;
        }
    }
    return count;
}

static BOOL NSRunLoopIsDefaultMode(NSString *mode) {
    return mode == NSDefaultRunLoopMode || [mode isEqual:NSDefaultRunLoopMode];
}

static id NSRunLoopCombineTimerModes(id existingModes, NSString *mode) {
    if (existingModes != nil) {
        if (existingModes == NSDefaultRunLoopMode)
            return mode;
        if ([existingModes isKindOfClass:[NSString class]]) {
            NSMutableArray *modes = [NSMutableArray arrayWithObject:existingModes];
            [modes addObject:NSDefaultRunLoopMode];
            [modes addObject:existingModes];
            [modes addObject:mode];
            return modes;
        }
        if ([existingModes count] == 1 && NSRunLoopIsDefaultMode(mode))
            return [existingModes objectAtIndex:0];
        if (![existingModes containsObject:mode])
            [existingModes addObject:mode];
        return existingModes;
    }
    if (NSRunLoopIsDefaultMode(mode))
        return NSDefaultRunLoopMode;
    return [NSMutableArray arrayWithObject:mode];
}

static NSTimer *NSRunLoopTimerAt(NSRunLoopPortVector *timers, unsigned index) {
    return (NSTimer *)timers->objects[index * 2];
}

static id NSRunLoopTimerModesAt(NSRunLoopPortVector *timers, unsigned index) {
    return timers->objects[index * 2 + 1];
}

static void NSRunLoopSetTimerModesAt(NSRunLoopPortVector *timers,
                                     unsigned index, id modes) {
    id oldModes = timers->objects[index];

    [modes retain];
    [oldModes release];
    timers->objects[index] = modes;
}

static void NSRunLoopInsertTimer(NSRunLoopPortVector **timerVector,
                                 NSTimer *timer, id modes, BOOL combineModes) {
    NSRunLoopPortVector *timers = *timerVector;
    int searchIndex = (int)timers->count - 2;
    unsigned index;
    NSTimeInterval fireTime = [[timer fireDate] timeIntervalSinceReferenceDate];

    while (searchIndex >= 0) {
        NSTimer *existingTimer;
        NSTimeInterval existingFireTime;

        existingTimer = (NSTimer *)timers->objects[searchIndex];
        if (existingTimer == timer) {
            if (combineModes) {
                id combinedModes = NSRunLoopCombineTimerModes(
                    timers->objects[searchIndex + 1], (NSString *)modes);
                NSRunLoopSetTimerModesAt(timers,
                                         (unsigned)(searchIndex + 1),
                                         combinedModes);
            }
            return;
        }
        if (![existingTimer isValid]) {
            searchIndex -= 2;
            continue;
        }
        existingFireTime = [[existingTimer fireDate]
            timeIntervalSinceReferenceDate];
        if (existingFireTime < fireTime)
            break;
        searchIndex -= 2;
    }

    if (searchIndex == -2)
        index = 0;
    else if (searchIndex >= 0)
        index = (unsigned)(searchIndex + 2);
    else
        return;

    if (timers->capacity < timers->count + 1) {
        timers->capacity = 2 * timers->capacity + 1;
        timers = (NSRunLoopPortVector *)NSZoneRealloc(
            NULL, timers, (unsigned)(12 + timers->capacity * sizeof(id)));
    }
    timers->count++;
    if (index < timers->count - 1)
        memmove(&timers->objects[index + 1], &timers->objects[index],
                (timers->count - index - 1) * sizeof(id));
    timers->objects[index] = [timer retain];
    *timerVector = timers;

    if (combineModes)
        modes = NSRunLoopCombineTimerModes(nil, (NSString *)modes);
    index++;
    if (timers->capacity < timers->count + 1) {
        timers->capacity = 2 * timers->capacity + 1;
        timers = (NSRunLoopPortVector *)NSZoneRealloc(
            NULL, timers, (unsigned)(12 + timers->capacity * sizeof(id)));
    }
    timers->count++;
    if (index < timers->count - 1)
        memmove(&timers->objects[index + 1], &timers->objects[index],
                (timers->count - index - 1) * sizeof(id));
    timers->objects[index] = [modes retain];
    *timerVector = timers;
}

static void NSRunLoopRemoveTimerAt(NSRunLoopPortVector *timers,
                                   unsigned index) {
    unsigned objectIndex = index * 2;
    [timers->objects[objectIndex] release];
    [timers->objects[objectIndex + 1] release];
    timers->count -= 2;
    if (objectIndex < timers->count)
        memmove(&timers->objects[objectIndex],
                &timers->objects[objectIndex + 2],
                (timers->count - objectIndex) * sizeof(id));
}

static int NSRunLoopFindTimer(NSRunLoopPortVector *timers, NSTimer *timer) {
    unsigned index = timers->count / 2;

    while (index != 0) {
        index--;
        if (NSRunLoopTimerAt(timers, index) == timer)
            return (int)index;
    }
    return -1;
}

static void NSRunLoopReleaseVector(NSRunLoopPortVector *vector) {
    unsigned index;

    if (vector == NULL || --vector->references != 0)
        return;
    for (index = 0; index < vector->count; index++)
        [vector->objects[index] release];
    NSZoneFree(NULL, vector);
}

static void NSRunLoopReleaseModeInfo(NSRunLoopModeInfo **modes) {
    NSRunLoopModeInfo *info = *modes;

    while (info != NULL) {
        NSRunLoopModeInfo *next = info->next;
        BOOL releasePortSet = info->portSet->ports->references == 1;

        NSRunLoopReleaseVector(info->portSet->ports);
        if (releasePortSet) {
            port_set_deallocate(task_self_, info->portSet->portSet);
            NSZoneFree(NULL, info->portSet);
        }
        NSRunLoopReleaseVector((NSRunLoopPortVector *)info->delegates);
        [info->mode release];
        NSZoneFree(NULL, info);
        info = next;
    }
    *modes = NULL;
}

static void NSRunLoopEnsureAllPorts(void) {
    mach_port_t portSet;
    kern_return_t error;

    if (_NSRunLoopAllPorts != NULL)
        return;
    error = port_set_allocate(task_self_, &portSet);
    if (error != KERN_SUCCESS)
        [NSException raise:NSInternalInconsistencyException
                    format:@"couldn't allocate port set (%d)", error];
    _NSRunLoopAllPorts = (NSRunLoopModePortSet *)NSZoneMalloc(NULL, 8);
    _NSRunLoopAllPorts->ports = NSRunLoopCreatePortVector(16);
    _NSRunLoopAllPorts->portSet = portSet;
}

static void NSRunLoopAddPortToGlobalSet(NSPort *port) {
    mach_error_t error;
    mach_port_t machPort;

    if (NSRunLoopFindObject(_NSRunLoopAllPorts->ports, port) < 0) {
        machPort = (mach_port_t)[port machPort];
        error = port_set_add(task_self_, _NSRunLoopAllPorts->portSet, machPort);
        if (error != KERN_SUCCESS)
            [NSException raise:NSInternalInconsistencyException
                        format:@"couldn't add port %d to port set %d (%s)",
                               machPort, _NSRunLoopAllPorts->portSet,
                               mach_error_string(error)];
    }
    _NSRunLoopAllPorts->ports = NSRunLoopAppendObject(
        _NSRunLoopAllPorts->ports, port);
}

static void NSRunLoopEnsureMachNotifyPort(void) {
    mach_port_t specialPort = MACH_PORT_NULL;
    kern_return_t error;

    if (_NSMachNotifyPort != nil)
        return;
    error = task_get_special_port(task_self_, 2, &specialPort);
    if (error != KERN_SUCCESS || specialPort == MACH_PORT_NULL) {
        _NSMachNotifyPort = [[NSPort allocWithZone:NULL] init];
        task_set_special_port(task_self_, 2,
                              (mach_port_t)[_NSMachNotifyPort machPort]);
    } else {
        _NSMachNotifyPort = [[NSPort allocWithZone:NULL]
            initWithMachPort:specialPort];
    }
    [_NSMachNotifyPort setDelegate:__NSMachPortClass];
    NSRunLoopAddPortToGlobalSet(_NSMachNotifyPort);
}

static NSRunLoopInputBuffer *NSRunLoopAllocateBuffer(void) {
    NSRunLoopInputBuffer *buffer;

    if (MsgBufferGate != nil)
        [MsgBufferGate lock];
    buffer = MsgBuffers;
    if (buffer != NULL) {
        MsgBuffers = *(NSRunLoopInputBuffer **)buffer;
        MsgBufferCacheCount--;
        if (MsgBufferGate != nil)
            [MsgBufferGate unlock];
    } else {
        if (MsgBufferGate != nil)
            [MsgBufferGate unlock];
        buffer = (NSRunLoopInputBuffer *)NSZoneMalloc(NULL, 260);
        buffer->message.header.msg_size = 256;
    }
    buffer->port = nil;
    return buffer;
}

static void NSRunLoopDeallocateBuffer(NSRunLoopInputBuffer *buffer) {
    if (buffer->port != nil)
        [buffer->port release];
    if (MsgBufferGate != nil)
        [MsgBufferGate lock];
    if (MsgBufferCacheCount <= 4
        && buffer->message.header.msg_size <= 256) {
        buffer->message.header.msg_size = 256;
        *(NSRunLoopInputBuffer **)buffer = MsgBuffers;
        MsgBuffers = buffer;
        MsgBufferCacheCount++;
    } else {
        NSZoneFree(NULL, buffer);
    }
    if (MsgBufferGate != nil)
        [MsgBufferGate unlock];
}

unsigned _NSMsgReceiveCount;
unsigned _NSMsgResizeCount;

NSRunLoopInputBuffer *NSCheapPortSetAcceptInput(
        NSRunLoopModePortSet *portSet, NSRunLoopInputBuffer *buffer,
        NSTimeInterval beforeTime) {
    int options = RCV_LARGE;
    int timeout = 0;
    int result;

    if (portSet == NULL)
        return NULL;
    if (beforeTime < 4294967.295) {
        options |= RCV_TIMEOUT;
        if (beforeTime > 0.0)
            timeout = (int)(beforeTime * 1000.0);
    }
    ++_NSMsgReceiveCount;
    buffer->message.header.msg_local_port = portSet->portSet;
    for (;;) {
        result = msg_receive(&buffer->message.header, options, timeout);
        if (result == 0)
            break;
        if (result == RCV_TOO_LARGE) {
            buffer = (NSRunLoopInputBuffer *)NSZoneRealloc(
                NULL, buffer,
                (unsigned)(sizeof(NSPort *) + buffer->message.header.msg_size));
            ++_NSMsgResizeCount;
            continue;
        }
        if (result == RCV_TIMED_OUT)
            return NULL;
        [NSException raise:(result == RCV_INVALID_PORT
                                ? NSInvalidReceivePortException
                                : NSPortReceiveException)
                    format:@"Port receive error:%s", mach_error_string(result)];
    }
    buffer->port = [NSMachPort newWithMachPort:
        (int)buffer->message.header.msg_local_port];
    return buffer;
}

static void NSRunLoopEnqueueMessage(NSRunLoopInputBuffer *buffer) {
    NSRunLoopMessageQueue *queue = NSRunLoopMessages;
    unsigned index;

    if (queue == NULL) {
        queue = (NSRunLoopMessageQueue *)NSZoneMalloc(NULL,
                                                     sizeof(NSRunLoopMessageQueue));
        queue->head = 0;
        queue->count = 0;
        queue->capacity = 5;
        queue->buffers = (NSRunLoopInputBuffer **)NSZoneMalloc(
            NULL, queue->capacity * sizeof(NSRunLoopInputBuffer *));
        NSRunLoopMessages = queue;
    }
    if (queue->count == queue->capacity) {
        unsigned oldCapacity = queue->capacity;

        queue->capacity *= 2;
        queue->buffers = (NSRunLoopInputBuffer **)NSZoneRealloc(
            NULL, queue->buffers,
            queue->capacity * sizeof(NSRunLoopInputBuffer *));
        if (queue->head != 0)
            memmove(&queue->buffers[oldCapacity], queue->buffers,
                    queue->head * sizeof(NSRunLoopInputBuffer *));
    }
    index = queue->head + queue->count;
    if (index >= queue->capacity)
        index -= queue->capacity;
    queue->buffers[index] = buffer;
    queue->count++;
}

static NSRunLoopInputBuffer *NSRunLoopDequeueMessage(
        NSRunLoopModeInfo *modeInfo, NSRunLoop *runLoop) {
    NSRunLoopMessageQueue *queue = NSRunLoopMessages;
    NSRunLoopInputBuffer *buffer;
    NSPort *port;
    unsigned offset;

    if (queue == NULL || queue->count == 0)
        return NULL;
    for (offset = 0; offset < queue->count; offset++) {
        unsigned index = queue->head + offset;
        unsigned found;

        if (index >= queue->capacity)
            index -= queue->capacity;
        buffer = queue->buffers[index];
        port = buffer->port;
        found = 0;
        if (ModePortsGate != nil)
            [ModePortsGate lock];
        if (modeInfo->portSet->ports != NULL
            && NSRunLoopFindObject(modeInfo->portSet->ports, port) >= 0)
            found = 1;
        if (ModePortsGate != nil)
            [ModePortsGate unlock];
        if (found || (port == _NSMachNotifyPort && runLoop == _NSNotifyRunLoop))
            break;
    }
    if (offset == queue->count)
        return NULL;

    {
        unsigned index = queue->head + offset;

        if (index >= queue->capacity)
            index -= queue->capacity;
        buffer = queue->buffers[index];
        queue->count--;
        if (queue->count != 0) {
            if (index != 0) {
                while (index != queue->head && index != 0) {
                    queue->buffers[index] = queue->buffers[index - 1];
                    index--;
                }
            }
            if (index == 0 && queue->head != 0) {
                queue->buffers[0] = queue->buffers[queue->capacity - 1];
                for (index = queue->capacity - 1;
                     index != queue->head; index--)
                    queue->buffers[index] = queue->buffers[index - 1];
            }
            if (queue->capacity == ++queue->head)
                queue->head = 0;
        }
    }

    NSRunLoopEnsureAllPorts();
    NSRunLoopEnsureMachNotifyPort();
    if (NSRunLoopFindObject(_NSRunLoopAllPorts->ports, buffer->port) >= 0)
        port_set_add(task_self_, _NSRunLoopAllPorts->portSet,
                     (mach_port_t)[buffer->port machPort]);
    return buffer;
}

static any_t NSRunLoopWorker(any_t argument) {
	unsigned pool = NSPushAutoreleasePool();

    (void)argument;
    (void)pool;
    for (;;) {
        NSRunLoopInputBuffer *buffer = NSRunLoopAllocateBuffer();
        NSRunLoop *runLoop = NULL;
        NSPort *port;
        int index;

        while ((buffer = NSCheapPortSetAcceptInput(
                    _NSRunLoopAllPorts, buffer, 4294967295.0)) == NULL)
            ;
        port = buffer->port;
        if (_NSRunLoopLock != nil)
            [_NSRunLoopLock lock];
        for (index = _NSRunLoopAllRunLoops == NULL
                         ? -1 : (int)_NSRunLoopAllRunLoops->count - 1;
             index >= 0; index--) {
            NSRunLoop *candidate = (NSRunLoop *)
                _NSRunLoopAllRunLoops->objects[index];
            NSRunLoopWorkerFields *fields = (NSRunLoopWorkerFields *)candidate;
            BOOL acceptsPort = NO;
            NSRunLoopModePortSet *currentSet;
            unsigned portIndex;

            [fields->condition lock];
            currentSet = (NSRunLoopModePortSet *)fields->currentSet;
            if (currentSet != NULL && fields->msg == NULL) {
                if (ModePortsGate != nil)
                    [ModePortsGate lock];
                if (currentSet->ports != NULL) {
                    for (portIndex = 0;
                         portIndex < currentSet->ports->count; portIndex++) {
                        if (currentSet->ports->objects[portIndex] == port) {
                            acceptsPort = YES;
                            break;
                        }
                    }
                }
                if (ModePortsGate != nil)
                    [ModePortsGate unlock];
                if (acceptsPort
                    || (port == _NSMachNotifyPort
                        && candidate == _NSNotifyRunLoop)) {
                    runLoop = candidate;
                    break;
                }
            }
            [fields->condition unlock];
        }
        if (runLoop != nil) {
            NSRunLoopWorkerFields *fields = (NSRunLoopWorkerFields *)runLoop;

            if (_NSRunLoopLock != nil)
                [_NSRunLoopLock unlock];
            fields->msg = (char *)buffer;
            [fields->condition unlock];
            [fields->condition signal];
        } else {
            NSRunLoopEnqueueMessage(buffer);
            if (_NSRunLoopAllPorts != NULL)
                port_set_remove(task_self_, (mach_port_t)[port machPort]);
            if (_NSRunLoopLock != nil)
                [_NSRunLoopLock unlock];
        }
    }
    return NULL;
}

static NSRunLoopModeInfo *NSRunLoopCreateModeInfo(NSRunLoopModeInfo **modes,
                                                   NSString *mode) {
    NSRunLoopModeInfo *info;
    mach_port_t portSet;
    kern_return_t error;

    info = (NSRunLoopModeInfo *)NSZoneMalloc(NULL, sizeof(NSRunLoopModeInfo));
    info->nextFireTime = 0;
    info->flag16 = 0;
    memset(info->reserved, 0, sizeof(info->reserved));
    info->delegates = NULL;
    error = port_set_allocate(task_self_, &portSet);
    if (error != KERN_SUCCESS)
        [NSException raise:NSInternalInconsistencyException
                    format:@"couldn't allocate port set (%d)", error];
    info->portSet = (NSRunLoopModePortSet *)NSZoneMalloc(NULL, 8);
    info->portSet->ports = NSRunLoopCreatePortVector(2);
    info->portSet->portSet = portSet;
    info->mode = [mode copyWithZone:NULL];
    info->next = *modes;
    *modes = info;
    return info;
}

static NSRunLoopModeInfo *NSRunLoopFindModeInfo(NSRunLoopModeInfo **modes,
                                                NSString *mode) {
    NSRunLoopModeInfo *info = *modes;
    NSRunLoopModeInfo *previous = NULL;

    while (info != NULL && info->mode != mode
           && ![(id)info->mode isEqual:mode]) {
        previous = info;
        info = info->next;
    }

    if (info != NULL && previous != NULL) {
        previous->next = info->next;
        info->next = *modes;
        *modes = info;
    }
    return info;
}

@interface NSThread (NSRunLoopPrivate)
- (NSRunLoop *)runLoop;
- (void)setRunLoop:(NSRunLoop *)runLoop;
@end

@interface NSRunLoop (NSRunLoopTimerPrivate)
- (NSRunLoopInputBuffer *)acceptInputForModeInfo:(NSRunLoopModeInfo *)modeInfo
                                        beforeTime:(NSTimeInterval)beforeTime;
- (BOOL)_nextTimerInterval:(NSTimeInterval *)interval
                   forMode:(NSString *)mode
                  modeInfo:(NSRunLoopModeInfo *)modeInfo;
- (void)_invalidateTimers;
- (void)removeTimersWithTarget:(id)target selector:(SEL)selector
                    withObject:(id)object;
- (void)_doPerformersForMode:(NSString *)mode reclaim:(BOOL)reclaim;
@end

@interface NSTimer (NSRunLoopTimerPrivate)
- (BOOL)_isEqualTimerWithTarget:(id)target selector:(SEL)selector
                     withObject:(id)object;
+ (void)scheduleTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target
                              selector:(SEL)selector withObject:(id)object;
+ (void)scheduleTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target
                              selector:(SEL)selector withObject:(id)object
                               inModes:(NSArray *)modes;
@end

@interface NSObject (NSRunLoopMonitorPrivate)
- (BOOL)_mightPostIdle;
- (BOOL)monitorRunLoop:(NSRunLoop *)runLoop
                  mode:(NSString *)mode
             activity:(unsigned)activity
                  quit:(BOOL *)quit;
- (void)monitoringDiscontinued;
@end

static BOOL NSRunLoopInformMonitors(NSRunLoop *runLoop, NSString *mode,
                                    unsigned activity, BOOL reclaim,
                                    id *callout, void **callouts) {
    BOOL handled = NO;
    BOOL quit = NO;
    NSRunLoopPortVector *monitors = (NSRunLoopPortVector *)*callouts;
    int index;

    if (*callout != nil) {
        quit = NO;
        handled |= [(id)*callout monitorRunLoop:runLoop mode:mode
                                      activity:activity quit:&quit];
        if (quit && reclaim) {
            [(id)*callout monitoringDiscontinued];
            [(id)*callout release];
            *callout = nil;
        }
    }
    if (monitors != NULL) {
        index = (int)monitors->count - 1;
        while (index >= 0) {
            id monitor = monitors->objects[index];

            quit = NO;
            handled |= [monitor monitorRunLoop:runLoop mode:mode
                                      activity:activity quit:&quit];
            if (quit && reclaim) {
                [monitor monitoringDiscontinued];
                NSRunLoopRemoveObjectAtIndex(monitors, (unsigned)index);
            }
            index--;
        }
        if (monitors->count == 0) {
            NSRunLoopReleaseVector(monitors);
            *callouts = NULL;
        }
    }
    return handled;
}

static NSString *NSRunLoopModeInfoDescription(NSRunLoopModeInfo *modeInfo) {
    NSMutableString *description = [[@"{" mutableCopy] autorelease];

    while (modeInfo != NULL) {
        NSRunLoopModePortSet *portSet = modeInfo->portSet;
        NSRunLoopPortVector *ports =
            portSet == NULL ? NULL : portSet->ports;
        id portDescription = @"()";
        NSArray *portArray = nil;

        if (ports != NULL && ports != (NSRunLoopPortVector *)-12) {
            portArray = [[NSArray allocWithZone:NULL]
                initWithObjects:ports->objects count:ports->count];
            portDescription = portArray;
        }
        [description appendFormat:@"%@ = %@;", modeInfo->mode,
                                 portDescription];
        [portArray release];
        modeInfo = modeInfo->next;
    }
    [description appendString:@"}"];
    return description;
}

static BOOL NSRunLoopTimerContainsMode(id modes, NSString *mode) {
    if (modes == mode)
        return YES;
    Class modesClass = *(Class *)modes;
    if (modesClass != __NSConstantStringClass
        && modesClass != __NSInlineCStringClass
        && ![modes isKindOfClass:[NSString class]])
        return [modes containsObject:mode];
    return mode == NSDefaultRunLoopMode || [modes isEqualToString:mode];
}

@implementation NSRunLoop

+ (void)_taskNowSingleThreaded {
    if (_NSRunLoopLock != nil) {
        [_NSRunLoopLock release];
        _NSRunLoopLock = nil;
    }
    if (_NSRunLoopAllPortsLock != nil) {
        [_NSRunLoopAllPortsLock release];
        _NSRunLoopAllPortsLock = nil;
    }
    if (MsgBufferGate != nil) {
        [MsgBufferGate release];
        MsgBufferGate = nil;
    }
    if (ModePortsGate != nil) {
        [ModePortsGate release];
        ModePortsGate = nil;
    }
}

+ (void)_taskNowMultiThreaded {
    NSLock *lock;

    lock = [NSLock allocWithZone:NULL];
    _NSRunLoopLock = [lock init];
    lock = [NSLock allocWithZone:NULL];
    _NSRunLoopAllPortsLock = [lock init];
    lock = [NSLock allocWithZone:NULL];
    MsgBufferGate = [lock init];
    lock = [NSLock allocWithZone:NULL];
    ModePortsGate = [lock init];

    NSRunLoopEnsureAllPorts();
    NSRunLoopEnsureMachNotifyPort();
    if (WorkerThread == NULL) {
        WorkerThread = cthread_fork(NSRunLoopWorker, NULL);
        if (WorkerThread != NULL) {
            cthread_set_name(WorkerThread, "Run Loop Worker");
            cthread_detach(WorkerThread);
        } else {
            NSLog(@"NSRunLoop can't fork worker thread.  Best to quit now.");
        }
    }
}

- (NSArray *)allModes {
    NSMutableArray *modes = [NSMutableArray array];
    NSRunLoopModeInfo *modeInfo;

    for (modeInfo = (NSRunLoopModeInfo *)_modes;
         modeInfo != NULL; modeInfo = modeInfo->next)
        [modes addObject:modeInfo->mode];
    return modes;
}

- (void)addRunLoopActivityMonitor:(id)monitor {
    NSRunLoopPortVector *monitors;

    if (_callout == nil) {
        _callout = [monitor retain];
        return;
    }

    monitors = (NSRunLoopPortVector *)_callouts;
    if (monitors == NULL)
        monitors = NSRunLoopCreatePortVector(2);
    _callouts = NSRunLoopAppendObject(monitors, monitor);
}

- (void)_wakeup {
    [_condition lock];
    if (_msg == NULL)
        _msg = (char *)-1;
    [_condition unlock];
    [_condition signal];
}

- (void)_doPerformersForMode:(NSString *)mode reclaim:(BOOL)reclaim {
    NSRunLoopPerformer *performer;

    for (performer = (NSRunLoopPerformer *)_performers; performer != NULL;
         performer = performer->next) {
        if (!performer->invalid
            && [performer->modes containsObject:mode])
            [(id)performer fire];
    }
    if (reclaim && _performers != NULL) {
        NSRunLoopPerformer *previous;

        while (_performers != NULL
               && ((NSRunLoopPerformer *)_performers)->invalid) {
            performer = (NSRunLoopPerformer *)_performers;
            _performers = performer->next;
            [(id)performer release];
        }
        previous = (NSRunLoopPerformer *)_performers;
        while (previous != NULL && previous->next != NULL) {
            performer = previous->next;
            if (performer->invalid) {
                previous->next = performer->next;
                [(id)performer release];
            } else {
                previous = performer;
            }
        }
    }
}

- (BOOL)_nextTimerInterval:(NSTimeInterval *)interval
                   forMode:(NSString *)mode
                  modeInfo:(NSRunLoopModeInfo *)modeInfo {
    NSRunLoopPortVector *timers;
    NSTimeInterval now = 0;
    BOOL haveCurrentTime = NO;
    BOOL firedTimer = NO;
    unsigned index;

    if (modeInfo->flag16) {
        now = (NSTimeInterval)_NSCurrentTime();
        haveCurrentTime = YES;
        if (modeInfo->nextFireTime > now) {
            *interval = modeInfo->nextFireTime;
            return YES;
        }
        modeInfo->flag16 = 0;
    }

    for (index = 0; ; ) {
        NSTimer *timer;
        id modes;

        timers = (NSRunLoopPortVector *)_timers;
        if (timers == NULL || index >= timers->count)
            break;
        timer = (NSTimer *)timers->objects[index];
        modes = timers->objects[index + 1];

        if (![timer isValid]) {
            NSRunLoopRemoveTimerAt(timers, index / 2);
            continue;
        }
        if (NSRunLoopTimerContainsMode(modes, mode)) {
            NSTimeInterval fireTime;

            if (!haveCurrentTime) {
                now = (NSTimeInterval)_NSCurrentTime();
                haveCurrentTime = YES;
            }
            fireTime = [[timer fireDate] timeIntervalSinceReferenceDate];
            if (fireTime > now) {
                if (!modeInfo->flag16 || fireTime < modeInfo->nextFireTime) {
                    modeInfo->nextFireTime = fireTime;
                    modeInfo->flag16 = 1;
                }
                break;
            }

            [timer retain];
            [modes retain];
            NSRunLoopRemoveTimerAt(timers, index / 2);
            [timer fire];
            firedTimer = YES;
            if ([timer isValid])
                NSRunLoopInsertTimer(
                    (NSRunLoopPortVector **)&_timers, timer, modes, NO);
            [timer release];
            [modes release];
            continue;
        }
        index += 2;
    }

    if (firedTimer) {
        if (_performers != NULL)
            [self _doPerformersForMode:mode reclaim:NO];
        if (_callout != nil || _callouts != NULL)
            NSRunLoopInformMonitors(self, _currentMode, 1, NO,
                                    &_callout, &_callouts);
    }
    *interval = modeInfo->nextFireTime;
    return modeInfo->flag16;
}

+ (NSRunLoop *)currentRunLoop {
    NSThread *thread = _NSCurrentThread();
    NSRunLoop *runLoop = [thread runLoop];

    if (runLoop == nil) {
        runLoop = [[self allocWithZone:NULL] init];
        [thread setRunLoop:runLoop];
        [runLoop release];
    }
    return runLoop;
}

- (id)init {
    NSThread *thread = _NSCurrentThread();

    if ([thread runLoop] != nil) {
        [super dealloc];
        return nil;
    }

    _timers = NULL;
    _callouts = NULL;
    if (_NSNotifyRunLoop == nil)
        _NSNotifyRunLoop = self;

    NSRunLoopEnsureAllPorts();
    NSRunLoopEnsureMachNotifyPort();

    _condition = [[NSCondition allocWithZone:[self zone]] init];
    _msg = NULL;

    if (_NSRunLoopLock != nil)
        [_NSRunLoopLock lock];
    if (_NSRunLoopAllRunLoops == NULL)
        _NSRunLoopAllRunLoops = NSRunLoopCreatePortVector(4);
    _NSRunLoopAllRunLoops = NSRunLoopAppendObject(_NSRunLoopAllRunLoops, self);
    if (_NSRunLoopLock != nil)
        [_NSRunLoopLock unlock];
    return self;
}

- (id)retain {
    NSIncrementExtraRefCount(self);
    return self;
}

- (unsigned)retainCount {
    return NSExtraRefCount(self) + 1;
}

- (oneway void)release {
    unsigned count = NSExtraRefCount(self);

    if (count != 0) {
        if (NSDecrementExtraRefCountWasZero(self)) {
            if (_NSRunLoopLock != nil)
                [_NSRunLoopLock lock];
            if (_NSRunLoopAllRunLoops != NULL) {
                NSRunLoopPortVector *runLoops = _NSRunLoopAllRunLoops;
                unsigned index;

                for (index = 0; index < runLoops->count; index++) {
                    id runLoop = runLoops->objects[index];

                    if (runLoop == self || [self isEqual:runLoop]) {
                        NSRunLoopRemoveObjectAtIndex(runLoops, index);
                        break;
                    }
                }
            }
            if (_NSRunLoopLock != nil)
                [_NSRunLoopLock unlock];
            [self dealloc];
        }
    } else if (NSKeepAllocationStatistics) {
        NSRecordAllocationEvent(NSObjectExtraRefDecrementedEvent, self);
    }
}

- (NSString *)currentMode {
    return _currentMode;
}

- (NSString *)description {
    id timersDescription = @"()";
    NSString *modeDescription;

#if defined(__ppc__) || defined(__POWERPC__)
    if (_timers != NULL) {
        NSRunLoopPortVector *timers = (NSRunLoopPortVector *)_timers;

        timersDescription = [[[NSArray allocWithZone:NULL]
            initWithObjects:timers->objects count:timers->count] autorelease];
    }
    modeDescription = NSRunLoopModeInfoDescription(
        (NSRunLoopModeInfo *)_modes);
#else
    modeDescription = NSRunLoopModeInfoDescription(
        (NSRunLoopModeInfo *)_modes);
    if (_timers != NULL) {
        NSRunLoopPortVector *timers = (NSRunLoopPortVector *)_timers;

        timersDescription = [[[NSArray allocWithZone:NULL]
            initWithObjects:timers->objects count:timers->count] autorelease];
    }
#endif
    return [NSString stringWithFormat:
        @"\nRunloop\n(currentMode %@)\n(timers %@)\n(modeInfo %@)\n",
        _currentMode, timersDescription, modeDescription];
}

- (BOOL)containsPort:(NSPort *)aPort forMode:(NSString *)mode {
    NSRunLoopModeInfo *modeInfo =
        NSRunLoopFindModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    NSRunLoopPortVector *ports;
    unsigned index;

    if (modeInfo == NULL || modeInfo->portSet == NULL)
        return NO;

    ports = modeInfo->portSet->ports;
    for (index = ports->count; index > 0; index--) {
        if (ports->objects[index - 1] == aPort)
            return YES;
    }
    return NO;
}

- (NSArray *)portsForMode:(NSString *)mode {
    NSRunLoopModeInfo *modeInfo =
        NSRunLoopFindModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    NSMutableArray *result;
    NSRunLoopPortVector *ports;
    unsigned index;

    if (modeInfo == NULL)
        return __NSEmptyArray;

    result = [NSMutableArray array];
    if (modeInfo->portSet == NULL || modeInfo->portSet->ports == NULL
        || modeInfo->portSet->ports == (NSRunLoopPortVector *)-12)
        return result;

    ports = modeInfo->portSet->ports;
    for (index = 0; index < ports->count; index++)
        [result addObject:ports->objects[index]];
    return result;
}

- (void)addTimer:(NSTimer *)timer forMode:(NSString *)mode {
    NSRunLoopModeInfo *modeInfo;
    NSTimeInterval fireTime;

    if (![timer isValid])
        return;

    modeInfo = NSRunLoopFindModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    if (modeInfo == NULL)
        modeInfo = NSRunLoopCreateModeInfo((NSRunLoopModeInfo **)&_modes,
                                           mode);
    if (_timers == NULL)
        _timers = NSRunLoopCreatePortVector(2);
    NSRunLoopInsertTimer((NSRunLoopPortVector **)&_timers,
                         timer, mode, YES);

    fireTime = [[timer fireDate] timeIntervalSinceReferenceDate];
    if (!modeInfo->flag16 || fireTime < modeInfo->nextFireTime) {
        modeInfo->nextFireTime = fireTime;
        modeInfo->flag16 = 1;
    }
}

- (BOOL)containsTimer:(NSTimer *)timer forMode:(NSString *)mode {
    NSRunLoopModeInfo *modeInfo;
    NSRunLoopPortVector *timers = (NSRunLoopPortVector *)_timers;
    BOOL defaultMode;
    unsigned index;

    if (timers == NULL)
        return NO;
    modeInfo = NSRunLoopFindModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    if (modeInfo == NULL)
        return NO;
    defaultMode = NSRunLoopIsDefaultMode(mode);
    for (index = timers->count / 2; index != 0; ) {
        id modes;

        index--;
        if (NSRunLoopTimerAt(timers, index) != timer)
            continue;
        modes = NSRunLoopTimerModesAt(timers, index);
        if (modes == nil) {
            if (defaultMode)
                return YES;
        } else if ([modes isKindOfClass:[NSString class]]) {
            if (defaultMode || [modes isEqualToString:mode])
                return YES;
        } else if ([modes containsObject:mode]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray *)timersForMode:(NSString *)mode {
    NSRunLoopModeInfo *modeInfo;
    NSRunLoopPortVector *timers = (NSRunLoopPortVector *)_timers;
    NSMutableArray *result;
    BOOL defaultMode;
    unsigned index;

    if (timers == NULL)
        return __NSEmptyArray;
    modeInfo = NSRunLoopFindModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    if (modeInfo == NULL)
        return __NSEmptyArray;
    defaultMode = NSRunLoopIsDefaultMode(mode);
    result = [NSMutableArray array];
    for (index = timers->count / 2; index != 0; ) {
        id modes;

        index--;
        modes = NSRunLoopTimerModesAt(timers, index);
        if (modes == nil) {
            if (defaultMode)
                [result addObject:NSRunLoopTimerAt(timers, index)];
        } else if ([modes isKindOfClass:[NSString class]]) {
            if (defaultMode || [modes isEqualToString:mode])
                [result addObject:NSRunLoopTimerAt(timers, index)];
        } else if ([modes containsObject:mode]) {
            [result addObject:NSRunLoopTimerAt(timers, index)];
        }
    }
    return result;
}

- (void)removeTimersWithTarget:(id)target selector:(SEL)selector
                    withObject:(id)object {
    NSRunLoopPortVector *timers;
    unsigned index;

    for (index = 0; ; ) {
        NSTimer *timer;

        timers = (NSRunLoopPortVector *)_timers;
        if (timers == NULL || index >= timers->count)
            break;
        timer = NSRunLoopTimerAt(timers, index / 2);

        if ([timer _isEqualTimerWithTarget:target selector:selector
                                withObject:object]) {
            [timer retain];
            NSRunLoopRemoveTimerAt(timers, index / 2);
            [timer invalidate];
            [timer release];
        } else {
            index += 2;
        }
    }
}

- (void)_invalidateTimers {
    NSRunLoopPortVector *timers = (NSRunLoopPortVector *)_timers;
    unsigned index;

    if (_timers != NULL) {
        for (index = 0; ; index += 2) {
            timers = (NSRunLoopPortVector *)_timers;
            if (index >= timers->count)
                break;
            [NSRunLoopTimerAt(timers, index / 2) invalidate];
        }
        timers = (NSRunLoopPortVector *)_timers;
        if (--timers->references == 0) {
            while (timers->count != 0)
                [timers->objects[--timers->count] release];
            NSZoneFree(NULL, timers);
        }
        _timers = NULL;
    }
}

- (void)removeTimer:(NSTimer *)timer forMode:(NSString *)mode {
    NSRunLoopModeInfo *modeInfo;
    NSRunLoopPortVector *timers = (NSRunLoopPortVector *)_timers;
    BOOL defaultMode;
    int index;

    if (timers == NULL)
        return;
    modeInfo = NSRunLoopFindModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    if (modeInfo == NULL)
        return;
    defaultMode = NSRunLoopIsDefaultMode(mode);
    index = NSRunLoopFindTimer(timers, timer);
    if (index >= 0) {
        id modes = NSRunLoopTimerModesAt(timers, (unsigned)index);

        if (modes != nil) {
            if ([modes isKindOfClass:[NSString class]]) {
                if (defaultMode) {
                    NSRunLoopSetTimerModesAt(
                        timers, (unsigned)index,
                        [NSMutableArray arrayWithObject:modes]);
                } else if ([modes isEqualToString:mode]) {
                    NSRunLoopSetTimerModesAt(timers, (unsigned)index, nil);
                }
            } else {
                [(NSMutableArray *)modes removeObject:mode];
            }
        } else if (defaultMode) {
            NSRunLoopRemoveTimerAt(timers, (unsigned)index);
        }
    }

    if (timers->count == 0) {
        modeInfo->flag16 = 0;
    }

    {
        NSTimer *firstTimer = NSRunLoopTimerAt(timers, 0);
        NSTimeInterval fireTime =
            [[firstTimer fireDate] timeIntervalSinceReferenceDate];

        if (!modeInfo->flag16 || fireTime < modeInfo->nextFireTime) {
            modeInfo->nextFireTime = fireTime;
            modeInfo->flag16 = 1;
        }
    }
}

- (void)addPort:(NSPort *)aPort forMode:(NSString *)mode {
    NSRunLoopModeInfo *modeInfo =
        NSRunLoopFindModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    NSRunLoopPortVector *ports;

    if (modeInfo == NULL)
        modeInfo = NSRunLoopCreateModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    if (ModePortsGate != nil)
        [ModePortsGate lock];

    ports = modeInfo->portSet->ports;
    if (NSRunLoopFindObject(ports, aPort) < 0) {
        NSRunLoopReleaseVector((NSRunLoopPortVector *)modeInfo->delegates);
        modeInfo->delegates = NULL;

        if (_NSRunLoopAllPortsLock != nil)
            [_NSRunLoopAllPortsLock lock];
        NSRunLoopEnsureAllPorts();
        NSRunLoopEnsureMachNotifyPort();
        NSRunLoopAddPortToGlobalSet(aPort);
        if (_NSRunLoopAllPortsLock != nil)
            [_NSRunLoopAllPortsLock unlock];
    }

    ports = NSRunLoopAppendObject(ports, aPort);
    modeInfo->portSet->ports = ports;

    if (ModePortsGate != nil)
        [ModePortsGate unlock];
}

- (void)removePort:(NSPort *)aPort forMode:(NSString *)mode {
    NSRunLoopModeInfo *modeInfo =
        NSRunLoopFindModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    NSRunLoopPortVector *ports;
    NSRunLoopPortVector *globalPorts;
    int index;

    if (modeInfo == NULL || modeInfo->portSet == NULL)
        return;
    ports = modeInfo->portSet->ports;
    index = NSRunLoopFindLastObject(ports, aPort);
    if (index < 0)
        return;

    if (ModePortsGate != nil)
        [ModePortsGate lock];
    ports = modeInfo->portSet->ports;
    if (NSRunLoopCountObject(ports, aPort) != 0) {
        index = NSRunLoopFindLastObject(ports, aPort);
        if (index >= 0)
            NSRunLoopRemoveObjectAtIndex(ports, (unsigned)index);
    }

    if (NSRunLoopFindObject(ports, aPort) < 0) {
        if (_NSRunLoopAllPortsLock != nil)
            [_NSRunLoopAllPortsLock lock];
        if (_NSRunLoopAllPorts != NULL) {
            globalPorts = _NSRunLoopAllPorts->ports;
            index = NSRunLoopFindLastObject(globalPorts, aPort);
            if (index >= 0) {
                if (NSRunLoopCountObject(globalPorts, aPort) == 1)
                    port_set_remove(task_self_, (mach_port_t)[aPort machPort]);
                NSRunLoopRemoveObjectAtIndex(globalPorts, (unsigned)index);
            }
        }
        if (_NSRunLoopAllPortsLock != nil)
            [_NSRunLoopAllPortsLock unlock];

        NSRunLoopReleaseVector((NSRunLoopPortVector *)modeInfo->delegates);
        modeInfo->delegates = NULL;
    }

    if (ModePortsGate != nil)
        [ModePortsGate unlock];
}

- (void)dealloc {
    [_condition release];
    NSRunLoopReleaseModeInfo((NSRunLoopModeInfo **)&_modes);
    [_callout release];
    NSRunLoopReleaseVector((NSRunLoopPortVector *)_callouts);
    NSRunLoopReleaseVector((NSRunLoopPortVector *)_timers);
    [super dealloc];
}

- (NSDate *)limitDateForMode:(NSString *)mode {
    NSRunLoopModeInfo *modeInfo =
        NSRunLoopFindModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    NSRunLoopPortVector *ports;
    NSRunLoopPortVector * volatile delegates = NULL;
    NSTimeInterval nextTime = 0;
    NSTimeInterval earliestTime = 0;
    NSString *savedMode = _currentMode;
    NSDate *distantFuture = __NSDistantFutureDate;
    BOOL hasTimer;
    BOOL hasEarliest = NO;
#if defined(__ppc__) || defined(__POWERPC__)
    volatile BOOL retainedDelegates = NO;
#endif
    unsigned uniquePortCount = 0;
    unsigned index;

    _currentMode = [mode copyWithZone:NULL];
    NS_DURING
    if (_performers != NULL)
        [self _doPerformersForMode:mode reclaim:(savedMode == nil)];
    if (_callout != nil || _callouts != NULL)
        NSRunLoopInformMonitors(self, _currentMode, 4, savedMode == nil,
                                &_callout, &_callouts);

    if (modeInfo == NULL) {
        [_currentMode release];
        _currentMode = savedMode;
        NS_VALUERETURN(nil, NSDate *);
    }

    hasTimer = NO;
    if (_timers != NULL && ((NSRunLoopPortVector *)_timers)->count != 0) {
        hasTimer = [self _nextTimerInterval:&nextTime forMode:mode
                                   modeInfo:modeInfo];
        if (hasTimer) {
            earliestTime = nextTime;
            hasEarliest = YES;
        }
    } else {
        modeInfo->flag16 = 0;
    }

    ports = modeInfo->portSet->ports;
    for (index = 0; index < ports->count; index++) {
        unsigned previous;

        for (previous = 0; previous < index; previous++) {
            if (ports->objects[previous] == ports->objects[index])
                break;
        }
        if (previous == index)
            uniquePortCount++;
    }
    if (!hasTimer && uniquePortCount == 0) {
        [_currentMode release];
        _currentMode = savedMode;
        NS_VALUERETURN(nil, NSDate *);
    }

    if (modeInfo->delegates == NULL) {
        unsigned capacity = ports->count < 2 ? 2 : ports->count;

        if (ModePortsGate != NULL)
            [ModePortsGate lock];
        delegates = NSRunLoopCreatePortVector(capacity);
        for (index = ports->count; index != 0; ) {
            id delegate;
            unsigned previous;

            index--;
            delegate = [(NSPort *)ports->objects[index] delegate];
            if (delegate == nil
                || ![delegate respondsToSelector:@selector(limitDateForMode:)])
                continue;
            for (previous = 0; previous < delegates->count; previous++) {
                if (delegates->objects[previous] == delegate)
                    break;
            }
            if (previous == delegates->count)
                delegates = NSRunLoopAppendObject(delegates, delegate);
        }
        modeInfo->delegates = delegates;
        if (ModePortsGate != NULL)
            [ModePortsGate unlock];
    }

    delegates = (NSRunLoopPortVector *)modeInfo->delegates;
    if (delegates != NULL) {
        delegates->references++;
#if defined(__ppc__) || defined(__POWERPC__)
        retainedDelegates = YES;
#endif
        for (index = 0; index < delegates->count; index++) {
            NSDate *delegateDate =
                [(id)delegates->objects[index] limitDateForMode:mode];

            if (delegateDate != distantFuture) {
                NSTimeInterval delegateTime =
                    [delegateDate timeIntervalSinceReferenceDate];

                if (!hasEarliest || delegateTime < earliestTime) {
                    earliestTime = delegateTime;
                    hasEarliest = YES;
                }
            }
        }
        NSRunLoopReleaseVector(delegates);
#if defined(__ppc__) || defined(__POWERPC__)
        retainedDelegates = NO;
#endif
    }

    [_currentMode release];
    _currentMode = savedMode;
    NS_HANDLER
#if defined(__ppc__) || defined(__POWERPC__)
        if (retainedDelegates)
            NSRunLoopReleaseVector(delegates);
#endif
        [_currentMode release];
        _currentMode = savedMode;
        [localException raise];
    NS_ENDHANDLER
    if (!hasEarliest)
        return distantFuture;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:earliestTime];
}

- (NSRunLoopInputBuffer *)acceptInputForModeInfo:(NSRunLoopModeInfo *)modeInfo
                                        beforeTime:(NSTimeInterval)beforeTime {
    NSRunLoopInputBuffer *buffer;

    if (WorkerThread != NULL) {
        self->_currentSet = modeInfo->portSet;
        if (self->_msg == NULL) {
            do {
                NSDate *limit = [NSDate dateWithTimeIntervalSinceReferenceDate:
                    beforeTime];
                if (![self->_condition waitUntilDate:limit])
                    break;
            } while (self->_msg == NULL);
        }
        self->_currentSet = NULL;
        buffer = self->_msg == (char *)-1
            ? NULL : (NSRunLoopInputBuffer *)self->_msg;
        self->_msg = NULL;
        return buffer;
    }

    for (;;) {
        NSRunLoopInputBuffer *allocated;
        NSPort *port;
        BOOL accepted = NO;
        unsigned index;

        allocated = NSRunLoopAllocateBuffer();
        buffer = NSCheapPortSetAcceptInput(
            _NSRunLoopAllPorts, allocated,
            beforeTime - (NSTimeInterval)_NSCurrentTime());
        if (buffer == NULL) {
            NSRunLoopDeallocateBuffer(allocated);
            return NULL;
        }
        port = buffer->port;
        if (ModePortsGate != nil)
            [ModePortsGate lock];
        if (modeInfo->portSet->ports != NULL) {
            for (index = 0; index < modeInfo->portSet->ports->count; index++) {
                if (modeInfo->portSet->ports->objects[index] == port) {
                    accepted = YES;
                    break;
                }
            }
        }
        if (ModePortsGate != nil)
            [ModePortsGate unlock];
        if (accepted || (port == _NSMachNotifyPort && self == _NSNotifyRunLoop))
            return buffer;

        NSRunLoopEnqueueMessage(buffer);
        if (_NSRunLoopAllPorts != NULL)
            port_set_remove(task_self_, (mach_port_t)[port machPort]);
    }
}

- (void)acceptInputForMode:(NSString *)mode beforeDate:(NSDate *)limitDate {
    NSRunLoopModeInfo *modeInfo;
    NSRunLoopInputBuffer *buffer = NULL;
    NSString *savedMode = _currentMode;
    NSTimeInterval beforeTime = 4294967295.0;
    BOOL unlimited = limitDate == __NSDistantFutureDate;
    BOOL reclaim = savedMode == nil;

    modeInfo = NSRunLoopFindModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    if (modeInfo == NULL)
        modeInfo = NSRunLoopCreateModeInfo((NSRunLoopModeInfo **)&_modes, mode);
    _currentMode = [mode copyWithZone:NULL];
    if (!unlimited)
        beforeTime = [limitDate timeIntervalSinceReferenceDate];
    if (modeInfo->flag16
        && (unlimited || modeInfo->nextFireTime < beforeTime)) {
        beforeTime = modeInfo->nextFireTime;
        unlimited = NO;
    }

    if (WorkerThread != NULL) {
        if (_NSRunLoopLock != nil)
            [_NSRunLoopLock lock];
        buffer = NSRunLoopDequeueMessage(modeInfo, self);
        if (buffer != NULL) {
            if (_NSRunLoopLock != nil)
                [_NSRunLoopLock unlock];
        } else {
            [_condition lock];
            if (_NSRunLoopLock != nil)
                [_NSRunLoopLock unlock];
            if (_callouts != NULL
                || (_callout != nil && [(id)_callout _mightPostIdle])) {
                if (unlimited
                    || (NSTimeInterval)_NSCurrentTime() < beforeTime) {
                    [_condition unlock];
                    if (NSRunLoopInformMonitors(self, _currentMode, 3,
                                                reclaim, &_callout,
                                                &_callouts))
                        goto done;
                    if (_NSRunLoopLock != nil)
                        [_NSRunLoopLock lock];
                    buffer = NSRunLoopDequeueMessage(modeInfo, self);
                    [_condition lock];
                    if (_NSRunLoopLock != nil)
                        [_NSRunLoopLock unlock];
                    if (buffer == NULL)
                        buffer = [self acceptInputForModeInfo:modeInfo
                                                   beforeTime:beforeTime];
                }
                [_condition unlock];
            } else {
                buffer = [self acceptInputForModeInfo:modeInfo
                                           beforeTime:beforeTime];
                [_condition unlock];
            }
        }
    } else {
        buffer = NSRunLoopDequeueMessage(modeInfo, self);
        if (buffer == NULL) {
            if (_callouts != NULL
                || (_callout != nil && [(id)_callout _mightPostIdle])) {
                buffer = [self acceptInputForModeInfo:modeInfo
                                           beforeTime:-2147483648.0];
                if (buffer == NULL
                    && !unlimited
                    && (NSTimeInterval)_NSCurrentTime() >= beforeTime)
                    goto done;
                if (buffer == NULL
                    && NSRunLoopInformMonitors(self, _currentMode, 3,
                                               reclaim, &_callout,
                                               &_callouts))
                    goto done;
            }
            if (buffer == NULL)
                buffer = [self acceptInputForModeInfo:modeInfo
                                           beforeTime:beforeTime];
        }
    }

    if (buffer != NULL) {
        id delegate;
        NSPortMessage * volatile message = nil;

        NS_DURING
            delegate = [buffer->port delegate];

            if ([delegate respondsToSelector:@selector(handleMachMessage:)]) {
                [delegate handleMachMessage:&buffer->message.header];
            } else if ([delegate respondsToSelector:
                           @selector(handlePortMessage:)]) {
                message = [[NSPortMessage allocWithZone:NULL]
                    initWithMachMessage:&buffer->message.header];
                [delegate handlePortMessage:message];
                [message release];
            }
            NSRunLoopInformMonitors(self, _currentMode, 1, reclaim,
                                    &_callout, &_callouts);
        NS_HANDLER
#if defined(__ppc__) || defined(__POWERPC__)
            [message release];
#endif
            NSRunLoopDeallocateBuffer(buffer);
            [_currentMode release];
            _currentMode = savedMode;
            [localException raise];
        NS_ENDHANDLER
        NSRunLoopDeallocateBuffer(buffer);
    }

done:
    [_currentMode release];
    _currentMode = savedMode;
}

- (BOOL)runBeforeDate:(NSDate *)limitDate {
    return [self runMode:NSDefaultRunLoopMode beforeDate:limitDate];
}

- (void)run {
    while ([self runMode:NSDefaultRunLoopMode
              beforeDate:__NSDistantFutureDate])
        ;
}

- (void)runUntilDate:(NSDate *)limitDate {
    [limitDate retain];
    while ([self runMode:NSDefaultRunLoopMode beforeDate:limitDate]) {
        if (!([limitDate timeIntervalSinceReferenceDate] > _NSCurrentTime()))
            break;
    }
    [limitDate release];
}

- (BOOL)runMode:(NSString *)mode untilDate:(NSDate *)limitDate {
    BOOL didRun = NO;

    [limitDate retain];
    while ([self runMode:mode beforeDate:limitDate]) {
        didRun = YES;
        if (!([limitDate timeIntervalSinceReferenceDate] > _NSCurrentTime()))
            break;
    }
    [limitDate release];
    return didRun;
}

- (BOOL)runMode:(NSString *)mode beforeDate:(NSDate *)limitDate {
	unsigned pool = NSPushAutoreleasePool();
    NSDate *modeLimitDate = [self limitDateForMode:mode];

    if (modeLimitDate != nil) {
        NSDate *inputLimitDate = modeLimitDate;

        if ([modeLimitDate timeIntervalSinceReferenceDate]
            > [limitDate timeIntervalSinceReferenceDate])
            inputLimitDate = limitDate;
        [self acceptInputForMode:mode beforeDate:inputLimitDate];
        NSPopAutoreleasePool(pool);
        return YES;
    }

    NSPopAutoreleasePool(pool);
    return NO;
}

- (void)configureAsServer {
}

@end

@implementation NSObject (NSDelayedPerforming)

- (void)performSelector:(SEL)aSelector withObject:(id)anArgument afterDelay:(NSTimeInterval)delay inModes:(NSArray *)modes {
    [NSTimer scheduleTimerWithTimeInterval:delay target:self selector:aSelector
                                withObject:anArgument inModes:modes];
}

- (void)performSelector:(SEL)aSelector withObject:(id)anArgument afterDelay:(NSTimeInterval)delay {
    [NSTimer scheduleTimerWithTimeInterval:delay target:self selector:aSelector
                                withObject:anArgument];
}

- (void)performSelector:(SEL)aSelector object:(id)anArgument afterDelay:(NSTimeInterval)delay {
    [self performSelector:aSelector withObject:anArgument afterDelay:delay];
}

+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget selector:(SEL)aSelector object:(id)anArgument {
    [[NSRunLoop currentRunLoop]
        removeTimersWithTarget:aTarget selector:aSelector withObject:anArgument];
}

@end

@implementation NSRunLoop (NSPerformTimerStuff)

- (void)performSelector:(SEL)aSelector target:(id)target argument:(id)arg order:(unsigned)order modes:(NSArray *)modes {
    NSRunLoopPerformer *performer = (NSRunLoopPerformer *)
        [NSPerformTimer newPerformSelector:aSelector target:target
                                  argument:arg order:order modes:modes];
    NSRunLoopPerformer *current = (NSRunLoopPerformer *)_performers;

    if (current == NULL || performer->order <= current->order) {
        performer->next = current;
        _performers = performer;
        return;
    }
    while (current->next != NULL && performer->order > current->next->order)
        current = current->next;
    performer->next = current->next;
    current->next = performer;
}

- (void)cancelPerformSelector:(SEL)aSelector target:(id)target argument:(id)arg {
    NSRunLoopPerformer *performer;

    for (performer = (NSRunLoopPerformer *)_performers;
         performer != NULL; performer = performer->next) {
        if (!performer->firing && !performer->invalid
            && performer->selector == aSelector
            && [performer->target isEqual:target]
            && (([performer->argument isEqual:arg])
                || (performer->argument == nil && arg == nil)))
            [(id)performer invalidate];
    }
}

@end
