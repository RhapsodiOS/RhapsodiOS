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
; *    atd_spec.asm - AUDIO TRANSFORM DECOMPRESSION			 *
; *    process spectrum
; ************************************************************************


; ***************************************************************************
; begin of process_spectrum
process_spectrum

; 	frameExponent = *in_ptr & (0x0000FF);
	readWordDMA A
	move	#>$ff,x0
	cmp	x0,a	; A1 = (frame_size,frame_exponent) > frame_exponent
	jle	break1	; if A is zero (frame_size = 0), we terminate
	and	x0,a
	move	a1,x:<frameExponent

; 		if(frameExponent==16) {
	move	#>(MAX_FRAME_EXPONENT),x0
	cmp	x0,a
	jne	<not_silent

	clr	a
	move	#g_buf,r1	; fft pointer
	rep	#(FRAME_SIZE/2)
	move	a,x:(r1)+
	rts

not_silent

	jsr	<unpackexp

;	inptr+=((NCB*4)/16) should be int

;	for (i=0; i<NPW; i++)
;		presp[i] = ip[i]
	move	#presp,r1	; presp pointer
	do	#(NPW),_endprs
	readWordDMA A0
	move	A0,x:(r1)+
_endprs
;
	jsr	<unpackmant



;	Denormalize
	move	#(g_buf),n2
	move	#cblo,r1	; cblo,cbgain pointer
	move	#exponent,r2	; cblo pointer
	move	#cbwid,r4	; cbwid pointer
	move	#>(rshft+AGCSHFT-4),y1	; rshift pointer + (AGC>=8) (- 4 for gain)

	do	#(NCB),endnorm		
	move	#cbgain,r5		; cbgain pointer
	move	n2,y0		
	move	y:(r1),a		; a = cblo[i]
	add	y0,a	y:(r4)+,x0	;a = g_buf+cblo[i], x0 =cbwid[i]
	move	a1,r0			;r0 =g_buf+cblo[i]
	move	x:(r2)+,b		;b= exp[i]

	add	y1,b	
					; b =  exp[i]+ rshft+AGC
	move	b1,r5			; r5 = exp[i]+ rshft+AGC
	move	x:(r1)+,y0		; y0=cbgain[i]
	move	x:(r5),x1		; x1 = right shift

	mpy	x1,y0,a	 x:(r0),y0	; a=cbgain*rigthtshift y0 = *(g_buf+cblo[i])
	move	a,x1			; x1=cbgain*rigthtshift 
	if DEBUG_VERSION
	  move x0,b
	  tst b
	  jne dn_ok
	  bset #B_BAD_WID,y:Y_DMA_STATUS	; X0 was not being saved
	  jsr abort
dn_ok	  nop
	endif
	do	x0,endrs
	mpyr	x1,y0,a
	move	a,x:(r0)+
	move	x:(r0),y0
endrs

	nop
endnorm

	rts




;    +--------------------------------------------------------------------+
;    +  Function Name : unpackexp
; 	unpack exponents
;    +--------------------------------------------------------------------+
;
unpackexp

	move	#exponent,r2	;  exponent pointer
	move	#>$f,y0
		
	do	#(NCBW),_endexp
	readWordDMA x0


; 	*ep++ = (*bp>>12) & (0x00000F);
	getnib	$c
	move	a1,x:(r2)+

; 	*ep++ = (*bp>>8) & (0x00000F);
	getnib	$8
	move	a1,x:(r2)+

; 	*ep++ = (*bp>>4) & (0x00000F);
	getnib	$4
	move	a1,x:(r2)+

; 	*ep++ = (*bp) & (0x00000F);
	move	x0,a	
	and	y0,a
	move	a1,x:(r2)+


_endexp	

	rts


;    +--------------------------------------------------------------------+
;    +  Function Name : unpackmant
; 	unpack mantissa
;    +--------------------------------------------------------------------+
;
unpackmant			
	move	#presp,r1	
	move	#(g_buf),r4	
	move	#>(BIT_FIELD_MASK),y0	; mantissa field in y0
	move	#(lshft-8),r5	; left shift by 8
	clr	a		; count in a
	move	#0,y1		; bitcount in y1
	move	x:(r1)+,b1
	move	b1,x:<tmpp	; presence bits in tmpp
	
; 	for(i=0; i<FRAME_STEP; i++) {
	do	#(FRAME_STEP),_endmant
	
	jset    #0,x:<tmpp,manpre
	clr	b
	move	b,x:(r4)+
	jmp	<nextbit

manpre
	tst	a
	jne	<nrddma
	readWordDMA x0
	clr 	a

nrddma	
	move	r5,b	; lshft by 8 address
	sub	a,b	; lshft by 8+a address
	move	b1,r2
	nop
	move	x:(r2),x1
	mpy	x1,x0,b
	move	b0,b
	and	y0,b	x:<mant_size,x1
	add	x1,a	x:<word_size,x1
	cmp	x1,a	b,x:(r4)+
	jne	<nextbit
	clr 	a

nextbit
	move	x:<int_1,b
	add	y1,b	x:<word_size,x1
	cmp	x1,b	b,y1
	jeq	<nextpr

	move	x:<tmpp,b1
	lsr	b
	jmp	<mantl1

nextpr	
	move x:(r1)+,b1		
	move	#0,y1

mantl1
	move b1,x:<tmpp	
	
_endmant
	
	rts

