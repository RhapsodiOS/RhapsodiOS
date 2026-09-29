#import <Foundation/NSAutoreleasePool.h>
#import <stdio.h>
#import "../NSFramebuffer.h"
#import "test_support.h"

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSFramebuffer *framebuffer;
    NSRect bounds;

    TestCheck(TestLoadSelectedFramework() != 0,
              "loads selected framework for framebuffer checks");
    TestCheck([[NSFramebuffer alloc] initWithScreen:nil] == nil,
              "rejects a missing screen");
    TestCheck([[NSFramebuffer alloc] initWithScreen:nil andMapIfPossible:NO] == nil,
              "rejects a missing screen when mapping is disabled");
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
        TestCheck([framebuffer conversionTable] == 0 &&
                  [framebuffer inverseConversionTable] == 0,
                  "unsupported sample and color-space pair has no conversion table");
        TestCheck([[framebuffer pixelEncoding] length] == 0 &&
                  [[framebuffer driver] length] == 0,
                  "pixel encoding and driver are lazily exposed as strings");
        bounds = [framebuffer screenBounds];
#if defined(__ppc__) || defined(__POWERPC__)
        TestCheck(bounds.origin.x == 1 && bounds.origin.y == 1 &&
                  bounds.size.width == 0 && bounds.size.height == 0,
                  "PPC framebuffer bounds preserve the one-point origin");
#elif defined(__i386__)
        TestCheck(bounds.origin.x == 0 && bounds.origin.y == 0 &&
                  bounds.size.width == 0 && bounds.size.height == 0,
                  "i386 framebuffer bounds use a zero origin");
#endif
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
