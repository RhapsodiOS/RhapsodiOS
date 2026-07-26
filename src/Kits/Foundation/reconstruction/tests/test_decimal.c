/*  Behavioural tests for NSDecimal.m, stage 1 of the Foundation
    reconstruction. Covers the 11 NSDecimal functions that do not touch
    NSString; NSDecimalString is deferred to stage 3.  */

#import <Foundation/NSDecimal.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

/*  Build a decimal from a base-10000 mantissa, most significant word last.  */
static NSDecimal make(int negative, int exponent, int length,
                      unsigned short w0, unsigned short w1)
{
    NSDecimal d;
    memset(&d, 0, sizeof(d));
    d._isNegative = negative;
    d._exponent = exponent;
    d._length = length;
    d._mantissa[0] = w0;
    d._mantissa[1] = w1;
    return d;
}

static NSDecimal nan_value(void)
{
    NSDecimal d;
    memset(&d, 0, sizeof(d));
    d._length = 0;
    d._isNegative = 1;
    return d;
}

static void test_copy(void)
{
    /*  The reference only copies the first _length mantissa words, so
        target must start zeroed like source (via make()) for a
        whole-struct memcmp to be well-defined -- otherwise it is
        comparing source's zeroed tail against target's uninitialized
        stack garbage.  */
    NSDecimal source = make(0, -2, 1, 1234, 0);
    NSDecimal target = make(0, 0, 0, 0, 0);
    NSDecimalCopy(&target, &source);
    CHECK(memcmp(&target, &source, sizeof(NSDecimal)) == 0);
}

static void test_compare(void)
{
    NSDecimal one = make(0, 0, 1, 1, 0);
    NSDecimal two = make(0, 0, 1, 2, 0);
    NSDecimal minus_one = make(1, 0, 1, 1, 0);

    CHECK(NSDecimalCompare(&one, &two) == NSOrderedAscending);
    CHECK(NSDecimalCompare(&two, &one) == NSOrderedDescending);
    CHECK(NSDecimalCompare(&one, &one) == NSOrderedSame);
    CHECK(NSDecimalCompare(&minus_one, &one) == NSOrderedAscending);
}

static void test_compare_across_exponents(void)
{
    /*  100 * 10^0  ==  1 * 10^2  */
    NSDecimal a = make(0, 0, 1, 100, 0);
    NSDecimal b = make(0, 2, 1, 1, 0);
    CHECK(NSDecimalCompare(&a, &b) == NSOrderedSame);
}

static void test_compact_removes_trailing_zero_words(void)
{
    NSDecimal d = make(0, 0, 2, 5, 0);
    NSDecimalCompact(&d);
    CHECK(d._length == 1);
    CHECK(d._isCompact != 0);
}

