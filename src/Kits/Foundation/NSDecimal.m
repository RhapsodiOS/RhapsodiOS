/*	NSDecimal.m
	Public library for large precision base-10 arithmetic
	Copyright 1995-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDecimal.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>

/*	The mantissa is a plain multi-word binary integer (base 65536, each
	unsigned short a little-endian "digit"): NSDecimalAdd/Subtract/
	Multiply/Divide/Round/Compact all reduce to ordinary bignum
	arithmetic on that integer, with the surrounding NSDecimal exponent
	tracking the base-10 scale. BigInteger below is scratch space for
	those computations -- four times NSDecimalMaxSize gives enough
	headroom for a full product of two mantissas, or a mantissa scaled
	up by the 38 extra decimal digits NSDecimalDivide uses for
	precision, without ever running out of room.  */

#define BIG_WORDS (NSDecimalMaxSize * 6)

typedef struct {
    unsigned short length;
    unsigned short words[BIG_WORDS];
} BigInteger;

static void
BigTrim(BigInteger *big)
{
    while (big->length > 0 && big->words[big->length - 1] == 0)
        big->length--;
}

static void
BigFromMantissa(BigInteger *big, const unsigned short *mantissa, int length)
{
    int i;

    for (i = 0; i < length; i++)
        big->words[i] = mantissa[i];
    big->length = length;
    BigTrim(big);
}

static void
BigToMantissa(unsigned short *mantissa, const BigInteger *big)
{
    int i;

    for (i = 0; i < big->length; i++)
        mantissa[i] = big->words[i];
}

/*  Magnitude comparison of two little-endian word arrays: 1 if a>b,
    -1 if a<b, 0 if equal. Both arrays must be trimmed (no high zero
    words), which every helper below maintains as an invariant.  */
static int
CompareMantissas(const unsigned short *a, int lengthA, const unsigned short *b, int lengthB)
{
    int i;

    if (lengthA != lengthB)
        return lengthA > lengthB ? 1 : -1;
    for (i = lengthA - 1; i >= 0; i--) {
        if (a[i] != b[i])
            return a[i] > b[i] ? 1 : -1;
    }
    return 0;
}

static void
BigAddMantissas(BigInteger *sum, const unsigned short *a, int lengthA,
                                   const unsigned short *b, int lengthB)
{
    int i, n;
    unsigned int carry, wordA, wordB, total;

    carry = 0;
    n = lengthA > lengthB ? lengthA : lengthB;
    for (i = 0; i < n; i++) {
        wordA = (i < lengthA) ? a[i] : 0;
        wordB = (i < lengthB) ? b[i] : 0;
        total = wordA + wordB + carry;
        sum->words[i] = (unsigned short)total;
        carry = total >> 16;
    }
    if (carry != 0)
        sum->words[n++] = (unsigned short)carry;
    sum->length = n;
    BigTrim(sum);
}

/*  difference = a - b; requires a >= b in magnitude.  */
static void
BigSubtractMantissas(BigInteger *difference, const unsigned short *a, int lengthA,
                                                const unsigned short *b, int lengthB)
{
    int i, borrow, wordB, total;

    borrow = 0;
    for (i = 0; i < lengthA; i++) {
        wordB = (i < lengthB) ? b[i] : 0;
        total = (int)a[i] - wordB - borrow;
        if (total < 0) {
            total += 0x10000;
            borrow = 1;
        } else {
            borrow = 0;
        }
        difference->words[i] = (unsigned short)total;
    }
    difference->length = lengthA;
    BigTrim(difference);
}

static void
BigMultiplyMantissas(BigInteger *product, const unsigned short *a, int lengthA,
                                             const unsigned short *b, int lengthB)
{
    int i, j;
    unsigned int carry, total;

    for (i = 0; i < lengthA + lengthB; i++)
        product->words[i] = 0;

    for (j = 0; j < lengthB; j++) {
        carry = 0;
        for (i = 0; i < lengthA; i++) {
            total = (unsigned int)a[i] * b[j] + product->words[i + j] + carry;
            product->words[i + j] = (unsigned short)total;
            carry = total >> 16;
        }
        product->words[j + lengthA] = (unsigned short)carry;
    }
    product->length = lengthA + lengthB;
    BigTrim(product);
}

