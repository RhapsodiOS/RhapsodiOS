#import <Foundation/NSAutoreleasePool.h>
#import <stdio.h>
#import <string.h>
#import "../Private/NSInterceptedRect.h"
#import "../NSShape.h"
#import "test_support.h"

@interface RectTarget : NSObject
{
@public
    int revealCount;
    int willMoveCount;
    int didMoveCount;
    int flushProbeCount;
    int flushCallbackCount;
    int obscureProbeCount;
    int obscureCallbackCount;
    BOOL supportObscureCallback;
}
- (void)areaDidReveal:(id)rect inRect:(NSRect)bounds;
- (void)areaWillMove:(id)rect by:(NSPoint)delta;
- (void)areaDidMove:(id)rect by:(NSPoint)delta;
- (void)areaWillObscure:(id)rect inRect:(NSRect)bounds;
- (NXInterceptorFlushReturn)areaWillFlush:(id)rect
                                      inRect:(NSRect)bounds
                                     theBits:(id)bits;
@end

@implementation RectTarget
- (void)areaDidReveal:(id)rect inRect:(NSRect)bounds
{
    revealCount++;
}
- (void)areaWillMove:(id)rect by:(NSPoint)delta
{
    willMoveCount++;
}
- (void)areaDidMove:(id)rect by:(NSPoint)delta
{
    didMoveCount++;
}
- (BOOL)respondsToSelector:(SEL)selector
{
    if (selector == @selector(areaWillFlush:inRect:theBits:)) {
        flushProbeCount++;
        return YES;
    }
    if (selector == @selector(areaWillObscure:inRect:)) {
        obscureProbeCount++;
        return supportObscureCallback;
    }
    return [super respondsToSelector:selector];
}
- (void)areaWillObscure:(id)rect inRect:(NSRect)bounds
{
    obscureCallbackCount++;
}
- (NXInterceptorFlushReturn)areaWillFlush:(id)rect
                                  inRect:(NSRect)bounds
                                 theBits:(id)bits
{
    flushCallbackCount++;
    return NXInterceptorFlushDone;
}
@end

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSRect input = NSMakeRect(11, 12, 13, 14);
    NSInterceptedRect *rect;
    NSRect output;
    RectTarget *target;
    InterceptorNotification message;
    InterceptorReply reply;

    TestCheck(TestLoadSelectedFramework() != 0,
              "loads selected framework for intercepted rectangle checks");
    rect = [[NSInterceptedRect alloc] initForRect:input inWindow:7
        onFramebuffer:nil forClient:nil];
    TestCheck(rect != nil, "constructs an intercepted rectangle");
    if (rect) {
        output = [rect rectangle];
        TestCheck(output.origin.x == 11 && output.origin.y == 12 &&
                  output.size.width == 13 && output.size.height == 14,
                  "rectangle accessor preserves original geometry");
        TestCheck([rect uniqueID] != 0, "assigns a nonzero unique identifier");
        TestCheck(![rect isLocked], "new rectangle starts unlocked");
        [rect lockRect];
        TestCheck([rect isLocked], "lockRect marks rectangle locked");
        [rect unlockRect];
        TestCheck(![rect isLocked], "unlockRect clears rectangle lock state");
        TestCheck([rect currentScreenRectShape] != nil,
                  "initializes screen rectangle shape");

        target = [[RectTarget alloc] init];
        [rect setTarget:target];
        memset(&message, 0, sizeof(message));
        message.flags = INTERCEPT_TOTALLY_VISIBLE;
        message.sequenceNumber = 19;
        message.type = INTERCEPT_DID_REVEAL;
        message.args[0] = 1;
        message.args[1] = 2;
        message.args[2] = 3;
        message.args[3] = 4;
        [rect _handleMsg:&message withReply:&reply];
        TestCheck(target->revealCount == 1,
                  "dispatches reveal notification to target");
        TestCheck(reply.h.msg_id == INTERCEPT_REPLY_MSGID &&
                  reply.sequenceNumber == 19 && reply.h.msg_size == sizeof(reply),
                  "builds notification reply with matching sequence");

        message.type = INTERCEPT_FLUSH;
        message.args[0] = 21;
        message.args[1] = 22;
        message.args[2] = 23;
        message.args[3] = 24;
        [rect _handleMsg:&message withReply:&reply];
        TestCheck(target->flushProbeCount == 1 &&
                  target->flushCallbackCount == 0 && reply.replyCode == 0,
                  "flush notification probes the target but does not dispatch bits");

        message.type = INTERCEPT_WILL_OBSCURE;
        message.flags = INTERCEPT_TOTALLY_VISIBLE;
        [rect _handleMsg:&message withReply:&reply];
        TestCheck([rect isTotallyVisible],
                  "preserves reported visibility when target has no obscure callback");
        target->supportObscureCallback = YES;
        [rect _handleMsg:&message withReply:&reply];
        TestCheck(target->obscureProbeCount == 2 &&
                  target->obscureCallbackCount == 1 && ![rect isTotallyVisible],
                  "clears visibility after an implemented obscure callback");

        message.type = INTERCEPT_WILL_MOVE;
        message.args[0] = 5;
        message.args[1] = -2;
        [rect _handleMsg:&message withReply:&reply];
        TestCheck(target->willMoveCount == 1 && [rect isLocked],
                  "move-start notification locks rectangle and dispatches");
        message.type = INTERCEPT_DID_MOVE;
        [rect _handleMsg:&message withReply:&reply];
        output = [rect currentScreenRect];
        TestCheck(target->didMoveCount == 1 && ![rect isLocked] &&
                  output.origin.x == 5 && output.origin.y == -2,
                  "move-complete notification offsets screen geometry");
        [target release];
        [rect release];
    }
    [pool release];
    return TestFinish();
}
