#import "Private/InterceptorPrivate.h"
#import "Private/InterceptorIPC.h"
#import "NSFramebuffer.h"
#import <Foundation/NSConnection.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMutableDictionary.h>
#import <Foundation/NSPort.h>
#import <mach/mach.h>
#import <mach/mach_error.h>
#import <mach/cthreads.h>
#import <stdio.h>
#import <string.h>

extern NSString *NTWindowServerDeathNotification;
extern port_t _rendezvousPort(void);

static NSLock *NSInterceptorClientThreadLock;
static NSThread *NSInterceptorClientHandlingThread;
static NSMutableDictionary *NSInterceptorClientByPort;
static port_t NSInterceptorClientNotifySet;
static NSLock *NSInterceptorClientHandlerLock;
static NSPort *NSInterceptorClientWindowServerPort;

@implementation NSInterceptorClient

+ (void)initialize
{
    if (self == [NSInterceptorClient class]) {
        NSInterceptorClientThreadLock = [[NSLock alloc] init];
        NSInterceptorClientHandlingThread = nil;
        NSInterceptorClientByPort = [[NSMutableDictionary alloc] init];
        if (port_set_allocate(task_self(), &NSInterceptorClientNotifySet) !=
            KERN_SUCCESS)
            mach_error("NSInterceptorClient port_set_allocate",
                       KERN_FAILURE);
    }
}

- init
{
    self = [super init];
    if (!self) return nil;

    context = InterceptorCreateContext();
    if (!context) {
        [self release];
        return nil;
    }
    handlingThread = nil;
    listLock = [[NSConditionLock alloc] initWithCondition:0];
    portLock = [[NSLock alloc] init];
    interceptedRects = [[NSMutableArray alloc] init];
    return self;
}

- (void)setHandlingThread:(id)aThread
{
    [NSInterceptorClientThreadLock lock];
    if (aThread != NSInterceptorClientHandlingThread)
        handlingThread = aThread;
    [NSInterceptorClientThreadLock unlock];
}

- (id)handlingThread
{
    return handlingThread ? handlingThread : NSInterceptorClientHandlingThread;
}

- (int)interceptorPort
{
    port_t notifyPort = PORT_NULL;
    port_t exceptionPort = PORT_NULL;
    thread_act_t thread;

    [portLock lock];
    if (context->notifyPort == PORT_NULL) {
        if (port_allocate(task_self(), &notifyPort) != KERN_SUCCESS) {
            [portLock unlock];
            return PORT_NULL;
        }
        thread = thread_self();
        if (thread_get_special_port(thread, 3, &exceptionPort) != KERN_SUCCESS ||
            exceptionPort == PORT_NULL)
            (void)task_get_special_port(task_self(), 3, &exceptionPort);

        if (_InterceptorSetNotifyPort(context->contextPort, context->replyPort,
                                      notifyPort, exceptionPort) != 0) {
            port_deallocate(task_self(), notifyPort);
            [portLock unlock];
            return PORT_NULL;
        }
        context->notifyPort = notifyPort;
        _notifyPort = [[NSPort alloc] initWithMachPort:notifyPort];
    }
    notifyPort = context->notifyPort;
    [portLock unlock];
    return notifyPort;
}

- (BOOL)handleInterceptorMessage:(InterceptorNotification *)message
                       withReply:(InterceptorReply *)reply
{
    unsigned int index;
    NSInterceptedRect *rect = nil;

    if (message->h.msg_id != INTERCEPT_NOTIFY_MSGID) {
        NSLog(@"NSInterceptorClient received unexpected message id %d",
              message->h.msg_id);
        return NO;
    }

    [listLock lock];
    for (index = 0; index < [interceptedRects count]; index++) {
        rect = [interceptedRects objectAtIndex:index];
        if ([rect uniqueID] == (unsigned int)message->uniqueID)
            break;
        rect = nil;
    }
    [listLock unlock];

    if (!rect) {
        NSLog(@"NSInterceptorClient received notification for unknown rectangle %d",
              message->uniqueID);
        return NO;
    }
    [rect _handleMsg:message withReply:reply];
    return YES;
}

- (id)_addInterceptedRect:(NSInterceptedRect *)rect
       returnedScreenRect:(NSRect *)returnedScreenRect
            returnedFlags:(int *)returnedFlags
{
    NSRect bounds;
    NSFramebuffer *framebuffer;
    InterceptedRectangle request;
    int result;

    [listLock lock];
    [interceptedRects addObject:rect];
    [listLock unlock];

    bounds = [rect rectangle];
    framebuffer = [rect framebuffer];
    request.x = (int)bounds.origin.x;
    request.y = (int)bounds.origin.y;
    request.w = (int)bounds.size.width;
    request.h = (int)bounds.size.height;
    request.idNum = (int)[rect uniqueID];
    request.wnum = [rect windowNumber];
    request.snum = [framebuffer screenNumber];
    request.flags = (int)[rect _flags];

    result = _InterceptorAddRect(context->contextPort, context->replyPort,
                                 &request);
    if (result != 0) {
        [listLock lock];
        [interceptedRects removeObject:rect];
        [listLock unlock];
        NSLog(@"NSInterceptorClient failed to add intercepted rectangle (%d)",
              result);
        return nil;
    }

    returnedScreenRect->origin.x = (float)request.x;
    returnedScreenRect->origin.y = (float)request.y;
    returnedScreenRect->size.width = (float)request.w;
    returnedScreenRect->size.height = (float)request.h;
    *returnedFlags = request.flags;
    return self;
}

