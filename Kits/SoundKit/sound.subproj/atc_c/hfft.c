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
//#define _TEST_PROGRAM
#define MaxN (512)
/*
cc -g -O2 -fomit-frame-pointer hfft.c
*/

/* Hermitian FFT of real data
 *
 * Routines for split-radix, real-only transforms.
 * Copyright 1991 NeXT, Inc.  All Rights Reserved.
 *
 * These routines are adapted from 
 * Sorenson, et. al., (1987)
 * IEEE Trans. Acoustics Speech and Sig. Proc., ASSP-35, 6, pp. 849-863
 * Maintained by J.O. Smith, R.E. Crandall, and L.R. Boynton, NeXT Inc.
 * 
 * When all x[j] are real the standard DFT of (x[0],x[1],...,x[N-1]), 
 * call it x^, has the property of Hermitian symmetry: x^[j] = x^[N-j]*.
 * Thus we only need to find the set
 * (x^[0].re, x^[1].re,..., x^[N/2].re, x^[N/2-1].im, ..., x^[1].im)
 * which, like the original signal x, has N elements.
 * The two key routines perform forward (real-to-Hermitian) FFT,
 * and backward (Hermitian-to-real) FFT, respectively.
 * For example, the sequence:
 * 
 * fft_hermitian(x, N);
 * fft_inverse_hermitian(x, N);
 *
 * is an identity operation on the signal x.
 * To convolve two pure-real signals x and y, one goes:
 *
 * fft_hermitian(x, N);
 * fft_hermitian(y, N);
 * mul_hermitian(y, x, N);
 * fft_inverse_hermitian(x, N);
 *
 * and x is the pure-real cyclic convolution of x and y.
 */
 

#import <libc.h>
#import <stdio.h>
#import <math.h>
#import "datatype.h"

#define TWOPI (double)(2*3.14159265358979323846264338327950)
#define SQRTHALF (double)(0.707106781186547524400844362104849)

#ifndef LIBSYS_VERSION
void mul_hermitian(DATA_TYPE *a, DATA_TYPE *b, int n)
{
        int k, half = n>>1;
        register DATA_TYPE c, d, e, f;
        
        b[0] = MUL(b[0],a[0]);
        b[half] = MUL(b[half],a[half]);
        for(k=1;k<half;k++) {
                c = a[k]; d = b[k]; e = a[n-k]; f = b[n-k];
                b[n-k] = MUL(c,f)+MUL(d,e);
                b[k] = MUL(c,d)-MUL(e,f);
        }
}
#endif

/* old, slower version, with type of x changed from double to int */
static void scramble_int(int *x, int n)
{
    register int i,j,k;
    int tmp;
    for(i=0,j=0;i<n-1;i++) {
	if(i<j) {
	    tmp = x[j];
	    x[j]=x[i];
	    x[i]=tmp;
	}
	k = n>>1;
	while(k<=j) {
	    j -= k;
	    k>>=1;
	}
	j += k;
    }
}

static int *flip = 0;

static void scramble_data(DATA_TYPE *x, int n)	/* n must be even */
{
    int i,j;
    DATA_TYPE tmp;
    DATA_TYPE *xip;
    DATA_TYPE *xjp;
    for (i=n; --i != -1; ) {
	j = flip[i];
	if (i<j) {		
	    xip = x + i;
	    xjp = x + j;
	    tmp = *xjp;
	    *xjp = *xip;
	    *xip = tmp;
	}
    }
}

static void init_flip(int n)
{
    register int i;
    int no2 = n;
    int temp[n];
    if (flip) free(flip);
    flip = malloc(no2 * sizeof(int));
    for (i=0; i<n; i++)
      temp[i] = i; /* Is double += 1.0 faster? */
    scramble_int(temp, n);
    for (i=0; i<no2; i++)
      flip[i] = (int) temp[i];
//#ifdef _TEST_PROGRAM
#if 0
/* Test it */
  {
      DATA_TYPE t[n],t2[n];
      for (i=0; i<n; i++)
	t[i] = t2[i] = INT_TO_DATA(i);
      scramble_data(t, n);
      for (i=0; i<n; i++)
	fprintf(stderr,"Flip[0x%X] == 0x%X\n",DATA_TO_INT(t2[i]), DATA_TO_INT(t[i]));
  }
#endif
}