/*  Divides big by a single word in place, returning the remainder.  */
static unsigned short
BigDivideByShort(BigInteger *big, unsigned short divisor)
{
    int i;
    unsigned int remainder, dividend;

    remainder = 0;
    for (i = big->length - 1; i >= 0; i--) {
        dividend = (remainder << 16) | big->words[i];
        big->words[i] = (unsigned short)(dividend / divisor);
        remainder = dividend % divisor;
    }
    BigTrim(big);
    return (unsigned short)remainder;
}

static void
BigMultiplyByShort(BigInteger *big, unsigned short factor)
{
    int i;
    unsigned int carry, total;

    carry = 0;
    for (i = 0; i < big->length; i++) {
        total = (unsigned int)big->words[i] * factor + carry;
        big->words[i] = (unsigned short)total;
        carry = total >> 16;
    }
    if (carry != 0)
        big->words[big->length++] = (unsigned short)carry;
}

static void
BigAddShort(BigInteger *big, unsigned short addend)
{
    int i;
    unsigned int carry, total;

    carry = addend;
    for (i = 0; i < big->length && carry != 0; i++) {
        total = (unsigned int)big->words[i] + carry;
        big->words[i] = (unsigned short)total;
        carry = total >> 16;
    }
    if (carry != 0)
        big->words[big->length++] = (unsigned short)carry;
}

/*  Shifts big left by one bit, shifting incomingBit (0 or 1) into the
    bottom, growing big->length if a new top word is needed.  */
static void
BigShiftLeft1(BigInteger *big, int incomingBit)
{
    int i;
    unsigned int carry, total;

    carry = (unsigned int)incomingBit;
    for (i = 0; i < big->length; i++) {
        total = ((unsigned int)big->words[i] << 1) | carry;
        big->words[i] = (unsigned short)total;
        carry = total >> 16;
    }
    if (carry != 0)
        big->words[big->length++] = (unsigned short)carry;
}

/*  Schoolbook binary long division: quotient = dividend / divisor,
    processing the dividend one bit at a time. Slower than the
    reference's word-at-a-time Knuth division, but the values here are
    at most a few hundred bits wide, so the simplicity is worth it.  */
static void
BigDivideMantissas(BigInteger *quotient, const BigInteger *dividendIn,
                     const unsigned short *divisorWords, int divisorLength)
{
    BigInteger dividend, remainder, reduced;
    int totalBits, bit, word, bitInWord, dividendBit, i;

    dividend = *dividendIn;

    while (divisorLength > 0 && divisorWords[divisorLength - 1] == 0)
        divisorLength--;

    remainder.length = 0;
    quotient->length = dividend.length;
    for (i = 0; i < dividend.length; i++)
        quotient->words[i] = 0;

    totalBits = dividend.length * 16;
    for (bit = totalBits - 1; bit >= 0; bit--) {
        word = bit / 16;
        bitInWord = bit % 16;
        dividendBit = (dividend.words[word] >> bitInWord) & 1;

        BigShiftLeft1(&remainder, dividendBit);

        if (CompareMantissas(remainder.words, remainder.length, divisorWords, divisorLength) >= 0) {
            BigSubtractMantissas(&reduced, remainder.words, remainder.length, divisorWords, divisorLength);
            remainder = reduced;
            quotient->words[word] |= (unsigned short)(1 << bitInWord);
        }
    }

    BigTrim(quotient);
}

/*  Multiplies (power >= 0) or divides (power < 0) big by 10^|power|.
    Division truncates -- callers that care about the discarded digits
    track them separately (see DropDigits/ShrinkToCapacity below).  */
