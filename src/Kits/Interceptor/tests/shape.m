#import <Foundation/NSAutoreleasePool.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <dlfcn.h>
#import "../NSShape.h"
#import "test_support.h"

static int ExpectRect(id<NSShapeEnumerator> e, float x, float y, float w, float h)
{
    NSRect *rect = [e nextRect];
    if (!TestCheck(rect != 0, "shape enumerator returns expected rectangle")) return 0;
    TestCheck(rect->origin.x == x && rect->origin.y == y &&
              rect->size.width == w && rect->size.height == h,
              "enumerated rectangle coordinates");
    return 1;
}

static void ExpectEnd(id<NSShapeEnumerator> e)
{
    TestCheck([e nextRect] == 0, "shape enumerator reaches end");
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSShape *empty;
    NSShape *a;
    NSShape *b;
    NSShape *copy;
    id<NSShapeEnumerator> e;

    TestCheck(TestLoadSelectedFramework() != 0, "loads selected framework for shape checks");

    empty = [[NSShape alloc] init];
    TestCheck([empty isEmpty], "new shape is empty");
    e = [empty rectEnumerator];
    ExpectEnd(e);

    a = [[NSShape alloc] initFromRect:NSMakeRect(0, 0, 4, 4)];
    e = [a rectEnumerator];
    ExpectRect(e, 0, 0, 4, 4);
    ExpectEnd(e);

    b = [[NSShape alloc] initFromRect:NSMakeRect(4, 0, 4, 4)];
    [a unionWithShape:b];
    e = [a rectEnumerator];
    ExpectRect(e, 0, 0, 8, 4);
    ExpectEnd(e);
    [a unionWithShape:a];
    TestCheck([a isEqual:a] && ![a isEmpty], "self union preserves the shape");

    [a release];
    [b release];
    a = [[NSShape alloc] initFromRect:NSMakeRect(0, 0, 4, 4)];
    b = [[NSShape alloc] initFromRect:NSMakeRect(2, 2, 4, 4)];
    [a intersectWithShape:b];
    e = [a rectEnumerator];
    ExpectRect(e, 2, 2, 2, 2);
    ExpectEnd(e);
    [a release];
    [b release];

    a = [[NSShape alloc] initFromRect:NSMakeRect(0, 0, 6, 6)];
    b = [[NSShape alloc] initFromRect:NSMakeRect(2, 2, 2, 2)];
    [a differenceWithShape:b];
    e = [a rectEnumerator];
    ExpectRect(e, 0, 0, 6, 2);
    ExpectRect(e, 0, 2, 2, 2);
    ExpectRect(e, 4, 2, 2, 2);
    ExpectRect(e, 0, 4, 6, 2);
    ExpectEnd(e);
    copy = [a copy];
    TestCheck([copy isEqual:a], "copy preserves exact region representation");
    [copy offsetShape:NSMakePoint(1, -1)];
    TestCheck(![copy isEqual:a], "copied shape has independent storage");
    e = [copy rectEnumerator];
    ExpectRect(e, 1, -1, 6, 2);
    ExpectRect(e, 1, 1, 2, 2);
    ExpectRect(e, 5, 1, 2, 2);
    ExpectRect(e, 1, 3, 6, 2);
    ExpectEnd(e);
    [copy release];
    [a release];
    [b release];

    a = [[NSShape alloc] initFromRect:NSMakeRect(10, 10, -4, -6)];
    e = [a rectEnumerator];
    ExpectRect(e, 6, 4, 4, 6);
    ExpectEnd(e);
    [a release];

    a = [[NSShape alloc] initFromRect:NSMakeRect(-3, -2, 0, 8)];
    TestCheck([a isEmpty], "zero-width rectangle produces empty shape");
    [a release];
    [empty release];
    [pool release];
    return TestFinish();
}
