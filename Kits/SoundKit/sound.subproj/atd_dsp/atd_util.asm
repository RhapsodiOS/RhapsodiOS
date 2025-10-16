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
; *    atd_util.asm - AUDIO TRANSFORM DECOMPRESSION			 *
; *    main loop and fft processing					 *
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

	if SHORT_CIRCUIT
	  warn 'process_frame short circuiting'
	  do #(FRAME_STEP),copy_loop
	    readShortDMA A
	    writeShortDMA A
copy_loop
	  rts
	endif


; update x:newoutstep for insert/delete samples if channel 0
;*	warn 'synch disabled'
	jsclr #0,x:chan,add_drop_samples	; channel 0 only

; Process Spectrum

	jsr	<process_spectrum

; Save registers clobbered by fftr2d and/or process_pre_ifft
; NOTE: the regs must be saved before and restored after the "blkl" 
; transfers below which save/restore on-chip l memory that is clobbered
; by fftr2d. 

	jsr 	save_io_pointers

;	save internal vars used by DMA and program

;*	mask_pio				; args ok if no on-chip state
	blkl	0,intmem_save,NUM_INTMEM	; fftbuf used from here onwards

; Now g_buf[0..255] (x) contains the dct/dst.
; Load fftbuf[0..255] (x = re ifft, y= img ifft) for ifft  
; Alternate between dct/dst

	btst    #0,x:frame_number
	jscs	<process_idct
	btst    #0,x:frame_number
	jscc	<process_idst


; Here we do 2N point real ifft using a N point complex fft.
; Calculate the 2N point real ifft using a N point complex fft.
; Hence The even output ifft points are stored in X memory,
; while odd output ifft points are stored in Y memory.

	jsr	<process_pre_ifft

; Radix 2, In-Place, Decimation-In-Time FFT
; (using DSP56001 Y Data ROM sine-cosine tables).  
; Call the FFTR2D macro
;
;       256 point complex, in-place FFT
;       input/output starts at address #fftbuf
;       Coefficient table starts at address FFTCOEFF=$100
; 	(stored at address $100 in the DSP56001 Y Data ROM)
;	The SINEWAVE macro generates identical coefficients to
; 	those stored at address $100 in the DSP56001 Y Data ROM.
;                          
        fftr2d FRAME_STEP,fftbuf,FFTCOEFF,FFTTABLE

; Now the even output data points are stored in X memory,
; while odd output data points are stored in Y memory.
; The window is also stored this way.
; Apply window and load frame buffer.

	jsr	<process_post_ifft

; Restore internal vars used by DMA and program

	blkl	intmem_save,0,NUM_INTMEM	; fftbuf not used anymore
;*	unmask_pio				; enable host_rcv intrpts

; Do shifting for frame exponent etc.

	jsr	<scale_data

; Do overlap add

	jsr 	restore_io_pointers

	jsr	<overlap_add	

; Increment channel number, bumping frame number when all channels done

	jmp_mono new_frame ; more generally, compare #channels to zero
	bchg	#0,x:<chan	; more generally, incr until = channels
	jcc	<same_frame
new_frame move	x:frame_number,a
 	  move	x:<int_1,x1
	  add	x1,a
	  move	a1,x:frame_number
same_frame

        rts




;    +--------------------------------------------------------------------+
;    +  Function Name : process_idct
; 	Load FFT buffer from dct buffer g_buf[x,0..255]
;	Note fftbuf[x,i] = fftbuf[x,i]*cosw0 	0 <= i <= 255
;	     fftbuf[y,i] = fftbuf[x,i]*sinw0 	
;    +--------------------------------------------------------------------+
;
process_idct
;
;	fx = f*nzr
;	fy = f*nzi
;
; Address pointers are organized as follows:
;
;  r1 = f input pointer (g_buf x memory)		
;  r0 = nzr,nzi pointer (nzbuf)	 
;  r4 = fx,fy output pointer (fftbuf x,y memory)		 


	move	#g_buf,r1	; fft pointer
	move	#fftbuf,r4	; dct output x,y pointer
	move	#nzbuf,r0	;nzbuf pointer

	move	x:(r1)+,x0	;f
	move	y:(r0),y1	; nzi

	do	#(FRAME_STEP),_enddct

	mpyr     x0,y1,b	x:(r0)+,x1	; f*nzi	 nzr
	mpyr     x0,x1,a	x:(r1)+,x0	b,y:(r4)	; f*nzr	fy
	move	 a,x:(r4)+	y:(r0),y1	;fx nzi	
_enddct

	rts