static void
BigMultiplyByPowerOf10(BigInteger *big, int power)
{
    if (power >= 0) {
        while (power-- > 0)
            BigMultiplyByShort(big, 10);
    } else {
        while (power++ < 0)
            BigDivideByShort(big, 10);
    }
}

/*  Rough estimate (matching the reference's 4.81647993 ~= log10(65536))
    of how many more decimal digits a mantissa with `length` of
    `capacity` words could still absorb.  */
static int
MaxAdditionalDigits(int length, int capacity)
{
    return (int)(4.81647993 * (double)(capacity - length));
}

/*  Removes exactly `count` trailing decimal digits from big, reporting
    the last digit dropped and whether any earlier dropped digit was
    nonzero. When there was hidden precision beyond an exact 0 or 5,
    the boundary digit is nudged to 1 or 6 so callers can treat "digit"
    as the true tie-break value.  */
static void
DropDigits(BigInteger *big, int count, int *digit, int *lostPrecision)
{
    int lastDigit, lost;

    lastDigit = 0;
    lost = 0;
    while (count-- > 0) {
        if (lastDigit != 0)
            lost = 1;
        lastDigit = BigDivideByShort(big, 10);
    }
    if (lost && (lastDigit == 0 || lastDigit == 5))
        lastDigit++;
    *digit = lastDigit;
    *lostPrecision = lost;
}

/*  Removes trailing decimal digits from big until it fits in `capacity`
    words, the same way DropDigits does, but stopping on word count
    rather than a fixed digit count.  */
static void
ShrinkToCapacity(BigInteger *big, int capacity, int *shift, int *digit, int *lostPrecision)
{
    int lastDigit, lost, count;

    lastDigit = 0;
    lost = 0;
    count = 0;
    while (big->length > capacity) {
        if (lastDigit != 0)
            lost = 1;
        lastDigit = BigDivideByShort(big, 10);
        count++;
    }
    if (lost && (lastDigit == 0 || lastDigit == 5))
        lastDigit++;
    *shift = count;
    *digit = lastDigit;
    *lostPrecision = lost;
}

/*  Implements the header's rounding-policy table: whether a value with
    a discarded next-digit of `digit` (1-9, boosted per DropDigits/
    ShrinkToCapacity when more was discarded past it) should be rounded
    away from the kept digits. `keptIsOdd` is the parity of the value
    that will remain once the digit is dropped.  */
static int
ShouldRoundUp(NSRoundingMode roundingMode, int digit, int keptIsOdd)
{
    switch (roundingMode) {
    case NSRoundDown:
        return 0;
    case NSRoundUp:
        return digit != 0;
    case NSRoundBankers:
        return digit > 5 || (digit == 5 && keptIsOdd);
    case NSRoundPlain:
    default:
        return digit >= 5;
    }
}

/*  Shrinks big to at most NSDecimalMaxSize words, folding any removed
    digits into *exponent and rounding what remains per roundingMode.
    Used by Add and Multiply, whose raw results can be one word wider
    than a decimal can hold.  */
static NSCalculationError
RoundToFit(BigInteger *big, int *exponent, NSRoundingMode roundingMode)
{
    int shift, digit, lostPrecision;

    if (big->length <= NSDecimalMaxSize)
        return NSCalculationNoError;

    ShrinkToCapacity(big, NSDecimalMaxSize, &shift, &digit, &lostPrecision);
    *exponent += shift;

    if (digit == 0)
        return NSCalculationNoError;

    if (ShouldRoundUp(roundingMode, digit, (big->words[0] & 1) != 0))
        BigAddShort(big, 1);

    return NSCalculationLossOfPrecision;
}

/*	Sets a decimal to the not-a-number value: length 0, isNegative set.
    NSDecimalIsNotANumber() (in the header) is exactly this test.  */
static void
SetNotANumber(NSDecimal *decimal)
{
    decimal->_length = 0;
    decimal->_isNegative = 1;
}

