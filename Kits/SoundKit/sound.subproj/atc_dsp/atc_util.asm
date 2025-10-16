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
; *    ATC_UTIL.ASM - TRANSFORM CODER					 *
; *    MAIN LOOP AND FFT PROCESSING					 *
; ************************************************************************


; ************************************************************************
; *                                                                      *
; *  Program resided inside DSP internal memory                          * 
; *                                                                      *
; ************************************************************************
;
	org	p:

; ***************************************************************************
; begin of process_frame

	
process_frame

; Save registers clobbered by this program.
; NOTE: the regs must be saved before and restored after the "blkl" 
; transfers below which save/restore on-chip l memory that is clobbered
; by subsequent program.


	jsr 	save_atc_io_pointers

;	save  internal variables used by DMA and program.
	blkl	0,intmem_save,NUM_INTMEM  ; fftbuf used from here onwards


; Load FFT buffer from input frame.
; Also apply window.
; Here we do 2N point real fft using a N point complex fft.
; Hence The even input data points are stored in X memory(fftbuf),
; while odd input data points are stored in Y memory(fftbuf).
	jsr	<load_inbuf

fin_load
; 
; radix 2, In-Place, Decimation-In-Time FFT
; (using DSP56001 Y Data ROM sine-cosine tables).  
; Call the FFTR2D macro
;
;       256 point complex, in-place FFT
;       Data starts at address #fftbuf
;       Coefficient table starts at address FFTCOEFF=$100
; 	(stored at address $100 in the DSP56001 Y Data ROM)
;	The SINEWAVE macro generates identical coefficients to
; 	those stored at address $100 in the DSP56001 Y Data ROM.
;                          
        fftr2d FRAME_STEP,fftbuf,FFTCOEFF,FFTTABLE

; Calculate the 2N point real fft using a N point complex fft.
	jsr	<process_post_fft


; Alternate between dct/dst
	btst    #0,x:frame_number
	jscs	<process_dct

	btst    #0,x:frame_number
	jscc	<process_dst


;	Restore internal variables
	blkl	intmem_save,0,NUM_INTMEM	; fftbuf not used anymore



; Process Spectrum
	jsr	<process_spectrum


; Increment frame number  if mono or stereo (channel 1)
; toggle channel index between 0 and 1
	jsr	update_frame_number

;	Restore registers used by DMA
;	r7,m7 restored in process_spectrum
	move 	x:<save_r6,r6
	move 	x:<save_m6,m6

        rts




;    +--------------------------------------------------------------------+
;    +  Function Name : load_inbuf
; 	Load frame buffer from input frame.
; 	Also apply window.
; 	Here we do 2N point real fft using a N point complex fft.
; 	Hence The even input data points are stored in X memory(fftbuf),
; 	while odd input data points are stored in Y memory(fftbuf).
;    +--------------------------------------------------------------------+
;
load_inbuf

	move	x:in_ptr,r0	;load input pointer
	move	x:channel_index,n0 ; load channel index	
	move	#window_buf,r5	;initialize window pointer
	move	#(DMA_READ_SIZE<<1)-1,m0 ; make it modulo
	move	#fftbuf,r1	;initialize fft input pointer 
	move	(r0)+n0		; update using channel index (always 0 for mono)
	move	x:atc_channels,n0	; 1 for mono, 2 for stereo

	move	x:(r5),x1	; get even window
	move	x:(r0)+n0,x0	; get even input 

	do	#(FRAME_STEP),_end_load
	mpyr	x0,x1,a 	x:(r0)+n0,y0	
				; apply even window  get odd input  	
	move	a,x:(r1) 	y:(r5)+,y1	
				; even output odd window
	mpyr	y0,y1,b 	x:(r0)+n0,x0
				; apply odd window  get even input
	move	x:(r5),x1      b,y:(r1)+
				; get even window  odd output
_end_load

;	update in_ptr
	move	x:in_ptr,r0
	move	#(FRAME_STEP),n0
	jmp_mono <mono_ptr
	jmp_chan0 <same_ptr	; in_ptr same for channel 0 in stereo
mono_ptr
	move x:atc_channels,x0
	rep x0
	move (r0)+n0

	move	r0,x:in_ptr
same_ptr
	move	#-1,m0	;restore m0 to linear
	rts



;    +--------------------------------------------------------------------+
;    +  Function Name : process_post_fft
; 	Calculate the 2N point real fft(fftbuf) 
;	using a N point complex fft(fftbuf).
;    +--------------------------------------------------------------------+
;

process_post_fft

;	Get the two real fft's(g_buf,h_buf) from one complex fft (fftbuf)
;	br(k) = ar(N-k), bi(k) = ai(N-k)
;	gr = (ar + br)/2
;	gi = (ai - bi)/2
;	hr = (ai + bi)/2
;	hi = (-ar + br)/2
;

; Address pointers are organized as follows:
;
;  r2 = ar,ai input pointer (fftbuf)	m2 = 0  n2 =FRAME_STEP/2 (br) (r2)+n2
;  r1 = br,bi input pointer (fftbuf)	m1 = 0  n1 =FRAME_STEP/2 (br) (r1)-n1
;  r5 = gr gi output pointer (g_buf)				
;  r4 = hr hi output pointer (h_buf)				

	move	#fftbuf,r2	;initialize fft (start) pointer
	move	r2,r1
	move	#g_buf,r5		;initialize G pointer (complex)
	move	#h_buf,r4		;initialize H pointer (complex)