static DATA_TYPE *cossinarr = 0;
static int current = 0;

static int initsincos(int n)
{       int j;
        double arg = TWOPI/n;
        if(n!=current) {
	    init_flip(n);
	    if (cossinarr) free(cossinarr);
	    cossinarr = malloc (2 * n * sizeof(DATA_TYPE));
	    for(j=0;j<n;j++) {
		cossinarr[2*j]   = DOUBLE_TO_DATA(cos(j*arg));
		cossinarr[2*j+1] = DOUBLE_TO_DATA(sin(j*arg));
	    }
	    current = n;
        }
	return 0;
}

#ifdef LIBSYS_VERSION
static
#endif
void fft_hermitian(DATA_TYPE *z, int n) {
	DATA_TYPE *x1, *x2, *x3, *x4, *x5, *x6, *x7, *x8;
        DATA_TYPE t1, t2, t3, t4, t5, t6;
        int nn = n>>1, is, id0, i0, i1;
	DATA_TYPE sqrthalf = SQRTHALF*DATA_ONE;
	DATA_TYPE *x, *y, e;
	DATA_TYPE cc1, ss1, cc3, ss3, cas1, cas3;
        int n2, n4, n8, i, j, a, a3, pc, nminus = n-1;
        
	if (n!=current)
		initsincos(n);
	scramble_data(z, n);
	x = z-1;  /* FORTRAN indexing compatibility. */
	is = 1;
	id0 = 4;
	do {
	    for(i0=is;i0<=n;i0+=id0) {
		i1 = i0+1;
		e = x[i0];
		x[i0] = e+x[i1];
		x[i1] = e-x[i1];
	    }
	    id0 += id0;
	    is = id0-1;
	    id0 += id0;
        } while(is<n);
        n2 = 2;
	pc = n>>2;
        while(nn>>=1) {
                n2 += n2;
                n8 = n2>>3;
                n4 = n2>>2;
                is = 0;
                id0 = n2+n2;
                do {
                       if(n4==1)
		           for(i=is;i<n;i+=id0) {
                                x1 = x+i+1;
                                x2 = x1 + n4;
                                x3 = x2 + n4;
                                x4 = x3 + n4;
                                t1 = *x4 + *x3;
                                *x4 -= *x3;
                                *x3 = *x1 - t1;
                                *x1 += t1;
			} else {
                           x1 = x+is+1;
                           x2 = x1 + n4;
                           x3 = x2 + n4;
                           x4 = x3 + n4;
			   i0 = id0-n8;
                           for(i=is;i<n;i+=id0) {
                                t1 = *x4 + *x3;
                                *x4 -= *x3;
                                *x3 = *x1 - t1;
                                *x1 += t1;
                                x1 += n8;
                                x2 += n8;
                                x3 += n8;
                                x4 += n8;
                                t1 = MUL((*x3 + *x4),sqrthalf);
				t2 = *x3; t2 -= *x4;
                                t2 = MUL(t2,sqrthalf);
                                *x4 = *x2 - t1;
                                *x3 = -*x2 - t1;
                                *x2 = *x1 - t2;
                                *x1 += t2;
				x1 += i0;
				x2 += i0;
				x3 += i0;
				x4 += i0;
                           }
			}
	    		id0 += id0;
	    		is = id0-n2;
	    		id0 += id0;
                } while(is<n);
                a = pc;
                for(j=2;j<=n8;j++) {
			a3 = a + a;
			y = cossinarr + a3;
			a3 += a; a3 &= nminus;                        
                        cc1 = *y++;
                        ss1 = *y;
			a3 += a3;
			y = cossinarr + a3;                        
                        cc3 = *y++;
                        ss3 = *y;
			cas1 = cc1 + ss1;
			cas3 = cc3 + ss3;
                        a += pc;
			a &= nminus;
                        is = 0;
                        id0 = n2+n2;
			do {
			    x1 = x + is+j;
			    x2 = x1 + n4;
			    x3 = x2 + n4;
			    x4 = x3 + n4;
			    x5 = x2 + 2 - j - j;
			    x6 = x5 + n4;
			    x7 = x6 + n4;
			    x8 = x7 + n4;
			    for(i = is+id0; i<n; i+= id0) {
                               /*
			          These old butterflies have been replaced
			          by 3-mul convolutions.
				t1 = MUL(*x3,cc1) + MUL(*x7,ss1);
				t2 = MUL(*x7,cc1) - MUL(*x3,ss1);
				t3 = MUL(*x4,cc3) + MUL(*x8,ss3);
				t4 = MUL(*x8,cc3) - MUL(*x4,ss3);
				*/

				t5 = MUL((*x3+*x7),cas1);
				t2 = MUL(*x7,cc1);
				t6 = MUL(*x3,ss1);
				t1 = t5 - t6 - t2;
				t2 -= t6;
				
				t5 = MUL((*x4+*x8),cas3);
				t4 = MUL(*x8,cc3);
				t6 = MUL(*x4,ss3);
				t3 = t5 - t6 - t4;
				t4 -= t6;				
				
				t5 = t1 + t3;
				t6 = t2 + t4;
				t3 = t1 - t3;
				t4 -= t2;
				*x8 = *x6 + t6;
				*x3 = t6 - *x6;
				*x4 = *x2 - t3;
				*x7 = -*x2 - t3;
				*x6 = *x1 - t5;
				*x1 += t5;
				*x2 = *x5 - t4;
				*x5 += t4;
				x1 += id0;
				x2 += id0;
				x3 += id0;
				x4 += id0;
				x5 += id0;
				x6 += id0;
				x7 += id0;
				x8 += id0;
			    }
			    t5 = MUL((*x3+*x7),cas1);
			    t2 = MUL(*x7,cc1);
			    t6 = MUL(*x3,ss1);
			    t1 = t5 - t6 - t2;
			    t2 -= t6;
			    t5 = MUL((*x4+*x8),cas3);
			    t4 = MUL(*x8,cc3);
			    t6 = MUL(*x4,ss3);
			    t3 = t5 - t6 - t4;
			    t4 -= t6;
			    						    	
			    t5 = t1 + t3;
			    t6 = t2 + t4;
			    t3 = t1 - t3;
			    t4 -= t2; /* negative that in prev. version */
			    *x8 = *x6 + t6;
			    *x3 = t6 - *x6;
			    *x4 = *x2 - t3;
			    *x7 = -*x2 - t3;
			    *x6 = *x1 - t5;
			    *x1 += t5;
			    *x2 = *x5 - t4;
			    *x5 += t4;

	    		   id0 += id0;
	    		   is = id0-n2;
	    		   id0 += id0;
                        } while(is<n);
                }
		pc >>= 1;
        }
}

