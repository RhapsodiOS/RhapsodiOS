/*	NSDecimal.m
	Public library for large precision base-10 arithmetic
	Copyright 1995-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDecimal.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSZone.h>

/*	The mantissa is a plain multi-word binary integer (base 65536, each
	unsigned short a little-endian "digit"): NSDecimalAdd/Subtract/
	Multiply/Divide/Round/Compact all reduce to ordinary bignum
	arithmetic on that integer, with the surrounding NSDecimal exponent
	tracking the base-10 scale. BigInteger below is scratch space for
	those computations -- six times NSDecimalMaxSize gives enough
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

int NSIntegerCompare(const unsigned short *left, unsigned short leftLength,
                     const unsigned short *right,
                     unsigned short rightLength)
{
    unsigned int index;

    if (leftLength > rightLength)
        return 1;
    if (leftLength < rightLength)
        return -1;
    for (index = leftLength; index != 0; index--) {
        if (left[index - 1] > right[index - 1])
            return 1;
        if (left[index - 1] < right[index - 1])
            return -1;
    }
    return 0;
}

int NSIntegerCopy(unsigned short *destination,
                  unsigned short *destinationLength,
                  const unsigned short *source, unsigned short sourceLength)
{
    unsigned short index;
    int result = 0;

    for (index = 0; index < sourceLength; index++) {
        destination[index] = source[index];
        result = index;
    }
    *destinationLength = sourceLength;
#if defined(__ppc__) || defined(__POWERPC__)
    return (int)(long)destination;
#else
    return result;
#endif
}

int NSIntegerAddShort(unsigned short *destination,
                      unsigned short *destinationLength,
                      const unsigned short *source,
                      unsigned short sourceLength,
                      unsigned short addend)
{
    unsigned int carry = addend;
    unsigned short index;

    for (index = 0; index < sourceLength; index++) {
        unsigned int sum = source[index] + carry;

        destination[index] = (unsigned short)sum;
        carry = sum >> 16;
    }
    if (carry != 0) {
        if (*destinationLength == sourceLength)
            return NSCalculationOverflow;
        destination[sourceLength] = (unsigned short)carry;
        sourceLength++;
    }
    *destinationLength = sourceLength;
    return NSCalculationNoError;
}

int NSIntegerSubShort(unsigned short *destination,
                      unsigned short *destinationLength,
                      const unsigned short *source,
                      unsigned short sourceLength,
                      unsigned short subtrahend)
{
    unsigned int state = (unsigned int)subtrahend - 1;
    unsigned short index;

    for (index = 0; index < sourceLength; index++) {
        unsigned int difference = (unsigned int)source[index] -
                                  (state - 0xffffU);

        destination[index] = (unsigned short)difference;
        state = difference >> 16;
    }
    *destinationLength = sourceLength;
    if (state == 0)
        return NSCalculationOverflow;
    while (*destinationLength != 0 &&
           destination[*destinationLength - 1] == 0)
        (*destinationLength)--;
    return NSCalculationNoError;
}

int NSIntegerMultiplyByShort(unsigned short *destination,
                             unsigned short *destinationLength,
                             const unsigned short *source,
                             unsigned short sourceLength,
                             unsigned short factor)
{
    unsigned int carry = 0;
    unsigned short index;

    if (factor == 0) {
        *destinationLength = 0;
        return NSCalculationNoError;
    }
    if (*destinationLength < sourceLength)
        return NSCalculationOverflow;
    for (index = 0; index < sourceLength; index++) {
        unsigned int product = (unsigned int)source[index] * factor + carry;

        destination[index] = (unsigned short)product;
        carry = product >> 16;
    }
    if (carry != 0) {
        if (*destinationLength == sourceLength)
            return NSCalculationOverflow;
        destination[sourceLength++] = (unsigned short)carry;
    }
    *destinationLength = sourceLength;
    return NSCalculationNoError;
}

int NSIntegerDivideByShort(unsigned short *destination,
                           unsigned short *destinationLength,
                           const unsigned short *source,
                           unsigned short sourceLength,
                           unsigned short divisor,
                           unsigned short *remainderResult)
{
    unsigned int remainder = 0;
    unsigned short index;

    if (divisor == 0) {
        *destinationLength = 0;
        return NSCalculationDivideByZero;
    }
    for (index = sourceLength; index != 0; index--) {
        unsigned int dividend = (remainder << 16) | source[index - 1];

        destination[index - 1] = (unsigned short)(dividend / divisor);
        remainder = dividend % divisor;
    }
    *destinationLength = sourceLength;
    while (*destinationLength != 0 &&
           destination[*destinationLength - 1] == 0)
        (*destinationLength)--;
    *remainderResult = (unsigned short)remainder;
    return NSCalculationNoError;
}

int NSIntegerAdd(unsigned short *destination,
                 unsigned short *destinationLength,
                 const unsigned short *left, unsigned short leftLength,
                 const unsigned short *right, unsigned short rightLength)
{
    unsigned int carry = 0;
    unsigned int index = 0;
    unsigned int commonLength = leftLength < rightLength
        ? leftLength : rightLength;

    for (; index < commonLength; index++) {
        unsigned int sum = carry + left[index] + right[index];

        destination[index] = (unsigned short)sum;
        carry = sum >> 16;
    }
    if (index < leftLength) {
        while ((unsigned short)carry != 0) {
            unsigned int sum = left[index] + (unsigned short)carry;

            destination[index++] = (unsigned short)sum;
            carry = sum >> 16;
            if (index >= leftLength)
                break;
        }
        while (index < leftLength) {
            destination[index] = left[index];
            index++;
        }
    }
    if (index < rightLength) {
        while ((unsigned short)carry != 0) {
            unsigned int sum = right[index] + (unsigned short)carry;

            destination[index++] = (unsigned short)sum;
            carry = sum >> 16;
            if (index >= rightLength)
                break;
        }
        while (index < rightLength) {
            destination[index] = right[index];
            index++;
        }
    }
    if ((unsigned short)carry != 0) {
        if (*destinationLength < index) {
            *destinationLength = (unsigned short)index;
            return NSCalculationOverflow;
        }
        destination[index] = (unsigned short)carry;
        *destinationLength = (unsigned short)(index + 1);
        return NSCalculationNoError;
    }
    *destinationLength = (unsigned short)index;
    return NSCalculationNoError;
}

int NSIntegerSubtract(unsigned short *destination,
                      unsigned short *destinationLength,
                      const unsigned short *left, unsigned short leftLength,
                      const unsigned short *right,
                      unsigned short rightLength)
{
    unsigned int state = 1;
    unsigned int index = 0;
    unsigned int commonLength = leftLength < rightLength
        ? leftLength : rightLength;

    for (; index < commonLength; index++) {
        unsigned int leftWord = left[index];
        unsigned int rightWord = right[index];
        unsigned int difference = (unsigned short)state + leftWord -
                                  rightWord - 1;

        destination[index] = (unsigned short)difference;
        state = ((unsigned short)state + leftWord - rightWord + 0xffffU)
                >> 16;
    }
    if (index < leftLength) {
        while ((unsigned short)state == 0) {
            unsigned int leftWord = left[index];

            destination[index] = (unsigned short)(leftWord - 1);
            state = (leftWord + 0xffffU) >> 16;
            index++;
            if (index >= leftLength)
                break;
        }
        while (index < leftLength) {
            destination[index] = left[index];
            index++;
        }
    }
    while (index < rightLength) {
        unsigned int rightWord = right[index];
        unsigned int difference = (unsigned short)state - 1 - rightWord;

        destination[index] = (unsigned short)difference;
        state = ((unsigned short)state + 0xffffU - rightWord) >> 16;
        index++;
    }
    *destinationLength = (unsigned short)index;
    if ((unsigned short)state == 0)
        return NSCalculationOverflow;
    while (*destinationLength != 0 &&
           destination[*destinationLength - 1] == 0)
        (*destinationLength)--;
    return NSCalculationNoError;
}

int NSIntegerMaxPowerOf10Multiplier(int, short currentLength,
                                    short maximumLength)
{
    unsigned short lengthDifference =
        (unsigned short)(maximumLength - currentLength);
    double scaled = 4.81647993 * (long double)lengthDifference;

    return (unsigned short)(long long)scaled;
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

int NSIntegerMultiply(unsigned short *destination,
                      unsigned short *destinationLength,
                      const unsigned short *left, unsigned short leftLength,
                      const unsigned short *right,
                      unsigned short rightLength)
{
    unsigned short *product = destination;
    unsigned short index;
    unsigned short leftIndex;
    unsigned short rightIndex;

    if (leftLength == 0 || rightLength == 0) {
        *destinationLength = 0;
        return NSCalculationNoError;
    }
    if (destination == left)
        product = NSZoneMalloc(NULL, 2 * *destinationLength);
    *destinationLength = (unsigned short)(leftLength + rightLength);
    for (index = 0; index < *destinationLength; index++)
        product[index] = 0;

    for (rightIndex = 0; rightIndex < rightLength; rightIndex++) {
        unsigned int carry = 0;

        for (leftIndex = 0; leftIndex < leftLength; leftIndex++) {
            unsigned int value = (unsigned int)left[leftIndex] *
                                 right[rightIndex]
                              + product[leftIndex + rightIndex] + carry;

            product[leftIndex + rightIndex] = (unsigned short)value;
            carry = value >> 16;
        }
        if (carry != 0)
            product[leftIndex + rightIndex] = (unsigned short)carry;
    }
    while (*destinationLength != 0 &&
           product[*destinationLength - 1] == 0)
        (*destinationLength)--;

    if (product != destination) {
        NSIntegerCopy(destination, destinationLength, product,
                      *destinationLength);
        NSZoneFree(NULL, product);
    }
    return NSCalculationNoError;
}

int NSIntegerDivide(unsigned short *destination,
                    unsigned short *destinationLength,
                    const unsigned short *dividend,
                    unsigned short dividendLength,
                    const unsigned short *divisor,
                    unsigned short divisorLength)
{
    unsigned short dividendStack[18];
    unsigned short divisorStack[18];
    unsigned short *normalizedDividend = dividendStack;
    unsigned short *normalizedDivisor = divisorStack;
    unsigned short normalizedDividendLength;
    unsigned short normalizedDivisorLength;
    unsigned short dividendCapacity;
    unsigned short divisorCapacity;
    unsigned short quotientLength;
    unsigned short remainder;
    unsigned short factor;
    unsigned short divisorTop;
    unsigned short divisorNext;
    unsigned short step;
    unsigned int index;
    unsigned int quotientDigit;
    unsigned int quotientRemainder;
    unsigned int numerator;
    unsigned int product;
    unsigned int carry;
    unsigned int borrow;
    unsigned int subtrahend;
    unsigned int word;

    if (divisorLength == 0)
        return NSCalculationDivideByZero;
    if (NSIntegerCompare(dividend, dividendLength, divisor, divisorLength) < 0) {
        *destinationLength = 0;
        return NSCalculationNoError;
    }
    if (divisorLength == 1)
        return NSIntegerDivideByShort(destination, destinationLength,
                                       dividend, dividendLength, divisor[0],
                                       &remainder);

    dividendCapacity = (unsigned short)(dividendLength + 1);
    divisorCapacity = (unsigned short)(divisorLength + 1);
    if (dividendLength > 16)
        normalizedDividend = NSZoneMalloc(NULL, 2 * dividendCapacity);
    if (divisorLength > 16)
        normalizedDivisor = NSZoneMalloc(NULL, 2 * divisorCapacity);

    normalizedDividendLength = dividendCapacity;
    normalizedDivisorLength = divisorCapacity;
    factor = (unsigned short)(0x10000U /
                              ((unsigned int)divisor[divisorLength - 1] + 1));
    NSIntegerMultiplyByShort(normalizedDividend, &normalizedDividendLength,
                             dividend, dividendLength, factor);
    NSIntegerMultiplyByShort(normalizedDivisor, &normalizedDivisorLength,
                             divisor, divisorLength, factor);

    if (normalizedDividendLength == dividendLength)
        normalizedDividend[normalizedDividendLength++] = 0;
    normalizedDivisor[normalizedDivisorLength] = 0;

    quotientLength = (unsigned short)(normalizedDividendLength -
                                      normalizedDivisorLength);
    divisorTop = normalizedDivisor[normalizedDivisorLength - 1];
    divisorNext = normalizedDivisorLength > 1
        ? normalizedDivisor[normalizedDivisorLength - 2] : 0;

    for (step = 0; step < quotientLength; step++) {
        unsigned short position =
            (unsigned short)(normalizedDividendLength - step - 1);
        unsigned short outputIndex = (unsigned short)(quotientLength - step - 1);
        unsigned int originalDigit;

        numerator = ((unsigned int)normalizedDividend[position] << 16) |
                    normalizedDividend[position - 1];
        quotientDigit = numerator / divisorTop;
        quotientRemainder = numerator % divisorTop;
        originalDigit = quotientDigit;
        if (quotientDigit == 0x10000U ||
            quotientDigit * divisorNext >
                (quotientRemainder << 16) + normalizedDividend[position - 2]) {
            quotientDigit--;
            quotientRemainder += divisorTop;
            if (quotientRemainder <= 0xffffU &&
                (originalDigit == 0x10001U ||
                 quotientDigit * divisorNext >
                    (quotientRemainder << 16) +
                    normalizedDividend[position - 2]))
                quotientDigit--;
        }

        carry = 0;
        borrow = 0;
        for (index = 0; index <= normalizedDivisorLength; index++) {
            product = quotientDigit * normalizedDivisor[index] + carry;
            carry = product >> 16;
            subtrahend = (product & 0xffffU) + borrow;
            word = normalizedDividend[position - normalizedDivisorLength +
                                      index];
            normalizedDividend[position - normalizedDivisorLength + index] =
                (unsigned short)(word - subtrahend);
            borrow = word < subtrahend;
        }

        if (borrow != 0) {
            quotientDigit--;
            carry = 0;
            for (index = 0; index <= normalizedDivisorLength; index++) {
                word = normalizedDividend[position - normalizedDivisorLength +
                                          index] +
                       normalizedDivisor[index] + carry;
                normalizedDividend[position - normalizedDivisorLength + index] =
                    (unsigned short)word;
                carry = word >> 16;
            }
        }
        destination[outputIndex] = (unsigned short)quotientDigit;
    }

    *destinationLength = quotientLength;
    while (*destinationLength != 0 &&
           destination[*destinationLength - 1] == 0)
        (*destinationLength)--;

    if (normalizedDivisor != divisorStack)
        NSZoneFree(NULL, normalizedDivisor);
    if (normalizedDividend != dividendStack)
        NSZoneFree(NULL, normalizedDividend);
    return NSCalculationNoError;
}

static unsigned short
NSDecimalBuildPowerOfTen(unsigned short words[8], unsigned power)
{
    unsigned short length = 1;
    unsigned index;

    words[0] = 1;
    for (index = 0; index < power; index++) {
        unsigned int carry = 0;
        unsigned short word;

        for (word = 0; word < length; word++) {
            unsigned int product = (unsigned int)words[word] * 10 + carry;

            words[word] = (unsigned short)product;
            carry = product >> 16;
        }
        if (carry != 0)
            words[length++] = (unsigned short)carry;
    }
    return length;
}

#if defined(__ppc__) || defined(__POWERPC__)
#include "NSDecimalPowerTablePPCRaw.inc"
#include "NSDecimalPowerTablePPCSHRTMin.inc"
#else
#include "NSDecimalPowerTableI386Raw.inc"
#include "NSDecimalPowerTableI386SHRTMin.inc"
#endif

/*  Models the divisor rows read by the reference. The raw snapshots cover
    every complete count-sized span for indices 39 through 32729. Return 0
    for a zero count, 1 for a nonzero count, or 3 outside that range.  */
