/*  Behavioural tests for NSRange.m, stage 1 of the Foundation reconstruction.
    NSStringFromRange and NSRangeFromString are deferred to stage 3.  */

#import <Foundation/NSRange.h>
#include <stdio.h>

/*  Exported by NSRange.m but declared in no public header; see
    reconstruction/divergences.md.  */
extern BOOL NSIntersectsRange(NSRange range1, NSRange range2);

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

#define CHECK_RANGE(r, loc, len) \
    CHECK((r).location == (unsigned)(loc) && (r).length == (unsigned)(len))

static void test_union_range(void)
{
    CHECK_RANGE(NSUnionRange(NSMakeRange(0, 2), NSMakeRange(5, 3)), 0, 8);
    CHECK_RANGE(NSUnionRange(NSMakeRange(5, 3), NSMakeRange(0, 2)), 0, 8);
    CHECK_RANGE(NSUnionRange(NSMakeRange(0, 10), NSMakeRange(2, 3)), 0, 10);
}

static void test_union_range_with_empty(void)
{
    CHECK_RANGE(NSUnionRange(NSMakeRange(4, 0), NSMakeRange(4, 6)), 4, 6);

    /*  An empty range outside the other still widens the span: the reference
        takes a plain min/max and does not special-case zero length.  */
    CHECK_RANGE(NSUnionRange(NSMakeRange(20, 0), NSMakeRange(4, 6)), 4, 16);
}

static void test_intersection_range(void)
{
    CHECK_RANGE(NSIntersectionRange(NSMakeRange(0, 5), NSMakeRange(3, 5)), 3, 2);
    CHECK_RANGE(NSIntersectionRange(NSMakeRange(3, 5), NSMakeRange(0, 5)), 3, 2);
}

static void test_intersection_range_when_disjoint(void)
{
    NSRange r = NSIntersectionRange(NSMakeRange(0, 2), NSMakeRange(9, 2));
    CHECK(r.length == 0);

    /*  Touching but not overlapping is still empty.  */
    CHECK(NSIntersectionRange(NSMakeRange(0, 3), NSMakeRange(3, 3)).length == 0);
}

static void test_intersection_range_when_nested(void)
{
    CHECK_RANGE(NSIntersectionRange(NSMakeRange(0, 10), NSMakeRange(4, 2)), 4, 2);
}

static void test_intersection_range_zero_length_inside(void)
{
    /*  A zero-length range inside the other keeps its own location rather
        than collapsing to {0, 0}.  Verified against the reference.  */
    CHECK_RANGE(NSIntersectionRange(NSMakeRange(4, 0), NSMakeRange(0, 10)), 4, 0);
}

static void test_intersects_range(void)
{
    CHECK(NSIntersectsRange(NSMakeRange(0, 5), NSMakeRange(3, 5)));
    CHECK(!NSIntersectsRange(NSMakeRange(0, 2), NSMakeRange(9, 2)));
    CHECK(!NSIntersectsRange(NSMakeRange(0, 3), NSMakeRange(3, 3)));
}

int main(void)
{
    test_union_range();
    test_union_range_with_empty();
    test_intersection_range();
    test_intersection_range_when_disjoint();
    test_intersection_range_when_nested();
    test_intersection_range_zero_length_inside();
    test_intersects_range();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
