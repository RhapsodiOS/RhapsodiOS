/*
	The dtoa conversion code in this file is derived from David M. Gay's
	1991 implementation, distributed with the following permission.

	Copyright (c) 1991 by AT&T.

	Permission to use, copy, modify, and distribute this software for any
	purpose without fee is hereby granted, provided that this entire notice
	is included in all copies of any software which is or includes a copy or
	modification of this software and in all copies of the supporting
	documentation for such software.

	THIS SOFTWARE IS BEING PROVIDED "AS IS", WITHOUT ANY EXPRESS OR IMPLIED
	WARRANTY.  IN PARTICULAR, NEITHER THE AUTHOR NOR AT&T MAKES ANY
	REPRESENTATION OR WARRANTY OF ANY KIND CONCERNING THE MERCHANTABILITY
	OF THIS SOFTWARE OR ITS FITNESS FOR ANY PARTICULAR PURPOSE.
*/

/*	NSDtoa.m
	PPC Foundation decimal-to-string conversion support.
*/

#import <Foundation/NSBigint.h>

#include <math.h>
#include <string.h>

#if defined(__ppc__) || defined(__POWERPC__)

/*
 * Divide the leading part of numerator by denominator, leaving the
 * remainder in numerator.  The quotient estimate and single correction
 * follow the target's normalized-divisor precondition.
 */
unsigned int
NSDtoaQuorem(NSBigint *numerator, NSBigint *denominator)
{
	unsigned int quotient;
	unsigned int words;
	unsigned int topWord;
	unsigned int index;
	unsigned int carry;
	unsigned int borrow;

	words = (unsigned int)denominator->wds;
	if ((unsigned int)numerator->wds < words)
		return 0;
	topWord = words - 1;

	quotient = numerator->x[words - 1]
		/ (denominator->x[words - 1] + 1U);
	if (quotient != 0) {
		carry = 0;
		borrow = 0;
		for (index = 0; index < words; index++) {
			unsigned long long product =
				(unsigned long long)denominator->x[index] * quotient + carry;
			unsigned int part = (unsigned int)product;
			unsigned int oldWord = numerator->x[index];
			unsigned int difference = oldWord - part - borrow;

			carry = (unsigned int)(product >> 32);
			borrow = oldWord < part || (borrow != 0 && oldWord == part);
			numerator->x[index] = difference;
		}
		if (numerator->x[topWord] == 0) {
			while (topWord > 1 && numerator->x[topWord - 1] == 0)
				--topWord;
			numerator->wds = (int)topWord;
		}
	}

	if (NSBigintCompare(numerator, denominator) >= 0) {
		++quotient;
		borrow = 0;
		for (index = 0; index < (unsigned int)denominator->wds; index++) {
			unsigned int divisorWord = denominator->x[index];
			unsigned int oldWord = numerator->x[index];
			unsigned int difference = oldWord - divisorWord - borrow;

			borrow = oldWord < divisorWord
				|| (borrow != 0 && oldWord == divisorWord);
			numerator->x[index] = difference;
		}
		if (numerator->x[topWord] == 0) {
			while (topWord > 1 && numerator->x[topWord - 1] == 0)
				--topWord;
			numerator->wds = (int)topWord;
		}
	}

	return quotient;
}

/* The live PPC IDA body is the behavioral reference for this adaptation. */
typedef int Long;
typedef unsigned int ULong;
typedef NSBigint Bigint;

#define IEEE_Arith 1
#define IEEE_BIG_ENDIAN 1
#define Pack_32 1
#define Exp_shift 20
#define Exp_shift1 20
#define Exp_msk1 0x100000U
#define Exp_mask 0x7ff00000U
#define P 53
#define Bias 1023
#define Exp_11 0x3ff00000U
#define Frac_mask 0x000fffffU
#define Frac_mask1 0x000fffffU
#define Ten_pmax 22
#define Bletch 0x10
#define Bndry_mask 0x000fffffU
#define Sign_bit 0x80000000U
#define Log2P 1
#define Quick_max 14
#define Int_max 14
#define n_bigtens 5
#define word0(value) (((ULong *)&(value))[0])
#define word1(value) (((ULong *)&(value))[1])
#define NSDtoaCopy(destination, source) \
    memcpy((char *)&(destination)->sign, (char *)&(source)->sign, \
           (source)->wds * sizeof(Long) + 2 * sizeof(int))

