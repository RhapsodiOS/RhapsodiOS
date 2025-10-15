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
#ifdef LIBSYS_VERSION
static
#endif
void fft_hermitian(DATA_TYPE *z, int n);
/* 
 * Fast Fourier Transform for real input data z.
 * The length n must be a power of 2.
 * Output is Re[0],...,Re[n/2],Im[n/2-1],...,Im[1].
 * Uses a decimation-in-time, in-place, split-radix algorithm.
 * Reference: Sorenson, et. al., (1987)
 * IEEE Trans. Acoustics Speech and Sig. Proc., ASSP-35, 6, pp. 849-863
 */

#ifdef LIBSYS_VERSION
static
#endif
void fft_inverse_hermitian(DATA_TYPE *z, int n);
/*
 * Inverse of fft_real_to_hermitian().
 * Input is Re[0],...,Re[n/2],Im[n/2-1],...,Im[1].
 * Uses a decimation-in-frequency, in-place, split-radix algorithm.
 */

#ifndef LIBSYS_VERSION
void mul_hermitian(DATA_TYPE *a, DATA_TYPE *b, int n);
/* b becomes b*a in Hermitian representation. */
#endif


