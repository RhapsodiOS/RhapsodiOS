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
; *    ATC_SPEC.ASM - TRANSFORM CODER					 *
; *    PROCESS SPECTRUM							 *
; ************************************************************************


; ***************************************************************************
; begin of process_spectrum
process_spectrum

; g_buf[x,0..255] contains the dct/dst data
; r7 points to datap coded data (x memory)
	move	#datap,r7

; find peak spectral value (use r0,b,y0), max value in a, buffer size in x0
	move	#g_buf,r0
	move	#>FRAME_STEP,x0
	maxmagx	0

	move	#>(MAX_FRAME_EXPONENT),x0

; if max magnitude = 0 then silent frame
	tst	a	#1,n0	
	jeq	<silent

; Now a contains peak spectral value normalize to get frame exponent
; uses a,r0,n0
	nrm24	0	; r0 contains frame exponent	

fe_done
; 		if(frameExponent==16) {
	move	r0,a
	cmp	x0,a	#1,n0	; number of coded words for silent case	
	jlt	<not_silent


silent
;	write frame exponent
	move	x0,x:(r7) 
	jmp	<wrdma


not_silent

;	store frame exponent
	move	r0,n0		; save frame exponent in n0
	move	r0,x:(r7)+	; save frame exponent in datap



;	Get exponents and left shift data and quantize exponents
;	Zero mantissas below threshold
	move	#(g_buf),r5	
	move	#cblo,r1	; cblo(y), cbth (x) pointer
	move	#exponent,r6	; exponent pointer
	move	#cbwid,r4	; cbwid pointer
	move	#>(lshft),y1	; lshft pointer


	do	#(NCB),_endnorm		

	move	r5,y0		
	move	y:(r1),b	; b = cblo[i]
	add	y0,b	y:(r4)+,x0	;b = fftbf+cblo[i], x0 =cbwid[i]
	move	b1,r2			;r2 =fftbf+cblo[i]
	move	b1,n1			;n1 =fftbf+cblo[i]


;	Zero mantissas below threshold
	clr	b	x:(r1)+,x1	      
	do	x0,_endzb
	move	x:(r2),a
        cmpm     x1,a	
        tlt     b,a  
	move	a,x:(r2)+	
_endzb


; 	find peak spectral value for each critical bin
;	(use r2,b,y0), max value in a, buffer size in x0
	move	n1,r2	; restore r2
	nop
	maxmagx	2

;	if bin is all zeros skip processing
	tst	a	#0,n3  ; n3 contains bin exp
	jeq	<_endfbe


; Now a contains peak spectral value normalize to get  bin exponent
; uses r2,n2,a
	nrm24	2	; r2 contains frame exponent+bin exponent
	move	n0,n2	; fe
	move	y1,b	; lshft pointer
	lua	(r2)-n2,r0	; r0 contains bin exponent (n2 fe)
	move	r2,a		;a contains frame exponent+bin exponent
	
	tst	a	r0,n3	; n3 contains bin exp
	jeq	<_endfbe

;	leftshift data by binexponent+frame exponent
	sub	a,b	n1,r2  ; lshft-(fe+exp)	get bin pointer
	move	b1,r0
	nop
	move	x:(r0),x1
	move	r2,r0
	move	x:(r2)+,y0
	do	x0,_endfbe
	mpy	x1,y0,a		x:(r2)+,y0
	move	a0,a1		; make sure left shift saturates	
	move	a,x:(r0)+
_endfbe

;	quantize exponent
	move	n3,b	; move exp in b for quant exp
	move	#>(MAX_EXPONENT),y0
	cmp	y0,b	; b contains frame exponent
	tgt	y0,b
	move	b,y:(r6)+

_endnorm


; 	quantize mantissas 
	jsr	<quantmant

;	pack exponents
	jsr	packexp

;	pack mantissas
	jsr	<packmant


;	write coded data to dma
;	n0 contains number of data words
wrdma
;	Restore registers used by putwordDMA
	move	#datap,r4
	move 	x:<save_r7,r7
	move 	x:<save_m7,m7
;
; 	Prepend frame byteCount to first short of this frame (with exponent)
	move	n0,X1		; wordCount
	clr A	#>@pow(2,-15),X0 ; shifter
	move	x:(r4),A0 	; frameExponent
	mac	X0,X1,A		; assemble in A0
	move	A0,x:(r4)	; byteCount,,frameExponent
	
	do	n0,_end_wrdma
	move	x:(r4)+,a
	jsr	putWordDMA		; write a coded word to DMA 
					; don't use r4	
_end_wrdma

	warn 'check for overflow here and go to second word for size count'
	move x:atc_outsize,a
	move n0,x0
	add x0,a
	move a,x:atc_outsize

	rts

;    +--------------------------------------------------------------------+
;    +  Function Name : packmant
; 	pack mantissa
;    +--------------------------------------------------------------------+
;
packmant			; mantissa pointer r5

	move	#(g_buf),r4
	move	#(mantp),r0	; packed mantissa start address	
	move	#(rshft+7),r5	; right shift by 7
	clr a	x:<allpv,y1	; count in a , presence word in y1	
	move	x:<int_1,y0	; $000001 bit count  
	move	a,x:<tmpp	; packed word in tmpp

	move	x:(r4)+,b	; mantissa
	
; 	for(i=0; i<FRAME_STEP; i++) {
	do	#(FRAME_STEP),_endmant
	tst	b	b,x0	; test for zero
	jne	<manpre
	move	y1,b
	eor	y0,b		; zero out presence bit
	move	b1,y1
	jmp	<nextbit

manpre
	move	r5,b	; rshft by 7 address
	add	a,b	; rshft by 7+a address
	move	b1,r2
	move	x0,b
	lsr	b	x:(r2),x1
	move	b1,x0	; rshft by 1 to make it 8 (also x0 always positive)
	mpy	x1,x0,b	 	x:<tmpp,x0
	or	x0,b	x:<mant_size,x1	
	add	x1,a	x:<word_size,x1
	cmp	x1,a	b,x:<tmpp
	jne	<nextbit
	move	b1,x:(r0)+	;	write packed mantissa
	clr 	a	
	move	a,x:<tmpp


nextbit	
	move	y0,b
	lsl	b	x:<pbcount,x1
	cmp	x1,b	b,y0
	jne	<mantl1

	move	y1,x:(r7)+	; write presence bit
	move	x:<allpv,y1	; next	time all present
	move	x:<int_1,y0	; presence bit

mantl1
	move	x:(r4)+,b	; mantissa
_endmant


	move	#datap,n0	; start of coded data
	tst	a	x:<tmpp,x0	
	jeq	<fullword
	move	x0,x:(r0)+	; ship partially packed word

fullword
	move	(r0)-n0
	move	r0,n0	; n0 contains number of coded words

	rts


;    +--------------------------------------------------------------------+
;    +  Function Name : quantmant
; 	quantize mantissas to four bit using mag trunc
;	r5 contains mantissa buffer
;    +--------------------------------------------------------------------+
;
quantmant
	move	#$F0,x1
	move	#$10,x0
	move	#$88,y1
	do	#(FRAME_STEP),_endqm	
	move	x:(r5),a1	
	and	x1,a	a1,b1	; qu= xu & $F00000 xu
	add	x0,a	a1,y0	; qu =qu+$100000 qu
	and	y1,b		; xu & $880000
	eor	y1,b		; (xu & $880000) == $880000
	tne	y0,a
	move	a1,x:(r5)+	; unsigned
_endqm

	rts

;    +--------------------------------------------------------------------+
;    +  Function Name : packexp
; 	pack exponents
;    +--------------------------------------------------------------------+
;

;	--- moved to partition 2 --- (atc_dsp.asm, bottom)




