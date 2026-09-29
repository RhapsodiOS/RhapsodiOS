/*  A minimal concrete NSCoder for this stage's own tests: an in-memory
    array of {type, bytes} entries, written and read back in order.
    Shared between test_coder.m and test_invocation.m.  */

#import <Foundation/NSCoder.h>

#define TestCoderCapacity 64

typedef struct {
    char type[16];
    char bytes[64];
    unsigned length;
} TestCoderEntry;

@interface TestCoder : NSCoder
{
    TestCoderEntry entries[TestCoderCapacity];
    unsigned writeIndex;
    unsigned readIndex;
    NSZone *zone;
}
@end
