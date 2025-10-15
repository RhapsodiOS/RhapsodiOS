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
/* comment the next line to use double floats instead of fractional numbers */

#define FRACTION

#ifdef FRACTION

#import "fraction.h"
#define DATA_TYPE fraction
#define ADD(x,y) frac_add(x,y)
#define SUB(x,y) frac_sub(x,y)
#define NEG(x) frac_negate(x)
#define MUL(x,y) frac_mul(x,y)
#define SHORT_TO_DATA(x) (SHORT_FRAC(x))
#define DATA_TO_SHORT(x) (FRAC_SHORT(x))
#define INT_TO_DATA(x) (INT_FRAC(x))
#define INT_LSHIFTED_TO_DATA(x,n) (INT_LSHD_FRAC(x,n))
#define DATA_TO_INT_RSHIFTED(x,n) (FRAC_INT_RSHD(x,n))
#define DOUBLE_TO_DATA(x) (DOUBLE_FRAC(x))
#define DATA_TO_INT(x) (FRAC_INT(x))
#define DATA_TO_DOUBLE(x) (FRAC_DOUBLE(x))
#define DATA_ONE (FRAC_ONE)

#else

#define DATA_TYPE double
#define ADD(x,y) (x+y)
#define SUB(x,y) (x-(y))
#define NEG(x) (-(x))
#define MUL(x,y) ((x)*(y))
#define SHORT_TO_DATA(x) ((double)x/((int)(0x7fff)))
#define DATA_TO_SHORT(x) ((int)(x*((double)(0x7fff))))
#define INT_TO_DATA(x) ((double)x/((int)(0x7fffffff)))
#define INT_LSHIFTED_TO_DATA(x,n) (INT_TO_DATA(x)*((double)(1<<(n))))
#define DATA_TO_INT_RSHIFTED(x,n) (((int)((x)*((double)(0x7fffffff))))>>(n))
#define DATA_TO_INT(x) ((int)(x*((double)(0x7fffffff))))
#define DOUBLE_TO_DATA(x) (x)
#define DATA_TO_DOUBLE(x) (x)
#define DATA_ONE (1.0)

#endif