;	Set registers for Bit reverse addressing for the FFT
	move	#0,m1		;initialize C address modifier for
				;reverse carry (bit-reversed) addressing
	move	m1,m2			
	move	#FRAME_STEP/2,n1	;initialize C pointer offset
	move	n1,n2

	move		x:(r2),x0	;ar	
	move		x:(r1),a	;br
	do	#(FRAME_STEP),_end_gh
	add	x0,a			y:(r2)+n2,b	;ar+br ai(br addr) 
	asr	a			y:(r1)-n1,y0	;ar+br/2 bi(br addr) 
	sub	x0,a	a,x:(r5)			;br-ar/2 gr
	sub	y0,b	x:(r2),x0	a,y:(r4)	;ai-bi ar hi
	asr	b			x:(r1),a	;ai-bi/2 br
	add	y0,b	b,y:(r5)+			;ai+bi/2 gi
	move	b,x:(r4)+				; hr 
_end_gh

	move	#-1,m1	;restore m1 to linear
	move	m1,m2	;restore m2 to linear


;Get one 2N point real fft (fftbuf) from two N point real fft's(g_buf,h_buf)
;             ___________
;            |           | 
; gr,gi ---->|  Radix 2  |----> fr,fi
; hr,hi ---->| Butterfly |
;            |___________|
;                  ^
;                  |
;                wr,wi
;	w = exp(j 2 pi k / 2N) = (wr,wi)
;	fr = (gr + wr*hr + wi*hi)/2 ( /2 to make the spectrum in [-1,1])
;	fi = (gi - wi*hr + wr*hi)/2  
;
; Address pointers are organized as follows:
;
;  r1 = gr,gi input pointer	(g_buf)
;  r2 = hr,hi input pointer	(h_buf)
;  r5 = fr,fi output pointer	(fftbuf)
;  r4 = wr,wi input pointer	(w2nbuf)


	move	#g_buf,r1		;initialize G pointer (complex)
	move	#h_buf,r2		;initialize H pointer (complex)
	move	#w2nbuf,r4	;w2n pointer
	move	#fftbuf,r5	;output fft pointer
	ori	#$4,mr		; set scaling mode to /2

	move	x:(r2),x1	y:(r4),y0	;hr wi
	move			y:(r1),b	;gi 
	do	#(FRAME_STEP),_endff	
	mac	-y0,x1,b	x:(r4)+,x0	y:(r2)+,y1 ;gi- wi*hr wr hi
	macr	x0,y1,b		x:(r1)+,a	           ;gi-wi*hr+wr*hi gr
	mac	x1,x0,a		x:(r2),x1	b,y:(r5)   ;gr+wr*hr hr fi
	macr	y1,y0,a				y:(r4),y0  ;gr+wr*hr+wi*hi wi
	move	a,x:(r5)+	y:(r1),b	;fr gi	
_endff

	andi	#$FB,mr		; reset scaling mode.
	rts



;    +--------------------------------------------------------------------+
;    +  Function Name : process_dct
; 	Calculate the dct from the fft
;	Note g_buf[x,i] = fftbuf[x,i]*cosw0 + fftbuf[y,i]*sinw0
;			 	0 <= i <= 255
;    +--------------------------------------------------------------------+
;

process_dct


;
;	dct = fr*nzr + fi*nzi
;
; Address pointers are organized as follows:
;
;  r1 = fr,fi input pointer (fftbuf x,y memory)	
;  r5 = nzr,nzi pointer	(nzbuf)
;  r2 = dct output pointer (g_buf x memory)	

	move	#fftbuf,r1	; fft pointer
	move	#nzbuf,r5	;nzbuf pointer
	move	#g_buf,r2	; dct pointer


	move	x:(r1),x0	;fr 
	move	x:(r5),x1	y:(r1)+,y1 ;nzr fi

	do	#(FRAME_STEP),_enddct

	mpy     x0,x1,a         x:(r1),x0	y:(r5)+,y0  ; fr*nzr  fr nzi
	macr    y0,y1,a         x:(r5),x1	y:(r1)+,y1  
						; fr*nzr+fi*nzi nzr fi
	move	a,x:(r2)+	 ; dct 
_enddct

	rts




;    +--------------------------------------------------------------------+
;    +  Function Name : process_dst
; 	Calculate the dst from the fft
;	Note g_buf[x,i] = fftbuf[x,i]*sinw0 - fftbuf[y,i]*cosw0
;			 	0 <= i <= 255
;    +--------------------------------------------------------------------+
;

process_dst

;
;	dst = fr*nzi - fi*nzr
;
; Address pointers are organized as follows:
;
;  r1 = fr,fi input pointer	(fftbuf x,y memory)	
;  r5 = nzr,nzi pointer	 (nzbuf)
;  r2 = dst out pout pointer (g_buf x memory)	


	move	#fftbuf,r1	; fft pointer
	move	#nzbuf,r5	;nzbuf pointer
	move	#g_buf,r2	; dst pointer

	move	x:(r1),x0	y:(r5),y0  ;fr nzi

	do	#(FRAME_STEP),_enddst

	mpy     x0,y0,a         x:(r5)+,x1	y:(r1)+,y1 
						; fr*nzi nzr fi
	macr    -x1,y1,a        x:(r1),x0	y:(r5),y0 
						; fr*nzi-fi*nzr fr nzi
	move	a,x:(r2)+		; dst  
_enddst

	rts
