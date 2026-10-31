/*	NSBigint.h
	Private binary-integer support shared by decimal conversion routines.
*/

#ifndef _NSBigint_h_
#define _NSBigint_h_

typedef struct NSBigint {
	struct NSBigint *next;
	int k;
	int maxwds;
	int sign;
	int wds;
	unsigned int x[1];
} NSBigint;

extern const double NSBigintTens[23];
extern const double NSBigintBigTens[5];

NSBigint *NSBigintBalloc(int k);
NSBigint *NSBigintBfree(NSBigint *value);
NSBigint *NSBigintD2B(double value, int *exponent, int *bitCount);
double NSBigintB2D(NSBigint *value, int *exponent);
int NSBigintLo0Bits(unsigned int *value);
int NSBigintHi0Bits(unsigned int value);
NSBigint *NSBigintI2B(int value);
NSBigint *NSBigintPow5Mult(NSBigint *value, int exponent);
NSBigint *NSBigintMult(NSBigint *left, NSBigint *right);
NSBigint *NSBigintLShift(NSBigint *value, int bits);
int NSBigintCompare(NSBigint *left, NSBigint *right);
NSBigint *NSBigintMultAdd(NSBigint *value, int multiplier,
					  unsigned int addend);
NSBigint *NSBigintDiff(NSBigint *left, NSBigint *right);

#if defined(__ppc__) || defined(__POWERPC__)
unsigned int NSDtoaQuorem(NSBigint *numerator, NSBigint *denominator);
char *__dtoa(double value, int mode, int digits, int *decimalPosition,
		int *negative, char **endPointer);
#endif

#endif /* _NSBigint_h_ */