char *
__dtoa
#ifdef KR_headers
	(d, mode, ndigits, decpt, sign, rve)
	double d; int mode, ndigits, *decpt, *sign; char **rve;
#else
	(double d, int mode, int ndigits, int *decpt, int *sign, char **rve)
#endif
{
 /*	Arguments ndigits, decpt, sign are similar to those
	of ecvt and fcvt; trailing zeros are suppressed from
	the returned string.  If not null, *rve is set to point
	to the end of the return value.  If d is +-Infinity or NaN,
	then *decpt is set to 9999.

	mode:
		0 ==> shortest string that yields d when read in
			and rounded to nearest.
		1 ==> like 0, but with Steele & White stopping rule;
			e.g. with IEEE P754 arithmetic , mode 0 gives
			1e23 whereas mode 1 gives 9.999999999999999e22.
		2 ==> max(1,ndigits) significant digits.  This gives a
			return value similar to that of ecvt, except
			that trailing zeros are suppressed.
		3 ==> through ndigits past the decimal point.  This
			gives a return value similar to that from fcvt,
			except that trailing zeros are suppressed, and
			ndigits can be negative.
		4-9 should give the same return values as 2-3, i.e.,
			4 <= mode <= 9 ==> same return as mode
			2 + (mode & 1).  These modes are mainly for
			debugging; often they run slower but sometimes
			faster than modes 2-3.
		4,5,8,9 ==> left-to-right digit generation.
		6-9 ==> don't try fast floating-point estimate
			(if applicable).

		Values of mode other than 0-9 are treated as mode 0.

		Sufficient space is allocated to the return value
		to hold the suppressed trailing zeros.
	*/

	int bbits, b2, b5, be, dig, i, ieps, ilim, ilim0, ilim1,
		j, j1, k, k0, k_check, leftright, m2, m5, s2, s5,
		spec_case, try_quick;
	Long L;
#ifndef Sudden_Underflow
	int denorm;
	ULong x;
#endif
	NSBigint *b, *b1, *delta, *mlo, *mhi, *S;
	double d2, ds, eps;
	char *s, *s0;
	static NSBigint *result;
	static int result_k;

	if (result) {
		result->k = result_k;
		result->maxwds = 1 << result_k;
		NSBigintBfree(result);
		result = 0;
		}

	if (word0(d) & Sign_bit) {
		/* set sign for everything, including 0's and NaNs */
		*sign = 1;
		word0(d) &= ~Sign_bit;	/* clear sign bit */
		}
	else
		*sign = 0;

#if defined(IEEE_Arith) + defined(VAX)
#ifdef IEEE_Arith
	if ((word0(d) & Exp_mask) == Exp_mask)
#else
	if (word0(d)  == 0x8000)
#endif
		{
		/* Infinity or NaN */
		*decpt = 9999;
		s =
#ifdef IEEE_Arith
			!word1(d) && !(word0(d) & 0xfffff) ? "Infinity" :
#endif
				"NaN";
		if (rve)
			*rve =
#ifdef IEEE_Arith
				s[3] ? s + 8 :
#endif
						s + 3;
		return s;
		}
#endif
#ifdef IBM
	d += 0; /* normalize */
#endif
	if (!d) {
		*decpt = 1;
		s = "0";
		if (rve)
			*rve = s + 1;
		return s;
		}

	b = NSBigintD2B(d, &be, &bbits);
#ifdef Sudden_Underflow
	i = (int)(word0(d) >> Exp_shift1 & (Exp_mask>>Exp_shift1));
#else
	if (i = (int)(word0(d) >> Exp_shift1 & (Exp_mask>>Exp_shift1))) {
#endif
		d2 = d;
		word0(d2) &= Frac_mask1;
		word0(d2) |= Exp_11;
#ifdef IBM
		if (j = 11 - NSBigintHi0Bits(word0(d2) & Frac_mask))
			d2 /= 1 << j;
#endif

		/* log(x)	~=~ log(1.5) + (x-1.5)/1.5
		 * log10(x)	 =  log(x) / log(10)
		 *		~=~ log(1.5)/log(10) + (x-1.5)/(1.5*log(10))
		 * log10(d) = (i-Bias)*log(2)/log(10) + log10(d2)
		 *
		 * This suggests computing an approximation k to log10(d) by
		 *
		 * k = (i - Bias)*0.301029995663981
		 *	+ ( (d2-1.5)*0.289529654602168 + 0.176091259055681 );
		 *
		 * We want k to be too large rather than too small.
		 * The error in the first-order Taylor series approximation
		 * is in our favor, so we just round up the constant enough
		 * to compensate for any error in the multiplication of
		 * (i - Bias) by 0.301029995663981; since |i - Bias| <= 1077,
		 * and 1077 * 0.30103 * 2^-52 ~=~ 7.2e-14,
		 * adding 1e-13 to the constant term more than suffices.
		 * Hence we adjust the constant term to 0.1760912590558.
		 * (We could get a more accurate k by invoking log10,
		 *  but this is probably not worthwhile.)
		 */

		i -= Bias;
#ifdef IBM
		i <<= 2;
		i += j;
#endif
#ifndef Sudden_Underflow
		denorm = 0;
		}
	else {
		/* d is denormalized */

		i = bbits + be + (Bias + (P-1) - 1);
		x = i > 32  ? word0(d) << 64 - i | word1(d) >> i - 32
			    : word1(d) << 32 - i;
		d2 = x;
		word0(d2) -= 31*Exp_msk1; /* adjust exponent */
		i -= (Bias + (P-1) - 1) + 1;
		denorm = 1;
		}
#endif
	ds = (d2-1.5)*0.289529654602168 + 0.1760912590558 + i*0.301029995663981;
	k = (int)ds;
	if (ds < 0. && ds != k)
		k--;	/* want k = floor(ds) */
	k_check = 1;
	if (k >= 0 && k <= Ten_pmax) {
		if (d < NSBigintTens[k])
			k--;
		k_check = 0;
		}
	j = bbits - i - 1;
	if (j >= 0) {
		b2 = 0;
		s2 = j;
		}
	else {
		b2 = -j;
		s2 = 0;
		}
	if (k >= 0) {
		b5 = 0;
		s5 = k;
		s2 += k;
		}
	else {
		b2 -= k;
		b5 = -k;
		s5 = 0;
		}
	if (mode < 0 || mode > 9)
		mode = 0;
	try_quick = 1;
	if (mode > 5) {
		mode -= 4;
		try_quick = 0;
		}
	leftright = 1;
	switch(mode) {
		case 0:
		case 1:
			ilim = ilim1 = -1;
			i = 18;
			ndigits = 0;
			break;
		case 2:
			leftright = 0;
			/* no break */
		case 4:
			if (ndigits <= 0)
				ndigits = 1;
			ilim = ilim1 = i = ndigits;
			break;
		case 3:
			leftright = 0;
			/* no break */
		case 5:
			i = ndigits + k + 1;
			ilim = i;
			ilim1 = i - 1;
			if (i <= 0)
				i = 1;
		}
	j = sizeof(ULong);
	for(result_k = 0; sizeof(NSBigint) - sizeof(ULong) + j <= i;
		j <<= 1) result_k++;
	result = NSBigintBalloc(result_k);
	s = s0 = (char *)result;

	if (ilim >= 0 && ilim <= Quick_max && try_quick) {

		/* Try to get by with floating-point arithmetic. */

		i = 0;
		d2 = d;
		k0 = k;
		ilim0 = ilim;
		ieps = 2; /* conservative */
		if (k > 0) {
			ds = NSBigintTens[k&0xf];
			j = k >> 4;
			if (j & Bletch) {
				/* prevent overflows */
				j &= Bletch - 1;
				d /= NSBigintBigTens[n_bigtens-1];
				ieps++;
				}
			for(; j; j >>= 1, i++)
				if (j & 1) {
					ieps++;
					ds *= NSBigintBigTens[i];
					}
			d /= ds;
			}
		else if (j1 = -k) {
			d *= NSBigintTens[j1 & 0xf];
			for(j = j1 >> 4; j; j >>= 1, i++)
				if (j & 1) {
					ieps++;
					d *= NSBigintBigTens[i];
					}
			}
		if (k_check && d < 1. && ilim > 0) {
			if (ilim1 <= 0)
				goto fast_failed;
			ilim = ilim1;
			k--;
			d *= 10.;
			ieps++;
			}
		eps = ieps*d + 7.;
		word0(eps) -= (P-1)*Exp_msk1;
		if (ilim == 0) {
			S = mhi = 0;
			d -= 5.;
			if (d > eps)
				goto one_digit;
			if (d < -eps)
				goto no_digits;
			goto fast_failed;
			}
#ifndef No_leftright
		if (leftright) {
			/* Use Steele & White method of only
			 * generating digits needed.
			 */
			eps = 0.5/NSBigintTens[ilim-1] - eps;
			for(i = 0;;) {
				L = d;
				d -= L;
				*s++ = '0' + (int)L;
				if (d < eps)
					goto ret1;
				if (1. - d < eps)
					goto bump_up;
				if (++i >= ilim)
					break;
				eps *= 10.;
				d *= 10.;
				}
			}
		else {
#endif
			/* Generate ilim digits, then fix them up. */
			eps *= NSBigintTens[ilim-1];
			for(i = 1;; i++, d *= 10.) {
				L = d;
				d -= L;
				*s++ = '0' + (int)L;
				if (i == ilim) {
					if (d > 0.5 + eps)
						goto bump_up;
					else if (d < 0.5 - eps) {
						while(*--s == '0');
						s++;
						goto ret1;
						}
					break;
					}
				}
#ifndef No_leftright
			}
#endif
 fast_failed:
		s = s0;
		d = d2;
		k = k0;
		ilim = ilim0;
		}

	/* Do we have a "small" integer? */

	if (be >= 0 && k <= Int_max) {
		/* Yes. */
		ds = NSBigintTens[k];
		if (ndigits < 0 && ilim <= 0) {
			S = mhi = 0;
			if (ilim < 0 || d <= 5*ds)
				goto no_digits;
			goto one_digit;
			}
		for(i = 1;; i++) {
			L = d / ds;
			d -= L*ds;
#ifdef Check_FLT_ROUNDS
			/* If FLT_ROUNDS == 2, L will usually be high by 1 */
			if (d < 0) {
				L--;
				d += ds;
				}
#endif
			*s++ = '0' + (int)L;
			if (i == ilim) {
				d += d;
				if (d > ds || d == ds && L & 1) {
 bump_up:
					while(*--s == '9')
						if (s == s0) {
							k++;
							*s = '0';
							break;
							}
					++*s++;
					}
				break;
				}
			if (!(d *= 10.))
				break;
			}
		goto ret1;
		}

	m2 = b2;
	m5 = b5;
	mhi = mlo = 0;
	if (leftright) {
		if (mode < 2) {
			i =
#ifndef Sudden_Underflow
				denorm ? be + (Bias + (P-1) - 1 + 1) :
#endif
#ifdef IBM
				1 + 4*P - 3 - bbits + ((bbits + be - 1) & 3);
#else
				1 + P - bbits;
#endif
			}
		else {
			j = ilim - 1;
			if (m5 >= j)
				m5 -= j;
			else {
				s5 += j -= m5;
				b5 += j;
				m5 = 0;
				}
			if ((i = ilim) < 0) {
				m2 -= i;
				i = 0;
				}
			}
		b2 += i;
		s2 += i;
		mhi = NSBigintI2B(1);
		}
	if (m2 > 0 && s2 > 0) {
		i = m2 < s2 ? m2 : s2;
		b2 -= i;
		m2 -= i;
		s2 -= i;
		}
	if (b5 > 0) {
		if (leftright) {
			if (m5 > 0) {
				mhi = NSBigintPow5Mult(mhi, m5);
				b1 = NSBigintMult(mhi, b);
				NSBigintBfree(b);
				b = b1;
				}
			if (j = b5 - m5)
				b = NSBigintPow5Mult(b, j);
			}
		else
			b = NSBigintPow5Mult(b, b5);
		}
	S = NSBigintI2B(1);
	if (s5 > 0)
		S = NSBigintPow5Mult(S, s5);

	/* Check for special case that d is a normalized power of 2. */

	if (mode < 2) {
		if (!word1(d) && !(word0(d) & Bndry_mask)
#ifndef Sudden_Underflow
		 && word0(d) & Exp_mask
#endif
				) {
			/* The special case */
			b2 += Log2P;
			s2 += Log2P;
			spec_case = 1;
			}
		else
			spec_case = 0;
		}

	/* Arrange for convenient computation of quotients:
	 * shift left if necessary so divisor has 4 leading 0 bits.
	 *
	 * Perhaps we should just compute leading 28 bits of S once
	 * and for all and pass them and a shift to NSDtoaQuorem, so it
	 * can do shifts and ors to compute the numerator for q.
	 */
#ifdef Pack_32
	if (i = ((s5 ? 32 - NSBigintHi0Bits(S->x[S->wds-1]) : 1) + s2) & 0x1f)
		i = 32 - i;
#else
	if (i = ((s5 ? 32 - NSBigintHi0Bits(S->x[S->wds-1]) : 1) + s2) & 0xf)
		i = 16 - i;
#endif
	if (i > 4) {
		i -= 4;
		b2 += i;
		m2 += i;
		s2 += i;
		}
	else if (i < 4) {
		i += 28;
		b2 += i;
		m2 += i;
		s2 += i;
		}
	if (b2 > 0)
		b = NSBigintLShift(b, b2);
	if (s2 > 0)
		S = NSBigintLShift(S, s2);
	if (k_check) {
		if (NSBigintCompare(b,S) < 0) {
			k--;
			b = NSBigintMultAdd(b, 10, 0);	/* we botched the k estimate */
			if (leftright)
				mhi = NSBigintMultAdd(mhi, 10, 0);
			ilim = ilim1;
			}
		}
	if (ilim <= 0 && mode > 2) {
		if (ilim < 0 || NSBigintCompare(b,S = NSBigintMultAdd(S,5,0)) <= 0) {
			/* no digits, fcvt style */
 no_digits:
			k = -1 - ndigits;
			goto ret;
			}
 one_digit:
		*s++ = '1';
		k++;
		goto ret;
		}
	if (leftright) {
		if (m2 > 0)
			mhi = NSBigintLShift(mhi, m2);

		/* Compute mlo -- check for special case
		 * that d is a normalized power of 2.
		 */

		mlo = mhi;
		if (spec_case) {
			mhi = NSBigintBalloc(mhi->k);
			NSDtoaCopy(mhi, mlo);
			mhi = NSBigintLShift(mhi, Log2P);
			}

		for(i = 1;;i++) {
			dig = NSDtoaQuorem(b,S) + '0';
			/* Do we yet have the shortest decimal string
			 * that will round to d?
			 */
			j = NSBigintCompare(b, mlo);
			delta = NSBigintDiff(S, mhi);
			j1 = delta->sign ? 1 : NSBigintCompare(b, delta);
			NSBigintBfree(delta);
#ifndef ROUND_BIASED
			if (j1 == 0 && !mode && !(word1(d) & 1)) {
				if (dig == '9')
					goto round_9_up;
				if (j > 0)
					dig++;
				*s++ = dig;
				goto ret;
				}
#endif
			if (j < 0 || j == 0 && !mode
#ifndef ROUND_BIASED
							&& !(word1(d) & 1)
#endif
					) {
				if (j1 > 0) {
					b = NSBigintLShift(b, 1);
					j1 = NSBigintCompare(b, S);
					if ((j1 > 0 || j1 == 0 && dig & 1)
					&& dig++ == '9')
						goto round_9_up;
					}
				*s++ = dig;
				goto ret;
				}
			if (j1 > 0) {
				if (dig == '9') { /* possible if i == 1 */
 round_9_up:
					*s++ = '9';
					goto roundoff;
					}
				*s++ = dig + 1;
				goto ret;
				}
			*s++ = dig;
			if (i == ilim)
				break;
			b = NSBigintMultAdd(b, 10, 0);
			if (mlo == mhi)
				mlo = mhi = NSBigintMultAdd(mhi, 10, 0);
			else {
				mlo = NSBigintMultAdd(mlo, 10, 0);
				mhi = NSBigintMultAdd(mhi, 10, 0);
				}
			}
		}
	else
		for(i = 1;; i++) {
			*s++ = dig = NSDtoaQuorem(b,S) + '0';
			if (i >= ilim)
				break;
			b = NSBigintMultAdd(b, 10, 0);
			}

	/* Round off last digit */

	b = NSBigintLShift(b, 1);
	j = NSBigintCompare(b, S);
	if (j > 0 || j == 0 && dig & 1) {
 roundoff:
		while(*--s == '9')
			if (s == s0) {
				k++;
				*s++ = '1';
				goto ret;
				}
		++*s++;
		}
	else {
		while(*--s == '0');
		s++;
		}
 ret:
	NSBigintBfree(S);
	if (mhi) {
		if (mlo && mlo != mhi)
			NSBigintBfree(mlo);
		NSBigintBfree(mhi);
		}
 ret1:
	NSBigintBfree(b);
	if (s == s0) {				/* don't return empty string */
		*s++ = '0';
		k = 0;
	}
	*s = 0;
	*decpt = k + 1;
	if (rve)
		*rve = s;
	return s0;
	}

#endif /* PowerPC */
