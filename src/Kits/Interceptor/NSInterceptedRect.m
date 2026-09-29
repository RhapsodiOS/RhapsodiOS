#import "Private/InterceptorPrivate.h"
#import "NSBitmap.h"
#import "NSShape.h"
#import <Foundation/NSLock.h>
#import <string.h>

@interface NSObject (NSInterceptorRectNotifications)
- (void)areaDidReveal:(id)rect inRect:(NSRect)bounds;
- (void)areaWillObscure:(id)rect inRect:(NSRect)bounds;
- (void)areaIsInvalid:(id)rect;
- (void)areaWillMove:(id)rect by:(NSPoint)delta;
- (void)areaDidMove:(id)rect by:(NSPoint)delta;
- (void)areaWasOrderedIn:(id)rect;
- (void)areaWasOrderedOut:(id)rect;
- (void)areaChangedScreen:(id)rect from:(int)oldScreen to:(int)newScreen;
- (void)areaWindowFreed:(id)rect;
- (int)areaWillChangeBuffering:(id)rect fromType:(int)type;
- (int)areaDidChangeBuffering:(id)rect toType:(int)type;
- (int)screenNumber;
@end

static unsigned int NSInterceptedRectNextUniqueID = 1;

@implementation NSInterceptedRect

+ (void)initialize
{
    if (self == [NSInterceptedRect class])
        NSInterceptedRectNextUniqueID = 1;
}

- initForRect:(NSRect)aRect inWindow:(int)aWindow
    onFramebuffer:(id)aFramebuffer forClient:(NSInterceptorClient *)aClient
{
    int returnedFlags = 0;

    self = [super init];
    if (!self) return nil;

    rect = aRect;
    windowNumber = aWindow;
    screen = aFramebuffer;
    uniqueID = NSInterceptedRectNextUniqueID++;
    target = nil;
    rectLock = [[NSConditionLock alloc] initWithCondition:0];
    tmpBitmap = [[NSSimpleBitmap allocWithZone:[self zone]] init];
    interceptorClient = aClient;
    [aClient _addInterceptedRect:self
        returnedScreenRect:&screenRect returnedFlags:&returnedFlags];
    screenRectShape = [[NSShape allocWithZone:[self zone]]
        initFromRect:screenRect];
    isTotallyVisible = (returnedFlags & INTERCEPT_TOTALLY_VISIBLE) != 0;
    isTotallyObscured = (returnedFlags & INTERCEPT_TOTALLY_OBSCURED) != 0;
    return self;
}

- (void)lockRect
{
    [rectLock lockWhenCondition:0];
    isLocked = YES;
}

- (void)unlockRect
{
    isLocked = NO;
    [rectLock unlockWithCondition:moveInProgress ? 1 : 0];
}

- (BOOL)isLocked { return isLocked || moveInProgress; }
- (void)setTarget:(id)aTarget { target = aTarget; }
- (id)target { return target; }
- (NSRect)currentScreenRect { return screenRect; }
- (NSShape *)currentScreenRectShape { return screenRectShape; }

- (id)currentClipList:(NSRect)aRect count:(int)count
{
    NSLog(@"NSInterceptedRect currentClipList:count: is not implemented");
    return nil;
}

- (id)compositeBits:(id)bits withOp:(int)operation
{
    NSLog(@"NSInterceptedRect compositeBits:withOp: is not implemented");
    return nil;
}

- (void)removeFromWindowServer
{
    [interceptorClient _removeInterceptedRect:self];
}

- (unsigned int)uniqueID { return uniqueID; }
- (int)windowNumber { return windowNumber; }
- (NSRect)rectangle { return rect; }
- (BOOL)isTotallyVisible { return isTotallyVisible; }
- (BOOL)isTotallyObscured { return isTotallyObscured; }
- (unsigned int)_flags { return flags; }
- (id)framebuffer { return screen; }