#ifdef LIBSYS_VERSION
static
#endif

void fft_inverse_hermitian(DATA_TYPE *z, int n) {
	DATA_TYPE *x1, *x2, *x3, *x4, *x5, *x6, *x7, *x8;
        DATA_TYPE t1, t2, t3, t4, t5;
        int nn = n>>1, is, id0, i0, i1;
	DATA_TYPE sqrthalf = SQRTHALF*DATA_ONE;
	DATA_TYPE *x, *y, e;
        DATA_TYPE cc1, ss1, cc3, ss3, cas1, cas3;
        int n2, n4, n8, i, j, a, a3, pc, nminus = n-1;
	int n_2 = n>>1, n_4 = n>>2, n3_4 = n_2+n_4;

	if (n!=current)
	  initsincos(n);
        x = z-1; 
        n2 = n+n;
	pc = 1;
        while(nn >>= 1) {
                is = 0;
                id0 = n2;
                n2 >>= 1;
                n4 = n2>>2;
                n8 = n4>>1;
                do {
 		     if(n4==1) {
                       	     for(i=is;i<n;i+=id0) {
                                x1 = x+i+1;
                                x2 = x1 + n4;
                                x3 = x2 + n4;
                                x4 = x3 + n4;
                                t1 = *x1 - *x3;
                                *x1 += *x3;
                                *x2 += *x2;
				*x3 = *x4; *x3 += *x3;
				*x4 = *x3 + t1;
                                *x3 = t1 - *x3;
			     }
		      } else {
                             x1 = x+is+1;
                             x2 = x1 + n4;
                             x3 = x2 + n4;
                             x4 = x3 + n4;
			     i0 = id0-n8;
                             for(i=is;i<n;i+=id0) {
                                t1 = *x1 - *x3;
                                *x1 += *x3;
                                *x2 += *x2;
				*x3 = *x4; *x3 += *x3;
				*x4 = *x3 + t1;
                                *x3 = t1 - *x3;
                                x1 += n8;
                                x2 += n8;
                                x3 += n8;
                                x4 += n8;
                                t1 = MUL((*x2 - *x1),sqrthalf);
                                t2 = MUL((*x4 + *x3),sqrthalf);
                                *x1 += *x2;
                                *x2 = *x4 - *x3;
				t3 = t1 - t2;
				*x4 = t3 + t3;
				t3 = -t2 - t1;  /* $$$rec fixed bug. */
				*x3 = t3 + t3;
				x1 += i0;
				x2 += i0;
				x3 += i0;
				x4 += i0;
                              }
			}
	    		id0 += id0;
	    		is = id0-n2;
	    		id0 += id0;
                } while(is<nminus);
                
                
                a = pc;
                for(j=2;j<=n8;j++) {
                       is = 0;
                       id0 = n2+n2;
			
// if((a==0) || (a==n_4) || (a==n_2) || (a==n3_4)) {
//	printf("%d %d %d\n",a,j,nn);
// }
		       if(a == 0) { /* (1+0i, 1+0i) butterfly. */
			   a += pc;
			   a &= nminus;
                        do {
			    x1 = x + is+j;
			    x2 = x1 + n4;
			    x3 = x2 + n4;
			    x4 = x3 + n4;
			    x5 = x2 + 2 - j - j;
			    x6 = x5 + n4;
			    x7 = x6 + n4;
			    x8 = x7 + n4;
			    for(i = is+id0; i<n ;i+= id0) {
                                t1 = *x1 - *x6;
                                *x1 += *x6;
                                t2 = *x5 - *x2;
                                *x5 += *x2;
                                t3 = *x8 + *x3;
                                *x6 = *x8 - *x3;
                                t4 = *x4 + *x7;
                                *x2 = *x4 - *x7;
                                t5 = t1 - t4;
                                t1 += t4;
                                t4 = t2 - t3;
                                t2 += t3;
				
				*x3 = t5;  /* Trivial 'fly. */
				*x7 = -t4;
				*x4 = t1;
				*x8 = t2;

				x1 += id0;
				x2 += id0;
				x3 += id0;
				x4 += id0;
				x5 += id0;
				x6 += id0;
				x7 += id0;
				x8 += id0;
                           }
                           t1 = *x1 - *x6;
                           *x1 += *x6;
                           t2 = *x5 - *x2;
                           *x5 += *x2;
                           t3 = *x8 + *x3;
                           *x6 = *x8 - *x3;
                           t4 = *x4 + *x7;
                           *x2 = *x4 - *x7;
                           t5 = t1 - t4;
                           t1 += t4;
                           t4 = t2 - t3;
                           t2 += t3;

			   *x3 = t5;
			   *x7 = t5 - t4;
			   *x8 = t2;
			   *x4 = t1 - t2;

	    		   id0 += id0;
	    		   is = id0-n2;			   
	    		   id0 += id0;
                        } while(is<nminus);
		       } else if(a == n_4) { /* (0+1i, 0-1i) butterfly. */
			   a += pc;
			   a &= nminus;
                        do {
			    x1 = x + is+j;
			    x2 = x1 + n4;
			    x3 = x2 + n4;
			    x4 = x3 + n4;
			    x5 = x2 + 2 - j - j;
			    x6 = x5 + n4;
			    x7 = x6 + n4;
			    x8 = x7 + n4;
			    for(i = is+id0; i<n ;i+= id0) {
                                t1 = *x1 - *x6;
                                *x1 += *x6;
                                t2 = *x5 - *x2;
                                *x5 += *x2;
                                t3 = *x8 + *x3;
                                *x6 = *x8 - *x3;
                                t4 = *x4 + *x7;
                                *x2 = *x4 - *x7;
                                t5 = t1 - t4;
                                t1 += t4;
                                t4 = t2 - t3;
                                t2 += t3;
				
				*x3 = t4;  /* Trivial 'fly. */
				*x7 = t5;
				*x4 = t2;
				*x8 = -t1;
	
				x1 += id0;
				x2 += id0;
				x3 += id0;
				x4 += id0;
				x5 += id0;
				x6 += id0;
				x7 += id0;
				x8 += id0;
                           }
                           t1 = *x1 - *x6;
                           *x1 += *x6;
                           t2 = *x5 - *x2;
                           *x5 += *x2;
                           t3 = *x8 + *x3;
                           *x6 = *x8 - *x3;
                           t4 = *x4 + *x7;
                           *x2 = *x4 - *x7;
                           t5 = t1 - t4;
                           t1 += t4;
                           t4 = t2 - t3;
                           t2 += t3;

			   *x3 = t4 - t5;
			   *x7 = t5;
			   *x8 = -t1;
			   *x4 = t2;

	    		   id0 += id0;
	    		   is = id0-n2;			   
	    		   id0 += id0;
                        } while(is<nminus);			
		       } else if(a == n_2) { /* (-1+0i, -1+0i) butterfly. */
			   a += pc;
			   a &= nminus;
                        do {
			    x1 = x + is+j;
			    x2 = x1 + n4;
			    x3 = x2 + n4;
			    x4 = x3 + n4;
			    x5 = x2 + 2 - j - j;
			    x6 = x5 + n4;
			    x7 = x6 + n4;
			    x8 = x7 + n4;
			    for(i = is+id0; i<n ;i+= id0) {
                                t1 = *x1 - *x6;
                                *x1 += *x6;
                                t2 = *x5 - *x2;
                                *x5 += *x2;
                                t3 = *x8 + *x3;
                                *x6 = *x8 - *x3;
                                t4 = *x4 + *x7;
                                *x2 = *x4 - *x7;
                                t5 = t1 - t4;
                                t1 += t4;
                                t4 = t2 - t3;
                                t2 += t3;
					
				*x3 = -t5;  /* Trivial 'fly. */
				*x7 = t4;
				*x4 = -t1;
				*x8 = -t2;
				
				x1 += id0;
				x2 += id0;
				x3 += id0;
				x4 += id0;
				x5 += id0;
				x6 += id0;
				x7 += id0;
				x8 += id0;
                           }
                           t1 = *x1 - *x6;
                           *x1 += *x6;
                           t2 = *x5 - *x2;
                           *x5 += *x2;
                           t3 = *x8 + *x3;
                           *x6 = *x8 - *x3;
                           t4 = *x4 + *x7;
                           *x2 = *x4 - *x7;
                           t5 = t1 - t4;
                           t1 += t4;
                           t4 = t2 - t3;
                           t2 += t3;

			   *x3 = -t5;
			   *x7 = t4;
			   *x8 = -t2;
			   *x4 = -t1;

	    		   id0 += id0;
	    		   is = id0-n2;			   
	    		   id0 += id0;
                        } while(is<nminus);		       
		       } else if(a == n3_4) { /* (0-1i,0+1i) butterfly. */
			   a += pc;
			   a &= nminus;
                        do {
			    x1 = x + is+j;
			    x2 = x1 + n4;
			    x3 = x2 + n4;
			    x4 = x3 + n4;
			    x5 = x2 + 2 - j - j;
			    x6 = x5 + n4;
			    x7 = x6 + n4;
			    x8 = x7 + n4;
			    for(i = is+id0; i<n ;i+= id0) {
                                t1 = *x1 - *x6;
                                *x1 += *x6;
                                t2 = *x5 - *x2;
                                *x5 += *x2;
                                t3 = *x8 + *x3;
                                *x6 = *x8 - *x3;
                                t4 = *x4 + *x7;
                                *x2 = *x4 - *x7;
                                t5 = t1 - t4;
                                t1 += t4;
                                t4 = t2 - t3;
                                t2 += t3;
				
				*x3 = -t4;  /* Trivial 'fly. */
				*x7 = -t5;
				*x4 = -t2;
				*x8 = t1;
	
				x1 += id0;
				x2 += id0;
				x3 += id0;
				x4 += id0;
				x5 += id0;
				x6 += id0;
				x7 += id0;
				x8 += id0;
                           }
                           t1 = *x1 - *x6;
                           *x1 += *x6;
                           t2 = *x5 - *x2;
                           *x5 += *x2;
                           t3 = *x8 + *x3;
                           *x6 = *x8 - *x3;
                           t4 = *x4 + *x7;
                           *x2 = *x4 - *x7;
                           t5 = t1 - t4;
                           t1 += t4;
                           t4 = t2 - t3;
                           t2 += t3;

			   *x3 = -t4;
			   *x7 = t5;
			   *x8 = t1;
			   *x4 = -t2;

	    		   id0 += id0;
	    		   is = id0-n2;			   
	    		   id0 += id0;
                        } while(is<nminus);				
		       } else { 
			a3 = a + a;
			y = cossinarr + a3;
			a3 += a; a3 &= nminus;                        
                        a += pc;
			a &= nminus;
                        cc1 = *y++;
                        ss1 = *y;
			a3 += a3;
			y = cossinarr + a3;                        
                        cc3 = *y++;
                        ss3 = *y;
			cas1 = cc1 + ss1;
			cas3 = cc3 + ss3;

			
                        do {
			    x1 = x + is+j;
			    x2 = x1 + n4;
			    x3 = x2 + n4;
			    x4 = x3 + n4;
			    x5 = x2 + 2 - j - j;
			    x6 = x5 + n4;
			    x7 = x6 + n4;
			    x8 = x7 + n4;
			    for(i = is+id0; i<n ;i+= id0) {
                                t1 = *x1 - *x6;
                                *x1 += *x6;
                                t2 = *x5 - *x2;
                                *x5 += *x2;
                                t3 = *x8 + *x3;
                                *x6 = *x8 - *x3;
                                t4 = *x4 + *x7;
                                *x2 = *x4 - *x7;
                                t5 = t1 - t4;
                                t1 += t4;
                                t4 = t2 - t3;
                                t2 += t3;
				
                               /*
			          These old butterflies have been replaced
			          by 3-mul convolutions.
			        *x3 = MUL(t5,cc1) + MUL(t4,ss1);
                                *x7 = MUL(t5,ss1) - MUL(t4,cc1);
                                *x4 = MUL(t1,cc3) - MUL(t2,ss3);
                                *x8 = MUL(t2,cc3) + MUL(t1,ss3);
				*/
				
				t3 = MUL((t5 + t4),cas1);
				t4 = MUL(t4,cc1);
				t5 = MUL(t5,ss1);
				*x3 = t3 - t4 - t5;
				*x7 = t5 - t4;
				t3 = MUL((t1+t2),cas3);
				t2 = MUL(t2,ss3);
				t1 = MUL(t1,cc3);
				*x8 = t3 - t2 - t1;
				*x4 = t1 - t2;
				
				x1 += id0;
				x2 += id0;
				x3 += id0;
				x4 += id0;
				x5 += id0;
				x6 += id0;
				x7 += id0;
				x8 += id0;
                           }
                           t1 = *x1 - *x6;
                           *x1 += *x6;
                           t2 = *x5 - *x2;
                           *x5 += *x2;
                           t3 = *x8 + *x3;
                           *x6 = *x8 - *x3;
                           t4 = *x4 + *x7;
                           *x2 = *x4 - *x7;
                           t5 = t1 - t4;
                           t1 += t4;
                           t4 = t2 - t3;
                           t2 += t3;

			   t3 = MUL((t5+t4),cas1);
		           t4 = MUL(t4,cc1);
			   t5 = MUL(t5,ss1);
			   *x3 = t3 - t4 - t5;
			   *x7 = t5 - t4;
			   t3 = MUL((t1+t2),cas3);
			   t2 = MUL(t2,ss3);
			   t1 = MUL(t1,cc3);
			   *x8 = t3 - t2 - t1;
			   *x4 = t1 - t2;

	    		   id0 += id0;
	    		   is = id0-n2;			   
	    		   id0 += id0;
                        } while(is<nminus);
		     }
                }
		pc += pc;
        }
        is = 1;
        id0 = 4;
        do {
          for(i0=is;i0<=n;i0+=id0){
                i1 = i0+1;
                e = x[i0];
                x[i0] = e + x[i1];
                x[i1] = e - x[i1];
          }
	    id0 += id0;
	    is = id0-1;
	    id0 += id0;
        } while(is<n);
        scramble_data(z, n);

#ifdef FRACTION
/* this is 4% slower than the shift version
	e = DOUBLE_TO_DATA(1/(double)n);
        for(i=(n>>2), x = z; --i != -1;)   { 
		*x++ = MUL(*x,e);
		*x++ = MUL(*x,e);
		*x++ = MUL(*x,e);
		*x++ = MUL(*x,e);
	} 
*/
	is = 1;
	while((1<<is)<n) ++is;
        for(i=(n>>2), x = z; --i != -1;)  { 
		*x++ >>= is;
		*x++ >>= is; 
		*x++ >>= is; 
		*x++ >>= is; 
	} 
#else
	e = DOUBLE_TO_DATA(1/(double)n);
        for(i=(n>>2), x = z; --i != -1;)   { 
		*x++ *= e;
		*x++ *= e;
		*x++ *= e;
		*x++ *= e;
	} 
#endif	                                        
}