/*	Operations		*/

void
NSDecimalCopy(NSDecimal *destination, const NSDecimal *source)
{
    int i;

    destination->_reserved = 0;
    destination->_isNegative = source->_isNegative;
    destination->_length = source->_length;
    destination->_exponent = source->_exponent;
    destination->_isCompact = source->_isCompact;

    for (i = 0; i < destination->_length; i++)
        destination->_mantissa[i] = source->_mantissa[i];
}

void
NSDecimalCompact(NSDecimal *number)
{
    int exponent;
    unsigned short remainder;
    BigInteger value;

    if (number->_isCompact || NSDecimalIsNotANumber(number) || number->_length == 0)
        return;

    exponent = number->_exponent;
    BigFromMantissa(&value, number->_mantissa, number->_length);

    do {
        remainder = BigDivideByShort(&value, 10);
        exponent++;
    } while (remainder == 0);

    /*  The last division didn't come out even -- undo it.  */
    BigMultiplyByShort(&value, 10);
    BigAddShort(&value, remainder);
    exponent--;

    /*  Keep the signed 8-bit exponent in range by giving back digits.  */
    while (exponent > 127) {
        BigMultiplyByShort(&value, 10);
        exponent--;
    }

    number->_exponent = exponent;
    BigToMantissa(number->_mantissa, &value);
    number->_length = value.length;
    number->_isCompact = 1;
}

NSComparisonResult
NSDecimalCompare(const NSDecimal *leftOperand, const NSDecimal *rightOperand)
{
    NSDecimal left, right;
    NSComparisonResult magnitude;

    if (NSDecimalIsNotANumber(leftOperand))
        return NSDecimalIsNotANumber(rightOperand) ? NSOrderedSame : NSOrderedAscending;
    if (NSDecimalIsNotANumber(rightOperand))
        return NSOrderedDescending;

    if (leftOperand->_isNegative != rightOperand->_isNegative)
        return leftOperand->_isNegative ? NSOrderedAscending : NSOrderedDescending;

    if (leftOperand->_length == 0)
        return (rightOperand->_length == 0) ? NSOrderedSame : NSOrderedAscending;
    if (rightOperand->_length == 0)
        return NSOrderedDescending;

    NSDecimalCopy(&left, leftOperand);
    NSDecimalCopy(&right, rightOperand);
    NSDecimalNormalize(&left, &right, NSRoundDown);

    magnitude = CompareMantissas(left._mantissa, left._length, right._mantissa, right._length);

    if (left._isNegative && magnitude != NSOrderedSame)
        return (magnitude == NSOrderedAscending) ? NSOrderedDescending : NSOrderedAscending;

    return magnitude;
}

void
NSDecimalRound(NSDecimal *result, const NSDecimal *number, int scale, NSRoundingMode roundingMode)
{
    BigInteger value;
    int exponent, placesToDrop, digit, lostPrecision;

    exponent = (int)number->_exponent + scale;
    if (scale == NSDecimalNoScale || exponent >= 0) {
        if (result != number)
            NSDecimalCopy(result, number);
        return;
    }

    placesToDrop = -exponent;
    exponent = -scale;

    NSDecimalCopy(result, number);
    BigFromMantissa(&value, result->_mantissa, result->_length);

    DropDigits(&value, placesToDrop, &digit, &lostPrecision);

    if (digit != 0) {
        if (ShouldRoundUp(roundingMode, digit, (value.words[0] & 1) != 0))
            BigAddShort(&value, 1);
        if (number->_isNegative && value.length == 0)
            result->_isNegative = 0;
    }

    while (exponent > 127) {
        BigMultiplyByShort(&value, 10);
        exponent--;
    }

    result->_exponent = exponent;
    BigToMantissa(result->_mantissa, &value);
    result->_length = value.length;
    result->_isCompact = 0;
    NSDecimalCompact(result);
}