- (id)_handleMsg:(InterceptorNotification *)message
        withReply:(InterceptorReply *)reply
{
    int callbackResult = 0;
    NSRect bounds;
    NSPoint delta;

    memset(reply, 0, sizeof(*reply));
    [rectLock lock];
    isTotallyVisible = (message->flags & INTERCEPT_TOTALLY_VISIBLE) != 0;
    isTotallyObscured = (message->flags & INTERCEPT_TOTALLY_OBSCURED) != 0;

    bounds = NSMakeRect(message->args[0], message->args[1],
                        message->args[2], message->args[3]);
    delta = NSMakePoint(message->args[0], message->args[1]);

    switch (message->type) {
    case INTERCEPT_DID_REVEAL:
        if ([target respondsToSelector:@selector(areaDidReveal:inRect:)])
            [target areaDidReveal:self inRect:bounds];
        break;
    case INTERCEPT_WILL_OBSCURE:
        if ([target respondsToSelector:@selector(areaWillObscure:inRect:)])
            [target areaWillObscure:self inRect:bounds];
        isTotallyVisible = NO;
        break;
    case INTERCEPT_INVALID:
        if ([target respondsToSelector:@selector(areaIsInvalid:)])
            [target areaIsInvalid:self];
        break;
    case INTERCEPT_WILL_MOVE:
        moveInProgress = YES;
        if ([target respondsToSelector:@selector(areaWillMove:by:)])
            [target areaWillMove:self by:delta];
        break;
    case INTERCEPT_DID_MOVE:
        screenRect.origin.x += delta.x;
        screenRect.origin.y += delta.y;
        [screenRectShape offsetShape:delta];
        if ([target respondsToSelector:@selector(areaDidMove:by:)])
            [target areaDidMove:self by:delta];
        moveInProgress = NO;
        break;
    case INTERCEPT_ORDER_IN:
        if ([target respondsToSelector:@selector(areaWasOrderedIn:)])
            [target areaWasOrderedIn:self];
        break;
    case INTERCEPT_ORDER_OUT:
        if ([target respondsToSelector:@selector(areaWasOrderedOut:)])
            [target areaWasOrderedOut:self];
        break;
    case INTERCEPT_FLUSH:
        /* The reference checks this callback but leaves bit delivery TODO. */
        break;
    case INTERCEPT_NEW_SCREEN:
        if (screen && [screen respondsToSelector:@selector(screenNumber)]) {
            int oldScreen = (int)[screen screenNumber];
            if (oldScreen == message->args[0] &&
                [target respondsToSelector:
                    @selector(areaChangedScreen:from:to:)])
                [target areaChangedScreen:self from:oldScreen
                    to:message->args[1]];
        }
        break;
    case INTERCEPT_WINDOW_FREED:
        if ([target respondsToSelector:@selector(areaWindowFreed:)])
            [target areaWindowFreed:self];
        break;
    case INTERCEPT_WILL_CHANGE_BUFFERING:
        moveInProgress = YES;
        if ([target respondsToSelector:
                @selector(areaWillChangeBuffering:fromType:)])
            callbackResult = [target areaWillChangeBuffering:self
                fromType:message->args[0]];
        break;
    case INTERCEPT_DID_CHANGE_BUFFERING:
        if ([target respondsToSelector:
                @selector(areaDidChangeBuffering:toType:)])
            callbackResult = [target areaDidChangeBuffering:self
                toType:message->args[0]];
        moveInProgress = NO;
        break;
    default:
        break;
    }

    reply->h.msg_simple = 1;
    reply->h.msg_size = sizeof(*reply);
    reply->h.msg_type = 0;
    reply->h.msg_local_port = 0;
    reply->h.msg_remote_port = 0;
    reply->h.msg_id = INTERCEPT_REPLY_MSGID;
    reply->interceptorMsgType.msg_type_name = 2;
    reply->interceptorMsgType.msg_type_size = 32;
    reply->interceptorMsgType.msg_type_number = 1;
    reply->interceptorMsgType.msg_type_inline = 1;
    reply->sequenceNumber = message->sequenceNumber;
    reply->replyType.msg_type_name = 2;
    reply->replyType.msg_type_size = 32;
    reply->replyType.msg_type_number = 1;
    reply->replyType.msg_type_inline = 1;
    reply->replyCode = callbackResult;
    [rectLock unlockWithCondition:moveInProgress ? 1 : 0];
    return self;
}

- (void)dealloc
{
    [interceptorClient _removeInterceptedRect:self];
    [tmpBitmap release];
    [rectLock release];
    [screenRectShape release];
    [super dealloc];
}

@end