- (void)_removeInterceptedRect:(NSInterceptedRect *)rect
{
    int result = _InterceptorRemoveRect(context->contextPort, context->replyPort,
                                        [rect uniqueID]);
    if (result != 0) {
        NSLog(@"NSInterceptorClient failed to remove intercepted rectangle (%d)",
              result);
        return;
    }
    [listLock lock];
    [interceptedRects removeObject:rect];
    [listLock unlock];
}

- (InterceptorClientContext *)_context
{
    return context;
}

- (void)windowServerPortDeath:(NSNotification *)notification
{
    (void)notification;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NTWindowServerDeathNotification object:self];
}

- (void)startHandlingThread
{
    port_t notifyPort = (port_t)[self interceptorPort];
    kern_return_t result;

    if (notifyPort == PORT_NULL) return;
    [_notifyPort setDelegate:self];
    [NSInterceptorClientThreadLock lock];
    [NSInterceptorClientByPort setObject:self forKey:_notifyPort];
    result = port_set_add(task_self(), NSInterceptorClientNotifySet,
                          notifyPort);
    if (result != KERN_SUCCESS)
        mach_error("NSInterceptorClient port_set_add", result);

    if (NSInterceptorClientHandlingThread == nil) {
        objc_setMultithreaded(YES);
        NSInterceptorClientHandlerLock = [[NSLock alloc] init];
        [NSInterceptorClientHandlerLock lock];
        [NSThread detachNewThreadSelector:@selector(_notifyHandler)
                                   toTarget:self withObject:nil];
        [NSInterceptorClientHandlerLock lock];
        [NSInterceptorClientHandlerLock unlock];
        [NSInterceptorClientHandlerLock release];
        NSInterceptorClientHandlerLock = nil;
    }
    [NSInterceptorClientThreadLock unlock];
}

- (void)_notifyHandler
{
    InterceptorNotification message;
    InterceptorReply reply;
    mach_error_t error;
    NSPort *messagePort;
    NSInterceptorClient *client;

    NSRemapMegaPixelDisplayForCurrentThread();
    cthread_set_name(cthread_self(), "Interceptor Notifier");
    NSInterceptorClientHandlingThread = [NSThread currentThread];
    [NSInterceptorClientHandlerLock unlock];
    [self setHandlingThread:[NSThread currentThread]];

    if (NSInterceptorClientWindowServerPort == nil) {
        NSInterceptorClientWindowServerPort =
            [[NSPort portWithMachPort:_rendezvousPort()] retain];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(windowServerPortDeath:)
            name:NSPortDidBecomeInvalidNotification
            object:NSInterceptorClientWindowServerPort];
    }

    while (1) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        memset(&message, 0, sizeof(message));
        message.h.msg_size = sizeof(message);
        message.h.msg_local_port = NSInterceptorClientNotifySet;
        error = msg_receive(&message.h, 0, 0);
        if (error != KERN_SUCCESS) {
            NSLog(@"NSInterceptorClient notification receive failed: %s",
                  mach_error_string(error));
            [pool release];
            [NSInterceptorClientThreadLock lock];
            NSInterceptorClientHandlingThread = nil;
            [NSInterceptorClientThreadLock unlock];
            [NSThread exit];
        }

        [NSInterceptorClientThreadLock lock];
        messagePort = [NSPort portWithMachPort:message.h.msg_local_port];
        client = [NSInterceptorClientByPort objectForKey:messagePort];
        if (client != nil &&
            [client handleInterceptorMessage:&message withReply:&reply]) {
            [NSInterceptorClientThreadLock unlock];
            if (message.h.msg_remote_port != PORT_NULL) {
                reply.h.msg_remote_port = message.h.msg_remote_port;
                error = msg_send(&reply.h, 32, 0);
                if (error != KERN_SUCCESS)
                    NSLog(@"NSInterceptorClient notification reply failed: %s",
                          mach_error_string(error));
            }
        } else {
            [NSInterceptorClientThreadLock unlock];
        }
        [pool release];
    }
}

- (void)dealloc
{
    [portLock lock];
    if (context && context->notifyPort != PORT_NULL) {
        [NSInterceptorClientThreadLock lock];
        port_set_remove(task_self(), NSInterceptorClientNotifySet,
                        context->notifyPort);
        [NSInterceptorClientByPort removeObjectForKey:_notifyPort];
        [NSInterceptorClientThreadLock unlock];
        [_notifyPort release];
        port_deallocate(task_self(), context->notifyPort);
        context->notifyPort = PORT_NULL;
    }
    [portLock unlock];

    [listLock lock];
    [interceptedRects removeAllObjects];
    [listLock unlock];
    [interceptedRects release];
    interceptedRects = nil;
    [listLock release];
    listLock = nil;
    [portLock release];
    portLock = nil;
    InterceptorDestroyContext(context);
    context = nil;
    [super dealloc];
}

@end