#ifdef _TEST_PROGRAM

/*

 Test

*/

#import <mach/time_stamp.h>
double getTime() {
    struct tsval ts;
#define MAX_TIME ((double)0xffffffff)
    kern_timestamp(&ts);
    return (((double)ts.high_val) * MAX_TIME + ((double)ts.low_val))/1000000;
}

double x[MaxN];
double y[MaxN];
double xdft[MaxN];

DATA_TYPE fx[MaxN];

/* dft - for testing */
static void rdft(double *x, double *y, int len)
{
    double step = TWOPI / len;
    register int k, l;
    register double ang, dAng;
    register double xr,acr,aci;
    
    acr = 0.0;
    for (l = 0; l < len; l++)
      acr += x[l];
    y[0] = acr;

    dAng = 0.0;
    for (k = 1; k < (len>>1); k++) {
	acr = 0.0;
	aci = 0.0;
	ang = 0.0;
	dAng += step;
	for (l = 0; l < len; l++) {
	    xr = x[l];
	    acr += xr * cos(ang);
	    aci -= xr * sin(ang);
	    ang += dAng;
	}
	y[k] = (double)acr;
	y[len-k] = (double)aci;
    }

    dAng += step;
    acr = 0.0;
    for (l = 0; l < len; l+=2) {
	acr += x[l];
	acr -= x[l+1];
    }
    y[len>>1] = acr;

}

