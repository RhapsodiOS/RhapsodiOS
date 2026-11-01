/*	NSBigint.m
	PPC private binary-integer primitives used by decimal conversion routines.
*/

#import <Foundation/NSBigint.h>
#import <Foundation/NSZone.h>

#include <string.h>

#if defined(__ppc__) || defined(__POWERPC__)

const double NSBigintTens[23] = {
	1.0,					1.0e1,				1.0e2,				1.0e3,
	1.0e4,				1.0e5,				1.0e6,				1.0e7,
	1.0e8,				1.0e9,				1.0e10,				1.0e11,
	1.0e12,				1.0e13,				1.0e14,				1.0e15,
	1.0e16,				1.0e17,				1.0e18,				1.0e19,
	1.0e20,				1.0e21,				1.0e22
};

const double NSBigintBigTens[5] = {
	1.0e16,	1.0e32,	1.0e64,	1.0e128,	1.0e256
};

static NSBigint *NSBigintFreeList[16];
static NSBigint *NSBigintPowerOfFiveSquares;
static const unsigned int NSBigintSmallPowersOfFive[4] = {
	0, 5, 25, 125
};

NSBigint *
NSBigintBalloc(int k)
{
	NSBigint *value = NSBigintFreeList[k];

	if (value != 0) {
		NSBigintFreeList[k] = value->next;
	} else {
		value = (NSBigint *)NSZoneMalloc(NULL,
				(unsigned)(20 + 4 * (1 << k)));
		value->k = k;
		value->maxwds = 1 << k;
	}
	value->wds = 0;
	value->sign = 0;
	return value;
}

NSBigint *
NSBigintBfree(NSBigint *value)
{
	if (value != 0) {
		value->next = NSBigintFreeList[value->k];
		NSBigintFreeList[value->k] = value;
	}
	return value;
}

int
NSBigintLo0Bits(unsigned int *value)
{
	unsigned int word = *value;
	int count = 0;

	if ((word & 7) != 0) {
		if (word & 1)
			return 0;
		if (word & 2) {
			*value = word >> 1;
			return 1;
		}
		*value = word >> 2;
		return 2;
	}
	if ((word & 0xffff) == 0) {
		count = 16;
		word >>= 16;
	}
	if ((word & 0xff) == 0) {
		count += 8;
		word >>= 8;
	}
	if ((word & 0xf) == 0) {
		count += 4;
		word >>= 4;
	}
	if ((word & 3) == 0) {
		count += 2;
		word >>= 2;
	}
	if (word & 1) {
		*value = word;
		return count;
	}
	++count;
	word >>= 1;
	if (word != 0) {
		*value = word;
		return count;
	}
	return 32;
}

int
NSBigintHi0Bits(unsigned int value)
{
	int count = 0;

	if ((value & 0xffff0000U) == 0) {
		count = 16;
		value <<= 16;
	}
	if ((value & 0xff000000U) == 0) {
		count += 8;
		value <<= 8;
	}
	if ((value & 0xf0000000U) == 0) {
		count += 4;
		value <<= 4;
	}
	if ((value & 0xc0000000U) == 0) {
		count += 2;
		value <<= 2;
	}
	if ((value & 0x80000000U) != 0)
		return count;
	++count;
	return (value & 0x40000000U) != 0 ? count : 32;
}

NSBigint *
NSBigintI2B(int number)
{
	NSBigint *value = NSBigintBalloc(1);

	value->x[0] = (unsigned int)number;
	value->wds = 1;
	return value;
}

NSBigint *
NSBigintMultAdd(NSBigint *value, int multiplier, unsigned int addend)
{
	unsigned long long carry = addend;
	int index;

	for (index = 0; index < value->wds; ++index) {
		unsigned long long product =
			(unsigned long long)value->x[index] * (unsigned int)multiplier + carry;
		value->x[index] = (unsigned int)product;
		carry = product >> 32;
	}
	if (carry != 0) {
		if (value->wds >= value->maxwds) {
			NSBigint *grown = NSBigintBalloc(value->k + 1);
			memcpy(&grown->sign, &value->sign,
					(unsigned)(8 + 4 * value->wds));
			NSBigintBfree(value);
			value = grown;
		}
		value->x[value->wds++] = (unsigned int)carry;
	}
	return value;
}

NSBigint *
NSBigintPow5Mult(NSBigint *value, int exponent)
{
	NSBigint *square;
	int power = exponent;

	if ((power & 3) != 0)
		value = NSBigintMultAdd(value,
				(int)NSBigintSmallPowersOfFive[power & 3], 0);
	power >>= 2;
	if (power == 0)
		return value;
	if (NSBigintPowerOfFiveSquares == 0) {
		NSBigintPowerOfFiveSquares = NSBigintI2B(625);
		NSBigintPowerOfFiveSquares->next = 0;
	}
	square = NSBigintPowerOfFiveSquares;
	for (;;) {
		if (power & 1) {
			NSBigint *product = NSBigintMult(value, square);
			NSBigintBfree(value);
			value = product;
		}
		power >>= 1;
		if (power == 0)
			break;
		if (square->next == 0) {
			square->next = NSBigintMult(square, square);
			square->next->next = 0;
		}
		square = square->next;
	}
	return value;
}