static int
NSDecimalReferencePowerTableDivisor(unsigned power,
                                    const unsigned short **divisor,
                                    unsigned short *divisorLength)
{
    unsigned index;

    if (power < 39 || power > 32729)
        return 3;
#if defined(__ppc__) || defined(__POWERPC__)
    index = 9 * (power - 39);
    *divisorLength = NSDecimalPPCRawPowerTable[index];
    *divisor = NSDecimalPPCRawPowerTable + index + 1;
#else
    index = 9 * (power - 39);
    *divisorLength = NSDecimalI386RawPowerTable[index];
    *divisor = NSDecimalI386RawPowerTable + index + 1;
#endif
    return *divisorLength == 0 ? 0 : 1;
}

static int
NSDecimalPositivePowerTableSpansAvailable(unsigned power)
{
    const unsigned short *divisor;
    unsigned short divisorLength;
    unsigned remaining = power;

    if (power > 32767)
        return 0;
    while (remaining > 38) {
        remaining -= 38;
        if (remaining > 38 &&
            NSDecimalReferencePowerTableDivisor(
                remaining, &divisor, &divisorLength) > 1)
            return 0;
    }
    return 1;
}

static int
NSDecimalMappedNegativePowerAvailable(unsigned power,
                                     unsigned short currentLength,
                                     unsigned short capacity)
{
    const unsigned short *divisor;
    unsigned short divisorLength;
    unsigned remaining = power;

    if (power > 32767)
        return 0;
    while (remaining > 38) {
        int divisorKind;

        remaining -= 38;
        if (remaining <= 38)
            break;
        divisorKind = NSDecimalReferencePowerTableDivisor(
            remaining, &divisor, &divisorLength);
        if (divisorKind == 0)
            currentLength = capacity;
        else if (divisorKind != 1)
            return 0;
        else if (divisorLength > currentLength)
            currentLength = 0;
    }
    return remaining <= 38;
}