;    +--------------------------------------------------------------------+
;    +  Function Name : process_idst
; 	Load FFT buffer from dst buffer g_buf[x,0..255]
;	Note fftbuf[x,i] = fftbuf[x,i]*sinw0 	0 <= i <= 255
;	     fftbuf[y,i] = fftbuf[x,i]*-cosw0 	
;    +--------------------------------------------------------------------+
;
process_idst
;
;	fx = f*nzi
;	fy = -f*nzr
;
; Address pointers are organized as follows:
;
;  r1 = f input pointer (g_buf x memory)		
;  r0 = nzr,nzi pointer (nzbuf)	 
;  r4 = fx,fy output pointer (fftbuf x,y memory)		 

	move	#g_buf,r1	; fft pointer
	move	#fftbuf,r4	; dst output x,y pointer
	move	#nzbuf,r0	;nzbuf pointer


	move	x:(r1)+,x0	;f
	move	y:(r0),y1	; nzi

	do	#(FRAME_STEP),_enddst

	mpyr     x0,y1,b	x:(r0)+,x1	; f*nzi	 nzr
	mpyr     -x0,x1,a	b,x:(r4)	y:(r0),y1	; -f*nzr fx nzi
	move	 x:(r1)+,x0	a,y:(r4)+	;f fy
_enddst

	rts



;    +--------------------------------------------------------------------+
;    +  Function Name : process_pre_ifft
; 	Calculate the 2N point real ifft using a N point complex fft.
;    +--------------------------------------------------------------------+
;

process_pre_ifft


;	Get the two real ifft's from one complex ifft
;	br(k) = ar(N-k), bi(k) = ai(N-k)
;	gr = (ar + br)/2
;	gi = (ai - bi)/2
;	hr = (ar - br)/2 * (wr) - (ai + bi)/2 * (wi)
;	hi = (ar - br)/2 * (wi) + (ai + bi)/2 * (wr)
;

; Address pointers are organized as follows:
;
;  r2 = ar,ai input pointer (fftbuf)			
;  r1 = br,bi input pointer (fftbuf)		m1 = modulo (256)
;  r5 = gr gi output pointer (g_buf)			
;  r6 = hr hi output pointer (h_buf)				
;  r4 = wr,wi input pointer  (w2nbuf)			

	move	#fftbuf,r2	;initialize fft (start) pointer (complex)
	move	r2,r1
	move	#g_buf,r5	;initialize G pointer (complex)
	move	#h_buf,r6	;initialize H pointer (complex)
	move	#w2nbuf,r4		;w2n pointer
	move	#(FRAME_STEP-1),m1	;for modulo(256) addressing


	move		x:(r2),a	;ar
	move		#0,x0		;br



	do	#(FRAME_STEP),_end_gh
	sub	x0,a			y:(r2)+,b	;ar-br	ai
	asr	a			y:(r1)-,y0	;(ar-br)/2 bi
	add	x0,a	x:(r4),x1	a,y1	;(ar+br)/2 wr (ar-br)/2
	add	y0,b	a,x:(r5)			;(ai+bi) gr
	asr	b			y:(r4)+,x0	;(ai+bi)/2  wi
	mpy	x1,y1,a  				;wr*(ar-br)/2
	sub	y0,b	b,y0				;(ai-bi)/2 (ai+bi)/2
	macr	-x0,y0,a  		b,y:(r5)+      
					;wr*(ar-br)/2 -  wi*(ai+bi)/2  gi  
	mpy	x0,y1,b		a,x:(r6)		;wi*(ar-br)/2  hr
	macr	x1,y0,b		x:(r1),x0 		
					;wi*(ar-br)/2 +  wr*(ai+bi)/2   br
	move	x:(r2),a	b,y:(r6)+		; ar hi	
_end_gh


	

	move	#-1,m1	;restore m1 to linear



; Get one complex ifft from two real ifft's
;
;	fr = gr - hi
;	fi = -(gi + hr)		(-) for conjugate
;
; Address pointers are organized as follows:
;
;  r1 = gr,gi input pointer	(g_buf)
;  r4 = hr,hi input pointer	(h_buf)
;  r5 = fr,fi output pointer	(fftbuf)


	move	#g_buf,r1		;initialize G pointer (complex)
	move	#h_buf,r4		;initialize H pointer (complex)
	move	#fftbuf,r5		;output fft pointer (complex)

	move	x:(r1),a	y:(r4),y0	;gr hi
						

	do	#(FRAME_STEP),_endff	

	sub	y0,a	x:(r4)+,x0	y:(r1)+,b	;gr-hi hr gi
	add	x0,b	a,x:(r5)			;gi+hr fr
	neg	b			y:(r4),y0	;-(gi+hr) hi 
	move	x:(r1),a	b,y:(r5)+		;gr fi
_endff

	rts



;    +--------------------------------------------------------------------+
;    +  Function Name : process_post_ifft
; 	Now the even output data points are stored in X memory,
; 	while odd output data points are stored in Y memory.
; 	The window is also stored this way.
; 	Apply window and load frame buffer.
;    +--------------------------------------------------------------------+
;

process_post_ifft

; Apply window and load in frame buffer
; Here The even points are stored in X memory,
; while odd output points are stored in Y memory.
;Bit reverse the FFT while loading from from fftbuf. 


	move	#0,m0		;initialize C address modifier for
				;reverse carry (bit-reversed) addressing
	move	#FRAME_STEP/2,n0	;initialize C pointer offset

	move	#window_buf,r5	;initialize window pointer
	move	#fftbuf,r0	;initialize fft input pointer (complex)
	move	#framebuf,r4	;initialize fft output pointer 


	move	x:(r5),x0	;window even 
	move	x:(r0),x1	; input buf even (bit reversed)

	do	#(FRAME_STEP),_end_post
	mpyr x0,x1,a		y:(r5)+,y1	; apply even window  window odd
	move a,x:(r4)+		y:(r0)+n0,y0 ; output buf even 		input buf odd(bit reversed) 
	mpyr -y0,y1,b		x:(r5),x0  ; apply odd window(neg for conj)  window even	
	move  x:(r0),x1		; input buf even (bit reversed)
	move  b,x:(r4)+		; output buf odd
