/*	NSStrtod.m
	PPC Foundation decimal-to-double conversion.
*/

#import <Foundation/NSBigint.h>

#include <errno.h>
#include <math.h>
#include <string.h>

#if defined(__ppc__) || defined(__POWERPC__)

static const double NSStrtodTinyTens[5] = {
	1.0e-16,	1.0e-32,	1.0e-64,	1.0e-128,	1.0e-256
};

static unsigned int
NSStrtodHighWord(double value)
{
	unsigned long long bits;

	memcpy(&bits, &value, sizeof(bits));
	return (unsigned int)(bits >> 32);
}

static unsigned int
NSStrtodLowWord(double value)
{
	unsigned long long bits;

	memcpy(&bits, &value, sizeof(bits));
	return (unsigned int)bits;
}

static double
NSStrtodSetHighWord(double value, unsigned int highWord)
{
	unsigned long long bits;

	memcpy(&bits, &value, sizeof(bits));
	bits = ((unsigned long long)highWord << 32) | (unsigned int)bits;
	memcpy(&value, &bits, sizeof(value));
	return value;
}

static double
NSStrtodSetLowWord(double value, unsigned int lowWord)
{
	unsigned long long bits;

	memcpy(&bits, &value, sizeof(bits));
	bits = (bits & 0xffffffff00000000ULL) | lowWord;
	memcpy(&value, &bits, sizeof(value));
	return value;
}

static double
NSStrtodRatio(NSBigint *numerator, NSBigint *denominator)
{
	int exponentNumerator;
	int exponentDenominator;
	int exponentDifference;
	double top = NSBigintB2D(numerator, &exponentNumerator);
	double bottom = NSBigintB2D(denominator, &exponentDenominator);

	exponentDifference = exponentNumerator - exponentDenominator
			+ 32 * (numerator->wds - denominator->wds);
	if (exponentDifference <= 0) {
		unsigned int high = NSStrtodHighWord(bottom);
		high -= (unsigned int)(exponentDifference * 0x100000);
		bottom = NSStrtodSetHighWord(bottom, high);
	} else {
		unsigned int high = NSStrtodHighWord(top);
		high += (unsigned int)(exponentDifference * 0x100000);
		top = NSStrtodSetHighWord(top, high);
	}
	return top / bottom;
}

static double
NSStrtodULP(double value)
{
	unsigned int high = NSStrtodHighWord(value);
	unsigned int exponent = high & 0x7ff00000U;
	unsigned int resultHigh;
	unsigned int resultLow;
	int shift;
	unsigned long long bits;
	double result;

	if (exponent <= 0x03400000U) {
		shift = (0x03400000U - exponent) >> 20;
		if (shift > 19) {
			int lowShift = shift - 20;
			resultHigh = 0;
			resultLow = lowShift > 30 ? 1 : 1U << (31 - lowShift);
		} else {
			resultHigh = 0x80000U >> shift;
			resultLow = 0;
		}
	} else {
		resultHigh = exponent - 0x03400000U;
		resultLow = 0;
	}
	bits = ((unsigned long long)resultHigh << 32) | resultLow;
	memcpy(&result, &bits, sizeof(result));
	return result;
}

static NSBigint *
NSStrtodS2B(const char *digits, int initialDigits, int totalDigits,
			unsigned int firstNineDigits)
{
	int groups = (totalDigits + 8) / 9;
	int sizeClass = 0;
	int capacity = 1;
	int count = 9;
	const char *cursor;
	NSBigint *value;

	while (groups > capacity) {
		capacity *= 2;
		++sizeClass;
	}
	value = NSBigintBalloc(sizeClass);
	value->x[0] = firstNineDigits;
	value->wds = 1;
	if (initialDigits <= 9) {
		cursor = digits + 10;
	} else {
		cursor = digits + 9;
		do {
			value = NSBigintMultAdd(value, 10,
					(unsigned int)((unsigned char)*cursor++ - '0'));
			++count;
		} while (count < initialDigits);
		++cursor;
	}
	while (count < totalDigits) {
		value = NSBigintMultAdd(value, 10,
				(unsigned int)((unsigned char)*cursor++ - '0'));
		++count;
	}
	return value;
}

