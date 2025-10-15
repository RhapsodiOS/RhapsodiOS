/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * Fractional arithmetic package.
 *
 * Copyright 1992 NeXT, Inc.  All Rights Reserved.
 *
 * Written by Lee R. Boynton, 1992.
 *
 */

/*
 * The data is represented as a signed 32 bit entity, with the high order
 * 16 bits representing the integer part, and the low 16 bits representing
 * the fractional part. Values:
 *	 -1.0 		0xffff0000
 *	 -0.5 		0xffff8000
 *	 -0.25 		0xffffc000
 *	  0.0		0x00000000
 *	  0.25		0x00004000
 *	  0.5		0x00008000
 *	  1.0		0x00010000
 */

typedef long int fraction;
#define FRAC_ONE (0x10000)
#define FRAC_ONEHALF (0x8000)
#define FRAC_MAX ((int)0x7fffffff)
#define FRAC_MIN (-(FRAC_MAX))

#define SHORT_FRAC(the_short) ((fraction)(the_short))
#define FRAC_SHORT(the_frac) ((short)(the_frac))

#define INT_FRAC(the_int) ((fraction)((the_int) >> 16))
#define FRAC_INT(the_frac) ((int)((the_frac) << 16))
#define INT_LSHD_FRAC(the_int,the_lsh) ((fraction)((the_int)>>(16-(the_lsh))))
#define FRAC_INT_RSHD(the_frac,the_rsh) ((((int)(the_frac))<<(16-(the_rsh))))

static inline fraction FLOAT_FRAC(float the_float) {
    float tmp = the_float * FRAC_ONE;
    if (tmp > FRAC_MAX) tmp = FRAC_MAX;
    else if (tmp < FRAC_MIN) tmp = FRAC_MIN;
    return (fraction)tmp;
}
#define FRAC_FLOAT(the_frac) (((float)the_frac) / FRAC_ONE)

static inline fraction DOUBLE_FRAC(double the_double) {
    double tmp = the_double * FRAC_ONE;
    if (tmp > FRAC_MAX) tmp = FRAC_MAX;
    else if (tmp < FRAC_MIN) tmp = FRAC_MIN;
    return (fraction)tmp;
}
#define FRAC_DOUBLE(the_frac) (((double)the_frac) / FRAC_ONE)

static inline fraction frac_negate(fraction f1) {
    return -f1;
}

static inline fraction frac_add(fraction f1, fraction f2) {
    return f1 + f2;
}

static inline fraction frac_sub(fraction f1, fraction f2) {
    return f1 - f2;
}

#if m68k

#if 1
/*** Only compatible with 3.1 C compiler ***/
static inline int frac_mul(fraction a, fraction b) {
    int result;
    asm("mulsl %2,%0,%1;swap %0;swap %1;movew %1,%0"
	: "=d&" (result)
	: "d" (a), "g"(b)
	: "1");
    return result;
}
#else
#warning Using slower frac_mul for 3.0 C compiler compatibility
static inline fraction frac_mul(fraction a, fraction b) {
    int result;
    asm("movel %1,d1;mulsl %2,d0,d1;swap d0;swap d1;movew d1,d0; movel d0,%0"
	: "=dm" (result)
	: "dms" (a), "dms"(b)
	: "d0");
    return result;
}
#endif

#else

#if i386

static inline int frac_mul(fraction a, fraction b) {
    int result;
    asm("imull %2; shld $0x10,%1,%0;"
	: "=d" (result)
	: "a" (a), "rm"(b));
    return result;
}

#else
static inline fraction frac_mul(fraction f1, fraction f2) {
    long long z = (long long)f1 * f2;
    long answer = (int)(z >> 16);
    return (int)answer;
}
#endif
#endif

