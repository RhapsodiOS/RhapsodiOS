;;;;
;; Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
;;
;; @APPLE_LICENSE_HEADER_START@
;; 
;; "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
;; Reserved.  This file contains Original Code and/or Modifications of
;; Original Code as defined in and that are subject to the Apple Public
;; Source License Version 1.0 (the 'License').  You may not use this file
;; except in compliance with the License.  Please obtain a copy of the
;; License at http://www.apple.com/publicsource and read it before using
;; this file.
;; 
;; The Original Code and all software distributed under the License are
;; distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
;; EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
;; INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
;; License for the specific language governing rights and limitations
;; under the License."
;; 
;; @APPLE_LICENSE_HEADER_END@
;;;;
; ************************************************************************
; *                                                                      *
; *    AUDIO TRANSFORM CODER  EQUATES  					 *
; *                      						 *
; *	SANDEEP POMBRA	OCT 7, 1991					 *
; *									 *
; ************************************************************************
;


MAX_FRAME_EXPONENT	equ	16	; less than 22

MAX_EXPONENT		equ	15	; adds to frame exponent
					; sum less than 22
MANTISSA_SIZE		equ	4

WORD_SIZE		equ	16


FRAME_SIZE		equ	512	; good fft size for 44khz sample rate
					; should be 2^k
						
NCB			equ	40	; no. of critical bands
NCBW			equ	10	; (NCB*4)/16 should be int
						

FRAME_STEP		equ	256	; frame step size = framesize/2
					; should be 2^k

FFTCOEFF		equ	$100	; FFT coeff table in DSP Y ROM

FFTTABLE		equ	256	; FFT coeff table size

ALL_PV			equ	$00FFFF	; all present vector

PI			equ	3.141592654

; Maximum size of the coded data
MAX_CODED_SIZE		equ   (1+NCBW+FRAME_STEP*(1+MANTISSA_SIZE)/WORD_SIZE)


; equates for memory locations
EXT_L_MEM		equ	$A800	;starting address of xfc l ext mem
					; multiple of framestep = 2^k


						
						
						
						