_end_post


	move	m1,m0		;restore m0 to linear
	rts




;    +--------------------------------------------------------------------+
;    +  Function Name : scale_data
; 	scale data according to frame exponent, scale factor
;	data in framebuf
;    +--------------------------------------------------------------------+
;


scale_data
;;	warn 'halting at scale data'
;;halt	jmp halt
;;resume

	move	#framebuf,r4	;initialize data pointer
	move	x:<frameExponent,a
	move	#>(AGCSHFT+1),y0	; scale factor of 2	
	sub 	y0,a	r4,r1
	jeq	<noscl	; was jeq
	jlt	<lscl
	move	#>(rshft),y1	
	add	y1,a
	move	a1,r2		;r2 = rshft+frameexp-(AGCSHFT+1)
	move	x:(r4)+,x1
	move	x:(r2),x0
	do	#(FRAME_SIZE),_endrscl
	mpy	x0,x1,a		x:(r4)+,x1		
	move	a,x:(r1)+
_endrscl

noscl
	rts

lscl


	move	#>(lshft),y1	
	add	y1,a
	move	a1,r2		;r2 = lshft-frameexp+(AGCSHFT+1)
	move	x:(r4)+,x1
	move	x:(r2),x0
	do	#(FRAME_SIZE),_endlscl
	mpy	x0,x1,a		x:(r4)+,x1		
	move	a0,a1
	move	a,x:(r1)+
_endlscl

	rts


;    +--------------------------------------------------------------------+
;    +  Function Name : overlap_add
;    +	do ovelap add of data in framebuf and DMA output buffer
;    +--------------------------------------------------------------------+
;

overlap_add

	if 0
	  warn 'halting at overlap_add'
halt	  jmp halt
resume
	endif

	jmp_chan1 ola_nc0 
;
; channel 0:
;
	move	x:newoutstep,y0  ; sample outstep from add drop
	move	x:<outstep,b	  ; old outstep
	move	#>(FRAME_SIZE),a
	sub 	y0,a	a,x1	; new overlap size = FRAME_SIZE - newoutstep
	sub x1,b 	a,x:<overlap	; negate for back-up, save overlap
	if WRITE_SNDOUT		; mono to stereo conversion repeats each sample
	  lsl b			;  => back up twice as far
	else
	  jmp_mono ola_go
	    lsl b		; stereo case => back up double also
	endif
	jmp 	ola_go
;
; channel 1:
;
ola_nc0
	move	#>(2*FRAME_SIZE),x0	; stereo
        move	x:<int_1,b		; points us to channel 1
	sub	x0,b
;
; Do overlap add
;
ola_go
	move	b1,N_DMA_OUT	; negative back-up amount for output pointer
	move	#framebuf,r1	; fft output pointer = OLA input pointer
	lua	(R_DMA_OUT)+N_DMA_OUT,R_DMA_OUT	; back up output pointer
	move	x:<channels,N_DMA_OUT	; skip factor in output buffer

; *CAUTION don't clobber y1 in the do loop
	move	#>@pow(2,-8),y1			

	if WRITE_SNDOUT
	  jmp_stereo ola_add
ola_mono_to_stereo_add
	  do x:overlap,ola_m2s_loop
	    move x:(r1)+,A   y:(R_DMA_OUT),y0	; current input and output
	    add y0,A				; add new value to output
	    move A,x1 	
	    mpy x1,y1,A  ; shift by 8 for output, saturation in overlap add
	    move A,y:(R_DMA_OUT)+		; dup for mono to stereo conv
	    move A,y:(R_DMA_OUT)+
ola_m2s_loop
	  move #2,N_DMA_OUT		; only copy to channel 0, skip chan 1
	  jmp ola_copy
	endif

ola_add
	do x:overlap,ola_stereo_loop
	    move x:(r1)+,A   y:(R_DMA_OUT),y0	; current input and output
	    add y0,A  
	    move A,x1 	
	    mpy x1,y1,A
	    move A,y:(R_DMA_OUT)+N_DMA_OUT
ola_stereo_loop

ola_copy
;
; Overlap-add done.  See if we crossed a buffer boundary.
;
	jmp ola_check_write_trigger		; fast_dma_support.asm
;
; Do copy part
;
ola_copy_go
	move x:(r1)+,A
	do x:<outstep,ola_cloop	; do non-overlapping part
	  move	x:(r1)+,A  A,y:(R_DMA_OUT)+N_DMA_OUT
;;	  Write-trigger impossible since addition not done yet
ola_cloop

	jmp_chan0 ola_return
	  move (R_DMA_OUT)-	; undo offset for chan1 => back to chan0

ola_return
	rts