NSCalculationError
NSDecimalNormalize(NSDecimal *number1, NSDecimal *number2, NSRoundingMode roundingMode)
{
    NSDecimal *larger, *smaller;
    int diff, headroom;
    BigInteger scaled;

    diff = (int)number1->_exponent - (int)number2->_exponent;
    if (diff == 0)
        return NSCalculationNoError;

    if (diff > 0) {
        larger = number1;
        smaller = number2;
    } else {
        larger = number2;
        smaller = number1;
        diff = -diff;
    }

    /*  larger has the bigger exponent: try scaling its mantissa up by
        10^diff so it can adopt smaller's (lower) exponent exactly.  */
    BigFromMantissa(&scaled, larger->_mantissa, larger->_length);
    BigMultiplyByPowerOf10(&scaled, diff);

    if (scaled.length <= NSDecimalMaxSize) {
        BigToMantissa(larger->_mantissa, &scaled);
        larger->_length = scaled.length;
        larger->_exponent = smaller->_exponent;
        larger->_isCompact = 0;
        return NSCalculationNoError;
    }

    /*  Scaling exactly would overflow the mantissa -- give back as
        much precision as fits on both sides and accept the loss.  */
    headroom = MaxAdditionalDigits(larger->_length, NSDecimalMaxSize);

    BigFromMantissa(&scaled, smaller->_mantissa, smaller->_length);
    BigMultiplyByPowerOf10(&scaled, headroom - diff);
    BigToMantissa(smaller->_mantissa, &scaled);
    smaller->_length = scaled.length;
    smaller->_exponent -= (headroom - diff);
    smaller->_isCompact = 0;

    if (smaller->_length != 0) {
        BigFromMantissa(&scaled, larger->_mantissa, larger->_length);
        BigMultiplyByPowerOf10(&scaled, headroom);
        BigToMantissa(larger->_mantissa, &scaled);
        larger->_length = scaled.length;
        larger->_exponent -= headroom;
        larger->_isCompact = 0;
    } else {
        smaller->_exponent = larger->_exponent;
    }

    return NSCalculationLossOfPrecision;
}

NSCalculationError
NSDecimalAdd(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand,
             NSRoundingMode roundingMode)
{
    NSDecimal left, right;
    NSCalculationError alignError, roundError;
    int exponent, cmp;
    BigInteger sum, difference;

    if (NSDecimalIsNotANumber(leftOperand) || NSDecimalIsNotANumber(rightOperand)) {
        SetNotANumber(result);
        return NSCalculationOverflow;
    }
    if (leftOperand->_length == 0) {
        NSDecimalCopy(result, rightOperand);
        return NSCalculationNoError;
    }
    if (rightOperand->_length == 0) {
        NSDecimalCopy(result, leftOperand);
        return NSCalculationNoError;
    }

    NSDecimalCopy(&left, leftOperand);
    NSDecimalCopy(&right, rightOperand);
    alignError = NSDecimalNormalize(&left, &right, roundingMode);

    if (left._length == 0) {
        NSDecimalCopy(result, &right);
        return alignError;
    }
    if (right._length == 0) {
        NSDecimalCopy(result, &left);
        return alignError;
    }

    exponent = left._exponent;
    roundError = NSCalculationNoError;

    if (left._isNegative == right._isNegative) {
        result->_isNegative = left._isNegative;
        BigAddMantissas(&sum, left._mantissa, left._length, right._mantissa, right._length);
        roundError = RoundToFit(&sum, &exponent, roundingMode);
        if (exponent > 127) {
            SetNotANumber(result);
            return NSCalculationOverflow;
        }
        BigToMantissa(result->_mantissa, &sum);
        result->_length = sum.length;
    } else {
        cmp = CompareMantissas(left._mantissa, left._length, right._mantissa, right._length);
        if (cmp == 0) {
            result->_length = 0;
            result->_isNegative = 0;
        } else if (cmp > 0) {
            BigSubtractMantissas(&difference, left._mantissa, left._length, right._mantissa, right._length);
            BigToMantissa(result->_mantissa, &difference);
            result->_length = difference.length;
            result->_isNegative = left._isNegative;
        } else {
            BigSubtractMantissas(&difference, right._mantissa, right._length, left._mantissa, left._length);
            BigToMantissa(result->_mantissa, &difference);
            result->_length = difference.length;
            result->_isNegative = right._isNegative;
        }
    }

    result->_exponent = exponent;
    result->_isCompact = 0;
    NSDecimalCompact(result);

    return (roundError != NSCalculationNoError) ? roundError : alignError;
}