NSBigint *
NSBigintD2B(double number, int *exponent, int *bitCount)
{
	unsigned long long bits;
	unsigned int high;
	unsigned int low;
	unsigned int exponentBits;
	int shift;
	int words;
	NSBigint *value = NSBigintBalloc(1);

	memcpy(&bits, &number, sizeof(bits));
	high = (unsigned int)(bits >> 32);
	low = (unsigned int)bits;
	exponentBits = (high & 0x7fffffffU) >> 20;
	high &= 0xfffffU;
	if (exponentBits != 0)
		high |= 0x100000U;
	if (low != 0) {
		shift = NSBigintLo0Bits(&low);
		if (shift != 0) {
			value->x[0] = low | (high << (32 - shift));
			high >>= shift;
		} else {
			value->x[0] = low;
		}
		value->x[1] = high;
		words = high != 0 ? 2 : 1;
	} else {
		shift = NSBigintLo0Bits(&high);
		value->x[0] = high;
		words = 1;
		shift += 32;
	}
	value->wds = words;
	if (exponentBits != 0) {
		*exponent = (int)exponentBits + shift - 1075;
		*bitCount = 53 - shift;
	} else {
		*exponent = shift - 1074;
		*bitCount = 32 * words - NSBigintHi0Bits(value->x[words - 1]);
	}
	return value;
}

double
NSBigintB2D(NSBigint *value, int *exponent)
{
	unsigned long long significand = 0;
	unsigned long long bits;
	int bitLength = (value->wds - 1) * 32 +
			(32 - NSBigintHi0Bits(value->x[value->wds - 1]));
	int sourceBit = bitLength - 53;
	int bit;

	if (sourceBit < 0)
		sourceBit = 0;
	for (bit = bitLength - 1; bit >= sourceBit; --bit) {
		int word = bit >> 5;
		int offset = bit & 31;
		significand = (significand << 1) |
				((value->x[word] >> offset) & 1U);
	}
	if (bitLength < 53)
		significand <<= 53 - bitLength;
	*exponent = bitLength - 32 * (value->wds - 1);
	bits = (0x3ffULL << 52) | (significand & 0xfffffffffffffULL);
	{
		double result;
		memcpy(&result, &bits, sizeof(result));
		return result;
	}
}

NSBigint *
NSBigintMult(NSBigint *left, NSBigint *right)
{
	NSBigint *larger = left;
	NSBigint *smaller = right;
	NSBigint *product;
	int words;
	int k;
	int i;

	if (larger->wds < smaller->wds) {
		larger = right;
		smaller = left;
	}
	words = larger->wds + smaller->wds;
	k = larger->k;
	if (words > larger->maxwds)
		++k;
	product = NSBigintBalloc(k);
	for (i = 0; i < words; ++i)
		product->x[i] = 0;
	for (i = 0; i < smaller->wds; ++i) {
		unsigned long long carry = 0;
		int j;
		for (j = 0; j < larger->wds; ++j) {
			unsigned long long current =
				(unsigned long long)larger->x[j] * smaller->x[i] +
				product->x[i + j] + carry;
			product->x[i + j] = (unsigned int)current;
			carry = current >> 32;
		}
		product->x[i + larger->wds] = (unsigned int)carry;
	}
	while (words > 0 && product->x[words - 1] == 0)
		--words;
	product->wds = words;
	return product;
}

NSBigint *
NSBigintLShift(NSBigint *value, int bits)
{
	int wordShift = bits >> 5;
	int shiftedWords = wordShift + value->wds + 1;
	int k = value->k;
	int capacity = value->maxwds;
	NSBigint *result;
	int index;
	int shift = bits & 0x1f;
	unsigned int carry = 0;

	while (shiftedWords > capacity) {
		++k;
		capacity *= 2;
	}
	result = NSBigintBalloc(k);
	for (index = 0; index < wordShift; ++index)
		result->x[index] = 0;
	if (shift != 0) {
		for (index = 0; index < value->wds; ++index) {
			result->x[wordShift + index] =
				(value->x[index] << shift) | carry;
			carry = value->x[index] >> (32 - shift);
		}
		result->x[wordShift + value->wds] = carry;
		if (carry != 0)
			++shiftedWords;
	} else {
		for (index = 0; index < value->wds; ++index)
			result->x[wordShift + index] = value->x[index];
	}
	result->wds = shiftedWords - 1;
	NSBigintBfree(value);
	return result;
}

int
NSBigintCompare(NSBigint *left, NSBigint *right)
{
	int difference = left->wds - right->wds;
	int index;

	if (difference != 0)
		return difference;
	for (index = left->wds - 1; index >= 0; --index) {
		if (left->x[index] != right->x[index])
			return left->x[index] < right->x[index] ? -1 : 1;
	}
	return 0;
}

NSBigint *
NSBigintDiff(NSBigint *left, NSBigint *right)
{
	int comparison = NSBigintCompare(left, right);
	NSBigint *larger;
	NSBigint *smaller;
	NSBigint *difference;
	int index;
	unsigned int borrow = 0;

	if (comparison == 0) {
		difference = NSBigintBalloc(0);
		difference->wds = 1;
		difference->x[0] = 0;
		return difference;
	}
	if (comparison > 0) {
		larger = left;
		smaller = right;
	} else {
		larger = right;
		smaller = left;
	}
	difference = NSBigintBalloc(larger->k);
	difference->sign = comparison < 0;
	for (index = 0; index < smaller->wds; ++index) {
		unsigned long long subtrahend =
			(unsigned long long)smaller->x[index] + borrow;
		unsigned int minuend = larger->x[index];
		difference->x[index] =
			(unsigned int)((unsigned long long)minuend - subtrahend);
		borrow = (unsigned long long)minuend < subtrahend;
	}
	for (; index < larger->wds; ++index) {
		unsigned int minuend = larger->x[index];
		difference->x[index] = minuend - borrow;
		borrow = borrow && minuend == 0;
	}
	while (index > 1 && difference->x[index - 1] == 0)
		--index;
	difference->wds = index;
	return difference;
}

#endif /* PowerPC */