static void test_add(void)
{
    NSDecimal a = make(0, 0, 1, 2, 0), b = make(0, 0, 1, 3, 0), r;
    CHECK(NSDecimalAdd(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._length == 1 && r._mantissa[0] == 5 && r._isNegative == 0);
}

static void test_add_with_differing_exponents(void)
{
    /*  1 * 10^2 + 5 * 10^0 == 105  */
    NSDecimal a = make(0, 2, 1, 1, 0), b = make(0, 0, 1, 5, 0), r;
    NSDecimal expected = make(0, 0, 1, 105, 0);
    CHECK(NSDecimalAdd(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);

    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);
}

static void test_subtract(void)
{
    NSDecimal a = make(0, 0, 1, 3, 0), b = make(0, 0, 1, 5, 0), r;
    CHECK(NSDecimalSubtract(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._isNegative == 1 && r._mantissa[0] == 2);
}

static void test_subtract_to_zero(void)
{
    NSDecimal a = make(0, 0, 1, 7, 0), r;
    CHECK(NSDecimalSubtract(&r, &a, &a, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._length == 0 && r._isNegative == 0);
}

static void test_multiply(void)
{
    NSDecimal a = make(0, 0, 1, 6, 0), b = make(0, 0, 1, 7, 0), r;
    CHECK(NSDecimalMultiply(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._mantissa[0] == 42);
}

static void test_multiply_adds_exponents(void)
{
    NSDecimal a = make(0, 2, 1, 3, 0), b = make(0, 3, 1, 2, 0), r;
    CHECK(NSDecimalMultiply(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._exponent == 5 && r._mantissa[0] == 6);
}

static void test_multiply_by_negative(void)
{
    NSDecimal a = make(0, 0, 1, 4, 0), b = make(1, 0, 1, 5, 0), r;
    /*  NSDecimalMultiply always compacts its result, and -20 compacts to
        -2 * 10^1 -- compare by value rather than raw mantissa words.  */
    NSDecimal expected = make(1, 0, 1, 20, 0);
    CHECK(NSDecimalMultiply(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._isNegative == 1);
    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);
}

static void test_divide(void)
{
    NSDecimal a = make(0, 0, 1, 42, 0), b = make(0, 0, 1, 6, 0), r;
    NSDecimal expected = make(0, 0, 1, 7, 0);
    CHECK(NSDecimalDivide(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);

    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);
}

static void test_divide_by_zero(void)
{
    NSDecimal a = make(0, 0, 1, 1, 0), zero = make(0, 0, 0, 0, 0), r;
    CHECK(NSDecimalDivide(&r, &a, &zero, NSRoundPlain) == NSCalculationDivideByZero);
    CHECK(NSDecimalIsNotANumber(&r));
}

static void test_nan_propagates(void)
{
    NSDecimal a = make(0, 0, 1, 1, 0), bad = nan_value(), r;
    NSDecimalAdd(&r, &a, &bad, NSRoundPlain);
    CHECK(NSDecimalIsNotANumber(&r));
}

static void test_power(void)
{
    NSDecimal base = make(0, 0, 1, 3, 0), r;
    CHECK(NSDecimalPower(&r, &base, 4, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._mantissa[0] == 81);
}

static void test_power_of_zero_is_one(void)
{
    NSDecimal base = make(0, 0, 1, 9, 0), r;
    NSDecimal one = make(0, 0, 1, 1, 0);
    CHECK(NSDecimalPower(&r, &base, 0, NSRoundPlain) == NSCalculationNoError);

    CHECK(NSDecimalCompare(&r, &one) == NSOrderedSame);
}

static void test_multiply_by_power_of_10(void)
{
    NSDecimal n = make(0, 0, 1, 5, 0), r;
    CHECK(NSDecimalMultiplyByPowerOf10(&r, &n, 3, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._exponent == 3 && r._mantissa[0] == 5);

    CHECK(NSDecimalMultiplyByPowerOf10(&r, &n, -2, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._exponent == -2 && r._mantissa[0] == 5);
}

static void test_normalize_aligns_exponents(void)
{
    NSDecimal a = make(0, 2, 1, 1, 0), b = make(0, 0, 1, 5, 0);
    NSDecimal hundred = make(0, 0, 1, 100, 0);
    CHECK(NSDecimalNormalize(&a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(a._exponent == b._exponent);

    CHECK(NSDecimalCompare(&a, &hundred) == NSOrderedSame);
}

static void test_round_down_truncates(void)
{
    /*  1.27 rounded to 1 place: Down -> 1.2, Up -> 1.3 (header's table)  */
    NSDecimal value = make(0, -2, 1, 127, 0), r;
    NSDecimal expected_down = make(0, -1, 1, 12, 0);
    NSDecimal expected_up = make(0, -1, 1, 13, 0);

    NSDecimalRound(&r, &value, 1, NSRoundDown);
    CHECK(NSDecimalCompare(&r, &expected_down) == NSOrderedSame);

    NSDecimalRound(&r, &value, 1, NSRoundUp);
    CHECK(NSDecimalCompare(&r, &expected_up) == NSOrderedSame);
}

static void test_round_plain_and_bankers_on_a_tie(void)
{
    /*  Header's table: 1.25 -> Plain 1.3, Bankers 1.2
                        1.35 -> Plain 1.4, Bankers 1.4  */
    NSDecimal quarter = make(0, -2, 1, 125, 0);
    NSDecimal three_five = make(0, -2, 1, 135, 0);
    NSDecimal r, expected;

    NSDecimalRound(&r, &quarter, 1, NSRoundPlain);
    expected = make(0, -1, 1, 13, 0);
    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);

    NSDecimalRound(&r, &quarter, 1, NSRoundBankers);
    expected = make(0, -1, 1, 12, 0);
    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);

    NSDecimalRound(&r, &three_five, 1, NSRoundBankers);
    expected = make(0, -1, 1, 14, 0);
    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);
}

static void test_round_in_place(void)
{
    /*  The header promises result may alias number.  */
    NSDecimal value = make(0, -2, 1, 127, 0);
    NSDecimal expected = make(0, -1, 1, 12, 0);
    NSDecimalRound(&value, &value, 1, NSRoundDown);

    CHECK(NSDecimalCompare(&value, &expected) == NSOrderedSame);
}

static void test_add_in_place(void)
{
    /*  The header promises result may alias either operand.  */
    NSDecimal a = make(0, 0, 1, 2, 0), b = make(0, 0, 1, 3, 0);
    CHECK(NSDecimalAdd(&a, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(a._mantissa[0] == 5);
}

int main(void)
{
    test_copy();
    test_compare();
    test_compare_across_exponents();
    test_compact_removes_trailing_zero_words();
    test_add();
    test_add_with_differing_exponents();
    test_subtract();
    test_subtract_to_zero();
    test_multiply();
    test_multiply_adds_exponents();
    test_multiply_by_negative();
    test_divide();
    test_divide_by_zero();
    test_nan_propagates();
    test_power();
    test_power_of_zero_is_one();
    test_multiply_by_power_of_10();
    test_normalize_aligns_exponents();
    test_round_down_truncates();
    test_round_plain_and_bankers_on_a_tie();
    test_round_in_place();
    test_add_in_place();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