NSCalculationError
NSDecimalSubtract(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand,
                   NSRoundingMode roundingMode)
{
    NSDecimal negatedRight;

    NSDecimalCopy(&negatedRight, rightOperand);
    if (negatedRight._length != 0)
        negatedRight._isNegative = !negatedRight._isNegative;

    return NSDecimalAdd(result, leftOperand, &negatedRight, roundingMode);
}

NSCalculationError
NSDecimalMultiply(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand,
                   NSRoundingMode roundingMode)
{
    BigInteger product;
    int exponent;
    NSCalculationError roundError;

    if (NSDecimalIsNotANumber(leftOperand) || NSDecimalIsNotANumber(rightOperand)) {
        SetNotANumber(result);
        return NSCalculationOverflow;
    }
    if (leftOperand->_length == 0 || rightOperand->_length == 0) {
        result->_length = 0;
        result->_isNegative = 0;
        return NSCalculationNoError;
    }

    BigMultiplyMantissas(&product, leftOperand->_mantissa, leftOperand->_length,
                                     rightOperand->_mantissa, rightOperand->_length);
    exponent = (int)leftOperand->_exponent + (int)rightOperand->_exponent;
    roundError = RoundToFit(&product, &exponent, roundingMode);

    if (exponent > 127) {
        SetNotANumber(result);
        return NSCalculationOverflow;
    }

    result->_isNegative = (leftOperand->_isNegative != rightOperand->_isNegative);
    BigToMantissa(result->_mantissa, &product);
    result->_length = product.length;
    result->_exponent = exponent;
    result->_isCompact = 0;
    NSDecimalCompact(result);

    return roundError;
}

NSCalculationError
NSDecimalDivide(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand,
                 NSRoundingMode roundingMode)
{
    BigInteger dividend, quotient;
    int exponent, shift;

    if (NSDecimalIsNotANumber(leftOperand) || NSDecimalIsNotANumber(rightOperand)) {
        SetNotANumber(result);
        return NSCalculationOverflow;
    }
    if (rightOperand->_length == 0) {
        SetNotANumber(result);
        return NSCalculationDivideByZero;
    }
    if (leftOperand->_length == 0) {
        result->_length = 0;
        result->_isNegative = 0;
        return NSCalculationNoError;
    }

    /*  Scale the dividend up by 38 extra decimal digits before
        dividing, so the quotient carries as much precision as the
        mantissa can hold. Division is truncated, not rounded -- the
        header documents that it "could be silently inexact".  */
    BigFromMantissa(&dividend, leftOperand->_mantissa, leftOperand->_length);
    BigMultiplyByPowerOf10(&dividend, 38);
    BigDivideMantissas(&quotient, &dividend, rightOperand->_mantissa, rightOperand->_length);

    shift = 0;
    while (quotient.length > NSDecimalMaxSize) {
        BigDivideByShort(&quotient, 10);
        shift++;
    }

    exponent = shift - 38 + (int)leftOperand->_exponent - (int)rightOperand->_exponent;
    if (exponent < -128) {
        SetNotANumber(result);
        return NSCalculationUnderflow;
    }
    if (exponent > 127) {
        SetNotANumber(result);
        return NSCalculationOverflow;
    }

    result->_isNegative = (leftOperand->_isNegative != rightOperand->_isNegative);
    BigToMantissa(result->_mantissa, &quotient);
    result->_length = quotient.length;
    result->_exponent = exponent;
    result->_isCompact = 0;
    NSDecimalCompact(result);

    return NSCalculationNoError;
}