double
_NSstrtod(const char *string, char **endPointer)
{
	const unsigned char *original = (const unsigned char *)string;
	const unsigned char *cursor = original;
	const unsigned char *significantStart;
	const unsigned char *exponentStart;
	unsigned int firstNine = 0, nextSeven = 0, digit;
	unsigned int word;
	int negative = 0, hadLeadingZero = 0, noToken = 0;
	int zeroRun = 0, fractionPlaces = 0, initialDigits, digits = 0;
	int exponent = 0, exponentNegative = 0, exponentDigits;
	int decimalExponent, keptDigits, scale, scaleMagnitude, powerIndex;
	int estimateExponent, bitCount, estimateShift;
	int leftShift, rightShift, denominatorShift, commonShift;
	int adjustment, comparison, differenceSign, direction;
	int i;
	double value = 0.0, previous, remainder, fraction, tieFraction;
	NSBigint *base = 0, *binary = 0, *denominator = 0, *one = 0;
	NSBigint *difference = 0, *copy;

	while (*cursor == '\t' || *cursor == '\n' || *cursor == '\v'
			|| *cursor == '\f' || *cursor == '\r' || *cursor == ' ')
		++cursor;
	if (*cursor == '-')
		negative = 1;
	if (*cursor == '-' || *cursor == '+')
		++cursor;
	if (*cursor == 0) {
		noToken = 1;
		goto finish;
	}
	if (*cursor == '0') {
		hadLeadingZero = 1;
		do {
			++cursor;
		} while (*cursor == '0');
		if (*cursor == 0)
			goto finish;
	}

	significantStart = cursor;
	while (*cursor >= '0' && *cursor <= '9') {
		digit = *cursor - '0';
		if (digits < 9)
			firstNine = firstNine * 10 + digit;
		else if (digits < 16)
			nextSeven = nextSeven * 10 + digit;
		++digits;
		++cursor;
	}
	initialDigits = digits;
	if (*cursor == '.') {
		++cursor;
		if (digits == 0) {
			while (*cursor == '0') {
				++zeroRun;
				++cursor;
			}
			if (*cursor >= '1' && *cursor <= '9') {
				significantStart = cursor;
				fractionPlaces = zeroRun;
				zeroRun = 0;
			}
		}
		while (*cursor >= '0' && *cursor <= '9') {
			++zeroRun;
			digit = *cursor - '0';
			if (digit != 0) {
				fractionPlaces += zeroRun;
				for (i = 1; i < zeroRun; ++i) {
					if (digits++ > 8) {
						if (digits <= 16)
							nextSeven *= 10;
					} else
						firstNine *= 10;
				}
				if (digits++ > 8) {
					if (digits <= 16)
						nextSeven = nextSeven * 10 + digit;
				} else
					firstNine = firstNine * 10 + digit;
				zeroRun = 0;
			}
			++cursor;
		}
	}

	if (*cursor == 'e' || *cursor == 'E') {
		if (digits == 0 && zeroRun == 0 && !hadLeadingZero) {
			noToken = 1;
			goto finish;
		}
		exponentStart = cursor++;
		if (*cursor == '+' || *cursor == '-') {
			exponentNegative = (*cursor == '-');
			++cursor;
		}
		if (*cursor < '0' || *cursor > '9')
			cursor = exponentStart;
		else {
			while (*cursor == '0')
				++cursor;
			if (*cursor >= '1' && *cursor <= '9') {
				exponent = *cursor++ - '0';
				exponentDigits = 1;
				while (*cursor >= '0' && *cursor <= '9') {
					if (exponentDigits < 9)
						exponent = exponent * 10 + *cursor - '0';
					++cursor;
					++exponentDigits;
				}
				if (exponentDigits > 8 || exponent > 19999)
					exponent = 19999;
				if (exponentNegative)
					exponent = -exponent;
			}
		}
	}
	if (digits == 0) {
		if (zeroRun != 0 || hadLeadingZero)
			goto finish;
		noToken = 1;
		goto finish;
	}

	decimalExponent = exponent - fractionPlaces;
	if (initialDigits == 0)
		initialDigits = digits;
	keptDigits = digits > 16 ? 16 : digits;
	value = (double)firstNine;
	if (keptDigits > 9)
		value = (double)firstNine * NSBigintTens[keptDigits - 9]
				+ (double)nextSeven - 4503599627370496.0;
	if (digits <= 15) {
		if (decimalExponent == 0)
			goto finish;
		if (decimalExponent < 0 && decimalExponent >= -22) {
			value /= NSBigintTens[-decimalExponent];
			goto finish;
		}
		if (decimalExponent > 0 && decimalExponent <= 22) {
			value *= NSBigintTens[decimalExponent];
			goto finish;
		}
		if (decimalExponent > 22
				&& decimalExponent <= 15 - digits + 22) {
			value = value * NSBigintTens[15 - digits]
					* NSBigintTens[decimalExponent - (15 - digits)];
			goto finish;
		}
	}

	scale = decimalExponent + digits - keptDigits;
	if (scale < 0) {
		scaleMagnitude = -scale;
		if ((scaleMagnitude & 15) != 0)
			value /= NSBigintTens[scaleMagnitude & 15];
		scaleMagnitude &= ~15;
		if (scaleMagnitude != 0) {
			powerIndex = scaleMagnitude >> 4;
			if (powerIndex > 31)
				goto underflow;
			for (i = 0; powerIndex > 1; powerIndex >>= 1) {
				if (powerIndex & 1)
					value *= NSStrtodTinyTens[i];
				++i;
			}
			previous = value;
			value *= NSStrtodTinyTens[i];
			if (value == 0.0) {
				if ((previous + previous) * NSStrtodTinyTens[i] == 0.0)
					goto underflow;
				value = NSStrtodSetHighWord(value, 0);
				value = NSStrtodSetLowWord(value, 1);
				goto correctionStart;
			}
		}
	} else if (scale > 0) {
		if ((scale & 15) != 0)
			value *= NSBigintTens[scale & 15];
		scale &= 0x7ffffff0;
		if (scale != 0) {
			if (scale > 308)
				goto overflow;
			powerIndex = scale >> 4;
			if (powerIndex != 0) {
				for (i = 0; powerIndex > 1; powerIndex >>= 1) {
					if (powerIndex & 1)
						value *= NSBigintBigTens[i];
					++i;
				}
				value = NSStrtodSetHighWord(value,
						NSStrtodHighWord(value) - 55574528U);
				value *= NSBigintBigTens[i];
				word = NSStrtodHighWord(value) & 0x7ff00000U;
				if (word > 0x7ca00000U)
					goto overflow;
				if (word > 0x7c900000U) {
					value = NSStrtodSetHighWord(value, 0x7fefffffU);
					value = NSStrtodSetLowWord(value, 0xffffffffU);
					goto correctionStart;
				}
				value = NSStrtodSetHighWord(value,
						NSStrtodHighWord(value) + 55574528U);
			}
		}
	}

correctionStart:
	base = NSStrtodS2B((const char *)significantStart, initialDigits,
			digits, firstNine);
	for (;;) {
		denominator = NSBigintBalloc(base->k);
		memmove(denominator->x, base->x,
				(unsigned)(sizeof(unsigned int) * base->wds));
		denominator->wds = base->wds;
		binary = NSBigintD2B(value, &estimateExponent, &bitCount);
		one = NSBigintI2B(1);
		if (decimalExponent < 0) {
			adjustment = -decimalExponent;
			leftShift = adjustment;
			rightShift = 0;
		} else {
			adjustment = 0;
			leftShift = 0;
			rightShift = decimalExponent;
		}
		if (estimateExponent < 0)
			rightShift -= estimateExponent;
		else
			leftShift += estimateExponent;
		denominatorShift = leftShift;
		if (estimateExponent + bitCount - 1 >= -1022)
			estimateShift = 54 - bitCount;
		else
			estimateShift = estimateExponent + 1075;
		leftShift += estimateShift;
		rightShift += estimateShift;
		commonShift = leftShift;
		if (leftShift > rightShift)
			commonShift = rightShift;
		if (commonShift > denominatorShift)
			commonShift = denominatorShift;
		if (commonShift > 0) {
			leftShift -= commonShift;
			rightShift -= commonShift;
			denominatorShift -= commonShift;
		}
		if (adjustment > 0) {
			one = NSBigintPow5Mult(one, adjustment);
			copy = NSBigintMult(one, binary);
			NSBigintBfree(binary);
			binary = copy;
		}
		if (leftShift > 0)
			binary = NSBigintLShift(binary, leftShift);
		if (rightShift > 0)
			denominator = NSBigintPow5Mult(denominator, rightShift);
		if (rightShift > 0)
			denominator = NSBigintLShift(denominator, rightShift);
		if (denominatorShift > 0)
			one = NSBigintLShift(one, denominatorShift);
		difference = NSBigintDiff(binary, denominator);
		comparison = difference->sign;
		difference->sign = 0;
		differenceSign = comparison;
		comparison = NSBigintCompare(difference, one);
		if (comparison < 0) {
			if (differenceSign != 0 || NSStrtodLowWord(value) != 0
					|| (NSStrtodHighWord(value) & 0xfffffU) != 0)
				goto corrected;
			difference = NSBigintLShift(difference, 1);
			if (NSBigintCompare(difference, one) > 0) {
				value = NSStrtodSetHighWord(value,
						(NSStrtodHighWord(value) & 0x7ff00000U) - 0x100000U);
				value = NSStrtodSetHighWord(value,
						NSStrtodHighWord(value) | 0x000fffffU);
				value = NSStrtodSetLowWord(value, 0xffffffffU);
			}
			goto corrected;
		}
		if (comparison == 0)
			break;
		remainder = NSStrtodRatio(difference, one);
		if (remainder > 2.0) {
			fraction = remainder * 0.5;
			direction = differenceSign ? 1 : -1;
		} else if (differenceSign) {
			fraction = 1.0;
			direction = 1;
		} else if (NSStrtodLowWord(value) == 0
				&& (NSStrtodHighWord(value) & 0xfffffU) == 0) {
			fraction = remainder >= 1.0 ? remainder * 0.5 : 0.5;
			direction = -1;
		} else {
			if ((((unsigned long long)NSStrtodHighWord(value) << 32)
					| NSStrtodLowWord(value)) == 1)
				goto rangeUnderflow;
			fraction = 1.0;
			direction = -1;
		}
		tieFraction = fraction;
		word = NSStrtodHighWord(value) & 0x7ff00000U;
		if (word == 0x7fe00000U) {
			previous = value;
			value = NSStrtodSetHighWord(value,
					NSStrtodHighWord(value) - 55574528U);
			value += direction * fraction * NSStrtodULP(value);
			if ((NSStrtodHighWord(value) & 0x7ff00000U) > 0x7c9fffffU) {
				if (previous == 1.797693134862316e308)
					goto overflow;
				value = 1.797693134862316e308;
				goto iterationDone;
			}
			value = NSStrtodSetHighWord(value,
					NSStrtodHighWord(value) + 55574528U);
		} else {
			if (word <= 0x03400000U && fraction >= 1.0) {
				fraction = (double)(int)(fraction + 0.5);
				direction = differenceSign ? 1 : -1;
			}
			value += direction * fraction * NSStrtodULP(value);
		}
		if (word == (NSStrtodHighWord(value) & 0x7ff00000U)) {
			remainder = tieFraction - (double)(int)tieFraction;
			if (differenceSign || NSStrtodLowWord(value) != 0
					|| (NSStrtodHighWord(value) & 0xfffffU) != 0) {
				if (remainder < 0.4999999 || remainder > 0.5000001)
					goto corrected;
			} else if (remainder < 0.24999995)
				goto corrected;
		}
iterationDone:
		NSBigintBfree(binary);
		NSBigintBfree(denominator);
		NSBigintBfree(one);
		NSBigintBfree(difference);
	}
	if (!differenceSign) {
		if ((NSStrtodHighWord(value) & 0xfffffU) != 0
				|| NSStrtodLowWord(value) != 0)
			goto tieCheck;
		value = NSStrtodSetHighWord(value,
				(NSStrtodHighWord(value) & 0x7ff00000U) - 0x100000U);
		value = NSStrtodSetHighWord(value,
				NSStrtodHighWord(value) | 0x000fffffU);
		value = NSStrtodSetLowWord(value, 0xffffffffU);
		goto corrected;
	}
	if ((NSStrtodHighWord(value) & 0xfffffU) == 0xfffffU
			&& NSStrtodLowWord(value) == 0xffffffffU) {
		value = NSStrtodSetHighWord(value,
				(NSStrtodHighWord(value) & 0x7ff00000U) + 0x100000U);
		value = NSStrtodSetLowWord(value, 0);
		goto corrected;
	}
tieCheck:
	if (NSStrtodLowWord(value) & 1U) {
		if (differenceSign)
			value += NSStrtodULP(value);
		else {
			value -= NSStrtodULP(value);
			if (value == 0.0)
				goto rangeUnderflow;
		}
	}
corrected:
	NSBigintBfree(binary);
	NSBigintBfree(denominator);
	NSBigintBfree(one);
	NSBigintBfree(base);
	NSBigintBfree(difference);
	goto finish;

underflow:
rangeUnderflow:
	value = 0.0;
	errno = 34;
	if (base != 0)
		goto corrected;
	goto finish;
overflow:
	value = INFINITY;
	errno = 34;
	if (base != 0)
		goto corrected;
	goto finish;
finish:
	if (endPointer != 0)
		*endPointer = (char *)(noToken ? original : cursor);
	return negative ? -value : value;
}

#endif /* PowerPC */