/*  Scales a little-endian mantissa by a power of ten.  The reference uses
    table entries in 10^38 chunks; 10^38 occupies eight 16-bit words.  The
    positive path checks the same upper-bound word count before writing.  */
int
NSIntegerMultiplyByPowerOf10(unsigned short *destination,
                             unsigned short *destinationLength,
                             const unsigned short *source,
                             unsigned short sourceLength, short power)
{
    unsigned short capacity = *destinationLength;
    unsigned short powerOfTen[8];
    unsigned short remainderPowerOfTen[8];
    unsigned short powerOfTenLength;
    unsigned short remainderPowerOfTenLength;
    unsigned short currentLength;
    unsigned short outOfTableDivisorLength;
    const unsigned short *outOfTableDivisor;
    unsigned short requiredLength;
    int remaining;
    int result;

    if (destination != source)
        NSIntegerCopy(destination, destinationLength, source, sourceLength);
    if (power == 0)
        return NSCalculationNoError;

    if (power == (short)(-32767 - 1)) {
#if defined(__ppc__) || defined(__POWERPC__)
        outOfTableDivisor = NSDecimalPPCSHRTMinRead + 1;
        outOfTableDivisorLength = NSDecimalPPCSHRTMinRead[0];
#else
        outOfTableDivisor = NSDecimalI386SHRTMinRead + 1;
        outOfTableDivisorLength = NSDecimalI386SHRTMinRead[0];
#endif
        return NSIntegerDivide(destination, destinationLength,
                               source, sourceLength, outOfTableDivisor,
                               outOfTableDivisorLength);
    }

    if (power > 0) {
        remaining = power;
        requiredLength = sourceLength;
        while (remaining > 38) {
            requiredLength = (unsigned short)(requiredLength + 8);
            remaining -= 38;
        }
        remainderPowerOfTenLength =
            NSDecimalBuildPowerOfTen(remainderPowerOfTen,
                                     (unsigned)remaining);
        requiredLength = (unsigned short)(requiredLength +
                                          remainderPowerOfTenLength);
        if ((short)capacity < (short)requiredLength)
            return NSCalculationOverflow;

        remaining = power;
        if (remaining <= 76) {
            while (remaining > 38) {
                currentLength = *destinationLength;
                *destinationLength = capacity;
                remaining -= 38;
                remainderPowerOfTenLength =
                    NSDecimalBuildPowerOfTen(remainderPowerOfTen,
                                             (unsigned)remaining);
                result = NSIntegerMultiply(destination, destinationLength,
                                           destination, currentLength,
                                           remainderPowerOfTen,
                                           remainderPowerOfTenLength);
                (void)result; /* The reference ignores loop-multiply errors. */
            }
            remainderPowerOfTenLength =
                NSDecimalBuildPowerOfTen(remainderPowerOfTen,
                                         (unsigned)remaining);
            *destinationLength = capacity;
            return NSIntegerMultiply(destination, destinationLength,
                                     source, sourceLength,
                                     remainderPowerOfTen,
                                     remainderPowerOfTenLength);
        }

        if (NSDecimalPositivePowerTableSpansAvailable(
                (unsigned)remaining)) {
            remaining = power;
            while (remaining > 38) {
                currentLength = *destinationLength;
                *destinationLength = capacity;
                remaining -= 38;
                if (remaining > 38) {
                    NSDecimalReferencePowerTableDivisor(
                        (unsigned)remaining, &outOfTableDivisor,
                        &outOfTableDivisorLength);
                    result = NSIntegerMultiply(destination,
                                               destinationLength,
                                               destination, currentLength,
                                               outOfTableDivisor,
                                               outOfTableDivisorLength);
                } else {
                    remainderPowerOfTenLength =
                        NSDecimalBuildPowerOfTen(remainderPowerOfTen,
                                                 (unsigned)remaining);
                    result = NSIntegerMultiply(destination,
                                               destinationLength,
                                               destination, currentLength,
                                               remainderPowerOfTen,
                                               remainderPowerOfTenLength);
                    (void)result;
                }
                (void)result;
            }
            remainderPowerOfTenLength =
                NSDecimalBuildPowerOfTen(remainderPowerOfTen,
                                         (unsigned)remaining);
            *destinationLength = capacity;
            return NSIntegerMultiply(destination, destinationLength,
                                     source, sourceLength,
                                     remainderPowerOfTen,
                                     remainderPowerOfTenLength);
        }

        if (remaining > 38)
            powerOfTenLength = NSDecimalBuildPowerOfTen(powerOfTen, 38);
        while (remaining > 38) {
            currentLength = *destinationLength;
            *destinationLength = capacity;
            result = NSIntegerMultiply(destination, destinationLength,
                                       destination, currentLength,
                                       powerOfTen, powerOfTenLength);
            if (result != NSCalculationNoError)
                return result;
            remaining -= 38;
        }
        remainderPowerOfTenLength =
            NSDecimalBuildPowerOfTen(remainderPowerOfTen,
                                     (unsigned)remaining);
        currentLength = *destinationLength;
        *destinationLength = capacity;
        return NSIntegerMultiply(destination, destinationLength,
                                 destination, currentLength,
                                 remainderPowerOfTen,
                                 remainderPowerOfTenLength);
    }

    remaining = -(int)power;
    if (NSDecimalMappedNegativePowerAvailable(
            (unsigned)remaining, *destinationLength, capacity)) {
        while (remaining > 38) {
            int divisorKind;

            currentLength = *destinationLength;
            *destinationLength = capacity;
            remaining -= 38;
            if (remaining <= 38) {
                remainderPowerOfTenLength =
                    NSDecimalBuildPowerOfTen(remainderPowerOfTen,
                                             (unsigned)remaining);
                result = NSIntegerDivide(destination, destinationLength,
                                         destination, currentLength,
                                         remainderPowerOfTen,
                                         remainderPowerOfTenLength);
            } else {
                divisorKind = NSDecimalReferencePowerTableDivisor(
                    (unsigned)remaining, &outOfTableDivisor,
                    &outOfTableDivisorLength);
                if (divisorKind == 0) {
                    result = NSIntegerDivide(destination, destinationLength,
                                             destination, currentLength,
                                             NULL, 0);
                } else if (divisorKind == 1) {
                    result = NSIntegerDivide(destination, destinationLength,
                                             destination, currentLength,
                                             outOfTableDivisor,
                                             outOfTableDivisorLength);
                } else {
                    *destinationLength = 0;
                    result = NSCalculationNoError;
                }
            }
            (void)result; /* The reference ignores loop-divide errors. */
        }
        remainderPowerOfTenLength =
            NSDecimalBuildPowerOfTen(remainderPowerOfTen,
                                     (unsigned)remaining);
        return NSIntegerDivide(destination, destinationLength,
                               source, sourceLength, remainderPowerOfTen,
                               remainderPowerOfTenLength);
    } else {
        powerOfTenLength = NSDecimalBuildPowerOfTen(powerOfTen, 38);
        while (remaining > 38) {
            currentLength = *destinationLength;
            result = NSIntegerDivide(destination, destinationLength,
                                     destination, currentLength,
                                     powerOfTen, powerOfTenLength);
            if (result != NSCalculationNoError)
                return result;
            remaining -= 38;
        }
    }
    remainderPowerOfTenLength =
        NSDecimalBuildPowerOfTen(remainderPowerOfTen,
                                 (unsigned)remaining);
    currentLength = *destinationLength;
    return NSIntegerDivide(destination, destinationLength,
                           destination, currentLength,
                           remainderPowerOfTen,
                           remainderPowerOfTenLength);
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
        return digit >= 5;
    default:
        return 0;
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

#if defined(__ppc__) || defined(__POWERPC__)
    *(unsigned int *)destination &= 0xFFFC0000U;
#else
    destination->_reserved = 0;
#endif
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

static int
NSDecimalAppendDigit(NSDecimal *number, unsigned short digit)
{
    NSDecimal previous = *number;
    unsigned short length = NSDecimalMaxSize;

    if (NSIntegerMultiplyByShort(number->_mantissa, &length,
                                 number->_mantissa, number->_length, 10) !=
        NSCalculationNoError) {
        *number = previous;
        return 0;
    }
    number->_length = length;
    length = NSDecimalMaxSize;
    if (NSIntegerAddShort(number->_mantissa, &length, number->_mantissa,
                          number->_length, digit) != NSCalculationNoError) {
        *number = previous;
        return 0;
    }
    number->_length = length;
    return 1;
}

NSDecimal *
_NSCStringToDecimal(NSDecimal *result, const char *string,
                    const char **endPointer)
{
    NSDecimal number;
    const unsigned char *cursor = (const unsigned char *)string;
    int overflowed = 0;

    memset(&number, 0, sizeof(number));
    if (endPointer != NULL)
        *endPointer = string;

    while (*cursor == ' ' || (*cursor >= '\t' && *cursor <= '\r'))
        cursor++;

    if (*cursor == '-') {
        number._isNegative = 1;
        cursor++;
    } else if (*cursor == '+') {
        cursor++;
    }

    while (*cursor != '\0' && *cursor >= '0' && *cursor <= '9') {
        if (!overflowed &&
            !NSDecimalAppendDigit(&number, (unsigned short)(*cursor - '0')))
            overflowed = 1;
        if (overflowed) {
            if (number._exponent == 127)
                goto overflow;
            number._exponent++;
        }
        cursor++;
    }

    if (*cursor == '.') {
        cursor++;
        while (*cursor != '\0' && *cursor >= '0' && *cursor <= '9') {
            if (!overflowed &&
                !NSDecimalAppendDigit(&number,
                                      (unsigned short)(*cursor - '0'))) {
                overflowed = 1;
            } else if (!overflowed) {
                if (number._exponent == -128)
                    goto overflow;
                number._exponent--;
            }
            cursor++;
        }
    }

    if (*cursor == 'e' || *cursor == 'E') {
        int exponent = 0;
        int exponentNegative = 0;
        int adjustedExponent;
        unsigned char exponentChar;

        cursor++;
        if (*cursor == '-') {
            exponentNegative = 1;
            cursor++;
        } else if (*cursor == '+') {
            cursor++;
        }
        while ((exponentChar = *cursor) != '\0' &&
               exponentChar >= '0' && exponentChar <= '9') {
            exponent = exponent * 10 + exponentChar - '0';
            cursor++;
            if (exponent > 254)
                goto overflow;
        }
        if (exponentNegative)
            exponent = -exponent;
        adjustedExponent = number._exponent + exponent;
        if (adjustedExponent < -128 || adjustedExponent > 127)
            goto overflow;
        number._exponent = adjustedExponent;
    }

    NSDecimalCompact(&number);
    if (endPointer != NULL)
        *endPointer = (const char *)cursor;
    *result = number;
    return result;

overflow:
    number._length = 0;
    number._isNegative = 1;
    *result = number;
    return result;
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

static BOOL
NSDecimalRoundShouldIncrement(NSRoundingMode roundingMode, BOOL isNegative,
                              int digit, BOOL keptIsOdd)
{
    switch (roundingMode) {
    case NSRoundDown:
        return isNegative && digit != 0;
    case NSRoundUp:
        return !isNegative && digit != 0;
    case NSRoundBankers:
        return digit > 5 || (digit == 5 &&
            (isNegative ? !keptIsOdd : keptIsOdd));
    case NSRoundPlain:
        return digit >= 5;
    default:
        return NO;
    }
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
        if (NSDecimalRoundShouldIncrement(roundingMode, number->_isNegative,
                                          digit, (value.words[0] & 1) != 0))
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
    NSDecimal savedLarger;
    unsigned short destinationLength = NSDecimalMaxSize;
    short maxPower;
    int difference;

    (void)roundingMode;
    difference = (int)number1->_exponent - (int)number2->_exponent;
    if (difference == 0)
        return NSCalculationNoError;

    if (difference >= 0) {
        larger = number1;
        smaller = number2;
    } else {
        larger = number2;
        smaller = number1;
        difference = -difference;
    }

    NSDecimalCopy(&savedLarger, larger);
    if (NSIntegerMultiplyByPowerOf10(larger->_mantissa, &destinationLength,
                                    larger->_mantissa, larger->_length,
                                    (short)difference)
        == NSCalculationNoError) {
        larger->_length = destinationLength;
        larger->_exponent = smaller->_exponent;
        larger->_isCompact = 0;
        return NSCalculationNoError;
    }

    NSDecimalCopy(larger, &savedLarger);
    maxPower = (short)NSIntegerMaxPowerOf10Multiplier(
        (int)larger->_mantissa, larger->_length, NSDecimalMaxSize);
    destinationLength = NSDecimalMaxSize;
    NSIntegerMultiplyByPowerOf10(smaller->_mantissa, &destinationLength,
                                 smaller->_mantissa, smaller->_length,
                                 (short)(maxPower - difference));
    smaller->_length = destinationLength;
    smaller->_exponent -= (short)(maxPower - difference);
    smaller->_isCompact = 0;

    if (smaller->_length != 0) {
        destinationLength = NSDecimalMaxSize;
        NSIntegerMultiplyByPowerOf10(larger->_mantissa, &destinationLength,
                                     larger->_mantissa, larger->_length,
                                     maxPower);
        larger->_length = destinationLength;
        larger->_exponent -= maxPower;
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
    unsigned short dividend[16];
    unsigned short dividendLength = 16;
    unsigned short remainder = 0;
    BOOL lostRemainder = NO;
    int exponent = 0;

    (void)roundingMode;
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
    NSIntegerMultiplyByPowerOf10(dividend, &dividendLength,
                                 leftOperand->_mantissa, leftOperand->_length,
                                 38);
    NSIntegerDivide(dividend, &dividendLength, dividend, dividendLength,
                    rightOperand->_mantissa, rightOperand->_length);

    if (dividendLength > NSDecimalMaxSize) {
        while (dividendLength > NSDecimalMaxSize + 1) {
            if (remainder != 0)
                lostRemainder = YES;
            NSIntegerDivideByShort(dividend, &dividendLength,
                                   dividend, dividendLength, 10000,
                                   &remainder);
            exponent += 4;
        }
        while (dividendLength > NSDecimalMaxSize) {
            if (remainder != 0)
                lostRemainder = YES;
            NSIntegerDivideByShort(dividend, &dividendLength,
                                   dividend, dividendLength, 10,
                                   &remainder);
            exponent++;
        }
        if (lostRemainder && (remainder == 0 || remainder == 5))
            remainder++;
    }

    exponent += -38 + (int)leftOperand->_exponent -
                (int)rightOperand->_exponent;
    if (exponent < -128) {
        SetNotANumber(result);
        return NSCalculationUnderflow;
    }
    if (exponent > 127) {
        SetNotANumber(result);
        return NSCalculationOverflow;
    }

    NSIntegerCopy(result->_mantissa, &dividendLength,
                  dividend, dividendLength);
    result->_length = dividendLength;
    result->_isNegative = (leftOperand->_isNegative != rightOperand->_isNegative);
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

static char *DecimalToString(const NSDecimal *decimal, char separator,
                             char *buffer, int bufferSize)
{
    NSDecimal value;
    unsigned short length, remainder;
    int index;

    if (NSDecimalIsNotANumber(decimal)) {
        buffer[0] = 'N';
        buffer[1] = 'a';
        buffer[2] = 'N';
        buffer[3] = '\0';
        return buffer;
    }
    if (decimal->_length == 0) {
        buffer[0] = '0';
        buffer[1] = '\0';
        return buffer;
    }

    NSDecimalCopy(&value, decimal);
    index = bufferSize - 1;
    buffer[index] = '\0';
    while (value._exponent > 0) {
        buffer[--index] = '0';
        value._exponent--;
    }
    if (value._exponent == 0)
        value._exponent = 1;

    while (value._length != 0) {
        if (++value._exponent == 1)
            buffer[--index] = separator;
        length = NSDecimalMaxSize;
        NSIntegerDivideByShort(value._mantissa, &length,
                               value._mantissa, value._length, 10,
                               &remainder);
        value._length = length;
        buffer[--index] = (char)('0' + remainder);
    }

    if (value._exponent <= 0) {
        while (value._exponent != 0) {
            buffer[--index] = '0';
            value._exponent++;
        }
        buffer[--index] = separator;
        buffer[--index] = '0';
    }
    if (value._isNegative)
        buffer[--index] = '-';
    return &buffer[index];
}

NSString *
NSDecimalString(const NSDecimal *decimal, NSDictionary *locale)
{
    char buffer[200];
    char *text;
    char separator;
    unsigned length;

    separator = '.';
    if (locale != nil) {
        id separatorString = [locale objectForKey:NSDecimalSeparator];
        if (separatorString != nil)
            separator = (char)[separatorString characterAtIndex:0];
    }

    text = DecimalToString(decimal, separator, buffer, sizeof(buffer));
    for (length = 0; text[length] != '\0'; length++)
        ;
    return [NSString stringWithCString:text length:length];
}
