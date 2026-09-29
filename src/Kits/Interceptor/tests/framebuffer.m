#import <Foundation/NSAutoreleasePool.h>
#import <stdio.h>
#import "../NSFramebuffer.h"
#import "test_support.h"

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSFramebuffer *framebuffer;

    TestCheck(TestLoadSelectedFramework() != 0,
              "loads selected framework for framebuffer checks");
    framebuffer = [NSFramebuffer alloc];
    TestCheck(framebuffer != nil, "allocates framebuffer instance");
    if (framebuffer) {
        TestCheck(![framebuffer isMappable], "new framebuffer is unmapped");
        TestCheck([framebuffer screenNumber] == 0 &&
                  [framebuffer deviceUnit] == 0 &&
                  [framebuffer deviceSlot] == 0,
                  "new framebuffer begins with zero device identifiers");
        TestCheck([framebuffer addressForPoint:NSMakePoint(2, 3)] == 0,
                  "unmapped framebuffer has no pixel address");
        TestCheck([[framebuffer pixelEncoding] length] == 0 &&
                  [[framebuffer driver] length] == 0,
                  "pixel encoding and driver are lazily exposed as strings");
        TestCheck([framebuffer canLockWithMode:NSFramebufferReadWrite] &&
                  [framebuffer canLockWithMode:NSFramebufferWriteOnly] &&
                  [framebuffer canLockWithMode:NSFramebufferReadOnly],
                  "all framebuffer access modes can lock");
        [framebuffer lockWithMode:NSFramebufferReadWrite];
        [framebuffer unlock];
        TestCheck([framebuffer retain] == framebuffer &&
                  [framebuffer retainCount] == (unsigned int)-1,
                  "cached framebuffer uses immortal retain semantics");
        [framebuffer release];
        TestCheck([framebuffer screenNumber] == 0,
                  "release leaves cached framebuffer alive");
    }

    [pool release];
    return TestFinish();
}
