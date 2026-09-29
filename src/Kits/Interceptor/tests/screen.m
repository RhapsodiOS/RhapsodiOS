#import <Foundation/NSAutoreleasePool.h>
#import "../NSDirectScreen.h"
#import "test_support.h"

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    TestCheck(TestLoadSelectedFramework() != 0,
              "loads selected framework for direct-screen checks");
    TestCheck([[NSDirectScreen alloc] initWithScreen:nil] == nil,
              "rejects a missing screen");

    [pool release];
    return TestFinish();
}