NSCalculationError
NSDecimalPower(NSDecimal *result, const NSDecimal *number, unsigned power, NSRoundingMode roundingMode)
{
    NSCalculationError error, step;

    if (NSDecimalIsNotANumber(number)) {
        SetNotANumber(result);
        return NSCalculationOverflow;
    }

    if (power == 0) {
        /*  x^0 == 1, but the reference keeps the operand's sign.  */
        result->_exponent = 0;
        result->_length = 1;
        result->_isNegative = number->_isNegative;
        result->_mantissa[0] = 1;
        result->_isCompact = 1;
        return NSCalculationNoError;
    }

    NSDecimalCopy(result, number);
    error = NSCalculationNoError;
    while (--power != 0) {
        step = NSDecimalMultiply(result, result, number, roundingMode);
        if (step > error)
            error = step;
        if (error == NSCalculationUnderflow || error == NSCalculationOverflow) {
            SetNotANumber(result);
            return error;
        }
    }
    return error;
}

NSCalculationError
NSDecimalMultiplyByPowerOf10(NSDecimal *result, const NSDecimal *number, short power, NSRoundingMode roundingMode)
{
    int exponent;

    if (NSDecimalIsNotANumber(number)) {
        SetNotANumber(result);
        return NSCalculationOverflow;
    }
    if (number->_length == 0) {
        result->_length = 0;
        result->_isNegative = 0;
        return NSCalculationNoError;
    }

    if (result != number)
        NSDecimalCopy(result, number);

    exponent = (int)result->_exponent + power;
    if (exponent < -128) {
        SetNotANumber(result);
        return NSCalculationUnderflow;
    }
    if (exponent > 127) {
        SetNotANumber(result);
        return NSCalculationOverflow;
    }

    result->_exponent = exponent;
    return NSCalculationNoError;
}

NSString *
NSDecimalString(const NSDecimal *decimal, NSDictionary *locale)
{
    char digits[64];
    char buffer[96];
    char *out;
    char separator;
    int digitCount, i, exponent, fractionDigits;
    BigInteger value;

    separator = '.';
    if (locale != nil) {
        id separatorString = [locale objectForKey:NSDecimalSeparator];
        if (separatorString != nil)
            separator = (char)[separatorString characterAtIndex:0];
    }

    out = buffer;
    if (NSDecimalIsNotANumber(decimal))
        return [NSString stringWithCString:"NaN"];

    if (decimal->_isNegative)
        *out++ = '-';

    if (decimal->_length == 0) {
        *out++ = '0';
        *out = '\0';
        return [NSString stringWithCString:buffer];
    }

    BigFromMantissa(&value, decimal->_mantissa, decimal->_length);
    digitCount = 0;
    while (value.length != 0)
        digits[digitCount++] = (char)('0' + BigDivideByShort(&value, 10));
    /*  digits[] now holds the decimal digits, least significant first.  */

    exponent = decimal->_exponent;
    if (exponent >= 0) {
        for (i = digitCount - 1; i >= 0; i--)
            *out++ = digits[i];
        for (i = 0; i < exponent; i++)
            *out++ = '0';
    } else {
        fractionDigits = -exponent;
        if (fractionDigits >= digitCount) {
            *out++ = '0';
            *out++ = separator;
            for (i = 0; i < fractionDigits - digitCount; i++)
                *out++ = '0';
            for (i = digitCount - 1; i >= 0; i--)
                *out++ = digits[i];
        } else {
            for (i = digitCount - 1; i >= fractionDigits; i--)
                *out++ = digits[i];
            *out++ = separator;
            for (i = fractionDigits - 1; i >= 0; i--)
                *out++ = digits[i];
        }
    }
    *out = '\0';

    return [NSString stringWithCString:buffer];
}