void main(int argc, char *argv[])
{
    double s,t;
    double err,e,ss;
    int i,N,sig;

#include "hfft_test.dat"

    if (argc > 2) N = atoi(argv[2]); else N = MaxN;
    if (N > MaxN) N = MaxN;

    printf("N=%d\n",N);

    sig = 5;
    if (argc > 1) sig = atoi(argv[1]);
    switch (sig) {
	case 0:
	    printf("Doing cos() test signal...\n");
	    t = 2.0 * M_PI / N;
	    if (argc > 2) t *= atof(argv[2]);
	    s = M_PI / 2.0;
	    if (argc > 3) s *= atof(argv[3]);
	    for (i = 0; i < N; i++)
		x[i] = cos(i*t+s);
	    break;
	case 1:
	    printf("Doing step test signal...\n");
	    for (i = 0; i < N/2; i++)
		x[i] = 1.0;
	    for (i = N/2; i < N; i++)
		x[i] = 0.0;
	    break;
	case 2:
	    printf("Doing constant test signal...\n");
	    for (i = 0; i < N; i++)
		x[i] = 1.0;
	    break;
	case 3:
	    printf("Doing hyperbola test signal...\n");
	    for (i = 0; i < N; i++)
		x[i] = (double)i/N;
	    break;
	case 4:
	    printf("Doing impulse test signal...\n");
	    for (i = 0; i < N; i++)
		x[i] = 0.0;
	    i = N >> 1;
	    if (argc > 2) i = atoi(argv[2]);
	    x[i] = 1.0;
	    break;
	case 5:
	    if (1) {
		int count = 1000;
		double start_time, end_time;	
		for (i = 0; i < N/2; i++)
		    x[i] = 1.0;
		for (i = N/2; i < N; i++)
		    x[i] = 0.0;
		printf("Doing performance test...\n");
		for (i=0;i<N;i++)
		    fx[i] = DOUBLE_TO_DATA(x[i]);
		/* grease the path: */
		fft_hermitian(fx, N);
		fft_inverse_hermitian(fx, N);  exit(0);
		start_time = getTime();
		for (i=0; i<count; i++) {
		    fft_hermitian(fx, N);
		    fft_inverse_hermitian(fx, N);
		}
		end_time = getTime();
		printf("transform and inverse, %d times, took %g seconds\n", 
		       count, end_time - start_time);
		exit(0);
	    }
	    break;
	case 6:
	    printf("Doing windowedBuffer test signal...\n");
	    for (i = 0; i < MIN(N,512); i++)
		x[i] = windowedBuffer[i];
	    break;
	default:
	    printf("No such test signal...\n");
	    exit(1);
	    break;
    }
    
    
    for (i=0;i<N;i++)
      y[i] = x[i];

    printf(" Signal: ");
    for (i=0;i<N;i++)
      printf("%f ",x[i]);
    printf("\n");

    rdft(x,xdft,N);
    for (i=0;i<N;i++)
      fx[i] = DOUBLE_TO_DATA(x[i]);

    fft_hermitian(fx, N);

    err = 0.0;
    ss = 0.0;
    for (i=0;i<N;i++) {
	e = DATA_TO_DOUBLE(fx[i]) - xdft[i];
	err += e*e;
	e = DATA_TO_DOUBLE(fx[i]);
	ss += e*e;
	printf("FFT[%d] = %f \t RDFT[%d] = %f\n",i, DATA_TO_DOUBLE(fx[i]),i,xdft[i]);
    }
    err = sqrt(err/ss);
    printf("RMS |FFT-DFT|/|FFT| error = %f\n",err);

    fft_inverse_hermitian(fx, N);
    for (i=0;i<N;i++)
      x[i] = DATA_TO_DOUBLE(fx[i]);

    err = 0.0;
    for (i=0;i<N;i++) {
	e = y[i] - x[i];
	err += e*e;
    }
    err = sqrt(err/ss);
    printf("RMS |x-IFFT(FFT(x))|/|x| error = %f\n",err);
}

#endif
