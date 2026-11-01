/*  Behavioural tests for NSGeometry.m, stage 1 of the Foundation
    reconstruction. Covers the 14 functions that do not touch NSString;
    the six string converters are deferred to stage 3, and the
    NSGeometryCoding category to stage 2.  */

#import <Foundation/NSGeometry.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

/*  Parameter names avoid x/y/w/h: the preprocessor would otherwise
    substitute those into the .x/.y/.width/.height field accesses
    below too (they're separate tokens after the '.', with no
    special-casing for member-access position), breaking the macro.  */
#define CHECK_RECT(r, ex, ey, ew, eh) \
    CHECK((r).origin.x == (ex) && (r).origin.y == (ey) && \
          (r).size.width == (ew) && (r).size.height == (eh))

static void test_zero_constants(void)
{
    CHECK(NSZeroPoint.x == 0.0 && NSZeroPoint.y == 0.0);
    CHECK(NSZeroSize.width == 0.0 && NSZeroSize.height == 0.0);
    CHECK_RECT(NSZeroRect, 0.0, 0.0, 0.0, 0.0);
}

static void test_equality(void)
{
    CHECK(NSEqualPoints(NSMakePoint(1, 2), NSMakePoint(1, 2)));
    CHECK(!NSEqualPoints(NSMakePoint(1, 2), NSMakePoint(2, 1)));
    CHECK(NSEqualSizes(NSMakeSize(3, 4), NSMakeSize(3, 4)));
    CHECK(!NSEqualSizes(NSMakeSize(3, 4), NSMakeSize(4, 3)));
    CHECK(NSEqualRects(NSMakeRect(1, 2, 3, 4), NSMakeRect(1, 2, 3, 4)));
    CHECK(!NSEqualRects(NSMakeRect(1, 2, 3, 4), NSMakeRect(1, 2, 3, 5)));
}

static void test_is_empty_rect(void)
{
    CHECK(NSIsEmptyRect(NSMakeRect(0, 0, 0, 10)));
    CHECK(NSIsEmptyRect(NSMakeRect(0, 0, 10, 0)));
    CHECK(!NSIsEmptyRect(NSMakeRect(0, 0, 1, 1)));
}

static void test_inset_rect(void)
{
    NSRect r = NSInsetRect(NSMakeRect(0, 0, 10, 10), 2, 3);
    CHECK_RECT(r, 2.0, 3.0, 6.0, 4.0);
}

static void test_offset_rect(void)
{
    NSRect r = NSOffsetRect(NSMakeRect(1, 2, 10, 10), 3, 4);
    CHECK_RECT(r, 4.0, 6.0, 10.0, 10.0);
}

static void test_integral_rect(void)
{
    NSRect r = NSIntegralRect(NSMakeRect(1.5, 2.4, 3.1, 4.8));
    /*  Integral: origin floors outward, corner ceils outward.  */
    CHECK_RECT(r, 1.0, 2.0, 4.0, 6.0);

    CHECK(NSIsEmptyRect(NSIntegralRect(NSMakeRect(1, 1, 0, 5))));
}

static void test_union_rect(void)
{
    NSRect r = NSUnionRect(NSMakeRect(0, 0, 2, 2), NSMakeRect(4, 4, 2, 2));
    CHECK_RECT(r, 0.0, 0.0, 6.0, 6.0);
}

static void test_union_rect_with_empty(void)
{
    NSRect solid = NSMakeRect(1, 2, 3, 4);
    CHECK(NSEqualRects(NSUnionRect(solid, NSZeroRect), solid));
    CHECK(NSEqualRects(NSUnionRect(NSZeroRect, solid), solid));
}

static void test_intersection_rect(void)
{
    NSRect r = NSIntersectionRect(NSMakeRect(0, 0, 4, 4), NSMakeRect(2, 2, 4, 4));
    CHECK_RECT(r, 2.0, 2.0, 2.0, 2.0);

    CHECK(NSIsEmptyRect(
        NSIntersectionRect(NSMakeRect(0, 0, 1, 1), NSMakeRect(5, 5, 1, 1))));
}

static void test_intersects_rect(void)
{
    CHECK(NSIntersectsRect(NSMakeRect(0, 0, 4, 4), NSMakeRect(2, 2, 4, 4)));
    CHECK(!NSIntersectsRect(NSMakeRect(0, 0, 1, 1), NSMakeRect(5, 5, 1, 1)));
    /*  Edge contact is not intersection.  */
    CHECK(!NSIntersectsRect(NSMakeRect(0, 0, 1, 1), NSMakeRect(1, 0, 1, 1)));
}

static void test_contains_rect(void)
{
    CHECK(NSContainsRect(NSMakeRect(0, 0, 10, 10), NSMakeRect(2, 2, 3, 3)));
    CHECK(!NSContainsRect(NSMakeRect(0, 0, 4, 4), NSMakeRect(2, 2, 4, 4)));
    CHECK(NSContainsRect(NSMakeRect(0, 0, 4, 4), NSMakeRect(0, 0, 4, 4)));
}

static void test_point_in_rect(void)
{
    NSRect r = NSMakeRect(0, 0, 4, 4);
    CHECK(NSPointInRect(NSMakePoint(2, 2), r));
    CHECK(!NSPointInRect(NSMakePoint(5, 2), r));
    CHECK(NSPointInRect(NSMakePoint(0, 0), r));
}

static void test_mouse_in_rect(void)
{
    /*  NSMouseInRect is flipped-aware; on the lower edge it differs from
        NSPointInRect for a non-flipped rect.  */
    NSRect r = NSMakeRect(0, 0, 4, 4);
    CHECK(NSMouseInRect(NSMakePoint(2, 2), r, NO));
    CHECK(!NSMouseInRect(NSMakePoint(9, 9), r, NO));
}

static void test_divide_rect(void)
{
    NSRect slice, remainder;
    NSDivideRect(NSMakeRect(0, 0, 10, 10), &slice, &remainder, 3, NSMinXEdge);
    CHECK_RECT(slice, 0.0, 0.0, 3.0, 10.0);
    CHECK_RECT(remainder, 3.0, 0.0, 7.0, 10.0);

    NSDivideRect(NSMakeRect(0, 0, 10, 10), &slice, &remainder, 4, NSMinYEdge);
    CHECK_RECT(slice, 0.0, 0.0, 10.0, 4.0);
    CHECK_RECT(remainder, 0.0, 4.0, 10.0, 6.0);
}

static void test_divide_rect_beyond_extent(void)
{
    NSRect slice, remainder;
    NSDivideRect(NSMakeRect(0, 0, 10, 10), &slice, &remainder, 20, NSMinXEdge);
    CHECK_RECT(slice, 0.0, 0.0, 10.0, 10.0);
    CHECK(NSIsEmptyRect(remainder));
}

int main(void)
{
    test_zero_constants();
    test_equality();
    test_is_empty_rect();
    test_inset_rect();
    test_offset_rect();
    test_integral_rect();
    test_union_rect();
    test_union_rect_with_empty();
    test_intersection_rect();
    test_intersects_rect();
    test_contains_rect();
    test_point_in_rect();
    test_mouse_in_rect();
    test_divide_rect();
    test_divide_rect_beyond_extent();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
